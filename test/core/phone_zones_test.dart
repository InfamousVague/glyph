import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/support/time_zones.dart';
import 'package:ghost_md/core/blanks.dart';
import 'package:ghost_md/core/fill_facts.dart';
import 'package:ghost_md/core/phone_zones.dart';

/// A blank that asks the time somewhere (docs/PARITY.md, Differs 27). Ghost.md's solver takes the phone's own
/// zone and every zone's offset from `Intl` (core/fillFacts.ts: `clock.zone ??
/// Intl.DateTimeFormat().resolvedOptions().timeZone`, and `offsetMinutes` by `timeZoneName: 'shortOffset'`), so
/// its sentence names your city and its summer time is the phone's own rules. This app said "here" and read a
/// table that stopped at 2040; it asks the phone for both now (lib/core/phone_zones.dart).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/zones');
  final asked = <MethodCall>[];

  /// A phone in New York whose database says: New York is four hours behind UTC until the first of November 2026,
  /// then five; Tokyo is nine ahead; and, past the table's last year, London still keeps summer time.
  int minute(DateTime at) => at.millisecondsSinceEpoch ~/ 60000;
  void phone({String zone = 'America/New_York'}) => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
        asked.add(call);
        if (call.method == 'zone') return zone;
        if (call.method == 'offsets') {
          final from = (call.arguments as Map)['from'] as int;
          return <String, List<int>>{
            'America/New_York': [-240, minute(DateTime.utc(2026, 11, 1, 6)), -300],
            'Asia/Tokyo': [540],
            'Europe/London': [0, minute(DateTime.utc(2045, 3, 26, 1)), 60, minute(DateTime.utc(2045, 10, 29, 1)), 0],
            'Antarctica/Troll': [from < 0 ? 0 : 120],
          };
        }
        return null;
      });

  setUp(asked.clear);
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
    deviceZone = null;
    deviceOffsets = null;
  });

  WorkedAnswer time(String text, DateTime now) => workOut(blanksIn(text).last, text, FactClock(now: now))! as WorkedAnswer;
  const tokyo = 'What time is it in Tokyo now? {?}';
  final october = DateTime.utc(2026, 10, 9, 14, 5);

  test('with nothing from the phone the sentence says "here", as it did', () {
    expect(time(tokyo, october).working, matches(RegExp(r'^Tokyo (is .* (ahead of|behind)|keeps the same time as) here today\. It changes each minute\.$')));
  });

  test('the phone is asked for its zone and for every zone a city is in, with its own, from last year for forty years', () async {
    phone();
    await usePhoneZones(channel: channel, now: october);
    expect(asked.map((call) => call.method), ['zone', 'offsets']);
    final args = (asked.last.arguments as Map).cast<String, Object?>();
    expect((args['zones']! as List).toSet(), {...cityZones.values, 'America/New_York'});
    expect(args['from'], minute(DateTime.utc(2025)));
    expect(args['to'], minute(DateTime.utc(2066)));
    expect(deviceZone, 'America/New_York');
  });

  test('the time in a city is said against your own city, by the phone\'s own clocks', () async {
    phone();
    await usePhoneZones(channel: channel, now: october);
    final found = time(tokyo, october);
    expect(found.answer, '23:05 Friday');
    expect(found.working, 'Tokyo is 13 hours ahead of New York today. It changes each minute.');
    // After the phone's own change of clocks, an hour more.
    expect(time(tokyo, DateTime.utc(2026, 11, 2, 14, 5)).working, 'Tokyo is 14 hours ahead of New York today. It changes each minute.');
  });

  test('a phone somewhere that is no city of the solver\'s is still "here", with its own offset', () async {
    phone(zone: 'Antarctica/Troll');
    await usePhoneZones(channel: channel, now: october);
    expect(time(tokyo, october).working, 'Tokyo is 7 hours ahead of here today. It changes each minute.');
  });

  test('past the table\'s last year the phone\'s own rules still give summer time', () async {
    final summer = DateTime.utc(2045, 7, 1, 12);
    expect(offsetMinutes('Europe/London', summer), 0, reason: 'the table stops at the offset 2040 ended with');
    phone();
    await usePhoneZones(channel: channel, now: DateTime.utc(2045, 1, 2));
    expect(offsetMinutes('Europe/London', summer), 60);
    expect(offsetMinutes('Europe/London', DateTime.utc(2045, 12, 1)), 0);
    // A moment the phone was not asked about, and a zone it did not answer for, are the table's.
    expect(offsetMinutes('Europe/London', DateTime.utc(2010, 7, 1)), 60);
    expect(offsetMinutes('Asia/Kolkata', summer), 330);
    expect(knowsZone('Antarctica/Troll', summer), isTrue);
    expect(knowsZone('Mars/Olympus', summer), isFalse);
  });

  test('a phone that does not answer leaves the solver as it was', () async {
    await usePhoneZones(channel: channel, now: october);
    expect(deviceZone, isNull);
    expect(deviceOffsets, isNull);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async => throw PlatformException(code: 'dates'));
    await usePhoneZones(channel: channel, now: october);
    expect(deviceZone, isNull);
  });

  test('offsetsFrom reads a zone\'s changes as the table is read', () {
    final read = offsetsFrom({'X/Y': [60, 100, 120, 200, 60]}, from: 0, to: 300);
    DateTime at(int minutes) => DateTime.fromMillisecondsSinceEpoch(minutes * 60000, isUtc: true);
    expect([for (final m in [0, 99, 100, 199, 200, 299]) read('X/Y', at(m))], [60, 60, 120, 120, 60, 60]);
    expect(read('X/Y', at(300)), isNull, reason: 'past what was asked for');
    expect(read('X/Y', at(-1)), isNull);
    expect(read('A/B', at(10)), isNull);
  });
}
