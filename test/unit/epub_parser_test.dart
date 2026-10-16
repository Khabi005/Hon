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
}
