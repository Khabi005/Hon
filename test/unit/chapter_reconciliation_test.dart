import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/models/novel_source.dart';
import 'package:hon/core/updates/chapter_update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chapter Reconciliation', () {
    test('areTitlesSimilar correctly compares chapter titles', () {
      expect(
        ChapterUpdateService.areTitlesSimilar('Chapter 1: The Beginning', 'Ch. 1 - The Beginning'),
        isTrue,
      );
      expect(
        ChapterUpdateService.areTitlesSimilar('Prologue', 'Prologue: Introduction'),
        isTrue,
      );
      // Different chapter numbers must NOT match
      expect(
        ChapterUpdateService.areTitlesSimilar('Chapter 1', 'Chapter 2'),
        isFalse,
      );
      // Completely unrelated title must NOT match
      expect(
        ChapterUpdateService.areTitlesSimilar('Chapter 1: The Beginning', 'Side Story: Afterword'),
        isFalse,
      );
    });

    test('Old chapter removed and new chapter at same index is NOT marked downloaded', () async {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetForTesting();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final db = DatabaseService.instance;
      await db.init(database);

      final now = DateTime.now();
      final book = Book(
        id: 'test_src:novel_1',
        sourceId: 'test_src',
        sourceNovelId: 'novel_1',
        title: 'Reconciliation Test Novel',
        format: BookFormat.webNovel,
        createdAt: now,
        updatedAt: now,
      );
      await db.saveBook(book);

      // Previously saved & downloaded chapter at index 0
      final oldChapter = Chapter(
        id: 'old_ch_1',
        bookId: book.id,
        sourceChapterId: 'src_ch_1',
        title: 'Chapter 1: The First Step',
        chapterIndex: 0.0,
        downloadState: ChapterDownloadState.downloaded,
        localFilePath: '/storage/novels/ch1.html',
        updatedAt: now,
      );
      await db.saveChapters(book.id, [oldChapter]);

      // Mock update service where upstream chapter 0 is a completely different chapter
      final updateService = ChapterUpdateService(
        fetch: (source, novel) async {
          return const NovelDetails(
            id: 'novel_1',
            title: 'Reconciliation Test Novel',
            author: 'Author',
            description: 'Desc',
            coverUrl: null,
            status: 'ongoing',
            chapters: [
              SourceChapter(
                id: 'ss_prologue',
                title: 'Side Story: An Unrelated Legend',
                index: 0.0,
                url: 'https://example.com/ss_prologue',
              ),
            ],
          );
        },
      );

      final added = await updateService.check(only: book);
      expect(added, 1);

      // Verify the chapters stored in database
      final currentChapters = db.getChapters(book.id);
      expect(currentChapters.isNotEmpty, isTrue);

      // Chapter at index 0 is the brand new side story
      final newChapter = currentChapters.firstWhere(
        (c) => c.sourceChapterId == 'ss_prologue',
      );
      expect(newChapter.chapterIndex, 0.0);
      expect(newChapter.title, 'Side Story: An Unrelated Legend');
      // CRITICAL: Must NOT inherit downloaded state from oldChapter!
      expect(newChapter.downloadState, ChapterDownloadState.notDownloaded);
      expect(newChapter.localFilePath, isNull);

      // The old chapter must be in unresolvedChaptersByBook
      final unresolved = updateService.unresolvedChaptersByBook[book.id];
      expect(unresolved, isNotNull);
      expect(unresolved!.any((c) => c.id == 'old_ch_1'), isTrue);
    });

    test('Old chapter with similar title at same index is recognized and reconciled', () async {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetForTesting();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final db = DatabaseService.instance;
      await db.init(database);

      final now = DateTime.now();
      final book = Book(
        id: 'test_src:novel_2',
        sourceId: 'test_src',
        sourceNovelId: 'novel_2',
        title: 'Reconciliation Test Novel 2',
        format: BookFormat.webNovel,
        createdAt: now,
        updatedAt: now,
      );
      await db.saveBook(book);

      // Downloaded chapter with old ID format or typo in sourceChapterId
      final oldChapter = Chapter(
        id: 'old_ch_idx0',
        bookId: book.id,
        sourceChapterId: 'old_id_123',
        title: 'Chapter 1: The Beginning',
        chapterIndex: 0.0,
        downloadState: ChapterDownloadState.downloaded,
        localFilePath: '/storage/novels/ch1.html',
        updatedAt: now,
      );
      await db.saveChapters(book.id, [oldChapter]);

      final updateService = ChapterUpdateService(
        fetch: (source, novel) async {
          return const NovelDetails(
            id: 'novel_2',
            title: 'Reconciliation Test Novel 2',
            author: 'Author',
            description: 'Desc',
            coverUrl: null,
            status: 'ongoing',
            chapters: [
              SourceChapter(
                id: 'new_id_999', // Source changed its ID format
                title: 'Ch. 1 - The Beginning', // Similar title at index 0
                index: 0.0,
                url: 'https://example.com/ch1',
              ),
            ],
          );
        },
      );

      final added = await updateService.check(only: book);
      expect(added, 0); // Matched, not brand new

      final currentChapters = db.getChapters(book.id);
      final reconciledChapter = currentChapters.first;
      expect(reconciledChapter.title, 'Ch. 1 - The Beginning');
      // Downloaded state preserved across similar title match!
      expect(reconciledChapter.downloadState, ChapterDownloadState.downloaded);
      expect(reconciledChapter.localFilePath, '/storage/novels/ch1.html');
      expect(updateService.unresolvedChaptersByBook[book.id], isNull);
    });

    test('Different titles with shared tokens (e.g. The red door vs The blue door) at same index do NOT transfer downloads', () async {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetForTesting();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final db = DatabaseService.instance;
      await db.init(database);

      final now = DateTime.now();
      final book = Book(
        id: 'test_src:novel_3',
        sourceId: 'test_src',
        sourceNovelId: 'novel_3',
        title: 'Reconciliation Test Novel 3',
        format: BookFormat.webNovel,
        createdAt: now,
        updatedAt: now,
      );
      await db.saveBook(book);

      final oldChapter = Chapter(
        id: 'old_red_door',
        bookId: book.id,
        sourceChapterId: 'ch_red',
        title: 'The red door',
        chapterIndex: 0.0,
        downloadState: ChapterDownloadState.downloaded,
        localFilePath: '/storage/novels/red_door.html',
        updatedAt: now,
      );
      await db.saveChapters(book.id, [oldChapter]);

      final updateService = ChapterUpdateService(
        fetch: (source, novel) async {
          return const NovelDetails(
            id: 'novel_3',
            title: 'Reconciliation Test Novel 3',
            author: 'Author',
            description: 'Desc',
            coverUrl: null,
            status: 'ongoing',
            chapters: [
              SourceChapter(
                id: 'ch_blue',
                title: 'The blue door',
                index: 0.0,
                url: 'https://example.com/ch_blue',
              ),
            ],
          );
        },
      );

      final added = await updateService.check(only: book);
      expect(added, 1); // Replacement chapter is brand new, not matched

      final currentChapters = db.getChapters(book.id);
      final newCh = currentChapters.firstWhere((c) => c.sourceChapterId == 'ch_blue');
      expect(newCh.title, 'The blue door');
      // CRITICAL: Must NOT inherit downloaded file from The red door!
      expect(newCh.downloadState, ChapterDownloadState.notDownloaded);
      expect(newCh.localFilePath, isNull);

      // The old chapter must be safely retained in unresolvedChaptersByBook
      final unresolved = updateService.unresolvedChaptersByBook[book.id];
      expect(unresolved, isNotNull);
      expect(unresolved!.any((c) => c.id == 'old_red_door'), isTrue);
    });
  });
}
