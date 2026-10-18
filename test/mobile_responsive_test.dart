import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/app.dart';
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/l10n/app_localizations.dart';
import 'package:invitation_studio/services/bundled_fonts.dart'
    show loadStudioFonts;
import 'package:invitation_studio/services/draft_store.dart';
import 'package:invitation_studio/ui/home_screen.dart';
import 'package:invitation_studio/ui/studio_theme.dart';

/// Mobile responsiveness suite.
///
/// Pumps the real screens at phone-sized viewports (logical pixels with a
/// device pixel ratio of 1) and asserts the compact shell, bottom navigation
/// and single-column flows hold across small phones through large phones.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);

  void setSize(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<StudioController> mountEditor(WidgetTester tester) async {
    final studio = StudioController(
      project: StudioProject.sample(),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);
    await tester.pumpWidget(StudioApp(controller: studio));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    return studio;
  }

  const phoneSizes = [
    Size(320, 568), // small phone (iPhone SE 1st gen)
    Size(360, 800), // common Android
    Size(390, 844), // iPhone 14
    Size(414, 896), // iPhone 11 Pro Max
  ];

  const panelTitles = {
    'Details': 'Your details',
    'Templates': 'Choose a template',
    'Layers': 'Canvas layers',
    'Style': 'Text & style',
  };

  for (final size in phoneSizes) {
    testWidgets(
      'editor shell is compact at ${size.width.toInt()}×${size.height.toInt()}',
      (tester) async {
        setSize(tester, size);
        await mountEditor(tester);

        expect(tester.takeException(), isNull);

        // Canvas is present and laid out without exceptions.
        expect(find.byType(CanvasEditorWidget), findsOneWidget);

        // Single nav rail: bottom navigation only, no desktop side tabs.
        expect(find.text('Details'), findsOneWidget);
        expect(find.text('Templates'), findsOneWidget);
        expect(find.text('Layers'), findsOneWidget);
        expect(find.text('Style'), findsOneWidget);

        // Compact Image/Video mode switch lives in the mobile sub-bar.
        expect(find.text('Image'), findsOneWidget);
        expect(find.text('Video'), findsOneWidget);

        // 'My drafts' quick button is hidden on the narrowest phone;
        // the options menu covers it there.
        if (size.width >= 380) {
          expect(find.byTooltip('My drafts'), findsOneWidget);
        } else {
          expect(find.byTooltip('My drafts'), findsNothing);
        }

        // Tapping Video flips to the compact video workspace.
        await tester.tap(find.text('Video'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Image'));
        await tester.pumpAndSettle();
        expect(find.byType(CanvasEditorWidget), findsOneWidget);
      },
    );
  }

  for (final size in phoneSizes) {
    testWidgets(
      'every bottom panel opens and closes at ${size.width.toInt()}px',
      (tester) async {
        setSize(tester, size);
        await mountEditor(tester);

        for (final entry in panelTitles.entries) {
          await tester.tap(find.text(entry.key).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.text(entry.value), findsOneWidget);
          await tester.tap(find.byTooltip('Close panel'));
          await tester.pumpAndSettle();
        }
      },
    );
  }

  testWidgets('narrow phones reach drafts through the options menu', (
    tester,
  ) async {
    setSize(tester, const Size(320, 568));
    await mountEditor(tester);

    expect(find.byTooltip('My drafts'), findsNothing);

    await tester.tap(find.byTooltip('Project options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My drafts'));
    await tester.pumpAndSettle();

    expect(find.text('Your drafts'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('home wizard flows in a single column at phone width', (
    tester,
  ) async {
    setSize(tester, const Size(360, 800));
    final studio = StudioController(
      project: StudioProject.sample(),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(studio: studio),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 360px < 520px breakpoint: every category tile stacks in one column.
    final categoryWrap = find.byType(Wrap).first;
    final tiles = tester
        .widgetList<SizedBox>(
          find.descendant(of: categoryWrap, matching: find.byWidgetPredicate(
            (w) => w is SizedBox,
          )),
        )
        .where((tile) => (tile.width ?? 0) > 40)
        .toList();
    expect(tiles, isNotEmpty);
    final tileWidth = tiles.first.width!;
    expect(
      tiles.every((tile) => tile.width == tileWidth),
      isTrue,
      reason: 'category tiles should share one full-width column',
    );

    final birthday = tester.getRect(find.text('Birthday').first);
    final wedding = tester.getRect(find.text('Wedding').first);
    expect(birthday.left, closeTo(wedding.left, 1));

    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();

    // Details step stays single-column and holds the seeded wording.
    expect(tester.takeException(), isNull);
    expect(find.text('First name'), findsOneWidget);
    final first = find.descendant(
      of: find.byKey(const ValueKey('home_field_first')),
      matching: find.byType(TextField),
    );
    await tester.enterText(first, 'Sana');
    await tester.pumpAndSettle();

    final footer = find.text('Choose a card');
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();
    await tester.tap(footer);
    await tester.pumpAndSettle();

    // Card step wraps to one column (< 640px) and completes on a phone.
    final designs = templatesFor(InvitationCategory.birthday);
    await tester.ensureVisible(find.text(designs.first.name).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(designs.first.name).first);
    await tester.pumpAndSettle();

    final create = find.text('Create invitation');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();

    // The editor opened with the phone shell, with no layout exceptions.
    expect(tester.takeException(), isNull);
    expect(find.byType(CanvasEditorWidget), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);

    // Let the debounced autosave fire so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('export dialog fits and switches formats on a phone', (
    tester,
  ) async {
    setSize(tester, const Size(320, 568));
    await mountEditor(tester);

    await tester.ensureVisible(find.text('Export'));
    final export = find.text('Export');
    await tester.ensureVisible(export);
    await tester.tap(export);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Ready for their inbox.'), findsOneWidget);
    expect(find.text('PNG'), findsOneWidget);
    expect(find.text('JPEG'), findsOneWidget);

    // JPEG previews switch the primary action label.
    await tester.tap(find.text('JPEG'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Create JPEG'), findsOneWidget);

    await tester.tap(find.byTooltip('Close export'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Let the debounced autosave fire so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
  });

  testWidgets('details typing and the invite-actions sheet hold on a phone', (
    tester,
  ) async {
    setSize(tester, const Size(320, 568));
    final studio = await mountEditor(tester);

    // Type a long first name through the real details sheet.
    await tester.tap(find.text('Details').last);
    await tester.pumpAndSettle();
    final first = find.descendant(
      of: find.byKey(const ValueKey('field_first')),
      matching: find.byType(TextField),
    );
    await tester.ensureVisible(first);
    await tester.enterText(first, 'Muhammed Abdulrahman Umar');
    await tester.pumpAndSettle();
    expect(studio.fieldValue('first'), 'Muhammed Abdulrahman Umar');
    expect(tester.takeException(), isNull);

    // The calendar/RSVP actions sheet lays out beside the keyboard-safe area.
    final actionsButton = find.text('Calendar file, link & RSVP code');
    for (var i = 0; i < 8 && tester.widgetList(actionsButton).isEmpty; i++) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -200));
      await tester.pumpAndSettle();
    }
    while (tester.getRect(actionsButton).bottom > 568) {
      await tester.drag(find.byType(ListView).first, const Offset(0, -120));
      await tester.pumpAndSettle();
    }
    await tester.tap(actionsButton);
    await tester.pumpAndSettle();
    expect(find.text('Invitation actions'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.enterText(
      find.byKey(const ValueKey('rsvp_url')),
      'https://rsvp.example.com/our-day',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Close the sheet by tapping the scrim above it.
    await tester.tapAt(const Offset(10, 20));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close panel'));
    await tester.pumpAndSettle();

    // Let the debounced autosave fire so no timer outlives the test.
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
  });

  testWidgets('home wizard completes on the narrowest phone', (tester) async {
    setSize(tester, const Size(320, 568));
    final studio = StudioController(
      project: StudioProject.sample(),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: studioTheme(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: HomeScreen(studio: studio),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Birthday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();

    final footer = find.text('Choose a card');
    await tester.ensureVisible(footer);
    await tester.pumpAndSettle();
    await tester.tap(footer);
    await tester.pumpAndSettle();

    final designs = templatesFor(InvitationCategory.birthday);
    await tester.ensureVisible(find.text(designs.first.name).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(designs.first.name).first);
    await tester.pumpAndSettle();

    final create = find.text('Create invitation');
    await tester.ensureVisible(create);
    await tester.pumpAndSettle();
    await tester.tap(create);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(CanvasEditorWidget), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
