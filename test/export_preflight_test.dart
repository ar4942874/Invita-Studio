import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/category_music.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/video/timeline.dart';
import 'package:invitation_studio/services/video/export_media.dart';
import 'package:invitation_studio/services/video/export_preflight.dart';
import 'package:invitation_studio/services/video/video_media.dart';

import 'support/fake_video_media.dart';

VideoTimeline _timeline({VideoAudio? audio, bool clip = false}) => VideoTimeline(
  durationMs: 15000,
  background: VideoBackground(
    kind: clip ? BackgroundKind.clip : BackgroundKind.artwork,
    assetId: clip ? 'clip_1' : null,
  ),
  audio: audio,
);

ExportPreflight _preflight(
  VideoTimeline timeline, {
  bool clipPresent = true,
  bool audioPresent = true,
  bool isWeb = false,
  bool encoderSupported = true,
  int outputWidth = 1080,
}) => buildExportPreflight(
  timeline: timeline,
  documentWidth: 1080,
  documentHeight: 1512,
  outputWidth: outputWidth,
  encoderSupported: encoderSupported,
  clipPresent: clipPresent,
  audioPresent: audioPresent,
  isWeb: isWeb,
);

ExportPreflightItem _item(ExportPreflight preflight, ExportCheck check) =>
    preflight.items.firstWhere((item) => item.check == check);

