import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/studio_controller.dart';
import '../domain/invitation_template.dart';
import '../domain/project.dart';
import '../services/file_actions.dart';
import '../services/invite_actions.dart';
import 'project_actions.dart';
import 'schedule_picker.dart';
import 'studio_theme.dart';
import 'widgets/qr_code.dart';

/// The actions that turn a pretty card into an invitation people can act on:
/// a calendar file, a Google Calendar link and a scannable RSVP code.
///
/// Everything is generated on the device from the structured date/time; nothing
/// is uploaded and no backend is involved.
class InviteActionsSheet extends StatefulWidget {
  const InviteActionsSheet({super.key, required this.studio});

  final StudioController studio;

  static Future<void> show(BuildContext context, StudioController studio) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        showDragHandle: true,
        useSafeArea: true,
        builder: (_) => InviteActionsSheet(studio: studio),
      );

  @override
  State<InviteActionsSheet> createState() => _InviteActionsSheetState();
}

class _InviteActionsSheetState extends State<InviteActionsSheet> {
  late final TextEditingController _url = TextEditingController(
    text: widget.studio.project.rsvpUrl ?? '',
  );
  String? _urlError;
  bool _busy = false;

  StudioController get _studio => widget.studio;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _locale => Localizations.localeOf(context).languageCode;

  String _description(StudioProject project) {
    final fields = fieldsFor(project.document);
    return [
      if ((fields['message'] ?? '').trim().isNotEmpty) fields['message']!.trim(),
      if ((fields['rsvp'] ?? '').trim().isNotEmpty) fields['rsvp']!.trim(),
    ].join('\n');
  }

  String _location(StudioProject project) {
    final fields = fieldsFor(project.document);
    return [fields['venue'], fields['address']]
        .map((value) => value?.trim() ?? '')
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  Future<void> _saveIcs() async {
    final project = _studio.project;
    final when = project.when;
    if (when == null || _busy) return;
    setState(() => _busy = true);
    final name = '${fileStem(project.title)}.ics';
    try {
      final ics = buildIcs(
        uid: project.id,
        title: project.title,
        when: when,
        description: _description(project),
        location: _location(project),
      );
      final bytes = utf8.encode(ics);
      // On a phone the point is to reach a calendar app, and only the share
      // sheet can do that — a file written into app documents cannot be opened
      // from there. Everywhere else (or when sharing is unavailable) fall back
      // to a real save/download.
      try {
        await SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(bytes, mimeType: 'text/calendar', name: name),
            ],
            fileNameOverrides: [name],
            subject: project.title,
          ),
        );
        _toast('Calendar file shared.');
        return;
      } catch (_) {
        // Fall through to saving.
      }
      final message = await saveBytes(bytes, name, 'text/calendar');
      if (message != null) _toast(message);
    } catch (_) {
      _toast('The calendar file could not be saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openCalendar() async {
    final project = _studio.project;
    final when = project.when;
    if (when == null) return;
    final url = googleCalendarUrl(
      title: project.title,
      when: when,
      description: _description(project),
      location: _location(project),
    );
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!opened) throw StateError('No calendar app answered.');
    } catch (_) {
      // No browser or handler: the link is still useful, so hand it over.
      await Clipboard.setData(ClipboardData(text: url));
      _toast('Calendar link copied to the clipboard.');
    }
  }

  Future<void> _saveUrl() async {
    final value = _url.text.trim();
    if (value.isNotEmpty && !isValidRsvpUrl(value)) {
      setState(() => _urlError = 'Use a full link starting with https://');
      return;
    }
    await _studio.setRsvpUrl(value.isEmpty ? null : value);
    if (!mounted) return;
    setState(() => _urlError = null);
    _toast(value.isEmpty ? 'RSVP link removed.' : 'RSVP link saved.');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _studio,
    builder: (context, _) {
      final project = _studio.project;
      final when = project.when;
      return ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Invitation actions',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              const Text(
                'Calendar entries and an RSVP code, generated on this device.',
                style: TextStyle(fontSize: 11, color: StudioColors.muted),
              ),
              const SizedBox(height: 18),
              _section('WHEN'),
              if (when == null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'The card has no date yet. Pick one to create calendar '
                      'entries — your typed date and time are not changed '
                      'unless you accept the picker.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.45,
                        color: StudioColors.muted,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => pickEventDate(context, _studio),
                      icon: const Icon(Icons.calendar_month_outlined, size: 16),
                      label: const Text('Pick a date'),
                    ),
                  ],
                )
              else ...[
                Row(
                  children: [
                    const Icon(
                      Icons.event_outlined,
                      size: 15,
                      color: StudioColors.accent,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${formatEventDate(when, _locale)}'
                        '${when.hasTime ? ' · ${formatEventTime(when, _locale)}' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    TextButton(
                      onPressed: () => pickEventDate(context, _studio),
                      child: const Text(
                        'Change',
                        style: TextStyle(fontSize: 10.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : _saveIcs,
                      icon: const Icon(Icons.file_download_outlined, size: 16),
                      label: const Text(
                        'Save .ics',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _openCalendar,
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text(
                        'Google Calendar',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              _section('RSVP CODE'),
              const Text(
                'Paste the page your guests should open. The code is drawn on '
                'this device and can be added to a printed card.',
                style: TextStyle(
                  fontSize: 10.5,
                  height: 1.45,
                  color: StudioColors.muted,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('rsvp_url'),
                controller: _url,
                keyboardType: TextInputType.url,
                style: const TextStyle(fontSize: 12),
                onChanged: (_) => setState(() => _urlError = null),
                decoration: InputDecoration(
                  labelText: 'RSVP link',
                  hintText: 'https://your-rsvp-page.com',
                  errorText: _urlError,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: _busy ? null : _saveUrl,
                    child: const Text('Save link', style: TextStyle(fontSize: 11.5)),
                  ),
                  const SizedBox(width: 10),
                  if (_url.text.trim().isNotEmpty && isValidRsvpUrl(_url.text))
                    TextButton(
                      onPressed: () => Clipboard.setData(
                        ClipboardData(text: _url.text.trim()),
                      ),
                      child: const Text(
                        'Copy link',
                        style: TextStyle(fontSize: 11.5),
                      ),
                    ),
                ],
              ),
              if (isValidRsvpUrl(_url.text)) ...[
                const SizedBox(height: 14),
                Center(
                  child: QrCodeView(
                    data: _url.text.trim(),
                    size: 150,
                  ),
                ),
                const SizedBox(height: 6),
                const Center(
                  child: Text(
                    'Scanning opens your RSVP page.',
                    style: TextStyle(fontSize: 9.5, color: StudioColors.muted),
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  Widget _section(String label) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.1,
        color: StudioColors.muted,
      ),
    ),
  );
}
