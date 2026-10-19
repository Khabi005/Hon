import 'bundled_source_catalog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/novel_source.dart';
import 'lua/shosetsu_lua_engine.dart';
import 'native_shosetsu_bridge.dart';
import 'extension_repository_service.dart';
import 'installed_extension_service.dart';
import 'source_preferences.dart';

class ExtensionMeta {
  final String id;
  final String name;
  final String lang;
  final String version;
  final String description;
  final bool isInstalled;
  final bool isEnabled;
  final String? repositoryId;
  final String? iconUrl;

  const ExtensionMeta({
    required this.id,
    required this.name,
    required this.lang,
    required this.version,
    required this.description,
    this.isInstalled = false,
    this.isEnabled = true,
    this.repositoryId,
    this.iconUrl,
  });

  ExtensionMeta copyWith({bool? isInstalled, bool? isEnabled, String? iconUrl}) {
    return ExtensionMeta(
      id: id,
      name: name,
      lang: lang,
      version: version,
      description: description,
      isInstalled: isInstalled ?? this.isInstalled,
      isEnabled: isEnabled ?? this.isEnabled,
      repositoryId: repositoryId,
      iconUrl: iconUrl ?? this.iconUrl,
    );
  }
}

class SourceRegistry {
  static SourceRegistry? _instance;
  static SourceRegistry get instance => _instance ??= SourceRegistry._();
  SourceRegistry._();

