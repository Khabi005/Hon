import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../shared/widgets/hon_large_title_header.dart';
import '../../../core/sources/source_registry.dart';
import '../../../core/sources/installed_extension_service.dart';
import 'source_catalog_screen.dart';
import '../../../shared/widgets/hon_segmented_control.dart';
import '../../settings/presentation/extension_repositories_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  int _selectedTabIndex = 0; // 0: Sources, 1: Extensions
  String _searchQuery = '';
  String? _languageFilter;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _busyExtensions = {};

  void _extensionMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _install(ExtensionMeta extension) async {
    if (extension.id.startsWith('ext_')) {
      final approved = await showCupertinoDialog<bool>(
        context: context,
        builder: (context) => CupertinoAlertDialog(
          title: Text('Install ${extension.name}?'),
          content: Text(
            '${extension.description}\n\nThis community script runs inside Hon and can request web pages. Install it only if you trust its repository.',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Install'),
            ),
          ],
        ),
      );
      if (approved != true || !mounted) return;
    }
    if (!_busyExtensions.add(extension.id)) return;
    setState(() {});
    try {
      await SourceRegistry.instance.installExtension(extension.id);
      _extensionMessage('Installed ${extension.name}.');
    } catch (error) {
      _extensionMessage('Could not install ${extension.name}: $error');
    } finally {
      _busyExtensions.remove(extension.id);
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    SourceRegistry.instance.changeNotifier.addListener(_onRegistryChanged);
  }

  @override
  void dispose() {
    SourceRegistry.instance.changeNotifier.removeListener(_onRegistryChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onRegistryChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? HonColors.darkTextPrimary
        : HonColors.lightTextPrimary;
    final textSecondary = isDark
        ? HonColors.darkTextSecondary
        : HonColors.lightTextSecondary;

    final installedSources = SourceRegistry.instance.getInstalledSources();
    final allExtensions = SourceRegistry.instance.getExtensions();

    final query = _searchQuery.trim().toLowerCase();
    bool matches(ExtensionMeta source) =>
        (_languageFilter == null ||
            SourceRegistry.languageName(source.lang) == _languageFilter) &&
        (query.isEmpty ||
            '${source.name} ${SourceRegistry.languageName(source.lang)}'
                .toLowerCase()
                .contains(query));
    final displayedSources = installedSources.where(matches).toList()
      ..sort((a, b) {
        final pinnedA = SourceRegistry.instance.isPinned(a.id);
        final pinnedB = SourceRegistry.instance.isPinned(b.id);
        return pinnedA == pinnedB
            ? a.name.compareTo(b.name)
            : pinnedA
            ? -1
            : 1;
      });
    final displayedExtensions = allExtensions.where(matches).toList();
    final languages =
        allExtensions
            .map((source) => SourceRegistry.languageName(source.lang))
            .toSet()
            .toList()
          ..sort();

    final uninstalledCount = allExtensions.where((e) => !e.isInstalled).length;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('browse-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            if (SourceRegistry.instance.isPreparing)
              const SliverToBoxAdapter(
                child: ListTile(
                  leading: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  title: Text('Preparing bundled sources…'),
                ),
              ),
            SliverHonLargeTitle(
              title: 'Browse',
              actions: [
                IconButton(
                  icon: Icon(
                    CupertinoIcons.square_stack_3d_up,
                    color: textSecondary,
                    size: 22,
                  ),
                  tooltip: 'Extension repositories',
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ExtensionRepositoriesScreen(),
                    ),
                  ),
                ),
              ],
            ),

            // Segmented Control: Sources | Extensions (Matching Reference Screenshot)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 6,
                ),
                child: HonSegmentedControl(
                  labels: [
                    'Sources',
                    uninstalledCount > 0
                        ? 'Extensions · $uninstalledCount'
                        : 'Extensions',
                  ],
                  selected: _selectedTabIndex,
                  onChanged: (index) => setState(() {
                    _selectedTabIndex = index;
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                ),
              ),
            ),

            // Search Bar for Current Tab
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  style: TextStyle(color: textPrimary),
                  placeholder: _selectedTabIndex == 0
                      ? 'Search installed sources...'
                      : 'Search repository extensions...',
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_selectedTabIndex == 0 ? displayedSources.length : displayedExtensions.length} sources',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Source language',
                      onSelected: (value) => setState(
                        () => _languageFilter = value.isEmpty ? null : value,
                      ),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: '',
                          child: Text('All languages'),
                        ),
                        ...languages.map(
                          (language) => PopupMenuItem(
                            value: language,
                            child: Text(language),
                          ),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Text(
                              _languageFilter ?? 'All languages',
                              style: TextStyle(
                                color: textPrimary,
                                fontSize: 13,
                              ),
                            ),
                            Icon(
                              Icons.expand_more,
                              size: 18,
                              color: textSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Tab View Body
            if (_selectedTabIndex == 0)
              _buildSourcesList(
                displayedSources,
                textPrimary,
                textSecondary,
                isDark,
              )
            else
              _buildExtensionsList(
                displayedExtensions,
                textPrimary,
                textSecondary,
                isDark,
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 128)),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceAvatar(ExtensionMeta source, {required bool isDark}) {
    final bgColor = source.isInstalled
        ? const Color(0xFF1B4965)
        : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA));
    final textColor = source.isInstalled || isDark
        ? Colors.white
        : Colors.black87;

    Widget letterFallback() => Center(
      child: Text(
        source.name.isNotEmpty
            ? source.name.substring(0, 1).toUpperCase()
            : '?',
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: source.iconUrl != null && source.iconUrl!.isNotEmpty
          ? Image.network(
              source.iconUrl!,
              width: 44,
              height: 44,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => letterFallback(),
            )
          : letterFallback(),
    );
  }

  Widget _buildSourcesList(
    List<ExtensionMeta> sources,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    if (sources.isEmpty) {
      return SliverFillRemaining(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                CupertinoIcons.compass,
                size: 48,
                color: textSecondary.withOpacity(0.4),
              ),
              const SizedBox(height: 12),
              Text(
                (_searchQuery.isNotEmpty || _languageFilter != null)
                    ? 'No Matching Sources'
                    : 'No Sources Installed',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                (_searchQuery.isNotEmpty || _languageFilter != null)
                    ? 'Try another name or language.'
                    : 'Switch to Extensions to install a source.',
                style: TextStyle(fontSize: 13, color: textSecondary),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final source = sources[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SourceCatalogScreen(sourceMeta: source),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? HonColors.darkSurface
                      : HonColors.lightSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark
                        ? Colors.white10
                        : Colors.black.withOpacity(0.06),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    // Source Icon Avatar
                    _buildSourceAvatar(source, isDark: isDark),
                    const SizedBox(width: 14),

                    // Name & Language
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${SourceRegistry.languageName(source.lang)} • v${source.version}',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),

                    IconButton(
                      tooltip: SourceRegistry.instance.isPinned(source.id)
                          ? 'Unpin source'
                          : 'Pin source',
                      onPressed: () async {
                        try {
                          await SourceRegistry.instance.togglePinned(source.id);
                        } catch (error) {
                          _extensionMessage('Could not save pin: $error');
                        }
                      },
                      icon: Icon(
                        SourceRegistry.instance.isPinned(source.id)
                            ? CupertinoIcons.pin_fill
                            : CupertinoIcons.pin,
                        size: 18,
                        color: textSecondary,
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 14,
                      color: textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          );
        }, childCount: sources.length),
      ),
    );
  }

  Widget _buildExtensionsList(
    List<ExtensionMeta> extensions,
    Color textPrimary,
    Color textSecondary,
    bool isDark,
  ) {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final ext = extensions[index];
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? HonColors.darkSurface : HonColors.lightSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark
                      ? Colors.white10
                      : Colors.black.withOpacity(0.06),
                  width: 0.5,
                ),
              ),
              child: Row(
                children: [
                  _buildSourceAvatar(ext, isDark: isDark),
                  const SizedBox(width: 14),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ext.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${ext.lang} • ${ext.version}',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                        if (ext.isInstalled && !ext.isEnabled)
                          Text(
                            'Disabled',
                            style: TextStyle(
                              fontSize: 12,
                              color: textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),

                  // Install / Uninstall action
                  if (ext.isInstalled)
                    IconButton(
                      tooltip: 'Manage extension',
                      icon: const Icon(CupertinoIcons.gear_alt, size: 20),
                      color: textSecondary,
                      onPressed: _busyExtensions.contains(ext.id)
                          ? null
                          : () {
                              _showExtensionSettings(ext);
                            },
                    )
                  else
                    IconButton(
                      tooltip: 'Install extension',
                      icon: const Icon(
                        CupertinoIcons.arrow_down_to_line_alt,
                        size: 20,
                      ),
                      color: HonColors.accentOrange,
                      onPressed: _busyExtensions.contains(ext.id)
                          ? null
                          : () => _install(ext),
                    ),
                ],
              ),
            ),
          );
        }, childCount: extensions.length),
      ),
    );
  }

  void _showExtensionSettings(ExtensionMeta ext) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(ext.name),
        message: Text('${ext.lang} • v${ext.version}\n${ext.description}'),
        actions: [
          if (ext.id.startsWith('ext_'))
            CupertinoActionSheetAction(
              child: Text(
                ext.isEnabled ? 'Disable Extension' : 'Enable Extension',
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  await InstalledExtensionService.instance.setEnabled(
                    ext.id,
                    !ext.isEnabled,
                  );
                } catch (error) {
                  _extensionMessage('Could not change extension state: $error');
                }
              },
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            child: const Text('Uninstall Extension'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              try {
                await SourceRegistry.instance.uninstallExtension(ext.id);
              } catch (error) {
                _extensionMessage('Could not uninstall ${ext.name}: $error');
              }
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }
}
