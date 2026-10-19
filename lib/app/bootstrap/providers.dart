import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/database/database_service.dart';
import '../../core/files/storage_service.dart';
import '../../core/models/book.dart';
import '../../core/models/download_job.dart';
import '../theme/reader_theme.dart';

// Shared so Home shortcuts select the existing tab rather than stacking copies.
final navigationTabProvider = StateProvider<int>((ref) => 0);

final databaseServiceProvider = Provider<DatabaseService>((ref) {
  return DatabaseService.instance;
});

final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService.instance;
});

class DatabaseNotifier extends StateNotifier<int> {
  DatabaseNotifier() : super(0) {
    DatabaseService.instance.changeNotifier.addListener(_onChange);
  }

  void _onChange() {
    state++;
  }

  @override
  void dispose() {
    DatabaseService.instance.changeNotifier.removeListener(_onChange);
    super.dispose();
  }
}

final databaseChangeProvider = StateNotifierProvider<DatabaseNotifier, int>((
  ref,
) {
  return DatabaseNotifier();
});

class LibraryNotifier extends StateNotifier<int> {
  LibraryNotifier() : super(0) {
    DatabaseService.instance.libraryChangeNotifier.addListener(_onChange);
  }
  void _onChange() { state++; }
  @override
  void dispose() {
    DatabaseService.instance.libraryChangeNotifier.removeListener(_onChange);
    super.dispose();
  }
}
final libraryChangeProvider = StateNotifierProvider<LibraryNotifier, int>((ref) => LibraryNotifier());

final libraryBooksProvider = Provider<List<Book>>((ref) {
  ref.watch(libraryChangeProvider);
  return DatabaseService.instance.getLibraryBooks();
});

final continueReadingProvider = Provider<List<Book>>((ref) {
  ref.watch(databaseChangeProvider);
  return DatabaseService.instance.getContinueReadingBooks();
});

final allDownloadJobsProvider = Provider<List<DownloadJob>>((ref) {
  ref.watch(databaseChangeProvider);
  return DatabaseService.instance.getAllDownloadJobs();
});

final activeDownloadsCountProvider = Provider<int>((ref) {
  final jobs = ref.watch(allDownloadJobsProvider);
  return jobs.where((j) => j.isActive).length;
});

class ReaderPreferencesNotifier extends StateNotifier<ReaderPreferencesState> {
  static const _storageKey = 'hon_reader_preferences_v1';
  String? _activeBookId;
  bool _dirty = false;
  Future<void> _pendingWrite = Future<void>.value();

  String? get activeBookId => _activeBookId;

  void setActiveBookId(String? bookId) {
    _activeBookId = bookId;
  }

