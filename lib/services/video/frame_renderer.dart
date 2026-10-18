import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../../domain/invitation_template.dart';
import '../../domain/video/timeline.dart';
import 'video_media.dart';

/// Decodes background-clip frames on demand and keeps a small LRU cache.
///
/// The export path uses a single-entry cache so a 15 s export never holds more
/// than one decoded background frame next to the frame being encoded.
class ClipFrameCache {
  ClipFrameCache({
    required this.clip,
    this.maxEntries = 8,
    this.decodeWidth,
  });

  final ImportedClip clip;
  final int maxEntries;

  /// Downscale target for the interactive preview. `null` decodes full size.
  final int? decodeWidth;

  final LinkedHashMap<int, ui.Image> _images = LinkedHashMap<int, ui.Image>();
  final Map<int, Future<ui.Image?>> _pending = {};
  bool _disposed = false;

  ui.Image? peek(int index) => _images[index];

  /// Loads [index] if needed. Safe to call repeatedly; concurrent calls share
  /// one decode.
  Future<ui.Image?> ensure(int index) {
    if (_disposed) return Future<ui.Image?>.value(null);
    final clamped = index.clamp(0, clip.frameCount - 1).toInt();
    final cached = _images[clamped];
    if (cached != null) {
      // Refresh LRU position.
      _images.remove(clamped);
      _images[clamped] = cached;
      return Future<ui.Image?>.value(cached);
    }
    return _pending.putIfAbsent(clamped, () async {
      try {
        final bytes = await clip.readFrame(clamped);
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: decodeWidth,
          allowUpscaling: false,
        );
        final frame = await codec.getNextFrame();
        codec.dispose();
        if (_disposed) {
          frame.image.dispose();
          return null;
        }
        _images[clamped] = frame.image;
        while (_images.length > maxEntries) {
          final oldest = _images.keys.first;
          _images.remove(oldest)?.dispose();
        }
        return frame.image;
      } catch (_) {
        // A single unreadable proxy frame should not abort playback; the
        // export validates the whole sequence first and reports missing media.
        return null;
      } finally {
        _pending.remove(clamped);
      }
    });
  }

  void dispose() {
    _disposed = true;
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _pending.clear();
  }
}

/// Maps a timeline instant to a proxy frame index, honouring trim and looping.
int clipFrameIndexFor({
  required VideoTimeline timeline,
  required ClipManifest manifest,
  required int timeMs,
}) {
  final trimStart = timeline.background.trimStartMs
      .clamp(0, manifest.proxyDurationMs - 1)
      .toInt();
  final trimEnd = timeline.background.trimEndMs > 0
      ? timeline.background.trimEndMs
            .clamp(trimStart + 1, manifest.proxyDurationMs)
            .toInt()
      : manifest.proxyDurationMs;
  final window = (trimEnd - trimStart).clamp(1, manifest.proxyDurationMs).toInt();
  var local = timeMs.clamp(0, timeline.durationMs).toInt();
  if (timeline.background.loop) {
    local = local % window;
  } else {
    local = local.clamp(0, window - 1).toInt();
  }
  final sourceMs = trimStart + local;
  final index = (sourceMs * manifest.fps) ~/ 1000;
  return index.clamp(0, manifest.frameCount - 1).toInt();
}

/// Paints one deterministic frame of the video invitation.
///
/// The same function is used by the interactive preview (through
/// [VideoFramePainter]) and by the exporter (into a [ui.PictureRecorder]), so
/// what the user sees is what is encoded. Layer transforms come from
/// [evaluateTimeline]; text layout, Arabic shaping, fonts and image fitting all
/// come from the shared canvas engine.
class TimelineFrameRenderer {
  TimelineFrameRenderer({
    required DesignDocument document,
    required this.imageCache,
  }) : document = fitTextDocument(document);

  final DesignDocument document;
  final Map<String, ui.Image> imageCache;

  static const Set<String> _nonLayerTypes = {'background'};

  Iterable<DesignNode> get _layers =>
      document.nodes.where((node) => !_nonLayerTypes.contains(node.type));

  BackgroundNode? get _background {
    for (final node in document.nodes) {
      if (node is BackgroundNode) return node;
    }
    return null;
  }

  Set<String> get layerIds => {for (final node in _layers) node.id};

