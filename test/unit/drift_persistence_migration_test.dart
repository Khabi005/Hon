import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/reading_progress.dart';
import 'package:hon/core/models/bookmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase inMemoryDb;
  late DatabaseService dbService;

  setUp(() async {
    inMemoryDb = AppDatabase.inMemory();
    dbService = DatabaseService.instance;
  });

  tearDown(() async {
    await inMemoryDb.close();
  });

  group('Phase 0D — Drift SQLite Persistence & Seamless Migration', () {
    test('Drift Migration: Seamlessly imports legacy SharedPreferences JSON into Drift tables', () async {
      final now = DateTime.now();

      // 1. Seed legacy SharedPreferences JSON state
      final legacyBookMap = {
        'id': 'legacy_book_1',
        'title': 'Pride and Prejudice',
        'author': 'Jane Austen',
        'description': 'A classic romantic novel',
        'coverPath': '/path/to/cover.jpg',
        'format': 'epub',
        'sourceId': 'gutenberg',
        'sourceNovelId': '/ebooks/1342',
        'filePath': '/managed/storage/books/pride.epub',
        'contentHash': 'hash_1342',
        'totalChapters': 61,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final legacyLibMap = {
        'bookId': 'legacy_book_1',
        'isInLibrary': 1,
        'dateAdded': now.toIso8601String(),
        'lastReadAt': now.toIso8601String(),
        'isFinished': 0,
        'collectionIds': 'classics,favorites',
        'customSortOrder': 1,
      };

      final legacyChapterMap = {
        'id': 'legacy_book_1:ch_1',
        'bookId': 'legacy_book_1',
        'sourceChapterId': 'ch_1',
        'title': 'Chapter 1',
        'chapterIndex': 1.0,
        'url': '/cache/epub/1342/pg1342-images.html',
        'localFilePath': '/managed/storage/chapters/ch_1.html',
        'downloadState': 'downloaded',
        'releaseDate': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final legacyProgMap = {
        'bookId': 'legacy_book_1',
        'lastChapterId': 'legacy_book_1:ch_1',
        'chapterIndex': 1.0,
        'pageIndex': 0,
        'totalPages': 61,
        'scrollOffset': 150.0,
        'locatorString': '{"href":"/ch1.xhtml"}',
        'locatorVersion': 'readium-v1',
        'completionPercentage': 0.25,
        'lastReadAt': now.toIso8601String(),
      };

      final legacyJobMap = {
        'id': 'job_legacy_1',
        'bookId': 'legacy_book_1',
        'chapterId': 'legacy_book_1:ch_1',
        'chapterTitle': 'Chapter 1',
        'sourceId': 'gutenberg',
        'status': 'completed',
        'progress': 1.0,
        'retryCount': 0,
        'errorMessage': null,
        'createdAt': now.toIso8601String(),
        'updatedAt': now.toIso8601String(),
      };

      final legacyBookmarkMap = {
        'id': 'bm_legacy_1',
        'bookId': 'legacy_book_1',
        'pageIndex': 1,
        'chapterIndex': 1,
        'label': 'Opening line',
        'createdAt': now.toIso8601String(),
        'snippet': 'It is a truth universally acknowledged...',
      };

      SharedPreferences.setMockInitialValues({
        'hon_books': jsonEncode([legacyBookMap]),
        'hon_library': jsonEncode([legacyLibMap]),
        'hon_chapters': jsonEncode({
          'legacy_book_1': [legacyChapterMap]
        }),
        'hon_progress': jsonEncode([legacyProgMap]),
        'hon_downloads': jsonEncode([legacyJobMap]),
        'hon_bookmarks': jsonEncode({
          'legacy_book_1': [legacyBookmarkMap]
        }),
      });

      // 2. Initialize DatabaseService with the clean in-memory Drift SQLite instance
      await dbService.init(inMemoryDb);

      // 3. Verify migration flag is marked complete
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('hon_drift_migrated_v1'), isTrue);

      // 4. Verify data directly from Drift SQLite tables
      final driftBooks = await inMemoryDb.select(inMemoryDb.booksTable).get();
      expect(driftBooks.length, 1);
      expect(driftBooks.first.id, 'legacy_book_1');
      expect(driftBooks.first.title, 'Pride and Prejudice');
      expect(driftBooks.first.author, 'Jane Austen');

      final driftEntries = await inMemoryDb.select(inMemoryDb.libraryEntriesTable).get();
      expect(driftEntries.length, 1);
      expect(driftEntries.first.isInLibrary, isTrue);

      final driftChapters = await inMemoryDb.select(inMemoryDb.chaptersTable).get();
      expect(driftChapters.length, 1);
      expect(driftChapters.first.title, 'Chapter 1');
      expect(driftChapters.first.downloadState, 'downloaded');

      final driftProgress = await inMemoryDb.select(inMemoryDb.readingProgressTable).get();
      expect(driftProgress.length, 1);
      expect(driftProgress.first.completionPercentage, 0.25);
      expect(driftProgress.first.locatorVersion, 'readium-v1');

      final driftJobs = await inMemoryDb.select(inMemoryDb.downloadJobsTable).get();
      expect(driftJobs.length, 1);
      expect(driftJobs.first.status, 'completed');

      final driftBookmarks = await inMemoryDb.select(inMemoryDb.bookmarksTable).get();
      expect(driftBookmarks.length, 1);
      expect(driftBookmarks.first.snippet, contains('truth universally acknowledged'));

      // 5. Verify DatabaseService in-memory queries return migrated items
      expect(dbService.getBookById('legacy_book_1'), isNotNull);
      expect(dbService.isBookInLibrary('legacy_book_1'), isTrue);
      expect(dbService.getChapters('legacy_book_1').length, 1);
      expect(dbService.getProgress('legacy_book_1')?.completionPercentage, 0.25);
      expect(dbService.getAllDownloadJobs().length, 1);
      expect(dbService.getBookmarks('legacy_book_1').length, 1);
    });

    test('Drift CRUD Operations: Saves, updates, and deletes persist into SQLite tables', () async {
      SharedPreferences.setMockInitialValues({'hon_drift_migrated_v1': true});
      await dbService.init(inMemoryDb);

      final now = DateTime.now();
      final newBook = Book(
        id: 'drift_book_test',
        title: 'Drift Test Book',
        author: 'Drift Author',
        format: BookFormat.epub,
        createdAt: now,
        updatedAt: now,
      );

      // Save book
      await dbService.saveBook(newBook);
      await dbService.setLibraryMembership('drift_book_test', true);

      // Verify in Drift table
      var dbRows = await inMemoryDb.select(inMemoryDb.booksTable).get();
      expect(dbRows.any((r) => r.id == 'drift_book_test'), isTrue);

      // Save Progress
      final prog = ReadingProgress(
        bookId: 'drift_book_test',
        completionPercentage: 0.65,
        lastReadAt: now,
      );
      await dbService.saveProgress(prog);

      var dbProg = await (inMemoryDb.select(inMemoryDb.readingProgressTable)
            ..where((t) => t.bookId.equals('drift_book_test')))
          .getSingleOrNull();
      expect(dbProg, isNotNull);
      expect(dbProg!.completionPercentage, 0.65);

      // Add Bookmark
      final bm = Bookmark(
        id: 'bm_drift_1',
        bookId: 'drift_book_test',
        pageIndex: 5,
        label: 'Bookmark 5',
        createdAt: now,
      );
      await dbService.addBookmark(bm);

      var dbBm = await (inMemoryDb.select(inMemoryDb.bookmarksTable)
            ..where((t) => t.id.equals('bm_drift_1')))
          .getSingleOrNull();
      expect(dbBm, isNotNull);
      expect(dbBm!.pageIndex, 5);

      // Remove Bookmark
      await dbService.removeBookmark('drift_book_test', 5);
      dbBm = await (inMemoryDb.select(inMemoryDb.bookmarksTable)
            ..where((t) => t.id.equals('bm_drift_1')))
          .getSingleOrNull();
      expect(dbBm, isNull);
    });
  });
}
