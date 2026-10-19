import '../../../../app/theme/glass_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../app/theme/hon_typography.dart';
import '../../../../core/sources/source_registry.dart';
import '../../../library/presentation/library_updates_screen.dart';

class SourceDiscoveryCard extends StatelessWidget {
  final VoidCallback onBrowse;
  const SourceDiscoveryCard({super.key, required this.onBrowse});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: SourceRegistry.instance.changeNotifier,
    builder: (context, _, child) {
      final sources = SourceRegistry.instance.getInstalledSources();
      final dark = Theme.of(context).brightness == Brightness.dark;
      final ink = dark ? const Color(0xFFFFE8D5) : const Color(0xFF573823);
      final muted = dark ? const Color(0xFFC9B6A5) : const Color(0xFF755A43);
      return GlassSurface(
        padding: const EdgeInsets.all(22),
        color: dark ? const Color(0xFF302720) : const Color(0xFFF3E6D4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: ink.withValues(alpha: .07),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(CupertinoIcons.compass, color: ink, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'A WORLD OF STORIES',
                    style: TextStyle(
                      color: muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Text(
              'Find your next chapter.',
              style: HonTypography.sectionHeader(color: ink),
            ),
            const SizedBox(height: 8),
            Text(
              SourceRegistry.instance.isPreparing
                  ? 'Preparing your bundled sources… Your library is ready to read.'
                  : sources.isEmpty
                  ? 'Explore Sources to add a place to discover and download novels.'
                  : 'Explore ${sources.length} enabled sources. Find a story, save a few chapters and make it yours.',
              style: TextStyle(color: muted, height: 1.5, fontSize: 14),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: onBrowse,
                  style: FilledButton.styleFrom(
                    backgroundColor: ink,
                    foregroundColor: dark
                        ? const Color(0xFF302720)
                        : const Color(0xFFFFF8F0),
                  ),
                  child: const Text('Browse Sources'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LibraryUpdatesScreen(),
                    ),
                  ),
                  style: TextButton.styleFrom(foregroundColor: ink),
                  child: const Text('Library Updates'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}
