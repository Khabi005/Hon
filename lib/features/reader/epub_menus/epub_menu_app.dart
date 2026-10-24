import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/glass_surface.dart';
import '../../../app/theme/hon_theme.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../core/utils/log_ignored.dart';
import '../sheets/reader_menu_popup.dart';
import '../sheets/themes_settings_sheet.dart';
import 'epub_contents_sheet.dart';
import 'epub_menu_state.dart';
import 'epub_search_sheet.dart';

/// The sheets the native EPUB reader can open.
enum EpubMenuSheet { menu, contents, search, appearance }

/// Calls into the native EPUB reader, which owns the book and its settings.
abstract class EpubMenuHost {
  Future<Object?> call(String method, [Map<String, Object?>? arguments]);
}

class ChannelEpubMenuHost implements EpubMenuHost {
  ChannelEpubMenuHost(this.channel);
  final MethodChannel channel;

  @override
  Future<Object?> call(String method, [Map<String, Object?>? arguments]) =>
      channel.invokeMethod<Object?>(method, arguments);
}

/// Passes the native reader's requests to the mounted [EpubMenuApp].
class EpubMenuController {
  void Function(EpubMenuSheet sheet, EpubMenuState state)? _show;
  VoidCallback? _back;
  (EpubMenuSheet, EpubMenuState)? _pending;

  void show(EpubMenuSheet sheet, EpubMenuState state) {
    final show = _show;
    if (show == null) {
      _pending = (sheet, state);
    } else {
      show(sheet, state);
    }
  }

  void back() => _back?.call();
}

const epubMenuChannel = MethodChannel('com.hon.reader/epub_menus');

/// Entry point of the second Flutter engine that the native EPUB reader runs
/// to show Hon's own menus over the book. It has no plugins and no database:
/// everything comes from, and goes back to, the native reader.
void runEpubMenus() {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = EpubMenuController();
  final host = ChannelEpubMenuHost(epubMenuChannel);
  epubMenuChannel.setMethodCallHandler((call) async {
    final arguments = call.arguments is Map ? call.arguments as Map : const {};
    switch (call.method) {
      case 'show':
        final sheet = EpubMenuSheet.values
            .where((value) => value.name == arguments['sheet'])
            .firstOrNull;
        final state = arguments['state'];
        if (sheet != null && state is Map) {
          controller.show(sheet, EpubMenuState.fromMap(state));
        }
      case 'back':
        controller.back();
    }
    return null;
  });
  runApp(EpubMenuApp(host: host, controller: controller));
  host.call('ready').catchError((Object e) {
    logIgnored(e, 'epub menus ready');
    return null;
  });
}

class EpubMenuApp extends StatefulWidget {
  final EpubMenuHost host;
  final EpubMenuController controller;

  /// How long a sheet takes to slide away before the native overlay hides.
  final Duration closeDelay;

  const EpubMenuApp({
    super.key,
    required this.host,
    required this.controller,
    this.closeDelay = const Duration(milliseconds: 320),
  });

  @override
  State<EpubMenuApp> createState() => _EpubMenuAppState();
}

class _EpubMenuAppState extends State<EpubMenuApp> {
  final _navigator = GlobalKey<NavigatorState>();
  EpubMenuState _state = const EpubMenuState();
  late final ReaderPreferencesNotifier _preferences =
      ReaderPreferencesNotifier.detached(
        const ReaderPreferencesState(),
        _preferencesChanged,
      );
  Timer? _closeTimer;

  EpubMenuHost get _host => widget.host;

