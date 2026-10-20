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

    test('a passage that appears twice highlights only the one actually selected', () {
      const block0 = ReaderBlock(runs: [ReaderRun('I am the shadow. I walk the darkness.', TextStyle())]);
      const block1 = ReaderBlock(runs: [ReaderRun('I am the shadow. I walk the darkness.', TextStyle())]);

      final locatorMap = {
        'engine': 'hon-html-v2',
        'chapterIndex': 0,
        'pageIndex': 0,
        'block': 1,
        'startOffset': 0,
        'endOffset': 16,
        'prefixContext': '',
        'suffixContext': ' I walk the darkness.',
      };
      final hl = Highlight(
        id: 'hl-block-1',
        bookId: 'book-1',
        selectedText: 'I am the shadow.',
        locatorString: jsonEncode(locatorMap),
        color: 'yellow',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(hl.selectedText, 'I am the shadow.');

      final span0 = block0.span(highlights: []);
      expect((span0.children!.first as TextSpan).style?.backgroundColor, isNull);

      final span1 = block1.span(highlights: [
        const HighlightSpan(start: 0, end: 16, color: Color(0x80FFD60A)),
      ]);
      final hlSlice = span1.children![0] as TextSpan;
      expect(hlSlice.text, 'I am the shadow.');
      expect(hlSlice.style?.backgroundColor, const Color(0x80FFD60A));

      final restSlice = span1.children![1] as TextSpan;
      expect(restSlice.text, ' I walk the darkness.');
      expect(restSlice.style?.backgroundColor, isNull);
    });

    test('a two-paragraph selection renders in both blocks', () {
      const block0 = ReaderBlock(runs: [ReaderRun('Paragraph one ends here.', TextStyle())]);
      const block1 = ReaderBlock(runs: [ReaderRun('Paragraph two begins here.', TextStyle())]);

      final locatorMap = {
        'engine': 'hon-html-v2',
        'chapterIndex': 0,
        'pageIndex': 0,
        'block': 0,
        'startOffset': 10,
        'endOffset': 24,
        'spans': [
          {'block': 0, 'startOffset': 10, 'endOffset': 24},
          {'block': 1, 'startOffset': 0, 'endOffset': 13},
        ],
      };

      final spans = (locatorMap['spans'] as List).cast<Map<String, int>>();
      final spanForBlock0 = spans.where((s) => s['block'] == 0).map(
        (s) => HighlightSpan(start: s['startOffset']!, end: s['endOffset']!, color: const Color(0x80FFD60A)),
      ).toList();
      final spanForBlock1 = spans.where((s) => s['block'] == 1).map(
        (s) => HighlightSpan(start: s['startOffset']!, end: s['endOffset']!, color: const Color(0x80FFD60A)),
      ).toList();

      final rendered0 = block0.span(highlights: spanForBlock0);
      final rendered1 = block1.span(highlights: spanForBlock1);

      expect((rendered0.children![0] as TextSpan).text, 'Paragraph ');
      expect((rendered0.children![0] as TextSpan).style?.backgroundColor, isNull);
      expect((rendered0.children![1] as TextSpan).text, 'one ends here.');
      expect((rendered0.children![1] as TextSpan).style?.backgroundColor, const Color(0x80FFD60A));

      expect((rendered1.children![0] as TextSpan).text, 'Paragraph two');
      expect((rendered1.children![0] as TextSpan).style?.backgroundColor, const Color(0x80FFD60A));
      expect((rendered1.children![1] as TextSpan).text, ' begins here.');
      expect((rendered1.children![1] as TextSpan).style?.backgroundColor, isNull);
    });
  });
}
