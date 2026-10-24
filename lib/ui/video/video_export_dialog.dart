import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/studio_controller.dart';
import '../../domain/category_music.dart';
import '../../domain/video/timeline.dart';
import '../../services/video/export_media.dart';
import '../../services/video/export_preflight.dart';
import '../../services/video/video_encoder.dart';
import '../../services/video/video_encoder_platform.dart';
import '../../services/video/video_export_service.dart';
import '../../services/video/video_media.dart';
import '../../services/video/video_media_platform.dart';
import '../studio_theme.dart';
import '../widgets/controls.dart';
import 'video_settings_sheet.dart';

enum VideoQuality {
  full('Story 1080p', '1080 × 1920 · 30 fps · about 8 Mbps'),
  light('Lighter file', '540 × 960 · 30 fps · about 3 Mbps');

  const VideoQuality(this.label, this.detail);
  final String label;
  final String detail;

  int get width => this == VideoQuality.full ? 1080 : 540;
}

/// Exports the video invitation to a real MP4 and offers the system share
/// sheet. Nothing is uploaded; "shared" is never claimed here because the share
/// sheet cannot confirm delivery.
///
/// The dialog checks the draft before rendering: what background it has, where
/// the music comes from, and what the file will cost. A missing file becomes a
/// row with a fix button instead of an exception at 90 %.
class VideoExportDialog extends StatefulWidget {
  const VideoExportDialog({
    super.key,
    required this.studio,
    this.backend,
    this.exporter,
    this.mediaService,
  });

  final StudioController studio;
  final VideoEncoderBackend? backend;
  final VideoExporter? exporter;

  /// Injectable so tests can drive the media lookup without platform storage.
  final VideoMediaService? mediaService;

  static Future<void> show(BuildContext context, StudioController studio) =>
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => VideoExportDialog(studio: studio),
      );

  @override
  State<VideoExportDialog> createState() => _VideoExportDialogState();
}

