// Settings › Meetings (lib/settings/panes/meetings_pane.dart, lib/meet/ui/meet_card.dart; GHST-110, Account's card
// until then): once there is an address, the invite first (a Meet link sent now, the address with Copy and a new
// one, asked first), then what Ghost does and where the sound goes over the meetings with where each stands in words,
// Don't join on one to come, and a meeting that became a note opening it. Then Email to a note, and the recordings'
// switch with how many stayed on this phone, which were Account's until 2026-10-24 (Matt: "move all google meet
// related stuff to under the meet section"). Without an address, Email to a note turns one on here. On a phone and a
// wide window, light and dark.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/summary_handoff.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/mail/ui/mail_card.dart';
import 'package:ghost_md/meet/meet_api.dart';
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/meet/ui/meet_card.dart';
import 'package:ghost_md/settings/kit/settings_kit.dart';
import 'package:ghost_md/settings/panes/account_pane.dart';
import 'package:ghost_md/settings/panes/meetings_pane.dart';
import 'package:glacier/glacier.dart';

import '../account_ui/support.dart';
import 'support.dart';

/// A device with Ghost in meetings; [refuseNew] has the service turn down a new address (as a service with mail
/// switched off since the page was drawn does), the address already made left as it was.
Future<({Device device, FakeMeet meet})> made({bool address = true, bool Function()? refuseNew}) async {
  final meet = FakeMeet();
  final service = await FakeService.start(seed: seeded);
  final over = meet.over(service.fetcher);
  final device = await Device.make(
    service: service,
    publishing: true,
    meeting: true,
    fetcher: (request) async {
      if (refuseNew != null && refuseNew() && request.method == 'POST' && request.url.path.endsWith('/mail/address')) return FetchResponse.json(503, {'error': 'Email to a note is not set up on this service yet.'});
      return over(request);
    },
  );
  if (address) await device.mailIn!.newAddress();
  return (device: device, meet: meet);
}

Map<String, Object?> meeting(String id, String? title, String state, {String? detail, int startsAt = 1792159200000}) =>
    {'id': id, 'title': title, 'url': 'https://meet.google.com/abc-defg-hij', 'startsAt': startsAt, 'endsAt': startsAt + 3600000, 'state': state, 'detail': detail};

/// A row's words, all of them, for what it says.
String hintOf(WidgetTester tester, String id) => tester.widgetList<Text>(find.descendant(of: find.byKey(ValueKey('meet-$id')), matching: find.byType(Text))).map((t) => t.data ?? '').join(' | ');

