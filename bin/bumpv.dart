import 'dart:io';

import 'package:easy_semver/easy_semver.dart';

/// Entrypoint for the `bumpv` command.
///
/// Kept deliberately thin: all behaviour lives in `run`, which returns an exit
/// code rather than calling `exit()`, so it can be driven from tests.
void main(List<String> args) => exitCode = run(args);
