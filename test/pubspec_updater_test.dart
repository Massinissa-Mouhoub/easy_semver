import 'package:easy_semver/easy_semver.dart';
import 'package:test/test.dart';

const _pubspec = '''
name: my_app
description: "A sample app."
publish_to: "none"

version: 1.2.1+1

environment:
  sdk: ^3.6.0

dependencies:
  flutter:
    sdk: flutter
''';

void main() {
  group('readPubspecVersion', () {
    test('reads the declared version', () {
      expect(readPubspecVersion(_pubspec), const Version(1, 2, 1, 1));
    });

    test('defaults the build number to 1 when there is no +BUILD', () {
      expect(readPubspecVersion('version: 2.0.0\n'), const Version(2, 0, 0, 1));
    });

    test('returns null when there is no version line', () {
      expect(readPubspecVersion('name: my_app\n'), isNull);
    });

    test('ignores version-like keys that are not the version line', () {
      const yaml = 'name: my_app\n'
          'dependencies:\n'
          '  some_pkg:\n'
          '    version: 9.9.9\n';
      // The nested key is indented, so the anchored pattern must not match it.
      expect(readPubspecVersion(yaml), isNull);
    });
  });

  group('updatePubspec', () {
    test('rewrites the version line', () {
      final result = updatePubspec(_pubspec, const Version(1, 3, 0, 2));
      expect(result, contains('version: 1.3.0+2'));
      expect(result, isNot(contains('1.2.1+1')));
    });

    test('preserves the blank line after the version', () {
      // Regression: a `\s*$` anchor also matches the trailing newline and the
      // following blank line, so substituting silently deleted the line break
      // and glued `version:` onto `environment:`.
      final result = updatePubspec(_pubspec, const Version(1, 3, 0, 1));
      expect(result, contains('version: 1.3.0+1\n\nenvironment:'));
    });

    test('changes nothing else in the file', () {
      final result = updatePubspec(_pubspec, const Version(1, 3, 0, 1));
      expect(
        result.replaceAll('1.3.0+1', '1.2.1+1'),
        _pubspec,
        reason: 'only the version token should differ',
      );
    });

    test('returns the input unchanged when already at that version', () {
      // The CLI relies on this to decide whether a write is needed.
      expect(updatePubspec(_pubspec, const Version(1, 2, 1, 1)), _pubspec);
    });

    test('handles a version line with no build number', () {
      expect(
        updatePubspec('version: 1.0.0\n', const Version(1, 0, 1, 3)),
        'version: 1.0.1+3\n',
      );
    });

    test('throws when there is no version line to rewrite', () {
      expect(
        () => updatePubspec('name: my_app\n', const Version(1, 0, 0, 1)),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
