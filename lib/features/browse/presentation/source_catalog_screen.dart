import '../../../app/theme/glass_surface.dart';
import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../core/database/database_service.dart';
import '../../../core/downloads/hon_download_manager.dart';
import '../../../core/models/book.dart';
import '../../../core/models/chapter.dart';
import '../../../core/models/novel_source.dart';
import '../../../core/sources/source_registry.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../../shared/widgets/book_grid_layout.dart';
import '../../reader/presentation/reader_navigator.dart';
import '../../sheets/add_to_library_prompt.dart';
import 'chapter_download_sheet.dart';
import '../../settings/presentation/source_controls_screen.dart';
import '../../../core/updates/chapter_update_service.dart';

class SourceCatalogScreen extends StatefulWidget {
  final ExtensionMeta sourceMeta;

  const SourceCatalogScreen({super.key, required this.sourceMeta});

  @override
  State<SourceCatalogScreen> createState() => _SourceCatalogScreenState();
}

class _SourceCatalogScreenState extends State<SourceCatalogScreen> {
  SourceCatalogInfo _catalogInfo = const SourceCatalogInfo();
  bool _infoLoaded = false;
  int _listingIndex = 0;
  int _page = 0;
  bool _hasMore = false;
  bool _loadingMore = false;
  String get _selectedListing => _searchQuery.isNotEmpty
      ? 'Search results'
      : _catalogInfo.listings
                .where((listing) => listing.index == _listingIndex)
                .firstOrNull
                ?.name ??
            'Browse';
  bool get _canIncrement =>
      _searchQuery.isNotEmpty || _catalogInfo.listings.isEmpty
      ? _catalogInfo.searchIncrementing
      : _catalogInfo.listings
                .where((listing) => listing.index == _listingIndex)
                .firstOrNull
                ?.incrementing ??
            false;
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isLoading = false;
  String? _errorMessage;
  String? _rawErrorDetails;
  bool _showErrorDetails = false;
  List<SourceNovelSummary> _novels = [];
  final TextEditingController _searchController = TextEditingController();
  int _searchGeneration = 0;

