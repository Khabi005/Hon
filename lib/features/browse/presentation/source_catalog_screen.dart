import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
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
  final String _selectedListing = 'Hot Novel';
  String _searchQuery = '';
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final textSecondary = isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary;

    final allNovels = SourceRegistry.instance.getNovelsForSource(widget.sourceMeta.id);
    final displayedNovels = _searchQuery.trim().isEmpty
        ? allNovels
        : allNovels.where((n) {
            final q = _searchQuery.toLowerCase();
            return n.title.toLowerCase().contains(q) ||
                (n.author?.toLowerCase().contains(q) ?? false);
          }).toList();

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
                onChanged: (val) => setState(() => _searchQuery = val),
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
            const SnackBar(content: Text('Filter presets: All genres, Completed & Ongoing')),
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

          // Novels Grid (3 Columns, matching reference screenshot)
          if (displayedNovels.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _searchQuery.isNotEmpty
                        ? 'No novels found matching "$_searchQuery"'
                        : 'No online novels in this source catalog.\nUpstream Lua runtime will fetch live novels in Phase 0C.',
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
                    final novel = displayedNovels[index];
                    return _buildNovelCard(novel, textPrimary, textSecondary);
                  },
                  childCount: displayedNovels.length,
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
          sourceName: widget.sourceMeta.name,
        ),
      ),
    );
  }
}

class SourceNovelDetailsScreen extends StatefulWidget {
  final SourceNovelSummary novel;
  final String sourceName;

  const SourceNovelDetailsScreen({
    super.key,
    required this.novel,
    required this.sourceName,
  });

  @override
  State<SourceNovelDetailsScreen> createState() => _SourceNovelDetailsScreenState();
}

class _SourceNovelDetailsScreenState extends State<SourceNovelDetailsScreen> {
  final List<String> _chapters = List.generate(
    15,
    (i) => 'Chapter ${i + 1}',
  );

  Future<void> _handleDownloadChapters() async {
    final db = DatabaseService.instance;
    final bookId = 'novel_${widget.novel.id}';

    // 1. Durably record or update novel record
    final book = Book(
      id: bookId,
      title: widget.novel.title,
      author: widget.novel.author ?? widget.sourceName,
      description: widget.novel.description ?? '',
      format: BookFormat.webNovel,
      sourceId: widget.sourceName,
      totalChapters: _chapters.length,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.saveBook(book);

    // 2. Queue download job with correct model fields
    final job = DownloadJob(
      id: 'job_${DateTime.now().millisecondsSinceEpoch}',
      bookId: bookId,
      chapterId: 'ch1',
      chapterTitle: 'Chapter 1',
      sourceId: widget.sourceName,
      status: DownloadStatus.queued,
      progress: 0.0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.enqueueDownload(job);

    // 3. Prompt logic: If not in library, prompt "Add to Library?"
    if (mounted) {
      await AddToLibraryPrompt.checkAndPrompt(
        context,
        novelId: bookId,
        novelTitle: widget.novel.title,
        onAddToLibrary: () async {
          await db.setLibraryMembership(bookId, true);
        },
      );
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading Chapter 1 of "${widget.novel.title}"...')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final textSecondary = isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary;

    final inLibrary = DatabaseService.instance.isBookInLibrary('novel_${widget.novel.id}');

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
          widget.novel.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // Cover & Metadata
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCoverWidget(
                title: widget.novel.title,
                author: widget.novel.author ?? widget.sourceName,
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
                      widget.novel.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.novel.author ?? 'Unknown Author',
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
                        final bookId = 'novel_${widget.novel.id}';
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
            widget.novel.description ?? 'No description available for this novel.',
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
                  onPressed: () {
                    final book = Book(
                      id: 'novel_${widget.novel.id}',
                      title: widget.novel.title,
                      author: widget.novel.author ?? widget.sourceName,
                      description: widget.novel.description ?? '',
                      format: BookFormat.webNovel,
                      sourceId: widget.sourceName,
                      totalChapters: _chapters.length,
                      createdAt: DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    ReaderNavigator.openBook(context, book);
                  },
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
                  onPressed: _handleDownloadChapters,
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
                'Chapters (${_chapters.length})',
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
          ..._chapters.asMap().entries.map((entry) {
            final idx = entry.key;
            final chTitle = entry.value;

            return InkWell(
              onTap: () {
                final book = Book(
                  id: 'novel_${widget.novel.id}',
                  title: widget.novel.title,
                  author: widget.novel.author ?? widget.sourceName,
                  description: widget.novel.description ?? '',
                  format: BookFormat.webNovel,
                  sourceId: widget.sourceName,
                  totalChapters: _chapters.length,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
                ReaderNavigator.openBook(context, book, initialChapterIndex: idx);
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      chTitle,
                      style: TextStyle(fontSize: 14, color: textPrimary, fontWeight: FontWeight.w500),
                    ),
                    Icon(CupertinoIcons.arrow_down_circle, size: 18, color: textSecondary),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
