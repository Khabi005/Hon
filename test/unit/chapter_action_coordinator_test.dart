import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/downloads/hon_download_manager.dart';
import 'package:hon/core/files/storage_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/models/download_job.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late DatabaseService db;
  final now = DateTime(2026, 10, 21);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    tempDir = await Directory.systemTemp.createTemp('hon_actions_test_');
    StorageService.instance.setBaseDirForTesting(tempDir);
    for (final child in ['publications', 'covers', 'chapters', 'staging']) {
      Directory('${tempDir.path}/$child').createSync(recursive: true);
    }
    db = DatabaseService.instance;
    await db.init();
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('deleteDownloadedChapters rejects paths outside managed storage', () async {
    final book = Book(
      id: 'source:novel_safe',
      title: 'Safe Novel',
      format: BookFormat.webNovel,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveBook(book);

    final outsideFile = File('${tempDir.parent.path}/evil_target.txt');
    outsideFile.writeAsStringSync('critical system data');
    expect(outsideFile.existsSync(), isTrue);

    final chapter = Chapter(
      id: 'source:novel_safe:ch_evil',
      bookId: book.id,
      sourceChapterId: 'ch_evil',
      title: 'Evil Chapter',
      chapterIndex: 0.0,
      downloadState: ChapterDownloadState.downloaded,
      localFilePath: outsideFile.path,
      updatedAt: now,
    );
    await db.saveChapters(book.id, [chapter]);

    final result = await db.deleteDownloadedChapters(book.id, [chapter]);
    expect(result.failedCount, 1);
    expect(result.deletedCount, 0);
    expect(outsideFile.existsSync(), isTrue); // Must not be deleted!
    outsideFile.deleteSync();

    // The chapter record must remain intact with its download state and path
    final reloaded = db.getChapters(book.id).first;
    expect(reloaded.downloadState, ChapterDownloadState.downloaded);
    expect(reloaded.localFilePath, isNotNull);
  });

  test('deleteDownloadedChapters deletes managed files and cancels active jobs', () async {
    final book = Book(
      id: 'source:novel_cancel',
      title: 'Cancel Novel',
      format: BookFormat.webNovel,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveBook(book);

    final managedFile = File('${tempDir.path}/chapters/ch1.html');
    managedFile.writeAsStringSync('<p>Chapter 1 text</p>');
    expect(managedFile.existsSync(), isTrue);

    final chapter = Chapter(
      id: 'source:novel_cancel:ch1',
      bookId: book.id,
      sourceChapterId: 'ch1',
      title: 'Chapter 1',
      chapterIndex: 0.0,
      downloadState: ChapterDownloadState.downloaded,
      localFilePath: managedFile.path,
      updatedAt: now,
    );
    await db.saveChapters(book.id, [chapter]);

    String? cancelledJobId;
    DatabaseService.onCancelJobForDeletion = (jobId) async {
      cancelledJobId = jobId;
    };

    final activeJob = DownloadJob(
      id: 'job_active_1',
      bookId: book.id,
      chapterId: chapter.id,
      chapterTitle: chapter.title,
      sourceId: 'source',
      status: DownloadStatus.running,
      createdAt: now,
      updatedAt: now,
    );
    await db.updateDownloadJob(activeJob);

    final result = await db.deleteDownloadedChapters(book.id, [chapter]);
    expect(result.deletedCount, 1);
    expect(result.failedCount, 0);
    expect(managedFile.existsSync(), isFalse);
    expect(cancelledJobId, 'job_active_1');

    final updated = db.getChapters(book.id).first;
    expect(updated.downloadState, ChapterDownloadState.notDownloaded);
    expect(updated.localFilePath, isNull);
  });

  test('resumeDownloadForChapter handles chapter ID and job ID lookups', () async {
    final book = Book(
      id: 'source:novel_resume',
      title: 'Resume Novel',
      format: BookFormat.webNovel,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveBook(book);

    final ch = Chapter(
      id: 'source:novel_resume:ch1',
      bookId: book.id,
      sourceChapterId: 'ch1',
      title: 'Chapter 1',
      chapterIndex: 0.0,
      downloadState: ChapterDownloadState.paused,
      updatedAt: now,
    );
    await db.saveChapters(book.id, [ch]);

    final pausedJob = DownloadJob(
      id: 'job_paused_1',
      bookId: book.id,
      chapterId: ch.id,
      chapterTitle: ch.title,
      sourceId: 'source',
      status: DownloadStatus.paused,
      createdAt: now,
      updatedAt: now,
    );
    await db.updateDownloadJob(pausedJob);

    // Call resume using the chapterId directly (Finding B fix verification)
    await HonDownloadManager.instance.resumeDownloadForChapter(book.id, ch.id);

    final updatedJob = db.getDownloadJob(pausedJob.id);
    expect(updatedJob, isNotNull);
    expect(updatedJob!.status, DownloadStatus.queued);
  });
}
