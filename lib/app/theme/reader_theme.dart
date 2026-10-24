import 'dart:convert';
import 'package:flutter/material.dart';
import '../../core/utils/log_ignored.dart';

enum ReaderThemePreset { original, quiet, paper, bold, calm, focus }

enum ReaderLayoutMode { paginated, verticalScroll }

// Persisted enum IDs remain stable for existing preferences. Labels name the
// actual bundled open-source typefaces, rather than unavailable Apple fonts.
enum ReaderFontFamily {
  georgia('Newsreader', 'Newsreader'),
  newYork('Literata', 'Literata'),
  sanFrancisco('System Sans', 'sans-serif'),
  palatino('Lora', 'Lora'),
  baskerville('Libre Baskerville', 'Libre Baskerville');

  final String displayName;
  final String fontFamily;
  const ReaderFontFamily(this.displayName, this.fontFamily);
  String get cssFontFamily =>
      '"$fontFamily", ${this == sanFrancisco ? 'sans-serif' : 'serif'}';
}

class ReaderThemeConfig {
  final ReaderThemePreset preset;
  final String name;
  final Color backgroundColor;
  final Color textColor;
  final Color secondaryTextColor;
  final Color ornamentColor;
  final Color uiControlsBackground;
  final Color uiControlsForeground;
  final Brightness systemBrightness;

  const ReaderThemeConfig({
    required this.preset,
    required this.name,
    required this.backgroundColor,
    required this.textColor,
    required this.secondaryTextColor,
    required this.ornamentColor,
    required this.uiControlsBackground,
    required this.uiControlsForeground,
    required this.systemBrightness,
  });

  static const ReaderThemeConfig original = ReaderThemeConfig(
    preset: ReaderThemePreset.original,
    name: 'Original',
    backgroundColor: Color(0xFFFFFFFF),
    textColor: Color(0xFF1A1A1A),
    secondaryTextColor: Color(0xFF68686F),
    ornamentColor: Color(0xFF8E8E93),
    uiControlsBackground: Color(0xF5F2F2F7),
    uiControlsForeground: Color(0xFF000000),
    systemBrightness: Brightness.light,
  );

  static const ReaderThemeConfig quiet = ReaderThemeConfig(
    preset: ReaderThemePreset.quiet,
    name: 'Quiet',
    backgroundColor: Color(0xFF2C2C2E),
    textColor: Color(0xFFE5E5EA),
    secondaryTextColor: Color(0xFFB0B0B6),
    ornamentColor: Color(0xFF636366),
    uiControlsBackground: Color(0xF51C1C1E),
    uiControlsForeground: Color(0xFFFFFFFF),
    systemBrightness: Brightness.dark,
  );

  static const ReaderThemeConfig paper = ReaderThemeConfig(
    preset: ReaderThemePreset.paper,
    name: 'Paper',
    backgroundColor: Color(0xFFF2F2F7),
    textColor: Color(0xFF1C1C1E),
    secondaryTextColor: Color(0xFF68686F),
    ornamentColor: Color(0xFF8E8E93),
    uiControlsBackground: Color(0xF5FFFFFF),
    uiControlsForeground: Color(0xFF000000),
    systemBrightness: Brightness.light,
  );

  static const ReaderThemeConfig bold = ReaderThemeConfig(
    preset: ReaderThemePreset.bold,
    name: 'Bold',
    backgroundColor: Color(0xFF000000),
    textColor: Color(0xFFFFFFFF),
    secondaryTextColor: Color(0xFFB0B0B6),
    ornamentColor: Color(0xFF48484A),
    uiControlsBackground: Color(0xF51C1C1E),
    uiControlsForeground: Color(0xFFFFFFFF),
    systemBrightness: Brightness.dark,
  );

  static const ReaderThemeConfig calm = ReaderThemeConfig(
    preset: ReaderThemePreset.calm,
    name: 'Calm',
    backgroundColor: Color(0xFFF1E5CD),
    textColor: Color(0xFF2C2211),
    secondaryTextColor: Color(0xFF70624E),
    ornamentColor: Color(0xFFA89782),
    uiControlsBackground: Color(0xF5E8DCBF),
    uiControlsForeground: Color(0xFF2C2211),
    systemBrightness: Brightness.light,
  );

  static const ReaderThemeConfig focus = ReaderThemeConfig(
    preset: ReaderThemePreset.focus,
    name: 'Focus',
    backgroundColor: Color(0xFFFFFDF5),
    textColor: Color(0xFF262624),
    secondaryTextColor: Color(0xFF736E62),
    ornamentColor: Color(0xFFC7C1B2),
    uiControlsBackground: Color(0xF5F6F3E6),
    uiControlsForeground: Color(0xFF262624),
    systemBrightness: Brightness.light,
  );

  static ReaderThemeConfig fromPreset(ReaderThemePreset preset) {
    switch (preset) {
      case ReaderThemePreset.original:
        return original;
      case ReaderThemePreset.quiet:
        return quiet;
      case ReaderThemePreset.paper:
        return paper;
      case ReaderThemePreset.bold:
        return bold;
      case ReaderThemePreset.calm:
        return calm;
      case ReaderThemePreset.focus:
        return focus;
    }
  }

  static const List<ReaderThemeConfig> all = [
    original,
    quiet,
    paper,
    bold,
    calm,
    focus,
  ];
}

