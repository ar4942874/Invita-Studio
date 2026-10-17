import 'dart:convert';

import 'package:intl/intl.dart';

import '../domain/event_schedule.dart';

/// Turns the structured event into the things people actually need: readable
/// card text, a calendar file, a Google Calendar link and a validated RSVP URL.
///
/// Everything here is pure string work — no I/O, no widgets — so the formats can
/// be tested without a renderer.

/// "Saturday, 12 December 2026" in the active locale, matching the card's own
/// date style rather than the device's numeric default.
String formatEventDate(
  EventDateTime when,
  String locale, {
  bool uppercase = false,
}) {
  String text;
  try {
    text = DateFormat('EEEE, d MMMM y', locale).format(when.start);
  } catch (_) {
    // The locale's date symbols load with the app's localizations. If they are
    // not ready (a picker callback before that, or a bare unit test), a plain
    // unambiguous date beats throwing inside the UI.
    text = _fallbackDate(when.start);
  }
  return uppercase ? text.toUpperCase() : text;
}

/// "7:00 PM" in the active locale. Empty for a date-only event.
String formatEventTime(EventDateTime when, String locale) {
  if (!when.hasTime) return '';
  try {
    return DateFormat.jm(locale).format(when.start);
  } catch (_) {
    final hour = when.hour == 0 ? 12 : (when.hour! > 12 ? when.hour! - 12 : when.hour!);
    final suffix = when.hour! < 12 ? 'AM' : 'PM';
    return '$hour:${_two(when.minute!)} $suffix';
  }
}

const _monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

const _weekdayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String _fallbackDate(DateTime value) =>
    '${_weekdayNames[value.weekday - 1]}, ${value.day} '
    '${_monthNames[value.month - 1]} ${value.year}';

String _two(int value) => value.toString().padLeft(2, '0');

/// A valid RSVP destination: absolute http(s) URL with a host.
bool isValidRsvpUrl(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.length > 300) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  return uri.host.isNotEmpty;
}

/// A calendar file for the event, as RFC 5545 text.
///
/// The event is floating local time (no `TZID`), which matches what the picker
/// captured: the wall-clock time the host typed, not an instant in a zone.
String buildIcs({
  required String uid,
  required String title,
  required EventDateTime when,
  String description = '',
  String location = '',
  int durationMinutes = 120,
  DateTime? stamp,
}) {
  final start = when.start;
  final end = when.hasTime
      ? start.add(Duration(minutes: durationMinutes))
      : start.add(const Duration(days: 1));
  final stampText = _stamp(stamp ?? DateTime.now());

  String day(DateTime value) => _day(value);
  String instant(DateTime value) => _instant(value);

  final lines = <String>[
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Invita Studio//Invitation//EN',
    'CALSCALE:GREGORIAN',
    'METHOD:PUBLISH',
    'BEGIN:VEVENT',
    'UID:${_icsUid(uid)}',
    'DTSTAMP:$stampText',
    if (when.hasTime) ...[
      'DTSTART:${instant(start)}',
      'DTEND:${instant(end)}',
    ] else ...[
      'DTSTART;VALUE=DATE:${day(start)}',
      'DTEND;VALUE=DATE:${day(end)}',
    ],
    'SUMMARY:${_icsText(title)}',
    if (description.trim().isNotEmpty)
      'DESCRIPTION:${_icsText(description)}',
    if (location.trim().isNotEmpty) 'LOCATION:${_icsText(location)}',
    'END:VEVENT',
    'END:VCALENDAR',
  ];
  // RFC 5545 wants CRLF and lines of at most 75 octets.
  return '${lines.map(_fold).join('\r\n')}\r\n';
}

/// A "add to Google Calendar" template link, with the same event details.
String googleCalendarUrl({
  required String title,
  required EventDateTime when,
  String description = '',
  String location = '',
  int durationMinutes = 120,
}) {
  final start = when.start;
  final end = when.hasTime
      ? start.add(Duration(minutes: durationMinutes))
      : start.add(const Duration(days: 1));
  String day(DateTime value) => _day(value);
  String instant(DateTime value) => _instant(value);
  final dates = when.hasTime
      ? '${instant(start)}/${instant(end)}'
      : '${day(start)}/${day(end)}';
  return Uri.https('calendar.google.com', '/calendar/render', {
    'action': 'TEMPLATE',
    'text': title,
    'dates': dates,
    if (description.trim().isNotEmpty) 'details': description,
    if (location.trim().isNotEmpty) 'location': location,
  }).toString();
}

/// `20261212` — RFC 5545 DATE.
String _day(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}${_two(value.month)}'
    '${_two(value.day)}';

/// `20261212T190000` — RFC 5545 local DATE-TIME.
String _instant(DateTime value) =>
    '${_day(value)}T${_two(value.hour)}${_two(value.minute)}'
    '${_two(value.second)}';

/// `20261017T093000Z` — RFC 5545 UTC timestamp.
String _stamp(DateTime value) => '${_instant(value.toUtc())}Z';

/// Escapes the four characters RFC 5545 reserves inside a text value.
String _icsText(String value) => value
    .replaceAll('\\', '\\\\')
    .replaceAll(';', '\\;')
    .replaceAll(',', '\\,')
    .replaceAll('\r\n', '\\n')
    .replaceAll('\n', '\\n');

/// Calendar UIDs must be stable per project and safe in a header.
String _icsUid(String projectId) {
  final safe = projectId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '-');
  return '$safe@invita.studio';
}

/// Folds a content line at 75 octets, continuation lines starting with a space.
///
/// Octets, not characters: an Urdu or Arabic summary is multi-byte, and a
/// character-counted fold would produce lines a strict parser rejects.
String _fold(String line) {
  const maxOctets = 75;
  if (utf8.encode(line).length <= maxOctets) return line;
  final parts = <String>[];
  var current = StringBuffer();
  var octets = 0;
  var first = true;
  for (final rune in line.runes) {
    final character = String.fromCharCode(rune);
    final size = utf8.encode(character).length;
    final limit = first ? maxOctets : maxOctets - 1;
    if (octets + size > limit && current.isNotEmpty) {
      parts.add((first ? '' : ' ') + current.toString());
      current = StringBuffer();
      octets = 0;
      first = false;
    }
    current.write(character);
    octets += size;
  }
  parts.add((first ? '' : ' ') + current.toString());
  return parts.join('\r\n');
}
