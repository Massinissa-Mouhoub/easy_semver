## 1.1.0

- `--tag` (`-t`) puts an annotated Git tag on the bump commit, named after the
  new version. To name it yourself the value must be attached — `--tag=NAME` or
  `-tNAME` — because the value is optional and a detached name could not be
  told apart from the bump type; that case is a usage error with a hint.
  `--tag` implies `--commit`. With `--dry-run` no tag is created, outside a
  repository it warns, and when the version is already current there is nothing
  to commit so the tag goes on `HEAD`.
- `--commit` (`-c`) commits the updated files when the project is a Git
  repository. Only the files bumpv wrote go into the commit, as
  `chore: bump version to X.Y.Z`, so unrelated work in progress is left alone.
  Outside a repository it warns and leaves the bump in place; with `--dry-run`
  nothing is written or committed.

## 1.0.0

Initial release.

- `bumpv <major|minor|patch>` and `bumpv X.Y.Z[+BUILD]` to set a version
  explicitly.
- Syncs `pubspec.yaml`, the iOS Xcode project and Android Gradle files in one
  command.
- iOS: keeps `FLUTTER_BUILD_NAME`, `FLUTTER_BUILD_NUMBER`, `MARKETING_VERSION`
  and `CURRENT_PROJECT_VERSION` in agreement across the app target's build
  configurations. Settings the project does not declare are left absent, and
  test targets keep their own version.
- Android: rewrites hardcoded `versionName`/`versionCode` in both the Kotlin
  DSL and Groovy templates; reports and skips them when they defer to
  `flutter.versionName`/`flutter.versionCode`.
- Re-running with the current version repairs drift between these files instead
  of doing nothing.
- The build number is preserved unless `--build` or `--bump-build` is given.
- `--dry-run` to preview, `--project` to target another directory.
- The updaters are exported as pure functions for use in your own scripts.
