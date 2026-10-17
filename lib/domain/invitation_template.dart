import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

enum InvitationFormat {
  classic('Classic', '5:7', 1512),
  story('Story', '9:16', 1920),
  square('Square', '1:1', 1080);

  const InvitationFormat(this.label, this.ratio, this.height);
  final String label;
  final String ratio;
  final double height;
  double get width => 1080;
  String get dimensions => '1080 × ${height.toInt()}';
}

class FieldSpec {
  const FieldSpec(
    this.id,
    this.label,
    this.initial, {
    this.maxLength = 160,
    this.lines = 1,
  });
  final String id;
  final String label;
  final String initial;
  final int maxLength;
  final int lines;
}

const invitationFields = [
  FieldSpec('first', 'First name', 'Ayesha', maxLength: 80),
  FieldSpec('second', 'Second name', 'Hamza', maxLength: 80),
  FieldSpec('date', 'Date', 'SATURDAY, 12 DECEMBER 2026'),
  FieldSpec('time', 'Time', 'Reception at 7:00 in the evening'),
  FieldSpec('venue', 'Venue', 'The Royal Orchard'),
  FieldSpec(
    'address',
    'Location / address',
    'Bahawalpur, Punjab',
    lines: 2,
    maxLength: 220,
  ),
  FieldSpec(
    'rsvp',
    'RSVP details',
    'Kindly RSVP by 01 December\n+92 300 123 4567',
    lines: 2,
    maxLength: 220,
  ),
  FieldSpec('header', 'Opening line', 'TOGETHER WITH THEIR FAMILIES'),
  FieldSpec(
    'message',
    'Invitation message',
    'joyfully invite you to celebrate their wedding',
    lines: 2,
    maxLength: 220,
  ),
];

/// The kind of celebration, chosen on the home screen.
///
/// A category seeds the wording and the project title, and orders the designs
/// offered on the card step: templates tagged for the category come first, the
/// universal designs (see [InvitationTemplate.categories]) fill in the rest.
enum InvitationCategory {
  wedding(
    'wedding',
    'Wedding',
    'Celebrate the two of you',
    Icons.favorite_outline,
    {},
  ),
  engagement(
    'engagement',
    'Engagement',
    'Announce your promise',
    Icons.diamond_outlined,
    {
      'header': 'WITH FAMILIES & FRIENDS',
      'message': 'invite you to celebrate their engagement',
    },
  ),
  birthday(
    'birthday',
    'Birthday',
    'Mark another year',
    Icons.cake_outlined,
    {
      'header': 'PLEASE JOIN US TO CELEBRATE',
      'message': 'join us to celebrate a birthday',
    },
  ),
  anniversary(
    'anniversary',
    'Anniversary',
    'Honour the years together',
    Icons.auto_awesome_outlined,
    {
      'header': 'TOGETHER WITH THEIR FAMILIES',
      'message': 'invite you to celebrate their anniversary',
    },
  ),
  babyShower(
    'babyShower',
    'Baby shower',
    'Welcome a little one',
    Icons.child_care_outlined,
    {
      'header': 'A LITTLE ONE IS ON THE WAY',
      'message': 'please join us to welcome their little one',
    },
  ),
  other(
    'other',
    'Something else',
    'Any occasion you like',
    Icons.celebration_outlined,
    {
      'header': 'YOU ARE INVITED',
      'message': 'please join us to celebrate',
    },
  );

  const InvitationCategory(
    this.wireName,
    this.label,
    this.tagline,
    this.icon,
    this.defaults,
  );

  final String wireName;
  final String label;
  final String tagline;
  final IconData icon;

  /// Wording that replaces the shared field initials for this category.
  final Map<String, String> defaults;

  static InvitationCategory? fromWire(String? value) {
    for (final category in InvitationCategory.values) {
      if (category.wireName == value) return category;
    }
    return null;
  }

  /// The initial details-form values: the shared field defaults with this
  /// category's wording layered on top.
  Map<String, String> seedFields() => {
    for (final field in invitationFields) field.id: field.initial,
    ...defaults,
  };

  /// A friendly default project title from the entered names.
  String titleFor(Map<String, String> fields) {
    final first = (fields['first'] ?? '').trim();
    final second = (fields['second'] ?? '').trim();
    if (first.isNotEmpty && second.isNotEmpty) return '$first & $second';
    if (first.isNotEmpty) return first;
    if (second.isNotEmpty) return second;
    return label;
  }
}