void main() {
  group('when an export needs the music file', () {
    const audible = VideoAudio(assetId: 'audio_1', volume: 80);
    const muted = VideoAudio(assetId: 'audio_1', volume: 0);

    test('native and audible: required', () {
      expect(exportNeedsAudio(audible, isWeb: false), isTrue);
    });

    test('muted: never required, because the MP4 has no audio track', () {
      expect(exportNeedsAudio(muted, isWeb: false), isFalse);
    });

    test('browser: never required, because the export is silent', () {
      expect(exportNeedsAudio(audible, isWeb: true), isFalse);
      expect(exportNeedsAudio(muted, isWeb: true), isFalse);
    });

    test('no track at all: nothing to resolve', () {
      expect(exportNeedsAudio(null, isWeb: false), isFalse);
    });
  });

  group('resolving the export audio', () {
    test('a bundled tune is loaded from the bundle, not from storage', () async {
      final media = FakeVideoMedia(
        tune: const ImportedAudio(
          assetId: 'tune_wedding',
          title: 'Wedding theme',
          durationMs: 7866,
          path: '/tmp/tune_wedding.wav',
        ),
      );
      final audio = await resolveExportAudio(
        media: media,
        projectId: 'p_1',
        audio: CategoryMusic.forCategory(InvitationCategory.wedding),
        isWeb: false,
      );
      expect(audio, isNotNull);
      expect(audio!.assetId, 'tune_wedding');
      expect(media.tuneLoads, 1);
      expect(
        media.trackLoads,
        0,
        reason: 'a tune must never be looked up in managed storage',
      );
    });

    test('imported music is looked up in managed storage', () async {
      final media = FakeVideoMedia(
        track: const ImportedAudio(
          assetId: 'audio_7',
          title: 'Song',
          durationMs: 60000,
          path: '/tmp/song.m4a',
        ),
      );
      final audio = await resolveExportAudio(
        media: media,
        projectId: 'p_1',
        audio: const VideoAudio(assetId: 'audio_7', title: 'Song', volume: 70),
        isWeb: false,
      );
      expect(audio!.path, '/tmp/song.m4a');
      expect(media.trackLoads, 1);
      expect(media.tuneLoads, 0);
    });

    test('a browser export touches no storage at all', () async {
      final media = FakeVideoMedia();
      final audio = await resolveExportAudio(
        media: media,
        projectId: 'p_1',
        audio: CategoryMusic.forCategory(InvitationCategory.wedding),
        isWeb: true,
      );
      expect(audio, isNull);
      expect(media.tuneLoads, 0);
      expect(media.trackLoads, 0);
    });

    test('a muted track is not loaded', () async {
      final media = FakeVideoMedia();
      final audio = await resolveExportAudio(
        media: media,
        projectId: 'p_1',
        audio: const VideoAudio(assetId: 'audio_7', volume: 0),
        isWeb: false,
      );
      expect(audio, isNull);
      expect(media.trackLoads, 0);
    });
  });

  group('preflight checklist', () {
    test('a new project with its bundled tune is ready', () {
      final preflight = _preflight(
        _timeline(audio: CategoryMusic.forCategory(InvitationCategory.wedding)),
      );
      expect(preflight.canExport, isTrue);
      expect(preflight.blockers, isEmpty);
      final music = _item(preflight, ExportCheck.music);
      expect(music.ok, isTrue);
      expect(music.title, 'Wedding theme');
      expect(preflight.silent, isFalse);
      final artwork = _item(preflight, ExportCheck.artwork);
      expect(artwork.title, 'Artwork background');
    });

    test('a missing background clip blocks the export and offers re-import', () {
      final preflight = _preflight(_timeline(clip: true), clipPresent: false);
      expect(preflight.canExport, isFalse);
      expect(preflight.blockers, hasLength(1));
      final clip = _item(preflight, ExportCheck.artwork);
      expect(clip.blocking, isTrue);
      expect(clip.fix, ExportFix.reimportClip);
      expect(clip.fixLabel, 'Re-import clip');
      expect(clip.detail, contains('not on this device'));
    });

    test('on the web a missing clip explains the session-only store', () {
      final preflight = _preflight(
        _timeline(clip: true),
        clipPresent: false,
        isWeb: true,
      );
      expect(_item(preflight, ExportCheck.artwork).detail, contains('session'));
    });

    test('missing music blocks on native and offers one-tap removal', () {
      final preflight = _preflight(
        _timeline(audio: const VideoAudio(assetId: 'audio_9', volume: 60)),
        audioPresent: false,
      );
      expect(preflight.canExport, isFalse);
      final music = _item(preflight, ExportCheck.music);
      expect(music.blocking, isTrue);
      expect(music.fix, ExportFix.removeMusic);
      expect(music.fixLabel, 'Remove music');
      // Silencing is the other legitimate repair, and it keeps the settings.
      expect(music.alternateFix, ExportFix.muteMusic);
      expect(music.alternateFixLabel, 'Switch to silent');
    });

    test('a muted track is a deliberate silent export, not a problem', () {
      final preflight = _preflight(
        _timeline(audio: const VideoAudio(assetId: 'audio_9', volume: 0)),
        audioPresent: false,
      );
      expect(preflight.canExport, isTrue);
      expect(_item(preflight, ExportCheck.music).title, 'Music muted');
      expect(preflight.silent, isTrue);
    });

    test('the browser never blocks on music and says the file is silent', () {
      final preflight = _preflight(
        _timeline(audio: CategoryMusic.forCategory(InvitationCategory.other)),
        audioPresent: false,
        isWeb: true,
      );
      expect(preflight.canExport, isTrue);
      expect(preflight.silent, isTrue);
      final browser = _item(preflight, ExportCheck.browser);
      expect(browser.detail, contains('no audio track'));
      expect(_item(preflight, ExportCheck.music).ok, isTrue);
    });

    test('an unavailable encoder is the blocker on desktop builds', () {
      final preflight = _preflight(_timeline(), encoderSupported: false);
      expect(preflight.canExport, isFalse);
      expect(_item(preflight, ExportCheck.encoder).blocking, isTrue);
    });

    test('output dimensions, size and time follow the chosen quality', () {
      final full = _preflight(_timeline(), outputWidth: 1080);
      final light = _preflight(_timeline(), outputWidth: 540);
      expect([full.outputWidth, full.outputHeight], [1080, 1512]);
      expect([light.outputWidth, light.outputHeight], [540, 756]);
      expect(full.frameCount, 450);
      expect(_item(full, ExportCheck.output).detail, contains('450 frames'));

      // 15 s at 8 Mbps (+2 % container) and at 3 Mbps.
      expect(full.estimatedBytes, 15300000);
      expect(light.estimatedBytes, 5737500);
      expect(full.estimatedSeconds, greaterThan(light.estimatedSeconds));
      expect(full.sizeLabel, '14.6 MB');
    });

    test('the checklist never claims a track it cannot hear', () {
      // Audible music that is present still reports the AAC track it will write.
      final native = _preflight(
        _timeline(audio: const VideoAudio(assetId: 'audio_9', volume: 60)),
      );
      expect(_item(native, ExportCheck.music).detail, contains('AAC'));
      expect(native.silent, isFalse);

      // ...and the browser reports preview-only playback instead.
      final web = _preflight(
        _timeline(audio: const VideoAudio(assetId: 'audio_9', volume: 60)),
        isWeb: true,
      );
      expect(_item(web, ExportCheck.music).title, contains('preview only'));
      expect(web.silent, isTrue);
    });
  });
}
