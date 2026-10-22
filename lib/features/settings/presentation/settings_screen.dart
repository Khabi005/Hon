import 'app_appearance_section.dart';
import '../../../app/theme/glass_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../core/database/database_service.dart';
import '../../../core/files/storage_service.dart';
import '../../reader/sheets/themes_settings_sheet.dart';
import 'extension_repositories_screen.dart';
import 'backup_restore_screen.dart';
import '../../../core/downloads/hon_download_manager.dart';
import '../../../core/updates/background_update_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _storageBytes = 0;
  bool _isCleaning = false;
  bool _wifiOnly = false;
  bool _changingNetwork = false;
  BackgroundUpdateSettings _updateSettings = const BackgroundUpdateSettings();
  bool _triggeringUpdate = false;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
    _loadUpdateSettings();
    HonDownloadManager.instance.wifiOnly.then((value) {
      if (mounted) setState(() => _wifiOnly = value);
    });
  }

  Future<void> _loadUpdateSettings() async {
    final settings = await BackgroundUpdateService.instance.getSettings();
    if (mounted) {
      setState(() => _updateSettings = settings);
    }
  }

  String _formatDateTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadStorageInfo() async {
    final bytes = await StorageService.instance.getStorageUsageBytes();
    if (mounted) {
      setState(() => _storageBytes = bytes);
    }
  }

  Future<void> _cleanStaging() async {
    setState(() => _isCleaning = true);
    try {
      await StorageService.instance.cleanStaging();
      await _loadStorageInfo();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Temporary staging storage cleaned.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not clean temporary storage: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mb = (_storageBytes / (1024 * 1024)).toStringAsFixed(1);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        flexibleSpace: GlassStyle.richOf(context)
            ? const GlassSurface(radius: 0, child: SizedBox.expand())
            : null,
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
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
          const AppAppearanceSection(),
          Text(
            'READER',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark
                  ? HonColors.darkTextSecondary
                  : HonColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GlassSurface(
            radius: 14,
            child: Consumer(
              builder: (context, ref, _) {
                final prefs = ref.watch(readerPreferencesProvider);
                return ListTile(
                  leading: const Icon(
                    CupertinoIcons.textformat_size,
                    color: HonColors.accentOrange,
                  ),
                  title: const Text('Reading appearance and layout'),
                  subtitle: Text(
                    '${prefs.themeConfig.name} • ${prefs.fontFamily.displayName} • ${prefs.layoutMode == ReaderLayoutMode.paginated ? 'Paged' : 'Scroll'}',
                  ),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: () => ThemesSettingsSheet.show(context),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          ListTile(
            leading: const Icon(
              CupertinoIcons.timer,
              color: HonColors.accentBlue,
            ),
            title: const Text('Daily reading goal'),
            subtitle: Text(
              '${DatabaseService.instance.getDailyGoalMinutes()} minutes',
            ),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () async {
              final current = DatabaseService.instance.getDailyGoalMinutes();
              final choices = {5, 10, 15, 20, 30, 45, 60, current}.toList()
                ..sort();
              final selected = await showDialog<int>(
                context: context,
                builder: (context) => SimpleDialog(
                  title: const Text('Daily reading goal'),
                  children: choices
                      .map(
                        (minutes) => SimpleDialogOption(
                          onPressed: () => Navigator.of(context).pop(minutes),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              '${minutes == current ? '✓ ' : ''}$minutes minutes',
                            ),
                          ),
                        ),
                      )
                      .toList(),
                ),
              );
              if (selected != null) {
                await DatabaseService.instance.setDailyGoalMinutes(selected);
                if (mounted) setState(() {});
              }
            },
          ),
          const SizedBox(height: 20),

          Text(
            'SOURCES & EXTENSIONS',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark
                  ? HonColors.darkTextSecondary
                  : HonColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GlassSurface(
            radius: 14,
            child: ListTile(
              leading: const Icon(
                CupertinoIcons.book,
                color: HonColors.accentBlue,
              ),
              title: const Text('Extension repositories'),
              subtitle: const Text('Add and refresh Shosetsu catalogs'),
              trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const ExtensionRepositoriesScreen(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section: Storage Management
          Text(
            'DOWNLOADS & STORAGE',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark
                  ? HonColors.darkTextSecondary
                  : HonColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GlassSurface(
            radius: 14,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Wi-Fi-only downloads'),
                  subtitle: const Text(
                    'Use unmetered networks for new and resumed downloads',
                  ),
                  value: _wifiOnly,
                  onChanged: _changingNetwork
                      ? null
                      : (value) async {
                          setState(() => _changingNetwork = true);
                          try {
                            await HonDownloadManager.instance.setWifiOnly(
                              value,
                            );
                            if (mounted) setState(() => _wifiOnly = value);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Could not update downloads: $error',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => _changingNetwork = false);
                            }
                          }
                        },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.chart_pie,
                    color: HonColors.accentOrange,
                  ),
                  title: const Text('Local Storage Used'),
                  trailing: Text(
                    '$mb MB',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.trash,
                    color: HonColors.accentCrimson,
                  ),
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

          ListTile(
            leading: const Icon(CupertinoIcons.doc_text),
            title: const Text('Open-source licenses'),
            trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
            onTap: () =>
                showLicensePage(context: context, applicationName: 'Hon'),
          ),
          const SizedBox(height: 24),

          Text(
            'AUTOMATIC UPDATES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark
                  ? HonColors.darkTextSecondary
                  : HonColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GlassSurface(
            radius: 14,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text('Check for updates in background'),
                  subtitle: const Text(
                    'Periodically check ongoing library novels for new chapters',
                  ),
                  value: _updateSettings.enabled,
                  onChanged: (val) async {
                    await BackgroundUpdateService.instance.saveSettings(
                      enabled: val,
                    );
                    await _loadUpdateSettings();
                  },
                ),
                if (_updateSettings.enabled) ...[
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Check frequency'),
                    trailing: DropdownButton<int>(
                      value: _updateSettings.intervalHours,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 6, child: Text('Every 6 hours')),
                        DropdownMenuItem(value: 12, child: Text('Every 12 hours')),
                        DropdownMenuItem(value: 24, child: Text('Daily (24 hours)')),
                      ],
                      onChanged: (hours) async {
                        if (hours != null) {
                          await BackgroundUpdateService.instance.saveSettings(
                            intervalHours: hours,
                          );
                          await _loadUpdateSettings();
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Wi-Fi only'),
                    subtitle: const Text(
                      'Only check when connected to unmetered network',
                    ),
                    value: _updateSettings.unmeteredOnly,
                    onChanged: (val) async {
                      await BackgroundUpdateService.instance.saveSettings(
                        unmeteredOnly: val,
                      );
                      await _loadUpdateSettings();
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Requires battery not low'),
                    subtitle: const Text('Wait if device battery is low'),
                    value: _updateSettings.requiresBatteryNotLow,
                    onChanged: (val) async {
                      await BackgroundUpdateService.instance.saveSettings(
                        requiresBatteryNotLow: val,
                      );
                      await _loadUpdateSettings();
                    },
                  ),
                ],
                const Divider(height: 1),
                ListTile(
                  title: const Text('Last check'),
                  subtitle: Text(
                    _updateSettings.lastCheckTime == null
                        ? 'Never checked'
                        : '${_formatDateTime(_updateSettings.lastCheckTime!)}\n${_updateSettings.lastCheckStatus ?? "Up to date"}',
                  ),
                  isThreeLine: _updateSettings.lastCheckTime != null,
                  trailing: _triggeringUpdate
                      ? const CupertinoActivityIndicator()
                      : TextButton(
                          onPressed: () async {
                            setState(() => _triggeringUpdate = true);
                            try {
                              await BackgroundUpdateService.instance
                                  .triggerImmediateCheck();
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Update check started in background',
                                    ),
                                  ),
                                );
                              }
                            } finally {
                              if (mounted) {
                                setState(() => _triggeringUpdate = false);
                              }
                            }
                          },
                          child: const Text('Check now'),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section: Reader & Behavior
          Text(
            'LIBRARY DATA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.6,
              color: isDark
                  ? HonColors.darkTextSecondary
                  : HonColors.lightTextSecondary,
            ),
          ),
          const SizedBox(height: 8),
          GlassSurface(
            radius: 14,
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(
                    CupertinoIcons.cloud_download,
                    color: HonColors.accentBlue,
                  ),
                  title: Text('Independent downloads'),
                  subtitle: Text(
                    'Downloading a novel does not force it into your library',
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.arrow_down_doc,
                    color: HonColors.accentIndigo,
                  ),
                  title: const Text('Backup & Restore'),
                  subtitle: const Text(
                    'Books, collections, settings and optional files',
                  ),
                  trailing: const Icon(CupertinoIcons.chevron_right, size: 16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BackupRestoreScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ListTile(
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/branding/hon_master_logo.jpg',
                width: 42,
                height: 42,
              ),
            ),
            title: const Text('Hon'),
            subtitle: const Text('Version 0.0.2 • Local-first reading'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: 'Hon',
              applicationVersion: '0.0.2',
              applicationIcon: Image.asset(
                'assets/branding/hon_master_logo.jpg',
                width: 48,
                height: 48,
              ),
              children: const [
                Text('Quiet, responsive, and focused on books.'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
