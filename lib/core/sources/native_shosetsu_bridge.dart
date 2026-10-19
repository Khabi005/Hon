import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/novel_source.dart';
import 'installed_extension_service.dart';
import 'source_preferences.dart';

class NativeShosetsuBridge {
  static NativeShosetsuBridge? _instance;
  static NativeShosetsuBridge get instance =>
      _instance ??= NativeShosetsuBridge._();
  NativeShosetsuBridge._();

  static const MethodChannel _channel = MethodChannel(
    'com.hon.reader/shosetsu_native',
  );

  bool? _isNativeAvailable;
  Object? _nativeError;

  @visibleForTesting
  static bool? platformOverrideIsAndroid;

  bool get isAndroidTarget => platformOverrideIsAndroid ?? Platform.isAndroid;

  @visibleForTesting
  void resetForTesting() {
    _isNativeAvailable = null;
    _nativeError = null;
    platformOverrideIsAndroid = null;
  }

  /// Checks whether Android native Kotlin Shosetsu runtime is active and responsive.
  /// On Android, engine failures (such as SOURCE_ENGINE_UNAVAILABLE) are rethrown
  /// so that they surface directly to the UI instead of falling back to Dart Lua.
  Future<bool> isSupported() async {
    final isAndroid = isAndroidTarget;
    if (!isAndroid || kIsWeb) return false;
    if (_nativeError != null) throw _nativeError!;
    if (_isNativeAvailable != null) return _isNativeAvailable!;

    try {
      final res = await _channel.invokeMethod<bool>('isNativeSupported');
      if (res != true) {
        throw const FormatException(
          'SOURCE_ENGINE_UNAVAILABLE: The native Shosetsu engine could not load on Android.',
        );
      }
      _isNativeAvailable = true;
      return true;
    } on PlatformException catch (e) {
      _isNativeAvailable = false;
      _nativeError = e;
      rethrow;
    } catch (e) {
      _isNativeAvailable = false;
      _nativeError = e;
      rethrow;
    }
  }

  List<String> _resolveAllowedHosts(String? sourceId, List<String>? explicit) {
    if (explicit != null) return explicit;
    if (sourceId != null) {
      return InstalledExtensionService.instance.find(sourceId)?.allowedHosts ?? const [];
    }
    return const [];
  }

  Future<void> validateExtension(
    String script, {
    List<String>? allowedHosts,
    String? baseUrl,
  }) async {
    final valid = await _channel.invokeMethod<bool>('validateExtension', {
      'script': script,
      'allowedHosts': allowedHosts ?? const <String>[],
      'baseUrl': ?baseUrl,
    });
    if (valid != true) {
      throw const FormatException(
        'Extension did not pass the native compatibility check.',
      );
    }
  }

  Future<SourceCatalogInfo> describeExtension(
    String script, {
    String? sourceId,
    List<String>? allowedHosts,
    String? baseUrl,
  }) async {
    final raw = await _channel.invokeMapMethod<String, dynamic>(
      'describeExtension',
      {
        'script': script,
        'sourceId': ?sourceId,
        'allowedHosts': _resolveAllowedHosts(sourceId, allowedHosts),
        'baseUrl': ?baseUrl,
      },
    );
    if (raw == null) throw const FormatException('Source metadata was empty.');
    return SourceCatalogInfo(
      baseUrl: raw['baseUrl'] as String? ?? '',
      settings: (raw['settings'] as List? ?? [])
          .map((value) => SourceControl.fromMap(value as Map))
          .toList(),
      filters: (raw['filters'] as List? ?? [])
          .map((value) => SourceControl.fromMap(value as Map))
          .toList(),
      hasSearch: raw['hasSearch'] as bool? ?? true,
      searchIncrementing: raw['searchIncrementing'] as bool? ?? true,
      listings: (raw['listings'] as List? ?? const []).map((value) {
        final entry = Map<String, dynamic>.from(value as Map);
        return SourceListing(
          index: entry['index'] as int,
          name: entry['name'] as String,
          incrementing: entry['incrementing'] as bool? ?? false,
        );
      }).toList(),
    );
  }

  Future<List<SourceNovelSummary>> search(
    String script,
    String query, {
    int page = 0,
    int? listing,
    String? sourceId,
    List<String>? allowedHosts,
    String? baseUrl,
  }) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('search', {
      'script': script,
      'query': query,
      'page': page,
      'listing': ?listing,
      'sourceId': ?sourceId,
      'allowedHosts': _resolveAllowedHosts(sourceId, allowedHosts),
      'baseUrl': ?baseUrl,
      'filters': sourceId == null
          ? <String, dynamic>{}
          : await SourcePreferences.read(sourceId, filters: true),
    });

    if (raw == null) return [];

    return raw.map((item) {
      final map = Map<String, dynamic>.from(item as Map);
      return SourceNovelSummary(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        coverUrl: map['cover']?.toString() ?? map['image']?.toString(),
        author: map['author']?.toString() ?? 'Unknown Author',
      );
    }).toList();
  }

  Future<NovelDetails> parseNovel(
    String script,
    String novelUrl, {
    bool loadChapters = true,
    String? sourceId,
    List<String>? allowedHosts,
    String? baseUrl,
  }) async {
    final raw = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('parseNovel', {
          'script': script,
          'novelUrl': novelUrl,
          'loadChapters': loadChapters,
          'sourceId': ?sourceId,
          'allowedHosts': _resolveAllowedHosts(sourceId, allowedHosts),
          'baseUrl': ?baseUrl,
        });

    if (raw == null) {
      throw const FormatException(
        'Empty novel details received from native Shosetsu engine',
      );
    }

    final map = Map<String, dynamic>.from(raw);
    final rawChapters = (map['chapters'] as List<dynamic>?) ?? [];
    final chapters = <SourceChapter>[];
    for (int i = 0; i < rawChapters.length; i++) {
      final chMap = Map<String, dynamic>.from(rawChapters[i] as Map);
      chapters.add(
        SourceChapter(
          id: chMap['id']?.toString() ?? '',
          title: chMap['title']?.toString() ?? 'Chapter ${i + 1}',
          index: (i + 1).toDouble(),
          url: chMap['url']?.toString() ?? chMap['id']?.toString() ?? '',
        ),
      );
    }

    return NovelDetails(
      id: novelUrl,
      title: map['title']?.toString() ?? '',
      author: map['author']?.toString() ?? 'Unknown Author',
      description:
          map['synopsis']?.toString() ?? map['description']?.toString() ?? '',
      coverUrl: map['cover']?.toString() ?? map['image']?.toString(),
      chapters: chapters,
    );
  }

  Future<String> getPassage(
    String script,
    String chapterUrl, {
    String? sourceId,
    List<String>? allowedHosts,
    String? baseUrl,
  }) async {
    final passage = await _channel.invokeMethod<String>('getPassage', {
      'script': script,
      'chapterUrl': chapterUrl,
      'sourceId': ?sourceId,
      'allowedHosts': _resolveAllowedHosts(sourceId, allowedHosts),
      'baseUrl': ?baseUrl,
    });

    return passage ?? '';
  }
}
