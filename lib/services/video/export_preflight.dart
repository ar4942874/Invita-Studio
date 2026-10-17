import '../../domain/video/timeline.dart';
import 'export_media.dart';
import 'video_media.dart';

/// One line of the export checklist.
enum ExportCheck { encoder, artwork, music, browser, output, size, time }

/// A one-tap repair offered next to a check that needs attention.
enum ExportFix { removeMusic, muteMusic, reimportClip, openVideoSettings }

/// A single checklist line: what was checked, what was found, and — when the
/// finding is a problem — the cheapest way to fix it.
class ExportPreflightItem {
  const ExportPreflightItem({
    required this.check,
    required this.ok,
    required this.title,
    required this.detail,
    this.fix,
    this.fixLabel,
    this.alternateFix,
    this.alternateFixLabel,
    this.blocking = false,
  });

  final ExportCheck check;
  final bool ok;
  final String title;
  final String detail;

  /// Repair offered for this line, if any.
  final ExportFix? fix;
  final String? fixLabel;

  /// A second, equally valid repair (e.g. silence the track instead of
  /// deleting it).
  final ExportFix? alternateFix;
  final String? alternateFixLabel;

  /// True when the export cannot run until this line is resolved.
  final bool blocking;
}

/// Everything the export dialog can tell the user *before* rendering a single
/// frame: what is present, what is missing, and what the file will cost.
///
/// This exists so a missing file becomes an actionable screen instead of an
/// exception thrown after the progress bar has already appeared.
class ExportPreflight {
  const ExportPreflight({
    required this.items,
    required this.outputWidth,
    required this.outputHeight,
    required this.frameCount,
    required this.durationMs,
    required this.fps,
    required this.estimatedBytes,
    required this.estimatedSeconds,
    required this.silent,
  });

  final List<ExportPreflightItem> items;
  final int outputWidth;
  final int outputHeight;
  final int frameCount;
  final int durationMs;
  final int fps;
  final int estimatedBytes;

  /// Rough wall-clock estimate for the whole export, in seconds.
  final int estimatedSeconds;

  /// True when the file will have no audio track.
  final bool silent;

  bool get canExport => !items.any((item) => item.blocking);
  List<ExportPreflightItem> get blockers =>
      items.where((item) => item.blocking).toList();

  String get sizeLabel => formatBytes(estimatedBytes);
  String get timeLabel => estimatedSeconds < 60
      ? 'about $estimatedSeconds s'
      : 'about ${(estimatedSeconds / 60).ceil()} min';
}

/// Bitrate the encoder will use for [outputWidth], matching
/// `VideoExporter`'s default so the size estimate is not a different number.
int exportBitrateFor(int outputWidth) => outputWidth >= 1080 ? 8000000 : 3000000;

