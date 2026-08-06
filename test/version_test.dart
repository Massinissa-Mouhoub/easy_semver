import 'package:easy_semver/easy_semver.dart';
import 'package:test/test.dart';

void main() {
  group('Version.tryParse', () {
    test('parses a bare X.Y.Z, applying the default build', () {
      expect(Version.tryParse('1.2.3'), const Version(1, 2, 3, 1));
      expect(
        Version.tryParse('1.2.3', defaultBuild: 9),
        const Version(1, 2, 3, 9),
      );
    });

    test('parses X.Y.Z+BUILD, which wins over the default', () {
      expect(
        Version.tryParse('1.2.3+4', defaultBuild: 9),
        const Version(1, 2, 3, 4),
      );
    });

    test('tolerates surrounding whitespace', () {
      expect(Version.tryParse('  2.0.0+7 '), const Version(2, 0, 0, 7));
    });

    test('returns null for anything that is not a version', () {
      for (final input in [
        '1.2',
        '1',
        'banana',
        '',
        'v1.2.3',
        '1.2.3.4',
        '1.2.3+',
        '-1.2.3',
      ]) {
        expect(
          Version.tryParse(input),
          isNull,
          reason: 'should reject "$input"',
        );
      }
    });
  });

  group('bump', () {
    const current = Version(1, 2, 3, 5);

    test('major resets minor and patch and keeps the build', () {
      expect(current.bump(BumpKind.major), const Version(2, 0, 0, 5));
    });

    test('minor resets patch and keeps the build', () {
      expect(current.bump(BumpKind.minor), const Version(1, 3, 0, 5));
    });

    test('patch keeps the build', () {
      expect(current.bump(BumpKind.patch), const Version(1, 2, 4, 5));
    });

    test('never mutates the receiver', () {
      current.bump(BumpKind.major);
      expect(current, const Version(1, 2, 3, 5));
    });
  });

  test('withBuild replaces only the build number', () {
    expect(const Version(1, 2, 3, 1).withBuild(12), const Version(1, 2, 3, 12));
  });

  group('formatting', () {
    const version = Version(1, 2, 3, 4);

    test('name omits the build number', () {
      // This is what goes into FLUTTER_BUILD_NAME / MARKETING_VERSION /
      // versionName, none of which accept the "+4" suffix.
      expect(version.name, '1.2.3');
    });

    test('toString is the full pubspec form', () {
      expect(version.toString(), '1.2.3+4');
    });
  });

  group('equality and ordering', () {
    test('two versions with the same parts are equal', () {
      expect(const Version(1, 2, 3, 4), const Version(1, 2, 3, 4));
      expect(
        const Version(1, 2, 3, 4).hashCode,
        const Version(1, 2, 3, 4).hashCode,
      );
    });

    test('a differing build number makes them unequal', () {
      // Matters because bumping only the build must still count as a change.
      expect(const Version(1, 2, 3, 4), isNot(const Version(1, 2, 3, 5)));
    });

    test('orders by each component in turn', () {
      final sorted = <Version>[
        const Version(1, 2, 3, 2),
        const Version(2, 0, 0, 0),
        const Version(1, 2, 3, 1),
        const Version(1, 10, 0, 0),
      ]..sort();
      expect(sorted.map((v) => v.toString()), [
        '1.2.3+1',
        '1.2.3+2',
        '1.10.0+0',
        '2.0.0+0',
      ]);
    });
  });

  group('BumpKind.tryParse', () {
    test('accepts the three bump names', () {
      expect(BumpKind.tryParse('major'), BumpKind.major);
      expect(BumpKind.tryParse('minor'), BumpKind.minor);
      expect(BumpKind.tryParse('patch'), BumpKind.patch);
    });

    test('rejects anything else', () {
      expect(BumpKind.tryParse('1.2.3'), isNull);
      expect(BumpKind.tryParse('Major'), isNull);
      expect(BumpKind.tryParse(''), isNull);
    });
  });
}
