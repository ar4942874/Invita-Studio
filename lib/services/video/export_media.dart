import '../../domain/category_music.dart';
import '../../domain/video/timeline.dart';
import 'video_media.dart';

/// Whether an export has to resolve the music file before it can start.
///
/// Two cases deliberately do not need it:
/// * the browser records a silent video, so a missing file cannot change the
///   output (and the browser store holds no imported audio after a reload);
/// * a muted track is written as an MP4 with no audio track at all.
///
/// Requiring the file in those cases is what turned a first run into
/// "The music file for this draft is missing": every project the wizard creates
/// starts with a bundled tune, and the browser store keeps tunes in a different
/// map from imported music.
bool exportNeedsAudio(VideoAudio? audio, {required bool isWeb}) =>
    !isWeb && audio != null && !audio.isMuted;

/// Loads the music an export will mux, or `null` when none is needed.
///
/// Bundled category tunes (`tune_*`) live in the app bundle and are resolved
/// with [VideoMediaService.loadBundledTune]; imported music is looked up in the
/// project's managed storage. A bundled tune cannot be missing, so a project
/// created from the wizard can always export on native with no import step.
Future<ImportedAudio?> resolveExportAudio({
  required VideoMediaService media,
  required String projectId,
  required VideoAudio? audio,
  required bool isWeb,
}) async {
  final track = audio;
  if (track == null || !exportNeedsAudio(track, isWeb: isWeb)) return null;
  if (CategoryMusic.isTune(track.assetId)) {
    return media.loadBundledTune(
      projectId: projectId,
      assetId: track.assetId,
      title: track.title,
    );
  }
  return media.loadAudio(
    projectId,
    track.assetId,
    title: track.title,
    durationMs: track.durationMs > 0 ? track.durationMs : null,
  );
}
