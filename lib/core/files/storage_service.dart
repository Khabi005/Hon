import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../utils/log_ignored.dart';

class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();
  StorageService._();

  Directory? _baseDir;

  Future<void> init() async {
    _baseDir = await getApplicationDocumentsDirectory();
    await publicationsDir.create(recursive: true);
    await coversDir.create(recursive: true);
    await chaptersDir.create(recursive: true);
    await stagingDir.create(recursive: true);
    await imagesDir.create(recursive: true);
  }

  Directory get baseDir => _baseDir!;
  Directory get publicationsDir =>
      Directory(p.join(_baseDir!.path, 'publications'));
  Directory get coversDir => Directory(p.join(_baseDir!.path, 'covers'));
  Directory get chaptersDir => Directory(p.join(_baseDir!.path, 'chapters'));
  Directory get stagingDir => Directory(p.join(_baseDir!.path, 'staging'));
  Directory get imagesDir => Directory(p.join(_baseDir!.path, 'images'));

  /// Only publications, covers, chapters, and images owned by Hon may be deleted.
  /// Resolves actual filesystem links; handles both existing files and absent destinations.
  bool isPathInsideManagedStorage(String filePath, {Directory? specificRoot}) {
    if (_baseDir == null) return false;
    try {
      final normalized = p.normalize(p.absolute(filePath));
      final candidateRoots = specificRoot != null
          ? [specificRoot]
          : [publicationsDir, coversDir, chaptersDir, imagesDir];

      final file = File(normalized);
      if (file.existsSync()) {
        final target = file.resolveSymbolicLinksSync();
        for (final dir in candidateRoots) {
          if (!dir.existsSync()) continue;
          final root = dir.resolveSymbolicLinksSync();
          if (p.isWithin(root, target) || root == target) return true;
        }
        return false;
      } else {
        // Destination does not exist on disk yet or was removed.
        // Traverse upwards to nearest existing ancestor to guard against symlink traversal.
        var dir = file.parent;
        while (!dir.existsSync() && dir.path != dir.parent.path) {
          dir = dir.parent;
        }
        if (!dir.existsSync()) return false;
        final resolvedAncestor = dir.resolveSymbolicLinksSync();
        for (final managedDir in candidateRoots) {
          if (!managedDir.existsSync()) continue;
          final root = managedDir.resolveSymbolicLinksSync();
          if (p.isWithin(root, resolvedAncestor) || root == resolvedAncestor) {
            final rootNorm = p.normalize(root);
            if (p.isWithin(rootNorm, normalized) || rootNorm == normalized) {
              return true;
            }
          }
        }
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  void setBaseDirForTesting(Directory dir) {
    _baseDir = dir;
  }

  Future<String> computeFileHash(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  Future<String?> saveCoverImage(String bookId, Uint8List imageBytes) async {
    try {
      final extension =
          imageBytes.length >= 2 &&
              imageBytes[0] == 0xff &&
              imageBytes[1] == 0xd8
          ? 'jpg'
          : imageBytes.length >= 4 &&
                String.fromCharCodes(imageBytes.take(4)) == 'RIFF'
          ? 'webp'
          : imageBytes.length >= 3 &&
                String.fromCharCodes(imageBytes.take(3)) == 'GIF'
          ? 'gif'
          : 'png';
      final safeId =
          p.basename(bookId) == bookId &&
              !bookId.contains('\\') &&
              bookId != '.' &&
              bookId != '..'
          ? bookId
          : sha256.convert(utf8.encode(bookId)).toString();
      final file = File(p.join(coversDir.path, '$safeId.$extension'));
      await file.writeAsBytes(imageBytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  Future<File> copyToStaging(File sourceFile) async {
    final stagingFile = File(
      p.join(
        stagingDir.path,
        'stage_${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourceFile.path)}',
      ),
    );
    return await sourceFile.copy(stagingFile.path);
  }

  Future<File> promoteStagingFile(File stagedFile, String finalFilename) async {
    final dest = File(p.join(publicationsDir.path, finalFilename));
    return await stagedFile.rename(dest.path);
  }

  Future<void> deleteStagingFile(File stagedFile) async {
    try {
      if (stagedFile.existsSync()) {
        stagedFile.deleteSync();
      }
    } catch (e) {
      logIgnored(e, 'storage_service');
    }
  }

  Future<void> cleanStaging() async {
    try {
      if (stagingDir.existsSync()) {
        for (final entity in stagingDir.listSync()) {
          entity.deleteSync(recursive: true);
        }
      }
    } catch (e) {
      logIgnored(e, 'storage_service');
    }
  }

  Future<int> getStorageUsageBytes() async {
    int total = 0;
    for (final dir in [publicationsDir, coversDir, chaptersDir, imagesDir]) {
      if (dir.existsSync()) {
        for (final f in dir.listSync(recursive: true)) {
          if (f is File) {
            total += f.lengthSync();
          }
        }
      }
    }
    return total;
  }
}
