import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/novel_source.dart';
import 'lua/shosetsu_lua_engine.dart';
import 'native_shosetsu_bridge.dart';

class ExtensionMeta {
  final String id;
  final String name;
  final String lang;
  final String version;
  final String description;
  final bool isInstalled;

  const ExtensionMeta({
    required this.id,
    required this.name,
    required this.lang,
    required this.version,
    required this.description,
    this.isInstalled = false,
  });

  ExtensionMeta copyWith({bool? isInstalled}) {
    return ExtensionMeta(
      id: id,
      name: name,
      lang: lang,
      version: version,
      description: description,
      isInstalled: isInstalled ?? this.isInstalled,
    );
  }
}

class SourceRegistry {
  static SourceRegistry? _instance;
  static SourceRegistry get instance => _instance ??= SourceRegistry._();
  SourceRegistry._();

  final ValueNotifier<int> changeNotifier = ValueNotifier<int>(0);
  final Set<String> _installedExtensionIds = <String>{};

  // Available extensions catalog (from repository)
  final List<ExtensionMeta> _availableExtensions = [
    const ExtensionMeta(
      id: 'novelfull',
      name: 'NovelFull (NET)',
      lang: 'English',
      version: '1.0.0',
      description: 'Web novel catalog with fantasy, xianxia, romance and adventure novels.',
      isInstalled: false,
    ),
    const ExtensionMeta(
      id: 'gutenberg',
      name: 'Project Gutenberg',
      lang: 'English',
      version: '1.2.0',
      description: 'Free public domain classics and literature.',
      isInstalled: false,
    ),
    const ExtensionMeta(
      id: 'royalroad',
      name: 'Royal Road',
      lang: 'English',
      version: '1.1.0',
      description: 'Web fiction and serial stories by independent authors.',
      isInstalled: false,
    ),
    const ExtensionMeta(
      id: 'scribblehub',
      name: 'Scribble Hub',
      lang: 'English',
      version: '1.0.4',
      description: 'Original web fiction, progression fantasy and litRPG.',
      isInstalled: false,
    ),
    const ExtensionMeta(
      id: 'fanfiction',
      name: 'FanFiction.net',
      lang: 'all',
      version: '1.0.0',
      description: 'The world\'s largest fanfiction archive.',
      isInstalled: false,
    ),
    const ExtensionMeta(
      id: 'arnovel',
      name: 'ArNovel',
      lang: 'Arabic',
      version: '1.0.1',
      description: 'Arabic translated light novels and web stories.',
      isInstalled: false,
    ),
  ];

  final Map<String, String> _testScripts = {};

