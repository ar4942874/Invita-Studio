import 'package:flutter/material.dart';
import 'package:qr/qr.dart';

import '../studio_theme.dart';

/// Renders [data] as a QR code.
///
/// The encoder is pure Dart (`package:qr`), so the code is produced on the
/// device: no image service, no network, no data leaving the app. The modules
/// are painted directly, which keeps the code crisp at any size and avoids
/// shipping a second UI package for one square of black and white.
class QrCodeView extends StatelessWidget {
  const QrCodeView({
    super.key,
    required this.data,
    this.size = 160,
    this.foreground = const Color(0xFF221E19),
  });

  final String data;
  final double size;
  final Color foreground;

  /// Builds the module matrix, or `null` when the payload does not fit.
  static QrImage? imageFor(String data) {
    try {
      return QrImage(
        QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M),
      );
    } on Exception {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = imageFor(data);
    if (image == null) {
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(
            'This link is too long for a code.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: StudioColors.muted),
          ),
        ),
      );
    }
    return Semantics(
      label: 'QR code that opens $data',
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: StudioColors.border),
        ),
        child: CustomPaint(
          size: Size.square(size),
          painter: _QrPainter(image: image, foreground: foreground),
        ),
      ),
    );
  }
}

class _QrPainter extends CustomPainter {
  const _QrPainter({required this.image, required this.foreground});

  final QrImage image;
  final Color foreground;

  @override
  void paint(Canvas canvas, Size size) {
    final count = image.moduleCount;
    final module = size.width / count;
    final paint = Paint()..color = foreground;
    for (var row = 0; row < count; row++) {
      for (var column = 0; column < count; column++) {
        if (!image.isDark(row, column)) continue;
        // Half a pixel of bleed stops hairline gaps between modules.
        canvas.drawRect(
          Rect.fromLTWH(
            column * module,
            row * module,
            module + 0.5,
            module + 0.5,
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter oldDelegate) =>
      oldDelegate.image != image || oldDelegate.foreground != foreground;
}
