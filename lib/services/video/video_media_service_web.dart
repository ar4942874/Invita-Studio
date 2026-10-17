import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:web/web.dart' as web;

import 'video_media.dart';

/// Browser default.
///
/// The browser has no managed filesystem, so imported background clips are
/// decoded from the source video, downscaled and held in memory for the session
/// only. Reloading the page loses them and the draft reports the media as
/// missing until it is re-imported.
VideoMediaService createVideoMediaService() => WebVideoMediaService();

class _WebClip {
  const _WebClip(this.manifest, this.frames);

  final ClipManifest manifest;
  final List<Uint8List> frames;

  int get bytes => frames.fold(0, (sum, frame) => sum + frame.length);
}

class WebVideoMediaService implements VideoMediaService {
  static final Map<String, _WebClip> _clips = <String, _WebClip>{};

  bool _cancelled = false;

  @override
  bool get isSupported => true;

  /// The browser export is silent, so music import is intentionally disabled.
  @override
  bool get isMusicSupported => false;

  static String _key(String projectId, String assetId) => '$projectId/$assetId';

  @override
  Future<VideoProbe> probeVideo(String sourcePath) async {
    final video = _createVideo(sourcePath);
    try {
      await _ready(video);
      final width = video.videoWidth;
      final height = video.videoHeight;
      final durationMs = (video.duration * 1000).round();
      if (durationMs <= 0 || width <= 0 || height <= 0) {
        throw const FormatException('That file is not a readable video.');
      }
      return VideoProbe(
        durationMs: durationMs,
        width: width,
        height: height,
        hasAudio: false,
      );
    } finally {
      _release(video);
    }
  }

  @override
  Future<ClipImportResult> extractClip({
    required String sourcePath,
    required String title,
    required String projectId,
    required String assetId,
    void Function(int done, int total)? onProgress,
  }) async {
    _cancelled = false;
    final video = _createVideo(sourcePath);
    try {
      await _ready(video);
      final sourceWidth = video.videoWidth;
      final sourceHeight = video.videoHeight;
      final durationMs = (video.duration * 1000).round();
      if (durationMs <= 0 || sourceWidth <= 0 || sourceHeight <= 0) {
        throw const FormatException('That file is not a readable video.');
      }

      final frameCount = (durationMs / 1000 * ClipLimits.extractionFps)
          .round()
          .clamp(1, ClipLimits.maxFrames)
          .toInt();
      final scale = _fitScale(sourceWidth, sourceHeight);
      final frameWidth = _even(sourceWidth * scale);
      final frameHeight = _even(sourceHeight * scale);

      final canvas = web.HTMLCanvasElement()
        ..width = frameWidth
        ..height = frameHeight;
      final context =
          canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (context == null) {
        throw const FormatException(
          'The browser could not create a drawing surface.',
        );
      }

      final frames = <Uint8List>[];
      for (var index = 0; index < frameCount; index++) {
        if (_cancelled) throw const FormatException('Import cancelled.');
        await _seek(video, index / ClipLimits.extractionFps);
        context.drawImage(video, 0, 0, frameWidth, frameHeight);
        final data = context.getImageData(0, 0, frameWidth, frameHeight);
        final clamped = data.data.toDart;
        final rgba = clamped.buffer.asUint8List(
          clamped.offsetInBytes,
          clamped.lengthInBytes,
        );
        frames.add(await _encodePng(rgba, frameWidth, frameHeight));
        onProgress?.call(index + 1, frameCount);
      }

      final manifest = ClipManifest(
        assetId: assetId,
        title: title,
        sourceDurationMs: durationMs,
        sourceWidth: sourceWidth,
        sourceHeight: sourceHeight,
        fps: ClipLimits.extractionFps,
        frameWidth: frameWidth,
        frameHeight: frameHeight,
        frameCount: frameCount,
        framePattern: 'f%05d.png',
        hasAudio: false,
      );
      final stored = _WebClip(manifest, frames);
      _clips[_key(projectId, assetId)] = stored;
      return ClipImportResult(
        manifest: manifest,
        clip: _clipFor(stored),
      );
    } finally {
      _release(video);
    }
  }

  @override
  Future<void> cancelExtraction() async {
    _cancelled = true;
  }

  @override
  Future<ImportedClip?> loadClip(String projectId, String assetId) async {
    final stored = _clips[_key(projectId, assetId)];
    if (stored == null) return null;
    return _clipFor(stored);
  }

  @override
  Future<ImportedAudio?> loadAudio(
    String projectId,
    String assetId, {
    String? title,
    int? durationMs,
  }) async => null;

  @override
  Future<void> deleteClip(String projectId, String assetId) async {
    _clips.remove(_key(projectId, assetId));
  }

  @override
  Future<int> projectBytes(String projectId) async {
    var total = 0;
    for (final entry in _clips.entries) {
      if (entry.key.startsWith('$projectId/')) total += entry.value.bytes;
    }
    return total;
  }

  @override
  Future<int> probeAudioDuration(String sourcePath) async {
    throw const FormatException('Music is not available in the browser build.');
  }

  @override
  Future<ImportedAudio?> importMusic({
    required String sourcePath,
    required String fileName,
    required String projectId,
    required String assetId,
  }) async => null;

  @override
  Future<void> deleteAudio(ImportedAudio audio) async {}

  ImportedClip _clipFor(_WebClip stored) => ImportedClip(
    manifest: stored.manifest,
    frameReader: (index) async {
      final clamped = index.clamp(0, stored.frames.length - 1).toInt();
      return stored.frames[clamped];
    },
  );

  web.HTMLVideoElement _createVideo(String source) {
    final video = web.HTMLVideoElement()
      ..src = source
      ..muted = true
      ..preload = 'auto';
    video.load();
    return video;
  }

  Future<void> _ready(web.HTMLVideoElement video) {
    final completer = Completer<void>();
    video.onloadedmetadata = ((web.Event event) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    video.onerror = ((web.Event event) {
      if (!completer.isCompleted) {
        completer.completeError(
          const FormatException('That video could not be read.'),
        );
      }
    }).toJS;
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () =>
          throw const FormatException('Reading that video timed out.'),
    );
  }

  Future<void> _seek(web.HTMLVideoElement video, double seconds) {
    if (seconds <= 0) {
      // The first frame is already displayed; seeking to 0 can skip 'seeked'.
      return Future<void>.value();
    }
    final completer = Completer<void>();
    video.onseeked = ((web.Event event) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    video.currentTime = seconds;
    return completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw const FormatException('Seeking that video timed out.'),
    );
  }

  void _release(web.HTMLVideoElement video) {
    video.onseeked = null;
    video.onloadedmetadata = null;
    video.onerror = null;
    video.removeAttribute('src');
    video.load();
  }

  double _fitScale(int width, int height) {
    final byWidth = ClipLimits.maxWidth / width;
    final byHeight = ClipLimits.maxHeight / height;
    final scale = byWidth < byHeight ? byWidth : byHeight;
    return scale < 1 ? scale : 1;
  }

  int _even(num value) {
    final rounded = value.round();
    final even = rounded.isOdd ? rounded - 1 : rounded;
    return even < 2 ? 2 : even;
  }

  Future<Uint8List> _encodePng(Uint8List rgba, int width, int height) async {
    final image = await _imageFromRgba(rgba, width, height);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw const FormatException('A frame could not be encoded.');
      }
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      image.dispose();
    }
  }

  Future<ui.Image> _imageFromRgba(Uint8List rgba, int width, int height) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
