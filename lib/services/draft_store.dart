import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart'
    show BackgroundNode, ImageNode;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/project.dart';

abstract class ProjectStore {
  Future<List<StudioProject>> load();
  Future<void> save(List<StudioProject> projects);
}

class LocalProjectStore implements ProjectStore {
  static const key = 'invita.studio.projects.v1';

  /// Sub-threshold drafts serialise on the UI isolate: they cost far less than
  /// the round-trip. Above this, megabyte drafts keep the UI smooth off-main.
  static const int offloadBytes = 512 * 1024;

  @override
  Future<List<StudioProject>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(key);
    if (data == null) return [];
    final decoded = data.length >= offloadBytes
        ? await compute(_decodeDrafts, data)
        : _decodeDrafts(data);
    if (decoded.length > 12) {
      throw const FormatException('Local draft storage is invalid.');
    }
    return decoded;
  }

  static List<StudioProject> _decodeDrafts(String data) {
    final decoded = jsonDecode(data);
    if (decoded is! List) {
      throw const FormatException('Local draft storage is invalid.');
    }
    return decoded
        .map((d) => StudioProject.decode(jsonEncode(d)))
        .toList();
  }

  @override
  Future<void> save(List<StudioProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = projects.take(12).map((p) => _estimateBytes(p));
    var estimated = 0;
    for (final size in payload) {
      estimated += size;
    }
    final encoded = estimated >= offloadBytes
        ? await compute(
            _encodeDrafts,
            projects.take(12).map((p) => p.toJson()).toList(),
          )
        : jsonEncode(projects.take(12).map((p) => p.toJson()).toList());
    final saved = await prefs.setString(key, encoded);
    if (!saved) throw StateError('Local storage did not accept this draft.');
  }

  static String _encodeDrafts(Object payload) => jsonEncode(payload);

  /// Embedded photo data URLs dominate a draft; text and layout are rounding
  /// errors, so the estimate skips them.
  static int _estimateBytes(StudioProject project) {
    var total = 4096;
    for (final node in project.document.nodes) {
      final assetId = switch (node) {
        ImageNode image => image.assetId,
        BackgroundNode background when background.hasBackgroundImage =>
          background.assetId,
        _ => null,
      };
      if (assetId != null) total += assetId.length;
    }
    return total;
  }
}

class MemoryProjectStore implements ProjectStore {
  List<StudioProject> projects = [];
  @override
  Future<List<StudioProject>> load() async => List.of(projects);
  @override
  Future<void> save(List<StudioProject> value) async {
    projects = List.of(value);
  }
}
