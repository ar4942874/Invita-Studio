import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../../domain/invitation_template.dart';
import '../../services/photo_service.dart';

BoxFit boxFitFromName(String fit) => switch (fit) {
  'contain' => BoxFit.contain,
  'fill' => BoxFit.fill,
  _ => BoxFit.cover,
};

Widget _photoImage(ImageNode node) {
  final bytes = photoBytesFromDataUrl(node.assetId);
  if (bytes == null) {
    return const ColoredBox(
      color: Color(0x11000000),
      child: Icon(Icons.broken_image_outlined, size: 20),
    );
  }
  return Image.memory(
    bytes,
    fit: boxFitFromName(node.fit),
    gaplessPlayback: true,
  );
}

/// Lightweight, noninteractive thumbnail of the actual editable document.
class DocumentPreview extends StatelessWidget {
  const DocumentPreview({super.key, required this.document});
  final DesignDocument document;
  @override
  Widget build(BuildContext context) {
    final sorted = [...document.nodes]
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    return MediaQuery.withNoTextScaling(
      child: AspectRatio(
        aspectRatio: document.width / document.height,
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: document.width,
            height: document.height,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (final node in sorted)
                  if (node is BackgroundNode)
                    Positioned.fill(
                      child: Image.asset(node.assetId!, fit: BoxFit.fill),
                    )
                  else if (node is TextNode)
                    Positioned.fromRect(
                      rect: node.frame,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: Transform(
                          alignment: Alignment.center,
                          transform: Matrix4.identity()
                            ..rotateZ(node.rotation * math.pi / 180)
                            ..multiply(
                              Matrix4.diagonal3Values(
                                node.scaleX,
                                node.scaleY,
                                1,
                              ),
                            ),
                          child: Text(
                            node.text,
                            textAlign: switch (node.textAlign) {
                              'center' => TextAlign.center,
                              'right' => TextAlign.right,
                              _ => TextAlign.left,
                            },
                            textDirection: invitationTextDirection(node.text),
                            style: nodeTextStyle(node).copyWith(
                              color: decodeDocumentColor(node.textColor),
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (node is ImageNode)
                    Positioned.fromRect(
                      rect: node.frame,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..rotateZ(node.rotation * math.pi / 180)
                          ..multiply(
                            Matrix4.diagonal3Values(
                              node.scaleX,
                              node.scaleY,
                              1,
                            ),
                          ),
                        child: ClipRect(
                          child: _photoImage(node),
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
