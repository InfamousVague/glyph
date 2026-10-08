import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/sync/arrived.dart';
import 'package:ghost_md/sync/feed.dart';

import '../support/fake_service.dart';
import 'signed.dart';

/// The feed against the service in memory (lib/sync/feed.dart): two devices converging on what was read and hidden,
/// a mark made here outliving a row fed before it landed, an invitation answered inline, a sealed row opened lazily
/// and never stalling, and the two 404s told apart - the service without the routes yet, which is quiet, and an
/// answer in the service's words, which is not. The web's `src/app/core/notifications/feed.test.ts`, case for case,
/// with the feed's memory and the account handed in where the page's tests reset and mock modules. The seals are
/// the fake crypto's: what is tried is the feed, not the cipher.

/// A device's feed, synced through a service: its own state, and a clock the test moves (`device`).
class Device {
  Device(this.service, [Fetcher? fetcher]) : api = apiOf(service, fetcher);
  final FakeService service;
  final Api api;
  FeedState state = FeedState.empty;
  int clock = 1000;

  /// The rows as the page lists them.
  List<FeedNotification> rows() => listedIn(state);
  FeedNotification? row(String id) => state.items[id];
  void mark(Mark mark) => state = withMark(state, mark, clock);
  Future<bool> sync() => syncNotifications(NotificationsContext(token: service.signedIn(), api: api, read: () => state, update: (change) => state = change(state), now: () => clock));
}

List<String> ids(Iterable<FeedNotification> rows) => [for (final n in rows) n.id];

Map<String, Object?>? detailsJson(NotificationDetails? d) =>
    d == null ? null : {'kind': d.kind, 'noteId': d.noteId, 'title': d.title, 'by': d.by, 'added': d.added, 'removed': d.removed, 'first': d.first, 'at': d.at};

