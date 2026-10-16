import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../core/files/storage_service.dart';
import '../../../core/models/book.dart';
import '../../../core/utils/epub_parser.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_screen.dart';
import '../../reader/presentation/pdf_reader_screen.dart';

enum LibraryFilter { all, epubs, pdfs, finished }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isGridMode = true;
  LibraryFilter _filter = LibraryFilter.all;
  bool _isImporting = false;

  Future<void> _handleImportBook() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf'],
      );

      if (result == null || result.files.isEmpty || result.files.first.path == null) {
        return;
      }

      setState(() => _isImporting = true);

      final originalFile = File(result.files.first.path!);
      final storage = StorageService.instance;
      final db = DatabaseService.instance;

      // 1. Copy to staging
      final stagedFile = await storage.copyToStaging(originalFile);

      // 2. Compute hash for duplicate check
      final hash = await storage.computeFileHash(stagedFile);
      final existingBook = db.findBookByContentHash(hash);
      if (existingBook != null) {
        // Already imported! Add to library if not in library
        await db.setLibraryMembership(existingBook.id, true);
        await storage.cleanStaging();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${existingBook.title}" is already in your library.')),
          );
          setState(() => _isImporting = false);
        }
        return;
      }

      // 3. Inspect format & metadata
      final ext = originalFile.path.split('.').last.toLowerCase();
      final isEpub = ext == 'epub';
      final bookId = 'book_${DateTime.now().millisecondsSinceEpoch}';

      String title = result.files.first.name.replaceAll('.$ext', '');
      String author = 'Unknown Author';
      String? coverPath;

      if (isEpub) {
        try {
          final meta = await EpubParser.parse(stagedFile);
          title = meta.title;
          author = meta.author;
          if (meta.coverBytes != null) {
            coverPath = await storage.saveCoverImage(bookId, meta.coverBytes!);
          }
        } catch (_) {}
      }

      // 4. Promote to permanent storage
      final finalFile = await storage.promoteStagingFile(
        stagedFile,
        '$bookId.$ext',
      );

      // 5. Commit book & library entry
      final newBook = Book(
        id: bookId,
        title: title,
        author: author,
        format: isEpub ? BookFormat.epub : BookFormat.pdf,
        filePath: finalFile.path,
        coverPath: coverPath,
        contentHash: hash,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await db.saveBook(newBook);
      await db.setLibraryMembership(newBook.id, true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Imported "$title" successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Import failed: $e')),
        );
      }
    } finally {
      await StorageService.instance.cleanStaging();
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryBooks = ref.watch(libraryBooksProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;

    // Filter books
    final filteredBooks = libraryBooks.where((b) {
      switch (_filter) {
        case LibraryFilter.all:
          return true;
        case LibraryFilter.epubs:
          return b.format == BookFormat.epub || b.format == BookFormat.webNovel;
        case LibraryFilter.pdfs:
          return b.format == BookFormat.pdf;
        case LibraryFilter.finished:
          final prog = DatabaseService.instance.getProgress(b.id);
          return (prog?.completionPercentage ?? 0) >= 0.99;
      }
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? HonColors.darkBackground : HonColors.lightBackground,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // Header Bar
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Library',
                      style: HonTypography.largeTitle(color: textPrimary),
                    ),
                    Row(
                      children: [
                        // View mode toggle (Grid / List)
                        IconButton(
                          icon: Icon(
                            _isGridMode
                                ? CupertinoIcons.list_bullet
                                : CupertinoIcons.square_grid_2x2,
                            color: textPrimary,
                            size: 22,
                          ),
                          onPressed: () {
                            setState(() => _isGridMode = !_isGridMode);
                          },
                        ),
                        // Import (+) button
                        IconButton(
                          icon: _isImporting
                              ? const CupertinoActivityIndicator()
                              : Icon(
                                  CupertinoIcons.plus,
                                  color: textPrimary,
                                  size: 24,
                                ),
                          onPressed: _isImporting ? null : _handleImportBook,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Filter Chips Bar
            SliverToBoxAdapter(
              child: SizedBox(
                height: 44,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    _buildFilterChip('All', LibraryFilter.all),
                    _buildFilterChip('EPUBs', LibraryFilter.epubs),
                    _buildFilterChip('PDFs', LibraryFilter.pdfs),
                    _buildFilterChip('Finished', LibraryFilter.finished),
                  ],
                ),
              ),
            ),

            // Books Content
            if (filteredBooks.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        CupertinoIcons.book,
                        size: 56,
                        color: isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Your library is quiet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap + to import an EPUB or PDF book',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_isGridMode)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 20,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildGridItem(filteredBooks[i]),
                    childCount: filteredBooks.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _buildListItem(filteredBooks[i]),
                    childCount: filteredBooks.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, LibraryFilter filter) {
    final isSelected = _filter == filter;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: isSelected,
        onSelected: (_) => setState(() => _filter = filter),
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
        selectedColor: isDark ? Colors.white : Colors.black,
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected
              ? (isDark ? Colors.black : Colors.white)
              : (isDark ? Colors.white70 : Colors.black87),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      ),
    );
  }

  Widget _buildGridItem(Book book) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prog = DatabaseService.instance.getProgress(book.id);
    final pct = prog != null ? (prog.completionPercentage * 100).toInt() : 0;

    return GestureDetector(
      onTap: () => _openBook(book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: BookCoverWidget(
              title: book.title,
              author: book.author,
              coverPath: book.coverPath,
              width: double.infinity,
              height: double.infinity,
              borderRadius: 6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            pct > 0 ? '$pct% read' : book.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildListItem(Book book) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prog = DatabaseService.instance.getProgress(book.id);
    final pct = prog != null ? (prog.completionPercentage * 100).toInt() : 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: InkWell(
        onTap: () => _openBook(book),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            BookCoverWidget(
              title: book.title,
              author: book.author,
              coverPath: book.coverPath,
              width: 50,
              height: 75,
              borderRadius: 4,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    book.author,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                    ),
                  ),
                  if (pct > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '$pct% read',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: HonColors.accentOrange,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }

  void _openBook(Book book) {
    if (book.format == BookFormat.pdf) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PdfReaderScreen(book: book)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
      );
    }
  }
}
