import 'dart:io';

import 'package:args/args.dart';

import 'change.dart';
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
    'dry-run',
    negatable: false,
    help: 'Print what would change without writing anything.',
  )
  ..addOption(
    'project',
    valueHelp: 'DIR',
    help: 'Project directory (defaults to the working directory).',
  )
  ..addFlag('version', negatable: false, help: 'Print the bumpv version.')
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

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

The build number is preserved unless --build or --bump-build is given. App
stores reject a repeated build number, so use --bump-build for a release.

Running with the current version re-syncs iOS and Android without changing the
version — useful when the files have drifted apart.''';

/// Runs the CLI and returns a process exit code.
int run(List<String> args, {Directory? workingDirectory}) {
  final parser = buildParser();
  final ArgResults options;
  try {
    options = parser.parse(args);
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
    return _usageError(
        'unexpected extra argument "${options.rest[1]}"', parser);
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

  stdout.writeln();
  if (writes.isEmpty) {
    stdout.writeln('Everything is already at this version — nothing to write.');
    return 0;
  }
  if (options.flag('dry-run')) {
    stdout.writeln('Dry run — no files written.');
    return 0;
  }

  writes.forEach((file, content) => file.writeAsStringSync(content));
  stdout
    ..writeln('Done. Review with:  git diff')
    ..writeln(
      'Then commit with:   git commit -am "chore: bump version to ${next.name}"',
    );
  return 0;
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
