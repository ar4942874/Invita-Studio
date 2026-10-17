import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Wait for local fonts before measuring templates or exporting text.
Future<void> loadStudioFonts() async {
  await Future.wait([
    for (final entry in {
      'CormorantGaramond': 'CormorantGaramond.ttf',
      'DMSans': 'DMSans.ttf',
      'NotoNaskhArabic': 'NotoNaskhArabic.ttf',
    }.entries)
      (FontLoader(
        entry.key,
      )..addFont(rootBundle.load('assets/fonts/${entry.value}'))).load(),
  ]);
}

/// Include the complete font licenses in Flutter's in-app license screen.
void registerStudioFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final family in ['CormorantGaramond', 'DMSans', 'NotoNaskhArabic']) {
      yield LicenseEntryWithLineBreaks([
        family,
      ], await rootBundle.loadString('assets/fonts/$family-OFL.txt'));
    }
  });
}
