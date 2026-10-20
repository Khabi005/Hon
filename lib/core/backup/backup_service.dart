import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_service.dart';
import '../files/storage_service.dart';
import '../sources/extension_repository_service.dart';

class BackupPreview {
  final int books, files;
  final String createdAt;
  const BackupPreview(this.books, this.files, this.createdAt);
}

class BackupService {
  static const preferenceKeys = [
    'hon_reader_preferences_v1',
    'hon_collections_v1',
    'hon_chapter_updates_v1',
    'hon_chapter_updates_checked',
    'hon_download_wifi_only',
    'hon_library_grid',
    'hon_library_sort',
    'hon_app_appearance_v1',
    'hon_daily_goal_minutes',
    'hon_reading_minutes',
    'hon_pdf_color_filter',
    'hon_pdf_view_mode',
    'hon_global_search_sources',
    'hon_pinned_sources',
    'hon_extension_repositories_v1',
  ];
  Future<File> create({required bool includeFiles}) async {
    final storage = StorageService.instance;
    await storage.stagingDir.create(recursive: true);
    final path =
        '${storage.stagingDir.path}/Hon-${DateTime.now().millisecondsSinceEpoch}.honbackup.zip';
    final metadata = await DatabaseService.instance.exportSnapshot();
    final prefs = await SharedPreferences.getInstance();
    final preferences = <String, Object?>{};
    for (final key in prefs.getKeys()) {
      if (preferenceKeys.contains(key) ||
          key.startsWith('hon_reading_secs_') ||
          RegExp(
            r'^hon_source_(settings|filters)_(ext_[0-9a-f]{64}|gutenberg)$',
          ).hasMatch(key)) {
        var value = prefs.get(key);
        if (key.startsWith('hon_source_settings_')) {
          final source = key.substring('hon_source_settings_'.length);
          final settings = Map<String, dynamic>.from(
            jsonDecode(value as String) as Map,
          );
          for (final secret
              in prefs.getStringList('hon_source_secret_keys_$source') ??
                  <String>[]) {
            settings.remove(secret);
          }
          value = jsonEncode(settings);
        }
        preferences[key] = value;
      }
    }
    final root = storage.baseDir.path;
    await _createArchive(root, path, metadata, preferences, includeFiles);
    return File(path);
  }

  Future<BackupPreview> inspect(File file) async {
    final data = await _inspectArchive(file.path);
    final metadata = Map<String, dynamic>.from(data['metadata'] as Map);
    return BackupPreview(
      (metadata['books'] as List).length,
      (data['files'] as List).length,
      data['createdAt'] as String,
    );
  }

