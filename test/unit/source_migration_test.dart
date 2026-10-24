import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/files/storage_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/models/novel_source.dart';
import 'package:hon/core/models/reading_progress.dart';
import 'package:hon/core/sources/source_migration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 10, 1);

  Chapter chapter(String bookId, int i, String title) => Chapter(
    id: '$bookId:c$i',
    bookId: bookId,
    sourceChapterId: 'c$i',
    title: title,
    chapterIndex: i.toDouble(),
    updatedAt: now,
  );

  group('matchChapter', () {
    final candidates = [
      for (var i = 0; i < 10; i++) chapter('new', i, 'Ch. ${i + 1} - Part'),
    ];

    test('prefers the same chapter number', () {
      final old = chapter('old', 40, 'Chapter 7: The Door');
      expect(SourceMigration.matchChapter(old, 40, 100, candidates), 6);
    });

    test('falls back to the same relative position', () {
      final old = chapter('old', 50, 'The Door Opens');
      expect(
        SourceMigration.matchChapter(old, 50, 101, [
          for (var i = 0; i < 11; i++) chapter('new', i, 'Untitled'),
        ]),
        5,
      );
    });

    test('reads numbers from common title shapes', () {
      expect(SourceMigration.chapterNumber('Chapter 12: Hello'), '12');
      expect(SourceMigration.chapterNumber('Ep. 3.5 Bonus'), '3.5');
      expect(SourceMigration.chapterNumber('Vol 2 - 14'), '2');
      expect(SourceMigration.chapterNumber('Prologue'), isNull);
    });
  });

  test('migrate keeps the place, library spot and finished flag', () async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    final folder = await Directory.systemTemp.createTemp('hon_migrate_');
    addTearDown(() => folder.delete(recursive: true));
    StorageService.instance.setBaseDirForTesting(folder);
    final sql = AppDatabase.inMemory();
    addTearDown(sql.close);
    final db = DatabaseService.instance;
    await db.init(sql);

    final old = Book(
      id: 'dead:novel',
      title: 'The Novel',
      author: 'Writer',
      format: BookFormat.webNovel,
      sourceId: 'dead',
      sourceNovelId: 'novel',
      totalChapters: 3,
      createdAt: now,
      updatedAt: now,
    );
    await db.saveBook(old);
    await db.saveChapters(old.id, [
      chapter(old.id, 0, 'Chapter 1'),
      chapter(old.id, 1, 'Chapter 2'),
      chapter(old.id, 2, 'Chapter 3'),
    ]);
    await db.setLibraryMembership(old.id, true);
    await db.markBookFinished(old.id, true);
    final readAt = DateTime(2026, 9, 1);
    await db.saveProgress(
      ReadingProgress(bookId: old.id, chapterIndex: 2, lastReadAt: readAt),
    );

    final result = await SourceMigration.migrate(
      from: old,
      targetSourceId: 'alive',
      details: const NovelDetails(
        id: 'n-42',
        title: 'The Novel',
        author: 'Writer',
        chapters: [
          SourceChapter(id: 'p', title: 'Prologue', index: 0),
          SourceChapter(id: 'a', title: 'Chapter 1', index: 1),
          SourceChapter(id: 'b', title: 'Chapter 2', index: 2),
          SourceChapter(id: 'c', title: 'Chapter 3', index: 3),
        ],
      ),
    );

    expect(result.book.id, 'alive:n-42');
    expect(result.resumeChapter!.title, 'Chapter 3');
    final progress = db.getProgress('alive:n-42')!;
    expect(progress.chapterIndex, 3);
    expect(progress.lastChapterId, 'alive:n-42:c');
    expect(progress.lastReadAt, readAt);
    expect(db.isBookInLibrary('alive:n-42'), isTrue);
    expect(db.getLibraryEntry('alive:n-42')!.isFinished, isTrue);
    expect(db.isBookInLibrary(old.id), isFalse);
    expect(db.getChapters('alive:n-42'), hasLength(4));

    expect(
      () => SourceMigration.migrate(
        from: result.book,
        targetSourceId: 'alive',
        details: const NovelDetails(id: 'n-42', title: 'The Novel'),
      ),
      throwsStateError,
    );
  });
}
