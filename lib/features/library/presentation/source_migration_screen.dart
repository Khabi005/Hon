import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../../core/database/database_service.dart';
import '../../../core/models/book.dart';
import '../../../core/models/novel_source.dart';
import '../../../core/sources/source_migration.dart';
import '../../../core/sources/source_registry.dart';
import '../../../shared/widgets/book_cover_widget.dart';

/// Finds the same novel on other sources and moves the library copy there,
/// keeping the reading position. Pops with the [SourceMigrationResult].
class SourceMigrationScreen extends StatefulWidget {
  final Book book;
  const SourceMigrationScreen({super.key, required this.book});

  @override
  State<SourceMigrationScreen> createState() => _SourceMigrationScreenState();
}

class _SourceMigrationScreenState extends State<SourceMigrationScreen> {
  static const _batch = 8;

  late final TextEditingController _query = TextEditingController(
    text: widget.book.title,
  );
  late final List<ExtensionMeta> _sources = _candidateSources();
  final Map<String, List<SourceNovelSummary>> _results = {};
  final Map<String, String> _errors = {};
  final Set<String> _loading = {};
  int _searched = 0;
  int _generation = 0;
  bool _migrating = false;

  /// Installed sources other than the current one, pinned ones first.
  List<ExtensionMeta> _candidateSources() {
    final registry = SourceRegistry.instance;
    final all = registry
        .getInstalledSources()
        .where((s) => s.id != widget.book.sourceId)
        .toList();
    all.sort((a, b) {
      final pinned = (registry.isPinned(b.id) ? 1 : 0).compareTo(
        registry.isPinned(a.id) ? 1 : 0,
      );
      return pinned != 0 ? pinned : a.name.compareTo(b.name);
    });
    return all;
  }

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _search() {
    _generation++;
    _results.clear();
    _errors.clear();
    _loading.clear();
    _searched = 0;
    _searchMore();
  }

  void _searchMore() {
    final query = _query.text.trim();
    if (query.isEmpty) return;
    final generation = _generation;
    final batch = _sources.skip(_searched).take(_batch).toList();
    setState(() {
      _searched += batch.length;
      _loading.addAll(batch.map((s) => s.id));
    });
    for (final source in batch) {
      SourceRegistry.instance
          .searchSource(source.id, query)
          .then((results) {
            if (!mounted || generation != _generation) return;
            setState(() {
              _results[source.id] = results;
              _loading.remove(source.id);
            });
          })
          .catchError((Object error) {
            if (!mounted || generation != _generation) return;
            setState(() {
              _errors[source.id] = '$error';
              _loading.remove(source.id);
            });
          });
    }
  }

  Future<void> _pick(ExtensionMeta source, SourceNovelSummary novel) async {
    if (_migrating) return;
    setState(() => _migrating = true);
    try {
      final details = await SourceRegistry.instance.getNovelDetails(
        source.id,
        novel.id,
      );
      if (!mounted) return;
      if (details.chapters.isEmpty) {
        _toast('${source.name} lists no chapters for this novel.');
        return;
      }
      final db = DatabaseService.instance;
      final progress = db.getProgress(widget.book.id);
      final current = db.getChapters(widget.book.id);
      final reading = progress != null && current.isNotEmpty
          ? current[progress.chapterIndex.floor().clamp(0, current.length - 1)]
          : null;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Move to ${source.name}?'),
          content: Text(
            [
              '${details.chapters.length} chapters on ${source.name}.',
              if (reading != null)
                'You will continue from the chapter that matches "${reading.title}".',
              'Highlights and bookmarks stay with the old copy.',
            ].join('\n\n'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Move'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final result = await SourceMigration.migrate(
        from: widget.book,
        targetSourceId: source.id,
        details: details,
      );
      if (mounted) Navigator.of(context).pop(result);
    } catch (error) {
      if (mounted) _toast('Could not move the novel: $error');
    } finally {
      if (mounted) setState(() => _migrating = false);
    }
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final secondary = Theme.of(context).colorScheme.onSurfaceVariant;
    final shown = _sources.take(_searched).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Move to another source')),
      body: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: CupertinoSearchTextField(
                  controller: _query,
                  onSubmitted: (_) => _search(),
                ),
              ),
              Expanded(
                child: _sources.isEmpty
                    ? Center(
                        child: Text(
                          'Install another source in Browse first.',
                          style: TextStyle(color: secondary),
                        ),
                      )
                    : ListView(
                        physics: const BouncingScrollPhysics(),
                        children: [
                          for (final source in shown) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      source.name,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  if (_loading.contains(source.id))
                                    const CupertinoActivityIndicator(radius: 8),
                                ],
                              ),
                            ),
                            if (_errors[source.id] != null)
                              _note('Search failed on this source.', secondary)
                            else if (_results[source.id]?.isEmpty == true)
                              _note('No matches.', secondary)
                            else
                              for (final novel
                                  in (_results[source.id] ?? const []).take(5))
                                ListTile(
                                  leading: BookCoverWidget(
                                    title: novel.title,
                                    author: novel.author ?? '',
                                    coverPath: novel.coverUrl,
                                    width: 36,
                                    height: 54,
                                    borderRadius: 3,
                                  ),
                                  title: Text(
                                    novel.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: novel.author == null
                                      ? null
                                      : Text(
                                          novel.author!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                  onTap: () => _pick(source, novel),
                                ),
                          ],
                          if (_searched < _sources.length)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: OutlinedButton(
                                onPressed: _searchMore,
                                child: Text(
                                  'Search ${(_sources.length - _searched).clamp(0, _batch)} more sources',
                                ),
                              ),
                            ),
                          SizedBox(
                            height: MediaQuery.paddingOf(context).bottom + 16,
                          ),
                        ],
                      ),
              ),
            ],
          ),
          if (_migrating)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CupertinoActivityIndicator(radius: 14)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _note(String text, Color color) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
    child: Text(text, style: TextStyle(color: color, fontSize: 13)),
  );
}
