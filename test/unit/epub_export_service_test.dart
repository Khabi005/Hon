import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/export/epub_export_service.dart';
import 'package:hon/core/files/storage_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';

void main() {
  group('EpubExportService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('hon_epub_export_test_');
      StorageService.instance.setBaseDirForTesting(tempDir);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    final testBook = Book(
      id: 'test_series_123',
      title: 'The Great Journey',
      author: 'Author Nim',
      format: BookFormat.webNovel,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('fails gracefully when no downloaded chapters are available', () async {
      final chapters = [
        Chapter(
          id: 'ch_1',
          bookId: testBook.id,
          sourceChapterId: 'src_1',
          title: 'Chapter 1: The Call',
          chapterIndex: 0.0,
          downloadState: ChapterDownloadState.notDownloaded,
          localFilePath: null,
          updatedAt: DateTime.now(),
        ),
      ];

      final result = await EpubExportService.exportSeriesAsEpub(
        book: testBook,
        chapters: chapters,
        outputDirectoryPath: tempDir.path,
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, contains('No downloaded chapters found'));
    });

    test('generates valid EPUB 3 with proper structure and uncompressed mimetype', () async {
      // Create temporary chapter files with mock HTML content
      final ch1File = File('${tempDir.path}/ch1.html');
      await ch1File.writeAsString('''
<div class="chapter-content">
  <div class="ad-container">Ad banner here</div>
  <p>The dawn was breaking across the horizon.</p>
  <p>Elena tightened the grip on her staff.</p>
</div>
''');

      final ch2File = File('${tempDir.path}/ch2.html');
      await ch2File.writeAsString('''
<div class="chapter-content">
  <p>"We must make haste," Marcus urged.</p>
  <p>They stepped into the ancient ruins.</p>
  <p>Visit novelupdates.com to read ahead.</p>
</div>
''');

      final chapters = [
        Chapter(
          id: 'ch_1',
          bookId: testBook.id,
          sourceChapterId: 'src_1',
          title: 'Chapter 1: Dawn',
          chapterIndex: 0.0,
          downloadState: ChapterDownloadState.downloaded,
          localFilePath: ch1File.path,
          updatedAt: DateTime.now(),
        ),
        Chapter(
          id: 'ch_2',
          bookId: testBook.id,
          sourceChapterId: 'src_2',
          title: 'Chapter 2: The Ruins',
          chapterIndex: 1.0,
          downloadState: ChapterDownloadState.downloaded,
          localFilePath: ch2File.path,
          updatedAt: DateTime.now(),
        ),
      ];

      final result = await EpubExportService.exportSeriesAsEpub(
        book: testBook,
        chapters: chapters,
        outputDirectoryPath: tempDir.path,
      );

      expect(result.success, isTrue);
      expect(result.chapterCount, 2);
      expect(result.exportedFilePath, isNotNull);

      final exportedFile = File(result.exportedFilePath!);
      expect(await exportedFile.exists(), isTrue);

      // Inspect EPUB archive structure
      final zipBytes = await exportedFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      // 1. mimetype must be the first file and contain 'application/epub+zip'
      expect(archive.files.isNotEmpty, isTrue);
      final firstFile = archive.files.first;
      expect(firstFile.name, 'mimetype');
      expect(utf8.decode(firstFile.content as List<int>), 'application/epub+zip');

      // 2. META-INF/container.xml
      final container = archive.findFile('META-INF/container.xml');
      expect(container, isNotNull);
      final containerXml = utf8.decode(container!.content as List<int>);
      expect(containerXml, contains('full-path="OEBPS/content.opf"'));

      // 3. OEBPS/style.css
      final css = archive.findFile('OEBPS/style.css');
      expect(css, isNotNull);

      // 4. OEBPS/content.opf (metadata, manifest, spine)
      final opf = archive.findFile('OEBPS/content.opf');
      expect(opf, isNotNull);
      final opfXml = utf8.decode(opf!.content as List<int>);
      expect(opfXml, contains('<dc:title>The Great Journey</dc:title>'));
      expect(opfXml, contains('<dc:creator>Author Nim</dc:creator>'));
      expect(opfXml, contains('id="ch_1" href="chapter_001.xhtml"'));
      expect(opfXml, contains('id="ch_2" href="chapter_002.xhtml"'));
      expect(opfXml, contains('<itemref idref="ch_1"/>'));
      expect(opfXml, contains('<itemref idref="ch_2"/>'));

      // 5. OEBPS/toc.xhtml (EPUB 3 nav)
      final toc = archive.findFile('OEBPS/toc.xhtml');
      expect(toc, isNotNull);
      final tocXml = utf8.decode(toc!.content as List<int>);
      expect(tocXml, contains('<nav epub:type="toc" id="toc">'));
      expect(tocXml, contains('<a href="chapter_001.xhtml">Chapter 1: Dawn</a>'));
      expect(tocXml, contains('<a href="chapter_002.xhtml">Chapter 2: The Ruins</a>'));

      // 6. Chapter XHTML files (sanitized content)
      final ch1Xhtml = archive.findFile('OEBPS/chapter_001.xhtml');
      expect(ch1Xhtml, isNotNull);
      final ch1Content = utf8.decode(ch1Xhtml!.content as List<int>);
      expect(ch1Content, contains('The dawn was breaking across the horizon.'));
      expect(ch1Content, isNot(contains('Ad banner here')));

      final ch2Xhtml = archive.findFile('OEBPS/chapter_002.xhtml');
      expect(ch2Xhtml, isNotNull);
      final ch2Content = utf8.decode(ch2Xhtml!.content as List<int>);
      expect(ch2Content, contains('They stepped into the ancient ruins.'));
      expect(ch2Content, isNot(contains('Visit novelupdates.com')));
    });

    test('bundles illustrations correctly, dedupes, strips missing images, and writes atomically', () async {
      // Configure managed storage baseDir
      StorageService.instance.setBaseDirForTesting(tempDir);
      final imagesDir = Directory('${tempDir.path}/images');
      await imagesDir.create(recursive: true);

      // Create valid managed image files
      final image1File = File('${imagesDir.path}/scene 1.png');
      await image1File.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]); // PNG header
      final image2File = File('${imagesDir.path}/scene2.jpg');
      await image2File.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0]); // JPEG header

      // Chapter with:
      // 1) single-slash file:/ URI
      // 2) percent-encoded URI pointing to same image1 (deduplication)
      // 3) valid second image
      // 4) missing image in managed dir
      // 5) unmanaged system file outside managed storage
      final chFile = File('${tempDir.path}/ch_with_images.html');
      final singleSlashUri = 'file:${image1File.path}';
      final encodedUri = 'file://${Uri.encodeFull(image1File.path)}';
      final normalUri = 'file://${image2File.path}';
      final missingUri = 'file://${imagesDir.path}/nonexistent.png';
      const unmanagedUri = 'file:///etc/hosts';

      await chFile.writeAsString('''
<div class="chapter-content">
  <p>First paragraph.</p>
  <img src="$singleSlashUri" alt="Scene 1" />
  <p>Second paragraph with repeated illustration.</p>
  <img src="$encodedUri" alt="Scene 1 Duplicate" />
  <p>Third paragraph.</p>
  <img src="$normalUri" />
  <p>Fourth paragraph with missing and unmanaged images.</p>
  <img src="$missingUri" />
  <img src="$unmanagedUri" />
</div>
''');

      final chapters = [
        Chapter(
          id: 'ch_img',
          bookId: testBook.id,
          sourceChapterId: 'src_img',
          title: 'Illustrated Chapter',
          chapterIndex: 0.0,
          downloadState: ChapterDownloadState.downloaded,
          localFilePath: chFile.path,
          updatedAt: DateTime.now(),
        ),
      ];

      final result = await EpubExportService.exportSeriesAsEpub(
        book: testBook,
        chapters: chapters,
        outputDirectoryPath: tempDir.path,
      );

      expect(result.success, isTrue);
      expect(result.exportedFilePath, isNotNull);

      // Verify atomic writing: .epub exists and .part file is gone
      final exportedFile = File(result.exportedFilePath!);
      expect(await exportedFile.exists(), isTrue);
      final partFiles = tempDir.listSync().where((f) => f.path.endsWith('.part'));
      expect(partFiles, isEmpty);

      // Inspect EPUB archive
      final zipBytes = await exportedFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);

      // Check bundled images in archive: exactly 2 distinct images bundled
      final bundledImages = archive.files.where((f) => f.name.startsWith('OEBPS/images/')).toList();
      expect(bundledImages.length, 2);
      expect(archive.findFile('OEBPS/images/img_0001.png'), isNotNull);
      expect(archive.findFile('OEBPS/images/img_0002.jpg'), isNotNull);

      // Check content.opf manifest
      final opf = archive.findFile('OEBPS/content.opf');
      expect(opf, isNotNull);
      final opfXml = utf8.decode(opf!.content as List<int>);
      expect(opfXml, contains('href="images/img_0001.png" media-type="image/png"'));
      expect(opfXml, contains('href="images/img_0002.jpg" media-type="image/jpeg"'));
      expect(opfXml, isNot(contains('nonexistent')));
      expect(opfXml, isNot(contains('hosts')));

      // Check chapter XHTML
      final chXhtml = archive.findFile('OEBPS/chapter_001.xhtml');
      expect(chXhtml, isNotNull);
      final chContent = utf8.decode(chXhtml!.content as List<int>);
      // Single-slash URI and encoded URI were both replaced by relative href to img_0001.png
      expect(chContent, contains('src="images/img_0001.png" alt="Scene 1"'));
      expect(chContent, contains('src="images/img_0001.png" alt="Scene 1 Duplicate"'));
      expect(chContent, contains('src="images/img_0002.jpg"'));
      // Missing and unmanaged images were stripped completely
      expect(chContent, isNot(contains('nonexistent')));
      expect(chContent, isNot(contains('hosts')));
    });

    test('bundles relative image paths and inline base64 data URIs', () async {
      final chaptersDir = Directory('${tempDir.path}/chapters');
      await chaptersDir.create(recursive: true);
      final chDir = Directory('${chaptersDir.path}/ch_rel_dir')..createSync(recursive: true);
      final relImgFile = File('${chDir.path}/relative_illustration.png');
      await relImgFile.writeAsBytes([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00]);

      final chFile = File('${chDir.path}/chapter.html');
      const dataUri = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
      await chFile.writeAsString('''
<div class="chapter-content">
  <p>Relative image test:</p>
  <img src="relative_illustration.png" alt="Relative Image" />
  <p>Data URI test:</p>
  <img src="$dataUri" alt="Data URI Image" />
</div>
''');

      final chapters = [
        Chapter(
          id: 'ch_rel',
          bookId: testBook.id,
          sourceChapterId: 'src_rel',
          title: 'Relative & Data URI Chapter',
          chapterIndex: 0.0,
          downloadState: ChapterDownloadState.downloaded,
          localFilePath: chFile.path,
          updatedAt: DateTime.now(),
        ),
      ];

      final result = await EpubExportService.exportSeriesAsEpub(
        book: testBook,
        chapters: chapters,
        outputDirectoryPath: tempDir.path,
      );

      expect(result.success, isTrue);
      expect(result.exportedFilePath, isNotNull);

      final exportedFile = File(result.exportedFilePath!);
      final archive = ZipDecoder().decodeBytes(await exportedFile.readAsBytes());

      // Both relative image and data URI should be bundled into OEBPS/images/
      final bundledImages = archive.files.where((f) => f.name.startsWith('OEBPS/images/')).toList();
      expect(bundledImages.length, 2);

      final chXhtml = archive.findFile('OEBPS/chapter_001.xhtml');
      expect(chXhtml, isNotNull);
      final chContent = utf8.decode(chXhtml!.content as List<int>);
      expect(chContent, contains('src="images/img_0001.png" alt="Relative Image"'));
      expect(chContent, contains('src="images/img_0002.png" alt="Data URI Image"'));
    });
  });
}
