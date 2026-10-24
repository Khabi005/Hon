import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/utils/reading_time.dart';
import 'package:hon/features/reader/presentation/reader_document.dart';

void main() {
  test('time left rounds up and switches to hours', () {
    expect(minutesLeftLabel(0), isNull);
    expect(minutesLeftLabel(1), '1 min left');
    expect(minutesLeftLabel(averageReadingWpm * 12), '12 min left');
    expect(minutesLeftLabel(averageReadingWpm * 12 + 1), '13 min left');
    expect(minutesLeftLabel(averageReadingWpm * 60), '1 h left');
    expect(minutesLeftLabel(averageReadingWpm * 75), '1 h 15 min left');
  });

  test(
    'words from an anchor count the rest of its block and all later ones',
    () {
      final document = ReaderDocument.parse(
        '<p>one two three four</p><p>five six</p><hr><p>seven</p>',
      );
      final first = document.blocks.indexWhere((b) => b.text.startsWith('one'));
      expect(document.wordsFrom(ReaderTextAnchor(first)), 7);
      // Offset 8 is the start of "three".
      expect(document.wordsFrom(ReaderTextAnchor(first, 8)), 5);
      expect(
        document.wordsFrom(ReaderTextAnchor(document.blocks.length - 1)),
        1,
      );
      expect(document.wordsFrom(ReaderTextAnchor(document.blocks.length)), 0);
    },
  );
}
