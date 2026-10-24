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

/// How a design arranges the wording on the card.
///
/// Every composition is a single vertical stack in [StudioController]'s reflow
/// order, so a larger field still pushes its siblings instead of overlapping
/// them. What changes is the measure, the alignment, the type scale and the
/// breathing room — the three things that make two invitations look like two
/// designers rather than one recoloured file.
enum InvitationLayout {
  centred('centred', 'Centred', 'Names stacked in the middle'),
  editorial('editorial', 'Editorial', 'A left column with quiet details'),
  statement('statement', 'Statement', 'Sans names with room to breathe');

  const InvitationLayout(this.wireName, this.label, this.blurb);
  final String wireName;
  final String label;
  final String blurb;

  static InvitationLayout fromWire(String? value) {
    for (final layout in InvitationLayout.values) {
      if (layout.wireName == value) return layout;
    }
    return InvitationLayout.centred;
  }
}

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
    this.layout = InvitationLayout.centred,
  });
  final String id, name, caption, paper, ink, accent;
  final bool dark;

  /// Celebrations this design was drawn for. Empty means it suits every
  /// category and always appears on the card step.
  final Set<InvitationCategory> categories;

  /// The vertical arrangement this design draws its wording in.
  final InvitationLayout layout;

  bool suits(InvitationCategory category) =>
      categories.isEmpty || categories.contains(category);

  /// The same design (same art, palette and ID) in another composition.
  ///
  /// The ID is deliberately unchanged: favourites, recents and the asset
  /// resolver all key on the design, not on how its text is arranged.
  InvitationTemplate withLayout(InvitationLayout layout) => InvitationTemplate(
    id,
    name,
    caption,
    paper,
    ink,
    accent,
    dark: dark,
    categories: categories,
    layout: layout,
  );

  String art(InvitationFormat format) => 'assets/art/${id}_${format.name}.png';
  String get thumbnail => 'assets/art/${id}_thumb.png';

  DesignDocument createDocument({
    required String documentId,
    required InvitationFormat format,
    Map<String, String> fields = const {},
  }) {
    final h = format.height.toDouble();
    final nodes = <DesignNode>[
      BackgroundNode(
        id: 'background',
        frame: Rect.fromLTWH(0, 0, 1080, h),
        zIndex: 0,
        color: paper,
        assetId: art(format),
      ),
    ];
    final composer = _Composer(
      nodes: nodes,
      height: h,
      fields: fields,
      ink: ink,
      accent: accent,
      muted: dark ? '#FFD6CBB4' : accent,
      width: 1080,
    );
    switch (layout) {
      case InvitationLayout.centred:
        _composeCentred(composer, format);
      case InvitationLayout.editorial:
        _composeEditorial(composer, format);
      case InvitationLayout.statement:
        _composeStatement(composer, format);
    }
    return DesignDocument(
      id: documentId,
      version: 1,
      width: 1080,
      height: format.height,
      nodes: List.unmodifiable(nodes),
    );
  }
}

/// Builds the text layers of one design.
///
/// Each composition below reads top to bottom exactly as it draws, and every
/// frame is bounded before the next one starts: a name that shrinks to fill its
/// frame can then never paint over the ampersand or the line beneath it.
class _Composer {
  _Composer({
    required this.nodes,
    required this.height,
    required this.fields,
    required this.ink,
    required this.accent,
    required this.muted,
    required this.width,
  });

  final List<DesignNode> nodes;
  final double height;
  final Map<String, String> fields;
  final String ink, accent, muted;
  final double width;

  /// The tallest a name may be drawn so it stops short of [nextTop].
  double nameHeight(double size, double top, double nextTop) =>
      math.min(size * 1.2, (nextTop - top) * height - 2);

  void field(
    String id, {
    required double top, // fraction of the card height
    required double frameHeight,
    required double size,
    String family = 'DMSans',
    int weight = 400,
    double spacing = 0,
    String align = 'center',
    String? color,
    double? boxWidth,
    double left = 0,
    double lineHeight = 1.15,
    String initial = '',
  }) {
    final value =
        fields[id] ??
        invitationFields.where((f) => f.id == id).firstOrNull?.initial ??
        initial;
    final box = boxWidth ?? width;
    final x = align == 'center' ? (width - box) / 2 : left;
    nodes.add(
      fitTextNode(
        TextNode(
          id: id,
          frame: Rect.fromLTWH(x, top * height, box, frameHeight),
          zIndex: nodes.length,
          text: value,
          fontFamily: family,
          fontSize: size,
          fontWeight: weight,
          lineHeight: lineHeight,
          letterSpacing: spacing,
          textColor: color ?? ink,
          textAlign: align,
        ),
        maxHeight: frameHeight,
      ),
    );
  }
}

