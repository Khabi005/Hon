import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../database/database_service.dart';
import '../models/chapter.dart';
import '../models/download_job.dart';
import '../sources/source_registry.dart';

class HonDownloadManager {
  static HonDownloadManager? _instance;
  static HonDownloadManager get instance => _instance ??= HonDownloadManager._();
  HonDownloadManager._();

  static const MethodChannel _channel = MethodChannel('com.hon.reader/download_worker');

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onDownloadStateChanged') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final bookId = args?['bookId'] as String?;
      if (bookId != null && bookId.isNotEmpty) {
        await DatabaseService.instance.refreshDownloadsAndChapters(bookId);
      } else {
        await DatabaseService.instance.refreshAllDownloads();
      }
    }
    return null;
  }

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
        // Handled in mock test environment
      }
    }

    return recoveredCount;
  }

  /// Enqueues a download job to Android WorkManager (or local fallback executor)
  Future<void> enqueueDownload(DownloadJob job, {bool wifiOnly = false}) async {
    init();

    // 1. Ensure persisted in database
    await DatabaseService.instance.updateDownloadJob(job);

    final chapters = DatabaseService.instance.getChapters(job.bookId);
    final ch = chapters.where((c) => c.id == job.chapterId).firstOrNull;
    final url = ch?.url ?? '';
    final targetPath = ch?.localFilePath ?? '';

    // 2. Delegate to Android WorkManager as the sole executor if running on Android
    if (Platform.isAndroid && !kIsWeb) {
      if (url.isNotEmpty && targetPath.isNotEmpty) {
        try {
          await _channel.invokeMethod('enqueueDownload', {
            'jobId': job.id,
            'url': url,
            'targetPath': targetPath,
            'bookId': job.bookId,
            'chapterId': job.chapterId,
            'sourceId': job.sourceId,
            'wifiOnly': wifiOnly,
          });
          return;
        } catch (_) {
          // Handled gracefully in mock / test environment
        }
      }
    }

    // 3. Fallback executor for non-Android platforms or tests where WorkManager is unavailable
    if (url.isNotEmpty && targetPath.isNotEmpty) {
      _executeLocalFallbackDownload(job, ch: ch, url: url, targetPath: targetPath);
    }
  }

  /// Local fallback execution for desktop or test environments
  Future<void> _executeLocalFallbackDownload(
    DownloadJob job, {
    required Chapter? ch,
    required String url,
    required String targetPath,
  }) async {
    try {
      await DatabaseService.instance.updateDownloadJob(
        job.copyWith(status: DownloadStatus.running, progress: 0.2, updatedAt: DateTime.now()),
      );

      final passage = await SourceRegistry.instance.getChapterPassage(job.sourceId, url);
      final file = File(targetPath);
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      final tempFile = File('$targetPath.tmp_${DateTime.now().millisecondsSinceEpoch}');
      await tempFile.writeAsString(passage);
      if (file.existsSync()) {
        await file.delete();
      }
      await tempFile.rename(targetPath);

      if (ch != null) {
        final completedChapter = ch.copyWith(
          localFilePath: targetPath,
          downloadState: ChapterDownloadState.downloaded,
          updatedAt: DateTime.now(),
        );
        await DatabaseService.instance.saveChapters(job.bookId, [completedChapter]);
      }

      await DatabaseService.instance.updateDownloadJob(
        job.copyWith(status: DownloadStatus.completed, progress: 1.0, updatedAt: DateTime.now()),
      );
    } catch (e) {
      await DatabaseService.instance.updateDownloadJob(
        job.copyWith(
          status: DownloadStatus.failed,
          errorMessage: e.toString(),
          updatedAt: DateTime.now(),
        ),
      );
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
