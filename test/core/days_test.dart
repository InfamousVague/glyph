import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/days.dart';

/// A day is the person's own, by the device's clock (lib/core/days.dart), case for case with the web's
/// `core/days.test.ts`.
///
/// What differs: the web moves `process.env.TZ` for three cases (New York, London, Los Angeles). A Dart test cannot
/// move its zone, so those cases are written to hold in whatever zone they run in: each makes its moment from local
/// fields, which is the claim (the day is the device's, never UTC's), and the UTC half of the New York case is
/// asserted only where the zone is west of Greenwich. Run them under `TZ=America/New_York` to see it bite.
void main() {
  group('a day from a moment', () {
    test('is the day on the device’s calendar, late or early', () {
      expect(isoDay(DateTime(2026, 10, 3, 23, 59)), '2026-10-03');
      expect(isoDay(DateTime(2026, 10, 3, 0, 1)), '2026-10-03');
      expect(isoDay(DateTime(2026, 1, 1, 12)), '2026-01-01');
    });

    test('is never the day in UTC: 23:30 on the 3rd is the 3rd, whatever UTC calls it', () {
      final evening = DateTime(2026, 10, 3, 23, 30);
      expect(isoDay(evening), '2026-10-03');
      // The same instant held as a UTC moment is still read by the device's clock, as a JavaScript Date is.
      expect(isoDay(evening.toUtc()), '2026-10-03');
      if (evening.timeZoneOffset.isNegative) {
        expect(evening.toUtc().toIso8601String().substring(0, 10), '2026-10-04');
      }
      final early = DateTime(2026, 10, 3, 0, 30);
      expect(isoDay(early.toUtc()), '2026-10-03');
    });
  });

  group('a written day', () {
    test('is four figures, two and two, on the calendar', () {
      for (final day in ['2026-10-03', '2028-02-29', '2026-12-31', '0099-01-01']) {
        expect(isIsoDay(day), isTrue, reason: day);
      }
    });

    test('is not a day the calendar has not got, another form, or a day with words round it', () {
      for (final text in ['2026-02-29', '2026-02-30', '2026-13-01', '2026-00-10', '2026-10-00', '2026-10-3', '26-10-03', '2026/10/03', '3 Oct', '', ' 2026-10-03', '2026-10-03T12:00']) {
        expect(isIsoDay(text), isFalse, reason: text);
      }
    });
  });

  group('a day some days on', () {
    test('counts on and back by the calendar, over months, years and a leap day', () {
      expect(isoDayAfter('2026-10-03', 7), '2026-10-10');
      expect(isoDayAfter('2026-10-03', 0), '2026-10-03');
      expect(isoDayAfter('2026-10-03', -3), '2026-09-30');
      expect(isoDayAfter('2026-12-31', 1), '2027-01-01');
      expect(isoDayAfter('2028-02-28', 1), '2028-02-29');
      expect(isoDayAfter('2027-02-28', 1), '2027-03-01');
      expect(isoDayAfter('2026-10-03', 365), '2027-10-03');
    });

    test('counts whole days, from a moment by its day on the device’s clock', () {
      expect(isoDayAfterDate(DateTime(2026, 10, 3, 23, 30), 1), '2026-10-04');
      expect(isoDayAfter('2026-10-03', 1.9), '2026-10-04');
    });

    test('is the next Saturday a week on from the Saturday before the clocks go back', () {
      expect(isoDayAfterDate(DateTime(2026, 10, 24, 23, 30), 7), '2026-10-31');
      expect(isoDayAfter('2026-10-24', 7), '2026-10-31');
      // And over the weeks the clocks change in America and in spring, whichever zone this runs in.
      expect(isoDayAfterDate(DateTime(2026, 10, 31, 23, 30), 7), '2026-11-07');
      expect(isoDayAfterDate(DateTime(2026, 3, 7, 23, 30), 7), '2026-03-14');
      expect(isoDayAfterDate(DateTime(2026, 3, 28, 0, 30), 7), '2026-04-04');
    });

    test('is nothing from words that are not a day', () {
      expect(isoDayAfter('Friday', 1), isNull);
      expect(isoDayAfter('2026-02-30', 1), isNull);
    });
  });

  group('days between two days', () {
    test('are whole days, later minus earlier', () {
      expect(daysBetween('2026-10-03', '2026-10-10'), 7);
      expect(daysBetween('2026-10-10', '2026-10-03'), -7);
      expect(daysBetween('2026-10-03', '2026-10-03'), 0);
      expect(daysBetween('2026-12-31', '2027-01-01'), 1);
      expect(daysBetween('2026-03-28', '2026-03-30'), 2);
    });

    test('are nothing where either is not a day', () {
      expect(daysBetween('2026-10-03', 'Friday'), isNull);
      expect(daysBetween('', '2026-10-03'), isNull);
    });
  });

  group('a written day as a moment', () {
    test('is noon that day on the device’s clock, for a calendar to place and to name', () {
      final at = dateOfDay('2026-10-03')!;
      expect([at.year, at.month, at.day, at.hour], [2026, 10, 3, 12]);
      expect(at.isUtc, isFalse);
      expect(isoDay(at), '2026-10-03');
      // Saturday: JavaScript's getDay() 6 is Dart's weekday 6 too (Sunday is 0 there and 7 here).
      expect(at.weekday, DateTime.saturday);
    });

    test('is the same day wherever the device is, and nothing for words that are not a day', () {
      expect(isoDay(dateOfDay('2026-10-03')!), '2026-10-03');
      expect(isoDay(dateOfDay('2026-03-08')!), '2026-03-08');
      expect(isoDay(dateOfDay('2026-10-25')!), '2026-10-25');
      expect(dateOfDay('2026-02-30'), isNull);
    });
  });
}