  /// Renders to an offscreen image. Callers must dispose the result.
  Future<ui.Image> renderImage({
    required VideoTimeline timeline,
    required int timeMs,
    required int width,
    required int height,
    ui.Image? backgroundFrame,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    paintFrame(
      canvas,
      ui.Size(width.toDouble(), height.toDouble()),
      timeline: timeline,
      timeMs: timeMs,
      backgroundFrame: backgroundFrame,
    );
    final picture = recorder.endRecording();
    try {
      return await picture.toImage(width, height);
    } finally {
      picture.dispose();
    }
  }

  /// Paints the frame into [canvas] at [size] (document aspect ratio).
  void paintFrame(
    ui.Canvas canvas,
    ui.Size size, {
    required VideoTimeline timeline,
    required int timeMs,
    ui.Image? backgroundFrame,
  }) {
    final scale = size.width / document.width;
    final coords = CoordinateSystem(
      width: document.width,
      height: document.height,
      viewportScale: scale,
      viewportOffset: ui.Offset.zero,
    );

    // 1. Background colour + bundled artwork.
    final frame = evaluateTimeline(timeline, layerIds, timeMs);
    final background = _background;
    if (background != null) {
      final backgroundOnly = document.copyWith(nodes: [background]);
      CanvasPainter(
        document: backgroundOnly,
        coords: coords,
        imageCache: imageCache,
        devicePixelRatio: 1,
      ).paint(canvas, size);
    }

    // 2. Imported background clip on top of the artwork.
    if (backgroundFrame != null && timeline.background.hasClip) {
      final dest = ui.Rect.fromLTWH(
        0,
        0,
        document.width * scale,
        document.height * scale,
      );
      paintImageFitted(canvas, backgroundFrame, dest, timeline.background.fit);
    }

    // 2b. Starlit backdrop dressing behind the layers (Spotlight style).
    if (timeline.backdrop == Backdrop.night) {
      _paintNightBackdrop(canvas, size, scale, timeline, frame, timeMs);
    }

    // 3. Animated layers. On the starlit backdrop the text turns white so it
    // reads against the near-black scene.
    final nodes = <DesignNode>[];
    final opacities = <String, double>{};
    final night = timeline.backdrop == Backdrop.night;
    for (final node in _layers) {
      final visual = frame.visualFor(node.id);
      if (!visual.visible || visual.opacity <= 0.002) continue;
      final layer = night && node is TextNode
          ? node.copyWith(textColor: '#FFFFFFFF')
          : node;
      nodes.add(_withVisual(layer, visual));
      opacities[node.id] = visual.opacity;
    }
    if (nodes.isEmpty) return;
    CanvasPainter(
      document: document.copyWith(nodes: nodes),
      coords: coords,
      imageCache: imageCache,
      devicePixelRatio: 1,
      nodeOpacities: opacities,
    ).paint(canvas, size);
  }

  DesignNode _withVisual(DesignNode node, LayerVisual visual) {
    final frame = node.frame.shift(visual.offset);
    if (visual.scale == 1) return node.copyWith(frame: frame);
    return node.copyWith(
      frame: frame,
      scaleX: node.scaleX * visual.scale,
      scaleY: node.scaleY * visual.scale,
    );
  }

  /// Deepens the artwork to near-black, twinkles a deterministic star field,
  /// and — while one layer's entrance is running — pools a soft light behind
  /// it, so the focus visibly travels name by name. Pure canvas math keyed to
  /// [timeMs]: the preview and the export paint identical frames.
  void _paintNightBackdrop(
    ui.Canvas canvas,
    ui.Size size,
    double scale,
    VideoTimeline timeline,
    TimelineFrame frame,
    int timeMs,
  ) {
    canvas.drawRect(
      ui.Offset.zero & size,
      ui.Paint()..color = const ui.Color(0xFF000000).withValues(alpha: 0.86),
    );

    final seconds = timeMs / 1000.0;
    final starScale = scale.clamp(0.5, 3.0).toDouble();
    for (var i = 0; i < 90; i++) {
      final x = _unit01(i, 1) * size.width;
      final y = _unit01(i, 2) * size.height;
      final radius = (0.7 + 1.5 * _unit01(i, 3)) * starScale;
      final twinkle = 0.5 +
          0.5 * math.sin(math.pi * 2 * ((0.35 + 0.85 * _unit01(i, 4)) * seconds) + math.pi * 2 * _unit01(i, 5));
      if (i % 11 == 0) {
        // A brighter star with a soft halo.
        canvas.drawCircle(
          ui.Offset(x, y),
          radius * 3.2,
          ui.Paint()..color = _starBlue.withValues(alpha: 0.05 + 0.1 * twinkle),
        );
      }
      final alpha = i % 11 == 0 ? 0.55 + 0.45 * twinkle : 0.25 + 0.6 * twinkle;
      canvas.drawCircle(
        ui.Offset(x, y),
        radius,
        ui.Paint()..color = _starWhite.withValues(alpha: alpha),
      );
    }

    // Pool the light behind the layer that is appearing right now.
    for (final node in _layers) {
      final motion = timeline.motionFor(node.id);
      final entrance = motion.entrance;
      if (!entrance.isAnimated) continue;
      final local =
          timeMs - motion.visibleStartMs - entrance.delayMs;
      if (local < 0 || local > entrance.durationMs) continue;
      final visual = frame.visualFor(node.id);
      if (!visual.visible || visual.opacity <= 0.002) continue;
      final center = node.frame.center + visual.offset;
      final glowCenter = ui.Offset(center.dx * scale, center.dy * scale);
      final radius = size.height * 0.3;
      final progress = local / entrance.durationMs;
      final alpha = 0.3 * math.sin(progress * math.pi);
      canvas.drawCircle(
        glowCenter,
        radius,
        ui.Paint()
          ..shader = ui.Gradient.radial(
            glowCenter,
            radius,
            [_spotGlow.withValues(alpha: alpha), _spotGlow.withValues(alpha: 0)],
            [0, 1],
          ),
      );
      break;
    }
  }

  static const ui.Color _starWhite = ui.Color(0xFFF2F7FF);
  static const ui.Color _starBlue = ui.Color(0xFFBFD4FF);
  static const ui.Color _spotGlow = ui.Color(0xFFF6E7B4);

  static int _starHash(int n) {
    var x = n & 0xFFFFFFFF;
    x = (x ^ 61) ^ (x >> 16);
    x = x + (x << 3);
    x = x ^ (x >> 4);
    x = x * 0x27d4eb2d;
    x = x ^ (x >> 15);
    return x & 0x7FFFFFFF;
  }

  static double _unit01(int i, int salt) =>
      (_starHash(i * 131 + salt) & 0xFFFFFF) / 0xFFFFFF;
}

/// Draws [image] into [dest] using the same cover/contain/fill rules as the
/// canvas engine, so a background clip is framed exactly like a photo layer.
void paintImageFitted(ui.Canvas canvas, ui.Image image, ui.Rect dest, String fit) {
  final src = ui.Rect.fromLTWH(
    0,
    0,
    image.width.toDouble(),
    image.height.toDouble(),
  );
  final paint = ui.Paint()
    ..isAntiAlias = true
    ..filterQuality = ui.FilterQuality.medium;
  if (fit == 'contain') {
    final scale = (dest.width / src.width)
        .clamp(0.0, dest.height / src.height)
        .toDouble();
    final w = src.width * scale;
    final h = src.height * scale;
    canvas.drawImageRect(
      image,
      src,
      ui.Rect.fromLTWH(
        dest.left + (dest.width - w) / 2,
        dest.top + (dest.height - h) / 2,
        w,
        h,
      ),
      paint,
    );
    return;
  }
  final srcRect = fit == 'fill' ? src : _coverRect(src, dest);
  canvas.drawImageRect(image, srcRect, dest, paint);
}

ui.Rect _coverRect(ui.Rect src, ui.Rect dest) {
  final srcAspect = src.width / src.height;
  final destAspect = dest.width / dest.height;
  if (srcAspect > destAspect) {
    final w = src.height * destAspect;
    return ui.Rect.fromLTWH((src.width - w) / 2, 0, w, src.height);
  }
  final h = src.width / destAspect;
  return ui.Rect.fromLTWH(0, (src.height - h) / 2, src.width, h);
}

/// [CustomPainter] wrapper used by the live preview.
class VideoFramePainter extends CustomPainter {
  VideoFramePainter({
    required this.renderer,
    required this.timeline,
    required this.timeMs,
    required this.backgroundFrame,
    required this.revision,
  });

