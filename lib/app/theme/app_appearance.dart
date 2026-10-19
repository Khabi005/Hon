import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppAppearance { standard, liquidGlass }

const appAppearanceKey = 'hon_app_appearance_v1';
final appAppearanceProvider =
    StateNotifierProvider<AppAppearanceNotifier, AppAppearance>((ref) {
      return AppAppearanceNotifier();
    });

class AppAppearanceNotifier extends StateNotifier<AppAppearance> {
  AppAppearanceNotifier() : super(AppAppearance.standard) {
    ready = _load();
  }
  late final Future<void> ready;
  bool _changed = false;
  Future<void> _writes = Future.value();

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted || _changed) return;
    state =
        AppAppearance.values
            .where((value) => value.name == prefs.getString(appAppearanceKey))
            .firstOrNull ??
        AppAppearance.standard;
  }

  Future<void> select(AppAppearance value) {
    _changed = true;
    final operation = _writes.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setString(appAppearanceKey, value.name)) {
        throw StateError('Could not save appearance');
      }
      if (mounted) state = value;
    });
    // A failed write must not prevent the next selection from being saved.
    _writes = operation.catchError((Object _) {});
    return operation;
  }
}
