import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/log_ignored.dart';

part 'app_database.g.dart';

class BooksTable extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant('Unknown Author'))();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get coverPath => text().nullable()();
  TextColumn get format => text()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get sourceNovelId => text().nullable()();
  TextColumn get filePath => text().nullable()();
  TextColumn get contentHash => text().nullable()();
  IntColumn get totalChapters => integer().withDefault(const Constant(1))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LibraryEntriesTable extends Table {
  TextColumn get bookId => text()();
  BoolColumn get isInLibrary => boolean().withDefault(const Constant(false))();
  DateTimeColumn get dateAdded => dateTime()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();
  BoolColumn get isFinished => boolean().withDefault(const Constant(false))();
  TextColumn get collectionIds => text().withDefault(const Constant(''))();
  IntColumn get customSortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {bookId};
}

class ChaptersTable extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get sourceChapterId => text()();
  TextColumn get title => text()();
  RealColumn get chapterIndex => real().withDefault(const Constant(0.0))();
  TextColumn get url => text().nullable()();
  TextColumn get localFilePath => text().nullable()();
  TextColumn get downloadState => text().withDefault(const Constant('notDownloaded'))();
  DateTimeColumn get releaseDate => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class DownloadJobsTable extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get chapterId => text()();
  TextColumn get chapterTitle => text()();
  TextColumn get sourceId => text()();
  TextColumn get status => text()();
  RealColumn get progress => real().withDefault(const Constant(0.0))();
  IntColumn get retryCount => integer().withDefault(const Constant(0))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class ReadingProgressTable extends Table {
  TextColumn get bookId => text()();
  TextColumn get lastChapterId => text().nullable()();
  RealColumn get chapterIndex => real().withDefault(const Constant(0.0))();
  IntColumn get pageIndex => integer().withDefault(const Constant(0))();
  IntColumn get totalPages => integer().withDefault(const Constant(1))();
  RealColumn get scrollOffset => real().withDefault(const Constant(0.0))();
  TextColumn get locatorString => text().nullable()();
  TextColumn get locatorVersion => text().nullable()();
  RealColumn get completionPercentage => real().withDefault(const Constant(0.0))();
  DateTimeColumn get lastReadAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

class BookmarksTable extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  IntColumn get pageIndex => integer().withDefault(const Constant(1))();
  IntColumn get chapterIndex => integer().nullable()();
  TextColumn get label => text().withDefault(const Constant('Bookmark'))();
  TextColumn get snippet => text().nullable()();
  TextColumn get locatorString => text().nullable()();
  TextColumn get locatorVersion => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class AppSettingsTable extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

class CollectionsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class LibraryCollectionMembershipsTable extends Table {
  TextColumn get collectionId => text()();
  TextColumn get bookId => text()();

  @override
  Set<Column> get primaryKey => {collectionId, bookId};
}

class ChapterUpdateHistoryTable extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get chapterId => text()();
  TextColumn get title => text()();
  DateTimeColumn get detectedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class HighlightsTable extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text()();
  TextColumn get locatorString => text()();
  TextColumn get selectedText => text()();
  TextColumn get color => text().withDefault(const Constant('yellow'))();
  TextColumn get note => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class BookReaderSettingsTable extends Table {
  TextColumn get bookId => text()();
  TextColumn get settingsJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId};
}

@DriftDatabase(tables: [
  BooksTable,
  LibraryEntriesTable,
  ChaptersTable,
  DownloadJobsTable,
  ReadingProgressTable,
  BookmarksTable,
  AppSettingsTable,
  CollectionsTable,
  LibraryCollectionMembershipsTable,
  ChapterUpdateHistoryTable,
  HighlightsTable,
  BookReaderSettingsTable,
])
class AppDatabase extends _$AppDatabase {
  /// When true, allows fallback to NativeDatabase.memory() if storage initialization
  /// fails (e.g., in headless test environments without path_provider mocks).
  /// In production, this flag is false by default so persistence failures throw a visible error.
  static bool allowMemoryFallbackForTesting = false;

  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 3;

