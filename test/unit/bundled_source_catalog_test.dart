import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hon/core/files/storage_service.dart';
import 'package:hon/core/sources/bundled_source_catalog.dart';
import 'package:hon/core/sources/extension_repository_service.dart';
import 'package:hon/core/sources/installed_extension_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'first install seeds the complete offline catalog and respects later removal',
    () async {
      SharedPreferences.setMockInitialValues({
        'hon_installed_extensions': ['gutenberg'],
      });
      final folder = await Directory.systemTemp.createTemp(
        'hon-bundled-catalog-',
      );
      addTearDown(() => folder.delete(recursive: true));
      StorageService.instance.setBaseDirForTesting(folder);
      final repositories = ExtensionRepositoryService();
      final extensions = InstalledExtensionService();
      await BundledSourceCatalog.seed(
        assets: rootBundle,
        repositories: repositories,
        extensions: extensions,
      );
      expect(repositories.loadError, isNull);
      expect(repositories.repositories.length, 5);
      expect(extensions.installed.length, 172);
      final source = extensions.installed.first;
      expect(await extensions.loadScript(source.sourceId), contains('return'));
      await extensions.setEnabled(source.sourceId, false);
      final removed = extensions.installed[1].sourceId;
      await extensions.uninstall(removed);
      await BundledSourceCatalog.seed(
        assets: rootBundle,
        repositories: repositories,
        extensions: extensions,
      );
      expect(extensions.find(source.sourceId)!.enabled, isFalse);
      expect(extensions.find(removed), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getStringList('hon_installed_extensions'), isEmpty);
      final reopened = InstalledExtensionService();
      await reopened.init();
      expect(reopened.installed.length, 171);
      expect(reopened.find(source.sourceId)!.enabled, isFalse);
    },
  );
}
