import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bootstrap/providers.dart';
import '../theme/hon_colors.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/browse/presentation/browse_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/downloads/presentation/downloads_screen.dart';

class TabScaffold extends ConsumerStatefulWidget {
  const TabScaffold({super.key});

  @override
  ConsumerState<TabScaffold> createState() => _TabScaffoldState();
}

class _TabScaffoldState extends ConsumerState<TabScaffold> {
  int _currentIndex = 0;

  final List<Widget> _tabs = const [
    HomeScreen(),
    LibraryScreen(),
    BrowseScreen(),
    SearchScreen(),
    DownloadsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeDownloads = ref.watch(activeDownloadsCountProvider);
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, bottomInset > 0 ? bottomInset + 4 : 12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(32),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              height: 60,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xDD1C1C1E) : const Color(0xEEFFFFFF),
                borderRadius: BorderRadius.circular(32),
                border: Border.all(
                  color: isDark ? const Color(0x33FFFFFF) : const Color(0x1F000000),
                  width: 0.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  _buildTabItem(
                    index: 0,
                    label: 'Home',
                    icon: CupertinoIcons.house_fill,
                    isDark: isDark,
                  ),
                  _buildTabItem(
                    index: 1,
                    label: 'Library',
                    icon: CupertinoIcons.book_fill,
                    isDark: isDark,
                  ),
                  _buildTabItem(
                    index: 2,
                    label: 'Browse',
                    icon: CupertinoIcons.compass_fill,
                    isDark: isDark,
                  ),
                  _buildTabItem(
                    index: 3,
                    label: 'Search',
                    icon: CupertinoIcons.search,
                    isDark: isDark,
                  ),
                  _buildTabItem(
                    index: 4,
                    label: 'Downloads',
                    icon: CupertinoIcons.arrow_down_circle_fill,
                    badgeCount: activeDownloads > 0 ? activeDownloads : null,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabItem({
    required int index,
    required String label,
    required IconData icon,
    int? badgeCount,
    required bool isDark,
  }) {
    final isSelected = _currentIndex == index;
    final color = isSelected
        ? (isDark ? Colors.white : Colors.black)
        : (isDark ? Colors.white54 : Colors.black45);

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _currentIndex = index);
        },
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(
                      icon,
                      size: 21,
                      color: color,
                    ),
                    if (badgeCount != null)
                      Positioned(
                        right: -6,
                        top: -4,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                            color: HonColors.accentOrange,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                          child: Text(
                            '$badgeCount',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: color,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
