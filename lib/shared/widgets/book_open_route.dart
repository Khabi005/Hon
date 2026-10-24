import 'package:flutter/material.dart';

/// Remembers where a book cover sits on screen, so opening the book can grow
/// out of it. Create one per build, wrap the cover, and read [rect] on tap.
class CoverOrigin {
  BuildContext? _context;

  Widget wrap(Widget cover) => Builder(
    builder: (context) {
      _context = context;
      return cover;
    },
  );

  /// The cover's bounds in global coordinates, or null once it has left the
  /// screen.
  Rect? get rect {
    final context = _context;
    if (context == null || !context.mounted) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }
}

/// Opens a full-screen page by zooming it out of a book cover, the way Apple
/// Books opens a book. The page is laid out at full size from the first frame,
/// so it never reflows while it grows; it is only scaled and clipped.
class BookOpenRoute<T> extends PageRouteBuilder<T> {
  BookOpenRoute({
    required WidgetBuilder builder,
    required Rect origin,
    super.settings,
  }) : super(
         fullscreenDialog: true,
         transitionDuration: const Duration(milliseconds: 420),
         reverseTransitionDuration: const Duration(milliseconds: 320),
         pageBuilder: (context, _, __) => builder(context),
         transitionsBuilder: (context, animation, _, child) =>
             _BookOpenTransition(
               animation: animation,
               origin: origin,
               child: child,
             ),
       );

  /// The route for [builder]: a zoom from [origin] when there is one and
  /// animations are on, otherwise the usual full-screen modal.
  static Route<T> to<T>(
    BuildContext context, {
    required WidgetBuilder builder,
    Rect? origin,
  }) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (origin == null || origin.isEmpty || reduceMotion) {
      // Modal, like Apple Books: no edge swipe-back to fight page turns.
      return MaterialPageRoute<T>(fullscreenDialog: true, builder: builder);
    }
    return BookOpenRoute<T>(builder: builder, origin: origin);
  }
}

class _BookOpenTransition extends StatelessWidget {
  final Animation<double> animation;
  final Rect origin;
  final Widget child;

  const _BookOpenTransition({
    required this.animation,
    required this.origin,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final grow = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    // The cover hands over to the page early, so the zoom reads as the book
    // opening rather than a picture stretching.
    final reveal = CurvedAnimation(
      parent: animation,
      curve: const Interval(0, 0.35, curve: Curves.easeOut),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final full = Offset.zero & constraints.biggest;
        return AnimatedBuilder(
          animation: grow,
          child: child,
          builder: (context, child) {
            // The tree keeps the same shape at every step, so the page keeps
            // its state when the animation ends.
            final t = grow.value;
            final rect = Rect.lerp(origin, full, t)!;
            final scale = rect.width / full.width;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6 * (1 - t)),
                    clipBehavior: t >= 1 ? Clip.none : Clip.antiAlias,
                    child: OverflowBox(
                      minWidth: full.width,
                      maxWidth: full.width,
                      minHeight: full.height,
                      maxHeight: full.height,
                      child: Transform.scale(
                        scale: scale,
                        child: FadeTransition(opacity: reveal, child: child),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