  ReaderPreferencesNotifier() : super(const ReaderPreferencesState()) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null || _dirty || !mounted) return;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      T pick<T extends Enum>(List<T> values, String key, T fallback) =>
          values.where((value) => value.name == json[key]).firstOrNull ??
          fallback;
      state = state.copyWith(
        themePreset: pick(ReaderThemePreset.values, 'theme', state.themePreset),
        layoutMode: pick(ReaderLayoutMode.values, 'layout', state.layoutMode),
        fontFamily: pick(ReaderFontFamily.values, 'font', state.fontFamily),
        fontSize: (json['size'] as num?)?.toDouble(),
        lineHeight: (json['lineHeight'] as num?)?.toDouble(),
        horizontalMargin: (json['margin'] as num?)?.toDouble(),
        paragraphSpacing: (json['paragraphSpacing'] as num?)?.toDouble(),
        textIndent: (json['indent'] as num?)?.toDouble(),
        isJustified: json['justified'] as bool?,
        brightness: (json['brightness'] as num?)?.toDouble(),
        publisherStyles: json['publisherStyles'] as bool?,
      );
    } catch (_) {
      // Keep defaults when a prior preference payload is invalid.
    }
  }

  void _set(ReaderPreferencesState next, {String? targetBookId}) {
    _dirty = true;
    state = next;
    final destinationBookId = targetBookId ?? _activeBookId;
    _pendingWrite = _pendingWrite
        .then((_) => _persist(next, targetBookId: destinationBookId))
        .catchError(
          (Object error) =>
              debugPrint('Could not save reader preferences: $error'),
        );
  }

  Future<void> _persist(
    ReaderPreferencesState snapshot, {
    String? targetBookId,
  }) async {
    if (targetBookId != null) {
      await DatabaseService.instance.saveBookReaderSettings(
        targetBookId,
        snapshot.toMap(),
      );
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode(snapshot.toMap()),
    );
  }

  void setPreset(ReaderThemePreset preset) {
    _set(state.copyWith(themePreset: preset));
  }

  void setLayoutMode(ReaderLayoutMode mode) {
    _set(state.copyWith(layoutMode: mode));
  }

  void setFontFamily(ReaderFontFamily family) {
    _set(state.copyWith(fontFamily: family, publisherStyles: false));
  }

  void setFontSize(double size) {
    _set(state.copyWith(fontSize: size.clamp(12.0, 32.0)));
  }

  void increaseFontSize() {
    setFontSize(state.fontSize + 1.5);
  }

  void decreaseFontSize() {
    setFontSize(state.fontSize - 1.5);
  }

  void setLineHeight(double height) {
    _set(state.copyWith(lineHeight: height.clamp(1.2, 2.5)));
  }

  void setHorizontalMargin(double value) =>
      _set(state.copyWith(horizontalMargin: value.clamp(8.0, 48.0)));
  void setParagraphSpacing(double value) =>
      _set(state.copyWith(paragraphSpacing: value.clamp(0.0, 32.0)));
  void setTextIndent(double value) =>
      _set(state.copyWith(textIndent: value.clamp(0.0, 64.0)));

  void setBrightness(double b) {
    _set(state.copyWith(brightness: b.clamp(0.1, 1.0)));
  }

  void toggleJustified() {
    _set(state.copyWith(isJustified: !state.isJustified));
  }

  void applyNative({
    required String theme,
    required bool scroll,
    required double fontSize,
    String? bookId,
  }) {
    final preset = ReaderThemePreset.values
        .where((p) => p.name == theme)
        .firstOrNull;
    if (bookId != null && bookId != _activeBookId) {
      _activeBookId = bookId;
    }
    _set(
      state.copyWith(
        themePreset: preset ?? state.themePreset,
        layoutMode: scroll
            ? ReaderLayoutMode.verticalScroll
            : ReaderLayoutMode.paginated,
        fontSize: (fontSize * 18.0).clamp(12.0, 32.0),
      ),
      targetBookId: bookId ?? _activeBookId,
    );
  }

  void applyNativeTypography(
    Map<String, dynamic> values, {
    String? bookId,
  }) {
    if (bookId != null && bookId != _activeBookId) {
      _activeBookId = bookId;
    }
    _set(
      state.copyWith(
        fontFamily: ReaderFontFamily.values
            .where((font) => font.name == values['font'])
            .firstOrNull,
        lineHeight: (values['lineHeight'] as num?)?.toDouble().clamp(1.3, 2.2),
        horizontalMargin: (values['margin'] as num?)?.toDouble().clamp(
          8.0,
          64.0,
        ),
        paragraphSpacing: (values['paragraphSpacing'] as num?)
            ?.toDouble()
            .clamp(0.0, 32.0),
        textIndent: (values['indent'] as num?)?.toDouble().clamp(0.0, 64.0),
        isJustified: values['justified'] as bool?,
        brightness: (values['brightness'] as num?)?.toDouble().clamp(0.1, 1.0),
        publisherStyles: values['publisherStyles'] as bool?,
      ),
      targetBookId: bookId ?? _activeBookId,
    );
  }

  void setPublisherStyles(bool enabled) {
    _set(state.copyWith(publisherStyles: enabled));
  }

  void loadFromState(ReaderPreferencesState next, {String? bookId}) {
    _activeBookId = bookId;
    _set(next, targetBookId: bookId);
  }

  Future<void> reloadDefaults({String? preserveBookId}) async {
    _activeBookId = preserveBookId;
    _dirty = false;
    state = const ReaderPreferencesState();
    await _load();
    if (preserveBookId != null) {
      _activeBookId = preserveBookId;
    }
  }
}

final readerPreferencesProvider =
    StateNotifierProvider<ReaderPreferencesNotifier, ReaderPreferencesState>((
      ref,
    ) {
      return ReaderPreferencesNotifier();
    });
