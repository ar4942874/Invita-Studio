import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../file_actions.dart';
import 'video_encoder.dart';

/// Browser default: record the rendered canvas through `MediaRecorder` and hand
/// the resulting blob to the download helper.
///
/// The recorder captures a silent video (audio muxing stays native-only) and
/// produces WebM on Chromium/Firefox or MP4 on Safari and newer Chromium.
VideoEncoderBackend createVideoEncoderBackend() => WebVideoEncoderBackend();

class WebVideoEncoderBackend implements VideoEncoderBackend {
  @override
  bool get isSupported =>
      web.MediaRecorder.isTypeSupported('video/webm') ||
      web.MediaRecorder.isTypeSupported('video/mp4');

  @override
  String get unsupportedReason =>
      'This browser cannot record video. Try the latest Chrome, Edge, Firefox '
      'or Safari to export from the browser.';

  @override
  Future<VideoEncoderSession> open(VideoEncodeSpec spec) async {
    final canvas = web.HTMLCanvasElement()
      ..width = spec.width
      ..height = spec.height;
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) {
      throw StateError('The browser could not create a 2D drawing surface.');
    }
    final stream = canvas.captureStream(0);
    final tracks = stream.getVideoTracks().toDart;
    if (tracks.isEmpty) {
      throw StateError('The browser did not expose a canvas video track.');
    }
    final track = tracks.first as web.CanvasCaptureMediaStreamTrack;
    final mime = _pickMimeType();
    final recorder = web.MediaRecorder(
      stream,
      web.MediaRecorderOptions(
        mimeType: mime,
        videoBitsPerSecond: spec.bitrate,
      ),
    );
    return _WebVideoEncoderSession(
      context: context,
      track: track,
      recorder: recorder,
      spec: spec,
      mimeType: mime,
    );
  }

  static String _pickMimeType() {
    const candidates = [
      'video/webm;codecs=vp9',
      'video/webm;codecs=vp8',
      'video/webm',
      'video/mp4',
    ];
    for (final candidate in candidates) {
      if (web.MediaRecorder.isTypeSupported(candidate)) return candidate;
    }
    // Let the browser choose; the blob type reports what it settled on.
    return '';
  }
}

class _WebVideoEncoderSession implements VideoEncoderSession {
  _WebVideoEncoderSession({
    required this.context,
    required this.track,
    required this.recorder,
    required this.spec,
    required this.mimeType,
  }) {
    recorder.ondataavailable = ((web.BlobEvent event) {
      if (event.data.size > 0) chunks.add(event.data);
    }).toJS;
    recorder.onstop = ((web.Event event) {
      if (!_stop.isCompleted) _stop.complete();
    }).toJS;
    recorder.onerror = ((web.Event event) {
      if (!_stop.isCompleted) {
        _stop.completeError(StateError('The browser recorder failed.'));
      }
    }).toJS;
    _startedAt = DateTime.now();
    recorder.start();
  }

  final web.CanvasRenderingContext2D context;
  final web.CanvasCaptureMediaStreamTrack track;
  final web.MediaRecorder recorder;
  final VideoEncodeSpec spec;
  final String mimeType;
  final List<web.Blob> chunks = <web.Blob>[];
  final Completer<void> _stop = Completer<void>();
  late final DateTime _startedAt;
  bool _closed = false;

  @override
  Future<void> addFrame(Uint8List rgba, int timestampUs) async {
    if (_closed) throw StateError('Encoder session is closed.');
    // Drive the recorder at real time so the browser stamps correct durations.
    final target = _startedAt.add(Duration(microseconds: timestampUs));
    final delay = target.difference(DateTime.now());
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    final clamped = Uint8ClampedList.view(
      rgba.buffer,
      rgba.offsetInBytes,
      rgba.lengthInBytes,
    );
    final image = web.ImageData(clamped.toJS, spec.width);
    context.putImageData(image, 0, 0);
    track.requestFrame();
  }

  @override
  Future<EncodedVideo> finish() async {
    if (_closed) throw StateError('Encoder session is closed.');
    _closed = true;
    if (recorder.state != 'inactive') recorder.stop();
    if (!_stop.isCompleted) await _stop.future;
    if (chunks.isEmpty) {
      throw StateError('The browser recorder captured no video data.');
    }
    final type = _blobType();
    final blob = web.Blob(chunks.toJS, web.BlobPropertyBag(type: type));
    final buffer = (await blob.arrayBuffer().toDart).toDart;
    final bytes = buffer.asUint8List();
    final name = _outputName(type);
    await saveBytes(bytes, name, type);
    return EncodedVideo(path: name, bytes: bytes.length);
  }

  @override
  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    try {
      if (recorder.state != 'inactive') recorder.stop();
    } catch (_) {
      // Stopping an already-failed recorder is a no-op.
    }
    chunks.clear();
  }

  String _blobType() {
    if (mimeType.isNotEmpty) return mimeType;
    final first = chunks.first;
    return first.type.isEmpty ? 'video/webm' : first.type;
  }

  String _outputName(String type) {
    final base = spec.outputPath.isEmpty ? 'invitation' : spec.outputPath;
    final extension = type.contains('mp4') ? 'mp4' : 'webm';
    final dot = base.lastIndexOf('.');
    final stem = dot > 0 ? base.substring(0, dot) : base;
    return '$stem.$extension';
  }
}
