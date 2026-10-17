import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

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

@DriftDatabase(tables: [
  BooksTable,
  LibraryEntriesTable,
  ChaptersTable,
  DownloadJobsTable,
  ReadingProgressTable,
  BookmarksTable,
  AppSettingsTable,
])
class AppDatabase extends _$AppDatabase {
  /// When true, allows fallback to NativeDatabase.memory() if storage initialization
  /// fails (e.g., in headless test environments without path_provider mocks).
  /// In production, this flag is false by default so persistence failures throw a visible error.
  static bool allowMemoryFallbackForTesting = false;

  AppDatabase([QueryExecutor? e]) : super(e ?? _openConnection());

  @override
  int get schemaVersion => 1;

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
