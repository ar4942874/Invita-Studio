import 'package:flutter/material.dart';

import 'studio_theme.dart';

/// Design tokens adapted from the OpenDesign `elegant` design system, applied
/// to the home screen only — the studio editor stays on the `premium` package
/// (see `studio_theme.dart`).
///
/// Source package: open-design/design-systems/elegant (`tokens.css`). Token
/// names keep parity with the CSS custom properties, mirroring how
/// `studio_theme.dart` maps the `premium` package, so the home shell can be
/// re-skinned from another OpenDesign package by editing this one file.
abstract final class HomeColors {
  // Surfaces.
  static const canvas = Color(0xFFFBF6EE); // --bg
  static const surface = Color(0xFFFFFDF8); // --surface
  static const surfaceWarm = Color(0xFFF1E3CF); // --surface-warm
  static const wash = Color(0xFFEEE4D7); // subtle fill (--border-soft)

  // Lines.
  static const border = Color(0xFFDED2C3); // --border
  static const borderSoft = Color(0xFFEEE4D7); // --border-soft

  // Ink.
  static const ink = Color(0xFF201914); // --fg
  static const inkSoft = Color(0xFF4C4037); // --fg-2
  static const muted = Color(0xFF7A6D63); // --muted
  static const meta = Color(0xFF9B5B32); // --meta (eyebrows)

  // Signal.
  static const accent = Color(0xFF9B5B32); // --accent (cacao)
  static const accentOn = Color(0xFFFFFFFF); // --accent-on
  static const accentHover = Color(0xFF8E542E); // accent x black 8%
  static const accentActive = Color(0xFF854D2B); // accent x black 14%
  static const accentSoft = Color(0xFFF1E3CF); // selected tint (--surface-warm)

  // Status.
  static const success = Color(0xFF4F8A4F); // --success
  static const warning = Color(0xFFC9822F); // --warn
  static const warningSoft = Color(0xFFF7EFDF);
  static const warningBorder = Color(0xFFE6D5B4);
  static const warningInk = Color(0xFF8A5A21);
  static const danger = Color(0xFFB33A3A); // --danger
}

/// Radii from the Elegant token contract. Radii outside this class keep type
/// parity with the studio's [StudioShape].
abstract final class HomeShape {
  static const double sm = 10; // --radius-sm (inputs, inner clips)
  static const double md = 16; // --radius-md (buttons, tiles, cards)
  static const double lg = 24; // --radius-lg

  static const smRadius = BorderRadius.all(Radius.circular(sm));
  static const mdRadius = BorderRadius.all(Radius.circular(md));
  static const lgRadius = BorderRadius.all(Radius.circular(lg));
}

/// The Elegant page treatment: an ivory wash across the landing screen.
const homePageGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  stops: [0, .56, 1],
  colors: [HomeColors.canvas, HomeColors.surface, HomeColors.surfaceWarm],
);

/// [studioTheme] with the color, shape and control signals swapped to the
/// Elegant package so every Material widget the home screen hosts (buttons,
/// inputs, popups) follows the same package as the bespoke tiles.
ThemeData elegantHomeTheme() {
  final base = studioTheme();
  return base.copyWith(
    scaffoldBackgroundColor: HomeColors.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: HomeColors.accent,
      onPrimary: HomeColors.accentOn,
      primaryContainer: HomeColors.accentSoft,
      onPrimaryContainer: HomeColors.ink,
      surface: HomeColors.surface,
      onSurface: HomeColors.ink,
      error: HomeColors.danger,
    ),
    dividerColor: HomeColors.border,
    dividerTheme: base.dividerTheme.copyWith(color: HomeColors.border),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: HomeColors.surface,
      border: const OutlineInputBorder(
        borderRadius: HomeShape.smRadius,
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: HomeShape.smRadius,
        borderSide: BorderSide(color: HomeColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: HomeShape.smRadius,
        borderSide: BorderSide(color: HomeColors.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: HomeColors.accent,
        foregroundColor: HomeColors.accentOn,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const RoundedRectangleBorder(borderRadius: HomeShape.mdRadius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: HomeColors.ink,
        backgroundColor: HomeColors.surface,
        side: const BorderSide(color: HomeColors.border),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const RoundedRectangleBorder(borderRadius: HomeShape.mdRadius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: HomeColors.accent,
        shape: const RoundedRectangleBorder(borderRadius: HomeShape.mdRadius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: HomeColors.ink),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: HomeColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: HomeShape.lgRadius),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: HomeColors.ink,
      contentTextStyle: const TextStyle(color: HomeColors.accentOn),
    ),
  );
}
