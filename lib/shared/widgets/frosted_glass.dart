import 'dart:ui';
import 'package:flutter/material.dart';

class FrostedGlass extends StatelessWidget {
  final Widget child;
  final double blur;
  final Color? color;
  final BorderRadius? borderRadius;
  final Border? border;

  const FrostedGlass({
    super.key,
    required this.child,
    this.blur = 20.0,
    this.color,
    this.borderRadius,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultBg = isDark
        ? const Color(0xCC1C1C1E)
        : const Color(0xCCFFFFFF);

    Widget content = ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: color ?? defaultBg,
            borderRadius: borderRadius,
            border: border,
          ),
          child: child,
        ),
      ),
    );

    return content;
  }
}
