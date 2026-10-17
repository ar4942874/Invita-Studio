/// The machine-readable half of the `date` and `time` fields.
///
/// The card keeps free text — people write "Reception at 7:00 in the evening",
/// and that must stay editable. This model stores the *same* event as structured
/// data, so the app can also produce a calendar file, a Google Calendar link and
/// an RSVP code without guessing at prose.
///
/// Times are floating (no time zone): the picker reads the device's local clock
/// and the calendar entries say "19:00 wherever you are". That is the honest
/// behaviour without a time-zone database, and it keeps a wedding invitation
/// readable for a guest in another country.
class EventDateTime {
  const EventDateTime({required this.date, this.hour, this.minute});

  /// Calendar date as `YYYY-MM-DD`.
  final String date;

  /// 0–23, or `null` for a date-only event.
  final int? hour;

  /// 0–59, or `null` for a date-only event.
  final int? minute;

  static final RegExp _datePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  bool get hasTime => hour != null && minute != null;

  /// Start instant in local time. A date-only event starts at 09:00 so a
  /// calendar entry lands on the right day rather than at midnight.
  DateTime get start {
    final parts = date.split('-').map(int.parse).toList();
    return DateTime(parts[0], parts[1], parts[2], hour ?? 9, minute ?? 0);
  }

  DateTime get end => start.add(const Duration(hours: 2));

  /// `2026-12-12T19:00` for a timed event, `2026-12-12` otherwise.
  String get isoString =>
      hasTime ? '${date}T${_two(hour!)}:${_two(minute!)}' : date;

  static String _two(int value) => value.toString().padLeft(2, '0');

  EventDateTime copyWith({String? date, int? hour, int? minute}) =>
      EventDateTime(
        date: date ?? this.date,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
      );

  /// Drops the time and keeps the date.
  EventDateTime asDateOnly() => EventDateTime(date: date);

  Map<String, dynamic> toJson() => {
    'date': date,
    if (hasTime) 'hour': hour,
    if (hasTime) 'minute': minute,
  };

  /// Strict decode: a malformed value is a damaged project, not something to
  /// silently drop.
  static EventDateTime decode(Object? raw) {
    if (raw is! Map) {
      throw const FormatException('The event date must be an object.');
    }
    final date = raw['date'];
    if (date is! String || !isValidDate(date)) {
      throw const FormatException('The event date is not a valid date.');
    }
    final hour = raw['hour'];
    final minute = raw['minute'];
    if (hour == null && minute == null) return EventDateTime(date: date);
    if (hour is! int ||
        minute is! int ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59) {
      throw const FormatException('The event time is out of range.');
    }
    return EventDateTime(date: date, hour: hour, minute: minute);
  }

  /// True for a real calendar date inside the supported range.
  static bool isValidDate(String value) {
    if (!_datePattern.hasMatch(value)) return false;
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return false;
    if (parsed.year < 1900 || parsed.year > 2100) return false;
    // Reject impossible dates such as 2026-02-31, which DateTime rolls over.
    return parsed.year == int.parse(value.substring(0, 4)) &&
        parsed.month == int.parse(value.substring(5, 7)) &&
        parsed.day == int.parse(value.substring(8, 10));
  }

  /// Builds the value a picker produced.
  static EventDateTime fromDateTime(DateTime value, {bool includeTime = true}) =>
      EventDateTime(
        date:
            '${value.year.toString().padLeft(4, '0')}-'
            '${_two(value.month)}-${_two(value.day)}',
        hour: includeTime ? value.hour : null,
        minute: includeTime ? value.minute : null,
      );

  @override
  bool operator ==(Object other) =>
      other is EventDateTime &&
      other.date == date &&
      other.hour == hour &&
      other.minute == minute;

  @override
  int get hashCode => Object.hash(date, hour, minute);

  @override
  String toString() => isoString;
}
