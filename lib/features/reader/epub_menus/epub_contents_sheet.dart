import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/theme/glass_surface.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/reader_theme.dart';
import 'epub_menu_state.dart';

/// Contents, bookmarks and highlights of a native EPUB, in the same sheet
/// style as the web novel reader's contents.
class EpubContentsSheet extends StatefulWidget {
  final EpubMenuState state;
  final ReaderThemeConfig theme;
  final ValueChanged<int> onSelectToc;
  final ValueChanged<int> onSelectBookmark;
  final ValueChanged<int> onSelectHighlight;

  /// Deletes a highlight and returns the remaining ones.
  final Future<List<EpubHighlightEntry>> Function(int index) onDeleteHighlight;

  const EpubContentsSheet({
    super.key,
    required this.state,
    required this.theme,
    required this.onSelectToc,
    required this.onSelectBookmark,
    required this.onSelectHighlight,
    required this.onDeleteHighlight,
  });

  static Future<void> show(
    BuildContext context, {
    required EpubMenuState state,
    required ReaderThemeConfig theme,
    required ValueChanged<int> onSelectToc,
    required ValueChanged<int> onSelectBookmark,
    required ValueChanged<int> onSelectHighlight,
    required Future<List<EpubHighlightEntry>> Function(int index)
    onDeleteHighlight,
  }) {
    SemanticsService.announce('Contents opened', TextDirection.ltr);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => EpubContentsSheet(
        state: state,
        theme: theme,
        onSelectToc: onSelectToc,
        onSelectBookmark: onSelectBookmark,
        onSelectHighlight: onSelectHighlight,
        onDeleteHighlight: onDeleteHighlight,
      ),
    );
  }

  @override
  State<EpubContentsSheet> createState() => _EpubContentsSheetState();
}

class _EpubContentsSheetState extends State<EpubContentsSheet> {
  static const _rowHeight = 52.0;
  int _tab = 0;
  late List<EpubHighlightEntry> _highlights = widget.state.highlights;
  late final ScrollController _scroll = ScrollController(
    initialScrollOffset: widget.state.currentToc > 3
        ? (widget.state.currentToc - 3) * _rowHeight
        : 0,
  );

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  bool get _isDark => widget.theme.systemBrightness == Brightness.dark;

