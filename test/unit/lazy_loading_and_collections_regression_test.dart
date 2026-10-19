import 'dart:convert';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/sources/native_shosetsu_bridge.dart';
import 'package:hon/core/sources/source_registry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase inMemoryDb;
  late DatabaseService dbService;

  setUp(() async {
    inMemoryDb = AppDatabase.inMemory();
    DatabaseService.resetForTesting(DatabaseService.instance);
    dbService = DatabaseService.instance;
  });

  tearDown(() async {
    await inMemoryDb.close();
  });

  group('Lazy Chapter Loading & Collections Migration Regressions', () {
    test(
      'Test (a): Cold start, exportSnapshot contains all chapter rows from unopened books',
      () async {
        SharedPreferences.setMockInitialValues({
          'hon_drift_migrated_v1': true,
          'hon_collections_migrated_v3': true,
        });
        await dbService.init(inMemoryDb);

        final now = DateTime.now();
        final book1 = Book(
          id: 'book_alpha',
          title: 'Alpha Book',
          format: BookFormat.webNovel,
          createdAt: now,
          updatedAt: now,
        );
        final book2 = Book(
          id: 'book_beta',
          title: 'Beta Book',
          format: BookFormat.webNovel,
          createdAt: now,
          updatedAt: now,
        );

        await dbService.saveBook(book1);
        await dbService.saveBook(book2);

        await dbService.saveChapters('book_alpha', [
          Chapter(
            id: 'alpha_ch1',
            bookId: 'book_alpha',
            sourceChapterId: 'ch1',
            title: 'Alpha Chapter 1',
            chapterIndex: 0.0,
            updatedAt: now,
          ),
          Chapter(
            id: 'alpha_ch2',
            bookId: 'book_alpha',
            sourceChapterId: 'ch2',
            title: 'Alpha Chapter 2',
            chapterIndex: 1.0,
            updatedAt: now,
          ),
        ]);

        await dbService.saveChapters('book_beta', [
          Chapter(
            id: 'beta_ch1',
            bookId: 'book_beta',
            sourceChapterId: 'ch1',
            title: 'Beta Chapter 1',
            chapterIndex: 0.0,
            updatedAt: now,
          ),
          Chapter(
            id: 'beta_ch2',
            bookId: 'book_beta',
            sourceChapterId: 'ch2',
            title: 'Beta Chapter 2',
            chapterIndex: 1.0,
            updatedAt: now,
          ),
          Chapter(
            id: 'beta_ch3',
            bookId: 'book_beta',
            sourceChapterId: 'ch3',
            title: 'Beta Chapter 3',
            chapterIndex: 2.0,
            updatedAt: now,
          ),
        ]);

        // Cold start simulation: re-init without loading any chapters into in-memory _chapters map
        DatabaseService.resetForTesting();
        final coldDbService = DatabaseService.instance;
        await coldDbService.init(inMemoryDb);

        // Verify neither book has loaded chapters in memory
        expect(coldDbService.getChapters('book_alpha'), isEmpty);
        expect(coldDbService.getChapters('book_beta'), isEmpty);

        // Export snapshot directly reads all chapter rows from SQLite
        final snapshot = await coldDbService.exportSnapshot();
        final exportedChapters = snapshot['chapters'] as List<dynamic>;

        expect(exportedChapters.length, 5);
        final exportedIds = exportedChapters.map((c) => (c as Map)['id']).toSet();
        expect(exportedIds, containsAll([
          'alpha_ch1',
          'alpha_ch2',
          'beta_ch1',
          'beta_ch2',
          'beta_ch3',
        ]));
      },
    );

    test(
      'Test (b): Cold start, saveChapters preserves downloaded state and localFilePath',
      () async {
        SharedPreferences.setMockInitialValues({
          'hon_drift_migrated_v1': true,
          'hon_collections_migrated_v3': true,
        });
        await dbService.init(inMemoryDb);

        final now = DateTime.now();
        const novelId = 'gutenberg:1234';
        final novel = Book(
          id: novelId,
          title: 'Gutenberg Novel',
          sourceId: 'gutenberg',
          sourceNovelId: '1234',
          format: BookFormat.webNovel,
          createdAt: now,
          updatedAt: now,
        );
        await dbService.saveBook(novel);

        // Initial state: Chapter 1 is downloaded to a local file
        final ch1 = Chapter(
          id: '$novelId:ch1',
          bookId: novelId,
          sourceChapterId: 'ch1',
          title: 'Chapter 1',
          chapterIndex: 0.0,
          downloadState: ChapterDownloadState.downloaded,
          localFilePath: '/managed/storage/chapters/ch1.html',
          updatedAt: now,
        );
        final ch2 = Chapter(
          id: '$novelId:ch2',
          bookId: novelId,
          sourceChapterId: 'ch2',
          title: 'Chapter 2',
          chapterIndex: 1.0,
          downloadState: ChapterDownloadState.notDownloaded,
          localFilePath: null,
          updatedAt: now,
        );

        await dbService.saveChapters(novelId, [ch1, ch2]);
        expect(dbService.getDownloadedChapterCount(novelId), 1);

        // Cold start simulation: re-initialize DatabaseService
        DatabaseService.resetForTesting();
        final coldDbService = DatabaseService.instance;
        await coldDbService.init(inMemoryDb);

        // The chapters are not loaded into memory yet
        expect(coldDbService.getChapters(novelId), isEmpty);

        // Simulate opening novel in Browse and calling saveChapters with newly fetched metadata
        // (which upstream provides with default notDownloaded and null localFilePath)
        final freshUpstreamChapters = [
          Chapter(
            id: '$novelId:ch1',
            bookId: novelId,
            sourceChapterId: 'ch1',
            title: 'Chapter 1 (Updated Title)',
            chapterIndex: 0.0,
            downloadState: ChapterDownloadState.notDownloaded,
            localFilePath: null,
            updatedAt: DateTime.now(),
          ),
          Chapter(
            id: '$novelId:ch2',
            bookId: novelId,
            sourceChapterId: 'ch2',
            title: 'Chapter 2',
            chapterIndex: 1.0,
            downloadState: ChapterDownloadState.notDownloaded,
            localFilePath: null,
            updatedAt: DateTime.now(),
          ),
          Chapter(
            id: '$novelId:ch3',
            bookId: novelId,
            sourceChapterId: 'ch3',
            title: 'Chapter 3',
            chapterIndex: 2.0,
            downloadState: ChapterDownloadState.notDownloaded,
            localFilePath: null,
            updatedAt: DateTime.now(),
          ),
        ];

        await coldDbService.saveChapters(novelId, freshUpstreamChapters);

        // Verify chapter 1 retained its downloaded state and localFilePath
        final chapters = coldDbService.getChapters(novelId);
        expect(chapters.length, 3);
        final ch1Merged = chapters.firstWhere((c) => c.id == '$novelId:ch1');
        expect(ch1Merged.downloadState, ChapterDownloadState.downloaded);
        expect(ch1Merged.localFilePath, '/managed/storage/chapters/ch1.html');
        expect(ch1Merged.title, 'Chapter 1 (Updated Title)');

        // Verify in SQLite directly
        final dbRow = await (inMemoryDb.select(inMemoryDb.chaptersTable)
              ..where((t) => t.id.equals('$novelId:ch1')))
            .getSingle();
        expect(dbRow.downloadState, 'downloaded');
        expect(dbRow.localFilePath, '/managed/storage/chapters/ch1.html');

        expect(coldDbService.getDownloadedChapterCount(novelId), 1);
        expect(coldDbService.getTotalChapterCount(novelId), 3);
      },
    );

    test(
      'Test (c): Collections migration copies v2 prefs and memberships, new collection does not erase old ones',
      () async {
        final now = DateTime.now();

        // 1. Seed v2 state: hon_collections_v1 in SharedPreferences, book in SQLite with comma-separated collectionIds
        final initialPrefs = {
          'hon_collections_v1': jsonEncode({
            'col_1': 'Favorites',
            'col_2': 'Sci-Fi',
          }),
          'hon_drift_migrated_v1': true,
          // 'hon_collections_migrated_v3' is absent
        };
        SharedPreferences.setMockInitialValues(initialPrefs);

        final book = Book(
          id: 'v2_book_1',
          title: 'V2 Book',
          format: BookFormat.epub,
          createdAt: now,
          updatedAt: now,
        );
        await inMemoryDb.into(inMemoryDb.booksTable).insert(
              BooksTableCompanion.insert(
                id: book.id,
                title: book.title,
                format: book.format.name,
                createdAt: now,
                updatedAt: now,
              ),
            );
        await inMemoryDb.into(inMemoryDb.libraryEntriesTable).insert(
              LibraryEntriesTableCompanion.insert(
                bookId: book.id,
                dateAdded: now,
                collectionIds: const Value('col_1,col_2'),
              ),
            );

        // 2. Initialize DatabaseService (triggers migration)
        await dbService.init(inMemoryDb);

        // 3. Assert initial 2 collections are migrated
        expect(dbService.collections.length, 2);
        expect(dbService.collections['col_1'], 'Favorites');
        expect(dbService.collections['col_2'], 'Sci-Fi');

        // Check memberships
        final entry = dbService.getLibraryEntry('v2_book_1');
        expect(entry?.collectionIds, containsAll(['col_1', 'col_2']));

        // Check SQLite tables
        final sqliteCols = await inMemoryDb.select(inMemoryDb.collectionsTable).get();
        expect(sqliteCols.length, 2);
        final sqliteMemberships = await inMemoryDb
            .select(inMemoryDb.libraryCollectionMembershipsTable)
            .get();
        expect(sqliteMemberships.length, 2);

        // 4. Create a third collection
        final col3Id = await dbService.createCollection('Classics');
        expect(dbService.collections.length, 3);
        expect(dbService.collections.values, containsAll(['Favorites', 'Sci-Fi', 'Classics']));

        // 5. Cold restart: simulate next app launch
        DatabaseService.resetForTesting();
        final restartedDbService = DatabaseService.instance;
        await restartedDbService.init(inMemoryDb);

        // Assert all 3 collections and memberships are STILL present
        expect(restartedDbService.collections.length, 3);
        expect(restartedDbService.collections['col_1'], 'Favorites');
        expect(restartedDbService.collections['col_2'], 'Sci-Fi');
        expect(restartedDbService.collections[col3Id], 'Classics');

        final restartedEntry = restartedDbService.getLibraryEntry('v2_book_1');
        expect(restartedEntry?.collectionIds, containsAll(['col_1', 'col_2']));
      },
    );

    test(
      'Test (d): NativeShosetsuBridge on Android surfaces SOURCE_ENGINE_UNAVAILABLE without falling back to Dart Lua',
      () async {
        NativeShosetsuBridge.instance.resetForTesting();
        NativeShosetsuBridge.platformOverrideIsAndroid = true;

        const channel = MethodChannel('com.hon.reader/shosetsu_native');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'isNativeSupported') {
            throw PlatformException(
              code: 'SOURCE_ENGINE_UNAVAILABLE',
              message: 'Native source engine failed to load',
            );
          }
          return null;
        });

        // If isSupported() is called when native throws SOURCE_ENGINE_UNAVAILABLE, it must rethrow PlatformException
        await expectLater(
          () => NativeShosetsuBridge.instance.isSupported(),
          throwsA(isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'SOURCE_ENGINE_UNAVAILABLE',
          )),
        );

        // searchSource must surface the error to the UI rather than falling back to Dart Lua
        SourceRegistry.instance.setSourceScriptForTesting(
          'gutenberg',
          'function search() return {} end',
        );
        await expectLater(
          () => SourceRegistry.instance.searchSource('gutenberg', 'test query'),
          throwsA(isA<PlatformException>().having(
            (e) => e.code,
            'code',
            'SOURCE_ENGINE_UNAVAILABLE',
          )),
        );

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        NativeShosetsuBridge.instance.resetForTesting();
      },
    );
  });
}
