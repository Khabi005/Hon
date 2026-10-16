import 'package:flutter/material.dart';

class OrnateDivider extends StatelessWidget {
  final Color? color;
  final double width;
  final double height;

  const OrnateDivider({
    super.key,
    this.color,
    this.width = 120,
    this.height = 20,
  });

  @override
  Widget build(BuildContext context) {
    final dividerColor = color ?? Theme.of(context).dividerColor;

    return Center(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          painter: _OrnateDividerPainter(dividerColor),
        ),
      ),
    );
  }
}

class _OrnateDividerPainter extends CustomPainter {
  final Color color;
  _OrnateDividerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final centerY = size.height / 2;
    final centerX = size.width / 2;

    // Left line tapering to center
    canvas.drawLine(
      Offset(0, centerY),
      Offset(centerX - 24, centerY),
      paint,
    );

    // Right line tapering from center
    canvas.drawLine(
      Offset(centerX + 24, centerY),
      Offset(size.width, centerY),
      paint,
    );

    // Center decorative motif: interlocking rounded loops like Apple Books reference
    final path = Path();
    // Left loop
    path.addOval(Rect.fromCenter(
      center: Offset(centerX - 12, centerY),
      width: 14,
      height: 9,
    ));
    // Center diamond/knot
    path.addOval(Rect.fromCenter(
      center: Offset(centerX, centerY),
      width: 14,
      height: 9,
    ));
    // Right loop
    path.addOval(Rect.fromCenter(
      center: Offset(centerX + 12, centerY),
      width: 14,
      height: 9,
    ));

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _OrnateDividerPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}