  Future<void> restore(File file) async {
    final root = StorageService.instance.baseDir.path;
    final restoreId = 'restore_${DateTime.now().microsecondsSinceEpoch}';
    final data = await _extractArchive(file.path, root, restoreId);
    final newDirectories = [
      for (final category in ['publications', 'covers', 'chapters', 'images'])
        Directory(p.join(root, category, restoreId)),
    ];
    try {
      final metadata = Map<String, dynamic>.from(data['metadata'] as Map);
      final db = DatabaseService.instance;
      for (final raw in metadata['books'] as List) {
        final book = raw as Map;
        final existing = db.getBookById(book['id'] as String);
        if (book['filePath'] == null &&
            existing?.filePath != null &&
            await File(existing!.filePath!).exists()) {
          book['filePath'] = existing.filePath;
        }
        if (book['coverPath'] == null && existing?.coverPath != null) {
          book['coverPath'] = existing!.coverPath;
        }
      }
      final bookIdsInChapters = {
        for (final raw in metadata['chapters'] as List? ?? [])
          (raw as Map)['bookId'] as String?,
      }.whereType<String>();
      for (final bId in bookIdsInChapters) {
        await db.ensureChaptersLoaded(bId);
      }
      for (final raw in metadata['chapters'] as List? ?? []) {
        final chapter = raw as Map;
        final existing = db
            .getChapters(chapter['bookId'] as String)
            .where((value) => value.id == chapter['id'])
            .firstOrNull;
        if (chapter['localFilePath'] == null &&
            existing?.localFilePath != null &&
            await File(existing!.localFilePath!).exists()) {
          chapter['localFilePath'] = existing.localFilePath;
          chapter['downloadState'] = existing.downloadState.name;
        }
      }
      final paths = {
        for (final raw in metadata['chapters'] as List? ?? [])
          (raw as Map)['id']: raw['localFilePath'],
      };
      for (final raw in metadata['downloads'] as List? ?? []) {
        final job = raw as Map;
        if (job['status'] == 'completed' && paths[job['chapterId']] == null) {
          job['status'] = 'paused';
          job['progress'] = 0.0;
        }
      }
      await db.importSnapshot(metadata);
    } catch (_) {
      for (final directory in newDirectories) {
        if (await directory.exists()) await directory.delete(recursive: true);
      }
      rethrow;
    }
    final prefs = await SharedPreferences.getInstance();
    for (final entry in Map<String, dynamic>.from(
      data['preferences'] as Map,
    ).entries) {
      if (!preferenceKeys.contains(entry.key) &&
          !RegExp(
            r'^hon_reading_secs_\d{4}_\d{1,2}_\d{1,2}$',
          ).hasMatch(entry.key) &&
          !RegExp(
            r'^hon_source_(settings|filters)_(ext_[0-9a-f]{64}|gutenberg)$',
          ).hasMatch(entry.key)) {
        continue;
      }
      final value = entry.value;
      if (value is String) {
        if (entry.key == 'hon_collections_v1') {
          final incoming = Map<String, String>.from(jsonDecode(value) as Map);
          final remap = <String, String>{};
          for (final c in incoming.entries) {
            final resolvedId = await DatabaseService.instance.createCollection(c.value, id: c.key);
            if (resolvedId != c.key) {
              remap[c.key] = resolvedId;
            }
          }
          if (remap.isNotEmpty) {
            final allEntries = DatabaseService.instance.libraryEntries;
            for (final libEntry in allEntries) {
              final needsRemap = libEntry.collectionIds.any((id) => remap.containsKey(id));
              if (needsRemap) {
                final remappedIds = libEntry.collectionIds.map((id) => remap[id] ?? id).toSet().toList();
                await DatabaseService.instance.setBookCollections(libEntry.bookId, remappedIds);
              }
            }
          }
        } else if (entry.key == 'hon_extension_repositories_v1') {
          final existing =
              jsonDecode(prefs.getString(entry.key) ?? '[]') as List;
          final incoming = jsonDecode(value) as List;
          final repositories = {
            for (final row in [...existing, ...incoming])
              (row as Map)['id']: row,
          };
          await prefs.setString(
            entry.key,
            jsonEncode(repositories.values.toList()),
          );
        } else if (entry.key.startsWith('hon_source_settings_')) {
          final existing = Map<String, dynamic>.from(
            jsonDecode(prefs.getString(entry.key) ?? '{}') as Map,
          );
          final incoming = Map<String, dynamic>.from(jsonDecode(value) as Map);
          await prefs.setString(
            entry.key,
            jsonEncode({...existing, ...incoming}),
          );
        } else {
          await prefs.setString(entry.key, value);
        }
      } else if (value is bool) {
        await prefs.setBool(entry.key, value);
      } else if (value is int) {
        await prefs.setInt(entry.key, value);
      } else if (value is double) {
        await prefs.setDouble(entry.key, value);
      } else if (value is List) {
        await prefs.setStringList(entry.key, value.cast<String>());
      }
    }
    await DatabaseService.instance.reloadPreferences();
  }
}

