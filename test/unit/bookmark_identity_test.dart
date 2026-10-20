import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('two bookmarks in one chapter both persist and retain distinct positions', () async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    final dbService = DatabaseService.instance;
    final appDb = AppDatabase.inMemory();
    await dbService.init(appDb);

    const bookId = 'book_multi_bookmark_1';
    final loc1 = jsonEncode({'chapter': 0, 'block': 2, 'offset': 15});
    final loc2 = jsonEncode({'chapter': 0, 'block': 8, 'offset': 42});

    // 1. Add first bookmark in chapter 0
    final added1 = await dbService.toggleBookmark(
      bookId,
      0,
      label: 'Paragraph 2 note',
      locatorString: loc1,
      locatorVersion: '1',
    );
    expect(added1, isTrue);

    // 2. Add second bookmark in same chapter 0 at a different position
    final added2 = await dbService.toggleBookmark(
      bookId,
      0,
      label: 'Paragraph 8 note',
      locatorString: loc2,
      locatorVersion: '1',
    );
    expect(added2, isTrue);

    // 3. Both bookmarks persist
    final bookmarks = dbService.getBookmarks(bookId);
    expect(bookmarks.length, 2);
    expect(bookmarks[0].pageIndex, 0);
    expect(bookmarks[1].pageIndex, 0);
    expect(bookmarks[0].id, isNot(equals(bookmarks[1].id)));

    // Verify positions can be unpacked for navigation
    final b1Loc = jsonDecode(bookmarks.firstWhere((b) => b.label == 'Paragraph 2 note').locatorString!);
    final b2Loc = jsonDecode(bookmarks.firstWhere((b) => b.label == 'Paragraph 8 note').locatorString!);
    expect(b1Loc['block'], 2);
    expect(b1Loc['offset'], 15);
    expect(b2Loc['block'], 8);
    expect(b2Loc['offset'], 42);

    // 4. Toggling loc1 again removes only loc1, keeping loc2
    final removed1 = await dbService.toggleBookmark(
      bookId,
      0,
      locatorString: loc1,
    );
    expect(removed1, isFalse);

    final afterRemoval = dbService.getBookmarks(bookId);
    expect(afterRemoval.length, 1);
    expect(afterRemoval.first.label, 'Paragraph 8 note');

    // 5. Remove loc2 by its specific ID
    await dbService.removeBookmarkById(afterRemoval.first.id);
    expect(dbService.getBookmarks(bookId), isEmpty);

    await appDb.close();
    DatabaseService.resetForTesting();
  });
}
