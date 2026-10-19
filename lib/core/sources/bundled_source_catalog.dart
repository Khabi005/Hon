import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'extension_repository_service.dart';
import 'installed_extension_service.dart';

/// Offline snapshots of Shosetsu's Universe and documented community catalogs.
/// Lua is loaded only when a source is used, not evaluated during startup.
class BundledSourceCatalog {
  static const marker = 'hon_bundled_shosetsu_catalog_v1';
  static const catalogHashKey = 'hon_bundled_shosetsu_catalog_sha256';

  /// Explicit reinstallation can use the verified snapshot offline. Never
  /// replaces a newer repository version or restores a deliberately removed
  /// source automatically.
  static Future<bool> reinstall(String sourceId, String version) async {
    final catalog = jsonDecode(await rootBundle.loadString('assets/sources/bundled/catalog.json')) as Map<String, dynamic>;
    final match = (catalog['sources'] as List).cast<Map>().where(
      (entry) => entry['sourceId'] == sourceId && entry['version'] == version,
    ).firstOrNull;
    if (match == null) return false;
    await InstalledExtensionService.instance.unmarkRemoved(sourceId);
    await InstalledExtensionService.instance.seedBundled([Map<String, dynamic>.from(match)], rootBundle.loadString);
    return true;
  }

  static Future<void> seed({
    AssetBundle? assets,
    ExtensionRepositoryService? repositories,
    InstalledExtensionService? extensions,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final bundle = assets ?? rootBundle;
    final repoService = repositories ?? ExtensionRepositoryService.instance;
    final extensionService = extensions ?? InstalledExtensionService.instance;
    if (repoService.loadError != null || extensionService.loadError != null) {
      return;
    }
    try {
      final rawCatalog = await bundle.loadString('assets/sources/bundled/catalog.json');
      final catalogHash = sha256.convert(utf8.encode(rawCatalog)).toString();
      if (prefs.getBool(marker) == true && prefs.getString(catalogHashKey) == catalogHash) {
        return;
      }
      final catalog = jsonDecode(rawCatalog) as Map<String, dynamic>;
      final repos = (catalog['repositories'] as List)
          .map(
            (value) => ExtensionRepository.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .toList();
      final sources = (catalog['sources'] as List)
          .map((value) => Map<String, dynamic>.from(value as Map))
          .toList();
      final scriptIconMap = <String, String>{};
      for (final repo in repos) {
        for (final script in repo.scripts) {
          if (script.iconUrl != null && script.iconUrl!.isNotEmpty) {
            scriptIconMap['${repo.id}_${script.id}'] = script.iconUrl!;
            scriptIconMap[script.name] = script.iconUrl!;
          }
        }
      }
      for (final source in sources) {
        final key = '${source['repositoryId']}_${source['scriptId']}';
        final icon = scriptIconMap[key] ?? scriptIconMap[source['name']];
        if (icon != null && (source['imageURL'] == null || (source['imageURL'] as String).isEmpty)) {
          source['imageURL'] = icon;
        }
      }
      await repoService.seedBundled(repos);
      await extensionService.seedBundled(sources, bundle.loadString);
      // Retain the Gutenberg loader for old books, but replace its default
      // activation with the user's requested Shosetsu collection on this upgrade.
      final legacy =
          prefs.getStringList('hon_installed_extensions') ?? <String>[];
      await prefs.setStringList(
        'hon_installed_extensions',
        legacy.where((id) => id != 'gutenberg').toList(),
      );
      await prefs.setString(catalogHashKey, catalogHash);
      if (!await prefs.setBool(marker, true)) {
        throw const FormatException('Could not save bundled catalog state.');
      }
    } catch (error) {
      repoService.loadError =
          'Could not prepare bundled sources: $error. Restart Hon to retry.';
      debugPrint(repoService.loadError);
    }
  }
}
