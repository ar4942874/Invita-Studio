import 'package:flutter/foundation.dart';

import 'jpeg_encoder.dart';

import '../application/studio_controller.dart';

enum ImageFormat { png, jpeg }

class ExportedFile {
  const ExportedFile({
    required this.bytes,
    required this.name,
    required this.mime,
    required this.width,
    required this.height,
  });
  final Uint8List bytes;
  final String name, mime;
  final int width, height;
  String get sizeLabel => bytes.length >= 1024 * 1024
      ? '${(bytes.length / (1024 * 1024)).toStringAsFixed(1)} MB'
      : '${(bytes.length / 1024).ceil()} KB';
}

class ExportService {
  static Future<ExportedFile> render(
    StudioController studio, {
    required ImageFormat format,
    required int scale,
  }) async {
    if (scale != 1 && scale != 2) {
      throw ArgumentError('Choose 1× or 2× export.');
    }
    await studio.flush();
    final doc = studio.document;
    final title = studio.project.title;
    final png = await studio.editor.exportToPng(pixelRatio: scale.toDouble());
    final bytes = format == ImageFormat.png ? png : await encodeJpeg(png);
    final slug = title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final ext = format == ImageFormat.png ? 'png' : 'jpg';
    return ExportedFile(
      bytes: bytes,
      name:
          '${slug.isEmpty ? 'invitation' : slug}-${(doc.width * scale).toInt()}x${(doc.height * scale).toInt()}.$ext',
      mime: format == ImageFormat.png ? 'image/png' : 'image/jpeg',
      width: (doc.width * scale).round(),
      height: (doc.height * scale).round(),
    );
  }
}
