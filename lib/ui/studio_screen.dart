import 'dart:async';
import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_settings.dart';
import '../application/studio_controller.dart';
import '../domain/project.dart';
import '../domain/video/timeline.dart' show MotionPreset;
import '../l10n/app_localizations.dart';
import '../services/file_actions.dart';
import 'event_settings_sheet.dart';
import 'invite_actions_sheet.dart';
import 'project_actions.dart';
import 'studio_theme.dart';
import 'widgets/artboard.dart';
import 'widgets/controls.dart';
import 'widgets/document_preview.dart';
import 'widgets/export_dialog.dart';
import 'widgets/panels.dart';
import 'video/video_export_dialog.dart';
import 'video/video_settings_sheet.dart';
import 'video/video_workspace.dart';

class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key, required this.studio});
  final StudioController studio;
  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen>
    with WidgetsBindingObserver {
  int _tab = 0;
  bool _videoMode = false;
  StudioController get studio => widget.studio;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(studio.flush().then((_) => studio.saveNow()));
    }
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  void _setVideoMode(bool value) {
    if (value == _videoMode) return;
    FocusScope.of(context).unfocus();
    if (value) {
      final timeline = studio.video;
      if (timeline.motions.isEmpty) {
        // First time in video mode: the card starts with the gentle whole-card
        // slide style instead of a frozen frame.
        studio.updateVideo(
          timeline.copyWith(
            enabled: true,
            motions: MotionPreset.slide.build(
              layerIds: studio.project.layerIds.toList(),
              durationMs: timeline.durationMs,
            ),
            ambient: MotionPreset.slide.ambient,
            backdrop: MotionPreset.slide.backdrop,
          ),
        );
      } else {
        studio.updateVideo(timeline.copyWith(enabled: true));
      }
    }
    setState(() => _videoMode = value);
  }

  void _openVideoSettings() => VideoSettingsSheet.show(context, studio);

  void _export() async {
    FocusScope.of(context).unfocus();
    await studio.flush();
    if (!mounted) return;
    if (_videoMode) {
      await VideoExportDialog.show(context, studio);
      return;
    }
    if (mounted) {
      showDialog<void>(
        context: context,
        builder: (_) => ExportDialog(studio: studio),
      );
    }
  }

  Widget _panel(int index) => switch (index) {
    0 => DetailsPanel(
      studio: studio,
      onTemplates: () {
        if (MediaQuery.sizeOf(context).width < 850) {
          Navigator.pop(context);
          _showPanel(1);
        } else {
          setState(() => _tab = 1);
        }
      },
    ),
    1 => TemplatesPanel(studio: studio),
    2 => LayersPanel(studio: studio),
    _ => StylePanel(studio: studio),
  };
  void _showPanel(int index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: StudioColors.surface,
      showDragHandle: true,
      useSafeArea: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .89,
        child: AnimatedPadding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          duration: const Duration(milliseconds: 150),
          child: ListenableBuilder(
            listenable: studio,
            builder: (context, _) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 0, 12, 9),
                  child: Row(
                    children: [
                      Text(
                        [
                          'Your details',
                          'Choose a template',
                          'Canvas layers',
                          'Text & style',
                        ][index],
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Close panel',
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 19),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Expanded(child: _panel(index)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _reset() async {
    final reset = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('A fresh arrangement?'),
        content: const Text(
          'Keep your invitation details and restore this template’s original layout and styling. Custom text layers will be removed. You can undo this change.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset layout'),
          ),
        ],
      ),
    );
    if (reset == true) await studio.resetLayout();
  }

  Future<void> _rename() async {
    final text = TextEditingController(text: studio.project.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name your invitation'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Project name'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Save name'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 350), text.dispose);
    if (title != null) studio.rename(title);
  }

  Future<void> _import() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: [
          const XTypeGroup(
            label: 'Invita Studio project',
            extensions: ['json'],
            mimeTypes: ['application/json'],
            uniformTypeIdentifiers: ['public.json'],
          ),
        ],
      );
      if (file == null) return;
      if (await file.length() > StudioProject.maxProjectBytes) {
        throw const FormatException('Project must be smaller than 12 MB.');
      }
      final project = StudioProject.decode(await file.readAsString());
      await studio.openProject(project);
      _toast('Project opened. All text and layers are editable.');
    } on FormatException catch (e) {
      _toast(e.message);
    } on StateError catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast(
        'Could not open the project. Choose a valid Invita Studio JSON file.',
      );
    }
  }

  Future<void> _backup() async {
    FocusScope.of(context).unfocus();
    await studio.flush();
    final project = studio.project;
    final bytes = Uint8List.fromList(utf8.encode(project.encode()));
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Keep a little backup.'),
        content: const Text(
          'Your editable project includes every field, layer and style. Open the JSON file in Invita Studio on another device.\n\nThis is not the flattened invitation image.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                final message = await saveBytes(
                  bytes,
                  '${project.id}.invita.json',
                  'application/json',
                );
                if (context.mounted) Navigator.pop(context);
                if (message != null) _toast(message);
              } catch (_) {
                _toast('Project backup could not be saved.');
              }
            },
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: Text(kIsWeb ? 'Download project' : 'Save project'),
          ),
        ],
      ),
    );
  }

  void _about() {
    showAboutDialog(
      context: context,
      applicationName: 'Invita Studio',
      applicationVersion: '1.1 · image & video',
      applicationIcon: const BrandMark(size: 50),
      applicationLegalese: 'Built with Flutter and the BSD-3-Clause flutter_canvas_editor engine.\nOriginal invitation art. Locally bundled OFL fonts.',
      children: [
        const SizedBox(height: 16),
        const Text(
          'Your invitation stays on this device. Export a JSON project for a portable backup. Native sharing uses your device’s share sheet; availability and delivery depend on the receiving app.\n\nVideo invitations render to MP4 with the device encoder on Android and iOS; the browser and desktop builds animate the invitation but cannot encode the file.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Future<void> _chooseLanguage() async {
    final settings = AppSettingsScope.maybeOf(context);
    if (settings == null) return;
    final l10n = AppLocalizations.of(context);
    final choice = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(l10n.language),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(dialogContext).pop('system'),
            child: Row(
              children: [
                Expanded(child: Text(l10n.languageSystem)),
                if (settings.locale == null) const Icon(Icons.check, size: 18),
              ],
            ),
          ),
          for (final locale in AppLocalizations.supportedLocales)
            SimpleDialogOption(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(locale.languageCode),
              child: Row(
                children: [
                  Expanded(child: Text(_languageName(locale.languageCode))),
                  if (settings.locale?.languageCode == locale.languageCode)
                    const Icon(Icons.check, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
    if (choice == null) return;
    await settings.setLocale(
      choice == 'system' ? null : Locale(choice),
    );
  }

  static String _languageName(String code) =>
      switch (code) { 'en' => 'English', 'es' => 'Español', _ => code };

  void _drafts() {
    FocusScope.of(context).unfocus();
    showDialog<void>(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .8,
            ),
            child: ListenableBuilder(
              listenable: studio,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(25, 23, 15, 15),
                    child: Row(
                      children: [
                        const Text(
                          'Your drafts',
                          style: TextStyle(
                            fontFamily: 'CormorantGaramond',
                            fontSize: 30,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Close drafts',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 25),
                    child: Text(
                      'Saved on this device. Export a project for a portable backup.',
                      style: TextStyle(fontSize: 11, color: StudioColors.muted),
                    ),
                  ),
                  const SizedBox(height: 17),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      children: [
                        for (final draft in studio.drafts)
                          ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            leading: SizedBox(
                              width: 42,
                              height: 59,
                              child: ExcludeSemantics(
                                child: DocumentPreview(
                                  document: draft.document,
                                  decodeWidth: 180,
                                ),
                              ),
                            ),
                            title: Text(
                              draft.title,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              '${draft.document.width.toInt()} × ${draft.document.height.toInt()} · Editable project',
                              style: const TextStyle(
                                fontSize: 10,
                                color: StudioColors.muted,
                              ),
                            ),
                            trailing: draft.id == studio.project.id
                                ? const Chip(
                                    label: Text(
                                      'Open',
                                      style: TextStyle(fontSize: 9),
                                    ),
                                    side: BorderSide.none,
                                    backgroundColor: StudioColors.accentSoft,
                                  )
                                : IconButton(
                                    tooltip: 'Delete local draft',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      size: 17,
                                    ),
                                    onPressed: () async {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text(
                                            'Delete local draft?',
                                          ),
                                          content: Text(
                                            'Remove “${draft.title}” from this device? Exported files will not be deleted.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Cancel'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Delete draft'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        await studio.deleteDraft(draft.id);
                                      }
                                    },
                                  ),
                            onTap: () async {
                              await studio.openProject(draft);
                              if (context.mounted) Navigator.pop(context);
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: studio.drafts.length >= 12
                            ? null
                            : () async {
                                await studio.newProject();
                                if (context.mounted) Navigator.pop(context);
                              },
                        icon: const Icon(Icons.add, size: 17),
                        label: const Text('New invitation'),
                      ),
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

  Widget _saveStatus({bool compact = false}) {
    final failed = studio.saveState == SaveState.failed;
    final saving = studio.saveState == SaveState.saving;
    final color = failed ? StudioColors.warning : StudioColors.accent;
    return Tooltip(
      message:
          studio.storageError ??
          (saving ? 'Saving on this device…' : 'Saved locally on this device'),
      child: InkWell(
        onTap: failed ? _backup : null,
        borderRadius: BorderRadius.circular(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              failed
                  ? Icons.cloud_off_outlined
                  : saving
                  ? Icons.more_horiz
                  : Icons.cloud_done_outlined,
              size: 15,
              color: color,
            ),
            if (!compact) ...[
              const SizedBox(width: 6),
              Text(
                failed
                    ? 'Backup recommended'
                    : saving
                    ? 'Saving locally…'
                    : 'All changes saved',
                style: TextStyle(
                  fontSize: 10,
                  color: failed ? color : StudioColors.muted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(double width) {
    final mobile = width < 850;
    return Container(
      height: mobile ? 66 : 76,
      padding: EdgeInsets.symmetric(horizontal: mobile ? 16 : 27),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: StudioColors.border)),
      ),
      child: Row(
        children: [
          const BrandMark(size: 33),
          const SizedBox(width: 10),
          const Text(
            'invita',
            style: TextStyle(
              fontFamily: 'CormorantGaramond',
              fontSize: 32,
              height: 1,
              fontWeight: FontWeight.w600,
              letterSpacing: -.8,
            ),
          ),
          if (!mobile) ...[
            const SizedBox(width: 7),
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: TinyLabel('Studio'),
            ),
            Container(
              width: 1,
              height: 28,
              color: StudioColors.border,
              margin: const EdgeInsets.symmetric(horizontal: 25),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width < 1000 ? 120 : 220),
              child: InkWell(
                onTap: _rename,
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        studio.project.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    const Icon(
                      Icons.edit_outlined,
                      size: 12,
                      color: StudioColors.muted,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 20),
          ],
          const Spacer(),
          if (!mobile) ...[
            _ModeSwitch(
              videoMode: _videoMode,
              onChanged: _setVideoMode,
            ),
            const SizedBox(width: 14),
          ],
          _saveStatus(compact: width < 1180),
          SizedBox(width: mobile ? 8 : 23),
          if (mobile && width >= 380)
            IconButton(
              tooltip: 'My drafts',
              onPressed: _drafts,
              icon: const Icon(Icons.folder_open_outlined, size: 20),
            )
          else if (!mobile && width >= 1000)
            TextButton.icon(
              onPressed: _drafts,
              icon: const Icon(Icons.folder_open_outlined, size: 17),
              label: const Text('My drafts'),
            ),
          PopupMenuButton<String>(
            tooltip: 'Project options',
            icon: const Icon(Icons.more_horiz, size: 21),
            onSelected: (value) {
              switch (value) {
                case 'home':
                  Navigator.of(context).maybePop();
                case 'drafts':
                  _drafts();
                case 'event':
                  EventSettingsSheet.show(context, studio);
                case 'invite':
                  InviteActionsSheet.show(context, studio);
                case 'import':
                  _import();
                case 'backup':
                  _backup();
                case 'copy':
                  saveProjectCopy(context, studio.project);
                case 'duplicate':
                  duplicateDraft(context, studio, studio.project);
                case 'rename':
                  _rename();
                case 'language':
                  _chooseLanguage();
                case 'about':
                  _about();
                case 'reset':
                  _reset();
              }
            },
            itemBuilder: (menuContext) {
              final l10n = AppLocalizations.of(menuContext);
              return [
                const PopupMenuItem(value: 'home', child: Text('Go to home')),
                const PopupMenuItem(value: 'drafts', child: Text('My drafts')),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'event',
                  child: Text('Event settings'),
                ),
                const PopupMenuItem(
                  value: 'invite',
                  child: Text('Invitation actions'),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'import',
                  child: Text('Open project JSON'),
                ),
                const PopupMenuItem(
                  value: 'backup',
                  child: Text('Export editable project'),
                ),
                const PopupMenuItem(
                  value: 'copy',
                  child: Text('Save a copy'),
                ),
                const PopupMenuItem(
                  value: 'duplicate',
                  child: Text('Duplicate draft'),
                ),
                const PopupMenuItem(
                  value: 'rename',
                  child: Text('Rename invitation'),
                ),
                const PopupMenuItem(value: 'reset', child: Text('Reset layout')),
                const PopupMenuDivider(),
                PopupMenuItem(value: 'language', child: Text(l10n.language)),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'about',
                  child: Text('About & open-source licenses'),
                ),
              ];
            },
          ),
          SizedBox(width: mobile ? 4 : 12),
          FilledButton.icon(
            onPressed: _export,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: mobile ? 13 : 20,
                vertical: mobile ? 14 : 18,
              ),
            ),
            icon: const Icon(Icons.file_download_outlined, size: 17),
            label: Text(mobile ? 'Export' : 'Export invitation'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: studio,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth,
            mobile = width < 850,
            inspector = width >= 1220;
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
                studio.undo,
            const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
                studio.undo,
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              control: true,
              shift: true,
            ): studio.redo,
            const SingleActivator(
              LogicalKeyboardKey.keyZ,
              meta: true,
              shift: true,
            ): studio.redo,
            const SingleActivator(LogicalKeyboardKey.keyY, control: true):
                studio.redo,
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              body: SafeArea(
                child: Column(
                  children: [
                    _header(width),
                    if (mobile)
                      Container(
                        height: 51,
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        color: StudioColors.wash,
                        child: Row(
                          children: [
                            _ModeSwitch(
                              videoMode: _videoMode,
                              onChanged: _setVideoMode,
                              compact: true,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: InkWell(
                                onTap: _rename,
                                child: Text(
                                  studio.project.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const Icon(
                              Icons.edit_outlined,
                              size: 12,
                              color: StudioColors.muted,
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: Row(
                        children: [
                          if (!mobile) ...[
                            SizedBox(
                              width: 304,
                              child: Column(
                                children: [
                                  Container(
                                    height: 57,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: StudioColors.border,
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        for (var i = 0; i < 3; i++)
                                          Expanded(
                                            child: _SideTab(
                                              label: [
                                                'Details',
                                                'Templates',
                                                'Layers',
                                              ][i],
                                              icon: [
                                                Icons.tune,
                                                Icons.grid_view_outlined,
                                                Icons.layers_outlined,
                                              ][i],
                                              selected: _tab == i,
                                              onTap: () =>
                                                  setState(() => _tab = i),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Expanded(child: _panel(_tab)),
                                ],
                              ),
                            ),
                            const VerticalDivider(width: 1),
                          ],
                          Expanded(
                            child: _videoMode
                                ? VideoWorkspace(
                                    studio: studio,
                                    onOpenSettings: _openVideoSettings,
                                    onExport: _export,
                                    compact: mobile,
                                  )
                                : ArtboardWorkspace(
                                    studio: studio,
                                    onReset: _reset,
                                    onStyle: () => _showPanel(3),
                                    compact: mobile,
                                    hasInspector: inspector,
                                  ),
                          ),
                          if (inspector) ...[
                            const VerticalDivider(width: 1),
                            SizedBox(
                              width: 278,
                              child: StylePanel(studio: studio),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (studio.storageError != null && mobile)
                      Material(
                        color: StudioColors.warningSoft,
                        child: InkWell(
                          onTap: _backup,
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 8,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: StudioColors.warning,
                                ),
                                SizedBox(width: 7),
                                Expanded(
                                  child: Text(
                                    'Local storage unavailable. Tap to export a backup.',
                                    style: TextStyle(fontSize: 10),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              bottomNavigationBar: mobile
                  ? SafeArea(
                      child: Container(
                        height: 66,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            top: BorderSide(color: StudioColors.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            for (var i = 0; i < 4; i++)
                              Expanded(
                                child: InkWell(
                                  onTap: () => _showPanel(i),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        [
                                          Icons.edit_note,
                                          Icons.grid_view_outlined,
                                          Icons.layers_outlined,
                                          Icons.format_color_text,
                                        ][i],
                                        size: 20,
                                        color: StudioColors.accent,
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        [
                                          'Details',
                                          'Templates',
                                          'Layers',
                                          'Style',
                                        ][i],
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: StudioColors.ink,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        );
      },
    ),
  );
}

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.videoMode,
    required this.onChanged,
    this.compact = false,
  });

  final bool videoMode;
  final ValueChanged<bool> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: StudioColors.wash,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: StudioColors.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _segment(
          label: 'Image',
          icon: Icons.image_outlined,
          selected: !videoMode,
          onTap: () => onChanged(false),
        ),
        _segment(
          label: 'Video',
          icon: Icons.play_circle_outline,
          selected: videoMode,
          onTap: () => onChanged(true),
        ),
      ],
    ),
  );

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color: selected ? Colors.white : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: selected
            ? const [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: selected ? StudioColors.accent : StudioColors.muted,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: selected ? StudioColors.ink : StudioColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SideTab extends StatelessWidget {
  const _SideTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(6),
    child: Container(
      height: 33,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: selected ? StudioColors.accentSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 13,
            color: selected ? StudioColors.accent : StudioColors.muted,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? StudioColors.accent : StudioColors.muted,
            ),
          ),
        ],
      ),
    ),
  );
}
