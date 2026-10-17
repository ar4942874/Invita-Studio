import 'dart:ui';

/// First-strong direction for invitation text. Digits and punctuation are neutral.
TextDirection invitationTextDirection(String text) {
  for (final rune in text.runes) {
    if ((rune >= 0x0590 && rune <= 0x08FF) ||
        (rune >= 0xFB1D && rune <= 0xFDFF) ||
        (rune >= 0xFE70 && rune <= 0xFEFF)) {
      return TextDirection.rtl;
    }
    if ((rune >= 0x0041 && rune <= 0x005A) ||
        (rune >= 0x0061 && rune <= 0x007A) ||
        (rune >= 0x00C0 && rune <= 0x02AF)) {
      return TextDirection.ltr;
    }
  }
  return TextDirection.ltr;
}