/// Whether the row keyed `meet-<id>` is pressed as a whole (the kit's chevron row).
bool pressed(WidgetTester tester, String id) => tester.widget<SettingRow>(find.byKey(ValueKey('meet-$id'))).onPress != null;

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

  testWidgets('without an address, the page turns one on itself, and the invite card is drawn once there is one', (tester) async {
    final d = await made(address: false);
    await d.device.mailIn!.refresh();
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    expect(find.byType(MeetCard), findsNothing);
    expect(find.text('Ghost is invited by your Email to a note address. Turn one on below, then invite Ghost here.'), findsOneWidget);
    expect(find.textContaining('It is the address Ghost is invited to a meeting by, too.'), findsOneWidget);
    await press(tester, 'Turn on an address');
    await settle(tester, 10);
    expect(find.byType(MeetCard), findsOneWidget);
    expect(find.text(d.device.service.mailAddress!.replaceFirst('@', '@​')), findsOneWidget, reason: 'drawn once, on the invite card');
    expect(titlesOf(tester), containsAllInOrder(['Invite Ghost', 'Ghost in meetings', 'Email to a note', 'Recordings']));
    await endSettings(tester);
  });

  testWidgets('Account no longer draws the meetings, the recordings switch or the address: a line points at Meetings', (tester) async {
    final d = await made();
    expect(meetingsOffered(d.device.services), isTrue);
    var opened = 0;
    await d.device.pump(tester, AccountPane(services: d.device.services, onOpenMeetings: () => opened++));
    await settle(tester, 10);
    expect(find.byType(MeetCard), findsNothing);
    expect(find.byType(MailCard), findsNothing);
    expect(titlesOf(tester), isNot(contains('Ghost in meetings')));
    expect(find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Sync meeting recordings'), findsNothing);
    expect(find.textContaining('stayed on this phone'), findsNothing);
    expect(find.text(d.device.service.mailAddress!.replaceFirst('@', '@​')), findsNothing);
    expect(accountFindable(signedIn: true, ported: true).map((found) => found.name), isNot(contains('Sync meeting recordings')));
    expect(find.text('Your address, which Ghost is invited by too, is under Meetings.'), findsOneWidget);
    await tapKey(tester, 'account-mail-moved');
    expect(opened, 1);
    await endSettings(tester);
  });

  testWidgets('the recordings switch is on Meetings, on by default, and writes the choice', (tester) async {
    final d = await made();
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    expect(find.textContaining("A meeting is other people's voices: off, the words sync and the audio stays on the device it was made on."), findsOneWidget);
    expect(find.textContaining('to everyone in the team'), findsOneWidget);
    expect((preferences.value.syncMeetingRecordings, preferences.value.syncMeetingRecordingsChosen), (true, false));
    final toggle = find.byWidgetPredicate((w) => w is GlacierSwitch && w.ariaLabel == 'Sync meeting recordings');
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await settle(tester);
    expect((preferences.value.syncMeetingRecordings, preferences.value.syncMeetingRecordingsChosen), (false, true));
    await endSettings(tester);
  });

  testWidgets('counts the recordings that stayed on this phone: a meeting’s while those stay, and any over the service’s limit', (tester) async {
    final d = await made();
    Note taped(String id, String body, int ms) => d.device.notes.held[id] = Note(id: id, body: body, createdAt: 0, updatedAt: 0, source: NoteSource.capture, recordingMs: ms, segments: const []);
    taped('m', '# Meeting, 26 Sep 14:05', 60000);
    taped('big', '# Long', 150 * 60000);
    taped('ok', '# Short', 60000);
    preferences.update((now) => now.copyWith(meetings: const {'m': 1}, syncMeetingRecordings: false, syncMeetingRecordingsChosen: true));
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester);
    expect(find.textContaining('2 recordings stayed on this phone: meetings, while their recordings stay'), findsOneWidget);
    preferences.update((now) => now.copyWith(syncMeetingRecordings: true));
    await settle(tester);
    expect(find.textContaining('1 recording stayed on this phone: longer than the account takes'), findsOneWidget);
    await endSettings(tester);
  });

  testWidgets('every name the search lists for Meetings is on the page', (tester) async {
    final d = await made();
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    final names = meetingsFindable(d.device.services).map((found) => found.name).toList();
    expect(names, containsAll(['Invite Ghost', 'Ghost in meetings', 'Email to a note', 'Sync meeting recordings']));
    for (final name in names) {
      expect(find.byWidgetPredicate((w) => w is SettingsFindableMark && w.name == name, skipOffstage: false), findsWidgets, reason: 'Meetings lists "$name" and does not draw it');
    }
    await endSettings(tester);
  });

  testWidgets('Check now reads the meetings at once, past the minute\'s wait, and says when it last did', (tester) async {
    // Matt, 2026-10-24: "add a \"check now\" button to check for new meetings".
    final d = await made();
    d.meet.meetings.add(meeting('a', 'Roadmap review', 'booked'));
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    final reads = d.meet.calls.where((c) => c == 'GET meet').length;
    expect(find.text('Checked just now'), findsOneWidget);
    // An invite booked a moment ago: the minute's read would not come for a while yet.
    d.meet.meetings.add(meeting('b', 'Engineering Standup', 'booked'));
    await bringIntoView(tester, find.byKey(const ValueKey('meet-check-now')));
    await tester.tap(find.byKey(const ValueKey('meet-check-now')));
    await settle(tester, 10);
    expect(d.meet.calls.where((c) => c == 'GET meet').length, reads + 1);
    expect(find.text('Engineering Standup'), findsOneWidget);
    // Refused: said, and the list stays as it was.
    d.meet.failList = true;
    await tester.tap(find.byKey(const ValueKey('meet-check-now')));
    await settle(tester, 10);
    expect(find.text('Engineering Standup'), findsOneWidget);
    expect(find.text('Your meetings could not be read just now.'), findsOneWidget, reason: 'said on the row, the list kept');
    expect(meetCheckedSaid(null, now: 0), 'Ghost.md checks every minute while this page is open.');
    expect(meetCheckedSaid(0, now: 3 * 60000 + 5), 'Checked 3 min ago');
    expect(meetCheckedSaid(0, now: 2 * 3600000), 'Checked 2 hr ago');
    await endSettings(tester);
  });

  testWidgets('the page opened reads the meetings at once past the minute\'s wait, unless it read a moment ago', (tester) async {
    // Matt, 2026-10-24: "meetings don't load on the phone app right away I have to wait several minutes for them to
    // sync".
    final d = await made();
    final meet = d.device.meetIn!;
    var now = DateTime.now().millisecondsSinceEpoch;
    meet.clock = () => now;
    int reads() => d.meet.calls.where((c) => c == 'GET meet').length;
    d.meet.meetings.add(meeting('a', 'Roadmap review', 'booked'));
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    final first = reads();
    expect(first, greaterThan(0));
    // Closed, and an invite booked meanwhile; opened again fifteen seconds on, well inside the minute the drawn page
    // waits between reads: read as it opens, and the new one is there.
    await tester.pumpWidget(const SizedBox.shrink());
    d.meet.meetings.add(meeting('b', 'Engineering Standup', 'booked'));
    now += 15000;
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    expect(reads(), first + 1);
    expect(find.text('Engineering Standup'), findsOneWidget);
    // Opened again a moment later: the list is that fresh, and not read again; nor by the page drawing itself.
    await tester.pumpWidget(const SizedBox.shrink());
    now += 3000;
    await d.device.pump(tester, MeetingsPane(services: d.device.services));
    await settle(tester, 10);
    expect(reads(), first + 1);
    await endSettings(tester);
  });

  testWidgets('read now while a read is under way: one more after it, which has what changed meanwhile', (tester) async {
    final d = await made();
    final meet = d.device.meetIn!;
    int reads() => d.meet.calls.where((c) => c == 'GET meet').length;
    final before = reads();
    // The service's word that the list changed (lib/live/poke.dart) comes twice while the first read is out.
    meet.readNow();
    meet.readNow();
    meet.readNow();
    d.meet.meetings.add(meeting('a', 'Roadmap review', 'booked'));
    await tester.runAsync(() async {
      for (var i = 0; i < 50 && reads() < before + 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      // Whatever else was to come has come.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    expect(reads(), before + 2, reason: 'the first, and one after it for what was asked meanwhile');
    expect(meet.meetings?.map((m) => m.id), ['a']);
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
    expect(tester.getTopLeft(find.text('Join')).dy, lessThan(tester.getTopLeft(find.byKey(const ValueKey('meet-address'))).dy));
    // Join on the link's line, to its right (Matt, 2026-10-24).
    final field = tester.getRect(find.bySemanticsLabel('Meet link').first), join = tester.getRect(find.byKey(const ValueKey('meet-send')));
    expect(join.left, greaterThan(field.right));
    expect((join.center.dy - field.center.dy).abs(), lessThan(4));
    expect(tester.getTopLeft(find.byKey(const ValueKey('meet-address'))).dy, lessThan(tester.getTopLeft(find.byWidgetPredicate((w) => w is PaneSection && w.title == 'Ghost in meetings')).dy));
    expect(meetingsSummary(d.device.services), 'Ghost is booked for 2 meetings');
    expect(find.text(meetCardFooter), findsOneWidget);
    expect(meetCardFooter, 'The meeting’s sound passes through Ghost.md’s server while it records, sealed to your account as it arrives; it is written up on your device.');
    expect(find.text('Add this address as a guest on a Google Calendar invite. Mail sent to it becomes a note in your Inbox.'), findsOneWidget);
    final address = d.device.service.mailAddress!;
    await bringIntoView(tester, find.byKey(const ValueKey('meet-address')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('meet-address')), matching: find.text('Copy')));
    await settle(tester);
    expect(copied.text, address);

    expect(hintOf(tester, 'a'), allOf(contains('Roadmap review'), contains('Booked'), contains('Don’t join')));
    expect(hintOf(tester, 'b'), allOf(contains('In the meeting'), contains('Leave now')));
    expect(hintOf(tester, 'c'), allOf(contains('A meeting'), contains('Couldn’t join: nobody let Ghost in')));
    // Done on the service, and no note here yet: the take waits for a device to file it.
    expect(hintOf(tester, 'd'), allOf(contains('Not written up yet'), isNot(contains('Don’t join'))));

    await bringIntoView(tester, find.byKey(const ValueKey('meet-a')));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('meet-a')), matching: find.text('Don’t join')));
    await settle(tester, 10);
    expect(d.meet.calls, contains('DELETE meet/a'));
    expect(hintOf(tester, 'a'), contains('Skipped'));

    await typeInto(tester, 'Meet link', 'not a link');
    expect(d.meet.booked, isNull);
    await typeInto(tester, 'Meet link', 'meet.google.com/xyz-abcd-efg');
    await press(tester, 'Join');
    await settle(tester, 10);
    expect(d.meet.booked, {'url': 'https://meet.google.com/xyz-abcd-efg'});
    expect(find.text('Ghost is on its way into the meeting.'), findsOneWidget);
    await endSettings(tester);
  });

  group('a meeting that became a note', () {
    const at = 1792159200000;
    const ghostBody = '# Retro\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n\n## Transcript\n\n**Sam:** Hello.\n';

    testWidgets('opens it, and one with no note yet, or still to come, is not pressed', (tester) async {
      final d = await made();
      d.meet.meetings.addAll([
        meeting('a', 'Roadmap review', 'booked', startsAt: at + 86400000),
        meeting('b', 'Standup', 'in_call', startsAt: at),
        meeting('d', 'Retro', 'done', startsAt: at - 86400000),
        meeting('e', 'Planning', 'done', startsAt: at - 2 * 86400000),
        meeting('f', 'Design', 'done', startsAt: at - 3 * 86400000),
      ]);
      d.device.keep('retro', ghostBody);
      d.device.keep('design', '# Design\n\nGhost was in this meeting on 15 Oct, 14:00. It is being written up on your device.\n');
      preferences.update((was) => withMeetingNote(withMeetingNote(was.copyWith(meetings: {'retro': at - 86400000, 'design': at - 3 * 86400000}), 'd', 'retro'), 'f', 'design'));
      final opened = <String>[];
      await d.device.pump(tester, MeetingsPane(services: d.device.services, onOpenNote: opened.add));
      await settle(tester, 10);
      expect(hintOf(tester, 'd'), contains('Written up'));
      expect(hintOf(tester, 'e'), contains('Not written up yet'));
      expect(hintOf(tester, 'f'), contains('Being written up'));
      expect([for (final id in ['a', 'b', 'd', 'e', 'f']) pressed(tester, id)], [false, false, true, false, true]);
      expect(hintOf(tester, 'a'), contains('Don’t join'), reason: 'a meeting to come keeps its Don’t join');

      await tapKey(tester, 'meet-d');
      await settle(tester);
      expect(opened, ['retro']);
      await tapKey(tester, 'meet-e');
      await settle(tester);
      expect(opened, ['retro'], reason: 'Not written up yet: nothing to open');
      await endSettings(tester);
    });

    testWidgets('a meeting filed before its note was kept against it is found by when Ghost recorded it', (tester) async {
      final d = await made();
      d.meet.meetings.add(meeting('d', null, 'done', startsAt: at));
      d.device.keep('old', ghostBody);
      preferences.update((was) => was.copyWith(meetings: {'old': at + 60000}));
      final opened = <String>[];
      await d.device.pump(tester, MeetingsPane(services: d.device.services, onOpenNote: opened.add));
      await settle(tester, 10);
      expect(hintOf(tester, 'd'), contains('Written up'));
      await tapKey(tester, 'meet-d');
      await settle(tester);
      expect(opened, ['old']);
      await endSettings(tester);
    });

    // Matt, 2026-10-26: "The engineering standup meeting was not auto summarized": the row said Written up while the
    // summary waited for a model the Mac did not have (lib/ai/summary_handoff.dart).
    testWidgets('says where a meeting waits for its summary, and what to do, until another device has written it', (tester) async {
      final d = await made();
      d.meet.meetings.add(meeting('d', 'Engineering standup', 'done', startsAt: at));
      d.device.keep('retro', ghostBody);
      final here = thisDevice();
      final now = DateTime.now().millisecondsSinceEpoch;
      Preferences marked(Preferences was, Handoff entry) => withHandoff(was, 'retro', entry, now: now);
      preferences.update((was) => marked(withMeetingNote(was.copyWith(meetings: {'retro': at}), 'd', 'retro'), Handoff(from: here.id, fromName: here.name, at: now)));
      await d.device.pump(tester, MeetingsPane(services: d.device.services, onOpenNote: (_) {}));
      await settle(tester, 10);
      expect(hintOf(tester, 'd'), contains(summaryWaitWords(here.name)));
      if (here.name == 'Mac') {
        expect(hintOf(tester, 'd'), contains('Waiting for a summary: turn on Claude or download the summary model on this Mac, or open Ghost.md on your phone.'));
      }
      preferences.update((was) => marked(was, Handoff(from: here.id, at: now, claimBy: 'fold-1', claimName: 'phone', claimAt: now)));
      await settle(tester, 10);
      expect(hintOf(tester, 'd'), contains('Being summarized on your phone.'));
      preferences.update((was) => marked(was, Handoff(from: here.id, at: now, done: now, doneBy: 'fold-1')));
      await settle(tester, 10);
      expect(hintOf(tester, 'd'), contains('Written up'));
      expect(hintOf(tester, 'd'), isNot(contains('Waiting')));
      await endSettings(tester);
    });

    testWidgets('without a way to open notes, nothing is pressed', (tester) async {
      final d = await made();
      d.meet.meetings.add(meeting('d', 'Retro', 'done', startsAt: at));
      d.device.keep('retro', ghostBody);
      preferences.update((was) => withMeetingNote(was.copyWith(meetings: {'retro': at}), 'd', 'retro'));
      await d.device.pump(tester, MeetCard(services: d.device.services));
      await settle(tester, 10);
      expect(hintOf(tester, 'd'), contains('Written up'));
      expect(pressed(tester, 'd'), isFalse);
      await endSettings(tester);
    });
  });

  group('a new address', () {
    testWidgets('asks first, then draws the new one in the old one’s place and says the old one is off', (tester) async {
      final d = await made();
      final first = d.device.service.mailAddress!;
      await d.device.pump(tester, MeetingsPane(services: d.device.services));
      await settle(tester, 10);
      final button = find.bySemanticsLabel('Make a new address');
      expect(button, findsOneWidget, reason: 'the icon beside Copy, named for a screen reader');

      // Cancel changes nothing.
      await tapKey(tester, 'meet-new');
      await settle(tester);
      expect(find.text('Make a new address?'), findsOneWidget);
      expect(find.text('Invites and mail sent to the old one are turned away from then on. A Calendar invite with it as a guest needs the new one.'), findsOneWidget);
      await press(tester, 'Cancel');
      expect(find.text('Make a new address?'), findsNothing);
      expect(d.device.service.mailAddress, first);

      await tapKey(tester, 'meet-new');
      await settle(tester);
      await press(tester, 'Make it');
      await settle(tester, 10);
      final second = d.device.service.mailAddress!;
      expect(second, isNot(first));
      expect(find.text(second.replaceFirst('@', '@​')), findsOneWidget);
      expect(find.text(first.replaceFirst('@', '@​')), findsNothing);
      expect(find.text('A new address: $second. The old one takes no more invites or mail.'), findsOneWidget);
      expect(find.text('Make a new address?'), findsNothing);
      await endSettings(tester);
    });

    testWidgets('a refusal is said in the card, and the old address stays', (tester) async {
      var refuse = false;
      final d = await made(refuseNew: () => refuse);
      final first = d.device.service.mailAddress!;
      refuse = true;
      await d.device.pump(tester, MeetingsPane(services: d.device.services));
      await settle(tester, 10);
      await tapKey(tester, 'meet-new');
      await settle(tester);
      await press(tester, 'Make it');
      await settle(tester, 10);
      expect(find.text('Email to a note is not set up on this service yet.'), findsOneWidget);
      expect(d.device.service.mailAddress, first);
      expect(find.text(first.replaceFirst('@', '@​')), findsOneWidget);
      await endSettings(tester);
    });

    testWidgets('is offered in Simple too', (tester) async {
      final d = await made();
      preferences.update((was) => was.copyWith(experience: 'simple', experienceChosen: true));
      expect(preferences.value.simple, isTrue);
      await d.device.pump(tester, MeetingsPane(services: d.device.services));
      await settle(tester, 10);
      expect(find.byKey(const ValueKey('meet-new')), findsOneWidget);
      await endSettings(tester);
    });
  });

  for (final (name, size, dark) in [('a phone, dark', const Size(390, 1600), true), ('a wide window, light', const Size(1200, 1600), false)]) {
    testWidgets('drawn whole on $name', (tester) async {
      final d = await made();
      d.meet.meetings.add(meeting('a', 'A meeting with a long title that has to wrap on a phone somewhere', 'failed', detail: 'signed_out'));
      await d.device.pump(tester, MeetingsPane(services: d.device.services), size: size, dark: dark);
      await settle(tester, 10);
      await tapKey(tester, 'meet-new');
      await settle(tester);
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
    // Account keeps Email to a note whole, since there is no Meetings to point at.
    await d.device.pump(tester, AccountPane(services: d.device.services));
    await settle(tester, 10);
    expect(find.byType(MailCard), findsOneWidget);
    expect(find.byKey(const ValueKey('account-mail-moved')), findsNothing);
    await endSettings(tester);
  });
}
