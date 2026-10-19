import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;

class ParsedEpubMetadata {
  final String title;
  final String author;
  final String description;
  final Uint8List? coverBytes;
  final List<EpubChapterItem> chapters;

  const ParsedEpubMetadata({
    required this.title,
    required this.author,
    required this.description,
    this.coverBytes,
    required this.chapters,
  });
}

class EpubChapterItem {
  final String id;
  final String title;
  final String contentHref;
  final String htmlContent;
  final int? playOrder;

  const EpubChapterItem({
    required this.id,
    required this.title,
    required this.contentHref,
    required this.htmlContent,
    this.playOrder,
  });
}

class EpubParser {
  static bool _supportedCover(String mediaType) => const {
    'image/jpeg',
    'image/png',
    'image/gif',
    'image/webp',
  }.contains(mediaType.toLowerCase());

  static bool _looksLikeImage(List<int> bytes) {
    if (bytes.length < 12) return false;
    final jpeg = bytes[0] == 0xff && bytes[1] == 0xd8;
    final png =
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47;
    final gif = bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46;
    final webp =
        String.fromCharCodes(bytes.take(4)) == 'RIFF' &&
        String.fromCharCodes(bytes.skip(8).take(4)) == 'WEBP';
    return jpeg || png || gif || webp;
  }

  static String? _archiveResourcePath(String opfDir, String href) {
    try {
      final cleanHref = Uri.decodeComponent(
        href.split('#').first.split('?').first,
      );
      final resolved = p.posix.normalize(p.posix.join(opfDir, cleanHref));
      if (p.posix.isAbsolute(resolved) ||
          resolved == '..' ||
          resolved.startsWith('../')) {
        return null;
      }
      return resolved;
    } catch (_) {
      return null;
    }
  }

