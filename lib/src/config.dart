import 'package:yaml/yaml.dart';

import 'tag_format.dart';

/// bumpv's own settings, from a top-level `bumpv:` section in pubspec.yaml:
///
/// ```yaml
/// bumpv:
///   tag_format: v{version}
/// ```
///
/// Kept in the pubspec rather than a dotfile because that is where the version
/// already lives, and pub ignores top-level keys it does not know.
class BumpvConfig {
  /// How to name the tag when `--tag` is given without a name.
  final TagFormat? tagFormat;

  const BumpvConfig({this.tagFormat});
}

const _section = 'bumpv';
const _tagFormatKey = 'tag_format';

/// Reads the `bumpv:` section of [pubspecText].
///
/// Throws [FormatException] when the pubspec is not valid YAML or the section
/// holds something bumpv cannot use. Unknown keys are rejected rather than
/// ignored: with a single setting, an unknown key is almost certainly a typo
/// that would otherwise go unnoticed until the wrong tag is pushed.
BumpvConfig readConfig(String pubspecText) {
  final Object? document;
  try {
    document = loadYaml(pubspecText);
  } on YamlException catch (e) {
    throw FormatException('pubspec.yaml is not valid YAML: ${e.message}');
  }

  final section = document is YamlMap ? document[_section] : null;
  if (section == null) return const BumpvConfig();
  if (section is! YamlMap) {
    throw const FormatException(
      'the "$_section" section of pubspec.yaml must be a map of settings',
    );
  }

  final unknown = section.keys.where((key) => key != _tagFormatKey);
  if (unknown.isNotEmpty) {
    throw FormatException(
      'unknown setting "$_section.${unknown.first}" in pubspec.yaml; '
      'the only one is "$_section.$_tagFormatKey"',
    );
  }

  final tagFormat = section[_tagFormatKey];
  if (tagFormat == null) return const BumpvConfig();
  if (tagFormat is! String) {
    throw const FormatException(
      '"$_section.$_tagFormatKey" in pubspec.yaml must be a string, '
      'such as v{version}',
    );
  }
  try {
    return BumpvConfig(tagFormat: TagFormat.parse(tagFormat));
  } on FormatException catch (e) {
    throw FormatException(
      '"$_section.$_tagFormatKey" in pubspec.yaml: ${e.message}',
    );
  }
}
