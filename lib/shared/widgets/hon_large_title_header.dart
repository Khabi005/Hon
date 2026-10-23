import 'dart:ui';
import 'package:flutter/material.dart';
import '../../app/theme/hon_typography.dart';

/// iOS-style large title: a big serif heading that, as the page scrolls,
/// fades into a compact centered title on a frosted bar pinned at the top.
/// Use as the first sliver of a tab's [CustomScrollView].
class SliverHonLargeTitle extends StatelessWidget {
  const SliverHonLargeTitle({
    super.key,
    required this.title,
    this.eyebrow,
    this.actions = const [],
  });

  final String title;

  /// Small uppercase line above the title (e.g. today's date on Home).
  final String? eyebrow;
  final List<Widget> actions;

  static const double _barHeight = 44;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final titlePainter = TextPainter(
      text: TextSpan(text: title, style: HonTypography.largeTitle()),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final titleHeight = titlePainter.height;
    titlePainter.dispose();
    final eyebrowHeight = eyebrow == null ? 0.0 : scaler.scale(10) * 1.3 + 6;
    final expanded = 20 + eyebrowHeight + titleHeight + 8;
    return SliverPersistentHeader(
      pinned: true,
      delegate: _LargeTitleDelegate(
        title: title,
        eyebrow: eyebrow,
        actions: actions,
        maxHeight: expanded < _barHeight ? _barHeight : expanded,
        minHeight: _barHeight,
        background: Theme.of(context).scaffoldBackgroundColor,
        foreground: Theme.of(context).colorScheme.onSurface,
        secondary: Theme.of(context).colorScheme.onSurfaceVariant,
        separator: Theme.of(context).colorScheme.outlineVariant,
      ),
    );
  }
}

class _LargeTitleDelegate extends SliverPersistentHeaderDelegate {
  _LargeTitleDelegate({
    required this.title,
    required this.eyebrow,
    required this.actions,
    required this.maxHeight,
    required this.minHeight,
    required this.background,
    required this.foreground,
    required this.secondary,
    required this.separator,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final double maxHeight;
  final double minHeight;
  final Color background;
  final Color foreground;
  final Color secondary;
  final Color separator;

  @override
  double get maxExtent => maxHeight;

  @override
  double get minExtent => minHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxHeight - minHeight;
    final t = range <= 0 ? 1.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final largeOpacity = (1 - t * 1.25).clamp(0.0, 1.0);
    final compactOpacity = ((t - .7) / .3).clamp(0.0, 1.0);
    final barOpacity = ((t - .85) / .15).clamp(0.0, 1.0);

    final bar = Stack(
      fit: StackFit.expand,
      children: [
        if (largeOpacity > 0)
          Positioned(
            left: 24,
            right: 16 + actions.length * 48.0,
            bottom: 8,
            child: Opacity(
              opacity: largeOpacity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (eyebrow != null) ...[
                    Text(
                      eyebrow!.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.2,
                        fontWeight: FontWeight.w600,
                        color: secondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: HonTypography.largeTitle(color: foreground),
                  ),
                ],
              ),
            ),
          ),
        if (compactOpacity > 0)
          Positioned(
            left: 72,
            right: 72,
            bottom: 0,
            height: minHeight,
            child: Opacity(
              opacity: compactOpacity,
              child: Center(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.3,
                    color: foreground,
                  ),
                ),
              ),
            ),
          ),
        if (actions.isNotEmpty)
          Positioned(
            right: 8,
            // Centred on the large title when open, on the bar when closed.
            bottom: lerpDouble(8, 0, t),
            height: minHeight,
            child: Row(mainAxisSize: MainAxisSize.min, children: actions),
          ),
      ],
    );

    if (barOpacity == 0) return ColoredBox(color: background, child: bar);
    // Frost only once collapsed, so the blur costs nothing at rest.
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 20 * barOpacity,
          sigmaY: 20 * barOpacity,
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Color.lerp(
              background,
              background.withValues(alpha: .78),
              barOpacity,
            ),
            border: Border(
              bottom: BorderSide(
                color: separator.withValues(alpha: barOpacity),
                width: .5,
              ),
            ),
          ),
          child: bar,
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _LargeTitleDelegate old) =>
      old.title != title ||
      old.eyebrow != eyebrow ||
      old.actions != actions ||
      old.maxHeight != maxHeight ||
      old.background != background ||
      old.foreground != foreground;
}
