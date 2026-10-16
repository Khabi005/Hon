import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allBooks = DatabaseService.instance.getAllBooks();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;

    final results = _query.trim().isEmpty
        ? <Book>[]
        : allBooks.where((b) {
            final q = _query.toLowerCase();
            return b.title.toLowerCase().contains(q) ||
                b.author.toLowerCase().contains(q) ||
                b.description.toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Search',
                style: HonTypography.largeTitle(color: textPrimary),
              ),
            ),

            // Search Bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: CupertinoSearchTextField(
                controller: _searchController,
                placeholder: 'Books, authors, or subjects',
                style: TextStyle(color: textPrimary),
                backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
                onChanged: (val) {
                  setState(() => _query = val);
                },
              ),
            ),

            // Results List
            Expanded(
              child: _query.trim().isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            CupertinoIcons.search,
                            size: 52,
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'Find in Library & Sources',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Search across all books, EPUBs, PDFs, and chapters.',
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : results.isEmpty
                      ? Center(
                          child: Text(
                            'No results found for "$_query"',
                            style: TextStyle(color: textPrimary, fontSize: 16),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(20, 10, 20, 100),
                          itemCount: results.length,
                          separatorBuilder: (_, __) => const Divider(),
                          itemBuilder: (ctx, i) {
                            final book = results[i];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: BookCoverWidget(
                                title: book.title,
                                author: book.author,
                                coverPath: book.coverPath,
                                width: 44,
                                height: 66,
                                borderRadius: 4,
                              ),
                              title: Text(
                                book.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                '${book.author} • ${book.format.name.toUpperCase()}',
                                style: TextStyle(
                                  color: isDark
                                      ? HonColors.darkTextSecondary
                                      : HonColors.lightTextSecondary,
                                ),
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
                                );
                              },
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
