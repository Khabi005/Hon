import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/download_job.dart';
import '../../reader/presentation/reader_screen.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(allDownloadJobsProvider);
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Downloads',
                      style: HonTypography.largeTitle(color: textPrimary),
                    ),
                    if (jobs.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          // Clear completed
                          final db = DatabaseService.instance;
                          for (final j in jobs) {
                            if (j.status == DownloadStatus.completed) {
                              db.removeDownloadJob(j.id);
                            }
                          }
                        },
                        child: const Text('Clear Completed'),
                      ),
                  ],
                ),
              ),
            ),

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
                              style: TextStyle(
                                fontSize: 12,
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
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Downloaded novel chapters will appear here.',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                      final job = jobs[i];
                      return _buildJobItem(context, job, isDark, textPrimary);
                    },
                    childCount: jobs.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildJobItem(BuildContext context, DownloadJob job, bool isDark, Color textPrimary) {
    final book = DatabaseService.instance.getBookById(job.bookId);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? HonColors.darkCardBorder : HonColors.lightCardBorder,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Icon(
            job.status == DownloadStatus.completed
                ? CupertinoIcons.check_mark_circled_solid
                : CupertinoIcons.arrow_down_circle_fill,
            color: job.status == DownloadStatus.completed
                ? HonColors.accentGreen
                : HonColors.accentOrange,
            size: 26,
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
                  book?.title ?? 'Online Novel',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          // Action button: If completed, tap to read!
          if (book != null && job.status == DownloadStatus.completed)
            TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
                );
              },
              child: const Text('Read'),
            )
          else
            IconButton(
              icon: const Icon(CupertinoIcons.xmark, size: 16),
              onPressed: () {
                DatabaseService.instance.removeDownloadJob(job.id);
              },
            ),
        ],
      ),
    );
  }
}
