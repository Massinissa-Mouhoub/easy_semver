import 'package:easy_semver/easy_semver.dart';
import 'package:test/test.dart';

void main() {
  const version = Version(1, 3, 0, 5);

  group('render', () {
    test('the default format is the bare version', () {
      expect(TagFormat.standard.render(version), '1.3.0');
    });

    test('text around {version} is kept as written', () {
      expect(TagFormat.parse('v{version}').render(version), 'v1.3.0');
      expect(TagFormat.parse('{version}-beta').render(version), '1.3.0-beta');
      expect(TagFormat.parse('app-v{version}').render(version), 'app-v1.3.0');
    });

    test('{build} is the build number', () {
      expect(TagFormat.parse('v{version}+{build}').render(version), 'v1.3.0+5');
    });
  });

  group('parse rejects', () {
    test('a format without {version}', () {
      expect(() => TagFormat.parse('release'), throwsFormatException);
      expect(() => TagFormat.parse('{build}'), throwsFormatException);
    });

    test('an empty format', () {
      expect(() => TagFormat.parse(''), throwsFormatException);
    });

    test('an unknown placeholder', () {
      expect(
        () => TagFormat.parse('v{version}-{major}'),
        throwsA(isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('{major}'),
        )),
      );
    });
  });
}
