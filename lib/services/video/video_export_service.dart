import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:path_provider/path_provider.dart';

import '../../domain/focus_light.dart';
import '../../domain/video/timeline.dart';
import 'export_media.dart';
import 'frame_renderer.dart';
import 'video_encoder.dart';
import 'video_encoder_platform.dart';
import 'video_media.dart';

enum VideoExportStage {
  preparing('Preparing'),
  rendering('Rendering frames'),
  finishing('Finishing file'),
  done('Done');

  const VideoExportStage(this.label);
  final String label;
}

class VideoExportProgress {
  const VideoExportProgress({
    required this.stage,
    required this.frame,
    required this.frameCount,
    this.message,
  });

  final VideoExportStage stage;
  final int frame;
  final int frameCount;
  final String? message;

  double get fraction {
    if (frameCount <= 0) return 0;
    final frameFraction = frame / frameCount;
    return switch (stage) {
      VideoExportStage.preparing => 0,
      VideoExportStage.rendering => frameFraction * 0.92,
      VideoExportStage.finishing => 0.98,
      VideoExportStage.done => 1,
    };
  }
}

class VideoExportResult {
  const VideoExportResult({
    required this.path,
    required this.bytes,
    required this.width,
    required this.height,
    required this.durationMs,
    required this.fps,
    required this.frameCount,
    required this.hasAudio,
    required this.elapsed,
  });

  final String path;
  final int bytes;
  final int width;
  final int height;
  final int durationMs;
  final int fps;
  final int frameCount;

  /// False means the MP4 has no audio track at all (a silent invitation).
  final bool hasAudio;
  final Duration elapsed;

  String get sizeLabel => formatBytes(bytes);
  String get durationLabel {
    final totalSeconds = durationMs / 1000;
    final seconds = totalSeconds.toStringAsFixed(1);
    return '$seconds s';
  }
}

/// Cancellation token shared between the export dialog and the exporter.
class ExportCancellation {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class VideoExportException implements Exception {
  const VideoExportException(this.message, {this.detail});
  final String message;
  final String? detail;
  @override
  String toString() => detail == null ? message : '$message ($detail)';
}

/// Everything an export needs, frozen before the first frame is rendered.
class VideoExportRequest {
  const VideoExportRequest({
    required this.projectId,
    required this.title,
    required this.document,
    required this.timeline,
    required this.backend,
    this.clip,
    this.audio,
    this.imageProvider,
    this.outputWidth = 1080,
    this.bitrate,
    this.focusLight = FocusLightSetting.none,
  });

  final String projectId;
  final String title;
  final DesignDocument document;
  final VideoTimeline timeline;
  final VideoEncoderBackend backend;
  final ImportedClip? clip;
  final ImportedAudio? audio;

  /// Resolves embedded data-URL photos for the shared canvas engine.
  final CanvasImageProvider? imageProvider;

  /// 1080 for a full-quality Story export, 540 for the lighter option.
  final int outputWidth;
  final int? bitrate;

  /// The card's light, frozen with the rest of the request.
  final FocusLightSetting focusLight;
}

/// Renders and encodes a video invitation.
///
/// Guarantees:
/// * the document and timeline are copied before the first `await`;
/// * frame timestamps come from the frame index only (no wall-clock);
/// * at most one full-resolution frame plus one background frame is decoded at
///   a time;
/// * a cancelled or failed export deletes its partial file and disposes every
///   image it created.
class VideoExporter {
  VideoExporter({
    Future<Directory> Function()? tempDirectory,
    Future<Directory> Function()? documentsDirectory,
  }) : _tempDirectory = tempDirectory ?? getTemporaryDirectory,
       _documentsDirectory = documentsDirectory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _tempDirectory;
  final Future<Directory> Function() _documentsDirectory;

