/// A short "how long ago" label for the drafts list, e.g. `2 h ago`.
///
/// Returns `null` once the timestamp is a week old: at that point a date reads
/// better than "9 d ago", and the caller can format one for the active locale.
String? relativeTimeLabel(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(time);
  // A clock that moved backwards should not produce "-3 h ago".
  if (difference.isNegative) return 'just now';
  if (difference.inMinutes < 1) return 'just now';
  if (difference.inMinutes < 60) {
    final minutes = difference.inMinutes;
    return '$minutes min ago';
  }
  if (difference.inHours < 24) {
    final hours = difference.inHours;
    return '$hours h ago';
  }
  if (difference.inDays < 7) {
    final days = difference.inDays;
    return days == 1 ? 'yesterday' : '$days d ago';
  }
  return null;
}
