import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Video-invitation timeline model.
///
/// This file is intentionally free of Flutter widget imports so the evaluation
/// rules that drive the preview and the exporter can be unit-tested without a
/// rendering surface. `dart:ui` is used only for [Offset].
///
/// Everything an export needs is stored here. The exporter freezes a copy of
/// this model together with a copy of the [DesignDocument] before it starts, so
/// later UI edits cannot change a running export.

/// Limits shared by the editor UI, the decoder and the exporter.
abstract final class TimelineLimits {
  static const int minDurationMs = 5000;
  static const int maxDurationMs = 30000;
  static const int fps = 30;
  static const int maxLayersWithMotion = 50;

  /// Slide distance in document units (the document is always 1080 wide).
  static const double slideDistance = 150;

  /// Range of the ambient (looping) motions, applied to every layer for the
  /// whole card so the invitation is never a frozen still.
  static const double ambientDriftDistance = 46;
  static const double ambientZoom = 0.10;
  static const double ambientBreathe = 0.03;

  static const int maxAudioVolume = 100;
  static const int maxFadeMs = 5000;
  static const int maxTrimMs = 60000;
}

/// Entrance/exit effects supported by the frame renderer.
///
/// The list is deliberately small: every value here is implemented in
/// [evaluateTimeline] and therefore exported. Unsupported ideas (blur, rotate)
/// are not exposed in the UI.
enum MotionEffect {
  none('none', 'None'),
  fade('fade', 'Fade'),
  slideUp('slideUp', 'Slide up'),
  slideDown('slideDown', 'Slide down'),
  slideLeft('slideLeft', 'Slide left'),
  slideRight('slideRight', 'Slide right'),
  zoomIn('zoomIn', 'Zoom in'),
  zoomOut('zoomOut', 'Zoom out');

  const MotionEffect(this.wireName, this.label);
  final String wireName;
  final String label;

  static MotionEffect? fromWire(String? value) {
    for (final effect in MotionEffect.values) {
      if (effect.wireName == value) return effect;
    }
    return null;
  }
}

/// Easing curves supported by the exporter (plain math, no Flutter dependency).
enum MotionEasing {
  linear('linear', 'Linear'),
  easeIn('easeIn', 'Ease in'),
  easeOut('easeOut', 'Ease out'),
  easeOutCubic('easeOutCubic', 'Ease out (soft)'),
  easeOutBack('easeOutBack', 'Ease out (overshoot)'),
  easeInOut('easeInOut', 'Ease in-out');

  const MotionEasing(this.wireName, this.label);
  final String wireName;
  final String label;

  static MotionEasing? fromWire(String? value) {
    for (final easing in MotionEasing.values) {
      if (easing.wireName == value) return easing;
    }
    return null;
  }

  double apply(double t) {
    final x = t.clamp(0.0, 1.0).toDouble();
    return switch (this) {
      MotionEasing.linear => x,
      MotionEasing.easeIn => x * x,
      MotionEasing.easeOut => 1 - (1 - x) * (1 - x),
      MotionEasing.easeOutCubic => 1 - math.pow(1 - x, 3).toDouble(),
      MotionEasing.easeOutBack => _easeOutBack(x),
      MotionEasing.easeInOut => x * x * (3 - 2 * x),
    };
  }

  /// Overshoots past 1 near the end, then settles — the "spring/pop" feel.
  static double _easeOutBack(double x) {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    final p = x - 1;
    return 1 + c3 * p * p * p + c1 * p * p;
  }
}

/// A single animated transition (entrance or exit).
class Motion {
  const Motion({
    this.effect = MotionEffect.none,
    this.durationMs = 600,
    this.delayMs = 0,
    this.easing = MotionEasing.easeOut,
  });

  static const Motion none = Motion();

  final MotionEffect effect;
  final int durationMs;

  /// Delay after the layer becomes visible (entrance only; ignored on exit).
  final int delayMs;
  final MotionEasing easing;

  bool get isAnimated => effect != MotionEffect.none && durationMs > 0;

  Motion copyWith({
    MotionEffect? effect,
    int? durationMs,
    int? delayMs,
    MotionEasing? easing,
  }) => Motion(
    effect: effect ?? this.effect,
    durationMs: durationMs ?? this.durationMs,
    delayMs: delayMs ?? this.delayMs,
    easing: easing ?? this.easing,
  );

  Map<String, dynamic> toJson() => {
    'effect': effect.wireName,
    'durationMs': durationMs,
    'delayMs': delayMs,
    'easing': easing.wireName,
  };

