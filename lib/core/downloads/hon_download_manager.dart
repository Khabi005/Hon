import 'dart:io';
import 'dart:async';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../files/storage_service.dart';
import '../models/book.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../database/database_service.dart';
import '../models/chapter.dart';
import '../models/download_job.dart';
import '../sources/source_registry.dart';

class HonDownloadManager {
  static HonDownloadManager? _instance;
  static HonDownloadManager get instance =>
      _instance ??= HonDownloadManager._();
  HonDownloadManager._();

  static const MethodChannel _channel = MethodChannel(
    'com.hon.reader/download_worker',
  );

  bool _initialized = false;
  final Map<String, int> _localTokens = {};
  final Set<String> _queuingChapters = {};
  final Set<String> _scheduling = {};
  Future<bool> get wifiOnly async =>
      (await SharedPreferences.getInstance()).getBool(
        'hon_download_wifi_only',
      ) ??
      false;

  Future<void> setWifiOnly(bool value) async {
    await (await SharedPreferences.getInstance()).setBool(
      'hon_download_wifi_only',
      value,
    );
    final active = DatabaseService.instance
        .getAllDownloadJobs()
        .where((job) => job.isActive)
        .toList();
    for (final job in active) {
      await pauseDownload(job.id);
    }
    for (final job in active) {
      await resumeDownload(job.id);
    }
  }