  @override
  void initState() {
    super.initState();
    final controller = widget.controller;
    controller._show = _show;
    controller._back = _back;
    final pending = controller._pending;
    controller._pending = null;
    if (pending != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _show(pending.$1, pending.$2),
      );
    }
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    widget.controller._show = null;
    widget.controller._back = null;
    super.dispose();
  }

  BuildContext? get _context => _navigator.currentContext;

  ReaderThemeConfig get _theme => _state.preferences.themeConfig;

  void _call(String method, [Map<String, Object?>? arguments]) {
    _host.call(method, arguments).catchError((Object e) {
      logIgnored(e, 'epub menus $method');
      return null;
    });
  }

  void _preferencesChanged(ReaderPreferencesState next) {
    _state = _state.copyWith(preferences: next);
    _call('setPreferences', next.toMap());
    // The app theme follows the reading theme.
    if (mounted) setState(() {});
  }

  void _show(EpubMenuSheet sheet, EpubMenuState state) {
    _closeTimer?.cancel();
    setState(() => _state = state);
    _preferences.replace(state.preferences);
    switch (sheet) {
      case EpubMenuSheet.menu:
        _openMenu();
      case EpubMenuSheet.contents:
        _openContents();
      case EpubMenuSheet.search:
        _openSearch();
      case EpubMenuSheet.appearance:
        _openAppearance();
    }
  }

  void _back() {
    final navigator = _navigator.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.maybePop();
    } else {
      _call('closed');
    }
  }

  /// Hides the native overlay once the last sheet has slid away. Opening one
  /// sheet from another keeps it.
  Future<void> _whenDone(Future<void> sheet) async {
    try {
      await sheet;
    } finally {
      _closeTimer?.cancel();
      _closeTimer = Timer(widget.closeDelay, () {
        if (!mounted) return;
        if (_navigator.currentState?.canPop() ?? false) return;
        _call('closed');
      });
    }
  }

  void _openMenu() {
    final context = _context;
    if (context == null) {
      _call('closed');
      return;
    }
    final state = _state;
    _whenDone(
      ReaderMenuPopup.show(
        context,
        theme: _theme,
        onOpenContents: _openContents,
        onOpenSearch: _openSearch,
        onOpenThemes: _openAppearance,
        onToggleReadingMode: () => _call('toggleScroll'),
        onToggleBookmark: () => _call('toggleBookmark'),
        onToggleOrientationLock: () => _call('toggleRotationLock'),
        isOrientationLocked: state.rotationLocked,
        isBookmarked: state.isBookmarked,
        isContinuousScroll:
            state.preferences.layoutMode == ReaderLayoutMode.verticalScroll,
      ),
    );
  }

  void _openContents() {
    final context = _context;
    if (context == null) {
      _call('closed');
      return;
    }
    _whenDone(
      EpubContentsSheet.show(
        context,
        state: _state,
        theme: _theme,
        onSelectToc: (index) => _call('goToToc', {'index': index}),
        onSelectBookmark: (index) => _call('goToBookmark', {'index': index}),
        onSelectHighlight: (index) => _call('goToHighlight', {'index': index}),
        onDeleteHighlight: (index) async {
          try {
            final remaining = await _host.call('deleteHighlight', {
              'index': index,
            });
            final highlights = EpubMenuState.highlightsFrom(remaining);
            _state = _state.copyWith(highlights: highlights);
            return highlights;
          } catch (e) {
            logIgnored(e, 'epub menus delete highlight');
            return _state.highlights;
          }
        },
      ),
    );
  }

  void _openSearch() {
    final context = _context;
    if (context == null) {
      _call('closed');
      return;
    }
    _whenDone(
      EpubSearchSheet.show(
        context,
        theme: _theme,
        search: _search,
        onSelect: (index) => _call('goToSearchResult', {'index': index}),
      ),
    );
  }

  Future<EpubSearchResult> _search(String query) async {
    try {
      final result = await _host.call('search', {'query': query});
      if (result is Map) {
        return (
          matches: const <EpubSearchMatch>[],
          error: result['error'] as String? ?? 'Search failed.',
        );
      }
      return (
        matches: [
          for (final item in result as List? ?? const [])
            if (item is Map)
              EpubSearchMatch(
                title: item['title'] as String?,
                before: item['before'] as String? ?? '',
                highlight: item['highlight'] as String? ?? '',
                after: item['after'] as String? ?? '',
              ),
        ],
        error: null,
      );
    } catch (e) {
      logIgnored(e, 'epub menus search');
      return (matches: const <EpubSearchMatch>[], error: 'Search failed.');
    }
  }

  void _openAppearance() {
    final context = _context;
    if (context == null) {
      _call('closed');
      return;
    }
    _whenDone(
      ThemesSettingsSheet.show(
        context,
        supportsTypography: _state.canReflow,
        // Fixed-layout books always open in pages.
        layoutControl: _state.canReflow ? null : const SizedBox.shrink(),
        onReset: () async {
          try {
            final values = await _host.call('resetPreferences');
            if (values is Map) {
              final next = ReaderPreferencesState.fromMap(
                Map<String, dynamic>.from(values),
              );
              _preferences.replace(next);
              setState(() => _state = _state.copyWith(preferences: next));
            }
          } catch (e) {
            logIgnored(e, 'epub menus reset');
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = _theme.systemBrightness == Brightness.dark;
    final base = dark ? HonTheme.darkTheme : HonTheme.lightTheme;
    return ProviderScope(
      overrides: [
        readerPreferencesProvider.overrideWith((ref) => _preferences),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        color: const Color(0x00000000),
        navigatorKey: _navigator,
        theme: base.copyWith(
          extensions: [
            ...base.extensions.values,
            GlassStyle(rich: _state.isGlass),
          ],
        ),
        // The book shows through; only the sheets are drawn.
        onGenerateRoute: (_) => PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => const SizedBox.expand(),
        ),
      ),
    );
  }
}
