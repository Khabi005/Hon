import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../database/database_service.dart';
import '../files/storage_service.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../sources/chapter_content_sanitizer.dart';
import '../utils/log_ignored.dart';

class EpubExportResult {
  final bool success;
  final String? exportedFilePath;
  final int chapterCount;
  final int omittedImageCount;
  final String? errorMessage;

  const EpubExportResult({
    required this.success,
    this.exportedFilePath,
    this.chapterCount = 0,
    this.omittedImageCount = 0,
    this.errorMessage,
  });
}

class ShareResult {
  final bool success;
  final String? errorMessage;

  const ShareResult({
    required this.success,
    this.errorMessage,
  });
}

enum SaveAsStatus {
  saved,
  cancelled,
  failed,
}

class SaveAsResult {
  final SaveAsStatus status;
  final String? errorMessage;

  const SaveAsResult({
    required this.status,
    this.errorMessage,
  });

  bool get isSaved => status == SaveAsStatus.saved;
  bool get isCancelled => status == SaveAsStatus.cancelled;
  bool get isFailed => status == SaveAsStatus.failed;
}

List<int>? _encodeZipArchive(Archive archive) {
  return ZipEncoder().encode(archive);
}

/// Service that compiles offline downloaded chapters of a novel series
/// into a standard, fully validated EPUB 3 publication.
class EpubExportService {
  static Future<EpubExportResult> exportSeriesAsEpub({
    required Book book,
    List<Chapter>? chapters,
    String? outputDirectoryPath,
  }) async {
    try {
      // 1. Gather downloaded chapters
      if (chapters == null) {
        await DatabaseService.instance.ensureChaptersLoaded(book.id);
      }
    final allChapters = chapters ?? DatabaseService.instance.getChapters(book.id);
    final downloaded = allChapters.where((c) {
      if (c.downloadState != ChapterDownloadState.downloaded) return false;
      final path = c.localFilePath;
      if (path == null) return false;
      return File(path).existsSync();
    }).toList();

    // Sort chapters in ascending reading order
    downloaded.sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));

    if (downloaded.isEmpty) {
      return const EpubExportResult(
        success: false,
        errorMessage: 'No downloaded chapters found for this series. Please download chapters first.',
      );
    }

    // 2. Prepare EPUB archive
    final archive = Archive();

    // 2.1 mimetype MUST be the very first file, uncompressed (STORED)
    final mimetypeBytes = utf8.encode('application/epub+zip');
    final mimetypeFile = ArchiveFile('mimetype', mimetypeBytes.length, mimetypeBytes)
      ..compress = false;
    archive.addFile(mimetypeFile);