/// The original arrangement: centred serif names over a centred measure.
///
/// Its numbers are the reference the other compositions were designed away
/// from, so legacy layouts and older drafts keep the card they were made with.
void _composeCentred(_Composer c, InvitationFormat format) {
  final square = format == InvitationFormat.square;
  final story = format == InvitationFormat.story;
  final nameSize = square
      ? 104.0
      : story
      ? 164.0
      : 148.0;
  final firstTop = square ? .220 : .268;
  final ampTop = square ? .330 : .382;

  c.field(
    'header',
    top: square ? .148 : .202,
    frameHeight: 50,
    size: square ? 19 : 22,
    spacing: 3.2,
    boxWidth: 820,
  );
  c.field(
    'first',
    top: firstTop,
    frameHeight: c.nameHeight(nameSize, firstTop, ampTop),
    size: nameSize,
    family: 'CormorantGaramond',
    boxWidth: 850,
  );
  c.field(
    'amp',
    top: ampTop,
    frameHeight: square ? 72 : 90,
    size: square ? 50 : 68,
    family: 'CormorantGaramond',
    color: c.accent,
    initial: '&',
    boxWidth: 820,
  );
  c.field(
    'second',
    top: square ? .390 : .435,
    frameHeight: nameSize * 1.2,
    size: nameSize,
    family: 'CormorantGaramond',
    boxWidth: 850,
  );
  c.field(
    'message',
    top: square ? .520 : .567,
    frameHeight: square ? 62 : 88,
    size: square ? 24 : 29,
    family: 'CormorantGaramond',
    boxWidth: 760,
  );
  c.field(
    'date',
    top: square ? .614 : .650,
    frameHeight: 54,
    size: square ? 27 : 30,
    spacing: 2.2,
    weight: 500,
    boxWidth: 840,
  );
  c.field(
    'time',
    top: square ? .660 : .696,
    frameHeight: 48,
    size: square ? 23 : 26,
    boxWidth: 820,
  );
  c.field(
    'venue',
    top: square ? .731 : .757,
    frameHeight: 64,
    size: square ? 36 : 42,
    family: 'CormorantGaramond',
    weight: 600,
    boxWidth: 820,
  );
  c.field(
    'address',
    top: square ? .783 : .805,
    frameHeight: square ? 60 : 78,
    size: square ? 22 : 24,
    boxWidth: 750,
  );
  c.field(
    'rsvp',
    top: square ? .877 : .881,
    frameHeight: square ? 70 : 90,
    size: square ? 20 : 23,
    color: c.muted,
    boxWidth: 750,
  );
}

/// A left-hand column: small tracked capitals for the announcement, tall serif
/// names, and the practical details stepped down in a quieter sans.
///
/// The column sits inside the artwork's carved centre (the generator keeps
/// decoration out of the middle 52%), so the text never lands on a branch.
void _composeEditorial(_Composer c, InvitationFormat format) {
  const left = 254.0;
  const box = 572.0;
  final square = format == InvitationFormat.square;
  final story = format == InvitationFormat.story;
  final nameSize = square
      ? 96.0
      : story
      ? 150.0
      : 136.0;
  final firstTop = .205;
  final ampTop = .330;
  final secondTop = .390;

  c.field(
    'header',
    top: .150,
    frameHeight: 46,
    size: 18,
    weight: 500,
    spacing: 4.2,
    align: 'left',
    left: left,
    boxWidth: box,
  );
  c.field(
    'first',
    top: firstTop,
    frameHeight: c.nameHeight(nameSize, firstTop, ampTop),
    size: nameSize,
    family: 'CormorantGaramond',
    align: 'left',
    left: left,
    boxWidth: box,
  );
  c.field(
    'amp',
    top: ampTop,
    frameHeight: 48,
    size: 40,
    family: 'CormorantGaramond',
    color: c.accent,
    align: 'left',
    left: left,
    boxWidth: box,
    initial: '&',
  );
  c.field(
    'second',
    top: secondTop,
    frameHeight: c.nameHeight(nameSize, secondTop, .495),
    size: nameSize,
    family: 'CormorantGaramond',
    align: 'left',
    left: left,
    boxWidth: box,
  );
  c.field(
    'message',
    top: .495,
    frameHeight: 80,
    size: 26,
    family: 'CormorantGaramond',
    align: 'left',
    left: left,
    boxWidth: box,
  );
  c.field(
    'date',
    top: .585,
    frameHeight: 46,
    size: 24,
    weight: 500,
    spacing: 2.4,
    align: 'left',
    left: left,
    boxWidth: box,
  );
  c.field(
    'time',
    top: .632,
    frameHeight: 40,
    size: 21,
    align: 'left',
    left: left,
    boxWidth: box,
  );
  c.field(
    'venue',
    top: .685,
    frameHeight: 60,
    size: 34,
    family: 'CormorantGaramond',
    weight: 600,
    align: 'left',
    left: left,
    boxWidth: box,
  );
  c.field(
    'address',
    top: .742,
    frameHeight: 72,
    size: 20,
    align: 'left',
    left: left,
    boxWidth: box,
  );
  c.field(
    'rsvp',
    top: .840,
    frameHeight: 76,
    size: 19,
    align: 'left',
    left: left,
    boxWidth: box,
    color: c.muted,
  );
}

