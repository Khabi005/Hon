import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/glass_surface.dart';
import '../../../app/theme/reader_theme.dart';

/// Common reader framing. EPUB's native equivalent follows the same placement,
/// spacing and labels while its publication remains in Readium.
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
    final rich = GlassStyle.richOf(context);
    final bg = rich
        ? theme.backgroundColor.withValues(alpha: .75)
        : theme.backgroundColor;

    final content = Container(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.paddingOf(context).top + 8,
        16,
        8,
      ),
      color: bg,
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Align(
              alignment: Alignment.centerLeft,
              child: onBack != null
                  ? TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: onBack,
                      icon: Icon(
                        CupertinoIcons.chevron_left,
                        size: 16,
                        color: theme.secondaryTextColor,
                      ),
                      label: Text(
                        backLabel ?? 'Catalogue',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: theme.secondaryTextColor,
                        ),
                      ),
                    )
                  : onPrevious != null
                      ? TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: onPrevious,
                          icon: Icon(
                            CupertinoIcons.arrow_counterclockwise,
                            size: 13,
                            color: theme.secondaryTextColor,
                          ),
                          label: Text(
                            location.isNotEmpty ? location : 'Prev',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.secondaryTextColor,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
            ),
          ),
          Expanded(
            child: Text(
              status,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: theme.secondaryTextColor),
            ),
          ),
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Close reader',
                onPressed: onClose,
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: theme.textColor.withValues(alpha: .08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.xmark,
                    size: 15,
                    color: theme.textColor,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (rich) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: content,
        ),
      );
    }
    return content;
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
    final rich = GlassStyle.richOf(context);
    final bg = rich
        ? theme.backgroundColor.withValues(alpha: .75)
        : theme.backgroundColor;

    final content = Container(
      color: bg,
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.paddingOf(context).bottom + 8,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: onReload != null
                ? IconButton(
                    tooltip: 'Reload chapter',
                    onPressed: onReload,
                    icon: Icon(
                      CupertinoIcons.arrow_clockwise,
                      size: 20,
                      color: theme.textColor,
                    ),
                  )
                : null,
          ),
          Expanded(
            child: Semantics(
              button: onProgress != null,
              label: 'Contents, $progress',
              child: GestureDetector(
                onTap: onProgress,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    progress,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: theme.secondaryTextColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Reader menu',
            onPressed: onMenu,
            icon: Icon(
              CupertinoIcons.textformat_size,
              size: 23,
              color: theme.textColor,
            ),
          ),
        ],
      ),
    );

    if (rich) {
      return ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: content,
        ),
      );
    }
    return content;
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
