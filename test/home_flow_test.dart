import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/services/bundled_fonts.dart'
    show loadStudioFonts;
import 'package:invitation_studio/services/draft_store.dart';
import 'package:invitation_studio/ui/home_screen.dart';
import 'package:invitation_studio/ui/studio_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);

  group('InvitationCategory', () {
    test('seeds wording and derives a title from the names', () {
      final seeds = InvitationCategory.birthday.seedFields();
      expect(seeds['header'], 'PLEASE JOIN US TO CELEBRATE');
      expect(seeds['first'], isNotEmpty);

      expect(
        InvitationCategory.wedding.titleFor({'first': 'Ayesha', 'second': 'Hamza'}),
        'Ayesha & Hamza',
      );
      expect(InvitationCategory.birthday.titleFor({'first': 'Sam'}), 'Sam');
      expect(InvitationCategory.other.titleFor(const {}), 'Something else');
    });

    test('wire names round-trip and unknown values fall back', () {
      expect(
        InvitationCategory.fromWire('babyShower'),
        InvitationCategory.babyShower,
      );
      expect(InvitationCategory.fromWire('nope'), isNull);
      expect(InvitationCategory.fromWire(null), isNull);
    });
  });

  testWidgets('wizard creates a project from category, details and card', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final studio = StudioController(
      project: StudioProject.sample(),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);

    await tester.pumpWidget(
      MaterialApp(theme: studioTheme(), home: HomeScreen(studio: studio)),
    );
    await tester.pumpAndSettle();

    // Step 1: choose a category.
    expect(find.text('What are we celebrating?'), findsOneWidget);
    await tester.tap(find.text('Birthday'));
    await tester.pumpAndSettle();

    // Step 2: the details form is seeded with the category wording.
    expect(find.text('First name'), findsOneWidget);
    final firstName = find.descendant(
      of: find.byKey(const ValueKey('home_field_first')),
      matching: find.byType(TextField),
    );
    await tester.enterText(firstName, 'Sana');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose a card'));
    await tester.pumpAndSettle();

    // Step 3: pick a card and create.
    expect(find.text('Choose a card'), findsWidgets);
    final birthdayDesigns = templatesFor(InvitationCategory.birthday);
    expect(birthdayDesigns.length, 10);
    await tester.tap(find.text(birthdayDesigns.first.name).first);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Create invitation'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create invitation'));
    await tester.pumpAndSettle();

    // The editor opened on a fresh project with the chosen category and value.
    expect(find.byType(CanvasEditorWidget), findsOneWidget);
    expect(studio.project.category, InvitationCategory.birthday);
    expect(studio.project.title, 'Sana & Hamza');
    expect(studio.fieldValue('first'), 'Sana');
    expect(templateFor(studio.document).id, birthdayDesigns.first.id);
    // The birthday tune is pre-selected.
    expect(studio.project.video.audio?.assetId, 'tune_birthday');

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
