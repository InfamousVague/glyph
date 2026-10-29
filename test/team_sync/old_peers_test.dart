// A note dragged out of an organization, or into one, on Matt's new device (2.3.79, 7dc009f3) while his second device
// still runs an OLD build's team channel, with another member on an old build and one on the new. The worry (the
// Testing session, 2026-10-29): on 2026-10-20 and 10-26 old builds deleted team rows when organization filing
// changed under them, an organization's deletes skip the Trash, and Matt's Mac ran 2.3.46 for days. The old build's
// channel is played faithfully: test/team_sync/old/team_sync_before_7dc009f3.dart is lib/team/sync.dart as it stood
// before 7dc009f3, its imports alone changed, and its `_takeRow` removes a note on a team's deletion even where the
// device has it filed outside the organization, and files a moved-out note back in when a member's row lands.
//
// What is asked after every device has synced, pass after pass: is the note still Matt's - on the new device, on
// the old one, and in the account's own copy on the service - or did the old device's removal go out as a personal
// deletion and take it from his account? And did anything else go: another team note, another personal note?
//
// What it showed first, before lib/sync/notes.dart's [LeftTeams]: dragged out and synced in turn, the old Mac
// removed its copy and never had it again (the account's copy and the new device's stood); and with the Mac a pass
// behind and Matt writing in the note meanwhile, the old Mac took the account's row as its own, removed its copy on
// the team's deletion, and sent the account a deletion: the note went from every device of Matt's, his new words
// with it, and all that was left was a copy the old Mac had kept of the words from before. Dragged in, nothing was
// lost either way. Now a note lately out of a team here is kept from the account's deletions and its row put again
// once an hour for a fortnight, so the old device's deletion is answered with the words, and it takes the note back.
//
// The devices are whole where they are Matt's (test/e2e/world.dart: the real engine, account, organizations and keys,
// the real crypto and CRDT over the Mac's core, tool/build-native.sh host; skipped out loud without it), the members
// the team's channel alone (support.dart), all over the service in memory, which holds one account: the members
// stand for other people as test/team_sync/sync_test.dart's do. A pass may be cut short before the organizations'
// channels, as a pass is when the organizations' list does not arrive (a network blip, a 500): that is how the Mac
// comes to know the new filing a pass before it hears the team's deletion. Each round of passes is an hour and a
// minute on Matt's devices' clock.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/folder_drag.dart';
import 'package:ghost_md/team/crdt.dart';

import '../e2e/world.dart';
import 'old/team_sync_before_7dc009f3.dart' as old;
import 'support.dart';

const String _password = 'correct horse battery';

/// The service in memory as one device reaches it, with the organizations' list refused while [listDown] is set: the
/// pass goes on without the organizations' channels, as it does when that one call fails.
class _Patchy implements World {
  _Patchy(this.inner);
  final FakeWorld inner;
  bool listDown = false;

  @override
  String get name => inner.name;

  @override
  bool get manyAccounts => false;

  @override
  Future<void> fresh() async {}

  @override
  Api api() => Api(
        base: 'http://service.test/api',
        fetcher: (request) async {
          if (listDown && request.method == 'GET' && request.url.path.endsWith('/v1/orgs')) return FetchResponse.json(503, {'error': 'Try again in a moment.'});
          return inner.service.fetcher(request);
        },
      );
}

/// What a case is played over: Matt's two devices, the organization and its Meetings, his Home, and two members.
typedef _World = ({Device phone, Device mac, _Patchy macLine, String orgId, Workspace meetings, Workspace home, TeamDevice fresh, TeamDevice stale});

