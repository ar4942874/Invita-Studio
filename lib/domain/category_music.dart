import 'category_music_durations.g.dart';
import 'invitation_template.dart';
import 'video/timeline.dart';

/// The short background tune bundled for each celebration, applied
/// automatically when a project is created from the home wizard.
///
/// The tracks live at `assets/music/<id>.wav` and are synthesised by
/// `tool/generate_music.py`. A bundled tune is a normal [VideoAudio] whose
/// asset ID carries the [assetPrefix]; the media services resolve it from the
/// app bundle instead of managed storage, so it needs no import step. On the web
/// it plays in the preview (the browser export stays silent); on native it is
/// written next to the project's imported music and muxed into the MP4.
abstract final class CategoryMusic {
  static const String assetPrefix = 'tune_';
  static const String folder = 'assets/music';

  /// Gentle defaults so the music sits under the invitation rather than over it.
  ///
  /// The fades are fixed rather than proportional: the shortest tune is over
  /// five seconds, so even the longest fade pair leaves more than two seconds
  /// of audible track.
  static const int volume = 55;
  static const int fadeInMs = 1200;
  static const int fadeOutMs = 1800;

  static String tuneId(InvitationCategory category) =>
      '$assetPrefix${category.wireName}';

  static String assetPath(InvitationCategory category) =>
      '$folder/${tuneId(category)}.wav';

  /// True when [assetId] names a bundled category tune.
  static bool isTune(String? assetId) =>
      assetId != null && assetId.startsWith(assetPrefix);

  /// Real length of [category]'s tune, measured from the bundled WAV.
  ///
  /// Trim bounds, fade limits and the export preflight all read this. It is
  /// generated (see `tool/generate_music.py`) rather than guessed, because a
  /// wrong length silently misplaces every trim handle in the UI.
  static int durationFor(InvitationCategory category) =>
      categoryTuneDurationsMs[category.wireName] ?? fallbackDurationMs;

  /// Real length of the tune behind [assetId], or [fallbackDurationMs] when the
  /// ID is not a bundled tune.
  static int durationForAsset(String assetId) {
    final key = assetId.startsWith(assetPrefix)
        ? assetId.substring(assetPrefix.length)
        : assetId;
    return categoryTuneDurationsMs[key] ?? fallbackDurationMs;
  }

  /// Used only if a category is added before its tune is generated: the
  /// shortest declared tune keeps trim bounds inside a real file.
  static int get fallbackDurationMs =>
      categoryTuneDurationsMs.values.reduce((a, b) => a < b ? a : b);

  static const _titles = <InvitationCategory, String>{
    InvitationCategory.wedding: 'Wedding theme',
    InvitationCategory.engagement: 'Engagement theme',
    InvitationCategory.birthday: 'Birthday theme',
    InvitationCategory.anniversary: 'Anniversary theme',
    InvitationCategory.babyShower: 'Baby shower theme',
    InvitationCategory.other: 'Celebration theme',
  };

  static String title(InvitationCategory category) =>
      _titles[category] ?? 'Celebration theme';

  /// The timeline entry for [category]'s tune.
  static VideoAudio forCategory(InvitationCategory category) => VideoAudio(
    assetId: tuneId(category),
    title: title(category),
    durationMs: durationFor(category),
    volume: volume,
    fadeInMs: fadeInMs,
    fadeOutMs: fadeOutMs,
  );
}
