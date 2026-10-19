import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/app/theme/reader_theme.dart';
import 'package:hon/features/reader/presentation/reader_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'rich pagination retains Unicode, nested formatting, links and images',
    () {
      final document = ReaderDocument.parse('''
      <section><h2>A heading</h2><p>Before <strong>bold <em>and italic</em></strong><br>日本語 🌙
      <a href="next">a link</a></p><img src="picture.png" alt="Map"><hr>
      <p>${List.filled(100, 'A long paragraph 🌙. ').join()}</p></section>
    ''', baseUrl: 'https://example.org/chapter/1');
      final paragraph = document.blocks.firstWhere(
        (block) => block.text.contains('Before'),
      );
      expect(
        paragraph.runs.any(
          (run) =>
              run.style.fontWeight == FontWeight.bold &&
              run.style.fontStyle == FontStyle.italic,
        ),
        isTrue,
      );
      expect(
        paragraph.runs.any(
          (run) => run.link == 'https://example.org/chapter/next',
        ),
        isTrue,
      );
      expect(
        document.blocks.where((block) => block.image != null).single.image,
        'https://example.org/chapter/picture.png',
      );
      final pages = document.paginate(
        const ReaderPreferencesState(),
        260,
        360,
        TextScaler.noScaling,
        TextDirection.ltr,
      );
      expect(pages.length, greaterThan(2));
      for (var block = 0; block < document.blocks.length; block++) {
        final original = document.blocks[block].text;
        if (original.isEmpty) continue;
        final restored = pages
            .expand((page) => page)
            .where((fragment) => fragment.block == block)
            .map((fragment) => original.substring(fragment.start, fragment.end))
            .join();
        expect(restored, original);
      }
      for (final page in pages) {
        expect(
          page.fold<double>(
            0,
            (height, fragment) => height + fragment.height + fragment.after,
          ),
          lessThanOrEqualTo(369),
        );
      }
    },
  );
}
