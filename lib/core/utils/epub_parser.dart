import 'dart:convert';
import 'dart:io';
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

  static Future<ParsedEpubMetadata> parse(File file) async {
    final bytes = await file.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // 1. Locate container.xml
    final containerFile = archive.findFile('META-INF/container.xml');
    if (containerFile == null) {
      throw Exception('Invalid EPUB: META-INF/container.xml missing');
    }

    final containerXml = XmlDocument.parse(_decodeString(containerFile.content as List<int>));
    final rootfile = containerXml.findAllElements('rootfile').firstOrNull;
    final opfPath = rootfile?.getAttribute('full-path') ?? 'OEBPS/content.opf';
    final opfDir = p.dirname(opfPath);

    // 2. Read OPF
    final opfFile = archive.findFile(opfPath);
    if (opfFile == null) {
      throw Exception('Invalid EPUB: Rootfile not found at $opfPath');
    }

    final opfXml = XmlDocument.parse(_decodeString(opfFile.content as List<int>));

    // Extract Title & Author
    final title = opfXml.findAllElements('dc:title').firstOrNull?.innerText.trim() ??
        p.basenameWithoutExtension(file.path);
    final author = opfXml.findAllElements('dc:creator').firstOrNull?.innerText.trim() ??
        'Unknown Author';
    final description = opfXml.findAllElements('dc:description').firstOrNull?.innerText.trim() ?? '';

    // Manifest map: id -> {href, media-type, properties}
    final manifest = <String, Map<String, String>>{};
    String? coverHref;
    String? ncxHref;
    String? navHref;

    for (final item in opfXml.findAllElements('item')) {
      final id = item.getAttribute('id') ?? '';
      final href = item.getAttribute('href') ?? '';
      final mediaType = item.getAttribute('media-type') ?? '';
      final properties = item.getAttribute('properties') ?? '';
      manifest[id] = {'href': href, 'media-type': mediaType, 'properties': properties};

      if (properties.contains('cover-image') || id.toLowerCase().contains('cover')) {
        coverHref = href;
      }
      if (mediaType == 'application/x-dtbncx+xml' || id.toLowerCase() == 'ncx') {
        ncxHref = href;
      }
      if (properties.contains('nav')) {
        navHref = href;
      }
    }

    // Extract Cover image
    Uint8List? coverBytes;
    if (coverHref != null) {
      final fullCoverPath = opfDir == '.' ? coverHref : p.normalize('$opfDir/$coverHref');
      final cFile = archive.findFile(fullCoverPath);
      if (cFile != null) {
        coverBytes = Uint8List.fromList(cFile.content as List<int>);
      }
    }

    // Try parsing Table of Contents from NCX if present
    final tocTitlesByHref = <String, String>{};
    if (ncxHref != null) {
      try {
        final fullNcxPath = opfDir == '.' ? ncxHref : p.normalize('$opfDir/$ncxHref');
        final ncxFile = archive.findFile(fullNcxPath);
        if (ncxFile != null) {
          final ncxDoc = XmlDocument.parse(_decodeString(ncxFile.content as List<int>));
          for (final navPoint in ncxDoc.findAllElements('navPoint')) {
            final label = navPoint.findElements('navLabel').firstOrNull?.findElements('text').firstOrNull?.innerText.trim();
            final src = navPoint.findElements('content').firstOrNull?.getAttribute('src');
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
        final fullNavPath = opfDir == '.' ? navHref : p.normalize('$opfDir/$navHref');
        final navFile = archive.findFile(fullNavPath);
        if (navFile != null) {
          final navDoc = XmlDocument.parse(_decodeString(navFile.content as List<int>));
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
    final spineRefs = opfXml.findAllElements('itemref').map((e) => e.getAttribute('idref') ?? '').toList();

    final chapters = <EpubChapterItem>[];
    for (int i = 0; i < spineRefs.length; i++) {
      final idref = spineRefs[i];
      final itemMeta = manifest[idref];
      if (itemMeta == null) continue;

      final href = itemMeta['href']!;
      final fullPath = opfDir == '.' ? href : p.normalize('$opfDir/$href');
      final contentFile = archive.findFile(fullPath);
      if (contentFile == null) continue;

      final html = _decodeString(contentFile.content as List<int>);

      // Determine chapter title from TOC or from HTML headings
      String chapterTitle = tocTitlesByHref[href] ?? tocTitlesByHref[p.basename(href)] ?? 'Chapter ${i + 1}';
      if (chapterTitle == 'Chapter ${i + 1}') {
        try {
          final doc = XmlDocument.parse(html);
          final h1 = doc.findAllElements('h1').firstOrNull ??
              doc.findAllElements('h2').firstOrNull ??
              doc.findAllElements('title').firstOrNull;
          if (h1 != null && h1.innerText.trim().isNotEmpty) {
            chapterTitle = h1.innerText.trim();
          }
        } catch (_) {}
      }

      chapters.add(EpubChapterItem(
        id: idref,
        title: chapterTitle,
        contentHref: href,
        htmlContent: html,
        playOrder: i + 1,
      ));
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
