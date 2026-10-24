import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/services/bundled_fonts.dart'
    show loadStudioFonts;
import 'package:invitation_studio/services/draft_store.dart';

/// The three arrangements a card can be drawn in.
///
/// Every composition has to survive the same things the centred one does: a
/// phone-sized square, a tall story card, long names and a page with no room to
/// spare. These tests hold that line without pinning exact pixels, so the look
/// can keep evolving.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);

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

  const longFields = {
    'first': 'Muhammed Abdulrahman Umar',
    'second': 'Ayesha Noor Fatima Khan',
    'venue': 'The Royal Orchard Marquee and Gardens',
    'address': '12 Cavalry Ground, Lahore Cantt, Punjab 54000',
    'message': 'invite you to celebrate their wedding with dinner and dancing',
  };

  double paintedHeight(TextNode node) {
    final painter = TextPainter(
      text: TextSpan(text: node.text, style: nodeTextStyle(node)),
      textDirection: invitationTextDirection(node.text),
    )..layout(maxWidth: node.frame.width);
    final height = painter.height;
    painter.dispose();
    return height;
  }

  group('every composition survives every format', () {
    for (final layout in InvitationLayout.values) {
      for (final format in InvitationFormat.values) {
        test('${layout.label} / ${format.label}', () {
          final template = catalogueTemplates.first.withLayout(layout);
          final doc = template.createDocument(
            documentId: 'layout',
            format: format,
            fields: longFields,
          );

          // The same ten linked layers, each once, still within the page.
          final texts = doc.nodes.whereType<TextNode>().toList();
          expect(texts.map((n) => n.id).toList(), order);
          expect(texts.map((n) => n.id).toSet(), boundIds);
          for (final node in texts) {
            expect(node.frame.left, greaterThanOrEqualTo(0), reason: node.id);
            expect(node.frame.top, greaterThanOrEqualTo(0), reason: node.id);
            expect(node.frame.width, greaterThan(0), reason: node.id);
            expect(node.frame.height, greaterThan(0), reason: node.id);
            expect(
              node.frame.right,
              lessThanOrEqualTo(doc.width),
              reason: node.id,
            );
            expect(
              node.frame.bottom,
              lessThanOrEqualTo(doc.height),
              reason: node.id,
            );
          }

          // Long names shrink inside their frame, and nothing paints over the
          // layer below it — the failure the phone wizard used to cause.
          for (var i = 0; i < texts.length - 1; i++) {
            final node = texts[i];
            expect(
              node.frame.top + paintedHeight(node),
              lessThanOrEqualTo(texts[i + 1].frame.top + .01),
              reason:
                  '${layout.label}/${format.name}: '
                  '${node.id} paints over ${texts[i + 1].id}',
            );
          }
        });
      }
    }
  });

  test('the centred composition is still the original arrangement', () {
    // The refactor moved the numbers into one table; these are the values the
    // shipped cards had, so switching compositions cannot quietly restyle the
    // default look.
    for (final format in InvitationFormat.values) {
      final doc = legacyTemplates.first.createDocument(
        documentId: 'centred',
        format: format,
      );
      final nodes = {
        for (final node in doc.nodes.whereType<TextNode>()) node.id: node,
      };
      final square = format == InvitationFormat.square;
      final height = format.height;
      final nameSize = square
          ? 104.0
          : format == InvitationFormat.story
          ? 164.0
          : 148.0;
      final firstTop = square ? .220 : .268;
      final ampTop = square ? .330 : .382;
      expect(nodes['first']!.frame.top, closeTo(firstTop * height, .01));
      expect(nodes['amp']!.frame.top, closeTo(ampTop * height, .01));
      expect(nodes['second']!.frame.top, closeTo((square ? .390 : .435) * height, .01));
      // The name frame still stops short of the ampersand, and the face is
      // drawn at or below its declared size rather than allowed to overflow.
      expect(
        nodes['first']!.frame.height,
        closeTo(
          (ampTop - firstTop) * height - 2 < nameSize * 1.2
              ? (ampTop - firstTop) * height - 2
              : nameSize * 1.2,
          .01,
        ),
      );
      expect(nodes['first']!.fontSize, lessThanOrEqualTo(nameSize));
      expect(nodes['first']!.textAlign, 'center');
      expect(nodes['first']!.frame.width, 850);
      expect(nodes['header']!.frame.width, 820);
      expect(nodes['venue']!.fontSize, square ? 36 : 42);
    }
  });

  test('a design carries its composition into its document', () {
    for (final template in catalogueTemplates) {
      final doc = template.createDocument(
        documentId: 'carry',
        format: InvitationFormat.classic,
      );
      final header = doc.nodes.whereType<TextNode>().firstWhere(
        (n) => n.id == 'header',
      );
      switch (template.layout) {
        case InvitationLayout.centred:
          expect(header.textAlign, 'center');
          expect(header.frame.left, greaterThan(100));
        case InvitationLayout.editorial:
          expect(header.textAlign, 'left');
          expect(header.frame.left, 254);
        case InvitationLayout.statement:
          expect(header.textAlign, 'center');
          expect(header.fontSize, 17);
      }
    }
    // The catalogue is not one arrangement recoloured sixty times.
    expect(
      catalogueTemplates.map((t) => t.layout).toSet(),
      InvitationLayout.values.toSet(),
    );
  });

  group('the studio follows the composition', () {
    late StudioController studio;
    setUp(() {
      studio = StudioController(
        project: StudioProject.sample(),
        store: MemoryProjectStore(),
      );
    });
    tearDown(() => studio.dispose());

    test('choosing a composition keeps every word and can be undone', () async {
      await studio.setField('first', 'Ayesha');
      await studio.setField('venue', 'The Royal Orchard');
      await studio.flush();

      final before = studio.document.nodes
          .whereType<TextNode>()
          .firstWhere((n) => n.id == 'header')
          .frame;
      expect(studio.layout, InvitationLayout.centred);

      await studio.chooseLayout(InvitationLayout.editorial);
      await studio.flush();

      expect(studio.layout, InvitationLayout.editorial);
      expect(studio.template.layout, InvitationLayout.editorial);
      expect(fieldsFor(studio.document).keys.toSet(), boundIds);
      expect(studio.fieldValue('first'), 'Ayesha');
      expect(studio.fieldValue('venue'), 'The Royal Orchard');
      final after = studio.document.nodes
          .whereType<TextNode>()
          .firstWhere((n) => n.id == 'header')
          .frame;
      expect(after, isNot(before));
      expect(after.left, 254);

      await studio.undo();
      await studio.flush();
      expect(studio.layout, InvitationLayout.centred);
      expect(
        studio.document.nodes
            .whereType<TextNode>()
            .firstWhere((n) => n.id == 'header')
            .frame,
        before,
      );
    });

    test('a format change keeps the chosen composition', () async {
      await studio.chooseLayout(InvitationLayout.statement);
      await studio.flush();
      expect(studio.layout, InvitationLayout.statement);

      await studio.chooseFormat(InvitationFormat.story);
      await studio.flush();

      expect(studio.format, InvitationFormat.story);
      expect(studio.layout, InvitationLayout.statement);
      final header = studio.document.nodes
          .whereType<TextNode>()
          .firstWhere((n) => n.id == 'header');
      expect(header.textAlign, 'center');
      expect(header.fontSize, 17);
    });

    test('reopening a draft keeps its composition', () async {
      final store = MemoryProjectStore();
      final opening = StudioController(
        project: StudioProject.sample(),
        store: store,
      );
      await opening.chooseLayout(InvitationLayout.editorial);
      await opening.flush();
      await opening.saveNow();
      final saved = opening.project;
      opening.dispose();

      final restored = StudioController(project: saved, store: store);
      addTearDown(restored.dispose);
      await restored.catalogLoaded;
      expect(restored.layout, InvitationLayout.editorial);
    });

    test('a moved layer leaves the composition unknown, not wrong', () async {
      final nodes = studio.document.nodes.map((node) {
        if (node is TextNode && node.id == 'header') {
          return node.copyWith(
            frame: node.frame.translate(120, 40),
          );
        }
        return node;
      }).toList();
      await studio.editor.applyDocument(
        studio.document.copyWith(nodes: nodes),
      );
      await studio.flush();

      // 9 of 10 layers still match the centred arrangement.
      expect(studio.layout, InvitationLayout.centred);

      final scattered = studio.document.nodes.map((node) {
        if (node is TextNode) {
          return node.copyWith(frame: node.frame.translate(200, 0));
        }
        return node;
      }).toList();
      await studio.editor.applyDocument(
        studio.document.copyWith(nodes: scattered),
      );
      await studio.flush();
      expect(studio.layout, isNull);
      // The card still behaves: it just reports no arrangement.
      expect(studio.template.id, isNotEmpty);
    });
  });
}
