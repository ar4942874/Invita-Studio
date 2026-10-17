import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/video/timeline.dart';
import 'package:invitation_studio/services/video/frame_renderer.dart';
import 'package:invitation_studio/services/video/video_encoder.dart';
import 'package:invitation_studio/services/video/video_export_service.dart';
import 'package:invitation_studio/services/video/video_media.dart';

ClipManifest _manifest({int frames = 450, int fps = 30}) => ClipManifest(
  assetId: 'clip_test',
  title: 'Test clip',
  sourceDurationMs: 15000,
  sourceWidth: 1080,
  sourceHeight: 1920,
  fps: fps,
  frameWidth: 1080,
  frameHeight: 1920,
  frameCount: frames,
  framePattern: 'f%05d.jpg',
);

void main() {
  group('clip manifest', () {
    test('round-trips and formats frame names', () {
      final manifest = _manifest();
      final decoded = ClipManifest.decode(manifest.encode());
      expect(decoded.frameCount, 450);
      expect(decoded.proxyDurationMs, 15000);
      expect(decoded.frameName(0), 'f00000.jpg');
      expect(decoded.frameName(7), 'f00007.jpg');
      expect(decoded.frameName(449), 'f00449.jpg');
    });

    test('rejects unknown manifests and impossible frame counts', () {
      expect(
        () => ClipManifest.decode('{"schema":"other","version":1}'),
        throwsFormatException,
      );
      final bad = _manifest().toJson();
      bad['frameCount'] = 5000;
      expect(() => ClipManifest.decode(jsonEncode(bad)), throwsFormatException);
      final missing = _manifest().toJson();
      missing.remove('assetId');
      expect(() => ClipManifest.decode(jsonEncode(missing)), throwsA(anything));
    });
  });

  group('clip frame mapping', () {
    test('uses trim start and loops inside the trimmed window', () {
      const timeline = VideoTimeline(
        durationMs: 10000,
        background: VideoBackground(
          kind: BackgroundKind.clip,
          assetId: 'clip_test',
          trimStartMs: 2000,
          trimEndMs: 6000,
          loop: true,
        ),
      );
      final manifest = _manifest();
      expect(clipFrameIndexFor(timeline: timeline, manifest: manifest, timeMs: 0), 60);
      expect(
        clipFrameIndexFor(timeline: timeline, manifest: manifest, timeMs: 1900),
        117, // 3.9 s * 30 fps, floored
      );
      expect(
        clipFrameIndexFor(timeline: timeline, manifest: manifest, timeMs: 4000),
        60,
      );
    });

    test('freezes on the last trimmed frame when looping is off', () {
      const timeline = VideoTimeline(
        durationMs: 10000,
        background: VideoBackground(
          kind: BackgroundKind.clip,
          assetId: 'clip_test',
          trimStartMs: 2000,
          trimEndMs: 6000,
          loop: false,
        ),
      );
      final manifest = _manifest();
      expect(clipFrameIndexFor(timeline: timeline, manifest: manifest, timeMs: 9000), 179);
      expect(clipFrameIndexFor(timeline: timeline, manifest: manifest, timeMs: 10000), 179);
    });

    test('clamps to the available proxy frames', () {
      const timeline = VideoTimeline(
        durationMs: 20000,
        background: VideoBackground(
          kind: BackgroundKind.clip,
          assetId: 'clip_test',
          trimStartMs: 0,
          trimEndMs: 0,
          loop: true,
        ),
      );
      final manifest = _manifest(frames: 90); // 3 s proxy
      final index = clipFrameIndexFor(
        timeline: timeline,
        manifest: manifest,
        timeMs: 19500,
      );
      expect(index, inInclusiveRange(0, 89));
    });
  });

  group('export progress', () {
    test('maps stages onto a monotonic fraction', () {
      double fraction(VideoExportStage stage, int frame) =>
          VideoExportProgress(stage: stage, frame: frame, frameCount: 450).fraction;
      expect(fraction(VideoExportStage.preparing, 0), 0);
      expect(fraction(VideoExportStage.rendering, 0), 0);
      expect(fraction(VideoExportStage.rendering, 225), closeTo(.46, 1e-9));
      expect(fraction(VideoExportStage.rendering, 450), closeTo(.92, 1e-9));
      expect(fraction(VideoExportStage.finishing, 450), closeTo(.98, 1e-9));
      expect(fraction(VideoExportStage.done, 450), 1);
    });

    test('encodes audio settings for the native muxer', () {
      const spec = EncoderAudioSpec(
        path: '/tmp/song.m4a',
        startMs: 500,
        trimStartMs: 1000,
        trimEndMs: 6000,
        volume: 65,
        fadeInMs: 400,
        fadeOutMs: 900,
        durationMs: 15000,
      );
      final map = spec.toMap();
      expect(map['path'], '/tmp/song.m4a');
      expect(map['volume'], 65);
      expect(map['trimEndMs'], 6000);
    });
  });

  test('formatBytes is human readable', () {
    expect(formatBytes(900), '900 B');
    expect(formatBytes(2048), '2 KB');
    expect(formatBytes(3 * 1024 * 1024), '3.0 MB');
  });

  test('imported clip reads frames through an in-memory reader', () async {
    final manifest = _manifest(frames: 3);
    final frames = [
      Uint8List.fromList([1, 2, 3]),
      Uint8List.fromList([4, 5]),
      Uint8List.fromList([6]),
    ];
    final clip = ImportedClip(
      manifest: manifest,
      frameReader: (index) async => frames[index],
    );
    expect(clip.directory, isEmpty);
    expect(await clip.readFrame(0), frames[0]);
    expect(await clip.readFrame(2), frames[2]);
    expect(clip.frameCount, 3);
  });
}
