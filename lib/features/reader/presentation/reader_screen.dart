import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/reading_progress.dart';
import '../../../core/utils/epub_parser.dart';
import '../../../shared/widgets/ornate_divider.dart';
import '../sheets/reader_contents_sheet.dart';
import '../sheets/reader_menu_popup.dart';
import '../sheets/themes_settings_sheet.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final Book book;
  final int initialChapterIndex;
  final int initialPageIndex;
  final double? initialScrollOffset;
  final String? initialLocator;
  final String? initialChapterContent;

  const ReaderScreen({
    super.key,
    required this.book,
    this.initialChapterIndex = 0,
    this.initialPageIndex = 0,
    this.initialScrollOffset,
    this.initialLocator,
    this.initialChapterContent,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> with WidgetsBindingObserver {
  bool _showControls = true;
  bool _isLoading = true;
  String? _errorMessage;

  List<EpubChapterItem> _chapters = [];
  int _currentChapterIndex = 0;
  int _currentPageIndex = 0;
  int _totalPages = 1;
  bool _isBookmarked = false;
  bool _isContinuousScroll = true;

  late PageController _pageController;
  late ScrollController _scrollController;
  Timer? _saveDebounceTimer;
  DateTime? _sessionStartTime;
  bool _isForegrounded = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Do NOT start timer during loading! Timer starts once content is parsed, readable, AND foregrounded.
    _sessionStartTime = null;
    _currentChapterIndex = widget.initialChapterIndex;
    _currentPageIndex = widget.initialPageIndex;
    _pageController = PageController(initialPage: _currentChapterIndex);
    _scrollController = ScrollController();

    _scrollController.addListener(_onScroll);
    _loadBookContent();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isForegrounded = false;
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
      _sessionStartTime = null; // Crucial: STOP timer so background time is never counted!
    }
  }

  void _resumeReadingSession() {
    // Only restart timer if reader has valid, readable content in foreground
    if (!_isLoading && _errorMessage == null && _isForegrounded) {
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
    _pageController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 600), () {
      _saveProgress();
    });
  }

  Future<void> _loadBookContent() async {
    try {
      final savedProgress = DatabaseService.instance.getProgress(widget.book.id);
      if (savedProgress != null) {
        if (widget.initialChapterIndex == 0 && savedProgress.chapterIndex > 0) {
          _currentChapterIndex = savedProgress.chapterIndex.toInt();
        }
        _currentPageIndex = savedProgress.pageIndex;
        _totalPages = savedProgress.totalPages > 0 ? savedProgress.totalPages : 1;
      }

      if (widget.book.format == BookFormat.webNovel) {
        final dbChapters = DatabaseService.instance.getChapters(widget.book.id);
        final loadedChapters = <EpubChapterItem>[];

        if (widget.initialChapterContent != null && widget.initialChapterContent!.isNotEmpty) {
          final title = dbChapters.isNotEmpty && _currentChapterIndex < dbChapters.length
              ? dbChapters[_currentChapterIndex].title
              : widget.book.title;
          loadedChapters.add(EpubChapterItem(
            id: 'ch_$_currentChapterIndex',
            title: title,
            contentHref: 'webnovel_ch_$_currentChapterIndex',
            htmlContent: widget.initialChapterContent!,
          ));
        } else if (dbChapters.isNotEmpty) {
          for (int i = 0; i < dbChapters.length; i++) {
            final ch = dbChapters[i];
            String body = '';
            if (ch.localFilePath != null && File(ch.localFilePath!).existsSync()) {
              body = File(ch.localFilePath!).readAsStringSync();
            }
            if (body.isNotEmpty) {
              loadedChapters.add(EpubChapterItem(
                id: ch.id,
                title: ch.title,
                contentHref: ch.url ?? ch.id,
                htmlContent: body,
              ));
            }
          }
        }

        if (loadedChapters.isNotEmpty && mounted) {
          setState(() {
            _chapters = loadedChapters;
            _totalPages = loadedChapters.length;
            _currentChapterIndex = _currentChapterIndex.clamp(0, loadedChapters.length - 1);
            _isBookmarked = DatabaseService.instance.isBookmarked(widget.book.id, _currentChapterIndex);
            _isLoading = false;
            if (_isForegrounded) {
              _sessionStartTime = DateTime.now();
            } else {
              _sessionStartTime = null;
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
          final tempFile = File('${Directory.systemTemp.path}/${widget.book.id}.epub');
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
          final rawLocator = widget.initialLocator ?? savedProgress?.locatorString;
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
              _isBookmarked = DatabaseService.instance
                  .isBookmarked(widget.book.id, _currentChapterIndex);
              _isLoading = false;
              // Start timer ONLY if both readable content is ready AND reader is foregrounded
              if (_isForegrounded) {
                _sessionStartTime = DateTime.now();
              } else {
                _sessionStartTime = null;
              }
            });

            // Post-frame scroll position restoration if scroll offset exists
            final targetOffset = widget.initialScrollOffset ??
                savedProgress?.scrollOffset ??
                0.0;
            if (targetOffset > 0) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Future.delayed(const Duration(milliseconds: 60), () {
                  if (_scrollController.hasClients) {
                    final maxExtent =
                        _scrollController.position.maxScrollExtent;
                    _scrollController
                        .jumpTo(targetOffset.clamp(0.0, maxExtent));
                  }
                });
              });
            }
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
    final total = _chapters.length;

    double currentOffset = 0.0;
    double chapterFraction = 0.0;
    if (_scrollController.hasClients) {
      currentOffset = _scrollController.offset;
      if (_scrollController.position.maxScrollExtent > 0) {
        chapterFraction = (_scrollController.offset /
                _scrollController.position.maxScrollExtent)
            .clamp(0.0, 1.0);
      }
    }

    // Accurate progress calculation:
    // Combine chapter index with within-chapter scroll depth.
    // Entering the final chapter does NOT mark 100% completion unless the user
    // actually scrolls near the end of the final chapter (>= 95%).
    final overallFraction =
        total > 0 ? (_currentChapterIndex + chapterFraction) / total : 0.0;
    final pct = overallFraction.clamp(0.0, 1.0);

    final currentChapterId = _chapters[_currentChapterIndex].id;
    final locator =
        '$currentChapterId#offset=${currentOffset.toStringAsFixed(1)}';

    final progress = ReadingProgress(
      bookId: widget.book.id,
      lastChapterId: currentChapterId,
      chapterIndex: _currentChapterIndex.toDouble(),
      pageIndex: _currentPageIndex,
      totalPages: total,
      scrollOffset: currentOffset,
      locatorString: locator,
      locatorVersion: 'dart-dom-v1',
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
        _isBookmarked =
            DatabaseService.instance.isBookmarked(widget.book.id, index);
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(0);
        }
      });
      if (_pageController.hasClients) {
        _pageController.jumpToPage(index);
      }
      _saveProgress();
    }
  }

  // --- HTML DOM Parser for Publication Typography ---
  List<Widget> _buildHtmlContent(
    String html,
    ReaderPreferencesState prefs,
    ReaderThemeConfig themeConfig,
  ) {
    if (html.isEmpty) {
      return [
        Center(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Text(
              'No content in this chapter.',
              style: TextStyle(color: themeConfig.secondaryTextColor),
            ),
          ),
        ),
      ];
    }

    try {
      final doc = html_parser.parse(html);
      final body = doc.body;
      if (body == null) return [];

      final widgets = <Widget>[];

      // Parse body children into blocks
      for (final node in body.children) {
        final tag = node.localName?.toLowerCase() ?? '';

        if (tag == 'h1' || tag == 'h2' || tag == 'h3') {
          final text = node.text.trim();
          if (text.isNotEmpty) {
            widgets.add(
              Padding(
                padding: const EdgeInsets.only(top: 24, bottom: 14),
                child: Text(
                  text,
                  textAlign: TextAlign.center,
                  style: HonTypography.chapterTitle(color: themeConfig.textColor).copyWith(
                    fontSize: tag == 'h1' ? 24 : (tag == 'h2' ? 20 : 18),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            );
          }
        } else if (tag == 'hr') {
          widgets.add(
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: OrnateDivider(
                  color: themeConfig.ornamentColor,
                  width: 120,
                  height: 20,
                ),
              ),
            ),
          );
        } else if (tag == 'p' || tag == 'div') {
          // Check if paragraph contains text or styled spans
          final spans = _parseInlineSpans(node, prefs, themeConfig);
          if (spans.isNotEmpty) {
            widgets.add(
              Padding(
                padding: EdgeInsets.only(bottom: prefs.paragraphSpacing),
                child: RichText(
                  textAlign: prefs.isJustified ? TextAlign.justify : TextAlign.left,
                  text: TextSpan(
                    children: spans,
                    style: HonTypography.readerBody(
                      color: themeConfig.textColor,
                      fontSize: prefs.fontSize,
                      lineHeight: prefs.lineHeight,
                      fontFamily: prefs.fontFamily.displayName,
                    ),
                  ),
                ),
              ),
            );
          }
        }
      }

      // If document was not structured with top-level tags, parse paragraphs
      if (widgets.isEmpty) {
        final textBlocks = body.text.split('\n\n');
        for (final block in textBlocks) {
          final trimmed = block.trim();
          if (trimmed.isNotEmpty) {
            widgets.add(
              Padding(
                padding: EdgeInsets.only(bottom: prefs.paragraphSpacing),
                child: Text(
                  trimmed,
                  textAlign: prefs.isJustified ? TextAlign.justify : TextAlign.left,
                  style: HonTypography.readerBody(
                    color: themeConfig.textColor,
                    fontSize: prefs.fontSize,
                    lineHeight: prefs.lineHeight,
                    fontFamily: prefs.fontFamily.displayName,
                  ),
                ),
              ),
            );
          }
        }
      }

      return widgets;
    } catch (_) {
      return [
        Text(
          html,
          style: TextStyle(color: themeConfig.textColor),
        ),
      ];
    }
  }

  List<InlineSpan> _parseInlineSpans(
    dom.Node node,
    ReaderPreferencesState prefs,
    ReaderThemeConfig themeConfig,
  ) {
    final spans = <InlineSpan>[];

    for (final child in node.nodes) {
      if (child.nodeType == dom.Node.TEXT_NODE) {
        final text = child.text ?? '';
        if (text.isNotEmpty) {
          spans.add(TextSpan(text: text));
        }
      } else if (child is dom.Element) {
        final tag = child.localName?.toLowerCase() ?? '';
        final isItalic = tag == 'i' || tag == 'em';
        final isBold = tag == 'b' || tag == 'strong';

        final childSpans = _parseInlineSpans(child, prefs, themeConfig);

        TextStyle inlineStyle = const TextStyle();
        if (isItalic && isBold) {
          inlineStyle = const TextStyle(
            fontStyle: FontStyle.italic,
            fontWeight: FontWeight.bold,
          );
        } else if (isItalic) {
          inlineStyle = const TextStyle(fontStyle: FontStyle.italic);
        } else if (isBold) {
          inlineStyle = const TextStyle(fontWeight: FontWeight.bold);
        }

        spans.add(TextSpan(
          children: childSpans.isNotEmpty ? childSpans : [TextSpan(text: child.text)],
          style: inlineStyle,
        ));
      }
    }

    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(readerPreferencesProvider);
    final themeConfig = prefs.themeConfig;

    return AnnotatedRegion<SystemUiOverlayStyle>(
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
                child: _isContinuousScroll
                    ? _buildScrollView(prefs, themeConfig)
                    : _buildPagedView(prefs, themeConfig),
              ),

              // Ambient Top Header Overlay
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                top: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildTopHeader(themeConfig),
              ),

              // Ambient Bottom Bar Overlay
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                bottom: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildBottomBar(themeConfig),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildScrollView(ReaderPreferencesState prefs, ReaderThemeConfig themeConfig) {
    if (_isLoading) {
      return Center(
        child: CupertinoActivityIndicator(color: themeConfig.textColor),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.book, size: 48, color: themeConfig.secondaryTextColor),
              const SizedBox(height: 16),
              Text(
                'Unable to open publication',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: themeConfig.textColor,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: themeConfig.secondaryTextColor, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    final chapter = _chapters.isNotEmpty
        ? _chapters[_currentChapterIndex]
        : EpubChapterItem(
            id: 'ch',
            title: widget.book.title,
            contentHref: '',
            htmlContent: '',
          );

    final topPadding = MediaQuery.of(context).padding.top + 52.0;
    final bottomPadding = MediaQuery.of(context).padding.bottom + 52.0;

    final contentBlocks = _buildHtmlContent(chapter.htmlContent, prefs, themeConfig);

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        prefs.horizontalMargin,
        topPadding,
        prefs.horizontalMargin,
        bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          // Clean Serif Chapter Title
          Text(
            chapter.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: HonTypography.chapterTitle(color: themeConfig.textColor).copyWith(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          // Ornate Apple Books flourish divider
          OrnateDivider(
            color: themeConfig.ornamentColor,
            width: 140,
            height: 22,
          ),
          const SizedBox(height: 28),

          // Render formatted publication blocks
          ...contentBlocks,

          const SizedBox(height: 48),

          // Chapter Navigation Buttons
          if (_chapters.length > 1)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentChapterIndex > 0)
                  TextButton.icon(
                    icon: Icon(CupertinoIcons.chevron_left, color: themeConfig.textColor),
                    label: Text(
                      'Previous Chapter',
                      style: TextStyle(color: themeConfig.textColor),
                    ),
                    onPressed: () => _jumpToChapter(_currentChapterIndex - 1),
                  )
                else
                  const SizedBox.shrink(),
                if (_currentChapterIndex < _chapters.length - 1)
                  TextButton.icon(
                    label: Text(
                      'Next Chapter',
                      style: TextStyle(color: themeConfig.textColor),
                    ),
                    icon: Icon(CupertinoIcons.chevron_right, color: themeConfig.textColor),
                    onPressed: () => _jumpToChapter(_currentChapterIndex + 1),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPagedView(ReaderPreferencesState prefs, ReaderThemeConfig themeConfig) {
    if (_isLoading) {
      return Center(
        child: CupertinoActivityIndicator(color: themeConfig.textColor),
      );
    }

    if (_errorMessage != null || _chapters.isEmpty) {
      return _buildScrollView(prefs, themeConfig);
    }

    return PageView.builder(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      onPageChanged: (page) {
        setState(() {
          _currentChapterIndex = page;
        });
        _saveProgress();
      },
      itemCount: _chapters.length,
      itemBuilder: (context, index) {
        final chapter = _chapters[index];
        final topPadding = MediaQuery.of(context).padding.top + 52.0;
        final bottomPadding = MediaQuery.of(context).padding.bottom + 52.0;
        final contentBlocks = _buildHtmlContent(chapter.htmlContent, prefs, themeConfig);

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            prefs.horizontalMargin,
            topPadding,
            prefs.horizontalMargin,
            bottomPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Text(
                chapter.title.toUpperCase(),
                textAlign: TextAlign.center,
                style: HonTypography.chapterTitle(color: themeConfig.textColor).copyWith(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              OrnateDivider(
                color: themeConfig.ornamentColor,
                width: 140,
                height: 22,
              ),
              const SizedBox(height: 28),
              ...contentBlocks,
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopHeader(ReaderThemeConfig themeConfig) {
    final topSafe = MediaQuery.of(context).padding.top;
    final remainingChapters = _chapters.length - (_currentChapterIndex + 1);

    return Container(
      padding: EdgeInsets.fromLTRB(16, topSafe + 8, 16, 8),
      color: themeConfig.backgroundColor.withOpacity(0.94),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Location jump back indicator
          InkWell(
            onTap: () {
              if (_currentChapterIndex > 0) {
                _jumpToChapter(_currentChapterIndex - 1);
              }
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.arrow_counterclockwise,
                    size: 14,
                    color: themeConfig.secondaryTextColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_currentChapterIndex + 1}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: themeConfig.secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Center: Remaining chapters status indicator
          Text(
            remainingChapters > 0
                ? '$remainingChapters ${remainingChapters == 1 ? "chapter" : "chapters"} left'
                : 'Last chapter',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: themeConfig.secondaryTextColor,
            ),
          ),

          // Right: Circular close button ( X )
          IconButton(
            onPressed: () {
              _saveProgress();
              Navigator.of(context).pop();
            },
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: themeConfig.textColor.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                CupertinoIcons.xmark,
                size: 15,
                color: themeConfig.textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ReaderThemeConfig themeConfig) {
    final bottomSafe = MediaQuery.of(context).padding.bottom;
    final total = _chapters.isNotEmpty ? _chapters.length : _totalPages;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 8, 20, bottomSafe + 8),
      color: themeConfig.backgroundColor.withOpacity(0.94),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SizedBox(width: 48), // Balancer for center text

          // Center: Chapter / progress indicator
          Text(
            'Chapter ${_currentChapterIndex + 1} of $total',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: themeConfig.secondaryTextColor,
            ),
          ),

          // Right: Apple Books Aa button with enlarged comfortable touch target
          GestureDetector(
            onTap: () {
              ReaderMenuPopup.show(
                context,
                onOpenContents: () {
                  ReaderContentsSheet.show(
                    context,
                    bookId: widget.book.id,
                    bookTitle: widget.book.title,
                    currentChapterIndex: _currentChapterIndex,
                    totalChapters: _chapters.length,
                    chapters: _chapters,
                    onSelectChapter: _jumpToChapter,
                  );
                },
                onOpenSearch: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('In-book text search is indexing publication...')),
                  );
                },
                onOpenThemes: () {
                  ThemesSettingsSheet.show(context);
                },
                onToggleReadingMode: () {
                  setState(() {
                    _isContinuousScroll = !_isContinuousScroll;
                  });
                },
                onToggleBookmark: () async {
                  final added = await DatabaseService.instance.toggleBookmark(
                    widget.book.id,
                    _currentChapterIndex,
                    label: _chapters.isNotEmpty
                        ? _chapters[_currentChapterIndex].title
                        : 'Chapter ${_currentChapterIndex + 1}',
                  );
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
                isBookmarked: _isBookmarked,
                isContinuousScroll: _isContinuousScroll,
              );
            },
            child: Container(
              width: 48,
              height: 44,
              alignment: Alignment.center,
              child: Icon(
                CupertinoIcons.textformat_size,
                color: themeConfig.textColor,
                size: 23,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
