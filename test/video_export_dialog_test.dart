import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/application/studio_controller.dart';
import 'package:invitation_studio/domain/category_music.dart';
import 'package:invitation_studio/domain/invitation_template.dart';
import 'package:invitation_studio/domain/project.dart';
import 'package:invitation_studio/domain/video/timeline.dart';
import 'package:invitation_studio/services/bundled_fonts.dart' show loadStudioFonts;
import 'package:invitation_studio/services/draft_store.dart';
import 'package:invitation_studio/services/video/video_encoder.dart';
import 'package:invitation_studio/services/video/video_export_service.dart';
import 'package:invitation_studio/services/video/video_media.dart';
import 'package:invitation_studio/ui/video/video_export_dialog.dart';

import 'support/fake_video_media.dart';

/// Accepts the export and reports success without rendering, so the test can
/// assert on what the dialog resolved rather than on pixels.
class _RecordingExporter extends VideoExporter {
  _RecordingExporter()
    : super(
        tempDirectory: () async => Directory.systemTemp,
        documentsDirectory: () async => Directory.systemTemp,
      );

  VideoExportRequest? request;

  @override
  Future<VideoExportResult> export({
    required VideoExportRequest request,
    required void Function(VideoExportProgress) onProgress,
    required ExportCancellation cancellation,
  }) async {
    this.request = request;
    onProgress(
      VideoExportProgress(
        stage: VideoExportStage.rendering,
        frame: 1,
        frameCount: request.timeline.frameCount,
      ),
    );
    return VideoExportResult(
      path: '/tmp/invitation.mp4',
      bytes: 4096,
      width: request.outputWidth,
      height: 1920,
      durationMs: request.timeline.durationMs,
      fps: request.timeline.fps,
      frameCount: request.timeline.frameCount,
      hasAudio: request.audio != null,
      elapsed: const Duration(seconds: 1),
    );
  }
}

class _FakeBackend implements VideoEncoderBackend {
  @override
  bool get isSupported => true;

  @override
  String get unsupportedReason => '';

  @override
  Future<VideoEncoderSession> open(VideoEncodeSpec spec) async =>
      throw UnimplementedError('the dialog only checks isSupported here');
}

/// The project the home wizard creates: a category, a matching design and the
/// category's bundled tune already selected.
StudioProject _wizardProject() {
  const id = 'p_wizard_export';
  return StudioProject(
    id: id,
    title: 'Ayesha & Hamza',
    updatedAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
    category: InvitationCategory.wedding,
    document: templatesFor(InvitationCategory.wedding).first.createDocument(
      documentId: id,
      format: InvitationFormat.classic,
    ),
    video: VideoTimeline(
      enabled: true,
      audio: CategoryMusic.forCategory(InvitationCategory.wedding),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadStudioFonts);

  testWidgets('a new project exports with its bundled tune', (tester) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final studio = StudioController(
      project: _wizardProject(),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);
    final media = FakeVideoMedia(
      tune: const ImportedAudio(
        assetId: 'tune_wedding',
        title: 'Wedding theme',
        durationMs: 7866,
        path: '/tmp/tune_wedding.wav',
      ),
    );
    final exporter = _RecordingExporter();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoExportDialog(
            studio: studio,
            backend: _FakeBackend(),
            exporter: exporter,
            mediaService: media,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The checklist is shown before anything is rendered.
    expect(find.text('BEFORE YOU EXPORT'), findsOneWidget);
    expect(find.text('Wedding theme'), findsOneWidget);
    expect(find.text('Ready'), findsOneWidget);

    final button = find.text('Export MP4');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();

    final request = exporter.request;
    if (request == null) fail('the export should have started');
    expect(
      request.audio,
      isNotNull,
      reason:
          'the bundled tune must be resolved through the bundle; looking it '
          'up as imported music returns null and aborts the export',
    );
    expect(
      request.audio!.assetId,
      CategoryMusic.tuneId(InvitationCategory.wedding),
    );
    expect(media.tuneLoads, greaterThanOrEqualTo(1));
    expect(
      media.trackLoads,
      0,
      reason: 'a tune must never be looked up in managed storage',
    );
    expect(find.text('MP4 written to this device'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The controller debounces its autosave by 650 ms; flushing it here keeps
    // the test from ending with a pending timer.
    await studio.saveNow();
  });

  testWidgets('a missing clip is reported before rendering, with a fix', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(520, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final base = _wizardProject();
    final studio = StudioController(
      project: base.copyWith(
        video: base.video.copyWith(
          background: const VideoBackground(
            kind: BackgroundKind.clip,
            assetId: 'clip_gone',
          ),
        ),
      ),
      store: MemoryProjectStore(),
    );
    addTearDown(studio.dispose);

    final exporter = _RecordingExporter();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoExportDialog(
            studio: studio,
            backend: _FakeBackend(),
            exporter: exporter,
            // The tune resolves, so the clip is the only thing to fix.
            mediaService: FakeVideoMedia(
              tune: const ImportedAudio(
                assetId: 'tune_wedding',
                title: 'Wedding theme',
                durationMs: 7866,
                path: '/tmp/tune_wedding.wav',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Background clip missing'), findsOneWidget);
    expect(find.text('1 to fix'), findsOneWidget);
    expect(find.text('Re-import clip'), findsOneWidget);
    // Tapping export does nothing instead of failing after the progress bar.
    await tester.tap(find.text('Export MP4'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(
      exporter.request,
      isNull,
      reason: 'a blocking check must disable the export, not defer the failure',
    );

    // The controller debounces its autosave by 650 ms; flushing it here keeps
    // the test from ending with a pending timer.
    await studio.saveNow();
  });
}
