import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/database/database_service.dart';

/// Seven local calendar days; no network requests or animated background work.
class ReadingWeek extends StatelessWidget {
  const ReadingWeek({super.key});

  @override
  Widget build(BuildContext context) {
    final db = DatabaseService.instance;
    final now = DateTime.now();
    final days = List.generate(
      7,
      (i) => DateTime(now.year, now.month, now.day - 6 + i),
    );
    final minutes = days.map(db.getReadingMinutesOn).toList();
    final maximum = minutes.fold<int>(
      db.getDailyGoalMinutes().clamp(1, 1440),
      (a, b) => a > b ? a : b,
    );
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'YOUR LAST 7 DAYS',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Semantics(
                  label:
                      '${DateFormat.MMMEd().format(days[i])}: ${minutes[i]} reading minutes',
                  child: ExcludeSemantics(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 48,
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              width: 18,
                              height: minutes[i] == 0
                                  ? 4
                                  : 6 + (minutes[i] / maximum).clamp(0, 1) * 42,
                              decoration: BoxDecoration(
                                color: minutes[i] == 0
                                    ? colors.onSurface.withValues(alpha: .08)
                                    : (i == 6
                                          ? const Color(0xFFB25D39)
                                          : const Color(0xFF9B927C)),
                                borderRadius: BorderRadius.circular(5),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          DateFormat.E().format(days[i]).substring(0, 1),
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                            fontWeight: i == 6
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
