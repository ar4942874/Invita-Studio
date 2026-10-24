import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/ui/occasion_theme.dart';
import 'package:invitation_studio/ui/studio_theme.dart';

/// WCAG 2.1 relative luminance.
double _luminance(Color colour) {
  double channel(double value) => value <= .03928
      ? value / 12.92
      : math.pow((value + .055) / 1.055, 2.4).toDouble();
  return .2126 * channel(colour.r) +
      .7152 * channel(colour.g) +
      .0722 * channel(colour.b);
}

/// WCAG contrast ratio, 1..21.
double _contrast(Color a, Color b) {
  final la = _luminance(a);
  final lb = _luminance(b);
  final lighter = la > lb ? la : lb;
  final darker = la > lb ? lb : la;
  return (lighter + .05) / (darker + .05);
}

void main() {
  group('every celebration has its own room', () {
    test('all six categories have a theme, and none share an accent', () {
      expect(OccasionTheme.all, hasLength(InvitationCategory.values.length));
      final accents = <Color>{};
      for (final category in InvitationCategory.values) {
        final theme = OccasionTheme.forCategory(category);
        expect(theme.category, category);
        expect(theme.mood, isNotEmpty);
        expect(theme.story, isNotEmpty);
        accents.add(theme.accent);
      }
      expect(accents, hasLength(InvitationCategory.values.length));
    });

    test('wedding is the calm sage-and-cream room', () {
      final wedding = OccasionTheme.forCategory(InvitationCategory.wedding);
      expect(wedding.mood, 'Pleasant');
      expect(wedding.canvas, const Color(0xFFFBF7F1));
      expect(wedding.accent, const Color(0xFF587452));
    });

    test('text clears 4.5:1 against every surface it is set on', () {
      for (final theme in OccasionTheme.all) {
        final pairs = <String, List<Color>>{
          'ink on canvas': [theme.ink, theme.canvas],
          'ink on surface': [theme.ink, theme.surface],
          'inkSoft on canvas': [theme.inkSoft, theme.canvas],
          'inkSoft on surface': [theme.inkSoft, theme.surface],
          'muted on canvas': [theme.muted, theme.canvas],
          'muted on surface': [theme.muted, theme.surface],
          'meta on canvas': [theme.meta, theme.canvas],
          'meta on surface': [theme.meta, theme.surface],
          'accent on canvas': [theme.accent, theme.canvas],
          'accent on surface': [theme.accent, theme.surface],
          'accentOn on accent': [theme.accentOn, theme.accent],
        };
        pairs.forEach((label, colours) {
          expect(
            _contrast(colours[0], colours[1]),
            greaterThanOrEqualTo(4.5),
            reason: '${theme.category.name}: $label is too faint',
          );
        });
      }
    });

    test('the page wash and the shadow follow the palette', () {
      for (final theme in OccasionTheme.all) {
        expect(theme.pageGradient.colors.first, theme.canvas);
        expect(theme.pageGradient.colors.last, theme.surfaceWarm);
        expect(theme.raisedShadow.single.color.a, greaterThan(0));
        expect(theme.glow, theme.accent);
      }
    });
  });

  group('the scope publishes one theme', () {
    testWidgets('occasionFor falls back to wedding without a scope', (
      tester,
    ) async {
      late OccasionTheme seen;
      await tester.pumpWidget(
        Builder(
          builder: (context) {
            seen = occasionFor(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(seen.category, InvitationCategory.wedding);
    });

    testWidgets('occasionFor reads the scope it is under', (tester) async {
      late OccasionTheme seen;
      await tester.pumpWidget(
        OccasionScope(
          theme: OccasionTheme.forCategory(InvitationCategory.birthday),
          child: Builder(
            builder: (context) {
              seen = occasionFor(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(seen.category, InvitationCategory.birthday);
      expect(seen.accent, OccasionTheme.forCategory(InvitationCategory.birthday).accent);
    });
  });

  group('the Material theme follows the occasion', () {
    test('the neutral theme is unchanged when no occasion is passed', () {
      final neutral = studioTheme();
      expect(neutral.colorScheme.primary, StudioColors.accent);
      expect(neutral.scaffoldBackgroundColor, StudioColors.canvas);
    });

    test('an occasion recolours controls, canvas and dividers', () {
      for (final theme in OccasionTheme.all) {
        final data = studioTheme(occasion: theme);
        expect(data.colorScheme.primary, theme.accent);
        expect(data.colorScheme.onPrimary, theme.accentOn);
        expect(data.colorScheme.surface, theme.surface);
        expect(data.colorScheme.onSurface, theme.ink);
        expect(data.scaffoldBackgroundColor, theme.canvas);
        expect(data.dividerTheme.color, theme.border);
        expect(data.inputDecorationTheme.hintStyle?.color, theme.muted);
        expect(data.sliderTheme.activeTrackColor, theme.accent);
        expect(data.snackBarTheme.backgroundColor, theme.ink);
        expect(data.iconButtonTheme.style?.foregroundColor?.resolve({}), theme.ink);
        expect(
          data.filledButtonTheme.style?.backgroundColor?.resolve({}),
          theme.accent,
        );
      }
    });
  });
}
