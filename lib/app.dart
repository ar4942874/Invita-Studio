import 'package:flutter/material.dart';

import 'application/app_settings.dart';
import 'application/studio_controller.dart';
import 'domain/invitation_template.dart';
import 'l10n/app_localizations.dart';
import 'ui/occasion_theme.dart';
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

  /// Cached per celebration: the controller notifies on every edit, and the
  /// palette only changes when the category does.
  final Map<InvitationCategory, ThemeData> _themes = {};

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _settings,
    builder: (context, _) => AppSettingsScope(
      settings: _settings,
      child: ListenableBuilder(
        listenable: widget.controller,
        builder: (context, _) {
          // Routes live above the editor's own scope, so the celebration's
          // palette has to be on the MaterialApp too — otherwise a dialog
          // would open in the neutral studio while the editor behind it is
          // sage, blush or gold.
          final occasion = OccasionTheme.forCategory(
            widget.controller.project.category,
          );
          return MaterialApp(
            title: 'Invita Studio',
            debugShowCheckedModeBanner: false,
            theme: _themes.putIfAbsent(
              occasion.category,
              () => studioTheme(occasion: occasion),
            ),
            locale: _settings.locale,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: widget.home ?? StudioScreen(studio: widget.controller),
          );
        },
      ),
    ),
  );
}
