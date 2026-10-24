import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// A soft colour taken from a book cover, like the tinted cards in Apple
/// Books. The cover is decoded at 12 px wide, so this is cheap; results are
/// cached per path for the session.
class CoverTint {
  CoverTint._();

  static final Map<String, Color?> _cache = {};
  static final Map<String, Future<Color?>> _pending = {};

  static Color? cached(String? path) => path == null ? null : _cache[path];

  static Future<Color?> of(String? path) {
    if (path == null || path.isEmpty) return Future.value(null);
    if (_cache.containsKey(path)) return Future.value(_cache[path]);
    return _pending.putIfAbsent(path, () async {
      Color? tint;
      try {
        tint = await _compute(path);
      } catch (_) {
        tint = null;
      }
      if (_cache.length > 64) _cache.remove(_cache.keys.first);
      _cache[path] = tint;
      _pending.remove(path);
      return tint;
    });
  }

  static ImageProvider? _provider(String path) {
    if (path.startsWith('assets/')) return AssetImage(path);
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return NetworkImage(path);
    }
    final file = File(path);
    return file.existsSync() ? FileImage(file) : null;
  }

  static Future<Color?> _compute(String path) async {
    final base = _provider(path);
    if (base == null) return null;
    final provider = ResizeImage(base, width: 12, allowUpscaling: false);
    final completer = Completer<ui.Image>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (!completer.isCompleted) completer.complete(info.image.clone());
        stream.removeListener(listener);
      },
      onError: (error, _) {
        if (!completer.isCompleted) completer.completeError(error);
        stream.removeListener(listener);
      },
    );
    stream.addListener(listener);
    final image = await completer.future.timeout(const Duration(seconds: 5));
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    if (data == null) return null;

    // Weight each pixel by its saturation so a colourful cover gives its
    // colour rather than the grey average of its title text and background.
    double r = 0, g = 0, b = 0, total = 0;
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final a = data.getUint8(i + 3) / 255;
      if (a < .5) continue;
      final pr = data.getUint8(i) / 255;
      final pg = data.getUint8(i + 1) / 255;
      final pb = data.getUint8(i + 2) / 255;
      final hsl = HSLColor.fromColor(
        Color.from(alpha: 1, red: pr, green: pg, blue: pb),
      );
      final w = .15 + hsl.saturation * (1 - (hsl.lightness - .5).abs() * 2);
      r += pr * w;
      g += pg * w;
      b += pb * w;
      total += w;
    }
    if (total == 0) return null;
    final avg = HSLColor.fromColor(
      Color.from(alpha: 1, red: r / total, green: g / total, blue: b / total),
    );
    // Keep the hue, tame the rest so text on top stays readable.
    return avg
        .withSaturation((avg.saturation * 1.2).clamp(0.0, .7))
        .withLightness(.5)
        .toColor();
  }
}

/// Gives [builder] the cover's tint once known (null until then, or when the
/// cover has no usable colour) and a 0–1 strength that fades it in.
class CoverTintBuilder extends StatefulWidget {
  const CoverTintBuilder({
    super.key,
    required this.coverPath,
    required this.builder,
  });

  final String? coverPath;
  final Widget Function(BuildContext context, Color? tint, double strength)
  builder;

  @override
  State<CoverTintBuilder> createState() => _CoverTintBuilderState();
}

class _CoverTintBuilderState extends State<CoverTintBuilder> {
  Color? _tint;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CoverTintBuilder old) {
    super.didUpdateWidget(old);
    if (old.coverPath != widget.coverPath) _load();
  }

  void _load() {
    final path = widget.coverPath;
    _tint = CoverTint.cached(path);
    if (_tint != null) return;
    CoverTint.of(path).then((tint) {
      if (mounted && widget.coverPath == path && tint != _tint) {
        setState(() => _tint = tint);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tint = _tint;
    // Animate the strength rather than the colour, so the first frame with a
    // tint fades in from the plain card.
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: tint == null ? 0 : 1),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 400),
      builder: (context, t, _) =>
          widget.builder(context, tint == null || t == 0 ? null : tint, t),
    );
  }
}
