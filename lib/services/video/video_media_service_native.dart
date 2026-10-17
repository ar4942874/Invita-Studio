import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../../domain/category_music.dart';
import 'video_media.dart';

/// Native default: platform codecs probe and extract the clip, and the managed
/// store keeps the frames on disk.
VideoMediaService createVideoMediaService() => NativeVideoMediaService();

class NativeVideoMediaService implements VideoMediaService {
  NativeVideoMediaService({VideoMediaStore? store, VideoMediaChannel? channel})
    : _store = store ?? VideoMediaStore(),
      _channel = channel ?? VideoMediaChannel();

  final VideoMediaStore _store;
  final VideoMediaChannel _channel;

  @override
  bool get isSupported => _channel.isSupported;

  @override
  bool get isMusicSupported => _channel.isSupported;

  @override
  Future<VideoProbe> probeVideo(String sourcePath) =>
      _channel.probeVideo(sourcePath);

  @override
  Future<ClipImportResult> extractClip({
    required String sourcePath,
    required String title,
    required String projectId,
    required String assetId,
    void Function(int done, int total)? onProgress,
  }) async {
    final probe = await _channel.probeVideo(sourcePath);
    if (probe.durationMs <= 0 || probe.width <= 0) {
      throw const FormatException('That file is not a readable video.');
    }
    final dir = await _store.clipDir(projectId, assetId);
    final extracted = await _channel.extractFrames(
      sourcePath: sourcePath,
      outputDir: dir.path,
      fps: ClipLimits.extractionFps,
      maxFrames: ClipLimits.maxFrames,
      maxWidth: ClipLimits.maxWidth,
      maxHeight: ClipLimits.maxHeight,
      onProgress: onProgress,
    );
    final manifest = ClipManifest(
      assetId: assetId,
      title: title,
      sourceDurationMs: probe.durationMs,
      sourceWidth: probe.width,
      sourceHeight: probe.height,
      fps: ClipLimits.extractionFps,
      frameWidth: extracted.width,
      frameHeight: extracted.height,
      frameCount: extracted.count,
      framePattern: 'f%05d.jpg',
      hasAudio: probe.hasAudio,
    );
    await _store.writeClipManifest(projectId, manifest);
    return ClipImportResult(
      manifest: manifest,
      clip: ImportedClip(manifest: manifest, directory: dir.path),
    );
  }

  @override
  Future<void> cancelExtraction() => _channel.cancelExtraction();

  @override
  Future<ImportedClip?> loadClip(String projectId, String assetId) =>
      _store.loadClip(projectId, assetId);

  @override
  Future<ImportedAudio?> loadAudio(
    String projectId,
    String assetId, {
    String? title,
    int? durationMs,
  }) => _store.loadAudio(
    projectId,
    assetId,
    title: title,
    durationMs: durationMs,
  );

  @override
  Future<void> deleteClip(String projectId, String assetId) =>
      _store.deleteClip(projectId, assetId);

  @override
  Future<int> projectBytes(String projectId) => _store.projectBytes(projectId);

  @override
  Future<int> probeAudioDuration(String sourcePath) =>
      _channel.probeAudioDuration(sourcePath);

  @override
  Future<ImportedAudio?> importMusic({
    required String sourcePath,
    required String fileName,
    required String projectId,
    required String assetId,
  }) async {
    final durationMs = await _channel.probeAudioDuration(sourcePath);
    final extension = fileName.contains('.') ? fileName.split('.').last : 'm4a';
    final path = await _store.audioPath(projectId, assetId, extension);
    await File(sourcePath).copy(path);
    return ImportedAudio(
      assetId: assetId,
      title: fileName,
      durationMs: durationMs,
      path: path,
    );
  }

  @override
  Future<ImportedAudio?> loadBundledTune({
    required String projectId,
    required String assetId,
    String? title,
    int durationMs = 0,
  }) async {
    final path = await _store.audioPath(projectId, assetId, 'wav');
    final file = File(path);
    if (!await file.exists()) {
      final data = await rootBundle.load(
        '${CategoryMusic.folder}/$assetId.wav',
      );
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
    }
    return ImportedAudio(
      assetId: assetId,
      title: title ?? assetId,
      durationMs: durationMs,
      path: path,
    );
  }

  @override
  Future<void> deleteAudio(ImportedAudio audio) async {
    try {
      await File(audio.path).delete();
    } catch (_) {
      // Best-effort; a stale file is harmless.
    }
  }
}
