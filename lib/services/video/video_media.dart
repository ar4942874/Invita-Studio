import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Imported media (background clips and music) lives in managed asset storage
/// next to the drafts, never inside the project JSON.
///
/// Layout:
/// ```
/// <documents>/InvitaStudioMedia/<projectId>/clips/<assetId>/manifest.json
/// <documents>/InvitaStudioMedia/<projectId>/clips/<assetId>/f00000.jpg …
/// <documents>/InvitaStudioMedia/<projectId>/audio/<assetId>.<ext>
/// ```
/// The project only stores asset IDs and trim settings, so a project JSON stays
/// small; the trade-off is that copied projects must be relinked (documented in
/// the export dialog and README).
abstract final class MediaPaths {
  static const String rootName = 'InvitaStudioMedia';
}

/// Bounded extraction settings. A 30 s story at 30 fps needs 900 frames.
abstract final class ClipLimits {
  static const int maxFrames = 900;
  static const int extractionFps = 30;
  static const int maxWidth = 1080;
  static const int maxHeight = 1920;
}

/// On-disk description of an imported background clip.
class ClipManifest {
  const ClipManifest({
    required this.assetId,
    required this.title,
    required this.sourceDurationMs,
    required this.sourceWidth,
    required this.sourceHeight,
    required this.fps,
    required this.frameWidth,
    required this.frameHeight,
    required this.frameCount,
    required this.framePattern,
    this.hasAudio = false,
  });

  static const String schema = 'invita.clip';
  static const int version = 1;

  final String assetId;
  final String title;
  final int sourceDurationMs;
  final int sourceWidth;
  final int sourceHeight;
  final int fps;
  final int frameWidth;
  final int frameHeight;
  final int frameCount;
  final String framePattern;
  final bool hasAudio;

  int get proxyDurationMs => frameCount * 1000 ~/ fps;

  String frameName(int index) =>
      framePattern.replaceFirst('%05d', index.toString().padLeft(5, '0'));

  Map<String, dynamic> toJson() => {
    'schema': schema,
    'version': version,
    'assetId': assetId,
    'title': title,
    'sourceDurationMs': sourceDurationMs,
    'sourceWidth': sourceWidth,
    'sourceHeight': sourceHeight,
    'fps': fps,
    'frameWidth': frameWidth,
    'frameHeight': frameHeight,
    'frameCount': frameCount,
    'framePattern': framePattern,
    'hasAudio': hasAudio,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static ClipManifest decode(String source) {
    final json = jsonDecode(source);
    if (json is! Map<String, dynamic> ||
        json['schema'] != schema ||
        json['version'] != version) {
      throw const FormatException('Unsupported clip manifest.');
    }
    int intValue(Object? value, String name, int min, int max) {
      if (value is! int || value < min || value > max) {
        throw FormatException('Clip manifest $name is invalid.');
      }
      return value;
    }

    return ClipManifest(
      assetId: json['assetId'] as String,
      title: (json['title'] as String?) ?? 'Background clip',
      sourceDurationMs: intValue(json['sourceDurationMs'], 'duration', 1, 600000),
      sourceWidth: intValue(json['sourceWidth'], 'width', 1, 8192),
      sourceHeight: intValue(json['sourceHeight'], 'height', 1, 8192),
      fps: intValue(json['fps'], 'fps', 1, 60),
      frameWidth: intValue(json['frameWidth'], 'frameWidth', 1, 4096),
      frameHeight: intValue(json['frameHeight'], 'frameHeight', 1, 4096),
      frameCount: intValue(json['frameCount'], 'frameCount', 1, ClipLimits.maxFrames),
      framePattern: json['framePattern'] as String? ?? 'f%05d.jpg',
      hasAudio: json['hasAudio'] == true,
    );
  }
}

/// An imported, managed background clip.
class ImportedClip {
  const ImportedClip({
    required this.manifest,
    required this.directory,
  });

  final ClipManifest manifest;

  /// Absolute directory that holds the frames. Not persisted.
  final String directory;

  String framePath(int index) =>
      '$directory/${manifest.frameName(index)}';

  int get frameCount => manifest.frameCount;
  int get fps => manifest.fps;
  int get durationMs => manifest.proxyDurationMs;
}

/// A managed music file.
class ImportedAudio {
  const ImportedAudio({
    required this.assetId,
    required this.title,
    required this.durationMs,
    required this.path,
  });

  final String assetId;
  final String title;
  final int durationMs;
  final String path;
}

/// Result of extracting the JPEG proxy sequence.
class ExtractedFrames {
  const ExtractedFrames({
    required this.count,
    required this.width,
    required this.height,
  });

  final int count;
  final int width;
  final int height;
}

/// Result of probing a picked video file before extraction.
class VideoProbe {
  const VideoProbe({
    required this.durationMs,
    required this.width,
    required this.height,
    required this.hasAudio,
  });

