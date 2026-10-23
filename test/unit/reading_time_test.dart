import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/utils/reading_time.dart';

void main() {
  final start = DateTime(2026, 10, 23, 20);

  test('active session counts in full', () {
    final end = start.add(const Duration(minutes: 12));
    final last = end.subtract(const Duration(seconds: 30));
    expect(countedReadingSeconds(start, last, end), 12 * 60);
  });

  test('idle tail is cut at the cap', () {
    final last = start.add(const Duration(minutes: 10));
    final end = start.add(const Duration(hours: 2));
    expect(countedReadingSeconds(start, last, end), (10 + 5) * 60);
    expect(readingWentIdle(start, last, end), isTrue);
  });

  test('activity before the session started counts from the start', () {
    final last = start.subtract(const Duration(hours: 1));
    final end = start.add(const Duration(minutes: 2));
    expect(countedReadingSeconds(start, last, end), 120);
    expect(readingWentIdle(start, last, end), isFalse);
  });

  test('no activity at all still caps', () {
    final end = start.add(const Duration(minutes: 40));
    expect(countedReadingSeconds(start, null, end), 5 * 60);
  });
}
