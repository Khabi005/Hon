import 'package:flutter/material.dart';
import '../../../core/models/novel_source.dart';
import '../../../core/sources/installed_extension_service.dart';
import '../../../core/sources/source_preferences.dart';
import '../../../core/sources/source_health_service.dart';

class SourceControlsScreen extends StatefulWidget {
  final String sourceId, name;
  final SourceCatalogInfo info;
  const SourceControlsScreen({
    super.key,
    required this.sourceId,
    required this.name,
    required this.info,
  });
  @override
  State<SourceControlsScreen> createState() => _SourceControlsScreenState();
}

class _SourceControlsScreenState extends State<SourceControlsScreen> {
  Map<String, dynamic> _settings = {}, _filters = {};
  List<String> _allowedHosts = [];
  bool _loading = true, _saving = false;
  int _revision = 0;
  String? _loadError;
  SourceHealthResult? _healthResult;
  bool _testingHealth = false;

  Future<void> _testHealth() async {
    setState(() => _testingHealth = true);
    try {
      final res = await SourceHealthService.testSource(widget.sourceId);
      if (mounted) setState(() => _healthResult = res);
    } finally {
      if (mounted) setState(() => _testingHealth = false);
    }
  }

  Future<void> _addBlockedHost(String host) async {
    final clean = host.trim().toLowerCase();
    if (clean.isEmpty) return;
    final updated = {..._allowedHosts, clean}.toList()..sort();
    setState(() {
      _allowedHosts = updated;
    });
    if (InstalledExtensionService.instance.find(widget.sourceId) != null) {
      await InstalledExtensionService.instance.updateAllowedHosts(
        widget.sourceId,
        updated,
      );
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added $clean to allowed hosts')),
      );
    }
    await _testHealth();
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final settings = await SourcePreferences.read(widget.sourceId);
      final filters = await SourcePreferences.read(
        widget.sourceId,
        filters: true,
      );
      final ext = InstalledExtensionService.instance.find(widget.sourceId);
      final allowedHosts = List<String>.from(ext?.allowedHosts ?? []);
      if (mounted) {
        setState(() {
          _settings = settings;
          _filters = filters;
          _allowedHosts = allowedHosts;
          _loading = false;
          _loadError = null;
        });
      }
    } catch (error) {
      if (mounted) setState(() { _loading = false; _loadError = 'Could not load saved preferences: $error'; });
    }
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _saving = true);
    try {
      await SourcePreferences.save(
        widget.sourceId,
        Map<String, dynamic>.from(_settings),
        secretKeys: widget.info.settings
            .where(
              (control) =>
                  control.kind == 'PasswordFilter' ||
                  RegExp(
                    r'password|token|secret|api.?key|username|e.?mail|login',
                    caseSensitive: false,
                  ).hasMatch(control.label),
            )
            .map((control) => '${control.id}')
            .toList(),
      );
      await SourcePreferences.save(
        widget.sourceId,
        Map<String, dynamic>.from(_filters),
        filters: true,
      );
      if (InstalledExtensionService.instance.find(widget.sourceId) != null) {
        await InstalledExtensionService.instance.updateAllowedHosts(
          widget.sourceId,
          _allowedHosts,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save source controls: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _promptAddHost() {
    final controller = TextEditingController();
    showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Allowed Host'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Hostname or domain',
            hintText: 'e.g. cdn.example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final raw = controller.text.trim().toLowerCase();
              final host = raw.replaceAll(RegExp(r'^https?://'), '').split('/')[0];
              if (host.isNotEmpty) {
                Navigator.pop(context, host);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    ).then((newHost) {
      if (newHost != null && newHost.isNotEmpty) {
        setState(() {
          if (!_allowedHosts.contains(newHost)) {
            _allowedHosts = [..._allowedHosts, newHost]..sort();
          }
        });
      }
    });
  }

  Widget _control(SourceControl control, Map<String, dynamic> values) {
    final key = '${control.id}';
    final value = values[key] ?? control.value;
    final label = control.label.isEmpty
        ? 'Option ${control.id}'
        : control.label;
    void update(dynamic next) => setState(() => values[key] = next);
    switch (control.kind) {
      case 'CheckboxFilter':
      case 'SwitchFilter':
        return SwitchListTile(
          title: Text(label),
          value: value == true,
          onChanged: _saving ? null : update,
        );
      case 'DropdownFilter':
      case 'RadioGroupFilter':
      case 'TriStateFilter':
        final options = control.kind == 'TriStateFilter'
            ? ['Any', 'Include', 'Exclude']
            : control.options;
        if (options.isEmpty) {
          return ListTile(
            title: Text(label),
            subtitle: const Text('No options supplied by this source.'),
          );
        }
        final selected = (value is num ? value.toInt() : 0).clamp(
          0,
          options.length - 1,
        );
        return ListTile(
          title: Text(label),
          subtitle: DropdownButton<int>(
            isExpanded: true,
            value: selected,
            items: [
              for (var i = 0; i < options.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    options[i],
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: _saving ? null : update,
          ),
        );
      case 'TextFilter':
      case 'PasswordFilter':
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextFormField(
            key: ValueKey(
              '$_revision:${control.kind}:$key:${identical(values, _settings)}',
            ),
            enabled: !_saving,
            initialValue: value?.toString() ?? '',
            obscureText: control.kind == 'PasswordFilter',
            maxLength: 4096,
            decoration: InputDecoration(labelText: label, counterText: ''),
            onChanged: (text) => values[key] = text,
          ),
        );
      default:
        return ListTile(
          title: Text(label),
          subtitle: const Text('This source control type is unavailable.'),
        );
    }
  }

  Widget _controlList(
    List<SourceControl> controls,
    Map<String, dynamic> values,
  ) => SliverList.builder(
    itemCount: controls.length,
    itemBuilder: (context, index) {
      final control = controls[index];
      final newGroup =
          control.group.isNotEmpty &&
          (index == 0 || controls[index - 1].group != control.group);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (newGroup)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                control.group,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          _control(control, values),
        ],
      );
    },
  );

  Future<void> _website() async {
    var url = widget.info.baseUrl;
    if (Uri.tryParse(url)?.scheme != 'https') {
      var entered = '';
      String? error;
      final chosen = await showDialog<String>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('Source Website'),
            content: TextField(
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(
                labelText: 'HTTPS website URL',
                errorText: error,
              ),
              onChanged: (value) => entered = value,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  final uri = Uri.tryParse(entered.trim());
                  if (uri?.scheme != 'https' ||
                      uri!.host.isEmpty ||
                      uri.userInfo.isNotEmpty) {
                    update(() => error = 'Enter the source’s HTTPS website.');
                    return;
                  }
                  Navigator.pop(context, entered.trim());
                },
                child: const Text('Open'),
              ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      url = chosen;
    }
    try {
      await SourcePreferences.openWebsite(widget.sourceId, url);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open source website: $error')),
        );
      }
    }
  }

  Widget _buildHealthBadge(SourceHealthResult res) {
    Color bg;
    Color fg;
    IconData icon;
    switch (res.state) {
      case SourceHealthState.ok:
        bg = Colors.green.withOpacity(0.15);
        fg = Colors.green;
        icon = Icons.check_circle_outline;
        break;
      case SourceHealthState.needsLogin:
        bg = Colors.amber.withOpacity(0.15);
        fg = Colors.amber.shade800;
        icon = Icons.lock_outline;
        break;
      case SourceHealthState.blockedByPolicy:
        bg = Colors.red.withOpacity(0.15);
        fg = Colors.redAccent;
        icon = Icons.security;
        break;
      case SourceHealthState.failing:
        bg = Colors.red.withOpacity(0.15);
        fg = Colors.redAccent;
        icon = Icons.error_outline;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  res.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: fg,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          if (res.details != null && res.details != res.label) ...[
            const SizedBox(height: 6),
            Text(
              res.details!,
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          if (res.state == SourceHealthState.blockedByPolicy && res.blockedHost != null) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.add_moderator, size: 16),
              label: Text('Add ${res.blockedHost} to allowed hosts'),
              onPressed: () => _addBlockedHost(res.blockedHost!),
            ),
          ],
          if (res.state == SourceHealthState.needsLogin) ...[
            const SizedBox(height: 10),
            FilledButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open website / Sign In'),
              onPressed: _website,
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final website = Uri.tryParse(widget.info.baseUrl);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          TextButton(
            onPressed: _loading || _saving ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                if (_loadError != null) SliverToBoxAdapter(child: ListTile(
                  title: Text(_loadError!),
                  subtitle: const Text('You can reset this source’s preferences below and sign in again.'),
                )),
                SliverToBoxAdapter(
                  child: ListTile(
                    leading: const Icon(Icons.public),
                    title: const Text('Website / Sign In'),
                    subtitle: Text(
                      website?.scheme == 'https'
                          ? website!.host
                          : 'Enter the source website',
                    ),
                    trailing: const Icon(Icons.open_in_new),
                    onTap: _website,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Card(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Source Health',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              OutlinedButton.icon(
                                icon: _testingHealth
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.network_check, size: 16),
                                label: Text(_testingHealth ? 'Testing…' : 'Test source'),
                                onPressed: _testingHealth ? null : _testHealth,
                              ),
                            ],
                          ),
                          if (_healthResult != null) ...[
                            const SizedBox(height: 12),
                            _buildHealthBadge(_healthResult!),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),

                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Source preferences',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                if (widget.info.settings.isEmpty)
                  const SliverToBoxAdapter(
                    child: ListTile(
                      subtitle: Text(
                        'This source does not declare additional preferences.',
                      ),
                    ),
                  ),
                _controlList(widget.info.settings, _settings),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(
                      'Search filters',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Saved filters apply to this source’s catalog and global search.',
                    ),
                  ),
                ),
                if (widget.info.filters.isEmpty)
                  const SliverToBoxAdapter(
                    child: ListTile(
                      subtitle: Text(
                        'This source does not declare search filters.',
                      ),
                    ),
                  ),
                _controlList(widget.info.filters, _filters),
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                    child: Text(
                      'Network Policy & Allowed Hosts',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Hon restricts network requests to the declared source baseURL and explicitly allowed hosts.',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ),
                if (widget.info.baseUrl.isNotEmpty)
                  SliverToBoxAdapter(
                    child: ListTile(
                      leading: const Icon(Icons.public),
                      title: const Text('Declared Base URL'),
                      subtitle: Text(widget.info.baseUrl),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Additional Allowed Hosts',
                          style: TextStyle(fontWeight: FontWeight.w500),
                        ),
                        TextButton.icon(
                          onPressed: _saving ? null : _promptAddHost,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Host'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_allowedHosts.isEmpty)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'No extra hosts configured. Subdomains of the base URL are automatically allowed.',
                        style: TextStyle(fontStyle: FontStyle.italic, fontSize: 13),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _allowedHosts.map((host) {
                          return Chip(
                            label: Text(host),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: _saving
                                ? null
                                : () {
                                    setState(() {
                                      _allowedHosts = _allowedHosts
                                          .where((h) => h != host)
                                          .toList();
                                    });
                                  },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () {
                              setState(() {
                                _settings = {};
                                _filters = {};
                                _revision++;
                              });
                            },
                      child: const Text('Reset to Source Defaults'),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: MediaQuery.paddingOf(context).bottom + 16,
                  ),
                ),
              ],
            ),
    );
  }
}
