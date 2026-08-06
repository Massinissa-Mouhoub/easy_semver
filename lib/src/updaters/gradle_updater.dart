import '../change.dart';
import '../version.dart';

/// Result of inspecting (and possibly rewriting) `android/app/build.gradle[.kts]`.
class GradleResult {
  /// The updated file content. Equal to the input when nothing moved.
  final String text;

  /// Per-setting before/after for values that were hardcoded and rewritten.
  final List<SettingChange> changes;

  /// True when `versionName` defers to Flutter (`flutter.versionName` or the
  /// older `flutterVersionName`), meaning pubspec.yaml already drives it.
  final bool versionNameDerived;

  /// As [versionNameDerived], for `versionCode`.
  final bool versionCodeDerived;

  /// False when neither declaration was found — an unusual Gradle layout that
  /// this tool should report rather than silently ignore.
  final bool found;

  const GradleResult({
    required this.text,
    required this.changes,
    required this.versionNameDerived,
    required this.versionCodeDerived,
    required this.found,
  });

  bool get changed => changes.any((c) => c.isChange);

  /// True when Gradle needs no edit because Flutter supplies both values.
  bool get fullyDerived => found && versionNameDerived && versionCodeDerived;
}

/// `versionName = "1.2.3"`, `versionName "1.2.3"`, `versionName = flutter.versionName`.
/// The `=` is optional because Groovy allows the method-call form.
final RegExp _versionNameLine = RegExp(
  r'^([ \t]*versionName[ \t]*=?[ \t]*)(\S.*?)[ \t]*$',
  multiLine: true,
);

final RegExp _versionCodeLine = RegExp(
  r'^([ \t]*versionCode[ \t]*=?[ \t]*)(\S.*?)[ \t]*$',
  multiLine: true,
);

/// A quoted string is a hardcoded name; anything else is an expression that
/// resolves at build time (`flutter.versionName`, `flutterVersionName`, …).
bool _isLiteralName(String value) =>
    value.startsWith('"') || value.startsWith("'");

/// A bare integer is a hardcoded code; `flutter.versionCode` and
/// `flutterVersionCode.toInteger()` are not.
bool _isLiteralCode(String value) => RegExp(r'^\d+$').hasMatch(value);

/// Syncs hardcoded `versionName`/`versionCode` to [next], leaving declarations
/// that defer to Flutter untouched.
///
/// Works for both the Kotlin DSL (`build.gradle.kts`) and Groovy
/// (`build.gradle`) templates.
GradleResult updateGradle(String gradle, Version next) {
  final changes = <SettingChange>[];
  var nameDerived = false;
  var codeDerived = false;
  var foundName = false;
  var foundCode = false;

  var text = gradle.replaceAllMapped(_versionNameLine, (match) {
    foundName = true;
    final prefix = match[1]!;
    final value = match[2]!;
    if (!_isLiteralName(value)) {
      nameDerived = true;
      return match[0]!;
    }
    final quote = value[0];
    changes.add(
      SettingChange(
        key: 'versionName',
        before: {value.replaceAll(quote, '')},
        after: next.name,
      ),
    );
    return '$prefix$quote${next.name}$quote';
  });

  text = text.replaceAllMapped(_versionCodeLine, (match) {
    foundCode = true;
    final prefix = match[1]!;
    final value = match[2]!;
    if (!_isLiteralCode(value)) {
      codeDerived = true;
      return match[0]!;
    }
    changes.add(
      SettingChange(
          key: 'versionCode', before: {value}, after: '${next.build}'),
    );
    return '$prefix${next.build}';
  });

  return GradleResult(
    text: text,
    changes: changes,
    versionNameDerived: nameDerived,
    versionCodeDerived: codeDerived,
    found: foundName || foundCode,
  );
}
