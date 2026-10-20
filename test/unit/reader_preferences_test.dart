import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/app/bootstrap/providers.dart';
import 'package:hon/app/theme/reader_theme.dart';
import 'package:hon/core/database/app_database.dart';
import 'package:hon/core/database/database_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native font changes persist together with typography and theme',
    () async {
      SharedPreferences.setMockInitialValues({});
      final notifier = ReaderPreferencesNotifier();
      notifier.applyNativeTypography({
        'font': 'newYork',
        'lineHeight': 1.8,
        'publisherStyles': true,
      });
      notifier.applyNative(theme: 'quiet', scroll: true, fontSize: 1.25);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      final reopened = ReaderPreferencesNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(reopened.debugState.fontFamily, ReaderFontFamily.newYork);
      expect(reopened.debugState.lineHeight, 1.8);
      expect(reopened.debugState.publisherStyles, isTrue);
      expect(reopened.debugState.themePreset, ReaderThemePreset.quiet);
      notifier.dispose();
      reopened.dispose();
    },
  );

  test(
    'rapid reader changes persist in order and load on a new session',
    () async {
      SharedPreferences.setMockInitialValues({});
      final current = ReaderPreferencesNotifier();
      current.setPreset(ReaderThemePreset.quiet);
      current.setLayoutMode(ReaderLayoutMode.verticalScroll);
      current.setFontSize(24);

      final prefs = await SharedPreferences.getInstance();
      for (var i = 0; i < 20; i++) {
        final raw = prefs.getString('hon_reader_preferences_v1');
        if (raw != null &&
            (jsonDecode(raw) as Map<String, dynamic>)['size'] == 24) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      final saved =
          jsonDecode(prefs.getString('hon_reader_preferences_v1')!)
              as Map<String, dynamic>;
      expect(saved['theme'], 'quiet');
      expect(saved['layout'], 'verticalScroll');
      expect(saved['size'], 24);

      final reopened = ReaderPreferencesNotifier();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(reopened.debugState.themePreset, ReaderThemePreset.quiet);
      expect(reopened.debugState.layoutMode, ReaderLayoutMode.verticalScroll);
      expect(reopened.debugState.fontSize, 24);
      current.dispose();
      reopened.dispose();
    },
  );

  test('change a book font, open another book, assert globals are unchanged', () async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    final db = DatabaseService.instance;
    final appDb = AppDatabase.inMemory();
    await db.init(appDb);

    // 1. Set global defaults
    final notifier = ReaderPreferencesNotifier();
    notifier.setFontFamily(ReaderFontFamily.georgia, explicitGlobal: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // 2. Open bookA and change font to newYork
    notifier.setActiveBookId('bookA');
    notifier.setFontFamily(ReaderFontFamily.newYork);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Assert bookA has newYork
    final bookASettings = db.getBookReaderSettings('bookA');
    expect(bookASettings, isNotNull);
    expect(bookASettings!['font'], 'newYork');

    // 3. Open bookB
    notifier.setActiveBookId('bookB');
    await notifier.loadBookSettings('bookB');
    expect(notifier.debugState.fontFamily, ReaderFontFamily.georgia);

    // Assert globals in SharedPreferences are still georgia
    final prefs = await SharedPreferences.getInstance();
    final rawGlobal = prefs.getString('hon_reader_preferences_v1');
    expect(rawGlobal, isNotNull);
    final globalJson = jsonDecode(rawGlobal!) as Map<String, dynamic>;
    expect(globalJson['font'], 'georgia');

    notifier.dispose();
    await appDb.close();
    DatabaseService.resetForTesting();
  });

  test('reset restores globals while keeping editing scope', () async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    final db = DatabaseService.instance;
    final appDb = AppDatabase.inMemory();
    await db.init(appDb);

    final notifier = ReaderPreferencesNotifier();
    notifier.setPreset(ReaderThemePreset.calm, explicitGlobal: true);
    notifier.setFontFamily(ReaderFontFamily.georgia, explicitGlobal: true);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // Book A override
    notifier.setActiveBookId('bookA');
    notifier.setFontFamily(ReaderFontFamily.palatino);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(db.getBookReaderSettings('bookA')?['font'], 'palatino');

    // Reset applies global defaults to bookA
    await notifier.resetToGlobalDefaults(targetBookId: 'bookA');
    expect(notifier.debugState.fontFamily, ReaderFontFamily.georgia);
    expect(db.getBookReaderSettings('bookA'), isNull);
    expect(notifier.activeBookId, 'bookA');

    // Subsequent edit still scopes to bookA
    notifier.setFontFamily(ReaderFontFamily.baskerville);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(db.getBookReaderSettings('bookA')?['font'], 'baskerville');

    // Global in prefs remains georgia
    final prefs = await SharedPreferences.getInstance();
    final globalJson = jsonDecode(prefs.getString('hon_reader_preferences_v1')!) as Map<String, dynamic>;
    expect(globalJson['font'], 'georgia');

    notifier.dispose();
    await appDb.close();
    DatabaseService.resetForTesting();
  });

  test('queued write after switching books lands on the correct destination', () async {
    SharedPreferences.setMockInitialValues({});
    DatabaseService.resetForTesting();
    final db = DatabaseService.instance;
    final appDb = AppDatabase.inMemory();
    await db.init(appDb);

    final notifier = ReaderPreferencesNotifier();

    // Set bookA and queue a write
    notifier.setActiveBookId('bookA');
    notifier.setFontFamily(ReaderFontFamily.newYork);

    // Immediately switch to bookB and queue a write before the previous async persist completes
    notifier.setActiveBookId('bookB');
    notifier.setFontFamily(ReaderFontFamily.palatino);

    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Both writes landed on their respective captured destinations
    expect(db.getBookReaderSettings('bookA')?['font'], 'newYork');
    expect(db.getBookReaderSettings('bookB')?['font'], 'palatino');

    notifier.dispose();
    await appDb.close();
    DatabaseService.resetForTesting();
  });
}
