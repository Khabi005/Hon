import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../app/theme/glass_surface.dart';
import '../../../app/theme/reader_theme.dart';

/// One match in a native EPUB search.
class EpubSearchMatch {
  final String? title;
  final String before;
  final String highlight;
  final String after;
  const EpubSearchMatch({
    this.title,
    this.before = '',
    required this.highlight,
    this.after = '',
  });
}

/// The outcome of a search: matches, or a message saying why there are none.
typedef EpubSearchResult = ({List<EpubSearchMatch> matches, String? error});

/// Searches the whole book through the native reader.
class EpubSearchSheet extends StatefulWidget {
  static const maxResults = 100;

  final ReaderThemeConfig theme;
  final Future<EpubSearchResult> Function(String query) search;
  final ValueChanged<int> onSelect;

  const EpubSearchSheet({
    super.key,
    required this.theme,
    required this.search,
    required this.onSelect,
  });

  static Future<void> show(
    BuildContext context, {
    required ReaderThemeConfig theme,
    required Future<EpubSearchResult> Function(String query) search,
    required ValueChanged<int> onSelect,
  }) {
    SemanticsService.announce('Search opened', TextDirection.ltr);
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          EpubSearchSheet(theme: theme, search: search, onSelect: onSelect),
    );
  }

  @override
  State<EpubSearchSheet> createState() => _EpubSearchSheetState();
}

class _EpubSearchSheetState extends State<EpubSearchSheet> {
  final _query = TextEditingController();
  List<EpubSearchMatch>? _matches;
  String? _status;
  bool _busy = false;
  int _generation = 0;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final query = _query.text.trim();
    if (query.length < 2) {
      setState(() => _status = 'Enter at least two characters.');
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _status = null;
    });
    final result = await widget.search(query);
    if (!mounted || generation != _generation) return;
    setState(() {
      _busy = false;
      _matches = result.matches;
      _status =
          result.error ??
          switch (result.matches.length) {
            0 => 'No matches.',
            1 => '1 match',
            EpubSearchSheet.maxResults =>
              'Showing the first ${EpubSearchSheet.maxResults} matches. Refine your search for more.',
            final count => '$count matches',
          };
    });
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.theme;
    final rich = GlassStyle.richOf(context);
    final background = rich
        ? cfg.uiControlsBackground.withValues(alpha: 0.82)
        : cfg.uiControlsBackground;
    final matches = _matches ?? const <EpubSearchMatch>[];
    // A Material, so list rows show their ink on the sheet colour.
    final content = Material(
      color: background,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Search Book',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: cfg.textColor,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close search',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      color: cfg.secondaryTextColor,
                      size: 25,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: CupertinoSearchTextField(
                controller: _query,
                autofocus: true,
                placeholder: 'Find a word or passage',
                style: TextStyle(color: cfg.textColor),
                onSubmitted: (_) => _submit(),
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(20),
                child: CupertinoActivityIndicator(),
              )
            else if (_status != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _status!,
                    style: TextStyle(
                      fontSize: 12,
                      color: cfg.secondaryTextColor,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.separated(
                physics: const BouncingScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  8,
                  4,
                  8,
                  MediaQuery.paddingOf(context).bottom + 12,
                ),
                itemCount: _busy ? 0 : matches.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: cfg.textColor.withValues(alpha: 0.08),
                ),
                itemBuilder: (context, index) {
                  final match = matches[index];
                  return ListTile(
                    title: match.title == null
                        ? null
                        : Text(
                            match.title!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: cfg.secondaryTextColor,
                            ),
                          ),
                    subtitle: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: match.before),
                          TextSpan(
                            text: match.highlight,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              backgroundColor: const Color(
                                0xFFFFCC00,
                              ).withValues(alpha: 0.35),
                            ),
                          ),
                          TextSpan(text: match.after),
                        ],
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 14, color: cfg.textColor),
                    ),
                    onTap: () {
                      Navigator.of(context).pop();
                      widget.onSelect(index);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        child: rich
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: content,
              )
            : content,
      ),
    );
  }
}
