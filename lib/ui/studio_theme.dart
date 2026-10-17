import 'package:flutter/material.dart';

/// Design tokens adapted from the OpenDesign `premium` design system:
/// a warm-white canvas, graphite type, and a muted bronze signal.
///
/// Source package: open-design/design-systems/premium
/// (`tokens.css`, `DESIGN.md`, `components.html`). Token names keep parity with
/// the CSS custom properties so the app can be re-skinned from another
/// OpenDesign package later.
abstract final class StudioColors {
  // Surfaces.
  static const canvas = Color(0xFFFAF8F4); // --bg
  static const surface = Color(0xFFFFFFFF); // --surface
  static const surfaceWarm = Color(0xFFF0E7D8); // --surface-warm
  static const wash = Color(0xFFEEE7DC); // subtle fill (--border-soft)

  // Lines.
  static const border = Color(0xFFDED6C9); // --border
  static const borderSoft = Color(0xFFEEE7DC); // --border-soft

  // Ink.
  static const ink = Color(0xFF1C1B19); // --fg
  static const inkSoft = Color(0xFF4B4740); // --fg-2
  static const muted = Color(0xFF746D63); // --muted
  static const meta = Color(0xFFA06A3B); // --meta (eyebrows)

  // Signal.
  static const accent = Color(0xFFA06A3B); // --accent (bronze)
  static const accentOn = Color(0xFFFFFFFF); // --accent-on
  static const accentHover = Color(0xFF936236); // accent x black 8%
  static const accentActive = Color(0xFF8A5B33); // accent x black 14%
  static const accentSoft = Color(0xFFF0E7D8); // selected tint (--surface-warm)

  // Status.
  static const success = Color(0xFF3F8F5F); // --success
  static const warning = Color(0xFFC4872C); // --warn
  static const warningSoft = Color(0xFFF7EBD8);
  static const warningBorder = Color(0xFFE6D3B4);
  static const warningInk = Color(0xFF8A5B1E);
  static const danger = Color(0xFFB84A4A); // --danger
}

/// Corner radii from the Premium token contract.
abstract final class StudioShape {
  static const double sm = 10; // inputs, chips
  static const double md = 16; // buttons, cards, tiles
  static const double lg = 28; // panels, dialogs

  static const smRadius = BorderRadius.all(Radius.circular(sm));
  static const mdRadius = BorderRadius.all(Radius.circular(md));
  static const lgRadius = BorderRadius.all(Radius.circular(lg));
}

/// Motion from the Premium token contract.
abstract final class StudioMotion {
  static const fast = Duration(milliseconds: 170); // --motion-fast
  static const base = Duration(milliseconds: 280); // --motion-base
  static const standard = Cubic(0.22, 1, 0.36, 1); // --ease-standard
}

/// Elevation from the Premium token contract.
abstract final class StudioShadows {
  /// `--elev-raised`: 0 24px 64px rgba(28, 27, 25, 0.12).
  static const raised = [
    BoxShadow(color: Color(0x1F1C1B19), blurRadius: 64, offset: Offset(0, 24)),
  ];

  /// `--focus-ring`: 0 0 0 4px rgba(160, 106, 59, 0.24).
  static final focus = [
    BoxShadow(
      color: StudioColors.accent.withValues(alpha: .24),
      spreadRadius: 4,
    ),
  ];
}

/// Type from the Premium token contract. The package names Canela (display)
/// and Inter (body); we stand in the bundled OFL families that share the same
/// role, so the app stays offline and portable.
abstract final class StudioType {
  static const display = 'CormorantGaramond'; // stand-in for Canela
  static const body = 'DMSans'; // stand-in for Inter

  static const double xs = 12;
  static const double sm = 14;
  static const double base = 16;
  static const double lg = 19;
  static const double xl = 26;
  static const double x2 = 40;
  static const double x3 = 60;
  static const double x4 = 84;
  static const double leadingBody = 1.58;
  static const double leadingTight = 1.02;
  static const double trackingDisplay = -0.02;
}

/// The Premium page treatment: a warm diagonal wash of canvas → surface → warm.
const studioPageGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  stops: [0, .56, 1],
  colors: [
    StudioColors.canvas,
    StudioColors.surface,
    StudioColors.surfaceWarm,
  ],
);

