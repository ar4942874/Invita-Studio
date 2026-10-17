import 'package:flutter/material.dart';

import 'application/app_settings.dart';
import 'application/studio_controller.dart';
import 'l10n/app_localizations.dart';
import 'ui/studio_screen.dart';
import 'ui/studio_theme.dart';

/// Can be embedded as a route in an existing Flutter app.
class StudioApp extends StatefulWidget {
  const StudioApp({
    super.key,
    required this.controller,
    this.home,
    this.settings,
  });
  final StudioController controller;

  /// Overrides the start screen. Defaults to [StudioScreen] so the editor can
  /// be embedded directly; the standalone app starts on the [HomeScreen].
  final Widget? home;

  /// Optional shared preferences holder; one is created when omitted so tests
  /// and embedding code need not supply it.
  final AppSettings? settings;

  @override
  State<StudioApp> createState() => _StudioAppState();
}

class _StudioAppState extends State<StudioApp> {
  late final AppSettings _settings = widget.settings ?? AppSettings();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, _) => AppSettingsScope(
      settings: _settings,
      child: MaterialApp(
        title: 'Invita Studio',
        debugShowCheckedModeBanner: false,
        theme: studioTheme(),
        locale: _settings.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: widget.home ?? StudioScreen(studio: widget.controller),
      ),
    ),
  );
}
