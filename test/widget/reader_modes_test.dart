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
      expect(find.byType(ListView), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pump();
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump(const Duration(milliseconds: 500));
        if (find.text('Chapter 2 of 2').evaluate().isNotEmpty) break;
      }
      expect(find.text('Chapter 2 of 2'), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, 600));
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
}
