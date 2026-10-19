import '../../../app/theme/glass_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_navigator.dart';
import '../../settings/presentation/settings_screen.dart';
import 'widgets/continue_reading_card.dart';
import 'widgets/reading_goals_sheet.dart';
import 'widgets/reading_week.dart';
import 'widgets/source_discovery_card.dart';
import 'reading_history_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(navigationTabProvider) == 0;
    if (active) ref.watch(databaseChangeProvider);
    final db = DatabaseService.instance;
    final continuing = active
        ? ref.watch(continueReadingProvider)
        : ref.read(continueReadingProvider);
    final library = active
        ? ref.watch(libraryBooksProvider)
        : ref.read(libraryBooksProvider);
    final recent = [...library]
      ..sort((a, b) => db.libraryAddedAt(b).compareTo(db.libraryAddedAt(a)));
    final offline = db
        .getAllBooks()
        .where(
          (book) =>
              (book.format != BookFormat.webNovel && book.filePath != null) ||
              db.hasDownloadedChapters(book.id),
        )
        .take(8)
        .toList();
    final minutes = db.getTodayReadingMinutes();
    final historyCount = db.getReadingHistoryBooks().length;
    final goal = db.getDailyGoalMinutes();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primary = isDark
        ? HonColors.darkTextPrimary
        : HonColors.lightTextPrimary;
    final secondary = isDark
        ? HonColors.darkTextSecondary
        : HonColors.lightTextSecondary;
    final surface = isDark ? const Color(0xFF222224) : const Color(0xFFF1F0EC);
    void openTab(int index) =>
        ref.read(navigationTabProvider.notifier).state = index;
    void goals() =>
        ReadingGoalsSheet.show(context, mostRecentBook: continuing.firstOrNull);
    void history() => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ReadingHistoryScreen()));

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('home-scroll'),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 20, 16, 8),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat(
                              'EEEE, d MMMM',
                            ).format(DateTime.now()).toUpperCase(),
                            style: TextStyle(
                              fontSize: 10,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w600,
                              color: secondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Home',
                            style: HonTypography.largeTitle(color: primary),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Reading goals',
                      onPressed: goals,
                      icon: SizedBox(
                        width: 30,
                        height: 30,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CircularProgressIndicator(
                              value: goal > 0
                                  ? (minutes / goal).clamp(0, 1)
                                  : 0,
                              strokeWidth: 2.5,
                              backgroundColor: surface,
                              color: HonColors.accentBlue,
                            ),
                            Text(
                              '$minutes',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      icon: Icon(CupertinoIcons.gear_alt, color: primary),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (continuing.isNotEmpty) ...[
              _heading('Continue Reading', primary, action: history, compact: true),
              SliverToBoxAdapter(
                child: SizedBox(
                  height:
                      160 +
                      (MediaQuery.textScalerOf(context).scale(20) - 20) * 8,
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                    scrollDirection: Axis.horizontal,
                    itemCount: continuing.length.clamp(0, 8),
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (_, index) => ContinueReadingCard(
                      book: continuing[index],
                      progress: db.getProgress(continuing[index].id),
                      width: (MediaQuery.sizeOf(context).width - 64).clamp(
                        260,
                        360,
                      ),
                    ),
                  ),
                ),
              ),
            ] else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
                sliver: SliverToBoxAdapter(
                  child: GlassSurface(
                    padding: const EdgeInsets.all(24),
                    radius: 22,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(CupertinoIcons.book, size: 30, color: primary),
                        const SizedBox(height: 18),
                        Text(
                          library.isEmpty
                              ? 'Make room for a good book.'
                              : 'Pick up something new.',
                          style: HonTypography.sectionHeader(color: primary),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          library.isEmpty
                              ? 'Bring your EPUBs and PDFs, or find a novel in Sources.'
                              : 'Your library is ready when you are. Open a book to start reading.',
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            FilledButton.icon(
                              onPressed: () => openTab(1),
                              icon: const Icon(CupertinoIcons.book, size: 17),
                              label: const Text('Open Library'),
                            ),
                            OutlinedButton(
                              onPressed: () => openTab(2),
                              child: const Text('Find a Novel'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 4),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: _shortcut(
                        'Your Library',
                        '${library.length} ${library.length == 1 ? 'book' : 'books'}',
                        CupertinoIcons.book,
                        surface,
                        primary,
                        secondary,
                        () => openTab(1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _shortcut(
                        'Reading History',
                        '$historyCount ${historyCount == 1 ? 'book' : 'books'} opened',
                        CupertinoIcons.clock,
                        surface,
                        primary,
                        secondary,
                        history,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
              sliver: SliverToBoxAdapter(
                child: SourceDiscoveryCard(onBrowse: () => openTab(2)),
              ),
            ),
            if (recent.isNotEmpty) ...[
              _heading('Recently Added', primary, action: () => openTab(1)),
              _shelf(context, recent.take(10).toList(), primary, secondary),
            ],
            if (offline.isNotEmpty) ...[
              _heading('Ready Offline', primary, action: () => openTab(4)),
              _shelf(context, offline, primary, secondary),
            ],
            _heading('A Little Every Day', primary),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
              sliver: SliverToBoxAdapter(
                child: InkWell(
                  onTap: goals,
                  borderRadius: BorderRadius.circular(18),
                  child: GlassSurface(
                    padding: const EdgeInsets.all(20),
                    radius: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              CupertinoIcons.timer,
                              color: HonColors.accentBlue,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '$minutes of $goal minutes today',
                                style: TextStyle(
                                  color: primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: secondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            minHeight: 4,
                            value: goal > 0 ? (minutes / goal).clamp(0, 1) : 0,
                            color: HonColors.accentBlue,
                            backgroundColor: primary.withValues(alpha: .08),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          minutes >= goal
                              ? 'You reached your daily reading goal.'
                              : 'A few quiet minutes with your next chapter.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: secondary,
                          ),
                        ),
                        const SizedBox(height: 22),
                        const ReadingWeek(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 128)),
          ],
        ),
      ),
    );
  }

  Widget _heading(String title, Color color, {VoidCallback? action, bool compact = false}) =>
      SliverPadding(
        padding: EdgeInsets.fromLTRB(24, compact ? 12 : 20, 20, compact ? 6 : 10),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: HonTypography.sectionHeader(color: color).copyWith(
                    fontSize: compact ? 19 : 21,
                  ),
                ),
              ),
              if (action != null)
                IconButton(
                  tooltip: 'See all $title',
                  onPressed: action,
                  icon: Icon(
                    CupertinoIcons.chevron_right,
                    size: 16,
                    color: color,
                  ),
                ),
            ],
          ),
        ),
      );

  Widget _shortcut(
    String title,
    String subtitle,
    IconData icon,
    Color surface,
    Color primary,
    Color secondary,
    VoidCallback onTap,
  ) => Material(
    color: surface,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: primary, size: 22),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 12, color: secondary)),
          ],
        ),
      ),
    ),
  );

  Widget _shelf(
    BuildContext context,
    List<Book> books,
    Color primary,
    Color secondary,
  ) => SliverToBoxAdapter(
    child: SizedBox(
      height: 216 + (MediaQuery.textScalerOf(context).scale(12) - 12) * 4,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        scrollDirection: Axis.horizontal,
        itemCount: books.length,
        separatorBuilder: (_, __) => const SizedBox(width: 18),
        itemBuilder: (_, index) {
          final book = books[index];
          return Semantics(
            button: true,
            label: 'Read ${book.title}',
            child: GestureDetector(
              onTap: () => ReaderNavigator.openBook(context, book),
              child: SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BookCoverWidget(
                      title: book.title,
                      author: book.author,
                      coverPath: book.coverPath,
                      width: 96,
                      height: 144,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: primary,
                        fontWeight: FontWeight.w500,
                        fontSize: 12,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      book.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: secondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}
