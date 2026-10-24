import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../../application/studio_controller.dart';
import '../../domain/invitation_template.dart';
import '../../services/invite_actions.dart';
import '../../services/photo_service.dart';
import '../invite_actions_sheet.dart';
import '../schedule_picker.dart';
import '../studio_theme.dart';
import 'controls.dart';
import 'document_preview.dart';

/// Picks a photo, prepares it and places it on the canvas.
Future<void> addPhoto(BuildContext context, StudioController studio) async {
  try {
    final bytes = await pickPhotoBytes();
    if (bytes == null) return;
    await studio.addPhotoFromBytes(bytes);
  } on FormatException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.message)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That photo could not be added.')),
      );
    }
  }
}

class DetailsPanel extends StatelessWidget {
  const DetailsPanel({
    super.key,
    required this.studio,
    required this.onTemplates,
  });
  final StudioController studio;
  final VoidCallback onTemplates;
  Widget field(String id) {
    final spec = invitationFields.firstWhere((f) => f.id == id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: BoundInput(
        key: ValueKey('field_$id'),
        value: studio.fieldValue(id),
        onChanged: (v) => studio.setField(id, v),
        label: spec.label,
        maxLines: spec.lines,
        maxLength: spec.maxLength,
      ),
    );
  }

  Widget heading(String number, String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 17),
    child: Row(
      children: [
        Container(
          width: 23,
          height: 23,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: StudioColors.accentSoft,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: StudioColors.accent,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
  /// The date and time stay free text; the pickers write *into* them, so a host
  /// can still type "Reception at 7:00 in the evening" by hand. The picker also
  /// stores the structured value that the calendar and RSVP actions need.
  Widget _scheduleFields(BuildContext context) {
    final when = studio.project.when;
    final locale = Localizations.localeOf(context).languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        field('date'),
        field('time'),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            OutlinedButton.icon(
              onPressed: () => pickEventDate(context, studio),
              icon: const Icon(Icons.calendar_month_outlined, size: 15),
              label: const Text('Pick a date', style: TextStyle(fontSize: 11)),
            ),
            OutlinedButton.icon(
              onPressed: () => pickEventTime(context, studio),
              icon: const Icon(Icons.schedule_outlined, size: 15),
              label: const Text('Pick a time', style: TextStyle(fontSize: 11)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          when == null
              ? 'Pick a date to unlock calendar and RSVP actions. Your typed '
                    'wording stays exactly as it is.'
              : 'Calendar: ${formatEventDate(when, locale)}'
                    '${when.hasTime ? ' · ${formatEventTime(when, locale)}' : ''}',
          style: const TextStyle(
            fontSize: 9.5,
            height: 1.4,
            color: StudioColors.muted,
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => InviteActionsSheet.show(context, studio),
            icon: const Icon(Icons.qr_code_2, size: 15),
            label: const Text(
              'Calendar file, link & RSVP code',
              style: TextStyle(fontSize: 10.5),
            ),
            style: TextButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(23, 25, 23, 24),
    children: [
      const Text(
        'Make it yours.',
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          letterSpacing: -.5,
        ),
      ),
      const SizedBox(height: 7),
      const Text(
        'Your words, beautifully brought together.',
        style: TextStyle(fontSize: 11, color: StudioColors.muted),
      ),
      const SizedBox(height: 22),
      Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          border: Border.all(color: StudioColors.border),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 34,
              height: 48,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Image.asset(
                  studio.template.thumbnail,
                  fit: BoxFit.cover,
                  // 34 px wide: decoding the full 360 px thumb is waste.
                  cacheWidth: 120,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const TinyLabel('Your template'),
                  const SizedBox(height: 5),
                  Text(
                    studio.template.name,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onTemplates,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                minimumSize: const Size(0, 35),
              ),
              child: const Text('Change', style: TextStyle(fontSize: 10)),
            ),
          ],
        ),
      ),
      heading('01', 'Your people'),
      field('first'),
      field('second'),
      const Divider(),
      heading('02', 'The celebration'),
      _scheduleFields(context),
      field('venue'),
      field('address'),
      const Divider(),
      heading('03', 'The little details'),
      field('rsvp'),
      field('header'),
      field('message'),
      const SizedBox(height: 5),
      const HintBox(
        'Every field updates your invitation live. Long text gently scales down to fit. You can also tap a text layer on the canvas to move or style it.',
      ),
      const SizedBox(height: 22),
      const Center(child: TinyLabel('Made personal. Kept local.')),
    ],
  );
}

/// Which slice of the catalogue the picker is showing.
enum _CatalogTab {
  forYou('For you'),
  all('All designs'),
  favourites('Favourites'),
  recent('Recent');

  const _CatalogTab(this.label);
  final String label;
}

class TemplatesPanel extends StatefulWidget {
  const TemplatesPanel({super.key, required this.studio});
  final StudioController studio;

  @override
  State<TemplatesPanel> createState() => _TemplatesPanelState();
}

/// The design catalogue: a grid with tabs, favourites, recents and a preview of
/// what is currently applied.
///
/// Legacy layouts are never listed — they exist only so older drafts resolve.
class _TemplatesPanelState extends State<TemplatesPanel> {
  /// Designs rendered before the user asks for more.
  ///
  /// The catalogue multiplies (motifs × celebration palettes), so the picker
  /// pages instead of building every tile at once. Only the rows on screen are
  /// built, and each thumbnail decodes at its display width — sixty tiles used
  /// to cost ~43 MB of decoded bitmaps before the user had scrolled at all.
  static const int _pageSize = 24;

  _CatalogTab _tab = _CatalogTab.forYou;
  int _visible = _pageSize;
  final ScrollController _scroll = ScrollController();

  StudioController get _studio => widget.studio;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _selectTab(_CatalogTab tab) {
    if (tab == _tab) return;
    setState(() {
      _tab = tab;
      // A different slice starts at its own first page, at the top.
      _visible = _pageSize;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  List<InvitationTemplate> get _designs {
    final favourites = _studio.favourites;
    final recent = _studio.recentDesigns;
    return switch (_tab) {
      _CatalogTab.forYou => templatesFor(_studio.project.category),
      _CatalogTab.all => catalogueTemplates,
      _CatalogTab.favourites => catalogueTemplates
          .where((t) => favourites.contains(t.id))
          .toList(),
      _CatalogTab.recent => [
        for (final id in recent)
          for (final template in catalogueTemplates)
            if (template.id == id) template,
      ],
    };
  }

  String get _emptyHint => switch (_tab) {
    _CatalogTab.favourites => 'Star a design to keep it here.',
    _CatalogTab.recent => 'Designs you use appear here.',
    _ => 'No designs to show.',
  };

  Future<void> _surprise() async {
    final pool = _designs.isEmpty
        ? templatesFor(_studio.project.category)
        : _designs;
    final next = surpriseDesign(pool, current: _studio.template);
    FocusScope.of(context).unfocus();
    await _studio.chooseTemplate(next);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _studio,
    builder: (context, _) {
      final designs = _designs;
      final visible = designs.take(_visible).toList();
      final remaining = designs.length - visible.length;
      return LayoutBuilder(
        builder: (context, constraints) {
          const gutter = 23.0;
          const gap = 10.0;
          // Two columns whenever they fit; a dense side panel or a very narrow
          // phone falls back to one rather than overflowing the row.
          final available = math.max(0.0, constraints.maxWidth - gutter * 2);
          final columns = available >= 250 ? 2 : 1;
          final tileWidth = columns == 2
              ? (available - gap) / 2
              : available;
          // The bundled thumbnails are 360 px wide; asking for more than that
          // only grows the decoded bitmap, asking for less saves memory.
          final ratio = MediaQuery.devicePixelRatioOf(context);
          final decodeWidth = (tileWidth * ratio).clamp(160.0, 360.0).round();
          final rows = (visible.length + columns - 1) ~/ columns;
          return CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(gutter, gutter, gutter, 0),
                sliver: SliverToBoxAdapter(child: _header(designs)),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(gutter, 16, gutter, 0),
                sliver: designs.isEmpty
                    ? SliverToBoxAdapter(child: _emptyState())
                    : SliverList(
                        delegate: SliverChildBuilderDelegate((context, row) {
                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: row == rows - 1 ? 0 : 14,
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                for (var slot = 0; slot < columns; slot++) ...[
                                  if (slot > 0) const SizedBox(width: gap),
                                  SizedBox(
                                    width: tileWidth,
                                    child: _tile(
                                      visible,
                                      row * columns + slot,
                                      decodeWidth,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }, childCount: rows),
                      ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(gutter, 10, gutter, gutter),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    children: [
                      if (remaining > 0) _showMore(remaining),
                      const HintBox(
                        'Switching a design keeps your words and custom text. Linked layers get the new design’s layout and styling. Undo brings everything back.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );

  /// Everything above the grid: the heading, the tabs and the applied design.
  Widget _header(List<InvitationTemplate> designs) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeading(
        'Find your feeling.',
        subtitle:
            'Ten designs for your celebration, sixty in the catalogue. '
            'Your words stay put when you switch.',
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final tab in _CatalogTab.values)
            _FilterChip(
              label: tab.label,
              selected: _tab == tab,
              onTap: () => _selectTab(tab),
            ),
        ],
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Text(
            '${designs.length} ${designs.length == 1 ? 'design' : 'designs'}',
            style: const TextStyle(fontSize: 9.5, color: StudioColors.muted),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: designs.isEmpty ? null : _surprise,
            icon: const Icon(Icons.shuffle, size: 14),
            label: const Text(
              'Surprise me',
              style: TextStyle(fontSize: 10.5),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      _selectedPreview(),
      const SizedBox(height: 14),
      _compositionPicker(),
    ],
  );

  /// Switches the applied design's arrangement, keeping every word.
  ///
  /// The catalogue already spreads its designs across the three compositions;
  /// this lets one design be taken in any of them, so a host can change the
  /// card's whole feel without losing the design they picked.
  Widget _compositionPicker() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const TinyLabel('Composition'),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _studio.layout?.blurb ?? 'Layers moved — pick one to reset',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, color: StudioColors.muted),
            ),
          ),
        ],
      ),
      const SizedBox(height: 7),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final layout in InvitationLayout.values)
            _FilterChip(
              label: layout.label,
              selected: _studio.layout == layout,
              onTap: () {
                FocusScope.of(context).unfocus();
                _studio.chooseLayout(layout);
              },
            ),
        ],
      ),
    ],
  );

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Text(
      _emptyHint,
      style: const TextStyle(fontSize: 11, color: StudioColors.muted),
    ),
  );

  /// One grid slot. The odd slot of the last row stays empty so the row keeps
  /// its width instead of stretching the final tile.
  Widget _tile(List<InvitationTemplate> visible, int index, int decodeWidth) {
    if (index >= visible.length) return const SizedBox.shrink();
    final template = visible[index];
    return _DesignTile(
      key: ValueKey('design_${template.id}'),
      studio: _studio,
      template: template,
      decodeWidth: decodeWidth,
    );
  }

  Widget _showMore(int remaining) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Center(
      child: OutlinedButton.icon(
        onPressed: () => setState(() => _visible += _pageSize),
        icon: const Icon(Icons.expand_more, size: 16),
        label: Text(
          'Show more ($remaining left)',
          style: const TextStyle(fontSize: 10.5),
        ),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    ),
  );

  /// The applied design, shown large enough to judge it with the host's own
  /// words rather than a stock thumbnail.
  Widget _selectedPreview() => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: StudioColors.wash,
      borderRadius: BorderRadius.circular(11),
      border: Border.all(color: StudioColors.border),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 62,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: ExcludeSemantics(
              child: DocumentPreview(
                document: _studio.document,
                decodeWidth: 240,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const TinyLabel('Selected'),
              const SizedBox(height: 4),
              Text(
                _studio.template.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _studio.template.caption,
                style: const TextStyle(
                  fontSize: 10,
                  color: StudioColors.muted,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${_studio.format.label} · ${_studio.format.dimensions}',
                style: const TextStyle(
                  fontSize: 9,
                  color: StudioColors.muted,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? StudioColors.accentSoft : StudioColors.wash,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? StudioColors.accent : StudioColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            color: selected ? StudioColors.accent : StudioColors.ink,
          ),
        ),
      ),
    ),
  );
}

/// One design in the grid: the bundled thumbnail, its motif name, the palette
/// it was drawn in, and a star.
class _DesignTile extends StatelessWidget {
  const _DesignTile({
    super.key,
    required this.studio,
    required this.template,
    required this.decodeWidth,
  });

  final StudioController studio;
  final InvitationTemplate template;

  /// Physical pixels to decode the thumbnail at: the tile's display width
  /// times the device pixel ratio, capped at the bundled 360 px source.
  final int decodeWidth;

  @override
  Widget build(BuildContext context) {
    final selected = studio.template.id == template.id;
    final favourite = studio.isFavourite(template.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: StudioColors.wash,
          borderRadius: BorderRadius.circular(9),
          child: InkWell(
            onTap: () {
              FocusScope.of(context).unfocus();
              studio.chooseTemplate(template);
            },
            borderRadius: BorderRadius.circular(9),
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: selected ? StudioColors.accent : StudioColors.border,
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Stack(
                children: [
                  AspectRatio(
                    aspectRatio: 1080 / 1512,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.asset(
                        template.thumbnail,
                        fit: BoxFit.cover,
                        // Decode at the size the tile actually draws. Without
                        // this every tile held a full-size bitmap whether or
                        // not it was on screen.
                        cacheWidth: decodeWidth,
                        // The tile already names the design; a second label
                        // here would be read twice.
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                  // The tile shows the artwork, which is shared by every
                  // composition; the tag names the arrangement it will draw.
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .82),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        template.layout.label,
                        style: const TextStyle(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: .2,
                          color: StudioColors.ink,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 2,
                    right: 2,
                    child: Material(
                      color: Colors.white.withValues(alpha: .82),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: favourite
                            ? 'Remove from favourites'
                            : 'Save to favourites',
                        onPressed: () => studio.toggleFavourite(template.id),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 28,
                          height: 28,
                        ),
                        iconSize: 15,
                        icon: Icon(
                          favourite ? Icons.star : Icons.star_border,
                          color: favourite
                              ? StudioColors.accent
                              : StudioColors.muted,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Text(
                template.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            if (selected)
              const Icon(
                Icons.check_circle,
                size: 11,
                color: StudioColors.accent,
              ),
          ],
        ),
        Text(
          template.caption,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 8.5, color: StudioColors.muted),
        ),
      ],
    );
  }
}

class LayersPanel extends StatelessWidget {
  const LayersPanel({super.key, required this.studio});
  final StudioController studio;
  @override
  Widget build(BuildContext context) {
    final nodes = studio.document.nodes
        .where((n) => n is! BackgroundNode)
        .toList()
      ..sort((a, b) => b.zIndex.compareTo(a.zIndex));
    final full = studio.nodeCount >= 49;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SectionHeading(
          'Every detail, editable.',
          subtitle: 'Select a layer to move, rotate, resize or style it.',
        ),
        const SizedBox(height: 17),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: full ? null : studio.addText,
                icon: const Icon(Icons.add, size: 16),
                label: const Text(
                  'Text',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: full ? null : () => addPhoto(context, studio),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                label: const Text(
                  'Photo',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        for (final n in nodes)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: studio.selectedNode?.id == n.id
                  ? StudioColors.accentSoft
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: ListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 4,
                ),
                leading: Icon(
                  n is ImageNode ? Icons.image_outlined : Icons.text_fields,
                  size: 19,
                  color: StudioColors.accent,
                ),
                title: Text(
                  n is ImageNode ? 'Photo' : layerLabel(n.id),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  n is ImageNode
                      ? 'Placed photo'
                      : (n as TextNode).text.isEmpty
                      ? 'Empty text'
                      : n.text.replaceAll('\n', ' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    color: StudioColors.muted,
                  ),
                ),
                trailing: n is TextNode && boundIds.contains(n.id)
                    ? const Tooltip(
                        message: 'Linked to invitation details',
                        child: Icon(
                          Icons.link,
                          size: 14,
                          color: StudioColors.muted,
                        ),
                      )
                    : null,
                onTap: () {
                  FocusScope.of(context).unfocus();
                  studio.selectLayer(n.id);
                },
              ),
            ),
          ),
        const SizedBox(height: 12),
        const HintBox(
          'Linked fields stay connected to Details, even after you move them. Only your own text and photo layers can be deleted.',
        ),
      ],
    );
  }
}

class StylePanel extends StatelessWidget {
  const StylePanel({super.key, required this.studio});
  final StudioController studio;
  Future<void> _customColor(BuildContext context) async {
    final text = TextEditingController(
      text: '#${studio.styleReference.textColor.substring(3)}',
    );
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your color'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 9,
          decoration: const InputDecoration(
            labelText: 'Hex color',
            hintText: '#354A3D',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final raw = text.text.trim();
              if (RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')
                  .hasMatch(raw)) {
                Navigator.pop(
                  context,
                  encodeDocumentColor(decodeDocumentColor(raw)),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Enter 6 or 8 hexadecimal digits, for example #354A3D.',
                    ),
                  ),
                );
              }
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    // Dialog route animations can still refer to the controller until disposed.
    Future<void>.delayed(const Duration(milliseconds: 350), text.dispose);
    if (value != null) studio.styleText(color: value);
  }

  @override
  Widget build(BuildContext context) {
    final photo = studio.selectedPhoto;
    if (photo != null) return _PhotoInspector(studio: studio, photo: photo);
    final reference = studio.styleReference, selected = studio.selectedText;
    final colors = studio.template.dark
        ? ['#FFF2EBDD', '#FFD8C9A6', '#FFFFFFFF', '#FFE6B9C3', '#FFC4D6CC']
        : ['#FF354A3D', '#FF69464F', '#FF93664E', '#FF243C4C', '#FF77715A'];
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      children: [
        const SectionHeading(
          'Finishing touches',
          subtitle: 'A few details. All the difference.',
        ),
        const SizedBox(height: 23),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StudioColors.wash,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.text_fields,
                size: 21,
                color: StudioColors.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TinyLabel(
                      selected == null
                          ? 'Styling both names'
                          : 'Selected layer',
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selected == null
                          ? 'The happy couple'
                          : layerLabel(selected.id),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected != null)
                IconButton(
                  tooltip: 'Clear selection',
                  onPressed: () => studio.selectLayer(null),
                  icon: const Icon(Icons.close, size: 15),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(maxWidth: 22),
                ),
            ],
          ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 17),
          BoundInput(
            key: ValueKey('inspector_${selected.id}'),
            value: studio.fieldValue(selected.id),
            onChanged: studio.editSelected,
            label: 'Layer text',
            maxLines: 3,
            maxLength: 500,
          ),
        ],
        const SizedBox(height: 24),
        const TinyLabel('Typography'),
        const SizedBox(height: 11),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            border: Border.all(color: StudioColors.border),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: fontFamilies.containsKey(reference.fontFamily)
                  ? reference.fontFamily
                  : 'CormorantGaramond',
              isExpanded: true,
              icon: const Icon(Icons.keyboard_arrow_down, size: 16),
              items: fontFamilies.entries
                  .map(
                    (f) => DropdownMenuItem(
                      value: f.key,
                      child: Text(
                        f.value,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: f.key,
                          fontSize: f.key == 'CormorantGaramond' ? 19 : 12,
                        ),
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                if (v != null) studio.styleText(fontFamily: v);
              },
            ),
          ),
        ),
        const SizedBox(height: 19),
        Row(
          children: [
            const Text('Size', style: TextStyle(fontSize: 11)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: StudioColors.wash,
                border: Border.all(color: StudioColors.border),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                '${reference.fontSize.round()} px',
                style: const TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
        Slider(
          value: reference.fontSize.clamp(8, 240),
          min: 8,
          max: 240,
          semanticFormatterCallback: (v) => '${v.round()} document pixels',
          onChangeStart: (_) => studio.beginStyleSession(),
          onChanged: (v) => studio.styleText(fontSize: v, recordUndo: false),
          onChangeEnd: (_) => studio.endStyleSession(),
        ),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<String>(
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStateProperty.all(
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                  ),
                  side: WidgetStateProperty.all(
                    const BorderSide(color: StudioColors.border),
                  ),
                ),
                segments: const [
                  ButtonSegment(
                    value: 'left',
                    icon: Icon(Icons.format_align_left, size: 16),
                    tooltip: 'Align left',
                  ),
                  ButtonSegment(
                    value: 'center',
                    icon: Icon(Icons.format_align_center, size: 16),
                    tooltip: 'Align center',
                  ),
                  ButtonSegment(
                    value: 'right',
                    icon: Icon(Icons.format_align_right, size: 16),
                    tooltip: 'Align right',
                  ),
                ],
                selected: {reference.textAlign},
                onSelectionChanged: (v) => studio.styleText(align: v.first),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filledTonal(
              isSelected: reference.fontWeight >= 600,
              tooltip: 'Bold',
              onPressed: () => studio.styleText(
                weight: reference.fontWeight >= 600 ? 400 : 600,
              ),
              style: IconButton.styleFrom(
                backgroundColor: reference.fontWeight >= 600
                    ? StudioColors.accentSoft
                    : StudioColors.wash,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(7),
                ),
              ),
              icon: const Icon(Icons.format_bold, size: 19),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 23),
        const TinyLabel('Ink color'),
        const SizedBox(height: 14),
        Wrap(
          spacing: 9,
          runSpacing: 10,
          children: [
            for (final color in colors)
              Tooltip(
                message: '#${color.substring(3)}',
                child: InkWell(
                  onTap: () => studio.styleText(color: color),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 29,
                    height: 29,
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: reference.textColor.toUpperCase() == color
                            ? StudioColors.accent
                            : Colors.transparent,
                        width: 1.4,
                      ),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        color: decodeDocumentColor(color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.black.withValues(alpha: .08),
                        ),
                      ),
                      child: reference.textColor.toUpperCase() == color
                          ? Icon(
                              Icons.check,
                              size: 12,
                              color:
                                  decodeDocumentColor(color)
                                          .computeLuminance() >
                                      .5
                                  ? StudioColors.ink
                                  : Colors.white,
                            )
                          : null,
                    ),
                  ),
                ),
              ),
            Tooltip(
              message: 'Custom color',
              child: InkWell(
                onTap: () => _customColor(context),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  width: 29,
                  height: 29,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: StudioColors.border),
                  ),
                  child: const Icon(Icons.add, size: 15),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Current: #${reference.textColor.substring(3)}',
          style: const TextStyle(fontSize: 10, color: StudioColors.muted),
        ),
        if (selected != null) ...[
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 21),
          const TinyLabel('Arrange layer'),
          const SizedBox(height: 9),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                tooltip: 'Center & straighten',
                onPressed: studio.centerSelected,
                icon: const Icon(Icons.align_horizontal_center),
              ),
              IconButton(
                tooltip: 'Move forward',
                onPressed: () => studio.moveLayer(true),
                icon: const Icon(Icons.flip_to_front),
              ),
              IconButton(
                tooltip: 'Move backward',
                onPressed: () => studio.moveLayer(false),
                icon: const Icon(Icons.flip_to_back),
              ),
              IconButton(
                tooltip: boundIds.contains(selected.id)
                    ? 'Linked field — clear its text instead'
                    : 'Delete text layer',
                onPressed: boundIds.contains(selected.id)
                    ? null
                    : studio.deleteSelected,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: studio.nodeCount >= 49 ? null : studio.addText,
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Text', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: studio.nodeCount >= 49
                    ? null
                    : () => addPhoto(context, studio),
                icon: const Icon(Icons.add_photo_alternate_outlined, size: 16),
                label: const Text('Photo', overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        const HintBox(
          'Tap a layer to select. Drag to position. Use its handles to resize or rotate. Tap it again to edit directly.',
          icon: Icons.touch_app_outlined,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: StudioColors.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'Open source. Yours to make.',
              style: TextStyle(fontSize: 9, color: StudioColors.muted),
            ),
          ],
        ),
      ],
    );
  }
}

