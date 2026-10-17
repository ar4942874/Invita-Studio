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
    // Some engines only emit canvas-capture frames while the canvas is attached
    // to the document, so keep it offscreen but rendered.
    canvas.setAttribute(
      'style',
      'position:fixed;left:-100000px;top:0;pointer-events:none;',
    );
    web.document.body?.appendChild(canvas);
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
    if (context == null) {
      canvas.remove();
      throw StateError('The browser could not create a 2D drawing surface.');
    }
    // Capture at the timeline frame rate. The exporter already paces frames at
    // real time, so the browser stamps each drawn frame with the right moment;
    // manual `requestFrame` capture is ignored by some browsers and produced a
    // still image there.
    final stream = canvas.captureStream(spec.fps);
    if (stream.getVideoTracks().toDart.isEmpty) {
      canvas.remove();
      throw StateError('The browser did not expose a canvas video track.');
    }
    final mime = _pickMimeType();
    final recorder = web.MediaRecorder(
      stream,
      web.MediaRecorderOptions(
        mimeType: mime,
        videoBitsPerSecond: spec.bitrate,
      ),
    );
    return _WebVideoEncoderSession(
      canvas: canvas,
      context: context,
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
    required this.canvas,
    required this.context,
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
  }

  final web.HTMLCanvasElement canvas;
  final web.CanvasRenderingContext2D context;
  final web.MediaRecorder recorder;
  final VideoEncodeSpec spec;
  final String mimeType;
  final List<web.Blob> chunks = <web.Blob>[];
  final Completer<void> _stop = Completer<void>();

  bool _started = false;

  /// Anchors timeline time to wall time; set once the recorder is live so the
  /// entrances are not compressed into the startup burst.
  DateTime? _clock;
  bool _closed = false;

  @override
  Future<void> addFrame(Uint8List rgba, int timestampUs) async {
    if (_closed) throw StateError('Encoder session is closed.');
    if (!_started) {
      _started = true;
      // Paint the first frame before the recorder goes live, so the video never
      // opens on a blank canvas. The recorder warms up while that frame is on
      // screen and the next frame is rendered.
      _draw(rgba);
      recorder.start();
      _clock = DateTime.now();
      return;
    }
    // Drive the recorder at real time so the browser stamps correct durations.
    final target = _clock!.add(Duration(microseconds: timestampUs));
    final delay = target.difference(DateTime.now());
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    _draw(rgba);
  }

  void _draw(Uint8List rgba) {
    final clamped = Uint8ClampedList.view(
      rgba.buffer,
      rgba.offsetInBytes,
      rgba.lengthInBytes,
    );
    context.putImageData(web.ImageData(clamped.toJS, spec.width), 0, 0);
  }

  @override
  Future<EncodedVideo> finish() async {
    if (_closed) throw StateError('Encoder session is closed.');
    _closed = true;
    if (_started) {
      // Give the auto-capturing recorder a moment to grab the final frame
      // before the stream stops.
      if (recorder.state != 'inactive') {
        await Future<void>.delayed(const Duration(milliseconds: 140));
        recorder.stop();
      }
      if (!_stop.isCompleted) await _stop.future;
    }
    _releaseCanvas();
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
    _releaseCanvas();
    chunks.clear();
  }

  void _releaseCanvas() {
    canvas.width = 0;
    canvas.height = 0;
    canvas.remove();
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
