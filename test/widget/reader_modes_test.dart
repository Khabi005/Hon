import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/app/bootstrap/providers.dart';
import 'package:hon/app/theme/reader_theme.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/features/reader/presentation/reader_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'downloaded reader pages within a chapter and scrolls into the next',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = DatabaseService.instance;
      await db.init(AppDatabase.inMemory());
      final folder = Directory.systemTemp.createTempSync('hon_reader_modes_');
      addTearDown(() {
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      });
      final first = File('${folder.path}/first.html');
      final second = File('${folder.path}/second.html');
      first.writeAsStringSync(
        '<p>${List.filled(400, 'First chapter text.').join(' ')}</p>',
      );
      second.writeAsStringSync(
        '<p>${List.filled(40, 'Second chapter text.').join(' ')}</p>',
      );
      final now = DateTime.now();
      final book = Book(
        id: 'reader_modes',
        title: 'Mode Test',
        format: BookFormat.webNovel,
        totalChapters: 2,
        createdAt: now,
        updatedAt: now,
      );
      await db.saveBook(book);
      await db.saveChapters(book.id, [
        Chapter(
          id: 'one',
          bookId: book.id,
          sourceChapterId: 'one',
          title: 'Chapter One',
          chapterIndex: 0,
          localFilePath: first.path,
          updatedAt: now,
        ),
        Chapter(
          id: 'two',
          bookId: book.id,
          sourceChapterId: 'two',
          title: 'Chapter Two',
          chapterIndex: 1,
          localFilePath: second.path,
          updatedAt: now,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(home: ReaderScreen(book: book)),
        ),
      );
      await tester.pump();
      // Lazy chapter reads now use real asynchronous file I/O.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 500));
      for (
        var attempt = 0;
        attempt < 10 && find.text('Chapter 1 of 2').evaluate().isEmpty;
        attempt++
      ) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump();
      }
      expect(find.text('Chapter 1 of 2'), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Chapter 1 of 2'), findsOneWidget);
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        closeTo(2, 0.1),
      );

      final element = tester.element(find.byType(ReaderScreen));
      ProviderScope.containerOf(element)
          .read(readerPreferencesProvider.notifier)
          .setLayoutMode(ReaderLayoutMode.verticalScroll);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(CustomScrollView), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 500));
        if (find.text('Chapter 2 of 2').evaluate().isNotEmpty) break;
      }
      expect(find.text('Chapter 2 of 2'), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 500));
        if (find.text('Chapter 1 of 2').evaluate().isNotEmpty) break;
      }
      expect(find.text('Chapter 1 of 2'), findsOneWidget);
    },
  );

  testWidgets(
    'scrolling up loads the previous chapter without moving the text',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final db = DatabaseService.instance;
      await db.init(AppDatabase.inMemory());
      final folder = Directory.systemTemp.createTempSync('hon_reader_prepend_');
      addTearDown(() {
        if (folder.existsSync()) folder.deleteSync(recursive: true);
      });
      final now = DateTime.now();
      final book = Book(
        id: 'reader_prepend',
        title: 'Prepend Test',
        format: BookFormat.webNovel,
        totalChapters: 2,
        createdAt: now,
        updatedAt: now,
      );
      final chapters = <Chapter>[];
      for (final (i, word) in ['Alpha', 'Beta'].indexed) {
        final file = File('${folder.path}/$i.html')
          ..writeAsStringSync(
            '<p>${List.filled(120, '$word chapter text.').join(' ')}</p>',
          );
        chapters.add(
          Chapter(
            id: 'c$i',
            bookId: book.id,
            sourceChapterId: 'c$i',
            title: '$word Chapter',
            chapterIndex: i.toDouble(),
            localFilePath: file.path,
            updatedAt: now,
          ),
        );
      }
      await db.saveBook(book);
      await db.saveChapters(book.id, chapters);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ReaderScreen(
              book: book,
              initialChapterIndex: 1,
              restoreSavedProgress: false,
            ),
          ),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump(const Duration(milliseconds: 200));
        }
      }

      await settle();
      final element = tester.element(find.byType(ReaderScreen));
      ProviderScope.containerOf(element)
          .read(readerPreferencesProvider.notifier)
          .setLayoutMode(ReaderLayoutMode.verticalScroll);
      await settle();
      expect(find.text('Chapter 2 of 2'), findsOneWidget);
      final heading = find.text('Beta Chapter', findRichText: true);
      expect(heading, findsOneWidget);

      // A small pull down from the top of chapter 2 asks for chapter 1.
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 40));
      await tester.pump();
      final before = tester.getTopLeft(heading).dy;
      await settle();
      // Chapter 1 went in above; chapter 2's heading stayed where it was.
      expect(tester.getTopLeft(heading).dy, closeTo(before, 1));

      for (var i = 0; i < 20; i++) {
        if (find.text('Chapter 1 of 2').evaluate().isNotEmpty) break;
        await tester.drag(find.byType(CustomScrollView), const Offset(0, 500));
        await settle();
      }
      expect(find.text('Chapter 1 of 2'), findsOneWidget);
      expect(find.text('Alpha Chapter', findRichText: true), findsOneWidget);
    },
  );
}