  @visibleForTesting
  void setSourceScriptForTesting(String sourceId, String script) {
    _testScripts[sourceId] = script;
  }

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('hon_installed_extensions');
    if (saved != null) {
      _installedExtensionIds.clear();
      _installedExtensionIds.addAll(saved);
    } else {
      // Default to Project Gutenberg so the verified upstream extension is active
      _installedExtensionIds.add('gutenberg');
    }
  }

  void _notify() => changeNotifier.value++;

  List<ExtensionMeta> getExtensions() {
    return _availableExtensions.map((e) {
      return e.copyWith(isInstalled: _installedExtensionIds.contains(e.id));
    }).toList();
  }

  List<ExtensionMeta> getInstalledSources() {
    return _availableExtensions
        .where((e) => _installedExtensionIds.contains(e.id))
        .map((e) => e.copyWith(isInstalled: true))
        .toList();
  }

  bool isInstalled(String extensionId) => _installedExtensionIds.contains(extensionId);

  /// Verified bundled sources supported by Hon's assets
  static const Set<String> _verifiedBundledSources = {'gutenberg'};

  /// External extension installation is strictly gated until the production
  /// Kotlin-side Shosetsu host runtime with full security restrictions is verified.
  Future<void> installExtension(String extensionId) async {
    if (!_verifiedBundledSources.contains(extensionId)) {
      throw const SourceParseException(
        'External extension installation is gated until production Kotlin-side host restrictions are implemented.',
      );
    }
    _installedExtensionIds.add(extensionId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hon_installed_extensions', _installedExtensionIds.toList());
    _notify();
  }

  Future<void> uninstallExtension(String extensionId) async {
    _installedExtensionIds.remove(extensionId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hon_installed_extensions', _installedExtensionIds.toList());
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
    throw SourceParseException('Upstream extension script not found for "$sourceId"');
  }

  /// Executes upstream extension search (e.g. Project Gutenberg)
  Future<List<SourceNovelSummary>> searchSource(
    String sourceId,
    String query, {
    int page = 0,
  }) async {
    final script = await getSourceScript(sourceId);
    if (await NativeShosetsuBridge.instance.isSupported()) {
      // Surface native failures directly on Android without silent fallback
      return await NativeShosetsuBridge.instance.search(script, query, page: page);
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
    if (await NativeShosetsuBridge.instance.isSupported()) {
      // Surface native failures directly on Android without silent fallback
      return await NativeShosetsuBridge.instance.parseNovel(script, novelUrl, loadChapters: loadChapters);
    }
    return await ShosetsuLuaEngine.instance.parseNovel(
      script,
      novelUrl,
      loadChapters: loadChapters,
    );
  }

  /// Retrieves readable chapter HTML via the upstream extension
  Future<String> getChapterPassage(
    String sourceId,
    String chapterUrl,
  ) async {
    final script = await getSourceScript(sourceId);
    if (await NativeShosetsuBridge.instance.isSupported()) {
      // Surface native failures directly on Android without silent fallback
      return await NativeShosetsuBridge.instance.getPassage(script, chapterUrl);
    }
    return await ShosetsuLuaEngine.instance.getPassage(script, chapterUrl);
  }

  /// When true, mock preview catalogues are returned for offline layout prototyping.
  /// Kept false in normal use so no fabricated novels are shown until Phase 0C connects live upstream Lua extensions.
  static const bool enableDemoCatalogues = false;

  // Catalog source data provider
  List<SourceNovelSummary> getNovelsForSource(String sourceId) {
    if (!enableDemoCatalogues) {
      return [];
    }
    if (sourceId == 'novelfull') {
      return [
        const SourceNovelSummary(
          id: 'nf_lotm',
          title: 'Lord of the Mysteries',
          author: 'Cuttlefish That Loves Diving',
          description: 'With the rising tide of steam power and machinery, who can come close to being a Beyonder? Shrouded in the fog of history and darkness...',
          genres: ['Mystery', 'Fantasy', 'Steampunk'],
          rating: 4.9,
        ),
        const SourceNovelSummary(
          id: 'nf_shadow_slave',
          title: 'Shadow Slave',
          author: 'Guiltythree',
          description: 'Growing up in poverty, Sunny never expected anything good from life. However, he did not expect to be chosen by the Nightmare Spell...',
          genres: ['Action', 'Adventure', 'Fantasy'],
          rating: 4.8,
        ),
        const SourceNovelSummary(
          id: 'nf_re_awakening',
          title: 'Re-Awakening: I Ascend with a Legendary class',
          author: 'Legion20',
          description: 'When the world ended, classes awakened. But his class was classified as unknown...',
          genres: ['Action', 'LitRPG'],
          rating: 4.7,
        ),
        const SourceNovelSummary(
          id: 'nf_supreme_magus',
          title: 'Supreme Magus',
          author: 'Legion20',
          description: 'Derek McCoy was a man who spent his entire life facing adversity and injustice...',
          genres: ['Fantasy', 'Reincarnation'],
          rating: 4.6,
        ),
        const SourceNovelSummary(
          id: 'nf_infinite_mana',
          title: 'Infinite Mana In The Apocalypse',
          author: 'AweSpec',
          description: 'Awakened with infinite mana in a collapsing world.',
          genres: ['Action', 'Fantasy'],
          rating: 4.5,
        ),
      ];
    } else if (sourceId == 'gutenberg') {
      // Gutenberg Classics
      return [
        const SourceNovelSummary(
          id: 'gt_pride',
          title: 'Pride and Prejudice',
          author: 'Jane Austen',
          description: 'The romantic clash between Elizabeth Bennet and Mr. Darcy.',
          genres: ['Classic', 'Romance'],
          rating: 4.8,
        ),
        const SourceNovelSummary(
          id: 'gt_frankenstein',
          title: 'Frankenstein',
          author: 'Mary Shelley',
          description: 'A scientist creates a sentient creature in an unorthodox scientific experiment.',
          genres: ['Classic', 'Horror', 'Sci-Fi'],
          rating: 4.7,
        ),
        const SourceNovelSummary(
          id: 'gt_sherlock',
          title: 'The Adventures of Sherlock Holmes',
          author: 'Arthur Conan Doyle',
          description: 'Twelve classic detective stories featuring Sherlock Holmes and Dr. Watson.',
          genres: ['Classic', 'Mystery'],
          rating: 4.9,
        ),
        const SourceNovelSummary(
          id: 'gt_dracula',
          title: 'Dracula',
          author: 'Bram Stoker',
          description: 'Count Dracula attempts to move from Transylvania to England.',
          genres: ['Classic', 'Horror', 'Gothic'],
          rating: 4.6,
        ),
      ];
    }
    // Extensions without a compiled runtime return an empty catalog
    return [];
  }

  // Global search across all installed sources
  Map<String, List<SourceNovelSummary>> globalSearch(String query) {
    final results = <String, List<SourceNovelSummary>>{};
    final cleanQuery = query.trim().toLowerCase();

    for (final source in getInstalledSources()) {
      final novels = getNovelsForSource(source.id);
      final matched = novels.where((n) {
        return n.title.toLowerCase().contains(cleanQuery) ||
            (n.author?.toLowerCase().contains(cleanQuery) ?? false) ||
            n.genres.any((g) => g.toLowerCase().contains(cleanQuery));
      }).toList();

      if (matched.isNotEmpty) {
        results[source.name] = matched;
      }
    }

    return results;
  }
}
