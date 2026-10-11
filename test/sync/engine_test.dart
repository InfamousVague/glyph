// Sync as the app runs it (lib/sync/engine.dart). A port of `src/app/core/sync/engine.test.tsx`, case for case: when
// a pass runs, that only one runs at a time with exactly one queued behind it, what stops it running at all, what
// the Account page is told, and what signing out forgets. A pass itself - notes.dart and prefs.dart - is proved
// against the service in memory elsewhere; here each is a stand-in the test drives, and the account is a session the
// test hands out. The last groups are this port's own: the hook step 5 is, and two whole engines on one service.
//
// Two of the web's cases are about its own device files (`recording_digest`, `sync_put_file`), which here are
// `KeptFiles` over whatever holds the bytes: local_test.dart has them.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/account/keystore.dart';
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/core/kept_workspaces.dart';
import 'package:ghost_md/core/locale_dates.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/org_keys.dart';
import 'package:ghost_md/orgs/orgs.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/feed.dart';
import 'package:ghost_md/sync/notes.dart';
import 'package:ghost_md/sync/prefs.dart';
import 'package:ghost_md/sync/record.dart';

import 'support.dart';

/// The account as the test hands it out, with what the engine asked of it counted.
class TestAccount extends ChangeNotifier implements SyncAccount {
  TestAccount(this.session, this.key);

  @override
  Session? session;
  SealKey? key;
  int resumes = 0;
  int signOuts = 0;
  final List<String> deleted = [];

  @override
  Future<SealKey?> accountKey() async => key;

  @override
  Future<void> resume() async => resumes += 1;

  @override
  Future<void> signOut() async {
    signOuts += 1;
    session = null;
    notifyListeners();
  }

  @override
  Future<void> deleteAccount(String password) async {
    deleted.add(password);
    session = null;
    notifyListeners();
  }
}

class Recorded extends SelfNotifications {
  Recorded({required super.feed, required super.api});
  final List<({String kind, Map<String, Object?> details})> made = [];

  @override
  Future<void> record(String kind, Map<String, Object?> details, {Api? api, int Function()? now}) async => made.add((kind: kind, details: details));
}

/// Everything an engine is made with, and the stand-ins the test drives.
class Rig {
  Rig._(this.service, {bool standIns = true, bool signedIn = true, Session? as, LocalNotes? notes, LocalFiles? files, TeamNotesPass? teamNotes}) {
    prefs.startWithoutStorage();
    account = TestAccount(signedIn ? (as ?? testSession) : null, service.accountKey);
    api = apiOf(service);
    feed = NotificationFeed(account: account, crypto: service.crypto, kept: kept, now: () => clock);
    workspaces = WorkspaceStore(storage: KeptWorkspaceStorage(prefs: prefs, stored: kept));
    orgs = Orgs(account: account, api: api, workspaces: workspaces, kept: kept);
    orgKeys = OrgKeys(crypto: service.crypto, api: api);
    recorded = Recorded(feed: feed, api: api);
    engine = SyncEngine(
      account: account,
      api: api,
      crypto: service.crypto,
      keys: keys,
      prefs: prefs,
      notes: notes ?? DeviceNotes(),
      files: files ?? DeviceFiles(),
      feed: feed,
      orgs: orgs,
      orgKeys: orgKeys,
      record: recorded,
      kept: kept,
      now: () => clock,
      touched: touched,
      onNotesChanged: () => told += 1,
      ready: () async => ready,
      teamNotes: teamNotes,
      notesPass: standIns
          ? (ctx) {
              passes.add(ctx);
              return notesPass(ctx);
            }
          : null,
      prefsPass: standIns ? (ctx) => prefsPass(ctx) : null,
      feedPass: standIns ? (ctx) => feedPass(ctx) : null,
      orgsPass: standIns ? (ctx) => orgsPass(ctx) : null,
    );
  }

  static Future<Rig> make({FakeService? service, bool standIns = true, bool signedIn = true, Session? as, LocalNotes? notes, LocalFiles? files, TeamNotesPass? teamNotes}) async =>
      Rig._(service ?? await FakeService.start(seed: testAccount), standIns: standIns, signedIn: signedIn, as: as, notes: notes, files: files, teamNotes: teamNotes);