const boundIds = {
  'first',
  'second',
  'date',
  'time',
  'venue',
  'address',
  'rsvp',
  'header',
  'message',
  'amp',
};
const fontFamilies = {
  'CormorantGaramond': 'Cormorant Garamond',
  'DMSans': 'DM Sans',
  'NotoNaskhArabic': 'Noto Naskh Arabic',
};

String layerLabel(String id) =>
    invitationFields.where((f) => f.id == id).firstOrNull?.label ??
    (id == 'amp' ? 'Ampersand' : 'Custom text');

class InvitationTemplate {
  const InvitationTemplate(
    this.id,
    this.name,
    this.caption,
    this.paper,
    this.ink,
    this.accent, {
    this.dark = false,
    this.categories = const {},
  });
  final String id, name, caption, paper, ink, accent;
  final bool dark;

  /// Celebrations this design was drawn for. Empty means it suits every
  /// category and always appears on the card step.
  final Set<InvitationCategory> categories;
  bool suits(InvitationCategory category) =>
      categories.isEmpty || categories.contains(category);

  String art(InvitationFormat format) => 'assets/art/${id}_${format.name}.png';
  String get thumbnail => 'assets/art/${id}_thumb.png';

  DesignDocument createDocument({
    required String documentId,
    required InvitationFormat format,
    Map<String, String> fields = const {},
  }) {
    final square = format == InvitationFormat.square;
    final story = format == InvitationFormat.story;
    final h = format.height;
    final nameSize = square
        ? 104.0
        : story
        ? 164.0
        : 148.0;
    final nodes = <DesignNode>[
      BackgroundNode(
        id: 'background',
        frame: Rect.fromLTWH(0, 0, 1080, h),
        zIndex: 0,
        color: paper,
        assetId: art(format),
      ),
    ];
    void text(
      String id,
      double y,
      double height,
      double size, {
      String family = 'DMSans',
      double spacing = 0,
      String? color,
      int weight = 400,
      double width = 820,
      String? initial,
    }) {
      final value =
          fields[id] ??
          invitationFields.where((f) => f.id == id).firstOrNull?.initial ??
          initial ??
          '';
      nodes.add(
        fitTextNode(
          TextNode(
            id: id,
            frame: Rect.fromLTWH((1080 - width) / 2, y * h, width, height),
            zIndex: nodes.length,
            text: value,
            fontFamily: family,
            fontSize: size,
            fontWeight: weight,
            lineHeight: 1.15,
            letterSpacing: spacing,
            textColor: color ?? ink,
            textAlign: 'center',
          ),
          maxHeight: height,
        ),
      );
    }

    text('header', square ? .148 : .202, 50, square ? 19 : 22, spacing: 3.2);
    text(
      'first',
      square ? .220 : .268,
      nameSize * 1.2,
      nameSize,
      family: 'CormorantGaramond',
      width: 850,
    );
    text(
      'amp',
      square ? .330 : .382,
      square ? 72 : 90,
      square ? 50 : 68,
      family: 'CormorantGaramond',
      color: accent,
      initial: '&',
    );
    text(
      'second',
      square ? .390 : .435,
      nameSize * 1.2,
      nameSize,
      family: 'CormorantGaramond',
      width: 850,
    );
    text(
      'message',
      square ? .520 : .567,
      square ? 62 : 88,
      square ? 24 : 29,
      family: 'CormorantGaramond',
      width: 760,
    );
    text(
      'date',
      square ? .614 : .650,
      54,
      square ? 27 : 30,
      spacing: 2.2,
      weight: 500,
      width: 840,
    );
    text('time', square ? .660 : .696, 48, square ? 23 : 26);
    text(
      'venue',
      square ? .731 : .757,
      64,
      square ? 36 : 42,
      family: 'CormorantGaramond',
      weight: 600,
    );
    text(
      'address',
      square ? .783 : .805,
      square ? 60 : 78,
      square ? 22 : 24,
      width: 750,
    );
    text(
      'rsvp',
      square ? .877 : .881,
      square ? 70 : 90,
      square ? 20 : 23,
      color: dark ? '#FFD6CBB4' : accent,
      width: 750,
    );
    return DesignDocument(
      id: documentId,
      version: 1,
      width: 1080,
      height: h,
      nodes: List.unmodifiable(nodes),
    );
  }
}

