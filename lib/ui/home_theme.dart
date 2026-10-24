import 'package:flutter/material.dart';

import 'occasion_theme.dart';
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

/// The Elegant page treatment with the neutral tokens — an ivory wash across
/// the landing screen before a category is picked. Once one is, the wash comes
/// from `OccasionTheme.pageGradient` instead.
const homePageGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  stops: [0, .56, 1],
  colors: [HomeColors.canvas, HomeColors.surface, HomeColors.surfaceWarm],
);

/// [studioTheme] with the shape and control signals swapped to the Elegant
/// package so every Material widget the home screen hosts (buttons, inputs,
/// popups) follows the same package as the bespoke tiles.
///
/// Pass [occasion] and the colours come from that celebration instead of the
/// neutral [HomeColors]; the shapes stay here either way. The palette is passed
/// straight through to [studioTheme] so the two screens never disagree about,
/// say, what "accent" means.
ThemeData elegantHomeTheme({OccasionTheme? occasion}) {
  final base = studioTheme(occasion: occasion);

  final canvas = occasion?.canvas ?? HomeColors.canvas;
  final surface = occasion?.surface ?? HomeColors.surface;
  final border = occasion?.border ?? HomeColors.border;
  final ink = occasion?.ink ?? HomeColors.ink;
  final accent = occasion?.accent ?? HomeColors.accent;
  final accentOn = occasion?.accentOn ?? HomeColors.accentOn;
  final accentSoft = occasion?.accentSoft ?? HomeColors.accentSoft;
  final danger = StudioColors.danger;

  return base.copyWith(
    scaffoldBackgroundColor: canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: accent,
      onPrimary: accentOn,
      primaryContainer: accentSoft,
      onPrimaryContainer: ink,
      surface: surface,
      onSurface: ink,
      error: danger,
    ),
    dividerColor: border,
    dividerTheme: base.dividerTheme.copyWith(color: border),
    inputDecorationTheme: base.inputDecorationTheme.copyWith(
      fillColor: surface,
      enabledBorder: OutlineInputBorder(
        borderRadius: HomeShape.smRadius,
        borderSide: BorderSide(color: border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: HomeShape.smRadius,
        borderSide: BorderSide(color: accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: accentOn,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: const RoundedRectangleBorder(borderRadius: HomeShape.mdRadius),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: ink,
        backgroundColor: surface,
        side: BorderSide(color: border),
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        shape: const RoundedRectangleBorder(borderRadius: HomeShape.mdRadius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
        shape: const RoundedRectangleBorder(borderRadius: HomeShape.mdRadius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: ink),
    ),
    dialogTheme: base.dialogTheme.copyWith(
      backgroundColor: surface,
      shape: const RoundedRectangleBorder(borderRadius: HomeShape.lgRadius),
    ),
    snackBarTheme: base.snackBarTheme.copyWith(
      backgroundColor: ink,
      contentTextStyle: TextStyle(color: accentOn),
    ),
  );
}
