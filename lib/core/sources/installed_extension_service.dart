import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../files/storage_service.dart';
import 'bundled_source_catalog.dart';
import 'extension_repository_service.dart';
import 'native_shosetsu_bridge.dart';

class InstalledExtension {
  final String sourceId;
  final String repositoryId;
  final String repositoryUrl;
  final String scriptId;
  final String name;
  final String language;
  final String version;
  final String scriptPath;
  final bool enabled;
  final List<String> allowedHosts;
  final String? iconUrl;

  const InstalledExtension({
    required this.sourceId,
    required this.repositoryId,
    required this.repositoryUrl,
    required this.scriptId,
    required this.name,
    required this.language,
    required this.version,
    required this.scriptPath,
    this.enabled = true,
    this.allowedHosts = const [],
    this.iconUrl,
  });

  InstalledExtension copyWith({
    bool? enabled,
    List<String>? allowedHosts,
    String? iconUrl,
  }) => InstalledExtension(
    sourceId: sourceId,
    repositoryId: repositoryId,
    repositoryUrl: repositoryUrl,
    scriptId: scriptId,
    name: name,
    language: language,
    version: version,
    scriptPath: scriptPath,
    enabled: enabled ?? this.enabled,
    allowedHosts: allowedHosts ?? this.allowedHosts,
    iconUrl: iconUrl ?? this.iconUrl,
  );

  Map<String, dynamic> toJson() => {
    'sourceId': sourceId,
    'repositoryId': repositoryId,
    'repositoryUrl': repositoryUrl,
    'scriptId': scriptId,
    'name': name,
    'language': language,
    'version': version,
    'scriptPath': scriptPath,
    'enabled': enabled,
    'allowedHosts': allowedHosts,
    if (iconUrl != null) 'iconUrl': iconUrl,
  };

  factory InstalledExtension.fromJson(Map<String, dynamic> json) =>
      InstalledExtension(
        sourceId: json['sourceId'] as String,
        repositoryId: json['repositoryId'] as String,
        repositoryUrl: json['repositoryUrl'] as String,
        scriptId: json['scriptId'] as String,
        name: json['name'] as String,
        language: json['language'] as String,
        version: json['version'] as String,
        scriptPath: json['scriptPath'] as String,
        enabled: json['enabled'] as bool? ?? true,
        allowedHosts: json['allowedHosts'] != null
            ? List<String>.from(json['allowedHosts'] as List)
            : const [],
        iconUrl: (json['iconUrl'] ?? json['imageURL']) as String?,
      );
}

class InstalledExtensionService extends ChangeNotifier {
  static final InstalledExtensionService instance = InstalledExtensionService();
  static const _storageKey = 'hon_installed_repository_extensions_v1';
  static const _removedStorageKey = 'hon_removed_sources_v1';
  final http.Client _client;
  final List<InstalledExtension> _installed = [];
  final Set<String> _removedSourceIds = {};
  String? loadError;

  InstalledExtensionService({http.Client? client})
    : _client = client ?? http.Client();

  List<InstalledExtension> get installed => List.unmodifiable(_installed);
  Set<String> get removedSourceIds => Set.unmodifiable(_removedSourceIds);
  bool isRemoved(String sourceId) => _removedSourceIds.contains(sourceId);

  Future<void> unmarkRemoved(String sourceId) async {
    if (_removedSourceIds.remove(sourceId)) {
      await _persistRemoved();
    }
  }

  InstalledExtension? find(String sourceId) {
    for (final extension in _installed) {
      if (extension.sourceId == sourceId) return extension;
    }
    return null;
  }

