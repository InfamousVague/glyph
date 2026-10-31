// A ticket's watchers told in their bell (lib/book/ticket_events.dart; Matt, 2026-10-31): status, assignee, due, a
// comment, closed; batched per ticket within two minutes; by the device whose change it was, after the pass, sealed
// under the organization key, once across devices. Against the service in memory (test/support/fake_service.dart),
// whose ticket-events route writes a row into each member's feed once per id, as server/src/notifications.rs does.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/book/ticket_events.dart';
import 'package:ghost_md/book/ticket_watchers.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/sync/feed.dart';

import '../feed/signed.dart';
import '../support/fake_service.dart';

const String start = '---\ntype: ticket\nid: GHO-12\nstatus: To do\nwatchers: ["@matt", "@sam", "@ana"]\n---\n# Fix the login loop\n';

const int minute = 60000;

/// One of Matt's devices: its ledger, its clock and its notes' words.
class Device {
  Device(this.service, this.clock) : ledger = TicketEventLedger(kept: MemoryStored(), now: () => clock.now);
  final FakeService service;
  final Clock clock;
  final TicketEventLedger ledger;
  final Map<String, String> notes = {};
  late String org;
  late SealKey key;

  /// A change this device made to a note.
  void changes(String noteId, String words) {
    final before = notes[noteId] ?? '';
    notes[noteId] = words;
    ledger.made(7, org, noteId, before, words);
  }

  /// Words from the team's log: never this device's to tell.
  void hears(String noteId, String words) => notes[noteId] = words;

  Future<int> pass() => sendTicketEvents(
        ledger,
        TicketEventSend(
          accountId: 7,
          token: service.signedIn(),
          orgId: org,
          key: key,
          generation: 1,
          api: apiOf(service),
          crypto: service.crypto,
          me: 'matt',
          words: (id) async => notes[id],
          title: (id, words) => ticketNoticeTitle(words, words.split('\n').firstWhere((l) => l.startsWith('# ')).substring(2)),
        ),
      );
}

class Clock {
  int now = 1000 * minute;
}

Future<({FakeService service, String org, SealKey key})> team() async {
  final service = await FakeService.start(seed: testAccount, peers: const ['sam', 'ana', 'zed']);
  final made = await apiOf(service).callMap('POST', 'orgs', token: service.signedIn(), body: {'name': 'Ghost'});
  final org = (made['org'] as Map)['id'] as String;
  final rows = service.orgs[org]!.rows;
  rows['sam'] = OrgRowKept(handle: 'sam', role: 'member', state: 'member', since: 1, invitedBy: 'matt');
  rows['ana'] = OrgRowKept(handle: 'ana', role: 'member', state: 'member', since: 1, invitedBy: 'matt');
  rows['zed'] = OrgRowKept(handle: 'zed', role: 'member', state: 'member', since: 1, invitedBy: 'matt');
  final key = await service.crypto.importSealKey(Uint8List.fromList(List<int>.filled(32, 7)));
  return (service: service, org: org, key: key);
}

Device deviceOn(({FakeService service, String org, SealKey key}) t, Clock clock) => Device(t.service, clock)
  ..org = t.org
  ..key = t.key;

