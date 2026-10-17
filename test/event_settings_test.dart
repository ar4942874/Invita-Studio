import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/category_music.dart';
import 'package:invitation_studio/domain/event_schedule.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/domain/video/timeline.dart';
import 'package:invitation_studio/services/draft_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

StudioProject _project({
  InvitationCategory category = InvitationCategory.wedding,
  VideoAudio? audio,
}) {
  const id = 'p_settings';
  return StudioProject(
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
      audio: audio ?? CategoryMusic.forCategory(category),
    ),
  );
}

Future<StudioController> _controller({
  StudioProject? project,
  List<StudioProject>? drafts,
}) async {
  final studio = StudioController(
    project: project ?? _project(),
    store: MemoryProjectStore(),
    drafts: drafts,
  );
  await studio.catalogLoaded;
  return studio;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('event settings', () {
    test('changing the celebration swaps the bundled tune', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);

      await studio.updateEventSettings(category: InvitationCategory.birthday);

      expect(studio.project.category, InvitationCategory.birthday);
      final audio = studio.project.video.audio!;
      expect(audio.assetId, CategoryMusic.tuneId(InvitationCategory.birthday));
      expect(audio.title, CategoryMusic.title(InvitationCategory.birthday));
      expect(
        audio.durationMs,
        CategoryMusic.durationFor(InvitationCategory.birthday),
      );
      // The mix settings survive the swap.
      expect(audio.volume, CategoryMusic.volume);
      expect(audio.fadeInMs, CategoryMusic.fadeInMs);
    });

    test('imported music is never replaced by a bundled tune', () async {
      final studio = await _controller(
        project: _project(
          audio: const VideoAudio(assetId: 'audio_7', title: 'Song', volume: 70),
        ),
      );
      addTearDown(studio.dispose);

      await studio.updateEventSettings(category: InvitationCategory.engagement);

      expect(studio.project.category, InvitationCategory.engagement);
      expect(studio.project.video.audio!.assetId, 'audio_7');
      expect(studio.project.video.audio!.volume, 70);
    });

    test('a matching design is applied and the words are kept', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      await studio.setField('first', 'Zara');
      await studio.flush();
      final target = templatesFor(InvitationCategory.birthday).last;

      await studio.updateEventSettings(
        category: InvitationCategory.birthday,
        template: target,
      );
      await studio.flush();

      expect(studio.template.id, target.id);
      expect(studio.fieldValue('first'), 'Zara');
      expect(studio.project.category, InvitationCategory.birthday);
    });

    test('the same template is not reflowed twice', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      final before = studio.document;

      await studio.updateEventSettings(
        category: InvitationCategory.wedding,
        template: studio.template,
      );
      await studio.flush();

      expect(studio.document.nodes.length, before.nodes.length);
      expect(studio.project.category, InvitationCategory.wedding);
    });
  });

  group('duplicate draft', () {
    test('forks a new draft and opens it', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      final source = studio.project;

      final copy = await studio.duplicateProject(source);

      expect(copy.id, isNot(source.id));
      expect(copy.document.id, copy.id, reason: 'the document follows the ID');
      expect(copy.title, 'Ayesha & Hamza (copy)');
      expect(copy.category, source.category);
      expect(studio.project.id, copy.id, reason: 'the copy becomes active');
      expect(studio.drafts.map((d) => d.id), containsAll([source.id, copy.id]));
      expect(studio.drafts.length, 2);
      expect(source.title, 'Ayesha & Hamza', reason: 'the original is intact');
    });

    test('keeps a copy title inside the 80 character limit', () async {
      final long = 'A' * 80;
      final studio = await _controller(project: _project().copyWith(title: long));
      addTearDown(studio.dispose);

      final copy = await studio.duplicateProject(studio.project);

      expect(copy.title.length, lessThanOrEqualTo(80));
      expect(copy.title, endsWith(' (copy)'));
    });

    test('refuses a 13th draft instead of silently dropping one', () async {
      final drafts = [
        for (var i = 0; i < 12; i++)
          _project().copyWith(title: 'Draft $i').fork(id: 'p_$i', title: 'Draft $i'),
      ];
      final studio = StudioController(
        project: drafts.first,
        store: MemoryProjectStore(),
        drafts: drafts,
      );
      addTearDown(studio.dispose);
      await studio.catalogLoaded;

      await expectLater(
        studio.duplicateProject(drafts.first),
        throwsStateError,
      );
    });
  });

  group('structured event on the project', () {
    test('survives a save and load round trip', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      const when = EventDateTime(date: '2026-12-12', hour: 19, minute: 0);

      await studio.setSchedule(when);
      await studio.setRsvpUrl('https://rsvp.example.com/ayesha');

      final decoded = StudioProject.decode(studio.project.encode());
      expect(decoded.when, when);
      expect(decoded.rsvpUrl, 'https://rsvp.example.com/ayesha');
    });

    test('can be cleared again', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      await studio.setSchedule(const EventDateTime(date: '2026-12-12'));
      await studio.setRsvpUrl('https://rsvp.example.com');

      await studio.setSchedule(null);
      await studio.setRsvpUrl('  ');

      expect(studio.project.when, isNull);
      expect(studio.project.rsvpUrl, isNull);
      final decoded = StudioProject.decode(studio.project.encode());
      expect(decoded.when, isNull);
      expect(decoded.rsvpUrl, isNull);
    });

    test('a hostile RSVP link is rejected when the file is opened', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      final json =
          jsonDecode(studio.project.encode()) as Map<String, dynamic>;
      json['rsvpUrl'] = 'javascript:alert(1)';
      expect(
        () => StudioProject.decode(jsonEncode(json)),
        throwsFormatException,
      );
    });

    test('a damaged date is rejected rather than guessed', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      final json =
          jsonDecode(studio.project.encode()) as Map<String, dynamic>;
      json['when'] = {'date': '2026-02-31'};
      expect(
        () => StudioProject.decode(jsonEncode(json)),
        throwsFormatException,
      );
    });
  });

  group('catalogue preferences', () {
    test('using a design records it as recent', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      final design = templatesFor(InvitationCategory.wedding)[3];

      await studio.chooseTemplate(design);
      await studio.flush();

      expect(studio.recentDesigns.first, design.id);
    });

    test('starring is idempotent per design and persists', () async {
      final studio = await _controller();
      addTearDown(studio.dispose);
      final design = templatesFor(InvitationCategory.wedding).first;

      studio.toggleFavourite(design.id);
      expect(studio.isFavourite(design.id), isTrue);
      studio.toggleFavourite(design.id);
      expect(studio.isFavourite(design.id), isFalse);

      studio.toggleFavourite(design.id);
      final reopened = await _controller();
      addTearDown(reopened.dispose);
      // A fresh controller reads the stored set through the same mock store.
      await reopened.catalogLoaded;
      expect(reopened.isFavourite(design.id), isTrue);
    });
  });
}
