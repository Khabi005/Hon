import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/bootstrap/providers.dart';
import '../../../app/theme/glass_surface.dart';
import '../../../app/theme/hon_theme.dart';
import '../../../app/theme/reader_theme.dart';
import '../../../core/database/database_service.dart';

class ThemesSettingsSheet extends ConsumerWidget {
  final bool supportsTypography;
  final Widget? layoutControl;
  final String? bookId;
  const ThemesSettingsSheet({
    super.key,
    this.supportsTypography = true,
    this.layoutControl,
    this.bookId,
  });

  static Future<void> show(
    BuildContext context, {
    bool supportsTypography = true,
    Widget? layoutControl,
    String? bookId,
  }) {
    SemanticsService.announce('Themes and settings opened', TextDirection.ltr);
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => ThemesSettingsSheet(
        supportsTypography: supportsTypography,
        layoutControl: layoutControl,
        bookId: bookId,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(readerPreferencesProvider);
    final notifier = ref.read(readerPreferencesProvider.notifier);
    if (bookId != null && notifier.activeBookId != bookId) {
      notifier.setActiveBookId(bookId);
    }
    final cfg = prefs.themeConfig;
    final rich = GlassStyle.richOf(context);
    final baseTheme = cfg.systemBrightness == Brightness.dark
        ? HonTheme.darkTheme
        : HonTheme.lightTheme;
    final themeData = baseTheme.copyWith(
      extensions: Theme.of(context).extensions.values,
    );
    final bg = rich
        ? cfg.uiControlsBackground.withValues(alpha: 0.78)
        : cfg.uiControlsBackground;

    final sheetContent = Material(
      color: bg,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .85,
          maxWidth: 600,
        ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              20,
              10,
              20,
              MediaQuery.paddingOf(context).bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(context, 'Themes & Settings', cfg),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (supportsTypography)
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: Tooltip(
                                  message: 'Decrease font size',
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: prefs.fontSize > 12
                                        ? () {
                                            notifier.decreaseFontSize();
                                            SemanticsService.announce(
                                              'Font size ${(prefs.fontSize - 1).round()}',
                                              TextDirection.ltr,
                                            );
                                          }
                                        : null,
                                    child: const Text(
                                      'A',
                                      semanticsLabel: 'Decrease font size',
                                      style: TextStyle(fontSize: 15),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                '${prefs.fontSize.round()}',
                                style: TextStyle(
                                  color: cfg.textColor,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SizedBox(
                                height: 48,
                                child: Tooltip(
                                  message: 'Increase font size',
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    onPressed: prefs.fontSize < 32
                                        ? () {
                                            notifier.increaseFontSize();
                                            SemanticsService.announce(
                                              'Font size ${(prefs.fontSize + 1).round()}',
                                              TextDirection.ltr,
                                            );
                                          }
                                        : null,
                                    child: const Text(
                                      'A',
                                      semanticsLabel: 'Increase font size',
                                      style: TextStyle(fontSize: 20),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (supportsTypography) const SizedBox(width: 10),
                    if (layoutControl != null)
                      Expanded(child: layoutControl!)
                    else
                      Tooltip(
                        message: prefs.layoutMode == ReaderLayoutMode.paginated
                            ? 'Switch to scrolling'
                            : 'Switch to pages',
                        child: SizedBox(
                          height: 48,
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            onPressed: () => notifier.setLayoutMode(
                              prefs.layoutMode == ReaderLayoutMode.paginated
                                  ? ReaderLayoutMode.verticalScroll
                                  : ReaderLayoutMode.paginated,
                            ),
                            icon: Icon(
                              prefs.layoutMode == ReaderLayoutMode.paginated
                                  ? CupertinoIcons.book
                                  : CupertinoIcons.doc_text,
                              size: 16,
                            ),
                            label: Text(
                              prefs.layoutMode == ReaderLayoutMode.paginated
                                  ? 'Page'
                                  : 'Scroll',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (supportsTypography)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: cfg.backgroundColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: cfg.textColor.withValues(alpha: 0.12),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      'A quiet moment. Just you and the next chapter.',
                      style: TextStyle(
                        fontFamily: prefs.fontFamily.fontFamily,
                        fontSize: (prefs.fontSize * 0.9).clamp(13, 20),
                        height: 1.3,
                        color: cfg.textColor,
                      ),
                    ),
                  ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Use system brightness',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: cfg.textColor,
                        ),
                      ),
                      Switch.adaptive(
                        value: prefs.isSystemBrightness,
                        onChanged: (useSystem) {
                          notifier.setBrightness(useSystem ? -1.0 : 0.85);
                        },
                      ),
                    ],
                  ),
                ),
                if (!prefs.isSystemBrightness)
                  // Apple Books style: a small sun, the slider, a large sun.
                  Semantics(
                    label: 'Brightness',
                    value: '${(prefs.brightness.clamp(0.1, 1.0) * 100).round()}%',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.sun_min,
                            size: 16,
                            color: cfg.secondaryTextColor,
                          ),
                          Expanded(
                            child: CupertinoSlider(
                              value: prefs.brightness.clamp(0.1, 1.0),
                              min: .1,
                              max: 1,
                              activeColor: cfg.textColor,
                              onChanged: notifier.setBrightness,
                            ),
                          ),
                          Icon(
                            CupertinoIcons.sun_max_fill,
                            size: 22,
                            color: cfg.secondaryTextColor,
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: ReaderThemeConfig.all.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisExtent: 62,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemBuilder: (_, index) {
                    final theme = ReaderThemeConfig.all[index];
                    final selected = prefs.themePreset == theme.preset;
                    return Semantics(
                      selected: selected,
                      button: true,
                      label: '${theme.name} theme',
                      child: Material(
                        color: theme.backgroundColor,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: selected
                                ? cfg.textColor
                                : cfg.textColor.withValues(alpha: .16),
                            width: selected ? 2 : 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: () => notifier.setPreset(theme.preset),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'Aa',
                                style: TextStyle(
                                  fontFamily: prefs.fontFamily.fontFamily,
                                  fontSize: 20,
                                  color: theme.textColor,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                theme.name,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: selected
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  color: theme.textColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (supportsTypography) ...[
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: () => _customize(context),
                    icon: const Icon(
                      CupertinoIcons.slider_horizontal_3,
                      size: 18,
                    ),
                    label: const Text('Customize Fonts & Spacing'),
                  ),
                ],
                if (bookId != null &&
                    DatabaseService.instance.getBookReaderSettings(bookId!) != null) ...[
                  const SizedBox(height: 10),
                  TextButton.icon(
                    onPressed: () async {
                      await notifier.resetToGlobalDefaults(targetBookId: bookId);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Reset book reader settings to defaults.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.restore, size: 16),
                    label: const Text('Reset to Defaults'),
                  ),
                ],
              ],
            ),
          ),
        ),
      );

    return Theme(
      data: themeData,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: rich
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: sheetContent,
              )
            : sheetContent,
      ),
    );
  }

  static Widget _header(
    BuildContext context,
    String title,
    ReaderThemeConfig cfg,
  ) => Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: cfg.textColor,
          ),
        ),
      ),
      IconButton(
        tooltip: 'Close settings',
        onPressed: () => Navigator.pop(context),
        icon: Icon(
          CupertinoIcons.xmark_circle_fill,
          color: cfg.secondaryTextColor,
          size: 25,
        ),
      ),
    ],
  );

  void _customize(BuildContext context) => showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: false,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final prefs = ref.watch(readerPreferencesProvider);
        final notifier = ref.read(readerPreferencesProvider.notifier);
        final cfg = prefs.themeConfig;
        final rich = GlassStyle.richOf(context);
        final baseTheme = cfg.systemBrightness == Brightness.dark
            ? HonTheme.darkTheme
            : HonTheme.lightTheme;
        final themeData = baseTheme.copyWith(
          extensions: Theme.of(context).extensions.values,
        );
        final bg = rich
            ? cfg.uiControlsBackground.withValues(alpha: 0.78)
            : cfg.uiControlsBackground;

        final customizeContent = Material(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .9,
                maxWidth: 640,
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  24,
                  16,
                  24,
                  MediaQuery.paddingOf(context).bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _header(context, 'Fonts & Spacing', cfg),
                    const SizedBox(height: 12),
                    Text(
                      'Font Family',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: cfg.textColor,
                      ),
                    ),
                    const SizedBox(height: 8),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: ReaderFontFamily.values.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisExtent: 52,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemBuilder: (context, index) {
                        final font = ReaderFontFamily.values[index];
                        final selected = prefs.fontFamily == font;
                        return Semantics(
                          button: true,
                          selected: selected,
                          label: '${font.displayName} font',
                          child: Material(
                            color: selected
                                ? cfg.textColor.withValues(alpha: 0.12)
                                : cfg.backgroundColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(
                                color: selected
                                    ? cfg.textColor
                                    : cfg.textColor.withValues(alpha: 0.16),
                                width: selected ? 2 : 1,
                              ),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: InkWell(
                              onTap: () {
                                notifier.setFontFamily(font);
                                SemanticsService.announce(
                                  'Font set to ${font.displayName}',
                                  TextDirection.ltr,
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        font.displayName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontFamily: font.fontFamily,
                                          fontSize: 14,
                                          fontWeight: selected
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                          color: cfg.textColor,
                                        ),
                                      ),
                                    ),
                                    if (selected)
                                      Icon(
                                        CupertinoIcons.checkmark_alt,
                                        size: 16,
                                        color: cfg.textColor,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 28),
                    _SettingSlider(
                      label: 'Line spacing',
                      value: prefs.lineHeight,
                      min: 1.3,
                      max: 2.2,
                      format: (v) => '${v.toStringAsFixed(2)}×',
                      onCommitted: notifier.setLineHeight,
                    ),
                    _SettingSlider(
                      label: 'Page margins',
                      value: prefs.horizontalMargin,
                      min: 8,
                      max: 48,
                      format: (v) => '${v.round()}',
                      onCommitted: notifier.setHorizontalMargin,
                    ),
                    _SettingSlider(
                      label: 'Paragraph spacing',
                      value: prefs.paragraphSpacing,
                      min: 0,
                      max: 32,
                      format: (v) => '${v.round()}',
                      onCommitted: notifier.setParagraphSpacing,
                    ),
                    _SettingSlider(
                      label: 'First-line indent',
                      value: prefs.textIndent,
                      min: 0,
                      max: 64,
                      format: (v) => '${v.round()}',
                      onCommitted: notifier.setTextIndent,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Justify text'),
                      value: prefs.isJustified,
                      onChanged: (_) => notifier.toggleJustified(),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use publisher typography'),
                      subtitle: const Text('Render with book-embedded CSS styling'),
                      value: prefs.publisherStyles,
                      onChanged: (enabled) async {
                        if (enabled) {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Publisher Typography'),
                              content: const Text(
                                'Enabling publisher typography renders the book with its original embedded styling and layout, overriding custom fonts and margins. Continue?'
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Enable'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            notifier.setPublisherStyles(true);
                            if (bookId != null) {
                              DatabaseService.instance.saveBookReaderSettings(
                                bookId!,
                                prefs.copyWith(publisherStyles: true).toMap(),
                              );
                            }
                          }
                        } else {
                          notifier.setPublisherStyles(false);
                          if (bookId != null) {
                            DatabaseService.instance.saveBookReaderSettings(
                              bookId!,
                              prefs.copyWith(publisherStyles: false).toMap(),
                            );
                          }
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          );

        return Theme(
          data: themeData,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: rich
                ? BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child: customizeContent,
                  )
                : customizeContent,
          ),
        );
      },
    ),
  );
}

/// Text layout changes commit at release, so a drag does not repaginate the book
/// on every pointer update.
class _SettingSlider extends StatefulWidget {
  final String label;
  final double value, min, max;
  final String Function(double) format;
  final ValueChanged<double> onCommitted;
  const _SettingSlider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.format,
    required this.onCommitted,
  });
  @override
  State<_SettingSlider> createState() => _SettingSliderState();
}

class _SettingSliderState extends State<_SettingSlider> {
  double? _drag;
  @override
  Widget build(BuildContext context) {
    final value = (_drag ?? widget.value).clamp(widget.min, widget.max);
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(widget.label)),
            Text(widget.format(value)),
          ],
        ),
        Slider(
          value: value,
          min: widget.min,
          max: widget.max,
          label: widget.format(value),
          semanticFormatterCallback: widget.format,
          onChanged: (next) {
            setState(() => _drag = next);
          },
          onChangeEnd: (next) {
            widget.onCommitted(next);
            setState(() => _drag = null);
          },
        ),
      ],
    );
  }
}
