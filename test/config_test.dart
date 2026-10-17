import 'package:easy_semver/easy_semver.dart';
import 'package:test/test.dart';

const _version = Version(1, 3, 0, 1);

String _pubspecWith(String section) => '''
name: my_app
version: 1.2.1+1
$section
''';

void main() {
  test('a pubspec without a bumpv section has no settings', () {
    expect(readConfig(_pubspecWith('')).tagFormat, isNull);
  });

  test('reads bumpv.tag_format', () {
    final config = readConfig(_pubspecWith('''
bumpv:
  tag_format: v{version}
'''));

    expect(config.tagFormat?.render(_version), 'v1.3.0');
  });

  test('an empty bumpv section has no settings', () {
    expect(readConfig(_pubspecWith('bumpv:')).tagFormat, isNull);
  });

  group('rejects', () {
    test('a bumpv section that is not a map', () {
      expect(
        () => readConfig(_pubspecWith('bumpv: v{version}')),
        throwsFormatException,
      );
    });

    test('a tag_format that is not a string', () {
      expect(
        () => readConfig(_pubspecWith('bumpv:\n  tag_format: 3')),
        throwsFormatException,
      );
    });

    test('a tag_format without {version}', () {
      expect(
        () => readConfig(_pubspecWith('bumpv:\n  tag_format: release')),
        throwsFormatException,
      );
    });

    test('an unknown key, which is most likely a typo', () {
      expect(
        () => readConfig(_pubspecWith('bumpv:\n  tagformat: v{version}')),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('tagformat'),
        )),
      );
    });

    test('a pubspec that is not valid YAML', () {
      expect(() => readConfig('version: [1.2.1'), throwsFormatException);
    });
  });
}
