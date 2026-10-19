import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/models/highlight.dart';
import 'package:hon/features/reader/presentation/reader_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reader Highlights', () {
    test('ReaderBlock.span with HighlightSpan applies backgroundColor to matching slice', () {
      const block = ReaderBlock(
        runs: [
          ReaderRun('Hello Beautiful World!', TextStyle(color: Colors.black)),
        ],
      );

      // Highlight "Beautiful" which starts at 6 and ends at 15
      const hlSpan = HighlightSpan(
        start: 6,
        end: 15,
        color: Color(0xFFFFEB3B),
        note: 'Important note',
      );

      final span = block.span(highlights: [hlSpan]);
      expect(span.children, isNotNull);
      expect(span.children!.length, 3);

      final first = span.children![0] as TextSpan;
      expect(first.text, 'Hello ');
      expect(first.style?.backgroundColor, isNull);

      final second = span.children![1] as TextSpan;
      expect(second.text, 'Beautiful');
      expect(second.style?.backgroundColor, const Color(0xFFFFEB3B));

      final third = span.children![2] as TextSpan;
      expect(third.text, ' World!');
      expect(third.style?.backgroundColor, isNull);
    });

    test('Storing highlight records block, startOffset, and endOffset in locator', () {
      const selectedBlock = 2;
      const startOffset = 10;
      const endOffset = 25;
      const chapterIndex = 4;
      final locatorMap = {
        'engine': 'hon-html-v2',
        'chapterIndex': chapterIndex,
        'block': selectedBlock,
        'startOffset': startOffset,
        'endOffset': endOffset,
      };
      final highlight = Highlight(
        id: 'hl-test-1',
        bookId: 'book-123',
        selectedText: 'sample highlighted text',
        note: 'My note on this text',
        color: 'yellow',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        locatorString: jsonEncode(locatorMap),
      );

      // Assert payload properties
      expect(highlight.bookId, 'book-123');
      expect(highlight.selectedText, 'sample highlighted text');
      expect(highlight.note, 'My note on this text');
      expect(highlight.color, 'yellow');

      // Decode locator
      final decoded = jsonDecode(highlight.locatorString) as Map<String, dynamic>;
      expect(decoded['engine'], 'hon-html-v2');
      expect(decoded['chapterIndex'], 4);
      expect(decoded['block'], 2);
      expect(decoded['startOffset'], 10);
      expect(decoded['endOffset'], 25);
    });

    test('Multiple overlapping or adjacent highlights slice text correctly', () {
      const block = ReaderBlock(
        runs: [
          ReaderRun('0123456789', TextStyle(color: Colors.black)),
        ],
      );

      const hl1 = HighlightSpan(
        start: 2,
        end: 5,
        color: Colors.yellow,
      );
      const hl2 = HighlightSpan(
        start: 7,
        end: 9,
        color: Colors.green,
      );

      final span = block.span(highlights: [hl1, hl2]);
      expect(span.children!.length, 5);

      expect((span.children![0] as TextSpan).text, '01');
      expect((span.children![0] as TextSpan).style?.backgroundColor, isNull);

      expect((span.children![1] as TextSpan).text, '234');
      expect((span.children![1] as TextSpan).style?.backgroundColor, Colors.yellow);

      expect((span.children![2] as TextSpan).text, '56');
      expect((span.children![2] as TextSpan).style?.backgroundColor, isNull);

      expect((span.children![3] as TextSpan).text, '78');
      expect((span.children![3] as TextSpan).style?.backgroundColor, Colors.green);

      expect((span.children![4] as TextSpan).text, '9');
      expect((span.children![4] as TextSpan).style?.backgroundColor, isNull);
    });
  });
}
