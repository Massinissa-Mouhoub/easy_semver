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

void main() {
  late Directory temp;

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

  test('finds the project root from a nested working directory', () {
    final root = makeProject();
    final nested = Directory('${root.path}/lib/features')
      ..createSync(recursive: true);

    expect(run(['patch', '--project', nested.path]), 0);
    expect(pubspecOf(root), contains('version: 1.2.2+1'));
  });
}
