import 'package:flutter/material.dart';

import '../application/studio_controller.dart';
import '../domain/event_schedule.dart';
import '../services/invite_actions.dart';

/// Opens the date picker, then writes *both* halves of the event: the
/// structured value (for calendar files and codes) and the card text (localized
/// and formatted, still editable by hand).
Future<EventDateTime?> pickEventDate(
  BuildContext context,
  StudioController studio,
) async {
  final current = studio.project.when;
  final initial =
      current?.start ?? DateTime.now().add(const Duration(days: 30));
  final picked = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(1900),
    lastDate: DateTime(2100),
    helpText: 'Invitation date',
  );
  if (picked == null) return null;
  final next = current == null
      ? EventDateTime.fromDateTime(picked, includeTime: false)
      : current.copyWith(date: EventDateTime.fromDateTime(picked).date);
  await studio.setSchedule(next);
  if (!context.mounted) return next;
  await studio.setField(
    'date',
    formatEventDate(
      next,
      Localizations.localeOf(context).languageCode,
      uppercase: true,
    ),
  );
  return next;
}

/// Opens the time picker. Requires a date first: a time alone cannot produce a
/// calendar entry, and silently inventing a date would be worse than asking.
Future<EventDateTime?> pickEventTime(
  BuildContext context,
  StudioController studio,
) async {
  final current = studio.project.when;
  if (current == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Pick the date first, then the time.')),
    );
    return null;
  }
  final picked = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(current.start),
    helpText: 'Invitation time',
  );
  if (picked == null) return null;
  final next = current.copyWith(hour: picked.hour, minute: picked.minute);
  await studio.setSchedule(next);
  if (!context.mounted) return next;
  await studio.setField(
    'time',
    formatEventTime(next, Localizations.localeOf(context).languageCode),
  );
  return next;
}
