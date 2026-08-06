/// Bump and sync a Flutter app's version across pubspec.yaml, the iOS Xcode
/// project and Android Gradle files.
///
/// The `bumpv` CLI is a thin shell over this library. Every updater is a pure
/// function from file *content* to file content, so it can be reused and tested
/// without touching the filesystem:
///
/// ```dart
/// final next = Version.tryParse('1.4.0+2')!;
/// final yaml = updatePubspec(pubspecText, next);
/// final ios = updateXcodeProject(pbxprojText, next);
/// print(describeChanges(ios.changes));
/// ```
library;

export 'src/change.dart';
export 'src/cli.dart' show buildParser, run, usage;
export 'src/project.dart';
export 'src/updaters/gradle_updater.dart';
export 'src/updaters/pubspec_updater.dart';
export 'src/updaters/xcode_updater.dart';
export 'src/version.dart';