const invitationTemplates = [
  InvitationTemplate(
    'botanical',
    'Botanical vows',
    'Organic · timeless',
    '#FFF6F3EB',
    '#FF354A3D',
    '#FF7A775C',
  ),
  InvitationTemplate(
    'midnight',
    'After dark',
    'Elegant · celestial',
    '#FF172C34',
    '#FFF2EBDD',
    '#FFB9A275',
    dark: true,
  ),
  InvitationTemplate(
    'rosewater',
    'Rosewater',
    'Soft · romantic',
    '#FFF8EFEC',
    '#FF69464F',
    '#FFA76F77',
  ),
  InvitationTemplate(
    'gilded',
    'Gilded bloom',
    'Luxe · gold foil',
    '#FF0F2A26',
    '#FFF6EFDC',
    '#FFC8A24B',
    dark: true,
    categories: {InvitationCategory.wedding, InvitationCategory.anniversary},
  ),
  InvitationTemplate(
    'terracotta',
    'Terracotta',
    'Warm · desert arch',
    '#FFF7EFE7',
    '#FF7A4A32',
    '#FFC87F5A',
    categories: {
      InvitationCategory.wedding,
      InvitationCategory.engagement,
      InvitationCategory.other,
    },
  ),
  InvitationTemplate(
    'blush',
    'Blush petals',
    'Gentle · petals',
    '#FFFDF0F2',
    '#FF8A4A5A',
    '#FFE39AA8',
    categories: {
      InvitationCategory.engagement,
      InvitationCategory.anniversary,
      InvitationCategory.babyShower,
    },
  ),
  InvitationTemplate(
    'confetti',
    'Confetti pop',
    'Playful · bright',
    '#FFFFF8EC',
    '#FF2E3A59',
    '#FFF07A5F',
    categories: {InvitationCategory.birthday, InvitationCategory.other},
  ),
  InvitationTemplate(
    'littleone',
    'Little one',
    'Sweet · cloud nine',
    '#FFEFF6FB',
    '#FF4A6B86',
    '#FFF2B8C6',
    categories: {InvitationCategory.babyShower},
  ),
  InvitationTemplate(
    'starlight',
    'Starlight',
    'Dreamy · night sky',
    '#FF111A3A',
    '#FFF3F1E7',
    '#FFF0C878',
    dark: true,
    categories: {
      InvitationCategory.babyShower,
      InvitationCategory.birthday,
    },
  ),
];

/// Designs to offer on the card step for [category]: the category-specific art
/// first, then the universal designs. Never empty.
List<InvitationTemplate> templatesFor(InvitationCategory category) => [
  ...invitationTemplates.where(
    (t) => t.categories.isNotEmpty && t.suits(category),
  ),
  ...invitationTemplates.where((t) => t.categories.isEmpty),
];

InvitationTemplate templateFor(DesignDocument doc) {
  final bg = doc.nodes.whereType<BackgroundNode>().firstOrNull;
  return invitationTemplates.firstWhere(
    (t) => bg?.assetId?.contains('/${t.id}_') ?? false,
    orElse: () => invitationTemplates.first,
  );
}

InvitationFormat formatFor(DesignDocument doc) =>
    InvitationFormat.values.firstWhere(
      (f) => f.height == doc.height,
      orElse: () => InvitationFormat.classic,
    );

TextStyle nodeTextStyle(TextNode node, {double? size}) => TextStyle(
  fontFamily: node.fontFamily,
  fontFamilyFallback: const ['NotoNaskhArabic'],
  fontSize: size ?? node.fontSize,
  fontWeight: FontWeight.values[((node.fontWeight ~/ 100) - 1).clamp(0, 8)],
  height: node.lineHeight,
  letterSpacing: node.letterSpacing,
);

/// Keep the entire value, shrinking only when needed. No truncation/ellipsis.
TextNode fitTextNode(TextNode node, {double? maxHeight}) {
  final allowed = maxHeight ?? node.frame.height;
  final painter = TextPainter(
    textDirection: invitationTextDirection(node.text),
  );
  double measure(double size) {
    painter.text = TextSpan(
      text: node.text,
      style: nodeTextStyle(node, size: size),
    );
    painter.layout(maxWidth: math.max(2, node.frame.width));
    return painter.height;
  }

  var size = node.fontSize;
  if (measure(size) > allowed) {
    var low = math.min(12.0, size), high = size;
    for (var i = 0; i < 20; i++) {
      final mid = (low + high) / 2;
      if (measure(mid) <= allowed) {
        low = mid;
      } else {
        high = mid;
      }
    }
    size = low;
  }
  painter.dispose();
  return node.copyWith(fontSize: size);
}

Map<String, String> fieldsFor(DesignDocument doc) => {
  for (final n in doc.nodes.whereType<TextNode>())
    if (boundIds.contains(n.id)) n.id: n.text,
};