  void _setError(Object error) {
    final raw = error.toString().replaceFirst('SourceNetworkException: ', '');
    _rawErrorDetails = raw;
    _showErrorDetails = false;
    final lower = raw.toLowerCase();
    if (lower.contains('sslhandshakeexception') ||
        lower.contains('certpathvalidatorexception') ||
        lower.contains('trust anchor') ||
        lower.contains('certificate')) {
      _errorMessage =
          'Unable to establish a secure connection to this source. '
          'The website\'s SSL certificate chain could not be verified by Android '
          '(missing intermediate certificates or untrusted root).';
    } else if (lower.contains('source network policy') ||
        lower.contains('network policy')) {
      _errorMessage =
          'Network request blocked by source security policy. '
          'This extension attempted to access an undeclared domain.';
    } else if (lower.contains('cloudflare') ||
        lower.contains('captcha') ||
        lower.contains('403 forbidden')) {
      _errorMessage =
          'This source is currently protected by Cloudflare or bot verification. '
          'You may need to open it in a browser or log in.';
    } else if (lower.contains('timeout') ||
        lower.contains('timed out') ||
        lower.contains('sockettimeoutexception')) {
      _errorMessage =
          'The source took too long to respond. Please check your internet '
          'connection and try again.';
    } else if (lower.contains('429') || lower.contains('too many requests')) {
      _errorMessage =
          'The source is rate-limiting requests. Please wait a moment before retrying.';
    } else {
      _errorMessage =
          'Failed to load catalog. The source encountered an unexpected error.';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadInitialCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialCatalog() async {
    if (!_infoLoaded) {
      setState(() => _isLoading = true);
      try {
        final info = await SourceRegistry.instance.getCatalogInfo(
          widget.sourceMeta.id,
        );
        if (!mounted) return;
        setState(() {
          _catalogInfo = info;
          _infoLoaded = true;
        });
      } catch (error) {
        if (mounted) {
          setState(() {
            _setError(error);
            _isLoading = false;
          });
        }
        return;
      }
    }
    await _performSearch('');
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    final generation = ++_searchGeneration;
    setState(() {
      _isLoading = true;
      _loadingMore = false;
      _errorMessage = null;
      _rawErrorDetails = null;
      _showErrorDetails = false;
      _searchQuery = query.trim();
      _page = 0;
      _hasMore = false;
    });

    try {
      final results = await SourceRegistry.instance.searchSource(
        widget.sourceMeta.id,
        query.trim(),
        listing: query.trim().isEmpty ? _listingIndex : null,
      );
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _novels = results;
          _hasMore = results.isNotEmpty && _canIncrement;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _setError(e);
          _isLoading = false;
          _novels = [];
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _isLoading) return;
    final generation = _searchGeneration;
    setState(() => _loadingMore = true);
    try {
      final results = await SourceRegistry.instance.searchSource(
        widget.sourceMeta.id,
        _searchQuery,
        page: _page + 1,
        listing: _searchQuery.isEmpty ? _listingIndex : null,
      );
      if (!mounted || generation != _searchGeneration) return;
      final seen = _novels.map((novel) => novel.id).toSet();
      final added = results.where((novel) => seen.add(novel.id)).toList();
      setState(() {
        _page++;
        _novels.addAll(added);
        _hasMore = added.isNotEmpty;
      });
    } catch (error) {
      if (mounted && generation == _searchGeneration) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not load more: $error')));
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? HonColors.darkTextPrimary
        : HonColors.lightTextPrimary;
    final textSecondary = isDark
        ? HonColors.darkTextSecondary
        : HonColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        flexibleSpace: GlassStyle.richOf(context)
            ? const GlassSurface(radius: 0, child: SizedBox.expand())
            : null,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.chevron_back, color: textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: _isSearching
            ? CupertinoSearchTextField(
                controller: _searchController,
                autofocus: true,
                style: TextStyle(color: textPrimary),
                placeholder: 'Search ${widget.sourceMeta.name}...',
                onSubmitted: (val) {
                  _searchQuery = val;
                  _performSearch(val);
                },
              )
            : Text(
                widget.sourceMeta.name,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'Source filters & settings',
            icon: const Icon(Icons.tune),
            onPressed: () async {
              await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => SourceControlsScreen(
                    sourceId: widget.sourceMeta.id,
                    name: widget.sourceMeta.name,
                    info: _catalogInfo,
                  ),
                ),
              );
              if (!mounted) return;
              try {
                final info = await SourceRegistry.instance.getCatalogInfo(
                  widget.sourceMeta.id,
                );
                if (!mounted) return;
                setState(() {
                  _catalogInfo = info;
                  _infoLoaded = true;
                });
                await _performSearch(_searchQuery);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Could not reload source: $error')),
                  );
                }
              }
            },
          ),
          if (_infoLoaded && _catalogInfo.hasSearch)
            IconButton(
              icon: Icon(
                _isSearching
                    ? CupertinoIcons.xmark_circle_fill
                    : CupertinoIcons.search,
                color: textPrimary,
                size: 21,
              ),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) {
                    _searchQuery = '';
                    _searchController.clear();
                    _loadInitialCatalog();
                  }
                });
              },
            ),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Sub-bar: Selected Listing dropdown / chips
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    'Selected Listing:  ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: textSecondary,
                    ),
                  ),
                  Expanded(
                    child: PopupMenuButton<int>(
                      enabled:
                          _searchQuery.isEmpty &&
                          _catalogInfo.listings.length > 1,
                      tooltip: 'Source listing',
                      onSelected: (index) {
                        setState(() => _listingIndex = index);
                        _performSearch('');
                      },
                      itemBuilder: (_) => _catalogInfo.listings
                          .map(
                            (listing) => PopupMenuItem(
                              value: listing.index,
                              child: Text(listing.name),
                            ),
                          )
                          .toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? const Color(0xFF2C2C2E)
                              : const Color(0xFFE5E5EA),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Expanded(
                              child: Text(
                                _selectedListing,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                            ),
                            if (_catalogInfo.listings.length > 1 &&
                                _searchQuery.isEmpty)
                              Icon(
                                Icons.expand_more,
                                size: 18,
                                color: textSecondary,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Content section
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator(radius: 14)),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        CupertinoIcons.exclamationmark_triangle_fill,
                        color: HonColors.accentOrange,
                        size: 44,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Failed to load catalog',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 12,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            icon: const Icon(CupertinoIcons.refresh, size: 16),
                            label: const Text('Retry'),
                            onPressed: () => _infoLoaded
                                ? _performSearch(_searchQuery)
                                : _loadInitialCatalog(),
                          ),
                          if (_rawErrorDetails != null && _rawErrorDetails!.isNotEmpty)
                            TextButton.icon(
                              icon: Icon(
                                _showErrorDetails
                                    ? CupertinoIcons.chevron_up
                                    : CupertinoIcons.chevron_down,
                                size: 14,
                              ),
                              label: Text(_showErrorDetails ? 'Hide details' : 'Technical details'),
                              onPressed: () => setState(() => _showErrorDetails = !_showErrorDetails),
                            ),
                        ],
                      ),
                      if (_showErrorDetails && _rawErrorDetails != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          constraints: const BoxConstraints(maxHeight: 180),
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF18181A) : const Color(0xFFF1F1F4),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isDark ? Colors.white12 : Colors.black12,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Error Details',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: textSecondary,
                                    ),
                                  ),
                                  InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: () {
                                      Clipboard.setData(ClipboardData(text: _rawErrorDetails!));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Details copied to clipboard'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(CupertinoIcons.doc_on_doc, size: 12, color: textSecondary),
                                          const SizedBox(width: 4),
                                          Text(
                                            'Copy',
                                            style: TextStyle(fontSize: 11, color: textSecondary),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Expanded(
                                child: SingleChildScrollView(
                                  child: SelectableText(
                                    _rawErrorDetails!,
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11,
                                      color: textSecondary,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else if (_novels.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'No novels found matching "$_searchQuery"'
                        : 'No novels available in this catalog.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: textSecondary, height: 1.5),
                  ),
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverGrid(
                gridDelegate: bookGridLayout(context, padding: 32, gap: 12),
                delegate: SliverChildBuilderDelegate((context, index) {
                  final novel = _novels[index];
                  return _buildNovelCard(novel, textPrimary, textSecondary);
                }, childCount: _novels.length),
              ),
            ),
          if (!_isLoading && _errorMessage == null && _hasMore)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: _loadingMore
                      ? const CupertinoActivityIndicator()
                      : OutlinedButton(
                          onPressed: _loadMore,
                          child: const Text('Load more'),
                        ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }

  Widget _buildNovelCard(
    SourceNovelSummary novel,
    Color textPrimary,
    Color textSecondary,
  ) {
    return GestureDetector(
      onTap: () => _openNovelDetails(novel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 2 / 3,
            child: BookCoverWidget(
              title: novel.title,
              author: novel.author ?? widget.sourceMeta.name,
              coverPath: novel.coverUrl,
              width: double.infinity,
              height: double.infinity,
              borderRadius: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            novel.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textPrimary,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
  }

  void _openNovelDetails(SourceNovelSummary novel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SourceNovelDetailsScreen(
          novel: novel,
          sourceId: widget.sourceMeta.id,
          sourceName: widget.sourceMeta.name,
        ),
      ),
    );
  }
}

class SourceNovelDetailsScreen extends StatefulWidget {
  final SourceNovelSummary novel;
  final String sourceId;
  final String sourceName;

  const SourceNovelDetailsScreen({
    super.key,
    required this.novel,
    required this.sourceId,
    required this.sourceName,
  });

  @override
  State<SourceNovelDetailsScreen> createState() =>
      _SourceNovelDetailsScreenState();
}

class _SourceNovelDetailsScreenState extends State<SourceNovelDetailsScreen> {
  bool _isLoadingDetails = true;
  String? _detailsError;
  NovelDetails? _novelDetails;
  bool _isOpeningChapter = false;
  bool _isDownloading = false;
  bool _reverseChapters = false;
  final ScrollController _scrollController = ScrollController();

  static String cleanHtmlSynopsis(String raw) {
    if (raw.isEmpty) return raw;
    var text = raw;
    text = text.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n');
    text = text.replaceAll(RegExp(r'<p[^>]*>', caseSensitive: false), '');
    text = text.replaceAll(RegExp(r'<[^>]+>'), '');
    text = text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&hellip;', '…')
        .replaceAll('&mdash;', '—')
        .replaceAll('&ndash;', '–');
    text = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text.trim();
  }

  void _scrollToChapter(int index) {
    if (!_scrollController.hasClients) return;
    final target = (420.0 + index * 56.0).clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void initState() {
    super.initState();
    DatabaseService.instance.changeNotifier.addListener(_onDbChanged);
    final bookId = '${widget.sourceId}:${widget.novel.id}';
    DatabaseService.instance.ensureChaptersLoaded(bookId).then((_) {
      if (mounted) setState(() {});
    });
    _loadNovelDetails();
  }

  @override
  void dispose() {
    DatabaseService.instance.changeNotifier.removeListener(_onDbChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onDbChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadNovelDetails() async {
    setState(() {
      _isLoadingDetails = true;
      _detailsError = null;
    });

    try {
      final details = await SourceRegistry.instance.getNovelDetails(
        widget.sourceId,
        widget.novel.id,
        loadChapters: true,
      );
      if (mounted) {
        setState(() {
          _novelDetails = details;
          _isLoadingDetails = false;
        });
        final bookId = '${widget.sourceId}:${widget.novel.id}';
        final progress = DatabaseService.instance.getProgress(bookId);
        if (progress != null && progress.chapterIndex > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToChapter(progress.chapterIndex.toInt());
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detailsError = e.toString().replaceFirst(
            'SourceNetworkException: ',
            '',
          );
          _isLoadingDetails = false;
        });
      }
    }
  }

  Future<Book> _saveNovel() async {
    final db = DatabaseService.instance;
    final id = '${widget.sourceId}:${widget.novel.id}';
    final previous = db.getBookById(id);
    final now = DateTime.now();
    final chapters = _novelDetails?.chapters ?? [];
    final rawDesc = _novelDetails?.description ?? widget.novel.description ?? '';
    final book = Book(
      id: id,
      title: _novelDetails?.title ?? widget.novel.title,
      author: _novelDetails?.author ?? widget.novel.author ?? widget.sourceName,
      description: cleanHtmlSynopsis(rawDesc),
      format: BookFormat.webNovel,
      sourceId: widget.sourceId,
      sourceNovelId: widget.novel.id,
      totalChapters: chapters.length,
      coverPath: _novelDetails?.coverUrl ?? widget.novel.coverUrl,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
    await db.saveBook(book);
    await db.ensureChaptersLoaded(id);
    final existing = {
      for (final chapter in db.getChapters(id))
        chapter.sourceChapterId: chapter,
    };
    await db.saveChapters(id, [
      for (var i = 0; i < chapters.length; i++)
        existing[chapters[i].id]?.copyWith(
              title: chapters[i].title,
              url: chapters[i].url ?? chapters[i].id,
              chapterIndex: i.toDouble(),
            ) ??
            Chapter(
              id: '$id:${chapters[i].id}',
              bookId: id,
              sourceChapterId: chapters[i].id,
              title: chapters[i].title,
              chapterIndex: i.toDouble(),
              url: chapters[i].url ?? chapters[i].id,
              updatedAt: now,
            ),
    ]);
    return book;
  }

  Future<void> _openChapter(SourceChapter chapter, int chapterIndex) async {
    if (_isOpeningChapter) return;
    setState(() => _isOpeningChapter = true);
    try {
      final chapterUrl = chapter.url ?? chapter.id;
      final passageHtml = await SourceRegistry.instance.getChapterPassage(
        widget.sourceId,
        chapterUrl,
      );

      final book = await _saveNovel();

      if (mounted) {
        setState(() => _isOpeningChapter = false);
        await ReaderNavigator.openBook(
          context,
          book,
          initialChapterIndex: chapterIndex,
          initialChapterContent: passageHtml,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOpeningChapter = false);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Error Loading Chapter'),
            content: Text('Failed to load chapter content from source:\n$e'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  Future<void> _handleDownloadChapters([int? index]) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);
    try {
      final book = await _saveNovel();
      await DatabaseService.instance.ensureChaptersLoaded(book.id);
      final chapters = DatabaseService.instance.getChapters(book.id);
      Set<String>? selected;
      if (index != null) {
        selected = {chapters[index].id};
      } else if (mounted) {
        final progress = DatabaseService.instance.getProgress(book.id);
        selected = await showModalBottomSheet<Set<String>>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => ChapterDownloadSheet(
            chapters: chapters,
            unreadStart: DatabaseService.instance.isBookFinished(book.id)
                ? chapters.length
                : progress == null
                ? 0
                : (progress.chapterIndex.toInt() +
                          (progress.completionPercentage >= 1 ? 1 : 0))
                      .clamp(0, chapters.length),
          ),
        );
      }
      if (selected == null || selected.isEmpty) return;
      final count = await HonDownloadManager.instance.queueChapters(
        book,
        chapters.where((chapter) => selected!.contains(chapter.id)),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            count == 0
                ? 'Already saved, queued or paused.'
                : 'Queued $count chapters.',
          ),
        ),
      );
      if (count > 0) {
        unawaited(
          AddToLibraryPrompt.checkAndPrompt(
            context,
            novelId: book.id,
            novelTitle: book.title,
            onAddToLibrary: () =>
                DatabaseService.instance.setLibraryMembership(book.id, true),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not queue chapters: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _downloadNext(int count) async {
    final book = await _saveNovel();
    await DatabaseService.instance.ensureChaptersLoaded(book.id);
    final chapters = DatabaseService.instance.getChapters(book.id);
    final progress = DatabaseService.instance.getProgress(book.id);
    final start = DatabaseService.instance.isBookFinished(book.id)
        ? chapters.length
        : progress == null
            ? 0
            : (progress.chapterIndex.toInt() +
                (progress.completionPercentage >= 1 ? 1 : 0))
                .clamp(0, chapters.length);
    final targets = chapters
        .skip(start)
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
    }
  }

  Future<void> _deleteReadDownloads() async {
    final book = await _saveNovel();
    final progress = DatabaseService.instance.getProgress(book.id);
    if (progress == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No reading progress found.')),
        );
      }
      return;
    }
    final deleted = await DatabaseService.instance.deleteReadChapters(
      book.id,
      progress.chapterIndex.toDouble(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $deleted read chapter files.')),
      );
      setState(() {});
    }
  }

  Future<void> _deleteAllOffline() async {
    final bookId = '${widget.sourceId}:${widget.novel.id}';
    final deleted =
        await DatabaseService.instance.deleteAllDownloadedChapters(bookId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Deleted $deleted offline chapter files.')),
      );
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? HonColors.darkTextPrimary
        : HonColors.lightTextPrimary;
    final textSecondary = isDark
        ? HonColors.darkTextSecondary
        : HonColors.lightTextSecondary;

    final bookId = '${widget.sourceId}:${widget.novel.id}';
    final inLibrary = DatabaseService.instance.isBookInLibrary(bookId);

    final title = _novelDetails?.title ?? widget.novel.title;
    final author =
        _novelDetails?.author ?? widget.novel.author ?? widget.sourceName;
    final description =
        _novelDetails?.description ??
        widget.novel.description ??
        'No description available for this novel.';
    final chapters = _novelDetails?.chapters ?? [];
    final unresolved = ChapterUpdateService.instance.unresolvedChaptersByBook[bookId] ?? [];
    final savedChapters = {
      for (final item in DatabaseService.instance.getChapters(bookId))
        item.sourceChapterId: item,
    };

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        flexibleSpace: GlassStyle.richOf(context)
            ? const GlassSurface(radius: 0, child: SizedBox.expand())
            : null,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.chevron_back, color: textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _isLoadingDetails
          ? const Center(child: CupertinoActivityIndicator(radius: 14))
          : _detailsError != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.exclamationmark_triangle_fill,
                      color: HonColors.accentOrange,
                      size: 44,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Failed to load novel details',
                      style: TextStyle(
                        color: textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _detailsError!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      icon: const Icon(CupertinoIcons.refresh, size: 16),
                      label: const Text('Retry'),
                      onPressed: _loadNovelDetails,
                    ),
                  ],
                ),
              ),
            )
          : Stack(
              children: [
                CustomScrollView(
                  controller: _scrollController,
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                      sliver: SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Cover & Metadata
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                BookCoverWidget(
                                  title: title,
                                  author: author,
                                  coverPath:
                                      _novelDetails?.coverUrl ??
                                      widget.novel.coverUrl,
                                  width: 90,
                                  height: 135,
                                  borderRadius: 8,
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        title,
                                        style: TextStyle(
                                          fontFamily: 'Newsreader',
                                          fontSize: 26,
                                          fontWeight: FontWeight.w600,
                                          color: textPrimary,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        author,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: textSecondary,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Source: ${widget.sourceName}',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: HonColors.accentOrange,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // Add to Library Button
                                      OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: inLibrary
                                              ? HonColors.accentGreen
                                              : textPrimary,
                                          side: BorderSide(
                                            color: inLibrary
                                                ? HonColors.accentGreen
                                                : (isDark
                                                      ? Colors.white24
                                                      : Colors.black26),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              16,
                                            ),
                                          ),
                                        ),
                                        icon: Icon(
                                          inLibrary
                                              ? CupertinoIcons.checkmark_alt
                                              : CupertinoIcons.heart,
                                          size: 16,
                                        ),
                                        label: Text(
                                          inLibrary
                                              ? 'In Library'
                                              : 'Add to Library',
                                        ),
                                        onPressed: () async {
                                          final db = DatabaseService.instance;
                                          final newStatus = !inLibrary;
                                          if (newStatus) await _saveNovel();
                                          await db.setLibraryMembership(
                                            bookId,
                                            newStatus,
                                          );
                                          if (mounted) setState(() {});
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 20),

                            // Synopsis
                            Text(
                              'Synopsis',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              description,
                              style: TextStyle(
                                fontSize: 13,
                                height: 1.45,
                                color: textSecondary,
                              ),
                            ),

                            const SizedBox(height: 24),

                            // Action row
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: HonColors.accentOrange,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: const Icon(
                                      CupertinoIcons.book,
                                      size: 18,
                                    ),
                                    label: const Text('Read Online'),
                                    onPressed: chapters.isNotEmpty
                                        ? () => _openChapter(chapters.first, 0)
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: textPrimary,
                                      side: BorderSide(
                                        color: isDark
                                            ? Colors.white24
                                            : Colors.black26,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                    ),
                                    icon: const Icon(
                                      CupertinoIcons.arrow_down_circle,
                                      size: 18,
                                    ),
                                    label: const Text('Download'),
                                    onPressed:
                                        chapters.isNotEmpty && !_isDownloading
                                        ? () => _handleDownloadChapters()
                                        : null,
                                  ),
                                ),
                              ],
                            ),

                            if (unresolved.isNotEmpty) ...[
                              const SizedBox(height: 20),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: Colors.amber.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.amber.withValues(alpha: 0.35),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const Icon(
                                          CupertinoIcons.exclamationmark_triangle_fill,
                                          size: 16,
                                          color: Colors.amber,
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'Needs review (${unresolved.length})',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                            color: Colors.amber,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'These previously saved chapters were removed or altered upstream. Saved offline content remains accessible.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: textPrimary.withValues(alpha: 0.75),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    ...unresolved.map((ch) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 3),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            CupertinoIcons.doc_text,
                                            size: 13,
                                            color: Colors.amber,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              ch.title,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: textPrimary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    )),
                                  ],
                                ),
                              ),
                            ],

                            const SizedBox(height: 28),

                            // Chapter List Header
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Chapters (${chapters.length})',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        CupertinoIcons.sort_down,
                                        size: 18,
                                      ),
                                      tooltip: _reverseChapters
                                          ? 'Oldest chapter first'
                                          : 'Newest chapter first',
                                      onPressed: () => setState(
                                        () =>
                                            _reverseChapters = !_reverseChapters,
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      tooltip: 'Bulk chapter options',
                                      icon: const Icon(
                                        CupertinoIcons.ellipsis_circle,
                                        size: 20,
                                      ),
                                      onSelected: (value) async {
                                        switch (value) {
                                          case 'next5':
                                            await _downloadNext(5);
                                            break;
                                          case 'next10':
                                            await _downloadNext(10);
                                            break;
                                          case 'next25':
                                            await _downloadNext(25);
                                            break;
                                          case 'custom':
                                            await _handleDownloadChapters();
                                            break;
                                          case 'deleteRead':
                                            await _deleteReadDownloads();
                                            break;
                                          case 'deleteAll':
                                            await _deleteAllOffline();
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
                                        const PopupMenuItem(
                                          value: 'custom',
                                          child: Text(
                                            'Select range / chapters...',
                                          ),
                                        ),
                                        const PopupMenuDivider(),
                                        const PopupMenuItem(
                                          value: 'deleteRead',
                                          child: Text('Delete read chapters'),
                                        ),
                                        const PopupMenuItem(
                                          value: 'deleteAll',
                                          child: Text(
                                            'Delete all offline files',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      sliver: SliverList.builder(
                        itemCount: chapters.length,
                        itemBuilder: (context, position) {
                          final index = _reverseChapters
                              ? chapters.length - 1 - position
                              : position;
                          final chapter = chapters[index];
                          final saved = savedChapters[chapter.id];
                          final state =
                              saved?.downloadState ??
                              ChapterDownloadState.notDownloaded;

                          Widget trailingWidget;
                          String? subtitleText;

                          switch (state) {
                            case ChapterDownloadState.downloaded:
                              subtitleText = 'Saved offline';
                              trailingWidget = const Icon(
                                CupertinoIcons.checkmark_circle_fill,
                                color: HonColors.accentGreen,
                                size: 20,
                              );
                              break;
                            case ChapterDownloadState.downloading:
                              subtitleText = 'Downloading...';
                              trailingWidget = const SizedBox(
                                width: 22,
                                height: 22,
                                child: CupertinoActivityIndicator(radius: 9),
                              );
                              break;
                            case ChapterDownloadState.queued:
                              subtitleText = 'Queued';
                              trailingWidget = Icon(
                                CupertinoIcons.clock,
                                color: textSecondary,
                                size: 20,
                              );
                              break;
                            case ChapterDownloadState.paused:
                              subtitleText = 'Paused';
                              trailingWidget = IconButton(
                                tooltip: 'Resume download',
                                onPressed: saved == null
                                    ? null
                                    : () => HonDownloadManager.instance
                                        .resumeDownload(saved.id),
                                icon: const Icon(
                                  CupertinoIcons.pause_circle_fill,
                                  color: HonColors.accentOrange,
                                  size: 20,
                                ),
                              );
                              break;
                            case ChapterDownloadState.failed:
                              subtitleText = 'Download failed';
                              trailingWidget = IconButton(
                                tooltip: 'Retry download',
                                onPressed: saved == null
                                    ? null
                                    : () => HonDownloadManager.instance
                                        .resumeDownload(saved.id),
                                icon: Icon(
                                  CupertinoIcons.exclamationmark_circle_fill,
                                  color: Theme.of(context).colorScheme.error,
                                  size: 20,
                                ),
                              );
                              break;
                            case ChapterDownloadState.notDownloaded:
                              trailingWidget = IconButton(
                                tooltip: 'Download chapter',
                                onPressed: _isDownloading
                                    ? null
                                    : () => _handleDownloadChapters(index),
                                icon: const Icon(
                                  CupertinoIcons.arrow_down_circle,
                                  size: 22,
                                ),
                              );
                              break;
                          }

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 6,
                            ),
                            title: Text(
                              chapter.title,
                              style: const TextStyle(fontSize: 14),
                            ),
                            subtitle: subtitleText != null
                                ? Text(
                                    subtitleText,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color:
                                          state == ChapterDownloadState.failed
                                          ? Theme.of(context).colorScheme.error
                                          : state ==
                                                ChapterDownloadState.downloaded
                                          ? HonColors.accentGreen
                                          : textSecondary,
                                    ),
                                  )
                                : null,
                            onTap: () => _openChapter(chapter, index),
                            trailing: trailingWidget,
                          );
                        },
                      ),
                    ),
                  ],
                ),

                if (_isOpeningChapter)
                  Container(
                    color: Colors.black45,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CupertinoActivityIndicator(
                            radius: 16,
                            color: Colors.white,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Loading chapter content from source...',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
