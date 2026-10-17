import 'package:flutter/material.dart';

import 'application/studio_controller.dart';
import 'ui/studio_screen.dart';
import 'ui/studio_theme.dart';

/// Can be embedded as a route in an existing Flutter app.
class StudioApp extends StatelessWidget {
  const StudioApp({super.key, required this.controller, this.home});
  final StudioController controller;

  /// Overrides the start screen. Defaults to [StudioScreen] so the editor can
  /// be embedded directly; the standalone app starts on the [HomeScreen].
  final Widget? home;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Invita Studio',
    debugShowCheckedModeBanner: false,
    theme: studioTheme(),
    home: home ?? StudioScreen(studio: controller),
  );
}