  final FakeService service;
  final MemoryStored kept = MemoryStored();
  final PreferencesStore prefs = PreferencesStore();
  final MemoryKeyStore keys = MemoryKeyStore();
  final ValueNotifier<int> touched = ValueNotifier<int>(0);
  late final TestAccount account;
  late final Api api;
  late final NotificationFeed feed;
  late final WorkspaceStore workspaces;
  late final Orgs orgs;
  late final OrgKeys orgKeys;
  late final Recorded recorded;
  late final SyncEngine engine;

  int clock = 0;
  bool ready = true;

  /// How many times the list was told to read again.
  int told = 0;

  /// Every notes pass the engine ran, with what it was given.
  final List<SyncContext> passes = [];

  /// How each step goes: at once and changing nothing, unless a test says otherwise.
  Future<Outcome> Function(SyncContext ctx) notesPass = (_) async => Outcome();
  Future<bool> Function(PrefsContext ctx) prefsPass = (_) async => false;
  Future<bool> Function(NotificationsContext ctx) feedPass = (_) async => true;
  Future<List<OrgRow>?> Function(OrgsContext ctx) orgsPass = (_) async => null;

  SyncStatus get status => engine.status.value;

  /// A pass that waits until the test lets it finish.
  Completer<Outcome> heldPass() {
    final held = Completer<Outcome>();
    notesPass = (_) => held.future;
    return held;
  }

  Object? keptJson(String key) {
    final text = kept.getItem(key);
    return text == null ? null : jsonDecode(text);
  }
}

/// A signed-in session of the seeded account, with a token the service will take.
Session live(FakeService service) => Session(token: service.signedIn(), handle: 'matt', accountId: 7);

