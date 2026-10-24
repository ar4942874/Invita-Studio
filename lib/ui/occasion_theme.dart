import 'package:flutter/material.dart';

import '../domain/invitation_template.dart' show InvitationCategory;

/// The app's own look for one celebration.
///
/// The artwork has always been per-category — ten motifs drawn in six palettes.
/// The chrome never was: every celebration sat in the same warm-white and
/// bronze studio. This is that missing layer: one palette per occasion, used by
/// the landing wizard, the studio header, every Material control and the guide
/// spotlight, so choosing "Wedding" changes the room you are standing in.
///
/// Contrast is not a matter of taste here: `OccasionTheme` exposes only pairings
/// that clear 4.5:1, and `test/occasion_theme_test.dart` recomputes it.
@immutable
class OccasionTheme {
  const OccasionTheme({
    required this.category,
    required this.mood,
    required this.story,
    required this.canvas,
    required this.surface,
    required this.surfaceWarm,
    required this.wash,
    required this.border,
    required this.borderSoft,
    required this.ink,
    required this.inkSoft,
    required this.muted,
    required this.meta,
    required this.accent,
    required this.accentOn,
    required this.accentSoft,
  });

  final InvitationCategory category;

  /// One word for the mood, shown next to the category.
  final String mood;

  /// One sentence describing the room this celebration opens in.
  final String story;

  // Surfaces.
  final Color canvas;
  final Color surface;
  final Color surfaceWarm;
  final Color wash;

  // Lines.
  final Color border;
  final Color borderSoft;

  // Ink.
  final Color ink;
  final Color inkSoft;
  final Color muted;
  final Color meta;

  // Signal.
  final Color accent;
  final Color accentOn;
  final Color accentSoft;

  /// The light the guide throws on the control it is pointing at.
  Color get glow => accent;