  final TimelineFrameRenderer renderer;
  final VideoTimeline timeline;
  final int timeMs;
  final ui.Image? backgroundFrame;
  final int revision;

  @override
  void paint(ui.Canvas canvas, ui.Size size) {
    canvas.save();
    canvas.clipRect(ui.Offset.zero & size);
    renderer.paintFrame(
      canvas,
      size,
      timeline: timeline,
      timeMs: timeMs,
      backgroundFrame: backgroundFrame,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant VideoFramePainter old) =>
      old.timeMs != timeMs ||
      old.revision != revision ||
      old.backgroundFrame != backgroundFrame ||
      !identical(old.timeline, timeline) ||
      old.renderer != renderer;
}

/// Reads proxy frames for export, one at a time.
class ExportFrameFeed {
  ExportFrameFeed({required this.clip, required this.timeline});

  final ImportedClip clip;
  final VideoTimeline timeline;
  late final ClipFrameCache _cache = ClipFrameCache(clip: clip, maxEntries: 2);

  Future<ui.Image?> frameFor(int timeMs) async {
    final index = clipFrameIndexFor(
      timeline: timeline,
      manifest: clip.manifest,
      timeMs: timeMs,
    );
    return _cache.ensure(index);
  }

  void dispose() => _cache.dispose();
}

/// Convenience: decode a JPEG/PNG byte buffer into an image for tests/tools.
Future<ui.Image> decodeImageBytes(Uint8List bytes, {int? targetWidth}) async {
  final codec = await ui.instantiateImageCodec(bytes, targetWidth: targetWidth);
  final frame = await codec.getNextFrame();
  codec.dispose();
  return frame.image;
}
