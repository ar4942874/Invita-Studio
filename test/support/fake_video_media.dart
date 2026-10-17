import 'package:invitation_studio/services/video/video_media.dart';

/// A [VideoMediaService] that records which lookup happened and returns
/// canned results.
///
/// Shared by the export tests: the bug they guard against was a lookup routed
/// to the wrong map, so *which* method runs is the assertion.
class FakeVideoMedia implements VideoMediaService {
  FakeVideoMedia({this.tune, this.track});

  final ImportedAudio? tune;
  final ImportedAudio? track;
  int tuneLoads = 0;
  int trackLoads = 0;

  @override
  bool get isSupported => true;

  @override
  bool get isMusicSupported => true;

  @override
  Future<ImportedAudio?> loadBundledTune({
    required String projectId,
    required String assetId,
    String? title,
  }) async {
    tuneLoads++;
    return tune;
  }

  @override
  Future<ImportedAudio?> loadAudio(
    String projectId,
    String assetId, {
    String? title,
    int? durationMs,
  }) async {
    trackLoads++;
    return track;
  }

  @override
  Future<void> deleteAudio(ImportedAudio audio) async {}

  @override
  Future<void> deleteClip(String projectId, String assetId) async {}

  @override
  Future<ClipImportResult> extractClip({
    required String sourcePath,
    required String title,
    required String projectId,
    required String assetId,
    void Function(int done, int total)? onProgress,
  }) async => throw UnimplementedError();

  @override
  Future<void> cancelExtraction() async {}

  @override
  Future<ImportedClip?> loadClip(String projectId, String assetId) async => null;

  @override
  Future<int> projectBytes(String projectId) async => 0;

  @override
  Future<int> probeAudioDuration(String sourcePath) async => 0;

  @override
  Future<VideoProbe> probeVideo(String sourcePath) async =>
      throw UnimplementedError();

  @override
  Future<ImportedAudio?> importMusic({
    required String sourcePath,
    required String fileName,
    required String projectId,
    required String assetId,
  }) async => throw UnimplementedError();
}
