import 'dart:io';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' as html;
import '../../../app/theme/hon_theme.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../core/utils/epub_parser.dart';

/// Searches saved text in a worker isolate. Opening a book no longer requires
/// reading every downloaded chapter, and typing never scans the whole novel.
class ReaderSearchDialog extends StatefulWidget {
  final List<EpubChapterItem> chapters;
  final Map<int, String> localFiles;
  final ReaderThemeConfig theme;
  const ReaderSearchDialog({
    super.key,
    required this.chapters,
    required this.localFiles,
    required this.theme,
  });
  @override
  State<ReaderSearchDialog> createState() => _ReaderSearchDialogState();
}

class _ReaderSearchDialogState extends State<ReaderSearchDialog> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;
  List<(int, String)>? _matches;
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim().toLowerCase();
    if (_busy || query.length < 2) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    // Capture serializable data only, never the widget/controller or UI state.
    final entries = [
      for (var i = 0; i < widget.chapters.length; i++)
        (
          i,
          widget.chapters[i].title,
          widget.chapters[i].htmlContent,
          widget.localFiles[i],
        ),
    ];
    try {
      final matches = await _searchSavedChapters(entries, query);
      if (mounted) setState(() => _matches = matches);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not search saved chapters. Try again.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: widget.theme.systemBrightness == Brightness.dark
        ? HonTheme.darkTheme
        : HonTheme.lightTheme,
    child: AlertDialog(
      title: const Text('Search Book'),
      backgroundColor: widget.theme.uiControlsBackground,
      content: SizedBox(
        width: 440,
        height: MediaQuery.sizeOf(context).height * .5,
        child: Column(
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(
                hintText: 'Search saved passages',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _busy
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? Center(child: Text(_error!))
                  : _matches == null
                  ? const Center(
                      child: Text(
                        'Search chapter titles and text available on this device.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _matches!.isEmpty
                  ? const Center(child: Text('No matching passages found.'))
                  : ListView.builder(
                      itemCount: _matches!.length,
                      itemBuilder: (context, index) {
                        final (chapter, snippet) = _matches![index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(widget.chapters[chapter].title),
                          subtitle: snippet.isEmpty
                              ? null
                              : Text(
                                  snippet,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => Navigator.pop(context, chapter),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: _busy ? null : _search,
          child: const Text('Search'),
        ),
      ],
    ),
  );
}

// A top-level entry point keeps State/controller closures out of the isolate
// message. Only immutable text/path records cross the boundary.
Future<List<(int, String)>> _searchSavedChapters(
  List<(int, String, String, String?)> entries,
  String query,
) => Isolate.run(() {
  final found = <(int, String)>[];
  for (final (index, title, body, path) in entries) {
    var text = body;
    if (text.isEmpty && path != null) {
      try {
        text = File(path).readAsStringSync();
      } on FileSystemException {
        /* Missing chapters are skipped. */
      }
    }
    text =
        html.parse(text).body?.text.replaceAll(RegExp(r'\s+'), ' ').trim() ??
        '';
    final offset = text.toLowerCase().indexOf(query);
    if (offset >= 0 || title.toLowerCase().contains(query)) {
      final start = (offset - 45).clamp(0, text.length);
      final end = (start + 180).clamp(start, text.length);
      found.add((index, text.substring(start, end)));
      if (found.length == 30) break;
    }
  }
  return found;
});
