import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/app/bootstrap/providers.dart';
import 'package:hon/app/theme/reader_theme.dart';
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
}
