# easy_semver

Bump a Flutter app's version **everywhere it is written**, in one command.

A Flutter app's version lives in more than one file, and those copies drift.
`bumpv` updates them together and tells you exactly what moved.

```console
$ bumpv minor
1.2.1+1  ->  1.3.0+1

  pubspec.yaml               1.2.1+1 -> 1.3.0+1
  ios/…/project.pbxproj      FLUTTER_BUILD_NAME: 1.2.1 -> 1.3.0, MARKETING_VERSION: 1.2.1 -> 1.3.0  (Debug, Release, Profile)
  android                    no edit needed — versionName/versionCode come from pubspec.yaml

Done. Review with:  git diff
```

## Why this exists

Bumping `pubspec.yaml` is usually enough — Flutter feeds `versionName`/
`versionCode` on Android and `$(FLUTTER_BUILD_NAME)`/`$(FLUTTER_BUILD_NUMBER)`
on iOS from it.

Usually. If `ios/Runner.xcodeproj/project.pbxproj` pins `FLUTTER_BUILD_NAME` in
its build settings — and plenty of projects do, often without anyone noticing —
that **target-level value overrides** the one Flutter generates into
`Generated.xcconfig`. Bump only `pubspec.yaml` and your pubspec says 1.3.0 while
the build you ship to TestFlight is stamped 1.2.1.

`bumpv` keeps all of it in agreement, and re-running it repairs drift that has
already happened.

## Install

```bash
dart pub global activate easy_semver
```

If you get `bumpv: command not found`, add pub's bin directory to your `PATH`:

```bash
export PATH="$HOME/.pub-cache/bin:$PATH"    # add to ~/.zshrc or ~/.bashrc
```

Or skip `PATH` entirely: `dart pub global run easy_semver:bumpv minor`.

## Usage

Run it anywhere inside a Flutter project — it walks up to find `pubspec.yaml`.

```bash
bumpv patch                 # 1.2.1 -> 1.2.2
bumpv minor                 # 1.2.1 -> 1.3.0
bumpv major                 # 1.2.1 -> 2.0.0
bumpv 2.4.0                 # set the version exactly
bumpv 2.4.0+7               # set version and build number
```

| Option | Effect |
|---|---|
| `--build N` | Set the build number explicitly |
| `--bump-build` | Increment the build number |
| `--commit`, `-c` | Commit the updated files (Git projects) |
| `--tag`, `-t` | Tag the bump commit — `--tag=NAME` to name it yourself |
| `--tag-format FORMAT` | Name the tag from a template such as `v{version}`; implies `--tag` |
| `--dry-run` | Print what would change, write nothing |
| `--project DIR` | Target another directory |

The build number is **preserved** unless you pass `--build` or `--bump-build`.
App stores reject a repeated build number, so use `--bump-build` for a release:

```bash
bumpv minor --bump-build    # 1.2.1+1 -> 1.3.0+2
```

### Committing the bump

`--commit` (or `-c`) commits the files it just wrote:

```console
$ bumpv patch --commit
1.2.1+1  ->  1.2.2+1

  pubspec.yaml               1.2.1+1 -> 1.2.2+1
  ios/…/project.pbxproj      FLUTTER_BUILD_NAME: 1.2.1 -> 1.2.2  (Debug, Release, Profile)
  android                    no edit needed — versionName/versionCode come from pubspec.yaml

Done. Committed:  chore: bump version to 1.2.2
```

Only the files bumpv wrote go into the commit, so whatever else you have in
progress stays exactly where it was — staged or not. If the project isn't a Git
repository you get a warning and the bump still stands, and `--dry-run` wins:
nothing is written and nothing is committed.

### Tagging the release

`--tag` (or `-t`) puts an annotated tag on that commit, named after the new
version:

```console
$ bumpv minor --tag
1.2.1+1  ->  1.3.0+1

  pubspec.yaml               1.2.1+1 -> 1.3.0+1
  ios/…/project.pbxproj      FLUTTER_BUILD_NAME: 1.2.1 -> 1.3.0  (Debug, Release, Profile)
  android                    no edit needed — versionName/versionCode come from pubspec.yaml

Done. Committed:  chore: bump version to 1.3.0
Tagged:           1.3.0
```

