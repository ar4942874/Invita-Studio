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

  /// Bundled length of every tune, in milliseconds.
  static const int durationMs = 12000;

  /// Gentle defaults so the music sits under the invitation rather than over it.
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
    durationMs: durationMs,
    volume: volume,
    fadeInMs: fadeInMs,
    fadeOutMs: fadeOutMs,
  );
}