  final int durationMs;
  final int width;
  final int height;
  final bool hasAudio;
}

/// Platform bridge for native media work (probe + frame extraction).
///
/// Frame extraction and probing need platform codecs, so they are native-only.
/// Preview and export never call this class; they read the extracted proxy that
/// it produces. On unsupported platforms [isSupported] is false and the UI
/// explains that background video needs the Android or iOS build.
class VideoMediaChannel {
  VideoMediaChannel({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('invita/video_media');

  final MethodChannel _channel;

  bool get isSupported =>
      !kIsWeb && (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<VideoProbe> probeVideo(String path) async {
    final result = await _channel.invokeMapMethod<String, Object?>(
      'probeVideo',
      {'path': path},
    );
    if (result == null) throw const FormatException('That video could not be read.');
    return VideoProbe(
      durationMs: (result['durationMs'] as num?)?.toInt() ?? 0,
      width: (result['width'] as num?)?.toInt() ?? 0,
      height: (result['height'] as num?)?.toInt() ?? 0,
      hasAudio: result['hasAudio'] == true,
    );
  }

  Future<int> probeAudioDuration(String path) async {
    final ms = await _channel.invokeMethod<int>('probeAudio', {'path': path});
    if (ms == null || ms <= 0) {
      throw const FormatException('That audio file could not be read.');
    }
    return ms;
  }

  /// Extracts evenly spaced JPEG frames into [outputDir].
  Future<ExtractedFrames> extractFrames({
    required String sourcePath,
    required String outputDir,
    required int fps,
    required int maxFrames,
    required int maxWidth,
    required int maxHeight,
    void Function(int done, int total)? onProgress,
  }) async {
    if (onProgress != null) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'extractionProgress' && call.arguments is Map) {
          final args = call.arguments as Map;
          onProgress(
            (args['done'] as num?)?.toInt() ?? 0,
            (args['total'] as num?)?.toInt() ?? 0,
          );
        }
        return null;
      });
    }
    try {
      final result = await _channel.invokeMapMethod<String, Object?>('extractFrames', {
        'sourcePath': sourcePath,
        'outputDir': outputDir,
        'fps': fps,
        'maxFrames': maxFrames,
        'maxWidth': maxWidth,
        'maxHeight': maxHeight,
        'framePattern': 'f%05d.jpg',
      });
      final count = (result?['count'] as num?)?.toInt() ?? 0;
      if (result == null || count <= 0) {
        throw const FormatException('No frames could be decoded from that video.');
      }
      return ExtractedFrames(
        count: count,
        width: (result['width'] as num?)?.toInt() ?? 0,
        height: (result['height'] as num?)?.toInt() ?? 0,
      );
    } finally {
      if (onProgress != null) _channel.setMethodCallHandler(null);
    }
  }

  Future<void> cancelExtraction() =>
      _channel.invokeMethod<void>('cancelExtraction');
}

/// Managed media storage with manifest IO and safe deletion.
class VideoMediaStore {
  VideoMediaStore({Directory? root}) : _rootOverride = root;

  final Directory? _rootOverride;
  Directory? _cachedRoot;

  bool get isSupported => !kIsWeb;

  Future<Directory> root() async {
    if (_rootOverride != null) return _rootOverride;
    final cached = _cachedRoot;
    if (cached != null) return cached;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/${MediaPaths.rootName}');
    if (!await dir.exists()) await dir.create(recursive: true);
    _cachedRoot = dir;
    return dir;
  }

  Future<Directory> projectDir(String projectId) async {
    final dir = Directory('${(await root()).path}/$projectId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> clipDir(String projectId, String assetId) async {
    final dir = Directory('${(await projectDir(projectId)).path}/clips/$assetId');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<void> writeClipManifest(String projectId, ClipManifest manifest) async {
    final dir = await clipDir(projectId, manifest.assetId);
    await File('${dir.path}/manifest.json').writeAsString(manifest.encode(), flush: true);
  }

  /// Returns `null` when the clip directory or manifest is missing, which the
  /// UI surfaces as "media missing" instead of failing to open the project.
  Future<ImportedClip?> loadClip(String projectId, String assetId) async {
    try {
      final dir = await clipDir(projectId, assetId);
      final manifest = File('${dir.path}/manifest.json');
      if (!await manifest.exists()) return null;
      final decoded = ClipManifest.decode(await manifest.readAsString());
      if (decoded.frameCount <= 0) return null;
      if (!await File('${dir.path}/${decoded.frameName(0)}').exists()) {
        return null;
      }
      return ImportedClip(manifest: decoded, directory: dir.path);
    } catch (_) {
      return null;
    }
  }

  Future<String> audioPath(String projectId, String assetId, String extension) async {
    final dir = Directory('${(await projectDir(projectId)).path}/audio');
    if (!await dir.exists()) await dir.create(recursive: true);
    final safeExt = extension.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
    return '${dir.path}/$assetId.${safeExt.isEmpty ? 'm4a' : safeExt}';
  }

  Future<ImportedAudio?> loadAudio(
    String projectId,
    String assetId, {
    String? title,
    int? durationMs,
  }) async {
    final dir = Directory('${(await projectDir(projectId)).path}/audio');
    if (!await dir.exists()) return null;
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!name.startsWith('$assetId.')) continue;
      return ImportedAudio(
        assetId: assetId,
        title: title ?? name,
        durationMs: durationMs ?? 0,
        path: entity.path,
      );
    }
    return null;
  }

  Future<void> deleteClip(String projectId, String assetId) async {
    try {
      final dir = Directory('${(await projectDir(projectId)).path}/clips/$assetId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Cleanup is best-effort; a stale directory is harmless.
    }
  }

  Future<void> deleteAllProjectMedia(String projectId) async {
    try {
      final dir = Directory('${(await root()).path}/$projectId');
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup.
    }
  }

  /// Bytes used by a project's managed media, for the storage panel.
  Future<int> projectBytes(String projectId) async {
    try {
      final dir = Directory('${(await root()).path}/$projectId');
      if (!await dir.exists()) return 0;
      var total = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) total += await entity.length();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }
}

/// Human-readable byte size (shared with the export sheet).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
