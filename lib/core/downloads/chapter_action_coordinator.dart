import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../database/database_service.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../models/download_job.dart';
import '../../features/sheets/add_to_library_prompt.dart';
import 'hon_download_manager.dart';

class ChapterActionCoordinator {
  static final ChapterActionCoordinator instance = ChapterActionCoordinator._();
  ChapterActionCoordinator._();

  /// Enqueues user-selected chapters for download, reports results, and triggers Add to Library prompt.
  Future<int> downloadChapters(
    BuildContext context, {
    required Book book,
    required Iterable<Chapter> chapters,
  }) async {
    final targets = chapters.toList();
    if (targets.isEmpty) return 0;

    final queued = await HonDownloadManager.instance.queueChapters(book, targets);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            queued == 0
                ? 'Already saved, queued or paused.'
                : 'Queued $queued chapter${queued == 1 ? '' : 's'}.',
          ),
        ),
      );

      if (queued > 0) {
        // As per brief: durably enqueue first, then invoke Add to Library prompt
        await AddToLibraryPrompt.checkAndPrompt(
          context,
          novelId: book.id,
          novelTitle: book.title,
          onAddToLibrary: () =>
              DatabaseService.instance.setLibraryMembership(book.id, true),
        );
      }
    }
    return queued;
  }

  /// Downloads the next N eligible chapters in canonical forward reading order.
  /// Rule: Starts at current reading chapter (or first chapter if unread).
  /// Excludes already downloaded chapters (with valid local files) AND already queued/running/paused jobs BEFORE taking N.
  Future<int> downloadNextN(
    BuildContext context, {
    required Book book,
    required int count,
    required int currentReadingIndex,
  }) async {
    final db = DatabaseService.instance;
    await db.ensureChaptersLoaded(book.id);
    final allChapters = db.getChapters(book.id);
    if (allChapters.isEmpty) return 0;

    // Canonical forward reading order: always sorted by chapterIndex ascending
    final sorted = List<Chapter>.from(allChapters)
      ..sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));

    final startIndex = currentReadingIndex.clamp(0, sorted.length);
    final activeJobs = {
      for (final j in db.getAllDownloadJobs())
        if (j.bookId == book.id && (j.isActive || j.status == DownloadStatus.paused))
          j.chapterId: j,
    };

    // Filter forward from current reading chapter
    final eligible = sorted.skip(startIndex).where((ch) {
      // 1. If currently active or paused in download queue, not eligible for new queue slot
      if (activeJobs.containsKey(ch.id)) return false;
      if (ch.downloadState == ChapterDownloadState.queued ||
          ch.downloadState == ChapterDownloadState.downloading ||
          ch.downloadState == ChapterDownloadState.paused) {
        return false;
      }

      // 2. If marked downloaded, verify file actually exists. Stale downloaded flags with missing files ARE eligible!
      if (ch.downloadState == ChapterDownloadState.downloaded) {
        if (ch.localFilePath != null && File(ch.localFilePath!).existsSync()) {
          return false;
        }
      }

      return true;
    }).take(count).toList();

    if (eligible.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No new chapters to download.')),
        );
      }
      return 0;
    }

    if (!context.mounted) return 0;
    return downloadChapters(context, book: book, chapters: eligible);
  }

  /// Prompts user with a confirmation dialog before deleting downloaded chapter files.
  Future<ChapterDeletionResult?> promptDeleteChapters(
    BuildContext context, {
    required Book book,
    required Iterable<Chapter> chapters,
    String? title,
    String? message,
  }) async {
    final targets = chapters.toList();
    if (targets.isEmpty) return null;

    final dialogTitle = title ?? 'Delete Downloaded Chapters?';
    final dialogMessage = message ??
        'Delete offline files for ${targets.length} chapter${targets.length == 1 ? '' : 's'}? '
            'Your chapter list and reading history will remain intact.';

    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(dialogTitle),
        content: Padding(
          padding: const EdgeInsets.only(top: 8.0),
          child: Text(dialogMessage),
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return null;

    final result = await DatabaseService.instance.deleteDownloadedChapters(book.id, targets);

    if (context.mounted) {
      final msg = result.hasFailures
          ? 'Deleted ${result.deletedCount} files. Failed to delete ${result.failedCount} files.'
          : 'Deleted ${result.deletedCount} chapter file${result.deletedCount == 1 ? '' : 's'}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
    return result;
  }

  /// Prompts and deletes read chapters prior to the current reading index.
  Future<ChapterDeletionResult?> promptDeleteRead(
    BuildContext context, {
    required Book book,
    required double currentChapterIndex,
  }) async {
    final db = DatabaseService.instance;
    await db.ensureChaptersLoaded(book.id);
    final toDelete = db
        .getChapters(book.id)
        .where((c) =>
            c.chapterIndex < currentChapterIndex &&
            (c.downloadState == ChapterDownloadState.downloaded || c.localFilePath != null))
        .toList();

    if (toDelete.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No downloaded read chapters to delete.')),
        );
      }
      return null;
    }

    if (!context.mounted) return null;
    return promptDeleteChapters(
      context,
      book: book,
      chapters: toDelete,
      title: 'Delete Read Chapters?',
      message: 'Delete offline files for ${toDelete.length} read chapter${toDelete.length == 1 ? '' : 's'}?',
    );
  }

  /// Prompts and deletes unread downloaded chapters (those ahead of the current reading index).
  Future<ChapterDeletionResult?> promptDeleteUnread(
    BuildContext context, {
    required Book book,
    required double currentChapterIndex,
    bool includeCurrent = false,
  }) async {
    final db = DatabaseService.instance;
    await db.ensureChaptersLoaded(book.id);
    final toDelete = db
        .getChapters(book.id)
        .where((c) {
          final isUnread = includeCurrent
              ? c.chapterIndex >= currentChapterIndex
              : c.chapterIndex > currentChapterIndex;
          return isUnread &&
              (c.downloadState == ChapterDownloadState.downloaded ||
                  c.localFilePath != null);
        })
        .toList();

    if (toDelete.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No downloaded unread chapters to delete.')),
        );
      }
      return null;
    }

    if (!context.mounted) return null;
    return promptDeleteChapters(
      context,
      book: book,
      chapters: toDelete,
      title: 'Delete Unread Chapters?',
      message: 'Delete offline files for ${toDelete.length} unread chapter${toDelete.length == 1 ? '' : 's'}?',
    );
  }

  /// Prompts user to input a custom count N of chapters to download forward from the current reading chapter.
  Future<int> promptDownloadCustomN(
    BuildContext context, {
    required Book book,
    required int currentReadingIndex,
  }) async {
    final controller = TextEditingController(text: '10');
    final count = await showCupertinoDialog<int>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Download Chapters'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Enter the number of upcoming chapters to download:'),
              const SizedBox(height: 12),
              CupertinoTextField(
                controller: controller,
                keyboardType: TextInputType.number,
                autofocus: true,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final parsed = int.tryParse(controller.text.trim());
              Navigator.of(ctx).pop(parsed != null && parsed > 0 ? parsed : null);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );

    if (count == null || count <= 0 || !context.mounted) return 0;
    return downloadNextN(
      context,
      book: book,
      count: count,
      currentReadingIndex: currentReadingIndex,
    );
  }

  /// Prompts and deletes all downloaded chapters for the given book.
  Future<ChapterDeletionResult?> promptDeleteAll(
    BuildContext context, {
    required Book book,
  }) async {
    final db = DatabaseService.instance;
    await db.ensureChaptersLoaded(book.id);
    final toDelete = db
        .getChapters(book.id)
        .where((c) =>
            c.downloadState == ChapterDownloadState.downloaded || c.localFilePath != null)
        .toList();

    if (toDelete.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No downloaded chapters to delete.')),
        );
      }
      return null;
    }

    if (!context.mounted) return null;
    return promptDeleteChapters(
      context,
      book: book,
      chapters: toDelete,
      title: 'Delete All Offline Files?',
      message: 'Delete offline files for all ${toDelete.length} downloaded chapter${toDelete.length == 1 ? '' : 's'}?',
    );
  }
}
