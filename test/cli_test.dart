import 'dart:io';

import 'package:easy_semver/easy_semver.dart';
import 'package:test/test.dart';

const _pubspec = '''
name: my_app
description: "A sample app."

version: 1.2.1+1

environment:
  sdk: ^3.6.0
''';

const _pbxproj = '''
\t\tAAA1 /* Debug */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tFLUTTER_BUILD_NAME = 1.2.1;
\t\t\t\tFLUTTER_BUILD_NUMBER = 1;
\t\t\t\tMARKETING_VERSION = 1.2.1;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.example.myApp;
\t\t\t};
\t\t\tname = Debug;
\t\t};
''';

const _gradle = '''
android {
    defaultConfig {
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
}
''';

/// Collects what bumpv prints to stderr. Only the two write methods are used.
class _CapturedStderr implements Stdout {
  final _text = StringBuffer();

  String get text => _text.toString();

  @override
  void write(Object? object) => _text.write(object);

  @override
  void writeln([Object? object = '']) => _text.writeln(object);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late Directory temp;

  /// Runs bumpv and returns its exit code with the first line it printed to
  /// stderr, which is the error itself.
  ({int code, String error}) runCapturing(List<String> args) {
    final captured = _CapturedStderr();
    final code = IOOverrides.runZoned(
      () => run(args),
      stderr: () => captured,
    );
    return (code: code, error: captured.text.split('\n').first);
  }

  /// A throwaway project with the three files bumpv knows about.
  Directory makeProject() {
    final root = Directory('${temp.path}/app')..createSync(recursive: true);
    File('${root.path}/pubspec.yaml').writeAsStringSync(_pubspec);
    Directory('${root.path}/ios/Runner.xcodeproj').createSync(recursive: true);
    File(
      '${root.path}/ios/Runner.xcodeproj/project.pbxproj',
    ).writeAsStringSync(_pbxproj);
    Directory('${root.path}/android/app').createSync(recursive: true);
    File(
      '${root.path}/android/app/build.gradle.kts',
    ).writeAsStringSync(_gradle);
    return root;
  }

  String pubspecOf(Directory root) =>
      File('${root.path}/pubspec.yaml').readAsStringSync();

  File pbxprojFile(Directory root) =>
      File('${root.path}/ios/Runner.xcodeproj/project.pbxproj');

  String pbxprojOf(Directory root) => pbxprojFile(root).readAsStringSync();

  /// Turns [root] into a repository with one commit, so a bump has a HEAD to
  /// commit against. Identity and signing are set locally to keep the test
  /// independent of the machine's global Git config.
  void initRepo(Directory root) {
    for (final args in const [
      ['init', '--quiet'],
      ['config', 'user.name', 'bumpv test'],
      ['config', 'user.email', 'bumpv@example.com'],
      ['config', 'commit.gpgsign', 'false'],
      ['config', 'tag.gpgsign', 'false'],
      ['add', '.'],
      ['commit', '--quiet', '-m', 'initial'],
    ]) {
      final result = Process.runSync('git', args, workingDirectory: root.path);
      expect(result.exitCode, 0, reason: 'git ${args.first}: ${result.stderr}');
    }
  }

  String gitOutput(Directory root, List<String> args) =>
      (Process.runSync('git', args, workingDirectory: root.path).stdout
              as String)
          .trim();

