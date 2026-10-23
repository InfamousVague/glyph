// The home page's Upcoming meetings (lib/home/home_meetings.dart; Matt, 2026-10-23): the meetings Ghost is booked for
// or in, soonest first, four at most, with when each is or where it stands; nothing when there are none, or no
// Ghost in meetings; its foot opens Settings › Meetings.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/home/home_meetings.dart';
import 'package:ghost_md/meet/meet_api.dart';

import '../account_ui/support.dart';
import 'support.dart';

const int at = 1792159200000;

Map<String, Object?> meeting(String id, String? title, String state, int startsAt) =>
    {'id': id, 'title': title, 'url': 'https://meet.google.com/abc-defg-hij', 'startsAt': startsAt, 'endsAt': startsAt + 3600000, 'state': state, 'detail': null};

Future<({Device device, FakeMeet meet})> made() async {
  final meet = FakeMeet();
  final service = await FakeService.start(seed: seeded);
  final device = await Device.make(service: service, publishing: true, meeting: true, fetcher: meet.over(service.fetcher), now: () => at);
  return (device: device, meet: meet);
}

void main() {
  setUpAll(loadAppFonts);

  test('the ones still to come or going on, soonest first, four at most', () {
    MeetBooking of(String id, String state, int startsAt) => MeetBooking.fromJson(meeting(id, id, state, startsAt))!;
    final list = [
      of('later', 'booked', at + 5 * 3600000),
      of('done', 'done', at - 7200000),
      of('now', 'in_call', at - 600000),
      of('skipped', 'skipped', at + 3600000),
      of('soon', 'booked', at + 3600000),
      of('over', 'booked', at - 3 * 3600000),
      of('a', 'booked', at + 6 * 3600000),
      of('b', 'booked', at + 7 * 3600000),
    ];
    expect([for (final m in upcomingMeetings(list, now: at)) m.id], ['now', 'soon', 'later', 'a']);
    expect(upcomingMeetings(null, now: at), isEmpty);
  });

  testWidgets('listed with when and where each stands, and Meetings opens the page', (tester) async {
    final d = await made();
    d.meet.meetings.addAll([
      meeting('b', 'Standup', 'in_call', at - 600000),
      meeting('a', 'Roadmap review', 'booked', at + 3600000),
      meeting('c', 'Retro', 'done', at - 86400000),
    ]);
    var opened = 0;
    await d.device.pump(tester, HomeMeetings(services: d.device.services, onOpen: () => opened++));
    await settle(tester, 10);
    expect(find.text('Upcoming meetings'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-meeting-b')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-meeting-a')), findsOneWidget);
    expect(find.byKey(const ValueKey('home-meeting-c')), findsNothing);
    expect(tester.getTopLeft(find.text('Standup')).dy, lessThan(tester.getTopLeft(find.text('Roadmap review')).dy));
    expect(find.text('In the meeting'), findsOneWidget);
    await tester.tap(find.text('Meetings'));
    await settle(tester);
    expect(opened, 1);
    await endSettings(tester);
  });

  testWidgets('nothing at all with no meeting to come', (tester) async {
    final d = await made();
    d.meet.meetings.add(meeting('c', 'Retro', 'done', at - 86400000));
    await d.device.pump(tester, HomeMeetings(services: d.device.services));
    await settle(tester, 10);
    expect(find.byKey(const ValueKey('home-meetings')), findsNothing);
    await endSettings(tester);
  });

  testWidgets('nothing at all where the service has no Ghost in meetings', (tester) async {
    final d = await made();
    d.meet.meetings.add(meeting('a', 'Roadmap review', 'booked', at + 3600000));
    d.meet.routes = false;
    await d.device.meetIn!.refresh();
    await d.device.pump(tester, HomeMeetings(services: d.device.services));
    await settle(tester, 10);
    expect(find.byKey(const ValueKey('home-meetings')), findsNothing);
    await endSettings(tester);
  });
}
