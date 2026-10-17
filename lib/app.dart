import 'package:flutter/material.dart';

import 'application/studio_controller.dart';
import 'ui/studio_screen.dart';
import 'ui/studio_theme.dart';

/// Can be embedded as a route in an existing Flutter app.
class StudioApp extends StatelessWidget {
  const StudioApp({super.key, required this.controller});
  final StudioController controller;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Invita Studio',
    debugShowCheckedModeBanner: false,
    theme: studioTheme(),
    home: StudioScreen(studio: controller),
  );
}
