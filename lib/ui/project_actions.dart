import 'dart:convert';

import 'package:flutter/material.dart';

import '../application/studio_controller.dart';
import '../domain/project.dart';
import '../services/file_actions.dart';

/// "Save a copy": writes the editable project JSON under a new file name
/// without changing the draft that is open.
Future<void> saveProjectCopy(
  BuildContext context,
  StudioProject project,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final message = await saveBytes(
      utf8.encode(project.encode()),
      '${fileStem(project.title)}.invita.json',
      'application/json',
    );
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('The copy could not be saved.')),
    );
  }
}

/// "Duplicate draft": forks [project] into a new draft, which becomes active so
/// the host can start the variation immediately.
Future<void> duplicateDraft(
  BuildContext context,
  StudioController studio,
  StudioProject project,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await studio.duplicateProject(project);
    messenger.showSnackBar(
      SnackBar(content: Text('Duplicated “${project.title}”.')),
    );
  } on StateError catch (error) {
    messenger.showSnackBar(SnackBar(content: Text(error.message)));
  }
}

/// A filesystem-safe stem for a project title.
String fileStem(String title) {
  final slug = title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'invitation' : slug;
}