Future<void> _createArchive(
  String root,
  String destination,
  Map<String, dynamic> metadata,
  Map<String, Object?> preferences,
  bool includeFiles,
) => Isolate.run(() async {
  final encoder = ZipFileEncoder()..create(destination);
  final files = <Map<String, dynamic>>[];
  var totalSize = 0;
  try {
    if (includeFiles) {
      for (final category in ['publications', 'covers', 'chapters', 'images']) {
        final directory = Directory(p.join(root, category));
        if (!directory.existsSync()) continue;
        for (final entity in directory.listSync(
          recursive: true,
          followLinks: false,
        )) {
          if (entity is! File ||
              entity.path.endsWith('.backup') ||
              entity.path.contains('.tmp')) {
            continue;
          }
          final canonical = entity.resolveSymbolicLinksSync();
          if (!p.isWithin(directory.resolveSymbolicLinksSync(), canonical)) {
            continue;
          }
          final length = entity.lengthSync();
          totalSize += length;
          if (totalSize > 2 * 1024 * 1024 * 1024 || files.length >= 20000) {
            throw const FormatException(
              'Backup exceeds the supported 2 GB or 20,000 file limit.',
            );
          }
          if (length > 256 * 1024 * 1024) {
            throw const FormatException(
              'A file exceeds the 256 MB backup limit. Create a metadata backup or move that file separately.',
            );
          }
          final relative = p
              .relative(entity.path, from: root)
              .replaceAll(p.separator, '/');
          final digest = await sha256.bind(entity.openRead()).first;
          files.add({
            'path': relative,
            'sha256': digest.toString(),
            'size': length,
          });
          await encoder.addFile(entity, 'files/$relative');
        }
      }
    }
    final manifest = {
      'format': 'hon-portable-backup',
      'version': 1,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'originRoot': root,
      'metadata': metadata,
      'preferences': preferences,
      'files': files,
    };
    final manifestBytes = utf8.encode(jsonEncode(manifest));
    encoder.addArchiveFile(
      ArchiveFile('manifest.json', manifestBytes.length, manifestBytes),
    );
  } catch (_) {
    encoder.closeSync();
    final file = File(destination);
    if (file.existsSync()) file.deleteSync();
    rethrow;
  }
  encoder.closeSync();
});

Map<String, dynamic> _manifest(Archive archive) {
  final entry = archive.findFile('manifest.json');
  if (entry == null || entry.size > 16 * 1024 * 1024) {
    throw const FormatException('This is not a supported Hon backup.');
  }
  final manifest = Map<String, dynamic>.from(
    jsonDecode(utf8.decode(_readEntry(entry, 16 * 1024 * 1024))) as Map,
  );
  if (manifest['format'] != 'hon-portable-backup' ||
      manifest['version'] != 1 ||
      manifest['metadata'] is! Map ||
      manifest['files'] is! List ||
      manifest['preferences'] is! Map) {
    throw const FormatException('Unsupported or incomplete Hon backup.');
  }
  if ((manifest['metadata'] as Map)['books'] is! List) {
    throw const FormatException('Backup book list is missing.');
  }
  if (DateTime.tryParse(manifest['createdAt'] as String? ?? '') == null ||
      manifest['originRoot'] is! String) {
    throw const FormatException('Backup dates or origin are invalid.');
  }
  final preferences = Map<String, dynamic>.from(manifest['preferences'] as Map);
  for (final item in preferences.entries) {
    final key = item.key;
    final value = item.value;
    if (RegExp(
      r'^hon_source_(settings|filters)_(ext_[0-9a-f]{64}|gutenberg)$',
    ).hasMatch(key)) {
      final settings = Map<String, dynamic>.from(
        jsonDecode(value as String) as Map,
      );
      if (settings.length > 2048 ||
          settings.entries.any(
            (entry) =>
                int.tryParse(entry.key) == null ||
                !(entry.value is bool ||
                    entry.value is String && entry.value.length <= 4096 ||
                    entry.value is num && (entry.value as num).isFinite),
          )) {
        throw const FormatException('Backup source preferences are invalid.');
      }
    } else if (key == 'hon_app_appearance_v1') {
      if (value != 'standard' && value != 'liquidGlass') {
        throw const FormatException('Backup appearance is invalid.');
      }
    } else if (key == 'hon_collections_v1') {
      final names = Map<String, String>.from(
        jsonDecode(value as String) as Map,
      );
      if (names.entries.any(
        (entry) =>
            !RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(entry.key) ||
            entry.value.trim().isEmpty ||
            entry.value.length > 80,
      )) {
        throw const FormatException('Backup collection names are invalid.');
      }
    } else if (key == 'hon_extension_repositories_v1') {
      for (final row in jsonDecode(value as String) as List) {
        final repo = ExtensionRepository.fromJson(
          Map<String, dynamic>.from(row as Map),
        );
        final uri = Uri.tryParse(repo.url);
        if (uri?.scheme != 'https' ||
            uri!.host.isEmpty ||
            uri.userInfo.isNotEmpty) {
          throw const FormatException('Backup repository URL is invalid.');
        }
      }
    } else if (key == 'hon_reader_preferences_v1') {
      final values = Map<String, dynamic>.from(
        jsonDecode(value as String) as Map,
      );
      for (final field in [
        'size',
        'lineHeight',
        'margin',
        'paragraphSpacing',
        'indent',
        'brightness',
      ]) {
        if (values[field] != null &&
            (values[field] is! num || !(values[field] as num).isFinite)) {
          throw const FormatException('Backup reader preferences are invalid.');
        }
      }
    } else if (key == 'hon_chapter_updates_v1') {
      final rows = jsonDecode(value as String) as List;
      if (rows.length > 2000) {
        throw const FormatException('Backup update history is too large.');
      }
      for (final row in rows) {
        if (row is! Map ||
            row['bookId'] is! String ||
            row['chapterId'] is! String ||
            row['title'] is! String ||
            DateTime.tryParse(row['detectedAt'] as String? ?? '') == null) {
          throw const FormatException('Backup update history is invalid.');
        }
      }
    } else if (key == 'hon_library_grid' || key == 'hon_download_wifi_only') {
      if (value is! bool) {
        throw const FormatException('Backup switch preference is invalid.');
      }
    } else if (key == 'hon_global_search_sources' ||
        key == 'hon_pinned_sources') {
      if (value is! List || value.any((entry) => entry is! String)) {
        throw const FormatException('Backup source selection is invalid.');
      }
    } else if (key == 'hon_daily_goal_minutes' ||
        key.startsWith('hon_reading_secs_')) {
      if (value is! int || value < 0) {
        throw const FormatException('Backup reading goal/history is invalid.');
      }
    }
  }
  if ((manifest['files'] as List).length > 20000 ||
      archive.files.length > 20001) {
    throw const FormatException('Backup contains too many files.');
  }
  final names = <String>{};
  var total = 0;
  for (final item in manifest['files'] as List) {
    final file = Map<String, dynamic>.from(item as Map);
    final name = file['path'] as String;
    if (name.contains('\\') ||
        p.posix.isAbsolute(name) ||
        p.posix.normalize(name) != name ||
        name.split('/').any((part) => part == '..' || part == '.') ||
        ![
          'publications',
          'covers',
          'chapters',
          'images',
        ].contains(name.split('/').first) ||
        !names.add(name)) {
      throw const FormatException(
        'Backup contains an unsafe or duplicate file path.',
      );
    }
    final size = file['size'] as int;
    total += size;
    final source = archive.findFile('files/$name');
    if (size < 0 ||
        size > 256 * 1024 * 1024 ||
        total > 2 * 1024 * 1024 * 1024 ||
        source == null ||
        !source.isFile ||
        source.isSymbolicLink ||
        source.size != size) {
      throw const FormatException(
        'Backup is incomplete or exceeds supported size limits.',
      );
    }
  }
  return manifest;
}

