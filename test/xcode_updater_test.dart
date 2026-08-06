import 'package:easy_semver/easy_semver.dart';
import 'package:test/test.dart';

/// One `XCBuildConfiguration` block in the shape Xcode writes them.
String _config({
  required String name,
  required String bundleId,
  String? marketing,
  String? current,
  String? flutterName,
  String? flutterNumber,
}) {
  final settings = <String>[
    if (current != null) 'CURRENT_PROJECT_VERSION = $current;',
    if (flutterName != null) 'FLUTTER_BUILD_NAME = $flutterName;',
    if (flutterNumber != null) 'FLUTTER_BUILD_NUMBER = $flutterNumber;',
    if (marketing != null) 'MARKETING_VERSION = $marketing;',
    'PRODUCT_BUNDLE_IDENTIFIER = $bundleId;',
    'PRODUCT_NAME = "\$(TARGET_NAME)";',
  ].map((s) => '\t\t\t\t$s').join('\n');

  return '''
\t\tAAA$name /* $name */ = {
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {
$settings
\t\t\t};
\t\t\tname = $name;
\t\t};
''';
}

/// A project that pins the version in the app target — the shape that made
/// `FLUTTER_BUILD_NAME` override Generated.xcconfig and ship a stale version.
String _hardcodedProject({String version = '1.2.1', String build = '1'}) => [
      for (final name in ['Debug', 'Release', 'Profile'])
        _config(
          name: name,
          bundleId: 'com.example.myApp',
          marketing: version,
          current: build,
          flutterName: version,
          flutterNumber: build,
        ),
      _config(
        name: 'Debug',
        bundleId: 'com.example.myApp.RunnerTests',
        marketing: '1.0',
        current: '1',
      ),
    ].join();

/// A stock `flutter create` project: no FLUTTER_BUILD_* pinned, so the version
/// comes from pubspec.yaml through Generated.xcconfig.
String _stockProject() => [
      for (final name in ['Debug', 'Release', 'Profile'])
        _config(
          name: name,
          bundleId: 'com.example.myApp',
          marketing: '1.0',
          current: '1',
        ),
      _config(
        name: 'Debug',
        bundleId: 'com.example.myApp.RunnerTests',
        marketing: '1.0',
        current: '1',
      ),
    ].join();

void main() {
  const next = Version(1, 4, 0, 2);

  group('a project that hardcodes the version', () {
    test('updates all four settings in every app configuration', () {
      final result = updateXcodeProject(_hardcodedProject(), next);

      expect('FLUTTER_BUILD_NAME = 1.4.0;'.occurrencesIn(result.text), 3);
      expect('FLUTTER_BUILD_NUMBER = 2;'.occurrencesIn(result.text), 3);
      expect('MARKETING_VERSION = 1.4.0;'.occurrencesIn(result.text), 3);
      expect('CURRENT_PROJECT_VERSION = 2;'.occurrencesIn(result.text), 3);
      expect(result.changed, isTrue);
      expect(result.hasVersionSettings, isTrue);
    });

    test('reports every configuration it touched', () {
      final result = updateXcodeProject(_hardcodedProject(), next);
      expect(result.configurations, ['Debug', 'Release', 'Profile']);
    });

    test('leaves the test target alone', () {
      // RunnerTests carries its own unrelated 1.0 and must not be bumped.
      final result = updateXcodeProject(_hardcodedProject(), next);
      expect(result.text, contains('MARKETING_VERSION = 1.0;'));
      expect(
        result.text,
        contains('PRODUCT_BUNDLE_IDENTIFIER = com.example.myApp.RunnerTests;'),
      );
    });

    test('describes the changes for the console', () {
      final result = updateXcodeProject(_hardcodedProject(), next);
      final described = describeChanges(result.changes)!;
      expect(described, contains('FLUTTER_BUILD_NAME: 1.2.1 -> 1.4.0'));
      expect(described, contains('CURRENT_PROJECT_VERSION: 1 -> 2'));
    });
  });

  group('a stock project', () {
    test('updates the settings it has without inventing the others', () {
      final result = updateXcodeProject(_stockProject(), next);

      expect(result.hasVersionSettings, isTrue);
      expect('MARKETING_VERSION = 1.4.0;'.occurrencesIn(result.text), 3);
      expect(
        result.text,
        isNot(contains('FLUTTER_BUILD_NAME')),
        reason: 'must not add settings the project deliberately omits',
      );
    });

    test('never overwrites a build-variable reference', () {
      // What `flutter create` actually writes:
      //   CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";
      // That already resolves from pubspec.yaml through Generated.xcconfig.
      // Replacing it with a literal would swap working indirection for a value
      // that silently drifts on every future bump.
      final referencing = _config(
        name: 'Release',
        bundleId: 'com.example.myApp',
        current: r'"$(FLUTTER_BUILD_NUMBER)"',
      );
      final result = updateXcodeProject(referencing, next);

      expect(result.text, contains(r'CURRENT_PROJECT_VERSION = "$('));
      expect(result.text, referencing, reason: 'file must be untouched');
      expect(result.changed, isFalse);
      expect(result.hasVersionSettings, isFalse);
      expect(result.configurations, isEmpty);
    });

    test('still updates a literal alongside a referenced sibling', () {
      final mixed = _config(
        name: 'Release',
        bundleId: 'com.example.myApp',
        marketing: '1.0',
        current: r'"$(FLUTTER_BUILD_NUMBER)"',
      );
      final result = updateXcodeProject(mixed, next);

      expect(result.text, contains('MARKETING_VERSION = 1.4.0;'));
      expect(result.text, contains(r'CURRENT_PROJECT_VERSION = "$('));
      expect(result.configurations, ['Release']);
    });
  });

  group('drift repair', () {
    test('reports both stale values when configurations disagree', () {
      // The exact failure we hit: MARKETING_VERSION was bumped but
      // FLUTTER_BUILD_NAME was left behind, so iOS shipped the old version.
      final drifted = _hardcodedProject().replaceFirst(
        'FLUTTER_BUILD_NAME = 1.2.1;',
        'FLUTTER_BUILD_NAME = 1.0.9;',
      );
      final result = updateXcodeProject(drifted, next);

      final change = result.changes.firstWhere(
        (c) => c.key == 'FLUTTER_BUILD_NAME',
      );
      expect(change.before, {'1.0.9', '1.2.1'});
      expect(change.toString(), 'FLUTTER_BUILD_NAME: 1.0.9/1.2.1 -> 1.4.0');
      expect('FLUTTER_BUILD_NAME = 1.4.0;'.occurrencesIn(result.text), 3);
    });

    test('re-running at the same version is a no-op', () {
      final atVersion = _hardcodedProject(version: '1.4.0', build: '2');
      final result = updateXcodeProject(atVersion, next);

      expect(result.changed, isFalse);
      expect(result.text, atVersion);
      expect(describeChanges(result.changes), isNull);
    });
  });

  test('a project with no version settings is reported, not an error', () {
    // e.g. only a test target, or a target that pins nothing.
    final onlyTests = _config(
      name: 'Debug',
      bundleId: 'com.example.myApp.RunnerTests',
      marketing: '1.0',
    );
    final result = updateXcodeProject(onlyTests, next);

    expect(result.hasVersionSettings, isFalse);
    expect(result.changed, isFalse);
    expect(result.text, onlyTests);
  });
}

extension on String {
  /// How many times this literal occurs in [text].
  int occurrencesIn(String text) => allMatches(text).length;
}
