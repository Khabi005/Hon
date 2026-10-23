import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../../app/theme/reader_theme.dart';
import '../../../core/files/storage_service.dart';
import '../../../core/utils/log_ignored.dart';

/// A location in the original chapter, independent of page size and typography.
class ReaderTextAnchor {
  final int block;
  final int offset;
  const ReaderTextAnchor(this.block, [this.offset = 0]);
}

class ReaderRun {
  final String text;
  final TextStyle style;
  final String? link;
  const ReaderRun(this.text, this.style, [this.link]);
}

class HighlightSpan {
  final int start;
  final int end;
  final Color color;
  final String? note;
  const HighlightSpan({
    required this.start,
    required this.end,
    required this.color,
    this.note,
  });
}

class ReaderBlock {
  final List<ReaderRun> runs;
  final String? image;
  final String alt;
  final bool divider;
  final bool heading;
  final bool preformatted;
  const ReaderBlock({
    this.runs = const [],
    this.image,
    this.alt = '',
    this.divider = false,
    this.heading = false,
    this.preformatted = false,
  });

  String get text => runs.map((run) => run.text).join();

  TextStyle style(ReaderPreferencesState prefs) => TextStyle(
    color: prefs.themeConfig.textColor,
    fontSize: prefs.fontSize * (heading ? 1.4 : 1.0),
    fontFamily: preformatted ? 'monospace' : prefs.fontFamily.fontFamily,
    fontFamilyFallback: const ['serif'],
    fontWeight: heading ? FontWeight.w700 : FontWeight.normal,
    letterSpacing: heading ? 0.3 : 0.0,
    height: heading ? 1.25 : prefs.lineHeight,
  );

  TextSpan span({
    int start = 0,
    int? end,
    TapGestureRecognizer Function(String)? link,
    List<HighlightSpan>? highlights,
  }) {
    var cursor = 0;
    final children = <InlineSpan>[];
    for (final run in runs) {
      final next = cursor + run.text.length;
      final a = math.max(start, cursor);
      final b = math.min(end ?? next, next);
      if (b > a) {
        final relA = a - cursor;
        final relB = b - cursor;
        final activeHls = (highlights ?? const [])
            .where((h) => h.end > a && h.start < b)
            .toList();

        if (activeHls.isEmpty) {
          children.add(
            TextSpan(
              text: run.text.substring(relA, relB),
              style: run.style,
              recognizer: run.link == null ? null : link?.call(run.link!),
            ),
          );
        } else {
          final boundaries = <int>{0, b - a};
          for (final h in activeHls) {
            boundaries.add((h.start - a).clamp(0, b - a));
            boundaries.add((h.end - a).clamp(0, b - a));
          }
          final sorted = boundaries.toList()..sort();
          for (int i = 0; i < sorted.length - 1; i++) {
            final segStart = sorted[i];
            final segEnd = sorted[i + 1];
            if (segEnd <= segStart) continue;
            final absStart = a + segStart;
            final absEnd = a + segEnd;
            final matchingHl = activeHls.firstWhere(
              (h) => h.start <= absStart && h.end >= absEnd,
              orElse: () => const HighlightSpan(start: -1, end: -1, color: Colors.transparent),
            );
            final isHl = matchingHl.start != -1;
            final hlStyle = isHl
                ? run.style.copyWith(backgroundColor: matchingHl.color)
                : run.style;
            children.add(
              TextSpan(
                text: run.text.substring(relA + segStart, relA + segEnd),
                style: hlStyle,
                recognizer: run.link == null ? null : link?.call(run.link!),
              ),
            );
          }
        }
      }
      cursor = next;
    }
    return TextSpan(children: children);
  }
}

class ReaderFragment {
  final int block;
  final int start;
  final int end;
  final double height;
  final double after;
  const ReaderFragment(
    this.block,
    this.start,
    this.end,
    this.height,
    this.after,
  );
}

class ReaderDocument {
  final List<ReaderBlock> blocks;
  const ReaderDocument(this.blocks);

  static Future<ReaderDocument> parseAsync(String source, {String? title, String? baseUrl}) =>
      Isolate.run(() => ReaderDocument.parse(source, title: title, baseUrl: baseUrl));

