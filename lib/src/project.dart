import 'dart:io';

/// The Flutter/Dart project being versioned, and the files that carry a version.
///
/// Resolved from the working directory rather than from the script location:
/// once installed with `dart pub global activate`, the executable lives in
/// `~/.pub-cache` and its own path says nothing about the target project.
class FlutterProject {
  final Directory root;

  const FlutterProject(this.root);

  File get pubspec => File('${root.path}/pubspec.yaml');

  /// `ios/Runner.xcodeproj/project.pbxproj`, or null when there is no iOS
  /// directory (a Dart-only package, or a project with iOS support removed).
  File? get xcodeProject {
    final file = File('${root.path}/ios/Runner.xcodeproj/project.pbxproj');
    return file.existsSync() ? file : null;
  }

  /// `android/app/build.gradle.kts`, falling back to the Groovy
  /// `android/app/build.gradle`. Null when neither exists.
  File? get gradleFile {
    for (final name in ['build.gradle.kts', 'build.gradle']) {
      final file = File('${root.path}/android/app/$name');
      if (file.existsSync()) return file;
    }
    return null;
  }

  /// Path relative to [root], for readable console output.
  String relative(File file) {
    final prefix = '${root.path}${Platform.pathSeparator}';
    final path = file.path;
    return path.startsWith(prefix) ? path.substring(prefix.length) : path;
  }

  /// Walks up from [start] until a directory containing `pubspec.yaml` is found.
  ///
  /// Returns null when none is found before the filesystem root, which means the
  /// command was run outside a Dart/Flutter project.
  static FlutterProject? find(Directory start) {
    var dir = start.absolute;
    while (true) {
      if (File('${dir.path}/pubspec.yaml').existsSync()) {
        return FlutterProject(dir);
      }
      final parent = dir.parent;
      if (parent.path == dir.path) return null; // reached the filesystem root
      dir = parent;
    }
  }
}
