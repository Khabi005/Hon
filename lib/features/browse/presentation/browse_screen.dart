import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/download_job.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_screen.dart';
import '../../sheets/add_to_library_prompt.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final String _selectedSource = 'Classics & Translations';

  final List<Book> _curatedNovels = [
    Book(
      id: 'src_great_gatsby',
      title: 'The Great Gatsby',
      author: 'F. Scott Fitzgerald',
      description: 'The story of the mysteriously wealthy Jay Gatsby and his love for the beautiful Daisy Buchanan.',
      format: BookFormat.webNovel,
      sourceId: 'gutenberg_source',
      totalChapters: 9,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Book(
      id: 'src_frankenstein',
      title: 'Frankenstein',
      author: 'Mary Shelley',
      description: 'A scientist creates a sentient creature in an unorthodox scientific experiment.',
      format: BookFormat.webNovel,
      sourceId: 'gutenberg_source',
      totalChapters: 24,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Book(
      id: 'src_sherlock_holmes',
      title: 'The Adventures of Sherlock Holmes',
      author: 'Arthur Conan Doyle',
      description: 'A collection of twelve short stories featuring consulting detective Sherlock Holmes.',
      format: BookFormat.webNovel,
      sourceId: 'gutenberg_source',
      totalChapters: 12,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Book(
      id: 'src_dracula',
      title: 'Dracula',
      author: 'Bram Stoker',
      description: 'The story of Count Dracula\'s attempt to move from Transylvania to England so that he may find new blood.',
      format: BookFormat.webNovel,
      sourceId: 'gutenberg_source',
      totalChapters: 27,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Book(
      id: 'src_moby_dick',
      title: 'Moby Dick',
      author: 'Herman Melville',
      description: 'The sailor Ishmael\'s narrative of the obsessive quest of Ahab, captain of the whaling ship Pequod.',
      format: BookFormat.webNovel,
      sourceId: 'gutenberg_source',
      totalChapters: 135,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
    Book(
      id: 'src_jane_eyre',
      title: 'Jane Eyre',
      author: 'Charlotte Brontë',
      description: 'A novel following the experiences of its eponymous heroine, including her growth to adulthood and her love for Mr. Rochester.',
      format: BookFormat.webNovel,
      sourceId: 'gutenberg_source',
      totalChapters: 38,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Browse',
                      style: HonTypography.largeTitle(color: textPrimary),
                    ),
                    // Source Selector
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.globe,
                            size: 14,
                            color: textPrimary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _selectedSource,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Source Categories Banner
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? HonColors.darkCardBorder : HonColors.lightCardBorder,
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: HonColors.accentOrange.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          CupertinoIcons.sparkles,
                          color: HonColors.accentOrange,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Shosetsu-Style Discovery',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Browse catalogues, explore chapters, and download for quiet offline reading.',
                              style: TextStyle(
                                fontSize: 13,
                                color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Curated Novels Grid
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.68,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 20,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final novel = _curatedNovels[i];
                    return _buildNovelCard(context, novel);
                  },
                  childCount: _curatedNovels.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNovelCard(BuildContext context, Book novel) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;

    return GestureDetector(
      onTap: () => _openNovelDetails(context, novel),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark ? HonColors.darkCardBorder : HonColors.lightCardBorder,
            width: 0.5,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Center(
                child: BookCoverWidget(
                  title: novel.title,
                  author: novel.author,
                  width: 90,
                  height: 130,
                  borderRadius: 6,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              novel.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              novel.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${novel.totalChapters} ch',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: HonColors.accentOrange,
                  ),
                ),
                Icon(
                  CupertinoIcons.cloud_download,
                  size: 16,
                  color: isDark ? Colors.white54 : Colors.black45,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openNovelDetails(BuildContext context, Book novel) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovelDetailsScreen(novel: novel),
      ),
    );
  }
}

class NovelDetailsScreen extends StatelessWidget {
  final Book novel;

  const NovelDetailsScreen({super.key, required this.novel});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.share),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Book Cover
            BookCoverWidget(
              title: novel.title,
              author: novel.author,
              width: 130,
              height: 195,
              borderRadius: 8,
            ),
            const SizedBox(height: 18),

            // Title & Author
            Text(
              novel.title,
              textAlign: TextAlign.center,
              style: HonTypography.sectionHeader(color: textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              novel.author,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 20),

            // Actions: Read & Download All
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => ReaderScreen(book: novel)),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isDark ? Colors.white : Colors.black,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Read Now', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(CupertinoIcons.arrow_down_to_line, size: 18),
                    label: const Text('Download All'),
                    onPressed: () => _handleDownloadAll(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: textPrimary,
                      side: BorderSide(
                        color: isDark ? HonColors.darkCardBorder : HonColors.lightCardBorder,
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Synopsis
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Synopsis',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              novel.description,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
              ),
            ),
            const SizedBox(height: 28),

            // Chapters Header
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Chapters (${novel.totalChapters})',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Chapter list
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: novel.totalChapters.clamp(1, 15),
              separatorBuilder: (_, __) => const Divider(),
              itemBuilder: (ctx, i) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Chapter ${i + 1}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: textPrimary,
                    ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(CupertinoIcons.arrow_down_circle),
                    onPressed: () => _handleDownloadChapter(context, i + 1),
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ReaderScreen(book: novel)),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleDownloadAll(BuildContext context) async {
    final db = DatabaseService.instance;
    await db.saveBook(novel);

    if (!context.mounted) return;
    // Section 5 Prompt: Prompt to Add to Library
    await AddToLibraryPrompt.show(context, novel: novel);

    // Queue downloads
    for (int i = 1; i <= novel.totalChapters.clamp(1, 5); i++) {
      final job = DownloadJob(
        id: 'job_${novel.id}_ch_$i',
        bookId: novel.id,
        chapterId: 'ch_$i',
        chapterTitle: 'Chapter $i',
        sourceId: novel.sourceId ?? 'source',
        status: DownloadStatus.completed,
        progress: 1.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.enqueueDownload(job);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading chapters for "${novel.title}"')),
      );
    }
  }

  Future<void> _handleDownloadChapter(BuildContext context, int chapterIndex) async {
    final db = DatabaseService.instance;
    await db.saveBook(novel);

    if (!context.mounted) return;
    // Section 5 Prompt: Prompt to Add to Library
    await AddToLibraryPrompt.show(context, novel: novel);

    final job = DownloadJob(
      id: 'job_${novel.id}_ch_$chapterIndex',
      bookId: novel.id,
      chapterId: 'ch_$chapterIndex',
      chapterTitle: 'Chapter $chapterIndex',
      sourceId: novel.sourceId ?? 'source',
      status: DownloadStatus.completed,
      progress: 1.0,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    await db.enqueueDownload(job);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded Chapter $chapterIndex')),
      );
    }
  }
}
