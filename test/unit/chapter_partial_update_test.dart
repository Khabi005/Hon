import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'one download update preserves every other chapter in cache and SQLite',
    () async {
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetForTesting();
      final database = AppDatabase.inMemory();
      addTearDown(database.close);
      final db = DatabaseService.instance;
      await db.init(database);
      final now = DateTime.now();
      await db.saveBook(
        Book(
          id: 'novel',
          title: 'Novel',
          format: BookFormat.webNovel,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final chapters = [
        for (var i = 0; i < 3; i++)
          Chapter(
            id: 'c$i',
            bookId: 'novel',
            sourceChapterId: 'c$i',
            title: 'Chapter $i',
            chapterIndex: i.toDouble(),
            updatedAt: now,
          ),
      ];
      await db.saveChapters('novel', chapters);
      await db.saveChapters('novel', [
        chapters[1].copyWith(
          downloadState: ChapterDownloadState.downloaded,
          localFilePath: '/tmp/chapter.html',
        ),
      ]);
      expect(db.getChapters('novel').map((chapter) => chapter.id), [
        'c0',
        'c1',
        'c2',
      ]);
      expect(
        db.getChapters('novel')[1].downloadState,
        ChapterDownloadState.downloaded,
      );
      await db.refreshAllChapters();
      expect(db.getChapters('novel').length, 3);
      expect(
        db
            .getChapters('novel')
            .singleWhere((chapter) => chapter.id == 'c1')
            .localFilePath,
        '/tmp/chapter.html',
      );
    },
  );
}
