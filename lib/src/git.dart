import 'dart:io';

/// Whether [directory] sits inside a Git working tree.
///
/// Asks Git rather than looking for a `.git` directory: submodules and linked
/// worktrees use a `.git` *file*, and the project root is often below the
/// repository root in a monorepo.
bool isGitRepository(Directory directory) {
  final result = _git(const ['rev-parse', '--is-inside-work-tree'], directory);
  return result != null &&
      result.exitCode == 0 &&
      (result.stdout as String).trim() == 'true';
}

/// Stages [files] and commits them with [message].
///
/// Only the given files are committed, so unrelated work in progress stays out
/// of the commit. Returns null on success, or a message describing the failure.
String? commitFiles({
  required Directory root,
  required Iterable<File> files,
  required String message,
}) {
  final paths = files.map((file) => file.path).toList();

  final staged = _git(['add', '--', ...paths], root);
  if (staged == null) return _gitMissing;
  if (staged.exitCode != 0) return _describe('git add', staged);

  // --only limits the commit to these paths even if something else was already
  // staged, so a version bump never sweeps up unrelated changes.
  final committed =
      _git(['commit', '--only', '-m', message, '--', ...paths], root);
  if (committed == null) return _gitMissing;
  if (committed.exitCode != 0) return _describe('git commit', committed);

  return null;
}

const _gitMissing = 'git is not installed or not on PATH';

/// Runs git in [directory], returning null when git itself cannot be run.
ProcessResult? _git(List<String> arguments, Directory directory) {
  try {
    return Process.runSync(
      'git',
      arguments,
      workingDirectory: directory.path,
      stdoutEncoding: systemEncoding,
      stderrEncoding: systemEncoding,
    );
  } on ProcessException {
    return null;
  }
}

/// Git reports some failures (an empty commit, a rejecting hook) on stdout
/// rather than stderr, so fall back to it before giving up on a reason.
String _describe(String command, ProcessResult result) {
  final stderrText = (result.stderr as String).trim();
  final stdoutText = (result.stdout as String).trim();
  final detail = stderrText.isNotEmpty ? stderrText : stdoutText;
  return detail.isEmpty
      ? '$command failed with exit code ${result.exitCode}'
      : '$command failed: $detail';
}
