import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/app/bootstrap/providers.dart';
import 'package:hon/app/theme/hon_theme.dart';
import 'package:hon/app/theme/reader_theme.dart';
import 'package:hon/core/utils/epub_parser.dart';
import 'package:hon/features/reader/sheets/reader_search_dialog.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/models/download_job.dart';
import 'package:hon/features/downloads/presentation/downloads_screen.dart';
import 'package:hon/features/library/presentation/library_screen.dart';
import 'package:hon/features/reader/sheets/themes_settings_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'Library filters distinguish formats and use explicit finished state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetForTesting();
      final db = DatabaseService.instance;
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      await db.init(database);
      final now = DateTime.now();
      for (final format in BookFormat.values) {
        final book = Book(
          id: format.name,
          title: '${format.name} title',
          format: format,
          createdAt: now,
          updatedAt: now,
        );
        await db.saveBook(book);
        await db.setLibraryMembership(book.id, true);
      }
      await db.markBookFinished(BookFormat.epub.name, true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [navigationTabProvider.overrideWith((ref) => 1)],
          child: MaterialApp(
            theme: HonTheme.lightTheme,
            home: const LibraryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('EPUBs'));
      await tester.pump();
      expect(find.text('epub title'), findsWidgets);
      expect(find.text('webNovel title'), findsNothing);
      await tester.tap(find.text('Finished'));
      await tester.pump();
      expect(find.text('epub title'), findsWidgets);
      expect(find.text('pdf title'), findsNothing);
      // A database notification refreshes the visible library without leaving it.
      await tester.runAsync(
        () => db.markBookFinished(BookFormat.epub.name, false),
      );
      await tester.pump();
      expect(find.text('No books in this view'), findsOneWidget);
      expect(find.text('Your next chapter starts here'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Offline shelf survives cleared queue and failed jobs show their actual state',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetForTesting();
      final db = DatabaseService.instance;
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      await db.init(database);
      final now = DateTime.now();
      final book = Book(
        id: 'saved-novel',
        title: 'Saved Novel',
        format: BookFormat.webNovel,
        createdAt: now,
        updatedAt: now,
      );
      await db.saveBook(book);
      await db.saveChapters(book.id, [
        Chapter(
          id: 'chapter',
          bookId: book.id,
          sourceChapterId: 'chapter',
          title: 'One',
          chapterIndex: 0,
          downloadState: ChapterDownloadState.downloaded,
          localFilePath: '/tmp/saved-chapter.html',
          updatedAt: now,
        ),
      ]);
      await db.enqueueDownload(
        DownloadJob(
          id: 'failure',
          bookId: book.id,
          chapterId: 'other',
          chapterTitle: 'A failed chapter',
          sourceId: 'source',
          status: DownloadStatus.failed,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [navigationTabProvider.overrideWith((ref) => 4)],
          child: MaterialApp(
            theme: HonTheme.lightTheme,
            home: const DownloadsScreen(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Download failed'), findsOneWidget);
      expect(find.byTooltip('Retry download'), findsOneWidget);
      expect(find.textContaining('Downloading ·'), findsNothing);
      await tester.tap(find.text('Ready Offline'));
      await tester.pump();
      expect(find.text('Saved Novel'), findsWidgets);
      expect(find.text('1 saved chapters'), findsOneWidget);
      expect(find.text('A failed chapter'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Spacing drag previews locally and commits one layout change on release',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HonTheme.lightTheme,
            home: const Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ThemesSettingsSheet(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Customize Fonts & Spacing'));
      await tester.tap(find.text('Customize Fonts & Spacing'));
      await tester.pumpAndSettle();
      final element = tester.element(find.byType(ThemesSettingsSheet));
      final container = ProviderScope.containerOf(element);
      final before = container.read(readerPreferencesProvider).lineHeight;
      // Line spacing is the only slider formatted as a multiplier ("1.65×").
      final slider = find.byWidgetPredicate(
        (w) => w is Slider && (w.label ?? '').endsWith('×'),
      );
      await tester.ensureVisible(slider);
      await tester.pumpAndSettle();
      final rect = tester.getRect(slider);
      final gesture = await tester.startGesture(
        rect.centerLeft + const Offset(30, 0),
      );
      await gesture.moveTo(rect.centerRight - const Offset(30, 0));
      await tester.pump();
      expect(container.read(readerPreferencesProvider).lineHeight, before);
      await gesture.up();
      await tester.pump();
      expect(
        container.read(readerPreferencesProvider).lineHeight,
        greaterThan(before),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'Book search finds saved text in a chapter that has not been opened',
    (tester) async {
      final folder = Directory.systemTemp.createTempSync('hon_search_');
      addTearDown(() => folder.deleteSync(recursive: true));
      final chapterFile = File('${folder.path}/unopened.html')
        ..writeAsStringSync('<p>The clockmaker remembers the winter.</p>');
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          theme: HonTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  selected = await showDialog<int>(
                    context: context,
                    builder: (_) => ReaderSearchDialog(
                      chapters: const [
                        EpubChapterItem(
                          id: 'one',
                          title: 'First Chapter',
                          contentHref: 'one',
                          htmlContent: '<p>A summer morning.</p>',
                        ),
                        EpubChapterItem(
                          id: 'two',
                          title: 'Unopened Chapter',
                          contentHref: 'two',
                          htmlContent: '',
                        ),
                      ],
                      localFiles: {1: chapterFile.path},
                      theme: ReaderThemeConfig.calm,
                    ),
                  );
                },
                child: const Text('Open search'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'clockmaker');
      await tester.tap(find.text('Search'));
      await tester.pump();
      for (
        var attempt = 0;
        attempt < 30 && find.text('Unopened Chapter').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }
      expect(
        find.text('Could not search saved chapters. Try again.'),
        findsNothing,
      );
      expect(find.text('Unopened Chapter'), findsOneWidget);
      expect(find.text('First Chapter'), findsNothing);
      await tester.tap(find.text('Unopened Chapter'));
      await tester.pumpAndSettle();
      expect(selected, 1);
    },
  );
}