  bool isPreparing = false;
  void setPreparing(bool value) {
    isPreparing = value;
    _notify();
  }
  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);
  final Set<String> _installedExtensionIds = <String>{};
  final Set<String> _pinnedSourceIds = <String>{};
  bool _listeningToRepositories = false;

  // Gutenberg is retained only as a loader for existing saved books. The
  // first-install source list comes from the complete Shosetsu catalog.
  final List<ExtensionMeta> _availableExtensions = [];
  List<ExtensionMeta>? _extensionCache;

  final Map<String, String> _testScripts = {};

  @visibleForTesting
  void setSourceScriptForTesting(String sourceId, String script) {
    _testScripts[sourceId] = script;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _pinnedSourceIds
      ..clear()
      ..addAll(prefs.getStringList('hon_pinned_sources') ?? const []);
    final saved = prefs.getStringList('hon_installed_extensions');
    _installedExtensionIds.clear();
    if (saved != null) {
      _installedExtensionIds.addAll(
        saved.where(_verifiedBundledSources.contains),
      );
      if (_installedExtensionIds.length != saved.length) {
        await prefs.setStringList(
          'hon_installed_extensions',
          _installedExtensionIds.toList(),
        );
      }
    } else {
      // Shosetsu sources are installed from the offline bundled catalog.
      await prefs.setStringList(
        'hon_installed_extensions',
        _installedExtensionIds.toList(),
      );
    }
    await SourcePreferences.syncNative();
    _notify();
    if (!_listeningToRepositories) {
      ExtensionRepositoryService.instance.addListener(_notify);
      InstalledExtensionService.instance.addListener(_notify);
      _listeningToRepositories = true;
    }
  }

  void _notify() {
    _extensionCache = null;
    changeNotifier.value++;
  }

  List<ExtensionMeta> getExtensions() {
    if (_extensionCache != null) return _extensionCache!;
    final bundled = _availableExtensions.map((e) {
      return e.copyWith(isInstalled: _installedExtensionIds.contains(e.id));
    }).toList();
    final installedService = InstalledExtensionService.instance;
    final seen = <String>{};
    final external = <ExtensionMeta>[];
    for (final repository in ExtensionRepositoryService.instance.repositories) {
      for (final script in repository.scripts) {
        final sourceId = installedService.sourceIdFor(repository, script);
        seen.add(sourceId);
        final installed = installedService.find(sourceId);
        external.add(
          ExtensionMeta(
            id: sourceId,
            name: script.name,
            lang: script.language,
            version: script.version,
            description: 'From ${repository.name} • ${repository.url}',
            isInstalled: installed != null,
            isEnabled: installed?.enabled ?? true,
            repositoryId: repository.id,
            iconUrl: script.iconUrl ?? installed?.iconUrl,
          ),
        );
      }
    }
    for (final installed in installedService.installed) {
      if (seen.contains(installed.sourceId)) continue;
      external.add(
        ExtensionMeta(
          id: installed.sourceId,
          name: installed.name,
          lang: installed.language,
          version: installed.version,
          description:
              'Installed from ${installed.repositoryUrl}; repository removed.',
          isInstalled: true,
          isEnabled: installed.enabled,
          repositoryId: installed.repositoryId,
          iconUrl: installed.iconUrl,
        ),
      );
    }
    return _extensionCache = List.unmodifiable(
      [...bundled, ...external]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    );
  }

  List<ExtensionMeta> getInstalledSources() {
    return getExtensions()
        .where((extension) => extension.isInstalled && extension.isEnabled)
        .toList();
  }

  bool isInstalled(String extensionId) =>
      _installedExtensionIds.contains(extensionId) ||
      InstalledExtensionService.instance.find(extensionId) != null;
  bool isPinned(String sourceId) => _pinnedSourceIds.contains(sourceId);

  static String languageName(String code) =>
      const {
        'en': 'English',
        'eng': 'English',
        'all': 'Multilingual',
        'ru': 'Russian',
        'rus': 'Russian',
        'es': 'Spanish',
        'spa': 'Spanish',
        'pt': 'Portuguese',
        'por': 'Portuguese',
        'ja': 'Japanese',
        'jpn': 'Japanese',
        'vi': 'Vietnamese',
        'vie': 'Vietnamese',
        'ar': 'Arabic',
        'ara': 'Arabic',
        'zh': 'Chinese',
        'zho': 'Chinese',
        'id': 'Indonesian',
        'ind': 'Indonesian',
        'fr': 'French',
        'fra': 'French',
        'ko': 'Korean',
        'kor': 'Korean',
      }[code.toLowerCase()] ??
      code;

  Future<void> togglePinned(String sourceId) async {
    if (!_pinnedSourceIds.add(sourceId)) _pinnedSourceIds.remove(sourceId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hon_pinned_sources', _pinnedSourceIds.toList());
    _notify();
  }

  /// Verified bundled sources supported by Hon's assets
  static const Set<String> _verifiedBundledSources = {'gutenberg'};

  Future<void> installExtension(String extensionId) async {
    if (!_verifiedBundledSources.contains(extensionId)) {
      final installedService = InstalledExtensionService.instance;
      for (final repository
          in ExtensionRepositoryService.instance.repositories) {
        for (final script in repository.scripts) {
          if (installedService.sourceIdFor(repository, script) == extensionId) {
            if (await BundledSourceCatalog.reinstall(extensionId, script.version)) return;
            await installedService.install(repository, script);
            return;
          }
        }
      }
      throw const SourceParseException(
        'Extension was not found in any added repository.',
      );
    }
    _installedExtensionIds.add(extensionId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'hon_installed_extensions',
      _installedExtensionIds.toList(),
    );
    _notify();
  }

  Future<void> uninstallExtension(String extensionId) async {
    if (extensionId.startsWith('ext_')) {
      await InstalledExtensionService.instance.uninstall(extensionId);
      return;
    }
    _installedExtensionIds.remove(extensionId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      'hon_installed_extensions',
      _installedExtensionIds.toList(),
    );
    _notify();
  }

  /// Loads the upstream Lua extension script from assets or test override
  Future<String> getSourceScript(String sourceId) async {
    if (_testScripts.containsKey(sourceId)) {
      return _testScripts[sourceId]!;
    }
    if (sourceId == 'gutenberg') {
      return await rootBundle.loadString('assets/sources/gutenberg.lua');
    }
    if (sourceId.startsWith('ext_')) {
      return InstalledExtensionService.instance.loadScript(sourceId);
    }
    throw SourceParseException(
      'Upstream extension script not found for "$sourceId"',
    );
  }

  Future<SourceCatalogInfo> getCatalogInfo(String sourceId) async {
    final script = await getSourceScript(sourceId);
    final isAndroid = NativeShosetsuBridge.instance.isAndroidTarget;
    if (isAndroid && !kIsWeb) {
      await NativeShosetsuBridge.instance.isSupported();
      return NativeShosetsuBridge.instance.describeExtension(
        script,
        sourceId: sourceId,
      );
    }
    if (await NativeShosetsuBridge.instance.isSupported()) {
      return NativeShosetsuBridge.instance.describeExtension(
        script,
        sourceId: sourceId,
      );
    }
    return const SourceCatalogInfo();
  }

  /// Executes upstream extension search (e.g. Project Gutenberg)
  Future<List<SourceNovelSummary>> searchSource(
    String sourceId,
    String query, {
    int page = 0,
    int? listing,
  }) async {
    final script = await getSourceScript(sourceId);
    final isAndroid = NativeShosetsuBridge.instance.isAndroidTarget;
    if (isAndroid && !kIsWeb) {
      // Surface native failures directly on Android without silent fallback to Dart Lua
      await NativeShosetsuBridge.instance.isSupported();
      return await NativeShosetsuBridge.instance.search(
        script,
        query,
        page: page,
        listing: listing,
        sourceId: sourceId,
      );
    }
    if (await NativeShosetsuBridge.instance.isSupported()) {
      return await NativeShosetsuBridge.instance.search(
        script,
        query,
        page: page,
        listing: listing,
        sourceId: sourceId,
      );
    }
    return await ShosetsuLuaEngine.instance.search(script, query, page: page);
  }

  /// Parses novel details and real chapter list via the upstream extension
  Future<NovelDetails> getNovelDetails(
    String sourceId,
    String novelUrl, {
    bool loadChapters = true,
  }) async {
    final script = await getSourceScript(sourceId);
    final isAndroid = NativeShosetsuBridge.instance.isAndroidTarget;
    if (isAndroid && !kIsWeb) {
      // Surface native failures directly on Android without silent fallback to Dart Lua
      await NativeShosetsuBridge.instance.isSupported();
      return await NativeShosetsuBridge.instance.parseNovel(
        script,
        novelUrl,
        loadChapters: loadChapters,
        sourceId: sourceId,
      );
    }
    if (await NativeShosetsuBridge.instance.isSupported()) {
      return await NativeShosetsuBridge.instance.parseNovel(
        script,
        novelUrl,
        loadChapters: loadChapters,
        sourceId: sourceId,
      );
    }
    return await ShosetsuLuaEngine.instance.parseNovel(
      script,
      novelUrl,
      loadChapters: loadChapters,
    );
  }

  /// Retrieves readable chapter HTML via the upstream extension
  Future<String> getChapterPassage(String sourceId, String chapterUrl) async {
    final script = await getSourceScript(sourceId);
    final isAndroid = NativeShosetsuBridge.instance.isAndroidTarget;
    if (isAndroid && !kIsWeb) {
      // Surface native failures directly on Android without silent fallback to Dart Lua
      await NativeShosetsuBridge.instance.isSupported();
      return await NativeShosetsuBridge.instance.getPassage(
        script,
        chapterUrl,
        sourceId: sourceId,
      );
    }
    if (await NativeShosetsuBridge.instance.isSupported()) {
      return await NativeShosetsuBridge.instance.getPassage(
        script,
        chapterUrl,
        sourceId: sourceId,
      );
    }
    return await ShosetsuLuaEngine.instance.getPassage(script, chapterUrl);
  }
}
