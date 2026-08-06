import '../change.dart';
import '../version.dart';

/// Result of rewriting an Xcode `project.pbxproj`.
class XcodeResult {
  /// The updated file content. Equal to the input when nothing moved.
  final String text;

  /// Names of the app-target build configurations that were visited
  /// (typically Debug, Release, Profile).
  final List<String> configurations;

  /// Per-setting before/after, including settings that were already correct.
  final List<SettingChange> changes;

  /// False when the project has no app target carrying any version setting —
  /// the normal case for a stock Flutter project, which leaves the version to
  /// `Generated.xcconfig`. Not an error.
  final bool hasVersionSettings;

  const XcodeResult({
    required this.text,
    required this.configurations,
    required this.changes,
    required this.hasVersionSettings,
  });

  bool get changed => changes.any((c) => c.isChange);
}

/// Each `XCBuildConfiguration` is `{ ...buildSettings... }; name = Debug;`.
/// buildSettings bodies contain no nested braces in a Flutter project.
final RegExp _configBlock = RegExp(
  r'\{([^{}]*?)\};(\s*name = (\w+);)',
  dotAll: true,
);

final RegExp _bundleId = RegExp(r'PRODUCT_BUNDLE_IDENTIFIER = ([^;]+);');

enum _SettingKind { name, build }

/// Settings that must agree with the app version.
///
/// `FLUTTER_BUILD_NAME`/`FLUTTER_BUILD_NUMBER` are the ones that actually ship:
/// `Info.plist` reads `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)`, and a
/// value set here at target level *overrides* the one Flutter generates into
/// `ios/Flutter/Generated.xcconfig` from pubspec.yaml. Many projects do not set
/// them here at all, in which case they are left alone.
///
/// `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` are what Xcode's General tab
/// and various CI/release tools display.
const _versionSettings = {
  'FLUTTER_BUILD_NAME': _SettingKind.name,
  'FLUTTER_BUILD_NUMBER': _SettingKind.build,
  'MARKETING_VERSION': _SettingKind.name,
  'CURRENT_PROJECT_VERSION': _SettingKind.build,
};

/// Rewrites the app target's version settings to [next].
///
/// Test targets are skipped: they carry their own unrelated version and their
/// bundle identifier ends in `Tests`/`UITests`. Configurations are matched by
/// bundle identifier rather than by their current version, so this keeps working
/// when the values have drifted apart — which is exactly when it is needed.
XcodeResult updateXcodeProject(String pbxproj, Version next) {
  final wanted = {
    for (final entry in _versionSettings.entries)
      entry.key: switch (entry.value) {
        _SettingKind.name => next.name,
        _SettingKind.build => '${next.build}',
      },
  };

  final configurations = <String>[];
  final before = {for (final key in wanted.keys) key: <String>{}};

  final text = pbxproj.replaceAllMapped(_configBlock, (match) {
    var body = match[1]!;
    final tail = match[2]!;
    final configuration = match[3]!;

    final bundle = _bundleId.firstMatch(body)?[1]?.trim();
    if (bundle == null || _isTestTarget(bundle)) return match[0]!;
    if (!wanted.keys.any(body.contains)) return match[0]!;

    var touched = false;
    for (final entry in wanted.entries) {
      final pattern = RegExp('${entry.key} = ([^;]+);');
      final found = pattern.firstMatch(body);
      if (found == null) continue; // absent here; do not introduce it

      final currentValue = found[1]!.trim();
      // A value that references another build setting — stock Flutter writes
      // CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)" — already resolves
      // from pubspec.yaml through Generated.xcconfig. Replacing it with a
      // literal would swap working indirection for a value that drifts.
      if (currentValue.contains(r'$(')) continue;

      before[entry.key]!.add(currentValue);
      body = body.replaceAll(pattern, '${entry.key} = ${entry.value};');
      touched = true;
    }
    if (!touched) return match[0]!;
    configurations.add(configuration);
    return '{$body};$tail';
  });

  final changes = [
    for (final entry in wanted.entries)
      if (before[entry.key]!.isNotEmpty)
        SettingChange(
          key: entry.key,
          before: before[entry.key]!,
          after: entry.value,
        ),
  ];

  return XcodeResult(
    text: text,
    configurations: configurations,
    changes: changes,
    hasVersionSettings: changes.isNotEmpty,
  );
}

/// Xcode names test targets `RunnerTests`, `RunnerUITests`, etc., and their
/// bundle identifiers inherit that suffix.
bool _isTestTarget(String bundleId) {
  final lower = bundleId.toLowerCase();
  return lower.endsWith('tests') || lower.contains('tests.');
}
