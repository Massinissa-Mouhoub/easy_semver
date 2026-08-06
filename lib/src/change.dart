/// One build setting that was rewritten, and what it held beforehand.
///
/// [before] is a set because the same setting appears in several build
/// configurations (Debug/Release/Profile) and they can have drifted apart —
/// reporting `1.2.1/1.3.0 -> 1.4.0` is more honest than picking one.
class SettingChange {
  final String key;
  final Set<String> before;
  final String after;

  const SettingChange({
    required this.key,
    required this.before,
    required this.after,
  });

  /// False when every configuration already held [after], i.e. nothing moved.
  bool get isChange =>
      before.isNotEmpty && !(before.length == 1 && before.first == after);

  @override
  String toString() {
    final from = (before.toList()..sort()).join('/');
    return '$key: $from -> $after';
  }
}

/// Formats a list of changes for the console, or null when nothing moved.
String? describeChanges(Iterable<SettingChange> changes) {
  final moved = changes.where((c) => c.isChange).toList();
  if (moved.isEmpty) return null;
  return moved.join(', ');
}
