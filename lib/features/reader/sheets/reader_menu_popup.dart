import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/reader_theme.dart';

class ReaderMenuPopup extends StatelessWidget {
  final VoidCallback onOpenContents;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenThemes;
  final VoidCallback onToggleReadingMode;
  final VoidCallback onToggleBookmark;
  final VoidCallback? onShareSelected;
  final VoidCallback? onReloadChapter;
  final String searchLabel;
  final ReaderThemeConfig? theme;
  final VoidCallback onToggleOrientationLock;
  final bool isOrientationLocked;
  final bool isBookmarked;
  final bool isContinuousScroll;

  const ReaderMenuPopup({
    super.key,
    required this.onOpenContents,
    required this.onOpenSearch,
    required this.onOpenThemes,
    required this.onToggleReadingMode,
    required this.onToggleBookmark,
    this.onShareSelected,
    this.onReloadChapter,
    this.searchLabel = 'Search Book',
    this.theme,
    required this.onToggleOrientationLock,
    required this.isOrientationLocked,
    required this.isBookmarked,
    required this.isContinuousScroll,
  });

  static Future<void> show(
    BuildContext context, {
    required VoidCallback onOpenContents,
    required VoidCallback onOpenSearch,
    required VoidCallback onOpenThemes,
    required VoidCallback onToggleReadingMode,
    required VoidCallback onToggleBookmark,
    VoidCallback? onShareSelected,
    VoidCallback? onReloadChapter,
    String searchLabel = 'Search Book',
    ReaderThemeConfig? theme,
    required VoidCallback onToggleOrientationLock,
    required bool isOrientationLocked,
    required bool isBookmarked,
    required bool isContinuousScroll,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ReaderMenu',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      pageBuilder: (ctx, anim1, anim2) {
        return Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              16,
              MediaQuery.of(ctx).padding.bottom + 56,
            ),
            child: Material(
              color: Colors.transparent,
              child: ReaderMenuPopup(
                theme: theme,
                searchLabel: searchLabel,
                onOpenContents: () {
                  Navigator.of(ctx).pop();
                  onOpenContents();
                },
                onOpenSearch: () {
                  Navigator.of(ctx).pop();
                  onOpenSearch();
                },
                onOpenThemes: () {
                  Navigator.of(ctx).pop();
                  onOpenThemes();
                },
                onToggleReadingMode: () {
                  Navigator.of(ctx).pop();
                  onToggleReadingMode();
                },
                onToggleBookmark: () {
                  Navigator.of(ctx).pop();
                  onToggleBookmark();
                },
                onShareSelected: onShareSelected == null
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        onShareSelected();
                      },
                onReloadChapter: onReloadChapter == null
                    ? null
                    : () {
                        Navigator.of(ctx).pop();
                        onReloadChapter();
                      },
                onToggleOrientationLock: () {
                  Navigator.of(ctx).pop();
                  onToggleOrientationLock();
                },
                isOrientationLocked: isOrientationLocked,
                isBookmarked: isBookmarked,
                isContinuousScroll: isContinuousScroll,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.92, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            alignment: Alignment.bottomRight,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        theme?.systemBrightness == Brightness.dark ||
        theme == null && Theme.of(context).brightness == Brightness.dark;
    final pillBg =
        theme?.uiControlsBackground ??
        (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7));
    final textColor =
        theme?.textColor ?? (isDark ? Colors.white : Colors.black);
    final iconColor = textColor;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Container(
        width: 250,
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000),
            width: 0.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.25),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 1. Contents
            _buildMenuItem(
              title: 'Contents',
              icon: CupertinoIcons.list_bullet,
              textColor: textColor,
              iconColor: iconColor,
              onTap: onOpenContents,
            ),
            _buildDivider(isDark),

            // 2. Search Book
            _buildMenuItem(
              title: searchLabel,
              icon: CupertinoIcons.search,
              textColor: textColor,
              iconColor: iconColor,
              onTap: onOpenSearch,
            ),
            _buildDivider(isDark),

            // 3. Themes & Settings
            _buildMenuItem(
              title: 'Themes & Settings',
              icon: CupertinoIcons.textformat_size,
              textColor: textColor,
              iconColor: iconColor,
              onTap: onOpenThemes,
            ),
            _buildDivider(isDark),

            // 4. Reload Chapter (if supported)
            if (onReloadChapter != null) ...[
              _buildMenuItem(
                title: 'Reload Chapter',
                icon: CupertinoIcons.arrow_clockwise,
                textColor: textColor,
                iconColor: iconColor,
                onTap: onReloadChapter!,
              ),
              _buildDivider(isDark),
            ],

            // 4. Quick Action Icons Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (onShareSelected != null)
                    _buildQuickAction(
                      icon: CupertinoIcons.share,
                      label: 'Share',
                      color: iconColor,
                      onTap: onShareSelected!,
                    ),
                  _buildQuickAction(
                    icon: CupertinoIcons.lock_rotation,
                    label: 'Lock',
                    color: isOrientationLocked ? Colors.amber : iconColor,
                    onTap: onToggleOrientationLock,
                  ),
                  _buildQuickAction(
                    icon: isContinuousScroll
                        ? CupertinoIcons.book
                        : CupertinoIcons.doc_plaintext,
                    label: isContinuousScroll ? 'Swipe' : 'Scroll',
                    color: iconColor,
                    onTap: onToggleReadingMode,
                  ),
                  _buildQuickAction(
                    icon: isBookmarked
                        ? CupertinoIcons.bookmark_fill
                        : CupertinoIcons.bookmark,
                    label: 'Bookmark',
                    color: isBookmarked ? Colors.amber : iconColor,
                    onTap: onToggleBookmark,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required String title,
    required IconData icon,
    required Color textColor,
    required Color iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
            Icon(icon, size: 19, color: iconColor),
          ],
        ),
      ),
    );
  }

  Widget _buildDivider(bool isDark) {
    return Divider(
      height: 0.5,
      thickness: 0.5,
      color: isDark ? const Color(0x22FFFFFF) : const Color(0x1F000000),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      icon: Icon(icon, size: 20, color: color),
      tooltip: label,
      onPressed: onTap,
    );
  }
}