  static Motion decode(Object? raw, String path) {
    if (raw == null) return Motion.none;
    if (raw is! Map) throw FormatException('$path must be an object.');
    final effect = MotionEffect.fromWire(raw['effect'] as String?);
    final easing = MotionEasing.fromWire(raw['easing'] as String?);
    final duration = raw['durationMs'];
    final delay = raw['delayMs'];
    if (effect == null) throw FormatException('$path has an unknown effect.');
    if (easing == null) throw FormatException('$path has an unknown easing.');
    if (duration is! int || duration < 100 || duration > 10000) {
      throw FormatException('$path.durationMs is out of range.');
    }
    if (delay is! int || delay < 0 || delay > 10000) {
      throw FormatException('$path.delayMs is out of range.');
    }
    return Motion(
      effect: effect,
      durationMs: duration,
      delayMs: delay,
      easing: easing,
    );
  }
}

/// Visibility window and entrance/exit motion for one layer.
class LayerMotion {
  const LayerMotion({
    this.visibleStartMs = 0,
    this.visibleEndMs = TimelineLimits.maxDurationMs,
    this.entrance = Motion.none,
    this.exit = Motion.none,
  });

  final int visibleStartMs;
  final int visibleEndMs;
  final Motion entrance;
  final Motion exit;

  bool get isDefault =>
      visibleStartMs == 0 &&
      visibleEndMs == TimelineLimits.maxDurationMs &&
      !entrance.isAnimated &&
      !exit.isAnimated;

  LayerMotion copyWith({
    int? visibleStartMs,
    int? visibleEndMs,
    Motion? entrance,
    Motion? exit,
  }) => LayerMotion(
    visibleStartMs: visibleStartMs ?? this.visibleStartMs,
    visibleEndMs: visibleEndMs ?? this.visibleEndMs,
    entrance: entrance ?? this.entrance,
    exit: exit ?? this.exit,
  );

  Map<String, dynamic> toJson() => {
    'visibleStartMs': visibleStartMs,
    'visibleEndMs': visibleEndMs,
    'entrance': entrance.toJson(),
    'exit': exit.toJson(),
  };

  static LayerMotion decode(Object? raw, String path) {
    if (raw == null) return const LayerMotion();
    if (raw is! Map) throw FormatException('$path must be an object.');
    final start = raw['visibleStartMs'];
    final end = raw['visibleEndMs'];
    if (start is! int || start < 0 || start > TimelineLimits.maxDurationMs) {
      throw FormatException('$path.visibleStartMs is out of range.');
    }
    if (end is! int || end > TimelineLimits.maxDurationMs || end - start < 200) {
      throw FormatException('$path.visibleEndMs is out of range.');
    }
    return LayerMotion(
      visibleStartMs: start,
      visibleEndMs: end,
      entrance: Motion.decode(raw['entrance'], '$path.entrance'),
      exit: Motion.decode(raw['exit'], '$path.exit'),
    );
  }
}

/// A one-tap animation style for the whole invitation card.
///
/// Presets are pure and Flutter-free: [build] turns the current layer IDs into
/// per-layer motions, so the interactive preview, the exporter and the tests all
/// agree on what "Rise up" means. The UI keeps the pro controls for individual
/// layers behind an "Advanced" toggle; a preset simply writes the same model.
enum MotionPreset {
  none('none', 'None', 'A still card, no motion'),
  fade('fade', 'Fade in', 'Everything fades in softly'),
  rise('rise', 'Rise up', 'Text and photos float up as they appear'),
  zoomIn('zoomIn', 'Zoom in', 'The card grows into place'),
  zoomOut('zoomOut', 'Zoom out', 'The card settles in from larger'),
  pop('pop', 'Pop', 'Layers spring in with a light bounce'),
  slide('slide', 'Slide in', 'Layers glide in from the sides'),
  stagger('stagger', 'One by one', 'Layers appear in a gentle sequence'),
  cascade('cascade', 'Cascade', 'A soft wave of fades, one after another'),
  glide('glide', 'Glide in', 'The card glides sideways into place'),
  dropIn('dropIn', 'Light drop', 'Layers fall softly with a bounce'),
  sweep('sweep', 'Side wave', 'A wave runs from the sides in order'),
  expand('expand', 'Grow in', 'Layers grow bigger one by one'),
  unfold('unfold', 'Pour down', 'Layers slide down into place in order'),
  bloom('bloom', 'Bloom open', 'The card blooms out from the middle'),
  popCascade('popCascade', 'Pop by one', 'Layers pop in one at a time'),
  floatIn('floatIn', 'Float', 'A gentle fade with a slow drift'),
  blinds('blinds', 'Slides and fades', 'Slides and fades mix in sequence'),
  shimmer('shimmer', 'Ripple', 'Zooms and fades ripple across the card'),
  hover('hover', 'Drift zoom', 'A quiet zoom deepens the whole time');

