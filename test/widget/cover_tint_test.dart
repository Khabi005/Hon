import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/shared/widgets/cover_tint.dart';

Future<String> _solidPng(Directory dir, Color color) async {
  final recorder = ui.PictureRecorder();
  Canvas(
    recorder,
  ).drawRect(const Rect.fromLTWH(0, 0, 40, 60), Paint()..color = color);
  final image = await recorder.endRecording().toImage(40, 60);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('${dir.path}/${color.toARGB32()}.png')
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
  return file.path;
}

void main() {
  testWidgets('cover tint keeps the cover hue and a readable lightness', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('hon_tint_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final tint = await tester.runAsync(() async {
      final path = await _solidPng(dir, const Color(0xFF1E5AA8));
      return CoverTint.of(path);
    });
    expect(tint, isNotNull);
    final hsl = HSLColor.fromColor(tint!);
    expect(
      hsl.hue,
      closeTo(HSLColor.fromColor(const Color(0xFF1E5AA8)).hue, 6),
    );
    expect(hsl.lightness, closeTo(.5, .01));
    expect(hsl.saturation, lessThanOrEqualTo(.71)); // 8-bit rounding
  });

  testWidgets('missing covers give no tint', (tester) async {
    final tint = await tester.runAsync(
      () => CoverTint.of('/nonexistent/cover.png'),
    );
    expect(tint, isNull);
    expect(await CoverTint.of(null), isNull);
  });
}
