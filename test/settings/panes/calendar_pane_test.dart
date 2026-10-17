// Settings › Calendar (lib/plugins/calendar/calendar_pane.dart, docs/CALENDAR.md): an iCal address added, checked,
// listed by its calendar's name with how its read went, and removed; Google offered only where its sign-in is set
// up, connected, its calendars ticked, and the to-dos' switch and calendar; Local only said; and the row's reading.
// Against calendars in memory (test/calendar/fake_google.dart).
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/calendar/calendar.dart';
import 'package:ghost_md/calendar/setup.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/plugins/calendar/calendar_pane.dart';
import 'package:glacier/glacier.dart';

import '../../calendar/fake_google.dart';
import '../support.dart';

const String work = 'https://cal.test/work.ics';
const String workIcs = 'BEGIN:VCALENDAR\r\nX-WR-CALNAME:Work\r\nBEGIN:VEVENT\r\nUID:a\r\nDTSTART:20261019T090000Z\r\nSUMMARY:Standup\r\nEND:VEVENT\r\nEND:VCALENDAR';

List<String> titles(WidgetTester tester) => [for (final section in tester.widgetList<PaneSection>(find.byType(PaneSection, skipOffstage: false))) section.title ?? ''];

String? hintOf(WidgetTester tester, String label) {
  final hint = tester.widget<SettingRow>(find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false)).hint;
  return hint is Text ? hint.data : null;
}

Finder row(String label) => find.byWidgetPredicate((w) => w is SettingRow && w.label == label, skipOffstage: false);

GlacierSwitch switchOf(WidgetTester tester, String label) => tester.widget<GlacierSwitch>(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == label, skipOffstage: false));

/// Taps [label] inside the row [of], scrolled to first.
Future<void> press(WidgetTester tester, String of, String label) async {
  final target = find.descendant(of: row(of), matching: find.text(label));
  await tester.ensureVisible(target);
  await tester.pump();
  await tester.tap(target);
  await settleSettings(tester);
}

void main() {
  setUpAll(loadAppFonts);

  late FakeGoogle google;
  late PreferencesStore prefs;
  late List<String> opened;
  late CalendarService service;

  Future<FetchResponse> fetch(FetchRequest request) async {
    if (request.url.host == 'cal.test') return request.url.toString() == work ? FetchResponse(200, bytes: utf8.encode(workIcs)) : FetchResponse(404);
    return google.fetch(request);
  }

  CalendarService make({String? base}) {
    final kept = MemoryStored();
    return service = CalendarService(fetch: fetch, prefs: prefs, kept: () => kept, googleBase: () => base, open: (url) async => opened.add(url));
  }

  setUp(() {
    google = FakeGoogle();
    prefs = PreferencesStore()..startWithoutStorage();
    opened = [];
  });

  Future<void> open(WidgetTester tester) async {
    await pumpSettings(tester, SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(16), child: CalendarPane(calendar: service, prefs: prefs))));
  }

  Future<void> close(WidgetTester tester) async {
    service.dispose();
    await endSettings(tester);
  }

  testWidgets('with no service, only the addresses; an address checked, added, read and removed', (tester) async {
    make();
    await open(tester);
    expect(titles(tester), ['Calendar addresses']);
    expect(find.text('Connect Google Calendar'), findsNothing);

    await tester.enterText(find.byType(EditableText), 'http://cal.test/work.ics');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('calendar-add')));
    await settleSettings(tester);
    expect(find.text('Only a secure address (https:// or webcal://) is read: the address is a secret.'), findsOneWidget);

    await tester.enterText(find.byType(EditableText), work);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('calendar-add')));
    await settleSettings(tester);
    expect(hintOf(tester, 'Work'), 'Read just now.');
    // The address is a secret: listed by its calendar's name, and never shown.
    expect(find.textContaining('cal.test/work'), findsNothing);
    expect(service.events.value.single.title, 'Standup');
    expect(row('Read now'), findsOneWidget);

    await press(tester, 'Work', 'Remove');
    expect(row('Work'), findsNothing);
    expect(calendarSetupOf(prefs.value).isEmpty, isTrue);
    await close(tester);
  });

  testWidgets('Google is offered where its sign-in is set up, and not where start answers 503', (tester) async {
    google.configured = false;
    make(base: fakeBase);
    await open(tester);
    expect(titles(tester), isNot(contains('Google Calendar')));
    await close(tester);

    google.configured = true;
    make(base: fakeBase);
    await open(tester);
    expect(titles(tester), contains('Google Calendar'));
    expect(hintOf(tester, 'Connect Google Calendar'), 'Google opens in your browser and asks what Ghost.md may see.');
    await close(tester);
  });

  testWidgets('connected: the calendars as switches, and the to-dos’ switch and calendar', (tester) async {
    make(base: fakeBase);
    await open(tester);
    await press(tester, 'Connect Google Calendar', 'Connect');
    expect(opened.single, startsWith('$fakeBase/start?state='));
    expect(row('Finish signing in on Google'), findsOneWidget);

    await service.collectGoogle();
    await service.collectGoogle();
    await settleSettings(tester);
    expect(titles(tester), ['Calendar addresses', 'Google Calendar', 'To-dos on the calendar', '']);
    expect(row('Connected'), findsOneWidget);
    expect(switchOf(tester, 'Show Me').checked, isTrue);
    expect(switchOf(tester, 'Show Team').checked, isFalse);

    switchOf(tester, 'Show Team').onCheckedChange!(true);
    await settleSettings(tester);
    expect(calendarSetupOf(prefs.value).google!.ticked, ['me@example.com', 'team@group.calendar.google.com']);

    expect(switchOf(tester, 'To-dos on the calendar').checked, isFalse);
    switchOf(tester, 'To-dos on the calendar').onCheckedChange!(true);
    await settleSettings(tester);
    expect(calendarSetupOf(prefs.value).google!.todos, isTrue);
    // Only a calendar the account may write to is offered, the primary chosen until another is.
    final picks = tester.widgetList<Pick>(find.byType(Pick, skipOffstage: false)).toList();
    expect([for (final pick in picks) '${pick.label} ${pick.checked}'], ['Put to-dos on Me true']);

    await press(tester, 'Connected', 'Disconnect');
    expect(calendarSetupOf(prefs.value).google, isNull);
    expect(row('Connect Google Calendar'), findsOneWidget);
    await close(tester);
  });

  testWidgets('says that nothing is read with Local only on', (tester) async {
    prefs.update((p) => withCalendarSetup(p.copyWith(localOnly: true), const CalendarSetup(addresses: [CalendarAddress(id: 'w', url: work, name: 'Work')])));
    make();
    await open(tester);
    expect(find.text('Local only is on: no calendar is read until it is off (Settings › Account).'), findsOneWidget);
    expect(hintOf(tester, 'Work'), 'Not read while Local only is on.');
    expect(hintOf(tester, 'Read now'), 'Not while Local only is on.');
    await close(tester);
  });

  test('the row’s reading', () {
    expect(calendarSummary(const Preferences()), 'None yet');
    final two = withCalendarSetup(const Preferences(), const CalendarSetup(addresses: [CalendarAddress(id: 'a', url: 'https://a.test/a.ics'), CalendarAddress(id: 'b', url: 'https://b.test/b.ics')]));
    expect(calendarSummary(two), '2 addresses');
    final google = withCalendarSetup(const Preferences(), const CalendarSetup(addresses: [CalendarAddress(id: 'a', url: 'https://a.test/a.ics')], google: GoogleSetup(refreshToken: 'r')));
    expect(calendarSummary(google), 'Google · 1 address');
  });
}
