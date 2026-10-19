import '../../../app/theme/app_appearance.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../core/backup/backup_service.dart';
import '../../../core/downloads/hon_download_manager.dart';
import '../../../core/sources/extension_repository_service.dart';
import '../../../core/sources/source_registry.dart';
import '../../../core/updates/chapter_update_service.dart';

class BackupRestoreScreen extends ConsumerStatefulWidget {
  const BackupRestoreScreen({super.key});
  @override
  ConsumerState<BackupRestoreScreen> createState() =>
      _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends ConsumerState<BackupRestoreScreen> {
  bool _files = true, _busy = false;
  String? _status;
  final _service = BackupService();
  void _message(String message) {
    if (mounted) setState(() => _status = message);
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    File? archive;
    try {
      _message('Pausing downloads…');
      await HonDownloadManager.instance.pauseAll();
      _message('Creating backup…');
      archive = await _service.create(includeFiles: _files);
      bool saved;
      if (Platform.isAndroid) {
        saved =
            await const MethodChannel(
              'com.hon.reader/files',
            ).invokeMethod<bool>('exportBackup', {'path': archive.path}) ??
            false;
      } else {
        final destination = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Hon Backup',
          fileName: archive.uri.pathSegments.last,
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        saved = destination != null;
        if (destination != null) await archive.copy(destination);
      }
      _message(
        saved
            ? 'Backup saved. Downloads were paused; resume them from Downloads when ready.'
            : 'Save cancelled. Your library is unchanged.',
      );
    } catch (error) {
      _message('Backup failed: $error');
    } finally {
      if (archive != null && await archive.exists()) await archive.delete();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
      if (picked?.files.first.path == null) return;
      final archive = File(picked!.files.first.path!);
      _message('Checking backup…');
      final preview = await _service.inspect(archive);
      if (!mounted) return;
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore Hon Backup?'),
          content: Text(
            '${preview.books} books and ${preview.files} files.\n\nBackup date: ${preview.createdAt}\n\nUnrelated books are kept. Matching books use the backup’s progress and metadata. Downloads will be paused. Source accounts are not included.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      _message('Pausing downloads…');
      await HonDownloadManager.instance.pauseAll();
      _message('Restoring…');
      await _service.restore(archive);
      await ExtensionRepositoryService.instance.init();
      await SourceRegistry.instance.init();
      await ChapterUpdateService.instance.init();
      ref.invalidate(readerPreferencesProvider);
      ref.invalidate(appAppearanceProvider);
      _message(
        'Backup restored. Download jobs are paused. Re-import publication files if this was a metadata-only backup. Custom extensions can be reinstalled from their repositories.',
      );
    } catch (error) {
      _message('Restore failed: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Backup & Restore')),
    body: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Keep a portable copy of your books, collections, bookmarks, progress and reading preferences.',
          style: TextStyle(height: 1.5),
        ),
        const SizedBox(height: 16),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Include saved book and chapter files'),
          subtitle: const Text(
            'Turn off for a smaller metadata-only backup. Source account sessions are excluded.',
          ),
          value: _files,
          onChanged: _busy ? null : (value) => setState(() => _files = value),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _backup,
          icon: const Icon(Icons.save_alt),
          label: const Text('Create Backup'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _busy ? null : _restore,
          icon: const Icon(Icons.restore),
          label: const Text('Restore Backup'),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(_status!, style: const TextStyle(height: 1.5)),
          ),
      ],
    ),
  );
}
