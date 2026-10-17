import 'package:flutter/material.dart';

import '../application/studio_controller.dart';
import '../domain/category_music.dart';
import '../domain/invitation_template.dart';
import 'studio_theme.dart';

/// Changes the celebration after the wizard.
///
/// The category is not cosmetic: it sets the wording defaults, the bundled
/// tune and which designs suit the card. This sheet makes those consequences
/// explicit instead of silently swapping things.
class EventSettingsSheet extends StatefulWidget {
  const EventSettingsSheet({super.key, required this.studio});

  final StudioController studio;

  static Future<void> show(BuildContext context, StudioController studio) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => EventSettingsSheet(studio: studio),
      );

  @override
  State<EventSettingsSheet> createState() => _EventSettingsSheetState();
}

class _EventSettingsSheetState extends State<EventSettingsSheet> {
  late InvitationCategory _category = widget.studio.project.category;
  late bool _switchDesign = false;
  bool _busy = false;

  StudioController get _studio => widget.studio;

  void _select(InvitationCategory category) {
    setState(() {
      _category = category;
      // A design drawn for another celebration is a bad default, so offer the
      // matching set; otherwise keep the card the host already chose.
      _switchDesign = !_studio.template.suits(category);
    });
  }

  Future<void> _apply() async {
    setState(() => _busy = true);
    await _studio.updateEventSettings(
      category: _category,
      template: _switchDesign ? templatesFor(_category).first : null,
    );
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(content: Text('Event set to ${_category.label}.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _studio.project.category;
    final changed = _category != current;
    final nextDesign = templatesFor(_category).first;
    final audio = _studio.project.video.audio;
    final tuneSwaps =
        audio != null &&
        CategoryMusic.isTune(audio.assetId) &&
        audio.assetId != CategoryMusic.tuneId(_category);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.86,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Event settings',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            const Text(
              'The celebration sets the wording, the tune and which designs '
              'suit this card.',
              style: TextStyle(fontSize: 11, color: StudioColors.muted),
            ),
            const SizedBox(height: 18),
            const Text(
              'CELEBRATION',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.1,
                color: StudioColors.muted,
              ),
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final category in InvitationCategory.values)
                  _CategoryChip(
                    category: category,
                    selected: category == _category,
                    onTap: _busy ? null : () => _select(category),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: StudioColors.wash,
                borderRadius: StudioShape.smRadius,
                border: Border.all(color: StudioColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Design',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        _studio.template.name,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: StudioColors.muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _studio.template.suits(_category)
                        ? 'Your current design is drawn for ${_category.label.toLowerCase()}.'
                        : 'Your current design was drawn for '
                              '${current.label.toLowerCase()}.',
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.4,
                      color: StudioColors.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Merged so a screen reader announces the switch with its
                  // label and the sentence explaining what it will apply.
                  MergeSemantics(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Use a ${_category.label.toLowerCase()} design',
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Applies ${nextDesign.name}. Your words, '
                                'photos and custom layers are kept.',
                                style: const TextStyle(
                                  fontSize: 9.8,
                                  height: 1.35,
                                  color: StudioColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: _switchDesign,
                          onChanged: _busy
                              ? null
                              : (value) =>
                                    setState(() => _switchDesign = value),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (tuneSwaps) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.music_note_outlined,
                    size: 14,
                    color: StudioColors.muted,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'The bundled tune switches to '
                      '${CategoryMusic.title(_category)}.',
                      style: const TextStyle(
                        fontSize: 10,
                        color: StudioColors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                TextButton(
                  onPressed: _busy ? null : () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: (_busy || (!changed && !_switchDesign))
                      ? null
                      : _apply,
                  child: Text(changed ? 'Save changes' : 'Apply design'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.category,
    required this.selected,
    required this.onTap,
  });

  final InvitationCategory category;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: selected ? StudioColors.accentSoft : StudioColors.wash,
    borderRadius: BorderRadius.circular(20),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? StudioColors.accent : StudioColors.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              category.icon,
              size: 13,
              color: selected ? StudioColors.accent : StudioColors.muted,
            ),
            const SizedBox(width: 5),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? StudioColors.accent : StudioColors.ink,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
