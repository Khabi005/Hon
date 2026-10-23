import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:drift/drift.dart' as drift;
import '../models/book.dart';
import '../models/library_entry.dart';
import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../models/download_job.dart';
import '../models/bookmark.dart';
import '../models/highlight.dart';
import '../models/chapter_deletion_result.dart';
import '../files/storage_service.dart';
import '../utils/epub_parser.dart';
import 'app_database.dart';

export '../models/chapter_deletion_result.dart';

enum LibrarySort { titleAz, titleZa, recent, progress }

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
  final Map<String, List<Highlight>> _highlights = {};
  final Map<String, Map<String, dynamic>> _bookReaderSettings = {};
  final Map<String, String> _collections = {};
  final Map<String, int> _downloadedCounts = {};
  final Map<String, int> _totalCounts = {};

  // Session-scoped suppressed novel IDs for library prompt
  final Set<String> _suppressedPromptNovelIds = {};

  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);
  final ValueNotifier<int> libraryChangeNotifier = ValueNotifier<int>(0);

  void addListener(VoidCallback listener) => changeNotifier.addListener(listener);
  void removeListener(VoidCallback listener) => changeNotifier.removeListener(listener);

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

    // 2. Run collections migration from v2 to v3 if needed
    await _migrateCollectionsV2ToV3IfNeeded();

    // 3. Load from Drift SQLite database into in-memory cache
    await _loadFromDrift();

    // 4. Clean up any legacy synthetic demo fixtures seeded by earlier versions
    _cleanLegacySyntheticDemos();
  }

  int _notificationBatch = 0;
  void _notify({bool library = true}) {
    if (_notificationBatch == 0) {
      changeNotifier.value++;
      if (library) libraryChangeNotifier.value++;
    }
  }

  Timer? _progressNotifyTimer;

  /// Native progress events can arrive many times a second per job. Coalesce
  /// them so Home, the tab bar and Downloads rebuild at most ~7 times a second.
  void _notifyDownloadProgress() {
    if (_progressNotifyTimer?.isActive ?? false) return;
    _progressNotifyTimer = Timer(const Duration(milliseconds: 150), () {
      _notify(library: false);
    });
  }

  Future<void> reloadPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _notify();
  }

  Map<String, String> get collections => Map.unmodifiable(_collections);

  List<LibraryEntry> get libraryEntries => List.unmodifiable(_libraryEntries.values);

  LibraryEntry? getLibraryEntry(String bookId) => _libraryEntries[bookId];

  Future<String> createCollection(String name, {String? id}) async {
    final clean = name.trim();
    if (clean.isEmpty || clean.length > 80) {
      throw const FormatException('Use a collection name of 1–80 characters.');
    }
    final all = Map<String, String>.from(collections);
    if (id != null && all.containsKey(id)) {
      return id;
    }
    if (all.values.any((value) => value.toLowerCase() == clean.toLowerCase())) {
      final existingKey = all.entries.firstWhere((e) => e.value.toLowerCase() == clean.toLowerCase()).key;
      return existingKey;
    }
    final resolvedId = id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final now = DateTime.now();
    _collections[resolvedId] = clean;
    final database = _db;
    if (database != null) {
      await database.into(database.collectionsTable).insert(
        CollectionsTableCompanion.insert(
          id: resolvedId,
          name: clean,
          createdAt: now,
          updatedAt: now,
        ),
        mode: drift.InsertMode.insertOrReplace,
      );
    }
    await _prefs?.setString('hon_collections_v1', jsonEncode(_collections));
    _notify();
    return resolvedId;
  }

  Future<void> renameCollection(String id, String name) async {
    final all = collections;
    final clean = name.trim();
    if (!all.containsKey(id) || clean.isEmpty || clean.length > 80) {
      throw const FormatException(
        'Choose an existing collection and a name of 1–80 characters.',
      );
    }
    if (all.entries.any(
      (entry) =>
          entry.key != id && entry.value.toLowerCase() == clean.toLowerCase(),
    )) {
      throw const FormatException('That collection already exists.');
    }
    _collections[id] = clean;
    final database = _db;
    if (database != null) {
      await (database.update(database.collectionsTable)..where((t) => t.id.equals(id))).write(
        CollectionsTableCompanion(
          name: drift.Value(clean),
          updatedAt: drift.Value(DateTime.now()),
        ),
      );
    }
    await _prefs?.setString('hon_collections_v1', jsonEncode(_collections));
    _notify();
  }

  Future<void> setBookCollections(String bookId, Iterable<String> ids) async {
    final entry = _libraryEntries[bookId];
    if (entry == null) throw StateError('Add this book to the library first.');
    final valid = collections;
    final updatedIds = ids.where(valid.containsKey).toSet().toList();
    final updated = entry.copyWith(collectionIds: updatedIds);
    final database = _db;
    if (database != null) {
      await database.transaction(() async {
        await (database.delete(database.libraryCollectionMembershipsTable)
              ..where((t) => t.bookId.equals(bookId)))
            .go();
        for (final colId in updatedIds) {
          await database.into(database.libraryCollectionMembershipsTable).insert(
            LibraryCollectionMembershipsTableCompanion.insert(
              collectionId: colId,
              bookId: bookId,
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
        }
        await _writeLibraryEntry(updated);
      });
    }
    _libraryEntries[bookId] = updated;
    _notify();
  }

  Future<void> deleteCollection(String id) async {
    _collections.remove(id);
    final database = _db;
    if (database != null) {
      await database.transaction(() async {
        await (database.delete(database.collectionsTable)
              ..where((t) => t.id.equals(id)))
            .go();
        await (database.delete(database.libraryCollectionMembershipsTable)
              ..where((t) => t.collectionId.equals(id)))
            .go();
        for (final entry in _libraryEntries.values
            .where((entry) => entry.collectionIds.contains(id))
            .toList()) {
          final updated = entry.copyWith(
            collectionIds: entry.collectionIds
                .where((value) => value != id)
                .toList(),
          );
          await _writeLibraryEntry(updated);
        }
      });
    }
    for (final entry in _libraryEntries.values.toList()) {
      if (entry.collectionIds.contains(id)) {
        _libraryEntries[entry.bookId] = entry.copyWith(
          collectionIds: entry.collectionIds
              .where((value) => value != id)
              .toList(),
        );
      }
    }
    await _prefs?.setString('hon_collections_v1', jsonEncode(_collections));
    _notify();
  }

  Future<void> _writeLibraryEntry(LibraryEntry entry) async {
    final database = db;
    await database.transaction(() async {
      await database
          .into(database.libraryEntriesTable)
          .insertOnConflictUpdate(
            LibraryEntriesTableCompanion.insert(
              bookId: entry.bookId,
              isInLibrary: drift.Value(entry.isInLibrary),
              dateAdded: entry.dateAdded,
              lastReadAt: drift.Value(entry.lastReadAt),
              isFinished: drift.Value(entry.isFinished),
              collectionIds: drift.Value(entry.collectionIds.join(',')),
              customSortOrder: drift.Value(entry.customSortOrder),
            ),
          );
      await (database.delete(database.libraryCollectionMembershipsTable)
            ..where((t) => t.bookId.equals(entry.bookId)))
          .go();
      for (final colId in entry.collectionIds) {
        if (colId.isNotEmpty) {
          await database.into(database.libraryCollectionMembershipsTable).insert(
            LibraryCollectionMembershipsTableCompanion.insert(
              collectionId: colId,
              bookId: entry.bookId,
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
        }
      }
    });
  }

  Future<Map<String, dynamic>> exportSnapshot() async {
    final database = _db;
    List<Map<String, dynamic>> chapterList;
    if (database != null) {
      final rows = await database.select(database.chaptersTable).get();
      chapterList = rows
          .map((r) => Chapter(
                id: r.id,
                bookId: r.bookId,
                sourceChapterId: r.sourceChapterId,
                title: r.title,
                chapterIndex: r.chapterIndex,
                url: r.url,
                localFilePath: r.localFilePath,
                downloadState: ChapterDownloadState.values.firstWhere(
                  (s) => s.name == r.downloadState,
                  orElse: () => ChapterDownloadState.notDownloaded,
                ),
                releaseDate: r.releaseDate,
                updatedAt: r.updatedAt,
              ).toMap())
          .toList();
    } else {
      chapterList = _chapters.values
          .expand((items) => items)
          .map((value) => value.toMap())
          .toList();
    }

    return {
      'books': _books.values.map((value) => value.toMap()).toList(),
      'library': _libraryEntries.values.map((value) => value.toMap()).toList(),
      'chapters': chapterList,
      'progress': _readingProgress.values.map((value) => value.toMap()).toList(),
      'bookmarks': _bookmarks.values
          .expand((items) => items)
          .map((value) => value.toMap())
          .toList(),
      'downloads': _downloadJobs.values.map((value) => value.toMap()).toList(),
      'highlights': _highlights.values
          .expand((items) => items)
          .map((value) => value.toMap())
          .toList(),
      'bookReaderSettings': _bookReaderSettings,
      'collections': _collections,
    };
  }

  /// All records are parsed and checked before any write. Existing unrelated
  /// books are retained; imported jobs remain paused until explicitly resumed.
  Future<void> enqueueChapterBatch(
    String bookId,
    List<Chapter> chapters,
    List<DownloadJob> jobs,
  ) async {
    _notificationBatch++;
    try {
      await db.transaction(() async {
        await saveChapters(bookId, chapters);
        for (final job in jobs) {
          await enqueueDownload(job);
        }
      });
    } catch (_) {
      await _loadFromDrift();
      rethrow;
    } finally {
      _notificationBatch--;
      _notify();
    }
  }

  Future<void> importSnapshot(Map<String, dynamic> data) async {
    List<Map<String, dynamic>> rows(String key) => (data[key] as List? ?? [])
        .map((value) => Map<String, dynamic>.from(value as Map))
        .toList();
    final books = rows('books').map(Book.fromMap).toList();
    final entries = rows('library').map(LibraryEntry.fromMap).toList();
    final chapters = rows('chapters').map(Chapter.fromMap).toList();
    final progress = rows('progress').map(ReadingProgress.fromMap).toList();
    final bookmarks = rows('bookmarks').map(Bookmark.fromMap).toList();
    final jobs = rows('downloads')
        .map(DownloadJob.fromMap)
        .map(
          (job) =>
              job.isActive ? job.copyWith(status: DownloadStatus.paused) : job,
        )
        .toList();
    final ids = {..._books.keys, ...books.map((book) => book.id)};
    final references = [
      ...entries.map((value) => value.bookId),
      ...chapters.map((value) => value.bookId),
      ...progress.map((value) => value.bookId),
      ...bookmarks.map((value) => value.bookId),
      ...jobs.map((value) => value.bookId),
    ];
    if (books.any((book) => book.id.isEmpty) ||
        references.any((id) => !ids.contains(id))) {
      throw const FormatException(
        'Backup contains missing or invalid book references.',
      );
    }
    for (final list in [
      books.map((value) => value.id),
      chapters.map((value) => value.id),
      jobs.map((value) => value.id),
    ]) {
      if (list.toSet().length != list.length) {
        throw const FormatException('Backup contains duplicate record IDs.');
      }
    }
    final Map<String, String> existingChapterBooks = {};
    final database = _db;
    if (database != null) {
      final rows = await database.select(database.chaptersTable).get();
      for (final r in rows) {
        existingChapterBooks[r.id] = r.bookId;
      }
    } else {
      for (final chapter in _chapters.values.expand((items) => items)) {
        existingChapterBooks[chapter.id] = chapter.bookId;
      }
    }
    final chapterBooks = {
      ...existingChapterBooks,
      for (final chapter in chapters) chapter.id: chapter.bookId,
    };
    if (jobs.any((job) => chapterBooks[job.chapterId] != job.bookId)) {
      throw const FormatException(
        'Backup download refers to a missing or different book chapter.',
      );
    }
    if (chapters.any(
      (chapter) =>
          existingChapterBooks.containsKey(chapter.id) &&
          existingChapterBooks[chapter.id] != chapter.bookId,
    )) {
      throw const FormatException(
        'Backup chapter ID conflicts with an unrelated book.',
      );
    }
    if (books.any((book) => book.totalChapters < 0) ||
        chapters.any(
          (chapter) =>
              !chapter.chapterIndex.isFinite || chapter.chapterIndex < 0,
        ) ||
        progress.any(
          (item) =>
              !item.chapterIndex.isFinite ||
              item.chapterIndex < 0 ||
              !item.completionPercentage.isFinite ||
              item.completionPercentage < 0 ||
              item.completionPercentage > 1,
        )) {
      throw const FormatException('Backup contains invalid reading positions.');
    }
    _notificationBatch++;
    try {
      await db.transaction(() async {
        for (final book in books) {
          await saveBook(book);
        }
        final collectionsMap = data['collections'] as Map?;
        final collectionRemap = <String, String>{};
        if (collectionsMap != null) {
          final allExisting = Map<String, String>.from(_collections);
          for (final entry in collectionsMap.entries) {
            final colId = entry.key.toString();
            final colName = entry.value.toString();
            final clean = colName.trim();
            final existingEntry = allExisting.entries.where(
              (e) => e.value.toLowerCase() == clean.toLowerCase(),
            ).firstOrNull;
            if (existingEntry != null && existingEntry.key != colId) {
              collectionRemap[colId] = existingEntry.key;
            } else {
              _collections[colId] = clean;
              if (database != null) {
                await database.into(database.collectionsTable).insert(
                  CollectionsTableCompanion.insert(
                    id: colId,
                    name: clean,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  ),
                  mode: drift.InsertMode.insertOrReplace,
                );
              }
            }
          }
        }
        for (final entry in entries) {
          final effective = collectionRemap.isEmpty
              ? entry
              : entry.copyWith(
                  collectionIds: entry.collectionIds
                      .map((id) => collectionRemap[id] ?? id)
                      .toSet()
                      .toList(),
                );
          await _writeLibraryEntry(effective);
          _libraryEntries[effective.bookId] = effective;
        }
        final groups = <String, List<Chapter>>{};
        for (final chapter in chapters) {
          groups.putIfAbsent(chapter.bookId, () => []).add(chapter);
        }
        for (final group in groups.entries) {
          await saveChapters(group.key, group.value);
        }
        for (final item in progress) {
          await saveProgress(item);
        }
        for (final item in bookmarks) {
          await addBookmark(item);
        }
        for (final item in jobs) {
          await updateDownloadJob(item);
        }
        for (final item in rows('highlights')) {
          try {
            await saveHighlight(Highlight.fromMap(item));
          } catch (_) {}
        }
        final settingsMap = data['bookReaderSettings'] as Map?;
        if (settingsMap != null) {
          for (final entry in settingsMap.entries) {
            try {
              await saveBookReaderSettings(
                entry.key.toString(),
                Map<String, dynamic>.from(entry.value as Map),
              );
            } catch (_) {}
          }
        }
      });
    } catch (_) {
      await _loadFromDrift();
      rethrow;
    } finally {
      _notificationBatch--;
      _notify();
    }
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
      } catch (e) {
        throw FormatException('Could not migrate legacy books: $e');
      }
    }

    final legacyLibEntries = <LibraryEntry>[];
    if (legacyLibJson != null) {
      try {
        final list = jsonDecode(legacyLibJson) as List<dynamic>;
        for (final item in list) {
          legacyLibEntries.add(
            LibraryEntry.fromMap(item as Map<String, dynamic>),
          );
        }
      } catch (e) {
        throw FormatException('Could not migrate legacy library: $e');
      }
    }

    final legacyProgress = <ReadingProgress>[];
    if (legacyProgJson != null) {
      try {
        final list = jsonDecode(legacyProgJson) as List<dynamic>;
        for (final item in list) {
          legacyProgress.add(
            ReadingProgress.fromMap(item as Map<String, dynamic>),
          );
        }
      } catch (e) {
        throw FormatException('Could not migrate legacy progress: $e');
      }
    }

    final legacyJobs = <DownloadJob>[];
    if (legacyJobsJson != null) {
      try {
        final list = jsonDecode(legacyJobsJson) as List<dynamic>;
        for (final item in list) {
          legacyJobs.add(DownloadJob.fromMap(item as Map<String, dynamic>));
        }
      } catch (e) {
        throw FormatException('Could not migrate legacy downloads: $e');
      }
    }

    final legacyChapters = <Chapter>[];
    if (legacyChaptersJson != null) {
      try {
        final map = jsonDecode(legacyChaptersJson) as Map<String, dynamic>;
        for (final entry in map.entries) {
          final chList = (entry.value as List<dynamic>).map(
            (c) => Chapter.fromMap(c as Map<String, dynamic>),
          );
          legacyChapters.addAll(chList);
        }
      } catch (e) {
        throw FormatException('Could not migrate legacy chapters: $e');
      }
    }

    final legacyBookmarks = <Bookmark>[];
    if (legacyBookmarksJson != null) {
      try {
        final map = jsonDecode(legacyBookmarksJson) as Map<String, dynamic>;
        for (final entry in map.entries) {
          final bmList = (entry.value as List<dynamic>).map(
            (b) => Bookmark.fromMap(b as Map<String, dynamic>),
          );
          legacyBookmarks.addAll(bmList);
        }
      } catch (e) {
        throw FormatException('Could not migrate legacy bookmarks: $e');
      }
    }

    // Atomic transaction for migration
    await database.transaction(() async {
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
              locatorString: drift.Value(bm.locatorString),
              locatorVersion: drift.Value(bm.locatorVersion),
              createdAt: bm.createdAt,
            ),
            mode: drift.InsertMode.insertOrReplace,
          );
        }

        final legacyCollectionsJson = prefs.getString('hon_collections_v1');
        if (legacyCollectionsJson != null) {
          try {
            final map = Map<String, dynamic>.from(jsonDecode(legacyCollectionsJson) as Map);
            for (final entry in map.entries) {
              final now = DateTime.now();
              batch.insert(
                database.collectionsTable,
                CollectionsTableCompanion.insert(
                  id: entry.key,
                  name: entry.value.toString(),
                  createdAt: now,
                  updatedAt: now,
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
            }
          } catch (_) {}
        }

        for (final l in legacyLibEntries) {
          for (final colId in l.collectionIds) {
            batch.insert(
              database.libraryCollectionMembershipsTable,
              LibraryCollectionMembershipsTableCompanion.insert(
                collectionId: colId,
                bookId: l.bookId,
              ),
              mode: drift.InsertMode.insertOrReplace,
            );
          }
        }
      });
    });

    for (final ch in legacyChapters) {
      _chapters.putIfAbsent(ch.bookId, () => []).add(ch);
    }

    if (!await prefs.setBool('hon_drift_migrated_v1', true)) {
      throw StateError(
        'Legacy migration completed but its completion flag was not saved',
      );
    }
  }

  /// Migrates collections from SharedPreferences into Drift collections_table and
  /// rebuilds library_collection_memberships_table from library_entries_table.collection_ids
  Future<void> _migrateCollectionsV2ToV3IfNeeded() async {
    final prefs = _prefs;
    final database = _db;
    if (prefs == null || database == null) return;

    final isMigrated = prefs.getBool('hon_collections_migrated_v3') ?? false;
    if (isMigrated) return;

    final now = DateTime.now();

    await database.transaction(() async {
      // 1. Copy hon_collections_v1 into collections_table
      final raw = prefs.getString('hon_collections_v1');
      if (raw != null && raw.isNotEmpty) {
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            for (final entry in decoded.entries) {
              final id = entry.key.toString();
              final name = entry.value.toString();
              await database.into(database.collectionsTable).insert(
                CollectionsTableCompanion.insert(
                  id: id,
                  name: name,
                  createdAt: now,
                  updatedAt: now,
                ),
                mode: drift.InsertMode.insertOrReplace,
              );
            }
          }
        } catch (_) {}
      }

      // 2. Rebuild library_collection_memberships_table from library_entries_table.collection_ids
      final entries = await database.select(database.libraryEntriesTable).get();
      for (final entry in entries) {
        final colIdsRaw = entry.collectionIds;
        if (colIdsRaw.isNotEmpty) {
          final colIds = colIdsRaw
              .split(',')
              .map((s) => s.trim())
              .where((s) => s.isNotEmpty);
          for (final colId in colIds) {
            await database.into(database.libraryCollectionMembershipsTable).insert(
              LibraryCollectionMembershipsTableCompanion.insert(
                collectionId: colId,
                bookId: entry.bookId,
              ),
              mode: drift.InsertMode.insertOrReplace,
            );
          }
        }
      }
    });

    await prefs.setBool('hon_collections_migrated_v3', true);
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
        collectionIds: row.collectionIds.isEmpty
            ? []
            : row.collectionIds.split(','),
        customSortOrder: row.customSortOrder,
      );
    }

    // Collections & Memberships (B2): Load collections and assign to library entries
    _collections.clear();
    final colRows = await database.select(database.collectionsTable).get();
    for (final row in colRows) {
      _collections[row.id] = row.name;
    }
    final membershipRows = await database.select(database.libraryCollectionMembershipsTable).get();
    final memberships = <String, List<String>>{};
    for (final row in membershipRows) {
      memberships.putIfAbsent(row.bookId, () => []).add(row.collectionId);
    }
    for (final bookId in _libraryEntries.keys) {
      final fromDb = memberships[bookId];
      if (fromDb != null && fromDb.isNotEmpty) {
        final existing = _libraryEntries[bookId]!;
        _libraryEntries[bookId] = existing.copyWith(collectionIds: fromDb);
      }
    }

    // Lazy chapter loading (B3): Do not eagerly load all chapter rows into memory.
    // Instead, load lightweight SQL aggregates for counts and unread numbers.
    final aggregateRows = await database.customSelect(
      'SELECT book_id, COUNT(*) as total_count, '
      "SUM(CASE WHEN download_state = 'downloaded' AND local_file_path IS NOT NULL THEN 1 ELSE 0 END) as downloaded_count "
      'FROM chapters_table GROUP BY book_id',
    ).get();
    _downloadedCounts.clear();
    _totalCounts.clear();
    for (final row in aggregateRows) {
      final bookId = row.read<String>('book_id');
      _totalCounts[bookId] = row.read<int>('total_count');
      _downloadedCounts[bookId] = row.read<int>('downloaded_count');
    }

    final progresses = await database
        .select(database.readingProgressTable)
        .get();
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
    _downloadJobs.clear();
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
        locatorString: row.locatorString,
        locatorVersion: row.locatorVersion,
        createdAt: row.createdAt,
      );
      _bookmarks.putIfAbsent(row.bookId, () => []).add(bm);
    }

    _highlights.clear();
    final highlightRows = await database.select(database.highlightsTable).get();
    for (final row in highlightRows) {
      final h = Highlight(
        id: row.id,
        bookId: row.bookId,
        locatorString: row.locatorString,
        selectedText: row.selectedText,
        color: row.color,
        note: row.note,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
      );
      _highlights.putIfAbsent(row.bookId, () => []).add(h);
    }

    _bookReaderSettings.clear();
    final settingsRows =
        await database.select(database.bookReaderSettingsTable).get();
    for (final row in settingsRows) {
      try {
        _bookReaderSettings[row.bookId] =
            Map<String, dynamic>.from(jsonDecode(row.settingsJson) as Map);
      } catch (_) {}
    }
  }

  /// Synchronizes cached downloads and chapters from the Drift SQLite database
  /// (e.g. after out-of-process Android WorkManager completion or recovery)
  Future<void> refreshDownloadsAndChapters(String bookId) async {
    final database = _db;
    if (database == null) return;

    final chapterRows = await (database.select(
      database.chaptersTable,
    )..where((t) => t.bookId.equals(bookId))).get();
    final updatedChapters = chapterRows.map((row) {
      return Chapter(
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
    }).toList();
    _chapters[bookId] = updatedChapters;
    _totalCounts[bookId] = updatedChapters.length;
    _downloadedCounts[bookId] = updatedChapters
        .where((c) =>
            c.downloadState == ChapterDownloadState.downloaded &&
            c.localFilePath != null)
        .length;

    await refreshAllDownloads();
  }

  /// Native progress events identify one job; do not reload every chapter.
  Future<void> refreshDownloadJob(String jobId) async {
    final database = _db;
    if (database == null) return;
    final row = await (database.select(database.downloadJobsTable)
      ..where((t) => t.id.equals(jobId))).getSingleOrNull();
    if (row == null) { _downloadJobs.remove(jobId); _notifyDownloadProgress(); return; }
    _downloadJobs[row.id] = DownloadJob(
      id: row.id, bookId: row.bookId, chapterId: row.chapterId,
      chapterTitle: row.chapterTitle, sourceId: row.sourceId,
      status: DownloadStatus.values.firstWhere((s) => s.name == row.status, orElse: () => DownloadStatus.failed),
      progress: row.progress, errorMessage: row.errorMessage, retryCount: row.retryCount,
      createdAt: row.createdAt, updatedAt: row.updatedAt,
    );
    final chapter = await (database.select(database.chaptersTable)
      ..where((t) => t.id.equals(row.chapterId))).getSingleOrNull();
    if (chapter != null) {
      final next = Chapter(
        id: chapter.id, bookId: chapter.bookId, sourceChapterId: chapter.sourceChapterId,
        title: chapter.title, chapterIndex: chapter.chapterIndex, url: chapter.url,
        localFilePath: chapter.localFilePath, releaseDate: chapter.releaseDate,
        downloadState: ChapterDownloadState.values.firstWhere(
          (s) => s.name == chapter.downloadState,
          orElse: () => ChapterDownloadState.notDownloaded,
        ),
        updatedAt: chapter.updatedAt,
      );
      final items = _chapters.putIfAbsent(chapter.bookId, () => []);
      final index = items.indexWhere((item) => item.id == chapter.id);
      if (index < 0) {
        items.add(next);
        items.sort((a,b) => a.chapterIndex.compareTo(b.chapterIndex));
      } else {
        items[index] = next;
      }
      _totalCounts[chapter.bookId] = items.length;
      _downloadedCounts[chapter.bookId] = items
          .where((c) =>
              c.downloadState == ChapterDownloadState.downloaded &&
              c.localFilePath != null)
          .length;
    } else if (row.status == 'completed') {
      _downloadedCounts[row.bookId] = (_downloadedCounts[row.bookId] ?? 0) + 1;
    }
    _notifyDownloadProgress();
  }

  /// Refreshes all download jobs from Drift SQLite database into in-memory cache
  Future<void> refreshAllDownloads() async {
    final database = _db;
    if (database == null) return;

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
    _notify();
  }

  /// Reloads all data caches from Drift SQLite and notifies library/change listeners.
  /// Used when Android WorkManager or an external process writes updates to SQLite.
  Future<void> reloadFromDatabase() async {
    final previouslyLoadedBookIds = _chapters.keys.toList();
    await _loadFromDrift();
    for (final bookId in previouslyLoadedBookIds) {
      await loadChapters(bookId);
    }
    _notify(library: true);
  }

  /// Reconciles chapter files written by Android WorkManager while Flutter was
  /// stopped and could not receive its MethodChannel notification.
  Future<void> refreshAllChapters() async {
    await reloadFromDatabase();
  }

  void _cleanLegacySyntheticDemos() {
    // Only remove synthetic books that have no physical file and were mock-seeded
    final demoIds = [
      'book_good_material',
      'book_first_lie_wins',
      'book_war_and_peace',
    ];
    bool modified = false;
    for (final id in demoIds) {
      if (_books.containsKey(id) &&
          (_books[id]?.filePath == null ||
              _books[id]?.filePath?.isEmpty == true)) {
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

  /// Legacy persistence for the explicitly configured no-SQL test fallback.
  /// Production writes commit to Drift in the calling method. Re-serializing
  /// every chapter/job on each progress event duplicates durable data and
  /// stalls the UI isolate for large libraries. Legacy migration snapshots are
  /// retained, while explicit metadata exports are created on user request.
  Future<void> _syncToDriftAndBackup() async {
    if (_db != null) return;
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
        list.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case LibrarySort.titleZa:
        list.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case LibrarySort.recent:
        list.sort((a, b) {
          final dateA =
              _readingProgress[a.id]?.lastReadAt ??
              _libraryEntries[a.id]?.dateAdded ??
              a.updatedAt;
          final dateB =
              _readingProgress[b.id]?.lastReadAt ??
              _libraryEntries[b.id]?.dateAdded ??
              b.updatedAt;
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

  List<Book> getFinishedBooks() => _books.values
      .where((book) => _libraryEntries[book.id]?.isFinished == true)
      .toList();

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

  /// Includes finished books and books read without library membership.
  List<Book> getReadingHistoryBooks() {
    final books = _books.values
        .where((book) => _readingProgress.containsKey(book.id))
        .toList();
    books.sort(
      (a, b) => _readingProgress[b.id]!.lastReadAt.compareTo(
        _readingProgress[a.id]!.lastReadAt,
      ),
    );
    return books;
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
      await database
          .into(database.booksTable)
          .insertOnConflictUpdate(
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

  /// Repairs imported EPUBs whose cover was absent or whose cached image was lost.
  /// Each publication is handled independently, so one malformed file cannot
  /// prevent the rest of the library from loading.
  Future<void> repairMissingEpubCovers() async {
    for (final book in _books.values.toList()) {
      if (book.format != BookFormat.epub || book.filePath == null) continue;
      if (book.coverPath != null && File(book.coverPath!).existsSync()) {
        continue;
      }
      final publication = File(book.filePath!);
      if (!publication.existsSync()) continue;
      try {
        final metadata = await EpubParser.parse(
          publication,
          includeContent: false,
        );
        final bytes = metadata.coverBytes;
        if (bytes == null) continue;
        final coverPath = await StorageService.instance.saveCoverImage(
          book.id,
          bytes,
        );
        if (coverPath != null && _books.containsKey(book.id)) {
          // A previous missing-file ImageProvider may be cached under this path.
          await FileImage(File(coverPath)).evict();
          await saveBook(
            _books[book.id]!.copyWith(
              coverPath: coverPath,
              updatedAt: DateTime.now(),
            ),
          );
        }
      } catch (e) {
        debugPrint('Could not repair EPUB cover for ${book.id}: $e');
      }
    }
  }

  Future<void> removeFromLibrary(String bookId) async {
    await setLibraryMembership(bookId, false);
  }

  Future<BookDeletionResult> deleteBook(String bookId) async {
    final book = _books[bookId];
    if (book == null) {
      return const BookDeletionResult(success: true, recordsPurged: true);
    }

    final storage = StorageService.instance;
    final jobs = _downloadJobs.values
        .where((job) => job.bookId == bookId)
        .toList();
    final database = _db;
    // The worker's completion transaction requires status=running. Marking jobs
    // cancelled first prevents a late worker from committing after deletion.
    if (database != null && jobs.isNotEmpty) {
      await database.transaction(() async {
        for (final job in jobs) {
          await (database.update(
            database.downloadJobsTable,
          )..where((t) => t.id.equals(job.id))).write(
            const DownloadJobsTableCompanion(status: drift.Value('cancelled')),
          );
        }
      });
      for (final job in jobs) {
        _downloadJobs[job.id] = job.copyWith(status: DownloadStatus.cancelled);
      }
    }
    if (Platform.isAndroid) {
      const channel = MethodChannel('com.hon.reader/download_worker');
      for (final job in jobs) {
        try {
          await channel.invokeMethod('cancelDownload', {'jobId': job.id});
        } catch (e) {
          return BookDeletionResult(
            success: false,
            recordsPurged: false,
            errorMessage: 'Could not stop active download ${job.id}: $e',
          );
        }
      }
    }
    final List<String> candidatePaths = [];

    if (book.filePath != null && !book.filePath!.startsWith('assets/')) {
      candidatePaths.add(book.filePath!);
    }
    if (book.coverPath != null &&
        !book.coverPath!.startsWith('http') &&
        !book.coverPath!.startsWith('assets/')) {
      candidatePaths.add(book.coverPath!);
    }

    // Include all downloaded chapter files and referenced illustrations
    await ensureChaptersLoaded(bookId);
    final chapters = _chapters[bookId] ?? [];
    for (final ch in chapters) {
      if (ch.localFilePath != null &&
          !ch.localFilePath!.startsWith('assets/')) {
        candidatePaths.add(ch.localFilePath!);
        try {
          final file = File(ch.localFilePath!);
          if (file.existsSync()) {
            final html = file.readAsStringSync();
            final matches = RegExp(r'''(?:src|href)=["'](?:file://)?([^"']+)["']''').allMatches(html);
            for (final m in matches) {
              final path = m.group(1);
              if (path != null && storage.isPathInsideManagedStorage(path)) {
                candidatePaths.add(path);
              }
            }
          }
        } catch (_) {}
      }
    }

    final List<String> deletedFiles = [];
    final List<String> failedFiles = [];
    final List<String> skippedExternalFiles = [];

    final stagedFiles = <String, String>{};
    void restoreStagedFiles() {
      for (final entry in stagedFiles.entries) {
        final staged = File(entry.value);
        if (!staged.existsSync()) continue;
        try {
          if (File(entry.key).existsSync()) {
            failedFiles.add(entry.value);
          } else {
            staged.renameSync(entry.key);
          }
        } catch (_) {
          failedFiles.add(entry.value);
        }
      }
    }

    for (final rawPath in candidatePaths.toSet()) {
      if (!File(rawPath).existsSync()) continue;
      if (!storage.isPathInsideManagedStorage(rawPath)) {
        skippedExternalFiles.add(rawPath);
        continue;
      }

      try {
        final staged =
            '$rawPath.hon_deleting_${DateTime.now().microsecondsSinceEpoch}';
        File(rawPath).renameSync(staged);
        stagedFiles[rawPath] = staged;
      } catch (e) {
        failedFiles.add(rawPath);
      }
    }

    if (failedFiles.isNotEmpty) {
      restoreStagedFiles();
      return BookDeletionResult(
        success: false,
        recordsPurged: false,
        deletedFiles: deletedFiles,
        failedFiles: failedFiles,
        skippedExternalFiles: skippedExternalFiles,
        errorMessage:
            'Failed to delete ${failedFiles.length} file(s) from storage.',
      );
    }

    try {
      if (database != null) {
        await database.transaction(() async {
          await (database.delete(
            database.booksTable,
          )..where((t) => t.id.equals(bookId))).go();
          await (database.delete(
            database.libraryEntriesTable,
          )..where((t) => t.bookId.equals(bookId))).go();
          await (database.delete(
            database.readingProgressTable,
          )..where((t) => t.bookId.equals(bookId))).go();
          await (database.delete(
            database.chaptersTable,
          )..where((t) => t.bookId.equals(bookId))).go();
          await (database.delete(
            database.bookmarksTable,
          )..where((t) => t.bookId.equals(bookId))).go();
          await (database.delete(
            database.downloadJobsTable,
          )..where((t) => t.bookId.equals(bookId))).go();
          await (database.delete(
            database.highlightsTable,
          )..where((t) => t.bookId.equals(bookId))).go();
          await (database.delete(
            database.bookReaderSettingsTable,
          )..where((t) => t.bookId.equals(bookId))).go();
        });
      }
    } catch (e) {
      restoreStagedFiles();
      return BookDeletionResult(
        success: false,
        recordsPurged: false,
        failedFiles: failedFiles,
        errorMessage: 'Could not remove book records: $e',
      );
    }

    _books.remove(bookId);
    _libraryEntries.remove(bookId);
    _readingProgress.remove(bookId);
    _chapters.remove(bookId);
    _downloadedCounts.remove(bookId);
    _totalCounts.remove(bookId);
    _bookmarks.remove(bookId);
    _highlights.remove(bookId);
    _bookReaderSettings.remove(bookId);
    _downloadJobs.removeWhere((k, v) => v.bookId == bookId);

    for (final entry in stagedFiles.entries) {
      try {
        File(entry.value).deleteSync();
        deletedFiles.add(entry.key);
      } catch (_) {
        failedFiles.add(entry.value);
      }
    }

    await _syncToDriftAndBackup();
    _notify();

    return BookDeletionResult(
      success: failedFiles.isEmpty,
      recordsPurged: true,
      deletedFiles: deletedFiles,
      failedFiles: failedFiles,
      skippedExternalFiles: skippedExternalFiles,
      errorMessage: failedFiles.isEmpty
          ? null
          : 'Book records removed, but ${failedFiles.length} staged file(s) need cleanup.',
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
      await database
          .into(database.libraryEntriesTable)
          .insertOnConflictUpdate(
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

  bool isBookFinished(String bookId) =>
      _libraryEntries[bookId]?.isFinished ?? false;

  DateTime libraryAddedAt(Book book) =>
      _libraryEntries[book.id]?.dateAdded ?? book.createdAt;

  bool isBookInLibrary(String bookId) {
    return _libraryEntries[bookId]?.isInLibrary ?? false;
  }

  Future<void> markBookFinished(String bookId, bool isFinished) async {
    final current = _libraryEntries[bookId];
    final updated = current != null
        ? current.copyWith(isFinished: isFinished)
        : LibraryEntry(
            bookId: bookId,
            isInLibrary: false,
            dateAdded: DateTime.now(),
            isFinished: isFinished,
          );
    _libraryEntries[bookId] = updated;

    final database = _db;
    if (database != null) {
      await database
          .into(database.libraryEntriesTable)
          .insertOnConflictUpdate(
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
      await database
          .into(database.readingProgressTable)
          .insertOnConflictUpdate(
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
      await database
          .into(database.downloadJobsTable)
          .insertOnConflictUpdate(
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
      await database
          .into(database.downloadJobsTable)
          .insertOnConflictUpdate(
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

  DownloadJob? getDownloadJob(String jobId) => _downloadJobs[jobId];

  Future<void> removeDownloadJob(String jobId) async {
    _downloadJobs.remove(jobId);
    final database = _db;
    if (database != null) {
      await (database.delete(
        database.downloadJobsTable,
      )..where((t) => t.id.equals(jobId))).go();
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
    await ensureChaptersLoaded(bookId);
    final existingChapters = {
      for (final chapter in getChapters(bookId)) chapter.id: chapter,
    };
    final resolvedChapters = chapters.map((ch) {
      final existing = existingChapters[ch.id];
      if (existing != null) {
        if (ch.localFilePath == null && existing.localFilePath != null) {
          return ch.copyWith(
            localFilePath: existing.localFilePath,
            downloadState: ch.downloadState == ChapterDownloadState.notDownloaded
                ? existing.downloadState
                : ch.downloadState,
          );
        }
      }
      return ch;
    }).toList();
    _chapters[bookId] = resolvedChapters;
    _totalCounts[bookId] = resolvedChapters.length;
    _downloadedCounts[bookId] = resolvedChapters
        .where((c) =>
            c.downloadState == ChapterDownloadState.downloaded &&
            c.localFilePath != null)
        .length;
    await _persistChapterRows(resolvedChapters);
  }

  /// Lazily loads chapters for a specific book from Drift SQLite database into memory.
  Future<List<Chapter>> loadChapters(String bookId) async {
    final database = _db;
    if (database == null) return _chapters[bookId] ?? [];
    final rows = await (database.select(database.chaptersTable)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => drift.OrderingTerm(expression: t.chapterIndex)]))
        .get();
    final chapters = rows
        .map((row) => Chapter(
              id: row.id,
              bookId: row.bookId,
              sourceChapterId: row.sourceChapterId,
              title: row.title,
              chapterIndex: row.chapterIndex,
              url: row.url,
              localFilePath: row.localFilePath,
              downloadState: ChapterDownloadState.values.firstWhere(
                (state) => state.name == row.downloadState,
                orElse: () => ChapterDownloadState.notDownloaded,
              ),
              releaseDate: row.releaseDate,
              updatedAt: row.updatedAt,
            ))
        .toList();
    _chapters[bookId] = chapters;
    _totalCounts[bookId] = chapters.length;
    _downloadedCounts[bookId] = chapters
        .where((c) =>
            c.downloadState == ChapterDownloadState.downloaded &&
            c.localFilePath != null)
        .length;
    return chapters;
  }

  /// Ensures chapters are loaded into memory for the requested book.
  Future<void> ensureChaptersLoaded(String bookId) async {
    if (!_chapters.containsKey(bookId)) {
      await loadChapters(bookId);
    }
  }

  int getDownloadedChapterCount(String bookId) {
    return _downloadedCounts[bookId] ??
        _chapters[bookId]
            ?.where((c) =>
                c.downloadState == ChapterDownloadState.downloaded &&
                c.localFilePath != null)
            .length ??
        0;
  }

  bool hasDownloadedChapters(String bookId) {
    return getDownloadedChapterCount(bookId) > 0;
  }

  int getTotalChapterCount(String bookId) {
    return _totalCounts[bookId] ?? _chapters[bookId]?.length ?? 0;
  }

  int getTotalDownloadedChapters() {
    return _downloadedCounts.values.fold<int>(0, (sum, count) => sum + count);
  }

  int getUnreadChapterCount(String bookId) {
    final total = getTotalChapterCount(bookId);
    final prog = _readingProgress[bookId];
    if (prog == null) return total;
    if (_libraryEntries[bookId]?.isFinished == true) return 0;
    final readIndex = prog.chapterIndex.floor();
    final unread = total - readIndex - 1;
    return unread.clamp(0, total);
  }

  Future<void> _persistChapterRows(List<Chapter> chapters) async {
    final database = _db;
    if (database != null) {
      for (final bId in chapters.map((c) => c.bookId).toSet()) {
        await ensureChaptersLoaded(bId);
      }
      final resolvedChapters = chapters.map((ch) {
        final existing = _chapters[ch.bookId]?.where((c) => c.id == ch.id).firstOrNull;
        if (existing != null) {
          if (ch.localFilePath == null && existing.localFilePath != null) {
            return ch.copyWith(
              localFilePath: existing.localFilePath,
              downloadState: ch.downloadState == ChapterDownloadState.notDownloaded
                  ? existing.downloadState
                  : ch.downloadState,
            );
          }
        }
        return ch;
      }).toList();

      await database.batch((batch) {
        for (final ch in resolvedChapters) {
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

  Future<void> saveChapters(String bookId, List<Chapter> chapters) async {
    await ensureChaptersLoaded(bookId);
    final merged = {
      for (final chapter in getChapters(bookId)) chapter.id: chapter,
    };
    final resolvedToPersist = <Chapter>[];
    for (final chapter in chapters) {
      final existing = merged[chapter.id];
      Chapter resolved = chapter;
      if (existing != null) {
        if (resolved.localFilePath == null && existing.localFilePath != null) {
          resolved = resolved.copyWith(
            localFilePath: existing.localFilePath,
            downloadState: resolved.downloadState == ChapterDownloadState.notDownloaded
                ? existing.downloadState
                : resolved.downloadState,
          );
        }
      }
      merged[resolved.id] = resolved;
      resolvedToPersist.add(resolved);
    }
    final sorted = merged.values.toList()
      ..sort((a, b) => a.chapterIndex.compareTo(b.chapterIndex));
    _chapters[bookId] = sorted;
    _totalCounts[bookId] = sorted.length;
    _downloadedCounts[bookId] = sorted
        .where((c) =>
            c.downloadState == ChapterDownloadState.downloaded &&
            c.localFilePath != null)
        .length;
    // Updating one download must not replace the novel's cached chapter list,
    // or rewrite every unchanged chapter in SQLite.
    await _persistChapterRows(resolvedToPersist);
  }

  /// Optional hook to coordinate download worker cancellation before file deletion.
  static Future<void> Function(String jobId)? onCancelJobForDeletion;

  /// Validates whether a file path is safely within Hon managed storage.
  bool isPathInsideHonManagedStorage(String filePath, {Directory? specificRoot}) {
    try {
      return StorageService.instance.isPathInsideManagedStorage(
        filePath,
        specificRoot: specificRoot,
      );
    } catch (_) {
      return false;
    }
  }

  /// Safely deletes offline files for the specified chapters and resets their state to notDownloaded.
  /// Coordinates active worker cancellation, validates managed paths, uses asynchronous IO,
  /// preserves records on failure so they remain retryable, and returns a detailed ChapterDeletionResult.
  Future<ChapterDeletionResult> deleteDownloadedChapters(
    String bookId,
    Iterable<Chapter> chaptersToDelete,
  ) async {
    await ensureChaptersLoaded(bookId);
    final currentChapters = getChapters(bookId);
    final targetIds = chaptersToDelete.map((c) => c.id).toSet();
    final updatedList = <Chapter>[];
    final failedChapterIds = <String>[];
    final errors = <String>[];
    int deletedCount = 0;
    int failedCount = 0;
    int skippedCount = 0;

    // 1. Coordinate cancellation of any active or queued download jobs for target chapters
    final jobsToCancel = getAllDownloadJobs()
        .where((j) => targetIds.contains(j.chapterId) && j.isActive)
        .toList();
    final failedCancellationChapterIds = <String>{};
    for (final job in jobsToCancel) {
      try {
        if (onCancelJobForDeletion != null) {
          await onCancelJobForDeletion!(job.id);
        }
      } catch (e) {
        debugPrint('Failed to cancel job ${job.id} for chapter ${job.chapterId}: $e');
        failedCancellationChapterIds.add(job.chapterId);
      }
    }

    // 2. Process each target chapter
    for (final chapter in currentChapters) {
      if (!targetIds.contains(chapter.id)) continue;

      if (failedCancellationChapterIds.contains(chapter.id)) {
        failedCount++;
        failedChapterIds.add(chapter.id);
        errors.add('Failed to cancel active download job for "${chapter.title}" before deletion');
        continue;
      }

      final isDownloaded = chapter.downloadState == ChapterDownloadState.downloaded;
      final filePath = chapter.localFilePath;

      if (!isDownloaded && filePath == null) {
        skippedCount++;
        continue;
      }

      if (filePath != null) {
        if (!isPathInsideHonManagedStorage(filePath, specificRoot: StorageService.instance.chaptersDir)) {
          failedCount++;
          failedChapterIds.add(chapter.id);
          errors.add('Refused to delete file outside managed storage: $filePath');
          continue;
        }

        try {
          final file = File(filePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          failedCount++;
          failedChapterIds.add(chapter.id);
          errors.add('Failed to delete chapter file for "${chapter.title}": $e');
          // KEEP the record intact with localFilePath and downloadState so it remains retryable!
          continue;
        }
      }

      updatedList.add(
        chapter.copyWith(
          localFilePath: null,
          downloadState: ChapterDownloadState.notDownloaded,
          updatedAt: DateTime.now(),
        ),
      );
      deletedCount++;
    }

    // 3. Persist updated chapters in DB and remove obsolete job records
    if (updatedList.isNotEmpty) {
      final updatedMap = {for (final c in updatedList) c.id: c};
      final newList = currentChapters.map((c) => updatedMap[c.id] ?? c).toList();
      _chapters[bookId] = newList;
      _totalCounts[bookId] = newList.length;
      _downloadedCounts[bookId] = newList
          .where((c) =>
              c.downloadState == ChapterDownloadState.downloaded &&
              c.localFilePath != null)
          .length;
      await _persistChapterRows(updatedList);
      for (final ch in updatedList) {
        final job = getAllDownloadJobs().where((j) => j.chapterId == ch.id).firstOrNull;
        if (job != null) {
          await removeDownloadJob(job.id);
        }
      }
      _notify();
    }

    return ChapterDeletionResult(
      requestedCount: chaptersToDelete.length,
      deletedCount: deletedCount,
      failedCount: failedCount,
      skippedCount: skippedCount,
      failedChapterIds: failedChapterIds,
      errors: errors,
    );
  }

  /// Deletes downloaded chapters prior to the current reading chapter index.
  Future<int> deleteReadChapters(String bookId, double currentChapterIndex) async {
    await ensureChaptersLoaded(bookId);
    final toDelete = getChapters(bookId)
        .where((c) => c.chapterIndex < currentChapterIndex && c.downloadState == ChapterDownloadState.downloaded);
    final res = await deleteDownloadedChapters(bookId, toDelete);
    return res.deletedCount;
  }

  /// Deletes all downloaded chapters for the given book.
  Future<int> deleteAllDownloadedChapters(String bookId) async {
    await ensureChaptersLoaded(bookId);
    final toDelete = getChapters(bookId)
        .where((c) => c.downloadState == ChapterDownloadState.downloaded || c.localFilePath != null);
    final res = await deleteDownloadedChapters(bookId, toDelete);
    return res.deletedCount;
  }

  // --- Bookmarks ---
  List<Bookmark> getBookmarks(String bookId) {
    final list = _bookmarks[bookId] ?? [];
    list.sort((a, b) => a.pageIndex.compareTo(b.pageIndex));
    return List.unmodifiable(list);
  }

  bool isBookmarked(String bookId, int pageIndex, {String? locatorString}) {
    final list = _bookmarks[bookId];
    if (list == null || list.isEmpty) return false;
    if (locatorString != null && locatorString.isNotEmpty) {
      return list.any((b) => b.locatorString == locatorString);
    }
    return list.any((b) => b.pageIndex == pageIndex);
  }

  Future<void> addBookmark(Bookmark bookmark) async {
    final list = _bookmarks.putIfAbsent(bookmark.bookId, () => []);
    list.removeWhere((b) =>
        b.id == bookmark.id ||
        (bookmark.locatorString != null &&
            bookmark.locatorString!.isNotEmpty &&
            b.locatorString == bookmark.locatorString));
    list.add(bookmark);

    final database = _db;
    if (database != null) {
      await database
          .into(database.bookmarksTable)
          .insertOnConflictUpdate(
            BookmarksTableCompanion.insert(
              id: bookmark.id,
              bookId: bookmark.bookId,
              pageIndex: drift.Value(bookmark.pageIndex),
              chapterIndex: drift.Value(bookmark.chapterIndex),
              label: drift.Value(bookmark.label),
              snippet: drift.Value(bookmark.snippet),
              locatorString: drift.Value(bookmark.locatorString),
              locatorVersion: drift.Value(bookmark.locatorVersion),
              createdAt: bookmark.createdAt,
            ),
          );
    }
    await _syncToDriftAndBackup();
    _notify();
  }

  Future<void> removeBookmarkById(String id) async {
    for (final list in _bookmarks.values) {
      list.removeWhere((b) => b.id == id);
    }
    final database = _db;
    if (database != null) {
      await (database.delete(database.bookmarksTable)
            ..where((t) => t.id.equals(id)))
          .go();
    }
    await _syncToDriftAndBackup();
    _notify();
  }

  Future<void> removeBookmark(String bookId, int pageIndex, {String? locatorString}) async {
    final list = _bookmarks[bookId];
    if (list != null) {
      if (locatorString != null && locatorString.isNotEmpty) {
        list.removeWhere((b) => b.locatorString == locatorString);
        final database = _db;
        if (database != null) {
          await (database.delete(database.bookmarksTable)
                ..where((t) => t.bookId.equals(bookId) & t.locatorString.equals(locatorString)))
              .go();
        }
      } else {
        list.removeWhere((b) => b.pageIndex == pageIndex);
        final database = _db;
        if (database != null) {
          await (database.delete(database.bookmarksTable)
                ..where((t) => t.bookId.equals(bookId) & t.pageIndex.equals(pageIndex)))
              .go();
        }
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
    String? locatorString,
    String? locatorVersion,
    String? customId,
  }) async {
    final list = _bookmarks[bookId] ?? [];
    Bookmark? existing;
    if (locatorString != null && locatorString.isNotEmpty) {
      for (final b in list) {
        if (b.locatorString == locatorString) {
          existing = b;
          break;
        }
      }
    } else {
      for (final b in list) {
        if (b.pageIndex == pageIndex) {
          existing = b;
          break;
        }
      }
    }

    if (existing != null) {
      await removeBookmarkById(existing.id);
      return false;
    } else {
      final locatorHash = (locatorString != null && locatorString.isNotEmpty)
          ? locatorString.hashCode.toRadixString(16)
          : '$pageIndex';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final bm = Bookmark(
        id: customId ?? 'bm_${bookId}_${locatorHash}_$timestamp',
        bookId: bookId,
        pageIndex: pageIndex,
        chapterIndex: pageIndex,
        label: label ?? 'Page $pageIndex',
        createdAt: DateTime.now(),
        snippet: snippet,
        locatorString: locatorString,
        locatorVersion: locatorVersion,
      );
      await addBookmark(bm);
      return true;
    }
  }

  // --- Highlights & Annotations ---
  List<Highlight> getHighlights(String bookId) {
    final list = _highlights[bookId] ?? [];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  Future<void> saveHighlight(Highlight highlight) async {
    final list = _highlights.putIfAbsent(highlight.bookId, () => []);
    list.removeWhere((h) => h.id == highlight.id);
    list.add(highlight);

    final database = _db;
    if (database != null) {
      await database
          .into(database.highlightsTable)
          .insertOnConflictUpdate(
            HighlightsTableCompanion.insert(
              id: highlight.id,
              bookId: highlight.bookId,
              locatorString: highlight.locatorString,
              selectedText: highlight.selectedText,
              color: drift.Value(highlight.color),
              note: drift.Value(highlight.note),
              createdAt: highlight.createdAt,
              updatedAt: highlight.updatedAt,
            ),
          );
    }
    _notify();
  }

  Future<void> deleteHighlight(String id) async {
    for (final list in _highlights.values) {
      list.removeWhere((h) => h.id == id);
    }
    final database = _db;
    if (database != null) {
      await (database.delete(database.highlightsTable)
            ..where((t) => t.id.equals(id)))
          .go();
    }
    _notify();
  }

  // --- Per-Book Reader Settings Overrides ---
  Map<String, dynamic>? getBookReaderSettings(String bookId) {
    final settings = _bookReaderSettings[bookId];
    if (settings != null) return Map.unmodifiable(settings);
    return null;
  }

  Future<void> saveBookReaderSettings(
    String bookId,
    Map<String, dynamic> settings,
  ) async {
    _bookReaderSettings[bookId] = Map<String, dynamic>.from(settings);
    final database = _db;
    if (database != null) {
      await database
          .into(database.bookReaderSettingsTable)
          .insertOnConflictUpdate(
            BookReaderSettingsTableCompanion.insert(
              bookId: bookId,
              settingsJson: jsonEncode(settings),
              updatedAt: DateTime.now(),
            ),
          );
    }
    _notify();
  }

  Future<void> resetBookReaderSettings(String bookId) async {
    _bookReaderSettings.remove(bookId);
    final database = _db;
    if (database != null) {
      await (database.delete(database.bookReaderSettingsTable)
            ..where((t) => t.bookId.equals(bookId)))
          .go();
    }
    _notify();
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
    return getReadingMinutesOn(DateTime.now());
  }

  int getReadingMinutesOn(DateTime day) {
    final dateKey = 'hon_reading_secs_${day.year}_${day.month}_${day.day}';
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