void main() {
  setUp(forgetPictureAsks);

  group('a pass', () {
    test('syncs the notes and then the settings, and says when it finished and how many notes were kept twice', () async {
      final rig = await Rig.make();
      rig.clock = 50000;
      var order = '';
      rig.notesPass = (_) async {
        order += 'notes ';
        return Outcome(conflicts: 2);
      };
      rig.prefsPass = (_) async {
        order += 'prefs';
        return false;
      };
      await rig.engine.syncNow();
      expect(order, 'notes prefs');
      expect(rig.status, const SyncStatus(phase: 'idle', lastAt: 50000, conflicts: 2));
      expect((rig.passes[0].token, rig.passes[0].key), ('t1', rig.service.accountKey));
    });

    test('takes the notifications first, then the organizations, then the notes and the settings', () async {
      final rig = await Rig.make();
      final order = <String>[];
      rig.feedPass = (ctx) async {
        order.add('notifications');
        expect(ctx.token, 't1');
        return true;
      };
      rig.notesPass = (_) async {
        order.add('notes');
        return Outcome();
      };
      rig.prefsPass = (_) async {
        order.add('prefs');
        return false;
      };
      rig.orgsPass = (ctx) async {
        order.add('orgs');
        expect(ctx.token, 't1');
        return null;
      };
      await rig.engine.syncNow();
      expect(order, ['notifications', 'orgs', 'notes', 'prefs']);
      expect(rig.status.phase, 'idle');
    });

    test('hands the notifications step the feed as it is at each step, kept under the account', () async {
      final rig = await Rig.make();
      rig.feedPass = (ctx) async {
        ctx.update((state) => state.copyWith(cursor: 12));
        expect(ctx.read().cursor, 12);
        return true;
      };
      await rig.engine.syncNow();
      expect(rig.keptJson('glyph-sync-7-notifications'), containsPair('cursor', 12));
    });

    test('records a note kept twice as a notification, with the copy’s id and title', () async {
      final rig = await Rig.make();
      rig.notesPass = (ctx) async {
        ctx.onConflict?.call((noteId: 'n-copy', title: 'Trip to Lisbon'));
        return Outcome(changed: 1, conflicts: 1);
      };
      await rig.engine.syncNow();
      expect(rig.recorded.made.single.kind, 'sync-conflict');
      expect(rig.recorded.made.single.details, {'noteId': 'n-copy', 'title': 'Trip to Lisbon'});
    });

    test('runs the notifications and the organizations alone when asked, leaving the notes’ status as it was', () async {
      final rig = await Rig.make();
      rig.clock = 50000;
      await rig.engine.syncNow();
      final order = <String>[];
      rig.feedPass = (_) async {
        order.add('notifications');
        return true;
      };
      rig.orgsPass = (_) async {
        order.add('orgs');
        return null;
      };
      await rig.engine.syncNotificationsNow();
      expect(order, ['notifications', 'orgs']);
      expect(rig.passes, hasLength(1));
      expect((rig.status.phase, rig.status.lastAt), ('idle', 50000));
      // A failure there is still said.
      rig.feedPass = (_) async => throw const ApiError(500, 'The service is down.');
      await rig.engine.syncNotificationsNow();
      expect((rig.status.phase, rig.status.message), ('error', 'The service is down.'));
    });

    test('runs a full pass when both kinds were asked for while one was running', () async {
      final rig = await Rig.make();
      final held = rig.heldPass();
      final first = rig.engine.syncNow();
      await pumpEventQueue();
      final light = rig.engine.syncNotificationsNow();
      final full = rig.engine.syncNow();
      expect(identical(light, first), isTrue);
      expect(identical(full, first), isTrue);
      rig.notesPass = (_) async => Outcome();
      held.complete(Outcome());
      await first;
      // The queued pass covered the most anybody asked: the notes ran twice.
      expect(rig.passes, hasLength(2));
    });

    test('says how many notes it could not send and why, and hands the pass which notes are meetings and whether their audio goes', () async {
      final rig = await Rig.make();
      rig.clock = 50000;
      rig.prefs.update((now) => now.copyWith(meetings: {'m1': 40}, syncMeetingRecordings: true));
      rig.notesPass = (_) async => Outcome(unsent: 2, reason: 'The recording is too big for the service.');
      await rig.engine.syncNow();
      expect((rig.status.phase, rig.status.unsent, rig.status.unsentReason), ('idle', 2, 'The recording is too big for the service.'));
      expect(syncSummary('matt', rig.status, now: 50000), 'matt · 2 notes not synced');
      expect(rig.passes[0].meetings!(), {'m1': 40});
      expect(rig.passes[0].syncMeetingRecordings!(), isTrue);
      // The next pass that sends everything clears the count.
      rig.notesPass = (_) async => Outcome();
      await rig.engine.syncNow();
      expect((rig.status.unsent, rig.status.unsentReason), (0, null));
      expect(syncSummary('matt', rig.status, now: 50000), 'matt · synced just now');
    });

    test('says it is syncing while it runs', () async {
      final rig = await Rig.make();
      final held = rig.heldPass();
      final running = rig.engine.syncNow();
      await pumpEventQueue();
      expect(rig.status.phase, 'syncing');
      held.complete(Outcome());
      await running;
      expect(rig.status.phase, 'idle');
    });

    test('tells the list to read again only when the pass changed notes here', () async {
      final rig = await Rig.make();
      await rig.engine.syncNow();
      expect(rig.told, 0);
      rig.notesPass = (_) async => Outcome(changed: 1);
      await rig.engine.syncNow();
      expect(rig.told, 1);
    });

    test('keeps what it learned under the account, and starts the next pass from it', () async {
      final rig = await Rig.make();
      rig.notesPass = (ctx) async {
        ctx.state.cursor += 5;
        ctx.save(ctx.state);
        return Outcome();
      };
      await rig.engine.syncNow();
      expect(rig.keptJson('glyph-sync-7-notes'), containsPair('cursor', 5));
      rig.notesPass = (_) async => Outcome();
      await rig.engine.syncNow();
      expect(rig.passes[1].state.cursor, 5);
    });
  });

  group('what stops a pass', () {
    test('does nothing signed out, or without the account key, and says sync is off', () async {
      final rig = await Rig.make();
      rig.account.session = null;
      await rig.engine.syncNow();
      rig.account.key = null;
      rig.account.session = testSession;
      await rig.engine.syncNow();
      expect(rig.passes, isEmpty);
      expect(rig.status.phase, 'off');
    });

    test('does nothing with "Nothing leaves the phone" on', () async {
      final rig = await Rig.make();
      rig.prefs.update((now) => now.copyWith(localOnly: true));
      await rig.engine.syncNow();
      expect(rig.passes, isEmpty);
      expect(rig.status.phase, 'off');
    });

    test('asks for the newest app on a device whose store cannot take a sync, and runs on one that can', () async {
      final rig = await Rig.make();
      rig.ready = false;
      await rig.engine.syncNow();
      expect(rig.passes, isEmpty);
      expect((rig.status.phase, rig.status.message), ('error', 'Sync needs the newest Ghost.md. Install it from attack.fm/glyph.'));
      rig.ready = true;
      await rig.engine.syncNow();
      expect(rig.passes, hasLength(1));
    });

    test('says what went wrong, and renews a session that lapsed mid-pass', () async {
      final rig = await Rig.make();
      rig.notesPass = (_) async => throw const ApiError(500, 'The service is down.');
      await rig.engine.syncNow();
      expect((rig.status.phase, rig.status.message), ('error', 'Notes: The service is down.'));
      expect(rig.account.resumes, 0);
      rig.notesPass = (_) async => throw const ApiError(401, 'Sign in again.');
      await rig.engine.syncNow();
      expect(rig.account.resumes, 1);
    });

    test('keeps the settings and the organizations going when a note will not sync', () async {
      final rig = await Rig.make();
      final order = <String>[];
      rig.notesPass = (_) async => throw const ApiError(500, 'The service is down.');
      rig.prefsPass = (_) async {
        order.add('prefs');
        return false;
      };
      rig.orgsPass = (_) async {
        order.add('orgs');
        return null;
      };
      await rig.engine.syncNow();
      expect(order, ['orgs', 'prefs']);
      expect((rig.status.phase, rig.status.message), ('error', 'Notes: The service is down.'));
    });
  });

  group('one pass at a time', () {
    test('queues exactly one more pass behind the one running, however many are asked for', () async {
      final rig = await Rig.make();
      final held = rig.heldPass();
      final first = rig.engine.syncNow();
      await pumpEventQueue();
      final second = rig.engine.syncNow();
      final third = rig.engine.syncNow();
      // Every request during a pass is answered with the pass that ends after the queued one.
      expect(identical(second, first), isTrue);
      expect(identical(third, first), isTrue);
      rig.notesPass = (_) async => Outcome();
      held.complete(Outcome());
      await first;
      expect(rig.passes, hasLength(2));
    });

    test('lets a reset wait for the pass running and the one it queued, and answers at once when none is', () async {
      final rig = await Rig.make();
      var settled = false;
      await rig.engine.syncSettled();
      final held = rig.heldPass();
      unawaited(rig.engine.syncNow());
      await pumpEventQueue();
      unawaited(rig.engine.syncNow());
      final waiting = rig.engine.syncSettled().then((_) => settled = true);
      await pumpEventQueue();
      expect(settled, isFalse);
      rig.notesPass = (_) async => Outcome();
      held.complete(Outcome());
      await waiting;
      expect(settled, isTrue);
      expect(rig.passes, hasLength(2));
    });

    testWidgets('holds a pull to refresh only as long as it is given, and the sync goes on', (tester) async {
      final rig = (await tester.runAsync(Rig.make))!;
      final held = rig.heldPass();
      var back = false;
      unawaited(rig.engine.syncWithin(const Duration(seconds: 5)).then((_) => back = true));
      await tester.pump(const Duration(seconds: 4));
      expect(back, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(back, isTrue);
      expect(rig.status.phase, 'syncing');
      held.complete(Outcome());
      await tester.pump();
      expect(rig.status.phase, 'idle');
    });
  });

  // The schedule keeps time with timers, so these run under the test binding's own clock: `pump` moves it.
  group('when sync runs by itself', () {
    testWidgets('renews the session and syncs just after launch, signed in, and never for a device that was not', (tester) async {
      final rig = (await tester.runAsync(Rig.make))!;
      final fresh = (await tester.runAsync(() => Rig.make(signedIn: false)))!;
      final stop = rig.engine.start();
      expect(rig.passes, isEmpty);
      await tester.pump(Duration.zero);
      expect(rig.account.resumes, 1);
      expect(rig.passes, hasLength(1));
      stop();

      final stopFresh = fresh.engine.start();
      await tester.pump(const Duration(minutes: 10));
      expect(fresh.account.resumes, 0);
      expect(fresh.passes, isEmpty);
      stopFresh();
    });

    testWidgets('syncs four seconds after the last of a run of saves, not after each', (tester) async {
      final rig = (await tester.runAsync(Rig.make))!;
      final stop = rig.engine.start();
      await tester.pump(Duration.zero);
      rig.passes.clear();
      for (var i = 0; i < 3; i += 1) {
        rig.touched.value += 1;
        await tester.pump(const Duration(seconds: 3));
      }
      expect(rig.passes, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(rig.passes, hasLength(1));
      stop();
    });

    testWidgets('syncs when the app comes back, and on a five-minute beat while it is open', (tester) async {
      final rig = (await tester.runAsync(Rig.make))!;
      final stop = rig.engine.start();
      await tester.pump(Duration.zero);
      rig.passes.clear();
      rig.engine.resumed();
      await tester.pump(Duration.zero);
      expect(rig.passes, hasLength(1));
      await tester.pump(const Duration(minutes: 5));
      expect(rig.passes, hasLength(2));
      stop();
      await tester.pump(const Duration(minutes: 5));
      expect(rig.passes, hasLength(2));
      // Stopped: coming back to the front asks for nothing.
      rig.engine.resumed();
      await tester.pump(Duration.zero);
      expect(rig.passes, hasLength(2));
    });

    testWidgets('syncs after a setting changes here, but not after the settings another device sent', (tester) async {
      final rig = (await tester.runAsync(Rig.make))!;
      rig.prefsPass = (ctx) async {
        ctx.write({'theme': 'light'});
        return true;
      };
      final stop = rig.engine.start();
      await tester.pump(Duration.zero);
      expect(rig.prefs.value.theme, 'light');
      // The settings the first pass wrote were the account's: no pass follows them.
      await tester.pump(const Duration(seconds: 4));
      expect(rig.passes, hasLength(1));
      rig.prefsPass = (_) async => false;
      rig.prefs.update((now) => now.copyWith(accent: 'red'));
      await tester.pump(const Duration(seconds: 4));
      expect(rig.passes, hasLength(2));
      stop();
    });

    testWidgets('starts once, however many times it is asked', (tester) async {
      final rig = (await tester.runAsync(Rig.make))!;
      final stop = rig.engine.start();
      final again = rig.engine.start();
      await tester.pump(Duration.zero);
      expect(rig.passes, hasLength(1));
      again();
      // The second stop was nobody's: the beat goes on.
      await tester.pump(const Duration(minutes: 5));
      expect(rig.passes, hasLength(2));
      stop();
    });
  });

  group('this device and the account', () {
    test('knows a note has changes the pass has not sent, and that nothing is pending signed out', () async {
      final rig = await Rig.make();
      final one = note('a', 'words');
      expect(rig.engine.hasUnsyncedChanges(one), isTrue);
      rig.notesPass = (ctx) async {
        ctx.state.notes['a'] = NoteMark(rev: 3, mark: mark(one));
        ctx.save(ctx.state);
        return Outcome();
      };
      await rig.engine.syncNow();
      expect(rig.engine.hasUnsyncedChanges(one), isFalse);
      expect(rig.engine.hasUnsyncedChanges(one.copyWith(body: 'more words')), isTrue);
      rig.account.session = null;
      expect(rig.engine.hasUnsyncedChanges(one.copyWith(body: 'more words')), isFalse);
    });

    test('forgets what it knew of the account when signing out, and keeps the notes', () async {
      final notes = DeviceNotes();
      final rig = await Rig.make(notes: notes);
      rig.kept
        ..setItem('glyph-sync-7-notes', '{"cursor":9}')
        ..setItem('glyph-sync-7-prefs', '{"rev":2}')
        ..setItem('glyph-sync-7-prefs-held', '{"synced":{"theme":"aurora"},"unknown":{}}')
        ..setItem('glyph-sync-7-notifications', '{"cursor":3,"items":{},"marks":[],"unsent":[]}')
        ..setItem('glyph-sync-7-orgs', '{"list":[{"id":"o1","name":"Ghost","role":"owner","state":"member"}],"at":1}')
        ..setItem('glyph-sync-7-team-o1', '{"cursor":4}')
        ..setItem('glyph-sync-8-notes', '{"cursor":1}');
      notes.held['kept'] = note('kept', '# Kept');
      await rig.engine.syncNow();
      await rig.engine.signOutHere();
      expect(rig.account.signOuts, 1);
      for (final part in ['notes', 'prefs', 'prefs-held', 'notifications', 'orgs', 'team-o1']) {
        expect(rig.kept.getItem('glyph-sync-7-$part'), isNull, reason: part);
      }
      expect(rig.kept.getItem('glyph-sync-8-notes'), isNotNull);
      expect(rig.status, const SyncStatus());
      expect(await notes.get('kept'), isNotNull);
    });

    test('empties the list of shares when the account is deleted, since the links read nothing now', () async {
      final rig = await Rig.make();
      rig.prefs.update((now) => now.copyWith(shares: {'a': ShareEntry(id: 'i' * 22, key: 'k' * 43, sent: 'p2:1')}));
      rig.kept.setItem('glyph-sync-7-notes', '{"cursor":9}');
      await rig.engine.deleteAccountHere('correct horse');
      expect(rig.account.deleted, ['correct horse']);
      expect(rig.prefs.value.shares, isEmpty);
      expect(rig.kept.getItem('glyph-sync-7-notes'), isNull);
    });

    test('reads which notes are meetings when it decides about a recording, not when the pass began', () async {
      final rig = await Rig.make();
      final pass = rig.heldPass();
      final running = rig.engine.syncNow();
      await pumpEventQueue();
      expect(rig.passes[0].meetings!(), isEmpty);
      // Done on the Mac's meeting while the pass is out: its note is listed as a meeting before its audio is kept.
      rig.prefs.update((now) => now.copyWith(meetings: {'m2': 1}));
      expect(rig.passes[0].meetings!(), {'m2': 1});
      pass.complete(Outcome());
      await running;
    });

    test('tells the pass which notes are a team’s: the ones filed in an organization’s workspace', () async {
      final rig = await Rig.make();
      rig.workspaces.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Ghost'));
      final own = rig.workspaces.addWorkspace('Home')!;
      rig.workspaces.fileNote('team', orgWorkspaceId('o1'));
      rig.workspaces.fileNote('mine', own.id);
      await rig.engine.syncNow();
      final teamNote = rig.passes[0].teamNote!;
      expect((teamNote('team'), teamNote('mine'), teamNote('unfiled')), (true, false, false));
    });
  });

  group('what the Account page says', () {
    test('says how long ago a sync finished', () {
      const now = 10 * 60 * 60000;
      expect(syncedWhen(now - 20000, now: now), 'just now');
      expect(syncedWhen(now - 5 * 60000, now: now), '5 min ago');
      expect(syncedWhen(now - 3 * 60 * 60000, now: now), isNot(matches(RegExp('ago|just now'))));
    });

    group('says a sync past the hour in the phone’s own words (core/locale_dates.dart)', () {
      tearDown(() => toldLocale = null);
      final morning = DateTime(2026, 9, 28, 9, 7).millisecondsSinceEpoch;
      final afternoon = DateTime(2026, 10, 9, 16, 5).millisecondsSinceEpoch;
      const later = 3 * 60 * 60000;

      test('an American phone has the month first and a 12-hour clock', () {
        toldLocale = DateLocale.enUS;
        expect(syncedWhen(morning, now: morning + later), 'Sep 28, 9:07 AM');
        expect(syncedWhen(afternoon, now: afternoon + later), 'Oct 9, 4:05 PM');
        expect(syncedWhen(afternoon, now: afternoon + 5 * 60000), '5 min ago');
      });

      test('a British phone has the day first and a 24-hour clock', () {
        toldLocale = DateLocale.enGB;
        expect(syncedWhen(morning, now: morning + later), '28 Sept, 9:07');
        expect(syncedWhen(afternoon, now: afternoon + later), '9 Oct, 16:05');
        expect(syncedWhen(afternoon, now: afternoon + 5 * 60000), '5 min ago');
      });
    });

    test('gives the Account row the handle and where sync stands', () {
      const now = 1000000;
      expect(syncSummary(null, const SyncStatus(phase: 'idle')), 'Not signed in');
      expect(syncSummary('matt', const SyncStatus(phase: 'idle')), 'matt');
      expect(syncSummary('matt', const SyncStatus(phase: 'syncing')), 'matt · syncing');
      expect(syncSummary('matt', const SyncStatus(phase: 'error')), 'matt · not synced');
      expect(syncSummary('matt', const SyncStatus(phase: 'idle', lastAt: now), now: now), 'matt · synced just now');
      expect(syncSummary('matt', const SyncStatus(phase: 'idle', lastAt: now, unsent: 1), now: now), 'matt · 1 note not synced');
    });
  });

  // --- not on the web: the hook, and the engine whole ---------------------------------------------------------------

  group('the organizations’ step', () {
    test('sees to the keys and hands each organization joined, with its key, to the team channel', () async {
      final service = await FakeService.start(seed: testAccount);
      final handed = <TeamPass>[];
      final rig = await Rig.make(
        service: service,
        standIns: false,
        as: live(service),
        teamNotes: (pass) async {
          handed.add(pass);
          expect(pass.loadState(), isNull);
          pass.saveState({'cursor': 3});
          return const TeamOutcome(unsent: 1, reason: 'One would not go.');
        },
      );
      final org = await rig.orgs.createOrg('Ghost');
      service.invited('Boo', 'sam');
      await rig.engine.syncNow();
      // The account's pair was registered, the first generation made and held, in memory only.
      expect(service.encryption, isNotNull);
      expect(service.keysOf(org.id).generation, 1);
      expect(rig.orgKeys.orgKeyGeneration(org.id), 1);
      expect(rig.kept.allKeys.where((key) => key.contains('key')), isEmpty);
      // The channel was handed the one organization joined, never the invitation.
      expect(handed.map((pass) => (pass.org.id, pass.generation, pass.reseal)), [(org.id, 1, false)]);
      expect(identical(handed.single.key, rig.orgKeys.orgKeyOf(org.id)), isTrue);
      rig.workspaces.fileNote('n1', orgWorkspaceId(org.id));
      expect((handed.single.isTeamNote('n1'), handed.single.isTeamNote('n2')), (true, false));
      handed.single.file('n2');
      expect(rig.workspaces.workspaceOf('n2')?.id, orgWorkspaceId(org.id));
      expect(rig.keptJson('glyph-sync-7-team-${org.id}'), {'cursor': 3});
      // What the channel could not send is the pass's to say.
      expect((rig.status.phase, rig.status.unsent, rig.status.unsentReason), ('idle', 1, 'One would not go.'));
    });

    test('turns the key when a member has gone, and has the channel seal the team’s notes again under it', () async {
      final service = await FakeService.start(seed: testAccount, peers: ['sam', 'lee']);
      final handed = <TeamPass>[];
      final rig = await Rig.make(
        service: service,
        standIns: false,
        as: live(service),
        teamNotes: (pass) async {
          handed.add(pass);
          return const TeamOutcome();
        },
      );
      final org = await rig.orgs.createOrg('Ghost');
      final lee = await service.crypto.newEncryptionKey();
      service.peerKey('lee', await service.crypto.encryptionPublicKeyOf(lee));
      service.orgs[org.id]!.rows['lee'] = OrgRowKept(handle: 'lee', role: 'member', state: 'member', since: 1, invitedBy: 'matt');
      await rig.engine.syncNow();
      expect(service.keysOf(org.id).generation, 1);
      await rig.orgs.removeMember(org.id, 'lee');
      handed.clear();
      await rig.engine.syncNow();
      expect(service.keysOf(org.id).generation, 2);
      expect(handed.map((pass) => (pass.generation, pass.reseal)), [(1, false), (2, true)]);
      expect(identical(handed.last.key, rig.orgKeys.orgKeyOf(org.id)), isTrue);
      // The generation before is still to hand, for a row no device has sealed again yet.
      expect(await handed.last.olderKey!(1), same(handed.first.key));
    });

    test('with no channel yet, keeps the keys in hand and never turns one', () async {
      final service = await FakeService.start(seed: testAccount, peers: ['sam', 'lee']);
      final rig = await Rig.make(service: service, standIns: false, as: live(service));
      final org = await rig.orgs.createOrg('Ghost');
      service.orgs[org.id]!.rows['lee'] = OrgRowKept(handle: 'lee', role: 'member', state: 'member', since: 1, invitedBy: 'matt');
      await rig.engine.syncNow();
      expect(rig.orgKeys.orgKeyGeneration(org.id), 1);
      await rig.orgs.removeMember(org.id, 'lee');
      await rig.engine.syncNow();
      expect(service.keysOf(org.id).generation, 1);
      expect(rig.status.phase, 'idle');
    });

    test('stops at a session that lapsed in a channel, and counts any other failure against that organization alone', () async {
      final service = await FakeService.start(seed: testAccount);
      Object failure = const ApiError(500, 'The team’s notes would not come.');
      final rig = await Rig.make(service: service, standIns: false, as: live(service), teamNotes: (_) async => throw failure);
      await rig.orgs.createOrg('Ghost');
      await rig.engine.syncNow();
      expect((rig.status.phase, rig.status.unsent, rig.status.unsentReason), ('idle', 1, 'Ghost: The team’s notes would not come.'));
      failure = const KeyTurned(2);
      await rig.engine.syncNow();
      expect((rig.status.phase, rig.status.unsent), ('idle', 0));
      failure = const ApiError(401, 'Sign in again.');
      await rig.engine.syncNow();
      expect((rig.status.phase, rig.account.resumes), ('error', 1));
    });
  });

  group('two devices, each a whole engine, on one service', () {
    test('a note, a setting, a workspace, an organization and an invitation’s answer all cross', () async {
      final service = await FakeService.start(seed: testAccount);
      final phoneNotes = DeviceNotes(), foldNotes = DeviceNotes();
      final phone = await Rig.make(service: service, standIns: false, as: live(service), notes: phoneNotes);
      final fold = await Rig.make(service: service, standIns: false, as: live(service), notes: foldNotes);

      phoneNotes.held['a'] = note('a', '# Groceries\n\nmilk', createdAt: 1, updatedAt: 1);
      phone.prefs.update((now) => now.copyWith(theme: 'ember', localOnly: false, formatModel: 'qwen3.5-2b'));
      final home = phone.workspaces.addWorkspace('Home', 'sea')!;
      phone.workspaces.fileNote('a', home.id);
      final org = await phone.orgs.createOrg('Ghost', hue: 'moss');
      final invited = service.invited('Boo', 'sam');
      await phone.engine.syncNow();
      expect(phone.status.phase, 'idle');

      await fold.engine.syncNow();
      expect(fold.status.phase, 'idle');
      expect(foldNotes.held['a']?.body, '# Groceries\n\nmilk');
      expect(fold.told, 1);
      // The settings that describe the person crossed; the phone's own did not.
      expect((fold.prefs.value.theme, fold.prefs.value.formatModel), ('ember', Preferences.defaults.formatModel));
      // The workspace and the filing, and the organization's own workspace, made from the list.
      expect(fold.workspaces.workspaceOf('a'), Workspace(id: home.id, name: 'Home', hue: 'sea'));
      expect(fold.workspaces.value.list.map((w) => w.id), containsAll([home.id, orgWorkspaceId(org.id)]));
      expect(fold.orgs.orgsState().list.map((row) => (row.id, row.state)), [(org.id, 'member'), (invited, 'invited')]);
      // The invitation is in the feed on both; answered on the fold, the feed's own answerInvite reaches the
      // organizations: joined on the service, and its workspace made here by the answer.
      expect(fold.feed.notifications().where((n) => n.kind == 'invite'), hasLength(1));
      fold.feed.answerInvite(invited, true);
      await fold.engine.syncNotificationsNow();
      expect(service.rowIn(invited), (role: 'member', state: 'member'));
      expect(fold.workspaces.value.list.map((w) => w.id), contains(orgWorkspaceId(invited)));

      // An edit on the fold, and both sides changed: the phone's words are kept as a copy, and say so in its feed.
      foldNotes.held['a'] = foldNotes.held['a']!.copyWith(body: '# Groceries\n\nmilk\neggs', updatedAt: 5);
      phoneNotes.held['a'] = phoneNotes.held['a']!.copyWith(body: '# Groceries\n\nmilk\nbread', updatedAt: 6);
      await fold.engine.syncNow();
      await phone.engine.syncNow();
      expect(phone.status.conflicts, 1);
      expect(phoneNotes.held['a']?.body, '# Groceries\n\nmilk\neggs');
      expect(phoneNotes.held.values.map((n) => n.body), contains('# Groceries\n\nmilk\nbread'));
      expect(phone.recorded.made.single.kind, 'sync-conflict');
      // And the engine knows what is and is not with the account.
      expect(phone.engine.hasUnsyncedChanges(phoneNotes.held['a']!), isFalse);
      expect(phone.engine.hasUnsyncedChanges(phoneNotes.held['a']!.copyWith(body: 'more')), isTrue);
    });

    test('a pass with "Nothing leaves the phone" on asks the service nothing at all', () async {
      final service = await FakeService.start(seed: testAccount);
      final rig = await Rig.make(service: service, standIns: false, as: live(service));
      rig.prefs.update((now) => now.copyWith(localOnly: true));
      service.calls.clear();
      await rig.engine.syncNow();
      expect(service.calls, isEmpty);
      expect(rig.status.phase, 'off');
    });
  });
}
