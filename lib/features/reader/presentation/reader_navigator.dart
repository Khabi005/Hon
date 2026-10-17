import 'dart:io';
import 'package:flutter/material.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/native/readium_reader_service.dart';
import 'pdf_reader_screen.dart';
import 'reader_screen.dart';

class ReaderNavigator {
  /// Opens a book in the appropriate reader (EPUB/WebNovel or PDF)
  /// restoring its last saved location or navigating to a specific chapter/page.
  static Future<void> openBook(
    BuildContext context,
    Book book, {
    int? initialChapterIndex,
    int? initialPageIndex,
    double? initialScrollOffset,
    String? locator,
    String? initialChapterContent,
  }) async {
    // If not explicitly provided, look up saved progress from DatabaseService
    final savedProgress = DatabaseService.instance.getProgress(book.id);
    final targetChapterIndex = initialChapterIndex ?? savedProgress?.chapterIndex.toInt() ?? 0;
    final targetPageIndex = initialPageIndex ?? savedProgress?.pageIndex ?? 0;
    final targetScrollOffset = initialScrollOffset ?? savedProgress?.scrollOffset ?? 0.0;
    final targetLocator = locator ?? savedProgress?.locatorString ?? savedProgress?.lastChapterId;

    if (book.format == BookFormat.pdf) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PdfReaderScreen(
            book: book,
            initialPage: targetPageIndex > 0 ? targetPageIndex : 1,
          ),
        ),
      );
    } else if (book.format == BookFormat.epub &&
        Platform.isAndroid &&
        book.filePath != null &&
        !book.filePath!.startsWith('assets/')) {
      final res = await ReadiumReaderService.openEpub(
        filePath: book.filePath!,
        bookId: book.id,
        title: book.title,
        chapterIndex: targetChapterIndex,
        initialLocator: targetLocator,
      );

      // If native Readium reader launched successfully, return
      if (res != null && res.success) {
        return;
      }

      // Native Readium launch failed: show explicit error dialog rather than silently falling back
      if (context.mounted) {
        final errorMsg = res?.errorMessage ?? res?.errorCode ?? 'Failed to initialize Readium reader engine';
        final shouldFallback = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text(
              'Readium Engine Notice',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              'Could not open this book in the native Readium engine:\n$errorMsg\n\nWould you like to open it in the fallback Dart preview reader?',
              style: const TextStyle(color: Color(0xFFE5E5EA), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFFA0A0A5))),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('Open Preview'),
              ),
            ],
          ),
        );

        if (shouldFallback == true && context.mounted) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ReaderScreen(
                book: book,
                initialChapterIndex: targetChapterIndex,
                initialPageIndex: targetPageIndex,
                initialScrollOffset: targetScrollOffset,
                initialLocator: targetLocator,
                initialChapterContent: initialChapterContent,
              ),
            ),
          );
        }
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            book: book,
            initialChapterIndex: targetChapterIndex,
            initialPageIndex: targetPageIndex,
            initialScrollOffset: targetScrollOffset,
            initialLocator: targetLocator,
            initialChapterContent: initialChapterContent,
          ),
        ),
      );
    }
  }
}
