import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/hon_app.dart';
import 'core/database/database_service.dart';
import 'core/downloads/hon_download_manager.dart';
import 'core/files/storage_service.dart';
import 'core/native/readium_reader_service.dart';
import 'core/sources/source_registry.dart';
import 'core/sources/bundled_source_catalog.dart';
import 'core/sources/extension_repository_service.dart';
import 'core/sources/installed_extension_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    final notice = await rootBundle.loadString(
      'assets/legal/shosetsu-NOTICE.txt',
    );
    final license = await rootBundle.loadString(
      'assets/legal/shosetsu-LICENSE.txt',
    );
    yield LicenseEntryWithLineBreaks([
      'Shosetsu kotlin-lib',
    ], '$notice\n\n$license');
  });

  LicenseRegistry.addLicense(() async* {
    for (final family in [
      'newsreader',
      'literata',
      'lora',
      'librebaskerville',
    ]) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/legal/$family-OFL.txt'));
    }
    yield LicenseEntryWithLineBreaks([
      'Shosetsu source catalog',
    ], await rootBundle.loadString('assets/legal/source-catalog-NOTICES.txt'));
  });

  // Edge-to-edge transparent system navigation
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
    ),
  );

  // Initialize core application services
  await StorageService.instance.init();
  await Future.wait([
    DatabaseService.instance.init(),
    ExtensionRepositoryService.instance.init(),
    InstalledExtensionService.instance.init(),
  ]);
  await SourceRegistry.instance.init();
  ReadiumReaderService.initialize();

  // Recover interrupted downloads from previous sessions via WorkManager
  HonDownloadManager.instance.init();
  SourceRegistry.instance.setPreparing(true);
  runApp(const ProviderScope(child: HonApp()));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_finishStartup());
  });
}

Future<void> _finishStartup() async {
  try {
    await BundledSourceCatalog.seed();
    await SourceRegistry.instance.init();
    await HonDownloadManager.instance.recoverInterruptedDownloads();
  } catch (error) {
    debugPrint('Could not complete source/download preparation: $error');
  } finally {
    SourceRegistry.instance.setPreparing(false);
  }
  await DatabaseService.instance.repairMissingEpubCovers();
}
