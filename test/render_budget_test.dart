import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/services/bundled_fonts.dart'
    show loadStudioFonts;
import 'package:invitation_studio/ui/widgets/document_preview.dart';

/// Guards the decode budget of the thumbnails the app draws everywhere.
///
/// The bundled artwork is a 2160 × 3024 asset (~26 MB decoded at full size).
/// The wizard draws ten previews at once and the panels draw them at 34–70 px,
/// so a preview must ask the image cache for a thumbnail-sized bitmap unless
/// the caller explicitly says it is showing one large.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);

  DesignDocument previewDocument() => catalogueTemplates.first.createDocument(
    documentId: 'budget',
    format: InvitationFormat.classic,
  );

  /// Pumps one preview and returns the resize the image cache was asked for.
  ///
  /// `cacheWidth` is not a field on [Image]: the named constructors wrap the
  /// provider in a [ResizeImage], which is what actually bounds the decode.
  Future<ResizeImage> pumpPreview(
    WidgetTester tester, {
    int? decodeWidth,
  }) async {
    final document = previewDocument();
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 120,
            child: decodeWidth == null
                ? DocumentPreview(document: document)
                : DocumentPreview(document: document, decodeWidth: decodeWidth),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final image = tester.widget<Image>(find.byType(Image).first);
    return image.image as ResizeImage;
  }

  testWidgets('a preview decodes its artwork as a thumbnail by default', (
    tester,
  ) async {
    final decode = await pumpPreview(tester);
    expect(decode.width, 420);
  });

  testWidgets('a caller that shows a large preview can raise the decode', (
    tester,
  ) async {
    final decode = await pumpPreview(tester, decodeWidth: 1080);
    expect(decode.width, 1080);
  });

  testWidgets('the decode size never changes the layout', (tester) async {
    // The preview lays the document out in document space and scales it with
    // FittedBox, so asking for a smaller bitmap must not move a single pixel.
    await pumpPreview(tester, decodeWidth: 180);
    final small = tester.getSize(find.byType(DocumentPreview));
    await pumpPreview(tester, decodeWidth: 1080);
    final large = tester.getSize(find.byType(DocumentPreview));
    expect(small, large);
  });
}