  @override
  Widget build(BuildContext context) {
    final cfg = widget.theme;
    final rich = GlassStyle.richOf(context);
    final background = rich
        ? cfg.uiControlsBackground.withValues(alpha: 0.82)
        : cfg.uiControlsBackground;
    final state = widget.state;
    // A Material, so list rows show their ink on the sheet colour.
    final content = Material(
      color: background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.88,
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: _isDark ? Colors.white24 : Colors.black26,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              child: Row(
                children: [
                  const SizedBox(width: 36),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          state.title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: cfg.textColor,
                          ),
                        ),
                        const SizedBox(height: 2),
                        if (state.chapterCount > 0)
                          Text(
                            'Chapter ${state.chapterIndex + 1} of ${state.chapterCount}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: cfg.secondaryTextColor,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Close contents',
                    child: GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFE5E5EA),
                        ),
                        child: Icon(
                          CupertinoIcons.checkmark,
                          size: 18,
                          color: cfg.textColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoSlidingSegmentedControl<int>(
                  groupValue: _tab,
                  backgroundColor: _isDark
                      ? const Color(0xFF2C2C2E)
                      : const Color(0xFFE5E5EA),
                  thumbColor: _isDark ? const Color(0xFF3A3A3C) : Colors.white,
                  onValueChanged: (tab) => setState(() => _tab = tab ?? 0),
                  children: {
                    for (final (index, label) in const [
                      (0, 'Contents'),
                      (1, 'Bookmarks'),
                      (2, 'Highlights'),
                    ])
                      index: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          label,
                          style: TextStyle(fontSize: 13, color: cfg.textColor),
                        ),
                      ),
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: _isDark ? Colors.white12 : Colors.black12,
            ),
            Expanded(
              child: switch (_tab) {
                0 => _contents(),
                1 => _bookmarks(),
                _ => _highlightList(),
              },
            ),
          ],
        ),
      ),
    );
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: rich
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: content,
            )
          : content,
    );
  }

  void _choose(ValueChanged<int> action, int index) {
    Navigator.of(context).pop();
    action(index);
  }

  Widget _contents() {
    final toc = widget.state.toc;
    if (toc.isEmpty) {
      return _empty('No Contents', 'This book has no table of contents.');
    }
    final cfg = widget.theme;
    return ListView.builder(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemExtent: _rowHeight,
      itemCount: toc.length,
      itemBuilder: (context, index) {
        final entry = toc[index];
        final current = index == widget.state.currentToc;
        return InkWell(
          onTap: () => _choose(widget.onSelectToc, index),
          child: Padding(
            padding: EdgeInsets.only(
              left: 20 + entry.depth.clamp(0, 4) * 16.0,
              right: 20,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: entry.depth == 0 ? 15 : 14,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                      color: current ? HonColors.accentOrange : cfg.textColor,
                    ),
                  ),
                ),
                if (current)
                  const Icon(
                    CupertinoIcons.book_fill,
                    size: 14,
                    color: HonColors.accentOrange,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _bookmarks() {
    final bookmarks = widget.state.bookmarks;
    if (bookmarks.isEmpty) {
      return _empty(
        'No Bookmarks',
        'Tap Bookmark in the reader menu to save your place.',
      );
    }
    final cfg = widget.theme;
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: bookmarks.length,
      separatorBuilder: (_, _) => _divider(),
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        final current = bookmark.chapterIndex == widget.state.chapterIndex;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Icon(
            CupertinoIcons.bookmark_fill,
            size: 18,
            color: current ? HonColors.accentOrange : cfg.secondaryTextColor,
          ),
          title: Text(
            bookmark.label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: current ? FontWeight.w700 : FontWeight.w500,
              color: current ? HonColors.accentOrange : cfg.textColor,
            ),
          ),
          subtitle: bookmark.chapterIndex == null
              ? null
              : Text(
                  'Chapter ${bookmark.chapterIndex! + 1}',
                  style: TextStyle(fontSize: 12, color: cfg.secondaryTextColor),
                ),
          onTap: () => _choose(widget.onSelectBookmark, index),
        );
      },
    );
  }

  Widget _highlightList() {
    if (_highlights.isEmpty) {
      return _empty(
        'No Highlights',
        'Select text while reading and tap Highlight to save passages and notes.',
      );
    }
    final cfg = widget.theme;
    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: _highlights.length,
      separatorBuilder: (_, _) => _divider(),
      itemBuilder: (context, index) {
        final highlight = _highlights[index];
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 4,
          ),
          leading: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: _highlightColor(highlight.color),
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            highlight.text,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              color: cfg.textColor,
            ),
          ),
          subtitle: highlight.note == null || highlight.note!.isEmpty
              ? null
              : Text(
                  highlight.note!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HonColors.accentOrange,
                  ),
                ),
          trailing: IconButton(
            tooltip: 'Delete highlight',
            icon: Icon(
              CupertinoIcons.trash,
              size: 18,
              color: cfg.secondaryTextColor,
            ),
            onPressed: () async {
              final remaining = await widget.onDeleteHighlight(index);
              if (mounted) setState(() => _highlights = remaining);
            },
          ),
          onTap: () => _choose(widget.onSelectHighlight, index),
        );
      },
    );
  }

  Widget _divider() => Divider(
    height: 1,
    color: _isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
  );

  static Color _highlightColor(String key) => switch (key) {
    'green' => const Color(0xFF34C759),
    'blue' => const Color(0xFF007AFF),
    'pink' => const Color(0xFFFF2D55),
    'purple' => const Color(0xFFAF52DE),
    'orange' => const Color(0xFFFF9500),
    _ => const Color(0xFFFFCC00),
  };

  Widget _empty(String title, String description) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: widget.theme.textColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: widget.theme.secondaryTextColor,
            ),
          ),
        ],
      ),
    ),
  );
}
