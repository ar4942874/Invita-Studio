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
    // The name frames sit directly above the ampersand. On a phone the wizard
    // is where the first long name is typed, so the frame must stop before the
    // next layer: otherwise a name that shrinks to fill its full height paints
    // over the "&". Keep a small gutter and never grow past the old height.
    final firstTop = square ? .220 : .268;
    final ampTop = square ? .330 : .382;
    text(
      'first',
      firstTop,
      math.min(nameSize * 1.2, (ampTop - firstTop) * h - 2),
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

/// The original artwork set. Kept so older drafts (whose backgrounds reference
/// these IDs) stay valid and exportable; it is no longer offered on the card
/// step, and it is not browsable in the studio either.
const legacyTemplates = [
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
  ),
  InvitationTemplate(
    'terracotta',
    'Terracotta',
    'Warm · desert arch',
    '#FFF7EFE7',
    '#FF7A4A32',
    '#FFC87F5A',
  ),
  InvitationTemplate(
    'blush',
    'Blush petals',
    'Gentle · petals',
    '#FFFDF0F2',
    '#FF8A4A5A',
    '#FFE39AA8',
  ),
  InvitationTemplate(
    'confetti',
    'Confetti pop',
    'Playful · bright',
    '#FFFFF8EC',
    '#FF2E3A59',
    '#FFF07A5F',
  ),
  InvitationTemplate(
    'littleone',
    'Little one',
    'Sweet · cloud nine',
    '#FFEFF6FB',
    '#FF4A6B86',
    '#FFF2B8C6',
  ),
  InvitationTemplate(
    'starlight',
    'Starlight',
    'Dreamy · night sky',
    '#FF111A3A',
    '#FFF3F1E7',
    '#FFF0C878',
    dark: true,
  ),
];

/// One decorative drawing. The same motif is rendered once per category palette
/// (see [_categoryPalettes]), so every celebration shows ten distinct designs.
class _Motif {
  const _Motif(this.id, this.name, this.caption);
  final String id;
  final String name;
  final String caption;
}

const _motifs = [
  _Motif('botanical', 'Botanical', 'organic foliage'),
  _Motif('celestial', 'Celestial', 'night-sky arcs'),
  _Motif('petals', 'Petals', 'soft blossom'),
  _Motif('foilframe', 'Foil frame', 'gilded border'),
  _Motif('arches', 'Arches', 'warm horizon'),
  _Motif('confetti', 'Confetti', 'playful sprinkle'),
  _Motif('clouds', 'Clouds', 'sweet dreams'),
  _Motif('constellation', 'Constellation', 'starlit'),
  _Motif('laurel', 'Laurel', 'classic wreath'),
  _Motif('sunburst', 'Sunburst', 'radiant rays'),
];

/// Paper, ink and accent for one celebration, mirroring the art generator's
/// `CATEGORY_PALETTES`.
class _Palette {
  const _Palette(this.paper, this.ink, this.accent, {this.dark = false});
  final String paper;
  final String ink;
  final String accent;
  final bool dark;
}

const _categoryPalettes = <InvitationCategory, _Palette>{
  InvitationCategory.wedding: _Palette(
    '#FFF7F2E9',
    '#FF3B4A38',
    '#FF8A7A4E',
  ),
  InvitationCategory.engagement: _Palette(
    '#FFFCF1F1',
    '#FF6E3F4C',
    '#FFC08A93',
  ),
  InvitationCategory.birthday: _Palette(
    '#FFFFF8EC',
    '#FF2E3A59',
    '#FFF07A5F',
  ),
  InvitationCategory.anniversary: _Palette(
    '#FF0F2A26',
    '#FFF6EFDC',
    '#FFC8A24B',
    dark: true,
  ),
  InvitationCategory.babyShower: _Palette(
    '#FFEFF6FB',
    '#FF4A6B86',
    '#FFF2B8C6',
  ),
  InvitationCategory.other: _Palette(
    '#FFF7EFE7',
    '#FF7A4A32',
    '#FFC87F5A',
  ),
};

InvitationTemplate _design(_Motif motif, InvitationCategory category) {
  final palette = _categoryPalettes[category]!;
  return InvitationTemplate(
    '${motif.id}_${category.wireName}',
    motif.name,
    '${category.label} · ${motif.caption}',
    palette.paper,
    palette.ink,
    palette.accent,
    dark: palette.dark,
    categories: {category},
  );
}

/// 10 motifs x 6 categories = 60 designs, ten per celebration.
final _categoryDesigns = <InvitationTemplate>[
  for (final category in InvitationCategory.values)
    for (final motif in _motifs) _design(motif, category),
];

