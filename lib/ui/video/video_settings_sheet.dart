import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../application/studio_controller.dart';
import '../../domain/video/timeline.dart';
import '../../services/video/video_media.dart';
import '../../services/video/video_media_platform.dart';
import '../studio_theme.dart';

const videoTypeGroup = XTypeGroup(
  label: 'Video',
  extensions: ['mp4', 'mov', 'm4v', 'webm', 'mkv'],
  mimeTypes: ['video/mp4', 'video/quicktime', 'video/x-m4v', 'video/webm'],
);

const audioTypeGroup = XTypeGroup(
  label: 'Music',
  extensions: ['mp3', 'm4a', 'aac', 'wav', 'ogg', 'opus', 'flac'],
  mimeTypes: ['audio/mpeg', 'audio/mp4', 'audio/aac', 'audio/wav', 'audio/ogg'],
);

/// Video settings: length, background clip, and music.
///
/// Imported files are copied/extracted into managed asset storage; the project
/// only keeps the asset ID and trims. If the media is later deleted the draft
/// still opens and this sheet explains what is missing.
class VideoSettingsSheet extends StatefulWidget {
  const VideoSettingsSheet({super.key, required this.studio});

  final StudioController studio;

  static Future<void> show(BuildContext context, StudioController studio) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        showDragHandle: true,
        builder: (_) => VideoSettingsSheet(studio: studio),
      );

  @override
  State<VideoSettingsSheet> createState() => _VideoSettingsSheetState();
}

class _VideoSettingsSheetState extends State<VideoSettingsSheet> {
  final VideoMediaService _service = createVideoMediaService();
  ImportedClip? _clip;
  ImportedAudio? _audio;
  bool _clipMissing = false;
  bool _audioMissing = false;
  bool _busy = false;
  bool _cancelled = false;
  String _status = '';
  double _progress = 0;
  int _storageBytes = 0;

  VideoTimeline get _timeline => widget.studio.project.video;

  @override
  void initState() {
    super.initState();
    _loadMedia();
    _refreshStorage();
  }

  Future<void> _refreshStorage() async {
    final bytes = await _service.projectBytes(widget.studio.project.id);
    if (mounted) setState(() => _storageBytes = bytes);
  }

  Future<void> _loadMedia() async {
    final clipId = _timeline.background.assetId;
    final audioId = _timeline.audio?.assetId;
    final clip = clipId == null
        ? null
        : await _service.loadClip(widget.studio.project.id, clipId);
    final audio = audioId == null
        ? null
        : await _service.loadAudio(
            widget.studio.project.id,
            audioId,
            title: _timeline.audio?.title,
            durationMs: _timeline.audio?.durationMs,
          );
    if (!mounted) return;
    setState(() {
      _clip = clip;
      _audio = audio;
      _clipMissing = clipId != null && clip == null;
      _audioMissing = audioId != null && audio == null;
    });
  }

  void _update(VideoTimeline next) => widget.studio.updateVideo(next);

  /// Changes the card length. Reads the stored timeline so existing windows are
  /// preserved, and re-fits the current whole-card preset (its stagger timing
  /// depends on the length) so the card still validates after resizing.
  void _setDuration(int valueMs) {
    final next = (valueMs / 500).round() * 500;
    final timeline = _timeline;
    final layerIds = widget.studio.project.layerIds.toList();
    final preset = MotionPreset.detect(
      layerIds: layerIds,
      durationMs: widget.studio.video.durationMs,
      motions: widget.studio.video.motions,
    );
    var updated = timeline.copyWith(durationMs: next);
    if (preset != null) {
      updated = updated.copyWith(
        motions: preset.build(layerIds: layerIds, durationMs: next),
      );
    }
    _update(updated);
  }

