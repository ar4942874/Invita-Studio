import 'package:flutter/material.dart';
import 'package:flutter_canvas_editor/flutter_canvas_editor.dart';

import '../../application/studio_controller.dart';
import '../../domain/invitation_template.dart';
import '../../services/photo_service.dart';
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
            color: StudioColors.paleGreen,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            number,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: StudioColors.green,
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
      field('date'),
      field('time'),
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

class TemplatesPanel extends StatelessWidget {
  const TemplatesPanel({super.key, required this.studio});
  final StudioController studio;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(23),
    children: [
      const SectionHeading(
        'Find your feeling.',
        subtitle: 'Three original designs. A world of possibilities.',
      ),
      const SizedBox(height: 20),
      for (final template in invitationTemplates)
        Padding(
          padding: const EdgeInsets.only(bottom: 17),
          child: _TemplateTile(studio: studio, template: template),
        ),
      const HintBox(
        'Switching a template keeps your words and custom text. Linked layers get the new design’s layout and styling. Undo brings everything back.',
      ),
    ],
  );
}

class _TemplateTile extends StatelessWidget {
  const _TemplateTile({required this.studio, required this.template});
  final StudioController studio;
  final InvitationTemplate template;
  @override
  Widget build(BuildContext context) {
    final selected = studio.template.id == template.id;
    final doc = template.createDocument(
      documentId: 'thumbnail',
      format: InvitationFormat.classic,
      fields: fieldsFor(studio.document),
    );
    return Material(
      color: selected
          ? StudioColors.paleGreen.withValues(alpha: .55)
          : StudioColors.wash,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        onTap: () {
          FocusScope.of(context).unfocus();
          studio.chooseTemplate(template);
        },
        borderRadius: BorderRadius.circular(11),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? StudioColors.green : StudioColors.border,
              width: selected ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 75,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: DocumentPreview(document: doc),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      template.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      template.caption,
                      style: const TextStyle(
                        fontSize: 10,
                        color: StudioColors.muted,
                      ),
                    ),
                    const SizedBox(height: 13),
                    Row(
                      children: [
                        for (final c in [
                          template.paper,
                          template.ink,
                          template.accent,
                        ])
                          Padding(
                            padding: const EdgeInsets.only(right: 5),
                            child: Container(
                              width: 13,
                              height: 13,
                              decoration: BoxDecoration(
                                color: decodeDocumentColor(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.black.withValues(alpha: .07),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (selected) ...[
                      const SizedBox(height: 13),
                      const Row(
                        children: [
                          Icon(
                            Icons.check_circle,
                            size: 12,
                            color: StudioColors.green,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Selected',
                            style: TextStyle(
                              fontSize: 9,
                              color: StudioColors.green,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
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
                  ? StudioColors.paleGreen
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
                  color: StudioColors.green,
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
                color: StudioColors.green,
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
                    ? StudioColors.paleGreen
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
                            ? StudioColors.green
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
                color: StudioColors.green,
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
    final bytes = photoBytesFromDataUrl(photo.assetId);
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