  setUp(() => temp = Directory.systemTemp.createTempSync('bumpv_test_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('usage errors exit 64', () {
    test('no argument', () {
      expect(run(const []), 64);
    });

    test('an argument that is neither a bump kind nor a version', () {
      expect(run(const ['banana']), 64);
      expect(run(const ['1.2']), 64);
    });

    test('an extra positional argument', () {
      expect(run(const ['minor', '1.2.3']), 64);
    });

    test('--build with a non-positive value', () {
      expect(run(const ['minor', '--build', '0']), 64);
      expect(run(const ['minor', '--build', 'x']), 64);
    });

    test('--build together with --bump-build', () {
      expect(run(const ['minor', '--build', '3', '--bump-build']), 64);
    });

    group('a -b that was meant as -B', () {
      test('-b with nothing after it', () {
        for (final args in const [
          ['minor', '-c', '-t', '-b'],
          ['minor', '--build'],
        ]) {
          final result = runCapturing(args);
          expect(result.code, 64);
          expect(result.error, contains('use -B (--bump-build)'));
        }
      });

      test('-b followed by something that is not a number', () {
        for (final args in const [
          ['minor', '-b', 'x'],
          ['minor', '-b', '-t'],
          ['-b', 'minor'],
        ]) {
          final result = runCapturing(args);
          expect(result.code, 64);
          expect(result.error, contains('use -B (--bump-build)'));
        }
      });

      test('a number that is not positive keeps the plain error', () {
        final result = runCapturing(const ['minor', '-b', '0']);
        expect(result.code, 64);
        expect(result.error, contains('positive integer'));
        expect(result.error, isNot(contains('-B')));
      });
    });

    test('an unknown flag', () {
      expect(run(const ['minor', '--oops']), 64);
    });
  });

  test('--help and --version exit 0 without needing a project', () {
    expect(run(const ['--help']), 0);
    expect(run(const ['--version']), 0);
  });

  test('running outside a Dart project fails cleanly', () {
    final empty = Directory('${temp.path}/empty')..createSync();
    expect(run(['minor', '--project', empty.path]), 1);
  });

  group('bumping', () {
    test('minor updates pubspec and the iOS settings', () {
      final root = makeProject();
      expect(run(['minor', '--project', root.path]), 0);

      expect(pubspecOf(root), contains('version: 1.3.0+1'));
      expect(pbxprojOf(root), contains('FLUTTER_BUILD_NAME = 1.3.0;'));
      expect(pbxprojOf(root), contains('MARKETING_VERSION = 1.3.0;'));
    });

    test('--bump-build advances the build number too', () {
      final root = makeProject();
      expect(run(['minor', '--bump-build', '--project', root.path]), 0);

      expect(pubspecOf(root), contains('version: 1.3.0+2'));
      expect(pbxprojOf(root), contains('FLUTTER_BUILD_NUMBER = 2;'));
      expect(pbxprojOf(root), contains('CURRENT_PROJECT_VERSION = 2;'));
    });

    test('-B is the short form of --bump-build', () {
      final root = makeProject();
      expect(run(['minor', '-B', '--project', root.path]), 0);

      expect(pubspecOf(root), contains('version: 1.3.0+2'));
      expect(pbxprojOf(root), contains('CURRENT_PROJECT_VERSION = 2;'));
    });

    test('-b still sets the build number it is given', () {
      final root = makeProject();
      expect(run(['minor', '-b', '7', '--project', root.path]), 0);

      expect(pubspecOf(root), contains('version: 1.3.0+7'));
    });

    test('an explicit version keeps the current build number', () {
      final root = makeProject();
      expect(run(['2.4.0', '--project', root.path]), 0);
      expect(pubspecOf(root), contains('version: 2.4.0+1'));
    });

    test('an explicit version with +BUILD sets both', () {
      final root = makeProject();
      expect(run(['2.4.0+7', '--project', root.path]), 0);
      expect(pubspecOf(root), contains('version: 2.4.0+7'));
      expect(pbxprojOf(root), contains('FLUTTER_BUILD_NUMBER = 7;'));
    });
  });

  test('--dry-run writes nothing', () {
    final root = makeProject();
    final beforePubspec = pubspecOf(root);
    final beforePbxproj = pbxprojOf(root);

    expect(run(['major', '--dry-run', '--project', root.path]), 0);

    expect(pubspecOf(root), beforePubspec);
    expect(pbxprojOf(root), beforePbxproj);
  });

