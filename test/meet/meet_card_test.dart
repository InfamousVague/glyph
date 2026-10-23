// Settings › Meetings (lib/settings/panes/meetings_pane.dart, lib/meet/ui/meet_card.dart; GHST-110, Account's card
// until then): once there is an address, the invite first (a Meet link sent now, the address with Copy), then what
// Ghost does and where the sound goes over the meetings with where each stands in words, Don't join on one to come.
// Without an address, a word pointing at Account. On a phone and a wide window, light and dark.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/meet/meet_api.dart';
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/meet/ui/meet_card.dart';
import 'package:ghost_md/settings/panes/account_pane.dart';
import 'package:ghost_md/settings/panes/meetings_pane.dart';

import '../account_ui/support.dart';
import 'support.dart';

Future<({Device device, FakeMeet meet})> made({bool address = true}) async {
  final meet = FakeMeet();
  final service = await FakeService.start(seed: seeded);
  final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher));
  if (address) await device.mailIn!.newAddress();
  return (device: device, meet: meet);
}

Map<String, Object?> meeting(String id, String? title, String state, {String? detail, int startsAt = 1792159200000}) =>
    {'id': id, 'title': title, 'url': 'https://meet.google.com/abc-defg-hij', 'startsAt': startsAt, 'endsAt': startsAt + 3600000, 'state': state, 'detail': detail};

void main() {
  setUpAll(loadAppFonts);

  test('a state, and why Ghost could not join, in words', () {
    MeetBooking of(String state, [String? detail]) => MeetBooking.fromJson(meeting('x', 'T', state, detail: detail))!;
    expect([for (final s in ['booked', 'joining', 'in_call', 'done', 'skipped']) meetStateWords(of(s))], ['Booked', 'Joining', 'In the meeting', 'Written up', 'Skipped']);
    expect(meetStateWords(of('failed', 'signed_out')), 'Couldn’t join: Ghost was signed out of Google');
    expect(meetStateWords(of('failed', 'not_admitted')), 'Couldn’t join: nobody let Ghost in');
    expect(meetStateWords(of('failed', 'refused')), 'Couldn’t join: the meeting refused Ghost');
    expect(meetStateWords(of('failed')), 'Couldn’t join');
    expect(meetLink(' meet.google.com/ABC-defg-hij?authuser=1 '), 'https://meet.google.com/abc-defg-hij');
    expect(meetLink('https://zoom.us/j/123'), isNull);
  });

  testWidgets('drawn only once there is an address to invite Ghost by, and the page says where to make one', (tester) async {
    final d = await made(address: false);
    await d.device.mailIn!.refresh();
    var opened = 0;
    await d.device.pump(tester, MeetingsPane(services: d.device.services, onOpenAccount: () => opened++));
    await settle(tester, 10);
    expect(find.byType(MeetCard), findsNothing);
    expect(find.text('Ghost is invited by your Email to a note address. Turn it on in Account, then come back here to invite Ghost.'), findsOneWidget);
    await tester.tap(find.text('Open Account'));
    await settle(tester);
    expect(opened, 1);
    await endSettings(tester);
  });

  testWidgets('Account no longer draws the meetings: they are a section of their own', (tester) async {
    final d = await made();
    expect(meetingsOffered(d.device.services), isTrue);
    await d.device.pump(tester, AccountPane(services: d.device.services));
    await settle(tester, 10);
    expect(find.byType(MeetCard), findsNothing);
    expect(titlesOf(tester), isNot(contains('Ghost in meetings')));
    await endSettings(tester);
  });

  testWidgets('the address with Copy, the meetings in words, Don\'t join, and a link sent now', (tester) async {
    final d = await made();
    final copied = Clipped(tester);
    d.meet.meetings.addAll([
      meeting('a', 'Roadmap review', 'booked'),
      meeting('b', 'Standup', 'in_call'),
      meeting('c', null, 'failed', detail: 'not_admitted'),
      meeting('d', 'Retro', 'done'),
    ]);
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    // The invite on top (Matt, 2026-10-23: "move the invite card to the top"), the link before the address.
    expect(titlesOf(tester), containsAllInOrder(['Invite Ghost', 'Ghost in meetings']));
    expect(tester.getTopLeft(find.text('Send Ghost to a meeting now')).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('meet-address'))).dy));
    expect(tester.getTopLeft(find.byKey(const ValueKey('meet-address'))).dy, lessThan(tester.getTopLeft(find.text('Ghost in meetings')).dy));
    expect(meetingsSummary(d.device.services), 'Ghost is booked for 2 meetings');
    expect(find.text(meetCardFooter), findsOneWidget);
    expect(meetCardFooter, 'The meeting’s sound passes through Ghost.md’s server while it records, sealed to your account as it arrives; it is written up on your device.');
    expect(find.text('Add this address as a guest on a Google Calendar invite.'), findsOneWidget);
    final address = d.device.service.mailAddress!;
    await bringIntoView(tester, find.byKey(const ValueKey('meet-address')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('meet-address')), matching: find.text('Copy')));
    await settle(tester);
    expect(copied.text, address);

    String hintOf(String id) => tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey('meet-$id')), matching: find.byType(Text))).map((t) => t.data ?? '').join(' | ');
    expect(hintOf('a'), allOf(contains('Roadmap review'), contains('Booked'), contains('Don’t join')));
    expect(hintOf('b'), allOf(contains('In the meeting'), contains('Leave now')));
    expect(hintOf('c'), allOf(contains('A meeting'), contains('Couldn’t join: nobody let Ghost in')));
    expect(hintOf('d'), allOf(contains('Written up'), isNot(contains('Don’t join'))));

    await bringIntoView(tester, find.byKey(const ValueKey('meet-a')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('meet-a')), matching: find.text('Don’t join')));
    await settle(tester, 10);
    expect(d.meet.calls, contains('DELETE meet/a'));
    expect(hintOf('a'), contains('Skipped'));

    await typeInto(tester, 'Meet link', 'not a link');
    expect(d.meet.booked, isNull);
    await typeInto(tester, 'Meet link', 'meet.google.com/xyz-abcd-efg');
    await press(tester, 'Send Ghost to a meeting now');
    await settle(tester, 10);
    expect(d.meet.booked, {'url': 'https://meet.google.com/xyz-abcd-efg'});
    expect(find.text('Ghost is on its way into the meeting.'), findsOneWidget);
    await endSettings(tester);
  });

  for (final (name, size, dark) in [('a phone, dark', const Size(390, 1600), true), ('a wide window, light', const Size(1200, 1600), false)]) {
    testWidgets('drawn whole on $name', (tester) async {
      final d = await made();
      d.meet.meetings.add(meeting('a', 'A meeting with a long title that has to wrap on a phone somewhere', 'failed', detail: 'signed_out'));
      await d.device.pump(tester, MeetCard(services: d.device.services), size: size, dark: dark);
      await settle(tester, 10);
      expect(tester.takeException(), isNull);
      expect(find.textContaining('Ghost was signed out of Google'), findsOneWidget);
      await endSettings(tester);
    });
  }

  testWidgets('a service with no meeting routes lists no Meetings and draws no card', (tester) async {
    final d = await made();
    d.meet.routes = false;
    await d.device.meetIn!.refresh();
    expect(meetingsOffered(d.device.services), isFalse, reason: 'and Settings does not list Meetings');
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    expect(find.byType(MeetCard), findsNothing);
    await endSettings(tester);
  });
}
