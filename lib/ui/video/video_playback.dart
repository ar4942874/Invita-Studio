import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Wall-clock playback for the interactive preview only.
///
/// Exports never use this clock: the exporter derives every timestamp from the
/// frame index, so export timing is independent of device speed.
class VideoPlaybackController extends ChangeNotifier {
  VideoPlaybackController({
    required TickerProvider vsync,
    required this.durationMs,
    this.loop = true,
  }) {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  final bool loop;

  int durationMs;
  int _positionMs = 0;
  bool _playing = false;
  Duration _lastElapsed = Duration.zero;

  int get positionMs => _positionMs;
  bool get playing => _playing;

  double get fraction => durationMs <= 0 ? 0 : _positionMs / durationMs;

  String get timecode => formatTimecode(_positionMs);
  String get durationTimecode => formatTimecode(durationMs);

  void setDuration(int value) {
    durationMs = value.clamp(1, 600000).toInt();
    if (_positionMs > durationMs) _positionMs = durationMs;
    notifyListeners();
  }

  void play() {
    if (_playing) return;
    if (_positionMs >= durationMs) _positionMs = 0;
    _playing = true;
    _lastElapsed = Duration.zero;
    _ticker.start();
    notifyListeners();
  }

  void pause() {
    if (!_playing) return;
    _ticker.stop();
    _playing = false;
    notifyListeners();
  }

  void toggle() => _playing ? pause() : play();

  void seek(int ms) {
    _positionMs = ms.clamp(0, durationMs).toInt();
    _lastElapsed = Duration.zero;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastElapsed).inMilliseconds;
    if (delta <= 0) return;
    _lastElapsed = elapsed;
    var next = _positionMs + delta;
    if (next >= durationMs) {
      if (loop) {
        next %= durationMs;
        _lastElapsed = elapsed;
      } else {
        next = durationMs;
        _ticker.stop();
        _playing = false;
      }
    }
    _positionMs = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}

String formatTimecode(int milliseconds) {
  final totalSeconds = milliseconds ~/ 1000;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  final tenths = ((milliseconds % 1000) ~/ 100).toString();
  return '$minutes:$seconds.$tenths';
}
