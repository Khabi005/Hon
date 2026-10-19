import 'package:flutter/material.dart';
import '../../../core/models/chapter.dart';

class ChapterDownloadSheet extends StatefulWidget {
  final List<Chapter> chapters;
  final int unreadStart;
  const ChapterDownloadSheet({
    super.key,
    required this.chapters,
    required this.unreadStart,
  });
  @override
  State<ChapterDownloadSheet> createState() => _ChapterDownloadSheetState();
}

class _ChapterDownloadSheetState extends State<ChapterDownloadSheet> {
  final Set<String> selected = {};
  final _from = TextEditingController(text: '1');
  final _to = TextEditingController();
  @override
  void initState() {
    super.initState();
    _to.text = '${widget.chapters.length}';
  }

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          ListTile(
            title: const Text('Download Chapters'),
            subtitle: Text('${selected.length} selected'),
            trailing: TextButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.pop(context, selected),
              child: const Text('Queue'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    selected.clear();
                    selected.addAll(
                      widget.chapters
                          .where(
                            (chapter) =>
                                chapter.downloadState !=
                                ChapterDownloadState.downloaded,
                          )
                          .map((chapter) => chapter.id),
                    );
                  }),
                  child: const Text('All Missing'),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    selected.clear();
                    selected.addAll(
                      widget.chapters
                          .skip(widget.unreadStart)
                          .where(
                            (chapter) =>
                                chapter.downloadState !=
                                ChapterDownloadState.downloaded,
                          )
                          .map((chapter) => chapter.id),
                    );
                  }),
                  child: const Text('Unread'),
                ),
                TextButton(
                  onPressed: () => setState(selected.clear),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _from,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'From chapter',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _to,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'To chapter'),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    final from = int.tryParse(_from.text);
                    final to = int.tryParse(_to.text);
                    if (from == null ||
                        to == null ||
                        from < 1 ||
                        to < from ||
                        to > widget.chapters.length) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Enter a valid chapter range.'),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      selected.clear();
                      selected.addAll(
                        widget.chapters
                            .sublist(from - 1, to)
                            .map((chapter) => chapter.id),
                      );
                    });
                  },
                  child: const Text('Select'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: widget.chapters.length,
              itemBuilder: (context, index) {
                final chapter = widget.chapters[index];
                return CheckboxListTile(
                  title: Text(chapter.title),
                  subtitle:
                      chapter.downloadState == ChapterDownloadState.downloaded
                      ? const Text('Already saved offline')
                      : null,
                  value: selected.contains(chapter.id),
                  onChanged: (checked) => setState(() {
                    checked == true
                        ? selected.add(chapter.id)
                        : selected.remove(chapter.id);
                  }),
                );
              },
            ),
          ),
        ],
      ),
    ),
  );
}
