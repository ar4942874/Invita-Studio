import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/services/bundled_fonts.dart'
    show loadStudioFonts;
import 'package:invitation_studio/services/draft_store.dart';
import 'package:invitation_studio/services/export_service.dart';
import 'package:invitation_studio/services/jpeg_encoder.dart';

class GatedImage extends ImageProvider<GatedImage> {
  GatedImage(this.image);
  final Completer<ui.Image> image;
  @override
  Future<GatedImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);
  @override
  ImageStreamCompleter loadImage(GatedImage key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(
        image.future.then((value) => ImageInfo(image: value)),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);
  tearDown(() {
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  });

  test('PNG 2x is high resolution; selection never appears; repeated exports keep assets alive', () async {
    final studio = StudioController(
      project: StudioProject.sample(),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);
    final first = await ExportService.render(
      studio,
      format: ImageFormat.png,
      scale: 2,
    );
    expect(first.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
    final image = img.decodePng(first.bytes)!;
    expect([image.width, image.height], [2160, 3024]);
    studio.selectLayer('first');
    await Future<void>.delayed(Duration.zero);
    final selected = await ExportService.render(
      studio,
      format: ImageFormat.png,
      scale: 2,
    );
    expect(
      listEquals(first.bytes, selected.bytes),
      isTrue,
      reason: 'Export must not include selection handles.',
    );
    final folder = Directory('artifacts/samples');
    await folder.create(recursive: true);
    await File('${folder.path}/botanical-2160x3024.png')
        .writeAsBytes(first.bytes);
  });
  test('JPEG is genuine JPEG at story 2x dimensions', () async {
    final studio = StudioController(
      project: StudioProject.sample(),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);
    await studio.chooseTemplate(invitationTemplates[1]);
    await studio.chooseFormat(InvitationFormat.story);
    await studio.flush();
    final file = await ExportService.render(
      studio,
      format: ImageFormat.jpeg,
      scale: 2,
    );
    expect(file.bytes.take(3), [255, 216, 255]);
    expect(file.mime, 'image/jpeg');
    expect(file.name, endsWith('.jpg'));
    final image = img.decodeJpg(file.bytes)!;
    expect([image.width, image.height], [2160, 3840]);
    final folder = Directory('artifacts/samples');
    await folder.create(recursive: true);
    await File('${folder.path}/midnight-story-2160x3840.jpg')
        .writeAsBytes(file.bytes);
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('JPEG flattens transparent pixels onto white', () async {
    final transparent = img.Image(width: 8, height: 8, numChannels: 4);
    final bytes = await encodeJpeg(
      Uint8List.fromList(img.encodePng(transparent)),
    );
    final pixel = img.decodeJpg(bytes)!.getPixel(0, 0);
    expect(pixel.r, greaterThan(250));
    expect(pixel.g, greaterThan(250));
    expect(pixel.b, greaterThan(250));
  });
  test('export freezes the full document before waiting for images', () async {
    final gate = Completer<ui.Image>();
    final provider = GatedImage(gate);
    final controller = CanvasEditorController(
      initialDocument: const DesignDocument(
        id: 'snapshot',
        version: 1,
        width: 100,
        height: 100,
        nodes: [
          BackgroundNode(
            id: 'bg',
            frame: Rect.fromLTWH(0, 0, 100, 100),
            zIndex: 0,
            color: '#FFFFFFFF',
            assetId: 'gated',
          ),
        ],
      ),
      imageProvider: (_) => provider,
    );
    addTearDown(controller.dispose);
    final future = controller.exportToPng(pixelRatio: 1);
    await Future<void>.delayed(Duration.zero);
    await controller.applyDocument(
      const DesignDocument(
        id: 'snapshot',
        version: 1,
        width: 200,
        height: 100,
        nodes: [
          BackgroundNode(
            id: 'bg',
            frame: Rect.fromLTWH(0, 0, 200, 100),
            zIndex: 0,
            color: '#FF0000FF',
          ),
        ],
      ),
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawColor(const Color(0xFFFF0000), BlendMode.src);
    final picture = recorder.endRecording();
    gate.complete(await picture.toImage(10, 10));
    picture.dispose();
    final decoded = img.decodePng(await future)!;
    expect([decoded.width, decoded.height], [100, 100]);
    expect(decoded.getPixel(50, 50).r, 255);
    expect(decoded.getPixel(50, 50).b, 0);
  });
  test(
    'missing assets fail loudly rather than exporting a blank placeholder',
    () async {
      final controller = CanvasEditorController(
        initialDocument: const DesignDocument(
          id: 'missing',
          version: 1,
          width: 100,
          height: 100,
          nodes: [
            BackgroundNode(
              id: 'bg',
              frame: Rect.fromLTWH(0, 0, 100, 100),
              zIndex: 0,
              color: '#FFFFFFFF',
              assetId: 'missing',
            ),
          ],
        ),
        imageProvider: (_) => throw StateError('Missing image'),
      );
      addTearDown(controller.dispose);
      await expectLater(
        controller.exportToPng(pixelRatio: 1),
        throwsStateError,
      );
    },
  );
  test('export rejects unsafe dimensions and invalid scales', () async {
    final controller = CanvasEditorController();
    addTearDown(controller.dispose);
    for (final ratio in [0.0, -1.0, double.nan, double.infinity, 10000.0]) {
      await expectLater(
        controller.exportToPng(pixelRatio: ratio),
        throwsArgumentError,
      );
    }
  });
  test(
    'center-aligned text is centered in its frame, not its intrinsic width',
    () async {
      final controller = CanvasEditorController(
        initialDocument: const DesignDocument(
          id: 'alignment',
          version: 1,
          width: 100,
          height: 50,
          nodes: [
            BackgroundNode(
              id: 'bg',
              frame: Rect.fromLTWH(0, 0, 100, 50),
              zIndex: 0,
              color: '#FFFFFFFF',
            ),
            TextNode(
              id: 'text',
              frame: Rect.fromLTWH(0, 0, 100, 50),
              zIndex: 1,
              text: 'I',
              fontFamily: 'DMSans',
              fontSize: 24,
              textAlign: 'center',
            ),
          ],
        ),
      );
      addTearDown(controller.dispose);
      final image = img.decodePng(await controller.exportToPng(pixelRatio: 1))!;
      final xs = <int>[];
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (image.getPixel(x, y).r < 100) xs.add(x);
        }
      }
      expect(xs, isNotEmpty);
      expect(xs.reduce((a, b) => a + b) / xs.length, inInclusiveRange(45, 55));
    },
  );
}
