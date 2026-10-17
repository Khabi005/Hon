import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/sources/source_registry.dart';
import 'source_catalog_screen.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  int _selectedTabIndex = 0; // 0: Sources, 1: Extensions
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final textSecondary = isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary;

    final installedSources = SourceRegistry.instance.getInstalledSources();
    final allExtensions = SourceRegistry.instance.getExtensions();

    final query = _searchQuery.trim().toLowerCase();
    final displayedSources = query.isEmpty
        ? installedSources
        : installedSources.where((s) => s.name.toLowerCase().contains(query)).toList();

    final displayedExtensions = query.isEmpty
        ? allExtensions
        : allExtensions.where((e) => e.name.toLowerCase().contains(query) || e.lang.toLowerCase().contains(query)).toList();

    final uninstalledCount = allExtensions.where((e) => !e.isInstalled).length;

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Top App Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Browse',
                      style: HonTypography.largeTitle(color: textPrimary),
                    ),
                    IconButton(
                      icon: Icon(CupertinoIcons.question_circle, color: textSecondary, size: 22),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Browse online sources & install extensions.')),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),

            // Segmented Control: Sources | Extensions (Matching Reference Screenshot)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                child: Container(
                  height: 38,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      _buildTabButton('Sources', 0, null, isDark),
                      _buildTabButton('Extensions', 1, uninstalledCount > 0 ? '$uninstalledCount' : null, isDark),
                    ],
                  ),
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

            // Tab View Body
            if (_selectedTabIndex == 0)
              _buildSourcesList(displayedSources, textPrimary, textSecondary, isDark)
            else
              _buildExtensionsList(displayedExtensions, textPrimary, textSecondary, isDark),

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(String title, int index, String? badge, bool isDark) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
            _searchQuery = '';
            _searchController.clear();
          });
        },
        child: Container(
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? (isDark ? Colors.white : Colors.black)
                      : (isDark ? Colors.white60 : Colors.black54),
                ),
              ),
              if (badge != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: HonColors.accentOrange,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    badge,
                    style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
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
              Icon(CupertinoIcons.compass, size: 48, color: textSecondary.withOpacity(0.4)),
              const SizedBox(height: 12),
              Text(
                'No Sources Installed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: textPrimary),
              ),
              const SizedBox(height: 6),
              Text(
                'Switch to the Extensions tab to install novel sources.',
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
        delegate: SliverChildBuilderDelegate(
          (context, index) {
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
                    color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF2F2F7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                      width: 0.5,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Source Icon Avatar
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2B4353),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          source.name.substring(0, 1),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Name & Language
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              source.name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${source.lang} • v${source.version}',
                              style: TextStyle(fontSize: 12, color: textSecondary),
                            ),
                          ],
                        ),
                      ),

                      // "Latest" button & Pin icon (matching reference)
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SourceCatalogScreen(sourceMeta: source),
                            ),
                          );
                        },
                        child: const Text('Latest', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Icon(CupertinoIcons.pin, size: 16, color: textSecondary),
                    ],
                  ),
                ),
              ),
            );
          },
          childCount: sources.length,
        ),
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
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final ext = extensions[index];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF2F2F7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: ext.isInstalled ? const Color(0xFF1B4965) : const Color(0xFF3D3D3D),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        ext.name.substring(0, 1),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),

                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ext.name,
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
                        ],
                      ),
                    ),

                    // Install / Uninstall action
                    if (ext.isInstalled)
                      IconButton(
                        icon: const Icon(CupertinoIcons.gear_alt, size: 20),
                        color: textSecondary,
                        onPressed: () {
                          _showExtensionSettings(ext);
                        },
                      )
                    else
                      IconButton(
                        icon: const Icon(CupertinoIcons.arrow_down_to_line_alt, size: 20),
                        color: HonColors.accentOrange,
                        onPressed: () async {
                          await SourceRegistry.instance.installExtension(ext.id);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Installed ${ext.name}! Available in Sources tab.')),
                          );
                        },
                      ),
                  ],
                ),
              ),
            );
          },
          childCount: extensions.length,
        ),
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
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            child: const Text('Uninstall Extension'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await SourceRegistry.instance.uninstallExtension(ext.id);
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
