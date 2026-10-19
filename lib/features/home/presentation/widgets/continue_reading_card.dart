import '../../../../app/theme/glass_surface.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/database/database_service.dart';
import '../../../../core/models/book.dart';
import '../../../../core/models/reading_progress.dart';
import '../../../../shared/widgets/book_cover_widget.dart';
import '../../../reader/presentation/reader_navigator.dart';

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
                    if (book.author.trim().isNotEmpty &&
                        book.author.trim() != '---' &&
                        book.author.trim() != 'Unknown') ...[
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
        message: Text(book.author),
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
