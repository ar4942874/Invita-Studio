import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import 'app.dart';
import 'application/app_settings.dart';
import 'application/studio_controller.dart';
import 'services/bundled_fonts.dart';
import 'ui/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadStudioFonts();
  registerStudioFontLicenses();
  final settings = AppSettings();
  await settings.load();
  final studio = await StudioController.restore();
  // Warm the initial paper before the first frame, avoiding a blank invitation.
  final images = await CanvasImageLoader.buildCacheForDocument(
    document: studio.document,
    imageProvider: studio.editor.imageProvider,
  );
  for (final image in images.values) {
    image.dispose();
  }
  runApp(
    StudioApp(
      controller: studio,
      settings: settings,
      home: HomeScreen(studio: studio),
    ),
  );
}
