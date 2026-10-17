import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../application/studio_controller.dart';
import '../../domain/video/timeline.dart';
import '../../services/video/video_encoder.dart';
import '../../services/video/video_encoder_platform.dart';
import '../../services/video/video_export_service.dart';
import '../../services/video/video_media.dart';
import '../../services/video/video_media_platform.dart';
import '../studio_theme.dart';
import '../widgets/controls.dart';

enum VideoQuality {
  full('Story 1080p', '1080 × 1920 · 30 fps · about 8 Mbps'),
  light('Lighter file', '540 × 960 · 30 fps · about 3 Mbps');

  const VideoQuality(this.label, this.detail);
  final String label;
  final String detail;
}

/// Exports the video invitation to a real MP4 and offers the system share
/// sheet. Nothing is uploaded; "shared" is never claimed here because the share
/// sheet cannot confirm delivery.
class VideoExportDialog extends StatefulWidget {
  const VideoExportDialog({
    super.key,
    required this.studio,
    this.backend,
    this.exporter,
  });

  final StudioController studio;
  final VideoEncoderBackend? backend;
  final VideoExporter? exporter;

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
  final VideoMediaService _store = createVideoMediaService();
  late final VideoEncoderBackend _backend;
  late final VideoExporter _exporter;
  VideoQuality _quality = VideoQuality.full;
  VideoExportResult? _result;
  String? _error;
  String? _message;
  VideoExportProgress? _progress;
  ExportCancellation? _cancellation;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _backend = widget.backend ?? createVideoEncoderBackend();
    _exporter = widget.exporter ?? VideoExporter();
  }

  @override
  void dispose() {
    _cancellation?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_running) return;
    final timeline = widget.studio.project.effectiveVideo;
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
      final audioId = timeline.audio?.assetId;
      final clip = clipId == null ? null : await _store.loadClip(projectId, clipId);
      final audio = audioId == null
          ? null
          : await _store.loadAudio(
              projectId,
              audioId,
              title: timeline.audio?.title,
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
          outputWidth: _quality == VideoQuality.full ? 1080 : 540,
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
    final timeline = widget.studio.project.effectiveVideo;
    final supported = _backend.isSupported;
    final result = _result;
    final exportable = widget.studio.document.height == 1920
        ? 'Story 9:16'
        : widget.studio.document.width == widget.studio.document.height
        ? 'Square 1:1'
        : 'Classic 5:7';
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
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
              const SizedBox(height: 6),
              _audioLine(timeline),
              if (!supported) ...[
                const SizedBox(height: 12),
                _notice(_backend.unsupportedReason, warning: true),
              ],
              if (result == null && _error == null) ...[
                const SizedBox(height: 14),
                for (final quality in VideoQuality.values)
                  _QualityRow(
                    quality: quality,
                    selected: _quality == quality,
                    enabled: !_running,
                    onTap: () => setState(() => _quality = quality),
                  ),
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
                      onPressed: supported ? _start : null,
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

  Widget _audioLine(VideoTimeline timeline) {
    if (kIsWeb) {
      return const Text(
        'Audio: browser export is silent (preview still plays the music)',
        style: TextStyle(fontSize: 11, color: StudioColors.muted),
      );
    }
    final audio = timeline.audio;
    if (audio == null) {
      return const Text(
        'Audio: silent MP4 (no music selected)',
        style: TextStyle(fontSize: 11, color: StudioColors.muted),
      );
    }
    if (audio.isMuted) {
      return const Text(
        'Audio: muted — the MP4 will have no audio track',
        style: TextStyle(fontSize: 11, color: StudioColors.muted),
      );
    }
    return Text(
      'Audio: ${audio.title ?? 'music'} · AAC · ${audio.volume}% · '
      'starts ${(audio.startMs / 1000).toStringAsFixed(1)} s',
      style: const TextStyle(fontSize: 11, color: StudioColors.muted),
    );
  }

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
