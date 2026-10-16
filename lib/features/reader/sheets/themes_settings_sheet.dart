import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/reader_theme.dart';

class ThemesSettingsSheet extends ConsumerWidget {
  const ThemesSettingsSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => const ThemesSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(readerPreferencesProvider);
    final notifier = ref.read(readerPreferencesProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final sheetBg = isDark ? HonColors.darkSurfaceElevated : Colors.white;
    final textCol = isDark ? Colors.white : Colors.black;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with Title & Close button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Themes & Settings',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: textCol,
                ),
              ),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white12 : Colors.black.withOpacity(0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 14,
                    color: isDark ? Colors.white70 : Colors.black54,
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Top Control Pill: [ A | A ] and Mode Toggles
          Row(
            children: [
              // Font Size Adjuster Pill
              Expanded(
                flex: 3,
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: notifier.decreaseFontSize,
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(12)),
                          child: Center(
                            child: Text(
                              'A',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: textCol,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 22,
                        color: isDark ? Colors.white24 : Colors.black12,
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: notifier.increaseFontSize,
                          borderRadius: const BorderRadius.horizontal(right: Radius.circular(12)),
                          child: Center(
                            child: Text(
                              'A',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: textCol,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Layout Mode Toggle (Paginated vs Scroll)
              InkWell(
                onTap: () {
                  final next = prefs.layoutMode == ReaderLayoutMode.paginated
                      ? ReaderLayoutMode.verticalScroll
                      : ReaderLayoutMode.paginated;
                  notifier.setLayoutMode(next);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 44,
                  width: 48,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    prefs.layoutMode == ReaderLayoutMode.paginated
                        ? CupertinoIcons.book
                        : CupertinoIcons.doc_text,
                    size: 19,
                    color: textCol,
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Theme Quick Invert
              InkWell(
                onTap: () {
                  final next = prefs.themePreset == ReaderThemePreset.bold
                      ? ReaderThemePreset.original
                      : ReaderThemePreset.bold;
                  notifier.setPreset(next);
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 44,
                  width: 48,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    CupertinoIcons.circle_righthalf_fill,
                    size: 19,
                    color: textCol,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Brightness Slider with Sun Icons
          Row(
            children: [
              Icon(
                CupertinoIcons.sun_min,
                size: 17,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: isDark ? Colors.white70 : Colors.black54,
                    inactiveTrackColor: isDark ? Colors.white12 : Colors.black12,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: prefs.brightness,
                    min: 0.2,
                    max: 1.0,
                    onChanged: (val) => notifier.setBrightness(val),
                  ),
                ),
              ),
              Icon(
                CupertinoIcons.sun_max,
                size: 21,
                color: isDark ? Colors.white54 : Colors.black45,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2x3 Grid of 6 Theme Cards
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.1,
            children: ReaderThemeConfig.all.map((cfg) {
              final isSelected = prefs.themePreset == cfg.preset;
              return _ThemeCard(
                config: cfg,
                isSelected: isSelected,
                onTap: () => notifier.setPreset(cfg.preset),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Bottom Pill: ⚙ Customize
          Center(
            child: InkWell(
              onTap: () => _showCustomizeSheet(context, ref),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE5E5EA),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.gear,
                      size: 16,
                      color: textCol,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Customize',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: textCol,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomizeSheet(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(readerPreferencesProvider.notifier);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        return Consumer(
          builder: (ctx, ref, _) {
            final p = ref.watch(readerPreferencesProvider);
            return Container(
              decoration: BoxDecoration(
                color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Accessibility & Layout',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(CupertinoIcons.xmark, size: 18),
                        onPressed: () => Navigator.of(ctx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Font Family Selector
                  const Text(
                    'Font Family',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ReaderFontFamily.values.map((f) {
                      final selected = p.fontFamily == f;
                      return ChoiceChip(
                        label: Text(f.displayName),
                        selected: selected,
                        onSelected: (_) => notifier.setFontFamily(f),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Line Height Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Line Spacing', style: TextStyle(fontSize: 14)),
                      Text('${p.lineHeight.toStringAsFixed(2)}x',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ],
                  ),
                  Slider(
                    value: p.lineHeight,
                    min: 1.3,
                    max: 2.2,
                    onChanged: (v) => notifier.setLineHeight(v),
                  ),
                  const SizedBox(height: 12),

                  // Justification Switch
                  SwitchListTile(
                    title: const Text('Justify Text', style: TextStyle(fontSize: 14)),
                    value: p.isJustified,
                    onChanged: (_) => notifier.toggleJustified(),
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _ThemeCard extends StatelessWidget {
  final ReaderThemeConfig config;
  final bool isSelected;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.config,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: config.backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.black.withOpacity(0.08),
            width: isSelected ? 2.5 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Aa',
              style: TextStyle(
                fontSize: 20,
                fontWeight: config.preset == ReaderThemePreset.bold
                    ? FontWeight.w900
                    : FontWeight.w600,
                color: config.textColor,
                fontFamily: 'serif',
              ),
            ),
            const SizedBox(height: 4),
            Text(
              config.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: config.textColor.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
