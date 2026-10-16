import 'package:flutter/material.dart';

enum ReaderThemePreset {
  original,
  quiet,
  paper,
  bold,
  calm,
  focus,
}

enum ReaderLayoutMode {
  paginated,
  verticalScroll,
}

enum ReaderFontFamily {
  georgia('Georgia', 'Georgia, serif'),
  newYork('New York', 'New York, serif'),
  sanFrancisco('San Francisco', 'sans-serif'),
  palatino('Palatino', 'Palatino, serif'),
  baskerville('Baskerville', 'Baskerville, serif');

  final String displayName;
  final String cssFontFamily;
  const ReaderFontFamily(this.displayName, this.cssFontFamily);
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
    secondaryTextColor: Color(0xFF8E8E93),
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
    secondaryTextColor: Color(0xFF8E8E93),
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
    secondaryTextColor: Color(0xFF8E8E93),
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
    secondaryTextColor: Color(0xFF8E8E93),
    ornamentColor: Color(0xFF48484A),
    uiControlsBackground: Color(0xF51C1C1E),
    uiControlsForeground: Color(0xFFFFFFFF),
    systemBrightness: Brightness.dark,
  );

  static const ReaderThemeConfig calm = ReaderThemeConfig(
    preset: ReaderThemePreset.calm,
    name: 'Calm',
    backgroundColor: Color(0xFFF7EED9),
    textColor: Color(0xFF382E24),
    secondaryTextColor: Color(0xFF8A7A6A),
    ornamentColor: Color(0xFFB5A695),
    uiControlsBackground: Color(0xF5EFE3CA),
    uiControlsForeground: Color(0xFF382E24),
    systemBrightness: Brightness.light,
  );

  static const ReaderThemeConfig focus = ReaderThemeConfig(
    preset: ReaderThemePreset.focus,
    name: 'Focus',
    backgroundColor: Color(0xFFFFFDF5),
    textColor: Color(0xFF262624),
    secondaryTextColor: Color(0xFF9E988A),
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
    this.brightness = 0.85,
  });

  ReaderThemeConfig get themeConfig => ReaderThemeConfig.fromPreset(themePreset);

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
    );
  }
}