  const MotionPreset(this.wireName, this.label, this.tagline);
  final String wireName;
  final String label;
  final String tagline;

  /// Entrance length shared by every preset. Deliberately slow so the card
  /// glides into place instead of snapping, and stays easy to follow on phone.
  static const int entranceMs = 2400;

  /// Builds the per-layer motions a preset writes over a clean window.
  ///
  /// The visibility window always spans the whole card (clamped to
  /// [TimelineLimits.maxDurationMs]) so the animation survives a length change.
  Map<String, LayerMotion> build({
    required List<String> layerIds,
    required int durationMs,
  }) {
    final span = durationMs
        .clamp(TimelineLimits.minDurationMs, TimelineLimits.maxDurationMs)
        .toInt();
    Motion entrance(
      MotionEffect effect, {
      MotionEasing easing = MotionEasing.easeOut,
      int delayMs = 0,
    }) => Motion(
      effect: effect,
      durationMs: entranceMs,
      delayMs: delayMs,
      easing: easing,
    );
    LayerMotion layer(Motion value) => LayerMotion(
      visibleStartMs: 0,
      visibleEndMs: span,
      entrance: value,
    );

    final count = layerIds.length;
    // Keep the last entrance inside the card and inside the decoder's delay
    // limit, so a saved project always re-loads and exports.
    final maxDelay = (span - entranceMs).clamp(0, 10000);
    int staggerDelay(int index) {
      if (count <= 1) return 0;
      final step = (maxDelay / (count - 1)).floor().clamp(0, 320);
      return (index * step).clamp(0, maxDelay).toInt();
    }

    switch (this) {
      case MotionPreset.none:
        return const <String, LayerMotion>{};
      case MotionPreset.fade:
        return {
          for (final id in layerIds)
            id: layer(entrance(MotionEffect.fade, easing: MotionEasing.easeInOut)),
        };
      case MotionPreset.rise:
        return {
          for (final id in layerIds)
            id: layer(
              entrance(MotionEffect.slideUp, easing: MotionEasing.easeOutBack),
            ),
        };
      case MotionPreset.zoomIn:
        return {
          for (final id in layerIds)
            id: layer(
              entrance(MotionEffect.zoomIn, easing: MotionEasing.easeOutCubic),
            ),
        };
      case MotionPreset.zoomOut:
        return {
          for (final id in layerIds)
            id: layer(
              entrance(MotionEffect.zoomOut, easing: MotionEasing.easeOutCubic),
            ),
        };
      case MotionPreset.pop:
        return {
          for (final id in layerIds)
            id: layer(
              entrance(MotionEffect.zoomIn, easing: MotionEasing.easeOutBack),
            ),
        };
      case MotionPreset.slide:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                i.isEven ? MotionEffect.slideLeft : MotionEffect.slideRight,
                easing: MotionEasing.easeOutCubic,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.stagger:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                MotionEffect.slideUp,
                easing: MotionEasing.easeOut,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.cascade:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                MotionEffect.fade,
                easing: MotionEasing.easeInOut,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.glide:
        return {
          for (final id in layerIds)
            id: layer(
              entrance(MotionEffect.slideLeft, easing: MotionEasing.easeInOut),
            ),
        };
      case MotionPreset.dropIn:
        return {
          for (final id in layerIds)
            id: layer(
              entrance(MotionEffect.slideDown, easing: MotionEasing.easeOutBack),
            ),
        };
      case MotionPreset.sweep:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                i.isEven ? MotionEffect.slideLeft : MotionEffect.slideRight,
                easing: MotionEasing.easeInOut,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.expand:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                MotionEffect.zoomIn,
                easing: MotionEasing.easeOutCubic,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.unfold:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                MotionEffect.slideDown,
                easing: MotionEasing.easeOutCubic,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.bloom:
        return {
          for (final id in layerIds)
            id: layer(
              entrance(MotionEffect.zoomOut, easing: MotionEasing.easeOutBack),
            ),
        };
      case MotionPreset.popCascade:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                MotionEffect.zoomIn,
                easing: MotionEasing.easeOutBack,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.floatIn:
        return {
          for (final id in layerIds)
            id: layer(entrance(MotionEffect.fade, easing: MotionEasing.easeOut)),
        };
      case MotionPreset.blinds:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                i.isEven ? MotionEffect.slideDown : MotionEffect.fade,
                easing: MotionEasing.easeInOut,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.shimmer:
        return {
          for (var i = 0; i < count; i++)
            layerIds[i]: layer(
              entrance(
                i.isEven ? MotionEffect.zoomIn : MotionEffect.fade,
                easing: MotionEasing.easeInOut,
                delayMs: staggerDelay(i),
              ),
            ),
        };
      case MotionPreset.hover:
        return {
          for (final id in layerIds)
            id: layer(
              entrance(MotionEffect.zoomIn, easing: MotionEasing.linear),
            ),
        };
    }
  }

