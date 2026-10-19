import 'package:flutter/material.dart';
import '../../app/theme/hon_typography.dart';

class HonScreenHeader extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const HonScreenHeader({
    super.key,
    required this.title,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final heading = Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: HonTypography.largeTitle(
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
        final scaled = MediaQuery.textScalerOf(context).scale(34);
        final titlePainter = TextPainter(
          text: TextSpan(text: title, style: HonTypography.largeTitle()),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        final needsSeparateRow =
            constraints.maxWidth - actions.length * 48 < titlePainter.width;
        titlePainter.dispose();
        if (actions.isNotEmpty &&
            (needsSeparateRow ||
                (constraints.maxWidth < 330 && scaled > 38 || scaled > 47))) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              heading,
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: heading),
            ...actions,
          ],
        );
      },
    ),
  );
}
