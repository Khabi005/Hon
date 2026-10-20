import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../core/utils/epub_parser.dart';

import '../../../core/database/database_service.dart';
import '../../../core/downloads/hon_download_manager.dart';
import '../../../core/models/bookmark.dart';
import '../../../core/models/chapter.dart';
import '../../../core/models/highlight.dart';

class ReaderContentsSheet extends StatefulWidget {
  final String? bookId;
  final String bookTitle;
  final ReaderThemeConfig? theme;
  final int currentChapterIndex;
  final int totalChapters;
  final List<EpubChapterItem> chapters;
  final ValueChanged<int> onSelectChapter;
  final ValueChanged<Highlight>? onSelectHighlight;
  final ValueChanged<Bookmark>? onSelectBookmark;

  const ReaderContentsSheet({
    super.key,
    this.theme,
    this.bookId,
    required this.bookTitle,
    required this.currentChapterIndex,
    required this.totalChapters,
    required this.chapters,
    required this.onSelectChapter,
    this.onSelectHighlight,
    this.onSelectBookmark,
  });

  static Future<void> show(
    BuildContext context, {
    ReaderThemeConfig? theme,
    String? bookId,
    required String bookTitle,
    required int currentChapterIndex,
    required int totalChapters,
    required List<EpubChapterItem> chapters,
    required ValueChanged<int> onSelectChapter,
    ValueChanged<Highlight>? onSelectHighlight,
    ValueChanged<Bookmark>? onSelectBookmark,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) => ReaderContentsSheet(
        theme: theme,
        bookId: bookId,
        bookTitle: bookTitle,
        currentChapterIndex: currentChapterIndex,
        totalChapters: totalChapters,
        chapters: chapters,
        onSelectChapter: onSelectChapter,
        onSelectHighlight: onSelectHighlight,
        onSelectBookmark: onSelectBookmark,
      ),
    );
  }

  @override
  State<ReaderContentsSheet> createState() => _ReaderContentsSheetState();
}

class _ReaderContentsSheetState extends State<ReaderContentsSheet> {
  int _selectedTabIndex = 0; // Chapters and bookmarks.
  late final ScrollController _chapterScrollController;

  @override
  void initState() {
    super.initState();
    final estimatedOffset =
        (widget.currentChapterIndex * 52.0 - 150.0).clamp(0.0, double.infinity);
    _chapterScrollController = ScrollController(
      initialScrollOffset: estimatedOffset,
    );
  }

  @override
  void dispose() {
    _chapterScrollController.dispose();
    super.dispose();
  }

