import '../../domain/video/timeline.dart';
import 'video_audio_player.dart';
import 'video_media.dart';

/// Native builds have no audio-playback dependency, so the preview is silent.
///
/// The exported video still contains the music: the Android/iOS encoder muxes
/// it directly from the source file.
VideoAudioPlayer createVideoAudioPlayer() => const NoopVideoAudioPlayer();

class NoopVideoAudioPlayer implements VideoAudioPlayer {
  const NoopVideoAudioPlayer();

  @override
  bool get isSupported => false;

  @override
  void configure({
    ImportedAudio? audio,
    VideoAudio? settings,
    required int timelineDurationMs,
  }) {}

  @override
  void update({required int positionMs, required bool playing}) {}

  @override
  void dispose() {}
}
