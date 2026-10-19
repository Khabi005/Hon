import '../../../app/theme/glass_surface.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../../shared/widgets/hon_empty_state.dart';
import '../../reader/presentation/reader_navigator.dart';

class ReadingHistoryScreen extends StatefulWidget {
  const ReadingHistoryScreen({super.key});

  @override
  State<ReadingHistoryScreen> createState() => _ReadingHistoryScreenState();
}

class _ReadingHistoryScreenState extends State<ReadingHistoryScreen> {
  final _search = TextEditingController();
  String _query = '';
  String _filter = 'All';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _day(DateTime time) {
    final local = time.toLocal();
    final now = DateTime.now();
    final date = DateTime(local.year, local.month, local.day);
    final today = DateTime(now.year, now.month, now.day);
    if (date == today) return 'Today';
    if (date == DateTime(now.year, now.month, now.day - 1)) return 'Yesterday';
    return DateFormat.yMMMd().format(local);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: DatabaseService.instance.changeNotifier,
    builder: (context, _) {
      final db = DatabaseService.instance;
      final all = db.getReadingHistoryBooks();
      bool finished(Book book) =>
          db.isBookFinished(book.id) ||
          (db.getProgress(book.id)?.completionPercentage ?? 0) >= 1;
      final books = all
          .where(
            (book) =>
                ('${book.title} ${book.author}'.toLowerCase().contains(
                  _query,
                )) &&
                (_filter == 'All' ||
                    (_filter == 'Finished' ? finished(book) : !finished(book))),
          )
          .toList();
      final colors = Theme.of(context).colorScheme;
      return Scaffold(
        appBar: AppBar(
          flexibleSpace: GlassStyle.richOf(context)
              ? const GlassSurface(radius: 0, child: SizedBox.expand())
              : null,
          title: const Text('Reading History'),
        ),
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              sliver: SliverToBoxAdapter(
                child: Text(
                  'Everything you have opened, including finished books and novels outside your library.',
                  style: TextStyle(height: 1.5),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              sliver: SliverToBoxAdapter(
                child: TextField(
                  controller: _search,
                  decoration: InputDecoration(
                    labelText: 'Search reading history',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                  ),
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              sliver: SliverToBoxAdapter(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final filter in ['All', 'In Progress', 'Finished'])
                      ChoiceChip(
                        label: Text(filter),
                        selected: _filter == filter,
                        onSelected: (_) => setState(() => _filter = filter),
                      ),
                  ],
                ),
              ),
            ),
            if (books.isEmpty)
              SliverToBoxAdapter(
                child: HonEmptyState(
                  icon: Icons.history,
                  title: all.isEmpty
                      ? 'Your reading trail starts here'
                      : 'No matching books',
                  message: all.isEmpty
                      ? 'Open an EPUB, PDF or novel. Return here to pick up where you left off.'
                      : 'Try another title, author or filter.',
                ),
              )
            else
              SliverList.builder(
                itemCount: books.length,
                itemBuilder: (context, index) {
                  final book = books[index];
                  final progress = db.getProgress(book.id)!;
                  final day = _day(progress.lastReadAt);
                  final showDay =
                      index == 0 ||
                      _day(db.getProgress(books[index - 1].id)!.lastReadAt) !=
                          day;
                  final format = switch (book.format) {
                    BookFormat.epub => 'EPUB',
                    BookFormat.pdf => 'PDF',
                    BookFormat.webNovel => 'Novel',
                  };
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (showDay)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                          child: Text(
                            day,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ListTile(
                        key: ValueKey('history-${book.id}'),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 8,
                        ),
                        leading: BookCoverWidget(
                          title: book.title,
                          author: book.author,
                          coverPath: book.coverPath,
                          width: 40,
                          height: 60,
                          borderRadius: 4,
                        ),
                        title: Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              book.author,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '$format · ${finished(book) ? 'Finished' : '${(progress.completionPercentage * 100).round()}% read'} · ${DateFormat.jm().format(progress.lastReadAt.toLocal())}',
                              style: const TextStyle(fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => ReaderNavigator.openBook(context, book),
                      ),
                    ],
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      );
    },
  );
}
