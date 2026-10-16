import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';
import '../models/library_entry.dart';
import '../models/chapter.dart';
import '../models/reading_progress.dart';
import '../models/download_job.dart';

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

  // Session-scoped suppressed novel IDs for library prompt
  final Set<String> _suppressedPromptNovelIds = {};

  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadFromDisk();

    // If completely empty, seed with initial fixtures inspired by the Apple Books iOS 18 reference
    if (_books.isEmpty) {
      await _seedFixtures();
    }
  }

  void _notify() {
    changeNotifier.value++;
  }

  Future<void> _loadFromDisk() async {
    final booksJson = _prefs?.getString('hon_books');
    if (booksJson != null) {
      final list = jsonDecode(booksJson) as List<dynamic>;
      for (final item in list) {
        final b = Book.fromMap(item as Map<String, dynamic>);
        _books[b.id] = b;
      }
    }

    final libJson = _prefs?.getString('hon_library');
    if (libJson != null) {
      final list = jsonDecode(libJson) as List<dynamic>;
      for (final item in list) {
        final entry = LibraryEntry.fromMap(item as Map<String, dynamic>);
        _libraryEntries[entry.bookId] = entry;
      }
    }

    final progJson = _prefs?.getString('hon_progress');
    if (progJson != null) {
      final list = jsonDecode(progJson) as List<dynamic>;
      for (final item in list) {
        final prog = ReadingProgress.fromMap(item as Map<String, dynamic>);
        _readingProgress[prog.bookId] = prog;
      }
    }

    final jobsJson = _prefs?.getString('hon_downloads');
    if (jobsJson != null) {
      final list = jsonDecode(jobsJson) as List<dynamic>;
      for (final item in list) {
        final job = DownloadJob.fromMap(item as Map<String, dynamic>);
        _downloadJobs[job.id] = job;
      }
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
  }

  // --- Books & Library ---
  List<Book> getAllBooks() => _books.values.toList();

  List<Book> getLibraryBooks() {
    return _books.values.where((b) {
      final entry = _libraryEntries[b.id];
      return entry != null && entry.isInLibrary;
    }).toList();
  }

  List<Book> getContinueReadingBooks() {
    final list = _books.values.where((b) {
      final prog = _readingProgress[b.id];
      final entry = _libraryEntries[b.id];
      final inLibOrProgress = (entry?.isInLibrary ?? false) || prog != null;
      return inLibOrProgress && (prog?.completionPercentage ?? 0) < 1.0;
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

  // --- Reading Progress ---
  ReadingProgress? getProgress(String bookId) => _readingProgress[bookId];

  Future<void> saveProgress(ReadingProgress progress) async {
    _readingProgress[progress.bookId] = progress;
    final entry = _libraryEntries[progress.bookId];
    if (entry != null) {
      _libraryEntries[progress.bookId] = entry.copyWith(
        lastReadAt: progress.lastReadAt,
        isFinished: progress.completionPercentage >= 0.99,
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

  void setChaptersForBook(String bookId, List<Chapter> chapters) {
    _chapters[bookId] = chapters;
    _notify();
  }

  // --- Seed Fixtures ---
  Future<void> _seedFixtures() async {
    final now = DateTime.now();

    // 1. Pride and Prejudice (Local EPUB with actual fixture)
    final pandp = Book(
      id: 'book_pride_and_prejudice',
      title: 'Pride and Prejudice',
      author: 'Jane Austen',
      description: 'The romantic clash between the opinionated Elizabeth and her proud beau, Mr. Darcy.',
      format: BookFormat.epub,
      filePath: 'assets/fixtures/pride_and_prejudice.epub',
      contentHash: 'hash_pandp_fixture',
      totalChapters: 61,
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(hours: 1)),
    );
    _books[pandp.id] = pandp;
    _libraryEntries[pandp.id] = LibraryEntry(
      bookId: pandp.id,
      isInLibrary: true,
      dateAdded: now.subtract(const Duration(days: 3)),
      lastReadAt: now.subtract(const Duration(hours: 1)),
    );
    _readingProgress[pandp.id] = ReadingProgress(
      bookId: pandp.id,
      lastChapterId: 'ch40',
      chapterIndex: 40.0,
      pageIndex: 394,
      totalPages: 691,
      completionPercentage: 395 / 691,
      lastReadAt: now.subtract(const Duration(hours: 1)),
    );

    // 2. Good Material (From Apple Books screenshot)
    final goodMaterial = Book(
      id: 'book_good_material',
      title: 'Good Material',
      author: 'Dolly Alderton',
      description: 'A brilliantly funny and heartbreakingly honest story about the end of a relationship.',
      format: BookFormat.epub,
      totalChapters: 24,
      createdAt: now.subtract(const Duration(days: 5)),
      updatedAt: now.subtract(const Duration(hours: 4)),
    );
    _books[goodMaterial.id] = goodMaterial;
    _libraryEntries[goodMaterial.id] = LibraryEntry(
      bookId: goodMaterial.id,
      isInLibrary: true,
      dateAdded: now.subtract(const Duration(days: 5)),
      lastReadAt: now.subtract(const Duration(hours: 4)),
    );
    _readingProgress[goodMaterial.id] = ReadingProgress(
      bookId: goodMaterial.id,
      chapterIndex: 2.0,
      pageIndex: 18,
      totalPages: 320,
      completionPercentage: 0.06,
      lastReadAt: now.subtract(const Duration(hours: 4)),
    );

    // 3. First Lie Wins (From Apple Books screenshot)
    final firstLieWins = Book(
      id: 'book_first_lie_wins',
      title: 'First Lie Wins',
      author: 'Ashley Elston',
      description: 'Evie Porter has everything a nice, Southern girl could want. The only problem? Evie Porter doesn\'t exist.',
      format: BookFormat.epub,
      totalChapters: 30,
      createdAt: now.subtract(const Duration(days: 10)),
      updatedAt: now.subtract(const Duration(days: 2)),
    );
    _books[firstLieWins.id] = firstLieWins;
    _libraryEntries[firstLieWins.id] = LibraryEntry(
      bookId: firstLieWins.id,
      isInLibrary: true,
      dateAdded: now.subtract(const Duration(days: 10)),
      lastReadAt: now.subtract(const Duration(days: 2)),
    );
    _readingProgress[firstLieWins.id] = ReadingProgress(
      bookId: firstLieWins.id,
      chapterIndex: 7.0,
      pageIndex: 72,
      totalPages: 340,
      completionPercentage: 0.21,
      lastReadAt: now.subtract(const Duration(days: 2)),
    );

    // 4. War and Peace (From Apple Books screenshot)
    final warAndPeace = Book(
      id: 'book_war_and_peace',
      title: 'War and Peace',
      author: 'Leo Tolstoy',
      description: 'A masterpiece detailing the French invasion of Russia and the impact of the Napoleonic era.',
      format: BookFormat.epub,
      totalChapters: 365,
      createdAt: now.subtract(const Duration(days: 15)),
      updatedAt: now.subtract(const Duration(days: 7)),
    );
    _books[warAndPeace.id] = warAndPeace;
    _libraryEntries[warAndPeace.id] = LibraryEntry(
      bookId: warAndPeace.id,
      isInLibrary: true,
      dateAdded: now.subtract(const Duration(days: 15)),
    );

    await _saveToDisk();
  }
}
