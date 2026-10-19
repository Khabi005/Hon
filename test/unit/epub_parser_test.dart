import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/utils/epub_parser.dart';
import 'package:archive/archive.dart';

void main() {
  test('EPUB 2 cover metadata chooses an image over an XHTML cover page', () async {
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'META-INF/container.xml',
          '<container><rootfiles><rootfile full-path="OEBPS/content.opf"/></rootfiles></container>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/content.opf',
          '<package><metadata><meta name="cover" content="art"/></metadata>'
              '<manifest><item id="cover-page" href="cover.xhtml" media-type="application/xhtml+xml"/>'
              '<item id="art" href="images/cover%20photo.jpg" media-type="image/jpeg"/></manifest>'
              '<spine><itemref idref="cover-page"/></spine></package>',
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'OEBPS/cover.xhtml',
          '<html><body>Cover page</body></html>',
        ),
      )
      ..addFile(
        ArchiveFile('OEBPS/images/cover photo.jpg', 12, [
          0xff,
          0xd8,
          0xff,
          0xe0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
        ]),
      );
    final dir = await Directory.systemTemp.createTemp('hon_epub_cover_test_');
    try {
      final file = File('${dir.path}/book.epub');
      await file.writeAsBytes(ZipEncoder().encode(archive)!);
      final metadata = await EpubParser.parse(file);
      expect(metadata.coverBytes, isNotNull);
      expect(metadata.coverBytes!.take(3), [0xff, 0xd8, 0xff]);
    } finally {
      await dir.delete(recursive: true);
    }
  });

  test('EpubParser successfully parses valid EPUB fixture', () async {
    final file = File('assets/fixtures/pride_and_prejudice.epub');
    expect(file.existsSync(), isTrue);

    final metadata = await EpubParser.parse(file);

    expect(metadata.title, equals('Pride and Prejudice'));
    expect(metadata.author, equals('Jane Austen'));
    expect(metadata.chapters.length, equals(2));

    final ch1 = metadata.chapters[0];
    expect(ch1.title, equals('Chapter 33'));
    expect(ch1.htmlContent, contains('More than once did Elizabeth'));

    final ch2 = metadata.chapters[1];
    expect(ch2.title, equals('Chapter 40'));
    expect(
      ch2.htmlContent,
      contains('Elizabeth\'s impatience to acquaint Jane'),
    );
  });

  test(
    'metadata-only import keeps spine and cover without copying chapter bodies',
    () async {
      final metadata = await EpubParser.parse(
        File('assets/fixtures/pride_and_prejudice.epub'),
        includeContent: false,
      );
      expect(metadata.title, 'Pride and Prejudice');
      expect(metadata.chapters.length, 2);
      expect(
        metadata.chapters.map((chapter) => chapter.htmlContent),
        everyElement(isEmpty),
      );
      expect(
        metadata.chapters.map((chapter) => chapter.contentHref),
        everyElement(isNotEmpty),
      );
    },
  );

  test(
    'UTF-8 decoder handles multi-byte Unicode (curly quotes, em-dashes, non-Latin) correctly',
    () {
      const originalText = '“The Fool” — Zhou Mingrui (周明瑞) • café résumé';
      final utf8Bytes = utf8.encode(originalText);

      // Using raw char codes (the previous buggy behavior) corrupted UTF-8 multi-byte bytes:
      final buggyDecoded = String.fromCharCodes(utf8Bytes);
      expect(buggyDecoded, isNot(equals(originalText)));
      expect(buggyDecoded, contains('â'));

      // Proper utf8.decode preserves multi-byte glyphs exactly:
      final properlyDecoded = utf8.decode(utf8Bytes, allowMalformed: true);
      expect(properlyDecoded, equals(originalText));
      expect(properlyDecoded, contains('“The Fool”'));
      expect(properlyDecoded, contains('—'));
      expect(properlyDecoded, contains('周明瑞'));
    },
  );
}