void main() {
  test('changes within two minutes are one notice to each watcher, never the one who made them', () async {
    final t = await team();
    final clock = Clock();
    final mac = deviceOn(t, clock);
    mac.hears('n1', start);
    mac.changes('n1', withProperty(start, 'status', 'In progress'));
    clock.now += 30000;
    mac.changes('n1', withProperty(withProperty(start, 'status', 'In review'), 'due', '2026-11-06'));
    expect(mac.ledger.owedIn(7, t.org), hasLength(1));
    expect(await mac.pass(), 0, reason: 'the window is still open');
    clock.now += 2 * minute;
    expect(await mac.pass(), 1);
    expect(t.service.ticketTold.keys, unorderedEquals(['sam', 'ana']));
    expect(t.service.ticketPosts.single['to'], ['sam', 'ana']);
    expect(mac.ledger.owedIn(7, t.org), isEmpty);
    expect(await mac.pass(), 0);
    expect(t.service.ticketPosts, hasLength(1));
  });

  test('moved and moved back is told nothing; a comment, a new assignee and a close each are', () async {
    final t = await team();
    final clock = Clock();
    final mac = deviceOn(t, clock);
    mac.hears('n1', start);
    mac.changes('n1', withProperty(start, 'status', 'In progress'));
    mac.changes('n1', start);
    expect(mac.ledger.owedIn(7, t.org), isEmpty);
    // A comment, and zed assigned from a board (not yet a watcher): zed is told too.
    final commented = '${withProperty(start, 'assignee', 'zed')}\nIt loops.[^c1]\n\n```comments\nc1 matt 2026-10-31T09:00:00Z\nOnly on Safari, I think.\n```\n';
    mac.changes('n1', commented);
    clock.now += 3 * minute;
    expect(await mac.pass(), 1);
    expect(t.service.ticketPosts.last['to'], ['sam', 'ana', 'zed']);
    // Closed.
    mac.changes('n1', withProperty(commented, 'status', 'Done'));
    clock.now += 3 * minute;
    await mac.pass();
    expect(t.service.ticketPosts, hasLength(2));
  });

  test('notify once across two devices: the other hears it and tells nobody, and a second telling lands once', () async {
    final t = await team();
    final clock = Clock();
    final mac = deviceOn(t, clock), phone = deviceOn(t, clock);
    mac.hears('n1', start);
    phone.hears('n1', start);
    final moved = withProperty(start, 'status', 'In review');
    mac.changes('n1', moved);
    phone.hears('n1', moved);
    expect(phone.ledger.owedIn(7, t.org), isEmpty);
    clock.now += 3 * minute;
    expect(await mac.pass(), 1);
    expect(await phone.pass(), 0);
    // The same change owed on both (the phone's copy reconciled as a change of its own, in the same window): one id.
    final again = deviceOn(t, clock);
    again.hears('n1', start);
    final clock2 = Clock()..now = 1000 * minute;
    final twin = Device(t.service, clock2)
      ..org = t.org
      ..key = t.key;
    twin.hears('n1', start);
    twin.changes('n1', moved);
    clock2.now += 3 * minute;
    await twin.pass();
    expect(t.service.ticketPosts, hasLength(2));
    expect(t.service.ticketTold['sam'], hasLength(1), reason: 'one row in sam’s bell');
  });

  test('sealed under the organization key for this batch alone, and sam’s bell opens it with Unwatch at hand', () async {
    final t = await team();
    final clock = Clock();
    final mac = deviceOn(t, clock);
    mac.hears('n1', start);
    mac.changes('n1', withProperty(start, 'status', 'Done'));
    clock.now += 3 * minute;
    await mac.pass();
    final id = t.service.ticketTold['sam']!.keys.single;
    final blob = t.service.ticketTold['sam']![id]!.blob;
    expect(blob, isNot(contains('login')));
    final opened = await t.service.crypto.open(t.key, blob, ticketEventContext(t.org, id));
    expect(opened, {'kind': 'ticket', 'noteId': 'n1', 'title': 'GHO-12 Fix the login loop', 'by': 'matt', 'first': 'To do → Done', 'what': 'closed'});
    await expectLater(t.service.crypto.open(t.key, blob, 'mention:${t.org}:$id'), throwsA(anything), reason: 'not a mention');
    await expectLater(t.service.crypto.open(t.service.accountKey, blob, ticketEventContext(t.org, id)), throwsA(anything));
    final row = FeedNotification(id: id, rev: 3, kind: 'ticket', at: 1, from: 'matt', org: (id: t.org, name: 'Ghost'), body: const {'name': 'Ghost', 'generation': 1}, blob: blob);
    final account = SignedAccount(session: testSession, key: t.service.accountKey);
    final feed = NotificationFeed(account: account, crypto: t.service.crypto, kept: MemoryStored());
    expect(sentenceOf(row), 'matt changed a ticket you watch');
    feed.orgKey = (org, generation) async => org == t.org ? t.key : null;
    final details = await feed.detailsFor(row);
    expect(sentenceOf(row, details), 'matt closed GHO-12 Fix the login loop');
    expect(detailOf(details), 'To do → Done');
    expect(isTicketEvent(row), isTrue);
    expect(isMention(row), isFalse);
    feed.dispose();
  });

  test('nobody watching is told nothing; a service without the route keeps the batch for later', () async {
    final t = await team();
    final clock = Clock();
    final mac = deviceOn(t, clock);
    final alone = withWatchersList(start, ['matt']);
    mac.hears('n1', alone);
    mac.changes('n1', withProperty(alone, 'status', 'Done'));
    clock.now += 3 * minute;
    expect(await mac.pass(), 0);
    expect(t.service.ticketPosts, isEmpty);
    expect(mac.ledger.owedIn(7, t.org), isEmpty);
    t.service.ticketEvents = false;
    mac.changes('n1', withProperty(start, 'status', 'In review'));
    clock.now += 3 * minute;
    expect(await mac.pass(), 0);
    expect(mac.ledger.owedIn(7, t.org), hasLength(1), reason: 'an older service: kept, a week at most');
    t.service.ticketEvents = true;
    expect(await mac.pass(), 1);
  });

  test('the words under the sentence', () {
    final batch = joinChange(null, orgId: 'o', noteId: 'n', before: start, after: withProperty(withProperty(withProperty(start, 'status', 'In review'), 'assignee', 'sam'), 'due', '2026-11-06'), at: 0)!;
    expect(batchWords(batch), 'To do → In review · Assigned to sam · Due 2026-11-06');
    expect(batchWhat(batch), 'changed');
  });
}