/// Builds the checklist for one export.
///
/// Pure: no I/O, no widgets. The dialog passes in what it has already resolved
/// (`clipPresent`, `audioPresent`), which is what makes the same logic testable
/// without a renderer.
ExportPreflight buildExportPreflight({
  required VideoTimeline timeline,
  required double documentWidth,
  required double documentHeight,
  required int outputWidth,
  required bool encoderSupported,
  required bool clipPresent,
  required bool audioPresent,
  required bool isWeb,
  int? bitrate,
}) {
  final width = outputWidth.clamp(360, 1080).toInt();
  final scale = documentWidth <= 0 ? 1.0 : width / documentWidth;
  final height = (documentHeight * scale).round();
  final frames = timeline.frameCount;
  final seconds = timeline.durationMs / 1000;
  final bitsPerSecond = bitrate ?? exportBitrateFor(width);
  // Container overhead is a couple of percent. Integer maths keeps the estimate
  // identical on every platform instead of depending on double rounding.
  final bytes =
      (bitsPerSecond ~/ 8) * timeline.durationMs ~/ 1000 * 102 ~/ 100;

  final track = timeline.audio;
  final needsAudio = exportNeedsAudio(track, isWeb: isWeb);
  // Kind, not `hasClip`: a clip background without an asset is still a broken
  // draft that must be fixed before rendering.
  final wantsClip = timeline.background.kind == BackgroundKind.clip;

  final items = <ExportPreflightItem>[
    ExportPreflightItem(
      check: ExportCheck.encoder,
      ok: encoderSupported,
      title: encoderSupported ? 'Encoder available' : 'Encoder unavailable',
      detail: encoderSupported
          ? 'This device can write the video file.'
          : 'This build can preview and edit but cannot encode.',
      blocking: !encoderSupported,
    ),
    ExportPreflightItem(
      check: ExportCheck.artwork,
      ok: !wantsClip || clipPresent,
      title: !wantsClip
          ? 'Artwork background'
          : clipPresent
          ? 'Background clip ready'
          : 'Background clip missing',
      detail: !wantsClip
          ? 'The card artwork is bundled, so nothing needs importing.'
          : clipPresent
          ? 'The imported clip will play behind the card.'
          : isWeb
          ? 'Browser imports last for the session only. Re-import the clip, '
                'or switch the background back to artwork.'
          : 'The frames are not on this device. Re-import the clip, or switch '
                'the background back to artwork.',
      fix: !wantsClip || clipPresent ? null : ExportFix.reimportClip,
      fixLabel: 'Re-import clip',
      blocking: wantsClip && !clipPresent,
    ),
    _musicItem(track, present: audioPresent, needsAudio: needsAudio, isWeb: isWeb),
    if (isWeb)
      const ExportPreflightItem(
        check: ExportCheck.browser,
        ok: true,
        title: 'Browser export is silent',
        detail: 'The music plays in the preview only; the downloaded video has '
            'no audio track.',
      ),
    ExportPreflightItem(
      check: ExportCheck.output,
      ok: true,
      title: 'Output',
      detail: '$width × $height · ${timeline.fps} fps · $frames frames · '
          '${seconds.toStringAsFixed(1)} s',
    ),
    ExportPreflightItem(
      check: ExportCheck.size,
      ok: true,
      title: 'Estimated file',
      detail: '${formatBytes(bytes)} at ${(bitsPerSecond / 1000000).toStringAsFixed(0)} Mbps',
    ),
    ExportPreflightItem(
      check: ExportCheck.time,
      ok: true,
      title: 'Estimated time',
      detail: 'About ${_timeEstimate(frames, width)} s on this device',
    ),
  ];

  return ExportPreflight(
    items: items,
    outputWidth: width,
    outputHeight: height,
    frameCount: frames,
    durationMs: timeline.durationMs,
    fps: timeline.fps,
    estimatedBytes: bytes,
    estimatedSeconds: _timeEstimate(frames, width),
    silent: !needsAudio,
  );
}

ExportPreflightItem _musicItem(
  VideoAudio? track, {
  required bool present,
  required bool needsAudio,
  required bool isWeb,
}) {
  if (track == null) {
    return ExportPreflightItem(
      check: ExportCheck.music,
      ok: true,
      title: 'No music',
      detail: isWeb
          ? 'The browser export is silent either way.'
          : 'The MP4 will have no audio track.',
    );
  }
  if (track.isMuted) {
    return const ExportPreflightItem(
      check: ExportCheck.music,
      ok: true,
      title: 'Music muted',
      detail: 'Deliberately silent: the MP4 will have no audio track.',
    );
  }
  final name = track.title ?? 'Music';
  if (!needsAudio) {
    // Browser export: the track cannot be heard in the file, and a missing
    // file is not a reason to block a silent export.
    return ExportPreflightItem(
      check: ExportCheck.music,
      ok: true,
      title: '$name · preview only',
      detail: 'The music plays in the preview; the downloaded video is silent.',
    );
  }
  if (!present) {
    return ExportPreflightItem(
      check: ExportCheck.music,
      ok: false,
      title: 'Music file missing',
      detail: 'The track is not on this device. Remove it, or export silently '
          'and keep the rest of the card.',
      fix: ExportFix.removeMusic,
      fixLabel: 'Remove music',
      alternateFix: ExportFix.muteMusic,
      alternateFixLabel: 'Switch to silent',
      blocking: true,
    );
  }
  final length = track.durationMs > 0
      ? '${(track.durationMs / 1000).toStringAsFixed(1)} s · '
      : '';
  return ExportPreflightItem(
    check: ExportCheck.music,
    ok: true,
    title: name,
    detail: '$length${track.volume}% · starts '
        '${(track.startMs / 1000).toStringAsFixed(1)} s · AAC track',
  );
}

/// Rough render cost: the encoder is fed one full frame at a time, so the
/// estimate scales with frame count and pixel count, plus a fixed setup cost.
int _timeEstimate(int frames, int width) {
  final perFrame = width >= 1080 ? 0.075 : 0.03;
  return (frames * perFrame + 2.5).ceil();
}
