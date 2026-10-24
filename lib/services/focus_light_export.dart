import 'dart:typed_data';
import 'dart:ui' as ui;

import '../domain/focus_light.dart';

/// Paints the card's light onto an already-rendered PNG.
///
/// The editor's export comes from the canvas engine, which knows nothing about
/// lights, so the light is composited afterwards at full document resolution.
/// Painted by the same [paintFocusLight] the artboard and the video renderer
/// use, which is why the file matches the screen pixel for pixel.
///
/// Never throws: a card that cannot be re-encoded is still exported, just
/// without the light, because losing the invitation is worse than losing a
/// gradient.
Future<Uint8List> applyFocusLightToPng(
  Uint8List png,
  FocusLightSetting setting,
) async {
  if (setting.isOff || png.isEmpty) return png;
  ui.Codec? codec;
  ui.Image? image;
  ui.Image? composited;
  ui.Picture? picture;
  try {
    codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    image = frame.image;
    final size = ui.Size(image.width.toDouble(), image.height.toDouble());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawImage(image, ui.Offset.zero, ui.Paint());
    paintFocusLight(canvas, size, setting);
    picture = recorder.endRecording();
    composited = await picture.toImage(image.width, image.height);
    final data = await composited.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return png;
    return data.buffer.asUint8List();
  } catch (_) {
    return png;
  } finally {
    composited?.dispose();
    picture?.dispose();
    image?.dispose();
    codec?.dispose();
  }
}