  Future<void> _addIndexes() async {
    for (final sql in [
      'CREATE INDEX IF NOT EXISTS chapters_book ON chapters_table(book_id)',
      'CREATE INDEX IF NOT EXISTS chapters_source ON chapters_table(book_id, source_chapter_id)',
      'CREATE INDEX IF NOT EXISTS download_status ON download_jobs_table(status)',
      'CREATE INDEX IF NOT EXISTS download_chapter ON download_jobs_table(chapter_id)',
      'CREATE INDEX IF NOT EXISTS bookmarks_book ON bookmarks_table(book_id)',
    ]) {
      await customStatement(sql);
    }
  }

  Future<void> _addIndexesV3() async {
    for (final sql in [
      'CREATE INDEX IF NOT EXISTS collections_name ON collections_table(name)',
      'CREATE INDEX IF NOT EXISTS memberships_book ON library_collection_memberships_table(book_id)',
      'CREATE INDEX IF NOT EXISTS memberships_collection ON library_collection_memberships_table(collection_id)',
      'CREATE INDEX IF NOT EXISTS update_history_book ON chapter_update_history_table(book_id)',
      'CREATE INDEX IF NOT EXISTS update_history_detected ON chapter_update_history_table(detected_at)',
      'CREATE INDEX IF NOT EXISTS highlights_book ON highlights_table(book_id)',
    ]) {
      await customStatement(sql);
    }
  }

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _addIndexes();
      await _addIndexesV3();
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) await _addIndexes();
      if (from < 3) {
        await m.createTable(collectionsTable);
        await m.createTable(libraryCollectionMembershipsTable);
        await m.createTable(chapterUpdateHistoryTable);
        await m.createTable(highlightsTable);
        await m.createTable(bookReaderSettingsTable);
        await m.addColumn(bookmarksTable, bookmarksTable.locatorString);
        await m.addColumn(bookmarksTable, bookmarksTable.locatorVersion);
        await _addIndexesV3();

        try {
          final prefs = await SharedPreferences.getInstance();
          final raw = prefs.getString('hon_collections_v1');
          final now = DateTime.now();
          if (raw != null && raw.isNotEmpty) {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              for (final entry in decoded.entries) {
                await into(collectionsTable).insert(
                  CollectionsTableCompanion.insert(
                    id: entry.key.toString(),
                    name: entry.value.toString(),
                    createdAt: now,
                    updatedAt: now,
                  ),
                  mode: InsertMode.insertOrReplace,
                );
              }
            }
          }
        } catch (e) {
          logIgnored(e, 'app_database');
        }

        try {
          final entries = await select(libraryEntriesTable).get();
          for (final entry in entries) {
            final colIdsRaw = entry.collectionIds;
            if (colIdsRaw.isNotEmpty) {
              final colIds = colIdsRaw
                  .split(',')
                  .map((s) => s.trim())
                  .where((s) => s.isNotEmpty);
              for (final colId in colIds) {
                await into(libraryCollectionMembershipsTable).insert(
                  LibraryCollectionMembershipsTableCompanion.insert(
                    collectionId: colId,
                    bookId: entry.bookId,
                  ),
                  mode: InsertMode.insertOrReplace,
                );
              }
            }
          }
        } catch (e) {
          logIgnored(e, 'app_database');
        }
      }
    },
    beforeOpen: (_) async {
      await customSelect('PRAGMA journal_mode = WAL').get();
      await customStatement('PRAGMA foreign_keys = ON');
      await customSelect('PRAGMA busy_timeout = 5000').get();
    },
  );

  static LazyDatabase _openConnection() {
    return LazyDatabase(() async {
      try {
        final dbFolder = await getApplicationDocumentsDirectory();
        final file = File(p.join(dbFolder.path, 'hon.sqlite'));
        return NativeDatabase.createInBackground(file);
      } catch (e) {
        if (allowMemoryFallbackForTesting) {
          return NativeDatabase.memory();
        }
        throw StateError(
          'Failed to open durable SQLite persistence database at hon.sqlite: $e. '
          'In-memory fallback is disabled in production to protect against data loss.',
        );
      }
    });
  }

  static AppDatabase inMemory() {
    return AppDatabase(NativeDatabase.memory());
  }
}
