import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as drift;
import '../models/book.dart';
import '../models/library_entry.dart';
import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../models/download_job.dart';
import '../models/bookmark.dart';
import '../files/storage_service.dart';
import 'app_database.dart';

enum LibrarySort {
  titleAz,
  titleZa,
  recent,
  progress,
}

class BookDeletionResult {
  final bool success;
  final bool recordsPurged;
  final List<String> deletedFiles;
  final List<String> failedFiles;
  final List<String> skippedExternalFiles;
  final String? errorMessage;

  const BookDeletionResult({
    required this.success,
    required this.recordsPurged,
    this.deletedFiles = const [],
    this.failedFiles = const [],
    this.skippedExternalFiles = const [],
    this.errorMessage,
  });
}

class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService._();
  DatabaseService._();

  AppDatabase? _db;
  AppDatabase get db => _db ??= AppDatabase();

  SharedPreferences? _prefs;

  final Map<String, Book> _books = {};
  final Map<String, LibraryEntry> _libraryEntries = {};
  final Map<String, List<Chapter>> _chapters = {};
  final Map<String, ReadingProgress> _readingProgress = {};
  final Map<String, DownloadJob> _downloadJobs = {};
  final Map<String, List<Bookmark>> _bookmarks = {};

  // Session-scoped suppressed novel IDs for library prompt
  final Set<String> _suppressedPromptNovelIds = {};

  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  /// Resets in-memory instance and custom DB (useful for tests)
  @visibleForTesting
  static void resetForTesting([DatabaseService? custom]) {
    _instance = custom;
  }

  Future<void> init([AppDatabase? customDb]) async {
    _prefs = await SharedPreferences.getInstance();
    _db = customDb ?? _db ?? AppDatabase();

    // 1. Run migration from legacy SharedPreferences if needed
    await _migrateFromSharedPreferencesIfNeeded();

    // 2. Load from Drift SQLite database into in-memory cache
    await _loadFromDrift();

    // 3. Clean up any legacy synthetic demo fixtures seeded by earlier versions
    _cleanLegacySyntheticDemos();
  }

  void _notify() {
    changeNotifier.value++;
  }

  /// Migrates legacy JSON-encoded records from SharedPreferences into Drift tables
  Future<void> _migrateFromSharedPreferencesIfNeeded() async {
    final prefs = _prefs;
    final database = _db;
    if (prefs == null || database == null) return;

    final isMigrated = prefs.getBool('hon_drift_migrated_v1') ?? false;
    if (isMigrated) return;

    // Read legacy records
    final legacyBooksJson = prefs.getString('hon_books');
    final legacyLibJson = prefs.getString('hon_library');
    final legacyProgJson = prefs.getString('hon_progress');
    final legacyJobsJson = prefs.getString('hon_downloads');
    final legacyChaptersJson = prefs.getString('hon_chapters');
    final legacyBookmarksJson = prefs.getString('hon_bookmarks');

    final legacyBooks = <Book>[];
    if (legacyBooksJson != null) {
      try {
        final list = jsonDecode(legacyBooksJson) as List<dynamic>;
        for (final item in list) {
          legacyBooks.add(Book.fromMap(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    final legacyLibEntries = <LibraryEntry>[];
    if (legacyLibJson != null) {
      try {
        final list = jsonDecode(legacyLibJson) as List<dynamic>;
        for (final item in list) {
          legacyLibEntries.add(LibraryEntry.fromMap(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    final legacyProgress = <ReadingProgress>[];
    if (legacyProgJson != null) {
      try {
        final list = jsonDecode(legacyProgJson) as List<dynamic>;
        for (final item in list) {
          legacyProgress.add(ReadingProgress.fromMap(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    final legacyJobs = <DownloadJob>[];
    if (legacyJobsJson != null) {
      try {
        final list = jsonDecode(legacyJobsJson) as List<dynamic>;
        for (final item in list) {
          legacyJobs.add(DownloadJob.fromMap(item as Map<String, dynamic>));
        }
      } catch (_) {}
    }

    final legacyChapters = <Chapter>[];
    if (legacyChaptersJson != null) {
      try {
        final map = jsonDecode(legacyChaptersJson) as Map<String, dynamic>;
        for (final entry in map.entries) {
          final chList = (entry.value as List<dynamic>)
              .map((c) => Chapter.fromMap(c as Map<String, dynamic>));
          legacyChapters.addAll(chList);
        }
      } catch (_) {}
    }

    final legacyBookmarks = <Bookmark>[];
    if (legacyBookmarksJson != null) {
      try {
        final map = jsonDecode(legacyBookmarksJson) as Map<String, dynamic>;
        for (final entry in map.entries) {
          final bmList = (entry.value as List<dynamic>)
              .map((b) => Bookmark.fromMap(b as Map<String, dynamic>));
          legacyBookmarks.addAll(bmList);
        }
      } catch (_) {}
    }

    // Atomic transaction for migration
    await database.batch((batch) {
      for (final b in legacyBooks) {
        batch.insert(
          database.booksTable,
          BooksTableCompanion.insert(
            id: b.id,
            title: b.title,
            author: drift.Value(b.author),
            description: drift.Value(b.description),
            coverPath: drift.Value(b.coverPath),
            format: b.format.name,
            sourceId: drift.Value(b.sourceId),
            sourceNovelId: drift.Value(b.sourceNovelId),
            filePath: drift.Value(b.filePath),
            contentHash: drift.Value(b.contentHash),
            totalChapters: drift.Value(b.totalChapters),
            createdAt: b.createdAt,
            updatedAt: b.updatedAt,
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
      }

      for (final l in legacyLibEntries) {
        batch.insert(
          database.libraryEntriesTable,
          LibraryEntriesTableCompanion.insert(
            bookId: l.bookId,
            isInLibrary: drift.Value(l.isInLibrary),
            dateAdded: l.dateAdded,
            lastReadAt: drift.Value(l.lastReadAt),
            isFinished: drift.Value(l.isFinished),
            collectionIds: drift.Value(l.collectionIds.join(',')),
            customSortOrder: drift.Value(l.customSortOrder),
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
      }

      for (final ch in legacyChapters) {
        batch.insert(
          database.chaptersTable,
          ChaptersTableCompanion.insert(
            id: ch.id,
            bookId: ch.bookId,
            sourceChapterId: ch.sourceChapterId,
            title: ch.title,
            chapterIndex: drift.Value(ch.chapterIndex),
            url: drift.Value(ch.url),
            localFilePath: drift.Value(ch.localFilePath),
            downloadState: drift.Value(ch.downloadState.name),
            releaseDate: drift.Value(ch.releaseDate),
            updatedAt: ch.updatedAt,
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
      }

      for (final p in legacyProgress) {
        batch.insert(
          database.readingProgressTable,
          ReadingProgressTableCompanion.insert(
            bookId: p.bookId,
            lastChapterId: drift.Value(p.lastChapterId),
            chapterIndex: drift.Value(p.chapterIndex),
            pageIndex: drift.Value(p.pageIndex),
            totalPages: drift.Value(p.totalPages),
            scrollOffset: drift.Value(p.scrollOffset),
            locatorString: drift.Value(p.locatorString),
            locatorVersion: drift.Value(p.locatorVersion),
            completionPercentage: drift.Value(p.completionPercentage),
            lastReadAt: p.lastReadAt,
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
      }

      for (final j in legacyJobs) {
        batch.insert(
          database.downloadJobsTable,
          DownloadJobsTableCompanion.insert(
            id: j.id,
            bookId: j.bookId,
            chapterId: j.chapterId,
            chapterTitle: j.chapterTitle,
            sourceId: j.sourceId,
            status: j.status.name,
            progress: drift.Value(j.progress),
            retryCount: drift.Value(j.retryCount),
            errorMessage: drift.Value(j.errorMessage),
            createdAt: j.createdAt,
            updatedAt: j.updatedAt,
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
      }

      for (final bm in legacyBookmarks) {
        batch.insert(
          database.bookmarksTable,
          BookmarksTableCompanion.insert(
            id: bm.id,
            bookId: bm.bookId,
            pageIndex: drift.Value(bm.pageIndex),
            chapterIndex: drift.Value(bm.chapterIndex),
            label: drift.Value(bm.label),
            snippet: drift.Value(bm.snippet),
            createdAt: bm.createdAt,
          ),
          mode: drift.InsertMode.insertOrReplace,
        );
      }
    });

    await prefs.setBool('hon_drift_migrated_v1', true);
  }

  /// Loads all records from Drift into high-performance in-memory maps
  Future<void> _loadFromDrift() async {
    final database = _db;
    if (database == null) return;

    _books.clear();
    _libraryEntries.clear();
    _chapters.clear();
    _readingProgress.clear();
    _downloadJobs.clear();
    _bookmarks.clear();

    final books = await database.select(database.booksTable).get();
    for (final row in books) {
      _books[row.id] = Book(
        id: row.id,
        title: row.title,
        author: row.author,
        description: row.description,
        coverPath: row.coverPath,
        format: BookFormat.values.firstWhere(
          (f) => f.name == row.format,
          orElse: () => BookFormat.epub,
        ),
        sourceId: row.sourceId,
        sourceNovelId: row.sourceNovelId,
        filePath: row.filePath,
        contentHash: row.contentHash,
        totalChapters: row.totalChapters,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
    }

    final entries = await database.select(database.libraryEntriesTable).get();
    for (final row in entries) {
      _libraryEntries[row.bookId] = LibraryEntry(
        bookId: row.bookId,
        isInLibrary: row.isInLibrary,
        dateAdded: row.dateAdded,
        lastReadAt: row.lastReadAt,
        isFinished: row.isFinished,
        collectionIds: row.collectionIds.isEmpty ? [] : row.collectionIds.split(','),
        customSortOrder: row.customSortOrder,
      );
    }

    final chapters = await database.select(database.chaptersTable).get();
    for (final row in chapters) {
      final ch = Chapter(
        id: row.id,
        bookId: row.bookId,
        sourceChapterId: row.sourceChapterId,
        title: row.title,
        chapterIndex: row.chapterIndex,
        url: row.url,
        localFilePath: row.localFilePath,
        downloadState: ChapterDownloadState.values.firstWhere(
          (d) => d.name == row.downloadState,
          orElse: () => ChapterDownloadState.notDownloaded,
        ),
        releaseDate: row.releaseDate,
        updatedAt: row.updatedAt,
      );
      _chapters.putIfAbsent(row.bookId, () => []).add(ch);
    }

    final progresses = await database.select(database.readingProgressTable).get();
    for (final row in progresses) {
      _readingProgress[row.bookId] = ReadingProgress(
        bookId: row.bookId,
        lastChapterId: row.lastChapterId,
        chapterIndex: row.chapterIndex,
        pageIndex: row.pageIndex,
        totalPages: row.totalPages,
        scrollOffset: row.scrollOffset,
        locatorString: row.locatorString,
        locatorVersion: row.locatorVersion,
        completionPercentage: row.completionPercentage,
        lastReadAt: row.lastReadAt,
      );
    }

    final jobs = await database.select(database.downloadJobsTable).get();
    for (final row in jobs) {
      _downloadJobs[row.id] = DownloadJob(
        id: row.id,
        bookId: row.bookId,
        chapterId: row.chapterId,
        chapterTitle: row.chapterTitle,
        sourceId: row.sourceId,
        status: DownloadStatus.values.firstWhere(
          (s) => s.name == row.status,
          orElse: () => DownloadStatus.queued,
        ),
        progress: row.progress,
        errorMessage: row.errorMessage,
        retryCount: row.retryCount,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
    }

    final bookmarks = await database.select(database.bookmarksTable).get();
    for (final row in bookmarks) {
      final bm = Bookmark(
        id: row.id,
        bookId: row.bookId,
        pageIndex: row.pageIndex,
        chapterIndex: row.chapterIndex,
        label: row.label,
        snippet: row.snippet,
        createdAt: row.createdAt,
      );
      _bookmarks.putIfAbsent(row.bookId, () => []).add(bm);
    }
  }

  void _cleanLegacySyntheticDemos() {
    // Only remove synthetic books that have no physical file and were mock-seeded
    final demoIds = ['book_good_material', 'book_first_lie_wins', 'book_war_and_peace'];
    bool modified = false;
    for (final id in demoIds) {
      if (_books.containsKey(id) && (_books[id]?.filePath == null || _books[id]?.filePath?.isEmpty == true)) {
        _books.remove(id);
        _libraryEntries.remove(id);
        _readingProgress.remove(id);
        modified = true;
      }
    }
    if (modified) {
      _syncToDriftAndBackup();
      _notify();
    }
  }

  /// Secondary JSON backup to SharedPreferences during Phase 0
  Future<void> _syncToDriftAndBackup() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setString(
      'hon_books',
      jsonEncode(_books.values.map((b) => b.toMap()).toList()),
    );
    await prefs.setString(
      'hon_library',
      jsonEncode(_libraryEntries.values.map((l) => l.toMap()).toList()),
    );
    await prefs.setString(
      'hon_progress',
      jsonEncode(_readingProgress.values.map((p) => p.toMap()).toList()),
    );
    await prefs.setString(
      'hon_downloads',
      jsonEncode(_downloadJobs.values.map((j) => j.toMap()).toList()),
    );

    final chaptersMap = <String, List<Map<String, dynamic>>>{};
    for (final entry in _chapters.entries) {
      chaptersMap[entry.key] = entry.value.map((c) => c.toMap()).toList();
    }
    await prefs.setString('hon_chapters', jsonEncode(chaptersMap));

    final bookmarksMap = <String, List<Map<String, dynamic>>>{};
    for (final entry in _bookmarks.entries) {
      bookmarksMap[entry.key] = entry.value.map((b) => b.toMap()).toList();
    }
    await prefs.setString('hon_bookmarks', jsonEncode(bookmarksMap));
  }

  // --- Books & Library ---
  List<Book> getAllBooks() => _books.values.toList();

  List<Book> getLibraryBooks({LibrarySort sort = LibrarySort.titleAz}) {
    final list = _books.values.where((b) {
      final entry = _libraryEntries[b.id];
      return entry != null && entry.isInLibrary;
    }).toList();

    switch (sort) {
      case LibrarySort.titleAz:
        list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case LibrarySort.titleZa:
        list.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case LibrarySort.recent:
        list.sort((a, b) {
          final dateA = _readingProgress[a.id]?.lastReadAt ?? _libraryEntries[a.id]?.dateAdded ?? a.updatedAt;
          final dateB = _readingProgress[b.id]?.lastReadAt ?? _libraryEntries[b.id]?.dateAdded ?? b.updatedAt;
          return dateB.compareTo(dateA);
        });
        break;
      case LibrarySort.progress:
        list.sort((a, b) {
          final pA = _readingProgress[a.id]?.completionPercentage ?? 0.0;
          final pB = _readingProgress[b.id]?.completionPercentage ?? 0.0;
          return pB.compareTo(pA);
        });
        break;
    }
    return list;
  }

  List<Book> getContinueReadingBooks() {
    final list = _books.values.where((b) {
      final prog = _readingProgress[b.id];
      final isFinished = _libraryEntries[b.id]?.isFinished ?? false;
      return prog != null && !isFinished && prog.completionPercentage < 1.0;
    }).toList();

    list.sort((a, b) {
      final dateA = _readingProgress[a.id]?.lastReadAt ?? a.updatedAt;
      final dateB = _readingProgress[b.id]?.lastReadAt ?? b.updatedAt;
      return dateB.compareTo(dateA);
    });
    return list;
  }

  Book? getBookById(String id) => _books[id];

  Book? findBookByContentHash(String hash) {
    for (final b in _books.values) {
      if (b.contentHash == hash) return b;
    }
    return null;
  }

  Future<void> saveBook(Book book) async {
    _books[book.id] = book;
    final database = _db;
    if (database != null) {
      await database.into(database.booksTable).insertOnConflictUpdate(
        BooksTableCompanion.insert(
          id: book.id,
          title: book.title,
          author: drift.Value(book.author),
          description: drift.Value(book.description),
          coverPath: drift.Value(book.coverPath),
          format: book.format.name,
          sourceId: drift.Value(book.sourceId),
          sourceNovelId: drift.Value(book.sourceNovelId),
          filePath: drift.Value(book.filePath),
          contentHash: drift.Value(book.contentHash),
          totalChapters: drift.Value(book.totalChapters),
          createdAt: book.createdAt,
          updatedAt: book.updatedAt,
        ),
      );
    }
    await _syncToDriftAndBackup();
    _notify();
  }

  Future<void> removeFromLibrary(String bookId) async {
    await setLibraryMembership(bookId, false);
  }

  Future<BookDeletionResult> deleteBook(String bookId) async {
    final book = _books[bookId];
    if (book == null) {
      return const BookDeletionResult(
        success: true,
        recordsPurged: true,
      );
    }

    final storage = StorageService.instance;
    final List<String> candidatePaths = [];

    if (book.filePath != null && !book.filePath!.startsWith('assets/')) {
      candidatePaths.add(book.filePath!);
    }
    if (book.coverPath != null &&
        !book.coverPath!.startsWith('http') &&
        !book.coverPath!.startsWith('assets/')) {
      candidatePaths.add(book.coverPath!);
    }

    // Include all downloaded chapter files
    final chapters = _chapters[bookId] ?? [];
    for (final ch in chapters) {
      if (ch.localFilePath != null && !ch.localFilePath!.startsWith('assets/')) {
        candidatePaths.add(ch.localFilePath!);
      }
    }

    final List<String> deletedFiles = [];
    final List<String> failedFiles = [];
    final List<String> skippedExternalFiles = [];

    for (final rawPath in candidatePaths.toSet()) {
      if (!storage.isPathInsideManagedStorage(rawPath)) {
        skippedExternalFiles.add(rawPath);
        continue;
      }

      try {
        final f = File(rawPath);
        if (f.existsSync()) {
          f.deleteSync();
          deletedFiles.add(rawPath);
        }
      } catch (e) {
        failedFiles.add(rawPath);
      }
    }

    if (failedFiles.isNotEmpty) {
      return BookDeletionResult(
        success: false,
        recordsPurged: false,
        deletedFiles: deletedFiles,
        failedFiles: failedFiles,
        skippedExternalFiles: skippedExternalFiles,
        errorMessage: 'Failed to delete ${failedFiles.length} file(s) from storage.',
      );
    }

    // Purge database records only when physical file deletion succeeded
    _books.remove(bookId);
    _libraryEntries.remove(bookId);
    _readingProgress.remove(bookId);
    _chapters.remove(bookId);
    _bookmarks.remove(bookId);
    _downloadJobs.removeWhere((k, v) => v.bookId == bookId);

    final database = _db;
    if (database != null) {
      await (database.delete(database.booksTable)..where((t) => t.id.equals(bookId))).go();
      await (database.delete(database.libraryEntriesTable)..where((t) => t.bookId.equals(bookId))).go();
      await (database.delete(database.readingProgressTable)..where((t) => t.bookId.equals(bookId))).go();
      await (database.delete(database.chaptersTable)..where((t) => t.bookId.equals(bookId))).go();
      await (database.delete(database.bookmarksTable)..where((t) => t.bookId.equals(bookId))).go();
      await (database.delete(database.downloadJobsTable)..where((t) => t.bookId.equals(bookId))).go();
    }

    await _syncToDriftAndBackup();
    _notify();

    return BookDeletionResult(
      success: true,
      recordsPurged: true,
      deletedFiles: deletedFiles,
      failedFiles: failedFiles,
      skippedExternalFiles: skippedExternalFiles,
    );
  }

  Future<void> setLibraryMembership(String bookId, bool isInLibrary) async {
    final current = _libraryEntries[bookId];
    final updated = current != null
        ? current.copyWith(
            isInLibrary: isInLibrary,
            dateAdded: isInLibrary ? DateTime.now() : current.dateAdded,
          )
        : LibraryEntry(
            bookId: bookId,
            isInLibrary: isInLibrary,
            dateAdded: DateTime.now(),
          );
    _libraryEntries[bookId] = updated;

    final database = _db;
    if (database != null) {
      await database.into(database.libraryEntriesTable).insertOnConflictUpdate(
        LibraryEntriesTableCompanion.insert(
          bookId: updated.bookId,
          isInLibrary: drift.Value(updated.isInLibrary),
          dateAdded: updated.dateAdded,
          lastReadAt: drift.Value(updated.lastReadAt),
          isFinished: drift.Value(updated.isFinished),
          collectionIds: drift.Value(updated.collectionIds.join(',')),
          customSortOrder: drift.Value(updated.customSortOrder),
        ),
      );
    }

    await _syncToDriftAndBackup();
    _notify();
  }

  bool isBookInLibrary(String bookId) {
    return _libraryEntries[bookId]?.isInLibrary ?? false;
  }

  Future<void> markBookFinished(String bookId, bool isFinished) async {
    final current = _libraryEntries[bookId];
    final updated = current != null
        ? current.copyWith(isFinished: isFinished)
        : LibraryEntry(
            bookId: bookId,
            isInLibrary: true,
            dateAdded: DateTime.now(),
            isFinished: isFinished,
          );
    _libraryEntries[bookId] = updated;

    final database = _db;
    if (database != null) {
      await database.into(database.libraryEntriesTable).insertOnConflictUpdate(
        LibraryEntriesTableCompanion.insert(
          bookId: updated.bookId,
          isInLibrary: drift.Value(updated.isInLibrary),
          dateAdded: updated.dateAdded,
          lastReadAt: drift.Value(updated.lastReadAt),
          isFinished: drift.Value(updated.isFinished),
          collectionIds: drift.Value(updated.collectionIds.join(',')),
          customSortOrder: drift.Value(updated.customSortOrder),
        ),
      );
    }

    await _syncToDriftAndBackup();
    _notify();
  }

  // --- Reading Progress ---
  ReadingProgress? getProgress(String bookId) => _readingProgress[bookId];

  Future<void> saveProgress(ReadingProgress progress) async {
    _readingProgress[progress.bookId] = progress;
    final entry = _libraryEntries[progress.bookId];
    if (entry != null) {
      _libraryEntries[progress.bookId] = entry.copyWith(
        lastReadAt: progress.lastReadAt,
        isFinished: entry.isFinished,
      );
    }

    final database = _db;
    if (database != null) {
      await database.into(database.readingProgressTable).insertOnConflictUpdate(
        ReadingProgressTableCompanion.insert(
          bookId: progress.bookId,
          lastChapterId: drift.Value(progress.lastChapterId),
          chapterIndex: drift.Value(progress.chapterIndex),
          pageIndex: drift.Value(progress.pageIndex),
          totalPages: drift.Value(progress.totalPages),
          scrollOffset: drift.Value(progress.scrollOffset),
          locatorString: drift.Value(progress.locatorString),
          locatorVersion: drift.Value(progress.locatorVersion),
          completionPercentage: drift.Value(progress.completionPercentage),
          lastReadAt: progress.lastReadAt,
        ),
      );
    }

    await _syncToDriftAndBackup();
    _notify();
  }

  // --- Downloads ---
  List<DownloadJob> getAllDownloadJobs() => _downloadJobs.values.toList();

  Future<void> enqueueDownload(DownloadJob job) async {
    _downloadJobs[job.id] = job;
    final database = _db;
    if (database != null) {
      await database.into(database.downloadJobsTable).insertOnConflictUpdate(
        DownloadJobsTableCompanion.insert(
          id: job.id,
          bookId: job.bookId,
          chapterId: job.chapterId,
          chapterTitle: job.chapterTitle,
          sourceId: job.sourceId,
          status: job.status.name,
          progress: drift.Value(job.progress),
          retryCount: drift.Value(job.retryCount),
          errorMessage: drift.Value(job.errorMessage),
          createdAt: job.createdAt,
          updatedAt: job.updatedAt,
        ),
      );
    }
    await _syncToDriftAndBackup();
    _notify();
  }

  Future<void> updateDownloadJob(DownloadJob job) async {
    _downloadJobs[job.id] = job;
    final database = _db;
    if (database != null) {
      await database.into(database.downloadJobsTable).insertOnConflictUpdate(
        DownloadJobsTableCompanion.insert(
          id: job.id,
          bookId: job.bookId,
          chapterId: job.chapterId,
          chapterTitle: job.chapterTitle,
          sourceId: job.sourceId,
          status: job.status.name,
          progress: drift.Value(job.progress),
          retryCount: drift.Value(job.retryCount),
          errorMessage: drift.Value(job.errorMessage),
          createdAt: job.createdAt,
          updatedAt: job.updatedAt,
        ),
      );
    }
    await _syncToDriftAndBackup();
    _notify();
  }

  Future<void> removeDownloadJob(String jobId) async {
    _downloadJobs.remove(jobId);
    final database = _db;
    if (database != null) {
      await (database.delete(database.downloadJobsTable)..where((t) => t.id.equals(jobId))).go();
    }
    await _syncToDriftAndBackup();
    _notify();
  }

  // --- Session-Scoped Prompt Suppression ---
  bool isPromptSuppressedForSession(String novelId) {
    return _suppressedPromptNovelIds.contains(novelId);
  }

  void suppressPromptForSession(String novelId) {
    _suppressedPromptNovelIds.add(novelId);
  }

  // --- Chapters ---
  List<Chapter> getChaptersForBook(String bookId) {
    return _chapters[bookId] ?? [];
  }

  List<Chapter> getChapters(String bookId) => getChaptersForBook(bookId);

  Future<void> setChaptersForBook(String bookId, List<Chapter> chapters) async {
    _chapters[bookId] = chapters;
    final database = _db;
    if (database != null) {
      await database.batch((batch) {
        for (final ch in chapters) {
          batch.insert(
            database.chaptersTable,
            ChaptersTableCompanion.insert(
              id: ch.id,
              bookId: ch.bookId,
              sourceChapterId: ch.sourceChapterId,
              title: ch.title,
              chapterIndex: drift.Value(ch.chapterIndex),
              url: drift.Value(ch.url),
              localFilePath: drift.Value(ch.localFilePath),
              downloadState: drift.Value(ch.downloadState.name),
              releaseDate: drift.Value(ch.releaseDate),
              updatedAt: ch.updatedAt,
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
        }
      });
    }
    await _syncToDriftAndBackup();
    _notify();
  }

  Future<void> saveChapters(String bookId, List<Chapter> chapters) =>
      setChaptersForBook(bookId, chapters);

  // --- Bookmarks ---
  List<Bookmark> getBookmarks(String bookId) {
    final list = _bookmarks[bookId] ?? [];
    list.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return List.unmodifiable(list);
  }

  bool isBookmarked(String bookId, int pageIndex) {
    final list = _bookmarks[bookId];
    if (list == null) return false;
    return list.any((b) => b.pageIndex == pageIndex);
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    final list = _bookmarks.putIfAbsent(bookmark.bookId, () => []);
    list.removeWhere((b) => b.pageIndex == bookmark.pageIndex);
    list.add(bookmark);

    final database = _db;
    if (database != null) {
      await database.into(database.bookmarksTable).insertOnConflictUpdate(
        BookmarksTableCompanion.insert(
          id: bookmark.id,
          bookId: bookmark.bookId,
          pageIndex: drift.Value(bookmark.pageIndex),
          chapterIndex: drift.Value(bookmark.chapterIndex),
          label: drift.Value(bookmark.label),
          snippet: drift.Value(bookmark.snippet),
          createdAt: bookmark.createdAt,
        ),
      );
    }
    await _syncToDriftAndBackup();
    _notify();
  }

  Future<void> removeBookmark(String bookId, int pageIndex) async {
    final list = _bookmarks[bookId];
    if (list != null) {
      list.removeWhere((b) => b.pageIndex == pageIndex);
      final database = _db;
      if (database != null) {
        await (database.delete(database.bookmarksTable)
              ..where((t) => t.bookId.equals(bookId) & t.pageIndex.equals(pageIndex)))
            .go();
      }
      await _syncToDriftAndBackup();
      _notify();
    }
  }

  Future<bool> toggleBookmark(
    String bookId,
    int pageIndex, {
    String? label,
    String? snippet,
  }) async {
    if (isBookmarked(bookId, pageIndex)) {
      await removeBookmark(bookId, pageIndex);
      return false;
    } else {
      final bm = Bookmark(
        id: 'bm_${bookId}_$pageIndex',
        bookId: bookId,
        pageIndex: pageIndex,
        label: label ?? 'Page $pageIndex',
        createdAt: DateTime.now(),
        snippet: snippet,
      );
      await addBookmark(bm);
      return true;
    }
  }

  // --- PDF Reader Preferences ---
  String getPdfColorFilter() {
    return _prefs?.getString('hon_pdf_color_filter') ?? 'original';
  }

  Future<void> setPdfColorFilter(String filterName) async {
    await _prefs?.setString('hon_pdf_color_filter', filterName);
  }

  String getPdfPageViewMode() {
    return _prefs?.getString('hon_pdf_view_mode') ?? 'continuousZoom';
  }

  Future<void> setPdfPageViewMode(String modeName) async {
    await _prefs?.setString('hon_pdf_view_mode', modeName);
  }

  // --- Reading Goals & Time ---
  int getDailyGoalMinutes() {
    return _prefs?.getInt('hon_daily_goal_minutes') ?? 5;
  }

  Future<void> setDailyGoalMinutes(int minutes) async {
    await _prefs?.setInt('hon_daily_goal_minutes', minutes);
    _notify();
  }

  int getTodayReadingMinutes() {
    final now = DateTime.now();
    final dateKey = 'hon_reading_secs_${now.year}_${now.month}_${now.day}';
    final secs = _prefs?.getInt(dateKey) ?? 0;
    return (secs / 60).floor();
  }

  Future<void> addReadingTime(int seconds) async {
    final now = DateTime.now();
    final dateKey = 'hon_reading_secs_${now.year}_${now.month}_${now.day}';
    final current = _prefs?.getInt(dateKey) ?? 0;
    await _prefs?.setInt(dateKey, current + seconds);
    _notify();
  }
}
