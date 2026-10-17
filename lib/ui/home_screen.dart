import 'package:flutter/material.dart';

import '../application/studio_controller.dart';
import '../domain/invitation_template.dart';
import '../domain/project.dart';
import '../l10n/app_localizations.dart';
import 'studio_screen.dart';
import 'studio_theme.dart';
import 'widgets/controls.dart';
import 'widgets/document_preview.dart';

/// The landing screen: pick a category, enter the details, then pick a card.
///
/// It never edits the canvas directly; once the user confirms a card it creates
/// a fresh [StudioProject] through [StudioController] and opens the editor.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.studio});
  final StudioController studio;

  static Route<void> route(StudioController studio) =>
      MaterialPageRoute<void>(builder: (_) => HomeScreen(studio: studio));

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _step = 0;
  InvitationCategory? _category;
  InvitationTemplate _template = invitationTemplates.first;
  final Map<String, String> _values = {};

  StudioController get _studio => widget.studio;

  AppLocalizations get _l10n => AppLocalizations.of(context);

  String get _stepTitle => switch (_step) {
    0 => _l10n.stepChooseCategory,
    1 => _l10n.stepYourDetails,
    _ => _l10n.stepPickCard,
  };

  @override
  void dispose() {
    super.dispose();
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _chooseCategory(InvitationCategory category) {
    FocusScope.of(context).unfocus();
    setState(() {
      _category = category;
      _values
        ..clear()
        ..addAll(category.seedFields());
      _template = templatesFor(category).first;
      _step = 1;
    });
  }

  void _back() {
    FocusScope.of(context).unfocus();
    if (_step == 0) return;
    setState(() => _step -= 1);
  }

  Future<void> _openStudio() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => StudioScreen(studio: _studio)));
  }

  Future<void> _continueEditing() => _openStudio();

  Future<void> _openDraft(StudioProject draft) async {
    try {
      await _studio.openProject(draft);
    } on StateError catch (error) {
      _toast(error.message);
      return;
    }
    if (mounted) await _openStudio();
  }

  Future<void> _create() async {
    final category = _category;
    if (category == null) return;
    FocusScope.of(context).unfocus();
    try {
      await _studio.createProject(
        category: category,
        template: _template,
        fields: {
          for (final field in invitationFields)
            field.id: (_values[field.id] ?? field.initial).trim(),
        },
      );
    } on StateError catch (error) {
      _toast(error.message);
      return;
    }
    if (mounted) await _openStudio();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: StudioColors.canvas,
    body: DecoratedBox(
      decoration: const BoxDecoration(gradient: studioPageGradient),
      child: SafeArea(
        child: Column(
          children: [
            _topBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1040),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      child: switch (_step) {
                        0 => _categoryStep(),
                        1 => _detailsStep(),
                        _ => _cardStep(),
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
    decoration: const BoxDecoration(
      color: StudioColors.surface,
      border: Border(bottom: BorderSide(color: StudioColors.border)),
    ),
    child: Row(
      children: [
        if (_step > 0)
          IconButton(
            tooltip: _l10n.back,
            onPressed: _back,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
        const BrandMark(size: 33),
        const SizedBox(width: 10),
        Text(
          _l10n.brandName,
          style: const TextStyle(
            fontFamily: 'CormorantGaramond',
            fontSize: 30,
            height: 1,
            fontWeight: FontWeight.w600,
            letterSpacing: -.8,
          ),
        ),
        const Spacer(),
        TinyLabel(_stepTitle),
      ],
    ),
  );

  Widget _heading(String title, String subtitle) => Column(
    key: ValueKey('heading_$title'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w600,
          letterSpacing: -.6,
        ),
      ),
      const SizedBox(height: 8),
      Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 24),
    ],
  );

  Widget _categoryStep() => Column(
    key: const ValueKey('step_category'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        _l10n.homeCelebrateTitle,
        _l10n.homeCelebrateSubtitle,
      ),
      _continueCard(),
      const SizedBox(height: 26),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 520
              ? 1
              : constraints.maxWidth < 820
              ? 2
              : 3;
          const gap = 14.0;
          final width =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final category in InvitationCategory.values)
                SizedBox(
                  width: width,
                  child: _CategoryTile(
                    category: category,
                    onTap: () => _chooseCategory(category),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _continueCard() {
    final drafts = _studio.drafts;
    if (drafts.isEmpty) return const SizedBox.shrink();
    final latest = drafts.first;
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: StudioColors.accentSoft.withValues(alpha: .5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: StudioColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.edit_note_outlined,
                size: 18,
                color: StudioColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _l10n.continueDraft(latest.title),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              FilledButton(
                onPressed: _continueEditing,
                child: Text(_l10n.continueEditing),
              ),
            ],
          ),
          if (drafts.length > 1) ...[
            const SizedBox(height: 12),
            TinyLabel(_l10n.recentInvitations),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final draft in drafts.take(4))
                  ActionChip(
                    label: Text(
                      draft.title,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11),
                    ),
                    onPressed: () => _openDraft(draft),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailsStep() => Column(
    key: const ValueKey('step_details'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        _category?.label ?? _l10n.stepYourDetails,
        _l10n.homeDetailsSubtitle,
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final twoUp = constraints.maxWidth >= 640;
          const gap = 18.0;
          final width = twoUp
              ? (constraints.maxWidth - gap) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: gap,
            runSpacing: 18,
            children: [
              for (final field in invitationFields)
                SizedBox(
                  width: width,
                  child: BoundInput(
                    key: ValueKey('home_field_${field.id}'),
                    value: _values[field.id] ?? field.initial,
                    label: field.label,
                    maxLines: field.lines,
                    maxLength: field.maxLength,
                    onChanged: (value) => _values[field.id] = value,
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 30),
      _footer(
        primaryLabel: _l10n.chooseACard,
        onPrimary: () {
          FocusScope.of(context).unfocus();
          setState(() => _step = 2);
        },
      ),
    ],
  );

  Widget _cardStep() => Column(
    key: const ValueKey('step_card'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(
        _l10n.chooseACard,
        _category == null
            ? _l10n.homeCardSubtitle
            : _l10n.homeCardSubtitleForCategory(
                _category!.label.toLowerCase(),
              ),
      ),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth < 640 ? 1 : 3;
          const gap = 16.0;
          final width =
              (constraints.maxWidth - gap * (columns - 1)) / columns;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final template
                  in templatesFor(_category ?? InvitationCategory.wedding))
                SizedBox(
                  width: width,
                  child: _CardTile(
                    template: template,
                    fields: _values,
                    selected: _template.id == template.id,
                    onTap: () => setState(() => _template = template),
                  ),
                ),
            ],
          );
        },
      ),
      const SizedBox(height: 30),
      _footer(
        primaryLabel: _l10n.createInvitation,
        onPrimary: _create,
      ),
    ],
  );

  Widget _footer({
    required String primaryLabel,
    required VoidCallback onPrimary,
  }) => Row(
    children: [
      OutlinedButton(onPressed: _back, child: Text(_l10n.back)),
      const Spacer(),
      FilledButton.icon(
        onPressed: onPrimary,
        icon: const Icon(Icons.arrow_forward, size: 17),
        label: Text(primaryLabel),
      ),
    ],
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onTap});
  final InvitationCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: StudioColors.wash,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: StudioColors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: StudioColors.accentSoft,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(category.icon, size: 21, color: StudioColors.accent),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    category.tagline,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: StudioColors.muted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios,
              size: 13,
              color: StudioColors.muted,
            ),
          ],
        ),
      ),
    ),
  );
}

class _CardTile extends StatelessWidget {
  const _CardTile({
    required this.template,
    required this.fields,
    required this.selected,
    required this.onTap,
  });

  final InvitationTemplate template;
  final Map<String, String> fields;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final document = template.createDocument(
      documentId: 'home_preview',
      format: InvitationFormat.classic,
      fields: fields,
    );
    return Material(
      color: selected
          ? StudioColors.accentSoft.withValues(alpha: .55)
          : StudioColors.wash,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? StudioColors.accent : StudioColors.border,
              width: selected ? 1.4 : 1,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: AspectRatio(
                  aspectRatio: 1080 / 1512,
                  child: DocumentPreview(document: document),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      template.name,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle,
                      size: 17,
                      color: StudioColors.accent,
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                template.caption,
                style: const TextStyle(
                  fontSize: 10,
                  color: StudioColors.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