void main() {
  late SignedAccount account;
  late MemoryStored kept;
  late NotificationFeed feed;
  const prefs = NotificationPrefs();
  const ghost = (id: 'o1', name: 'Ghost');

  NotificationFeed feedOf(FakeService service) {
    feed = NotificationFeed(account: account, crypto: service.crypto, kept: kept);
    addTearDown(feed.dispose);
    return feed;
  }

  setUp(() {
    account = SignedAccount(session: testSession);
    kept = MemoryStored();
  });

  group('what was read and hidden', () {
    test('reaches every device: read on the phone, hidden on the Mac, and both converge', () async {
      final service = await FakeService.start(seed: testAccount);
      final a = service.notifies(kind: 'member-joined', from: 'sam', org: ghost, at: 1);
      final b = service.notifies(kind: 'member-left', from: 'sam', org: ghost, at: 2);
      final phone = Device(service);
      final mac = Device(service);
      await phone.sync();
      await mac.sync();
      expect(ids(phone.rows()), [b.id, a.id]);
      expect(mac.rows(), hasLength(2));

      phone.mark(RowMark(a.id, read: true));
      expect(phone.row(a.id)?.readAt, 1000);
      mac.mark(RowMark(b.id, hidden: true));
      expect(ids(mac.rows()), [a.id]);
      await phone.sync();
      await mac.sync();
      await phone.sync();
      // Each took the other's change: the service fed the rows again at the revisions the marks made.
      expect(phone.row(b.id)?.hidden, isTrue);
      expect(ids(phone.rows()), [a.id]);
      expect(mac.row(a.id)?.readAt, isNotNull);
      expect(phone.state.marks, isEmpty);
      expect(mac.state.marks, isEmpty);
      expect(service.calls.where((c) => c.startsWith('PUT notifications/')), hasLength(2));
    });

    test('marks everything this device had been fed, and nothing fed since', () async {
      final service = await FakeService.start(seed: testAccount);
      final a = service.notifies(kind: 'member-joined', from: 'sam');
      final phone = Device(service);
      await phone.sync();
      phone.mark(AllMark(phone.state.cursor));
      final b = service.notifies(kind: 'member-left', from: 'sam');
      expect(phone.row(a.id)?.readAt, 1000);
      await phone.sync();
      // Confirmed, the row comes back with the service's own time on it.
      expect(phone.row(a.id)?.readAt, isNotNull);
      expect(phone.row(b.id)?.readAt, isNull);
      expect(service.feed[a.id]?.readAt, isNotNull);
      expect(service.feed[b.id]?.readAt, isNull);
    });

    test('keeps a mark made here over a row fed before the mark landed', () async {
      final service = await FakeService.start(seed: testAccount);
      final a = service.notifies(kind: 'member-joined', from: 'sam');
      FeedNotification again({required int rev, bool hidden = false}) => FeedNotification(id: a.id, rev: rev, kind: a.kind, at: a.at, from: a.from, hidden: hidden);
      // As a rule: a row fed at a higher revision is taken, with the pending mark laid over it again; a lower one
      // is not taken at all.
      var state = withFed(FeedState.empty, a, 1);
      state = withMark(state, RowMark(a.id, read: true), 5);
      final refed = withFed(state, again(rev: a.rev + 1), 6);
      expect((refed.items[a.id]!.rev, refed.items[a.id]!.readAt), (a.rev + 1, 6));
      expect(withFed(refed, again(rev: a.rev, hidden: true), 7), same(refed));

      // Live: read while the page carrying it unread is in flight.
      var raced = false;
      late final Device phone;
      phone = Device(service, (request) async {
        final response = await service.fetcher(request);
        if (request.url.path.endsWith('/notifications') && request.method == 'GET' && !raced) {
          raced = true;
          phone.mark(RowMark(a.id, read: true));
        }
        return response;
      });
      await phone.sync();
      expect(raced, isTrue);
      expect(phone.row(a.id)?.readAt, 1000);
      expect(phone.state.marks, hasLength(1));
      // The next pass replays it, and the service agrees.
      await phone.sync();
      expect(phone.state.marks, isEmpty);
      expect(service.feed[a.id]?.readAt, isNotNull);
      expect(phone.row(a.id)?.readAt, isNotNull);
    });
  });

  group('an invitation', () {
    test('arrives, is answered inline, and the answer reaches the service and the other device', () async {
      final service = await FakeService.start(seed: testAccount);
      final orgId = service.invited('Ghost', 'sam');
      final phone = Device(service);
      final mac = Device(service);
      await phone.sync();
      await mac.sync();
      final invite = phone.rows().single;
      expect((invite.kind, invite.from, invite.org, invite.state), ('invite', 'sam', (id: orgId, name: 'Ghost'), 'pending'));
      expect(isPendingInvite(invite), isTrue);
      phone.mark(InviteMark(orgId, answer: true));
      expect((phone.row(invite.id)?.state, phone.row(invite.id)?.readAt), ('accepted', 1000));
      await phone.sync();
      expect(service.rowIn(orgId), (role: 'member', state: 'member'));
      expect(service.calls, contains('POST orgs/$orgId/invite'));
      await mac.sync();
      expect(mac.row(invite.id)?.state, 'accepted');
    });

    test('answered elsewhere already, is read as done: the service’s "not invited" drops the mark and the pass goes on', () async {
      final service = await FakeService.start(seed: testAccount);
      final orgId = service.invited('Ghost', 'sam');
      final phone = Device(service);
      final mac = Device(service);
      await phone.sync();
      await mac.sync();
      mac.mark(InviteMark(orgId, answer: false));
      await mac.sync();
      expect(service.rowIn(orgId)?.state, 'declined');
      phone.mark(InviteMark(orgId, answer: true));
      expect(await phone.sync(), isTrue);
      expect(phone.state.marks, isEmpty);
      // The service's row, fed again at its new revision, says what the other device said.
      expect(phone.rows().first.state, 'declined');
    });

    test('is answered through whoever keeps the organizations, when they hand in the way', () async {
      // Not a case of the web's: there the answer always goes through core/orgs/orgs.ts; here that is handed in.
      final service = await FakeService.start(seed: testAccount);
      final orgId = service.invited('Ghost', 'sam');
      var state = FeedState.empty;
      final answers = <(String, bool)>[];
      Future<bool> sync() => syncNotifications(NotificationsContext(
            token: service.signedIn(),
            api: apiOf(service),
            read: () => state,
            update: (change) => state = change(state),
            answerInvite: (org, accept) async => answers.add((org, accept)),
          ));
      await sync();
      state = withMark(state, InviteMark(orgId, answer: true), 5);
      await sync();
      expect(answers, [(orgId, true)]);
      expect(state.marks, isEmpty);
      expect(service.calls, isNot(contains('POST orgs/$orgId/invite')));
    });
  });

  group('the two 404s', () {
    test('is quiet against a service without the routes yet, and changes nothing', () async {
      final service = await FakeService.start(seed: testAccount, teams: false);
      final phone = Device(service);
      phone.mark(const RowMark('x', read: true));
      expect(await phone.sync(), isFalse);
      expect(phone.state.cursor, 0);
      expect(phone.state.marks, const [RowMark('x', read: true)]);
    });

    test('surfaces a 404 in the service’s words, which is an answer', () async {
      final service = await FakeService.start(seed: testAccount);
      final phone = Device(service, (request) async {
        if (request.url.path.endsWith('/notifications') && request.method == 'GET') return FetchResponse.json(404, {'error': 'Nothing for you here.'});
        return service.fetcher(request);
      });
      await expectLater(phone.sync(), throwsA(isA<ApiError>().having((e) => e.message, 'message', 'Nothing for you here.')));
    });

    test('keeps its marks and unsent rows through any other failure, for the next pass', () async {
      final service = await FakeService.start(seed: testAccount);
      service.notifies(kind: 'member-joined', from: 'sam', id: 'a');
      final phone = Device(service);
      await phone.sync();
      phone.mark(const RowMark('a', read: true));
      final offline = Device(service, down);
      offline.mark(const RowMark('a', read: true));
      await expectLater(offline.sync(), throwsA(isA<ApiError>().having((e) => e.message, 'message', 'The service is down.')));
      expect(offline.state.marks, hasLength(1));
    });
  });

  group('a sealed row', () {
    const details = {'kind': 'note-edited', 'noteId': 'n1', 'title': 'Trip to Lisbon', 'by': 'Claude', 'added': 2, 'removed': 0, 'first': '- pack', 'at': 'l3'};

    Future<FeedNotification> sealed(FakeService service, String id, Object? payload) async =>
        service.notifies(kind: 'note-edited', id: id, blob: await service.crypto.seal(service.accountKey, payload, 'notification:$id'));

    /// The feed's listeners told [count] times: once per open that lands (`landed`).
    Future<void> landed(int count) {
      final done = Completer<void>();
      var told = 0;
      late void Function() hear;
      hear = () {
        told += 1;
        if (told == count) {
          feed.removeListener(hear);
          done.complete();
        }
      };
      feed.addListener(hear);
      return done.future;
    }

    test('is opened lazily, once, and the feed’s listeners hear when it lands', () async {
      final service = await FakeService.start(seed: testAccount);
      feedOf(service);
      account.key = service.accountKey;
      final row = await sealed(service, 'sealed', details);
      var told = 0;
      void count() => told += 1;
      feed.addListener(count);
      final one = landed(1);
      expect(feed.openDetails(row), isNull);
      expect(feed.openDetails(row), isNull);
      await one;
      expect(detailsJson(feed.openDetails(row)), details);
      expect(told, 1);
      feed.removeListener(count);
      // Waited for, it is the same answer, and no second open.
      expect(detailsJson(await feed.detailsFor(row)), details);
      expect(await feed.detailsFor(service.notifies(kind: 'member-joined', from: 'sam')), isNull);
    });

    test('never stalls on one that will not open: drawn by its kind, remembered as such, and the pass unaffected', () async {
      final service = await FakeService.start(seed: testAccount);
      feedOf(service);
      account.key = service.accountKey;
      final moved = await sealed(service, 'moved', details);
      // Sealed for another id: the context does not match, and the seal will not open.
      final stolen = FeedNotification(id: 'stolen', rev: moved.rev, kind: moved.kind, at: moved.at, blob: moved.blob);
      final rubbish = service.notifies(kind: 'note-created', id: 'rubbish', blob: 'not-a-seal');
      final wrongShape = await sealed(service, 'shape', {'hello': 'there'});
      final three = landed(3);
      expect(feed.openDetails(stolen), isNull);
      expect(feed.openDetails(rubbish), isNull);
      expect(feed.openDetails(wrongShape), isNull);
      await three;
      expect(feed.openDetails(stolen), isNull);
      expect(feed.openDetails(rubbish), isNull);
      expect(feed.openDetails(wrongShape), isNull);
      expect(await feed.detailsFor(stolen), isNull);
      final phone = Device(service);
      expect(await phone.sync(), isTrue);
      expect(phone.rows(), hasLength(3));
      // Without the key - a device that could not keep one - nothing opens, and nothing throws.
      account.key = null;
      feed.forgetOpened();
      final one = landed(1);
      expect(feed.openDetails(moved), isNull);
      await one;
      expect(feed.openDetails(moved), isNull);
    });

    test('is trusted for its kind over the row’s column', () {
      const row = FeedNotification(id: 'r', rev: 1, kind: 'summary-written', at: 1, blob: 'x');
      expect(sentenceOf(row, NotificationDetails.fromJson(details)), 'Claude edited Trip to Lisbon · 2 lines changed');
      expect(sentenceOf(row), 'A meeting was written up');
    });
  });

  group('what the page reads', () {
    test('lists the rows of the account signed in, newest first and never a hidden one, and counts the unread wanted ones', () async {
      final service = await FakeService.start(seed: testAccount);
      feedOf(service);
      final a = service.notifies(kind: 'member-joined', from: 'sam', org: ghost, at: 10);
      final b = service.notifies(kind: 'invite', from: 'sam', org: (id: 'o2', name: 'Boo'), state: 'pending', at: 20);
      final c = service.notifies(kind: 'summary-written', at: 30, readAt: 5);
      final d = service.notifies(kind: 'member-left', from: 'sam', org: ghost, at: 40, hidden: true);
      final phone = Device(service);
      await phone.sync();
      feed.saveFeed(7, phone.state);
      final rows = feed.notifications();
      expect(ids(rows), [c.id, b.id, a.id]);
      expect(feed.notifications(), same(rows));
      expect(unreadCount(prefs, rows), 2);
      // Team news off: the invitation still counts; an organization muted: its news does not.
      expect(unreadCount(prefs.copyWith(team: false), rows), 1);
      expect(unreadCount(prefs.copyWith(mutedOrgs: ['o1']), rows), 1);
      expect(isWanted(d, prefs), isTrue);
      expect(isWanted(c.copyWith(readAt: () => null), prefs.copyWith(summaries: false)), isFalse);
      var told = 0;
      feed.addListener(() => told += 1);
      account.session = null;
      account.notifyListeners();
      expect(told, 1);
      expect(feed.notifications(), isEmpty);
    });

    test('applies what the person did here at once, for the account signed in', () async {
      final service = await FakeService.start(seed: testAccount);
      feedOf(service);
      final a = service.notifies(kind: 'member-joined', from: 'sam', id: 'a');
      final orgId = service.invited('Ghost');
      final phone = Device(service);
      await phone.sync();
      feed.saveFeed(7, phone.state);
      feed.markRead('a');
      expect(feed.feedState(7).items['a']?.readAt, isNotNull);
      feed.hide('a');
      expect(feed.notifications().any((n) => n.id == a.id), isFalse);
      feed.answerInvite(orgId, false);
      expect(feed.notifications().first.state, 'declined');
      feed.markAllRead();
      expect(feed.feedState(7).marks, [const RowMark('a', read: true), const RowMark('a', hidden: true), InviteMark(orgId, answer: false), AllMark(phone.state.cursor)]);
      // Replayed by the next pass, and gone.
      await syncNotifications(feed.contextFor(7, token: service.signedIn(), api: apiOf(service)));
      expect(feed.feedState(7).marks, isEmpty);
      expect(service.feed['a']?.hidden, isTrue);
      expect(service.rowIn(orgId)?.state, 'declined');
    });

    test('marks every row it holds read, one held above its cursor included (docs/DESIGN.md §177)', () async {
      final service = await FakeService.start(seed: testAccount);
      feedOf(service);
      service.notifies(kind: 'member-joined', from: 'sam', id: 'a');
      service.notifies(kind: 'member-joined', from: 'priya', id: 'b');
      final phone = Device(service);
      await phone.sync();
      // A row fed by a page whose cursor never landed: above the cursor this device holds.
      final b = phone.state.items['b']!;
      final above = FeedNotification(id: b.id, rev: phone.state.cursor + 5, kind: b.kind, at: b.at, from: b.from);
      feed.saveFeed(7, phone.state.copyWith(items: {...phone.state.items, 'b': above}));
      feed.markAllRead();
      expect(feed.notifications().every((n) => n.readAt != null), isTrue);
      expect(feed.feedState(7).marks, [AllMark(phone.state.cursor + 5)]);
    });

    test('clears several rows out of the list as one change, each hidden on the service by the next pass', () async {
      final service = await FakeService.start(seed: testAccount);
      feedOf(service);
      service.notifies(kind: 'member-joined', from: 'sam', id: 'a', at: 3);
      service.notifies(kind: 'member-joined', from: 'priya', id: 'b', at: 2);
      service.notifies(kind: 'member-joined', from: 'alex', id: 'c', at: 1);
      final phone = Device(service);
      await phone.sync();
      feed.saveFeed(7, phone.state);
      var told = 0;
      feed.addListener(() => told += 1);
      feed.hideAll(['a', 'b']);
      expect(told, 1);
      expect(ids(feed.notifications()), ['c']);
      expect(feed.feedState(7).marks, const [RowMark('a', hidden: true), RowMark('b', hidden: true)]);
      await syncNotifications(feed.contextFor(7, token: service.signedIn(), api: apiOf(service)));
      expect(feed.feedState(7).marks, isEmpty);
      expect(service.feed['a']?.hidden, isTrue);
      expect(service.feed['b']?.hidden, isTrue);
      expect(service.feed['c']?.hidden, isFalse);
    });

    test('forgets an account’s feed, and keeps another’s', () async {
      feedOf(await FakeService.start(seed: testAccount));
      feed.saveFeed(7, FeedState.empty.copyWith(cursor: 4));
      feed.saveFeed(8, FeedState.empty.copyWith(cursor: 9));
      feed.forgetNotifications(7);
      expect(feed.feedState(7).cursor, 0);
      expect(feed.feedState(8).cursor, 9);
    });

    test('is kept on this device for the next launch: rows, marks and what is unsent, and nothing it cannot read', () async {
      // Not a case of the web's file: there the storage is tried through every other case's module state.
      final service = await FakeService.start(seed: testAccount);
      feedOf(service);
      service.notifies(kind: 'member-joined', from: 'sam', org: ghost, id: 'a', body: {'name': 'Ghost'});
      service.notifies(kind: 'a-kind-from-next-year', id: 'new');
      final phone = Device(service);
      await phone.sync();
      feed.saveFeed(7, withSelfRow(phone.state, const FeedNotification(id: 'mine', kind: 'sync-conflict', at: 9, blob: 'sealed')));
      feed.markRead('a');
      feed.answerInvite('o9', true);
      feed.markAllRead();
      // The next launch: another feed over the same memory.
      final next = NotificationFeed(account: account, crypto: service.crypto, kept: kept);
      addTearDown(next.dispose);
      final state = next.feedState(7);
      expect(state.cursor, phone.state.cursor);
      expect(state.items.keys, ['a', 'new', 'mine']);
      expect(state.items['a']!.org, ghost);
      expect(state.items['a']!.body, {'name': 'Ghost'});
      expect(state.marks, [const RowMark('a', read: true), const InviteMark('o9', answer: true), AllMark(phone.state.cursor)]);
      expect(state.unsent, ['mine']);
      // A row of a kind this build does not know is kept, and not drawn.
      expect(ids(next.notifications()), isNot(contains('new')));
      // Rubbish where the feed was is no feed; rubbish inside it is left out.
      kept.setItem('glyph-sync-8-notifications', '"nonsense"');
      expect(next.feedState(8).cursor, 0);
      final read = FeedState.fromJson({
        'cursor': 'four',
        'items': {'x': {'id': 'x', 'kind': 'invite', 'at': 1}, 'y': {'id': 'y'}, 'z': 7},
        'marks': [{'id': 'x', 'read': true}, {'all': true}, {'org': 'o1', 'answer': 'yes'}, 'nope', {'all': true, 'before': 3}],
        'unsent': ['x', 'gone', 4],
      })!;
      expect(read.cursor, 0);
      expect(read.items.keys, ['x']);
      expect(read.marks, const [RowMark('x', read: true), AllMark(3)]);
      expect(read.unsent, ['x']);
    });
  });

  group('reading the feed a page at a time', () {
    test('takes every row, moving the cursor a page at a time to the account’s head', () async {
      // Not a case of the web's file: its feeds fit one page.
      final service = await FakeService.start(seed: testAccount);
      for (var i = 0; i < 7; i += 1) {
        service.notifies(kind: 'member-joined', from: 'sam', id: 'n$i', at: i);
      }
      var state = FeedState.empty;
      final cursors = <int>[];
      final done = await syncNotifications(NotificationsContext(
        token: service.signedIn(),
        api: apiOf(service),
        read: () => state,
        update: (change) {
          state = change(state);
          cursors.add(state.cursor);
        },
        limit: 3,
      ));
      expect(done, isTrue);
      expect(cursors, [3, 6, 7]);
      expect(state.items, hasLength(7));
      expect(service.calls, ['GET notifications', 'GET notifications', 'GET notifications']);
    });
  });

  group('the rows a pass brought', () {
    test('are told to everyone who asked, and a listener that fails stops neither the others nor the pass', () async {
      // lib/sync/arrived.dart, which the web tries through its plugins' tests.
      final heard = <String>[];
      final stopOne = onArrived((before, rows) => throw StateError('mine to deal with'));
      final stopTwo = onArrived((before, rows) async => throw StateError('later, and still mine'));
      final stopThree = onArrived((before, rows) => heard.add('$before:${ids(rows).join(',')}'));
      const rows = [FeedNotification(id: 'a', kind: 'invite', at: 1, rev: 4)];
      await runZonedGuarded(() async {
        tellArrived(3, rows);
        await pumpEventQueue();
      }, (error, stack) => fail('A listener’s failure got out: $error'));
      expect(heard, ['3:a']);
      stopThree();
      tellArrived(4, rows);
      expect(heard, ['3:a']);
      stopOne();
      stopTwo();
    });
  });
}
