import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/category_music.dart';
import 'package:invitation_studio/domain/event_schedule.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/domain/video/timeline.dart';
import 'package:invitation_studio/services/bundled_fonts.dart' show loadStudioFonts;
import 'package:invitation_studio/services/draft_store.dart';
import 'package:invitation_studio/ui/event_settings_sheet.dart';
import 'package:invitation_studio/ui/invite_actions_sheet.dart';
import 'package:invitation_studio/ui/widgets/qr_code.dart';
import 'package:invitation_studio/ui/widgets/panels.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<StudioController> _studio({
  InvitationCategory category = InvitationCategory.wedding,
}) async {
  const id = 'p_panel';
  final project = StudioProject(
    id: id,
    title: 'Ayesha & Hamza',
    updatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    category: category,
    document: templatesFor(category).first.createDocument(
      documentId: id,
      format: InvitationFormat.classic,
    ),
    video: VideoTimeline(
      enabled: true,
      audio: CategoryMusic.forCategory(category),
    ),
  );
  final studio = StudioController(
    project: project,
    store: MemoryProjectStore(),
  );
  await studio.catalogLoaded;
  return studio;
}

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  StudioController? studio,
  Size size = const Size(390, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));
  await tester.pumpAndSettle();
  // Cancel the 650 ms autosave debounce: a widget test must not end with a
  // pending timer, and the controller schedules one on construction.
  await studio?.saveNow();
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the catalogue opens on the project category', (tester) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(tester, TemplatesPanel(studio: studio), studio: studio);

    expect(find.text('For you'), findsOneWidget);
    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('10 designs'), findsOneWidget);
    expect(find.text('Botanical'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"All designs" reaches the whole sixty', (tester) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(tester, TemplatesPanel(studio: studio), studio: studio);

    await tester.tap(find.text('All designs'));
    await tester.pumpAndSettle();

    expect(find.text('60 designs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('"All designs" pages instead of building sixty tiles', (
    tester,
  ) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(tester, TemplatesPanel(studio: studio), studio: studio);

    await tester.tap(find.text('All designs'));
    await tester.pumpAndSettle();

    // The whole catalogue is still counted...
    expect(find.text('60 designs'), findsOneWidget);
    // ...but only the rows in the viewport exist. The old Wrap built and
    // decoded all sixty at once.
    final built = find.byWidgetPredicate(
      (widget) =>
          widget.key is ValueKey<String> &&
          (widget.key! as ValueKey<String>).value.startsWith('design_'),
    );
    expect(built.evaluate().length, lessThan(10));
    expect(
      find.byKey(const ValueKey('design_arches_birthday')),
      findsNothing,
      reason: 'the 25th design is on page two and must not be built',
    );

    final showMore = find.textContaining('Show more');

    /// Scrolls [finder] into the viewport. A sliver builds a little past the
    /// viewport (cache extent), so finding it is not the same as seeing it —
    /// a tap on a cached-but-offscreen widget misses.
    Future<void> reveal(Finder finder) async {
      await tester.scrollUntilVisible(
        finder,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
    }

    await reveal(showMore);
    expect(find.text('Show more (36 left)'), findsOneWidget);
    expect(find.byKey(const ValueKey('design_arches_birthday')), findsNothing);

    // One page more: the second page starts with the 25th design.
    await tester.tap(showMore);
    await tester.pumpAndSettle();
    await reveal(find.byKey(const ValueKey('design_arches_birthday')));
    expect(
      find.byKey(const ValueKey('design_arches_birthday')),
      findsOneWidget,
    );
    await reveal(showMore);
    expect(find.text('Show more (12 left)'), findsOneWidget);

    // All sixty are in, so the button retires rather than hanging around.
    await tester.tap(showMore);
    await tester.pumpAndSettle();
    expect(find.textContaining('Show more'), findsNothing);
    await reveal(find.byKey(const ValueKey('design_sunburst_other')));
    expect(find.byKey(const ValueKey('design_sunburst_other')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await studio.saveNow();
  });

  testWidgets('design tiles decode thumbnails at their display width', (
    tester,
  ) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(tester, TemplatesPanel(studio: studio), studio: studio);

    final tile = find.byKey(const ValueKey('design_botanical_wedding'));
    expect(tile, findsOneWidget);
    final image = tester.widget<Image>(
      find.descendant(of: tile, matching: find.byType(Image)),
    );
    // `cacheWidth` is applied by wrapping the provider in a ResizeImage; that
    // is the value that bounds the decoded bitmap.
    final decode = image.image as ResizeImage;
    // A 167 px tile at DPR 1 decodes at its own size, never the 360 px source
    // and certainly not the 2160 px artwork.
    expect(decode.width, isNotNull);
    expect(decode.width, lessThanOrEqualTo(360));
    expect(decode.width, greaterThanOrEqualTo(160));
  });

  testWidgets('each tile names the composition it will draw', (tester) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(tester, TemplatesPanel(studio: studio), studio: studio);

    final tile = find.byKey(const ValueKey('design_botanical_wedding'));
    expect(
      find.descendant(of: tile, matching: find.text('Centred')),
      findsOneWidget,
    );
    // The category's designs are not all one arrangement.
    expect(
      templatesFor(InvitationCategory.wedding)
          .map((design) => design.layout)
          .toSet()
          .length,
      greaterThan(1),
    );
    expect(tester.takeException(), isNull);
    await studio.saveNow();
  });

  testWidgets('starring a design puts it in favourites', (tester) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(tester, TemplatesPanel(studio: studio), studio: studio);

    await tester.tap(find.byTooltip('Save to favourites').first);
    await tester.pumpAndSettle();
    expect(studio.favourites, hasLength(1));

    await tester.tap(find.text('Favourites'));
    await tester.pumpAndSettle();

    expect(find.text('1 design'), findsOneWidget);
    expect(find.byTooltip('Remove from favourites'), findsOneWidget);
  });

  testWidgets('"Surprise me" always changes the card', (tester) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(tester, TemplatesPanel(studio: studio), studio: studio);
    final before = studio.template.id;

    await tester.tap(find.text('Surprise me'));
    await tester.pumpAndSettle();

    expect(studio.template.id, isNot(before));
    expect(tester.takeException(), isNull);
    await studio.saveNow();
  });

  testWidgets('recently used lists the last design applied', (tester) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(tester, TemplatesPanel(studio: studio), studio: studio);

    // Applied while the tree is mounted: `flush()` is unusable here because its
    // zero-delay timer never fires under the test's fake clock.
    final design = templatesFor(InvitationCategory.wedding)[2];
    unawaited(studio.chooseTemplate(design));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Recent'));
    await tester.pumpAndSettle();

    expect(find.text('1 design'), findsOneWidget);
    expect(studio.recentDesigns.first, design.id);
    await studio.saveNow();
  });

  testWidgets('event settings changes the celebration and the tune', (
    tester,
  ) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await _pump(
      tester,
      studio: studio,
      Builder(
        builder: (context) => Center(
          child: TextButton(
            onPressed: () => EventSettingsSheet.show(context, studio),
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Event settings'), findsOneWidget);

    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(studio.project.category, InvitationCategory.birthday);
    expect(
      studio.project.video.audio!.assetId,
      CategoryMusic.tuneId(InvitationCategory.birthday),
    );
    expect(
      studio.template.categories,
      contains(InvitationCategory.birthday),
      reason: 'a birthday card is chosen when the old one does not suit',
    );
    expect(tester.takeException(), isNull);
    await studio.saveNow();
  });

  testWidgets('invitation actions renders the event and an RSVP code', (
    tester,
  ) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await studio.setSchedule(
      const EventDateTime(date: '2026-12-12', hour: 19, minute: 0),
    );
    await studio.setRsvpUrl('https://rsvp.example.com/ayesha');

    await _pump(tester, InviteActionsSheet(studio: studio), studio: studio);

    expect(
      find.textContaining('Saturday, 12 December 2026'),
      findsOneWidget,
    );
    expect(find.text('Save .ics'), findsOneWidget);
    expect(find.text('Google Calendar'), findsOneWidget);
    expect(find.byType(QrCodeView), findsOneWidget);
    expect(find.text('Scanning opens your RSVP page.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the details panel shows the structured calendar line', (
    tester,
  ) async {
    final studio = await _studio();
    addTearDown(studio.dispose);
    await studio.setSchedule(
      const EventDateTime(date: '2026-12-12', hour: 19, minute: 0),
    );

    await _pump(
      tester,
      DetailsPanel(studio: studio, onTemplates: () {}),
      studio: studio,
    );

    expect(
      find.textContaining('Calendar: Saturday, 12 December 2026'),
      findsOneWidget,
    );
    expect(find.text('Calendar file, link & RSVP code'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
