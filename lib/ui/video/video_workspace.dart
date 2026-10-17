import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../../application/studio_controller.dart';
import '../../domain/video/timeline.dart';
import '../../services/video/video_media.dart';
import '../studio_theme.dart';
import 'video_playback.dart';
import 'video_preview.dart';

/// The video-mode workspace: preview, transport, timeline and motion inspector.
///
/// It edits the same [StudioController] as the image editor, so wording, fonts,
/// colours and layer positions are shared. Switching modes never copies the
/// document.
class VideoWorkspace extends StatefulWidget {
  const VideoWorkspace({
    super.key,
    required this.studio,
    required this.onOpenSettings,
    required this.onExport,
    this.compact = false,
  });

  final StudioController studio;
  final VoidCallback onOpenSettings;
  final VoidCallback onExport;
  final bool compact;

  @override
  State<VideoWorkspace> createState() => _VideoWorkspaceState();
}

class _VideoWorkspaceState extends State<VideoWorkspace>
    with SingleTickerProviderStateMixin {
  late final VideoPlaybackController _playback;
  late final VideoMediaStore _store;
  VideoMediaBundle _media = VideoMediaBundle.empty;
  String? _loadedClipId;
  String? _loadedAudioId;
  int _loadedDuration = 0;

  @override
  void initState() {
    super.initState();
    _store = VideoMediaStore();
    final timeline = widget.studio.video;
    _playback = VideoPlaybackController(
      vsync: this,
      durationMs: timeline.durationMs,
    );
    _loadedDuration = timeline.durationMs;
    widget.studio.addListener(_onStudioChanged);
    _loadMedia();
  }

  @override
  void dispose() {
    widget.studio.removeListener(_onStudioChanged);
    _playback.dispose();
    super.dispose();
  }

  void _onStudioChanged() {
    final timeline = widget.studio.video;
    if (timeline.durationMs != _loadedDuration) {
      _loadedDuration = timeline.durationMs;
      _playback.setDuration(timeline.durationMs);
    }
    if (timeline.background.assetId != _loadedClipId ||
        timeline.audio?.assetId != _loadedAudioId) {
      _loadMedia();
    }
  }

  Future<void> _loadMedia() async {
    final timeline = widget.studio.video;
    final clipId = timeline.background.assetId;
    final audioId = timeline.audio?.assetId;
    _loadedClipId = clipId;
    _loadedAudioId = audioId;
    ImportedClip? clip;
    ImportedAudio? audio;
    if (clipId != null) {
      clip = await _store.loadClip(widget.studio.project.id, clipId);
    }
    if (audioId != null) {
      audio = await _store.loadAudio(
        widget.studio.project.id,
        audioId,
        title: timeline.audio?.title,
        durationMs: timeline.audio?.durationMs,
      );
    }
    if (!mounted) return;
    setState(() {
      _media = VideoMediaBundle(
        clip: clip,
        audio: audio,
        clipMissing: clipId != null && clip == null,
        audioMissing: audioId != null && audio == null,
      );
    });
  }

  DesignNode? get _selected {
    final node = widget.studio.selectedNode;
    if (node == null) return null;
    return node.type == 'background' ? null : node;
  }

  String _layerName(DesignNode node) {
    if (node is TextNode) {
      final text = node.text.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) return 'Text layer';
      return text.length > 26 ? '${text.substring(0, 26)}…' : text;
    }
    if (node is ImageNode) return 'Photo';
    return node.id;
  }

  @override
  Widget build(BuildContext context) {
    final timeline = widget.studio.video;
    final selected = _selected;
    return Column(
      children: [
        Expanded(
          child: ColoredBox(
            color: StudioColors.canvas,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: widget.compact ? 330 : 360,
                    maxHeight: 640,
                  ),
                  child: VideoPreview(
                    studio: widget.studio,
                    playback: _playback,
                    media: _media,
                  ),
                ),
              ),
            ),
          ),
        ),
        _Transport(
          playback: _playback,
          timeline: timeline,
          media: _media,
          onSettings: widget.onOpenSettings,
          onExport: widget.onExport,
        ),
        _TimelinePanel(
          studio: widget.studio,
          playback: _playback,
          layerName: _layerName,
          compact: widget.compact,
        ),
        _MotionInspector(
          studio: widget.studio,
          node: selected,
          layerName: selected == null ? null : _layerName(selected),
        ),
      ],
    );
  }
}

