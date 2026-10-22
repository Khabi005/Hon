import '../../../../app/theme/glass_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/models/book.dart';
import '../../../../core/models/reading_progress.dart';
import '../../../../shared/widgets/book_cover_widget.dart';
import '../../../reader/presentation/reader_navigator.dart';
import '../../../../app/theme/hon_colors.dart';

class ContinueReadingCard extends StatelessWidget {
  final Book book;
  final ReadingProgress? progress;
  final double width;

  const ContinueReadingCard({
    super.key,
    required this.book,
    this.progress,
    this.width = 310,
  });

  @override
  Widget build(BuildContext context) {
    final pct = progress != null
        ? (progress!.completionPercentage * 100).toInt()
        : 0;

    final colors = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: 'Continue reading ${book.title}, $pct percent read',
      child: GestureDetector(
        onTap: () => ReaderNavigator.openBook(context, book),
        child: GlassSurface(
          width: width,
          radius: 18,
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Left: Book Cover
              BookCoverWidget(
                title: book.title,
                author: book.author,
                coverPath: book.coverPath,
                width: 64,
                height: 96,
                borderRadius: 6,
              ),
              const SizedBox(width: 14),

              // Middle: Title, Author, Progress
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      book.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontFamily: 'Newsreader',
                        fontSize: 18,
                        height: 1.15,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (isKnownAuthor(book.author)) ...[
                      const SizedBox(height: 3),
                      Text(
                        book.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    Text(
                      '$pct% read',
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (progress?.completionPercentage ?? 0).clamp(0, 1),
                      minHeight: 2.5,
                      backgroundColor: colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ),
              ),

              // Right: Three dots action menu
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  tooltip: 'Book options',
                  icon: Icon(
                    CupertinoIcons.ellipsis,
                    color: colors.onSurfaceVariant,
                    size: 20,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: () {
                    _showBookContextMenu(context);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookContextMenu(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(book.title),
        message: isKnownAuthor(book.author) ? Text(book.author) : null,
        actions: [
          CupertinoActionSheetAction(
            child: const Text('Read from Last Location'),
            onPressed: () {
              Navigator.of(ctx).pop();
              ReaderNavigator.openBook(context, book);
            },
          ),
          CupertinoActionSheetAction(
            child: const Text('Mark as Finished'),
            onPressed: () {
              DatabaseService.instance.markBookFinished(book.id, true);
              Navigator.of(ctx).pop();
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }
}

bool isKnownAuthor(String? author) {
  if (author == null) return false;
  final clean = author.trim().toLowerCase();
  return clean.isNotEmpty &&
      clean != 'unknown' &&
      clean != 'unknown author' &&
      clean != '---' &&
      clean != '--' &&
      clean != '-' &&
      clean != 'none' &&
      clean != 'n/a';
}

class GroupedContinueReadingCard extends StatelessWidget {
  final List<Book> books;
  final DatabaseService db;
  final VoidCallback onHistory;

  const GroupedContinueReadingCard({
    super.key,
    required this.books,
    required this.db,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    if (books.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryBook = books.first;
    final primaryProgress = db.getProgress(primaryBook.id);
    final primaryPct = primaryProgress != null
        ? (primaryProgress.completionPercentage * 100).toInt()
        : 0;

    final secondaryBooks = books.skip(1).take(2).toList();

    return GlassSurface(
      width: double.infinity,
      radius: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary featured resume book
          Semantics(
            button: true,
            label:
                'Continue reading ${primaryBook.title}, $primaryPct percent read',
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => ReaderNavigator.openBook(context, primaryBook),
              child: Row(
                children: [
                  BookCoverWidget(
                    title: primaryBook.title,
                    author: primaryBook.author,
                    coverPath: primaryBook.coverPath,
                    width: 60,
                    height: 90,
                    borderRadius: 6,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          primaryBook.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontFamily: 'Newsreader',
                            fontSize: 17,
                            height: 1.15,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.2,
                          ),
                        ),
                        if (isKnownAuthor(primaryBook.author)) ...[
                          const SizedBox(height: 3),
                          Text(
                            primaryBook.author,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 12,
                              height: 1.25,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              '$primaryPct% read',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 12,
                                height: 1.2,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Spacer(),
                            FilledButton.tonal(
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 0,
                                ),
                                minimumSize: const Size(0, 32),
                              ),
                              onPressed: () =>
                                  ReaderNavigator.openBook(context, primaryBook),
                              child: const Text(
                                'Resume',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: (primaryProgress?.completionPercentage ?? 0)
                              .clamp(0, 1),
                          minHeight: 2.5,
                          backgroundColor: colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          if (secondaryBooks.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Divider(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            ...secondaryBooks.map((book) {
              final prog = db.getProgress(book.id);
              final pct = prog != null
                  ? (prog.completionPercentage * 100).toInt()
                  : 0;
              return Semantics(
                button: true,
                label: 'Continue reading ${book.title}, $pct percent read',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => ReaderNavigator.openBook(context, book),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 6,
                      horizontal: 4,
                    ),
                    child: Row(
                      children: [
                        BookCoverWidget(
                          title: book.title,
                          author: book.author,
                          coverPath: book.coverPath,
                          width: 34,
                          height: 50,
                          borderRadius: 4,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                book.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurface,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (isKnownAuthor(book.author)) ...[
                                const SizedBox(height: 2),
                                Text(
                                  book.author,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: LinearProgressIndicator(
                                      value: (prog?.completionPercentage ?? 0)
                                          .clamp(0, 1),
                                      minHeight: 2.0,
                                      backgroundColor:
                                          colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '$pct%',
                                    style: TextStyle(
                                      color: colors.onSurfaceVariant,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                          color: colors.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],

          if (books.length > 3) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: onHistory,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'View all ${books.length} books in progress',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: HonColors.accentBlue,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        CupertinoIcons.chevron_right,
                        size: 12,
                        color: HonColors.accentBlue,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
