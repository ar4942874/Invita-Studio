import '../../domain/video/timeline.dart';
import 'video_media.dart';

/// Plays the imported music during the interactive preview.
///
/// Only the browser implements playback: native builds return a no-op because
/// the project carries no audio-playback dependency. The exporter is
/// unaffected — native muxes the music in the platform encoder, while the
/// browser export is silent.
abstract class VideoAudioPlayer {
  bool get isSupported;

  /// Points the player at [audio] (or clears it when null) with the current
  /// timeline [settings] and total [timelineDurationMs].
  void configure({
    ImportedAudio? audio,
    VideoAudio? settings,
    required int timelineDurationMs,
  });

  /// Aligns playback with the transport: [positionMs] on the invitation
  /// timeline and whether it is currently playing.
  void update({required int positionMs, required bool playing});

  void dispose();
}
