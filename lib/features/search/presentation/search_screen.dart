import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/models/book.dart';
import '../../../core/models/novel_source.dart';
import '../../../core/sources/source_registry.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../../shared/widgets/hon_empty_state.dart';
import '../../browse/presentation/source_catalog_screen.dart';
import '../../reader/presentation/reader_navigator.dart';
import '../../../shared/widgets/hon_large_title_header.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _activeFilter = 'All'; // 'Pinned', 'All', 'Has results'
  Timer? _debounce;
  int _searchGeneration = 0;
  final Map<String, List<SourceNovelSummary>> _sourceResults = {};
  final Map<String, String> _sourceErrors = {};
  final Set<String> _loadingSources = {};
  Set<String>? _selectedSourceIds;

  @override
  void initState() {
    super.initState();
    _loadSourceSelection();
    SourceRegistry.instance.changeNotifier.addListener(_sourcesChanged);
  }

  void _sourcesChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSourceSelection() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = prefs.getStringList('hon_global_search_sources');
    if (saved != null) setState(() => _selectedSourceIds = saved.toSet());
  }

  List<ExtensionMeta> _searchSources() {
    final all = SourceRegistry.instance.getInstalledSources();
    if (_selectedSourceIds != null) {
      return all.where((s) => _selectedSourceIds!.contains(s.id)).toList();
    }
    final pinned = all
        .where((s) => SourceRegistry.instance.isPinned(s.id))
        .toList();
    if (pinned.isNotEmpty) return pinned;
    const preferred = {
      'RoyalRoad',
      'ScribbleHub',
      'NovelFull',
      'Free Web Novel',
      'FreeWebNovel',
      'Foxaholic',
      'NovelBuddy',
    };
    final defaults = all
        .where((s) => preferred.contains(s.name))
        .take(6)
        .toList();
    return defaults.isNotEmpty
        ? defaults
        : all.where((s) => s.lang == 'en' || s.lang == 'eng').take(6).toList();
  }

  Future<void> _chooseSources() async {
    final sources = SourceRegistry.instance.getInstalledSources();
    final selected = _searchSources().map((s) => s.id).toSet();
    var filter = '';
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, update) {
          final visible = sources
              .where(
                (source) =>
                    '${source.name} ${SourceRegistry.languageName(source.lang)}'
                        .toLowerCase()
                        .contains(filter.toLowerCase()),
              )
              .toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * .8,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 12, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Search sources (${selected.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, selected),
                          child: const Text('Done'),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: TextField(
                      decoration: const InputDecoration(
                        hintText: 'Find a source or language',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) => update(() => filter = value),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => update(
                          () => selected.addAll(visible.map((s) => s.id)),
                        ),
                        child: const Text('Select visible'),
                      ),
                      TextButton(
                        onPressed: () => update(selected.clear),
                        child: const Text('Clear'),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final source = visible[index];
                        return CheckboxListTile(
                          value: selected.contains(source.id),
                          title: Text(source.name),
                          subtitle: Text(
                            SourceRegistry.languageName(source.lang),
                          ),
                          onChanged: (checked) => update(() {
                            checked == true
                                ? selected.add(source.id)
                                : selected.remove(source.id);
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _selectedSourceIds = result);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('hon_global_search_sources', result.toList());
    if (mounted) _onQueryChanged(_query);
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final generation = ++_searchGeneration;
    setState(() {
      _query = value;
      _sourceResults.clear();
      _sourceErrors.clear();
      _loadingSources.clear();
      if (value.trim().isNotEmpty) {
        _loadingSources.addAll(_searchSources().map((s) => s.id));
      }
    });
    if (value.trim().isEmpty) return;
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _searchAll(value.trim(), generation),
    );
  }

  Future<void> _searchAll(String query, int generation) async {
    final sources = _searchSources();
    if (!mounted || generation != _searchGeneration) return;
    setState(() => _loadingSources.addAll(sources.map((source) => source.id)));
    for (var start = 0; start < sources.length; start += 3) {
      if (!mounted || generation != _searchGeneration) return;
      final batch = sources.skip(start).take(3);
      await Future.wait(
        batch.map((source) => _searchOne(source, query, generation)),
      );
    }
  }

  Future<void> _searchOne(
    ExtensionMeta source,
    String query,
    int generation,
  ) async {
    try {
      final results = await SourceRegistry.instance.searchSource(
        source.id,
        query,
      );
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _sourceResults[source.id] = results;
        _sourceErrors.remove(source.id);
        _loadingSources.remove(source.id);
      });
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _sourceErrors[source.id] = e.toString();
        _loadingSources.remove(source.id);
      });
    }
  }

  void _retrySource(ExtensionMeta source) {
    setState(() {
      _sourceErrors.remove(source.id);
      _loadingSources.add(source.id);
    });
    _searchOne(source, _query.trim(), _searchGeneration);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    SourceRegistry.instance.changeNotifier.removeListener(_sourcesChanged);
    _searchController.dispose();
    super.dispose();
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

    final allLibraryBooks = ref.watch(navigationTabProvider) == 3
        ? ref.watch(libraryBooksProvider)
        : ref.read(libraryBooksProvider);

    // 1. Library Matches
    final matchingLibraryBooks = _query.trim().isEmpty
        ? <Book>[]
        : allLibraryBooks.where((b) {
            final q = _query.toLowerCase();
            return b.title.toLowerCase().contains(q) ||
                b.author.toLowerCase().contains(q);
          }).toList();

    // 2. Global Source Matches
    final installedSources = _searchSources();
    final visibleSources = installedSources
        .where(
          (source) =>
              (_activeFilter != 'Pinned' ||
                  SourceRegistry.instance.isPinned(source.id)) &&
              (_activeFilter != 'Has results' ||
                  (_sourceResults[source.id]?.isNotEmpty ?? false) ||
                  _loadingSources.contains(source.id)),
        )
        .toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('search-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            const SliverHonLargeTitle(title: 'Search'),

            // Search Bar Input
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  style: TextStyle(color: textPrimary),
                  placeholder: 'Search library & selected sources...',
                  onChanged: _onQueryChanged,
                  onSuffixTap: () {
                    _searchController.clear();
                    _onQueryChanged('');
                  },
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${installedSources.length} sources selected',
                        style: TextStyle(fontSize: 12, color: textSecondary),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _chooseSources,
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('Choose sources'),
                    ),
                  ],
                ),
              ),
            ),

            // Filter Chips Bar (Matching Taison reference: Pinned | All | Has results)
            if (_query.trim().isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Wrap(
                    runSpacing: 8,
                    children: [
                      _buildFilterChip(
                        'Pinned',
                        CupertinoIcons.pin_fill,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'All',
                        CupertinoIcons.check_mark,
                        isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        'Has results',
                        CupertinoIcons.slider_horizontal_3,
                        isDark,
                      ),
                    ],
                  ),
                ),
              ),

            // Empty Query Initial State
            if (_query.trim().isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: HonEmptyState(
                  icon: CupertinoIcons.search,
                  title: 'Find your next good read',
                  message:
                      'Search your library and selected online sources by title or author.',
                ),
              )
            else ...[
              // Section 1: In Library
              if (matchingLibraryBooks.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'In Your Library',
                          style: HonTypography.sectionHeader(
                            color: textPrimary,
                          ),
                        ),
                        Text(
                          '${matchingLibraryBooks.length} found',
                          style: TextStyle(fontSize: 12, color: textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 140,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      scrollDirection: Axis.horizontal,
                      itemCount: matchingLibraryBooks.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 12),
                      itemBuilder: (context, index) {
                        final book = matchingLibraryBooks[index];
                        return GestureDetector(
                          onTap: () => ReaderNavigator.openBook(context, book),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              BookCoverWidget(
                                title: book.title,
                                author: book.author,
                                coverPath: book.coverPath,
                                width: 72,
                                height: 104,
                                borderRadius: 6,
                              ),
                              const SizedBox(height: 4),
                              SizedBox(
                                width: 72,
                                child: Text(
                                  book.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
              ],

              // Section 2: Global Sources Search Results (Grouped by Source, matching Taison)
              SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final source = visibleSources[index];
                  final sourceNovels = _sourceResults[source.id] ?? [];
                  final loading = _loadingSources.contains(source.id);
                  final error = _sourceErrors[source.id];
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Source Header Bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      source.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: textPrimary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    source.lang,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip:
                                  SourceRegistry.instance.isPinned(source.id)
                                  ? 'Unpin source'
                                  : 'Pin source',
                              onPressed: () async {
                                await SourceRegistry.instance.togglePinned(
                                  source.id,
                                );
                                if (mounted) setState(() {});
                              },
                              icon: Icon(
                                SourceRegistry.instance.isPinned(source.id)
                                    ? CupertinoIcons.pin_fill
                                    : CupertinoIcons.pin,
                                size: 18,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Source Results Row or "No results found"
                        if (loading)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: CupertinoActivityIndicator(),
                          )
                        else if (error != null)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Search failed: $error',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textSecondary,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () => _retrySource(source),
                                child: const Text('Retry'),
                              ),
                            ],
                          )
                        else if (sourceNovels.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No results found',
                              style: TextStyle(
                                fontSize: 13,
                                color: textSecondary,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        else
                          SizedBox(
                            height:
                                155 +
                                (MediaQuery.textScalerOf(context).scale(11) -
                                        11) *
                                    3,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: sourceNovels.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final novel = sourceNovels[index];
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            SourceNovelDetailsScreen(
                                              novel: novel,
                                              sourceId: source.id,
                                              sourceName: source.name,
                                            ),
                                      ),
                                    );
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      BookCoverWidget(
                                        title: novel.title,
                                        author: novel.author ?? source.name,
                                        coverPath: novel.coverUrl,
                                        width: 80,
                                        height: 115,
                                        borderRadius: 6,
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 80,
                                        child: Text(
                                          novel.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: textPrimary,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                      ],
                    ),
                  );
                }, childCount: visibleSources.length),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 128)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, IconData icon, bool isDark) {
    final isSelected = _activeFilter == label;
    return GestureDetector(
      onTap: () => setState(() => _activeFilter = label),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark ? Colors.white : Colors.black)
              : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 12,
              color: isSelected
                  ? (isDark ? Colors.black : Colors.white)
                  : (isDark ? Colors.white : Colors.black87),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? (isDark ? Colors.black : Colors.white)
                    : (isDark ? Colors.white : Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
