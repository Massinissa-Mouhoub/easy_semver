import '../version.dart';

/// Matches the `version:` line in a pubspec.
///
/// Horizontal whitespace only — `\s*$` would also match the trailing newline and
/// the blank line after it, so substituting the match would silently delete the
/// line break. That was a real regression; see `pubspec_updater_test.dart`.
final RegExp pubspecVersionPattern = RegExp(
  r'^version:[ \t]*(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?[ \t]*$',
  multiLine: true,
);

/// Reads the declared version, or null when the pubspec has no usable
/// `version:` line (Flutter apps always do; pure libraries may not).
Version? readPubspecVersion(String yaml) {
  final match = pubspecVersionPattern.firstMatch(yaml);
  if (match == null) return null;
  return Version(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
    int.tryParse(match[4] ?? '') ?? 1,
  );
}

/// Returns [yaml] with its version line set to [next].
///
/// Returns the input unchanged when it already declares [next], so callers can
/// detect a no-op by comparing strings. Throws [FormatException] when there is
/// no `version:` line to rewrite.
String updatePubspec(String yaml, Version next) {
  if (!pubspecVersionPattern.hasMatch(yaml)) {
    throw const FormatException(
      'no "version: X.Y.Z" line found in pubspec.yaml',
    );
  }
  var replaced = false;
  return yaml.replaceAllMapped(pubspecVersionPattern, (match) {
    if (replaced) return match[0]!; // only the first declaration is the version
    replaced = true;
    return 'version: $next';
  });
}
