import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../core/database/database_service.dart';
import '../../../core/sources/source_registry.dart';
import '../../../core/models/book.dart';
import '../../../core/models/reading_progress.dart';
import '../../../core/models/highlight.dart';
import '../../../core/models/bookmark.dart';
import '../../../core/utils/epub_parser.dart';
import '../../../shared/widgets/ornate_divider.dart';
import 'reader_document.dart';
import '../sheets/reader_contents_sheet.dart';
import '../sheets/reader_menu_popup.dart';
import '../widgets/reader_chrome.dart';
import '../sheets/themes_settings_sheet.dart';
import '../sheets/reader_search_dialog.dart';
import '../../../core/models/novel_source.dart';
import '../../../core/sources/chapter_content_sanitizer.dart';
import '../../browse/presentation/source_catalog_screen.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  final bool restoreSavedProgress;
  final int initialChapterIndex;
  final int initialPageIndex;
  final double? initialScrollOffset;
  final String? initialLocator;
  final String? initialChapterContent;
  final bool fromCatalogue;

  const ReaderScreen({
    super.key,
    required this.book,
    this.restoreSavedProgress = true,
    this.initialChapterIndex = 0,
    this.initialPageIndex = 0,
    this.initialScrollOffset,
    this.initialLocator,
    this.initialChapterContent,
    this.fromCatalogue = false,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

enum ChapterLoadResult { refreshedOnline, offlineFallback, skipped, failed }

class _ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  bool _showControls = true;
  bool _isLoading = true;
  String? _errorMessage;

  List<EpubChapterItem> _chapters = [];
  int _scrollBaseIndex = 0;
  final Map<int, GlobalKey> _chapterKeys = {};
  bool _prependingChapter = false;
  int _currentChapterIndex = 0;
  int _currentPageIndex = 0;
  int _chapterPageCount = 1;
  bool _changingPagedChapter = false;
  bool _pendingPagedEnd = false;
  Offset? _pageSwipeStart;
  double? _pageSwipeStartPage;
  int _totalPages = 1;
  bool _isBookmarked = false;
  bool _isOrientationLocked = false;
  String? _selectedQuote;
  final Map<int, String> _chapterFiles = {};
  final Map<int, ReaderDocument> _documents = {};
  double? _appliedBrightness;
  final Set<int> _loadingChapters = {};
  final Map<int, String> _chapterErrors = {};

  Future<ChapterLoadResult> _ensureChapterContent(
    int index, {
    bool force = false,
  }) async {
    if (_loadingChapters.contains(index)) {
      return ChapterLoadResult.skipped;
    }
    if (!force && _chapters[index].htmlContent.isNotEmpty) {
      return ChapterLoadResult.skipped;
    }
    _loadingChapters.add(index);
    bool usedOfflineFallback = false;
    try {
      String content;
      final path = _chapterFiles[index];
      if (force && widget.book.sourceId != null) {
        // When forcing a reload, fetch fresh passage from source for in-memory reader display.
        // Crucial: keep reload memory-only! Never overwrite the offline downloaded file directly,
        // which could strip local downloaded illustrations, bypass download locks, or race workers.
        try {
          content = await SourceRegistry.instance.getChapterPassage(
            widget.book.sourceId!,
            _chapters[index].contentHref,
          );
        } catch (_) {
          // If source fetch fails on reload but a local file exists, fall back to reading the file
          if (path != null && await File(path).exists()) {
            content = await File(path).readAsString();
            usedOfflineFallback = true;
          } else {
            rethrow;
          }
        }
      } else if (path != null && await File(path).exists()) {
        content = await File(path).readAsString();
        usedOfflineFallback = true;
      } else if (widget.book.sourceId != null) {
        content = await SourceRegistry.instance.getChapterPassage(
          widget.book.sourceId!,
          _chapters[index].contentHref,
        );
      } else {
        throw const FileSystemException(
          'This chapter is not saved on this device.',
        );
      }
      if (content.trim().isEmpty) {
        throw const FormatException('The source returned an empty chapter.');
      }
      content = ChapterContentSanitizer.sanitize(
        content,
        chapterTitle: _chapters[index].title,
      );
      if (!mounted) return ChapterLoadResult.skipped;
      final chapter = _chapters[index];
      final document = await ReaderDocument.parseAsync(
        content,
        title: chapter.title,
        baseUrl: chapter.contentHref,
      );
      if (!mounted) return ChapterLoadResult.skipped;
      setState(() {
        _chapters[index] = EpubChapterItem(
          id: chapter.id,
          title: chapter.title,
          contentHref: chapter.contentHref,
          htmlContent: content,
        );
        _documents[index] = document;
        _chapterErrors.remove(index);
        _layoutSignature = null;
      });
      if (index == _currentChapterIndex) _resumeReadingSession();
      return usedOfflineFallback
          ? ChapterLoadResult.offlineFallback
          : ChapterLoadResult.refreshedOnline;
    } catch (error) {
      if (mounted) {
        // Only show error in state if chapter had no prior content loaded,
        // preserving readable chapter content if reload fails.
        if (_chapters[index].htmlContent.isEmpty) {
          setState(
            () => _chapterErrors[index] = 'Could not load this chapter. $error',
          );
        }
      }
      if (force) rethrow;
      return ChapterLoadResult.failed;
    } finally {
      if (mounted) {
        setState(() {
          _loadingChapters.remove(index);
        });
      } else {
        _loadingChapters.remove(index);
      }
    }
  }

  Widget _missingChapter(int index, ReaderThemeConfig theme) {
    if (!_loadingChapters.contains(index) &&
        !_chapterErrors.containsKey(index)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _ensureChapterContent(index);
      });
    }
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _chapters[index].title,
            style: TextStyle(color: theme.textColor),
          ),
          const SizedBox(height: 16),
          if (_chapterErrors[index] == null)
            const CupertinoActivityIndicator()
          else
            Text(
              _chapterErrors[index]!,
              style: TextStyle(color: theme.textColor),
            ),
          TextButton(
            onPressed: () {
              setState(() => _chapterErrors.remove(index));
              _ensureChapterContent(index);
            },
            child: const Text('Retry loading chapter'),
          ),
        ],
      ),
    );
  }

  final Map<String, GlobalKey> _blockKeys = {};
  final Map<String, TapGestureRecognizer> _linkRecognizers = {};
  ReaderTextAnchor _anchor = const ReaderTextAnchor(0);
  List<List<ReaderFragment>> _pagedPages = [];
  String? _layoutSignature;
  bool _hasAnchor = false;
  bool _restoringAnchor = false;

  ReaderDocument _document(int chapter) => _documents.putIfAbsent(
    chapter,
    () => ReaderDocument.parse(
      _chapters[chapter].htmlContent,
      title: _chapters[chapter].title,
      baseUrl: _chapters[chapter].contentHref,
    ),
  );

  void _captureAnchor() {
    if (_chapters.isEmpty || _restoringAnchor) return;
    if (_scrollController.hasClients) {
      _updateVisibleChapter();
      final top = MediaQuery.of(context).padding.top + 68.0;
      final blocks = _document(_currentChapterIndex).blocks;
      for (var i = 0; i < blocks.length; i++) {
        final render = _blockKeys['$_currentChapterIndex:$i']?.currentContext
            ?.findRenderObject();
        if (render is! RenderBox || !render.hasSize) continue;
        final y = render.localToGlobal(Offset.zero).dy;
        if (y + render.size.height <= top) continue;
        final offset = render is RenderParagraph && y < top
            ? render.getPositionForOffset(Offset(0, top - y)).offset
            : 0;
        _anchor = ReaderTextAnchor(i, offset);
        _hasAnchor = true;
        break;
      }
    } else if (_pagedPages.isNotEmpty) {
      final page =
          _pagedPages[_currentPageIndex.clamp(0, _pagedPages.length - 1)];
      if (page.isNotEmpty) {
        _anchor = ReaderTextAnchor(page.first.block, page.first.start);
        _hasAnchor = true;
      }
    }
  }

  void _restoreScrollAnchor() {
    if (!_hasAnchor || !_scrollController.hasClients || !mounted) return;
    final render = _blockKeys['$_currentChapterIndex:${_anchor.block}']
        ?.currentContext
        ?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return;
    final caret = render is RenderParagraph
        ? render
              .getOffsetForCaret(
                TextPosition(
                  offset: _anchor.offset.clamp(
                    0,
                    render.text.toPlainText().length,
                  ),
                ),
                Rect.zero,
              )
              .dy
        : 0.0;
    final top = MediaQuery.of(context).padding.top + 68.0;
    final delta = render.localToGlobal(Offset.zero).dy + caret - top;
    _restoringAnchor = true;
    _scrollController.jumpTo(
      (_scrollController.offset + delta).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      ),
    );
    _restoringAnchor = false;
  }

  @override
  void didChangeMetrics() {
    if (!mounted || _chapters.isEmpty) return;
    _captureAnchor();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _restoreScrollAnchor();
    });
  }

  Color _highlightColor(String key) {
    switch (key.toLowerCase()) {
      case 'green':
        return const Color(0x7334C759);
      case 'blue':
        return const Color(0x73007AFF);
      case 'pink':
        return const Color(0x73FF2D55);
      case 'purple':
        return const Color(0x73AF52DE);
      case 'yellow':
      default:
        return const Color(0x80FFD60A);
    }
  }

  Widget _blockWidget(
    int chapter,
    int index,
    ReaderPreferencesState prefs, {
    int start = 0,
    int? end,
    double? imageHeight,
    bool track = false,
  }) {
    final block = _document(chapter).blocks[index];
    if (block.divider) {
      return OrnateDivider(
        color: prefs.themeConfig.ornamentColor,
        width: 120,
        height: 24,
      );
    }
    if (block.image != null) {
      return SizedBox(
        key: track
            ? _blockKeys.putIfAbsent('$chapter:$index', GlobalKey.new)
            : null,
        height: imageHeight ?? 220,
        child: readerImage(block.image!, block.alt, height: imageHeight ?? 220),
      );
    }

    final allHighlights = DatabaseService.instance.getHighlights(
      widget.book.id,
    );
    final blockHighlights = <HighlightSpan>[];
    final blockNotes = <Highlight>[];
    for (final h in allHighlights) {
      try {
        final loc = jsonDecode(h.locatorString) as Map<String, dynamic>;
        final ch = (loc['chapterIndex'] as num?)?.toInt();
        final blk = (loc['block'] as num?)?.toInt();
        if (ch == chapter) {
          if (blk == index) {
            final s =
                (loc['startOffset'] as num?)?.toInt() ??
                (loc['offset'] as num?)?.toInt() ??
                0;
            final e = (loc['endOffset'] as num?)?.toInt() ?? block.text.length;
            blockHighlights.add(
              HighlightSpan(
                start: s,
                end: e,
                color: _highlightColor(h.color),
                note: h.note,
              ),
            );
            if (h.note != null &&
                h.note!.trim().isNotEmpty &&
                !blockNotes.contains(h)) {
              blockNotes.add(h);
            }
          } else if (loc['spans'] is List) {
            for (final spanItem in loc['spans'] as List) {
              if (spanItem is Map &&
                  (spanItem['block'] as num?)?.toInt() == index) {
                final s = (spanItem['startOffset'] as num?)?.toInt() ?? 0;
                final e =
                    (spanItem['endOffset'] as num?)?.toInt() ??
                    block.text.length;
                blockHighlights.add(
                  HighlightSpan(
                    start: s,
                    end: e,
                    color: _highlightColor(h.color),
                    note: h.note,
                  ),
                );
                if (h.note != null &&
                    h.note!.trim().isNotEmpty &&
                    !blockNotes.contains(h)) {
                  blockNotes.add(h);
                }
              }
            }
          }
        }
      } catch (_) {}
    }

    final richText = Builder(
      builder: (context) => RichText(
        selectionRegistrar: SelectionContainer.maybeOf(context),
        selectionColor: prefs.themeConfig.textColor.withValues(alpha: 0.25),
        key: track
            ? _blockKeys.putIfAbsent('$chapter:$index', GlobalKey.new)
            : null,
        textScaler: MediaQuery.textScalerOf(context),
        textAlign: block.heading
            ? TextAlign.center
            : prefs.isJustified && !block.preformatted
            ? TextAlign.justify
            : TextAlign.start,
        text: TextSpan(
          style: block.style(prefs),
          children: [
            block.span(
              start: start,
              end: end,
              highlights: blockHighlights,
              link: (url) => _linkRecognizers.putIfAbsent(
                url,
                () => TapGestureRecognizer()
                  ..onTap = () async {
                    if (Platform.isAndroid) {
                      try {
                        await const MethodChannel(
                          'com.hon.reader/readium_reader',
                        ).invokeMethod('openLink', {'url': url});
                      } on PlatformException catch (_) {
                        /* Unsupported links stay in the reader. */
                      }
                    }
                  },
              ),
            ),
          ],
        ),
      ),
    );
    final selectableRichText = SelectionListener(
      selectionNotifier: _selectionNotifierFor(chapter, index),
      child: richText,
    );

    final contentWidget = block.heading
        ? Padding(
            padding: const EdgeInsets.only(top: 28, bottom: 18),
            child: selectableRichText,
          )
        : selectableRichText;

    if (blockNotes.isEmpty) return contentWidget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        contentWidget,
        for (final noteHl in blockNotes)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 2),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _highlightColor(noteHl.color).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border(
                  left: BorderSide(
                    color: _highlightColor(noteHl.color),
                    width: 3,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    CupertinoIcons.pencil,
                    size: 13,
                    color: prefs.themeConfig.secondaryTextColor,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      noteHl.note!,
                      style: TextStyle(
                        fontSize: math.max(12.0, prefs.fontSize * 0.8),
                        fontStyle: FontStyle.italic,
                        color: prefs.themeConfig.textColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  late PageController _pageController;
  late ScrollController _scrollController;
  Timer? _saveDebounceTimer;
  DateTime? _sessionStartTime;
  bool _isForegrounded = true;
  late ReaderPreferencesNotifier _prefsNotifier;
  final Map<String, SelectionListenerNotifier> _selectionNotifiers = {};

  SelectionListenerNotifier _selectionNotifierFor(int chapter, int block) {
    return _selectionNotifiers.putIfAbsent(
      '$chapter:$block',
      () => SelectionListenerNotifier(),
    );
  }

  @override
  void initState() {
    super.initState();
    _prefsNotifier = ref.read(readerPreferencesProvider.notifier);
    _prefsNotifier.setActiveBookId(widget.book.id);
    final bookOverrides = DatabaseService.instance.getBookReaderSettings(
      widget.book.id,
    );
    if (bookOverrides != null) {
      _prefsNotifier.loadFromState(
        ReaderPreferencesState.fromMap(bookOverrides),
        bookId: widget.book.id,
      );
    } else {
      _prefsNotifier.reloadDefaults(preserveBookId: widget.book.id);
    }
    WidgetsBinding.instance.addObserver(this);
    // Do NOT start timer during loading! Timer starts once content is parsed, readable, AND foregrounded.
    _sessionStartTime = null;
    _currentChapterIndex = widget.initialChapterIndex;
    _currentPageIndex = widget.initialPageIndex;
    _scrollBaseIndex = _currentChapterIndex;
    _pageController = PageController(initialPage: _currentPageIndex + 1);
    _scrollController = ScrollController();

    _scrollController.addListener(_onScroll);
    _loadBookContent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _isForegrounded = false;
      _captureAnchor();
      _saveProgress();
      _pauseReadingSession();
    } else if (state == AppLifecycleState.resumed) {
      _isForegrounded = true;
      _resumeReadingSession();
    }
  }

  void _pauseReadingSession() {
    if (_sessionStartTime != null) {
      final elapsed = DateTime.now().difference(_sessionStartTime!).inSeconds;
      if (elapsed > 0) {
        DatabaseService.instance.addReadingTime(elapsed);
      }
      _sessionStartTime =
          null; // Crucial: STOP timer so background time is never counted!
    }
  }

  void _resumeReadingSession() {
    // Only restart timer if reader has valid, readable content in foreground
    if (_sessionStartTime == null &&
        !_isLoading &&
        _errorMessage == null &&
        _isForegrounded &&
        _chapters.isNotEmpty &&
        _chapters[_currentChapterIndex].htmlContent.isNotEmpty) {
      _sessionStartTime = DateTime.now();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pauseReadingSession();
    _sessionStartTime = null;
    _saveDebounceTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    for (final recognizer in _linkRecognizers.values) {
      recognizer.dispose();
    }
    _pageController.dispose();
    if (Platform.isAndroid) {
      const MethodChannel(
        'com.hon.reader/readium_reader',
      ).invokeMethod('setBrightness', {'brightness': -1.0});
    }
    if (_isOrientationLocked) {
      SystemChrome.setPreferredOrientations(const []);
    }
    _prefsNotifier.setActiveBookId(null);
    _prefsNotifier.reloadDefaults();
    for (final notifier in _selectionNotifiers.values) {
      notifier.dispose();
    }
    _selectionNotifiers.clear();
    super.dispose();
  }

  Future<void> _shareSelectedQuote() async {
    final selected = _selectedQuote?.trim();
    if (selected == null || selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a passage first, then share it.')),
      );
      return;
    }
    final author = widget.book.author.trim();
    final attribution = [
      if (author.isNotEmpty && author != '---' && author != 'Unknown Author')
        author,
      widget.book.title,
    ].join(', ');
    await SystemChannels.platform.invokeMethod<void>(
      'Share.invoke',
      '“$selected”\n— $attribution',
    );
  }

  Widget _selectableContent(Widget child) => SelectionArea(
    onSelectionChanged: (selection) => _selectedQuote = selection?.plainText,
    contextMenuBuilder: (context, region) =>
        AdaptiveTextSelectionToolbar.buttonItems(
          anchors: region.contextMenuAnchors,
          buttonItems: [
            ContextMenuButtonItem(
              label: 'Highlight',
              onPressed: () {
                region.hideToolbar();
                _highlightSelectedText();
              },
            ),
            ContextMenuButtonItem(
              label: 'Add Note',
              onPressed: () {
                region.hideToolbar();
                _addNoteToSelection();
              },
            ),
            ...region.contextMenuButtonItems.where(
              (item) => item.type != ContextMenuButtonType.share,
            ),
            ContextMenuButtonItem(
              label: 'Share Quote',
              onPressed: () {
                region.hideToolbar();
                _shareSelectedQuote();
              },
            ),
          ],
        ),
    child: child,
  );

  Future<void> _highlightSelectedText([
    String color = 'yellow',
    String? note,
  ]) async {
    final text = _selectedQuote?.trim();
    if (text == null || text.isEmpty) return;

    final doc = _document(_currentChapterIndex);
    final blocks = doc.blocks;

    int foundBlock = -1;
    int foundStart = -1;
    int foundEnd = -1;
    List<Map<String, int>>? multiSpans;
    String actualSelectedText = text;

    // 0. Primary: Capture the real selection directly from SelectionListenerNotifiers
    final activeSelections = <({int block, int start, int end, String text})>[];
    for (int i = 0; i < blocks.length; i++) {
      final notifier = _selectionNotifiers['$_currentChapterIndex:$i'];
      if (notifier != null && notifier.registered) {
        try {
          final range = notifier.selection.range;
          if (range != null) {
            final startOffset = math.min(range.startOffset, range.endOffset);
            final endOffset = math.max(range.startOffset, range.endOffset);
            if (endOffset > startOffset) {
              final bText = blocks[i].text;
              final s = startOffset.clamp(0, bText.length);
              final e = endOffset.clamp(0, bText.length);
              if (e > s) {
                activeSelections.add((
                  block: i,
                  start: s,
                  end: e,
                  text: bText.substring(s, e),
                ));
              }
            }
          }
        } catch (_) {}
      }
    }

    if (activeSelections.isNotEmpty) {
      foundBlock = activeSelections.first.block;
      foundStart = activeSelections.first.start;
      foundEnd = activeSelections.first.end;
      if (activeSelections.length > 1) {
        multiSpans = activeSelections
            .map(
              (s) => {
                'block': s.block,
                'startOffset': s.start,
                'endOffset': s.end,
              },
            )
            .toList();
        actualSelectedText = activeSelections.map((s) => s.text).join('\n\n');
      } else {
        actualSelectedText = activeSelections.first.text;
      }
    }

    // Fallback: Gather currently visible block indices to prevent selecting repeated text elsewhere
    if (foundBlock == -1) {
      final visibleBlockIndices = <int>[];
      if (_pagedPages.isNotEmpty && _currentPageIndex < _pagedPages.length) {
        visibleBlockIndices.addAll(
          _pagedPages[_currentPageIndex].map((f) => f.block).toSet(),
        );
      } else {
        _captureAnchor();
        for (
          int i = math.max(0, _anchor.block - 1);
          i <= math.min(blocks.length - 1, _anchor.block + 3);
          i++
        ) {
          visibleBlockIndices.add(i);
        }
      }

      // 1. Check visible blocks for exact single-block match first
      for (final i in visibleBlockIndices) {
        if (i < 0 || i >= blocks.length) continue;
        final blockText = blocks[i].text;
        final idx = blockText.indexOf(text);
        if (idx != -1) {
          foundBlock = i;
          foundStart = idx;
          foundEnd = idx + text.length;
          break;
        }
      }

      // 2. Check all blocks for single-block match if not on visible screen
      if (foundBlock == -1) {
        for (int i = 0; i < blocks.length; i++) {
          final blockText = blocks[i].text;
          final idx = blockText.indexOf(text);
          if (idx != -1) {
            foundBlock = i;
            foundStart = idx;
            foundEnd = idx + text.length;
            break;
          }
        }
      }

      // 3. Multi-block / cross-paragraph selection fallback
      if (foundBlock == -1) {
        final paragraphs = text
            .split(RegExp(r'\n+'))
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty)
            .toList();

        if (paragraphs.length > 1) {
          final searchBlocks = [
            ...visibleBlockIndices,
            ...List.generate(
              blocks.length,
              (i) => i,
            ).where((i) => !visibleBlockIndices.contains(i)),
          ];
          for (final startB in searchBlocks) {
            if (startB + paragraphs.length - 1 >= blocks.length) continue;
            final firstText = blocks[startB].text;
            final firstIdx = firstText.lastIndexOf(paragraphs.first);
            if (firstIdx == -1) continue;

            bool matches = true;
            for (int k = 1; k < paragraphs.length - 1; k++) {
              if (!blocks[startB + k].text.contains(paragraphs[k])) {
                matches = false;
                break;
              }
            }
            if (!matches) continue;

            final lastB = startB + paragraphs.length - 1;
            final lastText = blocks[lastB].text;
            final lastIdx = lastText.indexOf(paragraphs.last);
            if (lastIdx == -1) continue;

            foundBlock = startB;
            foundStart = firstIdx;
            foundEnd = firstText.length;
            multiSpans = <Map<String, int>>[
              {
                'block': startB,
                'startOffset': firstIdx,
                'endOffset': firstText.length,
              },
            ];
            for (int k = 1; k < paragraphs.length - 1; k++) {
              multiSpans.add({
                'block': startB + k,
                'startOffset': 0,
                'endOffset': blocks[startB + k].text.length,
              });
            }
            multiSpans.add({
              'block': lastB,
              'startOffset': 0,
              'endOffset': lastIdx + paragraphs.last.length,
            });
            break;
          }
        }
      }

      // 4. Fallback to anchor if still not located
      if (foundBlock == -1) {
        _captureAnchor();
        foundBlock = _anchor.block;
        foundStart = _anchor.offset;
        foundEnd = foundStart + text.length;
      }
    }

    int pageIdx = _currentPageIndex;
    if (_pagedPages.isNotEmpty) {
      final p = _pagedPages.indexWhere(
        (page) => page.any((f) => f.block == foundBlock),
      );
      if (p != -1) pageIdx = p;
    }

    final blockText = (foundBlock >= 0 && foundBlock < blocks.length)
        ? blocks[foundBlock].text
        : '';
    final prefixContext = blockText.substring(
      math.max(0, foundStart - 32),
      math.max(0, foundStart),
    );
    final suffixContext = blockText.substring(
      math.min(blockText.length, foundEnd),
      math.min(blockText.length, foundEnd + 32),
    );

    final locatorMap = <String, dynamic>{
      'engine': 'hon-html-v2',
      'chapterIndex': _currentChapterIndex,
      'pageIndex': pageIdx,
      'block': foundBlock,
      'startOffset': foundStart,
      'endOffset': foundEnd,
      'prefixContext': prefixContext,
      'suffixContext': suffixContext,
    };
    if (multiSpans != null && multiSpans.isNotEmpty) {
      locatorMap['spans'] = multiSpans;
    }
    final locator = jsonEncode(locatorMap);
    final hl = Highlight(
      id: 'hl_${widget.book.id}_${DateTime.now().microsecondsSinceEpoch}',
      bookId: widget.book.id,
      locatorString: locator,
      selectedText: actualSelectedText,
      color: color,
      note: note,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await DatabaseService.instance.saveHighlight(hl);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(note != null ? 'Note added.' : 'Highlighted.'),
        duration: const Duration(seconds: 2),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await DatabaseService.instance.deleteHighlight(hl.id);
            if (mounted) setState(() {});
          },
        ),
      ),
    );
  }

  void _jumpToBookmark(Bookmark bm) {
    int chIdx = bm.pageIndex;
    int blockIdx = 0;
    int offset = 0;
    int pageIdx = 0;
    if (bm.locatorString != null && bm.locatorString!.isNotEmpty) {
      try {
        final loc = jsonDecode(bm.locatorString!) as Map<String, dynamic>;
        chIdx =
            (loc['chapter'] as num?)?.toInt() ??
            (loc['chapterIndex'] as num?)?.toInt() ??
            bm.pageIndex;
        blockIdx = (loc['block'] as num?)?.toInt() ?? 0;
        offset = (loc['offset'] as num?)?.toInt() ?? 0;
        pageIdx =
            (loc['page'] as num?)?.toInt() ??
            (loc['pageIndex'] as num?)?.toInt() ??
            0;
      } catch (_) {}
    }

    if (chIdx < 0 || chIdx >= _chapters.length) return;

    final isPaginated =
        ref.read(readerPreferencesProvider).layoutMode ==
        ReaderLayoutMode.paginated;
    setState(() {
      _currentChapterIndex = chIdx;
      _anchor = ReaderTextAnchor(blockIdx, offset);
      _hasAnchor = true;
      _layoutSignature = null;
      _scrollBaseIndex = chIdx;
      _chapterKeys.clear();
      _isBookmarked = DatabaseService.instance.isBookmarked(
        widget.book.id,
        chIdx,
      );
    });

    if (isPaginated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pagedPages.isNotEmpty) {
          final targetPage = _pagedPages.indexWhere(
            (page) => page.any(
              (f) =>
                  f.block == blockIdx &&
                  offset >= f.start &&
                  (f.end == 0 || offset <= f.end),
            ),
          );
          final finalPage = targetPage != -1
              ? targetPage
              : pageIdx.clamp(0, _pagedPages.length - 1);
          setState(() => _currentPageIndex = finalPage);
          if (_pageController.hasClients) {
            _pageController.jumpToPage(finalPage + 1);
          }
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final key = _blockKeys['$chIdx:$blockIdx'];
        final ctx = key?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 250),
            alignment: 0.1,
          );
        } else {
          _restoreScrollAnchor();
        }
      });
    }
  }

  void _jumpToHighlight(Highlight highlight) {
    int chIdx = 0;
    int blockIdx = 0;
    int offset = 0;
    int pageIdx = 0;
    try {
      final loc = jsonDecode(highlight.locatorString) as Map<String, dynamic>;
      chIdx = (loc['chapterIndex'] as num?)?.toInt() ?? 0;
      if (loc['spans'] is List && (loc['spans'] as List).isNotEmpty) {
        final firstSpan = (loc['spans'] as List).first as Map;
        blockIdx = (firstSpan['block'] as num?)?.toInt() ?? 0;
        offset = (firstSpan['startOffset'] as num?)?.toInt() ?? 0;
      } else {
        blockIdx = (loc['block'] as num?)?.toInt() ?? 0;
        offset =
            (loc['startOffset'] as num?)?.toInt() ??
            (loc['offset'] as num?)?.toInt() ??
            0;
      }
      pageIdx = (loc['pageIndex'] as num?)?.toInt() ?? 0;
    } catch (_) {}

    if (chIdx < 0 || chIdx >= _chapters.length) return;

    final isPaginated =
        ref.read(readerPreferencesProvider).layoutMode ==
        ReaderLayoutMode.paginated;
    setState(() {
      _currentChapterIndex = chIdx;
      _anchor = ReaderTextAnchor(blockIdx, offset);
      _hasAnchor = true;
      _layoutSignature = null;
      _scrollBaseIndex = chIdx;
      _chapterKeys.clear();
      _isBookmarked = DatabaseService.instance.isBookmarked(
        widget.book.id,
        chIdx,
      );
    });

    if (isPaginated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_pagedPages.isNotEmpty) {
          final targetPage = _pagedPages.indexWhere(
            (page) => page.any(
              (f) =>
                  f.block == blockIdx &&
                  offset >= f.start &&
                  (f.end == 0 || offset <= f.end),
            ),
          );
          final finalPage = targetPage != -1
              ? targetPage
              : pageIdx.clamp(0, _pagedPages.length - 1);
          setState(() => _currentPageIndex = finalPage);
          if (_pageController.hasClients) {
            _pageController.jumpToPage(finalPage + 1);
          }
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final key = _blockKeys['$chIdx:$blockIdx'];
        final ctx = key?.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 250),
            alignment: 0.1,
          );
        } else {
          _restoreScrollAnchor();
        }
      });
    }
  }

  Future<void> _addNoteToSelection() async {
    final text = _selectedQuote?.trim();
    if (text == null || text.isEmpty) return;
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Note'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter your note here...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note != null && note.isNotEmpty) {
      await _highlightSelectedText('yellow', note);
    }
  }

  Future<void> _toggleOrientationLock() async {
    final next = !_isOrientationLocked;
    if (next) {
      final width = MediaQuery.sizeOf(context).width;
      final height = MediaQuery.sizeOf(context).height;
      await SystemChrome.setPreferredOrientations([
        width > height
            ? DeviceOrientation.landscapeLeft
            : DeviceOrientation.portraitUp,
      ]);
    } else {
      await SystemChrome.setPreferredOrientations(const []);
    }
    if (mounted) setState(() => _isOrientationLocked = next);
  }

  Future<void> _showBookSearch() async {
    final index = await showDialog<int>(
      context: context,
      builder: (_) => ReaderSearchDialog(
        chapters: _chapters,
        localFiles: _chapterFiles,
        theme: ref.read(readerPreferencesProvider).themeConfig,
      ),
    );
    if (mounted && index != null) _jumpToChapter(index);
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(
      const Duration(milliseconds: 600),
      _saveProgress,
    );
  }

  Future<void> _loadBookContent() async {
    try {
      final bookSettings = DatabaseService.instance.getBookReaderSettings(
        widget.book.id,
      );
      if (bookSettings != null) {
        ref
            .read(readerPreferencesProvider.notifier)
            .loadFromState(
              ReaderPreferencesState.fromMap(bookSettings),
              bookId: widget.book.id,
            );
      } else {
        await ref.read(readerPreferencesProvider.notifier).reloadDefaults();
        ref
            .read(readerPreferencesProvider.notifier)
            .setActiveBookId(widget.book.id);
      }
      final savedProgress = widget.restoreSavedProgress
          ? DatabaseService.instance.getProgress(widget.book.id)
          : null;
      final stableLocator =
          widget.initialLocator ?? savedProgress?.locatorString;
      if (stableLocator != null && stableLocator.startsWith('{')) {
        try {
          final location = jsonDecode(stableLocator) as Map<String, dynamic>;
          if (location['engine'] == 'hon-html-v2') {
            _anchor = ReaderTextAnchor(
              location['block'] as int? ?? 0,
              location['offset'] as int? ?? 0,
            );
            _hasAnchor = true;
          }
        } catch (_) {}
      }
      if (savedProgress != null) {
        if (widget.initialChapterIndex == 0 && savedProgress.chapterIndex > 0) {
          _currentChapterIndex = savedProgress.chapterIndex.toInt();
        }
        _currentPageIndex = savedProgress.pageIndex;
        _totalPages = savedProgress.totalPages > 0
            ? savedProgress.totalPages
            : 1;
      }

      if (widget.book.format == BookFormat.webNovel) {
        await DatabaseService.instance.ensureChaptersLoaded(widget.book.id);
        final dbChapters = DatabaseService.instance.getChapters(widget.book.id);
        final loadedChapters = <EpubChapterItem>[];

        final requestedIndex = _currentChapterIndex;
        if (dbChapters.isNotEmpty) {
          for (var i = 0; i < dbChapters.length; i++) {
            final ch = dbChapters[i];
            var body = '';
            if (i == requestedIndex && widget.initialChapterContent != null) {
              body = widget.initialChapterContent!;
            }
            if (ch.localFilePath != null) {
              _chapterFiles[i] = ch.localFilePath!;
              if (i == requestedIndex &&
                  body.isEmpty &&
                  await File(ch.localFilePath!).exists()) {
                body = await File(ch.localFilePath!).readAsString();
              }
            }
            if (body.isNotEmpty) {
              body = ChapterContentSanitizer.sanitize(
                body,
                chapterTitle: ch.title,
              );
            }
            loadedChapters.add(
              EpubChapterItem(
                id: ch.id,
                title: ch.title,
                contentHref: ch.url ?? ch.id,
                htmlContent: body,
              ),
            );
          }
        } else if (widget.initialChapterContent?.isNotEmpty == true) {
          final title = 'Chapter ${requestedIndex + 1}';
          loadedChapters.add(
            EpubChapterItem(
              id: 'ch_$requestedIndex',
              title: title,
              contentHref: 'webnovel_ch_$requestedIndex',
              htmlContent: ChapterContentSanitizer.sanitize(
                widget.initialChapterContent!,
                chapterTitle: title,
              ),
            ),
          );
        }

        if (loadedChapters.isNotEmpty && mounted) {
          setState(() {
            _chapters = loadedChapters;
            _totalPages = loadedChapters.length;
            _currentChapterIndex = _currentChapterIndex.clamp(
              0,
              loadedChapters.length - 1,
            );
            _scrollBaseIndex = _currentChapterIndex;
            _isBookmarked = DatabaseService.instance.isBookmarked(
              widget.book.id,
              _currentChapterIndex,
            );
            _isLoading = false;
            if (_isForegrounded &&
                _chapters[_currentChapterIndex].htmlContent.isNotEmpty) {
              _sessionStartTime = DateTime.now();
            } else {
              _sessionStartTime = null;
            }
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(_currentPageIndex + 1);
            }
            final offset =
                widget.initialScrollOffset ??
                savedProgress?.scrollOffset ??
                0.0;
            if (_hasAnchor) {
              _restoreScrollAnchor();
            } else if (_scrollController.hasClients && offset > 0) {
              _scrollController.jumpTo(
                offset.clamp(0.0, _scrollController.position.maxScrollExtent),
              );
            }
          });
          return;
        }
      }

      File? file;
      if (widget.book.filePath != null) {
        if (widget.book.filePath!.startsWith('assets/')) {
          // Bundled fixture asset
          final bytes = await rootBundle.load(widget.book.filePath!);
          final tempFile = File(
            '${Directory.systemTemp.path}/hon_${sha256.convert(utf8.encode(widget.book.id))}.epub',
          );
          await tempFile.writeAsBytes(bytes.buffer.asUint8List());
          file = tempFile;
        } else {
          file = File(widget.book.filePath!);
        }
      }

      if (file != null && file.existsSync()) {
        final metadata = await EpubParser.parse(file);
        if (metadata.chapters.isNotEmpty) {
          int resolvedChapterIndex = _currentChapterIndex;
          final rawLocator =
              widget.initialLocator ?? savedProgress?.locatorString;
          if (rawLocator != null && rawLocator.trim().startsWith('{')) {
            try {
              final decoded = jsonDecode(rawLocator) as Map<String, dynamic>;
              final href = decoded['href'] as String?;
              if (href != null) {
                String normalize(String s) =>
                    s.replaceAll(RegExp(r'^[./]+'), '').toLowerCase();
                final normHref = normalize(href);
                final matchIdx = metadata.chapters.indexWhere((c) {
                  final normContent = normalize(c.contentHref);
                  return normContent == normHref ||
                      normContent.endsWith(normHref) ||
                      normHref.endsWith(normContent);
                });
                if (matchIdx >= 0) {
                  resolvedChapterIndex = matchIdx;
                }
              }
            } catch (_) {}
          }

          if (mounted) {
            setState(() {
              _chapters = metadata.chapters;
              _totalPages = metadata.chapters.length;
              if (resolvedChapterIndex < _chapters.length) {
                _currentChapterIndex = resolvedChapterIndex;
              } else {
                _currentChapterIndex = 0;
              }
              _scrollBaseIndex = _currentChapterIndex;
              _isBookmarked = DatabaseService.instance.isBookmarked(
                widget.book.id,
                _currentChapterIndex,
              );
              _isLoading = false;
              // Start timer ONLY if both readable content is ready AND reader is foregrounded
              if (_isForegrounded) {
                _sessionStartTime = DateTime.now();
              } else {
                _sessionStartTime = null;
              }
            });

            // Post-frame scroll position restoration if scroll offset exists
            final targetOffset =
                widget.initialScrollOffset ??
                savedProgress?.scrollOffset ??
                0.0;
            if (targetOffset > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future.delayed(const Duration(milliseconds: 60), () {
                  if (_scrollController.hasClients) {
                    final maxExtent =
                        _scrollController.position.maxScrollExtent;
                    _scrollController.jumpTo(
                      targetOffset.clamp(0.0, maxExtent),
                    );
                  }
                });
              });
            }
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_pageController.hasClients) {
                _pageController.jumpToPage(_currentPageIndex + 1);
              }
            });
            return;
          }
        }
      }

      // If physical book file could not be opened, display honest error
      if (mounted) {
        setState(() {
          _errorMessage = widget.book.filePath != null
              ? 'Could not read EPUB publication file at:\n${widget.book.filePath}'
              : 'No publication file path registered for this book.';
          _isLoading = false;
          _sessionStartTime = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'EPUB parsing error: $e';
          _isLoading = false;
          _sessionStartTime = null;
        });
      }
    }
  }

  void _saveProgress() {
    if (!mounted || _chapters.isEmpty) return;
    _captureAnchor();
    final total = _chapters.length;

    double currentOffset = 0.0;
    double chapterFraction = 0.0;
    if (_scrollController.hasClients) {
      final box = _chapterKeys[_currentChapterIndex]?.currentContext
          ?.findRenderObject();
      if (box is RenderBox && box.hasSize) {
        final top = box.localToGlobal(Offset.zero).dy;
        final viewportTop = MediaQuery.of(context).padding.top + 52.0;
        currentOffset = (viewportTop - top).clamp(0.0, box.size.height);
        chapterFraction = (currentOffset / box.size.height).clamp(0.0, 1.0);
      }
    } else if (ref.read(readerPreferencesProvider).layoutMode ==
        ReaderLayoutMode.paginated) {
      chapterFraction = (_currentPageIndex + 1) / _chapterPageCount;
    }

    // Accurate progress calculation:
    // Combine chapter index with within-chapter scroll depth.
    // Entering the final chapter does NOT mark 100% completion unless the user
    // actually scrolls near the end of the final chapter (>= 95%).
    final overallFraction = total > 0
        ? (_currentChapterIndex + chapterFraction) / total
        : 0.0;
    final pct = overallFraction.clamp(0.0, 1.0);

    final currentChapterId = _chapters[_currentChapterIndex].id;
    final locator = jsonEncode({
      'engine': 'hon-html-v2',
      'href': _chapters[_currentChapterIndex].contentHref,
      'block': _anchor.block,
      'offset': _anchor.offset,
    });

    final progress = ReadingProgress(
      bookId: widget.book.id,
      lastChapterId: currentChapterId,
      chapterIndex: _currentChapterIndex.toDouble(),
      pageIndex: _currentPageIndex,
      totalPages: _chapterPageCount,
      scrollOffset: currentOffset,
      locatorString: locator,
      locatorVersion: 'hon-html-v2',
      completionPercentage: pct,
      lastReadAt: DateTime.now(),
    );
    DatabaseService.instance.saveProgress(progress);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _jumpToChapter(int index) {
    if (index >= 0 && index < _chapters.length) {
      setState(() {
        _currentChapterIndex = index;
        _currentPageIndex = 0;
        _anchor = const ReaderTextAnchor(0);
        _hasAnchor = true;
        _layoutSignature = null;
        _scrollBaseIndex = index;
        _chapterKeys.clear();
        _isBookmarked = DatabaseService.instance.isBookmarked(
          widget.book.id,
          index,
        );
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(1);
      }
      _saveProgress();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ReaderPreferencesState>(readerPreferencesProvider, (
      previous,
      next,
    ) {
      if (previous == null) return;
      final reflowsText =
          previous.layoutMode != next.layoutMode ||
          previous.fontFamily != next.fontFamily ||
          previous.fontSize != next.fontSize ||
          previous.lineHeight != next.lineHeight ||
          previous.horizontalMargin != next.horizontalMargin ||
          previous.paragraphSpacing != next.paragraphSpacing ||
          previous.textIndent != next.textIndent ||
          previous.isJustified != next.isJustified;
      if (!reflowsText) return;
      _captureAnchor();
      if (next.layoutMode == ReaderLayoutMode.verticalScroll &&
          previous.layoutMode != next.layoutMode) {
        _scrollBaseIndex = _currentChapterIndex;
        _chapterKeys.clear();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreScrollAnchor();
      });
    });
    final prefs = ref.watch(readerPreferencesProvider);
    final themeConfig = prefs.themeConfig;
    if (Platform.isAndroid && _appliedBrightness != prefs.brightness) {
      _appliedBrightness = prefs.brightness;
      unawaited(
        const MethodChannel(
          'com.hon.reader/readium_reader',
        ).invokeMethod<void>('setBrightness', {'brightness': prefs.brightness}),
      );
    }

    return PopScope(
      // System back skips the X button, so flush the debounced scroll save.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        _saveDebounceTimer?.cancel();
        _saveProgress();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: themeConfig.systemBrightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
        child: Scaffold(
          backgroundColor: themeConfig.backgroundColor,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Stack(
              children: [
                // Main Reading Content Area
                GestureDetector(
                  onTap: _toggleControls,
                  behavior: HitTestBehavior.opaque,
                  child: prefs.layoutMode == ReaderLayoutMode.verticalScroll
                      ? _buildScrollView(prefs, themeConfig)
                      : _buildPagedView(prefs, themeConfig),
                ),

                // Ambient Top Header Overlay
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    offset: _showControls ? Offset.zero : const Offset(0, -1),
                    child: ReaderControlsVisibility(
                      visible: _showControls,
                      child: _buildTopHeader(themeConfig),
                    ),
                  ),
                ),

                // Ambient Bottom Bar Overlay
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedSlide(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    offset: _showControls ? Offset.zero : const Offset(0, 1),
                    child: ReaderControlsVisibility(
                      visible: _showControls,
                      child: _buildBottomBar(themeConfig),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrollView(
    ReaderPreferencesState prefs,
    ReaderThemeConfig themeConfig,
  ) {
    if (_isLoading) {
      return Center(
        child: CupertinoActivityIndicator(color: themeConfig.textColor),
      );
    }
    if (_errorMessage != null || _chapters.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            _errorMessage ?? 'No readable chapters in this publication.',
            textAlign: TextAlign.center,
            style: TextStyle(color: themeConfig.textColor),
          ),
        ),
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is OverscrollNotification &&
            notification.overscroll < 0 &&
            _scrollBaseIndex > 0 &&
            !_prependingChapter) {
          _prependingChapter = true;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _prependPreviousChapter(),
          );
        }
        if (notification is ScrollUpdateNotification ||
            notification is ScrollEndNotification) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _updateVisibleChapter(),
          );
        }
        return false;
      },
      child: ListView.builder(
        key: ValueKey('scroll_$_scrollBaseIndex'),
        controller: _scrollController,
        physics: const BouncingScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
          prefs.horizontalMargin,
          MediaQuery.of(context).padding.top + 68,
          prefs.horizontalMargin,
          MediaQuery.of(context).padding.bottom + 52,
        ),
        itemCount: _chapters.length - _scrollBaseIndex,
        itemBuilder: (context, index) {
          final chapterIndex = _scrollBaseIndex + index;
          if (_chapters[chapterIndex].htmlContent.isEmpty) {
            return SizedBox(
              key: _chapterKeys.putIfAbsent(chapterIndex, GlobalKey.new),
              height: MediaQuery.sizeOf(context).height * 0.8,
              child: _missingChapter(chapterIndex, themeConfig),
            );
          }
          return _selectableContent(
            Column(
              key: _chapterKeys.putIfAbsent(chapterIndex, GlobalKey.new),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (chapterIndex > _scrollBaseIndex) const SizedBox(height: 52),
                for (
                  var block = 0;
                  block < _document(chapterIndex).blocks.length;
                  block++
                )
                  Padding(
                    padding: EdgeInsets.only(bottom: prefs.paragraphSpacing),
                    child: _blockWidget(
                      chapterIndex,
                      block,
                      prefs,
                      track: true,
                    ),
                  ),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }

  void _prependPreviousChapter() {
    if (_scrollBaseIndex <= 0 || !_scrollController.hasClients) {
      _prependingChapter = false;
      return;
    }
    final oldOffset = _scrollController.offset;
    final previous = _scrollBaseIndex - 1;
    setState(() => _scrollBaseIndex = previous);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final box = _chapterKeys[previous]?.currentContext?.findRenderObject();
      if (box is RenderBox) {
        _scrollController.jumpTo(oldOffset + box.size.height);
      }
      _prependingChapter = false;
    });
  }

  void _updateVisibleChapter() {
    if (!mounted || _chapters.isEmpty) return;
    final screenHeight = MediaQuery.of(context).size.height;
    final checkY = screenHeight * 0.35;
    int? visible;
    final sortedKeys = _chapterKeys.keys.toList()..sort();
    for (final chapterIndex in sortedKeys) {
      final key = _chapterKeys[chapterIndex];
      final box = key?.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (top <= checkY && bottom > checkY) {
        visible = chapterIndex;
        break;
      }
    }
    if (visible == null) {
      double? minDistance;
      for (final chapterIndex in sortedKeys) {
        final key = _chapterKeys[chapterIndex];
        final box = key?.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.hasSize) continue;
        final top = box.localToGlobal(Offset.zero).dy;
        final bottom = top + box.size.height;
        if (bottom <= 0 || top >= screenHeight) continue;
        final dist = (top - checkY).abs();
        if (minDistance == null || dist < minDistance) {
          minDistance = dist;
          visible = chapterIndex;
        }
      }
    }
    if (visible != null && visible != _currentChapterIndex) {
      setState(() {
        _pauseReadingSession();
        _currentChapterIndex = visible!;
        _anchor = const ReaderTextAnchor(0);
        _resumeReadingSession();
        _isBookmarked = DatabaseService.instance.isBookmarked(
          widget.book.id,
          visible,
        );
      });
    }
  }

  Widget _buildPagedView(
    ReaderPreferencesState prefs,
    ReaderThemeConfig themeConfig,
  ) {
    if (_isLoading || _errorMessage != null || _chapters.isEmpty) {
      return _buildScrollView(prefs, themeConfig);
    }
    if (_chapters[_currentChapterIndex].htmlContent.isEmpty) {
      return Center(child: _missingChapter(_currentChapterIndex, themeConfig));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final top = MediaQuery.of(context).padding.top + 68.0;
        final bottom = MediaQuery.of(context).padding.bottom + 52.0;
        final width = (constraints.maxWidth - prefs.horizontalMargin * 2).clamp(
          80.0,
          double.infinity,
        );
        final height = (constraints.maxHeight - top - bottom).clamp(
          100.0,
          double.infinity,
        );
        final signature =
            '$_currentChapterIndex:$width:$height:${MediaQuery.textScalerOf(context)}:${prefs.fontSize}:${prefs.fontFamily}:${prefs.lineHeight}:${prefs.paragraphSpacing}:${prefs.isJustified}';
        if (_layoutSignature != signature) {
          final pages = _document(_currentChapterIndex).paginate(
            prefs,
            width,
            height,
            MediaQuery.textScalerOf(context),
            Directionality.of(context),
          );
          _pagedPages = pages;
          _chapterPageCount = pages.length;
          _layoutSignature = signature;
          if (_pendingPagedEnd) {
            _currentPageIndex = pages.length - 1;
            _pendingPagedEnd = false;
          } else if (_hasAnchor) {
            _currentPageIndex = pages
                .lastIndexWhere(
                  (page) =>
                      page.isNotEmpty &&
                      (page.first.block < _anchor.block ||
                          page.first.block == _anchor.block &&
                              page.first.start <= _anchor.offset),
                )
                .clamp(0, pages.length - 1);
          } else {
            _currentPageIndex = _currentPageIndex.clamp(0, pages.length - 1);
          }
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pageController.hasClients) {
              _pageController.jumpToPage(_currentPageIndex + 1);
            }
          });
        }
        final pages = _pagedPages;
        return Listener(
          onPointerDown: (event) {
            _pageSwipeStart = event.position;
            _pageSwipeStartPage = _pageController.hasClients
                ? _pageController.page
                : null;
          },
          onPointerUp: (event) {
            final start = _pageSwipeStart;
            final initialPage = _pageSwipeStartPage;
            _pageSwipeStart = null;
            _pageSwipeStartPage = null;
            if (start == null ||
                initialPage == null ||
                !_pageController.hasClients) {
              return;
            }
            final dx = event.position.dx - start.dx;
            final dy = event.position.dy - start.dy;
            if (dx.abs() < 80 || dx.abs() < dy.abs() * 1.3) return;
            final currentPage = _pageController.page ?? initialPage;
            if ((currentPage - initialPage).abs() > 0.05) return;
            if (dx < 0) {
              _pageController.nextPage(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            } else {
              _pageController.previousPage(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            }
          },
          child: PageView.builder(
            controller: _pageController,
            physics: const BouncingScrollPhysics(),
            itemCount: pages.length + 2,
            onPageChanged: (page) {
              if (_changingPagedChapter) return;
              if (page == 0 && _currentChapterIndex > 0) {
                _changePagedChapter(_currentChapterIndex - 1, atEnd: true);
              } else if (page == pages.length + 1 &&
                  _currentChapterIndex < _chapters.length - 1) {
                _changePagedChapter(_currentChapterIndex + 1);
              } else if (page == 0 || page == pages.length + 1) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_pageController.hasClients) {
                    _pageController.jumpToPage(page == 0 ? 1 : pages.length);
                  }
                });
              } else if (page >= 1 && page <= pages.length) {
                setState(() => _currentPageIndex = page - 1);
                _saveProgress();
              }
            },
            itemBuilder: (context, index) {
              if (index == 0 || index == pages.length + 1) {
                return Center(
                  child: Icon(
                    index == 0
                        ? CupertinoIcons.chevron_left
                        : CupertinoIcons.chevron_right,
                    color: themeConfig.secondaryTextColor,
                  ),
                );
              }
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  prefs.horizontalMargin,
                  top,
                  prefs.horizontalMargin,
                  bottom,
                ),
                child: _selectableContent(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final fragment in pages[index - 1])
                        Padding(
                          padding: EdgeInsets.only(bottom: fragment.after),
                          child: _blockWidget(
                            _currentChapterIndex,
                            fragment.block,
                            prefs,
                            start: fragment.start,
                            end: fragment.end,
                            imageHeight: fragment.height,
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  void _changePagedChapter(int index, {bool atEnd = false}) {
    if (index < 0 || index >= _chapters.length) return;
    _changingPagedChapter = true;
    _pendingPagedEnd = atEnd;
    if (_pageController.hasClients) _pageController.jumpToPage(1);
    setState(() {
      _currentChapterIndex = index;
      _currentPageIndex = 0;
      _anchor = const ReaderTextAnchor(0);
      _hasAnchor = !atEnd;
      _layoutSignature = null;
      _isBookmarked = DatabaseService.instance.isBookmarked(
        widget.book.id,
        index,
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pageController.hasClients) {
        _changingPagedChapter = false;
        return;
      }
      _pageController.jumpToPage(atEnd ? _chapterPageCount : 1);
      _currentPageIndex = atEnd ? _chapterPageCount - 1 : 0;
      _changingPagedChapter = false;
      _saveProgress();
    });
  }

  Widget _buildTopHeader(ReaderThemeConfig themeConfig) {
    final isWebNovel = widget.book.format == BookFormat.webNovel;
    final chapterTitle = _chapters.isEmpty
        ? ''
        : _chapters[_currentChapterIndex].title.trim();
    return ReaderHeader(
      theme: themeConfig,
      location: '${_currentChapterIndex + 1}',
      // Like Apple Books: name where you are; the footer carries progress.
      status: chapterTitle.isNotEmpty ? chapterTitle : widget.book.title,
      onBack: isWebNovel ? _backToCatalogue : null,
      backLabel: 'Catalogue',
      onPrevious: !isWebNovel && _currentChapterIndex > 0
          ? () => _jumpToChapter(_currentChapterIndex - 1)
          : null,
      onClose: () {
        _saveProgress();
        Navigator.of(context).pop();
      },
    );
  }

  void _backToCatalogue() {
    _saveProgress();
    if (widget.fromCatalogue) {
      Navigator.of(context).pop();
    } else {
      final sourceId =
          widget.book.sourceId ??
          (widget.book.id.contains(':')
              ? widget.book.id.split(':').first
              : 'unknown');
      final sourceNovelId =
          widget.book.sourceNovelId ??
          (widget.book.id.contains(':')
              ? widget.book.id.substring(widget.book.id.indexOf(':') + 1)
              : widget.book.id);
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SourceNovelDetailsScreen(
            novel: SourceNovelSummary(
              id: sourceNovelId,
              title: widget.book.title,
              author: widget.book.author,
              coverUrl: widget.book.coverPath,
            ),
            sourceId: sourceId,
            sourceName: sourceId,
          ),
        ),
      );
    }
  }

  Widget _buildBottomBar(ReaderThemeConfig themeConfig) {
    final total = _chapters.isNotEmpty ? _chapters.length : _totalPages;
    return ReaderFooter(
      theme: themeConfig,
      progress: 'Chapter ${_currentChapterIndex + 1} of $total',
      onReload: _reloadCurrentChapter,
      onMenu: () {
        ReaderMenuPopup.show(
          context,
          theme: themeConfig,
          onOpenContents: () {
            ReaderContentsSheet.show(
              context,
              theme: themeConfig,
              bookId: widget.book.id,
              bookTitle: widget.book.title,
              currentChapterIndex: _currentChapterIndex,
              totalChapters: _chapters.length,
              chapters: _chapters,
              onSelectChapter: _jumpToChapter,
              onSelectHighlight: _jumpToHighlight,
              onSelectBookmark: _jumpToBookmark,
            );
          },
          onOpenSearch: () {
            _showBookSearch();
          },
          onOpenThemes: () {
            ThemesSettingsSheet.show(context, bookId: widget.book.id);
          },
          onToggleReadingMode: () {
            ref
                .read(readerPreferencesProvider.notifier)
                .setLayoutMode(
                  ref.read(readerPreferencesProvider).layoutMode ==
                          ReaderLayoutMode.verticalScroll
                      ? ReaderLayoutMode.paginated
                      : ReaderLayoutMode.verticalScroll,
                );
          },
          onToggleBookmark: () async {
            _captureAnchor();
            final locator = jsonEncode({
              'engine': 'hon-html-v2',
              'href': _chapters.isNotEmpty
                  ? _chapters[_currentChapterIndex].contentHref
                  : '',
              'block': _anchor.block,
              'offset': _anchor.offset,
              'chapter': _currentChapterIndex,
              'page': _currentPageIndex,
            });
            final added = await DatabaseService.instance.toggleBookmark(
              widget.book.id,
              _currentChapterIndex,
              label: _chapters.isNotEmpty
                  ? _chapters[_currentChapterIndex].title
                  : 'Chapter ${_currentChapterIndex + 1}',
              locatorString: locator,
              locatorVersion: '1',
            );
            if (!mounted) return;
            setState(() {
              _isBookmarked = added;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    added
                        ? 'Bookmark added for Chapter ${_currentChapterIndex + 1}'
                        : 'Bookmark removed',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  duration: const Duration(seconds: 1),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            }
          },
          onReloadChapter: _reloadCurrentChapter,
          onShareSelected: _shareSelectedQuote,
          onToggleOrientationLock: _toggleOrientationLock,
          isOrientationLocked: _isOrientationLocked,
          isBookmarked: _isBookmarked,
          isContinuousScroll:
              ref.read(readerPreferencesProvider).layoutMode ==
              ReaderLayoutMode.verticalScroll,
        );
      },
    );
  }

  Future<void> _reloadCurrentChapter() async {
    final idx = _currentChapterIndex;
    if (_loadingChapters.contains(idx)) return;
    _captureAnchor();
    try {
      final result = await _ensureChapterContent(idx, force: true);
      if (!mounted) return;
      if (result == ChapterLoadResult.skipped) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _restoreScrollAnchor();
      });
      final String msg;
      switch (result) {
        case ChapterLoadResult.refreshedOnline:
          msg = 'Chapter refreshed from source';
          break;
        case ChapterLoadResult.offlineFallback:
          msg = 'Reloaded from saved offline copy';
          break;
        case ChapterLoadResult.failed:
          msg = 'Failed to reload chapter';
          break;
        case ChapterLoadResult.skipped:
          return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reload chapter: $e'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}
