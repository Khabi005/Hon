import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

enum PdfColorFilterMode {
  original,
  sepia,
  inverted,
}

enum PdfPageViewMode {
  continuousZoom,
  singlePage,
}

class PdfAppearanceSheet extends StatelessWidget {
  final PdfColorFilterMode currentFilter;
  final PdfPageViewMode currentViewMode;
  final ValueChanged<PdfColorFilterMode> onSelectFilter;
  final ValueChanged<PdfPageViewMode> onSelectViewMode;

  const PdfAppearanceSheet({
    super.key,
    required this.currentFilter,
    required this.currentViewMode,
    required this.onSelectFilter,
    required this.onSelectViewMode,
  });

  static Future<void> show(
    BuildContext context, {
    required PdfColorFilterMode currentFilter,
    required PdfPageViewMode currentViewMode,
    required ValueChanged<PdfColorFilterMode> onSelectFilter,
    required ValueChanged<PdfPageViewMode> onSelectViewMode,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PdfAppearanceSheet(
        currentFilter: currentFilter,
        currentViewMode: currentViewMode,
        onSelectFilter: onSelectFilter,
        onSelectViewMode: onSelectViewMode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reading Appearance',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                ),
              ),
              IconButton(
                icon: const Icon(CupertinoIcons.xmark_circle_fill),
                color: isDark ? Colors.white38 : Colors.black38,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Section 1: Page Tone / Filter
          Text(
            'PAGE TONE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: subtextColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildFilterOption(
                context,
                title: 'Original',
                mode: PdfColorFilterMode.original,
                previewBg: Colors.white,
                previewTextColor: Colors.black,
                isDark: isDark,
              ),
              const SizedBox(width: 10),
              _buildFilterOption(
                context,
                title: 'Sepia',
                mode: PdfColorFilterMode.sepia,
                previewBg: const Color(0xFFFBF0D9),
                previewTextColor: const Color(0xFF5F4B32),
                isDark: isDark,
              ),
              const SizedBox(width: 10),
              _buildFilterOption(
                context,
                title: 'Inverted',
                mode: PdfColorFilterMode.inverted,
                previewBg: const Color(0xFF1C1C1E),
                previewTextColor: Colors.white,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Section 2: View Mode
          Text(
            'PAGE NAVIGATION',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: subtextColor,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildViewModeOption(
                context,
                title: 'Continuous & Zoom',
                subtitle: 'Scroll & pinch',
                icon: CupertinoIcons.arrow_up_arrow_down,
                mode: PdfPageViewMode.continuousZoom,
                isDark: isDark,
              ),
              const SizedBox(width: 10),
              _buildViewModeOption(
                context,
                title: 'Single Page',
                subtitle: 'Page flip',
                icon: CupertinoIcons.book,
                mode: PdfPageViewMode.singlePage,
                isDark: isDark,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterOption(
    BuildContext context, {
    required String title,
    required PdfColorFilterMode mode,
    required Color previewBg,
    required Color previewTextColor,
    required bool isDark,
  }) {
    final isSelected = currentFilter == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          onSelectFilter(mode);
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: previewBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF007AFF)
                  : (isDark ? Colors.white24 : Colors.black12),
              width: isSelected ? 2.5 : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF007AFF).withOpacity(0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    )
                  ]
                : null,
          ),
          child: Column(
            children: [
              Text(
                'Aa',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: previewTextColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: previewTextColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewModeOption(
    BuildContext context, {
    required String title,
    required String subtitle,
    required IconData icon,
    required PdfPageViewMode mode,
    required bool isDark,
  }) {
    final isSelected = currentViewMode == mode;

    return Expanded(
      child: GestureDetector(
        onTap: () {
          onSelectViewMode(mode);
          Navigator.of(context).pop();
        },
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF007AFF).withOpacity(0.12)
                : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF007AFF)
                  : (isDark ? Colors.white12 : Colors.black12),
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF007AFF)
                    : (isDark ? Colors.white70 : Colors.black54),
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? const Color(0xFF007AFF)
                            : (isDark ? Colors.white : Colors.black),
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
