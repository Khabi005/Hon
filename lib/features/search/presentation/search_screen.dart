import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/models/book.dart';
import '../../../core/models/novel_source.dart';
import '../../../core/sources/source_registry.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../browse/presentation/source_catalog_screen.dart';
import '../../reader/presentation/reader_navigator.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _activeFilter = 'All'; // 'Pinned', 'All', 'Has results'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final textSecondary = isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary;

    final allLibraryBooks = ref.watch(libraryBooksProvider);

    // 1. Library Matches
    final matchingLibraryBooks = _query.trim().isEmpty
        ? <Book>[]
        : allLibraryBooks.where((b) {
            final q = _query.toLowerCase();
            return b.title.toLowerCase().contains(q) ||
                b.author.toLowerCase().contains(q);
          }).toList();

    // 2. Global Source Matches
    final globalResults = _query.trim().isEmpty
        ? <String, List<SourceNovelSummary>>{}
        : SourceRegistry.instance.globalSearch(_query);

    final installedSources = SourceRegistry.instance.getInstalledSources();

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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  'Search',
                  style: HonTypography.largeTitle(color: textPrimary),
                ),
              ),
            ),

            // Search Bar Input
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                child: CupertinoSearchTextField(
                  controller: _searchController,
                  style: TextStyle(color: textPrimary),
                  placeholder: 'Search library & all online sources...',
                  onChanged: (val) => setState(() => _query = val),
                  onSuffixTap: () {
                    setState(() {
                      _query = '';
                      _searchController.clear();
                    });
                  },
                ),
              ),
            ),

            // Filter Chips Bar (Matching Taison reference: Pinned | All | Has results)
            if (_query.trim().isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      _buildFilterChip('Pinned', CupertinoIcons.pin_fill, isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('All', CupertinoIcons.check_mark, isDark),
                      const SizedBox(width: 8),
                      _buildFilterChip('Has results', CupertinoIcons.slider_horizontal_3, isDark),
                    ],
                  ),
                ),
              ),

            // Empty Query Initial State
            if (_query.trim().isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.search,
                        size: 54,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Find in Library & Sources',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Global multi-source search across web novels and local books.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
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
                          style: HonTypography.sectionHeader(color: textPrimary),
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
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textPrimary),
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
              ...installedSources.map((source) {
                final sourceNovels = globalResults[source.name] ?? [];
                if (_activeFilter == 'Has results' && sourceNovels.isEmpty) {
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                }

                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Source Header Bar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(
                                  source.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: textPrimary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  source.lang,
                                  style: TextStyle(fontSize: 12, color: textSecondary),
                                ),
                              ],
                            ),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 16,
                              color: textSecondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Source Results Row or "No results found"
                        if (sourceNovels.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Text(
                              'No results found',
                              style: TextStyle(fontSize: 13, color: textSecondary, fontStyle: FontStyle.italic),
                            ),
                          )
                        else
                          SizedBox(
                            height: 155,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: sourceNovels.length,
                              separatorBuilder: (_, __) => const SizedBox(width: 12),
                              itemBuilder: (context, index) {
                                final novel = sourceNovels[index];
                                return GestureDetector(
                                  onTap: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => SourceNovelDetailsScreen(
                                          novel: novel,
                                          sourceName: source.name,
                                        ),
                                      ),
                                    );
                                  },
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
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
                  ),
                );
              }),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 100)),
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
