import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RepositoryScript {
  final String id;
  final String name;
  final String language;
  final String fileName;
  final String version;
  final String libraryVersion;
  final String? checksum;
  final String? iconUrl;
  final List<String> dependencies;

  const RepositoryScript({
    required this.id,
    required this.name,
    required this.language,
    required this.fileName,
    required this.version,
    required this.libraryVersion,
    this.checksum,
    this.iconUrl,
    this.dependencies = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'lang': language,
    'fileName': fileName,
    'ver': version,
    'libVer': libraryVersion,
    'md5': checksum,
    if (iconUrl != null) 'imageURL': iconUrl,
    'dependencies': dependencies,
  };

  factory RepositoryScript.fromJson(Map<String, dynamic> json) =>
      RepositoryScript(
        id: json['id'].toString(),
        name: json['name'] as String,
        language: json['lang'] as String,
        fileName: json['fileName'] as String,
        version: json['ver'] as String,
        libraryVersion: json['libVer'] as String? ?? '',
        checksum: json['md5'] as String?,
        iconUrl: (json['imageURL'] ?? json['iconUrl']) as String?,
        dependencies:
            (json['dependencies'] as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );
}

class ExtensionRepository {
  final String id;
  final String name;
  final String url;
  final DateTime refreshedAt;
  final List<RepositoryScript> scripts;
  final Map<String, String> libraries;

  const ExtensionRepository({
    required this.id,
    required this.name,
    required this.url,
    required this.refreshedAt,
    required this.scripts,
    this.libraries = const {},
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'url': url,
    'refreshedAt': refreshedAt.toIso8601String(),
    'scripts': scripts.map((script) => script.toJson()).toList(),
    'libraries': libraries,
  };

  factory ExtensionRepository.fromJson(
    Map<String, dynamic> json,
  ) => ExtensionRepository(
    id: json['id'] as String,
    name: json['name'] as String,
    url: json['url'] as String,
    refreshedAt: DateTime.parse(json['refreshedAt'] as String),
    libraries: Map<String, String>.from(json['libraries'] as Map? ?? const {}),
    scripts: (json['scripts'] as List<dynamic>)
        .map(
          (entry) => RepositoryScript.fromJson(
            Map<String, dynamic>.from(entry as Map),
          ),
        )
        .toList(),
  );
}

/// Reads and persists Shosetsu repository catalogs. Installation is handled by
/// InstalledExtensionService after runtime compatibility validation.
class ExtensionRepositoryService extends ChangeNotifier {
  static final ExtensionRepositoryService instance =
      ExtensionRepositoryService();
  static const _storageKey = 'hon_extension_repositories_v1';
  final http.Client _client;
  final List<ExtensionRepository> _repositories = [];
  String? loadError;

  ExtensionRepositoryService({http.Client? client})
    : _client = client ?? http.Client();

  List<ExtensionRepository> get repositories =>
      List.unmodifiable(_repositories);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    try {
      final values = jsonDecode(raw) as List<dynamic>;
      final parsed = values
          .map(
            (entry) => ExtensionRepository.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList();
      _repositories
        ..clear()
        ..addAll(parsed);
      notifyListeners();
    } catch (error) {
      loadError = 'Saved extension repository catalog is invalid: $error';
      debugPrint(loadError);
    }
  }

  Future<ExtensionRepository> add(String name, String url) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty || cleanName.length > 100) {
      throw const FormatException(
        'Enter a repository name of up to 100 characters.',
      );
    }
    final base = _normalizeUrl(url);
    final id = sha256.convert(utf8.encode(base.toString())).toString();
    if (_repositories.any((repo) => repo.id == id)) {
      throw const FormatException('This repository has already been added.');
    }
    final catalog = await _fetchScripts(base);
    final repository = ExtensionRepository(
      id: id,
      name: cleanName,
      url: base.toString(),
      refreshedAt: DateTime.now(),
      scripts: catalog.$1,
      libraries: catalog.$2,
    );
    _repositories.add(repository);
    try {
      await _persist();
    } catch (_) {
      _repositories.remove(repository);
      rethrow;
    }
    notifyListeners();
    return repository;
  }

  /// Ships a known catalog without blocking first launch on network access.
  /// Existing user catalogs and refreshes retain their own metadata.
  Future<void> seedBundled(List<ExtensionRepository> repositories) async {
    final previous = _repositories.toList();
    final ids = _repositories.map((repo) => repo.id).toSet();
    _repositories.addAll(repositories.where((repo) => ids.add(repo.id)));
    try {
      await _persist();
    } catch (_) {
      _repositories
        ..clear()
        ..addAll(previous);
      rethrow;
    }
    notifyListeners();
  }

  Future<ExtensionRepository> refresh(String id) async {
    final index = _repositories.indexWhere((repo) => repo.id == id);
    if (index < 0) throw const FormatException('Repository was removed.');
    final previous = _repositories[index];
    final catalog = await _fetchScripts(Uri.parse(previous.url));
    final updated = ExtensionRepository(
      id: previous.id,
      name: previous.name,
      url: previous.url,
      refreshedAt: DateTime.now(),
      scripts: catalog.$1,
      libraries: catalog.$2,
    );
    _repositories[index] = updated;
    try {
      await _persist();
    } catch (_) {
      _repositories[index] = previous;
      rethrow;
    }
    notifyListeners();
    return updated;
  }

  Future<void> remove(String id) async {
    final previous = _repositories.toList();
    _repositories.removeWhere((repo) => repo.id == id);
    try {
      await _persist();
    } catch (_) {
      _repositories
        ..clear()
        ..addAll(previous);
      rethrow;
    }
    notifyListeners();
  }

  Uri _normalizeUrl(String raw) {
    final parsed = Uri.tryParse(raw.trim());
    if (parsed == null ||
        parsed.scheme != 'https' ||
        parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const FormatException('Enter an HTTPS repository base URL.');
    }
    var base = parsed;
    if (parsed.host == 'github.com') {
      final segments = parsed.pathSegments
          .where((segment) => segment.isNotEmpty)
          .toList();
      if (segments.length >= 2) {
        final branch =
            segments.length >= 4 &&
                (segments[2] == 'tree' || segments[2] == 'blob')
            ? segments[3]
            : 'repo';
        final rest = segments.length > 4
            ? '${segments.skip(4).join('/')}/'
            : '';
        base = Uri.parse(
          'https://raw.githubusercontent.com/${segments[0]}/${segments[1]}/$branch/$rest',
        );
      }
    }
    var path = base.path.replaceFirst(RegExp(r'/+$'), '');
    if (path.endsWith('/index.json')) {
      path = path.substring(0, path.length - 'index.json'.length);
    }
    if (!path.endsWith('/')) path = '$path/';
    return base.replace(path: path);
  }

  Future<(List<RepositoryScript>, Map<String, String>)> _fetchScripts(
    Uri base,
  ) async {
    final request = http.Request('GET', base.resolve('index.json'))
      ..followRedirects = false;
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200 || response.request?.url.scheme != 'https') {
      throw FormatException(
        'Repository index returned HTTP ${response.statusCode}.',
      );
    }
    const maxBytes = 2 * 1024 * 1024;
    final bytes = <int>[];
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 20),
    )) {
      bytes.addAll(chunk);
      if (bytes.length > maxBytes) {
        throw const FormatException('Repository index exceeds 2 MB.');
      }
    }
    final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final entries = decoded['scripts'];
    if (entries is! List) {
      throw const FormatException('Repository index has no scripts list.');
    }
    if (entries.length > 1000) {
      throw const FormatException('Repository index has too many scripts.');
    }
    final scripts = <RepositoryScript>[];
    final identities = <String>{};
    final safeSegment = RegExp(r'^[a-zA-Z0-9_-]+$');
    final safeFileName = RegExp(r'^[a-zA-Z0-9_-]+(?:\.[a-zA-Z0-9_-]+)*$');
    for (final rawEntry in entries) {
      if (rawEntry is! Map) continue;
      final entry = Map<String, dynamic>.from(rawEntry);
      final id = entry['id']?.toString() ?? '';
      final lang = entry['lang']?.toString() ?? '';
      final fileName = entry['fileName']?.toString() ?? '';
      final name = entry['name']?.toString() ?? '';
      final version = entry['ver']?.toString() ?? '';
      if (id.isEmpty ||
          name.isEmpty ||
          !safeSegment.hasMatch(lang) ||
          !safeFileName.hasMatch(fileName) ||
          version.isEmpty) {
        continue;
      }
      if (!identities.add('$lang:$id')) continue;
      scripts.add(
        RepositoryScript(
          id: id,
          name: name,
          language: lang,
          fileName: fileName,
          version: version,
          libraryVersion: entry['libVer']?.toString() ?? '',
          checksum: entry['md5']?.toString(),
          dependencies:
              (entry['dependencies'] as List<dynamic>?)
                  ?.map((dependency) => dependency.toString())
                  .toList() ??
              const [],
        ),
      );
    }
    final libraries = <String, String>{};
    for (final entry in decoded['libraries'] as List<dynamic>? ?? const []) {
      if (entry is Map &&
          safeSegment.hasMatch(entry['name']?.toString() ?? '') &&
          (entry['ver'] ?? entry['version']) is String) {
        libraries[entry['name'] as String] =
            (entry['ver'] ?? entry['version']) as String;
      }
    }
    return (scripts, libraries);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _storageKey,
      jsonEncode(_repositories.map((repo) => repo.toJson()).toList()),
    );
    if (!saved) {
      throw const FileSystemException('Could not save repository catalog.');
    }
  }
}