    // 2.2 META-INF/container.xml
    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''';
    final containerBytes = utf8.encode(containerXml);
    archive.addFile(ArchiveFile('META-INF/container.xml', containerBytes.length, containerBytes));

    // 2.3 OEBPS/style.css
    const styleCss = '''
body {
  font-family: Georgia, serif;
  line-height: 1.65;
  margin: 1.5em;
  color: #1a1a1a;
  background-color: #ffffff;
}
h1, h2 {
  text-align: center;
  margin-top: 1.5em;
  margin-bottom: 1em;
}
p {
  text-indent: 1.5em;
  margin-top: 0;
  margin-bottom: 0.5em;
}
img {
  max-width: 100%;
  height: auto;
  display: block;
  margin: 1em auto;
}
''';
    final cssBytes = utf8.encode(styleCss);
    archive.addFile(ArchiveFile('OEBPS/style.css', cssBytes.length, cssBytes));

    // 2.4 Chapters
    final manifestItems = <String>[];
    final spineItems = <String>[];
    final navItems = <String>[];
    final ncxNavPoints = <String>[];

    manifestItems.add('<item id="style" href="style.css" media-type="text/css"/>');
    manifestItems.add('<item id="toc" href="toc.xhtml" media-type="application/xhtml+xml" properties="nav"/>');
    manifestItems.add('<item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>');

    // Bundled cover if available
    String? coverManifestId;
    if (book.coverPath != null && File(book.coverPath!).existsSync()) {
      try {
        final coverFile = File(book.coverPath!);
        final coverBytes = await coverFile.readAsBytes();
        final ext = coverFile.path.split('.').last.toLowerCase();
        final mime = ext == 'png'
            ? 'image/png'
            : ext == 'webp'
                ? 'image/webp'
                : 'image/jpeg';
        final coverEntryName = 'OEBPS/images/cover.$ext';
        archive.addFile(ArchiveFile(coverEntryName, coverBytes.length, coverBytes));
        coverManifestId = 'cover-image';
        manifestItems.add('<item id="cover-image" href="images/cover.$ext" media-type="$mime" properties="cover-image"/>');
      } catch (e) {
        logIgnored(e, 'epub_export_service');
      }
    }

    int imageCounter = 0;
    int omittedImagesCounter = 0;
    final Map<String, String> localImageMap = {};

    for (int i = 0; i < downloaded.length; i++) {
      if (i > 0 && i % 20 == 0) {
        // Yield periodically to allow UI isolate event processing
        await Future<void>.delayed(Duration.zero);
      }
      final ch = downloaded[i];
      final chId = 'ch_${i + 1}';
      final fileName = 'chapter_${(i + 1).toString().padLeft(3, '0')}.xhtml';
      final rawHtml = await File(ch.localFilePath!).readAsString();
      final sanitized = ChapterContentSanitizer.sanitize(rawHtml, chapterTitle: ch.title);
      final bundledBody = await _bundleIllustrations(
        bodyHtml: sanitized,
        archive: archive,
        manifestItems: manifestItems,
        localImageMap: localImageMap,
        nextImageIndex: () => ++imageCounter,
        onImageOmitted: () => omittedImagesCounter++,
        chapterFilePath: ch.localFilePath,
      );
      final xhtml = ChapterContentSanitizer.toValidXhtml(
        title: ch.title,
        bodyHtml: '<h1>${_escapeXml(ch.title)}</h1>\n$bundledBody',
        cssPath: 'style.css',
      );
      final xhtmlBytes = utf8.encode(xhtml);
      archive.addFile(ArchiveFile('OEBPS/$fileName', xhtmlBytes.length, xhtmlBytes));

      manifestItems.add('<item id="$chId" href="$fileName" media-type="application/xhtml+xml"/>');
      spineItems.add('<itemref idref="$chId"/>');
      navItems.add('<li><a href="$fileName">${_escapeXml(ch.title)}</a></li>');
      ncxNavPoints.add('''
    <navPoint id="navPoint-${i + 1}" playOrder="${i + 1}">
      <navLabel><text>${_escapeXml(ch.title)}</text></navLabel>
      <content src="$fileName"/>
    </navPoint>''');
    }

    // 2.5 OEBPS/toc.xhtml (EPUB 3 Navigation Document)
    final tocXhtml = '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head>
  <title>${_escapeXml(book.title)} - Table of Contents</title>
  <link rel="stylesheet" type="text/css" href="style.css"/>
</head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>Table of Contents</h1>
    <ol>
      ${navItems.join('\n      ')}
    </ol>
  </nav>
</body>
</html>''';
    final tocBytes = utf8.encode(tocXhtml);
    archive.addFile(ArchiveFile('OEBPS/toc.xhtml', tocBytes.length, tocBytes));

    // 2.6 OEBPS/toc.ncx (EPUB 2 compatibility)
    final ncxXml = '''<?xml version="1.0" encoding="UTF-8"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <head>
    <meta name="dtb:uid" content="${_escapeXml(book.id)}"/>
    <meta name="dtb:depth" content="1"/>
    <meta name="dtb:totalPageCount" content="0"/>
    <meta name="dtb:maxPageNumber" content="0"/>
  </head>
  <docTitle><text>${_escapeXml(book.title)}</text></docTitle>
  <docAuthor><text>${_escapeXml(book.author.isEmpty ? 'Unknown Author' : book.author)}</text></docAuthor>
  <navMap>
${ncxNavPoints.join('\n')}
  </navMap>
</ncx>''';
    final ncxBytes = utf8.encode(ncxXml);
    archive.addFile(ArchiveFile('OEBPS/toc.ncx', ncxBytes.length, ncxBytes));

