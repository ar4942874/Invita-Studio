import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../application/studio_controller.dart';
import '../domain/invitation_template.dart';
import '../domain/project.dart';
import '../domain/relative_time.dart';
import '../l10n/app_localizations.dart';
import 'home_theme.dart';
import 'occasion_theme.dart';
import 'project_actions.dart';
import 'studio_screen.dart';
import 'widgets/controls.dart';
import 'widgets/document_preview.dart';

/// The landing screen: pick a category, enter the details, then pick a card.
///
/// It never edits the canvas directly; once the user confirms a card it creates
/// a fresh [StudioProject] through [StudioController] and opens the editor.
///
/// Composition follows the OpenDesign `elegant` package: serif display
/// headlines at hero scale, generous section rhythm, quiet ringed cards.
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

  /// The room this celebration opens in. Before a category is chosen the
  /// wizard shows the neutral warm palette rather than guessing.
  OccasionTheme get _occasion => OccasionTheme.forCategory(
    _category ?? InvitationCategory.other,
  );

  /// The home shell runs on the OpenDesign `elegant` package; see
  /// `home_theme.dart`. Derived from the chosen occasion and cached per
  /// category, because `ThemeData` is rebuilt every frame otherwise.
  final Map<InvitationCategory, ThemeData> _themes = {};
  ThemeData get _elegant => _themes.putIfAbsent(
    _occasion.category,
    () => elegantHomeTheme(occasion: _occasion),
  );

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

  Future<void> _openStudio({bool startGuide = false}) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            StudioScreen(studio: _studio, startGuide: startGuide),
      ),
    );
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
    // A brand-new card gets the tour; a draft the host opens does not.
    if (mounted) await _openStudio(startGuide: true);
  }

  @override
  Widget build(BuildContext context) => OccasionScope(
    theme: _occasion,
    child: Theme(
      data: _elegant,
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: _occasion.canvas,
          body: DecoratedBox(
            decoration: BoxDecoration(gradient: _occasion.pageGradient),
          child: SafeArea(
            child: Column(
              children: [
                _topBar(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(0, 0, 0, 56),
                    child: Center(
                      child: ConstrainedBox(
                        // --container-max from the Elegant contract.
                        constraints: const BoxConstraints(maxWidth: 1180),
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
      ),
    ),
    ),
  );

  Widget _topBar() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    decoration: BoxDecoration(
      color: _occasion.surface,
      border: Border(bottom: BorderSide(color: _occasion.borderSoft)),
    ),
    child: Row(
      children: [
        if (_step > 0)
          IconButton(
            tooltip: _l10n.back,
            onPressed: _back,
            icon: const Icon(Icons.arrow_back, size: 20),
          ),
        const BrandMark(size: 36),
        const SizedBox(width: 11),
        Text(
          _l10n.brandName,
          style: const TextStyle(
            fontFamily: 'CormorantGaramond',
            fontSize: 32,
            height: 1,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.2,
          ),
        ),
        const Spacer(),
        // The indicator needs ~200px; on the narrowest phones the step title
        // in the editor shell and the heading carry the orientation instead.
        if (MediaQuery.sizeOf(context).width >= 420) _stepsIndicator(),
      ],
    ),
  );

  /// 1 Category → 2 Details → 3 Card, as small numbered pips; the active one
  /// reads in cacao and the label beside it names the current step.
  Widget _stepsIndicator() => Row(
    key: const ValueKey('home_steps'),
    children: [
      Text(_stepTitle, style: const TextStyle(fontSize: 12.5)),
      const SizedBox(width: 12),
      for (var i = 0; i < 3; i++) ...[
        Container(
          width: i == _step ? 26 : 8,
          height: 8,
          decoration: BoxDecoration(
            color: i == _step
                ? _occasion.accent
                : i < _step
                ? _occasion.surfaceWarm
                : _occasion.borderSoft,
            borderRadius: const BorderRadius.all(Radius.circular(4)),
          ),
        ),
        if (i < 2) const SizedBox(width: 6),
      ],
    ],
  );

  /// Serif hero headline at the Elegant display scale — 2xl (42px) on wide
  /// screens, stepping down for phones. Keep `height`/`letterspacing` from
  /// `--leading-tight` and `--tracking-display`.
  double get _heroSize {
    final width = MediaQuery.sizeOf(context).width;
    return width >= 720 ? 42 : width >= 400 ? 34 : 30;
  }

  TextStyle get _displayStyle => TextStyle(
    fontFamily: 'CormorantGaramond',
    fontSize: _heroSize,
    height: 1.02,
    fontWeight: FontWeight.w600,
    letterSpacing: -_heroSize * .025,
    color: _occasion.ink,
  );

  Widget _eyebrow(String text) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.8,
      color: _occasion.meta,
    ),
  );

  Widget _heading(String title, String subtitle, {String? eyebrow}) => Column(
    key: ValueKey('heading_$title'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (eyebrow != null) ...[_eyebrow(eyebrow), const SizedBox(height: 10)],
      Text(title, style: _displayStyle),
      const SizedBox(height: 10),
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Text(
          subtitle,
          style: const TextStyle(fontSize: 15, height: 1.55),
        ),
      ),
      const SizedBox(height: 32),
    ],
  );

  Widget _categoryStep() => Column(
    key: const ValueKey('step_category'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: _heading(
          _l10n.homeCelebrateTitle,
          _l10n.homeCelebrateSubtitle,
          eyebrow: _l10n.brandName,
        ),
      ),
      _continueCard(),
      const SizedBox(height: 26),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 520
                ? 1
                : constraints.maxWidth < 820
                ? 2
                : 3;
            const gap = 18.0;
            final width = (constraints.maxWidth - gap * (columns - 1)) /
                columns;
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
      ),
    ],
  );

  Widget _continueCard() {
    final drafts = _studio.drafts;
    if (drafts.isEmpty) return const SizedBox.shrink();
    final latest = drafts.first;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
      child: Container(
        margin: const EdgeInsets.only(top: 2),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _occasion.surface,
          borderRadius: HomeShape.lgRadius,
          border: Border.all(color: _occasion.borderSoft),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _occasion.accentSoft,
                    borderRadius: HomeShape.smRadius,
                  ),
                  child: Icon(
                    Icons.edit_note_outlined,
                    size: 21,
                    color: _occasion.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _l10n.continueDraft(latest.title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
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
            const SizedBox(height: 14),
            Divider(height: 1, color: _occasion.borderSoft),
            const SizedBox(height: 8),
            TinyLabel(_l10n.recentInvitations, color: _occasion.meta),
            const SizedBox(height: 4),
            for (final draft in drafts.take(4))
              _DraftRow(
                draft: draft,
                active: draft.id == _studio.project.id,
                onOpen: () => _openDraft(draft),
                onDuplicate: () => duplicateDraft(context, _studio, draft),
                onSaveCopy: () => saveProjectCopy(context, draft),
                onDelete: draft.id == _studio.project.id
                    ? null
                    : () => _deleteDraft(draft),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDraft(StudioProject draft) async {
    await _studio.deleteDraft(draft.id);
    if (mounted) _toast('Draft deleted.');
  }

  Widget _detailsStep() => Column(
    key: const ValueKey('step_details'),
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: _heading(
          _category?.label ?? _l10n.stepYourDetails,
          _l10n.homeDetailsSubtitle,
          eyebrow: _l10n.stepYourDetails,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final twoUp = constraints.maxWidth >= 640;
            const gap = 24.0;
            final width = twoUp
                ? (constraints.maxWidth - gap) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: 20,
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
                      compact: false,
                      onChanged: (value) => _values[field.id] = value,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
      const SizedBox(height: 28),
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
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: _heading(
          _l10n.chooseACard,
          _category == null
              ? _l10n.homeCardSubtitle
              : _l10n.homeCardSubtitleForCategory(_category!.label.toLowerCase()),
          eyebrow: _l10n.stepPickCard,
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 640 ? 1 : 3;
            const gap = 20.0;
            final width = (constraints.maxWidth - gap * (columns - 1)) /
                columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final template in templatesFor(
                  _category ?? InvitationCategory.wedding,
                ))
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
      ),
      const SizedBox(height: 28),
      _footer(primaryLabel: _l10n.createInvitation, onPrimary: _create),
    ],
  );

  Widget _footer({
    required String primaryLabel,
    required VoidCallback onPrimary,
  }) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
    child: Column(
      children: [
        Divider(height: 1, color: _occasion.borderSoft),
        const SizedBox(height: 24),
        Row(
          children: [
            OutlinedButton(
              onPressed: _back,
              child: Text(_l10n.back, style: const TextStyle(fontSize: 14)),
            ),
            const Spacer(),
            FilledButton.icon(
              onPressed: onPrimary,
              icon: const Icon(Icons.arrow_forward, size: 17),
              label: Text(primaryLabel, style: const TextStyle(fontSize: 14)),
            ),
          ],
        ),
      ],
    ),
  );
}

/// One category choice: a warm medallion, the label and a tagline, inside a
/// quiet ringed card that lifts slightly on hover — Elegant's `elev-raised`
/// softened for a landing grid.
class _CategoryTile extends StatefulWidget {
  const _CategoryTile({required this.category, required this.onTap});
  final InvitationCategory category;
  final VoidCallback onTap;

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final o = occasionFor(context);
    final category = widget.category;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: o.surface,
          borderRadius: HomeShape.lgRadius,
          border: Border.all(
            color: _hovered ? o.border : o.borderSoft,
          ),
          boxShadow: _hovered
              ? [
                  BoxShadow(
                    color: o.ink.withValues(alpha: .07),
                    blurRadius: 28,
                    offset: const Offset(0, 10),
                  ),
                ]
              : const [],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: HomeShape.lgRadius,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: HomeShape.lgRadius,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [o.surfaceWarm, o.accentSoft],
                      ),
                      borderRadius: const BorderRadius.all(
                        Radius.circular(14),
                      ),
                    ),
                    child: Icon(
                      category.icon,
                      size: 25,
                      color: o.accent,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category.label,
                          style: TextStyle(
                            fontFamily: 'CormorantGaramond',
                            fontSize: 21,
                            height: 1.1,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.2,
                            color: o.ink,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          category.tagline,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.45,
                            color: o.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: o.wash,
                    ),
                    child: Icon(
                      Icons.arrow_forward,
                      size: 14,
                      color: o.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
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
    final o = occasionFor(context);
    final document = template.createDocument(
      documentId: 'home_preview',
      format: InvitationFormat.classic,
      fields: fields,
    );
    // One label per card. Without `excludeSemantics` the whole invitation is
    // announced for every tile — ten full cards read out in a row.
    return Semantics(
      label: '${template.name}, ${template.caption}',
      button: true,
      selected: selected,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected
              ? o.accentSoft.withValues(alpha: .45)
              : o.surface,
          borderRadius: HomeShape.lgRadius,
          border: Border.all(
            color: selected ? o.accent : o.borderSoft,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: HomeShape.lgRadius,
          child: InkWell(
            onTap: onTap,
            borderRadius: HomeShape.lgRadius,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.all(Radius.circular(10)),
                    child: AspectRatio(
                      aspectRatio: 1080 / 1512,
                      // ~300 px wide on a phone: 600 physical px is crisp
                      // without decoding the full 2160 px artwork ten times.
                      child: DocumentPreview(
                        document: document,
                        decodeWidth: 600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          template.name,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_circle,
                          size: 18,
                          color: o.accent,
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Text(
                    template.caption,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.45,
                      color: o.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One draft in the recent list: its title, "Wedding · edited 2 h ago", and the
/// two workflows people actually use when making variations.
class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.draft,
    required this.active,
    required this.onOpen,
    required this.onDuplicate,
    required this.onSaveCopy,
    this.onDelete,
  });

  final StudioProject draft;
  final bool active;
  final VoidCallback onOpen;
  final VoidCallback onDuplicate;
  final VoidCallback onSaveCopy;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final o = occasionFor(context);
    final locale = Localizations.localeOf(context).languageCode;
    final relative = relativeTimeLabel(draft.updatedAt);
    final stamp =
        relative ?? DateFormat.yMMMd(locale).format(draft.updatedAt.toLocal());
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onOpen,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      draft.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${draft.category.label} · edited $stamp',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: o.muted,
                      ),
                    ),
                  ],
                ),
              ),
              if (active)
                Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: TinyLabel('Editing', color: o.meta),
                ),
              PopupMenuButton<String>(
                tooltip: 'Draft options',
                icon: const Icon(Icons.more_vert, size: 18),
                padding: EdgeInsets.zero,
                onSelected: (value) {
                  switch (value) {
                    case 'open':
                      onOpen();
                    case 'duplicate':
                      onDuplicate();
                    case 'copy':
                      onSaveCopy();
                    case 'delete':
                      onDelete?.call();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'open', child: Text('Open')),
                  const PopupMenuItem(
                    value: 'duplicate',
                    child: Text('Duplicate draft'),
                  ),
                  const PopupMenuItem(
                    value: 'copy',
                    child: Text('Save a copy'),
                  ),
                  if (onDelete != null) ...[
                    const PopupMenuDivider(),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete draft'),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