class _QualityRow extends StatelessWidget {
  const _QualityRow({
    required this.quality,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final VideoQuality quality;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(8),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
      child: Row(
        children: [
          Icon(
            selected
                ? Icons.radio_button_checked
                : Icons.radio_button_unchecked,
            size: 17,
            color: selected ? StudioColors.accent : StudioColors.muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quality.label, style: const TextStyle(fontSize: 12.5)),
                Text(
                  quality.detail,
                  style: const TextStyle(fontSize: 10, color: StudioColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _VideoExportDialogState extends State<VideoExportDialog> {
  late final VideoMediaService _store;
  late final VideoEncoderBackend _backend;
  late final VideoExporter _exporter;
  VideoQuality _quality = VideoQuality.full;
  VideoExportResult? _result;
  String? _error;
  String? _message;
  VideoExportProgress? _progress;
  ExportCancellation? _cancellation;
  bool _running = false;

  ImportedClip? _clip;
  ImportedAudio? _audio;
  bool _mediaLoaded = false;

  @override
  void initState() {
    super.initState();
    _store = widget.mediaService ?? createVideoMediaService();
    _backend = widget.backend ?? createVideoEncoderBackend();
    _exporter = widget.exporter ?? VideoExporter();
    _loadMedia();
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  VideoTimeline get _timeline => widget.studio.project.effectiveVideo;

  /// Resolves the draft's media for the checklist. Display state only:
  /// [_start] resolves the music again through [resolveExportAudio], which is
  /// the single rule for whether the file is actually needed.
  Future<void> _loadMedia() async {
    final timeline = _timeline;
    final clipId = timeline.background.assetId;
    final audioId = timeline.audio?.assetId;
    ImportedClip? clip;
    ImportedAudio? audio;
    if (clipId != null) {
      clip = await _store.loadClip(widget.studio.project.id, clipId);
    }
    if (audioId != null) {
      audio = CategoryMusic.isTune(audioId)
          ? await _store.loadBundledTune(
              projectId: widget.studio.project.id,
              assetId: audioId,
              title: timeline.audio?.title,
            )
          : await _store.loadAudio(
              widget.studio.project.id,
              audioId,
              title: timeline.audio?.title,
              durationMs: timeline.audio?.durationMs,
            );
    }
    if (!mounted) return;
    setState(() {
      _clip = clip;
      _audio = audio;
      _mediaLoaded = true;
    });
  }

  Future<void> _start() async {
    if (_running) return;
    final timeline = _timeline;
    final cancellation = ExportCancellation();
    setState(() {
      _running = true;
      _error = null;
      _message = null;
      _result = null;
      _cancellation = cancellation;
      _progress = VideoExportProgress(
        stage: VideoExportStage.preparing,
        frame: 0,
        frameCount: timeline.frameCount,
      );
    });
    announceForAccessibility(context, 'Exporting video.');
    try {
      final projectId = widget.studio.project.id;
      final clipId = timeline.background.assetId;
      final clip = clipId == null ? null : await _store.loadClip(projectId, clipId);
      // Bundled tunes live in the app bundle, not in managed storage: resolving
      // them here is what makes a wizard project exportable at all.
      final audio = await resolveExportAudio(
        media: _store,
        projectId: projectId,
        audio: timeline.audio,
        isWeb: kIsWeb,
      );
      if (!mounted) return;
      final result = await _exporter.export(
        request: VideoExportRequest(
          projectId: projectId,
          title: widget.studio.project.title,
          document: widget.studio.document,
          timeline: timeline,
          backend: _backend,
          clip: clip,
          audio: audio,
          imageProvider: widget.studio.editor.imageProvider,
          outputWidth: _quality.width,
          focusLight: widget.studio.project.focusLight,
        ),
        onProgress: (value) {
          if (!mounted) return;
          setState(() => _progress = value);
        },
        cancellation: cancellation,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _running = false;
      });
      announceForAccessibility(
        context,
        'Video ready, ${result.width} by ${result.height} pixels.',
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _running = false;
        _error = error is VideoExportException
            ? error.message
            : 'The video could not be exported.';
      });
      announceForAccessibility(context, _error!);
    }
  }

  /// Applies a preflight repair in place, then re-reads the draft so the
  /// checklist reflects the new state instead of the one it was opened with.
  Future<void> _applyFix(ExportFix fix) async {
    final timeline = _timeline;
    if (fix == ExportFix.removeMusic) {
      widget.studio.updateVideo(timeline.copyWith(clearAudio: true));
      setState(() {});
      await _loadMedia();
      return;
    }
    if (fix == ExportFix.muteMusic) {
      final audio = timeline.audio;
      if (audio != null) {
        widget.studio.updateVideo(
          timeline.copyWith(audio: audio.copyWith(volume: 0)),
        );
        setState(() {});
      }
      await _loadMedia();
      return;
    }
    // Re-importing a clip needs the picker, which lives in the settings sheet.
    await VideoSettingsSheet.show(context, widget.studio);
    if (!mounted) return;
    setState(() {});
    await _loadMedia();
  }

  Future<void> _share(VideoExportResult result) async {
    final box = context.findRenderObject() as RenderBox?;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final outcome = await SharePlus.instance.share(
        ShareParams(
          files: [XFile(result.path, mimeType: 'video/mp4')],
          fileNameOverrides: [result.path.split('/').last],
          subject: 'Your invitation video',
          title: 'Share invitation video',
          sharePositionOrigin: origin,
          downloadFallbackEnabled: false,
          mailToFallbackEnabled: false,
        ),
      );
      if (!mounted) return;
      setState(() {
        _message = outcome.status == ShareResultStatus.dismissed
            ? 'Sharing cancelled.'
            : 'Your device handled the share. Delivery is not confirmed by this app.';
      });
      announceForAccessibility(context, _message!);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = 'The share sheet could not be opened.');
      announceForAccessibility(context, _message!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline;
    final supported = _backend.isSupported;
    final result = _result;
    final exportable = widget.studio.document.height == 1920
        ? 'Story 9:16'
        : widget.studio.document.width == widget.studio.document.height
        ? 'Square 1:1'
        : 'Classic 5:7';
    final preflight = buildExportPreflight(
      timeline: timeline,
      documentWidth: widget.studio.document.width,
      documentHeight: widget.studio.document.height,
      outputWidth: _quality.width,
      encoderSupported: supported,
      clipPresent: _clip != null,
      audioPresent: _audio != null,
      isWeb: kIsWeb,
    );
    // Until the media lookup finishes, "missing" would be a guess: keep the
    // export enabled, because the export resolves everything itself.
    final ready = supported && (!_mediaLoaded || preflight.canExport);
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 430,
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Export video invitation',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: _running ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 18),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$exportable · ${(timeline.durationMs / 1000).toStringAsFixed(1)} s · '
                '${timeline.fps} fps · ${timeline.frameCount} frames',
                style: const TextStyle(fontSize: 11, color: StudioColors.muted),
              ),
              if (result == null && _error == null) ...[
                const SizedBox(height: 14),
                _checklist(preflight),
                const SizedBox(height: 14),
                for (final quality in VideoQuality.values)
                  _QualityRow(
                    quality: quality,
                    selected: _quality == quality,
                    enabled: !_running,
                    onTap: () => setState(() => _quality = quality),
                  ),
              ],
              if (!supported) ...[
                const SizedBox(height: 12),
                _notice(_backend.unsupportedReason, warning: true),
              ],
              if (_running) ...[
                const SizedBox(height: 10),
                _progressView(),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                _notice(_error!, warning: true),
              ],
              if (result != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: StudioColors.accentSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline, size: 16, color: StudioColors.accent),
                          const SizedBox(width: 6),
                          Text(
                            kIsWeb
                                ? 'Video downloaded to your device'
                                : 'MP4 written to this device',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${result.width} × ${result.height} · ${result.durationLabel} · '
                        '${result.frameCount} frames · ${result.sizeLabel}',
                        style: const TextStyle(fontSize: 10.5, color: StudioColors.ink),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        result.hasAudio
                            ? 'Audio: AAC music track'
                            : kIsWeb
                            ? 'Audio: none (browser export is silent)'
                            : 'Audio: none (silent MP4)',
                        style: const TextStyle(fontSize: 10.5, color: StudioColors.muted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        result.path,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 9.5, color: StudioColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(
                  _message!,
                  style: const TextStyle(fontSize: 10.5, color: StudioColors.muted),
                ),
              ],
              const SizedBox(height: 14),
              Row(
                children: [
                  if (_running)
                    OutlinedButton(
                      onPressed: () => _cancellation?.cancel(),
                      child: const Text('Cancel export'),
                    )
                  else if (result != null) ...[
                    if (!kIsWeb) ...[
                      OutlinedButton(
                        onPressed: () => _share(result),
                        child: const Text('Share .mp4'),
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Done'),
                    ),
                  ] else ...[
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: ready ? _start : null,
                      icon: const Icon(Icons.movie_creation_outlined, size: 16),
                      label: Text(kIsWeb ? 'Export video' : 'Export MP4'),
                    ),
                  ],
                ],
              ),
              if (!supported) ...[
                const SizedBox(height: 8),
                const Text(
                  'Preview, timing and animation editing still work on this platform. '
                  'Only the encoder is unavailable.',
                  style: TextStyle(fontSize: 9.5, color: StudioColors.muted),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The preflight checklist: every line the exporter would otherwise discover
  /// only after the progress bar appeared.
  Widget _checklist(ExportPreflight preflight) => Container(
    padding: const EdgeInsets.fromLTRB(12, 11, 12, 6),
    decoration: BoxDecoration(
      color: StudioColors.wash,
      borderRadius: StudioShape.smRadius,
      border: Border.all(
        color: !_mediaLoaded || preflight.canExport
            ? StudioColors.border
            : StudioColors.warningBorder,
      ),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'BEFORE YOU EXPORT',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: StudioColors.muted,
                ),
              ),
            ),
            Text(
              !_mediaLoaded
                  ? 'Checking media…'
                  : preflight.canExport
                  ? 'Ready'
                  : '${preflight.blockers.length} to fix',
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: !_mediaLoaded
                    ? StudioColors.muted
                    : preflight.canExport
                    ? StudioColors.accent
                    : StudioColors.warningInk,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Nothing is reported as missing until the lookup has actually run.
        if (_mediaLoaded)
          for (final item in preflight.items) _checkRow(item)
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 7),
            child: Text(
              'Looking up the artwork, clip and music for this draft.',
              style: TextStyle(fontSize: 9.8, color: StudioColors.muted),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _running
                ? null
                : () => _applyFix(ExportFix.openVideoSettings),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              minimumSize: const Size(0, 32),
            ),
            child: const Text('Video settings', style: TextStyle(fontSize: 10.5)),
          ),
        ),
      ],
    ),
  );

  Widget _checkRow(ExportPreflightItem item) {
    final icon = item.blocking
        ? Icons.error_outline
        : item.ok
        ? Icons.check_circle_outline
        : Icons.info_outline;
    final color = item.blocking
        ? StudioColors.warningInk
        : item.ok
        ? StudioColors.accent
        : StudioColors.muted;
    final fixes = <Widget>[
      if (item.fix != null && item.fixLabel != null)
        _fixButton(item.fixLabel!, item.fix!),
      if (item.alternateFix != null && item.alternateFixLabel != null)
        _fixButton(item.alternateFixLabel!, item.alternateFix!),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: item.blocking ? StudioColors.warningInk : StudioColors.ink,
                  ),
                ),
                Text(
                  item.detail,
                  style: const TextStyle(
                    fontSize: 9.8,
                    height: 1.35,
                    color: StudioColors.muted,
                  ),
                ),
                if (fixes.isNotEmpty && !_running)
                  Wrap(
                    spacing: 2,
                    children: fixes,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fixButton(String label, ExportFix fix) => TextButton(
    onPressed: () => _applyFix(fix),
    style: TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      minimumSize: const Size(0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    ),
    child: Text(label, style: const TextStyle(fontSize: 10)),
  );

  Widget _progressView() {
    final progress = _progress;
    final frame = progress?.frame ?? 0;
    final total = progress?.frameCount ?? 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(value: progress?.fraction),
        const SizedBox(height: 6),
        Text(
          '${progress?.stage.label ?? 'Rendering'} · '
          '${frame.clamp(0, total)}/$total frames',
          style: const TextStyle(fontSize: 10.5, color: StudioColors.muted),
        ),
      ],
    );
  }

  Widget _notice(String text, {bool warning = false}) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: warning ? StudioColors.warningSoft : StudioColors.wash,
      borderRadius: StudioShape.smRadius,
      border: Border.all(
        color: warning ? StudioColors.warningBorder : StudioColors.border,
      ),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        height: 1.45,
        color: warning ? StudioColors.warningInk : StudioColors.ink,
      ),
    ),
  );
}
