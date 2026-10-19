import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/app_appearance.dart';
import '../../../app/theme/glass_surface.dart';

class AppAppearanceSection extends ConsumerWidget {
  const AppAppearanceSection({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(appAppearanceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('APP APPEARANCE', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 8),
        GlassSurface(
          radius: 20,
          child: Column(
            children: [
              for (final style in AppAppearance.values)
                Semantics(
                  selected: selected == style,
                  child: ListTile(
                    leading: Icon(
                      style == AppAppearance.standard
                          ? Icons.auto_awesome_outlined
                          : Icons.blur_on_rounded,
                    ),
                    title: Text(
                      style == AppAppearance.standard
                          ? 'Standard'
                          : 'Liquid Glass',
                    ),
                    subtitle: Text(
                      style == AppAppearance.standard
                          ? 'Quiet surfaces with a softly frosted tab bar.'
                          : 'Translucent panels, luminous edges and a tinted backdrop.',
                    ),
                    trailing: Icon(
                      selected == style
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                    ),
                    onTap: () async {
                      try {
                        await ref
                            .read(appAppearanceProvider.notifier)
                            .select(style);
                      } catch (_) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Could not save appearance. Please try again.',
                              ),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Follows your system light or dark mode. High contrast makes glass opaque.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