    // 2.7 OEBPS/content.opf
    final modifiedDate = '${DateTime.now().toUtc().toIso8601String().split('.').first}Z';
    final contentOpf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="pub-id">${_escapeXml(book.id)}</dc:identifier>
    <dc:title>${_escapeXml(book.title)}</dc:title>
    <dc:creator>${_escapeXml(book.author.isEmpty ? 'Unknown Author' : book.author)}</dc:creator>
    <dc:language>en</dc:language>
    <meta property="dcterms:modified">$modifiedDate</meta>
    ${coverManifestId != null ? '<meta name="cover" content="cover-image"/>' : ''}
  </metadata>
  <manifest>
    ${manifestItems.join('\n    ')}
  </manifest>
  <spine toc="ncx">
    ${spineItems.join('\n    ')}
  </spine>
</package>''';
    final opfBytes = utf8.encode(contentOpf);
    archive.addFile(ArchiveFile('OEBPS/content.opf', opfBytes.length, opfBytes));

    // 3. Encode ZIP off UI isolate via compute
    List<int>? zipBytes;
    try {
      zipBytes = await compute(_encodeZipArchive, archive);
    } catch (e) {
      if (Platform.isAndroid) {
        return EpubExportResult(
          success: false,
          errorMessage: 'Background compression failed on Android: $e',
        );
      }
      // Non-Android testing fallback (e.g. headless unit tests without isolates)
      final zipEncoder = ZipEncoder();
      zipBytes = zipEncoder.encode(archive);
    }
    if (zipBytes == null) {
      return const EpubExportResult(
        success: false,
        errorMessage: 'Failed to encode EPUB archive',
      );
    }

    // 4. Output to destination file
    Directory outDir;
    if (outputDirectoryPath != null) {
      outDir = Directory(outputDirectoryPath);
      if (!await outDir.exists()) {
        await outDir.create(recursive: true);
      }
    } else {
      final docDir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${docDir.path}/exports');
      if (!await exportDir.exists()) {
        await exportDir.create(recursive: true);
      }
      outDir = exportDir;
    }

    final safeTitle = book.title
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), '_');
    final targetFile = File('${outDir.path}/$safeTitle.epub');
    final tempFile = File('${outDir.path}/$safeTitle.${DateTime.now().millisecondsSinceEpoch}.part');
    try {
      await tempFile.writeAsBytes(zipBytes, flush: true);
      // Atomic rename within same directory preserves previous targetFile until committed
      await tempFile.rename(targetFile.path);
    } catch (e) {
      if (await tempFile.exists()) {
        try {
          await tempFile.delete();
        } catch (e) {
          logIgnored(e, 'epub_export_service');
        }
      }
      return EpubExportResult(
        success: false,
        errorMessage: 'Failed to write exported EPUB file: $e',
      );
    }

    return EpubExportResult(
      success: true,
      exportedFilePath: targetFile.path,
      chapterCount: downloaded.length,
      omittedImageCount: omittedImagesCounter,
    );
    } catch (e) {
      return EpubExportResult(
        success: false,
        errorMessage: 'EPUB export failed: $e',
      );
    }
  }

  static Future<String> _bundleIllustrations({
    required String bodyHtml,
    required Archive archive,
    required List<String> manifestItems,
    required Map<String, String> localImageMap,
    required int Function() nextImageIndex,
    required VoidCallback onImageOmitted,
    String? chapterFilePath,
  }) async {
    final imgRegex = RegExp(r'''<img\s+([^>]*?)src=["']([^"'>]+)["']([^>]*?)>''', caseSensitive: false);
    if (!imgRegex.hasMatch(bodyHtml)) return bodyHtml;

    final matches = imgRegex.allMatches(bodyHtml);
    var result = bodyHtml;

    for (final match in matches) {
      final fullMatch = match.group(0)!;
      final preAttrs = match.group(1) ?? '';
      final rawSrc = match.group(2) ?? '';
      final postAttrs = match.group(3) ?? '';

      // Check for inline data URIs
      if (rawSrc.startsWith('data:image/')) {
        final commaIdx = rawSrc.indexOf(',');
        if (commaIdx != -1) {
          try {
            final meta = rawSrc.substring(5, commaIdx);
            final mime = meta.split(';').first.trim();
            final isBase64 = meta.contains(';base64');
            final dataStr = rawSrc.substring(commaIdx + 1);
            final bytes = isBase64 ? base64Decode(dataStr) : Uri.decodeComponent(dataStr).codeUnits;
            final idx = nextImageIndex();
            final ext = mime == 'image/png'
                ? 'png'
                : mime == 'image/webp'
                    ? 'webp'
                    : mime == 'image/gif'
                        ? 'gif'
                        : 'jpg';
            final imgName = 'img_${idx.toString().padLeft(4, '0')}.$ext';
            final href = 'images/$imgName';
            archive.addFile(ArchiveFile('OEBPS/$href', bytes.length, bytes));
            manifestItems.add('<item id="img_$idx" href="$href" media-type="$mime"/>');
            result = result.replaceAll(fullMatch, '<img ${preAttrs}src="$href"$postAttrs>');
            continue;
          } catch (_) {
            onImageOmitted();
            result = result.replaceAll(fullMatch, '');
            continue;
          }
        }
      }

      String localPath = rawSrc.trim();
      final uri = Uri.tryParse(localPath);
      if (uri != null && uri.scheme == 'file') {
        localPath = Uri.decodeFull(uri.path);
      } else if (localPath.startsWith('file:')) {
        final pathOnly = localPath.replaceFirst(RegExp(r'^file:/+'), '/');
        localPath = Uri.decodeFull(pathOnly);
      } else {
        localPath = Uri.decodeFull(localPath);
        // If relative path without scheme and not absolute, resolve relative to chapter directory
        if (!p.isAbsolute(localPath) && chapterFilePath != null) {
          final chapterDir = File(chapterFilePath).parent.path;
          localPath = p.normalize(p.join(chapterDir, localPath));
        }
      }

      final file = File(localPath);
      final isManaged = StorageService.instance.isPathInsideManagedStorage(file.path);
      if (isManaged && file.existsSync()) {
        String? relativeHref;
        if (localImageMap.containsKey(file.path)) {
          relativeHref = localImageMap[file.path];
        } else {
          final idx = nextImageIndex();
          final ext = file.path.split('.').last.toLowerCase();
          final validExt = (ext == 'png' || ext == 'webp' || ext == 'gif' || ext == 'jpeg' || ext == 'jpg') ? ext : 'jpg';
          final mime = validExt == 'png'
              ? 'image/png'
              : validExt == 'webp'
                  ? 'image/webp'
                  : validExt == 'gif'
                      ? 'image/gif'
                      : 'image/jpeg';
          final imgName = 'img_${idx.toString().padLeft(4, '0')}.$validExt';
          final href = 'images/$imgName';

          try {
            final bytes = await file.readAsBytes();
            archive.addFile(ArchiveFile('OEBPS/$href', bytes.length, bytes));
            manifestItems.add('<item id="img_$idx" href="$href" media-type="$mime"/>');
            localImageMap[file.path] = href;
            relativeHref = href;
          } catch (_) {
            relativeHref = null;
          }
        }
        if (relativeHref != null) {
          result = result.replaceAll(fullMatch, '<img ${preAttrs}src="$relativeHref"$postAttrs>');
        } else {
          onImageOmitted();
          result = result.replaceAll(fullMatch, '');
        }
      } else {
        onImageOmitted();
        result = result.replaceAll(fullMatch, '');
      }
    }
    return result;
  }

  /// Shares an exported EPUB file via the system share sheet using FileProvider.
  static Future<ShareResult> shareExportedEpub(String filePath, {String? title}) async {
    try {
      final success = await const MethodChannel('com.hon.reader/readium_reader').invokeMethod<bool>(
        'shareFile',
        {
          'filePath': filePath,
          'mimeType': 'application/epub+zip',
          'title': title ?? 'Share EPUB',
        },
      );
      if (success != true) {
        return const ShareResult(
          success: false,
          errorMessage: 'Share sheet was dismissed or failed to launch',
        );
      }
      return const ShareResult(success: true);
    } catch (e) {
      return ShareResult(
        success: false,
        errorMessage: 'Failed to share EPUB: $e',
      );
    }
  }

  /// Saves an exported EPUB file to user-selected location via SAF or system file picker.
  static Future<SaveAsResult> saveExportedEpubAs(String filePath, {String? defaultFileName}) async {
    final sourceFile = File(filePath);
    if (!sourceFile.existsSync()) {
      return const SaveAsResult(status: SaveAsStatus.failed, errorMessage: 'Exported file does not exist.');
    }
    final fileName = defaultFileName ?? sourceFile.uri.pathSegments.last;
    try {
      if (Platform.isAndroid) {
        final saved = await const MethodChannel('com.hon.reader/files').invokeMethod<bool>(
          'exportFileAs',
          {
            'path': sourceFile.path,
            'title': fileName,
            'mimeType': 'application/epub+zip',
          },
        );
        if (saved == true) {
          return const SaveAsResult(status: SaveAsStatus.saved);
        } else {
          return const SaveAsResult(status: SaveAsStatus.cancelled);
        }
      }
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'Save EPUB',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );
      if (destination != null) {
        await sourceFile.copy(destination);
        return const SaveAsResult(status: SaveAsStatus.saved);
      }
      return const SaveAsResult(status: SaveAsStatus.cancelled);
    } on PlatformException catch (pe) {
      return SaveAsResult(
        status: SaveAsStatus.failed,
        errorMessage: pe.message ?? 'Platform error while saving file',
      );
    } catch (e) {
      return SaveAsResult(
        status: SaveAsStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }

  static String _escapeXml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
