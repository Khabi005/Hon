import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../app/theme/hon_typography.dart';
import '../../../core/database/database_service.dart';
import '../../../core/files/storage_service.dart';
import '../../../core/models/book.dart';
import '../../../core/utils/epub_parser.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_navigator.dart';

enum LibraryFilter { all, epubs, pdfs, finished }

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _isGridMode = true;
  LibraryFilter _filter = LibraryFilter.all;
  LibrarySort _sort = LibrarySort.titleAz;
  bool _isImporting = false;

  Future<void> _handleImportBook() async {
    File? stagedFile;
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

      // 1. Copy to staging safely
      stagedFile = await storage.copyToStaging(originalFile);

      // 2. Compute hash for duplicate check
      final hash = await storage.computeFileHash(stagedFile);
      final existingBook = db.findBookByContentHash(hash);
      if (existingBook != null) {
        await db.setLibraryMembership(existingBook.id, true);
        await storage.deleteStagingFile(stagedFile);
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
      int? totalChapters;

      if (isEpub) {
        try {
          final meta = await EpubParser.parse(stagedFile);
          title = meta.title;
          author = meta.author;
          totalChapters = meta.chapters.length;
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
        totalChapters: totalChapters ?? 1,
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
      if (stagedFile != null) {
        await StorageService.instance.deleteStagingFile(stagedFile);
      }
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _showSortSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Sort Library'),
        actions: [
          CupertinoActionSheetAction(
            isDefaultAction: _sort == LibrarySort.titleAz,
            child: const Text('Title (A to Z)'),
            onPressed: () {
              setState(() => _sort = LibrarySort.titleAz);
              Navigator.of(ctx).pop();
            },
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _sort == LibrarySort.titleZa,
            child: const Text('Title (Z to A)'),
            onPressed: () {
              setState(() => _sort = LibrarySort.titleZa);
              Navigator.of(ctx).pop();
            },
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _sort == LibrarySort.recent,
            child: const Text('Recently Read'),
            onPressed: () {
              setState(() => _sort = LibrarySort.recent);
              Navigator.of(ctx).pop();
            },
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _sort == LibrarySort.progress,
            child: const Text('Reading Progress'),
            onPressed: () {
              setState(() => _sort = LibrarySort.progress);
              Navigator.of(ctx).pop();
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Read library books sorted per current selection
    final allLibraryBooks = DatabaseService.instance.getLibraryBooks(sort: _sort);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? HonColors.darkTextPrimary : HonColors.lightTextPrimary;

    // Filter books
    final filteredBooks = allLibraryBooks.where((b) {
      switch (_filter) {
        case LibraryFilter.all:
          return true;
        case LibraryFilter.epubs:
          return b.format == BookFormat.epub || b.format == BookFormat.webNovel;
        case LibraryFilter.pdfs:
          return b.format == BookFormat.pdf;
        case LibraryFilter.finished:
          final prog = DatabaseService.instance.getProgress(b.id);
          return (prog != null && prog.completionPercentage >= 0.99);
      }
    }).toList();

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
                        // Sort Button
                        IconButton(
                          icon: Icon(
                            CupertinoIcons.sort_down,
                            color: textPrimary,
                            size: 21,
                          ),
                          onPressed: _showSortSheet,
                        ),

                        // Grid / List toggle
                        IconButton(
                          icon: Icon(
                            _isGridMode ? CupertinoIcons.list_bullet : CupertinoIcons.square_grid_2x2,
                            color: textPrimary,
                            size: 21,
                          ),
                          onPressed: () => setState(() => _isGridMode = !_isGridMode),
                        ),

                        // Import EPUB/PDF button (+)
                        IconButton(
                          icon: _isImporting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CupertinoActivityIndicator(),
                                )
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
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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

            // Library Books Grid/List or Empty State
            if (filteredBooks.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.book,
                          size: 64,
                          color: isDark ? Colors.white24 : Colors.black26,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Your Library is Empty',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Import your EPUB or PDF books using the + button to build your library.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 24),
                        CupertinoButton.filled(
                          onPressed: _handleImportBook,
                          borderRadius: BorderRadius.circular(20),
                          child: const Text('Import Book', style: TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else if (_isGridMode)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
                sliver: SliverGrid(
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 22,
                    childAspectRatio: 0.52,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildGridItem(filteredBooks[index]),
                    childCount: filteredBooks.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildListItem(filteredBooks[index]),
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
      padding: const EdgeInsets.only(right: 8, top: 4, bottom: 4),
      child: GestureDetector(
        onTap: () => setState(() => _filter = filter),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? (isDark ? Colors.white : Colors.black)
                : (isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSelected) ...[
                Icon(
                  CupertinoIcons.checkmark,
                  size: 13,
                  color: isDark ? Colors.black : Colors.white,
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? (isDark ? Colors.black : Colors.white)
                      : (isDark ? Colors.white : Colors.black87),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showBookOptionsSheet(BuildContext context, Book book) {
    final messenger = ScaffoldMessenger.of(context);
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(
          book.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        message: Text(book.author.isNotEmpty ? book.author : 'Library Book'),
        actions: [
          CupertinoActionSheetAction(
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.minus_circle, size: 20),
                SizedBox(width: 8),
                Text('Remove from Library'),
              ],
            ),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await DatabaseService.instance.removeFromLibrary(book.id);
              messenger.showSnackBar(
                SnackBar(
                  content: Text('Removed "${book.title}" from Library (files kept).'),
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () {
                      DatabaseService.instance.setLibraryMembership(book.id, true);
                    },
                  ),
                ),
              );
            },
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.trash, size: 20, color: CupertinoColors.destructiveRed),
                SizedBox(width: 8),
                Text('Remove from Library and Delete'),
              ],
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              _confirmDeleteBook(context, book);
            },
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          child: const Text('Cancel'),
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ),
    );
  }

  void _confirmDeleteBook(BuildContext context, Book book) {
    final messenger = ScaffoldMessenger.of(context);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Remove from Library and Delete?'),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'This will remove "${book.title}" from your library, delete all downloaded publication and chapter files from Hon\'s storage, and erase your reading progress, bookmarks, and history for this novel. This action cannot be undone.',
          ),
        ),
        actions: [
          CupertinoDialogAction(
            child: const Text('Cancel'),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Delete'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              final result = await DatabaseService.instance.deleteBook(book.id);
              if (result.success) {
                if (result.skippedExternalFiles.isNotEmpty) {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Removed "${book.title}". External files left untouched.'),
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text('Removed and deleted "${book.title}".'),
                    ),
                  );
                }
              } else {
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: CupertinoColors.destructiveRed,
                    content: Text('Failed to delete files: ${result.errorMessage}'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGridItem(Book book) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prog = DatabaseService.instance.getProgress(book.id);
    final pct = prog != null ? (prog.completionPercentage * 100).toInt() : 0;
    final totalChapters = book.totalChapters;

    return GestureDetector(
      onTap: () => ReaderNavigator.openBook(context, book),
      onLongPress: () => _showBookOptionsSheet(context, book),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tactile cover with chapter count badge on top right and options button
          Expanded(
            child: Stack(
              children: [
                BookCoverWidget(
                  title: book.title,
                  author: book.author,
                  coverPath: book.coverPath,
                  borderRadius: 6,
                ),
                // Options button on top-left of cover
                Positioned(
                  top: 6,
                  left: 6,
                  child: GestureDetector(
                    onTap: () => _showBookOptionsSheet(context, book),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.68),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.ellipsis,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                // Chapter Count Badge in top-right corner (matching reference screenshot)
                if (totalChapters > 0)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.72),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$totalChapters',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Title
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

          // Reading progress
          if (pct > 0)
            Text(
              '$pct% read',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? HonColors.darkTextSecondary : HonColors.lightTextSecondary,
              ),
            )
          else
            Text(
              book.author,
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
        onTap: () => ReaderNavigator.openBook(context, book),
        onLongPress: () => _showBookOptionsSheet(context, book),
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
            IconButton(
              icon: const Icon(CupertinoIcons.ellipsis_vertical, size: 18),
              color: isDark ? Colors.white54 : Colors.black45,
              onPressed: () => _showBookOptionsSheet(context, book),
            ),
          ],
        ),
      ),
    );
  }
}
