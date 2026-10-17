import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../models/library_entry.dart';
import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../models/download_job.dart';
import '../models/bookmark.dart';

enum LibrarySort {
  titleAz,
  titleZa,
  recent,
  progress,
}

class DatabaseService {
  static DatabaseService? _instance;
  static DatabaseService get instance => _instance ??= DatabaseService._();
  DatabaseService._();

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

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadFromDisk();

    // Clean up any legacy synthetic demo fixtures seeded by earlier versions
    _cleanLegacySyntheticDemos();
  }

  void _notify() {
    changeNotifier.value++;
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
      _saveToDisk();
      _notify();
    }
  }

  Future<void> _loadFromDisk() async {
    final booksJson = _prefs?.getString('hon_books');
    if (booksJson != null) {
      try {
        final list = jsonDecode(booksJson) as List<dynamic>;
        for (final item in list) {
          final b = Book.fromMap(item as Map<String, dynamic>);
          _books[b.id] = b;
        }
      } catch (_) {}
    }

    final libJson = _prefs?.getString('hon_library');
    if (libJson != null) {
      try {
        final list = jsonDecode(libJson) as List<dynamic>;
        for (final item in list) {
          final entry = LibraryEntry.fromMap(item as Map<String, dynamic>);
          _libraryEntries[entry.bookId] = entry;
        }
      } catch (_) {}
    }

    final progJson = _prefs?.getString('hon_progress');
    if (progJson != null) {
      try {
        final list = jsonDecode(progJson) as List<dynamic>;
        for (final item in list) {
          final prog = ReadingProgress.fromMap(item as Map<String, dynamic>);
          _readingProgress[prog.bookId] = prog;
        }
      } catch (_) {}
    }

    final jobsJson = _prefs?.getString('hon_downloads');
    if (jobsJson != null) {
      try {
        final list = jsonDecode(jobsJson) as List<dynamic>;
        for (final item in list) {
          final job = DownloadJob.fromMap(item as Map<String, dynamic>);
          _downloadJobs[job.id] = job;
        }
      } catch (_) {}
    }

    final chaptersJson = _prefs?.getString('hon_chapters');
    if (chaptersJson != null) {
      try {
        final map = jsonDecode(chaptersJson) as Map<String, dynamic>;
        for (final entry in map.entries) {
          final chList = (entry.value as List<dynamic>)
              .map((c) => Chapter.fromMap(c as Map<String, dynamic>))
              .toList();
          _chapters[entry.key] = chList;
        }
      } catch (_) {}
    }

    final bookmarksJson = _prefs?.getString('hon_bookmarks');
    if (bookmarksJson != null) {
      try {
        final map = jsonDecode(bookmarksJson) as Map<String, dynamic>;
        for (final entry in map.entries) {
          final bmList = (entry.value as List<dynamic>)
              .map((b) => Bookmark.fromMap(b as Map<String, dynamic>))
              .toList();
          _bookmarks[entry.key] = bmList;
        }
      } catch (_) {}
    }
  }

  Future<void> _saveToDisk() async {
    await _prefs?.setString(
      'hon_books',
      jsonEncode(_books.values.map((b) => b.toMap()).toList()),
    );
    await _prefs?.setString(
      'hon_library',
      jsonEncode(_libraryEntries.values.map((l) => l.toMap()).toList()),
    );
    await _prefs?.setString(
      'hon_progress',
      jsonEncode(_readingProgress.values.map((p) => p.toMap()).toList()),
    );
    await _prefs?.setString(
      'hon_downloads',
      jsonEncode(_downloadJobs.values.map((j) => j.toMap()).toList()),
    );

    final chaptersMap = <String, List<Map<String, dynamic>>>{};
    for (final entry in _chapters.entries) {
      chaptersMap[entry.key] = entry.value.map((c) => c.toMap()).toList();
    }
    await _prefs?.setString('hon_chapters', jsonEncode(chaptersMap));

    final bookmarksMap = <String, List<Map<String, dynamic>>>{};
    for (final entry in _bookmarks.entries) {
      bookmarksMap[entry.key] = entry.value.map((b) => b.toMap()).toList();
    }
    await _prefs?.setString('hon_bookmarks', jsonEncode(bookmarksMap));
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
      // Only include books that have actual reading progress recorded and are not marked finished
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
    await _saveToDisk();
    _notify();
  }

  Future<void> removeFromLibrary(String bookId) async {
    await setLibraryMembership(bookId, false);
  }

  Future<void> deleteBook(String bookId) async {
    final book = _books[bookId];
    if (book != null && book.filePath != null) {
      try {
        final f = File(book.filePath!);
        if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
      if (book.coverPath != null &&
          !book.coverPath!.startsWith('http') &&
          !book.coverPath!.startsWith('assets/')) {
        try {
          final c = File(book.coverPath!);
          if (c.existsSync()) {
            c.deleteSync();
          }
        } catch (_) {}
      }
    }
    _books.remove(bookId);
    _libraryEntries.remove(bookId);
    _readingProgress.remove(bookId);
    _chapters.remove(bookId);
    _bookmarks.remove(bookId);
    _downloadJobs.removeWhere((k, v) => v.bookId == bookId);
    await _saveToDisk();
    _notify();
  }

  Future<void> setLibraryMembership(String bookId, bool isInLibrary) async {
    final current = _libraryEntries[bookId];
    if (current != null) {
      _libraryEntries[bookId] = current.copyWith(
        isInLibrary: isInLibrary,
        dateAdded: isInLibrary ? DateTime.now() : current.dateAdded,
      );
    } else {
      _libraryEntries[bookId] = LibraryEntry(
        bookId: bookId,
        isInLibrary: isInLibrary,
        dateAdded: DateTime.now(),
      );
    }
    await _saveToDisk();
    _notify();
  }

  bool isBookInLibrary(String bookId) {
    return _libraryEntries[bookId]?.isInLibrary ?? false;
  }

  Future<void> markBookFinished(String bookId, bool isFinished) async {
    final current = _libraryEntries[bookId];
    if (current != null) {
      _libraryEntries[bookId] = current.copyWith(isFinished: isFinished);
    } else {
      _libraryEntries[bookId] = LibraryEntry(
        bookId: bookId,
        isInLibrary: true,
        dateAdded: DateTime.now(),
        isFinished: isFinished,
      );
    }
    await _saveToDisk();
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
        // Preserve explicit finished state; do not overwrite automatically
        isFinished: entry.isFinished,
      );
    }
    await _saveToDisk();
    _notify();
  }

  // --- Downloads ---
  List<DownloadJob> getAllDownloadJobs() => _downloadJobs.values.toList();

  Future<void> enqueueDownload(DownloadJob job) async {
    _downloadJobs[job.id] = job;
    await _saveToDisk();
    _notify();
  }

  Future<void> updateDownloadJob(DownloadJob job) async {
    _downloadJobs[job.id] = job;
    await _saveToDisk();
    _notify();
  }

  Future<void> removeDownloadJob(String jobId) async {
    _downloadJobs.remove(jobId);
    await _saveToDisk();
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

  Future<void> setChaptersForBook(String bookId, List<Chapter> chapters) async {
    _chapters[bookId] = chapters;
    await _saveToDisk();
    _notify();
  }

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
    await _saveToDisk();
    _notify();
  }

  Future<void> removeBookmark(String bookId, int pageIndex) async {
    final list = _bookmarks[bookId];
    if (list != null) {
      list.removeWhere((b) => b.pageIndex == pageIndex);
      await _saveToDisk();
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
