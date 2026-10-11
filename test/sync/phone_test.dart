// The bell's rows as the phone's own notifications (lib/sync/phone.dart), against a stand-in for the phone: what is
// posted while the app is in the background, and the watch the closed app's worker is handed. A port of
// `src/app/core/notifications/phone.test.ts`, case for case, with the account, the feed and the preferences handed in
// where the page's tests mock and reset modules. The last groups are this port's own: a whole engine against the
// service in memory, with the rows it brings posted and the watch moved on, and the channel the phone answers on.
// That it is made only for the service a build was given is test/root/wiring_test.dart's.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/keystore.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/notifications.dart';
import 'package:ghost_md/core/phone_notices.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/org_keys.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/feed.dart';
import 'package:ghost_md/sync/notes.dart';
import 'package:ghost_md/sync/phone.dart';
import 'package:ghost_md/sync/record.dart';

import '../feed/signed.dart' show SignedAccount;
import '../support/fake_phone.dart';
import 'support.dart';

var _ids = 0;

FeedNotification row({
  String? id,
  int rev = 10,
  required String kind,
  int? readAt,
  bool hidden = false,
  String? from = 'sam',
  NotificationOrg? org = (id: 'org1', name: 'Ghost'),
  Map<String, Object?>? body = const {'name': 'Ghost'},
  String? blob,
  String? state,
}) =>
    FeedNotification(id: id ?? 'n${_ids++}', rev: rev, kind: kind, at: 1, readAt: readAt, hidden: hidden, from: from, org: org, body: body, blob: blob, state: state);

/// The account as the engine asks it, signed in to the service or out.
class EngineAccount extends ChangeNotifier implements SyncAccount {
  EngineAccount(this.session, this.key);

  @override
  Session? session;
  SealKey? key;

  @override
  Future<SealKey?> accountKey() async => key;

  @override
  Future<void> resume() async {}

  @override
  Future<void> signOut() async {
    session = null;
    notifyListeners();
  }

  @override
  Future<void> deleteAccount(String password) async => signOut();
}

