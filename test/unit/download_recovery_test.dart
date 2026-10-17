import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/downloads/hon_download_manager.dart';
import 'package:hon/core/models/download_job.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase inMemoryDb;
  late DatabaseService dbService;

  setUp(() async {
    inMemoryDb = AppDatabase.inMemory();
    SharedPreferences.setMockInitialValues({'hon_drift_migrated_v1': true});
    dbService = DatabaseService.instance;
    await dbService.init(inMemoryDb);
  });

  tearDown(() async {
    await inMemoryDb.close();
  });

  group('Phase 0E — WorkManager Background Download Recovery', () {
    test('Recovers interrupted "running" downloads after process restart', () async {
      final now = DateTime.now();

      // Seed 3 jobs: one was running when app crashed/killed, one queued, one completed
      final runningJob = DownloadJob(
        id: 'job_interrupted_1',
        bookId: 'book_gutenberg_1342',
        chapterId: 'ch_1',
        chapterTitle: 'Chapter 1',
        sourceId: 'gutenberg',
        status: DownloadStatus.running,
        progress: 0.45,
        createdAt: now.subtract(const Duration(minutes: 5)),
        updatedAt: now.subtract(const Duration(minutes: 5)),
      );

      final queuedJob = DownloadJob(
        id: 'job_queued_2',
        bookId: 'book_gutenberg_1342',
        chapterId: 'ch_2',
        chapterTitle: 'Chapter 2',
        sourceId: 'gutenberg',
        status: DownloadStatus.queued,
        progress: 0.0,
        createdAt: now.subtract(const Duration(minutes: 4)),
        updatedAt: now.subtract(const Duration(minutes: 4)),
      );

      final completedJob = DownloadJob(
        id: 'job_completed_3',
        bookId: 'book_gutenberg_1342',
        chapterId: 'ch_3',
        chapterTitle: 'Chapter 3',
        sourceId: 'gutenberg',
        status: DownloadStatus.completed,
        progress: 1.0,
        createdAt: now.subtract(const Duration(minutes: 10)),
        updatedAt: now.subtract(const Duration(minutes: 8)),
      );

      await dbService.enqueueDownload(runningJob);
      await dbService.enqueueDownload(queuedJob);
      await dbService.enqueueDownload(completedJob);

      // Verify initial states in database
      expect(dbService.getAllDownloadJobs().length, 3);
      expect(
        dbService.getAllDownloadJobs().firstWhere((j) => j.id == 'job_interrupted_1').status,
        DownloadStatus.running,
      );

      // Run recovery
      final recoveredCount = await HonDownloadManager.instance.recoverInterruptedDownloads();

      // Both the running job and queued job should be processed/queued for recovery
      expect(recoveredCount, 2);

      // Verify interrupted job was transitioned from 'running' to 'queued' with an explanation
      final recoveredJob = dbService.getAllDownloadJobs().firstWhere((j) => j.id == 'job_interrupted_1');
      expect(recoveredJob.status, DownloadStatus.queued);
      expect(recoveredJob.progress, 0.0);
      expect(recoveredJob.errorMessage, contains('Interrupted by process termination'));

      // Verify completed job was left completed
      final untouchedCompleted = dbService.getAllDownloadJobs().firstWhere((j) => j.id == 'job_completed_3');
      expect(untouchedCompleted.status, DownloadStatus.completed);
      expect(untouchedCompleted.progress, 1.0);
    });
  });
}