class _Transport extends StatelessWidget {
  const _Transport({
    required this.playback,
    required this.timeline,
    required this.media,
    required this.onSettings,
    required this.onExport,
  });

  final VideoPlaybackController playback;
  final VideoTimeline timeline;
  final VideoMediaBundle media;
  final VoidCallback onSettings;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    final audio = timeline.audio;
    final audioLabel = audio == null
        ? 'Silent video'
        : audio.isMuted
        ? 'Music muted · silent MP4'
        : media.audioMissing
        ? 'Music missing'
        : 'Music on';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: StudioColors.border)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: playback,
            builder: (context, _) => IconButton.filled(
              tooltip: playback.playing ? 'Pause' : 'Play',
              onPressed: playback.toggle,
              icon: Icon(
                playback.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: playback,
            builder: (context, _) => Text(
              '${playback.timecode} / ${playback.durationTimecode}',
              style: const TextStyle(
                fontSize: 11.5,
                fontFeatures: [FontFeature.tabularFigures()],
                color: StudioColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              audioLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: media.audioMissing ? const Color(0xFFAD722B) : StudioColors.muted,
              ),
            ),
          ),
          const Spacer(),
          if (!timeline.enabled)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text(
                'Video mode is off',
                style: TextStyle(fontSize: 10.5, color: StudioColors.muted),
              ),
            ),
          IconButton(
            tooltip: 'Video settings (background, music, length)',
            onPressed: onSettings,
            icon: const Icon(Icons.tune, size: 19),
          ),
          const SizedBox(width: 4),
          FilledButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.movie_creation_outlined, size: 16),
            label: const Text('Export MP4'),
          ),
        ],
      ),
    );
  }
}

class _TimelinePanel extends StatelessWidget {
  const _TimelinePanel({
    required this.studio,
    required this.playback,
    required this.layerName,
    required this.compact,
  });

