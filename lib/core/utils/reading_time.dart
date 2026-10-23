/// How long a page can sit untouched before the time stops counting as
/// reading. Long enough for a dense page, short enough that a phone left open
/// on the nightstand doesn't log an hour.
const readingIdleCap = Duration(minutes: 5);

/// Seconds of the session from [start] to [end] that count as reading.
///
/// [lastActivity] is the last scroll, tap or page turn. Once nothing has
/// happened for [idleCap], the rest of the session is not counted.
int countedReadingSeconds(
  DateTime start,
  DateTime? lastActivity,
  DateTime end, {
  Duration idleCap = readingIdleCap,
}) {
  final active = lastActivity == null || lastActivity.isBefore(start)
      ? start
      : lastActivity;
  final cutoff = active.add(idleCap);
  final stop = end.isAfter(cutoff) ? cutoff : end;
  final seconds = stop.difference(start).inSeconds;
  return seconds > 0 ? seconds : 0;
}

/// Whether the gap since [lastActivity] is long enough that the session
/// should be banked and a fresh one started at the next interaction.
bool readingWentIdle(
  DateTime start,
  DateTime? lastActivity,
  DateTime now, {
  Duration idleCap = readingIdleCap,
}) {
  final active = lastActivity == null || lastActivity.isBefore(start)
      ? start
      : lastActivity;
  return now.difference(active) > idleCap;
}