  String sourceIdFor(ExtensionRepository repo, RepositoryScript script) =>
      'ext_${sha256.convert(utf8.encode('${repo.id}:${script.language}:${script.id}'))}';

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final removedRaw = prefs.getStringList(_removedStorageKey);
    if (removedRaw != null) {
      _removedSourceIds.addAll(removedRaw);
    }
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      await _recoverInterruptedOperations();
      return;
    }
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      final parsed = values
          .map(
            (value) => InstalledExtension.fromJson(
              Map<String, dynamic>.from(value as Map),
            ),
          )
          .where(
            (extension) =>
                RegExp(r'^ext_[0-9a-f]{64}$').hasMatch(extension.sourceId) &&
                extension.scriptPath ==
                    p.join(
                      StorageService.instance.baseDir.path,
                      'extensions',
                      '${extension.sourceId}.lua',
                    ),
          )
          .toList();
      _installed
        ..clear()
        ..addAll(parsed);
      await _recoverInterruptedOperations();
      notifyListeners();
    } catch (error) {
      loadError = 'Could not read saved extensions: $error';
      debugPrint(loadError);
    }
  }

  Future<InstalledExtension> install(
    ExtensionRepository repo,
    RepositoryScript script,
  ) async {
    if (script.libraryVersion.isNotEmpty &&
        !script.libraryVersion.startsWith('1.')) {
      throw FormatException(
        'Unsupported Shosetsu library API ${script.libraryVersion}; Hon supports 1.x.',
      );
    }
    final sourceId = sourceIdFor(repo, script);
    // Reuse verified bundled snapshot when versions match without a network request
    if (await BundledSourceCatalog.reinstall(sourceId, script.version)) {
      final installedBundled = find(sourceId);
      if (installedBundled != null) return installedBundled;
    }
    final fileName = script.fileName.endsWith('.lua')
        ? script.fileName
        : '${script.fileName}.lua';
    final uri = Uri.parse(repo.url).resolve('src/${script.language}/$fileName');
    final bytes = await _fetchBytes(uri, 512 * 1024);
    final expected = script.checksum?.trim().toLowerCase();
    final digest = expected?.length == 64 ? sha256 : md5;
    if (expected != null &&
        expected.isNotEmpty &&
        digest.convert(bytes).toString() != expected) {
      throw const FormatException(
        'Extension checksum does not match the repository index.',
      );
    }
    final source = utf8.decode(bytes);
    final libraries = <String, String>{};
    final loading = <String>{};
    final requirePattern = RegExp(
      r'''Require\s*\(\s*['"]([A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*)['"]\s*\)''',
    );
    List<String> dependencies(String text) {
      final header = RegExp(
        r'^\s*--\s*(\{[^\n]+\})',
      ).firstMatch(text)?.group(1);
      if (header == null) return const [];
      try {
        final metadata = jsonDecode(header) as Map<String, dynamic>;
        final api = metadata['libVer']?.toString();
        if (api != null && !api.startsWith('1.')) {
          throw FormatException('Unsupported Shosetsu library API $api.');
        }
        return (metadata['dep'] as List<dynamic>? ?? const [])
            .map((entry) => entry.toString())
            .toList();
      } on FormatException {
        rethrow;
      } catch (_) {
        throw const FormatException('Invalid extension dependency metadata.');
      }
    }

    Future<void> loadDependency(String requirement) async {
      final match = RegExp(
        r'^([A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*)(?:>=(\d+(?:\.\d+)*))?$',
      ).firstMatch(requirement);
      if (match == null) {
        throw FormatException('Unsupported library requirement: $requirement');
      }
      final name = match.group(1)!;
      if ((name == 'FilterOptions' || name == 'url') &&
          !repo.libraries.containsKey(name)) {
        return;
      }
      final available = repo.libraries[name];
      // Nested helper modules are referenced by a declared library, and stay
      // inside this repository's lib directory. They have no index version.
      if (available == null && !name.contains('/')) {
        throw FormatException(
          'Repository does not provide required library $name.',
        );
      }
      final minimum = match.group(2);
      if (minimum != null &&
          (available == null || _compareVersions(available, minimum) < 0)) {
        throw FormatException(
          '$name requires $minimum or newer; repository provides $available.',
        );
      }
      if (libraries.containsKey(name)) return;
      if (!loading.add(name)) {
        throw FormatException('Circular library dependency: $name');
      }
      if (libraries.length + loading.length > 24) {
        throw const FormatException('Extension has too many libraries.');
      }
      final library = utf8.decode(
        await _fetchBytes(
          Uri.parse(repo.url).resolve('lib/$name.lua'),
          512 * 1024,
        ),
      );
      for (final dependency in {
        ...dependencies(library),
        ...requirePattern.allMatches(library).map((match) => match.group(1)!),
      }) {
        await loadDependency(dependency);
      }
      libraries[name] = library;
      loading.remove(name);
    }

    for (final dependency in {
      ...script.dependencies,
      ...dependencies(source),
      ...requirePattern.allMatches(source).map((match) => match.group(1)!),
    }) {
      await loadDependency(dependency);
    }
    final bundle = libraries.isEmpty
        ? source
        : _bundle(repo, source, libraries);
    final bundleBytes = utf8.encode(bundle);
    if (bundleBytes.length > 2 * 1024 * 1024) {
      throw const FormatException('Extension with libraries exceeds 2 MB.');
    }
    final prior = find(sourceId);
    final initialAllowedHosts = <String>{};
    if (prior != null) {
      initialAllowedHosts.addAll(prior.allowedHosts);
    }
    initialAllowedHosts.addAll(script.allowedHosts);
    final match = RegExp(r'''baseURL\s*=\s*["']([^"']+)["']''').firstMatch(source);
    final scriptBaseUrl = match?.group(1);
    final scriptBaseHost = scriptBaseUrl != null ? Uri.tryParse(scriptBaseUrl)?.host : null;
    if (scriptBaseHost != null && scriptBaseHost.isNotEmpty) {
      initialAllowedHosts.add(scriptBaseHost);
    }
    if (await NativeShosetsuBridge.instance.isSupported()) {

      await NativeShosetsuBridge.instance.validateExtension(
        bundle,
        allowedHosts: initialAllowedHosts.toList(),
        baseUrl: scriptBaseUrl,
      );
    }

    final directory = Directory(
      p.join(StorageService.instance.baseDir.path, 'extensions'),
    );
    await directory.create(recursive: true);
    final target = File(p.join(directory.path, '$sourceId.lua'));
    final temporary = File('${target.path}.new');
    final backup = File('${target.path}.old');
    final journal = File('${target.path}.pending');
    final priorFile = File(
      prior?.enabled == false ? '${target.path}.disabled' : target.path,
    );
    await temporary.writeAsBytes(bundleBytes, flush: true);
    await journal.writeAsString(
      jsonEncode({
        'sourceId': sourceId,
        'version': script.version,
        'hadPrior': prior != null,
      }),
      flush: true,
    );
    try {
      if (backup.existsSync()) await backup.delete();
      if (priorFile.existsSync()) await priorFile.rename(backup.path);
      await temporary.rename(target.path);
      if (prior?.enabled == false) {
        await target.rename('${target.path}.disabled');
      }
      final extension = InstalledExtension(
        sourceId: sourceId,
        repositoryId: repo.id,
        repositoryUrl: repo.url,
        scriptId: script.id,
        name: script.name,
        language: script.language,
        version: script.version,
        scriptPath: target.path,
        enabled: prior?.enabled ?? true,
        allowedHosts: {
          ...initialAllowedHosts,
          if (prior != null) ...prior.allowedHosts,
        }.toList()
          ..sort(),
        iconUrl: script.iconUrl ?? prior?.iconUrl,
      );
      _installed.removeWhere((item) => item.sourceId == sourceId);
      _installed.add(extension);
      _removedSourceIds.remove(sourceId);
      await _persist();
      await _persistRemoved();
      // The persisted catalog is the commit point. Cleanup can be retried on
      // startup and must not roll back an already committed installation.
      try {
        if (backup.existsSync()) await backup.delete();
        if (journal.existsSync()) await journal.delete();
      } on FileSystemException catch (error) {
        debugPrint('Extension cleanup deferred: $error');
      }
      notifyListeners();
      return extension;
    } catch (_) {
      if (target.existsSync()) await target.delete();
      if (backup.existsSync()) await backup.rename(priorFile.path);
      if (temporary.existsSync()) await temporary.delete();
      if (journal.existsSync()) await journal.delete();
      _installed.removeWhere((item) => item.sourceId == sourceId);
      if (prior != null) _installed.add(prior);
      rethrow;
    }
  }

  /// Installs the app's bundled scripts once. Subsequent updates never undo a
  /// user's disable/remove choice or replace an installed repository update.
  Future<void> seedBundled(
    List<Map<String, dynamic>> sources,
    Future<String> Function(String asset) loadAsset,
  ) async {
    final previous = _installed.toList();
    final directory = Directory(
      p.join(StorageService.instance.baseDir.path, 'extensions'),
    );
    await directory.create(recursive: true);
    for (final source in sources) {
      final id = source['sourceId'] as String;
      if (!RegExp(r'^ext_[0-9a-f]{64}$').hasMatch(id)) {
        throw const FormatException('Invalid bundled source identity.');
      }
      if (_removedSourceIds.contains(id)) {
        // Preserves deliberate user removal across catalog hash changes / app upgrades.
        continue;
      }
      final existing = find(id);
      if (existing != null) {
        final catalogHosts = <String>{
          if (source['allowedHosts'] is List)
            ...(source['allowedHosts'] as List)
                .map((e) => e.toString().trim())
                .where((e) => e.isNotEmpty),
        }..remove('');
        final merged = {...existing.allowedHosts, ...catalogHosts}.toList()..sort();
        final icon = source['imageURL'] as String?;
        if (merged.length != existing.allowedHosts.length || (existing.iconUrl == null && icon != null)) {
          final index = _installed.indexWhere((e) => e.sourceId == id);
          if (index != -1) {
            _installed[index] = existing.copyWith(
              allowedHosts: merged,
              iconUrl: existing.iconUrl ?? icon,
            );
          }
        }
        continue;
      }
      final text = await loadAsset(source['asset'] as String);
      if (sha256.convert(utf8.encode(text)).toString() != source['sha256']) {
        throw FormatException(
          'Bundled script integrity failed: ${source['name']}',
        );
      }
      final target = File(p.join(directory.path, '$id.lua'));
      final staging = File('${target.path}.new');
      await staging.writeAsString(text, flush: true);
      await staging.rename(target.path);
      final initialAllowedHosts = <String>{};
      if (source['allowedHosts'] is List) {
        initialAllowedHosts.addAll(
          (source['allowedHosts'] as List)
              .map((e) => e.toString().trim())
              .where((e) => e.isNotEmpty),
        );
      }

      _installed.add(
        InstalledExtension(
          sourceId: id,
          repositoryId: source['repositoryId'] as String,
          repositoryUrl: source['repositoryUrl'] as String,
          scriptId: source['scriptId'] as String,
          name: source['name'] as String,
          language: source['language'] as String,
          version: source['version'] as String,
          scriptPath: target.path,
          allowedHosts: initialAllowedHosts.toList()..sort(),
          iconUrl: source['imageURL'] as String?,
        ),
      );
    }
    try {
      await _persist();
    } catch (_) {
      _installed
        ..clear()
        ..addAll(previous);
      rethrow;
    }
    notifyListeners();
  }

  Future<void> setEnabled(String sourceId, bool enabled) async {
    final current = find(sourceId);
    if (current == null) {
      throw const FormatException('Extension is not installed.');
    }
    if (current.enabled == enabled) return;
    final active = File(current.scriptPath);
    final inactive = File('${current.scriptPath}.disabled');
    final from = enabled ? inactive : active;
    final to = enabled ? active : inactive;
    if (!from.existsSync()) {
      throw const FileSystemException('Installed extension script is missing.');
    }
    await from.rename(to.path);
    final index = _installed.indexOf(current);
    _installed[index] = current.copyWith(enabled: enabled);
    try {
      await _persist();
      notifyListeners();
    } catch (_) {
      _installed[index] = current;
      await to.rename(from.path);
      rethrow;
    }
  }

  Future<void> updateAllowedHosts(String sourceId, List<String> hosts) async {
    final current = find(sourceId);
    if (current == null) {
      throw const FormatException('Extension is not installed.');
    }
    final index = _installed.indexOf(current);
    final cleanHosts = hosts
        .map((h) => h.trim().toLowerCase())
        .where((h) => h.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    _installed[index] = current.copyWith(allowedHosts: cleanHosts);
    try {
      await _persist();
      notifyListeners();
    } catch (_) {
      _installed[index] = current;
      rethrow;
    }
  }

  Future<void> uninstall(String sourceId) async {
    final current = find(sourceId);
    if (current == null) return;
    final file = File(
      current.enabled ? current.scriptPath : '${current.scriptPath}.disabled',
    );
    final staged = File('${current.scriptPath}.removing');
    if (staged.existsSync()) await staged.delete();
    if (file.existsSync()) await file.rename(staged.path);
    _installed.remove(current);
    _removedSourceIds.add(sourceId);
    try {
      await _persist();
      await _persistRemoved();
      try {
        if (staged.existsSync()) await staged.delete();
      } on FileSystemException catch (error) {
        debugPrint('Extension cleanup deferred: $error');
      }
      notifyListeners();
    } catch (_) {
      _installed.add(current);
      _removedSourceIds.remove(sourceId);
      if (staged.existsSync()) await staged.rename(file.path);
      rethrow;
    }
  }

  Future<String> loadScript(String sourceId) async {
    final extension = find(sourceId);
    if (extension == null || !extension.enabled) {
      throw const FormatException('Extension is not installed or is disabled.');
    }
    final file = File(extension.scriptPath);
    if (!file.existsSync()) {
      throw const FileSystemException('Installed extension script is missing.');
    }
    return file.readAsString();
  }

  Future<void> _recoverInterruptedOperations() async {
    final directory = Directory(
      p.join(StorageService.instance.baseDir.path, 'extensions'),
    );
    if (!directory.existsSync()) return;
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !entry.path.endsWith('.pending')) continue;
      final name = p.basename(entry.path);
      if (!RegExp(r'^ext_[0-9a-f]{64}\.lua\.pending$').hasMatch(name)) continue;
      final journal =
          jsonDecode(await entry.readAsString()) as Map<String, dynamic>;
      final sourceId = name.substring(0, name.length - '.lua.pending'.length);
      final current = find(sourceId);
      final target = File(p.join(directory.path, '$sourceId.lua'));
      final old = File('${target.path}.old');
      if (current?.version != journal['version']) {
        // An uncommitted first install can be removed. A failed update keeps
        // its previous file even if the process died before moving it aside.
        if (old.existsSync()) {
          if (target.existsSync()) await target.delete();
          await old.rename(
            current?.enabled == false ? '${target.path}.disabled' : target.path,
          );
        } else if (journal['hadPrior'] != true && target.existsSync()) {
          await target.delete();
        }
      } else if (old.existsSync()) {
        await old.delete();
      }
      final temporary = File('${target.path}.new');
      if (temporary.existsSync()) await temporary.delete();
      await entry.delete();
    }
    for (final extension in _installed) {
      final expected = File(
        extension.enabled
            ? extension.scriptPath
            : '${extension.scriptPath}.disabled',
      );
      final alternate = File(
        extension.enabled
            ? '${extension.scriptPath}.disabled'
            : extension.scriptPath,
      );
      final removing = File('${extension.scriptPath}.removing');
      if (!expected.existsSync()) {
        if (removing.existsSync()) {
          await removing.rename(expected.path);
        } else if (alternate.existsSync()) {
          await alternate.rename(expected.path);
        }
      }
    }
  }

  static int _compareVersions(String a, String b) {
    final first = a.split('.').map(int.tryParse).map((n) => n ?? 0).toList();
    final second = b.split('.').map(int.tryParse).map((n) => n ?? 0).toList();
    for (var i = 0; i < first.length || i < second.length; i++) {
      final comparison = (i < first.length ? first[i] : 0).compareTo(
        i < second.length ? second[i] : 0,
      );
      if (comparison != 0) return comparison;
    }
    return 0;
  }

  Future<List<int>> _fetchBytes(Uri uri, int limit) async {
    final response = await _client
        .send(http.Request('GET', uri)..followRedirects = false)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.request?.url.scheme != 'https') {
      throw FormatException(
        'Extension resource returned HTTP ${response.statusCode}.',
      );
    }
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > limit) {
        throw const FormatException(
          'Extension resource exceeds its size limit.',
        );
      }
    }
    if (bytes.isEmpty) {
      throw const FormatException('Extension resource is empty.');
    }
    return bytes;
  }

  String _bundle(
    ExtensionRepository repo,
    String source,
    Map<String, String> libraries,
  ) {
    // Keep upstream source and license comments verbatim inside lexical loaders.
    // Require can only access installed modules; no file, Java or dynamic loader.
    return [
      '-- Installed from ${repo.url} ; licenses/notices: ${repo.url}LICENSE',
      'local __modules, __loaded, __loading = {}, {}, {}',
      'local __builtin = Require',
      'local function Require(name)',
      '  if __loaded[name] ~= nil then return __loaded[name] end',
      '  if not __modules[name] then return __builtin(name) end',
      '  if __loading[name] then error("Circular library dependency: " .. name) end',
      '  __loading[name] = true',
      '  local value = __modules[name]()',
      '  if value == nil then value = true end',
      '  __loaded[name], __loading[name] = value, nil',
      '  return value',
      'end',
      for (final entry in libraries.entries)
        '__modules["${entry.key}"] = function()\n${entry.value}\nend',
      'return (function()\n$source\nend)()',
    ].join('\n');
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _storageKey,
      jsonEncode(_installed.map((item) => item.toJson()).toList()),
    );
    if (!saved) {
      throw const FileSystemException('Could not save installed extensions.');
    }
  }

  Future<void> _persistRemoved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_removedStorageKey, _removedSourceIds.toList());
  }
}