  /// The looping motion a preset enables alongside its entrances, so the card
  /// keeps moving after the entrances settle instead of freezing.
  AmbientMotion get ambient => switch (this) {
    MotionPreset.none => AmbientMotion.none,
    MotionPreset.fade => AmbientMotion.breathe,
    MotionPreset.rise => AmbientMotion.drift,
    MotionPreset.zoomIn => AmbientMotion.zoom,
    MotionPreset.zoomOut => AmbientMotion.zoom,
    MotionPreset.pop => AmbientMotion.breathe,
    MotionPreset.slide => AmbientMotion.drift,
    MotionPreset.stagger => AmbientMotion.drift,
    MotionPreset.cascade => AmbientMotion.breathe,
    MotionPreset.glide => AmbientMotion.drift,
    MotionPreset.dropIn => AmbientMotion.drift,
    MotionPreset.sweep => AmbientMotion.zoom,
    MotionPreset.expand => AmbientMotion.zoom,
    MotionPreset.unfold => AmbientMotion.drift,
    MotionPreset.bloom => AmbientMotion.breathe,
    MotionPreset.popCascade => AmbientMotion.breathe,
    MotionPreset.floatIn => AmbientMotion.drift,
    MotionPreset.blinds => AmbientMotion.drift,
    MotionPreset.shimmer => AmbientMotion.breathe,
    MotionPreset.hover => AmbientMotion.zoom,
  };

  /// Whether [motions] is exactly what this preset writes for [layerIds].
  bool matches({
    required Iterable<String> layerIds,
    required int durationMs,
    required Map<String, LayerMotion> motions,
  }) {
    final ids = layerIds.toList();
    final expected = build(layerIds: ids, durationMs: durationMs);
    final idSet = ids.toSet();
    for (final key in motions.keys) {
      if (!idSet.contains(key)) return false;
    }
    for (final id in ids) {
      final actual = motions[id] ?? const LayerMotion();
      final want = expected[id] ?? const LayerMotion();
      if (!_sameLayerMotion(actual, want, durationMs)) return false;
    }
    return true;
  }

  /// The preset a timeline currently matches, or null when it is custom.
  static MotionPreset? detect({
    required Iterable<String> layerIds,
    required int durationMs,
    required Map<String, LayerMotion> motions,
  }) {
    for (final preset in MotionPreset.values) {
      if (preset.matches(
        layerIds: layerIds,
        durationMs: durationMs,
        motions: motions,
      )) {
        return preset;
      }
    }
    return null;
  }

  static bool _sameLayerMotion(LayerMotion a, LayerMotion b, int durationMs) =>
      _normEnd(a.visibleEndMs, durationMs) ==
          _normEnd(b.visibleEndMs, durationMs) &&
      a.visibleStartMs == b.visibleStartMs &&
      _sameMotion(a.entrance, b.entrance) &&
      _sameMotion(a.exit, b.exit);

  /// A window that reaches [durationMs] or beyond is treated as "the whole
  /// card", because the timeline clamps store-side ends to the current length.
  static int _normEnd(int end, int durationMs) =>
      end >= durationMs ? durationMs : end;

  static bool _sameMotion(Motion a, Motion b) =>
      a.effect == b.effect &&
      a.durationMs == b.durationMs &&
      a.delayMs == b.delayMs &&
      a.easing == b.easing;
}

/// A slow looping motion applied to every layer for the whole card.
///
/// Entrances/exit only occupy the start (and end) of the video, so a card with
/// just a preset entrance is frozen for most of its length. The ambient motion
/// runs across the entire duration so the exported video always shows movement.
enum AmbientMotion {
  none('none', 'Still', 'No looping motion'),
  drift('drift', 'Slow drift', 'The card glides gently the whole time'),
  zoom('zoom', 'Slow zoom', 'The card keeps growing very slowly'),
  breathe('breathe', 'Breathe', 'The card softly pulses in and out');

  const AmbientMotion(this.wireName, this.label, this.tagline);
  final String wireName;
  final String label;
  final String tagline;

  static AmbientMotion? fromWire(String? value) {
    for (final motion in AmbientMotion.values) {
      if (motion.wireName == value) return motion;
    }
    return null;
  }

  bool get isAnimated => this != AmbientMotion.none;
}

/// What fills the frame behind the invitation layers.
enum BackgroundKind {
  artwork('artwork'),
  clip('clip');

  const BackgroundKind(this.wireName);
  final String wireName;