  final StudioController studio;
  final VideoPlaybackController playback;
  final String Function(DesignNode) layerName;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final timeline = studio.video;
    final layers = studio.document.nodes
        .where((node) => node.type != 'background')
        .toList()
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    final rows = layers.take(compact ? 4 : 6).toList();
    return Container(
      height: 42.0 + rows.length * 30 + (rows.isEmpty ? 26 : 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: StudioColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: AnimatedBuilder(
        animation: playback,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final duration = timeline.durationMs;
            final progress = duration <= 0
                ? 0.0
                : playback.positionMs.clamp(0, duration) / duration;
            void seek(Offset local) {
              final fraction = (local.dx / width).clamp(0.0, 1.0);
              playback.seek((fraction * duration).round());
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) => seek(details.localPosition),
              onHorizontalDragUpdate: (details) => seek(details.localPosition),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 18,
                          child: Row(
                            children: [
                              const Text(
                                'TIMELINE',
                                style: TextStyle(
                                  fontSize: 9,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w600,
                                  color: StudioColors.muted,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${(duration / 1000).toStringAsFixed(0)} s · ${timeline.fps} fps',
                                style: const TextStyle(
                                  fontSize: 9.5,
                                  color: StudioColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        _Ruler(durationMs: duration, width: width),
                        const SizedBox(height: 2),
                        for (final node in rows) ...[
                          _LayerRow(
                            node: node,
                            name: layerName(node),
                            timeline: timeline,
                            selected: studio.selectedNode?.id == node.id,
                            onTap: () {
                              studio.editor.selectNode(node.id);
                              final motion = timeline.motionFor(node.id);
                              playback.seek(motion.visibleStartMs);
                            },
                          ),
                          const SizedBox(height: 4),
                        ],
                        if (rows.isEmpty)
                          const Text(
                            'Add a text or photo layer to animate it.',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: StudioColors.muted,
                            ),
                          ),
                      ],
                    ),
                  ),
                  Positioned(
                    left: (progress * width)
                        .clamp(0.0, width - 1.5)
                        .toDouble(),
                    top: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Container(
                        width: 1.5,
                        color: StudioColors.green,
                      ),
                    ),
                  ),
                  Positioned(
                    left: (progress * width - 5)
                        .clamp(0.0, width - 10)
                        .toDouble(),
                    top: 16,
                    child: IgnorePointer(
                      child: _PlayheadHandle(),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlayheadHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    width: 10,
    height: 10,
    decoration: BoxDecoration(
      color: StudioColors.green,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

class _Ruler extends StatelessWidget {
  const _Ruler({required this.durationMs, required this.width});
  final int durationMs;
  final double width;

  @override
  Widget build(BuildContext context) {
    final seconds = (durationMs / 1000).ceil();
    return SizedBox(
      height: 12,
      width: width,
      child: CustomPaint(
        painter: _RulerPainter(seconds: seconds),
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  _RulerPainter({required this.seconds});
  final int seconds;

  @override
  void paint(Canvas canvas, Size size) {
    if (seconds <= 0) return;
    final paint = Paint()
      ..color = StudioColors.border
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(fontSize: 7.5, color: StudioColors.muted);
    for (var second = 0; second <= seconds; second++) {
      final x = size.width * second / seconds;
      final isMajor = second % 5 == 0;
      canvas.drawLine(
        Offset(x, size.height - (isMajor ? 7 : 4)),
        Offset(x, size.height),
        paint,
      );
      if (isMajor && second > 0) {
        final painter = TextPainter(
          text: TextSpan(text: '${second}s', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(canvas, Offset(x + 2, 0));
        painter.dispose();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter old) => old.seconds != seconds;
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    required this.node,
    required this.name,
    required this.timeline,
    required this.selected,
    required this.onTap,
  });

  final DesignNode node;
  final String name;
  final VideoTimeline timeline;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final motion = timeline.motionFor(node.id);
    final duration = timeline.durationMs;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 26,
        child: Row(
          children: [
            SizedBox(
              width: 114,
              child: Row(
                children: [
                  Icon(
                    node is TextNode ? Icons.title : Icons.photo_outlined,
                    size: 12,
                    color: selected ? StudioColors.green : StudioColors.muted,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? StudioColors.ink : StudioColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final track = constraints.maxWidth;
                  final left = duration <= 0
                      ? 0.0
                      : motion.visibleStartMs / duration * track;
                  final barWidth = duration <= 0
                      ? 6.0
                      : ((motion.visibleEndMs - motion.visibleStartMs) /
                                duration *
                                track)
                            .clamp(6.0, track)
                            .toDouble();
                  return Stack(
                    children: [
                      Positioned.fill(
                        top: 9,
                        bottom: 9,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: StudioColors.wash,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      Positioned(
                        left: left.clamp(0.0, track).toDouble(),
                        top: 5,
                        child: Container(
                          height: 16,
                          width: barWidth,
                          decoration: BoxDecoration(
                            color: selected
                                ? StudioColors.green
                                : StudioColors.paleGreen,
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                              color: selected
                                  ? StudioColors.green
                                  : StudioColors.border,
                            ),
                          ),
                          child: Row(
                            children: [
                              if (motion.entrance.isAnimated)
                                const Padding(
                                  padding: EdgeInsets.only(left: 3),
                                  child: Icon(
                                    Icons.play_arrow_rounded,
                                    size: 9,
                                    color: Colors.white,
                                  ),
                                ),
                              const Spacer(),
                              if (motion.exit.isAnimated)
                                const Padding(
                                  padding: EdgeInsets.only(right: 3),
                                  child: Icon(
                                    Icons.stop_rounded,
                                    size: 9,
                                    color: Colors.white,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MotionInspector extends StatefulWidget {
  const _MotionInspector({
    required this.studio,
    required this.node,
    required this.layerName,
  });

  final StudioController studio;
  final DesignNode? node;
  final String? layerName;

  @override
  State<_MotionInspector> createState() => _MotionInspectorState();
}

class _MotionInspectorState extends State<_MotionInspector> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    if (node == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: StudioColors.border)),
        ),
        child: const Text(
          'Select a layer in the timeline to animate it.',
          style: TextStyle(fontSize: 11, color: StudioColors.muted),
        ),
      );
    }
    final timeline = widget.studio.video;
    final motion = timeline.motionFor(node.id);
    void update(LayerMotion next) {
      widget.studio.updateVideo(timeline.withMotion(node.id, next));
    }

    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: StudioColors.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 14, color: StudioColors.green),
                const SizedBox(width: 6),
                Text(
                  'Animate “${widget.layerName}”',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${(motion.visibleStartMs / 1000).toStringAsFixed(1)}s → ${(motion.visibleEndMs / 1000).toStringAsFixed(1)}s',
                  style: const TextStyle(fontSize: 9.5, color: StudioColors.muted),
                ),
                const SizedBox(width: 8),
                Icon(
                  _expanded ? Icons.expand_more : Icons.expand_less,
                  size: 16,
                  color: StudioColors.muted,
                ),
              ],
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 6),
            _windowSlider(motion, update),
            const SizedBox(height: 4),
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _motionEditor(
                  label: 'In',
                  motion: motion.entrance,
                  onChanged: (value) => update(motion.copyWith(entrance: value)),
                ),
                _motionEditor(
                  label: 'Out',
                  motion: motion.exit,
                  onChanged: (value) => update(motion.copyWith(exit: value)),
                ),
                TextButton.icon(
                  onPressed: () => _applyToAll(timeline, motion),
                  icon: const Icon(Icons.done_all, size: 14),
                  label: const Text(
                    'Apply entrance to all layers',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _windowSlider(LayerMotion motion, void Function(LayerMotion) update) {
    final duration = widget.studio.video.durationMs;
    final start = motion.visibleStartMs.clamp(0, duration - 200);
    final end = motion.visibleEndMs.clamp(start + 200, duration);
    return Row(
      children: [
        const SizedBox(
          width: 34,
          child: Text('Show', style: TextStyle(fontSize: 10, color: StudioColors.muted)),
        ),
        Expanded(
          child: RangeSlider(
            min: 0,
            max: duration.toDouble(),
            values: RangeValues(start.toDouble(), end.toDouble()),
            onChanged: (values) => update(
              motion.copyWith(
                visibleStartMs: values.start.round(),
                visibleEndMs: values.end.round(),
              ),
            ),
          ),
        ),
        Text(
          '${((end - start) / 1000).toStringAsFixed(1)}s',
          style: const TextStyle(fontSize: 9.5, color: StudioColors.muted),
        ),
      ],
    );
  }

  Widget _motionEditor({
    required String label,
    required Motion motion,
    required void Function(Motion) onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 26,
          child: Text(
            label,
            style: const TextStyle(fontSize: 10, color: StudioColors.muted),
          ),
        ),
        DropdownButton<MotionEffect>(
          value: motion.effect,
          isDense: true,
          underline: const SizedBox.shrink(),
          style: const TextStyle(fontSize: 10.5, color: StudioColors.ink),
          items: [
            for (final effect in MotionEffect.values)
              DropdownMenuItem(value: effect, child: Text(effect.label)),
          ],
          onChanged: (effect) {
            if (effect != null) onChanged(motion.copyWith(effect: effect));
          },
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 86,
          child: Slider(
            min: 100,
            max: 3000,
            divisions: 29,
            value: motion.durationMs.clamp(100, 3000).toDouble(),
            onChanged: (value) =>
                onChanged(motion.copyWith(durationMs: value.round())),
          ),
        ),
        Text(
          '${(motion.durationMs / 1000).toStringAsFixed(1)}s',
          style: const TextStyle(fontSize: 9.5, color: StudioColors.muted),
        ),
      ],
    );
  }

  void _applyToAll(VideoTimeline timeline, LayerMotion template) {
    final ids = {
      for (final node in widget.studio.document.nodes)
        if (node.type != 'background') node.id,
    };
    var next = timeline;
    for (final id in ids) {
      final current = timeline.motionFor(id);
      next = next.withMotion(
        id,
        current.copyWith(entrance: template.entrance),
      );
    }
    widget.studio.updateVideo(next);
  }
}