  Future<int> queueChapters(Book book, Iterable<Chapter> chapters) async {
    final db = DatabaseService.instance;
    final knownJobs = {
      for (final job in db.getAllDownloadJobs()) job.chapterId: job,
    };
    final updates = <Chapter>[];
    final jobs = <DownloadJob>[];
    final held = <String>{};
    String hash(String value) => sha256.convert(utf8.encode(value)).toString();
    try {
      for (final chapter in chapters) {
        if (chapter.url == null ||
            book.sourceId == null ||
            !_queuingChapters.add(chapter.id)) {
          continue;
        }
        held.add(chapter.id);
        final old = knownJobs[chapter.id];
        if (old?.isActive == true || old?.status == DownloadStatus.paused) {
          continue;
        }
        if (chapter.downloadState == ChapterDownloadState.downloaded &&
            chapter.localFilePath != null &&
            await File(chapter.localFilePath!).exists()) {
          continue;
        }
        final destination =
            chapter.localFilePath ??
            '${StorageService.instance.chaptersDir.path}/${hash(book.id)}_${hash(chapter.sourceChapterId)}.html';
        updates.add(
          chapter.copyWith(
            localFilePath: destination,
            downloadState: ChapterDownloadState.queued,
            updatedAt: DateTime.now(),
          ),
        );
        jobs.add(
          DownloadJob(
            id:
                old?.id ??
                'dl_${hash('${book.id}:${chapter.sourceChapterId}')}',
            bookId: book.id,
            chapterId: chapter.id,
            chapterTitle: chapter.title,
            sourceId: book.sourceId!,
            createdAt: old?.createdAt ?? DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }
      if (jobs.isEmpty) return 0;
      await db.enqueueChapterBatch(book.id, updates, jobs);
      unawaited(
        _scheduleJobs(jobs).catchError(
          (Object error) =>
              debugPrint('Could not schedule queued downloads: $error'),
        ),
      );
      return jobs.length;
    } finally {
      _queuingChapters.removeAll(held);
    }
  }

  Future<void> _scheduleJobs(List<DownloadJob> jobs) async {
    final db = DatabaseService.instance;
    for (final job in jobs) {
      if (!_scheduling.add(job.id)) continue;
      try {
        final latest = db.getDownloadJob(job.id);
        if (latest == null || !latest.isActive) continue;
        await enqueueDownload(latest, persist: false);
      } catch (error) {
        final latest = db.getDownloadJob(job.id);
        if (latest?.isActive == true) {
          await db.updateDownloadJob(
            latest!.copyWith(
              status: DownloadStatus.failed,
              errorMessage: 'Could not schedule: $error',
              updatedAt: DateTime.now(),
            ),
          );
        }
      } finally {
        _scheduling.remove(job.id);
      }
    }
  }

  Future<void> pauseDownload(String jobId) async {
    final db = DatabaseService.instance;
    final job = db.getDownloadJob(jobId);
    if (job == null || !job.isActive) return;
    _localTokens[jobId] = (_localTokens[jobId] ?? 0) + 1;
    if (Platform.isAndroid && !kIsWeb) {
      await _channel.invokeMethod('cancelDownload', {
        'jobId': jobId,
        'status': 'paused',
      });
      await db.refreshDownloadsAndChapters(job.bookId);
      return;
    }
    final latest = db.getDownloadJob(jobId);
    if (latest == null || latest.status == DownloadStatus.completed) return;
    await db.updateDownloadJob(
      latest.copyWith(status: DownloadStatus.paused, updatedAt: DateTime.now()),
    );
    await db.ensureChaptersLoaded(job.bookId);
    final chapters = db.getChapters(job.bookId);
    final ch = chapters.where((c) => c.id == job.chapterId).firstOrNull;
    if (ch != null && ch.downloadState != ChapterDownloadState.downloaded) {
      await db.saveChapters(job.bookId, [
        ch.copyWith(downloadState: ChapterDownloadState.paused, updatedAt: DateTime.now()),
      ]);
    }
  }

  Future<void> resumeDownload(String jobId) async {
    final db = DatabaseService.instance;
    final job = db.getDownloadJob(jobId);
    if (job == null || job.status == DownloadStatus.completed || job.isActive) {
      return;
    }
    final next = job.copyWith(
      status: DownloadStatus.queued,
      progress: 0,
      errorMessage: null,
      updatedAt: DateTime.now(),
    );
    await db.ensureChaptersLoaded(job.bookId);
    final chapters = db.getChapters(job.bookId);
    final ch = chapters.where((c) => c.id == job.chapterId).firstOrNull;
    if (ch != null && ch.downloadState != ChapterDownloadState.downloaded) {
      await db.saveChapters(job.bookId, [
        ch.copyWith(downloadState: ChapterDownloadState.queued, updatedAt: DateTime.now()),
      ]);
    }
    try {
      await enqueueDownload(next, replace: true);
    } catch (error) {
      await db.updateDownloadJob(
        next.copyWith(
          status: DownloadStatus.failed,
          errorMessage: 'Could not resume: $error',
          updatedAt: DateTime.now(),
        ),
      );
      rethrow;
    }
  }

  Future<void> pauseAll() async {
    for (final job
        in DatabaseService.instance
            .getAllDownloadJobs()
            .where((job) => job.isActive)
            .toList()) {
      await pauseDownload(job.id);
    }
  }

  Future<void> resumeAll() async {
    for (final job
        in DatabaseService.instance
            .getAllDownloadJobs()
            .where((job) => job.status == DownloadStatus.paused || job.status == DownloadStatus.failed)
            .toList()) {
      await resumeDownload(job.id);
    }
  }

  Future<void> cancelAll() async {
    for (final job
        in DatabaseService.instance
            .getAllDownloadJobs()
            .where((job) => job.isActive || job.status == DownloadStatus.paused)
            .toList()) {
      await cancelDownload(job.id);
    }
  }

  Future<void> pauseSelected(Iterable<String> jobIds) async {
    for (final id in jobIds) {
      await pauseDownload(id);
    }
  }

  Future<void> resumeSelected(Iterable<String> jobIds) async {
    for (final id in jobIds) {
      await resumeDownload(id);
    }
  }

  Future<void> cancelSelected(Iterable<String> jobIds) async {
    for (final id in jobIds) {
      await cancelDownload(id);
    }
  }

  void init() {
    if (_initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onDownloadStateChanged') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final jobId = args?['jobId'] as String?;
      final bookId = args?['bookId'] as String?;
      if (jobId != null && jobId.isNotEmpty) {
        await DatabaseService.instance.refreshDownloadJob(jobId);
      } else if (bookId != null && bookId.isNotEmpty) {
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
    int recoveredCount = 0;

    if (Platform.isAndroid && !kIsWeb) {
      // Older versions also scheduled a RECOVER_ALL worker which could race with
      // these per-job WorkManager requests. Retire that legacy work first.
      await _channel.invokeMethod('cancelLegacyRecovery');
      await db.refreshAllDownloads();
    }

    final allJobs = db.getAllDownloadJobs();
    for (final job in allJobs) {
      if (job.status == DownloadStatus.running ||
          job.status == DownloadStatus.queued ||
          job.status == DownloadStatus.retryWaiting) {
        try {
          await enqueueDownload(job, persist: false);
          recoveredCount++;
        } catch (error) {
          debugPrint('Could not recover download ${job.id}: $error');
        }
      }
    }

    return recoveredCount;
  }

  /// Enqueues a download job to Android WorkManager (or local fallback executor)
  Future<void> enqueueDownload(
    DownloadJob job, {
    bool? wifiOnly,
    bool persist = true,
    bool replace = false,
  }) async {
    init();

    // 1. Ensure persisted in database
    if (persist) await DatabaseService.instance.updateDownloadJob(job);

    await DatabaseService.instance.ensureChaptersLoaded(job.bookId);
    final chapters = DatabaseService.instance.getChapters(job.bookId);
    var ch = chapters.where((c) => c.id == job.chapterId).firstOrNull;
    final url = ch?.url ?? '';
    var targetPath = ch?.localFilePath ?? '';
    // A metadata-only restore deliberately drops paths from the old device.
    // Recreate and persist a managed destination before resuming its job.
    if (ch != null && url.isNotEmpty && targetPath.isEmpty) {
      String hash(String value) =>
          sha256.convert(utf8.encode(value)).toString();
      targetPath =
          '${StorageService.instance.chaptersDir.path}/${hash(job.bookId)}_${hash(ch.sourceChapterId)}.html';
      ch = ch.copyWith(
        localFilePath: targetPath,
        downloadState: ChapterDownloadState.queued,
        updatedAt: DateTime.now(),
      );
      await DatabaseService.instance.saveChapters(job.bookId, [ch]);
    }

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
            'chapterTitle': ch?.title ?? job.chapterTitle,
            'sourceId': job.sourceId,
            'wifiOnly': wifiOnly ?? await this.wifiOnly,
            'replace': replace,
          });
          return;
        } catch (e) {
          throw StateError('Could not schedule Android download ${job.id}: $e');
        }
      }
      throw StateError('Download ${job.id} has no saved URL or destination');
    }

