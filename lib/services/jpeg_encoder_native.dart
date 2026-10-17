import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> encodeJpeg(Uint8List png) => compute(_encode, png);

/// Real JPEG encoding, alpha-composited onto white, off the mobile UI isolate.
Uint8List _encode(Uint8List png) {
  final decoded = img.decodePng(png);
  if (decoded == null) {
    throw StateError('Could not decode the invitation for JPEG.');
  }
  final flattened = img.Image(
    width: decoded.width,
    height: decoded.height,
    numChannels: 3,
  );
  img.fill(flattened, color: img.ColorRgb8(255, 255, 255));
  img.compositeImage(flattened, decoded);
  return Uint8List.fromList(img.encodeJpg(flattened, quality: 95));
}
