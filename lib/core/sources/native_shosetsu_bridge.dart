import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/novel_source.dart';

class NativeShosetsuBridge {
  static NativeShosetsuBridge? _instance;
  static NativeShosetsuBridge get instance => _instance ??= NativeShosetsuBridge._();
  NativeShosetsuBridge._();

  static const MethodChannel _channel = MethodChannel('com.hon.reader/shosetsu_native');

  bool? _isNativeAvailable;

  /// Checks whether Android native Kotlin Shosetsu runtime is active and responsive
  Future<bool> isSupported() async {
    if (!Platform.isAndroid || kIsWeb) return false;
    if (_isNativeAvailable != null) return _isNativeAvailable!;

    try {
      final res = await _channel.invokeMethod<bool>('isNativeSupported');
      _isNativeAvailable = res ?? false;
      return _isNativeAvailable!;
    } catch (_) {
      _isNativeAvailable = false;
      return false;
    }
  }

  Future<List<SourceNovelSummary>> search(String script, String query, {int page = 0}) async {
    final raw = await _channel.invokeMethod<List<dynamic>>('search', {
      'script': script,
      'query': query,
      'page': page,
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

  Future<NovelDetails> parseNovel(String script, String novelUrl, {bool loadChapters = true}) async {
    final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>('parseNovel', {
      'script': script,
      'novelUrl': novelUrl,
      'loadChapters': loadChapters,
    });

    if (raw == null) {
      throw const FormatException('Empty novel details received from native Shosetsu engine');
    }

    final map = Map<String, dynamic>.from(raw);
    final rawChapters = (map['chapters'] as List<dynamic>?) ?? [];
    final chapters = <SourceChapter>[];
    for (int i = 0; i < rawChapters.length; i++) {
      final chMap = Map<String, dynamic>.from(rawChapters[i] as Map);
      chapters.add(SourceChapter(
        id: chMap['id']?.toString() ?? '',
        title: chMap['title']?.toString() ?? 'Chapter ${i + 1}',
        index: (i + 1).toDouble(),
        url: chMap['url']?.toString() ?? chMap['id']?.toString() ?? '',
      ));
    }

    return NovelDetails(
      id: novelUrl,
      title: map['title']?.toString() ?? '',
      author: map['author']?.toString() ?? 'Unknown Author',
      description: map['synopsis']?.toString() ?? map['description']?.toString() ?? '',
      coverUrl: map['cover']?.toString() ?? map['image']?.toString(),
      chapters: chapters,
    );
  }

  Future<String> getPassage(String script, String chapterUrl) async {
    final passage = await _channel.invokeMethod<String>('getPassage', {
      'script': script,
      'chapterUrl': chapterUrl,
    });

    return passage ?? '';
  }
}
