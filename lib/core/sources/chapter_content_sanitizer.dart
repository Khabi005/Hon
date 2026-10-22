import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Sanitizes raw chapter HTML from web sources to remove ad banners,
/// promotional blocks, tracking scripts, and formatting glitches
/// while strictly preserving narrative prose and illustrations.
class ChapterContentSanitizer {
  static final RegExp _adTokenRegex = RegExp(
    r'(?:^|[\s\-_])(?:advertisement|ad-container|adsbygoogle|banner-ad|sponsor|patreon|discord-link|watermark|share-button|social-share|chapter-nav|comment-box|popup|floating-ad|ad_wrapper)(?:$|[\s\-_])',
    caseSensitive: false,
  );

  static final List<RegExp> _promoTextPatterns = [
    RegExp(r'visit\s+.*\s+to\s+read\s+(?:up\s+to\s+.*\s+chapters\s+)?ahead', caseSensitive: false),
    RegExp(r'read\s+(?:more|latest)\s+chapters?\s+(?:at|on)\s+.*', caseSensitive: false),
    RegExp(r'support\s+.*\s+on\s+patreon', caseSensitive: false),
    RegExp(r'join\s+our\s+discord(?:\s*:\s*.*|\s+server)?', caseSensitive: false),
    RegExp(r'this\s+chapter\s+is\s+updated\s+by\s+.*', caseSensitive: false),
    RegExp(r'please\s+bookmark\s+this\s+site\s+to\s+read\s+.*', caseSensitive: false),
  ];

  static const Set<String> _disallowedTags = {
    'script',
    'style',
    'iframe',
    'form',
    'input',
    'button',
    'noscript',
    'object',
    'embed',
    'applet',
    'link',
    'meta',
    'svg',
  };

  /// Sanitizes raw HTML body content and returns clean HTML.
  static String sanitize(String rawContent, {String? chapterTitle}) {
    if (rawContent.trim().isEmpty) return '';

    // If pure plaintext without tags, wrap into clean paragraphs
    if (!rawContent.contains('<') && !rawContent.contains('>')) {
      return _wrapPlainText(rawContent);
    }

    final fragment = html_parser.parseFragment(rawContent);

    // 1. Remove dangerous/unwanted tags
    for (final tag in _disallowedTags) {
      final elements = fragment.querySelectorAll(tag);
      for (final el in elements) {
        el.remove();
      }
    }

    // 2. Remove elements with ad/promo class or id using boundary-anchored tokens
    final allElements = fragment.querySelectorAll('*');
    for (final el in allElements) {
      final className = el.className;
      final id = el.id;
      final hasAdClass = className.isNotEmpty && _adTokenRegex.hasMatch(className);
      final hasAdId = id.isNotEmpty && _adTokenRegex.hasMatch(id);
      if (hasAdClass || hasAdId) {
        el.remove();
      }
    }

    // 3. Remove duplicate chapter heading if the top element mirrors chapterTitle
    if (chapterTitle != null && chapterTitle.trim().isNotEmpty) {
      final normalizedTarget = _normalizeTitle(chapterTitle);
      final firstHeading = fragment.querySelector('h1, h2, h3, h4, h5, h6, p');
      if (firstHeading != null) {
        final headingText = _normalizeTitle(firstHeading.text);
        if (headingText.isNotEmpty && headingText == normalizedTarget) {
          firstHeading.remove();
        }
      }
    }

    // 4. Remove known promo paragraphs or text blocks (ignoring parent wrappers)
    final paragraphs = fragment.querySelectorAll('p, div, span, blockquote');
    for (final p in paragraphs) {
      if (p.querySelector('p, div, blockquote') != null) continue;
      final text = p.text.trim();
      if (text.isEmpty) continue;
      for (final pattern in _promoTextPatterns) {
        if (pattern.hasMatch(text) && text.length < 250) {
          p.remove();
          break;
        }
      }
    }

    // 5. Clean attributes from remaining elements (allow only safe href on <a>, src/alt on <img>)
    for (final el in fragment.querySelectorAll('*')) {
      final tag = el.localName?.toLowerCase();
      final allowedAttrs = <String>{};
      if (tag == 'a') {
        final href = el.attributes['href'];
        if (href != null) {
          final uri = Uri.tryParse(href.trim());
          if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto')) {
            allowedAttrs.add('href');
          }
        }
      } else if (tag == 'img') {
        allowedAttrs.addAll(['src', 'alt', 'title']);
      }
      final toRemove = el.attributes.keys
          .where((attr) => !allowedAttrs.contains(attr.toString()))
          .toList();
      for (final attr in toRemove) {
        el.attributes.remove(attr);
      }
    }

    return fragment.outerHtml;
  }

  static String _normalizeTitle(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Wraps sanitized body HTML into a strictly valid XHTML document for EPUB 3.
  static String toValidXhtml({
    required String title,
    required String bodyHtml,
    String lang = 'en',
    String? cssPath,
  }) {
    final cleanBody = _ensureXmlCompliant(bodyHtml);
    final linkTag = cssPath != null
        ? '<link rel="stylesheet" type="text/css" href="$cssPath" />\n'
        : '';

    return '''<?xml version="1.0" encoding="utf-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="$lang">
<head>
  <title>${_escapeXml(title)}</title>
  $linkTag
</head>
<body>
$cleanBody
</body>
</html>''';
  }

  static String _wrapPlainText(String text) {
    final lines = text.split(RegExp(r'\r?\n'));
    final buffer = StringBuffer();
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty) {
        buffer.writeln('<p>${_escapeXml(trimmed)}</p>');
      }
    }
    return buffer.toString();
  }

  static String _ensureXmlCompliant(String html) {
    try {
      final fragment = html_parser.parseFragment(html);
      final buffer = StringBuffer();
      for (final node in fragment.nodes) {
        _serializeXmlNode(node, buffer);
      }
      return buffer.toString();
    } catch (_) {
      // If parsing fails on corrupt markup, safely wrap text as clean XML paragraphs
      return _wrapPlainText(html);
    }
  }

  static const _voidTags = {
    'area', 'base', 'br', 'col', 'embed', 'hr', 'img', 'input',
    'link', 'meta', 'param', 'source', 'track', 'wbr',
  };

  static void _serializeXmlNode(dom.Node node, StringBuffer buffer) {
    if (node is dom.Element) {
      final tag = node.localName?.toLowerCase() ?? 'div';
      buffer.write('<$tag');
      node.attributes.forEach((key, value) {
        final attrName = key.toString();
        buffer.write(' $attrName="${_escapeXml(value)}"');
      });
      if (_voidTags.contains(tag) && node.nodes.isEmpty) {
        buffer.write(' />');
      } else {
        buffer.write('>');
        for (final child in node.nodes) {
          _serializeXmlNode(child, buffer);
        }
        buffer.write('</$tag>');
      }
    } else if (node is dom.Text) {
      buffer.write(_escapeXml(node.text));
    } else if (node is dom.Comment) {
      // In XML 1.0, comments must never contain '--' or end with '-'
      final safeComment = (node.data ?? '')
          .replaceAll('--', ' - - ')
          .replaceAll(RegExp(r'-+$'), '');
      if (safeComment.isNotEmpty) {
        buffer.write('<!--$safeComment-->');
      }
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
