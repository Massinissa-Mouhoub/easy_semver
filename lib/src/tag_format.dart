import 'version.dart';

/// A template for Git tag names, such as `v{version}`.
///
/// `{version}` is the marketing version (`1.3.0`) and `{build}` the build
/// number; everything else is copied as written, so a prefix, a suffix and a
/// monorepo package name are all the same feature.
class TagFormat {
  final String pattern;

  const TagFormat._(this.pattern);

  /// Tags named after the bare version: `1.3.0`.
  static const standard = TagFormat._('{version}');

  static final RegExp _placeholder = RegExp(r'\{([^{}]*)\}');

  /// Throws [FormatException] when [pattern] has no `{version}`, since every
  /// release would then get the same tag, or uses a placeholder bumpv does
  /// not know, which is far more likely a typo than a literal.
  factory TagFormat.parse(String pattern) {
    final names = _placeholder.allMatches(pattern).map((m) => m[1]!).toSet();

    final unknown = names.difference(const {'version', 'build'});
    if (unknown.isNotEmpty) {
      throw FormatException(
        'unknown placeholder {${unknown.first}} in tag format "$pattern"; '
        'use {version} or {build}',
      );
    }
    if (!names.contains('version')) {
      throw FormatException(
        'tag format "$pattern" has no {version}, so every release would get '
        'the same tag',
      );
    }
    return TagFormat._(pattern);
  }

  /// The tag name for [version].
  String render(Version version) => pattern.replaceAllMapped(
        _placeholder,
        (match) => match[1] == 'version' ? version.name : '${version.build}',
      );
}
