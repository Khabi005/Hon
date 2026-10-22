import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as drift;
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/models/novel_source.dart';
import 'package:hon/core/updates/chapter_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late DatabaseService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    AppDatabase.allowMemoryFallbackForTesting = true;
    db = AppDatabase();
    service = DatabaseService.instance;
    await service.init(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('Worker & Dart Chapter Reconciliation Interop', () {
    test('Worker-created chapter rows seamlessly interoperate with Dart without duplicates', () async {
      const bookId = 'book_interop_1';
      final now = DateTime.now();

      // 1. Create book in Drift
      await service.saveBook(Book(
        id: bookId,
        title: 'Interop Novel',
        author: 'Author',
        description: 'Description',
        format: BookFormat.webNovel,
        sourceId: 'src_test',
        sourceNovelId: 'https://example.com/novel/1',
        createdAt: now,
        updatedAt: now,
      ));

      // 2. Simulate worker writing 2 chapters directly into Drift chapters_table
      // using the worker format: id = '$bookId:$sourceChapterId', chapterIndex = i.toDouble()
      await db.into(db.chaptersTable).insert(
        ChaptersTableCompanion.insert(
          id: '$bookId:ch_1',
          bookId: bookId,
          sourceChapterId: 'ch_1',
          title: 'Chapter 1: The Prologue',
          chapterIndex: const drift.Value(0.0),
          url: const drift.Value('https://example.com/novel/ch1'),
          downloadState: const drift.Value('notDownloaded'),
          updatedAt: now,
        ),
      );
      await db.into(db.chaptersTable).insert(
        ChaptersTableCompanion.insert(
          id: '$bookId:ch_2',
          bookId: bookId,
          sourceChapterId: 'ch_2',
          title: 'Chapter 2: The Departure',
          chapterIndex: const drift.Value(1.0),
          url: const drift.Value('https://example.com/novel/ch2'),
          downloadState: const drift.Value('downloaded'),
          localFilePath: const drift.Value('/data/ch2.html'),
          updatedAt: now,
        ),
      );

      // 3. Reload from database in Dart
      await service.reloadFromDatabase();
      await service.ensureChaptersLoaded(bookId);

      final loaded = service.getChapters(bookId);
      expect(loaded.length, 2);
      expect(loaded[0].id, '$bookId:ch_1');
      expect(loaded[0].sourceChapterId, 'ch_1');
      expect(loaded[0].chapterIndex, 0.0);
      expect(loaded[1].id, '$bookId:ch_2');
      expect(loaded[1].sourceChapterId, 'ch_2');
      expect(loaded[1].chapterIndex, 1.0);
      expect(loaded[1].downloadState, ChapterDownloadState.downloaded);
      expect(loaded[1].localFilePath, '/data/ch2.html');

      // 4. Now simulate Dart's source_catalog_screen or ChapterUpdateService saving chapters
      // with chapter 1, 2, and a new chapter 3
      final dartChapters = [
        Chapter(
          id: '$bookId:ch_1',
          bookId: bookId,
          sourceChapterId: 'ch_1',
          title: 'Chapter 1: The Prologue (Clean)',
          chapterIndex: 0.0,
          url: 'https://cdn.example.com/novel/ch1',
          updatedAt: now,
        ),
        Chapter(
          id: '$bookId:ch_2',
          bookId: bookId,
          sourceChapterId: 'ch_2',
          title: 'Chapter 2: The Departure',
          chapterIndex: 1.0,
          url: 'https://cdn.example.com/novel/ch2',
          updatedAt: now,
        ),
        Chapter(
          id: '$bookId:ch_3',
          bookId: bookId,
          sourceChapterId: 'ch_3',
          title: 'Chapter 3: The Arrival',
          chapterIndex: 2.0,
          url: 'https://cdn.example.com/novel/ch3',
          updatedAt: now,
        ),
      ];

      await service.saveChapters(bookId, dartChapters);

      final finalChapters = service.getChapters(bookId);
      // There must be EXACTLY 3 chapters - ZERO duplicate entries!
      expect(finalChapters.length, 3);
      expect(finalChapters[0].id, '$bookId:ch_1');
      expect(finalChapters[0].title, 'Chapter 1: The Prologue (Clean)');
      expect(finalChapters[1].id, '$bookId:ch_2');
      // Preserves existing downloadState and localFilePath!
      expect(finalChapters[1].downloadState, ChapterDownloadState.downloaded);
      expect(finalChapters[1].localFilePath, '/data/ch2.html');
      expect(finalChapters[2].id, '$bookId:ch_3');
      expect(finalChapters[2].chapterIndex, 2.0);

      // Total count aggregate in service must be 3
      expect(service.getTotalChapterCount(bookId), 3);
      expect(service.getDownloadedChapterCount(bookId), 1);
    });

    test('reloadFromDatabase updates total counts, downloaded counts, and notifies listeners', () async {
      const bookId = 'book_resume_test';
      final now = DateTime.now();

      await service.saveBook(Book(
        id: bookId,
        title: 'Background Updated Book',
        author: 'Author',
        description: 'Description',
        format: BookFormat.webNovel,
        sourceId: 'src_test',
        sourceNovelId: 'https://example.com/novel/2',
        totalChapters: 1,
        createdAt: now,
        updatedAt: now,
      ));

      expect(service.getTotalChapterCount(bookId), 0);

      // Simulate background worker updating chapters in SQLite while app was in background
      await db.into(db.chaptersTable).insert(
        ChaptersTableCompanion.insert(
          id: '$bookId:c1',
          bookId: bookId,
          sourceChapterId: 'c1',
          title: 'Chapter 1',
          chapterIndex: const drift.Value(0.0),
          downloadState: const drift.Value('downloaded'),
          localFilePath: const drift.Value('/file/1'),
          updatedAt: now,
        ),
      );
      await db.into(db.chaptersTable).insert(
        ChaptersTableCompanion.insert(
          id: '$bookId:c2',
          bookId: bookId,
          sourceChapterId: 'c2',
          title: 'Chapter 2',
          chapterIndex: const drift.Value(1.0),
          downloadState: const drift.Value('notDownloaded'),
          updatedAt: now,
        ),
      );
      await (db.update(db.booksTable)..where((b) => b.id.equals(bookId))).write(
        const BooksTableCompanion(totalChapters: drift.Value(2)),
      );

      var notificationReceived = false;
      service.changeNotifier.addListener(() {
        notificationReceived = true;
      });

      // App resumes -> calls reloadFromDatabase
      await service.reloadFromDatabase();

      expect(notificationReceived, isTrue);
      expect(service.getTotalChapterCount(bookId), 2);
      expect(service.getDownloadedChapterCount(bookId), 1);
      expect(service.getBookById(bookId)?.totalChapters, 2);
    });

    test('Initial check in ChapterUpdateService does not flag new chapters', () async {
      const bookId = 'book_initial_dart';
      final now = DateTime.now();

      await service.saveBook(Book(
        id: bookId,
        title: 'Initial Novel',
        author: 'Author',
        description: 'Description',
        format: BookFormat.webNovel,
        sourceId: 'src_test',
        sourceNovelId: 'https://example.com/novel/initial',
        createdAt: now,
        updatedAt: now,
      ));
      await service.setLibraryMembership(bookId, true);

      final updateService = ChapterUpdateService(
        fetch: (source, novel) async {
          return const NovelDetails(
            id: 'https://example.com/novel/initial',
            title: 'Initial Novel',
            author: 'Author',
            description: 'Desc',
            coverUrl: null,
            chapters: [
              SourceChapter(id: 'c1', title: 'Chapter 1', index: 0.0, url: 'https://example.com/c1'),
              SourceChapter(id: 'c2', title: 'Chapter 2', index: 1.0, url: 'https://example.com/c2'),
            ],
          );
        },
      );

      final added = await updateService.check(only: service.getBookById(bookId));
      // Mirroring worker: on initial check with 0 existing chapters, added is 0!
      expect(added, 0);

      final saved = service.getChapters(bookId);
      expect(saved.length, 2);
      expect(saved[0].id, '$bookId:c1');
      expect(saved[1].id, '$bookId:c2');
    });

    test('Dart normalizeTitle preserves chapter numbers and differentiates distinct chapters', () {
      expect(ChapterUpdateService.normalizeTitle('Chapter 1: The Beginning!'), 'c1thebeginning');
      expect(ChapterUpdateService.normalizeTitle('Chap. 1 - The Beginning'), 'c1thebeginning');
      expect(ChapterUpdateService.normalizeTitle('Ch 1 The Beginning'), 'c1thebeginning');
      expect(ChapterUpdateService.normalizeTitle('Chapter 2: The Beginning'), 'c2thebeginning');
      expect(ChapterUpdateService.normalizeTitle('Chapter 10: The Big Climax'), 'c10thebigclimax');
      expect(ChapterUpdateService.normalizeTitle('Epilogue - Aftermath'), 'epilogueaftermath');

      // Crucial: Chapter 1 and Chapter 2 must NOT normalize to the same string!
      expect(
        ChapterUpdateService.normalizeTitle('Chapter 1'),
        isNot(equals(ChapterUpdateService.normalizeTitle('Chapter 2'))),
      );
      expect(
        ChapterUpdateService.normalizeTitle('Chapter 1: Part A'),
        isNot(equals(ChapterUpdateService.normalizeTitle('Chapter 2: Part A'))),
      );
    });
  });
}