  /// The landing screen's wash: canvas → surface → warm tint, the same stops
  /// the neutral theme used, so layout and contrast do not move.
  LinearGradient get pageGradient => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    stops: const [0, .56, 1],
    colors: [canvas, surface, surfaceWarm],
  );

  /// A shadow tinted by the occasion rather than neutral black, so cards sit in
  /// the same light as the rest of the screen.
  List<BoxShadow> get raisedShadow => [
    BoxShadow(
      color: ink.withValues(alpha: .10),
      blurRadius: 32,
      offset: const Offset(0, 16),
    ),
  ];

  static const Map<InvitationCategory, OccasionTheme> _byCategory = {
    // "Pleasant": sage and cream, like a garden marquee in daylight.
    InvitationCategory.wedding: OccasionTheme(
      category: InvitationCategory.wedding,
      mood: 'Pleasant',
      story: 'Sage, cream and quiet light — a garden in the afternoon.',
      canvas: Color(0xFFFBF7F1),
      surface: Color(0xFFFFFFFF),
      surfaceWarm: Color(0xFFEAF0E4),
      wash: Color(0xFFF3ECE1),
      border: Color(0xFFE2D8C7),
      borderSoft: Color(0xFFEFE7DA),
      ink: Color(0xFF24352B),
      inkSoft: Color(0xFF3E5346),
      muted: Color(0xFF5D6B5C),
      meta: Color(0xFF8A6B45),
      accent: Color(0xFF587452),
      accentOn: Color(0xFFFFFFFF),
      accentSoft: Color(0xFFE9F0E4),
    ),
    // Rose and ink: warm, close, a little flushed.
    InvitationCategory.engagement: OccasionTheme(
      category: InvitationCategory.engagement,
      mood: 'Romantic',
      story: 'Blush and deep rose, with just enough warmth to feel personal.',
      canvas: Color(0xFFFDF6F5),
      surface: Color(0xFFFFFFFF),
      surfaceWarm: Color(0xFFF7E4E7),
      wash: Color(0xFFF7EAEC),
      border: Color(0xFFEBD8DB),
      borderSoft: Color(0xFFF4E6E8),
      ink: Color(0xFF3B2530),
      inkSoft: Color(0xFF5A3B48),
      muted: Color(0xFF6E5862),
      meta: Color(0xFFA9526A),
      accent: Color(0xFFA9526A),
      accentOn: Color(0xFFFFFFFF),
      accentSoft: Color(0xFFF8E4E8),
    ),
    // Bright, saturated, a little loud — the way a party should be.
    InvitationCategory.birthday: OccasionTheme(
      category: InvitationCategory.birthday,
      mood: 'Playful',
      story: 'Warm paper with a coral signal and ink-blue type.',
      canvas: Color(0xFFFFF9EF),
      surface: Color(0xFFFFFFFF),
      surfaceWarm: Color(0xFFFBE3D6),
      wash: Color(0xFFF9EEDD),
      border: Color(0xFFEBDCC6),
      borderSoft: Color(0xFFF6EADA),
      ink: Color(0xFF26314D),
      inkSoft: Color(0xFF3C4866),
      muted: Color(0xFF55617C),
      meta: Color(0xFFB8481F),
      accent: Color(0xFFB8481F),
      accentOn: Color(0xFFFFFFFF),
      accentSoft: Color(0xFFFBE5D9),
    ),
    // Gold on parchment: the years deserve a little gilt.
    InvitationCategory.anniversary: OccasionTheme(
      category: InvitationCategory.anniversary,
      mood: 'Golden',
      story: 'Parchment, forest ink and a thin gold rule.',
      canvas: Color(0xFFF6F1E4),
      surface: Color(0xFFFFFFFF),
      surfaceWarm: Color(0xFFEFE4C9),
      wash: Color(0xFFF1EADA),
      border: Color(0xFFE2D7C0),
      borderSoft: Color(0xFFEFE7D5),
      ink: Color(0xFF1F2E28),
      inkSoft: Color(0xFF37463F),
      muted: Color(0xFF5A665B),
      meta: Color(0xFF7E611E),
      accent: Color(0xFF7E611E),
      accentOn: Color(0xFFFFFFFF),
      accentSoft: Color(0xFFEFE6CE),
    ),
    // Pale sky: soft, clean, unhurried.
    InvitationCategory.babyShower: OccasionTheme(
      category: InvitationCategory.babyShower,
      mood: 'Gentle',
      story: 'Pale sky and a soft blue signal, with room to breathe.',
      canvas: Color(0xFFF3F8FC),
      surface: Color(0xFFFFFFFF),
      surfaceWarm: Color(0xFFE1EEF6),
      wash: Color(0xFFEAF3F9),
      border: Color(0xFFD5E4EE),
      borderSoft: Color(0xFFE7F0F7),
      ink: Color(0xFF24384B),
      inkSoft: Color(0xFF3A4F62),
      muted: Color(0xFF4F6B7D),
      meta: Color(0xFF2F647D),
      accent: Color(0xFF2F647D),
      accentOn: Color(0xFFFFFFFF),
      accentSoft: Color(0xFFE1EEF6),
    ),
    // Terracotta: the default warm room, for anything without a category.
    InvitationCategory.other: OccasionTheme(
      category: InvitationCategory.other,
      mood: 'Warm',
      story: 'Terracotta and linen — an open brief, warmly framed.',
      canvas: Color(0xFFFBF4EC),
      surface: Color(0xFFFFFFFF),
      surfaceWarm: Color(0xFFF6E3D5),
      wash: Color(0xFFF6EADD),
      border: Color(0xFFE9D8C6),
      borderSoft: Color(0xFFF3E8DB),
      ink: Color(0xFF3E2A1F),
      inkSoft: Color(0xFF55402F),
      muted: Color(0xFF715C4E),
      meta: Color(0xFFA0522A),
      accent: Color(0xFFA0522A),
      accentOn: Color(0xFFFFFFFF),
      accentSoft: Color(0xFFF6E3D5),
    ),
  };

  /// The palette for [category]. Every category has one; there is no "no theme"
  /// branch to forget.
  static OccasionTheme forCategory(InvitationCategory category) =>
      _byCategory[category]!;

  static List<OccasionTheme> get all => _byCategory.values.toList();
}

/// Publishes the active occasion theme down the tree.
///
/// Screens read it with [OccasionScope.maybeOf] so a widget can still be pumped
/// in isolation (tests, storybook-style previews) without one.
class OccasionScope extends InheritedWidget {
  const OccasionScope({
    super.key,
    required this.theme,
    required super.child,
  });

  final OccasionTheme theme;

  static OccasionTheme? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OccasionScope>()?.theme;

  @override
  bool updateShouldNotify(OccasionScope oldWidget) =>
      oldWidget.theme.category != theme.category;
}

/// The occasion in scope, or [fallback] when the widget is used on its own.
OccasionTheme occasionFor(
  BuildContext context, {
  InvitationCategory fallback = InvitationCategory.wedding,
}) => OccasionScope.maybeOf(context) ?? OccasionTheme.forCategory(fallback);