  Future<void> _downloadNextInContents(int count) async {
    if (widget.bookId == null) return;
    final db = DatabaseService.instance;
    final book = db.getBookById(widget.bookId!);
    if (book == null) return;
    await db.ensureChaptersLoaded(book.id);
    final chapters = db.getChapters(book.id);
    final targets = chapters
        .skip(widget.currentChapterIndex)
        .where((c) => c.downloadState != ChapterDownloadState.downloaded)
        .take(count)
        .toList();
    if (targets.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No new chapters to download.')),
        );
      }
      return;
    }
    final queued = await HonDownloadManager.instance.queueChapters(book, targets);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued $queued chapters.')),
      );
      setState(() {});
    }
  }

  Future<void> _deleteReadDownloadsInContents() async {
    if (widget.bookId == null) return;
    final deleted = await DatabaseService.instance.deleteReadChapters(
      widget.bookId!,
      widget.currentChapterIndex.toDouble(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $deleted read chapter files.')),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark =
        widget.theme?.systemBrightness == Brightness.dark ||
        widget.theme == null && Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        widget.theme?.uiControlsBackground ??
        (isDark ? const Color(0xFF1C1C1E) : Colors.white);
    final textColor =
        widget.theme?.textColor ?? (isDark ? Colors.white : Colors.black);
    final subtextColor =
        widget.theme?.secondaryTextColor ??
        (isDark ? Colors.white60 : Colors.black54);

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
                if (widget.bookId != null)
                  PopupMenuButton<String>(
                    tooltip: 'Chapter options',
                    icon: Icon(
                      CupertinoIcons.ellipsis_circle,
                      size: 22,
                      color: textColor,
                    ),
                    onSelected: (value) async {
                      switch (value) {
                        case 'next5':
                          await _downloadNextInContents(5);
                          break;
                        case 'next10':
                          await _downloadNextInContents(10);
                          break;
                        case 'next25':
                          await _downloadNextInContents(25);
                          break;
                        case 'deleteRead':
                          await _deleteReadDownloadsInContents();
                          break;
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'next5',
                        child: Text('Download next 5'),
                      ),
                      const PopupMenuItem(
                        value: 'next10',
                        child: Text('Download next 10'),
                      ),
                      const PopupMenuItem(
                        value: 'next25',
                        child: Text('Download next 25'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'deleteRead',
                        child: Text('Delete read chapters'),
                      ),
                    ],
                  )
                else
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
                        style: TextStyle(fontSize: 13, color: subtextColor),
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
                      color: isDark
                          ? const Color(0xFF2C2C2E)
                          : const Color(0xFFE5E5EA),
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
                color: isDark
                    ? const Color(0xFF2C2C2E)
                    : const Color(0xFFE5E5EA),
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
          Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),

          // Tab Content
          Expanded(
            child: _selectedTabIndex == 0
                ? _buildChaptersList(textColor, subtextColor, isDark)
                : _selectedTabIndex == 1
                    ? _buildBookmarksTab(textColor, subtextColor, isDark)
                    : _buildHighlightsTab(textColor, subtextColor, isDark),
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
                    ),
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

    final dbChapters = widget.bookId != null
        ? DatabaseService.instance.getChapters(widget.bookId!)
        : <Chapter>[];
    final dbChapterMap = {
      for (final c in dbChapters) c.chapterIndex.toInt(): c,
    };

    return ListView.separated(
      controller: _chapterScrollController,
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
        final dbCh = dbChapterMap[index];
        final state = dbCh?.downloadState ?? ChapterDownloadState.notDownloaded;

        Widget? trailingStatus;
        if (widget.bookId != null && dbCh != null) {
          switch (state) {
            case ChapterDownloadState.downloaded:
              trailingStatus = const Icon(
                CupertinoIcons.checkmark_circle_fill,
                color: HonColors.accentGreen,
                size: 18,
              );
              break;
            case ChapterDownloadState.downloading:
              trailingStatus = const SizedBox(
                width: 18,
                height: 18,
                child: CupertinoActivityIndicator(radius: 8),
              );
              break;
            case ChapterDownloadState.queued:
              trailingStatus = Icon(
                CupertinoIcons.clock,
                color: subtextColor,
                size: 18,
              );
              break;
            case ChapterDownloadState.paused:
              trailingStatus = GestureDetector(
                onTap: () async {
                  await HonDownloadManager.instance.resumeDownload(dbCh.id);
                  if (mounted) setState(() {});
                },
                child: const Icon(
                  CupertinoIcons.pause_circle_fill,
                  color: HonColors.accentOrange,
                  size: 18,
                ),
              );
              break;
            case ChapterDownloadState.failed:
              trailingStatus = GestureDetector(
                onTap: () async {
                  await HonDownloadManager.instance.resumeDownload(dbCh.id);
                  if (mounted) setState(() {});
                },
                child: Icon(
                  CupertinoIcons.exclamationmark_circle_fill,
                  color: Theme.of(context).colorScheme.error,
                  size: 18,
                ),
              );
              break;
            case ChapterDownloadState.notDownloaded:
              trailingStatus = GestureDetector(
                onTap: () async {
                  final book =
                      DatabaseService.instance.getBookById(widget.bookId!);
                  if (book != null) {
                    await HonDownloadManager.instance
                        .queueChapters(book, [dbCh]);
                    if (mounted) setState(() {});
                  }
                },
                child: Icon(
                  CupertinoIcons.arrow_down_circle,
                  color: subtextColor,
                  size: 18,
                ),
              );
              break;
          }
        }

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
                if (trailingStatus != null) ...[
                  trailingStatus,
                  const SizedBox(width: 8),
                ],
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
        final chIdx =
            bm.chapterIndex ?? (bm.pageIndex > 0 ? bm.pageIndex - 1 : 0);
        final isCurrent = chIdx == widget.currentChapterIndex;

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 4,
          ),
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
                await DatabaseService.instance.removeBookmarkById(bm.id);
                setState(() {});
              }
            },
          ),
          onTap: () {
            if (widget.onSelectBookmark != null) {
              widget.onSelectBookmark!(bm);
            } else {
              widget.onSelectChapter(chIdx);
            }
            Navigator.of(context).pop();
          },
        );
      },
    );
  }

  Widget _buildHighlightsTab(Color textColor, Color subtextColor, bool isDark) {
    final highlights = widget.bookId != null
        ? DatabaseService.instance.getHighlights(widget.bookId!)
        : <Highlight>[];

    if (highlights.isEmpty) {
      return _buildEmptyTabState(
        'No Highlights',
        'Select text while reading and tap Highlight to save passages and notes.',
        textColor,
        subtextColor,
      );
    }

    Color colorFromKey(String key) {
      switch (key) {
        case 'green':
          return const Color(0xFF34C759);
        case 'blue':
          return const Color(0xFF007AFF);
        case 'pink':
          return const Color(0xFFFF2D55);
        case 'purple':
          return const Color(0xFFAF52DE);
        case 'yellow':
        default:
          return const Color(0xFFFFCC00);
      }
    }

    return ListView.separated(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: highlights.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
      ),
      itemBuilder: (context, index) {
        final hl = highlights[index];
        var chIdx = 0;
        try {
          final loc = jsonDecode(hl.locatorString) as Map<String, dynamic>;
          chIdx = (loc['chapterIndex'] as num?)?.toInt() ?? 0;
        } catch (_) {}

        final hlColor = colorFromKey(hl.color);

        return ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 6,
          ),
          leading: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: hlColor,
              shape: BoxShape.circle,
            ),
          ),
          title: Text(
            hl.selectedText,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: textColor,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hl.note != null && hl.note!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  hl.note!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: HonColors.accentOrange,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                'Chapter ${chIdx + 1}',
                style: TextStyle(fontSize: 12, color: subtextColor),
              ),
            ],
          ),
          trailing: IconButton(
            icon: Icon(
              CupertinoIcons.trash,
              size: 18,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
            onPressed: () async {
              await DatabaseService.instance.deleteHighlight(hl.id);
              if (mounted) setState(() {});
            },
          ),
          onTap: () {
            if (widget.onSelectHighlight != null) {
              widget.onSelectHighlight!(hl);
            } else {
              widget.onSelectChapter(chIdx);
            }
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
              style: TextStyle(fontSize: 13, color: subtextColor, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}
