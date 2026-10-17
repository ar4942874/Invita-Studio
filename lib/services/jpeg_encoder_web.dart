import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

/// Use the browser's native JPEG encoder instead of shipping a large decoder.
Future<Uint8List> encodeJpeg(Uint8List png) async {
  final source = web.Blob(
    [png.toJS].toJS,
    web.BlobPropertyBag(type: 'image/png'),
  );
  final bitmap = await web.window.createImageBitmap(source).toDart;
  final canvas = web.HTMLCanvasElement()
    ..width = bitmap.width
    ..height = bitmap.height;
  try {
    final context = canvas.getContext('2d') as web.CanvasRenderingContext2D;
    context.fillStyle = '#ffffff'.toJS;
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(bitmap, 0, 0);
    final encoded = Completer<web.Blob>();
    canvas.toBlob(
      ((web.Blob? blob) {
        if (blob == null || blob.type != 'image/jpeg') {
          encoded.completeError(
            StateError('This browser could not encode JPEG. Try PNG.'),
          );
        } else {
          encoded.complete(blob);
        }
      }).toJS,
      'image/jpeg',
      .95.toJS,
    );
    final result = await encoded.future;
    return (await result.arrayBuffer().toDart).toDart.asUint8List();
  } finally {
    bitmap.close();
    canvas.width = 0;
    canvas.height = 0;
  }
}
