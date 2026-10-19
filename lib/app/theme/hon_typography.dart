import 'package:flutter/material.dart';

class HonTypography {
  HonTypography._();

  // Large screen titles (e.g. "Home", "Library", "Browse")
  static TextStyle largeTitle({Color? color}) {
    return TextStyle(
      fontFamily: 'Newsreader',
      fontSize: 34,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
      color: color,
    );
  }

  // Section titles (e.g. "Continue", "Top Picks", "Want to Read")
  static TextStyle sectionHeader({Color? color}) {
    return TextStyle(
      fontFamily: 'Newsreader',
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: color,
    );
  }

  // Book reader chapter titles (e.g. "Chapter 40")
  static TextStyle chapterTitle({Color? color}) {
    return TextStyle(
      fontFamily: 'Newsreader',
      fontSize: 26,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: color,
    );
  }

  // Card titles (e.g. "Good Material")
  static TextStyle cardTitle({Color? color}) {
    return TextStyle(
      fontSize: 17,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: color,
    );
  }

  // Author / subtitle (e.g. "Dolly Alderton")
  static TextStyle cardSubtitle({Color? color}) {
    return TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.1,
      color: color,
    );
  }

  // Meta label (e.g. "Book • 6%")
  static TextStyle cardMeta({Color? color}) {
    return TextStyle(fontSize: 12, fontWeight: FontWeight.w400, color: color);
  }

  // Standard body text
  static TextStyle body({Color? color}) {
    return TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.2,
      color: color,
    );
  }

  // Reader body text (Jane Austen paragraph style)
  static TextStyle readerBody({
    Color? color,
    double fontSize = 18.0,
    double lineHeight = 1.65,
    String? fontFamily,
  }) {
    return TextStyle(
      fontFamily: fontFamily ?? 'Newsreader',
      fontSize: fontSize,
      height: lineHeight,
      fontWeight: FontWeight.w400,
      color: color,
    );
  }

  // Tab bar labels
  static TextStyle tabLabel({Color? color}) {
    return TextStyle(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: -0.1,
      color: color,
    );
  }
}
