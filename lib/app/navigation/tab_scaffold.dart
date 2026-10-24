import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../bootstrap/providers.dart';
import '../theme/glass_surface.dart';
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
  final Set<int> _visited = {0};
  int? _pressedIndex;
  static const _tabs = [
    HomeScreen(),
    LibraryScreen(),
    BrowseScreen(),
    SearchScreen(),
    DownloadsScreen(),
  ];
  static const _labels = ['Home', 'Library', 'Browse', 'Search', 'Downloads'];
  static const _icons = [
    CupertinoIcons.house_fill,
    CupertinoIcons.book_fill,
    CupertinoIcons.compass_fill,
    CupertinoIcons.search,
    CupertinoIcons.arrow_down_circle_fill,
  ];

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(navigationTabProvider);
    final activeDownloads = ref.watch(activeDownloadsCountProvider);
    _visited.add(selected);
    final colors = Theme.of(context).colorScheme;
    final reduced = MediaQuery.disableAnimationsOf(context);
    final compact =
        MediaQuery.sizeOf(context).width < 370 ||
        MediaQuery.textScalerOf(context).scale(12) > 17;
    return PopScope(
      canPop: selected == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(navigationTabProvider.notifier).state = 0;
      },
      child: Scaffold(
        extendBody: true,
        body: IndexedStack(
          index: selected,
          children: List.generate(
            _tabs.length,
            (index) => _visited.contains(index)
                ? TickerMode(
                    enabled: selected == index,
                    child: ExcludeFocus(
                      excluding: selected != index,
                      child: RepaintBoundary(child: _tabs[index]),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        // Blur is clipped to the floating navigation capsule.
        bottomNavigationBar: SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: GlassSurface(
                navigation: true,
                radius: 36,
                child: SizedBox(
                  height: compact ? 58 : 64,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final tabWidth = constraints.maxWidth / _tabs.length;
                      final capsuleWidth = (tabWidth - 8).clamp(36.0, 72.0);
                      final capsuleHeight = compact ? 46.0 : 52.0;
                      final isDark =
                          Theme.of(context).brightness == Brightness.dark;
                      final isPressed = _pressedIndex != null;

                      return Stack(
                        children: [
                          // Single liquid glass capsule, driven by a spring.
                          _SpringCapsule(
                            left:
                                selected * tabWidth +
                                (tabWidth - capsuleWidth) / 2,
                            top: ((compact ? 58.0 : 64.0) - capsuleHeight) / 2,
                            width: capsuleWidth,
                            height: capsuleHeight,
                            reduced: reduced,
                            child: AnimatedScale(
                              scale: isPressed && _pressedIndex == selected
                                  ? 0.92
                                  : 1.0,
                              duration: const Duration(milliseconds: 100),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.16)
                                      : Colors.black.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.15)
                                        : Colors.black.withValues(alpha: 0.06),
                                    width: 0.7,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: isDark
                                          ? Colors.black.withValues(alpha: 0.25)
                                          : Colors.black.withValues(
                                              alpha: 0.04,
                                            ),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // Row of tab items with touch handlers
                          Row(
                            children: List.generate(_tabs.length, (index) {
                              final active = selected == index;
                              return Expanded(
                                child: Semantics(
                                  selected: active,
                                  button: true,
                                  label: _labels[index],
                                  child: Tooltip(
                                    message: _labels[index],
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTapDown: (_) =>
                                          setState(() => _pressedIndex = index),
                                      onTapUp: (_) =>
                                          setState(() => _pressedIndex = null),
                                      onTapCancel: () =>
                                          setState(() => _pressedIndex = null),
                                      onTap: () {
                                        if (selected == index) return;
                                        HapticFeedback.selectionClick();
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        ref
                                                .read(
                                                  navigationTabProvider
                                                      .notifier,
                                                )
                                                .state =
                                            index;
                                      },
                                      child: Center(
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 5,
                                          ),
                                          child: ExcludeSemantics(
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Badge(
                                                  isLabelVisible:
                                                      index == 4 &&
                                                      activeDownloads > 0,
                                                  label: Text(
                                                    activeDownloads > 99
                                                        ? '99+'
                                                        : '$activeDownloads',
                                                  ),
                                                  child: Icon(
                                                    _icons[index],
                                                    size: 21,
                                                    color: active
                                                        ? (isDark
                                                              ? Colors.white
                                                              : Colors.black)
                                                        : colors
                                                              .onSurfaceVariant
                                                              .withValues(
                                                                alpha: 0.75,
                                                              ),
                                                  ),
                                                ),
                                                if (!compact) ...[
                                                  const SizedBox(height: 3),
                                                  FittedBox(
                                                    fit: BoxFit.scaleDown,
                                                    child: Text(
                                                      _labels[index],
                                                      maxLines: 1,
                                                      style: TextStyle(
                                                        fontSize: 10,
                                                        fontWeight: active
                                                            ? FontWeight.w600
                                                            : FontWeight.w400,
                                                        color: active
                                                            ? (isDark
                                                                  ? Colors.white
                                                                  : Colors
                                                                        .black)
                                                            : colors
                                                                  .onSurfaceVariant
                                                                  .withValues(
                                                                    alpha: 0.75,
                                                                  ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Moves the tab capsule with a critically damped spring and stretches it
/// slightly while it travels, so it reads as liquid rather than sliding.
class _SpringCapsule extends StatefulWidget {
  const _SpringCapsule({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
    required this.reduced,
    required this.child,
  });

  final double left;
  final double top;
  final double width;
  final double height;
  final bool reduced;
  final Widget child;

  @override
  State<_SpringCapsule> createState() => _SpringCapsuleState();
}

class _SpringCapsuleState extends State<_SpringCapsule>
    with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 320,
    damping: 31,
  );
  late final AnimationController _x = AnimationController.unbounded(
    vsync: this,
    value: widget.left,
  );

  @override
  void didUpdateWidget(covariant _SpringCapsule oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.left == oldWidget.left) return;
    if (widget.reduced) {
      _x.value = widget.left;
      return;
    }
    _x.animateWith(
      SpringSimulation(_spring, _x.value, widget.left, _x.velocity),
    );
  }

  @override
  void dispose() {
    _x.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _x,
    builder: (context, child) {
      // Up to 18% wider at peak speed, shrinking back as it settles.
      final stretch = (_x.velocity.abs() / 6000).clamp(0.0, .18);
      final width = widget.width * (1 + stretch);
      return Positioned(
        left: _x.value - (width - widget.width) / 2,
        top: widget.top,
        width: width,
        height: widget.height,
        child: child!,
      );
    },
    child: widget.child,
  );
}
