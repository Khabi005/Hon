import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:hon/core/models/book.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late AppDatabase db;
  late DatabaseService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    dir = await Directory.systemTemp.createTemp('hon_resume_');
    db = AppDatabase(NativeDatabase(File('${dir.path}/hon.sqlite')));
    service = DatabaseService.instance;
    await service.init(db);
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  test('resume skips the reload unless another connection wrote', () async {
    final now = DateTime.now();
    // The app's own write does not count as external.
    await service.saveBook(
      Book(
        id: 'own',
        title: 'Own write',
        author: 'A',
        description: '',
        format: BookFormat.webNovel,
        createdAt: now,
        updatedAt: now,
      ),
    );
    var notified = 0;
    void listener() => notified++;
    service.libraryChangeNotifier.addListener(listener);
    await service.reloadIfChangedExternally();
    expect(notified, 0);

    // A worker on its own connection commits a row while the app is away.
    final worker = sqlite.sqlite3.open('${dir.path}/hon.sqlite');
    final stamp = now.millisecondsSinceEpoch ~/ 1000;
    worker.execute(
      "INSERT INTO books_table (id, title, author, description, format, "
      "total_chapters, created_at, updated_at) "
      "VALUES ('worker', 'From worker', 'B', '', 'webNovel', 1, $stamp, $stamp)",
    );
    worker.dispose();

    await service.reloadIfChangedExternally();
    expect(notified, greaterThan(0));
    expect(service.getBookById('worker')?.title, 'From worker');

    // Nothing new: the next resume is free again.
    notified = 0;
    await service.reloadIfChangedExternally();
    expect(notified, 0);
    service.libraryChangeNotifier.removeListener(listener);
  });
}
