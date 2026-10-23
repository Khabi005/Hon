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

/// A typical silent reading speed for fiction, in words per minute.
const averageReadingWpm = 230;

final _word = RegExp(r'\S+');

/// Number of words in [text].
int countWords(String text) => _word.allMatches(text).length;

/// "12 min left", rounded up so the last page never says 0, or null when
/// there is nothing left to read.
String? minutesLeftLabel(int words, {int wpm = averageReadingWpm}) {
  if (words <= 0) return null;
  final minutes = (words / wpm).ceil();
  if (minutes < 60) return '$minutes min left';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0 ? '$hours h left' : '$hours h $rest min left';
}
