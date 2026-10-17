import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ReaderMenuPopup extends StatelessWidget {
  final VoidCallback onOpenContents;
  final VoidCallback onOpenSearch;
  final VoidCallback onOpenThemes;
  final VoidCallback onToggleReadingMode;
  final VoidCallback onToggleBookmark;
  final bool isBookmarked;
  final bool isContinuousScroll;

  const ReaderMenuPopup({
    super.key,
    required this.onOpenContents,
    required this.onOpenSearch,
    required this.onOpenThemes,
    required this.onToggleReadingMode,
    required this.onToggleBookmark,
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
    required bool isBookmarked,
    required bool isContinuousScroll,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'ReaderMenu',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 180),
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
              CurvedAnimation(parent: anim1, curve: Curves.easeOutBack),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pillBg = isDark
        ? const Color(0xDD2C2C2E)
        : const Color(0xEEF2F2F7);
    final textColor = isDark ? Colors.white : Colors.black;
    final iconColor = isDark ? Colors.white : Colors.black;

    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
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
                title: 'Search Book',
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

              // 4. Quick Action Icons Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildQuickAction(
                      icon: CupertinoIcons.share,
                      label: 'Share',
                      color: iconColor,
                      onTap: () {},
                    ),
                    _buildQuickAction(
                      icon: CupertinoIcons.lock_rotation,
                      label: 'Lock',
                      color: iconColor,
                      onTap: () {},
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
            Icon(
              icon,
              size: 19,
              color: iconColor,
            ),
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
      onPressed: onTap,
    );
  }
}
