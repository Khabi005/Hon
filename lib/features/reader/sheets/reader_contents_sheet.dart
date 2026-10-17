import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../core/utils/epub_parser.dart';

import '../../../core/database/database_service.dart';
import '../../../core/models/bookmark.dart';

class ReaderContentsSheet extends StatefulWidget {
  final String? bookId;
  final String bookTitle;
  final int currentChapterIndex;
  final int totalChapters;
  final List<EpubChapterItem> chapters;
  final ValueChanged<int> onSelectChapter;

  const ReaderContentsSheet({
    super.key,
    this.bookId,
    required this.bookTitle,
    required this.currentChapterIndex,
    required this.totalChapters,
    required this.chapters,
    required this.onSelectChapter,
  });

  static Future<void> show(
    BuildContext context, {
    String? bookId,
    required String bookTitle,
    required int currentChapterIndex,
    required int totalChapters,
    required List<EpubChapterItem> chapters,
    required ValueChanged<int> onSelectChapter,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderContentsSheet(
        bookId: bookId,
        bookTitle: bookTitle,
        currentChapterIndex: currentChapterIndex,
        totalChapters: totalChapters,
        chapters: chapters,
        onSelectChapter: onSelectChapter,
      ),
    );
  }

  @override
  State<ReaderContentsSheet> createState() => _ReaderContentsSheetState();
}

class _ReaderContentsSheetState extends State<ReaderContentsSheet> {
  int _selectedTabIndex = 0; // 0: Chapters, 1: Bookmarks, 2: Highlights

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark ? Colors.white60 : Colors.black54;

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 8),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header: Title, Page count, and Checkmark Close Button (matching Apple Books reference)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const SizedBox(width: 36), // Balancer
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        widget.bookTitle,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Chapter ${widget.currentChapterIndex + 1} of ${widget.totalChapters > 0 ? widget.totalChapters : widget.chapters.length}',
                        style: TextStyle(
                          fontSize: 13,
                          color: subtextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // Circular Checkmark Button
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    ),
                    child: Icon(
                      CupertinoIcons.checkmark,
                      size: 18,
                      color: textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Segmented Control: Chapters | Bookmarks | Highlights
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 36,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _buildSegmentItem('Chapters', 0, isDark),
                  _buildSegmentItem('Bookmarks', 1, isDark),
                  _buildSegmentItem('Highlights', 2, isDark),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark ? Colors.white12 : Colors.black12,
          ),

          // Tab Content
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildChaptersList(textColor, subtextColor, isDark)
                : _selectedTabIndex == 1
                    ? _buildBookmarksTab(textColor, subtextColor, isDark)
                    : _buildEmptyTabState(
                        'No Highlights',
                        'Select text while reading to create notes and highlights.',
                        textColor,
                        subtextColor,
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(String title, int index, bool isDark) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTabIndex = index),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: isSelected
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark ? Colors.white60 : Colors.black54),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildChaptersList(Color textColor, Color subtextColor, bool isDark) {
    if (widget.chapters.isEmpty) {
      return Center(
        child: Text(
          'No chapters available.',
          style: TextStyle(color: subtextColor),
        ),
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: widget.chapters.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
      ),
      itemBuilder: (context, index) {
        final chapter = widget.chapters[index];
        final isCurrent = index == widget.currentChapterIndex;

        return InkWell(
          onTap: () {
            widget.onSelectChapter(index);
            Navigator.of(context).pop();
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    chapter.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent ? HonColors.accentOrange : textColor,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    color: isCurrent ? HonColors.accentOrange : subtextColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBookmarksTab(Color textColor, Color subtextColor, bool isDark) {
    final bookmarks = widget.bookId != null
        ? DatabaseService.instance.getBookmarks(widget.bookId!)
        : <Bookmark>[];

    if (bookmarks.isEmpty) {
      return _buildEmptyTabState(
        'No Bookmarks',
        'Tap the bookmark icon in the reading menu to save chapters and pages.',
        textColor,
        subtextColor,
      );
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: bookmarks.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
      ),
      itemBuilder: (context, index) {
        final bm = bookmarks[index];
        final chIdx = bm.chapterIndex ?? (bm.pageIndex > 0 ? bm.pageIndex - 1 : 0);
        final isCurrent = chIdx == widget.currentChapterIndex;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isCurrent
                  ? HonColors.accentOrange.withOpacity(0.15)
                  : (isDark ? Colors.white10 : Colors.black.withOpacity(0.04)),
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.bookmark_fill,
              size: 18,
              color: isCurrent ? HonColors.accentOrange : subtextColor,
            ),
          ),
          title: Text(
            bm.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
              color: isCurrent ? HonColors.accentOrange : textColor,
            ),
          ),
          subtitle: Text(
            'Chapter ${chIdx + 1}',
            style: TextStyle(fontSize: 12, color: subtextColor),
          ),
          trailing: IconButton(
            icon: Icon(
              CupertinoIcons.trash,
              size: 18,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            onPressed: () async {
              if (widget.bookId != null) {
                await DatabaseService.instance
                    .removeBookmark(widget.bookId!, bm.pageIndex);
                setState(() {});
              }
            },
          ),
          onTap: () {
            widget.onSelectChapter(chIdx);
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Widget _buildEmptyTabState(
    String title,
    String description,
    Color textColor,
    Color subtextColor,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: subtextColor,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