    // 3. Fallback executor for non-Android platforms or tests where WorkManager is unavailable
    if (url.isNotEmpty && targetPath.isNotEmpty) {
      final token = (_localTokens[job.id] ?? 0) + 1;
      _localTokens[job.id] = token;
      unawaited(
        _executeLocalFallbackDownload(
          job,
          token: token,
          ch: ch,
          url: url,
          targetPath: targetPath,
        ),
      );
    }
  }

  /// Local fallback execution for desktop or test environments
  Future<void> _executeLocalFallbackDownload(
    DownloadJob job, {
    required int token,
    required Chapter? ch,
    required String url,
    required String targetPath,
  }) async {
    try {
      await DatabaseService.instance.updateDownloadJob(
        job.copyWith(
          status: DownloadStatus.running,
          progress: 0.2,
          updatedAt: DateTime.now(),
        ),
      );

      final passage = await SourceRegistry.instance.getChapterPassage(
        job.sourceId,
        url,
      );
      if (_localTokens[job.id] != token) return;
      final file = File(targetPath);
      final parent = file.parent;
      if (!parent.existsSync()) {
        parent.createSync(recursive: true);
      }
      final tempFile = File(
        '$targetPath.tmp_${DateTime.now().millisecondsSinceEpoch}',
      );
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
        await DatabaseService.instance.saveChapters(job.bookId, [
          completedChapter,
        ]);
      }

      await DatabaseService.instance.updateDownloadJob(
        job.copyWith(
          status: DownloadStatus.completed,
          progress: 1.0,
          updatedAt: DateTime.now(),
        ),
      );
    } catch (e) {
      if (_localTokens[job.id] != token) return;
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
    _localTokens[jobId] = (_localTokens[jobId] ?? 0) + 1;
    final db = DatabaseService.instance;
    final job = db.getDownloadJob(jobId);
    if (job == null) return;
    if (Platform.isAndroid && !kIsWeb) {
      await _channel.invokeMethod('cancelDownload', {
        'jobId': jobId,
        'status': 'cancelled',
      });
      await db.refreshDownloadsAndChapters(job.bookId);
      return;
    }
    final latest = db.getDownloadJob(jobId);
    if (latest == null || latest.status == DownloadStatus.completed) return;
    await db.updateDownloadJob(
      latest.copyWith(
        status: DownloadStatus.cancelled,
        updatedAt: DateTime.now(),
      ),
    );
    await db.ensureChaptersLoaded(job.bookId);
    final chapters = db.getChapters(job.bookId);
    final ch = chapters.where((c) => c.id == job.chapterId).firstOrNull;
    if (ch != null && ch.downloadState != ChapterDownloadState.downloaded) {
      await db.saveChapters(job.bookId, [
        ch.copyWith(downloadState: ChapterDownloadState.notDownloaded, updatedAt: DateTime.now()),
      ]);
    }
  }
}