void main() {
  late GhostCore core;
  late FakeWorld world;
  final devices = <Device>[];
  final members = <TeamDevice>[];
  final oldStates = <TeamDevice, old.TeamSyncState>{};

  /// Matt's devices' time: the wall's at the start, moved on by the rounds.
  var clock = DateTime.now().millisecondsSinceEpoch;

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await GhostCore.open(libraryPath: File(coreLibrary).absolute.path);
    world = FakeWorld(core);
  });

  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  setUp(() async {
    clock = DateTime.now().millisecondsSinceEpoch;
    if (coreBuilt) await world.fresh();
  });

  tearDown(() async {
    for (final each in devices) {
      await each.close();
    }
    for (final each in members) {
      await each.docs.forget();
    }
    devices.clear();
    members.clear();
    oldStates.clear();
  });

  /// One of Matt's devices: on today's build, or with the old build's team channel.
  Device device(String label, {required bool oldBuild, World? through}) {
    final made = Device(through ?? world, core, label: label, folders: true, teamPass: oldBuild ? old.teamNotesPass : null, clock: () => clock);
    devices.add(made);
    return made;
  }

  /// Another member's device, the organization's channel alone, its folders its own.
  TeamDevice member(Device of, String orgId) {
    final made = TeamDevice(crdt: Crdt(core.invoke), api: world.api(), crypto: CoreCrypto(core.invoke), token: () => of.account.session!.token, orgId: orgId, orgKey: of.orgKeys.orgKeyOf(orgId)!, folders: true);
    members.add(made);
    return made;
  }

  /// A member on the old build: the same device, its channel the old one's, with that channel's own state.
  Future<TeamOutcome> oldPass(TeamDevice d) => old.syncTeamNotes(old.TeamSyncContext(
        token: d.token(),
        orgId: d.orgId,
        key: d.orgKey,
        notes: d.local,
        files: d.files,
        docs: d.docs,
        state: oldStates[d] ??= old.emptyTeamState(),
        save: (next) => oldStates[d] = next,
        api: d.api,
        crypto: d.crypto,
        now: () => d.clock,
        isTeamNote: d.isTeamNote,
        leftTeam: d.leftTeam,
        file: d.file,
        folders: d.folders,
        meetings: () => d.meetings,
        syncMeetingRecordings: () => d.syncMeetingRecordings,
      ));

  Set<String> live(String orgId) => {for (final MapEntry(:key, :value) in world.service.teamNotes(orgId).entries) if (!value.deleted) key};

  /// The account's own copies on the service that are live.
  Set<String> accountLive() => {for (final MapEntry(:key, :value) in world.service.notes.entries) if (!value.deleted) key};

  void moveAsked(Device on, String noteId, String title, String to) {
    final carry = FolderCarry.note(noteId, title);
    expect(folderVerdict(on.workspaces, carry, to).landing, FolderLanding.asks);
    expect(moveCarried(on.workspaces, carry, to, asked: true), isNotNull);
  }

  /// Everything Matt's account and the team hold, in a line, for the test's log and its failures.
  String said(String at, _World w) =>
      '$at: phone ${w.phone.notes.keys.toSet()}, mac ${w.mac.notes.keys.toSet()}, account ${accountLive()}, team ${live(w.orgId)}, members ${[for (final m in [w.fresh, w.stale]) m.notes.keys.toSet()]}';

  /// Matt's two devices, the second on [macOld]'s build, and two members, one on each build, over one organization:
  /// HelloTrade › Meetings holds Plan and Standup, HelloTrade itself Roadmap; Matt's own Home holds Trip, and
  /// Groceries is in no folder.
  Future<_World> worldOf({required bool macOld}) async {
    final macLine = _Patchy(world);
    final phone = device('phone', oldBuild: false), mac = device('mac', oldBuild: macOld, through: macLine);
    await phone.account.signUp('matt', _password);
    await mac.account.signIn('matt', _password);
    final org = await phone.orgs.createOrg('HelloTrade', hue: 'violet');
    await phone.sync();
    final root = orgWorkspaceId(org.id);
    final meetings = phone.workspaces.addWorkspace('Meetings', 'ink', root)!;
    final home = phone.workspaces.addWorkspace('Home', 'sea')!;
    phone.write('plan', '# Plan\n\nThe team’s, for now.');
    phone.workspaces.fileNote('plan', meetings.id);
    phone.write('standup', '# Standup');
    phone.workspaces.fileNote('standup', meetings.id);
    phone.write('roadmap', '# Roadmap');
    phone.workspaces.fileNote('roadmap', root);
    phone.write('trip', '# Trip\n\nTrains at 9.');
    phone.workspaces.fileNote('trip', home.id);
    phone.write('groceries', '# Groceries');
    for (var pass = 0; pass < 2; pass += 1) {
      await phone.sync();
      await mac.sync();
    }
    final fresh = member(phone, org.id), stale = member(phone, org.id);
    await fresh.sync();
    await oldPass(stale);
    expect(live(org.id), {'plan', 'standup', 'roadmap'});
    expect(accountLive(), {'trip', 'groceries'});
    expect(mac.notes.keys.toSet(), {'plan', 'standup', 'roadmap', 'trip', 'groceries'});
    expect(fresh.notes.keys.toSet(), {'plan', 'standup', 'roadmap'});
    expect(stale.notes.keys.toSet(), {'plan', 'standup', 'roadmap'});
    return (phone: phone, mac: mac, macLine: macLine, orgId: org.id, meetings: meetings, home: home, fresh: fresh, stale: stale);
  }

  /// Rounds of every device's pass, each an hour and a minute on.
  Future<void> everyone(_World w, {int rounds = 4}) async {
    for (var round = 0; round < rounds; round += 1) {
      clock += const Duration(hours: 1, minutes: 1).inMilliseconds;
      await w.phone.sync();
      await w.mac.sync();
      await w.fresh.sync();
      await oldPass(w.stale);
    }
  }

  /// The Mac's pass cut short before the organizations' channels: the account's notes and the settings come.
  Future<void> macWithoutTeams(_World w) async {
    w.macLine.listDown = true;
    await w.mac.engine.syncNow();
    w.macLine.listDown = false;
  }

  test('a note lately out of a team is kept from a deletion for a fortnight, the price of never losing one to an old build, and after it a deletion is taken', () async {
    final w = await worldOf(macOld: false);
    moveAsked(w.phone, 'plan', 'Plan', w.home.id);
    await everyone(w, rounds: 2);
    expect(w.mac.notes.containsKey('plan'), isTrue);
    // Deleted for good on the Mac within the fortnight: the new device keeps it, sends it again, and the Mac has it
    // back.
    w.mac.notes.remove('plan');
    await w.mac.sync();
    await everyone(w, rounds: 2);
    expect(w.phone.notes.containsKey('plan'), isTrue);
    expect(w.mac.notes.containsKey('plan'), isTrue);
    expect(accountLive(), contains('plan'));
    // A fortnight on, it is an ordinary note: deleted on the Mac, it goes from the new device and the account too, and
    // its row is no longer put again.
    clock += const Duration(days: 15).inMilliseconds;
    await everyone(w, rounds: 1);
    w.mac.notes.remove('plan');
    await w.mac.sync();
    await everyone(w, rounds: 2);
    expect(w.phone.notes.containsKey('plan'), isFalse);
    expect(w.mac.notes.containsKey('plan'), isFalse);
    expect(accountLive(), {'trip', 'groceries'});
    expect(live(w.orgId), {'standup', 'roadmap'});
  }, skip: coreSkip);

  for (final macOld in [true, false]) {
    final second = macOld ? 'the second device on the OLD build' : 'the second device on the new build too';

    group('a note dragged OUT of the organization on the new device, $second:', () {
      /// Matt keeps it with [body], everywhere of his; nothing else of anyone's goes; and the only note more than
      /// before is, at most, a copy the Mac kept of the words from before the move, [before].
      void holds(_World w, String body, {String? before}) {
        final at = said('after', w);
        expect(w.phone.notes['plan']?.body, body, reason: at);
        expect(w.mac.notes['plan']?.body, body, reason: at);
        expect(w.phone.workspaces.workspaceOf('plan')?.id, w.home.id, reason: at);
        expect(w.mac.workspaces.workspaceOf('plan')?.id, w.home.id, reason: at);
        final copies = accountLive().difference({'plan', 'trip', 'groceries'});
        expect(accountLive(), containsAll(['plan', 'trip', 'groceries']), reason: at);
        expect(copies.length, lessThanOrEqualTo(before == null ? 0 : 1), reason: at);
        for (final copy in copies) {
          expect(w.phone.notes[copy]?.body, before, reason: '$at: a copy is the words from before, and nothing else');
        }
        // Out of the team, for every member, and the team's other notes with every one of them.
        expect(live(w.orgId), {'standup', 'roadmap'}, reason: at);
        for (final m in [w.fresh, w.stale]) {
          expect(m.notes.keys.toSet(), {'standup', 'roadmap'}, reason: at);
        }
        for (final d in [w.phone, w.mac]) {
          expect(d.notes.keys.toSet(), {'plan', 'standup', 'roadmap', 'trip', 'groceries', ...copies}, reason: at);
          expect(d.notes['trip']?.body, '# Trip\n\nTrains at 9.', reason: at);
        }
      }

      test('synced in turn, pass after pass', () async {
        final w = await worldOf(macOld: macOld);
        moveAsked(w.phone, 'plan', 'Plan', w.home.id);
        await everyone(w);
        printOnFailure(said('out, in turn, mac ${macOld ? 'old' : 'new'}', w));
        holds(w, '# Plan\n\nThe team’s, for now.');
      }, skip: coreSkip);

      test('the Mac hearing the new filing a pass before the team’s deletion, and Matt writing in it meanwhile', () async {
        final w = await worldOf(macOld: macOld);
        moveAsked(w.phone, 'plan', 'Plan', w.home.id);
        await w.phone.sync();
        await macWithoutTeams(w);
        expect(w.mac.workspaces.workspaceOf('plan')?.id, w.home.id);
        // Matt goes on writing in it on the new device, his own note now.
        w.phone.write('plan', '# Plan\n\nMine now.', at: 50);
        await w.phone.sync();
        await everyone(w);
        printOnFailure(said('out, the Mac a pass behind, mac ${macOld ? 'old' : 'new'}', w));
        holds(w, '# Plan\n\nMine now.', before: '# Plan\n\nThe team’s, for now.');
      }, skip: coreSkip);
    });

    group('a note dragged INTO the organization on the new device, $second:', () {
      void holds(_World w, String body) {
        final at = said('after', w);
        expect(w.phone.notes['trip']?.body, body, reason: at);
        expect(w.mac.notes['trip']?.body, body, reason: at);
        expect(w.phone.workspaces.workspaceOf('trip')?.id, w.meetings.id, reason: at);
        expect(w.mac.workspaces.workspaceOf('trip')?.id, w.meetings.id, reason: at);
        expect(live(w.orgId), {'plan', 'standup', 'roadmap', 'trip'}, reason: at);
        expect(accountLive(), {'groceries'}, reason: at);
        for (final d in [w.phone, w.mac]) {
          expect(d.notes.keys.toSet(), {'plan', 'standup', 'roadmap', 'trip', 'groceries'}, reason: at);
        }
        for (final m in [w.fresh, w.stale]) {
          expect(m.notes.keys.toSet(), {'plan', 'standup', 'roadmap', 'trip'}, reason: at);
          expect(m.notes['trip']?.body, body, reason: at);
        }
      }

      test('synced in turn, pass after pass', () async {
        final w = await worldOf(macOld: macOld);
        moveAsked(w.phone, 'trip', 'Trip', w.meetings.id);
        await everyone(w);
        printOnFailure(said('in, in turn, mac ${macOld ? 'old' : 'new'}', w));
        holds(w, '# Trip\n\nTrains at 9.');
      }, skip: coreSkip);

      test('the Mac hearing the new filing a pass before the team’s row, and Matt writing in it meanwhile', () async {
        final w = await worldOf(macOld: macOld);
        moveAsked(w.phone, 'trip', 'Trip', w.meetings.id);
        await w.phone.sync();
        await macWithoutTeams(w);
        w.phone.write('trip', '# Trip\n\nTrains at 10.', at: 50);
        await w.phone.sync();
        await everyone(w);
        printOnFailure(said('in, the Mac a pass behind, mac ${macOld ? 'old' : 'new'}', w));
        holds(w, '# Trip\n\nTrains at 10.');
      }, skip: coreSkip);
    });
  }
}
