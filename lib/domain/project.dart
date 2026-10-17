import 'dart:convert';

import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../services/photo_service.dart';
import 'invitation_template.dart';

class StudioProject {
  /// Projects may embed bounded photos, so the envelope is larger than JSON text.
  static const int maxProjectBytes = 12 * 1024 * 1024;
  static const int maxPhotoNodes = 8;

  const StudioProject({
    required this.id,
    required this.title,
    required this.updatedAt,
    required this.document,
  });
  final String id, title;
  final DateTime updatedAt;
  final DesignDocument document;

  factory StudioProject.sample() {
    final id = 'p_${DateTime.now().microsecondsSinceEpoch}';
    return StudioProject(
      id: id,
      title: 'Ayesha & Hamza',
      updatedAt: DateTime.now(),
      document: invitationTemplates.first.createDocument(
        documentId: id,
        format: InvitationFormat.classic,
      ),
    );
  }

  StudioProject copyWith({
    String? title,
    DesignDocument? document,
    DateTime? updatedAt,
  }) => StudioProject(
    id: id,
    title: title ?? this.title,
    updatedAt: updatedAt ?? DateTime.now(),
    document: document ?? this.document,
  );

  Map<String, dynamic> toJson() => {
    'schema': 'invita.project',
    'version': 1,
    'id': id,
    'title': title,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'document': document.toJson(),
  };
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Explicit allowlist: portable local assets, bounded embedded photos and
  /// editable text only. No filesystem paths, arbitrary URLs, custom nodes, or
  /// unbounded canvases.
  static StudioProject decode(String source) {
    if (utf8.encode(source).length > maxProjectBytes) {
      throw const FormatException('Project must be smaller than 12 MB.');
    }
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, dynamic> ||
          json['schema'] != 'invita.project' ||
          json['version'] != 1) {
        throw const FormatException(
          'This is not a supported Invita Studio project (version 1).',
        );
      }
      final id = json['id'];
      if (id is! String || !RegExp(r'^[\w.-]{1,80}$').hasMatch(id)) {
        throw const FormatException('Invalid project ID.');
      }
      final title = json['title'];
      if (title is! String || title.trim().isEmpty || title.length > 80) {
        throw const FormatException('Invalid project title.');
      }
      final raw = json['document'];
      if (raw is! Map<String, dynamic>) {
        throw const FormatException('Missing invitation document.');
      }
      if (raw['id'] != id || raw['version'] != 1) {
        throw const FormatException('Invalid document metadata.');
      }
      if (raw['width'] != 1080 ||
          !InvitationFormat.values.any((f) => f.height == raw['height'])) {
        throw const FormatException(
          'Use a supported 1080-pixel invitation format.',
        );
      }
      final nodes = raw['nodes'];
      if (nodes is! List || nodes.isEmpty || nodes.length > 50) {
        throw const FormatException(
          'An invitation can contain up to 50 layers.',
        );
      }
      final ids = <String>{};
      var backgrounds = 0;
      var photos = 0;
      String? asset;
      final validAssets = {
        for (final t in invitationTemplates)
          for (final f in InvitationFormat.values)
            if (f.height == raw['height']) t.art(f),
      };
      bool number(dynamic value, double min, double max) =>
          value is num && value.isFinite && value >= min && value <= max;
      bool color(dynamic value) =>
          value is String && RegExp(r'^#[0-9a-fA-F]{8}$').hasMatch(value);
      for (final node in nodes) {
        if (node is! Map<String, dynamic>) {
          throw const FormatException('Invalid layer.');
        }
        final nid = node['id'];
        if (nid is! String ||
            !RegExp(r'^[\w.-]{1,80}$').hasMatch(nid) ||
            !ids.add(nid)) {
          throw const FormatException('Layer IDs must be unique.');
        }
        if (node['localPath'] != null) {
          throw const FormatException(
            'Local file references are not allowed in portable projects.',
          );
        }
        final f = node['frame'];
        if (f is! Map ||
            !number(f['x'], -2160, 2160) ||
            !number(f['y'], -3840, 3840) ||
            !number(f['width'], 2, 2160) ||
            !number(f['height'], 2, 3840)) {
          throw const FormatException('Invalid layer bounds.');
        }
        if (node['zIndex'] is! int || !number(node['zIndex'], 0, 100)) {
          throw const FormatException('Invalid layer order.');
        }
        final transform = node['transform'];
        if (transform is! Map ||
            !number(transform['rotation'], -360, 360) ||
            !number(transform['scaleX'], .1, 5) ||
            !number(transform['scaleY'], .1, 5)) {
          throw const FormatException('Invalid layer transform.');
        }
        if (node['type'] == 'background') {
          backgrounds++;
          asset = node['assetId'] as String?;
          if (nid != 'background' ||
              !validAssets.contains(asset) ||
              !color(node['color']) ||
              node['zIndex'] != 0 ||
              f['x'] != 0 ||
              f['y'] != 0 ||
              f['width'] != 1080 ||
              f['height'] != raw['height'] ||
              transform['rotation'] != 0 ||
              transform['scaleX'] != 1 ||
              transform['scaleY'] != 1) {
            throw const FormatException(
              'Use one of the bundled invitation backgrounds.',
            );
          }
        } else if (node['type'] == 'text') {
          final style = node['style'];
          if (node['assetId'] != null ||
              node['text'] is! String ||
              (node['text'] as String).length > 500 ||
              style is! Map ||
              !fontFamilies.containsKey(style['fontFamily']) ||
              !number(style['fontSize'], 8, 240) ||
              !number(style['lineHeight'], .8, 2.2) ||
              !number(style['letterSpacing'], -3, 20) ||
              !color(style['textColor']) ||
              ![
                100,
                200,
                300,
                400,
                500,
                600,
                700,
                800,
                900,
              ].contains(style['fontWeight']) ||
              !['left', 'center', 'right'].contains(style['textAlign']) ||
              node['zIndex'] == 0) {
            throw const FormatException(
              'Invalid text layer or unsupported font.',
            );
          }
        } else if (node['type'] == 'image') {
          if (!isPhotoDataUrl(node['assetId'] as String?) ||
              node['zIndex'] == 0 ||
              !['cover', 'contain', 'fill'].contains(node['fit'] ?? 'cover')) {
            throw const FormatException(
              'Photo layers must be embedded images this app created.',
            );
          }
          photos++;
          if (photos > maxPhotoNodes) {
            throw const FormatException('An invitation can hold up to 8 photos.');
          }
        } else {
          throw const FormatException(
            'This version accepts text layers, embedded photos and bundled backgrounds only.',
          );
        }
      }
      if (backgrounds != 1 || asset == null || !ids.containsAll(boundIds)) {
        throw const FormatException(
          'Project is missing its background or invitation fields.',
        );
      }
      final document = DesignDocument.fromJson(raw);
      return StudioProject(
        id: id,
        title: title,
        updatedAt:
            DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.now(),
        document: document,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'The project is damaged or has invalid field types.',
      );
    }
  }
}
