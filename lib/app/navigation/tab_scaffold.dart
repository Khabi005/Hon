import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bootstrap/providers.dart';
import '../theme/hon_colors.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/browse/presentation/browse_screen.dart';
import '../../features/downloads/presentation/downloads_screen.dart';
import '../../features/search/presentation/search_screen.dart';

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
    DownloadsScreen(),
    SearchScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeColor = isDark ? HonColors.tabActiveDark : HonColors.tabActiveLight;
    final inactiveColor = isDark ? HonColors.tabInactiveDark : HonColors.tabInactiveLight;
    final activeDownloads = ref.watch(activeDownloadsCountProvider);

    return Scaffold(
      extendBody: true,
      body: IndexedStack(
        index: _currentIndex,
        children: _tabs,
      ),
      bottomNavigationBar: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Container(
            decoration: BoxDecoration(
              color: (isDark ? const Color(0xDD1C1C1E) : const Color(0xEEFFFFFF)),
              border: Border(
                top: BorderSide(
                  color: isDark ? const Color(0x22FFFFFF) : const Color(0x1F000000),
                  width: 0.5,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 52,
                child: Row(
                  children: [
                    _buildTabItem(
                      index: 0,
                      label: 'Home',
                      icon: CupertinoIcons.house_fill,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                    _buildTabItem(
                      index: 1,
                      label: 'Library',
                      icon: CupertinoIcons.book_fill,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                    _buildTabItem(
                      index: 2,
                      label: 'Browse',
                      icon: CupertinoIcons.compass_fill,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                    _buildTabItem(
                      index: 3,
                      label: 'Downloads',
                      icon: CupertinoIcons.arrow_down_circle_fill,
                      badgeCount: activeDownloads > 0 ? activeDownloads : null,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                    _buildTabItem(
                      index: 4,
                      label: 'Search',
                      icon: CupertinoIcons.search,
                      activeColor: activeColor,
                      inactiveColor: inactiveColor,
                    ),
                  ],
                ),
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
    required Color activeColor,
    required Color inactiveColor,
  }) {
    final isSelected = _currentIndex == index;
    final color = isSelected ? activeColor : inactiveColor;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _currentIndex = index);
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  icon,
                  size: 23,
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
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: color,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
