/// Which component of a semantic version to increment.
enum BumpKind {
  major,
  minor,
  patch;

  static BumpKind? tryParse(String input) {
    for (final kind in BumpKind.values) {
      if (kind.name == input) return kind;
    }
    return null;
  }
}

/// A Flutter app version: `MAJOR.MINOR.PATCH+BUILD`.
///
/// The `+BUILD` suffix is Flutter's build number (`CFBundleVersion` on iOS,
/// `versionCode` on Android). It is tracked separately from the three semver
/// components because bumping the version does not necessarily bump the build.
class Version implements Comparable<Version> {
  final int major;
  final int minor;
  final int patch;
  final int build;

  const Version(this.major, this.minor, this.patch, this.build);

  static final RegExp _pattern = RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$');

  /// Parses `1.2.3` or `1.2.3+4`, returning null when [input] is not a version.
  ///
  /// When [input] carries no `+BUILD`, [defaultBuild] is used — callers pass the
  /// project's current build number so an explicit `X.Y.Z` leaves it untouched.
  static Version? tryParse(String input, {int defaultBuild = 1}) {
    final match = _pattern.firstMatch(input.trim());
    if (match == null) return null;
    return Version(
      int.parse(match[1]!),
      int.parse(match[2]!),
      int.parse(match[3]!),
      int.tryParse(match[4] ?? '') ?? defaultBuild,
    );
  }

  /// Increments [kind], resetting the less significant components and keeping
  /// the build number.
  Version bump(BumpKind kind) => switch (kind) {
        BumpKind.major => Version(major + 1, 0, 0, build),
        BumpKind.minor => Version(major, minor + 1, 0, build),
        BumpKind.patch => Version(major, minor, patch + 1, build),
      };

  Version withBuild(int value) => Version(major, minor, patch, value);

  /// `1.2.3` — the marketing version, without the build number. This is what
  /// goes into `FLUTTER_BUILD_NAME`, `MARKETING_VERSION` and `versionName`.
  String get name => '$major.$minor.$patch';

  /// `1.2.3+4` — the full pubspec form.
  @override
  String toString() => '$name+$build';

  @override
  int compareTo(Version other) {
    for (final (a, b) in [
      (major, other.major),
      (minor, other.minor),
      (patch, other.patch),
      (build, other.build),
    ]) {
      final diff = a.compareTo(b);
      if (diff != 0) return diff;
    }
    return 0;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Version && compareTo(other) == 0);

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}
