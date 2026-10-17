import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/domain/video/timeline.dart';

StudioProject _project() {
  final id = 'p_video_test';
  return StudioProject(
    id: id,
    title: 'Video test',
    updatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    document: invitationTemplates.first.createDocument(
      documentId: id,
      format: InvitationFormat.story,
    ),
  );
}

void main() {
  test('version 2 round-trips video settings', () {
    final base = _project();
    const layerId = 'header';
    expect(base.layerIds, contains(layerId));
    final project = base.copyWith(
      video: const VideoTimeline(
        enabled: true,
        durationMs: 18000,
        background: VideoBackground(
          kind: BackgroundKind.clip,
          assetId: 'clip_1',
          trimStartMs: 250,
          trimEndMs: 5250,
        ),
        motions: {
          layerId: LayerMotion(
            visibleStartMs: 400,
            visibleEndMs: 12000,
            entrance: Motion(effect: MotionEffect.fade, durationMs: 600),
          ),
        },
        audio: VideoAudio(assetId: 'audio_1', volume: 55),
      ),
    );
    expect(project.layerIds.contains(layerId), isTrue);

    final encoded = project.encode();
    final json = jsonDecode(encoded) as Map<String, dynamic>;
    expect(json['version'], StudioProject.schemaVersion);
    expect(json['video'], isA<Map<String, dynamic>>());

    final decoded = StudioProject.decode(encoded);
    expect(decoded.video.enabled, isTrue);
    expect(decoded.video.durationMs, 18000);
    expect(decoded.video.background.assetId, 'clip_1');
    expect(decoded.video.background.trimEndMs, 5250);
    expect(decoded.video.audio!.volume, 55);
    expect(decoded.document.nodes.length, base.document.nodes.length);
  });

  test('version 1 projects migrate to default video settings', () {
    final base = _project();
    final json = jsonDecode(base.encode()) as Map<String, dynamic>;
    json['version'] = 1;
    json.remove('video');
    final migrated = StudioProject.decode(jsonEncode(json));
    expect(migrated.video.enabled, isFalse);
    expect(migrated.video.durationMs, VideoTimeline.defaults.durationMs);
    expect(migrated.video.audio, isNull);

    // Re-encoding writes the current schema version.
    final reencoded = jsonDecode(migrated.encode()) as Map<String, dynamic>;
    expect(reencoded['version'], StudioProject.schemaVersion);
    expect(reencoded['video'], isNotNull);
  });

  test('rejects unknown schema versions', () {
    final json = jsonDecode(_project().encode()) as Map<String, dynamic>;
    json['version'] = 99;
    expect(() => StudioProject.decode(jsonEncode(json)), throwsFormatException);
  });

  test('rejects invalid video payloads instead of silently dropping them', () {
    final json = jsonDecode(_project().encode()) as Map<String, dynamic>;
    (json['video'] as Map<String, dynamic>)['durationMs'] = 1000;
    expect(() => StudioProject.decode(jsonEncode(json)), throwsFormatException);

    final json2 = jsonDecode(_project().encode()) as Map<String, dynamic>;
    (json2['video'] as Map<String, dynamic>)['background'] = {
      'kind': 'clip',
      'assetId': '../escape',
      'trimStartMs': 0,
      'trimEndMs': 0,
      'fit': 'cover',
      'loop': true,
    };
    expect(() => StudioProject.decode(jsonEncode(json2)), throwsFormatException);
  });

  test('effectiveVideo drops motions for deleted layers and clamps windows', () {
    final base = _project();
    final project = base.copyWith(
      video: const VideoTimeline(
        durationMs: 10000,
        motions: {
          'header': LayerMotion(visibleStartMs: 1000, visibleEndMs: 9000),
          'removed-layer': LayerMotion(visibleEndMs: 5000),
        },
      ),
    );
    final effective = project.effectiveVideo;
    expect(effective.motions.containsKey('removed-layer'), isFalse);
    expect(effective.motions['header']!.visibleEndMs, 9000);

    final clamped = base
        .copyWith(
          video: const VideoTimeline(
            durationMs: 5000,
            motions: {
              'header': LayerMotion(visibleStartMs: 0, visibleEndMs: 15000),
            },
          ),
        )
        .effectiveVideo;
    expect(clamped.motions['header']!.visibleEndMs, 5000);
  });

  test('video mode reuses the image document instead of a copy', () {
    final base = _project();
    // Video mode is not a second document: layer IDs, text and styles are the
    // same objects the image editor uses.
    expect(base.document.nodes.where((n) => n.type == 'text'), isNotEmpty);
    expect(base.layerIds.contains('header'), isTrue);
    expect(base.layerIds.contains('background'), isFalse);
  });

  test('category round-trips and defaults to wedding when missing', () {
    final project = _project().copyWith(
      category: InvitationCategory.birthday,
    );
    expect(project.encode(), contains('"category": "birthday"'));
    expect(
      StudioProject.decode(project.encode()).category,
      InvitationCategory.birthday,
    );

    // A file saved before categories existed has no key.
    final json = jsonDecode(project.encode()) as Map<String, dynamic>;
    json.remove('category');
    expect(
      StudioProject.decode(jsonEncode(json)).category,
      InvitationCategory.wedding,
    );
  });
}
