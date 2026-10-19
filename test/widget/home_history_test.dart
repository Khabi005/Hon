import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/app/bootstrap/providers.dart';
import 'package:hon/app/theme/hon_theme.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/reading_progress.dart';
import 'package:hon/features/home/presentation/home_screen.dart';
import 'package:hon/features/home/presentation/reading_history_screen.dart';
import 'package:hon/features/home/presentation/widgets/reading_week.dart';

void main() {
  late AppDatabase sql;
  late DatabaseService db;
  final now = DateTime.now();
  Book book(String id) => Book(
    id: id,
    title: 'Book $id',
    author: 'Author $id',
    format: BookFormat.webNovel,
    createdAt: now,
    updatedAt: now,
  );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    sql = AppDatabase.inMemory();
    db = DatabaseService.instance;
    await db.init(sql);
  });
  tearDown(() => sql.close());

  Future<void> seed() async {
    for (final id in ['current', 'finished', 'outside', 'unread']) {
      await db.saveBook(book(id));
      if (id != 'outside') await db.setLibraryMembership(id, true);
    }
    for (var i = 0; i < 3; i++) {
      final id = ['outside', 'current', 'finished'][i];
      await db.saveProgress(
        ReadingProgress(
          bookId: id,
          completionPercentage: id == 'finished' ? 1 : .3,
          lastReadAt: now.subtract(Duration(days: i)),
        ),
      );
    }
    await db.markBookFinished('finished', true);
  }

  test(
    'History includes finished and non-library books in durable last-read order',
    () async {
      await seed();
      await db.markBookFinished('outside', true);
      await db.init(sql);
      expect(db.getReadingHistoryBooks().map((book) => book.id), [
        'outside',
        'current',
        'finished',
      ]);
      expect(db.isBookInLibrary('outside'), false);
      expect(
        db.getContinueReadingBooks().map((book) => book.id),
        isNot(contains('finished')),
      );
      await db.addReadingTime(7 * 60);
      expect(db.getReadingMinutesOn(now), 7);
      expect(
        db.getReadingMinutesOn(DateTime(now.year, now.month, now.day - 1)),
        0,
      );
    },
  );

  testWidgets(
    'History searches authors, filters finished books and responds to saved progress',
    (tester) async {
      await seed();
      await tester.pumpWidget(
        MaterialApp(
          theme: HonTheme.lightTheme,
          home: const ReadingHistoryScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-outside')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-unread')), findsNothing);
      await tester.enterText(find.byType(TextField), 'Author outside');
      await tester.pump();
      expect(find.byKey(const ValueKey('history-outside')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-current')), findsNothing);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.tap(find.widgetWithText(ChoiceChip, 'Finished'));
      await tester.pump();
      expect(find.byKey(const ValueKey('history-finished')), findsOneWidget);
      expect(find.byKey(const ValueKey('history-outside')), findsNothing);
      await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
      await tester.runAsync(
        () => db.saveProgress(
          ReadingProgress(bookId: 'unread', lastReadAt: DateTime.now()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-unread')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Empty Home offers working History and source navigation', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: HonTheme.lightTheme,
          home: const HomeScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Reading History'));
    await tester.tap(find.text('Reading History'));
    await tester.pumpAndSettle();
    expect(find.text('Your reading trail starts here'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Browse Sources'));
    await tester.tap(find.text('Browse Sources'));
    await tester.pump();
    expect(container.read(navigationTabProvider), 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Narrow large-text Home and History remain usable with real weekly totals',
    (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await seed();
      await db.addReadingTime(3 * 60);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: HonTheme.darkTheme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.4)),
              child: child!,
            ),
            home: const HomeScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byType(ReadingWeek),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('3 of 5 minutes today'), findsOneWidget);
      expect(find.byType(ReadingWeek), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MaterialApp(
          theme: HonTheme.darkTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: const ReadingHistoryScreen(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('history-outside')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
