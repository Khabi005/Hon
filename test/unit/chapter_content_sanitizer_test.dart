import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/sources/chapter_content_sanitizer.dart';

void main() {
  group('ChapterContentSanitizer', () {
    test('removes scripts, styles, iframes, and forms', () {
      const dirtyHtml = '''
<div>
  <script>alert("malicious script");</script>
  <style>.ad { color: red; }</style>
  <p>The dawn was breaking over the horizon.</p>
  <iframe src="https://ads.example.com"></iframe>
  <form action="/submit"><input type="text"/></form>
  <p>Arthur drew his sword from the stone.</p>
</div>
''';

      final clean = ChapterContentSanitizer.sanitize(dirtyHtml);

      expect(clean, isNot(contains('<script')));
      expect(clean, isNot(contains('<style')));
      expect(clean, isNot(contains('<iframe')));
      expect(clean, isNot(contains('<form')));
      expect(clean, contains('The dawn was breaking over the horizon.'));
      expect(clean, contains('Arthur drew his sword from the stone.'));
    });

    test('removes ad elements matching class and id patterns', () {
      const dirtyHtml = '''
<div>
  <div class="banner-ad advertisement">Click here to win a prize!</div>
  <p>First paragraph of the chapter.</p>
  <div id="adsbygoogle" class="sponsor">Sponsored content</div>
  <p>Second paragraph of the chapter.</p>
  <div class="patreon-box">Support me on Patreon for bonuses!</div>
  <div class="watermark">Read on FakeNovel.com</div>
  <p>Third paragraph of the chapter.</p>
</div>
''';

      final clean = ChapterContentSanitizer.sanitize(dirtyHtml);

      expect(clean, isNot(contains('Click here to win a prize!')));
      expect(clean, isNot(contains('Sponsored content')));
      expect(clean, isNot(contains('Support me on Patreon for bonuses!')));
      expect(clean, isNot(contains('Read on FakeNovel.com')));
      expect(clean, contains('First paragraph of the chapter.'));
      expect(clean, contains('Second paragraph of the chapter.'));
      expect(clean, contains('Third paragraph of the chapter.'));
    });

    test('removes promotional sentences while preserving actual narrative', () {
      const dirtyHtml = '''
<div>
  <p>Visit novelupdates.com to read up to 10 chapters ahead of the public release.</p>
  <p>The wind howled across the desolate mountain peak.</p>
  <p>Join our Discord server: https://discord.gg/example</p>
  <p>"We must make camp before nightfall," Elena whispered.</p>
  <p>This chapter is updated by NovelFull</p>
</div>
''';

      final clean = ChapterContentSanitizer.sanitize(dirtyHtml);

      expect(clean, isNot(contains('read up to 10 chapters ahead')));
      expect(clean, isNot(contains('Join our Discord server')));
      expect(clean, isNot(contains('This chapter is updated by')));
      expect(clean, contains('The wind howled across the desolate mountain peak.'));
      expect(clean, contains('"We must make camp before nightfall," Elena whispered.'));
    });

    test('preserves illustrations and cleans unsafe attributes', () {
      const rawHtml = '''
<p>
  <img src="https://images.example.com/ch1_illustration.jpg" alt="Dragon" onclick="badFunc()" data-ad-slot="1234"/>
  The dragon roared fiercely.
</p>
''';

      final clean = ChapterContentSanitizer.sanitize(rawHtml);

      expect(clean, contains('src="https://images.example.com/ch1_illustration.jpg"'));
      expect(clean, contains('alt="Dragon"'));
      expect(clean, isNot(contains('onclick')));
      expect(clean, isNot(contains('data-ad-slot')));
      expect(clean, contains('The dragon roared fiercely.'));
    });

    test('wraps plaintext into HTML paragraphs', () {
      const plainText = 'Line 1 of the story.\nLine 2 of the story.\n\nLine 3 after blank.';

      final clean = ChapterContentSanitizer.sanitize(plainText);

      expect(clean, contains('<p>Line 1 of the story.</p>'));
      expect(clean, contains('<p>Line 2 of the story.</p>'));
      expect(clean, contains('<p>Line 3 after blank.</p>'));
    });

    test('generates valid XHTML document with self-closed void tags', () {
      const body = '<p>First line<br>Second line with an image:<img src="test.png" alt="Test"></p>';

      final xhtml = ChapterContentSanitizer.toValidXhtml(
        title: 'Chapter 1: The Beginning & End',
        bodyHtml: body,
        cssPath: 'style.css',
      );

      expect(xhtml, startsWith('<?xml version="1.0" encoding="utf-8"?>'));
      expect(xhtml, contains('<!DOCTYPE html>'));
      expect(xhtml, contains('xmlns="http://www.w3.org/1999/xhtml"'));
      expect(xhtml, contains('<title>Chapter 1: The Beginning &amp; End</title>'));
      expect(xhtml, contains('<link rel="stylesheet" type="text/css" href="style.css" />'));
      expect(xhtml, contains('<br />'));
      expect(xhtml, contains('<img src="test.png" alt="Test" />'));
    });

    test('preserves legitimate translator attributions in prose', () {
      const html = '''
<div>
  <p>Translated by White Oak Translations</p>
  <p>Edited by Cedar</p>
  <p>The night was calm and quiet.</p>
</div>
''';
      final clean = ChapterContentSanitizer.sanitize(html);
      expect(clean, contains('Translated by White Oak Translations'));
      expect(clean, contains('Edited by Cedar'));
      expect(clean, contains('The night was calm and quiet.'));
    });

    test('removes duplicate chapter heading matching chapterTitle', () {
      const html = '''
<div>
  <h1>Chapter 42: The Revelation</h1>
  <p>The grand hall was filled with silence.</p>
</div>
''';
      final clean = ChapterContentSanitizer.sanitize(html, chapterTitle: 'Chapter 42: The Revelation');
      expect(clean, isNot(contains('<h1>')));
      expect(clean, isNot(contains('The Revelation')));
      expect(clean, contains('The grand hall was filled with silence.'));
    });

    test('restricts anchor href to http, https, and mailto schemes', () {
      const html = '''
<div>
  <p><a href="javascript:alert('xss')">Malicious Link</a></p>
  <p><a href="https://example.com/source">Safe Web Link</a></p>
  <p><a href="mailto:author@example.com">Contact Author</a></p>
  <p><a href="file:///etc/passwd">Unsafe File Link</a></p>
</div>
''';
      final clean = ChapterContentSanitizer.sanitize(html);
      expect(clean, isNot(contains('javascript:')));
      expect(clean, isNot(contains('file:///etc/passwd')));
      expect(clean, contains('href="https://example.com/source"'));
      expect(clean, contains('href="mailto:author@example.com"'));
    });
  });
}