  group('drift repair', () {
    test('re-running at the current version fixes a stale iOS setting', () {
      // pubspec says 1.2.1 but the pbxproj was left at 1.0.9 — the bug that
      // shipped an iOS build stamped with the wrong version.
      final root = makeProject();
      pbxprojFile(root).writeAsStringSync(
        _pbxproj.replaceAll(
          'FLUTTER_BUILD_NAME = 1.2.1;',
          'FLUTTER_BUILD_NAME = 1.0.9;',
        ),
      );

      expect(run(['1.2.1', '--project', root.path]), 0);

      expect(pbxprojOf(root), contains('FLUTTER_BUILD_NAME = 1.2.1;'));
      expect(pubspecOf(root), contains('version: 1.2.1+1'));
    });

    test('a second run changes nothing', () {
      final root = makeProject();
      expect(run(['minor', '--project', root.path]), 0);
      final afterPubspec = pubspecOf(root);
      final afterPbxproj = pbxprojOf(root);

      expect(run(['1.3.0', '--project', root.path]), 0);

      expect(pubspecOf(root), afterPubspec);
      expect(pbxprojOf(root), afterPbxproj);
    });
  });

  group('--commit', () {
    test('commits the updated files', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['minor', '--commit', '--project', root.path]), 0);

      expect(
        gitOutput(root, ['log', '-1', '--pretty=%s']),
        'chore: bump version to 1.3.0',
      );
      expect(gitOutput(root, ['status', '--porcelain']), isEmpty);
      expect(
        gitOutput(root, ['show', '--name-only', '--pretty=', 'HEAD']),
        allOf(contains('pubspec.yaml'), contains('project.pbxproj')),
      );
    });

    test('-c is the short form', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['patch', '-c', '--project', root.path]), 0);
      expect(
        gitOutput(root, ['log', '-1', '--pretty=%s']),
        'chore: bump version to 1.2.2',
      );
    });

    test('leaves unrelated changes out of the commit', () {
      final root = makeProject();
      initRepo(root);
      File('${root.path}/README.md').writeAsStringSync('work in progress\n');

      expect(run(['minor', '--commit', '--project', root.path]), 0);

      expect(
        gitOutput(root, ['show', '--name-only', '--pretty=', 'HEAD']),
        isNot(contains('README.md')),
      );
      expect(gitOutput(root, ['status', '--porcelain']), contains('README.md'));
    });

    test('warns but still succeeds outside a repository', () {
      final root = makeProject();

      expect(run(['minor', '--commit', '--project', root.path]), 0);
      expect(pubspecOf(root), contains('version: 1.3.0+1'));
    });

    test('with --dry-run writes nothing and commits nothing', () {
      final root = makeProject();
      initRepo(root);

      expect(
        run(['major', '--commit', '--dry-run', '--project', root.path]),
        0,
      );

      expect(pubspecOf(root), contains('version: 1.2.1+1'));
      expect(gitOutput(root, ['log', '-1', '--pretty=%s']), 'initial');
    });

    test('does not commit when nothing needed writing', () {
      final root = makeProject();
      expect(run(['minor', '--project', root.path]), 0);
      initRepo(root);

      expect(run(['1.3.0', '--commit', '--project', root.path]), 0);
      expect(gitOutput(root, ['log', '-1', '--pretty=%s']), 'initial');
    });
  });

  group('--tag', () {
    /// The tag names in the repository, newest bump first.
    List<String> tagsOf(Directory root) {
      final output = gitOutput(root, ['tag', '--list']);
      return output.isEmpty ? const [] : output.split('\n');
    }

    /// The commit a tag resolves to, peeling the annotation away.
    String commitOf(Directory root, String tag) =>
        gitOutput(root, ['rev-parse', '$tag^{commit}']);

    test('tags the bump with the new version by default', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['minor', '--tag', '--project', root.path]), 0);

      expect(tagsOf(root), ['1.3.0']);
    });

    test('-t is the short form', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['patch', '-t', '--project', root.path]), 0);

      expect(tagsOf(root), ['1.2.2']);
    });

    test('an attached value names the tag instead', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['minor', '--tag=v1.3.0', '--project', root.path]), 0);

      expect(tagsOf(root), ['v1.3.0']);
    });

    test('the short form takes an attached value too', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['minor', '-trelease-candidate', '--project', root.path]), 0);

      expect(tagsOf(root), ['release-candidate']);
    });

    test('the tag is annotated, not lightweight', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['minor', '--tag', '--project', root.path]), 0);

      expect(gitOutput(root, ['cat-file', '-t', '1.3.0']), 'tag');
    });

    test('implies --commit, and tags the commit carrying the bump', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['minor', '--tag', '--project', root.path]), 0);

      expect(
        gitOutput(root, ['log', '-1', '--pretty=%s']),
        'chore: bump version to 1.3.0',
      );
      expect(commitOf(root, '1.3.0'), gitOutput(root, ['rev-parse', 'HEAD']));
      expect(gitOutput(root, ['status', '--porcelain']), isEmpty);
    });

    test('a detached name is a usage error, not a silent default', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['minor', '--tag', 'v1.3.0', '--project', root.path]), 64);
      expect(tagsOf(root), isEmpty);
      expect(pubspecOf(root), contains('version: 1.2.1+1'));
    });

    test('with --dry-run nothing is written, committed or tagged', () {
      final root = makeProject();
      initRepo(root);

      expect(run(['major', '--tag', '--dry-run', '--project', root.path]), 0);

      expect(pubspecOf(root), contains('version: 1.2.1+1'));
      expect(gitOutput(root, ['log', '-1', '--pretty=%s']), 'initial');
      expect(tagsOf(root), isEmpty);
    });

    test('warns but still succeeds outside a repository', () {
      final root = makeProject();

      expect(run(['minor', '--tag', '--project', root.path]), 0);
      expect(pubspecOf(root), contains('version: 1.3.0+1'));
    });

    test('tags HEAD when the files already carry this version', () {
      final root = makeProject();
      expect(run(['minor', '--project', root.path]), 0);
      initRepo(root);

      expect(run(['1.3.0', '--tag', '--project', root.path]), 0);

      // Nothing needed writing, so there is no new commit to make — but the
      // version is the one HEAD carries, so the tag belongs there.
      expect(gitOutput(root, ['log', '-1', '--pretty=%s']), 'initial');
      expect(tagsOf(root), ['1.3.0']);
    });

    test('fails when the tag already exists', () {
      final root = makeProject();
      initRepo(root);
      expect(
        Process.runSync('git', ['tag', '1.3.0'], workingDirectory: root.path)
            .exitCode,
        0,
      );

      expect(run(['minor', '--tag', '--project', root.path]), 1);

      // The bump itself stands: re-running would find the version current and
      // go straight back to tagging it.
      expect(pubspecOf(root), contains('version: 1.3.0+1'));
      expect(
        gitOutput(root, ['log', '-1', '--pretty=%s']),
        'chore: bump version to 1.3.0',
      );
    });
  });

  group('tag naming', () {
    List<String> tagsOf(Directory root) {
      final output = gitOutput(root, ['tag', '--list']);
      return output.isEmpty ? const [] : output.split('\n');
    }

    /// Adds a `bumpv:` section to [root]'s pubspec and commits it, so the
    /// working tree is clean before the bump runs.
    void configure(Directory root, String section) {
      final pubspec = File('${root.path}/pubspec.yaml');
      pubspec.writeAsStringSync('${pubspec.readAsStringSync()}\n$section');
      for (final args in const [
        ['add', 'pubspec.yaml'],
        ['commit', '--quiet', '-m', 'configure bumpv'],
      ]) {
        Process.runSync('git', args, workingDirectory: root.path);
      }
    }

    test('--tag-format names the tag from a template', () {
      final root = makeProject();
      initRepo(root);

      expect(
        run(['minor', '--tag-format=v{version}', '--project', root.path]),
        0,
      );

      expect(tagsOf(root), ['v1.3.0']);
    });

    test('--tag-format takes a detached value, since it is never optional', () {
      final root = makeProject();
      initRepo(root);

      expect(
        run([
          'minor',
          '--tag-format',
          '{version}-beta',
          '--project',
          root.path
        ]),
        0,
      );

      expect(tagsOf(root), ['1.3.0-beta']);
    });

    test('--tag-format implies --tag and --commit', () {
      final root = makeProject();
      initRepo(root);

      expect(
        run(['minor', '--tag-format=v{version}', '--project', root.path]),
        0,
      );

      expect(
        gitOutput(root, ['log', '-1', '--pretty=%s']),
        'chore: bump version to 1.3.0',
      );
      expect(
        gitOutput(root, ['rev-parse', 'v1.3.0^{commit}']),
        gitOutput(root, ['rev-parse', 'HEAD']),
      );
    });

    test('{build} is the build number after the bump', () {
      final root = makeProject();
      initRepo(root);

      expect(
        run([
          'minor',
          '--bump-build',
          '--tag-format=v{version}+{build}',
          '--project',
          root.path,
        ]),
        0,
      );

      expect(tagsOf(root), ['v1.3.0+2']);
    });

    test('a --tag-format without {version} is a usage error', () {
      final root = makeProject();
      initRepo(root);

      expect(
          run(['minor', '--tag-format=release', '--project', root.path]), 64);

      expect(pubspecOf(root), contains('version: 1.2.1+1'));
      expect(tagsOf(root), isEmpty);
    });

    test('--tag=NAME together with --tag-format is a usage error', () {
      final root = makeProject();
      initRepo(root);

      expect(
        run([
          'minor',
          '--tag=v1.3.0',
          '--tag-format=v{version}',
          '--project',
          root.path,
        ]),
        64,
      );

      expect(pubspecOf(root), contains('version: 1.2.1+1'));
    });

    test('a bare --tag uses bumpv.tag_format from pubspec.yaml', () {
      final root = makeProject();
      initRepo(root);
      configure(root, 'bumpv:\n  tag_format: v{version}\n');

      expect(run(['minor', '--tag', '--project', root.path]), 0);

      expect(tagsOf(root), ['v1.3.0']);
    });

    test('--tag-format overrides the pubspec setting', () {
      final root = makeProject();
      initRepo(root);
      configure(root, 'bumpv:\n  tag_format: v{version}\n');

      expect(
        run(['minor', '--tag-format=app-{version}', '--project', root.path]),
        0,
      );

      expect(tagsOf(root), ['app-1.3.0']);
    });

    test('--tag=NAME overrides the pubspec setting', () {
      final root = makeProject();
      initRepo(root);
      configure(root, 'bumpv:\n  tag_format: v{version}\n');

      expect(run(['minor', '--tag=rc1', '--project', root.path]), 0);

      expect(tagsOf(root), ['rc1']);
    });

    test('the pubspec setting alone does not tag or commit', () {
      final root = makeProject();
      initRepo(root);
      configure(root, 'bumpv:\n  tag_format: v{version}\n');

      expect(run(['minor', '--project', root.path]), 0);

      expect(pubspecOf(root), contains('version: 1.3.0+1'));
      expect(gitOutput(root, ['log', '-1', '--pretty=%s']), 'configure bumpv');
      expect(tagsOf(root), isEmpty);
    });

    test('an invalid pubspec setting fails before anything is written', () {
      final root = makeProject();
      initRepo(root);
      configure(root, 'bumpv:\n  tag_format: release\n');

      expect(run(['minor', '--tag', '--project', root.path]), 1);

      expect(pubspecOf(root), contains('version: 1.2.1+1'));
      expect(tagsOf(root), isEmpty);
    });
  });

  test('finds the project root from a nested working directory', () {
    final root = makeProject();
    final nested = Directory('${root.path}/lib/features')
      ..createSync(recursive: true);

    expect(run(['patch', '--project', nested.path]), 0);
    expect(pubspecOf(root), contains('version: 1.2.2+1'));
  });
}
