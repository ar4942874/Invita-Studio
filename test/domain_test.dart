import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/category_music.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/services/bundled_fonts.dart'
    show loadStudioFonts;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);
  for (final template in invitationTemplates) {
    for (final format in InvitationFormat.values) {
      test(
        '${template.name} / ${format.label}: complete, portable document',
        () {
          final doc = template.createDocument(
            documentId: 'test',
            format: format,
          );
          final project = StudioProject(
            id: 'test',
            title: 'Wedding invitation',
            updatedAt: DateTime.utc(2026, 10, 16),
            document: doc,
          );
          final restored = StudioProject.decode(project.encode());
          expect(restored.document, doc);
          expect(doc.nodes.map((n) => n.id).toSet().length, doc.nodes.length);
          expect(fieldsFor(doc).keys.toSet(), boundIds);
          expect(formatFor(restored.document), format);
          expect(templateFor(restored.document).id, template.id);
          for (final node in doc.nodes) {
            expect(node.frame.left, greaterThanOrEqualTo(0));
            expect(node.frame.top, greaterThanOrEqualTo(0));
            expect(node.frame.right, lessThanOrEqualTo(doc.width));
            expect(node.frame.bottom, lessThanOrEqualTo(doc.height));
          }
        },
      );
    }
  }
  test('every bundled design ships art for each format and a thumbnail', () async {
    for (final template in invitationTemplates) {
      for (final format in InvitationFormat.values) {
        final bytes = await rootBundle.load(template.art(format));
        expect(bytes.lengthInBytes, greaterThan(0));
      }
      final thumb = await rootBundle.load(template.thumbnail);
      expect(thumb.lengthInBytes, greaterThan(0));
    }
  });
  test('every category ships a bundled tune', () async {
    for (final category in InvitationCategory.values) {
      final audio = CategoryMusic.forCategory(category);
      expect(audio.assetId, CategoryMusic.tuneId(category));
      expect(CategoryMusic.isTune(audio.assetId), isTrue);
      expect(audio.durationMs, greaterThan(0));
      final bytes = await rootBundle.load(CategoryMusic.assetPath(category));
      // A RIFF/WAVE header plus at least some samples.
      expect(bytes.lengthInBytes, greaterThan(1000));
    }
  });
  group('category designs', () {
    test('every category offers exactly ten of its own designs', () {
      for (final category in InvitationCategory.values) {
        final designs = templatesFor(category);
        expect(designs.length, 10);
        for (final design in designs) {
          expect(design.categories, {category});
          expect(design.suits(category), isTrue);
        }
        expect(designs.map((t) => t.id).toSet().length, 10);
      }
    });
    test('a birthday leads with playful art in the birthday palette', () {
      final ids = templatesFor(InvitationCategory.birthday).map((t) => t.id);
      expect(ids, contains('confetti_birthday'));
      expect(ids, contains('botanical_birthday'));
    });
  });
  test('long names retain the full value and fit the frame', () {
    final doc = invitationTemplates.first.createDocument(
      documentId: 'long',
      format: InvitationFormat.square,
    );
    final node = doc.nodes.whereType<TextNode>().firstWhere(
      (n) => n.id == 'first',
    );
    const value = 'Ayesha Noor Fatima Muhammad';
    final fitted = fitTextNode(node.copyWith(text: value));
    expect(fitted.text, value);
    expect(fitted.fontSize, lessThan(node.fontSize));
    final painter = TextPainter(
      text: TextSpan(text: fitted.text, style: nodeTextStyle(fitted)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: fitted.frame.width);
    expect(painter.height, lessThanOrEqualTo(fitted.frame.height + .1));
    painter.dispose();
  });
  test('long names never paint over the ampersand on any format', () {
    const fields = {
      'first': 'Muhammed Abdulrahman Umar',
      'second': 'Ayesha Noor Fatima Khan',
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

    for (final format in InvitationFormat.values) {
      final doc = invitationTemplates.first.createDocument(
        documentId: 'overlap',
        format: format,
        fields: fields,
      );
      TextNode node(String id) =>
          doc.nodes.whereType<TextNode>().firstWhere((n) => n.id == id);
      final first = node('first');
      final amp = node('amp');
      final second = node('second');
      expect(
        first.frame.top + paintedHeight(first),
        lessThanOrEqualTo(amp.frame.top),
        reason: '${format.name}: the first name paints over the ampersand',
      );
      expect(
        amp.frame.top + paintedHeight(amp),
        lessThanOrEqualTo(second.frame.top),
        reason: '${format.name}: the ampersand paints over the second name',
      );
    }
  });
  test(
    'first-strong text direction supports Arabic script and neutral prefixes',
    () {
      expect(invitationTextDirection('12 — عائشہ'), TextDirection.rtl);
      expect(invitationTextDirection('12 — Ayesha'), TextDirection.ltr);
      expect(invitationTextDirection('Hamza & حمزہ'), TextDirection.ltr);
    },
  );
  for (final attack in [
    'local path',
    'remote background',
    'custom node',
    'duplicate IDs',
    'huge canvas',
    'unknown font',
    'oversized font',
    'missing linked field',
  ]) {
    test('project import rejects $attack', () {
      final json =
          jsonDecode(StudioProject.sample().encode()) as Map<String, dynamic>;
      final doc = json['document'] as Map<String, dynamic>;
      final nodes = doc['nodes'] as List;
      switch (attack) {
        case 'local path':
          nodes[0]['localPath'] = '/etc/passwd';
        case 'remote background':
          nodes[0]['assetId'] = 'https://untrusted.invalid/image.png';
        case 'custom node':
          nodes[1]['type'] = 'remote_widget';
        case 'duplicate IDs':
          nodes[2]['id'] = nodes[1]['id'];
        case 'huge canvas':
          doc['width'] = 1000000;
        case 'unknown font':
          nodes[1]['style']['fontFamily'] = 'unbundled';
        case 'oversized font':
          nodes[1]['style']['fontSize'] = 100000;
        case 'missing linked field':
          nodes.removeAt(1);
      }
      expect(
        () => StudioProject.decode(jsonEncode(json)),
        throwsFormatException,
      );
    });
  }
  const tinyPng =
      'data:image/png;base64,'
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

  Map<String, dynamic> photoNode({
    String? assetId = tinyPng,
    String? localPath,
    int zIndex = 11,
    String? fit = 'cover',
  }) => {
    'id': 'photo.layer',
    'type': 'image',
    'frame': {'x': 10.0, 'y': 10.0, 'width': 100.0, 'height': 100.0},
    'assetId': assetId,
    'localPath': localPath,
    'fit': fit,
    'transform': {'rotation': 0.0, 'scaleX': 1.0, 'scaleY': 1.0},
    'zIndex': zIndex,
  };

  Map<String, dynamic> withPhoto(Map<String, dynamic> node) {
    final json =
        jsonDecode(StudioProject.sample().encode()) as Map<String, dynamic>;
    ((json['document'] as Map<String, dynamic>)['nodes'] as List).add(node);
    return json;
  }

  test('project import accepts an embedded photo layer', () {
    final decoded = StudioProject.decode(jsonEncode(withPhoto(photoNode())));
    expect(decoded.document.nodes.whereType<ImageNode>().length, 1);
  });

  for (final attack in const [
    'remote photo',
    'photo with file path',
    'photo behind background',
    'photo with unknown fit',
  ]) {
    test('project import rejects $attack', () {
      final node = switch (attack) {
        'remote photo' => photoNode(assetId: 'https://untrusted.invalid/x.png'),
        'photo with file path' => photoNode(localPath: '/etc/passwd'),
        'photo behind background' => photoNode(zIndex: 0),
        _ => photoNode(fit: 'stretch'),
      };
      expect(
        () => StudioProject.decode(jsonEncode(withPhoto(node))),
        throwsFormatException,
      );
    });
  }

  test('project import rejects excessive input before parsing', () {
    expect(
      () => StudioProject.decode(' ' * (StudioProject.maxProjectBytes + 1)),
      throwsFormatException,
    );
  });
}