  static String _decodeString(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return utf8.decode(bytes, allowMalformed: true);
      } catch (_) {
        return String.fromCharCodes(bytes);
      }
    }
  }

  static Future<ParsedEpubMetadata> parse(
    File file, {
    bool includeContent = true,
  }) {
    final path = file.path;
    // ZIP decompression and XML/spine parsing can take hundreds of milliseconds
    // for large novels. Keep that CPU work off the rendering isolate.
    return Isolate.run(() => _parseFile(path, includeContent));
  }

  static Future<ParsedEpubMetadata> _parseFile(
    String path,
    bool includeContent,
  ) async {
    final file = File(path);
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Locate container.xml
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      throw Exception('Invalid EPUB: META-INF/container.xml missing');
    }

    final containerXml = XmlDocument.parse(
      _decodeString(containerFile.content as List<int>),
    );
    final rootfile = containerXml.findAllElements('rootfile').firstOrNull;
    final opfPath = rootfile?.getAttribute('full-path') ?? 'OEBPS/content.opf';
    final opfDir = p.dirname(opfPath);

    // 2. Read OPF
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('Invalid EPUB: Rootfile not found at $opfPath');
    }

    final opfXml = XmlDocument.parse(
      _decodeString(opfFile.content as List<int>),
    );

    // Extract Title & Author
    final title =
        opfXml.findAllElements('dc:title').firstOrNull?.innerText.trim() ??
        p.basenameWithoutExtension(file.path);
    final author =
        opfXml.findAllElements('dc:creator').firstOrNull?.innerText.trim() ??
        'Unknown Author';
    final description =
        opfXml
            .findAllElements('dc:description')
            .firstOrNull
            ?.innerText
            .trim() ??
        '';

    // Manifest map: id -> {href, media-type, properties}
    final manifest = <String, Map<String, String>>{};
    String? ncxHref;
    String? navHref;

    for (final item in opfXml.findAllElements('item')) {
      final id = item.getAttribute('id') ?? '';
      final href = item.getAttribute('href') ?? '';
      final mediaType = item.getAttribute('media-type') ?? '';
      final properties = item.getAttribute('properties') ?? '';
      manifest[id] = {
        'href': href,
        'media-type': mediaType,
        'properties': properties,
      };

      if (mediaType == 'application/x-dtbncx+xml' ||
          id.toLowerCase() == 'ncx') {
        ncxHref = href;
      }
      if (properties.contains('nav')) {
        navHref = href;
      }
    }

    // EPUB 3 cover-image, EPUB 2 metadata ID, then image-name fallback.
    // Never treat a cover XHTML page as image bytes.
    final coverIds = <String>[];
    for (final item in opfXml.findAllElements('item')) {
      if ((item.getAttribute('properties') ?? '')
          .split(RegExp(r'\s+'))
          .contains('cover-image')) {
        coverIds.add(item.getAttribute('id') ?? '');
      }
    }
    for (final meta in opfXml.findAllElements('meta')) {
      if (meta.getAttribute('name')?.toLowerCase() == 'cover') {
        coverIds.add(meta.getAttribute('content') ?? '');
      }
    }
    for (final entry in manifest.entries) {
      if (entry.key.toLowerCase().contains('cover') ||
          (entry.value['href'] ?? '').toLowerCase().contains('cover')) {
        coverIds.add(entry.key);
      }
    }
    Uint8List? coverBytes;
    for (final id in coverIds.toSet()) {
      final item = manifest[id];
      if (item == null || !_supportedCover(item['media-type'] ?? '')) continue;
      final imagePath = _archiveResourcePath(opfDir, item['href'] ?? '');
      if (imagePath == null) continue;
      final image = archive.findFile(imagePath);
      if (image == null || image.content is! List<int>) continue;
      final imageData = image.content as List<int>;
      if (_looksLikeImage(imageData)) {
        coverBytes = Uint8List.fromList(imageData);
        break;
      }
    }

    // Try parsing Table of Contents from NCX if present
    final tocTitlesByHref = <String, String>{};
    if (ncxHref != null) {
      try {
        final fullNcxPath = opfDir == '.'
            ? ncxHref
            : p.normalize('$opfDir/$ncxHref');
        final ncxFile = archive.findFile(fullNcxPath);
        if (ncxFile != null) {
          final ncxDoc = XmlDocument.parse(
            _decodeString(ncxFile.content as List<int>),
          );
          for (final navPoint in ncxDoc.findAllElements('navPoint')) {
            final label = navPoint
                .findElements('navLabel')
                .firstOrNull
                ?.findElements('text')
                .firstOrNull
                ?.innerText
                .trim();
            final src = navPoint
                .findElements('content')
                .firstOrNull
                ?.getAttribute('src');
            if (label != null && src != null && label.isNotEmpty) {
              final cleanSrc = src.split('#').first;
              tocTitlesByHref[cleanSrc] = label;
              tocTitlesByHref[p.basename(cleanSrc)] = label;
            }
          }
        }
      } catch (_) {}
    }

    // Try parsing Table of Contents from EPUB 3 Nav if present
    if (navHref != null && tocTitlesByHref.isEmpty) {
      try {
        final fullNavPath = opfDir == '.'
            ? navHref
            : p.normalize('$opfDir/$navHref');
        final navFile = archive.findFile(fullNavPath);
        if (navFile != null) {
          final navDoc = XmlDocument.parse(
            _decodeString(navFile.content as List<int>),
          );
          for (final a in navDoc.findAllElements('a')) {
            final href = a.getAttribute('href');
            final label = a.innerText.trim();
            if (href != null && label.isNotEmpty) {
              final cleanSrc = href.split('#').first;
              tocTitlesByHref[cleanSrc] = label;
              tocTitlesByHref[p.basename(cleanSrc)] = label;
            }
          }
        }
      } catch (_) {}
    }

    // Spine
    final spineRefs = opfXml
        .findAllElements('itemref')
        .map((e) => e.getAttribute('idref') ?? '')
        .toList();

    final chapters = <EpubChapterItem>[];
    for (int i = 0; i < spineRefs.length; i++) {
      final idref = spineRefs[i];
      final itemMeta = manifest[idref];
      if (itemMeta == null) continue;

      final href = itemMeta['href']!;
      final fullPath = opfDir == '.' ? href : p.normalize('$opfDir/$href');
      final contentFile = archive.findFile(fullPath);
      if (contentFile == null) continue;

      final html = includeContent
          ? _decodeString(contentFile.content as List<int>)
          : '';

      // Determine chapter title from TOC or from HTML headings
      String chapterTitle =
          tocTitlesByHref[href] ??
          tocTitlesByHref[p.basename(href)] ??
          'Chapter ${i + 1}';
      if (includeContent && chapterTitle == 'Chapter ${i + 1}') {
        try {
          final doc = XmlDocument.parse(html);
          final h1 =
              doc.findAllElements('h1').firstOrNull ??
              doc.findAllElements('h2').firstOrNull ??
              doc.findAllElements('title').firstOrNull;
          if (h1 != null && h1.innerText.trim().isNotEmpty) {
            chapterTitle = h1.innerText.trim();
          }
        } catch (_) {}
      }

      chapters.add(
        EpubChapterItem(
          id: idref,
          title: chapterTitle,
          contentHref: href,
          htmlContent: html,
          playOrder: i + 1,
        ),
      );
    }

    return ParsedEpubMetadata(
      title: title,
      author: author,
      description: description,
      coverBytes: coverBytes,
      chapters: chapters,
    );
  }
}