  Future<void> _importClip() async {
    if (!_service.isSupported) {
      _toast(
        'Background video import is not available on this platform. '
        'The bundled artwork works everywhere.',
      );
      return;
    }
    final file = await openFile(acceptedTypeGroups: const [videoTypeGroup]);
    if (file == null || !mounted) return;
    final assetId =
        'clip_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    setState(() {
      _busy = true;
      _cancelled = false;
      _status = 'Reading video…';
      _progress = 0;
    });
    try {
      final result = await _service.extractClip(
        sourcePath: file.path,
        title: file.name,
        projectId: widget.studio.project.id,
        assetId: assetId,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _progress = total <= 0
                ? 0
                : (done / total).clamp(0.0, 1.0).toDouble();
            _status = 'Extracting frame $done of $total…';
          });
        },
      );
      if (_cancelled) {
        await _service.deleteClip(widget.studio.project.id, assetId);
        throw const FormatException('Import cancelled.');
      }
      final clipDuration = result.manifest.proxyDurationMs;
      _update(
        _timeline.copyWith(
          enabled: true,
          background: VideoBackground(
            kind: BackgroundKind.clip,
            assetId: assetId,
            trimStartMs: 0,
            trimEndMs: clipDuration < _timeline.durationMs
                ? clipDuration
                : _timeline.durationMs,
            loop: true,
          ),
        ),
      );
      await _loadMedia();
      await _refreshStorage();
    } catch (error) {
      _toast(_messageFor(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
          _progress = 0;
        });
      }
    }
  }

  Future<void> _removeClip() async {
    final assetId = _timeline.background.assetId;
    _update(
      _timeline.copyWith(
        background: const VideoBackground(),
      ),
    );
    if (assetId != null) {
      await _service.deleteClip(widget.studio.project.id, assetId);
    }
    await _loadMedia();
    await _refreshStorage();
  }

  Future<void> _importMusic() async {
    if (!_service.isMusicSupported) {
      _toast('Music import is not available on this platform.');
      return;
    }
    final file = await openFile(acceptedTypeGroups: const [audioTypeGroup]);
    if (file == null || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'Reading music…';
    });
    try {
      final assetId =
          'audio_${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
      final audio = await _service.importMusic(
        sourcePath: file.path,
        fileName: file.name,
        projectId: widget.studio.project.id,
        assetId: assetId,
      );
      if (audio == null) {
        throw const FormatException('That music file could not be imported.');
      }
      _update(
        _timeline.copyWith(
          audio: VideoAudio(
            assetId: assetId,
            title: file.name,
            startMs: 0,
            durationMs: audio.durationMs,
            volume: 80,
            fadeInMs: 800,
            fadeOutMs: 1200,
          ),
        ),
      );
      await _loadMedia();
      await _refreshStorage();
    } catch (error) {
      _toast(_messageFor(error));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _removeMusic() async {
    final id = _timeline.audio?.assetId;
    _update(_timeline.copyWith(clearAudio: true));
    if (id != null) {
      final audio = await _service.loadAudio(widget.studio.project.id, id);
      if (audio != null) await _service.deleteAudio(audio);
    }
    await _loadMedia();
    await _refreshStorage();
  }

  String _messageFor(Object error) {
    if (error is FormatException) return error.message;
    return 'That media could not be imported. Try a shorter clip.';
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final timeline = _timeline;
    final mediaHeight = MediaQuery.sizeOf(context).height * 0.86;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mediaHeight),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Video settings',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(
              'Length, background and music are saved with this draft.',
              style: const TextStyle(fontSize: 11, color: StudioColors.muted),
            ),
            const SizedBox(height: 16),
            _section('LENGTH'),
            Row(
              children: [
                Expanded(
                  child: Slider(
                    min: TimelineLimits.minDurationMs.toDouble(),
                    max: TimelineLimits.maxDurationMs.toDouble(),
                    divisions: 25,
                    value: timeline.durationMs
                        .clamp(
                          TimelineLimits.minDurationMs,
                          TimelineLimits.maxDurationMs,
                        )
                        .toDouble(),
                    onChanged: (value) => _setDuration(value.round()),
                  ),
                ),
                SizedBox(
                  width: 54,
                  child: Text(
                    '${(timeline.durationMs / 1000).toStringAsFixed(1)} s',
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _section('BACKGROUND'),
            SegmentedButton<BackgroundKind>(
              segments: const [
                ButtonSegment(
                  value: BackgroundKind.artwork,
                  label: Text('Artwork', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.image_outlined, size: 15),
                ),
                ButtonSegment(
                  value: BackgroundKind.clip,
                  label: Text('Video clip', style: TextStyle(fontSize: 11)),
                  icon: Icon(Icons.videocam_outlined, size: 15),
                ),
              ],
              selected: {timeline.background.kind},
              onSelectionChanged: (value) {
                if (value.first == BackgroundKind.artwork) {
                  _update(timeline.copyWith(
                    background: timeline.background.copyWith(
                      kind: BackgroundKind.artwork,
                    ),
                  ));
                } else if (_timeline.background.assetId != null) {
                  _update(timeline.copyWith(
                    background: timeline.background.copyWith(
                      kind: BackgroundKind.clip,
                    ),
                  ));
                } else {
                  _importClip();
                }
              },
            ),
            if (timeline.background.kind == BackgroundKind.clip) ...[
              const SizedBox(height: 10),
              if (_clipMissing)
                _warning(
                  kIsWeb
                      ? 'This background video is not in memory. Browser imports '
                            'last for the session only, so re-import it after a '
                            'reload, or switch back to artwork.'
                      : 'This background video is missing on this device. '
                            'Re-import it, or switch back to artwork.',
                )
              else if (_clip != null) ...[
                Row(
                  children: [
                    const Icon(Icons.movie_outlined, size: 15, color: StudioColors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _clip!.manifest.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    Text(
                      '${(_clip!.durationMs / 1000).toStringAsFixed(1)} s source',
                      style: const TextStyle(fontSize: 10, color: StudioColors.muted),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _trimRow(
                  label: 'Trim',
                  maxMs: _clip!.manifest.proxyDurationMs,
                  startMs: timeline.background.trimStartMs,
                  endMs: timeline.background.trimEndMs == 0
                      ? _clip!.manifest.proxyDurationMs
                      : timeline.background.trimEndMs,
                  onChanged: (start, end) => _update(
                    timeline.copyWith(
                      background: timeline.background.copyWith(
                        trimStartMs: start,
                        trimEndMs: end,
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [
                    const Text('Fit', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 10),
                    DropdownButton<String>(
                      value: timeline.background.fit,
                      isDense: true,
                      style: const TextStyle(fontSize: 11, color: StudioColors.ink),
                      items: const [
                        DropdownMenuItem(value: 'cover', child: Text('Crop to fill')),
                        DropdownMenuItem(value: 'contain', child: Text('Fit inside')),
                        DropdownMenuItem(value: 'fill', child: Text('Stretch')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          _update(timeline.copyWith(
                            background: timeline.background.copyWith(fit: value),
                          ));
                        }
                      },
                    ),
                    const Spacer(),
                    const Text('Loop', style: TextStyle(fontSize: 11)),
                    Switch(
                      value: timeline.background.loop,
                      onChanged: (value) => _update(
                        timeline.copyWith(
                          background: timeline.background.copyWith(loop: value),
                        ),
                      ),
                    ),
                  ],
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _busy ? null : _removeClip,
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Remove clip', style: TextStyle(fontSize: 11)),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: _busy ? null : _importClip,
                icon: const Icon(Icons.video_library_outlined, size: 16),
                label: Text(
                  _clip == null ? 'Import background video' : 'Replace background video',
                  style: const TextStyle(fontSize: 11.5),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _section('MUSIC'),
            if (_timeline.audio == null)
              Text(
                kIsWeb
                    ? 'No music. It will play in the preview; the browser export stays silent.'
                    : 'No music. The MP4 will have no audio track.',
                style: const TextStyle(fontSize: 11, color: StudioColors.muted),
              )
            else ...[
              if (_audioMissing)
                _warning('The music file is missing on this device. Re-import it or remove the track.')
              else
                Row(
                  children: [
                    const Icon(Icons.music_note_outlined, size: 15, color: StudioColors.green),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _timeline.audio!.title ?? 'Music',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11.5),
                      ),
                    ),
                    if (_audio != null && _audio!.durationMs > 0) ...[
                      Text(
                        '${(_audio!.durationMs / 1000).toStringAsFixed(1)} s source',
                        style: const TextStyle(fontSize: 10, color: StudioColors.muted),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _timeline.audio!.isMuted ? 'Muted' : '${_timeline.audio!.volume}%',
                      style: const TextStyle(fontSize: 10, color: StudioColors.muted),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Row(
                children: [
                  const SizedBox(
                    width: 48,
                    child: Text('Volume', style: TextStyle(fontSize: 11)),
                  ),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 100,
                      divisions: 20,
                      value: _timeline.audio!.volume.toDouble(),
                      onChanged: (value) => _update(
                        timeline.copyWith(
                          audio: _timeline.audio!.copyWith(volume: value.round()),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    _timeline.audio!.isMuted ? 'Silent MP4' : 'AAC',
                    style: const TextStyle(fontSize: 9.5, color: StudioColors.muted),
                  ),
                  Tooltip(
                    message: 'Mute writes an MP4 without an audio track',
                    child: Switch(
                      value: !_timeline.audio!.isMuted,
                      onChanged: (value) => _update(
                        timeline.copyWith(
                          audio: _timeline.audio!.copyWith(
                            volume: value
                                ? (_timeline.audio!.volume == 0
                                      ? 80
                                      : _timeline.audio!.volume)
                                : 0,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  const SizedBox(
                    width: 48,
                    child: Text('Starts', style: TextStyle(fontSize: 11)),
                  ),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: (timeline.durationMs - 500).clamp(1, 29500).toDouble(),
                      value: _timeline.audio!.startMs
                          .clamp(0, (timeline.durationMs - 500).clamp(1, 29500))
                          .toDouble(),
                      onChanged: (value) => _update(
                        timeline.copyWith(
                          audio: _timeline.audio!.copyWith(startMs: value.round()),
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '${(_timeline.audio!.startMs / 1000).toStringAsFixed(1)} s',
                    style: const TextStyle(fontSize: 10, color: StudioColors.muted),
                  ),
                ],
              ),
              if (_timeline.audio!.durationMs > 0)
                _trimRow(
                  label: 'Trim',
                  maxMs: _timeline.audio!.durationMs,
                  startMs: _timeline.audio!.trimStartMs,
                  endMs: _timeline.audio!.trimEndMs == 0
                      ? _timeline.audio!.durationMs
                      : _timeline.audio!.trimEndMs,
                  onChanged: (start, end) => _update(
                    timeline.copyWith(
                      audio: _timeline.audio!.copyWith(
                        trimStartMs: start,
                        trimEndMs: end,
                      ),
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: _fadeSlider(
                      'Fade in',
                      _timeline.audio!.fadeInMs,
                      (value) => _update(timeline.copyWith(
                        audio: _timeline.audio!.copyWith(fadeInMs: value),
                      )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _fadeSlider(
                      'Fade out',
                      _timeline.audio!.fadeOutMs,
                      (value) => _update(timeline.copyWith(
                        audio: _timeline.audio!.copyWith(fadeOutMs: value),
                      )),
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _importMusic,
                    icon: const Icon(Icons.library_music_outlined, size: 15),
                    label: const Text('Replace', style: TextStyle(fontSize: 11)),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _removeMusic,
                    icon: const Icon(Icons.delete_outline, size: 15),
                    label: const Text('Remove music', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
            if (_timeline.audio == null) ...[
              const SizedBox(height: 6),
              OutlinedButton.icon(
                onPressed: _busy ? null : _importMusic,
                icon: const Icon(Icons.library_music_outlined, size: 16),
                label: const Text('Import music', style: TextStyle(fontSize: 11.5)),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _progress == 0 ? null : _progress),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(fontSize: 10.5, color: StudioColors.muted),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() => _cancelled = true);
                      await _service.cancelExtraction();
                    },
                    child: const Text('Cancel', style: TextStyle(fontSize: 11)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.sd_storage_outlined, size: 14, color: StudioColors.muted),
                const SizedBox(width: 6),
                Text(
                  'Managed media: ${formatBytes(_storageBytes)}',
                  style: const TextStyle(fontSize: 10, color: StudioColors.muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              kIsWeb
                  ? 'Browser imports are decoded into memory for this session '
                        'only and are not saved, so re-import after a reload. '
                        'Music plays in the preview; the browser export is silent.'
                  : 'Imported video and music are stored on this device, not '
                        'inside the project JSON. Backups need the media '
                        'relinked on another device.',
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.45,
                color: StudioColors.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 9,
        letterSpacing: 1.3,
        fontWeight: FontWeight.w600,
        color: StudioColors.muted,
      ),
    ),
  );

  Widget _warning(String text) => Container(
    padding: const EdgeInsets.all(10),
    margin: const EdgeInsets.only(bottom: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF3E5),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFE9D3B4)),
    ),
    child: Text(
      text,
      style: const TextStyle(fontSize: 10.5, height: 1.4, color: Color(0xFF8A5B1E)),
    ),
  );

  Widget _trimRow({
    required String label,
    required int maxMs,
    required int startMs,
    required int endMs,
    required void Function(int start, int end) onChanged,
  }) {
    final safeMax = maxMs <= 0 ? 1 : maxMs;
    return Row(
      children: [
        SizedBox(
          width: 34,
          child: Text(label, style: const TextStyle(fontSize: 11)),
        ),
        Expanded(
          child: RangeSlider(
            min: 0,
            max: safeMax.toDouble(),
            values: RangeValues(
              startMs.clamp(0, safeMax - 1).toDouble(),
              endMs
                  .clamp((startMs + 1).clamp(1, safeMax), safeMax)
                  .toDouble(),
            ),
            onChanged: (values) =>
                onChanged(values.start.round(), values.end.round()),
          ),
        ),
        Text(
          '${(startMs / 1000).toStringAsFixed(1)}–${(endMs / 1000).toStringAsFixed(1)}s',
          style: const TextStyle(fontSize: 9.5, color: StudioColors.muted),
        ),
      ],
    );
  }

  Widget _fadeSlider(String label, int value, void Function(int) onChanged) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label · ${(value / 1000).toStringAsFixed(1)}s',
            style: const TextStyle(fontSize: 9.5, color: StudioColors.muted),
          ),
          Slider(
            min: 0,
            max: TimelineLimits.maxFadeMs.toDouble(),
            divisions: 20,
            value: value.clamp(0, TimelineLimits.maxFadeMs).toDouble(),
            onChanged: (next) => onChanged(next.round()),
          ),
        ],
      );
}
