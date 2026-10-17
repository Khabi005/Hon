import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/utils/epub_parser.dart';

void main() {
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
    expect(ch2.htmlContent, contains('Elizabeth\'s impatience to acquaint Jane'));
  });

  test('UTF-8 decoder handles multi-byte Unicode (curly quotes, em-dashes, non-Latin) correctly', () {
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
  });
}
