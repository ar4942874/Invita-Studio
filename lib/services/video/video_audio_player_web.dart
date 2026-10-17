import 'package:web/web.dart' as web;

import '../../domain/video/timeline.dart';
import 'video_audio_player.dart';
import 'video_media.dart';

VideoAudioPlayer createVideoAudioPlayer() => WebVideoAudioPlayer();

/// Drives an `<audio>` element in step with the preview transport.
///
/// The element loops nothing on its own; [update] keeps it within a small drift
/// window of the timeline and applies the volume plus fade-in/fade-out envelope
/// so the web preview matches the exported mix.
class WebVideoAudioPlayer implements VideoAudioPlayer {
  web.HTMLAudioElement? _element;
  VideoAudio? _settings;
  int _timelineDurationMs = 0;
  String? _url;

  @override
  bool get isSupported => true;

  @override
  void configure({
    ImportedAudio? audio,
    VideoAudio? settings,
    required int timelineDurationMs,
  }) {
    _timelineDurationMs = timelineDurationMs;
    _settings = settings;
    final url = audio?.url;
    if (url == null) {
      _clear();
      return;
    }
    if (url != _url) {
      _clear();
      final element = web.HTMLAudioElement()
        ..src = url
        ..preload = 'auto';
      element.load();
      _element = element;
      _url = url;
    }
  }

  @override
  void update({required int positionMs, required bool playing}) {
    final element = _element;
    final settings = _settings;
    if (element == null || settings == null) return;
    if (settings.isMuted || positionMs < settings.startMs) {
      if (!element.paused) element.pause();
      return;
    }
    final targetSeconds = (positionMs - settings.startMs) / 1000;
    if ((element.currentTime - targetSeconds).abs() > 0.35) {
      try {
        element.currentTime = targetSeconds;
      } catch (_) {
        // Metadata is not ready yet; the next tick retries.
      }
    }
    element.volume = _gain(positionMs, settings).clamp(0.0, 1.0).toDouble();
    if (playing) {
      if (element.paused) {
        element.play();
      }
    } else if (!element.paused) {
      element.pause();
    }
  }

  double _gain(int positionMs, VideoAudio settings) {
    var gain = settings.volume / 100;
    final local = positionMs - settings.startMs;
    if (local < 0) return 0;
    final fadeIn = settings.fadeInMs;
    if (fadeIn > 0 && local < fadeIn) gain *= local / fadeIn;
    final length = _usedLengthMs(settings);
    final end =
        settings.startMs +
        (length > 0 ? length : (_timelineDurationMs - settings.startMs));
    final fadeOut = settings.fadeOutMs;
    final toEnd = end - positionMs;
    if (fadeOut > 0 && toEnd < fadeOut) {
      gain *= (toEnd / fadeOut).clamp(0.0, 1.0);
    }
    return gain.clamp(0.0, 1.0).toDouble();
  }

  int _usedLengthMs(VideoAudio settings) {
    final trimEnd = settings.trimEndMs > 0
        ? settings.trimEndMs
        : settings.durationMs;
    final length = trimEnd - settings.trimStartMs;
    return length > 0 ? length : 0;
  }

  void _clear() {
    final element = _element;
    if (element != null) {
      element.pause();
      element.removeAttribute('src');
      element.load();
    }
    _element = null;
    _url = null;
  }

  @override
  void dispose() => _clear();
}
