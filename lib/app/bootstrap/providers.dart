import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/database/database_service.dart';
import '../../core/files/storage_service.dart';
import '../../core/models/book.dart';
import '../../core/models/download_job.dart';
import '../theme/reader_theme.dart';

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

final databaseChangeProvider = StateNotifierProvider<DatabaseNotifier, int>((ref) {
  return DatabaseNotifier();
});

final libraryBooksProvider = Provider<List<Book>>((ref) {
  ref.watch(databaseChangeProvider);
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
  ReaderPreferencesNotifier() : super(const ReaderPreferencesState());

  void setPreset(ReaderThemePreset preset) {
    state = state.copyWith(themePreset: preset);
  }

  void setLayoutMode(ReaderLayoutMode mode) {
    state = state.copyWith(layoutMode: mode);
  }

  void setFontFamily(ReaderFontFamily family) {
    state = state.copyWith(fontFamily: family);
  }

  void setFontSize(double size) {
    state = state.copyWith(fontSize: size.clamp(12.0, 32.0));
  }

  void increaseFontSize() {
    setFontSize(state.fontSize + 1.5);
  }

  void decreaseFontSize() {
    setFontSize(state.fontSize - 1.5);
  }

  void setLineHeight(double height) {
    state = state.copyWith(lineHeight: height.clamp(1.2, 2.5));
  }

  void setBrightness(double b) {
    state = state.copyWith(brightness: b.clamp(0.1, 1.0));
  }

  void toggleJustified() {
    state = state.copyWith(isJustified: !state.isJustified);
  }
}

final readerPreferencesProvider =
    StateNotifierProvider<ReaderPreferencesNotifier, ReaderPreferencesState>((ref) {
  return ReaderPreferencesNotifier();
});
