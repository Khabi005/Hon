import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/app/theme/reader_theme.dart';
import 'package:hon/features/reader/presentation/reader_document.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'bundled font choices have distinct real text metrics offline',
    () async {
      for (final entry in {
        'Newsreader': 'newsreader',
        'Literata': 'literata',
        'Lora': 'lora',
        'Libre Baskerville': 'librebaskerville',
      }.entries) {
        await (FontLoader(entry.key)..addFont(
              rootBundle.load('assets/fonts/${entry.value}-Regular.ttf'),
            ))
            .load();
      }
      const text =
          'A quiet paragraph: the mysteries of books, letters and reading.';
      final widths = <double>[];
      const block = ReaderBlock(runs: [ReaderRun(text, TextStyle())]);
      for (final family in ReaderFontFamily.values) {
        final prefs = ReaderPreferencesState(fontFamily: family);
        final painter = TextPainter(
          text: TextSpan(text: text, style: block.style(prefs)),
          textDirection: TextDirection.ltr,
        )..layout();
        widths.add(painter.width);
        painter.dispose();
      }
      expect(
        widths.toSet().length,
        ReaderFontFamily.values.length,
        reason: 'Font options must not silently use the same fallback face.',
      );
    },
  );
}