/// Every design the app can render: the legacy set (for drafts) plus the
/// sixty per-category designs. The importer allowlist and image provider are
/// both derived from this list.
final invitationTemplates = <InvitationTemplate>[
  ...legacyTemplates,
  ..._categoryDesigns,
];

/// The browsable catalogue: sixty designs, ten per celebration.
///
/// The legacy layouts are excluded on purpose. They carry no category, exist
/// only so old drafts keep resolving and exporting, and must not come back into
/// the picker — `invitationTemplates` (not this list) is what the asset
/// resolver and allowlist use.
final catalogueTemplates =
    List<InvitationTemplate>.unmodifiable(_categoryDesigns);

/// Exactly ten designs for [category], ordered by motif.
///
/// The fallback covers a future category whose art has not been generated yet:
/// it shows the universal catalogue rather than resurrecting legacy layouts.
List<InvitationTemplate> templatesFor(InvitationCategory category) {
  final designs = catalogueTemplates
      .where((t) => t.categories.contains(category))
      .toList();
  return designs.isEmpty ? catalogueTemplates.take(10).toList() : designs;
}

/// Every bundled background path the app is allowed to render.
///
/// Derived once: the image provider consulted this on every image load and
/// rebuilt the whole 207-string set each time.
final Set<String> invitationArtAssets = Set<String>.unmodifiable({
  for (final format in InvitationFormat.values)
    ...invitationArtAssetsFor(format),
});

/// The bundled backgrounds that belong to one format, for the importer's
/// allowlist. Built once per format.
final Map<InvitationFormat, Set<String>> _artByFormat = {
  for (final format in InvitationFormat.values)
    format: Set<String>.unmodifiable({
      for (final template in invitationTemplates) template.art(format),
    }),
};

Set<String> invitationArtAssetsFor(InvitationFormat format) =>
    _artByFormat[format]!;

/// Background asset path → the design that draws it.
///
/// A document is resolved back to its design on open, on import and on every
/// restore. That used to be a 69 × 3 string scan; this index is built once and
/// does not grow with the number of lookups. First registration wins, matching
/// the old scan order, so a legacy layout keeps the design it always resolved
/// to.
final Map<String, InvitationTemplate> _designByArt = () {
  final index = <String, InvitationTemplate>{};
  for (final template in invitationTemplates) {
    for (final format in InvitationFormat.values) {
      index.putIfAbsent(template.art(format), () => template);
    }
  }
  return Map<String, InvitationTemplate>.unmodifiable(index);
}();

InvitationTemplate templateFor(DesignDocument doc) {
  final asset = doc.nodes.whereType<BackgroundNode>().firstOrNull?.assetId;
  if (asset != null) {
    final design = _designByArt[asset];
    if (design != null) return design;
  }
  return invitationTemplates.first;
}

InvitationFormat formatFor(DesignDocument doc) =>
    InvitationFormat.values.firstWhere(
      (f) => f.height == doc.height,
      orElse: () => InvitationFormat.classic,
    );

/// Looks a design up by ID, for favourites and recently-used lists that store
/// only IDs. Returns `null` for a design that no longer exists.
InvitationTemplate? templateById(String id) {
  for (final template in invitationTemplates) {
    if (template.id == id) return template;
  }
  return null;
}

/// Picks a design for "Surprise me".
///
/// Never returns [current] while another option exists, so the button always
/// changes the card. [random] is injectable so the behaviour can be tested.
InvitationTemplate surpriseDesign(
  List<InvitationTemplate> pool, {
  InvitationTemplate? current,
  math.Random? random,
}) {
  final options = pool.where((t) => t.id != current?.id).toList();
  final source = options.isEmpty ? pool : options;
  return source[(random ?? math.Random()).nextInt(source.length)];
}

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

/// Re-fits every text node of [doc] to its own frame.
///
/// Used before rendering an export (PNG, JPEG or video frame): if a stored
/// frame carries text the live metrics say no longer fits — a device font
/// rounding, a resized frame, an older draft — the downloaded image would
/// draw the overflow over neighbouring layers even though the on-screen
/// preview hid it. Shrinking to [fitTextNode] guarantees the saved output
/// only ever adds whitespace, never overlap.
DesignDocument fitTextDocument(DesignDocument doc) => doc.copyWith(
  nodes: [
    for (final node in doc.nodes)
      if (node is TextNode) fitTextNode(node) else node,
  ],
);

Map<String, String> fieldsFor(DesignDocument doc) => {
  for (final n in doc.nodes.whereType<TextNode>())
    if (boundIds.contains(n.id)) n.id: n.text,
};
