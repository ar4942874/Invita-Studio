// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get brandName => 'invita';

  @override
  String get back => 'Atrás';

  @override
  String get stepChooseCategory => 'Elige una categoría';

  @override
  String get stepYourDetails => 'Tus datos';

  @override
  String get stepPickCard => 'Elige una tarjeta';

  @override
  String get homeCelebrateTitle => '¿Qué celebramos?';

  @override
  String get homeCelebrateSubtitle =>
      'Elige una categoría para adaptar el texto. Podrás cambiarlo todo después.';

  @override
  String get homeDetailsSubtitle =>
      'Estos datos rellenan tu invitación. El texto largo se reduce para encajar; no se recorta nada.';

  @override
  String get homeCardSubtitle =>
      'Cada diseño conserva tus palabras. Puedes cambiar o rediseñar cuando quieras.';

  @override
  String homeCardSubtitleForCategory(String category) {
    return 'Diseños para $category. Cada diseño conserva tus palabras.';
  }

  @override
  String continueDraft(String title) {
    return 'Continuar «$title»';
  }

  @override
  String get continueEditing => 'Seguir editando';

  @override
  String get recentInvitations => 'Invitaciones recientes';

  @override
  String get chooseACard => 'Elige una tarjeta';

  @override
  String get createInvitation => 'Crear invitación';

  @override
  String get language => 'Idioma';

  @override
  String get languageSystem => 'Predeterminado del sistema';
}
