import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/video/timeline.dart';

void main() {
  group('timeline timing is deterministic', () {
    test('frame count and timestamps come from the frame index', () {
      const timeline = VideoTimeline(durationMs: 15000);
      expect(timeline.fps, TimelineLimits.fps);
      expect(timeline.frameCount, 450);
      expect(timeline.frameTimestampUs(0), 0);
      expect(timeline.frameTimestampUs(1), 33333);
      expect(timeline.frameTimestampUs(30), 1000000);
      expect(timeline.frameTimestampUs(449), 14966666);
      // Two calls with the same index are identical: no wall-clock input.
      expect(timeline.frameTimestampUs(123), timeline.frameTimestampUs(123));
    });

    test('easing endpoints and monotonicity', () {
      for (final easing in MotionEasing.values) {
        expect(easing.apply(0), 0);
        expect(easing.apply(1), 1);
        var previous = -1.0;
        for (var i = 0; i <= 20; i++) {
          final value = easing.apply(i / 20);
          expect(value, greaterThanOrEqualTo(previous));
          previous = value;
        }
      }
    });
  });

  group('evaluateTimeline', () {
    const ids = ['a'];

    test('defaults keep every layer fully visible', () {
      const timeline = VideoTimeline(durationMs: 10000);
      final frame = evaluateTimeline(timeline, ids, 5000);
      final visual = frame.visualFor('a');
      expect(visual.visible, isTrue);
      expect(visual.opacity, 1);
      expect(visual.offset, Offset.zero);
      expect(visual.scale, 1);
    });

    test('visibility window hides the layer outside its range', () {
      const timeline = VideoTimeline(
        durationMs: 10000,
        motions: {
          'a': LayerMotion(visibleStartMs: 2000, visibleEndMs: 6000),
        },
      );
      expect(evaluateTimeline(timeline, ids, 1999).visualFor('a').visible, isFalse);
      expect(evaluateTimeline(timeline, ids, 2000).visualFor('a').visible, isTrue);
      expect(evaluateTimeline(timeline, ids, 5999).visualFor('a').visible, isTrue);
      expect(evaluateTimeline(timeline, ids, 6000).visualFor('a').visible, isFalse);
    });

    test('fade entrance ramps opacity and respects delay', () {
      const timeline = VideoTimeline(
        durationMs: 10000,
        motions: {
          'a': LayerMotion(
            entrance: Motion(
              effect: MotionEffect.fade,
              durationMs: 1000,
              delayMs: 500,
              easing: MotionEasing.linear,
            ),
          ),
        },
      );
      expect(evaluateTimeline(timeline, ids, 0).visualFor('a').visible, isFalse);
      expect(evaluateTimeline(timeline, ids, 499).visualFor('a').visible, isFalse);
      expect(
        evaluateTimeline(timeline, ids, 500).visualFor('a').opacity,
        closeTo(0, 1e-9),
      );
      expect(
        evaluateTimeline(timeline, ids, 1000).visualFor('a').opacity,
        closeTo(.5, 1e-9),
      );
      expect(
        evaluateTimeline(timeline, ids, 1500).visualFor('a').opacity,
        closeTo(1, 1e-9),
      );
    });

    test('slide entrance starts offset and settles at zero', () {
      const timeline = VideoTimeline(
        durationMs: 10000,
        motions: {
          'a': LayerMotion(
            entrance: Motion(
              effect: MotionEffect.slideUp,
              durationMs: 1000,
              easing: MotionEasing.linear,
            ),
          ),
        },
      );
      expect(
        evaluateTimeline(timeline, ids, 0).visualFor('a').offset.dy,
        closeTo(TimelineLimits.slideDistance, 1e-9),
      );
      expect(
        evaluateTimeline(timeline, ids, 500).visualFor('a').offset.dy,
        closeTo(TimelineLimits.slideDistance / 2, 1e-9),
      );
      expect(
        evaluateTimeline(timeline, ids, 1000).visualFor('a').offset.dy,
        closeTo(0, 1e-9),
      );
    });

    test('zoom entrance scales from 0.9 and exit fades to zero', () {
      const timeline = VideoTimeline(
        durationMs: 5000,
        motions: {
          'a': LayerMotion(
            visibleEndMs: 4000,
            entrance: Motion(
              effect: MotionEffect.zoomIn,
              durationMs: 1000,
              easing: MotionEasing.linear,
            ),
            exit: Motion(
              effect: MotionEffect.fade,
              durationMs: 1000,
              easing: MotionEasing.linear,
            ),
          ),
        },
      );
      expect(
        evaluateTimeline(timeline, ids, 0).visualFor('a').scale,
        closeTo(.9, 1e-9),
      );
      expect(
        evaluateTimeline(timeline, ids, 1000).visualFor('a').scale,
        closeTo(1, 1e-9),
      );
      // Exit starts at 3000 and ends at 4000.
      expect(
        evaluateTimeline(timeline, ids, 3500).visualFor('a').opacity,
        closeTo(.5, 1e-9),
      );
      expect(evaluateTimeline(timeline, ids, 3999).visualFor('a').visible, isTrue);
    });

    test('layers without a motion entry are visible for the whole timeline', () {
      const timeline = VideoTimeline(
        durationMs: 5000,
        motions: {
          'a': LayerMotion(visibleEndMs: 1000),
        },
      );
      final frame = evaluateTimeline(timeline, ['a', 'b'], 4000);
      expect(frame.visualFor('a').visible, isFalse);
      expect(frame.visualFor('b').visible, isTrue);
    });
  });

  group('validation', () {
    const ids = {'a', 'b'};

    test('duration bounds', () {
      expect(
        const VideoTimeline(durationMs: 4000).validate(layerIds: ids),
        isNotEmpty,
      );
      expect(
        const VideoTimeline(durationMs: 31000).validate(layerIds: ids),
        isNotEmpty,
      );
      expect(const VideoTimeline(durationMs: 15000).validate(layerIds: ids), isEmpty);
    });

    test('motions must refer to existing layers', () {
      const timeline = VideoTimeline(
        durationMs: 15000,
        motions: {'missing': LayerMotion(visibleEndMs: 5000)},
      );
      expect(timeline.validate(layerIds: ids), isNotEmpty);
    });

    test('music must start before the invitation ends', () {
      const timeline = VideoTimeline(
        durationMs: 5000,
        audio: VideoAudio(assetId: 'audio_1', startMs: 5000),
      );
      expect(timeline.validate(layerIds: ids), isNotEmpty);
    });

    test('clip background requires an asset id', () {
      const timeline = VideoTimeline(
        durationMs: 15000,
        background: VideoBackground(kind: BackgroundKind.clip),
      );
      expect(timeline.validate(layerIds: ids), isNotEmpty);
    });
  });

  group('JSON', () {
    test('round-trips every supported field', () {
      const timeline = VideoTimeline(
        enabled: true,
        durationMs: 12000,
        background: VideoBackground(
          kind: BackgroundKind.clip,
          assetId: 'clip_abc',
          trimStartMs: 500,
          trimEndMs: 4000,
          fit: 'contain',
          loop: false,
        ),
        motions: {
          'title': LayerMotion(
            visibleStartMs: 1000,
            visibleEndMs: 9000,
            entrance: Motion(
              effect: MotionEffect.slideLeft,
              durationMs: 700,
              delayMs: 100,
              easing: MotionEasing.easeInOut,
            ),
            exit: Motion(effect: MotionEffect.zoomOut, durationMs: 400),
          ),
        },
        audio: VideoAudio(
          assetId: 'audio_abc',
          title: 'Song',
          startMs: 250,
          trimStartMs: 1000,
          trimEndMs: 9000,
          volume: 40,
          fadeInMs: 300,
          fadeOutMs: 900,
        ),
      );
      final decoded = VideoTimeline.decode(timeline.toJson());
      expect(decoded.enabled, isTrue);
      expect(decoded.durationMs, 12000);
      expect(decoded.background.assetId, 'clip_abc');
      expect(decoded.background.fit, 'contain');
      expect(decoded.background.loop, isFalse);
      expect(decoded.motions['title']!.entrance.effect, MotionEffect.slideLeft);
      expect(decoded.motions['title']!.exit.effect, MotionEffect.zoomOut);
      expect(decoded.audio!.volume, 40);
      expect(decoded.audio!.trimEndMs, 9000);
    });

    test('rejects unknown effects, fps and out-of-range duration', () {
      expect(
        () => VideoTimeline.decode({
          'durationMs': 15000,
          'fps': 24,
        }),
        throwsFormatException,
      );
      expect(
        () => VideoTimeline.decode({
          'durationMs': 15000,
          'motions': {
            'a': {
              'entrance': {
                'effect': 'explode',
                'durationMs': 500,
                'delayMs': 0,
                'easing': 'linear',
              },
            },
          },
        }),
        throwsFormatException,
      );
      expect(
        () => VideoTimeline.decode({'durationMs': 30000.5}),
        throwsFormatException,
      );
    });

    test('legacy projects without a video key decode to defaults', () {
      final decoded = VideoTimeline.decode(null);
      expect(decoded.enabled, isFalse);
      expect(decoded.durationMs, 15000);
      expect(decoded.audio, isNull);
      expect(decoded.motions, isEmpty);
    });
  });
}
