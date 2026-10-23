import 'dart:convert';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/glass_surface.dart';
import '../../../core/utils/epub_parser.dart';

import '../../../core/database/database_service.dart';
import '../../../core/downloads/hon_download_manager.dart';
import '../../../core/downloads/chapter_action_coordinator.dart';
import '../../../core/models/bookmark.dart';
import '../../../core/models/chapter.dart';
import '../../../core/models/highlight.dart';
import '../../../core/utils/log_ignored.dart';

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
    SemanticsService.announce('Reader contents opened', TextDirection.ltr);
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
  bool _isSelectionMode = false;
  final Set<String> _selectedChapterIds = <String>{};
  final GlobalKey _currentChapterKey = GlobalKey();
  final Set<int> _mountedChapterIndices = <int>{};
  final Map<int, double> _measuredItemHeights = <int, double>{};

  void _jumpToCurrentChapter({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final immediateCtx = _currentChapterKey.currentContext;
      if (immediateCtx != null) {
        Scrollable.ensureVisible(
          immediateCtx,
          alignment: 0.5,
          duration: animate ? const Duration(milliseconds: 300) : Duration.zero,
          curve: Curves.easeOutCubic,
        );
        return;
      }

      if (!_chapterScrollController.hasClients) return;
      if (widget.currentChapterIndex < 0 || widget.currentChapterIndex >= widget.chapters.length) return;
      final targetIndex = widget.currentChapterIndex;

      for (int iteration = 0; iteration < 6; iteration++) {
        if (!mounted) return;
        final ctx = _currentChapterKey.currentContext;
        if (ctx != null && ctx.mounted) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.5,
            duration: animate && iteration == 0 ? const Duration(milliseconds: 300) : Duration.zero,
            curve: Curves.easeOutCubic,
          );
          return;
        }

        final currentOffset = _chapterScrollController.offset;
        final viewport = _chapterScrollController.position.viewportDimension;
        final maxScroll = _chapterScrollController.position.maxScrollExtent;
        final avgHeight = _measuredItemHeights.isNotEmpty
            ? (_measuredItemHeights.values.reduce((a, b) => a + b) / _measuredItemHeights.length)
            : 56.0;

        double nextOffset;
        if (_mountedChapterIndices.isNotEmpty) {
          final minMounted = _mountedChapterIndices.reduce((a, b) => a < b ? a : b);
          final maxMounted = _mountedChapterIndices.reduce((a, b) => a > b ? a : b);

          if (targetIndex < minMounted) {
            final delta = minMounted - targetIndex;
            nextOffset = (currentOffset - (delta * avgHeight) - (viewport / 2)).clamp(0.0, maxScroll);
          } else if (targetIndex > maxMounted) {
            final delta = targetIndex - maxMounted;
            nextOffset = (currentOffset + (delta * avgHeight) + (viewport / 2)).clamp(0.0, maxScroll);
          } else {
            nextOffset = (currentOffset + ((targetIndex - minMounted) * avgHeight) - (viewport / 2)).clamp(0.0, maxScroll);
          }
        } else {
          nextOffset = (8.0 + targetIndex * avgHeight - (viewport / 2)).clamp(0.0, maxScroll);
        }

        if ((nextOffset - currentOffset).abs() > 4.0) {
          if (animate && iteration == 0) {
            await _chapterScrollController.animateTo(
              nextOffset,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOutCubic,
            );
          } else {
            _chapterScrollController.jumpTo(nextOffset);
          }
        }

        await WidgetsBinding.instance.endOfFrame;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }

      if (mounted) {
        final finalCtx = _currentChapterKey.currentContext;
        if (finalCtx != null && finalCtx.mounted) {
          Scrollable.ensureVisible(finalCtx, alignment: 0.5, duration: Duration.zero);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    DatabaseService.instance.addListener(_onDatabaseChanged);
    _chapterScrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _jumpToCurrentChapter(animate: false);
    });
  }

  void _onDatabaseChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    DatabaseService.instance.removeListener(_onDatabaseChanged);
    _chapterScrollController.dispose();
    super.dispose();
  }

  Future<void> _downloadNextInContents(int count) async {
    if (widget.bookId == null) return;
    final db = DatabaseService.instance;
    final book = db.getBookById(widget.bookId!);
    if (book == null) return;
    await ChapterActionCoordinator.instance.downloadNextN(
      context,
      book: book,
      count: count,
      currentReadingIndex: widget.currentChapterIndex,
    );
  }

  Future<void> _downloadCustomInContents() async {
    if (widget.bookId == null) return;
    final db = DatabaseService.instance;
    final book = db.getBookById(widget.bookId!);
    if (book == null) return;
    await ChapterActionCoordinator.instance.promptDownloadCustomN(
      context,
      book: book,
      currentReadingIndex: widget.currentChapterIndex,
    );
  }

  Future<void> _deleteReadDownloadsInContents() async {
    if (widget.bookId == null) return;
    final db = DatabaseService.instance;
    final book = db.getBookById(widget.bookId!);
    if (book == null) return;
    await ChapterActionCoordinator.instance.promptDeleteRead(
      context,
      book: book,
      currentChapterIndex: widget.currentChapterIndex.toDouble(),
    );
  }

  Future<void> _deleteUnreadDownloadsInContents() async {
    if (widget.bookId == null) return;
    final db = DatabaseService.instance;
    final book = db.getBookById(widget.bookId!);
    if (book == null) return;
    await ChapterActionCoordinator.instance.promptDeleteUnread(
      context,
      book: book,
      currentChapterIndex: widget.currentChapterIndex.toDouble(),
    );
  }

  Future<void> _deleteAllDownloadsInContents() async {
    if (widget.bookId == null) return;
    final db = DatabaseService.instance;
    final book = db.getBookById(widget.bookId!);
    if (book == null) return;
    await ChapterActionCoordinator.instance.promptDeleteAll(
      context,
      book: book,
    );
  }

  Future<void> _downloadSelectedInContents() async {
    if (widget.bookId == null || _selectedChapterIds.isEmpty) return;
    final db = DatabaseService.instance;
    final book = db.getBookById(widget.bookId!);
    if (book == null) return;
    await db.ensureChaptersLoaded(book.id);
    final chapters = db.getChapters(book.id).where((c) => _selectedChapterIds.contains(c.id));
    if (!mounted) return;
    await ChapterActionCoordinator.instance.downloadChapters(context, book: book, chapters: chapters);
    if (mounted) setState(() => _isSelectionMode = false);
  }

  Future<void> _deleteSelectedInContents() async {
    if (widget.bookId == null || _selectedChapterIds.isEmpty) return;
    final db = DatabaseService.instance;
    final book = db.getBookById(widget.bookId!);
    if (book == null) return;
    await db.ensureChaptersLoaded(book.id);
    final chapters = db.getChapters(book.id).where((c) => _selectedChapterIds.contains(c.id));
    if (!mounted) return;
    final res = await ChapterActionCoordinator.instance.promptDeleteChapters(context, book: book, chapters: chapters);
    if (res != null && mounted) {
      setState(() {
        _selectedChapterIds.clear();
        _isSelectionMode = false;
      });
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
    final rich = GlassStyle.richOf(context);
    final sheetBg = rich ? bgColor.withValues(alpha: 0.82) : bgColor;

    final sheetContent = Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: sheetBg,
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
                        case 'next15':
                          await _downloadNextInContents(15);
                          break;
                        case 'next25':
                          await _downloadNextInContents(25);
                          break;
                        case 'custom':
                          await _downloadCustomInContents();
                          break;
                        case 'select':
                          setState(() => _isSelectionMode = true);
                          break;
                        case 'deleteRead':
                          await _deleteReadDownloadsInContents();
                          break;
                        case 'deleteUnread':
                          await _deleteUnreadDownloadsInContents();
                          break;
                        case 'deleteAll':
                          await _deleteAllDownloadsInContents();
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
                        value: 'next15',
                        child: Text('Download next 15'),
                      ),
                      const PopupMenuItem(
                        value: 'next25',
                        child: Text('Download next 25'),
                      ),
                      const PopupMenuItem(
                        value: 'custom',
                        child: Text('Download custom count...'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'select',
                        child: Text('Select chapters...'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(
                        value: 'deleteRead',
                        child: Text('Delete read chapters'),
                      ),
                      const PopupMenuItem(
                        value: 'deleteUnread',
                        child: Text('Delete unread chapters'),
                      ),
                      const PopupMenuItem(
                        value: 'deleteAll',
                        child: Text('Delete all offline files'),
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
                      InkWell(
                        onTap: () => _jumpToCurrentChapter(),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Chapter ${widget.currentChapterIndex + 1} of ${widget.totalChapters > 0 ? widget.totalChapters : widget.chapters.length}',
                                style: TextStyle(fontSize: 13, color: subtextColor),
                              ),
                              const SizedBox(width: 4),
                              Icon(CupertinoIcons.location, size: 12, color: subtextColor),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Jump to current chapter',
                  icon: const Icon(CupertinoIcons.location, size: 20),
                  onPressed: () => _jumpToCurrentChapter(),
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

    if (rich) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: sheetContent,
        ),
      );
    }
    return sheetContent;
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

    final listWidget = ListView.separated(
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
        final dbCh = (index < dbChapters.length) ? dbChapters[index] : dbChapterMap[index];
        final chId = dbCh?.id ?? 'ch_$index';
        final isSelected = _selectedChapterIds.contains(chId);
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
                  await HonDownloadManager.instance.resumeDownloadForChapter(widget.bookId!, dbCh.id);
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
                  await HonDownloadManager.instance.resumeDownloadForChapter(widget.bookId!, dbCh.id);
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
                    await ChapterActionCoordinator.instance
                        .downloadChapters(context, book: book, chapters: [dbCh]);
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

        return _TrackedChapterItem(
          key: ValueKey(chId),
          displayIndex: index,
          onMount: (idx) => _mountedChapterIndices.add(idx),
          onUnmount: (idx) => _mountedChapterIndices.remove(idx),
          onMeasured: (idx, height) => _measuredItemHeights[idx] = height,
          child: InkWell(
            key: isCurrent ? _currentChapterKey : null,
            onTap: () {
              if (_isSelectionMode) {
                setState(() {
                  if (_selectedChapterIds.contains(chId)) {
                    _selectedChapterIds.remove(chId);
                  } else {
                    _selectedChapterIds.add(chId);
                  }
                });
                return;
              }
              widget.onSelectChapter(index);
              Navigator.of(context).pop();
            },
            onLongPress: () {
              if (!_isSelectionMode && widget.bookId != null) {
                setState(() {
                  _isSelectionMode = true;
                  _selectedChapterIds.add(chId);
                });
              }
            },
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
              child: Row(
                children: [
                  if (_isSelectionMode) ...[
                    Icon(
                      isSelected
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      color: isSelected ? HonColors.accentOrange : subtextColor,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                  ],
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
          ),
        );
      },
    );

    if (!_isSelectionMode) {
      return listWidget;
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
            border: Border(
              bottom: BorderSide(
                color: isDark ? Colors.white12 : Colors.black12,
              ),
            ),
          ),
          child: Row(
            children: [
              Text(
                '${_selectedChapterIds.length} selected',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: textColor,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_selectedChapterIds.length == dbChapters.length) {
                      _selectedChapterIds.clear();
                    } else {
                      _selectedChapterIds.addAll(dbChapters.map((c) => c.id));
                    }
                  });
                },
                child: Text(_selectedChapterIds.length == dbChapters.length ? 'Clear' : 'Select All'),
              ),
              IconButton(
                tooltip: 'Download selected',
                icon: const Icon(CupertinoIcons.arrow_down_circle, size: 20),
                onPressed: _selectedChapterIds.isEmpty ? null : _downloadSelectedInContents,
              ),
              IconButton(
                tooltip: 'Delete downloaded',
                icon: const Icon(CupertinoIcons.trash, size: 20),
                onPressed: _selectedChapterIds.isEmpty ? null : _deleteSelectedInContents,
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedChapterIds.clear();
                  });
                },
                child: const Text('Done'),
              ),
            ],
          ),
        ),
        Expanded(child: listWidget),
      ],
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
            tooltip: 'Delete bookmark',
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
        } catch (e) {
          logIgnored(e, 'reader_contents_sheet');
        }

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
            tooltip: 'Delete highlight',
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

class _TrackedChapterItem extends StatefulWidget {
  final int displayIndex;
  final ValueChanged<int> onMount;
  final ValueChanged<int> onUnmount;
  final void Function(int displayIndex, double height)? onMeasured;
  final Widget child;

  const _TrackedChapterItem({
    super.key,
    required this.displayIndex,
    required this.onMount,
    required this.onUnmount,
    this.onMeasured,
    required this.child,
  });

  @override
  State<_TrackedChapterItem> createState() => _TrackedChapterItemState();
}

class _TrackedChapterItemState extends State<_TrackedChapterItem> {
  @override
  void initState() {
    super.initState();
    widget.onMount(widget.displayIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final h = context.size?.height;
        if (h != null && h > 0) {
          widget.onMeasured?.call(widget.displayIndex, h);
        }
      }
    });
  }

  @override
  void didUpdateWidget(_TrackedChapterItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.displayIndex != widget.displayIndex) {
      widget.onUnmount(oldWidget.displayIndex);
      widget.onMount(widget.displayIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          final h = context.size?.height;
          if (h != null && h > 0) {
            widget.onMeasured?.call(widget.displayIndex, h);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    widget.onUnmount(widget.displayIndex);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
