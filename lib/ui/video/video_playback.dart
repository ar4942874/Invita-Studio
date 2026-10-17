import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Wall-clock playback for the interactive preview only.
///
/// Exports never use this clock: the exporter derives every timestamp from the
/// frame index, so export timing is independent of device speed.
class VideoPlaybackController extends ChangeNotifier {
  VideoPlaybackController({
    required TickerProvider vsync,
    required int durationMs,
    this.loop = true,
  }) : _durationMs = durationMs {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  final bool loop;

  int _durationMs;
  int _positionMs = 0;
  bool _playing = false;
  int _startPositionMs = 0;
  Duration _lastElapsed = Duration.zero;

  int get durationMs => _durationMs;
  int get positionMs => _positionMs;
  bool get playing => _playing;

  double get fraction => _durationMs <= 0 ? 0 : _positionMs / _durationMs;

  String get timecode => formatTimecode(_positionMs);
  String get durationTimecode => formatTimecode(_durationMs);

  void setDuration(int value) {
    _durationMs = value.clamp(1, 600000).toInt();
    if (_positionMs > _durationMs) _positionMs = _durationMs;
    notifyListeners();
  }

  void play() {
    if (_playing) return;
    if (_positionMs >= _durationMs) _positionMs = 0;
    _playing = true;
    _startPositionMs = _positionMs;
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
    _positionMs = ms.clamp(0, _durationMs).toInt();
    _startPositionMs = _positionMs;
    _lastElapsed = Duration.zero;
    notifyListeners();
  }

  void _onTick(Duration elapsed) {
    final delta = (elapsed - _lastElapsed).inMilliseconds;
    if (delta <= 0) return;
    _lastElapsed = elapsed;
    var next = _positionMs + delta;
    if (next >= _durationMs) {
      if (loop) {
        next %= _durationMs;
        _startPositionMs = 0;
        _lastElapsed = elapsed;
      } else {
        next = _durationMs;
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