To choose the name yourself, **attach** it — `--tag=NAME` or `-tNAME`:

```bash
bumpv minor --tag=v1.3.0     # tag it v1.3.0
bumpv minor -tv1.3.0         # same, short form
```

The value has to be attached because it is optional: in `bumpv --tag minor`
there would be no way to tell a tag name from the bump type, so a detached
name is rejected with a hint rather than quietly doing the wrong thing.

`--tag` implies `--commit` — a tag is only worth having on the commit that
carries the bump. The exceptions behave the way you would expect: `--dry-run`
creates no tag, a project without Git warns, and if the version is already
current there is nothing to commit, so the tag simply goes on `HEAD`. Should
the tag name already exist, Git says so and bumpv exits non-zero with the bump
itself intact — re-running with the version you just set tags it without
touching anything else.

### Naming tags with a format

Most projects want every tag shaped the same way, such as `v1.3.0`. Give
`--tag-format` a template and bumpv fills it in; it implies `--tag`:

```bash
bumpv minor --tag-format=v{version}           # v1.3.0
bumpv minor --tag-format={version}-beta       # 1.3.0-beta
bumpv minor --tag-format=app-v{version}       # app-v1.3.0 (monorepos)
bumpv minor --bump-build --tag-format=v{version}+{build}   # v1.3.0+2
```

| Placeholder | Becomes |
|---|---|
| `{version}` | The new version without the build number: `1.3.0` |
| `{build}` | The build number after the bump: `2` |

A format must contain `{version}`, because without it every release would get
the same tag, and any other placeholder is rejected as a likely typo.

To use one format for every release, put it in `pubspec.yaml`. A plain `--tag`
then picks it up:

```yaml
bumpv:
  tag_format: v{version}
```

```bash
bumpv minor --tag       # tagged v1.3.0
```

The setting only names tags; it never creates one by itself. When more than one
name is given, the most specific wins: `--tag=NAME`, then `--tag-format`, then
`bumpv.tag_format`, then the bare version. Passing both `--tag=NAME` and
`--tag-format` is a usage error. bumpv reads the `bumpv:` section on every run
and stops before writing anything if it holds an unknown key or an invalid
format.

### Repairing drift

Run `bumpv` with the version you already have. It won't change the version, but
it will re-sync the native files and report anything that was out of step:

```console
$ bumpv 1.3.0
1.3.0+1 (unchanged)

  pubspec.yaml               unchanged
  ios/…/project.pbxproj      FLUTTER_BUILD_NAME: 1.2.1 -> 1.3.0  (Debug, Release, Profile)
```

## What it touches

| File | Behaviour |
|---|---|
| `pubspec.yaml` | `version:` is rewritten |
| `ios/Runner.xcodeproj/project.pbxproj` | `FLUTTER_BUILD_NAME`, `FLUTTER_BUILD_NUMBER`, `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` are synced **in the app target only** — settings the project doesn't declare are left absent, and test targets keep their own version |
| `android/app/build.gradle[.kts]` | Hardcoded `versionName`/`versionCode` are rewritten (Kotlin DSL and Groovy). When they defer to `flutter.versionName`/`flutter.versionCode`, nothing is written and that is reported |

Nothing else in those files is altered.

## Use it as a library

The updaters are pure functions from file content to file content, so you can
drive them from your own release script without inheriting any filesystem
assumptions:

```dart
import 'package:easy_semver/easy_semver.dart';

final next = Version.tryParse('1.4.0+2')!;

final yaml = updatePubspec(pubspecText, next);

final ios = updateXcodeProject(pbxprojText, next);
print(describeChanges(ios.changes));   // FLUTTER_BUILD_NAME: 1.2.1 -> 1.4.0, …
print(ios.configurations);             // [Debug, Release, Profile]
```

## Not handled

macOS, Windows and Linux desktop targets keep their own version files and are
out of scope for now.

## License

MIT