/// Inspector shown in the Style tab when a photo layer is selected.
class _PhotoInspector extends StatelessWidget {
  const _PhotoInspector({required this.studio, required this.photo});
  final StudioController studio;
  final ImageNode photo;

  @override
  Widget build(BuildContext context) {
    final bytes = photoBytesCached(photo.assetId);
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 24),
      children: [
        const SectionHeading(
          'Your photo',
          subtitle: 'Position it on the canvas, then choose how it fills.',
        ),
        const SizedBox(height: 23),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: StudioColors.wash,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: StudioColors.border),
                ),
                child: bytes == null
                    ? const Icon(Icons.broken_image_outlined, size: 20)
                    : Image.memory(bytes, fit: BoxFit.cover),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TinyLabel('Selected layer'),
                    SizedBox(height: 4),
                    Text(
                      'Photo',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Clear selection',
                onPressed: () => studio.selectLayer(null),
                icon: const Icon(Icons.close, size: 15),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(maxWidth: 22),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        const TinyLabel('Fill'),
        const SizedBox(height: 11),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'cover', label: Text('Cover')),
            ButtonSegment(value: 'contain', label: Text('Contain')),
            ButtonSegment(value: 'fill', label: Text('Fill')),
          ],
          selected: {photo.fit},
          onSelectionChanged: (v) => studio.setPhotoFit(v.first),
        ),
        const SizedBox(height: 24),
        const Divider(),
        const SizedBox(height: 21),
        const TinyLabel('Arrange layer'),
        const SizedBox(height: 9),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              tooltip: 'Center & straighten',
              onPressed: studio.centerSelected,
              icon: const Icon(Icons.align_horizontal_center),
            ),
            IconButton(
              tooltip: 'Move forward',
              onPressed: () => studio.moveLayer(true),
              icon: const Icon(Icons.flip_to_front),
            ),
            IconButton(
              tooltip: 'Move backward',
              onPressed: () => studio.moveLayer(false),
              icon: const Icon(Icons.flip_to_back),
            ),
            IconButton(
              tooltip: 'Delete photo layer',
              onPressed: studio.deleteSelected,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const HintBox(
          'Drag the photo to reposition it. Use its handles on the canvas to resize or rotate. Pick another layer to keep editing.',
          icon: Icons.touch_app_outlined,
        ),
      ],
    );
  }
}
