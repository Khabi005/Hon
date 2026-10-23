import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/utils/epub_parser.dart';
import 'package:hon/features/reader/sheets/reader_contents_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const count = 24;

  Future<void> openSheet(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final db = DatabaseService.instance;
    await db.init(AppDatabase.inMemory());
    final now = DateTime.now();
    final book = Book(
      id: 'contents',
      title: 'Contents Test',
      format: BookFormat.webNovel,
      totalChapters: count,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveBook(book);
    await db.saveChapters(book.id, [
      for (var i = 0; i < count; i++)
        Chapter(
          id: 'c$i',
          bookId: book.id,
          sourceChapterId: 'c$i',
          title: 'Episode ${i + 1}',
          chapterIndex: i.toDouble(),
          // Every third chapter is saved offline.
          localFilePath: i % 3 == 0 ? '/managed/c$i.html' : null,
          downloadState: i % 3 == 0
              ? ChapterDownloadState.downloaded
              : ChapterDownloadState.notDownloaded,
          updatedAt: now,
        ),
    ]);

    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReaderContentsSheet(
            bookId: book.id,
            bookTitle: book.title,
            currentChapterIndex: 4,
            totalChapters: count,
            chapters: [
              for (var i = 0; i < count; i++)
                EpubChapterItem(
                  id: 'c$i',
                  title: 'Episode ${i + 1}',
                  contentHref: '',
                  htmlContent: '',
                ),
            ],
            onSelectChapter: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('filters, search and newest-first narrow the chapter list', (
    tester,
  ) async {
    await openSheet(tester);
    expect(find.text('Episode 2'), findsOneWidget);

    await tester.tap(find.text('Downloaded'));
    await tester.pumpAndSettle();
    expect(find.text('Episode 1'), findsOneWidget);
    expect(find.text('Episode 2'), findsNothing);
    expect(find.text('Episode 4'), findsOneWidget);
    expect(find.text('Episode 5'), findsNothing);

    await tester.tap(find.text('Unread'));
    await tester.pumpAndSettle();
    expect(find.text('Episode 5'), findsNothing); // The one being read.
    expect(find.text('Episode 6'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.enterText(find.byType(CupertinoSearchTextField), '12');
    await tester.pumpAndSettle();
    expect(find.text('Episode 12'), findsOneWidget);
    expect(find.text('Episode 6'), findsNothing);

    await tester.enterText(find.byType(CupertinoSearchTextField), '');
    await tester.tap(find.byTooltip('Show newest first'));
    await tester.pumpAndSettle();
    expect(find.text('Episode 24'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Episode 24')).dy,
      lessThan(tester.getTopLeft(find.text('Episode 23')).dy),
    );

    // The choice is remembered for the next time Contents opens.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('hon_contents_newest_first'), isTrue);
    expect(prefs.getString('hon_contents_chapter_filter'), 'all');
  });

  testWidgets('select range fills in the chapters between two picks', (
    tester,
  ) async {
    await openSheet(tester);
    await tester.longPress(find.text('Episode 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Episode 5'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Selection options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select range between'));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Selection options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Invert selection'));
    await tester.pumpAndSettle();
    expect(find.text('${count - 3} selected'), findsOneWidget);
  });
}
