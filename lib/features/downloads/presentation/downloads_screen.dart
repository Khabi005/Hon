import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../shared/widgets/hon_large_title_header.dart';
import '../../../core/database/database_service.dart';
import '../../../core/downloads/hon_download_manager.dart';
import '../../../core/models/book.dart';
import '../../../core/models/download_job.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../../shared/widgets/hon_empty_state.dart';
import '../../../shared/widgets/hon_segmented_control.dart';
import '../../reader/presentation/reader_navigator.dart';
import '../../library/presentation/library_updates_screen.dart';

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});
  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _tab = 0;
  final Set<String> _busy = {};

  Future<void> _act(DownloadJob job, {bool cancel = false}) async {
    if (!_busy.add(job.id)) return;
    setState(() {});
    try {
      final manager = HonDownloadManager.instance;
      if (cancel) {
        await manager.cancelDownload(job.id);
      } else {
        await manager.resumeDownload(job.id);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update download: $error')),
        );
      }
    } finally {
      _busy.remove(job.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTab = ref.watch(navigationTabProvider) == 4;
    final jobs =
        [
          ...(activeTab
              ? ref.watch(allDownloadJobsProvider)
              : ref.read(allDownloadJobsProvider)),
        ]..sort((a, b) {
          if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
          return b.updatedAt.compareTo(a.updatedAt);
        });
    final db = DatabaseService.instance;
    final offline = db
        .getAllBooks()
        .where(
          (book) =>
              (book.format != BookFormat.webNovel && book.filePath != null) ||
              db.hasDownloadedChapters(book.id),
        )
        .toList();
    final chapterCount = db.getTotalDownloadedChapters();
    final imported = offline
        .where((book) => book.format != BookFormat.webNovel)
        .length;
    final downloading = jobs
        .where((job) => job.status == DownloadStatus.running)
        .length;
    final queued = jobs
        .where(
          (job) =>
              job.status == DownloadStatus.queued ||
              job.status == DownloadStatus.retryWaiting,
        )
        .length;
    final paused = jobs
        .where((job) => job.status == DownloadStatus.paused)
        .length;
    String queueLabel;
    if (downloading > 0) {
      queueLabel =
          'Queue · $downloading downloading${queued > 0 ? ', $queued queued' : ''}';
    } else if (queued > 0) {
      queueLabel = 'Queue · $queued queued';
    } else if (paused > 0) {
      queueLabel = 'Queue · $paused paused';
    } else {
      queueLabel = 'Queue';
    }
    final completed = jobs
        .where((job) => job.status == DownloadStatus.completed)
        .toList();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('downloads-scroll'),
          slivers: [
            SliverHonLargeTitle(
              title: 'Downloads',
              actions: [
                IconButton(
                  tooltip: 'Library updates',
                  icon: const Icon(Icons.update),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const LibraryUpdatesScreen(),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Queue controls',
                  onSelected: (value) async {
                    try {
                      if (value == 'pause') {
                        await HonDownloadManager.instance.pauseAll();
                      } else {
                        await HonDownloadManager.instance.resumeAll();
                      }
                    } catch (error) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text('$error')));
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'pause',
                      child: Text('Pause all downloads'),
                    ),
                    const PopupMenuItem(
                      value: 'resume',
                      child: Text('Resume paused downloads'),
                    ),
                  ],
                ),
                if (_tab == 0 && completed.isNotEmpty)
                  PopupMenuButton<String>(
                    tooltip: 'Download queue options',
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'clear',
                        child: Text('Clear completed history'),
                      ),
                    ],
                    onSelected: (_) async {
                      for (final job in completed) {
                        await db.removeDownloadJob(job.id);
                      }
                    },
                  ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              sliver: SliverToBoxAdapter(
                child: HonSegmentedControl(
                  labels: [queueLabel, 'Ready Offline'],
                  selected: _tab,
                  onChanged: (value) => setState(() => _tab = value),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
              sliver: SliverToBoxAdapter(
                child: Text(
                  '$chapterCount saved chapters · $imported imported ${imported == 1 ? 'book' : 'books'}',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            if (_tab == 0 && jobs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: HonEmptyState(
                  icon: CupertinoIcons.arrow_down_circle,
                  title: 'Take your next chapter offline',
                  message:
                      'Downloads appear here as you save chapters. Clearing queue history keeps your saved files.',
                  actionLabel: 'Browse Sources',
                  onAction: () =>
                      ref.read(navigationTabProvider.notifier).state = 2,
                ),
              )
            else if (_tab == 1 && offline.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: HonEmptyState(
                  icon: CupertinoIcons.book,
                  title: 'A shelf for wherever you go',
                  message:
                      'Imported books and downloaded novels will be collected here.',
                  actionLabel: 'Open Library',
                  onAction: () =>
                      ref.read(navigationTabProvider.notifier).state = 1,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                sliver: SliverList.builder(
                  itemCount: _tab == 0 ? jobs.length : offline.length,
                  itemBuilder: (context, index) => _tab == 0
                      ? _job(context, jobs[index])
                      : _offlineBook(context, offline[index]),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
          ],
        ),
      ),
    );
  }

  Widget _offlineBook(BuildContext context, Book book) {
    final colors = Theme.of(context).colorScheme;
    final count = DatabaseService.instance.getDownloadedChapterCount(book.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => ReaderNavigator.openBook(context, book),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                BookCoverWidget(
                  title: book.title,
                  author: book.author,
                  coverPath: book.coverPath,
                  width: 48,
                  height: 72,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        book.format == BookFormat.webNovel
                            ? '$count saved chapters'
                            : '${book.format.name.toUpperCase()} · On this device',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 15,
                  color: colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _job(BuildContext context, DownloadJob job) {
    final colors = Theme.of(context).colorScheme;
    final db = DatabaseService.instance;
    final book = db.getBookById(job.bookId);
    final label = switch (job.status) {
      DownloadStatus.queued => 'Queued',
      DownloadStatus.running =>
        'Downloading · ${(job.progress.clamp(0, 1) * 100).round()}%',
      DownloadStatus.completed => 'Saved for offline reading',
      DownloadStatus.retryWaiting => 'Waiting to retry',
      DownloadStatus.paused => 'Paused',
      DownloadStatus.cancelled => 'Cancelled',
      DownloadStatus.failed => 'Download failed',
    };
    final failed =
        job.status == DownloadStatus.failed ||
        job.status == DownloadStatus.retryWaiting;
    final canRetry = !job.isActive && job.status != DownloadStatus.completed;
    return Padding(
      key: ValueKey(job.id),
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              switch (job.status) {
                DownloadStatus.completed => const Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: HonColors.accentGreen,
                  size: 24,
                ),
                DownloadStatus.running => const SizedBox(
                  width: 24,
                  height: 24,
                  child: CupertinoActivityIndicator(radius: 10),
                ),
                DownloadStatus.queued => Icon(
                  CupertinoIcons.clock,
                  color: colors.onSurfaceVariant,
                  size: 24,
                ),
                DownloadStatus.retryWaiting => const Icon(
                  CupertinoIcons.clock_fill,
                  color: HonColors.accentOrange,
                  size: 24,
                ),
                DownloadStatus.paused => const Icon(
                  CupertinoIcons.pause_circle_fill,
                  color: HonColors.accentOrange,
                  size: 24,
                ),
                DownloadStatus.failed => Icon(
                  CupertinoIcons.exclamationmark_circle_fill,
                  color: colors.error,
                  size: 24,
                ),
                DownloadStatus.cancelled => Icon(
                  CupertinoIcons.xmark_circle,
                  color: colors.onSurfaceVariant,
                  size: 24,
                ),
              },
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (book != null)
                      Text(
                        book.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 3),
                    Text(
                      job.chapterTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: failed ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                    if (job.status == DownloadStatus.running) ...[
                      const SizedBox(height: 10),
                      LinearProgressIndicator(
                        value: job.progress > 0
                            ? job.progress.clamp(0, 1)
                            : null,
                        minHeight: 3,
                      ),
                    ],
                    if (failed && job.errorMessage?.isNotEmpty == true)
                      Text(
                        job.errorMessage!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.5,
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (_busy.contains(job.id))
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: CupertinoActivityIndicator(),
                )
              else if (job.isActive)
                PopupMenuButton<String>(
                  tooltip: 'Download actions',
                  onSelected: (action) async {
                    if (action == 'cancel') {
                      await _act(job, cancel: true);
                    } else {
                      try {
                        await HonDownloadManager.instance.pauseDownload(job.id);
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(
                            context,
                          ).showSnackBar(SnackBar(content: Text('$error')));
                        }
                      }
                    }
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'pause', child: Text('Pause')),
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Text('Cancel download'),
                    ),
                  ],
                )
              else if (canRetry)
                IconButton(
                  tooltip: job.status == DownloadStatus.paused
                      ? 'Resume download'
                      : 'Retry download',
                  icon: const Icon(CupertinoIcons.arrow_clockwise, size: 20),
                  onPressed: () => _act(job),
                )
              else if (book != null)
                IconButton(
                  tooltip: 'Read chapter',
                  icon: const Icon(CupertinoIcons.book, size: 20),
                  onPressed: () async {
                    await db.ensureChaptersLoaded(book.id);
                    if (context.mounted) {
                      await ReaderNavigator.openBook(
                        context,
                        book,
                        initialChapterIndex: db
                            .getChapters(book.id)
                            .where((c) => c.id == job.chapterId)
                            .firstOrNull
                            ?.chapterIndex
                            .toInt(),
                      );
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
