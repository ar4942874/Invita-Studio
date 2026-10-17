import 'video_encoder.dart';

/// Native (Android/iOS/desktop) default: the platform MethodChannel encoder.
VideoEncoderBackend createVideoEncoderBackend() => NativeVideoEncoderBackend();
