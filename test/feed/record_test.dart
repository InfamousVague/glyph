import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/sync/feed.dart';
import 'package:ghost_md/sync/record.dart';

import '../support/fake_service.dart';
import 'signed.dart';

/// A self notification recorded (lib/sync/record.dart): sealed with the kind inside, in the feed here before the
/// post is made, and listed as unsent until the post lands - which the next pass does again, and the service
/// answers the same for an id it already has. The web's `src/app/core/notifications/record.test.ts`, case for case.
void main() {
  late SignedAccount account;
  late FakeService service;
  late NotificationFeed feed;
  late SelfNotifications self;
  var localOnly = false;

  setUp(() async {
    service = await FakeService.start(seed: testAccount);
    account = SignedAccount()..signIn(service);
    feed = NotificationFeed(account: account, crypto: service.crypto, kept: MemoryStored());
    addTearDown(feed.dispose);
    localOnly = false;
    self = SelfNotifications(feed: feed, api: apiOf(service), localOnly: () => localOnly);
  });

  Future<bool> sync() => syncNotifications(feed.contextFor(7, token: service.signedIn(), api: apiOf(service)));

  group('recording a notification', () {
    test('seals the kind and the details under the account key, keeps the row here, and posts it', () async {
      await self.record('summary-written', {'noteId': 'n1', 'title': 'Standup'}, now: () => 42);
      final row = feed.notifications().single;
      expect((row.kind, row.at, row.readAt, row.hidden), ('summary-written', 42, null, false));
      expect(row.id, hasLength(22));
      expect(row.rev, greaterThan(0));
      expect(feed.feedState(7).unsent, isEmpty);
      expect(service.calls, ['POST notifications']);
      // What the service holds opens only as this notification, and says what it is inside.
      final stored = service.feed[row.id]!;
      expect(await service.crypto.open(service.accountKey, stored.blob!, 'notification:${row.id}'), {'kind': 'summary-written', 'noteId': 'n1', 'title': 'Standup'});
      await expectLater(service.crypto.open(service.accountKey, stored.blob!, 'notification:other'), throwsA(anything));
      // Already opened here: never asked of the seal.
      account.key = null;
      final opened = feed.openDetails(row)!;
      expect((opened.kind, opened.noteId, opened.title), ('summary-written', 'n1', 'Standup'));
    });

    test('keeps the row as unsent when the post fails, and the next pass sends it, clearing it', () async {
      await self.record('sync-conflict', {'noteId': 'n2', 'title': 'Trip to Lisbon'}, api: apiOf(service, down));
      final row = feed.notifications().single;
      expect((row.kind, row.rev), ('sync-conflict', 0));
      expect(feed.feedState(7).unsent, [row.id]);
      await sync();
      expect(feed.feedState(7).unsent, isEmpty);
      expect(feed.feedState(7).items[row.id]?.rev, 1);
      expect(service.feed.containsKey(row.id), isTrue);
    });

    test('is idempotent: a post sent again for an id the service has answers the same revision and writes nothing', () async {
      // The answer is lost on the way back: the row is unsent here though the service has it.
      Future<FetchResponse> lossy(FetchRequest request) async {
        await service.fetcher(request);
        throw const FormatException('Failed to fetch');
      }

      await self.record('summary-written', {'noteId': 'n1', 'title': 'Standup'}, api: apiOf(service, lossy));
      final row = feed.notifications().single;
      expect(feed.feedState(7).unsent, [row.id]);
      final rev = service.feed[row.id]!.rev;
      await sync();
      expect(feed.feedState(7).unsent, isEmpty);
      expect(feed.feedState(7).items[row.id]?.rev, rev);
      expect(service.feed, hasLength(1));
      expect(feed.notifications(), hasLength(1));
    });

    test('records nothing signed out or without the key, and keeps the row here alone under Local only', () async {
      account.key = null;
      await self.record('summary-written', {'noteId': 'n1', 'title': 'Standup'});
      expect(feed.notifications(), isEmpty);
      account.key = service.accountKey;
      final was = account.session;
      account.session = null;
      await self.record('summary-written', {'noteId': 'n1', 'title': 'Standup'});
      account.session = was;
      expect(feed.notifications(), isEmpty);
      localOnly = true;
      await self.record('summary-written', {'noteId': 'n1', 'title': 'Standup'});
      expect(feed.notifications(), hasLength(1));
      expect(service.calls, isEmpty);
      // Nor anything no device could draw: a kind the service makes, or no note to name.
      await self.record('invite', {'noteId': 'n1', 'title': 'Standup'});
      await self.record('summary-written', {'title': 'Standup'});
      expect(feed.notifications(), hasLength(1));
    });

    test('marks a row read here before its post landed on the service too, so it does not come back unread', () async {
      await self.record('summary-written', {'noteId': 'n1', 'title': 'Standup'}, api: apiOf(service, down));
      final row = feed.notifications().single;
      feed.markRead(row.id);
      await sync();
      expect(service.feed[row.id]?.readAt, isNotNull);
      expect(feed.feedState(7).items[row.id]?.readAt, isNotNull);
      // The mark goes first and meets a row the service does not have yet (its 404 is an answer, and drops it);
      // then the row is posted, and what was done to it here is said again.
      expect(service.calls, ['PUT notifications/${row.id}', 'POST notifications', 'PUT notifications/${row.id}', 'GET notifications']);
    });
  });
}