/// User's reading layout preferences
class ReaderPreferencesState {
  final ReaderThemePreset themePreset;
  final ReaderLayoutMode layoutMode;
  final ReaderFontFamily fontFamily;
  final double fontSize;
  final double lineHeight;
  final double horizontalMargin;
  final double paragraphSpacing;
  final double textIndent;
  final bool isJustified;
  final double brightness;
  final bool publisherStyles;

  const ReaderPreferencesState({
    this.themePreset = ReaderThemePreset.calm,
    this.layoutMode = ReaderLayoutMode.paginated,
    this.fontFamily = ReaderFontFamily.georgia,
    this.fontSize = 18.0,
    this.lineHeight = 1.65,
    this.horizontalMargin = 24.0,
    this.paragraphSpacing = 8.0,
    this.textIndent = 24.0,
    this.isJustified = true,
    this.brightness = -1.0,
    this.publisherStyles = false,
  });

  ReaderThemeConfig get themeConfig =>
      ReaderThemeConfig.fromPreset(themePreset);

  bool get isSystemBrightness => brightness < 0;

  ReaderPreferencesState copyWith({
    ReaderThemePreset? themePreset,
    ReaderLayoutMode? layoutMode,
    ReaderFontFamily? fontFamily,
    double? fontSize,
    double? lineHeight,
    double? horizontalMargin,
    double? paragraphSpacing,
    double? textIndent,
    bool? isJustified,
    double? brightness,
    bool? publisherStyles,
  }) {
    return ReaderPreferencesState(
      themePreset: themePreset ?? this.themePreset,
      layoutMode: layoutMode ?? this.layoutMode,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      horizontalMargin: horizontalMargin ?? this.horizontalMargin,
      paragraphSpacing: paragraphSpacing ?? this.paragraphSpacing,
      textIndent: textIndent ?? this.textIndent,
      isJustified: isJustified ?? this.isJustified,
      brightness: brightness ?? this.brightness,
      publisherStyles: publisherStyles ?? this.publisherStyles,
    );
  }

  Map<String, dynamic> toMap() => {
        'theme': themePreset.name,
        'layout': layoutMode.name,
        'font': fontFamily.name,
        'size': fontSize,
        'lineHeight': lineHeight,
        'margin': horizontalMargin,
        'paragraphSpacing': paragraphSpacing,
        'indent': textIndent,
        'justified': isJustified,
        'brightness': brightness,
        'publisherStyles': publisherStyles,
      };

  factory ReaderPreferencesState.fromMap(Map<String, dynamic> rawMap) {
    final map = Map<String, dynamic>.from(rawMap);
    // Unpack nested typography if stored in native representation
    if (map['typography'] != null) {
      if (map['typography'] is String) {
        try {
          final decoded = jsonDecode(map['typography'] as String);
          if (decoded is Map) {
            map.addAll(Map<String, dynamic>.from(decoded));
          }
        } catch (e) {
          logIgnored(e, 'reader_theme');
        }
      } else if (map['typography'] is Map) {
        map.addAll(Map<String, dynamic>.from(map['typography'] as Map));
      }
    }

    final themeStr = map['theme'] as String?;
    final layoutStr = map['layout'] as String?;
    final isScroll = map['isScroll'] as bool?;

    // Determine layout mode
    ReaderLayoutMode resolvedLayout = ReaderLayoutMode.paginated;
    if (layoutStr != null) {
      resolvedLayout = ReaderLayoutMode.values.firstWhere(
        (m) => m.name == layoutStr,
        orElse: () => ReaderLayoutMode.paginated,
      );
    } else if (isScroll != null) {
      resolvedLayout =
          isScroll ? ReaderLayoutMode.verticalScroll : ReaderLayoutMode.paginated;
    }

    // Determine font size
    double resolvedFontSize = 18.0;
    if (map['size'] is num) {
      resolvedFontSize = (map['size'] as num).toDouble();
    } else if (map['fontSize'] is num) {
      resolvedFontSize = (map['fontSize'] as num).toDouble() * 18.0;
    }

    return ReaderPreferencesState(
      themePreset: ReaderThemePreset.values.firstWhere(
        (p) => p.name == themeStr,
        orElse: () => ReaderThemePreset.calm,
      ),
      layoutMode: resolvedLayout,
      fontFamily: ReaderFontFamily.values.firstWhere(
        (f) => f.name == map['font'],
        orElse: () => ReaderFontFamily.georgia,
      ),
      fontSize: resolvedFontSize.clamp(12.0, 32.0),
      lineHeight:
          ((map['lineHeight'] as num?)?.toDouble() ?? 1.65).clamp(1.3, 2.2),
      horizontalMargin:
          ((map['margin'] as num?)?.toDouble() ?? 24.0).clamp(8.0, 64.0),
      paragraphSpacing:
          ((map['paragraphSpacing'] as num?)?.toDouble() ?? 8.0).clamp(0.0, 32.0),
      textIndent:
          ((map['indent'] as num?)?.toDouble() ?? 24.0).clamp(0.0, 64.0),
      isJustified: (map['justified'] as bool?) ?? true,
      brightness: () {
        final b = (map['brightness'] as num?)?.toDouble() ?? -1.0;
        return b < 0 ? -1.0 : b.clamp(0.1, 1.0);
      }(),
      publisherStyles: (map['publisherStyles'] as bool?) ?? false,
    );
  }
}
