import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A finished encode: where it lives and how big it is.
///
/// Native backends return an absolute file path; the browser backend returns a
/// suggested file name (the bytes are handed to the download helper instead).
class EncodedVideo {
  const EncodedVideo({required this.path, required this.bytes});
  final String path;
  final int bytes;
}

/// Audio settings handed to the native muxer with the video track.
class EncoderAudioSpec {
  const EncoderAudioSpec({
    required this.path,
    required this.startMs,
    required this.trimStartMs,
    required this.trimEndMs,
    required this.volume,
    required this.fadeInMs,
    required this.fadeOutMs,
    required this.durationMs,
  });

  final String path;

  /// Where the music starts on the video timeline.
  final int startMs;
  final int trimStartMs;

  /// Zero means "to the end of the source file".
  final int trimEndMs;

  /// 0..100, linear gain.
  final int volume;
  final int fadeInMs;
  final int fadeOutMs;
  final int durationMs;

  Map<String, Object?> toMap() => {
    'path': path,
    'startMs': startMs,
    'trimStartMs': trimStartMs,
    'trimEndMs': trimEndMs,
    'volume': volume,
    'fadeInMs': fadeInMs,
    'fadeOutMs': fadeOutMs,
    'durationMs': durationMs,
  };
}

class VideoEncodeSpec {
  const VideoEncodeSpec({
    required this.outputPath,
    required this.width,
    required this.height,
    required this.fps,
    required this.frameCount,
    this.bitrate = 8000000,
    this.audio,
  });

  final String outputPath;
  final int width;
  final int height;
  final int fps;
  final int frameCount;

  /// H.264 target bitrate in bits per second.
  final int bitrate;

  /// `null` produces a silent MP4 with no audio track (explicit, not implicit).
  final EncoderAudioSpec? audio;

  Map<String, Object?> toMap() => {
    'outputPath': outputPath,
    'width': width,
    'height': height,
    'fps': fps,
    'frameCount': frameCount,
    'bitrate': bitrate,
    'audio': audio?.toMap(),
  };
}

/// One open encoder session. Frames are RGBA8888 in document resolution.
abstract class VideoEncoderSession {
  Future<void> addFrame(Uint8List rgba, int timestampUs);
  Future<EncodedVideo> finish();
  Future<void> cancel();
}

/// Backend abstraction: the app talks only to this interface, so platform
/// support is explicit and testable with a fake.
abstract class VideoEncoderBackend {
  bool get isSupported;

  /// Human-readable reason shown when [isSupported] is false.
  String get unsupportedReason;

  Future<VideoEncoderSession> open(VideoEncodeSpec spec);
}

/// Method-channel backend implemented in `MainActivity` (Kotlin/MediaCodec) and
/// `AppDelegate` (Swift/AVAssetWriter).
class NativeVideoEncoderBackend implements VideoEncoderBackend {
  NativeVideoEncoderBackend({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('invita/video_export');

  final MethodChannel _channel;

  @override
  bool get isSupported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  @override
  String get unsupportedReason {
    if (kIsWeb) {
      return 'The browser build can preview video invitations but cannot encode MP4. '
          'Open the project in the Android or iOS app to export.';
    }
    return 'MP4 export uses the platform H.264 encoder and is available on Android and iOS. '
        'This desktop build can preview and edit the video but cannot encode it.';
  }

  @override
  Future<VideoEncoderSession> open(VideoEncodeSpec spec) async {
    if (!isSupported) {
      throw UnsupportedError(unsupportedReason);
    }
    final sessionId = await _channel.invokeMethod<String>('open', spec.toMap());
    if (sessionId == null || sessionId.isEmpty) {
      throw StateError('The platform encoder did not start.');
    }
    return _NativeSession(_channel, sessionId);
  }
}

class _NativeSession implements VideoEncoderSession {
  _NativeSession(this._channel, this._id);

  final MethodChannel _channel;
  final String _id;
  bool _closed = false;

  @override
  Future<void> addFrame(Uint8List rgba, int timestampUs) async {
    if (_closed) throw StateError('Encoder session is closed.');
    await _channel.invokeMethod<void>('addFrame', {
      'sessionId': _id,
      'timestampUs': timestampUs,
      'bytes': rgba,
    });
  }

  @override
  Future<EncodedVideo> finish() async {
    if (_closed) throw StateError('Encoder session is closed.');
    _closed = true;
    final path = await _channel.invokeMethod<String>('finish', {
      'sessionId': _id,
    });
    if (path == null || path.isEmpty) {
      throw StateError('The encoder did not produce a file.');
    }
    final bytes = await File(path).length();
    return EncodedVideo(path: path, bytes: bytes);
  }

  @override
  Future<void> cancel() async {
    if (_closed) return;
    _closed = true;
    try {
      await _channel.invokeMethod<void>('cancel', {'sessionId': _id});
    } on PlatformException {
      // Cancelling an already-failed session is fine.
    }
  }
}
