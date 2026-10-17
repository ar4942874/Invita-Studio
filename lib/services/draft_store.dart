import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/project.dart';

abstract class ProjectStore {
  Future<List<StudioProject>> load();
  Future<void> save(List<StudioProject> projects);
}

class LocalProjectStore implements ProjectStore {
  static const key = 'invita.studio.projects.v1';
  @override
  Future<List<StudioProject>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString(key);
    if (data == null) return [];
    final decoded = jsonDecode(data);
    if (decoded is! List || decoded.length > 12) {
      throw const FormatException('Local draft storage is invalid.');
    }
    return decoded.map((p) => StudioProject.decode(jsonEncode(p))).toList();
  }

  @override
  Future<void> save(List<StudioProject> projects) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      key,
      jsonEncode(projects.take(12).map((p) => p.toJson()).toList()),
    );
    if (!saved) throw StateError('Local storage did not accept this draft.');
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
