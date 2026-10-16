import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_screen.dart';
import '../../settings/presentation/settings_screen.dart';
import 'widgets/continue_reading_card.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueBooks = ref.watch(continueReadingProvider);
    final allBooks = ref.watch(libraryBooksProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Top App Bar with Serif Title and Settings Action
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Home',
                      style: HonTypography.largeTitle(color: textPrimary),
                    ),
                    Row(
                      children: [
                        // Reading streak / progress ring badge (Apple Books 20/20 style)
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: HonColors.accentBlue,
                              width: 2.2,
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '20',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: HonColors.accentBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),

                        // Settings action button (Toolbar button, no fake avatar!)
                        IconButton(
                          icon: Icon(
                            CupertinoIcons.gear_alt,
                            color: textPrimary,
                            size: 24,
                          ),
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // "Continue" Section
            if (continueBooks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Text(
                    'Continue',
                    style: HonTypography.sectionHeader(color: textPrimary),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 124,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    itemCount: continueBooks.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (ctx, i) {
                      final book = continueBooks[i];
                      final prog = DatabaseService.instance.getProgress(book.id);
                      return ContinueReadingCard(book: book, progress: prog);
                    },
                  ),
                ),
              ),
            ],

            // "Top Picks" Hero Carousel (From Image 2 reference)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Text(
                  'Top Picks',
                  style: HonTypography.sectionHeader(color: textPrimary),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 290,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Orange Curated Card from Reference Image 2
                    _buildCuratedCard(
                      context,
                      tag: 'Hon Reader',
                      headline: 'STAFF PICKS\n2026 SO FAR',
                      subtext: 'Check out our favorite classics and translated novels of the year.',
                      gradient: const [Color(0xFFFF7E39), Color(0xFFFF5224)],
                      onTap: () {
                        // Open Pride and Prejudice
                        final p = DatabaseService.instance.getBookById('book_pride_and_prejudice');
                        if (p != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ReaderScreen(book: p)),
                          );
                        }
                      },
                    ),
                    const SizedBox(width: 14),

                    // Crimson War and Peace Card from Reference Image 2
                    _buildCuratedCard(
                      context,
                      tag: 'SUGGESTED CLASSIC',
                      headline: 'War and Peace',
                      subtext: 'Leo Tolstoy • Russian literature monumental epic',
                      gradient: const [Color(0xFF8B0000), Color(0xFF5A0000)],
                      onTap: () {
                        final b = DatabaseService.instance.getBookById('book_war_and_peace');
                        if (b != null) {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => ReaderScreen(book: b)),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),

            // "Want to Read >" Section (From Image 2 reference)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'Want to Read',
                      style: HonTypography.sectionHeader(color: textPrimary),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 185,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: allBooks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 16),
                  itemBuilder: (ctx, i) {
                    final book = allBooks[i];
                    return GestureDetector(
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
                        );
                      },
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          BookCoverWidget(
                            title: book.title,
                            author: book.author,
                            coverPath: book.coverPath,
                            width: 100,
                            height: 150,
                            borderRadius: 8,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100), // Bottom padding for frosted nav bar
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCuratedCard(
    BuildContext context, {
    required String tag,
    required String headline,
    required String subtext,
    required List<Color> gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 250,
        height: 290,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tag.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.85),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.15,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            Text(
              subtext,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
