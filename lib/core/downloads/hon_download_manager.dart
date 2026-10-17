import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../database/database_service.dart';
import '../models/download_job.dart';

class HonDownloadManager {
  static HonDownloadManager? _instance;
  static HonDownloadManager get instance => _instance ??= HonDownloadManager._();
  HonDownloadManager._();

  static const MethodChannel _channel = MethodChannel('com.hon.reader/download_worker');

  /// Recovers any downloads that were interrupted (e.g. app terminated while running)
  Future<int> recoverInterruptedDownloads() async {
    final db = DatabaseService.instance;
    final allJobs = db.getAllDownloadJobs();
    int recoveredCount = 0;

    for (final job in allJobs) {
      if (job.status == DownloadStatus.running) {
        // App process was killed while this job was active; reset to queued for recovery
        final recoveredJob = job.copyWith(
          status: DownloadStatus.queued,
          progress: 0.0,
          errorMessage: 'Interrupted by process termination; queued for recovery',
          updatedAt: DateTime.now(),
        );
        await db.updateDownloadJob(recoveredJob);
        recoveredCount++;

        // Enqueue with background manager
        await enqueueDownload(recoveredJob);
      } else if (job.status == DownloadStatus.queued || job.status == DownloadStatus.retryWaiting) {
        await enqueueDownload(job);
        recoveredCount++;
      }
    }

    if (Platform.isAndroid && !kIsWeb) {
      try {
        await _channel.invokeMethod('scheduleDownloadRecovery');
      } catch (_) {
        // Ignored if channel is unavailable or in mock test environment
      }
    }

    return recoveredCount;
  }

  /// Enqueues a download job to Android WorkManager or local worker
  Future<void> enqueueDownload(DownloadJob job, {bool wifiOnly = false}) async {
    // 1. Ensure persisted in database
    await DatabaseService.instance.updateDownloadJob(job);

    // 2. Delegate to Android WorkManager if running on Android
    if (Platform.isAndroid && !kIsWeb) {
      final chapters = DatabaseService.instance.getChapters(job.bookId);
      final ch = chapters.where((c) => c.id == job.chapterId).firstOrNull;
      final url = ch?.url ?? '';
      final targetPath = ch?.localFilePath ?? '';

      if (url.isNotEmpty && targetPath.isNotEmpty) {
        try {
          await _channel.invokeMethod('enqueueDownload', {
            'jobId': job.id,
            'url': url,
            'targetPath': targetPath,
            'bookId': job.bookId,
            'chapterId': job.chapterId,
            'wifiOnly': wifiOnly,
          });
        } catch (_) {
          // Handled gracefully in mock / test environment
        }
      }
    }
  }

  /// Cancels an active or queued download job
  Future<void> cancelDownload(String jobId) async {
    final db = DatabaseService.instance;
    final job = db.getAllDownloadJobs().where((j) => j.id == jobId).firstOrNull;
    if (job != null) {
      await db.updateDownloadJob(job.copyWith(
        status: DownloadStatus.cancelled,
        updatedAt: DateTime.now(),
      ));
    }

    if (Platform.isAndroid && !kIsWeb) {
      try {
        await _channel.invokeMethod('cancelDownload', {'jobId': jobId});
      } catch (_) {}
    }
  }
}
