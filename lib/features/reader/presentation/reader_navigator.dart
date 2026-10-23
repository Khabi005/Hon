import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/theme/app_appearance.dart';
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
    bool fromCatalogue = false,
  }) async {
    // If not explicitly provided, look up saved progress from DatabaseService
    final savedProgress = DatabaseService.instance.getProgress(book.id);
    final explicitLocation =
        initialChapterIndex != null || initialPageIndex != null;
    final targetChapterIndex =
        initialChapterIndex ?? savedProgress?.chapterIndex.toInt() ?? 0;
    final targetPageIndex = initialPageIndex ?? savedProgress?.pageIndex ?? 0;
    final targetScrollOffset =
        initialScrollOffset ??
        (explicitLocation ? 0.0 : savedProgress?.scrollOffset ?? 0.0);
    final targetLocator =
        locator ??
        (explicitLocation
            ? null
            : savedProgress?.locatorString ?? savedProgress?.lastChapterId);

    if (book.format == BookFormat.pdf) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          // Modal, like Apple Books: no edge swipe-back to fight page turns.
          fullscreenDialog: true,
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
      final preferences = await SharedPreferences.getInstance();
      final stored = preferences.getString('hon_reader_preferences_v1');
      Map<String, dynamic> readerPrefs = {};
      if (stored != null) {
        try {
          readerPrefs = jsonDecode(stored) as Map<String, dynamic>;
        } catch (_) {
          // Keep the last valid native preferences if stored Dart preferences are damaged.
        }
      }
      final bookOverrides = DatabaseService.instance.getBookReaderSettings(
        book.id,
      );
      double fontSize =
          (((readerPrefs['size'] as num?)?.toDouble() ?? 18.0) / 18.0).clamp(
            0.5,
            2.5,
          );
      String theme = readerPrefs['theme'] as String? ?? 'calm';
      bool isScroll = readerPrefs['layout'] == 'verticalScroll';
      Map<String, dynamic> typography = Map<String, dynamic>.from(readerPrefs);

      if (bookOverrides != null) {
        if (bookOverrides['fontSize'] is num) {
          fontSize = (bookOverrides['fontSize'] as num).toDouble().clamp(
            0.5,
            2.5,
          );
        }
        if (bookOverrides['theme'] is String) {
          theme = bookOverrides['theme'] as String;
        }
        if (bookOverrides['isScroll'] is bool) {
          isScroll = bookOverrides['isScroll'] as bool;
        }
        if (bookOverrides['typography'] is String) {
          try {
            final typo = jsonDecode(bookOverrides['typography'] as String);
            if (typo is Map) {
              typography.addAll(Map<String, dynamic>.from(typo));
            }
          } catch (_) {}
        } else if (bookOverrides['typography'] is Map) {
          typography.addAll(
            Map<String, dynamic>.from(bookOverrides['typography'] as Map),
          );
        }
      }

      final appAppearance =
          preferences.getString(appAppearanceKey) ??
          preferences.getString('hon_app_appearance');
      final isGlass = appAppearance == AppAppearance.liquidGlass.name;

      await ReadiumReaderService.applySettings(
        fontSize: fontSize,
        theme: theme,
        isScroll: isScroll,
        isGlass: isGlass,
        typography: typography,
      );
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
      if (res?.cancelled == true) {
        return;
      }

      // Native Readium launch failed: show explicit error dialog rather than silently falling back
      if (context.mounted) {
        final errorMsg =
            res?.errorMessage ??
            res?.errorCode ??
            'Failed to initialize Readium reader engine';
        final shouldFallback = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1C1C1E),
            title: const Text(
              'Readium Engine Notice',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            content: Text(
              'Could not open this book in the native Readium engine:\n$errorMsg\n\nWould you like to open it in the fallback Dart preview reader?',
              style: const TextStyle(color: Color(0xFFE5E5EA), fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: Color(0xFFA0A0A5)),
                ),
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
              // Modal, like Apple Books: no edge swipe-back to fight page turns.
              fullscreenDialog: true,
              builder: (_) => ReaderScreen(
                book: book,
                restoreSavedProgress: false,
                initialChapterIndex: targetChapterIndex,
                initialPageIndex: targetPageIndex,
                initialScrollOffset: targetScrollOffset,
                initialLocator: targetLocator,
                initialChapterContent: initialChapterContent,
                fromCatalogue: fromCatalogue,
              ),
            ),
          );
        }
      }
    } else {
      await Navigator.of(context).push(
        MaterialPageRoute(
          // Modal, like Apple Books: no edge swipe-back to fight page turns.
          fullscreenDialog: true,
          builder: (_) => ReaderScreen(
            book: book,
            restoreSavedProgress: false,
            initialChapterIndex: targetChapterIndex,
            initialPageIndex: targetPageIndex,
            initialScrollOffset: targetScrollOffset,
            initialLocator: targetLocator,
            initialChapterContent: initialChapterContent,
            fromCatalogue: fromCatalogue,
          ),
        ),
      );
    }
  }
}
