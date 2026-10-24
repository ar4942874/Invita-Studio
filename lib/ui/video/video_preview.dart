import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../../application/studio_controller.dart';
import '../../services/video/frame_renderer.dart';
import '../../services/video/video_media.dart';
import 'video_playback.dart';

/// Imported media resolved for a project, plus "missing" flags so the UI can
/// explain a broken reference instead of silently rendering a blank frame.
class VideoMediaBundle {
  const VideoMediaBundle({
    this.clip,
    this.audio,
    this.clipMissing = false,
    this.audioMissing = false,
  });

  static const VideoMediaBundle empty = VideoMediaBundle();

  final ImportedClip? clip;
  final ImportedAudio? audio;
  final bool clipMissing;
  final bool audioMissing;
}

/// Live preview of the video invitation.
///
/// It paints with [TimelineFrameRenderer], the same code the exporter uses, so
/// animations, fonts and framing match the MP4 frame-for-frame.
class VideoPreview extends StatefulWidget {
  const VideoPreview({
    super.key,
    required this.studio,
    required this.playback,
    required this.media,
    this.borderRadius = 18,
  });

  final StudioController studio;
  final VideoPlaybackController playback;
  final VideoMediaBundle media;
  final double borderRadius;

  @override
  State<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends State<VideoPreview> {
  Map<String, ui.Image> _images = {};
  String _signature = '';
  TimelineFrameRenderer? _renderer;
  ClipFrameCache? _clipCache;
  ImportedClip? _clip;
  ui.Image? _background;
  int _revision = 0;
  bool _loadingImages = false;
  ui.Size _paintSize = ui.Size.zero;

  @override
  void initState() {
    super.initState();
    widget.studio.addListener(_onDocumentChanged);
    widget.playback.addListener(_onPositionChanged);
    _syncDocument();
    _syncClip();
    _onPositionChanged();
  }

  @override
  void didUpdateWidget(covariant VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.studio != widget.studio) {
      oldWidget.studio.removeListener(_onDocumentChanged);
      widget.studio.addListener(_onDocumentChanged);
      _syncDocument();
    }
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.removeListener(_onPositionChanged);
      widget.playback.addListener(_onPositionChanged);
      _onPositionChanged();
    }
    if (!identical(oldWidget.media.clip, widget.media.clip)) {
      _syncClip();
      _onPositionChanged();
    }
  }

  @override
  void dispose() {
    widget.studio.removeListener(_onDocumentChanged);
    widget.playback.removeListener(_onPositionChanged);
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _background?.dispose();
    _clipCache?.dispose();
    super.dispose();
  }

  void _onDocumentChanged() => _syncDocument();

  void _onPositionChanged() {
    final clip = _clip;
    final cache = _clipCache;
    if (clip == null || cache == null) {
      // Always repaint: with an artwork background there is no decoded frame to
      // trigger a rebuild, and a frozen painter would hide the animation.
      final previous = _background;
      setState(() {
        _background = null;
        _revision++;
      });
      previous?.dispose();
      return;
    }
    final index = clipFrameIndexFor(
      timeline: widget.studio.video,
      manifest: clip.manifest,
      timeMs: _paintTimeMs,
    );
    final cached = cache.peek(index);
    if (cached != null) {
      _setBackground(cached);
      return;
    }
    unawaited(
      cache.ensure(index).then((image) {
        // The cache may have been replaced while this decode was in flight
        // (resize or re-import); its images are disposed with the old cache.
        if (!mounted || image == null || !identical(cache, _clipCache)) return;
        _setBackground(image);
      }),
    );
  }

  void _setBackground(ui.Image image) {
    final clone = image.clone();
    final previous = _background;
    setState(() {
      _background = clone;
      _revision++;
    });
    previous?.dispose();
  }

  void _syncClip() {
    final clip = widget.media.clip;
    if (identical(clip, _clip)) return;
    _clipCache?.dispose();
    _clipCache = null;
    _clip = clip;
    _background?.dispose();
    _background = null;
    if (clip != null) {
      _clipCache = ClipFrameCache(
        clip: clip,
        maxEntries: 6,
        decodeWidth: _paintSize.width > 0 ? (_paintSize.width * 2).round() : 720,
      );
    }
  }

  /// The instant the preview paints.
  ///
  /// While idle at the very start of the card it paints the settled frame, so
  /// an entrance animation never leaves an apparently blank preview before the
  /// user presses play.
  int get _paintTimeMs {
    final playback = widget.playback;
    final position = playback.positionMs;
    if (playback.playing || position > 0) return position;
    return widget.studio.video.settledTimeMs;
  }

  String _imageSignature(DesignDocument document) {
    final refs = <String>[];
    for (final node in document.nodes) {
      String? key;
      if (node is ImageNode) key = CanvasImageReference.fromImageNode(node).cacheKey;
      if (node is BackgroundNode && node.hasBackgroundImage) {
        key = CanvasImageReference.fromBackgroundNode(node).cacheKey;
      }
      if (key != null) refs.add(key);
    }
    refs.sort();
    return refs.join('|');
  }

  void _syncDocument() {
    final document = widget.studio.document;
    final signature = _imageSignature(document);
    if (signature != _signature) {
      _signature = signature;
      _rebuildImages(document);
    } else {
      setState(() {
        _renderer = TimelineFrameRenderer(
          document: document,
          imageCache: _images,
          focusLight: widget.studio.project.focusLight,
        );
        _revision++;
      });
    }
  }

  Future<void> _rebuildImages(DesignDocument document) async {
    setState(() => _loadingImages = true);
    Map<String, ui.Image>? next;
    try {
      next = await CanvasImageLoader.buildCacheForDocument(
        document: document,
        imageProvider: widget.studio.editor.imageProvider,
      );
    } catch (_) {
      next = {};
    }
    if (!mounted) {
      for (final image in next.values) {
        image.dispose();
      }
      return;
    }
    final old = _images;
    setState(() {
      _images = next!;
      _renderer = TimelineFrameRenderer(
        document: widget.studio.document,
        imageCache: _images,
        focusLight: widget.studio.project.focusLight,
      );
      _revision++;
      _loadingImages = false;
    });
    for (final image in old.values) {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.studio.document;
    final timeline = widget.studio.video;
    final aspect = document.width / document.height;
    final renderer = _renderer;
    final preview = AspectRatio(
      aspectRatio: aspect,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = ui.Size(constraints.maxWidth, constraints.maxHeight);
          if (size != _paintSize) {
            _paintSize = size;
            // Preview decoding can follow the on-screen size on the next frame.
            if (_clipCache != null && _clip != null) {
              final clip = _clip!;
              _clipCache!.dispose();
              _clipCache = ClipFrameCache(
                clip: clip,
                maxEntries: 6,
                decodeWidth: (size.width * 2).round(),
              );
              _background?.dispose();
              _background = null;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _onPositionChanged();
              });
            }
          }
          return ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: ColoredBox(
              color: Colors.black,
              child: renderer == null
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        RepaintBoundary(
                          child: CustomPaint(
                            painter: VideoFramePainter(
                              renderer: renderer,
                              timeline: timeline,
                              timeMs: _paintTimeMs,
                              backgroundFrame: _background,
                              revision: _revision,
                            ),
                          ),
                        ),
                        if (_loadingImages)
                          const Align(
                            alignment: Alignment.topRight,
                            child: Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 1.5),
                              ),
                            ),
                          ),
                        if (widget.media.clipMissing)
                          Positioned(
                            left: 10,
                            right: 10,
                            bottom: 10,
                            child: _MissingBadge(
                              text:
                                  'Background video is missing on this device. Switch to artwork or re-import it.',
                            ),
                          ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
    return Semantics(
      image: true,
      container: true,
      label: 'Invitation video preview',
      child: preview,
    );
  }
}

class _MissingBadge extends StatelessWidget {
  const _MissingBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xE63A2A1E),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 10.5, height: 1.4),
      ),
    ),
  );
}
