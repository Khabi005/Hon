import '../../../app/theme/glass_surface.dart';
import 'package:flutter/material.dart';
import '../../../core/updates/chapter_update_service.dart';
import '../../../core/database/database_service.dart';
import '../../../core/downloads/hon_download_manager.dart';
import '../../reader/presentation/reader_navigator.dart';
import '../../../shared/widgets/hon_empty_state.dart';

class LibraryUpdatesScreen extends StatefulWidget {
  const LibraryUpdatesScreen({super.key});
  @override
  State<LibraryUpdatesScreen> createState() => _LibraryUpdatesScreenState();
}

class _LibraryUpdatesScreenState extends State<LibraryUpdatesScreen> {
  final service = ChapterUpdateService.instance;
  @override
  void initState() {
    super.initState();
    service.init().then((_) async {
      final db = DatabaseService.instance;
      for (final row in service.history) {
        final bId = row['bookId'] as String?;
        if (bId != null) await db.ensureChaptersLoaded(bId);
      }
      if (mounted) setState(() {});
    });
  }

  Future<void> _check() async {
    try {
      final count = await service.check();
      final db = DatabaseService.instance;
      for (final row in service.history) {
        final bId = row['bookId'] as String?;
        if (bId != null) await db.ensureChaptersLoaded(bId);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Found $count newly discovered chapters${service.errors.isEmpty ? '.' : '; ${service.errors.length} novels could not be checked.'}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not check updates: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: service,
    builder: (context, _) {
      final db = DatabaseService.instance;
      final rows = service.history
          .where((item) => db.isBookInLibrary(item['bookId'] as String))
          .toList();
      return Scaffold(
        appBar: AppBar(
          flexibleSpace: GlassStyle.richOf(context)
              ? const GlassSurface(radius: 0, child: SizedBox.expand())
              : null,
          title: const Text('Library Updates'),
          actions: [
            if (service.checking)
              const Padding(
                padding: EdgeInsets.all(16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              IconButton(
                tooltip: 'Check for new chapters',
                onPressed: _check,
                icon: const Icon(Icons.refresh),
              ),
            PopupMenuButton(
              onSelected: (_) => service.clearHistory(),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'clear',
                  child: Text('Clear update history'),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                service.lastCheck == null
                    ? 'Check your library novels for new chapters.'
                    : 'Last checked: ${service.lastCheck!.toLocal().toString().substring(0, 16)}',
              ),
            ),
            if (service.errors.isNotEmpty)
              ExpansionTile(
                title: Text(
                  '${service.errors.length} novels could not be checked',
                ),
                children: service.errors.entries
                    .map(
                      (entry) => ListTile(
                        title: Text(
                          db.getBookById(entry.key)?.title ?? entry.key,
                        ),
                        subtitle: Text(entry.value),
                      ),
                    )
                    .toList(),
              ),
            Expanded(
              child: rows.isEmpty
                  ? HonEmptyState(
                      icon: Icons.update,
                      title: 'Your next chapters will appear here',
                      message:
                          'Check your saved online novels. Imported EPUBs and PDFs do not need source updates.',
                      actionLabel: service.checking ? null : 'Check Now',
                      onAction: service.checking ? null : _check,
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final book = db.getBookById(row['bookId'] as String);
                        return ListTile(
                          title: Text(row['title'] as String),
                          subtitle: Text(
                            '${book?.title ?? 'Removed book'} · ${(row['detectedAt'] as String).substring(0, 10)}',
                          ),
                          onTap: book == null
                              ? null
                              : () async {
                                  await db.ensureChaptersLoaded(book.id);
                                  final ch = db
                                      .getChapters(book.id)
                                      .where(
                                        (c) => c.id == row['chapterId'],
                                      )
                                      .firstOrNull;
                                  if (ch != null && context.mounted) {
                                    await ReaderNavigator.openBook(
                                      context,
                                      book,
                                      initialChapterIndex:
                                          ch.chapterIndex.toInt(),
                                    );
                                  }
                                },
                          trailing: book == null
                              ? null
                              : IconButton(
                                  tooltip: 'Download chapter',
                                  icon: const Icon(Icons.download_outlined),
                                  onPressed: () async {
                                    try {
                                      await db.ensureChaptersLoaded(book.id);
                                      final ch = db
                                          .getChapters(book.id)
                                          .where(
                                            (c) => c.id == row['chapterId'],
                                          )
                                          .firstOrNull;
                                      if (ch == null) return;
                                      final count = await HonDownloadManager
                                          .instance
                                          .queueChapters(book, [ch]);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              count == 0
                                                  ? 'Already downloaded, queued or paused.'
                                                  : 'Chapter queued.',
                                            ),
                                          ),
                                        );
                                      }
                                    } catch (error) {
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(content: Text('$error')),
                                        );
                                      }
                                    }
                                  },
                                ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
