import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/reader_theme.dart';

/// Common reader framing. EPUB's native equivalent follows the same placement,
/// spacing and labels while its publication remains in Readium.
class ReaderHeader extends StatelessWidget {
  final ReaderThemeConfig theme;
  final String location;
  final String status;
  final VoidCallback? onPrevious;
  final VoidCallback onClose;
  const ReaderHeader({
    super.key,
    required this.theme,
    required this.location,
    required this.status,
    this.onPrevious,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.paddingOf(context).top + 8,
      16,
      8,
    ),
    color: theme.backgroundColor.withValues(alpha: .96),
    child: Row(
      children: [
        SizedBox(
          width: 64,
          child: TextButton(
            onPressed: onPrevious,
            style: TextButton.styleFrom(
              foregroundColor: theme.secondaryTextColor,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(56, 44),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.arrow_counterclockwise, size: 14),
                const SizedBox(width: 4),
                Flexible(child: Text(location, maxLines: 1)),
              ],
            ),
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
}

class ReaderFooter extends StatelessWidget {
  final ReaderThemeConfig theme;
  final String progress;
  final VoidCallback? onProgress;
  final VoidCallback onMenu;
  const ReaderFooter({
    super.key,
    required this.theme,
    required this.progress,
    this.onProgress,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) => Container(
    color: theme.backgroundColor.withValues(alpha: .96),
    padding: EdgeInsets.fromLTRB(
      20,
      8,
      20,
      MediaQuery.paddingOf(context).bottom + 8,
    ),
    child: Row(
      children: [
        const SizedBox(width: 48),
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
