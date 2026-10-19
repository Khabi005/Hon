import 'dart:io';
import 'package:flutter/material.dart';

class BookCoverWidget extends StatelessWidget {
  final String? coverPath;
  final String title;
  final String author;
  final double? width;
  final double? height;
  final double borderRadius;
  final bool showSpineShadow;

  const BookCoverWidget({
    super.key,
    this.coverPath,
    required this.title,
    this.author = '',
    this.width = 90,
    this.height = 135,
    this.borderRadius = 6,
    this.showSpineShadow = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = width != null && width!.isFinite
            ? width!
            : (constraints.maxWidth.isFinite ? constraints.maxWidth : 90.0);
        final double h = height != null && height!.isFinite
            ? height!
            : (constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : w * 1.5);

        final decodeWidth = (w * MediaQuery.devicePixelRatioOf(context))
            .ceil()
            .clamp(1, 1200);
        Widget imageContent;

        if (coverPath != null && coverPath!.isNotEmpty) {
          if (coverPath!.startsWith('assets/')) {
            imageContent = Image.asset(
              coverPath!,
              width: w,
              height: h,
              cacheWidth: decodeWidth,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackCover(w, h),
            );
          } else if (coverPath!.startsWith('http://') ||
              coverPath!.startsWith('https://')) {
            imageContent = Image.network(
              coverPath!,
              width: w,
              height: h,
              cacheWidth: decodeWidth,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildFallbackCover(w, h),
            );
          } else {
            final file = File(coverPath!);
            // Missing managed covers can be repaired after the first frame.
            // Keep a fallback widget until a file exists, so the repair builds
            // a fresh Image state instead of retaining an errored stream.
            imageContent = file.existsSync()
                ? Image.file(
                    file,
                    width: w,
                    height: h,
                    cacheWidth: decodeWidth,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildFallbackCover(w, h),
                  )
                : _buildFallbackCover(w, h);
          }
        } else {
          imageContent = _buildFallbackCover(w, h);
        }

        return Container(
          width: width != null && width!.isFinite ? width : null,
          height: height != null && height!.isFinite ? height : null,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 8,
                offset: const Offset(1, 4),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: Stack(
              children: [
                Positioned.fill(child: imageContent),
                if (showSpineShadow)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: (w * 0.08).clamp(4.0, 16.0),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Color(0x55000000),
                            Color(0x22000000),
                            Color(0x00000000),
                          ],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                      ),
                    ),
                  ),
                // Right-edge subtle highlight for realistic 3D sheen
                Positioned(
                  right: 0,
                  top: 0,
                  bottom: 0,
                  width: 2,
                  child: Container(color: Colors.white.withOpacity(0.12)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFallbackCover(double w, double h) {
    final hash = title.hashCode.abs();
    final palettes = [
      [const Color(0xFF2C3E50), const Color(0xFF34495E)],
      [const Color(0xFF51465F), const Color(0xFF786581)],
      [const Color(0xFF865740), const Color(0xFFAC8060)],
      [const Color(0xFF365D59), const Color(0xFF638078)],
      [const Color(0xFF485A3D), const Color(0xFF748364)],
      [const Color(0xFF6B3D45), const Color(0xFF956770)],
      [const Color(0xFF344960), const Color(0xFF607C95)],
      [const Color(0xFF494652), const Color(0xFF76727D)],
    ];
    final gradientColors = palettes[hash % palettes.length];

    return Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: (w * 0.1).clamp(6.0, 20.0),
        vertical: (h * 0.1).clamp(6.0, 20.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: (w * 0.13).clamp(10.0, 16.0),
                height: 1.2,
                fontFamily: 'Newsreader',
              ),
            ),
          ),
          if (author.isNotEmpty)
            Text(
              author,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.75),
                fontWeight: FontWeight.w400,
                fontSize: (w * 0.09).clamp(8.0, 12.0),
              ),
            ),
        ],
      ),
    );
  }
}
