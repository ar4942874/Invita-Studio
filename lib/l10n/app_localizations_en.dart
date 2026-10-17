// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get brandName => 'invita';

  @override
  String get back => 'Back';

  @override
  String get stepChooseCategory => 'Choose a category';

  @override
  String get stepYourDetails => 'Your details';

  @override
  String get stepPickCard => 'Pick a card';

  @override
  String get homeCelebrateTitle => 'What are we celebrating?';

  @override
  String get homeCelebrateSubtitle =>
      'Pick a category to shape the wording. You can change everything later.';

  @override
  String get homeDetailsSubtitle =>
      'These fill your invitation. Long text scales down to fit — nothing is cut off.';

  @override
  String get homeCardSubtitle =>
      'Every design keeps your words. You can switch or restyle at any time.';

  @override
  String homeCardSubtitleForCategory(String category) {
    return 'Designs for a $category, plus our timeless favourites. Every design keeps your words.';
  }

  @override
  String continueDraft(String title) {
    return 'Continue “$title”';
  }

  @override
  String get continueEditing => 'Continue editing';

  @override
  String get recentInvitations => 'Recent invitations';

  @override
  String get chooseACard => 'Choose a card';

  @override
  String get createInvitation => 'Create invitation';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System default';
}