void main() {
  late SignedAccount account;
  late MemoryStored kept;
  late PreferencesStore prefs;
  late NotificationFeed feed;
  late FakePhone phone;
  late PhoneNotices notices;
  var behind = true;

  setUp(() async {
    final service = await FakeService.start(seed: testAccount);
    // Signed in as matt; no account key, so a sealed row is worded by its kind.
    account = SignedAccount(session: const Session(token: 'tok', handle: 'matt', accountId: 7));
    kept = MemoryStored();
    prefs = PreferencesStore()..startWithoutStorage();
    feed = NotificationFeed(account: account, crypto: service.crypto, kept: kept);
    phone = FakePhone();
    behind = true;
    notices = PhoneNotices(host: phone, account: account, feed: feed, prefs: prefs, base: 'http://service.test/api', kept: kept, hidden: () => behind);
    addTearDown(() {
      notices.dispose();
      feed.dispose();
    });
  });

  NotificationPrefs wanted() => prefs.value.notifications;
  void mute(List<String> orgs) => prefs.update((now) => now.copyWith(notifications: now.notifications.copyWith(mutedOrgs: orgs)));

  group('a row on the phone', () {
    test('is what the bell counts, less a meeting and a conflict, which have their own', () {
      expect(postsToPhone(row(kind: 'member-joined'), wanted()), isTrue);
      expect(postsToPhone(row(kind: 'note-edited', org: null, body: null, blob: 'x'), wanted()), isTrue);
      expect(postsToPhone(row(kind: 'invite', state: 'pending'), wanted()), isTrue);
      expect(postsToPhone(row(kind: 'invite', state: 'accepted'), wanted()), isFalse);
      expect(postsToPhone(row(kind: 'summary-written'), wanted()), isFalse);
      expect(postsToPhone(row(kind: 'sync-conflict'), wanted()), isFalse);
      expect(postsToPhone(row(kind: 'member-joined', readAt: 5), wanted()), isFalse);
      expect(postsToPhone(row(kind: 'member-joined', hidden: true), wanted()), isFalse);
      expect(postsToPhone(row(kind: 'a-kind-from-a-newer-build'), wanted()), isFalse);
      mute(['org1']);
      expect(postsToPhone(row(kind: 'member-joined'), wanted()), isFalse);
      expect(postsToPhone(row(kind: 'invite'), wanted()), isTrue, reason: 'an invitation is never muted');
    });

    test('opens the note Claude changed, the organization while it is yours, or the drawer', () {
      expect(linkFor(row(kind: 'note-edited'), 'note-1'), 'ghostmd://note/note-1');
      expect(linkFor(row(kind: 'member-joined'), null), 'ghostmd://org/org1');
      expect(linkFor(row(kind: 'invite'), null), 'ghostmd://notifications');
      expect(linkFor(row(kind: 'org-deleted'), null), 'ghostmd://notifications');
      expect(linkFor(row(kind: 'member-removed'), null), 'ghostmd://notifications');
      expect(linkFor(row(kind: 'member-removed', body: const {'name': 'Ghost', 'handle': 'kim'}), null), 'ghostmd://org/org1');
      expect(linkFor(row(kind: 'note-created', org: null), null), 'ghostmd://notifications');
    });
  });

  group('posting a pass’s rows', () {
    test('posts the new ones, oldest first, in the bell’s words, while the app is in the background', () async {
      final rows = [
        row(id: 'b', rev: 12, kind: 'member-joined'),
        row(id: 'a', rev: 11, kind: 'note-edited', org: null, body: null, blob: 'sealed'),
        row(id: 'old', rev: 9, kind: 'member-left'),
      ];
      expect(await notices.postNewRows(10, rows), 2);
      expect(phone.posted, [
        // No line under its title: no `text` at all, since Android reads a JSON null as the word "null".
        {'id': 'a', 'title': 'Claude edited a note', 'link': 'ghostmd://notifications'},
        {'id': 'b', 'title': 'sam joined Ghost', 'text': 'Ghost', 'link': 'ghostmd://org/org1'},
      ]);
    });

    test('posts nothing with the app in front, on a device’s first look, or with the switch off', () async {
      final rows = [row(rev: 12, kind: 'member-joined')];
      behind = false;
      expect(await notices.postNewRows(10, rows), 0);
      behind = true;
      expect(await notices.postNewRows(0, rows), 0);
      await notices.setOn(false);
      expect(notices.on, isFalse);
      expect(kept.readText(phoneNoticesKey), 'off');
      expect(await notices.postNewRows(10, rows), 0);
      expect(phone.posted, isEmpty);
    });

    test('posts nothing where the binary cannot', () async {
      phone.there = false;
      expect(await notices.postNewRows(10, [row(rev: 12, kind: 'member-joined')]), 0);
    });

    test('posts nothing the switches or a mute keep from the bell', () async {
      prefs.update((now) => now.copyWith(notifications: now.notifications.copyWith(claude: false, mutedOrgs: ['org1'])));
      final rows = [
        row(id: 'team', rev: 11, kind: 'member-joined'),
        row(id: 'claude', rev: 12, kind: 'rule-added', org: null, body: null, blob: 'sealed'),
        row(id: 'ask', rev: 13, kind: 'invite', state: 'pending'),
      ];
      expect(await notices.postNewRows(10, rows), 1);
      expect(phone.posted.single, {'id': 'ask', 'title': 'sam invited you to Ghost', 'text': 'Ghost', 'link': 'ghostmd://notifications'});
    });
  });

  group('the closed app’s watch', () {
    test('hands the session, the cursor and the switches, once while nothing changes', () async {
      feed.saveFeed(7, FeedState.empty.copyWith(cursor: 42));
      await notices.syncWatch();
      await notices.syncWatch();
      expect(phone.watches, hasLength(1));
      // The service is the one this build was given: there is none built in.
      expect(jsonDecode(phone.watches[0]), {'api': 'http://service.test/api', 'token': 'tok', 'accountId': 7, 'cursor': 42, 'team': true, 'claude': true, 'mutedOrgs': <Object?>[]});
      prefs.update((now) => now.copyWith(notifications: now.notifications.copyWith(claude: false)));
      await notices.syncWatch();
      expect((jsonDecode(phone.watches[1]) as Map)['claude'], isFalse);
      expect(notices.shown.value, NoticesState.on);
    });

    test('stops on signing out, on Local only, and with the switch off', () async {
      await notices.syncWatch();
      account.session = null;
      await notices.syncWatch();
      expect(phone.watches.last, '');
      expect(notices.shown.value, NoticesState.off);
      account.session = const Session(token: 'tok', handle: 'matt', accountId: 7);
      await notices.syncWatch();
      expect(phone.watches.last, isNot(''));
      prefs.update((now) => now.copyWith(localOnly: true));
      await notices.syncWatch();
      expect(phone.watches.last, '');
      prefs.update((now) => now.copyWith(localOnly: false));
      await notices.syncWatch();
      await notices.setOn(false);
      expect(phone.watches.last, '');
    });

    test('tries again on a binary that could not take it', () async {
      phone.there = false;
      await notices.syncWatch();
      expect(notices.shown.value, isNull);
      phone.there = true;
      await notices.syncWatch();
      expect(phone.watches, hasLength(1));
    });

    test('is handed in the order asked, each as things stand at its turn', () async {
      // Three asks in one breath: signed in, out, in again. The phone ends watching, having heard no stale one last.
      final first = notices.syncWatch();
      account.session = null;
      final second = notices.syncWatch();
      account.session = const Session(token: 'tok2', handle: 'matt', accountId: 7);
      final third = notices.syncWatch();
      await Future.wait([first, second, third]);
      expect((jsonDecode(phone.watches.last) as Map)['token'], 'tok2');
      expect(notices.shown.value, NoticesState.on);
    });

    test('reads what Android says now, for the row in Settings', () async {
      expect(notices.shown.value, isNull);
      phone.current = NoticesState.blocked;
      expect(await notices.read(), NoticesState.blocked);
      expect(notices.shown.value, NoticesState.blocked);
      phone.current = NoticesState.on;
      await notices.read();
      expect(notices.shown.value, NoticesState.on);
    });

    test('asks the phone to let it notify, and reads what Android says again', () async {
      phone.current = NoticesState.blocked;
      await notices.read();
      // Android may already show them by the time the ask has answered (a prompt answered at once, a permission
      // given in the phone's settings meanwhile): the row follows without waiting for its next look.
      phone.current = NoticesState.on;
      expect(await notices.allow(), isTrue);
      expect(phone.allows, 1);
      expect(notices.shown.value, NoticesState.on);
      // Where no prompt can change it, it says so.
      phone
        ..current = NoticesState.blocked
        ..prompts = false;
      expect(await notices.allow(), isFalse);
      expect(notices.shown.value, NoticesState.blocked);
    });
  });

  group('a whole engine against the service in memory', () {
    late FakeService service;
    late EngineAccount signed;
    late SyncEngine engine;
    late NotificationFeed fed;
    late PhoneNotices heard;

    Future<void> make() async {
      service = await FakeService.start(seed: testAccount);
      signed = EngineAccount(Session(token: service.signedIn(), handle: 'matt', accountId: 7), service.accountKey);
      final api = apiOf(service);
      fed = NotificationFeed(account: signed, crypto: service.crypto, kept: kept);
      final workspaces = WorkspaceStore(storage: KeptWorkspaceStorage(prefs: prefs, stored: kept));
      final orgs = Orgs(account: signed, api: api, workspaces: workspaces, kept: kept);
      engine = SyncEngine(
        account: signed,
        api: api,
        crypto: service.crypto,
        keys: MemoryKeyStore(),
        prefs: prefs,
        notes: DeviceNotes(),
        files: DeviceFiles(),
        feed: fed,
        orgs: orgs,
        orgKeys: OrgKeys(crypto: service.crypto, api: api),
        record: SelfNotifications(feed: fed, api: api),
        kept: kept,
        // The feed's pass is the real one; the notes and the settings are not what is tried here.
        notesPass: (_) async => Outcome(),
        prefsPass: (_) async => false,
        orgsPass: (_) async => null,
      );
      heard = PhoneNotices(host: phone, account: signed, feed: fed, prefs: prefs, base: 'http://service.test/api', kept: kept, hidden: () => behind)..start();
      addTearDown(() {
        heard.dispose();
        engine.dispose();
        fed.dispose();
      });
    }

    /// The rows a pass tells of are posted a moment after it ends, and the watch after them.
    Future<void> settled() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('a device’s first look posts nothing, and hands the worker the cursor it reached', () async {
      await make();
      service.notifies(kind: 'member-joined', from: 'sam', org: (id: 'o1', name: 'Ghost'));
      await engine.syncNotificationsNow();
      await settled();
      expect(phone.posted, isEmpty, reason: 'its whole history is not news');
      final watch = jsonDecode(phone.watches.single) as Map;
      expect(watch['api'], 'http://service.test/api');
      expect(watch['token'], signed.session!.token);
      expect(watch['cursor'], fed.feedState(7).cursor);
      expect(watch['cursor'], greaterThan(0));
    });

    test('what the next pass brings is posted in the bell’s words, a Claude row opened with the account key, and the watch moves on', () async {
      await make();
      service.notifies(kind: 'member-joined', from: 'sam', org: (id: 'o1', name: 'Ghost'));
      await engine.syncNotificationsNow();
      await settled();
      final before = fed.feedState(7).cursor;

      final left = service.notifies(kind: 'member-left', from: 'kim', org: (id: 'o1', name: 'Ghost'));
      final blob = await service.crypto.seal(service.accountKey, {'kind': 'note-edited', 'noteId': 'n-trip', 'title': 'Trip to Lisbon', 'by': 'Claude', 'added': 2, 'removed': 1, 'first': 'Book the train'}, 'notification:claude1');
      service.notifies(kind: 'note-edited', id: 'claude1', blob: blob);
      final answered = service.notifies(kind: 'invite', from: 'sam', org: (id: 'o2', name: 'Attic'), state: 'accepted');
      await engine.syncNotificationsNow();
      await settled();

      expect(phone.posted, [
        {'id': left.id, 'title': 'kim left Ghost', 'text': 'Ghost', 'link': 'ghostmd://org/o1'},
        {'id': 'claude1', 'title': 'Claude edited Trip to Lisbon · 3 lines changed', 'text': 'Book the train', 'link': 'ghostmd://note/n-trip'},
      ]);
      expect(phone.posted.map((p) => p['id']), isNot(contains(answered.id)), reason: 'an invitation answered asks nothing');
      final watch = jsonDecode(phone.watches.last) as Map;
      expect(watch['cursor'], greaterThan(before));
      expect(watch['cursor'], fed.feedState(7).cursor);
    });

    test('nothing is posted with the app in front, and the worker is still told where the feed is', () async {
      await make();
      // Something to have looked at first: a feed never fed is still at its first look.
      service.notifies(kind: 'org-renamed', from: 'sam', org: (id: 'o1', name: 'Ghost'), body: const {'name': 'Ghost', 'was': 'Old'});
      await engine.syncNotificationsNow();
      await settled();
      service.notifies(kind: 'member-joined', from: 'sam', org: (id: 'o1', name: 'Ghost'));
      await engine.syncNotificationsNow();
      await settled();
      final seen = phone.watches.length;
      behind = false;
      service.notifies(kind: 'member-left', from: 'sam', org: (id: 'o1', name: 'Ghost'));
      await engine.syncNotificationsNow();
      await settled();
      expect(phone.posted, hasLength(1), reason: 'only the one that came while the app was behind another');
      expect(phone.watches.length, greaterThan(seen));
    });

    test('signing out takes the session back from the phone', () async {
      await make();
      await engine.syncNotificationsNow();
      await settled();
      expect(phone.watches.last, isNot(''));
      await signed.signOut();
      await settled();
      expect(phone.watches.last, '');
      expect(heard.shown.value, NoticesState.off);
    });

    test('a mute made in Settings reaches the worker without waiting for a pass', () async {
      await make();
      await engine.syncNotificationsNow();
      await settled();
      mute(['o1']);
      await settled();
      expect((jsonDecode(phone.watches.last) as Map)['mutedOrgs'], ['o1']);
    });
  });

  group('the phone’s half', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <MethodCall>[];
    Object? answer;

    setUp(() {
      calls.clear();
      answer = 'on';
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(noticesChannel, (call) async {
        calls.add(call);
        return answer;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(noticesChannel, null));
    });

    test('is asked over its channel on Android, in the page’s own words', () async {
      const host = PhoneNoticesHost(android: true);
      expect(await host.watch('{"api":"x"}'), NoticesState.on);
      expect(calls.last.method, 'watch');
      expect(calls.last.arguments, {'json': '{"api":"x"}'});
      answer = 'blocked';
      expect(await host.state(), NoticesState.blocked);
      expect(calls.last.method, 'state');
      answer = 'posted';
      expect(await host.post((id: 'a', title: 'sam joined Ghost', text: null, link: 'ghostmd://org/o1')), isTrue);
      // No `text` at all for a row with no line under its title: never a JSON null, which Android reads as "null".
      expect(jsonDecode((calls.last.arguments as Map)['json'] as String), {'id': 'a', 'title': 'sam joined Ghost', 'link': 'ghostmd://org/o1'});
      answer = 'seen';
      expect(await host.post((id: 'a', title: 't', text: '  ', link: '')), isTrue);
      expect((jsonDecode((calls.last.arguments as Map)['json'] as String) as Map).containsKey('text'), isFalse);
      answer = 'blocked';
      expect(await host.post((id: 'a', title: 't', text: 'under', link: '')), isFalse);
      answer = 'something this build does not know';
      expect(await host.state(), isNull);
    });

    // Settings › Notifications' Allow (docs/PARITY.md, found beside 3): the phone's own prompt, asked for on the
    // notices' channel, which is there whether or not a recorder or a meeting's host has been made.
    test('is asked for Android’s prompt on the same channel: allowed and asked are a yes, blocked is not', () async {
      const host = PhoneNoticesHost(android: true);
      answer = 'asked';
      expect(await host.allow(), isTrue);
      expect(calls.last.method, 'allow');
      answer = 'allowed';
      expect(await host.allow(), isTrue);
      answer = 'blocked';
      expect(await host.allow(), isFalse);
      // Anywhere else, and on a build whose phone has no half, nothing is asked and nothing can be allowed.
      final before = calls.length;
      expect(await const PhoneNoticesHost(android: false).allow(), isFalse);
      expect(calls, hasLength(before));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(noticesChannel, null);
      expect(await host.allow(), isFalse);
    });

    test('answers nothing anywhere else, and asks nothing', () async {
      const host = PhoneNoticesHost(android: false);
      expect(await host.watch('{}'), isNull);
      expect(await host.state(), isNull);
      expect(await host.post((id: 'a', title: 't', text: null, link: '')), isFalse);
      expect(calls, isEmpty);
    });

    test('answers nothing on a build whose phone has no half yet', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(noticesChannel, null);
      const host = PhoneNoticesHost(android: true);
      expect(await host.watch('{}'), isNull);
      expect(await host.state(), isNull);
      expect(await host.post((id: 'a', title: 't', text: null, link: '')), isFalse);
    });
  });
}