  Future<VideoExportResult> export({
    required VideoExportRequest request,
    required void Function(VideoExportProgress) onProgress,
    required ExportCancellation cancellation,
  }) async {
    // Freeze everything before the first await so edits during the export
    // cannot leak into the file or the progress numbers.
    final document = request.document.copyWith(
      nodes: List<DesignNode>.unmodifiable(request.document.nodes),
    );
    final timeline = request.timeline.copyWith(
      motions: Map<String, LayerMotion>.unmodifiable(request.timeline.motions),
    );
    final started = DateTime.now();
    if (!request.backend.isSupported) {
      throw VideoExportException(request.backend.unsupportedReason);
    }
    final problems = timeline.validate(layerIds: {
      for (final node in document.nodes)
        if (node.type != 'background') node.id,
    });
    if (problems.isNotEmpty) {
      throw VideoExportException(problems.first);
    }
    if (timeline.audio != null &&
        exportNeedsAudio(timeline.audio, isWeb: kIsWeb) &&
        request.audio == null) {
      throw const VideoExportException(
        'The music file for this draft is missing. Re-import it or mute the track.',
      );
    }
    if (timeline.background.hasClip && request.clip == null) {
      throw const VideoExportException(
        'The background video for this draft is missing. Re-import it or switch back to artwork.',
      );
    }
    final totalFrames = timeline.frameCount;
    if (totalFrames < 1 || totalFrames > 900) {
      throw const VideoExportException('Unsupported video length.');
    }
    final outputWidth = request.outputWidth.clamp(360, 1080).toInt();
    final scale = outputWidth / document.width;
    final outputHeight = (document.height * scale).round();
    if (outputWidth.isOdd || outputHeight.isOdd) {
      // H.264 4:2:0 needs even dimensions; the invitation formats are even but
      // guard anyway so a future format cannot produce unencodable output.
      throw const VideoExportException('Unsupported output size.');
    }

    onProgress(
      VideoExportProgress(
        stage: VideoExportStage.preparing,
        frame: 0,
        frameCount: totalFrames,
        message: 'Loading layers',
      ),
    );

    final images = await CanvasImageLoader.buildCacheForDocument(
      document: document,
      imageProvider: request.imageProvider,
    );
    for (final node in document.nodes) {
      final ref = node is ImageNode
          ? CanvasImageReference.fromImageNode(node)
          : node is BackgroundNode && node.hasBackgroundImage
          ? CanvasImageReference.fromBackgroundNode(node)
          : null;
      if (ref != null && !ref.isEmpty && !images.containsKey(ref.cacheKey)) {
        for (final image in images.values) {
          image.dispose();
        }
        throw const VideoExportException(
          'An image layer could not be loaded. Export was stopped instead of writing a placeholder.',
        );
      }
    }

    final fileName = '${_slug(request.title)}-${_stamp(started)}.mp4';

    // The browser backend records and downloads the artefact itself, so no
    // native temp directory or file is created there.
    File? tempFile;
    if (!kIsWeb) {
      final tempDir = Directory(
        '${(await _tempDirectory()).path}/invita-video-exports',
      );
      if (!await tempDir.exists()) await tempDir.create(recursive: true);
      tempFile = File('${tempDir.path}/$fileName');
      if (await tempFile.exists()) await tempFile.delete();
    }

    // Browsers record a silent video; audio muxing stays native-only, and a
    // muted track is written without an audio track. Both cases are decided by
    // the same rule the dialog uses to decide whether to resolve the file.
    final audioTrack = timeline.audio;
    final audioSource = exportNeedsAudio(audioTrack, isWeb: kIsWeb)
        ? request.audio
        : null;
    EncoderAudioSpec? encoderAudio;
    if (audioTrack != null && audioSource != null) {
      encoderAudio = EncoderAudioSpec(
        path: audioSource.path,
        startMs: audioTrack.startMs,
        trimStartMs: audioTrack.trimStartMs,
        trimEndMs: audioTrack.trimEndMs,
        volume: audioTrack.volume,
        fadeInMs: audioTrack.fadeInMs,
        fadeOutMs: audioTrack.fadeOutMs,
        durationMs: timeline.durationMs,
      );
    }

    final renderer = TimelineFrameRenderer(
      document: document,
      imageCache: images,
      focusLight: request.focusLight,
    );
    final feed = request.clip == null
        ? null
        : ExportFrameFeed(
            clip: request.clip!,
            timeline: timeline,
          );
    VideoEncoderSession? session;
    var succeeded = false;
    try {
      session = await request.backend.open(
        VideoEncodeSpec(
          outputPath: tempFile?.path ?? fileName,
          width: outputWidth,
          height: outputHeight,
          fps: timeline.fps,
          frameCount: totalFrames,
          bitrate: request.bitrate ?? (outputWidth >= 1080 ? 8000000 : 3000000),
          audio: encoderAudio,
        ),
      );
      for (var frame = 0; frame < totalFrames; frame++) {
        if (cancellation.isCancelled) {
          throw const VideoExportException('Export cancelled.');
        }
        final timeMs = (frame * 1000) ~/ timeline.fps;
        final background = feed == null ? null : await feed.frameFor(timeMs);
        final image = await renderer.renderImage(
          timeline: timeline,
          timeMs: timeMs,
          width: outputWidth,
          height: outputHeight,
          backgroundFrame: background,
        );
        try {
          final data = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          if (data == null) {
            throw const VideoExportException(
              'A video frame could not be read back from the renderer.',
            );
          }
          await session.addFrame(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            timeline.frameTimestampUs(frame),
          );
        } finally {
          image.dispose();
        }
        if (cancellation.isCancelled) {
          throw const VideoExportException('Export cancelled.');
        }
        onProgress(
          VideoExportProgress(
            stage: VideoExportStage.rendering,
            frame: frame + 1,
            frameCount: totalFrames,
          ),
        );
      }
      onProgress(
        VideoExportProgress(
          stage: VideoExportStage.finishing,
          frame: totalFrames,
          frameCount: totalFrames,
          message: kIsWeb
              ? 'Finalising video'
              : encoderAudio == null
              ? 'Writing silent MP4'
              : 'Muxing AAC audio',
        ),
      );
      final encoded = await session.finish();
      var resultPath = encoded.path;
      var resultBytes = encoded.bytes;
      if (!kIsWeb) {
        final encodedFile = File(encoded.path);
        if (!await encodedFile.exists() || encoded.bytes < 1024) {
          throw const VideoExportException(
            'The encoder finished without writing a usable MP4.',
          );
        }
        final exportsDir = Directory(
          '${(await _documentsDirectory()).path}/InvitaStudioExports',
        );
        if (!await exportsDir.exists()) await exportsDir.create(recursive: true);
        final finalFile = File('${exportsDir.path}/$fileName');
        await encodedFile.rename(finalFile.path);
        resultPath = finalFile.path;
        resultBytes = await finalFile.length();
      } else if (encoded.bytes < 1024) {
        throw const VideoExportException(
          'The encoder finished without producing a usable video.',
        );
      }
      succeeded = true;
      onProgress(
        VideoExportProgress(
          stage: VideoExportStage.done,
          frame: totalFrames,
          frameCount: totalFrames,
        ),
      );
      return VideoExportResult(
        path: resultPath,
        bytes: resultBytes,
        width: outputWidth,
        height: outputHeight,
        durationMs: timeline.durationMs,
        fps: timeline.fps,
        frameCount: totalFrames,
        hasAudio: !kIsWeb && encoderAudio != null,
        elapsed: DateTime.now().difference(started),
      );
    } catch (error) {
      if (!succeeded) {
        try {
          await session?.cancel();
        } catch (_) {
          // Best-effort; the partial file is removed below.
        }
        try {
          if (tempFile != null && await tempFile.exists()) {
            await tempFile.delete();
          }
        } catch (_) {
          // Best-effort cleanup.
        }
      }
      if (error is VideoExportException) rethrow;
      throw VideoExportException(
        cancellation.isCancelled
            ? 'Export cancelled.'
            : 'The video could not be exported.',
        detail: error is Exception ? error.toString() : null,
      );
    } finally {
      feed?.dispose();
      for (final image in images.values) {
        image.dispose();
      }
      images.clear();
    }
  }

  static String _slug(String title) {
    final base = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final trimmed = base.isEmpty ? 'invitation' : base;
    return trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed;
  }

  static String _stamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}${two(time.month)}${two(time.day)}-'
        '${two(time.hour)}${two(time.minute)}${two(time.second)}';
  }
}

/// Convenience for tests and the UI: is this build able to encode?
bool get isVideoExportSupported => createVideoEncoderBackend().isSupported;
