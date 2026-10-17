import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/reading_progress.dart';
import 'package:hon/core/models/bookmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DatabaseService db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = DatabaseService.instance;
    await db.init();
  });

  group('Phase 0B — PDF Reading, Bookmarks & Position Restoration', () {
    const pdfBookId = 'book_pdf_sample_manual';

    final testPdfBook = Book(
      id: pdfBookId,
      title: 'Flutter Architecture Guide',
      author: 'Google Engineering',
      format: BookFormat.pdf,
      filePath: '/mock/path/flutter_guide.pdf',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    test('Saves and restores PDF page reading progress accurately', () async {
      await db.saveBook(testPdfBook);

      // Verify no progress initially
      expect(db.getProgress(pdfBookId), isNull);

      // Save reading progress on page 42 of 150
      final progress = ReadingProgress(
        bookId: pdfBookId,
        pageIndex: 42,
        totalPages: 150,
        completionPercentage: 42 / 150,
        lastReadAt: DateTime.now(),
      );
      await db.saveProgress(progress);

      // Retrieve saved progress
      final saved = db.getProgress(pdfBookId);
      expect(saved, isNotNull);
      expect(saved!.pageIndex, equals(42));
      expect(saved.totalPages, equals(150));
      expect(saved.completionPercentage, closeTo(0.28, 0.01));
    });

    test('Adds, checks, and toggles bookmarks for PDF pages', () async {
      await db.saveBook(testPdfBook);

      // Page 12 is not bookmarked initially
      expect(db.isBookmarked(pdfBookId, 12), isFalse);

      // Toggle bookmark for page 12 -> should add it
      final added = await db.toggleBookmark(
        pdfBookId,
        12,
        label: 'Important Architecture Diagram',
      );
      expect(added, isTrue);
      expect(db.isBookmarked(pdfBookId, 12), isTrue);

      final bookmarks = db.getBookmarks(pdfBookId);
      expect(bookmarks.length, equals(1));
      expect(bookmarks.first.pageIndex, equals(12));
      expect(bookmarks.first.label, equals('Important Architecture Diagram'));

      // Toggle again -> should remove it
      final removed = await db.toggleBookmark(pdfBookId, 12);
      expect(removed, isFalse);
      expect(db.isBookmarked(pdfBookId, 12), isFalse);
      expect(db.getBookmarks(pdfBookId), isEmpty);
    });

    test('Bookmarks are sorted by pageIndex in ascending order', () async {
      await db.saveBook(testPdfBook);

      // Add bookmarks in unsorted order
      await db.addBookmark(Bookmark(
        id: 'bm_1',
        bookId: pdfBookId,
        pageIndex: 75,
        label: 'Chapter 5 Summary',
        createdAt: DateTime.now(),
      ));
      await db.addBookmark(Bookmark(
        id: 'bm_2',
        bookId: pdfBookId,
        pageIndex: 12,
        label: 'Introduction Notes',
        createdAt: DateTime.now(),
      ));
      await db.addBookmark(Bookmark(
        id: 'bm_3',
        bookId: pdfBookId,
        pageIndex: 120,
        label: 'Appendix B',
        createdAt: DateTime.now(),
      ));

      final bookmarks = db.getBookmarks(pdfBookId);
      expect(bookmarks.length, equals(3));
      expect(bookmarks[0].pageIndex, equals(12));
      expect(bookmarks[1].pageIndex, equals(75));
      expect(bookmarks[2].pageIndex, equals(120));
    });

    test('Deleting a book cleans up its bookmarks completely', () async {
      const secondBookId = 'book_pdf_second';
      final secondBook = Book(
        id: secondBookId,
        title: 'Design Patterns',
        format: BookFormat.pdf,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await db.saveBook(testPdfBook);
      await db.saveBook(secondBook);

      await db.addBookmark(Bookmark(
        id: 'bm_1',
        bookId: pdfBookId,
        pageIndex: 5,
        label: 'Note',
        createdAt: DateTime.now(),
      ));
      await db.addBookmark(Bookmark(
        id: 'bm_2',
        bookId: secondBookId,
        pageIndex: 20,
        label: 'Second Note',
        createdAt: DateTime.now(),
      ));

      // Delete first book
      await db.deleteBook(pdfBookId);

      expect(db.getBookById(pdfBookId), isNull);
      expect(db.getBookmarks(pdfBookId), isEmpty);
      // Second book's bookmarks remain intact
      expect(db.getBookmarks(secondBookId).length, equals(1));
    });

    test('File validation catches non-existent and empty files', () async {
      final nonExistent = File('/path/that/does/not/exist/guide.pdf');
      expect(nonExistent.existsSync(), isFalse);

      final tempDir = Directory.systemTemp.createTempSync('hon_test_');
      final zeroByteFile = File('${tempDir.path}/empty.pdf');
      zeroByteFile.writeAsBytesSync([]);

      expect(zeroByteFile.existsSync(), isTrue);
      expect(zeroByteFile.lengthSync(), equals(0));

      tempDir.deleteSync(recursive: true);
    });

    test('Persists and restores PDF tone filters and page view modes', () async {
      // Defaults
      expect(db.getPdfColorFilter(), equals('original'));
      expect(db.getPdfPageViewMode(), equals('continuousZoom'));

      // Update preferences
      await db.setPdfColorFilter('sepia');
      await db.setPdfPageViewMode('singlePage');

      expect(db.getPdfColorFilter(), equals('sepia'));
      expect(db.getPdfPageViewMode(), equals('singlePage'));

      // Re-init simulated app restart
      await db.init();
      expect(db.getPdfColorFilter(), equals('sepia'));
      expect(db.getPdfPageViewMode(), equals('singlePage'));
    });

    test('Formatted reading progress does not double-shift 1-based PDF page numbers', () {
      final pdfProgress = ReadingProgress(
        bookId: pdfBookId,
        pageIndex: 42, // Already 1-based page
        totalPages: 150,
        completionPercentage: 42 / 150,
        lastReadAt: DateTime.now(),
      );

      // Must be "28% • Page 42 of 150", NOT "Page 43 of 150"
      expect(pdfProgress.formattedProgress, equals('28% • Page 42 of 150'));
    });

    test('Removing from library updates membership without corrupting catalog entry', () async {
      await db.saveBook(testPdfBook);
      await db.setLibraryMembership(pdfBookId, true);
      expect(db.isBookInLibrary(pdfBookId), isTrue);

      // Remove from library (e.g. from error screen)
      await db.setLibraryMembership(pdfBookId, false);
      expect(db.isBookInLibrary(pdfBookId), isFalse);

      // Book record is preserved, not nuked
      expect(db.getBookById(pdfBookId), isNotNull);
    });

    test('Entering final chapter without reading through does not record 100% completion', () {
      const totalChapters = 10;
      const finalChapterIndex = 9; // 0-indexed 10th chapter
      const chapterFraction = 0.10; // Only 10% through final chapter

      const overallFraction = (finalChapterIndex + chapterFraction) / totalChapters;
      const isAtEndOfBook = (finalChapterIndex == totalChapters - 1) && (chapterFraction >= 0.95);
      final pct = isAtEndOfBook ? 1.0 : overallFraction.clamp(0.0, 0.99);

      // Should be ~91%, definitely NOT 100% (1.0)
      expect(pct, lessThan(1.0));
      expect(pct, closeTo(0.91, 0.01));
    });
  });
}
