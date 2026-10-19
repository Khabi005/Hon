import 'dart:ui';
import 'package:flutter/material.dart';

@immutable
class GlassStyle extends ThemeExtension<GlassStyle> {
  const GlassStyle({this.rich = false});
  final bool rich;
  static bool richOf(BuildContext context) =>
      Theme.of(context).extension<GlassStyle>()?.rich ?? false;
  @override
  GlassStyle copyWith({bool? rich}) => GlassStyle(rich: rich ?? this.rich);
  @override
  GlassStyle lerp(covariant GlassStyle? other, double t) =>
      t < .5 ? this : other ?? this;
}

/// Bounded, static frost. The standard style uses it only for navigation.
/// High contrast removes transparency; reduced motion adds no effect animation.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.navigation = false,
    this.radius = 22,
    this.padding = EdgeInsets.zero,
    this.width,
    this.color,
  });
  final Widget child;
  final bool navigation;
  final double radius;
  final EdgeInsetsGeometry padding;
  final double? width;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final rich = GlassStyle.richOf(context);
    final glass = (navigation || rich) && !MediaQuery.highContrastOf(context);
    final base = color ?? colors.surface;
    final border = BorderRadius.circular(radius);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: border,
        color: glass ? null : base,
        gradient: glass
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  base.withValues(alpha: rich ? .72 : .94),
                  base.withValues(alpha: rich ? .48 : .80),
                ],
              )
            : null,
        border: Border.all(
          color: glass
              ? Colors.white.withValues(alpha: dark ? .18 : .75)
              : colors.outlineVariant,
          width: .8,
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(padding: padding, child: child),
      ),
    );
    return Container(
      width: width,
      decoration: BoxDecoration(
        borderRadius: border,
        boxShadow: glass
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: dark ? .18 : .06),
                  blurRadius: navigation ? 18 : 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: border,
        child: glass
            ? BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: navigation ? 18 : 10,
                  sigmaY: navigation ? 18 : 10,
                ),
                child: content,
              )
            : content,
      ),
    );
  }
}

/// Solid background beneath the translucent surfaces; no gradient wash.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child, required this.dark});
  final Widget child;
  final bool dark;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: dark ? const Color(0xFF000000) : const Color(0xFFF2F2F7),
    child: child,
  );
}
