import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/download_job.dart';
import 'package:hon/app/theme/reader_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = DatabaseService.instance;
    await db.init();
  });

  group('Section 5 — Chapter Download and Library Independence Rules', () {
    test('User can download chapters without being forced to add novel to library', () async {
      final novel = Book(
        id: 'novel_solo_leveling',
        title: 'Solo Leveling',
        author: 'Chugong',
        format: BookFormat.webNovel,
        sourceId: 'webnovel_source',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.saveBook(novel);

      // Book is saved, but NOT added to library
      expect(db.isBookInLibrary(novel.id), isFalse);

      // Download a chapter
      final job = DownloadJob(
        id: 'job_sl_1',
        bookId: novel.id,
        chapterId: 'ch_1',
        chapterTitle: 'Chapter 1: The E-Rank Hunter',
        sourceId: 'webnovel_source',
        status: DownloadStatus.completed,
        progress: 1.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.enqueueDownload(job);

      // Verify: Job is stored & completed, but novel is still NOT in library!
      expect(db.isBookInLibrary(novel.id), isFalse);
      final allJobs = db.getAllDownloadJobs();
      expect(allJobs.any((j) => j.id == 'job_sl_1' && j.status == DownloadStatus.completed), isTrue);

      // Downloaded novel is accessible outside library
      expect(db.getBookById(novel.id), isNotNull);
    });

    test('Following Not Now, suppress repeat prompts for that novel during current app session', () async {
      const novelId = 'novel_lord_of_mysteries';

      expect(db.isPromptSuppressedForSession(novelId), isFalse);

      // User chose "Not Now"
      db.suppressPromptForSession(novelId);

      // Prompt is now suppressed for this session
      expect(db.isPromptSuppressedForSession(novelId), isTrue);
    });

    test('Removing novel from library does NOT automatically delete its downloads', () async {
      const bookId = 'book_good_material';
      expect(db.isBookInLibrary(bookId), isTrue);

      // Add a download for Good Material
      final job = DownloadJob(
        id: 'job_gm_1',
        bookId: bookId,
        chapterId: 'ch_1',
        chapterTitle: 'Chapter 1',
        sourceId: 'local',
        status: DownloadStatus.completed,
        progress: 1.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.enqueueDownload(job);

      // Remove from library
      await db.setLibraryMembership(bookId, false);
      expect(db.isBookInLibrary(bookId), isFalse);

      // Verify downloads remain intact
      final jobs = db.getAllDownloadJobs();
      expect(jobs.any((j) => j.bookId == bookId), isTrue);
    });

    test('Deleting downloads does NOT automatically remove library membership', () async {
      const bookId = 'book_pride_and_prejudice';
      expect(db.isBookInLibrary(bookId), isTrue);

      // Add a download job
      final job = DownloadJob(
        id: 'job_pandp_1',
        bookId: bookId,
        chapterId: 'ch_33',
        chapterTitle: 'Chapter 33',
        sourceId: 'local',
        status: DownloadStatus.completed,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.enqueueDownload(job);

      // Delete the download job
      await db.removeDownloadJob('job_pandp_1');

      // Verify library membership is STILL true
      expect(db.isBookInLibrary(bookId), isTrue);
    });
  });

  group('Section 6 — Reader Themes & Typography Presets', () {
    test('All 6 themes from Apple Books iOS 18 reference exist with distinct palettes', () {
      expect(ReaderThemeConfig.all.length, equals(6));

      final original = ReaderThemeConfig.fromPreset(ReaderThemePreset.original);
      final quiet = ReaderThemeConfig.fromPreset(ReaderThemePreset.quiet);
      final paper = ReaderThemeConfig.fromPreset(ReaderThemePreset.paper);
      final bold = ReaderThemeConfig.fromPreset(ReaderThemePreset.bold);
      final calm = ReaderThemeConfig.fromPreset(ReaderThemePreset.calm);
      final focus = ReaderThemeConfig.fromPreset(ReaderThemePreset.focus);

      expect(original.name, equals('Original'));
      expect(quiet.name, equals('Quiet'));
      expect(paper.name, equals('Paper'));
      expect(bold.name, equals('Bold'));
      expect(calm.name, equals('Calm'));
      expect(focus.name, equals('Focus'));

      // Original is white background
      expect(original.backgroundColor.value, equals(0xFFFFFFFF));
      // Bold is pure pitch black OLED
      expect(bold.backgroundColor.value, equals(0xFF000000));
      // Quiet is slate dark
      expect(quiet.backgroundColor.value, equals(0xFF2C2C2E));
    });

    test('ReaderPreferencesState correctly adjusts font size, line height, and layout mode', () {
      var state = const ReaderPreferencesState();
      expect(state.fontSize, equals(18.0));
      expect(state.lineHeight, equals(1.65));
      expect(state.themePreset, equals(ReaderThemePreset.calm));

      state = state.copyWith(
        fontSize: 22.0,
        lineHeight: 1.8,
        themePreset: ReaderThemePreset.quiet,
        layoutMode: ReaderLayoutMode.verticalScroll,
      );

      expect(state.fontSize, equals(22.0));
      expect(state.lineHeight, equals(1.8));
      expect(state.themePreset, equals(ReaderThemePreset.quiet));
      expect(state.layoutMode, equals(ReaderLayoutMode.verticalScroll));
    });
  });
}
