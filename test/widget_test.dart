import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/app.dart';
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/domain/video/timeline.dart';
import 'package:invitation_studio/services/bundled_fonts.dart'
    show loadStudioFonts;
import 'package:invitation_studio/services/draft_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);
  Future<StudioController> mount(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final studio = StudioController(
      project: StudioProject.sample(),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);
    await tester.pumpWidget(StudioApp(controller: studio));
    await tester.pumpAndSettle();
    return studio;
  }

  for (final size in [
    const Size(320, 760),
    const Size(390, 844),
    const Size(850, 900),
    const Size(1024, 900),
    const Size(1440, 1000),
  ]) {
    testWidgets('responsive editor ${size.width.toInt()}px without overflow', (
      tester,
    ) async {
      await mount(tester, size);
      expect(tester.takeException(), isNull);
      expect(find.byType(CanvasEditorWidget), findsOneWidget);
      if (size.width < 850) {
        await tester.tap(find.text('Details').last);
        await tester.pumpAndSettle();
        expect(find.text('Make it yours.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close panel'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Style').last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.byTooltip('Close panel'));
        await tester.pumpAndSettle();
      }
      await tester.tap(
        find.text(size.width < 850 ? 'Export' : 'Export invitation'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Ready for their inbox.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });
  }
  testWidgets('guided fields edit the real canvas; undo updates inputs', (
    tester,
  ) async {
    final studio = await mount(tester, const Size(1440, 1000));
    final input = find.descendant(
      of: find.byKey(const ValueKey('field_first')),
      matching: find.byType(TextField),
    );
    await tester.enterText(input, 'Zara');
    await tester.pumpAndSettle();
    expect(studio.fieldValue('first'), 'Zara');
    expect(
      studio.document.nodes
          .whereType<TextNode>()
          .firstWhere((n) => n.id == 'first')
          .text,
      'Zara',
    );
    await tester.tap(find.byTooltip('Undo (Ctrl / Cmd Z)'));
    await tester.pumpAndSettle();
    expect(studio.fieldValue('first'), 'Ayesha');
    expect((tester.widget<TextField>(input).controller!).text, 'Ayesha');
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  testWidgets(
    'real canvas drag and inline text editing flow back to guided fields',
    (tester) async {
      final studio = await mount(tester, const Size(1440, 1000));
      final canvasRect = tester.getRect(find.byType(CanvasEditorWidget));
      final node = studio.document.nodes.whereType<TextNode>().firstWhere(
        (n) => n.id == 'first',
      );
      final scale = canvasRect.width / studio.document.width;
      Offset point(TextNode n) =>
          canvasRect.topLeft +
          Offset(n.frame.center.dx * scale, n.frame.center.dy * scale);
      final gesture = await tester.startGesture(point(node));
      await gesture.moveBy(const Offset(22, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(30, 15));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      final moved = studio.document.nodes.whereType<TextNode>().firstWhere(
        (n) => n.id == 'first',
      );
      expect(moved.frame.left, greaterThan(node.frame.left));
      studio.selectLayer(null);
      await tester.pumpAndSettle();
      await tester.tapAt(point(moved));
      await tester.pumpAndSettle();
      await tester.tapAt(point(moved));
      await tester.pumpAndSettle();
      final inline = find.descendant(
        of: find.byType(CanvasEditorWidget),
        matching: find.byType(TextField),
      );
      expect(inline, findsOneWidget);
      await tester.enterText(inline, 'Mariam');
      await tester.pumpAndSettle();
      await tester.tapAt(canvasRect.topLeft + const Offset(20, 20));
      await tester.pumpAndSettle();
      expect(studio.fieldValue('first'), 'Mariam');
      final form = find.descendant(
        of: find.byKey(const ValueKey('field_first')),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(form).controller!.text, 'Mariam');
      await tester.tap(find.byTooltip('Undo (Ctrl / Cmd Z)'));
      await tester.pumpAndSettle();
      expect(studio.fieldValue('first'), 'Ayesha');
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
  );
  testWidgets('video mode applies a whole-card preset in one tap', (
    tester,
  ) async {
    final studio = await mount(tester, const Size(1440, 1000));
    await tester.tap(find.text('Video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Animation'), findsOneWidget);
    expect(studio.video.motions, isEmpty);

    await tester.tap(find.text('Rise up'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    expect(studio.video.enabled, isTrue);
    expect(studio.video.motions.keys, containsAll(studio.project.layerIds));
    expect(
      studio.video.motions.values.every(
        (motion) => motion.entrance.effect == MotionEffect.slideUp,
      ),
      isTrue,
    );
    // Let the debounced autosave fire so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
