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
        expect(easing.apply(0), closeTo(0, 1e-9));
        expect(easing.apply(1), closeTo(1, 1e-9));
        if (easing == MotionEasing.easeOutBack) {
          // Overshoots past 1 before settling: the spring/pop feel is not
          // monotonic by design.
          expect(easing.apply(0.8), greaterThan(1));
          continue;
        }
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

    test('zoom entrance scales from 0.82 and exit fades to zero', () {
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
        closeTo(.82, 1e-9),
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

  group('MotionPreset', () {
    const ids = ['header', 'first', 'second'];

    test('none writes a static card and matches an empty timeline', () {
      final built = MotionPreset.none.build(layerIds: ids, durationMs: 15000);
      expect(built, isEmpty);
      expect(
        MotionPreset.none.matches(
          layerIds: ids,
          durationMs: 15000,
          motions: const {},
        ),
        isTrue,
      );
    });

    test('rise, zoomIn and zoomOut animate every layer with a full window', () {
      Map<String, MotionEffect> effectsFor(MotionPreset preset) {
        final built = preset.build(layerIds: ids, durationMs: 15000);
        expect(built.keys, containsAll(ids));
        return {
          for (final entry in built.entries) entry.key: entry.value.entrance.effect,
        };
      }

      expect(effectsFor(MotionPreset.rise)['first'], MotionEffect.slideUp);
      expect(effectsFor(MotionPreset.zoomIn)['first'], MotionEffect.zoomIn);
      expect(effectsFor(MotionPreset.zoomOut)['first'], MotionEffect.zoomOut);

      final layer = MotionPreset.rise
          .build(layerIds: ids, durationMs: 15000)['first']!;
      expect(layer.visibleStartMs, 0);
      expect(layer.visibleEndMs, 15000);
      expect(layer.exit.isAnimated, isFalse);
    });

    test('fade, pop and slide use their signature effects', () {
      Map<String, MotionEffect> effectsFor(MotionPreset preset) => {
        for (final entry
            in preset.build(layerIds: ids, durationMs: 15000).entries)
          entry.key: entry.value.entrance.effect,
      };
      expect(effectsFor(MotionPreset.fade)['first'], MotionEffect.fade);
      expect(effectsFor(MotionPreset.pop)['first'], MotionEffect.zoomIn);
      expect(
        MotionPreset.pop
            .build(layerIds: ids, durationMs: 15000)['first']!
            .entrance
            .easing,
        MotionEasing.easeOutBack,
      );
      final slide = effectsFor(MotionPreset.slide);
      expect(slide['header'], MotionEffect.slideLeft);
      expect(slide['first'], MotionEffect.slideRight);
    });

    test('the newer style presets keep distinct signatures', () {
      Map<String, MotionEffect> effectsFor(MotionPreset preset) => {
        for (final entry
            in preset.build(layerIds: ids, durationMs: 15000).entries)
          entry.key: entry.value.entrance.effect,
      };
      expect(effectsFor(MotionPreset.glide)['first'], MotionEffect.slideLeft);
      expect(effectsFor(MotionPreset.dropIn)['first'], MotionEffect.slideDown);
      expect(effectsFor(MotionPreset.bloom)['first'], MotionEffect.zoomOut);
      expect(effectsFor(MotionPreset.unfold)['first'], MotionEffect.slideDown);

      final cascade = MotionPreset.cascade.build(
        layerIds: ids,
        durationMs: 15000,
      );
      expect(
        cascade.values.map((m) => m.entrance.delayMs),
        anyElement(greaterThan(0)),
        reason: 'cascade should stagger its fades',
      );
      final hover = MotionPreset.hover.build(
        layerIds: ids,
        durationMs: 15000,
      );
      expect(
        hover.values.map((m) => m.entrance.easing),
        everyElement(MotionEasing.linear),
      );
    });

    test('settledTimeMs reaches past every entrance', () {
      const timeline = VideoTimeline(durationMs: 15000);
      expect(timeline.settledTimeMs, 0);
      final motions = MotionPreset.stagger.build(
        layerIds: ids,
        durationMs: 15000,
      );
      final staggered = VideoTimeline(durationMs: 15000, motions: motions);
      final last = motions['second']!;
      expect(
        staggered.settledTimeMs,
        last.entrance.delayMs + last.entrance.durationMs,
      );
    });

    test('stagger delays increase and stay inside the card and delay limit', () {
      final built = MotionPreset.stagger.build(layerIds: ids, durationMs: 15000);
      final delays = [for (final id in ids) built[id]!.entrance.delayMs];
      expect(delays[0], 0);
      expect(delays[1], greaterThan(delays[0]));
      expect(delays[2], greaterThan(delays[1]));
      expect(delays[2], lessThanOrEqualTo(10000));
      for (final id in ids) {
        final entrance = built[id]!.entrance;
        expect(
          entrance.delayMs + entrance.durationMs,
          lessThanOrEqualTo(15000),
        );
      }
    });

    test('built presets satisfy timeline validation', () {
      for (final preset in MotionPreset.values) {
        final timeline = VideoTimeline(
          enabled: true,
          durationMs: 15000,
          motions: preset.build(layerIds: ids, durationMs: 15000),
        );
        expect(
          timeline.validate(layerIds: ids.toSet()),
          isEmpty,
          reason: '${preset.wireName} should validate',
        );
      }
    });

    test('detect round-trips every preset and rejects a custom edit', () {
      for (final preset in MotionPreset.values) {
        final motions = preset.build(layerIds: ids, durationMs: 15000);
        expect(
          MotionPreset.detect(
            layerIds: ids,
            durationMs: 15000,
            motions: motions,
          ),
          preset,
        );
      }
      final custom = MotionPreset.rise.build(layerIds: ids, durationMs: 15000);
      custom['first'] = custom['first']!.copyWith(
        entrance: custom['first']!.entrance.copyWith(durationMs: 1200),
      );
      expect(
        MotionPreset.detect(layerIds: ids, durationMs: 15000, motions: custom),
        isNull,
      );
    });

    test('preset motions survive a JSON round-trip', () {
      final timeline = VideoTimeline(
        enabled: true,
        durationMs: 12000,
        motions: MotionPreset.stagger.build(layerIds: ids, durationMs: 12000),
      );
      final decoded = VideoTimeline.decode(timeline.toJson());
      expect(decoded.motions, hasLength(ids.length));
      expect(decoded.motions['second']!.entrance.effect, MotionEffect.slideUp);
    });
  });

  group('ambient motion', () {
    test('drift moves every layer across the whole card', () {
      const timeline = VideoTimeline(
        durationMs: 10000,
        ambient: AmbientMotion.drift,
      );
      final start = evaluateTimeline(timeline, const ['a'], 0).visualFor('a');
      final mid = evaluateTimeline(timeline, const ['a'], 5000).visualFor('a');
      final end = evaluateTimeline(timeline, const ['a'], 10000).visualFor('a');
      expect(start.offset.dy, closeTo(0, 1e-9));
      expect(
        end.offset.dy,
        closeTo(-TimelineLimits.ambientDriftDistance, 1e-9),
      );
      expect(mid.offset.dy, lessThan(start.offset.dy));
      expect(mid.offset.dy, greaterThan(end.offset.dy));
    });

    test('zoom grows the scale and breathe stays in range', () {
      const zoom = VideoTimeline(
        durationMs: 10000,
        ambient: AmbientMotion.zoom,
      );
      expect(evaluateTimeline(zoom, const ['a'], 0).visualFor('a').scale, 1);
      expect(
        evaluateTimeline(zoom, const ['a'], 10000).visualFor('a').scale,
        closeTo(1 + TimelineLimits.ambientZoom, 1e-9),
      );
      const breathe = VideoTimeline(
        durationMs: 10000,
        ambient: AmbientMotion.breathe,
      );
      for (var t = 0; t <= 10000; t += 250) {
        final scale =
            evaluateTimeline(breathe, const ['a'], t).visualFor('a').scale;
        expect(scale, greaterThanOrEqualTo(0.2));
        expect(scale, lessThanOrEqualTo(1 + TimelineLimits.ambientBreathe + 1e-9));
      }
    });

    test('is off by default and survives a JSON round-trip', () {
      expect(VideoTimeline.decode(null).ambient, AmbientMotion.none);
      const timeline = VideoTimeline(
        durationMs: 12000,
        ambient: AmbientMotion.zoom,
      );
      expect(VideoTimeline.decode(timeline.toJson()).ambient, AmbientMotion.zoom);
      expect(
        VideoTimeline.decode({'durationMs': 12000, 'ambient': 'nonsense'}).ambient,
        AmbientMotion.none,
      );
    });

    test('presets that animate a card also enable a looping motion', () {
      for (final preset in MotionPreset.values) {
        if (preset == MotionPreset.none) {
          expect(preset.ambient, AmbientMotion.none);
        } else {
          expect(
            preset.ambient.isAnimated,
            isTrue,
            reason: '${preset.wireName} should keep the card moving',
          );
        }
      }
    });
  });
}
