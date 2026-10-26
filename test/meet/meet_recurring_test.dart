// Recurring meetings and the history in pages on Settings › Meetings (lib/meet/ui/meet_card.dart, lib/meet/meet_in.dart;
// Matt, 2026-10-24: "show recurring meetings in the meetings UI and paginate the meeting history"): a Recurring card
// with each series' rule and next, "Stop joining" asked first; nothing of it against a service from before series; the
// meetings to come, then those over by day, twenty at first and "Show more" below them, which loads in place, says a
// failure with Retry, and keeps what it loaded when the list is read again; an occurrence's own Don't join as it was;
// the same in Simple; and the repeat mark on home's Upcoming meetings.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/meet/meet_api.dart';
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/meet/ui/meet_card.dart';
import 'package:ghost_md/plugins/meetings/meetings.dart';

import '../account_ui/support.dart';
import 'support.dart';

/// Saturday 24 October 2026, 9:00 here.
final int at = DateTime(2026, 10, 24, 9, 0).millisecondsSinceEpoch;
const int hour = 3600000;

/// This device's offset from UTC at [ms], in minutes: a series on the same clock names no zone.
int here(int ms) => DateTime.fromMillisecondsSinceEpoch(ms).timeZoneOffset.inMinutes;

Map<String, Object?> meeting(String id, String? title, String state, int startsAt, {String? series}) =>
    {'id': id, 'title': title, 'url': null, 'startsAt': startsAt, 'endsAt': startsAt + hour, 'state': state, 'detail': null, 'series': ?series};

/// Engineering Standup, every weekday at 9:30 here, its next on Monday 26 October.
Map<String, Object?> standup({String nextState = 'booked', bool joins = true, int? offset}) {
  final next = DateTime(2026, 10, 26, 9, 30).millisecondsSinceEpoch;
  return {
    'id': 'stand',
    'title': 'Engineering Standup',
    'rule': 'Every weekday at 9:30',
    'time': '09:30',
    'zone': 'America/New_York',
    'offset': offset ?? here(next),
    'next': {'id': 'occ', 'startsAt': next, 'endsAt': next + hour ~/ 4, 'state': nextState, 'joins': joins},
    'until': null,
    'count': null,
  };
}

/// A device with Ghost in meetings at [at], over a service that pages and lists series unless [old]; [gate], while
/// it is not complete, holds every page after the first.
Future<({Device device, FakeMeet meet})> made({bool old = false, Completer<void>? Function()? gate}) async {
  final meet = FakeMeet(now: () => at)..paging = !old;
  final service = await FakeService.start(seed: seeded);
  final over = meet.over(service.fetcher);
  final device = await Device.make(
    service: service,
    publishing: true,
    meeting: true,
    now: () => at,
    fetcher: (request) async {
      final held = gate?.call();
      if (held != null && request.url.queryParameters.containsKey('before')) await held.future;
      return over(request);
    },
  );
  await device.mailIn!.newAddress();
  return (device: device, meet: meet);
}

/// [n] meetings over, an hour apart from an hour ago, `p00` the latest.
void history(FakeMeet meet, int n) {
  for (var i = 0; i < n; i++) {
    meet.meetings.add(meeting('p${i.toString().padLeft(2, '0')}', i == 4 ? null : 'Retro $i', 'done', at - (i + 2) * hour));
  }
}

int rowsOver(WidgetTester tester) => find.byWidgetPredicate((w) => w.key is ValueKey<String> && RegExp(r'^meet-p\d\d$').hasMatch((w.key! as ValueKey<String>).value)).evaluate().length;

String hintOf(WidgetTester tester, String key) => tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Text))).map((t) => t.data ?? '').join(' | ');

