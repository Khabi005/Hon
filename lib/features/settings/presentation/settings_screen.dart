import 'dart:convert';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../core/files/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _storageBytes = 0;
  bool _isCleaning = false;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    final bytes = await StorageService.instance.getStorageUsageBytes();
    if (mounted) {
      setState(() => _storageBytes = bytes);
    }
  }

  Future<void> _cleanStaging() async {
    setState(() => _isCleaning = true);
    await StorageService.instance.cleanStaging();
    await _loadStorageInfo();
    if (mounted) {
      setState(() => _isCleaning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Temporary staging storage cleaned.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final mb = (_storageBytes / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.w700)),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        children: [
          // About Hon Header with master calligraphic logo
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? HonColors.darkCardBorder : HonColors.lightCardBorder,
                width: 0.5,
              ),
            ),
            child: Column(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.asset(
                    'assets/branding/hon_master_logo.jpg',
                    width: 90,
                    height: 90,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Hon',
                  style: HonTypography.sectionHeader(color: textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Version 1.0.0 (Build 1) • Local-first',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Quiet, responsive, and focused on books.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section: Storage Management
          Text(
            'STORAGE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(CupertinoIcons.chart_pie, color: HonColors.accentOrange),
                  title: const Text('Local Storage Used'),
                  trailing: Text(
                    '$mb MB',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(CupertinoIcons.trash, color: HonColors.accentCrimson),
                  title: const Text('Clean Temporary Staging'),
                  trailing: _isCleaning
                      ? const CupertinoActivityIndicator()
                      : const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: _isCleaning ? null : _cleanStaging,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section: Reader & Behavior
          Text(
            'PREFERENCES & DATA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(CupertinoIcons.cloud_download, color: HonColors.accentBlue),
                  title: Text('Download Library Prompt'),
                  subtitle: Text('Ask to add novel when downloading chapters'),
                  trailing: Icon(CupertinoIcons.check_mark, color: HonColors.accentGreen),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(CupertinoIcons.arrow_down_doc, color: HonColors.accentIndigo),
                  title: const Text('Export Metadata Backup'),
                  subtitle: const Text('Versioned SQLite & settings archive'),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: () async {
                    try {
                      final db = DatabaseService.instance;
                      final storage = StorageService.instance;
                      final backupData = {
                        'version': 1,
                        'exportedAt': DateTime.now().toIso8601String(),
                        'books': db.getAllBooks().map((b) => b.toMap()).toList(),
                        'library': db.getLibraryBooks().map((b) => b.id).toList(),
                      };
                      final backupFile = File('${storage.baseDir.path}/hon_backup_${DateTime.now().millisecondsSinceEpoch}.json');
                      await backupFile.writeAsString(jsonEncode(backupData));
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Backup created: ${p.basename(backupFile.path)}')),
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Backup failed: $e')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
