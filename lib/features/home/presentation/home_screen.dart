import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_navigator.dart';
import '../../settings/presentation/settings_screen.dart';
import 'widgets/continue_reading_card.dart';
import 'widgets/reading_goals_sheet.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final continueBooks = ref.watch(continueReadingProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;
    final textSecondary = isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary;

    final finishedBooks = ref.watch(libraryBooksProvider).where((b) {
      final prog = DatabaseService.instance.getProgress(b.id);
      return prog != null && prog.completionPercentage >= 0.99;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Top App Bar with Serif Title and Reading Streak Action
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
                        // Reading streak badge button -> opens Reading Goals modal
                        GestureDetector(
                          onTap: () {
                            ReadingGoalsSheet.show(
                              context,
                              mostRecentBook: continueBooks.firstOrNull,
                            );
                          },
                          child: Container(
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
                        ),
                        const SizedBox(width: 12),

                        // Settings action button
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

            // "Continue" Section (Real reading progress only)
            if (continueBooks.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
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

            // Reading Goals Banner Card
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: GestureDetector(
                  onTap: () {
                    ReadingGoalsSheet.show(
                      context,
                      mostRecentBook: continueBooks.firstOrNull,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF2F2F7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark ? Colors.white10 : Colors.black.withOpacity(0.06),
                        width: 0.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: HonColors.accentBlue.withOpacity(0.15),
                          ),
                          child: const Icon(
                            CupertinoIcons.timer,
                            size: 20,
                            color: HonColors.accentBlue,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Reading Goals',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '0 of 5 mins today • Tap to view stats',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 16,
                          color: textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // Books Read This Year Section
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Books Read This Year',
                      style: HonTypography.sectionHeader(color: textPrimary),
                    ),
                    Text(
                      '${finishedBooks.length} books',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(
                height: 110,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  itemCount: finishedBooks.isNotEmpty ? finishedBooks.length : 3,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (ctx, i) {
                    if (finishedBooks.isNotEmpty && i < finishedBooks.length) {
                      final b = finishedBooks[i];
                      return GestureDetector(
                        onTap: () => ReaderNavigator.openBook(context, b),
                        child: BookCoverWidget(
                          title: b.title,
                          author: b.author,
                          coverPath: b.coverPath,
                          width: 72,
                          height: 108,
                          borderRadius: 6,
                        ),
                      );
                    }
                    return Container(
                      width: 72,
                      height: 108,
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF1E1E20) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isDark ? Colors.white10 : Colors.black12,
                          width: 0.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${i + 1}',
                        style: TextStyle(
                          fontSize: 24,
                          fontFamily: 'serif',
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            // Empty state guidance if continue is empty
            if (continueBooks.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          CupertinoIcons.book,
                          size: 48,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No Active Reading',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Import EPUB or PDF books in Library, or discover novels in Browse to begin reading.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: textSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 90)),
          ],
        ),
      ),
    );
  }
}