void main() {
  setUpAll(loadAppFonts);

  test('a series in words: the zone only where the clock differs, how it ends, and its next', () {
    MeetSeries of(Map<String, Object?> raw) => MeetSeries.fromJson(raw)!;
    expect(meetSeriesRule(of(standup()), now: at), 'Every weekday at 9:30');
    final next = DateTime(2026, 10, 26, 9, 30).millisecondsSinceEpoch;
    expect(meetSeriesRule(of(standup(offset: here(next) + 60)), now: at), 'Every weekday at 9:30, New York time');
    expect(meetSeriesRule(of({...standup(offset: here(next) + 60), 'zone': null}), now: at), 'Every weekday at 9:30, UTC time');
    expect(meetSeriesRule(of({...standup(offset: here(next) + 60), 'rule': 'Repeats'}), now: at), 'Repeats', reason: 'no time in it to name a zone for');
    expect(meetSeriesRule(of({...standup(), 'until': DateTime(2026, 12, 12).millisecondsSinceEpoch}), now: at), 'Every weekday at 9:30, until 12 Dec');
    expect(meetSeriesRule(of({...standup(), 'count': 10}), now: at), 'Every weekday at 9:30, 10 times');
    expect(meetSeriesNext(of(standup())), 'Next: Mon 26 Oct');
    expect(meetSeriesNext(of(standup(nextState: 'skipped', joins: false))), 'Next: Mon 26 Oct, skipped');
    expect(meetSeriesNext(of(standup(nextState: 'cancelled', joins: false))), 'Next: Mon 26 Oct, cancelled');
    expect(meetSeriesNext(of({...standup(), 'next': null})), 'Nothing more to come');
    expect(meetStopWarning(of(standup())), 'Ghost won’t join Engineering Standup any more. Past recordings stay.');
    expect(meetZoneWords('America/Los_Angeles'), 'Los Angeles');

    // The list's parts: to come first, soonest first; then over by day, the latest first.
    MeetBooking b(String id, String state, int startsAt) => MeetBooking.fromJson(meeting(id, id, state, startsAt))!;
    final listed = meetListed([
      b('old', 'done', at - 4 * 24 * hour),
      b('later', 'booked', at + 5 * hour),
      b('y', 'done', at - 20 * hour),
      b('t1', 'done', at - 3 * hour),
      b('running', 'in_call', at - 2 * hour),
      b('t2', 'failed', at - 5 * hour),
      b('soon', 'booked', at + hour),
    ], now: at);
    expect([for (final row in listed) (row.day, row.meeting.id)], [
      ('Coming up', 'running'),
      (null, 'soon'),
      (null, 'later'),
      ('Today', 't1'),
      (null, 't2'),
      ('Yesterday', 'y'),
      ('Tue 20 Oct', 'old'),
    ]);
    expect(meetListed([b('x', 'done', at - hour)], now: at).first.day, 'Today', reason: 'no Coming up when nothing is to come');
    expect(meetListed([b('x', 'booked', at + hour)], now: at).first.day, isNull, reason: 'nor over a list of only those to come');
  });

  testWidgets('the Recurring card: each series with its rule and next, and Stop joining asked first', (tester) async {
    final d = await made();
    d.meet.series.add(standup());
    d.meet.meetings.addAll([meeting('occ', 'Engineering Standup', 'booked', DateTime(2026, 10, 26, 9, 30).millisecondsSinceEpoch, series: 'stand'), meeting('one', 'Planning', 'booked', at + 3 * hour)]);
    history(d.meet, 3);
    await d.device.pump(tester, MeetingPluginPane(services: d.device.services, kind: 'meet'));
    await settle(tester, 10);
    expect(titlesOf(tester), containsAllInOrder(['Invite Ghost', 'Recurring', 'Ghost in Google Meet', 'Recordings', 'Sorting']));
    expect(hintOf(tester, 'meet-series-stand'), allOf(contains('Engineering Standup'), contains('Every weekday at 9:30\nNext: Mon 26 Oct'), contains('Stop joining')));
    expect(find.text('Ghost won’t join Engineering Standup any more. Past recordings stay.'), findsNothing);
    // The occurrence is marked as a series', the meeting of its own is not.
    LucideIcon icon(String id) => tester.widget<AppIcon>(find.descendant(of: find.byKey(ValueKey('meet-$id')), matching: find.byType(AppIcon))).icon;
    expect((icon('occ'), icon('one')), (Lucide.repeat, Lucide.calendarDays));

    // Cancel changes nothing.
    await tapKey(tester, 'meet-series-stop-stand');
    await settle(tester);
    expect(find.text('Stop joining Engineering Standup?'), findsOneWidget);
    expect(find.text('Ghost won’t join Engineering Standup any more. Past recordings stay.'), findsOneWidget);
    await press(tester, 'Cancel');
    expect(find.text('Stop joining Engineering Standup?'), findsNothing);
    expect(d.meet.calls.where((c) => c.startsWith('DELETE')), isEmpty);

    await tapKey(tester, 'meet-series-stop-stand');
    await settle(tester);
    await tapKey(tester, 'meet-series-yes-stand');
    await settle(tester, 10);
    expect(d.meet.calls, contains('DELETE meet/series/stand'));
    expect(find.byKey(const ValueKey('meet-series-stand')), findsNothing);
    expect(find.text('Ghost won’t join Engineering Standup any more.'), findsOneWidget);
    expect(hintOf(tester, 'meet-occ'), allOf(contains('Cancelled'), isNot(contains('Don’t join'))), reason: 'its occurrence to come is called off');
    expect(icon('occ'), Lucide.ban);
    expect(hintOf(tester, 'meet-one'), contains('Don’t join'), reason: 'a meeting of its own is untouched');
    await endSettings(tester);
  });

  testWidgets('an occurrence’s Don’t join skips that one alone, and the series stays', (tester) async {
    final d = await made();
    d.meet.series.add(standup());
    d.meet.meetings.add(meeting('occ', 'Engineering Standup', 'booked', DateTime(2026, 10, 26, 9, 30).millisecondsSinceEpoch, series: 'stand'));
    await d.device.pump(tester, MeetingPluginPane(services: d.device.services, kind: 'meet'));
    await settle(tester, 10);
    await bringIntoView(tester, find.byKey(const ValueKey('meet-occ')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('meet-occ')), matching: find.text('Don’t join')));
    await settle(tester, 10);
    expect(d.meet.calls, contains('DELETE meet/occ'));
    expect(d.meet.calls, isNot(contains('DELETE meet/series/stand')));
    expect(hintOf(tester, 'meet-occ'), contains('Skipped'));
    expect(find.byKey(const ValueKey('meet-series-stand')), findsOneWidget);
    // Skipped, it keeps its series' mark: the skip's answer does not say the series, and the row remembers it.
    expect(d.device.meetIn!.meetings!.single.series, 'stand');
    await endSettings(tester);
  });

  testWidgets('a service from before series draws no Recurring card, says nothing of it, and has no Show more', (tester) async {
    final d = await made(old: true);
    d.meet.series.add(standup());
    d.meet.meetings.add(meeting('one', 'Planning', 'booked', at + 3 * hour));
    history(d.meet, 30);
    await d.device.pump(tester, MeetingPluginPane(services: d.device.services, kind: 'meet'));
    await settle(tester, 10);
    expect(titlesOf(tester), isNot(contains('Recurring')));
    expect(d.device.meetIn!.series, isNull);
    expect(d.device.meetIn!.problem, isNull);
    expect(find.textContaining('could not be read'), findsNothing);
    expect(rowsOver(tester), 30, reason: 'its one list, as it answers it');
    expect(find.byKey(const ValueKey('meet-more')), findsNothing);
    expect(find.text(meetCardFooter), findsOneWidget, reason: 'and no word of thirty days it may not keep');
    expect(d.meet.calls.first, 'GET meet');
    await endSettings(tester);
  });

  testWidgets('the history: twenty at first by day, Show more loads the next below in place, then no more', (tester) async {
    Completer<void>? gate;
    final d = await made(gate: () => gate);
    history(d.meet, 45);
    d.meet.meetings.add(meeting('ahead', 'Planning', 'booked', at + 3 * hour));
    await d.device.pump(tester, MeetingPluginPane(services: d.device.services, kind: 'meet'), size: const Size(390, 900));
    await settle(tester, 10);
    expect(rowsOver(tester), 20);
    expect(find.byKey(const ValueKey('meet-day-Coming up')), findsOneWidget);
    expect(find.byKey(const ValueKey('meet-day-Today')), findsOneWidget);
    expect(find.byKey(const ValueKey('meet-day-Yesterday')), findsOneWidget);
    expect(hintOf(tester, 'meet-p00'), contains('Retro 0 | 07:00 · '), reason: 'under its day, the time alone');
    expect(hintOf(tester, 'meet-p04'), contains('A meeting'), reason: 'one the service has forgotten the title of');
    expect(find.text('$meetCardFooter $meetHistoryKept'), findsOneWidget);

    // Pressed: the word says Loading… where it stood, and nothing above it moves when the page comes.
    gate = Completer<void>();
    await tapKey(tester, 'meet-more');
    await tester.pump();
    expect(find.text('Loading…'), findsOneWidget);
    final word = tester.getTopLeft(find.byKey(const ValueKey('meet-more')));
    final last = tester.getTopLeft(find.byKey(const ValueKey('meet-p19')));
    final row = tester.getTopLeft(find.byKey(const ValueKey('meet-more-row')));
    expect(tester.getTopLeft(find.text('Loading…')).dy, closeTo(word.dy, 30));
    gate.complete();
    gate = null;
    await settle(tester, 10);
    expect(rowsOver(tester), 40);
    expect(tester.getTopLeft(find.byKey(const ValueKey('meet-p19'))), last, reason: 'Show more never jumps');
    expect(tester.getTopLeft(find.byKey(const ValueKey('meet-p20'))).dy, greaterThan(last.dy));
    expect(tester.getTopLeft(find.byKey(const ValueKey('meet-more-row'))).dy, greaterThan(row.dy));
    expect(d.meet.calls.where((c) => c == 'GET meet'), hasLength(2));

    // Read again a minute on, the pages loaded stay.
    await d.device.meetIn!.refresh();
    await settle(tester);
    expect(rowsOver(tester), 40);

    await tapKey(tester, 'meet-more');
    await settle(tester, 10);
    expect(rowsOver(tester), 45);
    expect(find.byKey(const ValueKey('meet-more')), findsNothing, reason: 'the last page has no next');
    await endSettings(tester);
  });

  testWidgets('a page that fails is said in the row with Retry, which loads it', (tester) async {
    final d = await made();
    history(d.meet, 25);
    await d.device.pump(tester, MeetingPluginPane(services: d.device.services, kind: 'meet'));
    await settle(tester, 10);
    d.meet.failMore = true;
    await tapKey(tester, 'meet-more');
    await settle(tester, 10);
    expect(find.text('Older meetings could not be read just now.'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const ValueKey('meet-more')), matching: find.text('Retry')), findsOneWidget);
    expect(rowsOver(tester), 20);
    expect(d.device.meetIn!.problem, isNull, reason: 'the list itself was read');
    d.meet.failMore = false;
    await tapKey(tester, 'meet-more');
    await settle(tester, 10);
    expect(find.text('Older meetings could not be read just now.'), findsNothing);
    expect(rowsOver(tester), 25);
    expect(find.byKey(const ValueKey('meet-more')), findsNothing);
    await endSettings(tester);
  });

  testWidgets('Simple shows the same', (tester) async {
    final d = await made();
    preferences.update((was) => was.copyWith(experience: 'simple', experienceChosen: true));
    expect(preferences.value.simple, isTrue);
    d.meet.series.add(standup());
    history(d.meet, 25);
    await d.device.pump(tester, MeetingPluginPane(services: d.device.services, kind: 'meet'));
    await settle(tester, 10);
    expect(titlesOf(tester), contains('Recurring'));
    expect(find.byKey(const ValueKey('meet-series-stop-stand')), findsOneWidget);
    expect(find.byKey(const ValueKey('meet-more')), findsOneWidget);
    await endSettings(tester);
  });

  for (final (name, size, dark) in [('a phone, dark', const Size(390, 2400), true), ('a wide window, light', const Size(1200, 2400), false)]) {
    testWidgets('drawn whole on $name, asking and loading', (tester) async {
      final d = await made();
      d.meet.series.addAll([standup(), {...standup(offset: here(at) + 60), 'id': 'm', 'title': 'Monthly planning with a title long enough to wrap on a phone', 'rule': 'Monthly on the 2nd Tuesday at 11:00', 'count': 12}]);
      history(d.meet, 25);
      await d.device.pump(tester, MeetingPluginPane(services: d.device.services, kind: 'meet'), size: size, dark: dark);
      await settle(tester, 10);
      await tapKey(tester, 'meet-series-stop-m');
      await settle(tester);
      expect(tester.takeException(), isNull);
      d.meet.failMore = true;
      await tapKey(tester, 'meet-more');
      await settle(tester, 10);
      expect(tester.takeException(), isNull);
      await endSettings(tester);
    });
  }
}
