import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../core/database/database_service.dart';
import '../../../core/downloads/hon_download_manager.dart';
import '../../../core/files/storage_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/chapter.dart';
import '../../../core/models/download_job.dart';
import '../../../core/models/novel_source.dart';
import '../../../core/sources/source_registry.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_navigator.dart';
import '../../sheets/add_to_library_prompt.dart';

class SourceCatalogScreen extends StatefulWidget {
  final ExtensionMeta sourceMeta;

  const SourceCatalogScreen({
    super.key,
    required this.sourceMeta,
  });

  @override
  State<SourceCatalogScreen> createState() => _SourceCatalogScreenState();
}

class _SourceCatalogScreenState extends State<SourceCatalogScreen> {
  final String _selectedListing = 'Browse';
  String _searchQuery = '';
  bool _isSearching = false;
  bool _isLoading = false;
  String? _errorMessage;
  List<SourceNovelSummary> _novels = [];
  final TextEditingController _searchController = TextEditingController();

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
    await _performSearch('pride');
  }

  Future<void> _performSearch(String query) async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final results = await SourceRegistry.instance.searchSource(
        widget.sourceMeta.id,
        query.trim().isEmpty ? 'pride' : query.trim(),
      );
      if (mounted) {
        setState(() {
          _novels = results;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString().replaceFirst('SourceNetworkException: ', '');
          _isLoading = false;
          _novels = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final textSecondary = isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary;

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
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
            icon: Icon(
              _isSearching ? CupertinoIcons.xmark_circle_fill : CupertinoIcons.search,
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
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF334E68),
        icon: const Icon(CupertinoIcons.slider_horizontal_3, size: 18, color: Colors.white),
        label: const Text('Filter', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Filter presets: All languages, Popular & New')),
          );
        },
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _selectedListing,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textPrimary,
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
              child: Center(
                child: CupertinoActivityIndicator(radius: 14),
              ),
            )
          else if (_errorMessage != null)
            SliverFillRemaining(
              child: Center(
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
                        style: TextStyle(color: textSecondary, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        icon: const Icon(CupertinoIcons.refresh, size: 16),
                        label: const Text('Retry'),
                        onPressed: () => _performSearch(_searchQuery),
                      ),
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
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.53,
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final novel = _novels[index];
                    return _buildNovelCard(novel, textPrimary, textSecondary);
                  },
                  childCount: _novels.length,
                ),
              ),
            ),
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
          Expanded(
            child: BookCoverWidget(
              title: novel.title,
              author: novel.author ?? widget.sourceMeta.name,
              coverPath: novel.coverUrl,
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
  State<SourceNovelDetailsScreen> createState() => _SourceNovelDetailsScreenState();
}

class _SourceNovelDetailsScreenState extends State<SourceNovelDetailsScreen> {
  bool _isLoadingDetails = true;
  String? _detailsError;
  NovelDetails? _novelDetails;
  bool _isOpeningChapter = false;

  @override
  void initState() {
    super.initState();
    DatabaseService.instance.changeNotifier.addListener(_onDbChanged);
    _loadNovelDetails();
  }

  @override
  void dispose() {
    DatabaseService.instance.changeNotifier.removeListener(_onDbChanged);
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
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _detailsError = e.toString().replaceFirst('SourceNetworkException: ', '');
          _isLoadingDetails = false;
        });
      }
    }
  }

  Future<void> _openChapter(SourceChapter chapter, int chapterIndex) async {
    setState(() => _isOpeningChapter = true);
    try {
      final chapterUrl = chapter.url ?? chapter.id;
      final passageHtml = await SourceRegistry.instance.getChapterPassage(
        widget.sourceId,
        chapterUrl,
      );

      final bookId = '${widget.sourceId}:${widget.novel.id}';
      final book = Book(
        id: bookId,
        title: _novelDetails?.title ?? widget.novel.title,
        author: _novelDetails?.author ?? widget.novel.author ?? widget.sourceName,
        description: _novelDetails?.description ?? widget.novel.description ?? '',
        format: BookFormat.webNovel,
        sourceId: widget.sourceId, // Real machine source ID
        totalChapters: _novelDetails?.chapters.length ?? 1,
        coverPath: _novelDetails?.coverUrl ?? widget.novel.coverUrl,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Save book record
      await DatabaseService.instance.saveBook(book);

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

  Future<void> _handleDownloadChapters() async {
    final chapters = _novelDetails?.chapters ?? [];
    if (chapters.isEmpty) return;
    final ch = chapters.first;

    final bookId = '${widget.sourceId}:${widget.novel.id}';
    final book = Book(
      id: bookId,
      title: _novelDetails?.title ?? widget.novel.title,
      author: _novelDetails?.author ?? widget.novel.author ?? widget.sourceName,
      description: _novelDetails?.description ?? widget.novel.description ?? '',
      format: BookFormat.webNovel,
      sourceId: widget.sourceId,
      totalChapters: chapters.length,
      coverPath: _novelDetails?.coverUrl ?? widget.novel.coverUrl,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    // 1. Save book record
    await DatabaseService.instance.saveBook(book);

    // 2. Compute managed destination path and save Chapter record BEFORE scheduling WorkManager
    final chapterId = '$bookId:${ch.id}';
    final jobId = 'dl_${bookId}_${ch.id}'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final storage = StorageService.instance;
    final filePrefix = bookId.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    final targetPath = '${storage.chaptersDir.path}/${filePrefix}_ch1.html';

    final dbChapter = Chapter(
      id: chapterId,
      bookId: bookId,
      sourceChapterId: ch.id,
      title: ch.title,
      chapterIndex: 0,
      url: ch.url ?? ch.id,
      localFilePath: targetPath, // Persisted before scheduling!
      downloadState: ChapterDownloadState.queued,
      updatedAt: DateTime.now(),
    );
    await DatabaseService.instance.saveChapters(bookId, [dbChapter]);

    // 3. Durably enqueue download job
    final job = DownloadJob(
      id: jobId,
      bookId: bookId,
      chapterId: chapterId,
      chapterTitle: ch.title,
      sourceId: widget.sourceId,
      status: DownloadStatus.queued,
      progress: 0.0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await DatabaseService.instance.enqueueDownload(job);

    // 4. Trigger Add-to-Library prompt non-blockingly without conditioning download creation
    if (mounted) {
      unawaited(AddToLibraryPrompt.checkAndPrompt(
        context,
        novelId: bookId,
        novelTitle: widget.novel.title,
        onAddToLibrary: () async {
          await DatabaseService.instance.setLibraryMembership(bookId, true);
          if (mounted) setState(() {});
        },
      ));
    }

    // 5. Delegate to HonDownloadManager / Android WorkManager as the sole executor.
    // Competing foreground downloads are removed; WorkManager executes out-of-process.
    await HonDownloadManager.instance.enqueueDownload(job);

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading "${ch.title}" in background...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final textSecondary = isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary;

    final bookId = '${widget.sourceId}:${widget.novel.id}';
    final inLibrary = DatabaseService.instance.isBookInLibrary(bookId);

    final title = _novelDetails?.title ?? widget.novel.title;
    final author = _novelDetails?.author ?? widget.novel.author ?? widget.sourceName;
    final description = _novelDetails?.description ?? widget.novel.description ?? 'No description available for this novel.';
    final chapters = _novelDetails?.chapters ?? [];

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      appBar: AppBar(
        backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
        elevation: 0,
        leading: IconButton(
          icon: Icon(CupertinoIcons.chevron_back, color: textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
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
                        const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: HonColors.accentOrange, size: 44),
                        const SizedBox(height: 12),
                        Text('Failed to load novel details', style: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        Text(_detailsError!, textAlign: TextAlign.center, style: TextStyle(color: textSecondary, fontSize: 13)),
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
                    ListView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      children: [
                        // Cover & Metadata
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            BookCoverWidget(
                              title: title,
                              author: author,
                              coverPath: _novelDetails?.coverUrl ?? widget.novel.coverUrl,
                              width: 90,
                              height: 135,
                              borderRadius: 8,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
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
                                    style: const TextStyle(fontSize: 12, color: HonColors.accentOrange),
                                  ),
                                  const SizedBox(height: 12),

                                  // Add to Library Button
                                  OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: inLibrary ? HonColors.accentGreen : textPrimary,
                                      side: BorderSide(
                                        color: inLibrary ? HonColors.accentGreen : (isDark ? Colors.white24 : Colors.black26),
                                      ),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                    ),
                                    icon: Icon(
                                      inLibrary ? CupertinoIcons.checkmark_alt : CupertinoIcons.heart,
                                      size: 16,
                                    ),
                                    label: Text(inLibrary ? 'In Library' : 'Add to Library'),
                                    onPressed: () async {
                                      final db = DatabaseService.instance;
                                      final newStatus = !inLibrary;
                                      await db.setLibraryMembership(bookId, newStatus);
                                      setState(() {});
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
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          description,
                          style: TextStyle(fontSize: 13, height: 1.45, color: textSecondary),
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
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(CupertinoIcons.book, size: 18),
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
                                  side: BorderSide(color: isDark ? Colors.white24 : Colors.black26),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                icon: const Icon(CupertinoIcons.arrow_down_circle, size: 18),
                                label: const Text('Download Ch 1'),
                                onPressed: chapters.isNotEmpty ? _handleDownloadChapters : null,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 28),

                        // Chapter List Header
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Chapters (${chapters.length})',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textPrimary),
                            ),
                            IconButton(
                              icon: const Icon(CupertinoIcons.sort_down, size: 18),
                              onPressed: () {},
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // Chapters list
                        ...chapters.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final ch = entry.value;

                          return InkWell(
                            onTap: () => _openChapter(ch, idx),
                            borderRadius: BorderRadius.circular(8),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      ch.title,
                                      style: TextStyle(fontSize: 14, color: textPrimary, fontWeight: FontWeight.w500),
                                    ),
                                  ),
                                  Icon(CupertinoIcons.arrow_down_circle, size: 18, color: textSecondary),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),

                    if (_isOpeningChapter)
                      Container(
                        color: Colors.black45,
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CupertinoActivityIndicator(radius: 16, color: Colors.white),
                              SizedBox(height: 12),
                              Text(
                                'Loading chapter content from source...',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
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
