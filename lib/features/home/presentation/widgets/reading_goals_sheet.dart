import 'dart:math';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../app/theme/hon_colors.dart';
import '../../../../app/theme/hon_typography.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/models/book.dart';
import '../../../reader/presentation/reader_navigator.dart';

class ReadingGoalsSheet extends StatelessWidget {
  final Book? mostRecentBook;

  const ReadingGoalsSheet({
    super.key,
    this.mostRecentBook,
  });

  static Future<void> show(BuildContext context, {Book? mostRecentBook}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReadingGoalsSheet(mostRecentBook: mostRecentBook),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF141416) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark ? Colors.white60 : Colors.black54;

    final finishedBooks = DatabaseService.instance.getLibraryBooks().where((b) {
      final prog = DatabaseService.instance.getProgress(b.id);
      return (prog != null && prog.completionPercentage >= 0.99);
    }).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Drag indicator
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Close button bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: Icon(CupertinoIcons.xmark_circle_fill, color: isDark ? Colors.white38 : Colors.black38),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Column(
                children: [
                  Text(
                    'Reading Goals',
                    style: HonTypography.largeTitle(color: textColor).copyWith(fontSize: 26),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Read every day, see your stats soar and\nfinish more books.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: subtextColor, height: 1.35),
                  ),
                  const SizedBox(height: 32),

                  // Half-circle arc gauge matching Apple Books screenshot
                  Builder(
                    builder: (context) {
                      final todayMins = DatabaseService.instance.getTodayReadingMinutes();
                      final goalMins = DatabaseService.instance.getDailyGoalMinutes();
                      final fraction = goalMins > 0 ? (todayMins / goalMins).clamp(0.0, 1.0) : 0.0;

                      return SizedBox(
                        width: 240,
                        height: 125,
                        child: CustomPaint(
                          painter: _ArcGaugePainter(
                            progress: fraction > 0 ? fraction : 0.02,
                            color: fraction >= 1.0 ? HonColors.accentGreen : HonColors.accentBlue,
                            trackColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              Text(
                                'Today\'s Reading',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$todayMins:00',
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w800,
                                  fontFamily: 'serif',
                                  color: textColor,
                                  letterSpacing: -1,
                                ),
                              ),
                              Text(
                                'of your $goalMins-minute goal >',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: subtextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 36),

                  // Keep Reading Button
                  if (mostRecentBook != null)
                    GestureDetector(
                      onTap: () {
                        Navigator.of(context).pop();
                        ReaderNavigator.openBook(context, mostRecentBook!);
                      },
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Keep Reading',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              mostRecentBook!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: subtextColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 40),

                  // Books Read This Year Section
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Books Read This Year',
                      style: HonTypography.sectionHeader(color: textColor).copyWith(fontSize: 19),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    height: 140,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: max(3, finishedBooks.length + 1),
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final book = index < finishedBooks.length ? finishedBooks[index] : null;
                        return Container(
                          width: 90,
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF242426) : const Color(0xFFF2F2F7),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.white10 : Colors.black12,
                              width: 0.5,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: book != null
                              ? Padding(
                                  padding: const EdgeInsets.all(8),
                                  child: Text(
                                    book.title,
                                    textAlign: TextAlign.center,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: textColor,
                                    ),
                                  ),
                                )
                              : Text(
                                  '${index + 1}',
                                  style: TextStyle(
                                    fontSize: 32,
                                    fontFamily: 'serif',
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.white24 : Colors.black26,
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color trackColor;

  _ArcGaugePainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2 - 8;

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // Draw background semicircle
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      pi,
      pi,
      false,
      trackPaint,
    );

    // Draw active arc
    if (progress > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        pi,
        pi * progress.clamp(0.0, 1.0),
        false,
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ArcGaugePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
