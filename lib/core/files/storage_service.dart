import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  }

  Directory get baseDir => _baseDir!;
  Directory get publicationsDir => Directory(p.join(_baseDir!.path, 'publications'));
  Directory get coversDir => Directory(p.join(_baseDir!.path, 'covers'));
  Directory get chaptersDir => Directory(p.join(_baseDir!.path, 'chapters'));
  Directory get stagingDir => Directory(p.join(_baseDir!.path, 'staging'));

  Future<String> computeFileHash(File file) async {
    final bytes = await file.readAsBytes();
    return sha256.convert(bytes).toString();
  }

  Future<String?> saveCoverImage(String bookId, Uint8List imageBytes) async {
    try {
      final file = File(p.join(coversDir.path, '$bookId.png'));
      await file.writeAsBytes(imageBytes);
      return file.path;
    } catch (e) {
      return null;
    }
  }

  Future<File> copyToStaging(File sourceFile) async {
    final stagingFile = File(p.join(
      stagingDir.path,
      'stage_${DateTime.now().millisecondsSinceEpoch}_${p.basename(sourceFile.path)}',
    ));
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
    } catch (_) {}
  }

  Future<void> cleanStaging() async {
    try {
      if (stagingDir.existsSync()) {
        for (final entity in stagingDir.listSync()) {
          entity.deleteSync(recursive: true);
        }
      }
    } catch (_) {}
  }

  Future<int> getStorageUsageBytes() async {
    int total = 0;
    for (final dir in [publicationsDir, coversDir, chaptersDir]) {
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
