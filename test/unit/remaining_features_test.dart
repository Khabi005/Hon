import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hon/core/backup/backup_service.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/files/storage_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/bookmark.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:hon/core/models/download_job.dart';
import 'package:hon/core/models/novel_source.dart';
import 'package:hon/core/models/reading_progress.dart';
import 'package:hon/core/updates/chapter_update_service.dart';
import 'package:hon/core/downloads/hon_download_manager.dart';
import 'package:hon/core/sources/source_registry.dart';
import 'package:hon/core/sources/source_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory folder;
  late AppDatabase sql;
  late DatabaseService db;
  final now = DateTime(2026, 10, 19);
  Book book(
    String id, {
    BookFormat format = BookFormat.webNovel,
    String? path,
  }) => Book(
    id: id,
    title: 'Book $id',
    format: format,
    sourceId: 'fixture',
    sourceNovelId: id,
    filePath: path,
    createdAt: now,
    updatedAt: now,
  );
  Chapter chapter(String id, String bookId, int index, {String? path}) =>
      Chapter(
        id: id,
        bookId: bookId,
        sourceChapterId: id,
        title: 'Chapter $index',
        chapterIndex: index.toDouble(),
        url: 'https://example.test/$id',
        localFilePath: path,
        downloadState: path == null
            ? ChapterDownloadState.notDownloaded
            : ChapterDownloadState.downloaded,
        updatedAt: now,
      );
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    folder = await Directory.systemTemp.createTemp('hon_completion_');
    StorageService.instance.setBaseDirForTesting(folder);
    for (final child in ['publications', 'covers', 'chapters', 'staging']) {
      await Directory('${folder.path}/$child').create();
    }
    sql = AppDatabase.inMemory();
    db = DatabaseService.instance;
    await db.init(sql);
  });
  tearDown(() async {
    await sql.close();
    if (await folder.exists()) await folder.delete(recursive: true);
  });
  test(
    'collections survive reload; rename/delete preserve books and membership',
    () async {
      await db.saveBook(book('one'));
      await db.setLibraryMembership('one', true);
      final first = await db.createCollection('Favorites');
      final second = await db.createCollection('Next');
      await db.setBookCollections('one', [first, second]);
      await db.renameCollection(first, 'Keepers');
      await db.init(sql);
      expect(db.collections[first], 'Keepers');
      expect(db.getLibraryEntry('one')!.collectionIds, [first, second]);
      await db.deleteCollection(first);
      await db.init(sql);
      expect(db.collections.containsKey(first), false);
      expect(db.getLibraryEntry('one')!.collectionIds, [second]);
      expect(db.isBookInLibrary('one'), true);
    },
  );
  test(
    'update checks deduplicate history and preserve existing downloaded chapters',
    () async {
      await db.saveBook(book('one'));
      await db.setLibraryMembership('one', true);
      await db.saveChapters('one', [
        chapter('old', 'one', 0, path: '${folder.path}/chapters/old.html'),
      ]);
      await db.saveProgress(
        ReadingProgress(
          bookId: 'one',
          lastChapterId: 'old',
          chapterIndex: 0,
          lastReadAt: now,
        ),
      );
      final updates = ChapterUpdateService(
        fetch: (source, id) async => NovelDetails(
          id: id,
          title: 'Updated',
          chapters: const [
            SourceChapter(
              id: 'new',
              title: 'New',
              index: 0,
              url: 'https://example.test/new',
            ),
            SourceChapter(
              id: 'old',
              title: 'Old',
              index: 1,
              url: 'https://example.test/old',
            ),
          ],
        ),
      );
      expect(await updates.check(), 1);
      expect(await updates.check(), 0);
      expect(updates.history.length, 1);
      expect(
        db.getChapters('one').last.downloadState,
        ChapterDownloadState.downloaded,
      );
      expect(db.getProgress('one')!.chapterIndex, 1);
      expect(db.getProgress('one')!.lastChapterId, 'old');
      final reopened = ChapterUpdateService();
      await reopened.init();
      expect(reopened.history.length, 1);
      final failed = ChapterUpdateService(
        fetch: (source, id) async =>
            throw const FormatException('Source unavailable'),
      );
      await failed.check();
      expect(failed.errors['one'], contains('Source unavailable'));
      expect(db.getChapters('one').length, 2);
    },
  );
  test(
    'portable backup restores files, locators, collections and paused jobs',
    () async {
      final publication = File('${folder.path}/publications/book.epub')
        ..writeAsStringSync('publication bytes');
      final saved = book(
        'one',
        format: BookFormat.epub,
        path: publication.path,
      );
      await db.saveBook(saved);
      await db.setLibraryMembership('one', true);
      final collection = await db.createCollection('Shelf 本');
      await db.setBookCollections('one', [collection]);
      await db.saveProgress(
        ReadingProgress(
          bookId: 'one',
          chapterIndex: 2,
          locatorString: '{"href":"chapter.xhtml"}',
          completionPercentage: .45,
          lastReadAt: now,
        ),
      );
      await db.addBookmark(
        Bookmark(
          id: 'bookmark',
          bookId: 'one',
          pageIndex: 2,
          label: 'Passage',
          createdAt: now,
        ),
      );
      final text = File('${folder.path}/chapters/one.html')
        ..writeAsStringSync('<p>Offline text</p>');
      await db.saveChapters('one', [chapter('c1', 'one', 0, path: text.path)]);
      await db.enqueueDownload(
        DownloadJob(
          id: 'job',
          bookId: 'one',
          chapterId: 'c1',
          chapterTitle: 'One',
          sourceId: 'fixture',
          status: DownloadStatus.running,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await db.setDailyGoalMinutes(20);
      final service = BackupService();
      final archive = await service.create(includeFiles: true);
      final preview = await service.inspect(archive);
      expect(preview.books, 1);
      expect(preview.files, 2);
      await sql.close();
      final restoredRoot = Directory('${folder.path}/restored')..createSync();
      StorageService.instance.setBaseDirForTesting(restoredRoot);
      SharedPreferences.setMockInitialValues({});
      DatabaseService.resetForTesting();
      sql = AppDatabase.inMemory();
      db = DatabaseService.instance;
      await db.init(sql);
      await service.restore(archive);
      final restored = db.getBookById('one')!;
      expect(
        restored.filePath,
        startsWith('${restoredRoot.path}/publications/restore_'),
      );
      expect(File(restored.filePath!).readAsStringSync(), 'publication bytes');
      expect(db.getProgress('one')!.completionPercentage, .45);
      expect(db.getProgress('one')!.locatorString, contains('chapter.xhtml'));
      expect(db.getBookmarks('one').single.label, 'Passage');
      expect(db.collections[collection], 'Shelf 本');
      expect(db.getLibraryEntry('one')!.collectionIds, [collection]);
      expect(db.getAllDownloadJobs().single.status, DownloadStatus.paused);
      expect(db.getDailyGoalMinutes(), 20);
      expect(
        File(db.getChapters('one').single.localFilePath!).readAsStringSync(),
        contains('Offline text'),
      );
    },
  );
  test(
    'tampered and path-traversal archives fail without importing records',
    () async {
      final pub = File('${folder.path}/publications/book.epub')
        ..writeAsStringSync('original');
      await db.saveBook(book('one', format: BookFormat.epub, path: pub.path));
      final service = BackupService();
      final original = await service.create(includeFiles: true);
      final decoded = ZipDecoder().decodeBytes(await original.readAsBytes());
      final manifest =
          jsonDecode(
                utf8.decode(
                  decoded.findFile('manifest.json')!.content as List<int>,
                ),
              )
              as Map<String, dynamic>;
      final path = (manifest['files'] as List).first['path'] as String;
      final corrupt = Archive()
        ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
        ..addFile(ArchiveFile.string('files/$path', 'modified'));
      final archive = File('${folder.path}/corrupt.zip')
        ..writeAsBytesSync(ZipEncoder().encode(corrupt)!);
      await expectLater(
        service.restore(archive),
        throwsA(isA<FormatException>()),
      );
      expect(db.getAllBooks().length, 1);
      expect(
        File(db.getBookById('one')!.filePath!).readAsStringSync(),
        'original',
      );
      (manifest['files'] as List).first['path'] = '../escape';
      final unsafe = Archive()
        ..addFile(ArchiveFile.string('manifest.json', jsonEncode(manifest)))
        ..addFile(ArchiveFile.string('files/../escape', 'original'));
      archive.writeAsBytesSync(ZipEncoder().encode(unsafe)!);
      await expectLater(
        service.restore(archive),
        throwsA(isA<FormatException>()),
      );
      expect(File('${folder.parent.path}/escape').existsSync(), false);
    },
  );
  test(
    'invalid restore references leave the existing library unchanged',
    () async {
      await db.saveBook(book('existing'));
      await expectLater(
        db.importSnapshot({
          'books': [book('bad').toMap()],
          'chapters': [chapter('orphan', 'missing', 0).toMap()],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(db.getBookById('bad'), isNull);
      expect(db.getBookById('existing'), isNotNull);
    },
  );
  test(
    'backup includes source preferences and filters but excludes declared credentials',
    () async {
      final source = 'ext_${List.filled(64, 'a').join()}';
      await SourcePreferences.save(
        source,
        {'2': 'private-password', '3': true},
        secretKeys: ['2'],
      );
      await SourcePreferences.save(source, {'10': 'forest'}, filters: true);
      final service = BackupService();
      final file = await service.create(includeFiles: false);
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final manifest =
          jsonDecode(
                utf8.decode(
                  archive.findFile('manifest.json')!.content as List<int>,
                ),
              )
              as Map;
      final prefs = manifest['preferences'] as Map;
      expect(jsonDecode(prefs['hon_source_settings_$source'] as String), {
        '3': true,
      });
      expect(jsonEncode(manifest), isNot(contains('private-password')));
      await (await SharedPreferences.getInstance()).remove(
        'hon_source_filters_$source',
      );
      await service.restore(file);
      expect(await SourcePreferences.read(source, filters: true), {
        '10': 'forest',
      });
    },
  );
  test(
    'SQL import failure rolls back new rows and reloads the in-memory cache',
    () async {
      await db.saveBook(book('existing'));
      await sql.customStatement(
        "CREATE TRIGGER reject_backup BEFORE INSERT ON books_table WHEN NEW.id = 'reject' BEGIN SELECT RAISE(ABORT, 'test rejection'); END",
      );
      await expectLater(
        db.importSnapshot({
          'books': [book('good').toMap(), book('reject').toMap()],
        }),
        throwsA(anything),
      );
      expect(db.getBookById('good'), isNull);
      expect(db.getBookById('reject'), isNull);
      expect(db.getBookById('existing'), isNotNull);
      expect((await sql.select(sql.booksTable).get()).length, 1);
    },
  );
  test(
    'bulk queue deduplicates and pause/resume keeps work recoverable',
    () async {
      SourceRegistry.instance.setSourceScriptForTesting(
        'fixture',
        "return {getPassage=function(url) return '<p>Saved chapter</p>' end}",
      );
      final novel = book('one');
      await db.saveBook(novel);
      final chapters = [chapter('c1', 'one', 0), chapter('c2', 'one', 1)];
      await db.saveChapters('one', chapters);
      final manager = HonDownloadManager.instance;
      expect(await manager.queueChapters(novel, [...chapters, ...chapters]), 2);
      for (
        var i = 0;
        i < 60 && db.getAllDownloadJobs().any((job) => job.isActive);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(db.getAllDownloadJobs().length, 2);
      expect(
        db.getAllDownloadJobs().every(
          (job) => job.status == DownloadStatus.completed,
        ),
        true,
      );
      expect(await manager.queueChapters(novel, db.getChapters('one')), 0);
      final queued = DownloadJob(
        id: 'paused',
        bookId: 'one',
        chapterId: 'c1',
        chapterTitle: 'One',
        sourceId: 'fixture',
        createdAt: now,
        updatedAt: now,
      );
      await db.enqueueDownload(queued);
      await manager.pauseDownload('paused');
      expect(
        db.getAllDownloadJobs().singleWhere((job) => job.id == 'paused').status,
        DownloadStatus.paused,
      );
      await manager.setWifiOnly(true);
      expect(await manager.wifiOnly, true);
      // Match a metadata-only restore: no destination from the old device.
      await db.saveChapters('one', [chapter('c1', 'one', 0)]);
      await manager.resumeDownload('paused');
      for (
        var i = 0;
        i < 60 &&
            db
                .getAllDownloadJobs()
                .singleWhere((job) => job.id == 'paused')
                .isActive;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(
        db.getAllDownloadJobs().singleWhere((job) => job.id == 'paused').status,
        DownloadStatus.completed,
      );
      final resumed = db
          .getChapters('one')
          .singleWhere((chapter) => chapter.id == 'c1');
      expect(resumed.localFilePath, startsWith('${folder.path}/chapters/'));
      expect(await File(resumed.localFilePath!).exists(), true);
    },
  );

  test(
    'deleteReadChapters and deleteAllDownloadedChapters delete files and reset state',
    () async {
      await db.saveBook(book('novel1'));
      final file0 = File('${folder.path}/chapters/c0.html')
        ..writeAsStringSync('Chapter 0 content');
      final file1 = File('${folder.path}/chapters/c1.html')
        ..writeAsStringSync('Chapter 1 content');
      final file2 = File('${folder.path}/chapters/c2.html')
        ..writeAsStringSync('Chapter 2 content');

      final ch0 = chapter('c0', 'novel1', 0, path: file0.path);
      final ch1 = chapter('c1', 'novel1', 1, path: file1.path);
      final ch2 = chapter('c2', 'novel1', 2, path: file2.path);
      await db.saveChapters('novel1', [ch0, ch1, ch2]);

      expect(file0.existsSync(), isTrue);
      expect(file1.existsSync(), isTrue);
      expect(file2.existsSync(), isTrue);

      final deletedRead = await db.deleteReadChapters('novel1', 2.0);
      expect(deletedRead, 2);
      expect(file0.existsSync(), isFalse);
      expect(file1.existsSync(), isFalse);
      expect(file2.existsSync(), isTrue);

      var updatedChapters = db.getChapters('novel1');
      expect(updatedChapters[0].downloadState, ChapterDownloadState.notDownloaded);
      expect(updatedChapters[0].localFilePath, isNull);
      expect(updatedChapters[1].downloadState, ChapterDownloadState.notDownloaded);
      expect(updatedChapters[1].localFilePath, isNull);
      expect(updatedChapters[2].downloadState, ChapterDownloadState.downloaded);
      expect(updatedChapters[2].localFilePath, file2.path);

      final deletedAll = await db.deleteAllDownloadedChapters('novel1');
      expect(deletedAll, 1);
      expect(file2.existsSync(), isFalse);

      updatedChapters = db.getChapters('novel1');
      expect(
        updatedChapters.every(
          (c) => c.downloadState == ChapterDownloadState.notDownloaded,
        ),
        isTrue,
      );
      expect(updatedChapters.every((c) => c.localFilePath == null), isTrue);
    },
  );
}

