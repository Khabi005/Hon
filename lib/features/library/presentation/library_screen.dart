import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/theme/hon_colors.dart';
import '../../../shared/widgets/hon_screen_header.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../shared/widgets/book_grid_layout.dart';
import '../../../shared/widgets/hon_empty_state.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/database/database_service.dart';
import '../../../core/files/storage_service.dart';
import '../../../core/models/book.dart';
import '../../../core/utils/epub_parser.dart';
import '../../../shared/widgets/book_cover_widget.dart';
import '../../reader/presentation/reader_navigator.dart';
import 'collections_screen.dart';
import 'library_updates_screen.dart';
import '../../browse/presentation/source_catalog_screen.dart';
import '../../../core/models/novel_source.dart';
import '../../../core/updates/chapter_update_service.dart';
import '../../../core/export/epub_export_service.dart';
import '../../../shared/widgets/pressable_scale.dart';

enum LibraryFilter { all, epubs, pdfs, novels, finished }

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
  String? _collectionId;

  @override
  void initState() {
    super.initState();
    _loadViewPreferences();
  }

  Future<void> _loadViewPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _isGridMode = prefs.getBool('hon_library_grid') ?? true;
      _sort =
          LibrarySort.values
              .where((sort) => sort.name == prefs.getString('hon_library_sort'))
              .firstOrNull ??
          LibrarySort.titleAz;
    });
  }

  Future<void> _saveViewPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('hon_library_grid', _isGridMode);
    await prefs.setString('hon_library_sort', _sort.name);
  }

  Future<void> _handleImportBook() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    File? stagedFile;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub', 'pdf'],
      );

      if (result == null ||
          result.files.isEmpty ||
          result.files.first.path == null) {
        return;
      }

      if (!mounted) return;

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
            SnackBar(
              content: Text(
                '"${existingBook.title}" is already in your library.',
              ),
            ),
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
          final meta = await EpubParser.parse(
            stagedFile,
            includeContent: false,
          );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Import failed: $e')));
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
              _saveViewPreferences();
              Navigator.of(ctx).pop();
            },
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _sort == LibrarySort.titleZa,
            child: const Text('Title (Z to A)'),
            onPressed: () {
              setState(() => _sort = LibrarySort.titleZa);
              _saveViewPreferences();
              Navigator.of(ctx).pop();
            },
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _sort == LibrarySort.recent,
            child: const Text('Recently Read'),
            onPressed: () {
              setState(() => _sort = LibrarySort.recent);
              _saveViewPreferences();
              Navigator.of(ctx).pop();
            },
          ),
          CupertinoActionSheetAction(
            isDefaultAction: _sort == LibrarySort.progress,
            child: const Text('Reading Progress'),
            onPressed: () {
              setState(() => _sort = LibrarySort.progress);
              _saveViewPreferences();
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
    if (ref.watch(navigationTabProvider) == 1) {
      ref.watch(libraryChangeProvider);
    }
    // Read library books sorted per current selection
    final allLibraryBooks = DatabaseService.instance.getLibraryBooks(
      sort: _sort,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? HonColors.darkTextPrimary
        : HonColors.lightTextPrimary;

    // Filter books
    final collections = DatabaseService.instance.collections;
    if (!collections.containsKey(_collectionId)) _collectionId = null;
    final filteredBooks = allLibraryBooks.where((b) {
      if (_collectionId != null &&
          !(DatabaseService.instance
                  .getLibraryEntry(b.id)
                  ?.collectionIds
                  .contains(_collectionId) ??
              false)) {
        return false;
      }
      switch (_filter) {
        case LibraryFilter.all:
          return true;
        case LibraryFilter.epubs:
          return b.format == BookFormat.epub;
        case LibraryFilter.novels:
          return b.format == BookFormat.webNovel;
        case LibraryFilter.pdfs:
          return b.format == BookFormat.pdf;
        case LibraryFilter.finished:
          return DatabaseService.instance.isBookFinished(b.id);
      }
    }).toList();

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('library-scroll'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            SliverToBoxAdapter(
              child: HonScreenHeader(
                title: 'Library',
                actions: [
                  IconButton(
                    tooltip: 'Library updates',
                    icon: const Icon(Icons.update),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LibraryUpdatesScreen(),
                      ),
                    ),
                  ),
                  // Sort Button
                  IconButton(
                    tooltip: 'Sort library',
                    icon: Icon(
                      CupertinoIcons.sort_down,
                      color: textPrimary,
                      size: 21,
                    ),
                    onPressed: _showSortSheet,
                  ),

                  // Grid / List toggle
                  IconButton(
                    tooltip: _isGridMode ? 'List view' : 'Grid view',
                    icon: Icon(
                      _isGridMode
                          ? CupertinoIcons.list_bullet
                          : CupertinoIcons.square_grid_2x2,
                      color: textPrimary,
                      size: 21,
                    ),
                    onPressed: () {
                      setState(() => _isGridMode = !_isGridMode);
                      _saveViewPreferences();
                    },
                  ),

                  // Import EPUB/PDF button (+)
                  IconButton(
                    tooltip: 'Import EPUB or PDF',
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
            ),

            // Filter Chips Bar
            SliverToBoxAdapter(
              child: SizedBox(
                height: 52,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'Collections',
                      onSelected: (id) async {
                        if (id == '__manage') {
                          final selected = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const CollectionsScreen(),
                            ),
                          );
                          if (mounted && selected != null) {
                            setState(() => _collectionId = selected);
                          }
                        } else {
                          setState(
                            () => _collectionId = id.isEmpty ? null : id,
                          );
                        }
                      },
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: '',
                          child: Text('All collections'),
                        ),
                        ...collections.entries.map(
                          (entry) => PopupMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                        ),
                        const PopupMenuItem(
                          value: '__manage',
                          child: Text('Manage Collections'),
                        ),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.folder_outlined, size: 18),
                            const SizedBox(width: 6),
                            Text(collections[_collectionId] ?? 'Collections'),
                            const Icon(Icons.expand_more, size: 18),
                          ],
                        ),
                      ),
                    ),
                    _buildFilterChip('All', LibraryFilter.all),
                    _buildFilterChip('EPUBs', LibraryFilter.epubs),
                    _buildFilterChip('PDFs', LibraryFilter.pdfs),
                    _buildFilterChip('Novels', LibraryFilter.novels),
                    _buildFilterChip('Finished', LibraryFilter.finished),
                  ],
                ),
              ),
            ),

            // Library Books Grid/List or Empty State
            if (filteredBooks.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: HonEmptyState(
                  icon: CupertinoIcons.book,
                  title: allLibraryBooks.isEmpty
                      ? 'Your next chapter starts here'
                      : 'No books in this view',
                  message: allLibraryBooks.isEmpty
                      ? 'Import an EPUB or PDF, or save a novel from Browse.'
                      : 'Choose another filter to see more of your library.',
                  actionLabel: allLibraryBooks.isEmpty
                      ? 'Import a Book'
                      : 'Show All Books',
                  onAction: _isImporting
                      ? null
                      : allLibraryBooks.isEmpty
                      ? _handleImportBook
                      : () => setState(() {
                          _filter = LibraryFilter.all;
                          _collectionId = null;
                        }),
                ),
              )
            else if (_isGridMode)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 128),
                sliver: SliverGrid(
                  gridDelegate: bookGridLayout(context),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildGridItem(filteredBooks[index]),
                    childCount: filteredBooks.length,
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 128),
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
      child: Semantics(
        selected: isSelected,
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _filter = filter),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? Colors.white : Colors.black)
                  : (isDark
                        ? const Color(0xFF2C2C2E)
                        : const Color(0xFFE5E5EA)),
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
          if (book.format == BookFormat.webNovel) ...[
            CupertinoActionSheetAction(
              child: Text(
                (DatabaseService.instance.getProgress(book.id)?.chapterIndex ?? 0) > 0
                    ? 'Continue Reading'
                    : 'Start Reading',
              ),
              onPressed: () {
                Navigator.of(ctx).pop();
                ReaderNavigator.openBook(context, book);
              },
            ),
            CupertinoActionSheetAction(
              child: const Text('View Series Catalogue'),
              onPressed: () {
                Navigator.of(ctx).pop();
                final sourceId = book.sourceId ??
                    (book.id.contains(':') ? book.id.split(':').first : 'unknown');
                final sourceNovelId = book.sourceNovelId ??
                    (book.id.contains(':')
                        ? book.id.substring(book.id.indexOf(':') + 1)
                        : book.id);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SourceNovelDetailsScreen(
                      novel: SourceNovelSummary(
                        id: sourceNovelId,
                        title: book.title,
                        author: book.author,
                        coverUrl: book.coverPath,
                      ),
                      sourceId: sourceId,
                      sourceName: sourceId,
                    ),
                  ),
                );
              },
            ),
            CupertinoActionSheetAction(
              child: const Text('Check for New Chapters'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                try {
                  final count = await ChapterUpdateService.instance.check(
                    only: book,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ChapterUpdateService.instance.errors[book.id] ??
                              'Found $count newly discovered chapters.',
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('$error')));
                  }
                }
              },
            ),
          ],
          if (book.isWebNovel)
            CupertinoActionSheetAction(
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.square_arrow_up, size: 20),
                  SizedBox(width: 8),
                  Text('Export Series as EPUB'),
                ],
              ),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final result = await EpubExportService.exportSeriesAsEpub(book: book);
                if (!context.mounted) return;
                if (result.success && result.exportedFilePath != null) {
                  showModalBottomSheet(
                    context: context,
                    builder: (sheetCtx) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'EPUB Exported (${result.chapterCount} chapters)',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            if (result.omittedImageCount > 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                                child: Text(
                                  'Note: ${result.omittedImageCount} remote or missing image${result.omittedImageCount > 1 ? "s" : ""} could not be bundled.',
                                  style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            const SizedBox(height: 8),
                            ListTile(
                              leading: const Icon(CupertinoIcons.share),
                              title: const Text('Share EPUB'),
                              subtitle: const Text('Send to another app or device'),
                              onTap: () async {
                                Navigator.of(sheetCtx).pop();
                                final shareRes = await EpubExportService.shareExportedEpub(result.exportedFilePath!);
                                if (!shareRes.success && context.mounted && shareRes.errorMessage != null) {
                                  messenger.showSnackBar(SnackBar(content: Text(shareRes.errorMessage!)));
                                }
                              },
                            ),
                            ListTile(
                              leading: const Icon(CupertinoIcons.folder),
                              title: const Text('Save As...'),
                              subtitle: const Text('Save to device storage or Downloads'),
                              onTap: () async {
                                Navigator.of(sheetCtx).pop();
                                final saveRes = await EpubExportService.saveExportedEpubAs(result.exportedFilePath!);
                                if (context.mounted) {
                                  final message = saveRes.isSaved
                                      ? 'EPUB saved successfully'
                                      : saveRes.isFailed
                                          ? 'Failed to save EPUB: ${saveRes.errorMessage ?? "Unknown error"}'
                                          : 'Save cancelled';
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text(message),
                                    ),
                                  );
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(result.errorMessage ?? 'Export failed'),
                    ),
                  );
                }
              },
            ),
          CupertinoActionSheetAction(
            child: const Text('Organize in Collections'),
            onPressed: () {
              Navigator.of(ctx).pop();
              organizeBook(context, book.id);
            },
          ),
          CupertinoActionSheetAction(
            child: Text(
              DatabaseService.instance.isBookFinished(book.id)
                  ? 'Mark as Unfinished'
                  : 'Mark as Finished',
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              DatabaseService.instance.markBookFinished(
                book.id,
                !DatabaseService.instance.isBookFinished(book.id),
              );
            },
          ),
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
                  content: Text(
                    'Removed "${book.title}" from Library (files kept).',
                  ),
                  action: SnackBarAction(
                    label: 'Undo',
                    onPressed: () {
                      DatabaseService.instance.setLibraryMembership(
                        book.id,
                        true,
                      );
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
                Icon(
                  CupertinoIcons.trash,
                  size: 20,
                  color: CupertinoColors.destructiveRed,
                ),
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
                      content: Text(
                        'Removed "${book.title}". External files left untouched.',
                      ),
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
                    content: Text(
                      'Failed to delete files: ${result.errorMessage}',
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _handleBookTap(BuildContext context, Book book) async {
    if (book.format == BookFormat.webNovel) {
      final prefs = await SharedPreferences.getInstance();
      final mode = prefs.getString('hon_webnovel_library_tap_action') ?? 'catalogue';
      if (mode == 'reader') {
        if (context.mounted) {
          await ReaderNavigator.openBook(context, book);
        }
        return;
      }
      final sourceId = book.sourceId ??
          (book.id.contains(':') ? book.id.split(':').first : 'unknown');
      final sourceNovelId = book.sourceNovelId ??
          (book.id.contains(':')
              ? book.id.substring(book.id.indexOf(':') + 1)
              : book.id);
      if (context.mounted) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SourceNovelDetailsScreen(
              novel: SourceNovelSummary(
                id: sourceNovelId,
                title: book.title,
                author: book.author,
                coverUrl: book.coverPath,
              ),
              sourceId: sourceId,
              sourceName: sourceId,
            ),
          ),
        );
      }
    } else {
      await ReaderNavigator.openBook(context, book);
    }
  }

  Widget _buildGridItem(Book book) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final prog = DatabaseService.instance.getProgress(book.id);
    final pct = prog != null ? (prog.completionPercentage * 100).toInt() : 0;

    return Semantics(
      button: true,
      label: 'Read ${book.title}',
      hint: 'Long press for book options',
      child: PressableScale(
        onTap: () => _handleBookTap(context, book),
        onLongPress: () => _showBookOptionsSheet(context, book),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
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
                  color: isDark
                      ? HonColors.darkTextSecondary
                      : HonColors.lightTextSecondary,
                ),
              )
            else
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? HonColors.darkTextSecondary
                      : HonColors.lightTextSecondary,
                ),
              ),
          ],
        ),
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
        onTap: () => _handleBookTap(context, book),
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
                      color: isDark
                          ? HonColors.darkTextSecondary
                          : HonColors.lightTextSecondary,
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
