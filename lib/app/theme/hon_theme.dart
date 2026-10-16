import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'hon_colors.dart';

class HonTheme {
  HonTheme._();

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: HonColors.lightBackground,
      colorScheme: const ColorScheme.light(
        primary: HonColors.lightTextPrimary,
        secondary: HonColors.accentOrange,
        surface: HonColors.lightSurface,
        surfaceContainerHighest: HonColors.lightSurfaceElevated,
        onSurface: HonColors.lightTextPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        iconTheme: IconThemeData(color: HonColors.lightTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: HonColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HonColors.lightCardBorder, width: 0.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: HonColors.lightSeparator,
        thickness: 0.5,
        space: 1,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HonColors.darkBackground,
      colorScheme: const ColorScheme.dark(
        primary: HonColors.darkTextPrimary,
        secondary: HonColors.accentOrange,
        surface: HonColors.darkSurface,
        surfaceContainerHighest: HonColors.darkSurfaceElevated,
        onSurface: HonColors.darkTextPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        iconTheme: IconThemeData(color: HonColors.darkTextPrimary),
      ),
      cardTheme: CardThemeData(
        color: HonColors.darkSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HonColors.darkCardBorder, width: 0.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: HonColors.darkSeparator,
        thickness: 0.5,
        space: 1,
      ),
    );
  }
}
