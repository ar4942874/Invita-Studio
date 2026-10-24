import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show immutable;

/// The four lights a host can throw across the card.
///
/// Each one is a pool of warm or cool light from one corner plus a vignette
/// that pulls the eye to the type. They are deliberately cheap: two radial
/// gradients per frame, painted from the same function in the editor, the
/// thumbnails, the video renderer and the exported PNG, so what the host sees
/// is what leaves the app.
enum FocusLight {
  none('None', 'Plain paper, no light or shade.'),
  warmGlow('Warm glow', 'A soft pool from the top, like a table lamp.'),
  goldenHour('Golden hour', 'Late sun from the left, low and honeyed.'),
  candlelight('Candlelight', 'A small warm fire below the card, in the dark.'),
  coolDawn('Cool dawn', 'Early daylight from the right, quiet and blue.');

  const FocusLight(this.label, this.description);

  final String label;
  final String description;

  /// Where the light comes from, in fractions of the card.
  ui.Offset get origin => switch (this) {
    FocusLight.none => const ui.Offset(.5, .5),
    FocusLight.warmGlow => const ui.Offset(.5, .06),
    FocusLight.goldenHour => const ui.Offset(.12, .18),
    FocusLight.candlelight => const ui.Offset(.5, .96),
    FocusLight.coolDawn => const ui.Offset(.88, .12),
  };

  /// Radius of the pool as a fraction of the card's longest side.
  double get spread => switch (this) {
    FocusLight.none => 0,
    FocusLight.warmGlow => .95,
    FocusLight.goldenHour => .85,
    FocusLight.candlelight => .78,
    FocusLight.coolDawn => .9,
  };

  ui.Color get glow => switch (this) {
    FocusLight.none => const ui.Color(0x00000000),
    FocusLight.warmGlow => const ui.Color(0xFFFFEFC8),
    FocusLight.goldenHour => const ui.Color(0xFFFFCE8C),
    FocusLight.candlelight => const ui.Color(0xFFFFDFAE),
    FocusLight.coolDawn => const ui.Color(0xFFCFE6FF),
  };

  ui.Color get shade => switch (this) {
    FocusLight.none => const ui.Color(0x00000000),
    FocusLight.warmGlow => const ui.Color(0xFF3B2410),
    FocusLight.goldenHour => const ui.Color(0xFF4A2A0F),
    FocusLight.candlelight => const ui.Color(0xFF2C1707),
    FocusLight.coolDawn => const ui.Color(0xFF0F2030),
  };

  /// Lights the host can pick; `none` is the off switch, not a choice.
  static List<FocusLight> get choices =>
      values.where((light) => light != FocusLight.none).toList();

  static FocusLight? byName(String? name) {
    for (final light in values) {
      if (light.name == name) return light;
    }
    return null;
  }
}

/// Which light is on the card, and how strong.
///
/// Stored on the project, so it travels with the draft and the exported JSON.
@immutable
class FocusLightSetting {
  const FocusLightSetting({
    this.light = FocusLight.none,
    this.intensity = defaultIntensity,
  });

  static const double defaultIntensity = .55;

  /// The off switch. Identical to the default, spelled out at call sites.
  static const FocusLightSetting none = FocusLightSetting();

  final FocusLight light;

  /// 0–1. Above ~.45 the glow starts to compete with the type, so the sheet
  /// warns rather than blocks.
  final double intensity;

  bool get isOff => light == FocusLight.none || intensity <= 0;

  FocusLightSetting copyWith({FocusLight? light, double? intensity}) =>
      FocusLightSetting(
        light: light ?? this.light,
        intensity: (intensity ?? this.intensity).clamp(0.0, 1.0),
      );

  Map<String, dynamic> toJson() => {
    'light': light.name,
    'intensity': double.parse(intensity.toStringAsFixed(2)),
  };

  /// Tolerant by design: an unknown or missing light is simply no light, so a
  /// project written by a newer build still opens.
  static FocusLightSetting decode(Object? raw) {
    if (raw is! Map) return none;
    final light = FocusLight.byName(raw['light'] as String?);
    if (light == null) return none;
    final rawIntensity = raw['intensity'];
    final intensity = rawIntensity is num && rawIntensity.isFinite
        ? rawIntensity.toDouble().clamp(0.0, 1.0)
        : defaultIntensity;
    return FocusLightSetting(light: light, intensity: intensity);
  }

  @override
  bool operator ==(Object other) =>
      other is FocusLightSetting &&
      other.light == light &&
      other.intensity == intensity;

  @override
  int get hashCode => Object.hash(light, intensity);

  @override
  String toString() => 'FocusLightSetting(${light.name}, $intensity)';
}

/// Paints [setting] onto [canvas] at [size].
///
/// Pure canvas maths with no widget or asset dependency: the artboard, the
/// document thumbnails, the video frame renderer and the PNG compositor all
/// call this, so a light cannot look different in the export.
void paintFocusLight(ui.Canvas canvas, ui.Size size, FocusLightSetting setting) {
  if (setting.isOff || size.isEmpty) return;
  final light = setting.light;
  final strength = setting.intensity.clamp(0.0, 1.0);
  final rect = ui.Offset.zero & size;
  final longest = size.longestSide;

  canvas.save();
  canvas.clipRect(rect);

  // The pool: from the light's origin, fading out before the card edge.
  final origin = ui.Offset(
    size.width * light.origin.dx,
    size.height * light.origin.dy,
  );
  canvas.drawRect(
    rect,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        origin,
        longest * light.spread,
        [
          light.glow.withValues(alpha: .34 * strength),
          light.glow.withValues(alpha: .12 * strength),
          light.glow.withValues(alpha: 0),
        ],
        const [0, .55, 1],
      ),
  );

  // The falloff: corners sink, so the centre of the card keeps the eye.
  canvas.drawRect(
    rect,
    ui.Paint()
      ..shader = ui.Gradient.radial(
        rect.center,
        longest * .62,
        [
          light.shade.withValues(alpha: 0),
          light.shade.withValues(alpha: .30 * strength),
        ],
        const [.55, 1],
      ),
  );

  canvas.restore();
}
