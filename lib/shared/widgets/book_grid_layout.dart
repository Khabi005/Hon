import 'package:flutter/material.dart';

/// Gives every cover a 2:3 frame and reserves space for scaled labels.
SliverGridDelegate bookGridLayout(
  BuildContext context, {
  double padding = 40,
  double gap = 16,
}) {
  final width = MediaQuery.sizeOf(context).width - padding;
  final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
  final columns = (width / (scale > 1.3 ? 160 : 112)).floor().clamp(2, 6);
  final itemWidth = (width - (columns - 1) * gap) / columns;
  return SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: columns,
    crossAxisSpacing: gap,
    mainAxisSpacing: 24,
    mainAxisExtent: itemWidth * 1.5 + 12 + 56 * scale,
  );
}
