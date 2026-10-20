import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/backup/backup_service.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/files/storage_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:hon/core/models/chapter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('hon_backup_edge_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('restoring to a different root with original files absent rewrites img attributes', () async {
    final origRoot = Directory('${tempDir.path}/orig_root')..createSync(recursive: true);
    StorageService.instance.setBaseDirForTesting(origRoot);
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    final sql = AppDatabase.inMemory();
    final db = DatabaseService.instance;
    await db.init(sql);

    // Setup original files
    final pubFile = File('${origRoot.path}/publications/book1.epub')
      ..createSync(recursive: true)
      ..writeAsStringSync('epub-content');
    final imgFile = File('${origRoot.path}/images/illus1.png')
      ..createSync(recursive: true)
      ..writeAsStringSync('png-image-bytes');
    final oldImgUri = Uri.file(imgFile.path).toString();

    final chFile = File('${origRoot.path}/chapters/book1_ch1.html')
      ..createSync(recursive: true)
      ..writeAsStringSync('<p>Chapter text</p><img src="$oldImgUri" data-src="$oldImgUri">');

    final now = DateTime.now();
    await db.saveBook(Book(
      id: 'book_img_1',
      title: 'Book Image 1',
      author: 'Author 1',
      format: BookFormat.epub,
      filePath: pubFile.path,
      totalChapters: 1,
      createdAt: now,
      updatedAt: now,
    ));
    await db.saveChapters('book_img_1', [
      Chapter(
        id: 'ch_img_1',
        bookId: 'book_img_1',
        sourceChapterId: 'ch_img_1',
        chapterIndex: 0,
        title: 'Chapter 1',
        localFilePath: chFile.path,
        downloadState: ChapterDownloadState.downloaded,
        updatedAt: now,
      ),
    ]);

    // Create backup
    final service = BackupService();
    final originalArchive = await service.create(includeFiles: true);
    final savedArchive = File('${tempDir.path}/saved_backup.zip')
      ..writeAsBytesSync(originalArchive.readAsBytesSync());

    // Completely erase original root and database
    await sql.close();
    origRoot.deleteSync(recursive: true);
    expect(origRoot.existsSync(), isFalse);

    // Prepare fresh restored root
    final restoredRoot = Directory('${tempDir.path}/restored_root')..createSync(recursive: true);
    StorageService.instance.setBaseDirForTesting(restoredRoot);
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    final sql2 = AppDatabase.inMemory();
    final db2 = DatabaseService.instance;
    await db2.init(sql2);

    // Restore into fresh environment
    await service.restore(savedArchive);

    final restoredCh = db2.getChapters('book_img_1').first;
    expect(restoredCh.localFilePath, isNotNull);
    final restoredChFile = File(restoredCh.localFilePath!);
    expect(restoredChFile.existsSync(), isTrue);

    final restoredContent = restoredChFile.readAsStringSync();
    // Verify old root URI was replaced
    expect(restoredContent.contains(oldImgUri), isFalse);
    expect(restoredContent.contains(origRoot.path), isFalse);

    // Verify new path points into restoredRoot/images/
    expect(restoredContent.contains('${restoredRoot.path}/images/'), isTrue);

    await sql2.close();
    DatabaseService.resetForTesting();
  });

  test('collection ID remapping preserves memberships when target has same-name collection', () async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    final sql = AppDatabase.inMemory();
    final db = DatabaseService.instance;
    await db.init(sql);

    // Target DB already has "Sci-Fi" collection under a preexisting ID
    final preexistingId = await db.createCollection('Sci-Fi');
    expect(preexistingId, isNotEmpty);

    // Incoming snapshot has a book in a "Sci-Fi" collection under a different legacy ID "legacy_scifi_99"
    final now = DateTime.now();
    final snapshotData = {
      'books': [
        {
          'id': 'book_scifi',
          'title': 'Space Odyssey',
          'author': 'Arthur',
          'format': 'epub',
          'totalChapters': 1,
          'createdAt': now.toIso8601String(),
          'updatedAt': now.toIso8601String(),
        }
      ],
      'library': [
        {
          'bookId': 'book_scifi',
          'isInLibrary': true,
          'dateAdded': now.toIso8601String(),
          'collectionIds': ['legacy_scifi_99'],
        }
      ],
      'collections': {
        'legacy_scifi_99': 'Sci-Fi',
      },
    };

    await db.importSnapshot(snapshotData);

    // Verify that the collection ID was remapped to the preexisting collection ID
    final entry = db.getLibraryEntry('book_scifi');
    expect(entry, isNotNull);
    expect(entry!.collectionIds, contains(preexistingId));
    expect(entry.collectionIds, isNot(contains('legacy_scifi_99')));

    // Only one "Sci-Fi" collection should exist
    expect(db.collections.values.where((name) => name == 'Sci-Fi').length, 1);
    expect(db.collections[preexistingId], 'Sci-Fi');

    await sql.close();
    DatabaseService.resetForTesting();
  });
}