ThemeData studioTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: StudioType.body,
  scaffoldBackgroundColor: StudioColors.canvas,
  colorScheme: ColorScheme.fromSeed(
    seedColor: StudioColors.accent,
    primary: StudioColors.accent,
    onPrimary: StudioColors.accentOn,
    surface: StudioColors.surface,
    onSurface: StudioColors.ink,
    error: StudioColors.danger,
  ),
  textTheme: const TextTheme(
    displayLarge: TextStyle(
      fontFamily: StudioType.display,
      fontSize: StudioType.x4,
      height: StudioType.leadingTight,
      letterSpacing: StudioType.trackingDisplay,
      fontWeight: FontWeight.w600,
      color: StudioColors.ink,
    ),
    displayMedium: TextStyle(
      fontFamily: StudioType.display,
      fontSize: StudioType.x3,
      height: StudioType.leadingTight,
      letterSpacing: StudioType.trackingDisplay,
      fontWeight: FontWeight.w600,
      color: StudioColors.ink,
    ),
    displaySmall: TextStyle(
      fontFamily: StudioType.display,
      fontSize: StudioType.x2,
      height: StudioType.leadingTight,
      letterSpacing: StudioType.trackingDisplay,
      fontWeight: FontWeight.w600,
      color: StudioColors.ink,
    ),
    headlineMedium: TextStyle(
      fontFamily: StudioType.display,
      fontSize: StudioType.xl,
      height: StudioType.leadingTight,
      letterSpacing: StudioType.trackingDisplay,
      fontWeight: FontWeight.w600,
      color: StudioColors.ink,
    ),
    titleLarge: TextStyle(
      fontFamily: StudioType.display,
      fontSize: StudioType.lg,
      height: 1.1,
      letterSpacing: StudioType.trackingDisplay,
      fontWeight: FontWeight.w600,
      color: StudioColors.ink,
    ),
    titleMedium: TextStyle(
      fontFamily: StudioType.display,
      fontSize: 18,
      height: 1.12,
      letterSpacing: StudioType.trackingDisplay,
      fontWeight: FontWeight.w600,
      color: StudioColors.ink,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: StudioColors.ink,
    ),
    bodyLarge: TextStyle(
      fontSize: StudioType.base,
      height: StudioType.leadingBody,
      color: StudioColors.ink,
    ),
    bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: StudioColors.ink),
    bodySmall: TextStyle(fontSize: 11, height: 1.45, color: StudioColors.muted),
    labelLarge: TextStyle(
      fontSize: StudioType.sm,
      fontWeight: FontWeight.w700,
      color: StudioColors.ink,
    ),
  ),
  dividerColor: StudioColors.border,
  dividerTheme: const DividerThemeData(
    color: StudioColors.border,
    thickness: 1,
    space: 1,
  ),
  tooltipTheme: const TooltipThemeData(
    waitDuration: Duration(milliseconds: 450),
  ),
  inputDecorationTheme: InputDecorationThemeData(
    filled: true,
    fillColor: StudioColors.surface,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
    border: const OutlineInputBorder(
      borderRadius: StudioShape.smRadius,
      borderSide: BorderSide.none,
    ),
    enabledBorder: const OutlineInputBorder(
      borderRadius: StudioShape.smRadius,
      borderSide: BorderSide(color: StudioColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: StudioShape.smRadius,
      borderSide: const BorderSide(color: StudioColors.accent, width: 1.4),
    ),
    hintStyle: const TextStyle(color: StudioColors.muted, fontSize: 12),
    counterStyle: const TextStyle(fontSize: 10),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: StudioColors.accent,
      foregroundColor: StudioColors.accentOn,
      textStyle: const TextStyle(
        fontFamily: StudioType.body,
        fontWeight: FontWeight.w700,
        fontSize: StudioType.sm,
      ),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      shape: const RoundedRectangleBorder(borderRadius: StudioShape.mdRadius),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: StudioColors.ink,
      backgroundColor: StudioColors.surface,
      side: const BorderSide(color: StudioColors.border),
      textStyle: const TextStyle(
        fontFamily: StudioType.body,
        fontSize: StudioType.sm,
        fontWeight: FontWeight.w700,
      ),
      minimumSize: const Size(0, 44),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      shape: const RoundedRectangleBorder(borderRadius: StudioShape.mdRadius),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: StudioColors.accent,
      textStyle: const TextStyle(
        fontFamily: StudioType.body,
        fontSize: StudioType.sm,
        fontWeight: FontWeight.w700,
      ),
      shape: const RoundedRectangleBorder(borderRadius: StudioShape.mdRadius),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: StudioColors.ink,
      iconSize: 19,
    ),
  ),
  sliderTheme: SliderThemeData(
    activeTrackColor: StudioColors.accent,
    thumbColor: StudioColors.accent,
    inactiveTrackColor: StudioColors.borderSoft,
    overlayColor: StudioColors.accent.withValues(alpha: .12),
    trackHeight: 3,
    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayShape: const RoundSliderOverlayShape(overlayRadius: 15),
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: StudioColors.surface,
    shape: RoundedRectangleBorder(borderRadius: StudioShape.lgRadius),
  ),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: StudioColors.ink,
    contentTextStyle: TextStyle(color: StudioColors.accentOn),
  ),
);
