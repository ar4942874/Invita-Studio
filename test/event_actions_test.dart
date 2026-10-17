import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:invitation_studio/domain/event_schedule.dart';
import 'package:invitation_studio/domain/relative_time.dart';
import 'package:invitation_studio/services/invite_actions.dart';

const _when = EventDateTime(date: '2026-12-12', hour: 19, minute: 0);
const _dateOnly = EventDateTime(date: '2026-12-12');

void main() {
  group('structured event date', () {
    test('round-trips a timed event', () {
      final decoded = EventDateTime.decode(_when.toJson());
      expect(decoded, _when);
      expect(decoded.hasTime, isTrue);
      expect(decoded.isoString, '2026-12-12T19:00');
    });

    test('round-trips a date-only event without inventing a time', () {
      final decoded = EventDateTime.decode(_dateOnly.toJson());
      expect(decoded.hasTime, isFalse);
      expect(decoded.toJson(), {'date': '2026-12-12'});
      expect(decoded.isoString, '2026-12-12');
      // Calendars still need an instant: 09:00 local, not midnight.
      expect(decoded.start.hour, 9);
    });

    test('rejects impossible dates and out-of-range times', () {
      expect(EventDateTime.isValidDate('2026-02-31'), isFalse);
      expect(EventDateTime.isValidDate('12/12/2026'), isFalse);
      expect(EventDateTime.isValidDate('1899-12-12'), isFalse);
      expect(EventDateTime.isValidDate('2026-12-12'), isTrue);

      expect(
        () => EventDateTime.decode({'date': '2026-02-31'}),
        throwsFormatException,
      );
      expect(
        () => EventDateTime.decode({'date': '2026-12-12', 'hour': 24, 'minute': 0}),
        throwsFormatException,
      );
      expect(
        () => EventDateTime.decode({'date': '2026-12-12', 'hour': 19}),
        throwsFormatException,
        reason: 'an hour without minutes is ambiguous',
      );
      expect(
        () => EventDateTime.decode({'date': 20261212}),
        throwsFormatException,
      );
    });

    test('builds from a picked DateTime', () {
      final value = DateTime(2026, 3, 4, 7, 5);
      final event = EventDateTime.fromDateTime(value);
      expect(event.date, '2026-03-04');
      expect(event.hour, 7);
      expect(event.minute, 5);
      expect(EventDateTime.fromDateTime(value, includeTime: false).hasTime, isFalse);
    });
  });

  group('calendar file', () {
    test('writes a VEVENT with escaped text and CRLF endings', () {
      final ics = buildIcs(
        uid: 'p_123',
        title: 'Ayesha & Hamza, Wedding',
        when: _when,
        description: 'Line one\nLine two',
        location: 'The Royal Orchard, Bahawalpur',
        stamp: DateTime.utc(2026, 10, 17, 9, 30),
      );
      expect(ics.startsWith('BEGIN:VCALENDAR\r\n'), isTrue);
      expect(ics.endsWith('\r\n'), isTrue);
      expect(ics, contains('UID:p_123@invita.studio'));
      expect(ics, contains('DTSTAMP:20261017T093000Z'));
      expect(ics, contains('DTSTART:20261212T190000'));
      expect(ics, contains('DTEND:20261212T210000'));
      expect(ics, contains('SUMMARY:Ayesha & Hamza\\, Wedding'));
      expect(ics, contains('LOCATION:The Royal Orchard\\, Bahawalpur'));
      expect(ics, contains('DESCRIPTION:Line one\\nLine two'));
      // No bare LF: a strict parser rejects it.
      expect(ics.replaceAll('\r\n', ''), isNot(contains('\n')));
    });

    test('date-only events become all-day entries', () {
      final ics = buildIcs(uid: 'p', title: 'Party', when: _dateOnly);
      expect(ics, contains('DTSTART;VALUE=DATE:20261212'));
      expect(ics, contains('DTEND;VALUE=DATE:20261213'));
    });

    test('folds long lines at 75 octets', () {
      final ics = buildIcs(uid: 'p', title: 'x' * 200, when: _when);
      final lines = ics.split('\r\n');
      for (final line in lines) {
        expect(
          line.length,
          lessThanOrEqualTo(75),
          reason: 'line too long: ${line.length} chars',
        );
      }
      expect(ics, contains('\r\n '), reason: 'continuation lines need a space');
      // Unfolding restores the original title.
      expect(ics.replaceAll('\r\n ', ''), contains('SUMMARY:${'x' * 200}'));
    });

    test('keeps non-ASCII summaries inside the octet budget', () {
      final ics = buildIcs(
        uid: 'p',
        title: 'شمیرہ کی شادی کی تقریب — دعوت نامہ',
        when: _when,
      );
      for (final line in ics.split('\r\n')) {
        expect(
          utf8.encode(line).length,
          lessThanOrEqualTo(75),
          reason: 'a multi-byte line exceeded the octet limit',
        );
      }
      expect(ics, contains('SUMMARY:'));
    });
  });

  group('google calendar link', () {
    test('encodes the event for a template link', () {
      final url = googleCalendarUrl(
        title: 'Ayesha & Hamza',
        when: _when,
        location: 'Bahawalpur',
      );
      final uri = Uri.parse(url);
      expect(uri.host, 'calendar.google.com');
      expect(uri.queryParameters['action'], 'TEMPLATE');
      expect(uri.queryParameters['dates'], '20261212T190000/20261212T210000');
      expect(uri.queryParameters['text'], 'Ayesha & Hamza');
      expect(uri.queryParameters['location'], 'Bahawalpur');
    });

    test('spans one day for a date-only event', () {
      final uri = Uri.parse(
        googleCalendarUrl(title: 'Party', when: _dateOnly),
      );
      expect(uri.queryParameters['dates'], '20261212/20261213');
    });
  });

  group('rsvp link', () {
    test('accepts absolute http(s) links only', () {
      expect(isValidRsvpUrl('https://rsvp.example.com/a&b'), isTrue);
      expect(isValidRsvpUrl('http://rsvp.example.com'), isTrue);
      expect(isValidRsvpUrl('rsvp.example.com'), isFalse);
      expect(isValidRsvpUrl('javascript:alert(1)'), isFalse);
      expect(isValidRsvpUrl('https://'), isFalse);
      expect(isValidRsvpUrl('  '), isFalse);
      expect(isValidRsvpUrl('https://x.com/${'a' * 300}'), isFalse);
    });
  });

  group('relative time', () {
    final now = DateTime(2026, 10, 17, 12, 0);
    test('reads like a person wrote it', () {
      expect(relativeTimeLabel(now, now: now), 'just now');
      expect(
        relativeTimeLabel(now.subtract(const Duration(minutes: 5)), now: now),
        '5 min ago',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(hours: 2)), now: now),
        '2 h ago',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 1)), now: now),
        'yesterday',
      );
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 3)), now: now),
        '3 d ago',
      );
    });

    test('stops at a week so the caller can show a date', () {
      expect(
        relativeTimeLabel(now.subtract(const Duration(days: 9)), now: now),
        isNull,
      );
    });

    test('a clock that moved backwards does not read as negative', () {
      expect(
        relativeTimeLabel(now.add(const Duration(hours: 3)), now: now),
        'just now',
      );
    });
  });
}