  factory ReaderDocument.parse(
    String source, {
    String? title,
    String? baseUrl,
  }) {
    final body = html.parse(source).body;
    final blocks = <ReaderBlock>[];
    String resolve(String value) {
      if (baseUrl == null) return value;
      return Uri.tryParse(baseUrl)?.resolve(value).toString() ?? value;
    }

    const blockTags = {
      'p',
      'div',
      'section',
      'article',
      'main',
      'header',
      'footer',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'blockquote',
      'ul',
      'ol',
      'li',
      'pre',
      'figure',
      'figcaption',
      'table',
      'tr',
      'td',
    };
    void visit(
      dom.Node node, {
      TextStyle inherited = const TextStyle(),
      bool pre = false,
      bool heading = false,
    }) {
      final runs = <ReaderRun>[];
      void flush() {
        if (runs.any((run) => run.text.trim().isNotEmpty)) {
          blocks.add(
            ReaderBlock(
              runs: List.of(runs),
              heading: heading,
              preformatted: pre,
            ),
          );
        }
        runs.clear();
      }

      void inline(dom.Node child, TextStyle style, String? link) {
        if (child is dom.Text) {
          final text = pre
              ? child.data
              : child.data.replaceAll(RegExp(r'\s+'), ' ');
          if (text.isNotEmpty) runs.add(ReaderRun(text, style, link));
          return;
        }
        if (child is! dom.Element) return;
        final tag = child.localName;
        if (const {'script', 'style', 'noscript', 'iframe'}.contains(tag)) {
          return;
        }
        if (tag == 'img' || tag == 'image') {
          flush();
          final src =
              child.attributes['src'] ??
              child.attributes['href'] ??
              child.attributes['xlink:href'];
          if (src != null && src.isNotEmpty) {
            blocks.add(
              ReaderBlock(
                image: resolve(src),
                alt: child.attributes['alt'] ?? 'Illustration',
              ),
            );
          }
          return;
        }
        if (tag == 'hr') {
          flush();
          blocks.add(const ReaderBlock(divider: true));
          return;
        }
        if (tag == 'br') {
          runs.add(ReaderRun('\n', style));
          return;
        }
        final nextStyle = style.merge(
          TextStyle(
            fontWeight: const {'b', 'strong'}.contains(tag)
                ? FontWeight.bold
                : null,
            fontStyle: const {'i', 'em'}.contains(tag)
                ? FontStyle.italic
                : null,
            decoration: tag == 'u' || tag == 'a'
                ? TextDecoration.underline
                : tag == 's' || tag == 'del'
                ? TextDecoration.lineThrough
                : null,
            fontFamily: tag == 'code' ? 'monospace' : null,
          ),
        );
        if (blockTags.contains(tag)) {
          flush();
          visit(
            child,
            inherited: nextStyle,
            pre: pre || tag == 'pre',
            heading: RegExp(r'^h[1-6]$').hasMatch(tag ?? ''),
          );
          return;
        }
        final target = tag == 'a' && child.attributes['href'] != null
            ? resolve(child.attributes['href']!)
            : link;
        for (final nested in child.nodes) {
          inline(nested, nextStyle, target);
        }
      }

      if (node is dom.Element && node.localName == 'li') {
        runs.add(ReaderRun('• ', inherited));
      }
      for (final child in node.nodes) {
        inline(child, inherited, null);
      }
      flush();
    }

    if (body != null) visit(body);
    if (title != null && title.trim().isNotEmpty) {
      final cleanTitle = title.trim();
      String norm(String s) =>
          s.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '').toLowerCase();
      final normTitle = norm(cleanTitle);
      bool hasExistingHeading = false;
      if (blocks.isNotEmpty) {
        final firstBlockText = norm(blocks.first.text);
        if (firstBlockText.isNotEmpty) {
          if (firstBlockText == normTitle ||
              firstBlockText.contains(normTitle) ||
              (normTitle.length > 5 && normTitle.contains(firstBlockText))) {
            hasExistingHeading = true;
          }
        }
      }
      if (!hasExistingHeading) {
        blocks.insert(
          0,
          ReaderBlock(
            heading: true,
            runs: [ReaderRun(cleanTitle, const TextStyle())],
          ),
        );
      }
    }
    return ReaderDocument(blocks);
  }

  /// Split at measured line boundaries. Each fragment retains its inline styles
  /// and source offset, so reflow can restore the same passage.
  List<List<ReaderFragment>> paginate(
    ReaderPreferencesState prefs,
    double width,
    double height,
    TextScaler scaler,
    TextDirection direction,
  ) {
    final pages = <List<ReaderFragment>>[];
    var page = <ReaderFragment>[];
    var remaining = height;
    void nextPage() {
      if (page.isNotEmpty) pages.add(page);
      page = [];
      remaining = height;
    }

    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      final gap = prefs.paragraphSpacing;
      if (block.image != null || block.divider) {
        final h = block.divider ? 24.0 : math.min(height * 0.65, width * 0.75);
        if (remaining < h && page.isNotEmpty) nextPage();
        page.add(ReaderFragment(index, 0, 0, h, gap));
        remaining -= h + gap;
        continue;
      }
      final text = block.text;
      var start = 0;
      while (start < text.length) {
        final painter = TextPainter(
          text: TextSpan(
            style: block.style(prefs),
            children: [block.span(start: start)],
          ),
          textDirection: direction,
          textScaler: scaler,
          textAlign: block.heading
              ? TextAlign.center
              : prefs.isJustified && !block.preformatted
              ? TextAlign.justify
              : TextAlign.start,
        )..layout(maxWidth: width);
        final lines = painter.computeLineMetrics();
        final fits = lines
            .takeWhile(
              (line) => line.baseline + line.descent <= remaining + 0.01,
            )
            .toList();
        if (fits.isEmpty && page.isNotEmpty) {
          painter.dispose();
          nextPage();
          continue;
        }
        final last = fits.isEmpty ? lines.first : fits.last;
        var count = painter
            .getLineBoundary(
              painter.getPositionForOffset(Offset(0, last.baseline)),
            )
            .end;
        if (fits.length == lines.length) count = text.length - start;
        // Include the newline consumed at a page boundary.
        if (start + count < text.length && text[start + count] == '\n') count++;
        if (count <= 0) count = text.length - start;
        final used = last.baseline + last.descent;
        final end = math.min(text.length, start + count);
        page.add(
          ReaderFragment(index, start, end, used, end == text.length ? gap : 0),
        );
        remaining -= used + (end == text.length ? gap : 0);
        painter.dispose();
        start = end;
        if (start < text.length || remaining <= 0) nextPage();
      }
    }
    if (page.isNotEmpty) pages.add(page);
    return pages.isEmpty ? [[]] : pages;
  }
}

