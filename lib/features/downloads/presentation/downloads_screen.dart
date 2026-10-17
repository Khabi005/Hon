import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/download_job.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_navigator.dart';

class ChapterUpdateItem {
  final String novelTitle;
  final String chapterTitle;
  final String date;
  final bool isDownloaded;
  final Book? book;

  const ChapterUpdateItem({
    required this.novelTitle,
    required this.chapterTitle,
    required this.date,
    this.isDownloaded = false,
    this.book,
  });
}

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _selectedTabIndex = 0; // 0: Downloads, 1: Updates

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(allDownloadJobsProvider);
    final libraryBooks = ref.watch(libraryBooksProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final textSecondary = isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary;

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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _selectedTabIndex == 0 ? 'Downloads' : 'Updates',
                      style: HonTypography.largeTitle(color: textPrimary),
                    ),
                    if (_selectedTabIndex == 0 && jobs.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          final db = DatabaseService.instance;
                          for (final j in jobs) {
                            if (j.status == DownloadStatus.completed) {
                              db.removeDownloadJob(j.id);
                            }
                          }
                        },
                        child: const Text('Clear Completed'),
                      )
                    else if (_selectedTabIndex == 1)
                      IconButton(
                        icon: const Icon(CupertinoIcons.arrow_clockwise, size: 20),
                        color: textPrimary,
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Checking library novels for new chapters...')),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),

            // Mini Tabs: Downloads | Updates
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _buildTabButton('Downloads', 0, jobs.isNotEmpty ? '${jobs.length}' : null, isDark),
                      _buildTabButton('Updates', 1, null, isDark),
                    ],
                  ),
                ),
              ),
            ),

            // Content Body based on selected tab
            if (_selectedTabIndex == 0)
              ..._buildDownloadsTab(jobs, textPrimary, textSecondary, isDark)
            else
              ..._buildUpdatesTab(libraryBooks, textPrimary, textSecondary, isDark),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String title, int index, String? badge, bool isDark) {
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.black)
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: HonColors.accentOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildDownloadsTab(
    List<DownloadJob> jobs,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    return [
      // Storage Overview Card
      SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Container(
            padding: const EdgeInsets.all(16),
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
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: HonColors.accentGreen.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    CupertinoIcons.device_phone_portrait,
                    color: HonColors.accentGreen,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Offline Reading Storage',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${jobs.where((j) => j.status == DownloadStatus.completed).length} chapters ready offline in airplane mode.',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

      // Jobs List
      if (jobs.isEmpty)
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.arrow_down_circle,
                  size: 56,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
                const SizedBox(height: 16),
                Text(
                  'No Active Downloads',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Novel chapters queued for offline reading appear here.',
                  style: TextStyle(fontSize: 13, color: textSecondary),
                ),
              ],
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final job = jobs[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          job.status == DownloadStatus.completed
                              ? CupertinoIcons.check_mark_circled_solid
                              : CupertinoIcons.arrow_down_circle,
                          color: job.status == DownloadStatus.completed
                              ? HonColors.accentGreen
                              : HonColors.accentOrange,
                          size: 24,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                job.chapterTitle,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                job.status == DownloadStatus.completed
                                    ? 'Downloaded & ready offline'
                                    : 'Downloading... ${(job.progress * 100).toInt()}%',
                                style: TextStyle(fontSize: 12, color: textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (job.status == DownloadStatus.completed)
                          TextButton(
                            child: const Text('Read'),
                            onPressed: () {
                              final book = DatabaseService.instance.getBookById(job.bookId);
                              if (book != null) {
                                ReaderNavigator.openBook(context, book);
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
              childCount: jobs.length,
            ),
          ),
        ),
    ];
  }

  List<Widget> _buildUpdatesTab(
    List<Book> libraryBooks,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    // Note: Live upstream chapter updates will be populated when Phase 0C Lua extensions are integrated.
    // We intentionally do not fabricate mock updates.
    final updates = <ChapterUpdateItem>[];

    return [
      if (updates.isEmpty)
        SliverFillRemaining(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.clock, size: 48, color: textSecondary.withOpacity(0.4)),
                const SizedBox(height: 12),
                Text(
                  'No Chapter Updates',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Chapter update tracking will be activated once novel extensions are connected in Phase 0C.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: textSecondary),
                  ),
                ),
              ],
            ),
          ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = updates[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: InkWell(
                    onTap: () {
                      if (item.book != null) {
                        ReaderNavigator.openBook(context, item.book!);
                      }
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          if (item.book != null)
                            BookCoverWidget(
                              title: item.book!.title,
                              author: item.book!.author,
                              coverPath: item.book!.coverPath,
                              width: 44,
                              height: 62,
                              borderRadius: 4,
                            )
                          else
                            Container(
                              width: 44,
                              height: 62,
                              decoration: BoxDecoration(
                                color: HonColors.accentOrange.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Icon(CupertinoIcons.book, size: 20),
                            ),
                          const SizedBox(width: 14),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.novelTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: HonColors.accentBlue,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      item.chapterTitle,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: textSecondary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          Icon(
                            item.isDownloaded
                                ? CupertinoIcons.check_mark_circled_solid
                                : CupertinoIcons.arrow_down_circle,
                            color: item.isDownloaded ? HonColors.accentGreen : textSecondary,
                            size: 22,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: updates.length,
            ),
          ),
        ),
    ];
  }
}