  static BackgroundKind? fromWire(String? value) {
    for (final kind in BackgroundKind.values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// Background choice for video mode.
class VideoBackground {
  const VideoBackground({
    this.kind = BackgroundKind.artwork,
    this.assetId,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.fit = 'cover',
    this.loop = true,
  });

  final BackgroundKind kind;

  /// Managed-media asset ID of the imported clip (never a filesystem path).
  final String? assetId;

  /// Trim window inside the source clip. `trimEndMs == 0` means "to the end".
  final int trimStartMs;
  final int trimEndMs;
  final String fit;
  final bool loop;

  bool get hasClip => kind == BackgroundKind.clip && assetId != null;

  VideoBackground copyWith({
    BackgroundKind? kind,
    String? assetId,
    bool clearAsset = false,
    int? trimStartMs,
    int? trimEndMs,
    String? fit,
    bool? loop,
  }) => VideoBackground(
    kind: kind ?? this.kind,
    assetId: clearAsset ? null : (assetId ?? this.assetId),
    trimStartMs: trimStartMs ?? this.trimStartMs,
    trimEndMs: trimEndMs ?? this.trimEndMs,
    fit: fit ?? this.fit,
    loop: loop ?? this.loop,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.wireName,
    'assetId': assetId,
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'fit': fit,
    'loop': loop,
  };

  static VideoBackground decode(Object? raw, String path) {
    if (raw == null) return const VideoBackground();
    if (raw is! Map) throw FormatException('$path must be an object.');
    final kind = BackgroundKind.fromWire(raw['kind'] as String?);
    if (kind == null) throw FormatException('$path has an unknown kind.');
    final assetId = raw['assetId'];
    final trimStart = raw['trimStartMs'];
    final trimEnd = raw['trimEndMs'];
    final fit = raw['fit'];
    final loop = raw['loop'];
    if (assetId != null &&
        (assetId is! String || !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(assetId))) {
      throw FormatException('$path.assetId is invalid.');
    }
    if (kind == BackgroundKind.clip && assetId == null) {
      throw FormatException('$path is missing its clip reference.');
    }
    if (trimStart is! int ||
        trimStart < 0 ||
        trimStart > TimelineLimits.maxTrimMs) {
      throw FormatException('$path.trimStartMs is out of range.');
    }
    if (trimEnd is! int ||
        trimEnd < 0 ||
        trimEnd > TimelineLimits.maxTrimMs ||
        (trimEnd != 0 && trimEnd <= trimStart)) {
      throw FormatException('$path.trimEndMs is out of range.');
    }
    if (!const {'cover', 'contain', 'fill'}.contains(fit)) {
      throw FormatException('$path.fit is unsupported.');
    }
    if (loop is! bool) throw FormatException('$path.loop must be a boolean.');
    return VideoBackground(
      kind: kind,
      assetId: assetId as String?,
      trimStartMs: trimStart,
      trimEndMs: trimEnd,
      fit: fit as String,
      loop: loop,
    );
  }
}

/// Optional user-owned music track.
class VideoAudio {
  const VideoAudio({
    required this.assetId,
    this.title,
    this.startMs = 0,
    this.trimStartMs = 0,
    this.trimEndMs = 0,
    this.durationMs = 0,
    this.volume = 80,
    this.fadeInMs = 800,
    this.fadeOutMs = 1200,
  });

  final String assetId;
  final String? title;

  /// When playback of the music starts on the invitation timeline.
  final int startMs;
  final int trimStartMs;
  final int trimEndMs;

  /// Length of the imported music file, recorded at import time so the trim
  /// controls survive an app restart without re-probing the file. Zero means
  /// "unknown" and the UI hides the trim range.
  final int durationMs;

  /// 0..100. Zero means the user muted the track: the exporter then writes an
  /// explicit silent MP4 (no audio track) instead of a silent AAC track.
  final int volume;
  final int fadeInMs;
  final int fadeOutMs;

  bool get isMuted => volume <= 0;

  VideoAudio copyWith({
    String? assetId,
    String? title,
    int? startMs,
    int? trimStartMs,
    int? trimEndMs,
    int? durationMs,
    int? volume,
    int? fadeInMs,
    int? fadeOutMs,
  }) => VideoAudio(
    assetId: assetId ?? this.assetId,
    title: title ?? this.title,
    startMs: startMs ?? this.startMs,
    trimStartMs: trimStartMs ?? this.trimStartMs,
    trimEndMs: trimEndMs ?? this.trimEndMs,
    durationMs: durationMs ?? this.durationMs,
    volume: volume ?? this.volume,
    fadeInMs: fadeInMs ?? this.fadeInMs,
    fadeOutMs: fadeOutMs ?? this.fadeOutMs,
  );

  Map<String, dynamic> toJson() => {
    'assetId': assetId,
    'title': title,
    'startMs': startMs,
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'durationMs': durationMs,
    'volume': volume,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
  };

  static VideoAudio decode(Object? raw, String path) {
    if (raw == null) return throw FormatException('$path is missing.');
    if (raw is! Map) throw FormatException('$path must be an object.');
    final assetId = raw['assetId'];
    if (assetId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch(assetId)) {
      throw FormatException('$path.assetId is invalid.');
    }
    final title = raw['title'];
    if (title != null && (title is! String || title.length > 120)) {
      throw FormatException('$path.title is invalid.');
    }
    int intIn(Object? value, String name, int min, int max) {
      if (value is! int || value < min || value > max) {
        throw FormatException('$name is out of range.');
      }
      return value;
    }

    final start = intIn(raw['startMs'] ?? 0, '$path.startMs', 0, TimelineLimits.maxDurationMs);
    final trimStart = intIn(raw['trimStartMs'] ?? 0, '$path.trimStartMs', 0, TimelineLimits.maxTrimMs);
    final trimEnd = intIn(raw['trimEndMs'] ?? 0, '$path.trimEndMs', 0, TimelineLimits.maxTrimMs);
    if (trimEnd != 0 && trimEnd <= trimStart) {
      throw FormatException('$path.trimEndMs must follow trimStartMs.');
    }
    final duration = intIn(
      raw['durationMs'] ?? 0,
      '$path.durationMs',
      0,
      600000,
    );
    final volume = intIn(raw['volume'] ?? 80, '$path.volume', 0, 100);
    final fadeIn = intIn(raw['fadeInMs'] ?? 0, '$path.fadeInMs', 0, TimelineLimits.maxFadeMs);
    final fadeOut = intIn(raw['fadeOutMs'] ?? 0, '$path.fadeOutMs', 0, TimelineLimits.maxFadeMs);
    return VideoAudio(
      assetId: assetId,
      title: title as String?,
      startMs: start,
      trimStartMs: trimStart,
      trimEndMs: trimEnd,
      durationMs: duration,
      volume: volume,
      fadeInMs: fadeIn,
      fadeOutMs: fadeOut,
    );
  }
}

/// The complete, versioned video settings of a project.
class VideoTimeline {
  const VideoTimeline({
    this.enabled = false,
    this.durationMs = 15000,
    this.background = const VideoBackground(),
    this.motions = const {},
    this.ambient = AmbientMotion.none,
    this.audio,
  });

  static const VideoTimeline defaults = VideoTimeline();

  final bool enabled;
  final int durationMs;
  final VideoBackground background;

  /// Motion overrides keyed by layer ID. Layers without an entry are visible
  /// for the whole timeline with no effects.
  final Map<String, LayerMotion> motions;

  /// Looping motion that runs for the whole card, on top of the entrances.
  final AmbientMotion ambient;
  final VideoAudio? audio;

  int get fps => TimelineLimits.fps;

  /// Number of frames an export writes. Integer math keeps it deterministic.
  int get frameCount => (durationMs * fps) ~/ 1000;

  /// A time at which every entrance has finished and no exit has begun.
  ///
  /// The preview shows this frame when it is idle at the start of the card, so
  /// an entrance animation does not leave an apparently blank card before the
  /// user presses play.
  int get settledTimeMs {
    var settled = 0;
    for (final motion in motions.values) {
      final end =
          motion.visibleStartMs +
          motion.entrance.delayMs +
          motion.entrance.durationMs;
      if (end > settled) settled = end;
    }
    final limit = durationMs > 0 ? durationMs - 1 : 0;
    return settled.clamp(0, limit).toInt();
  }

  /// Timestamp of a frame, in microseconds since the start of the video.
  ///
  /// Timestamps are derived from the frame index only, never from wall-clock
  /// playback time, so an export is reproducible.
  int frameTimestampUs(int frame) => frame * 1000000 ~/ fps;

  VideoTimeline copyWith({
    bool? enabled,
    int? durationMs,
    VideoBackground? background,
    Map<String, LayerMotion>? motions,
    AmbientMotion? ambient,
    VideoAudio? audio,
    bool clearAudio = false,
  }) => VideoTimeline(
    enabled: enabled ?? this.enabled,
    durationMs: durationMs ?? this.durationMs,
    background: background ?? this.background,
    motions: motions ?? this.motions,
    ambient: ambient ?? this.ambient,
    audio: clearAudio ? null : (audio ?? this.audio),
  );

  VideoTimeline withMotion(String nodeId, LayerMotion motion) {
    final next = Map<String, LayerMotion>.of(motions);
    if (motion.isDefault) {
      next.remove(nodeId);
    } else {
      next[nodeId] = motion;
    }
    return copyWith(motions: next);
  }

  LayerMotion motionFor(String nodeId) =>
      motions[nodeId] ?? const LayerMotion();

  /// Validation shared by the decoder and the exporter. Returns a list of
  /// human-readable problems; empty means the timeline can be exported.
  List<String> validate({required Set<String> layerIds}) {
    final problems = <String>[];
    if (durationMs < TimelineLimits.minDurationMs ||
        durationMs > TimelineLimits.maxDurationMs) {
      problems.add('Duration must be between 5 and 30 seconds.');
    }
    if (background.kind == BackgroundKind.clip && background.assetId == null) {
      problems.add('Background clip is missing.');
    }
    if (motions.length > TimelineLimits.maxLayersWithMotion) {
      problems.add('Too many animated layers.');
    }
    for (final entry in motions.entries) {
      if (!layerIds.contains(entry.key)) {
        problems.add('Animation refers to a missing layer.');
        break;
      }
      final motion = entry.value;
      if (motion.visibleEndMs <= motion.visibleStartMs) {
        problems.add('A layer is visible for zero seconds.');
        break;
      }
      if (motion.entrance.delayMs + motion.entrance.durationMs >
          motion.visibleEndMs - motion.visibleStartMs) {
        problems.add('An entrance animation is longer than its layer window.');
        break;
      }
    }
    final track = audio;
    if (track != null) {
      if (track.startMs >= durationMs) {
        problems.add('Music starts after the invitation ends.');
      }
      if (track.volume < 0 || track.volume > 100) {
        problems.add('Music volume is out of range.');
      }
    }
    return problems;
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'durationMs': durationMs,
    'fps': fps,
    'background': background.toJson(),
    'motions': {
      for (final entry in motions.entries) entry.key: entry.value.toJson(),
    },
    'ambient': ambient.wireName,
    'audio': audio?.toJson(),
  };

  static VideoTimeline decode(Object? raw) {
    if (raw == null) return VideoTimeline.defaults;
    if (raw is! Map) throw const FormatException('video must be an object.');
    final enabled = raw['enabled'] ?? false;
    if (enabled is! bool) {
      throw const FormatException('video.enabled must be a boolean.');
    }
    final duration = raw['durationMs'] ?? 15000;
    if (duration is! int ||
        duration < TimelineLimits.minDurationMs ||
        duration > TimelineLimits.maxDurationMs) {
      throw const FormatException('video.durationMs is out of range.');
    }
    if ((raw['fps'] ?? TimelineLimits.fps) != TimelineLimits.fps) {
      throw const FormatException('Only 30 fps is supported.');
    }
    final rawMotions = raw['motions'];
    final motions = <String, LayerMotion>{};
    if (rawMotions != null) {
      if (rawMotions is! Map) {
        throw const FormatException('video.motions must be an object.');
      }
      for (final entry in rawMotions.entries) {
        final id = entry.key;
        if (id is! String || !RegExp(r'^[\w.-]{1,80}$').hasMatch(id)) {
          throw const FormatException('video.motions has an invalid layer ID.');
        }
        motions[id] = LayerMotion.decode(entry.value, 'video.motions.$id');
      }
    }
    final rawAmbient = raw['ambient'];
    return VideoTimeline(
      enabled: enabled,
      durationMs: duration,
      background: VideoBackground.decode(
        raw['background'],
        'video.background',
      ),
      motions: motions,
      ambient: rawAmbient is String
          ? (AmbientMotion.fromWire(rawAmbient) ?? AmbientMotion.none)
          : AmbientMotion.none,
      audio: raw['audio'] == null ? null : VideoAudio.decode(raw['audio'], 'video.audio'),
    );
  }
}

/// The evaluated visual state of a layer at a point in time.
class LayerVisual {
  const LayerVisual({
    required this.visible,
    this.opacity = 1,
    this.offset = Offset.zero,
    this.scale = 1,
  });

  static const LayerVisual hidden = LayerVisual(visible: false);

  final bool visible;
  final double opacity;
  final Offset offset;
  final double scale;
}

/// A frozen snapshot of the timeline at one instant.
class TimelineFrame {
  const TimelineFrame({required this.timeMs, required this.layers});
  final int timeMs;
  final Map<String, LayerVisual> layers;

  LayerVisual visualFor(String nodeId) =>
      layers[nodeId] ?? const LayerVisual(visible: true);
}

/// Computes the visual state of every layer at [timeMs].
///
/// This is the single source of truth used by both the interactive preview and
/// the exporter, which is what keeps the exported MP4 identical to the preview.
TimelineFrame evaluateTimeline(
  VideoTimeline timeline,
  Iterable<String> nodeIds,
  int timeMs,
) {
  final t = timeMs.clamp(0, timeline.durationMs).toInt();
  final ambient = _ambientAt(timeline, t);
  final layers = <String, LayerVisual>{};
  for (final id in nodeIds) {
    final motion = timeline.motionFor(id);
    layers[id] = _evaluateLayer(motion, t, ambient);
  }
  return TimelineFrame(timeMs: t, layers: layers);
}

/// The looping transform shared by every layer at instant [t].
class _Ambient {
  const _Ambient(this.dy, this.scale);
  final double dy;
  final double scale;
}

_Ambient _ambientAt(VideoTimeline timeline, int t) {
  final duration = timeline.durationMs;
  if (duration <= 0) return const _Ambient(0, 1);
  final q = (t / duration).clamp(0.0, 1.0).toDouble();
  return switch (timeline.ambient) {
    AmbientMotion.none => const _Ambient(0, 1),
    AmbientMotion.drift => _Ambient(-TimelineLimits.ambientDriftDistance * q, 1),
    AmbientMotion.zoom => _Ambient(0, 1 + TimelineLimits.ambientZoom * q),
    AmbientMotion.breathe => _Ambient(
      0,
      1 + TimelineLimits.ambientBreathe * math.sin(2 * math.pi * q),
    ),
  };
}

LayerVisual _evaluateLayer(LayerMotion motion, int t, _Ambient ambient) {
  final start = motion.visibleStartMs;
  final end = motion.visibleEndMs;
  if (t < start || t >= end) return LayerVisual.hidden;

  var opacity = 1.0;
  var offset = Offset.zero;
  var scale = 1.0;

  final entrance = motion.entrance;
  if (entrance.isAnimated) {
    final local = t - start - entrance.delayMs;
    if (local < 0) {
      // Delayed entrance: keep the layer hidden until the delay elapses.
      return LayerVisual.hidden;
    }
    final progress = entrance.easing.apply(local / entrance.durationMs);
    final result = _applyEffect(entrance.effect, progress, entering: true);
    opacity *= result.opacity;
    offset += result.offset;
    scale *= result.scale;
  }

  final exit = motion.exit;
  if (exit.isAnimated) {
    final exitStart = end - exit.durationMs;
    if (t >= exitStart) {
      final progress = exit.easing.apply(
        (t - exitStart) / exit.durationMs,
      );
      final result = _applyEffect(exit.effect, progress, entering: false);
      opacity *= result.opacity;
      offset += result.offset;
      scale *= result.scale;
    }
  }

  return LayerVisual(
    visible: true,
    opacity: opacity.clamp(0.0, 1.0).toDouble(),
    offset: offset + Offset(0, ambient.dy),
    scale: (scale * ambient.scale).clamp(0.2, 3.0).toDouble(),
  );
}

class _EffectResult {
  const _EffectResult(this.opacity, this.offset, this.scale);
  final double opacity;
  final Offset offset;
  final double scale;
}

/// `progress` is 0 at the start of an entrance and 1 at its end; for exits the
/// same 0→1 progress runs from "just before the leave" to "gone".
_EffectResult _applyEffect(
  MotionEffect effect,
  double progress, {
  required bool entering,
}) {
  final p = progress.clamp(0.0, 1.0).toDouble();
  const d = TimelineLimits.slideDistance;
  final visible = entering ? p : 1 - p;
  return switch (effect) {
    MotionEffect.none => const _EffectResult(1, Offset.zero, 1),
    MotionEffect.fade => _EffectResult(visible, Offset.zero, 1),
    MotionEffect.slideUp => _EffectResult(
      visible,
      Offset(0, (entering ? 1 - p : -p) * d),
      1,
    ),
    MotionEffect.slideDown => _EffectResult(
      visible,
      Offset(0, (entering ? p - 1 : p) * d),
      1,
    ),
    MotionEffect.slideLeft => _EffectResult(
      visible,
      Offset((entering ? 1 - p : -p) * d, 0),
      1,
    ),
    MotionEffect.slideRight => _EffectResult(
      visible,
      Offset((entering ? p - 1 : p) * d, 0),
      1,
    ),
    // Entrances settle at 1.0; exits pull away from it.
    MotionEffect.zoomIn => _EffectResult(
      visible,
      Offset.zero,
      entering ? 0.82 + 0.18 * p : 1 + 0.18 * p,
    ),
    MotionEffect.zoomOut => _EffectResult(
      visible,
      Offset.zero,
      entering ? 1.18 - 0.18 * p : 1 - 0.18 * p,
    ),
  };
}