Widget readerImage(String source, String alt, {required double height}) =>
    _ReaderImage(source: source, alt: alt, height: height);

class _ReaderImage extends StatefulWidget {
  const _ReaderImage({required this.source, required this.alt, required this.height});
  final String source, alt;
  final double height;
  @override
  State<_ReaderImage> createState() => _ReaderImageState();
}

class _ReaderImageState extends State<_ReaderImage> {
  Future<Uint8List>? _data;
  void _decode() {
    final source = widget.source;
    if (source.startsWith('data:')) {
      _data = Isolate.run(() {
        final comma = source.indexOf(',');
        return base64Decode(source.substring(comma + 1));
      }).then((bytes) {
        _extractToImagesDir(source, bytes);
        return bytes;
      });
    } else {
      _data = null;
    }
  }

  void _extractToImagesDir(String source, Uint8List bytes) {
    try {
      final storage = StorageService.instance;
      final dir = storage.imagesDir;
      if (!dir.existsSync()) return;
      final hash = sha256.convert(bytes).toString();
      final ext = bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xd8
          ? 'jpg'
          : bytes.length >= 8 &&
                  bytes[0] == 0x89 &&
                  bytes[1] == 0x50 &&
                  bytes[2] == 0x4e &&
                  bytes[3] == 0x47
              ? 'png'
              : bytes.length >= 4 &&
                      bytes[0] == 0x52 &&
                      bytes[1] == 0x49 &&
                      bytes[2] == 0x46 &&
                      bytes[3] == 0x46
                  ? 'webp'
                  : bytes.length >= 3 &&
                          bytes[0] == 0x47 &&
                          bytes[1] == 0x49 &&
                          bytes[2] == 0x46
                      ? 'gif'
                      : source.contains('image/jpeg')
                          ? 'jpg'
                          : source.contains('image/webp')
                              ? 'webp'
                              : source.contains('image/gif')
                                  ? 'gif'
                                  : 'png';
      final file = File(p.join(dir.path, '$hash.$ext'));
      if (!file.existsSync()) {
        final tmp = File(p.join(dir.path, 'tmp_${DateTime.now().microsecondsSinceEpoch}'));
        tmp.writeAsBytesSync(bytes, flush: true);
        tmp.renameSync(file.path);
      }
    } catch (e) {
      logIgnored(e, 'reader_document');
    }
  }
  @override
  void initState() { super.initState(); _decode(); }
  @override
  void didUpdateWidget(covariant _ReaderImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source) _decode();
  }
  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    final uri = Uri.tryParse(source);
    final width = (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 2048);
    Widget failure(BuildContext _, Object __, StackTrace? ___) => Center(child: Text(widget.alt));
    if (_data != null) {
      return FutureBuilder<Uint8List>(future: _data, builder: (context, snapshot) {
        if (snapshot.hasError) return SizedBox(height: widget.height, child: Text(widget.alt));
        if (!snapshot.hasData) return SizedBox(height: widget.height);
        return Image.memory(snapshot.data!, height: widget.height, cacheWidth: width, fit: BoxFit.contain, errorBuilder: failure);
      });
    }
    if (uri?.scheme == 'http' || uri?.scheme == 'https') {
      return Image.network(source, height: widget.height, cacheWidth: width, fit: BoxFit.contain, errorBuilder: failure);
    }
    return Image.file(File(uri?.scheme == 'file' ? uri!.toFilePath() : source),
        height: widget.height, cacheWidth: width, fit: BoxFit.contain, errorBuilder: failure);
  }
}
