import 'dart:io';

import 'package:args/args.dart';

import 'change.dart';
import 'git.dart';
import 'project.dart';
import 'updaters/gradle_updater.dart';
import 'updaters/pubspec_updater.dart';
import 'updaters/xcode_updater.dart';
import 'version.dart';

const _packageVersion = '1.0.0';

/// Exit codes: 0 success, 1 runtime failure, 64 usage error (sysexits.h).
const _exitFailure = 1;
const _exitUsage = 64;

/// Column width so every summary line's detail starts at the same place.
const _labelWidth = 26;

/// Elides the middle of a long path so the summary column stays aligned:
/// `ios/Runner.xcodeproj/project.pbxproj` -> `ios/…/project.pbxproj`.
String _shorten(String path) {
  if (path.length <= _labelWidth) return path;
  final parts = path.split('/');
  if (parts.length < 3) return path;
  return '${parts.first}/…/${parts.last}';
}

ArgParser buildParser() => ArgParser()
  ..addOption(
    'build',
    abbr: 'b',
    valueHelp: 'N',
    help: 'Set the build number explicitly.',
  )
  ..addFlag(
    'bump-build',
    negatable: false,
    help: 'Increment the build number (use for store uploads).',
  )
  ..addFlag(
    'commit',
    abbr: 'c',
    negatable: false,
    help: 'Commit the updated files when the project is a Git repository.',
  )
  ..addFlag(
    'dry-run',
    negatable: false,
    help: 'Print what would change without writing anything.',
  )
  ..addOption(
    'project',
    valueHelp: 'DIR',
    help: 'Project directory (defaults to the working directory).',
  )
  ..addOption(
    'tag',
    abbr: 't',
    valueHelp: 'NAME',
    help: 'Tag the bump commit, named after the new version unless a name is '
        'attached. Implies --commit.',
  )
  ..addFlag('version', negatable: false, help: 'Print the bumpv version.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

/// Stands in for `--tag` given without a name.
///
/// ArgParser has no notion of an optional value — an option always consumes the
/// next argument — so the bare forms are rewritten to carry this marker and the
/// real name is resolved once the new version is known. An empty value is the
/// marker because it cannot be a tag anyway, which makes a hand-written
/// `--tag=` mean the same thing as `--tag`.
const _bareTag = '';

/// Rewrites a bare `--tag`/`-t` so ArgParser does not swallow the bump target.
///
/// The cost is that a custom name has to be *attached* (`--tag=NAME`, `-tNAME`),
/// which is the usual convention for an option whose value is optional —
/// otherwise `bumpv --tag minor` could not be read both ways.
List<String> _markBareTag(List<String> args) {
  final marked = <String>[];
  var afterSeparator = false;
  for (final arg in args) {
    final isBareTag = !afterSeparator && (arg == '--tag' || arg == '-t');
    marked.add(isBareTag ? '--tag=$_bareTag' : arg);
    if (arg == '--') afterSeparator = true;
  }
  return marked;
}

String usage(ArgParser parser) => '''
Bump a Flutter app's version across pubspec.yaml, iOS and Android.

Usage: bumpv <major|minor|patch|X.Y.Z[+BUILD]> [options]

${parser.usage}

Examples:
  bumpv patch                 1.2.1 -> 1.2.2
  bumpv minor                 1.2.1 -> 1.3.0
  bumpv major                 1.2.1 -> 2.0.0
  bumpv 2.4.0                 set the version exactly
  bumpv 2.4.0+7               set version and build number
  bumpv minor --bump-build    bump both, for a store upload
  bumpv patch --commit        bump, then commit the files that changed
  bumpv patch --tag           commit, then tag that commit 1.2.2
  bumpv patch --tag=v1.2.2    tag it v1.2.2 instead

The build number is preserved unless --build or --bump-build is given. App
stores reject a repeated build number, so use --bump-build for a release.

--commit stages only the files bumpv wrote and commits them as
"chore: bump version to X.Y.Z", leaving any other work in progress alone.

--tag puts an annotated Git tag on that commit, named after the new version.
To name it yourself the value must be attached — --tag=NAME or -tNAME, not
--tag NAME, which would be indistinguishable from the bump type. --tag implies
--commit: a tag is only worth having on the commit that carries the bump.

Running with the current version re-syncs iOS and Android without changing the
version — useful when the files have drifted apart.''';

/// Runs the CLI and returns a process exit code.
int run(List<String> args, {Directory? workingDirectory}) {
  final parser = buildParser();
  final ArgResults options;
  try {
    options = parser.parse(_markBareTag(args));
  } on FormatException catch (e) {
    return _usageError(e.message, parser);
  }

  if (options.flag('help')) {
    stdout.writeln(usage(parser));
    return 0;
  }
  if (options.flag('version')) {
    stdout.writeln('bumpv $_packageVersion');
    return 0;
  }

  if (options.rest.isEmpty) {
    return _usageError('missing bump type or version', parser);
  }
  if (options.rest.length > 1) {
    final extra = options.rest[1];
    // `--tag NAME` lands here, the name having fallen through as a positional.
    // Point at the attached form rather than just rejecting the argument.
    final hint = options.option('tag') == _bareTag
        ? ' — to name a tag, attach it: --tag=$extra'
        : '';
    return _usageError('unexpected extra argument "$extra"$hint', parser);
  }
  final target = options.rest.single;

  final kind = BumpKind.tryParse(target);
  if (kind == null && Version.tryParse(target) == null) {
    return _usageError(
      '"$target" is neither major/minor/patch nor a version like 2.4.0',
      parser,
    );
  }

  int? explicitBuild;
  final buildOption = options.option('build');
  if (buildOption != null) {
    if (options.flag('bump-build')) {
      return _usageError('use either --build or --bump-build', parser);
    }
    explicitBuild = int.tryParse(buildOption);
    if (explicitBuild == null || explicitBuild < 1) {
      return _usageError('--build needs a positive integer', parser);
    }
  }

  final projectOption = options.option('project');
  final start = projectOption != null
      ? Directory(projectOption)
      : (workingDirectory ?? Directory.current);
  if (!start.existsSync()) {
    return _fail('no such directory: ${start.path}');
  }

  final project = FlutterProject.find(start);
  if (project == null) {
    return _fail(
      'no pubspec.yaml in ${start.absolute.path} or any parent directory',
    );
  }

  final pubspecText = project.pubspec.readAsStringSync();
  final current = readPubspecVersion(pubspecText);
  if (current == null) {
    return _fail('no "version: X.Y.Z" line in ${project.pubspec.path}');
  }

  var next = kind != null
      ? current.bump(kind)
      : Version.tryParse(target, defaultBuild: current.build)!;
  if (explicitBuild != null) next = next.withBuild(explicitBuild);
  if (options.flag('bump-build')) next = next.withBuild(current.build + 1);

  // Deliberately no early return when next == current: the native files can
  // have drifted out of sync with pubspec, and re-running repairs them.
  stdout
    ..writeln(next == current ? '$current (unchanged)' : '$current  ->  $next')
    ..writeln();

  final writes = <File, String>{};

  // ── pubspec.yaml ──────────────────────────────────────────────────────────
  final String nextPubspec;
  try {
    nextPubspec = updatePubspec(pubspecText, next);
  } on FormatException catch (e) {
    return _fail(e.message);
  }
  final pubspecChanged = nextPubspec != pubspecText;
  _report('pubspec.yaml', pubspecChanged ? '$current -> $next' : null);
  if (pubspecChanged) writes[project.pubspec] = nextPubspec;

  // ── iOS ───────────────────────────────────────────────────────────────────
  final xcode = project.xcodeProject;
  if (xcode == null) {
    _report('ios', 'no Xcode project found, skipping');
  } else {
    final text = xcode.readAsStringSync();
    final result = updateXcodeProject(text, next);
    if (!result.hasVersionSettings) {
      _report(
        'ios',
        'no version settings in the app target — derived from pubspec.yaml',
      );
    } else {
      _report(
        project.relative(xcode),
        '${describeChanges(result.changes) ?? 'already in sync'}  '
        '(${result.configurations.join(', ')})',
      );
      if (result.text != text) writes[xcode] = result.text;
    }
  }

  // ── Android ───────────────────────────────────────────────────────────────
  final gradle = project.gradleFile;
  if (gradle == null) {
    _report('android', 'no build.gradle found, skipping');
  } else {
    final text = gradle.readAsStringSync();
    final result = updateGradle(text, next);
    if (!result.found) {
      _warn(
        'no versionName/versionCode in ${project.relative(gradle)} — the '
        'Android build may not pick this bump up.',
      );
    } else if (result.fullyDerived) {
      _report(
        'android',
        'no edit needed — versionName/versionCode come from pubspec.yaml',
      );
    } else {
      _report(
        project.relative(gradle),
        describeChanges(result.changes) ?? 'already in sync',
      );
      if (result.text != text) writes[gradle] = result.text;
    }
  }

  // Resolved here rather than at parse time because the default name is the
  // version we have only just worked out.
  final tagOption = options.option('tag');
  final tag = tagOption == null
      ? null
      : (tagOption.trim().isEmpty ? next.name : tagOption);

  return _publish(
    project: project,
    writes: writes,
    version: next,
    tag: tag,
    // A tag on a commit that does not carry the bump would point at the wrong
    // thing, so asking for one asks for the commit as well.
    commit: options.flag('commit') || tag != null,
    dryRun: options.flag('dry-run'),
  );
}

/// Writes the pending [writes], then commits and tags as asked.
///
/// Split out of [run] because the version work is finished by this point:
/// everything here is about handing the result to Git. Returns an exit code.
int _publish({
  required FlutterProject project,
  required Map<File, String> writes,
  required Version version,
  required String? tag,
  required bool commit,
  required bool dryRun,
}) {
  final message = 'chore: bump version to ${version.name}';
  final nothingToWrite = writes.isEmpty;

  stdout.writeln();
  if (nothingToWrite) {
    stdout.writeln('Everything is already at this version — nothing to write.');
    // A tag is still worth creating: the files already carry this version, so
    // HEAD is the commit it belongs on.
    if (tag == null) return 0;
  }

  if (dryRun) {
    stdout.writeln(_dryRunSummary(
      nothingToWrite: nothingToWrite,
      commit: commit,
      tag: tag,
    ));
    return 0;
  }

  writes.forEach((file, content) => file.writeAsStringSync(content));

  if (!commit) {
    stdout
      ..writeln('Done. Review with:  git diff')
      ..writeln('Then commit with:   git commit -am "$message"');
    return 0;
  }

  // The bump itself succeeded, so a project without Git is a warning rather
  // than a failure — there is nothing to undo.
  if (!isGitRepository(project.root)) {
    if (!nothingToWrite) stdout.writeln('Done — files written.');
    _warn('${tag != null ? '--tag' : '--commit'} was given but this is not a '
        'Git repository.');
    return 0;
  }

  if (!nothingToWrite) {
    final failure = commitFiles(
      root: project.root,
      files: writes.keys,
      message: message,
    );
    if (failure != null) {
      stdout.writeln('Done — files written, but the commit failed.');
      return _fail(failure);
    }
    stdout.writeln('Done. Committed:  $message');
  }

  if (tag == null) return 0;

  // A tag that already exists, or a name Git rejects, fails here — after the
  // commit. Nothing is left inconsistent: re-running reports the version as
  // already current and goes straight back to tagging it.
  final failure = createTag(root: project.root, name: tag);
  if (failure != null) return _fail(failure);

  stdout.writeln('Tagged:           $tag');
  return 0;
}

/// What a dry run declined to do, so the message never claims more than the
/// given flags would actually have done.
String _dryRunSummary({
  required bool nothingToWrite,
  required bool commit,
  required String? tag,
}) {
  // Only reachable with a tag: without one there is nothing left to skip.
  if (nothingToWrite) return 'Dry run — the "$tag" tag was not created.';

  final skipped = [
    'no files written',
    if (commit) 'nothing committed',
    if (tag != null) 'no "$tag" tag',
  ];
  return 'Dry run — ${skipped.join(', ')}.';
}

void _report(String label, String? detail) => stdout.writeln(
      '  ${_shorten(label).padRight(_labelWidth)} ${detail ?? 'unchanged'}',
    );

void _warn(String message) => stderr.writeln('  WARNING: $message');

int _fail(String message) {
  stderr.writeln('error: $message');
  return _exitFailure;
}

int _usageError(String message, ArgParser parser) {
  stderr
    ..writeln('error: $message\n')
    ..writeln(usage(parser));
  return _exitUsage;
}