/// A modern centred card: sans-serif names, a wide-tracked announcement and
/// more air between the blocks than the serif arrangement allows.
void _composeStatement(_Composer c, InvitationFormat format) {
  final square = format == InvitationFormat.square;
  final story = format == InvitationFormat.story;
  final nameSize = square
      ? 92.0
      : story
      ? 128.0
      : 112.0;
  final firstTop = .195;
  final ampTop = .315;
  final secondTop = .372;

  c.field(
    'header',
    top: .135,
    frameHeight: 42,
    size: 17,
    weight: 600,
    spacing: 5.2,
    color: c.accent,
  );
  c.field(
    'first',
    top: firstTop,
    frameHeight: c.nameHeight(nameSize, firstTop, ampTop),
    size: nameSize,
    weight: 600,
    boxWidth: 760,
  );
  c.field(
    'amp',
    top: ampTop,
    frameHeight: 52,
    size: 40,
    family: 'CormorantGaramond',
    color: c.accent,
    initial: '&',
  );
  c.field(
    'second',
    top: secondTop,
    frameHeight: c.nameHeight(nameSize, secondTop, .485),
    size: nameSize,
    weight: 600,
    boxWidth: 760,
  );
  c.field(
    'message',
    top: .485,
    frameHeight: 76,
    size: 25,
    family: 'CormorantGaramond',
    boxWidth: 700,
  );
  c.field(
    'date',
    top: .575,
    frameHeight: 42,
    size: 22,
    weight: 500,
    spacing: 3.4,
    boxWidth: 760,
  );
  c.field(
    'time',
    top: .615,
    frameHeight: 36,
    size: 20,
  );
  c.field(
    'venue',
    top: .668,
    frameHeight: 56,
    size: 33,
    family: 'CormorantGaramond',
    weight: 600,
  );
  c.field(
    'address',
    top: .722,
    frameHeight: 66,
    size: 20,
    boxWidth: 720,
  );
  c.field(
    'rsvp',
    top: .828,
    frameHeight: 72,
    size: 18,
    spacing: 1.6,
    color: c.muted,
    boxWidth: 700,
  );
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
  const _Motif(this.id, this.name, this.caption, this.layout);
  final String id;
  final String name;
  final String caption;

  /// Composition this motif is drawn in. Spread across the three so a
  /// celebration's ten designs do not all share one arrangement.
  final InvitationLayout layout;
}

const _motifs = [
  _Motif('botanical', 'Botanical', 'organic foliage', InvitationLayout.centred),
  _Motif('celestial', 'Celestial', 'night-sky arcs', InvitationLayout.editorial),
  _Motif('petals', 'Petals', 'soft blossom', InvitationLayout.statement),
  _Motif(
    'foilframe',
    'Foil frame',
    'gilded border',
    InvitationLayout.centred,
  ),
  _Motif('arches', 'Arches', 'warm horizon', InvitationLayout.editorial),
  _Motif('confetti', 'Confetti', 'playful sprinkle', InvitationLayout.statement),
  _Motif('clouds', 'Clouds', 'sweet dreams', InvitationLayout.centred),
  _Motif(
    'constellation',
    'Constellation',
    'starlit',
    InvitationLayout.editorial,
  ),
  _Motif('laurel', 'Laurel', 'classic wreath', InvitationLayout.statement),
  _Motif('sunburst', 'Sunburst', 'radiant rays', InvitationLayout.editorial),
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
    layout: motif.layout,
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

/// The composition [doc] was drawn in, judged from the geometry it carries.
///
/// Nothing stores the layout: a project keeps the document itself, so the
/// arrangement is recoverable from where the text sits. Each candidate is
/// rebuilt for the document's own format and fields and scored on how many
/// bound layers share its left edge, width and alignment. Returns `null` when
/// no candidate is close enough (the host moved the layers), which callers read
/// as "keep whatever is there".
InvitationLayout? detectLayout(
  DesignDocument doc, {
  InvitationTemplate? template,
  double tolerance = 1.0,
  double minimumAgreement = .7,
}) {
  final format = formatFor(doc);
  final fields = fieldsFor(doc);
  final base = template ?? templateFor(doc);

  double score(InvitationLayout layout) {
    final candidate = base
        .withLayout(layout)
        .createDocument(
          documentId: doc.id,
          format: format,
          fields: fields,
        );
    final expected = {
      for (final node in candidate.nodes.whereType<TextNode>())
        if (boundIds.contains(node.id)) node.id: node,
    };
    var matched = 0;
    var total = 0;
    for (final node in doc.nodes.whereType<TextNode>()) {
      final reference = expected[node.id];
      if (reference == null) continue;
      total++;
      final same =
          (node.frame.left - reference.frame.left).abs() <= tolerance &&
          (node.frame.width - reference.frame.width).abs() <= tolerance &&
          node.textAlign == reference.textAlign;
      if (same) matched++;
    }
    return total == 0 ? 0 : matched / total;
  }

  InvitationLayout? best;
  var bestScore = 0.0;
  var tied = false;
  for (final layout in InvitationLayout.values) {
    final value = score(layout);
    if (value > bestScore + 1e-9) {
      best = layout;
      bestScore = value;
      tied = false;
    } else if ((value - bestScore).abs() <= 1e-9) {
      tied = true;
    }
  }
  if (best == null || tied || bestScore < minimumAgreement) return null;
  return best;
}

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
