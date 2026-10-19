import 'package:flutter/material.dart';
import '../../../core/sources/extension_repository_service.dart';
import '../../../core/sources/installed_extension_service.dart';
import '../../../core/sources/source_registry.dart';

class ExtensionRepositoriesScreen extends StatefulWidget {
  final ExtensionRepositoryService? repositoryService;
  const ExtensionRepositoriesScreen({super.key, this.repositoryService});

  @override
  State<ExtensionRepositoriesScreen> createState() =>
      _ExtensionRepositoriesScreenState();
}

class _ExtensionRepositoriesScreenState
    extends State<ExtensionRepositoriesScreen> {
  late final service =
      widget.repositoryService ?? ExtensionRepositoryService.instance;
  final installed = InstalledExtensionService.instance;
  final Set<String> busy = {};

  @override
  void initState() {
    super.initState();
    service.addListener(_changed);
    installed.addListener(_changed);
  }

  @override
  void dispose() {
    service.removeListener(_changed);
    installed.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _addRepository() async {
    final submitted = await showDialog<(String, String)>(
      context: context,
      builder: (_) => const _AddRepositoryDialog(),
    );
    if (!mounted) return;
    if (submitted != null) {
      setState(() => busy.add('add'));
      try {
        await service.add(submitted.$1, submitted.$2);
        if (mounted) _message('Repository catalog added.');
      } catch (error) {
        if (mounted) _message('Could not add repository: $error');
      } finally {
        if (mounted) setState(() => busy.remove('add'));
      }
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..removeCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _refresh(String id) async {
    setState(() => busy.add(id));
    try {
      await service.refresh(id);
      if (mounted) _message('Repository catalog refreshed.');
    } catch (error) {
      if (mounted) _message('Refresh failed: $error');
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  Future<void> _remove(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove repository?'),
        content: const Text(
          'This removes the catalog entry. Books and downloads stay in your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      try {
        await service.remove(id);
      } catch (error) {
        if (mounted) _message('Could not remove repository: $error');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final repositories = service.repositories;
    return Scaffold(
      appBar: AppBar(title: const Text('Extension repositories')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: busy.contains('add') ? null : _addRepository,
        icon: const Icon(Icons.add),
        label: const Text('Add repository'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (service.loadError != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(service.loadError!),
              ),
            ),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Add an HTTPS Shosetsu repository, then install compatible scripts. '
                'Shared libraries are resolved automatically. '
                'Only install scripts from repositories you trust.',
              ),
            ),
          ),
          if (repositories.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('No custom repositories added.'),
            ),
          for (final repository in repositories)
            Card(
              key: ValueKey(repository.id),
              child: ListTile(
                title: Text(repository.name),
                subtitle: Text(
                  '${repository.scripts.length} sources\n${repository.url}',
                ),
                isThreeLine: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => _RepositorySourcesScreen(
                      repositoryId: repository.id,
                      service: service,
                    ),
                  ),
                ),
                trailing: busy.contains(repository.id)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : PopupMenuButton<String>(
                        onSelected: (action) => action == 'refresh'
                            ? _refresh(repository.id)
                            : _remove(repository.id),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: 'refresh',
                            child: Text('Refresh'),
                          ),
                          PopupMenuItem(
                            value: 'remove',
                            child: Text('Remove repository'),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }
}

// Dialog-owned controllers remain alive throughout the route's exit animation.
class _AddRepositoryDialog extends StatefulWidget {
  const _AddRepositoryDialog();

  @override
  State<_AddRepositoryDialog> createState() => _AddRepositoryDialogState();
}

class _AddRepositoryDialogState extends State<_AddRepositoryDialog> {
  final name = TextEditingController();
  final url = TextEditingController();
  final form = GlobalKey<FormState>();

  @override
  void dispose() {
    name.dispose();
    url.dispose();
    super.dispose();
  }

  void submit() {
    if (form.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      Navigator.of(context).pop((name.text.trim(), url.text.trim()));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add extension repository'),
    content: SingleChildScrollView(
      child: Form(
        key: form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Name'),
              autofocus: true,
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  value == null || value.trim().isEmpty ? 'Enter a name' : null,
            ),
            TextFormField(
              controller: url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'HTTPS repository URL',
                hintText: 'https://example.com/repo/',
              ),
              onFieldSubmitted: (_) => submit(),
              validator: (value) {
                final uri = Uri.tryParse(value?.trim() ?? '');
                return uri?.scheme != 'https' || uri!.host.isEmpty
                    ? 'Enter an HTTPS URL'
                    : null;
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: submit, child: const Text('Add')),
    ],
  );
}

class _RepositorySourcesScreen extends StatefulWidget {
  final String repositoryId;
  final ExtensionRepositoryService service;
  const _RepositorySourcesScreen({
    required this.repositoryId,
    required this.service,
  });
  @override
  State<_RepositorySourcesScreen> createState() =>
      _RepositorySourcesScreenState();
}

class _RepositorySourcesScreenState extends State<_RepositorySourcesScreen> {
  final installed = InstalledExtensionService.instance;
  final busy = <String>{};
  String query = '';
  @override
  void initState() {
    super.initState();
    widget.service.addListener(changed);
    installed.addListener(changed);
  }

  void changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.service.removeListener(changed);
    installed.removeListener(changed);
    super.dispose();
  }

  Future<void> install(
    ExtensionRepository repo,
    RepositoryScript script,
  ) async {
    final id = installed.sourceIdFor(repo, script);
    if (busy.contains(id)) return;
    if (installed.find(id) == null) {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Install ${script.name}?'),
          content: Text(
            'This source is provided by ${repo.name}. It runs inside Hon and requests pages from its website.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Install'),
            ),
          ],
        ),
      );
      if (!mounted || approved != true) return;
    }
    setState(() => busy.add(id));
    try {
      await installed.install(repo, script);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Installed ${script.name}.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Install failed: $error')));
      }
    } finally {
      if (mounted) setState(() => busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = widget.service.repositories
        .where((repo) => repo.id == widget.repositoryId)
        .firstOrNull;
    final scripts =
        repo?.scripts
            .where(
              (script) => '${script.name} ${script.language}'
                  .toLowerCase()
                  .contains(query.toLowerCase()),
            )
            .toList() ??
        <RepositoryScript>[];
    return Scaffold(
      appBar: AppBar(title: Text(repo?.name ?? 'Repository removed')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Find a source or language',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => query = value),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: scripts.length,
              itemBuilder: (context, index) {
                final script = scripts[index];
                final id = installed.sourceIdFor(repo!, script);
                final current = installed.find(id);
                return ListTile(
                  title: Text(script.name),
                  subtitle: Text(
                    '${SourceRegistry.languageName(script.language)} • v${script.version}${current == null
                        ? ''
                        : current.enabled
                        ? ' • Installed'
                        : ' • Disabled'}',
                  ),
                  trailing: busy.contains(id)
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : TextButton(
                          onPressed: () => install(repo, script),
                          child: Text(
                            current == null
                                ? 'Install'
                                : current.version == script.version
                                ? 'Reinstall'
                                : 'Update',
                          ),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
