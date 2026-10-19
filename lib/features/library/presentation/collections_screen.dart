import '../../../app/theme/glass_surface.dart';
import 'package:flutter/material.dart';
import '../../../core/database/database_service.dart';
import '../../../shared/widgets/hon_empty_state.dart';

class CollectionsScreen extends StatefulWidget {
  const CollectionsScreen({super.key});
  @override
  State<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends State<CollectionsScreen> {
  final _db = DatabaseService.instance;
  Future<void> _name([String? id]) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) =>
          _NameDialog(initial: id == null ? '' : _db.collections[id] ?? ''),
    );
    if (value == null) return;
    try {
      if (id == null) {
        await _db.createCollection(value);
      } else {
        await _db.renameCollection(id, value);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete collection?'),
        content: const Text(
          'Your books, files and reading progress will be kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _db.deleteCollection(id);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: _db.changeNotifier,
    builder: (context, _, __) {
      final collections = _db.collections.entries.toList()
        ..sort(
          (a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()),
        );
      return Scaffold(
        appBar: AppBar(
          flexibleSpace: GlassStyle.richOf(context)
              ? const GlassSurface(radius: 0, child: SizedBox.expand())
              : null,
          title: const Text('Collections'),
          actions: [
            IconButton(
              tooltip: 'New collection',
              onPressed: _name,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        body: collections.isEmpty
            ? HonEmptyState(
                icon: Icons.folder_open,
                title: 'A shelf for every mood',
                message:
                    'Create collections to organize your library. A book can belong to more than one.',
                actionLabel: 'New Collection',
                onAction: _name,
              )
            : ListView.builder(
                itemCount: collections.length,
                itemBuilder: (context, index) {
                  final entry = collections[index];
                  final count = _db
                      .getLibraryBooks()
                      .where(
                        (book) =>
                            _db
                                .getLibraryEntry(book.id)
                                ?.collectionIds
                                .contains(entry.key) ??
                            false,
                      )
                      .length;
                  return ListTile(
                    leading: const Icon(Icons.folder_outlined),
                    title: Text(entry.value),
                    subtitle: Text('$count ${count == 1 ? 'book' : 'books'}'),
                    onTap: () => Navigator.pop(context, entry.key),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) => action == 'rename'
                          ? _name(entry.key)
                          : _delete(entry.key),
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'rename',
                          child: Text('Rename'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete collection'),
                        ),
                      ],
                    ),
                  );
                },
              ),
      );
    },
  );
}

class _NameDialog extends StatefulWidget {
  final String initial;
  const _NameDialog({required this.initial});
  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _controller = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.initial.isEmpty ? 'New Collection' : 'Rename Collection',
    ),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 80,
      decoration: const InputDecoration(labelText: 'Name'),
      onSubmitted: (value) {
        if (value.trim().isNotEmpty) Navigator.pop(context, value);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          if (_controller.text.trim().isNotEmpty) {
            Navigator.pop(context, _controller.text);
          }
        },
        child: const Text('Save'),
      ),
    ],
  );
}

Future<void> organizeBook(BuildContext context, String bookId) async {
  final db = DatabaseService.instance;
  var selected = {...?db.getLibraryEntry(bookId)?.collectionIds};
  final choices = db.collections;
  if (choices.isEmpty) {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const CollectionsScreen()),
    );
    if (!context.mounted) return;
    if (db.collections.isEmpty) return;
    return organizeBook(context, bookId);
  }
  final result = await showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => StatefulBuilder(
      builder: (context, update) => SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: Column(
          children: [
            ListTile(
              title: const Text('Organize in Collections'),
              trailing: TextButton(
                onPressed: () => Navigator.pop(context, selected),
                child: const Text('Save'),
              ),
            ),
            Expanded(
              child: ListView(
                children: choices.entries
                    .map(
                      (entry) => CheckboxListTile(
                        title: Text(entry.value),
                        value: selected.contains(entry.key),
                        onChanged: (checked) => update(() {
                          checked == true
                              ? selected.add(entry.key)
                              : selected.remove(entry.key);
                        }),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (result != null) await db.setBookCollections(bookId, result);
}
