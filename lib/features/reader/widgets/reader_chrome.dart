import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../shared/widgets/pressable_scale.dart';

/// Common reader framing: floating frosted buttons over the page instead of
/// full-width bars, so the text stays visible behind the controls. EPUB's
/// native equivalent follows the same placement, spacing and labels while its
/// publication remains in Readium.
class ReaderHeader extends StatelessWidget {
  final ReaderThemeConfig theme;
  final String location;
  final String status;
  final VoidCallback? onPrevious;
  final VoidCallback? onBack;
  final String? backLabel;
  final VoidCallback onClose;
  const ReaderHeader({
    super.key,
    required this.theme,
    required this.location,
    required this.status,
    this.onPrevious,
    this.onBack,
    this.backLabel,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    Widget? leading;
    if (onBack != null) {
      leading = _ReaderGlassButton(
        theme: theme,
        tooltip: backLabel ?? 'Catalogue',
        onTap: onBack!,
        icon: CupertinoIcons.chevron_left,
        iconSize: 15,
        label: backLabel ?? 'Catalogue',
      );
    } else if (onPrevious != null) {
      leading = _ReaderGlassButton(
        theme: theme,
        tooltip: 'Previous chapter',
        onTap: onPrevious!,
        icon: CupertinoIcons.arrow_counterclockwise,
        iconSize: 13,
        label: location.isNotEmpty ? location : 'Prev',
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        MediaQuery.paddingOf(context).top + 6,
        12,
        6,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 104,
            child: Align(
              alignment: Alignment.centerLeft,
              child: leading ?? const SizedBox.shrink(),
            ),
          ),
          Expanded(
            child: status.isEmpty
                ? const SizedBox.shrink()
                : Center(
                    child: _ReaderGlass(
                      theme: theme,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        status,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.secondaryTextColor,
                        ),
                      ),
                    ),
                  ),
          ),
          SizedBox(
            width: 104,
            child: Align(
              alignment: Alignment.centerRight,
              child: _ReaderGlassButton(
                theme: theme,
                tooltip: 'Close reader',
                onTap: onClose,
                icon: CupertinoIcons.xmark,
                iconSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ReaderFooter extends StatelessWidget {
  final ReaderThemeConfig theme;
  final String progress;
  final VoidCallback? onProgress;
  final VoidCallback? onReload;
  final VoidCallback onMenu;
  const ReaderFooter({
    super.key,
    required this.theme,
    required this.progress,
    this.onProgress,
    this.onReload,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final label = Text(
      progress,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: theme.secondaryTextColor,
      ),
    );
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        6,
        12,
        MediaQuery.paddingOf(context).bottom + 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Align(
              alignment: Alignment.centerLeft,
              child: onReload != null
                  ? _ReaderGlassButton(
                      theme: theme,
                      tooltip: 'Reload chapter',
                      onTap: onReload!,
                      icon: CupertinoIcons.arrow_clockwise,
                      iconSize: 18,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          Expanded(
            child: Center(
              child: Semantics(
                button: onProgress != null,
                label: 'Contents, $progress',
                excludeSemantics: true,
                child: onProgress != null
                    ? PressableScale(
                        onTap: onProgress,
                        child: _ReaderGlass(
                          theme: theme,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: label,
                        ),
                      )
                    : _ReaderGlass(
                        theme: theme,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        child: label,
                      ),
              ),
            ),
          ),
          SizedBox(
            width: 56,
            child: Align(
              alignment: Alignment.centerRight,
              child: _ReaderGlassButton(
                theme: theme,
                tooltip: 'Reader menu',
                onTap: onMenu,
                icon: CupertinoIcons.textformat_size,
                iconSize: 20,
                size: 48,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Frosted capsule tinted with the page colour, like the floating controls in
/// Apple Books. High contrast swaps the blur for a solid fill.
class _ReaderGlass extends StatelessWidget {
  const _ReaderGlass({
    required this.theme,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.circle = false,
  });

  final ReaderThemeConfig theme;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool circle;

  @override
  Widget build(BuildContext context) {
    final solid = MediaQuery.highContrastOf(context);
    final dark = theme.systemBrightness == Brightness.dark;
    final shape = circle ? const CircleBorder() : const StadiumBorder();
    final body = DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape,
        color: theme.backgroundColor.withValues(alpha: solid ? 1 : .72),
      ),
      child: Padding(padding: padding, child: child),
    );
    return DecoratedBox(
      decoration: ShapeDecoration(
        shape: shape.copyWith(
          side: BorderSide(
            color: theme.textColor.withValues(alpha: dark ? .14 : .08),
            width: .6,
          ),
        ),
        shadows: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .28 : .10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: solid
            ? body
            : BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: body,
              ),
      ),
    );
  }
}

class _ReaderGlassButton extends StatelessWidget {
  const _ReaderGlassButton({
    required this.theme,
    required this.tooltip,
    required this.onTap,
    required this.icon,
    this.iconSize = 16,
    this.label,
    this.size = 40,
  });

  final ReaderThemeConfig theme;
  final String tooltip;
  final VoidCallback onTap;
  final IconData icon;
  final double iconSize;
  final String? label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final iconWidget = Icon(icon, size: iconSize, color: theme.textColor);
    final Widget content = label == null
        ? SizedBox.square(
            dimension: size,
            child: Center(child: iconWidget),
          )
        : SizedBox(
            height: size,
            child: Padding(
              padding: const EdgeInsets.only(left: 10, right: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  iconWidget,
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      label!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: theme.textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: PressableScale(
          onTap: onTap,
          pressedScale: .92,
          child: _ReaderGlass(
            theme: theme,
            circle: label == null,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Hidden chrome stays out of touch and accessibility navigation while its
/// paint-only slide animation completes.
class ReaderControlsVisibility extends StatelessWidget {
  final bool visible;
  final Widget child;
  const ReaderControlsVisibility({
    super.key,
    required this.visible,
    required this.child,
  });
  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: ExcludeSemantics(
      excluding: !visible,
      child: RepaintBoundary(child: child),
    ),
  );
}