Future<Map<String, dynamic>> _inspectArchive(String path) => Isolate.run(() {
  if (File(path).lengthSync() > 2200 * 1024 * 1024) {
    throw const FormatException(
      'Backup archive exceeds the supported size limit.',
    );
  }
  final input = InputFileStream(path);
  try {
    return _manifest(ZipDecoder().decodeBuffer(input));
  } finally {
    input.closeSync();
  }
});
Future<Map<String, dynamic>> _extractArchive(
  String path,
  String root,
  String restoreId,
) => Isolate.run(() async {
  if (File(path).lengthSync() > 2200 * 1024 * 1024) {
    throw const FormatException(
      'Backup archive exceeds the supported size limit.',
    );
  }
  final input = InputFileStream(path);
  final created = <Directory>[];
  try {
    final archive = ZipDecoder().decodeBuffer(input);
    final manifest = _manifest(archive);
    final files = (manifest['files'] as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final destinations = <String, String>{};
    // Extract into unique new directories. Existing files stay untouched;
    // failed validation removes these directories before any database import.
    for (final item in files) {
      final relative = item['path'] as String;
      final parts = relative.split('/');
      final destination = p.join(
        root,
        parts.first,
        restoreId,
        p.joinAll(parts.skip(1)),
      );
      final folder = Directory(p.join(root, parts.first, restoreId));
      if (!created.any((entry) => entry.path == folder.path)) {
        created.add(folder);
      }
      await File(destination).parent.create(recursive: true);
      final entry = archive.findFile('files/$relative')!;
      final bytes = _readEntry(entry, 256 * 1024 * 1024);
      if (sha256.convert(bytes).toString() != item['sha256']) {
        throw const FormatException(
          'Backup file checksum failed. Nothing was restored.',
        );
      }
      await File(destination).writeAsBytes(bytes, flush: true);
      entry.clear();
      destinations[relative] = destination;
    }
    final origin = manifest['originRoot'] as String;
    String? relocate(dynamic value) {
      if (value is! String) return null;
      if (value.startsWith('https://') ||
          value.startsWith('http://') ||
          value.startsWith('assets/')) {
        return value;
      }
      if (p.isWithin(origin, value)) {
        return destinations[p
            .relative(value, from: origin)
            .replaceAll(p.separator, '/')];
      }
      return null;
    }

    final imageSrcMap = <String, String>{};
    for (final entry in destinations.entries) {
      final rel = entry.key;
      if (rel.startsWith('images/')) {
        final oldAbs = p.join(origin, rel.replaceAll('/', p.separator));
        final oldFileUri = Uri.file(oldAbs).toString();
        final newFileUri = Uri.file(entry.value).toString();
        imageSrcMap[oldAbs] = entry.value;
        imageSrcMap[oldFileUri] = newFileUri;
      }
    }

    final metadata = Map<String, dynamic>.from(manifest['metadata'] as Map);
    for (final value in metadata['books'] as List) {
      final book = value as Map;
      book['filePath'] = relocate(book['filePath']);
      book['coverPath'] = relocate(book['coverPath']);
    }
    for (final value in metadata['chapters'] as List? ?? []) {
      final chapter = value as Map;
      chapter['localFilePath'] = relocate(chapter['localFilePath']);
      if (chapter['localFilePath'] == null &&
          chapter['downloadState'] == 'downloaded') {
        chapter['downloadState'] = 'notDownloaded';
      }
      final newChapterPath = chapter['localFilePath'] as String?;
      if (newChapterPath != null && imageSrcMap.isNotEmpty) {
        final chapterFile = File(newChapterPath);
        if (chapterFile.existsSync()) {
          final content = chapterFile.readAsStringSync();
          final fragment = html_parser.parseFragment(content);
          final imgElements = fragment.querySelectorAll('img[src], img[data-src]');
          var modified = false;
          for (final img in imgElements) {
            final src = img.attributes['src'];
            if (src != null && imageSrcMap.containsKey(src)) {
              img.attributes['src'] = imageSrcMap[src]!;
              modified = true;
            }
            final dataSrc = img.attributes['data-src'];
            if (dataSrc != null && imageSrcMap.containsKey(dataSrc)) {
              img.attributes['data-src'] = imageSrcMap[dataSrc]!;
              modified = true;
            }
          }
          if (modified) {
            chapterFile.writeAsStringSync(fragment.outerHtml, flush: true);
          }
        }
      }
    }
    manifest['metadata'] = metadata;
    return manifest;
  } catch (_) {
    for (final directory in created) {
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    rethrow;
  } finally {
    input.closeSync();
  }
});

// Enforce the declared size during inflation, including manifest decoding.
// A forged ZIP header must not turn a tiny archive into unbounded allocation.
class _LimitedOutput extends OutputStream {
  final int limit;
  _LimitedOutput(this.limit) : super(size: 1024);
  void _check(int additional) {
    if (length + additional > limit) {
      throw const FormatException('Backup data exceeds its declared size.');
    }
  }

  @override
  void writeByte(int value) {
    _check(1);
    super.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, [int? len]) {
    _check(len ?? bytes.length);
    super.writeBytes(bytes, len);
  }

  @override
  void writeInputStream(InputStreamBase stream) {
    _check(stream.length);
    super.writeInputStream(stream);
  }
}

List<int> _readEntry(ArchiveFile entry, int limit) {
  if (entry.size < 0 || entry.size > limit) {
    throw const FormatException('Backup entry exceeds supported limits.');
  }
  final output = _LimitedOutput(entry.size);
  entry.clear();
  entry.decompress(output);
  final bytes = output.getBytes();
  if (bytes.length != entry.size) {
    throw const FormatException(
      'Backup entry size does not match its contents.',
    );
  }
  return bytes;
}
