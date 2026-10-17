import 'package:flutter/material.dart';

abstract final class StudioColors {
  static const ink = Color(0xFF29372F);
  static const green = Color(0xFF425B4A);
  static const muted = Color(0xFF858A82);
  static const border = Color(0xFFE6E9E1);
  static const wash = Color(0xFFF5F6F1);
  static const canvas = Color(0xFFEFF1EA);
  static const paleGreen = Color(0xFFEAF0E5);
}

ThemeData studioTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'DMSans',
  scaffoldBackgroundColor: Colors.white,
  colorScheme: ColorScheme.fromSeed(
    seedColor: StudioColors.green,
    primary: StudioColors.green,
    surface: Colors.white,
    onSurface: StudioColors.ink,
  ),
  textTheme: const TextTheme(
    bodyMedium: TextStyle(fontSize: 13, height: 1.5, color: StudioColors.ink),
    bodySmall: TextStyle(fontSize: 11, height: 1.45, color: StudioColors.muted),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: StudioColors.ink,
    ),
    titleSmall: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w600,
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
    fillColor: StudioColors.wash,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: StudioColors.border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: StudioColors.green, width: 1.3),
    ),
    hintStyle: const TextStyle(color: StudioColors.muted, fontSize: 12),
    counterStyle: const TextStyle(fontSize: 10),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: StudioColors.green,
      foregroundColor: Colors.white,
      textStyle: const TextStyle(
        fontFamily: 'DMSans',
        fontWeight: FontWeight.w500,
        fontSize: 12,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: StudioColors.ink,
      side: const BorderSide(color: StudioColors.border),
      textStyle: const TextStyle(
        fontFamily: 'DMSans',
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 17),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: StudioColors.green,
      textStyle: const TextStyle(
        fontFamily: 'DMSans',
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
  iconButtonTheme: IconButtonThemeData(
    style: IconButton.styleFrom(
      foregroundColor: StudioColors.ink,
      iconSize: 19,
    ),
  ),
  sliderTheme: const SliderThemeData(
    trackHeight: 3,
    thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    overlayShape: RoundSliderOverlayShape(overlayRadius: 15),
  ),
  dialogTheme: DialogThemeData(
    backgroundColor: Colors.white,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
  ),
  snackBarTheme: const SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: StudioColors.ink,
  ),
);
