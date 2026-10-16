import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../../../core/models/book.dart';
import '../../../../core/models/reading_progress.dart';
import '../../../../shared/widgets/book_cover_widget.dart';
import '../../../reader/presentation/reader_screen.dart';
import '../../../reader/presentation/pdf_reader_screen.dart';

class ContinueReadingCard extends StatelessWidget {
  final Book book;
  final ReadingProgress? progress;

  const ContinueReadingCard({
    super.key,
    required this.book,
    this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final pct = progress != null ? (progress!.completionPercentage * 100).toInt() : 0;

    // Card gradient based on book identity
    final hash = book.title.hashCode.abs();
    final gradients = [
      [const Color(0xFF634133), const Color(0xFF8B5A2B)],
      [const Color(0xFF2B4353), const Color(0xFF456268)],
      [const Color(0xFF3B2F4C), const Color(0xFF5D4E6D)],
      [const Color(0xFF2C4A3E), const Color(0xFF43655A)],
      [const Color(0xFF5B323E), const Color(0xFF7A4A58)],
    ];
    final gradient = gradients[hash % gradients.length];

    return GestureDetector(
      onTap: () {
        if (book.format == BookFormat.pdf) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => PdfReaderScreen(book: book)),
          );
        } else {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
          );
        }
      },
      child: Container(
        width: 290,
        height: 120,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withOpacity(0.35),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
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
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    book.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.75),
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Book • $pct%',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Right: Three dots action menu
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(
                  CupertinoIcons.ellipsis,
                  color: Colors.white70,
                  size: 20,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  _showBookContextMenu(context);
                },
              ),
            ),
          ],
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
            child: const Text('Book Details'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoActionSheetAction(
            child: const Text('Mark as Finished'),
            onPressed: () => Navigator.of(ctx).pop(),
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
