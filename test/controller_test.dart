import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/services/draft_store.dart';
import 'package:invitation_studio/services/photo_service.dart';
import 'package:invitation_studio/services/bundled_fonts.dart'
    show loadStudioFonts;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);
  late StudioController studio;
  setUp(
    () => studio = StudioController(
      project: StudioProject.sample(),
      store: MemoryProjectStore(),
    ),
  );
  tearDown(() => studio.dispose());

  test('rapid form updates do not lose names or other fields', () async {
    final updates = <Future<void>>[];
    for (final value in ['Z', 'Za', 'Zar', 'Zara']) {
      updates.add(studio.setField('first', value));
    }
    updates.add(studio.setField('second', 'Omar'));
    updates.add(studio.setField('venue', 'Garden Pavilion'));
    expect(studio.fieldValue('first'), 'Zara');
    await Future.wait(updates);
    await studio.flush();
    expect(fieldsFor(studio.document)['first'], 'Zara');
    expect(studio.fieldValue('second'), 'Omar');
    expect(studio.fieldValue('venue'), 'Garden Pavilion');
    await studio.undo();
    await studio.flush();
    expect(studio.fieldValue('venue'), 'The Royal Orchard');
    expect(studio.fieldValue('first'), 'Zara');
    await studio.redo();
    await studio.flush();
    expect(studio.fieldValue('venue'), 'Garden Pavilion');
  });
  test(
    'template change keeps fields/custom text and is one undo step',
    () async {
      await studio.setField('first', 'Zara');
      await studio.addText();
      await studio.flush();
      final before = studio.document;
      await studio.chooseTemplate(invitationTemplates[1]);
      await studio.flush();
      expect(studio.template.id, 'midnight');
      expect(studio.fieldValue('first'), 'Zara');
      expect(studio.layerCount, 11);
      await studio.undo();
      await studio.flush();
      expect(studio.document, before);
      expect(studio.template.id, 'botanical');
    },
  );
  test('format reflows text, retains ink and custom layers', () async {
    await studio.styleText(color: '#FF69464F');
    await studio.addText();
    await studio.flush();
    for (final format in InvitationFormat.values) {
      await studio.chooseFormat(format);
      await studio.flush();
      expect(studio.format, format);
      expect(studio.layerCount, 11);
      final first = studio.document.nodes.whereType<TextNode>().firstWhere(
        (n) => n.id == 'first',
      );
      expect(first.textColor, '#FF69464F');
      expect(
        StudioProject.decode(studio.project.encode()).document,
        studio.document,
      );
    }
  });
  test('style slider history is coalesced into a single undo step', () async {
    final before = studio.document;
    studio.beginStyleSession();
    await studio.styleText(fontSize: 100, recordUndo: false);
    await studio.styleText(fontSize: 115, recordUndo: false);
    studio.endStyleSession();
    await studio.flush();
    expect(studio.styleReference.fontSize, 115);
    await studio.undo();
    await studio.flush();
    expect(studio.document, before);
  });
  test('growing a field re-stacks the wording without overlap', () async {
    studio.selectLayer('first');
    await Future<void>.delayed(Duration.zero);
    final before = studio.document.nodes
        .whereType<TextNode>()
        .firstWhere((n) => n.id == 'first');
    await studio.styleText(fontSize: 200);
    await studio.flush();
    final stack = {
      for (final n in studio.document.nodes.whereType<TextNode>()) n.id: n,
    };
    const order = [
      'header',
      'first',
      'amp',
      'second',
      'message',
      'date',
      'time',
      'venue',
      'address',
      'rsvp',
    ];
    var previousBottom = double.negativeInfinity;
    for (final id in order) {
      final node = stack[id]!;
      expect(
        node.frame.top,
        greaterThanOrEqualTo(previousBottom - .5),
        reason: '$id overlaps the field above it',
      );
      previousBottom = node.frame.bottom;
    }
    expect(stack['first']!.fontSize, 200);
    expect(stack['first']!.frame.height, greaterThan(before.frame.height));
    expect(
      stack['rsvp']!.frame.bottom,
      lessThanOrEqualTo(studio.document.height + .5),
    );
  });
  test('direct canvas changes flow back into fields and persist', () async {
    studio.editor.updateTextContent('venue', 'Moonlit Gardens');
    await Future<void>.delayed(Duration.zero);
    await studio.flush();
    expect(studio.fieldValue('venue'), 'Moonlit Gardens');
    await studio.saveNow();
    expect(
      (studio.store as MemoryProjectStore).projects.first.document,
      studio.document,
    );
  });
  test('custom text can be deleted but linked fields cannot', () async {
    studio.selectLayer('first');
    await Future<void>.delayed(Duration.zero);
    await studio.deleteSelected();
    await studio.flush();
    expect(studio.layerCount, 10);
    await studio.addText();
    await studio.flush();
    expect(studio.layerCount, 11);
    await studio.deleteSelected();
    await studio.flush();
    expect(studio.layerCount, 10);
  });
  test('a photo layer can be added, restyled, persisted and deleted', () async {
    await studio.addPhotoFromBytes(
      img.encodePng(img.Image(width: 240, height: 120)),
    );
    await studio.flush();
    await Future<void>.delayed(Duration.zero);
    final photo = studio.selectedPhoto;
    expect(photo, isNotNull);
    expect(isPhotoDataUrl(photo!.assetId), isTrue);
    expect(studio.nodeCount, 11);
    await studio.setPhotoFit('contain');
    await studio.flush();
    await Future<void>.delayed(Duration.zero);
    expect(studio.selectedPhoto?.fit, 'contain');
    expect(
      StudioProject.decode(studio.project.encode()).document,
      studio.document,
    );
    await studio.deleteSelected();
    await studio.flush();
    expect(studio.nodeCount, 10);
  });
  test('moved/rotated out-of-bounds text is flagged before export', () async {
    final nodes = studio.document.nodes
        .map(
          (n) => n.id == 'first'
              ? n.copyWith(
                  frame: const Rect.fromLTWH(-300, -200, 800, 200),
                  rotation: 45,
                )
              : n,
        )
        .toList();
    await studio.editor.applyDocument(studio.document.copyWith(nodes: nodes));
    await studio.flush();
    expect(studio.layoutWarnings, isNotEmpty);
  });
  test('all preset template formats have no clipped text', () async {
    for (final template in invitationTemplates) {
      await studio.chooseTemplate(template);
      for (final format in InvitationFormat.values) {
        await studio.chooseFormat(format);
        await studio.flush();
        expect(
          studio.layoutWarnings,
          isEmpty,
          reason: '${template.name}/${format.name}',
        );
      }
    }
  });
  test('JSON-backed local drafts survive restore', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalProjectStore();
    await studio.setField('venue', 'The Olive Grove');
    await studio.flush();
    await store.save([studio.project]);
    final restored = await StudioController.restore(store: store);
    expect(restored.fieldValue('venue'), 'The Olive Grove');
    expect(restored.document, studio.document);
    restored.dispose();
  });
  test('multiple drafts restore the most recently edited project', () async {
    final store = MemoryProjectStore();
    await store.save([studio.project]);
    final other = await StudioController.restore(store: store);
    await other.newProject();
    other.rename('Another celebration');
    await other.setField('first', 'Mariam');
    await other.flush();
    await other.saveNow();
    expect(other.drafts.length, 2);
    final again = await StudioController.restore(store: store);
    expect(again.project.title, 'Another celebration');
    expect(again.fieldValue('first'), 'Mariam');
    again.dispose();
    other.dispose();
  });
}
