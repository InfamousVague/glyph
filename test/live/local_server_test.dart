// Live typing between two Dart devices through the REAL relay (server `live.rs`), run on this Mac by
// tool/local-server.sh, with the real crypto, the real CRDT and real sockets: a note of the account's own on two
// of its devices (the web's core/live/live.e2e.test.ts, case for case), and a team's note between two members'
// devices with their carets, who is where, and the word that there is something to fetch.
//
//   tool/local-server.sh start     # prints GHOST_E2E_API=http://127.0.0.1:<port>/api
//   GHOST_E2E_API=http://127.0.0.1:<port>/api flutter test --no-pub test/live/local_server_test.dart
//
// Skipped unless GHOST_E2E_API is set, so the ordinary suite needs no server; refused unless it names 127.0.0.1
// (test/e2e/world.dart `LocalWorld`), so nothing here can reach the real service whatever the variable says.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/presence.dart';
import 'package:ghost_md/live/session.dart';
import 'package:ghost_md/live/team.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';

import '../e2e/world.dart';
import 'support.dart';

/// Waits for [check], asked every few milliseconds: a real socket has no `settled` to wait on.
Future<void> until(bool Function() check, String what, {Duration within = const Duration(seconds: 8)}) async {
  final clock = Stopwatch()..start();
  while (!check()) {
    if (clock.elapsed > within) fail('Timed out waiting for $what');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

class Open {
  Open(this.session, this.shown, this.copies);
  final LiveSession session;
  final Future<String> shown;
  final List<String> copies;
}

void main() {
  final base = Platform.environment['GHOST_E2E_API'] ?? '';
  final skip = base.isEmpty ? 'no local server: run tool/local-server.sh start and set GHOST_E2E_API' : coreSkip;
  late GhostCore core;
  late LocalWorld world;
  final devices = <Device>[];

  setUpAll(() async {
    if (skip != null) return;
    world = LocalWorld(base);
    core = await openCore();
  });
  tearDownAll(() async {
    for (final each in devices) {
      await each.close();
    }
    if (skip == null) await core.close();
  });

  Device device(String label) {
    final made = Device(world, core, label: label, live: true);
    devices.add(made);
    return made;
  }

  Future<Open> open(Device on, String noteId, String words, {bool unsynced = false}) async {
    final shown = Completer<String>();
    final copies = <String>[];
    on.live!.enabled.set(true);
    final session = await on.live!.hub.openLive(
      noteId,
      words,
      SessionListener(ready: (shown_) => shown.isCompleted ? null : shown.complete(shown_), peers: (_) {}),
      SyncHooks(hasUnsynced: (_) async => unsynced, keepCopy: (_, kept) async => copies.add(kept)),
    );
    return Open(session!, shown.future, copies);
  }

  test('a note live on two devices of one account, through the relay: made on the phone and adopted on the Mac, each keystroke carried, both typing into one spot kept, a device that went away caught up, and the relay never given the words', () async {
    final handle = freshHandle('live');
    final phone = device('phone'), mac = device('mac');
    await phone.account.signUp(handle, 'correct horse');
    await mac.account.signIn(handle, 'correct horse');

    // Is made on the phone and adopted on the Mac, not built twice.
    final a = await open(phone, 'note-trip', 'Weekend trip');
    expect(await a.shown, 'Weekend trip');
    final b = await open(mac, 'note-trip', 'Weekend trip');
    expect(await b.shown, 'Weekend trip');
    expect(b.session.seed, a.session.seed);
    expect(b.session.words, 'Weekend trip');
    await until(() => phone.live!.shared.isShared('note-trip') && mac.live!.shared.isShared('note-trip'), 'both to know the note is shared');

    // Carries each keystroke across, and says how long one takes.
    final times = <int>[];
    for (final letter in ' to the coast 🌊'.runes.map(String.fromCharCode)) {
      final want = a.session.words + letter;
      final clock = Stopwatch()..start();
      await a.session.edit([CrdtEdit(a.session.words.length, insert: letter)], base: a.session.rev);
      await until(() => b.session.words == want, '"$letter" on the Mac');
      times.add(clock.elapsedMicroseconds);
    }
    times.sort();
    // ignore: avoid_print
    print('a keystroke reached the other device in ${(times[times.length ~/ 2] / 1000).toStringAsFixed(1)} ms (median), ${(times.last / 1000).toStringAsFixed(1)} ms at worst, over ${times.length}');
    await b.session.edit([const CrdtEdit(0, insert: '# ')], base: b.session.rev);
    await until(() => a.session.words == '# Weekend trip to the coast 🌊', 'the Mac\'s edit on the phone');

    // Keeps both people typing into the same spot at once.
    final at = a.session.words.indexOf('coast');
    await Future.wait([
      a.session.edit([CrdtEdit(at, insert: 'PHONE ')], base: a.session.rev),
      b.session.edit([CrdtEdit(at, insert: 'MAC ')], base: b.session.rev),
    ]);
    await until(() => a.session.words == b.session.words && a.session.words.contains('PHONE ') && a.session.words.contains('MAC '), 'both edits on both devices');

    // Lets a device that went away come back and catch up.
    mac.live!.hub.closeLive('note-trip');
    await a.session.edit([CrdtEdit(a.session.words.length, insert: '. Leave at eight.')], base: a.session.rev);
    final back = await open(mac, 'note-trip', 'stale words');
    expect(await back.shown, a.session.words);
    expect(back.copies, isEmpty);

    // The app behind another: no socket, and the room empties of it; in front again, it is back and whole.
    mac.live!.paused();
    await until(() => !phone.live!.shared.isShared('note-trip'), 'the phone to see the Mac go');
    await a.session.edit([CrdtEdit(0, insert: '(at the weekend) ')], base: a.session.rev);
    mac.live!.resumed();
    await until(() => back.session.words == a.session.words, 'the Mac to be whole again after resting');

    // Never gives the relay the words: nothing the service keeps holds them.
    final data = Platform.environment['GHOST_E2E_DATA'] ?? '';
    if (data.isNotEmpty) {
      final bytes = [for (final file in Directory(data).listSync().whereType<File>()) String.fromCharCodes(file.readAsBytesSync())].join();
      for (final word in ['Weekend', 'coast', 'Leave at eight']) {
        expect(bytes.contains(word), isFalse, reason: 'the service kept "$word"');
      }
    }
    phone.live!.hub.closeLive('note-trip');
    mac.live!.hub.closeLive('note-trip');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('a team note live between two members: each one\'s typing on the other\'s device as it is made, their carets where they are, who is where on the dashboard, and a member\'s pass run by a word in the room', () async {
    final owner = freshHandle('ada'), member = freshHandle('ben');
    final ada = device('ada'), ben = device('ben');
    await ada.account.signUp(owner, 'correct horse');
    await ben.account.signUp(member, 'another password, ben\'s');
    final org = await ada.orgs.createOrg('Ghost');
    await ada.orgs.setOrgColour(org.id, 'rose');
    await ada.sync();
    ada.write('t1', '# Plan\n- a 😀');
    ada.workspaces.fileNote('t1', orgWorkspaceId(org.id));
    await ada.sync();
    await ada.orgs.inviteByHandle(org.id, member);
    await ben.engine.syncNotificationsNow();
    ben.feed.answerInvite(org.id, true);
    // Ben has no key yet: the word in the organization's `sync` room has Ada wrap it for him and him read it and
    // fetch the team's notes, with no pass asked for by hand on either side.
    await ben.engine.syncNow();
    await until(() => ben.notes['t1']?.body == '# Plan\n- a 😀', 'the team\'s note on Ben\'s device by the nudge alone', within: const Duration(seconds: 20));
    expect(ben.orgKeys.orgKeyOf(org.id), isNotNull);
    await ada.engine.syncNow();
    await ben.engine.syncNow();

    // Both in the organization's own room, by the watch alone.
    await until(() => ada.live!.presence.presenceIn(org.id).any((seen) => seen.handle == member), 'Ben on Ada\'s dashboard');
    await until(() => ben.live!.presence.presenceIn(org.id).any((seen) => seen.handle == owner && seen.hue == 'rose'), 'Ada, in rose, on Ben\'s dashboard');

    // The note opened on both, as its editor opens it: the document, then its room.
    Future<(TeamDoc, TeamRoom)> opened(Device on) async {
      final doc = (await on.docs.doc('t1', seedWords: on.notes['t1']!.body))!;
      await doc.reconcile(on.notes['t1']!.body);
      // The note's screen saves what its editor holds: the library follows the document, whoever typed.
      doc.onWords((words) => on.write('t1', words, at: 9));
      doc.onUpdate((_) => on.write('t1', doc.words, at: 9));
      return (doc, on.live!.rooms.openTeamRoom(org.id, 't1', doc)!);
    }

    final (docA, roomA) = await opened(ada);
    final (docB, roomB) = await opened(ben);
    ada.live!.presence.announce(org.id, const Whereabouts(note: 't1', title: 'Plan'));
    await until(() => roomA.others == 1 && roomB.others == 1, 'both in the note\'s room');
    await until(() => ben.live!.presence.presenceIn(org.id).any((seen) => seen.at?.title == 'Plan'), '"editing Plan" beside Ada on Ben\'s dashboard');

    await docA.edit([CrdtEdit(docA.words.length, insert: '\n- ada\'s')], base: docA.rev);
    await until(() => docB.words == '# Plan\n- a 😀\n- ada\'s', 'Ada\'s line on Ben\'s device');
    await docB.edit([const CrdtEdit(6, insert: ' (ben)')], base: docB.rev);
    await until(() => docA.words == '# Plan (ben)\n- a 😀\n- ada\'s', 'Ben\'s words on Ada\'s device');

    // Ada's selection, as her editor says it; Ben places it in his own copy, and it moves with what he types before
    // it.
    final from = docA.words.indexOf('ada'), to = docA.words.length;
    roomA.setField('cursor', {'anchor': await docA.crdt.relative(from), 'head': await docA.crdt.relative(to)});
    Map<String, Object?>? adasCaret() => roomB.states.entries.where((each) => each.key != roomB.clientId).map((each) => each.value['cursor']).whereType<Map<Object?, Object?>>().firstOrNull?.cast<String, Object?>();
    await until(() => adasCaret() != null, 'Ada\'s caret in Ben\'s room');
    expect(await docB.crdt.caretIndexes(adasCaret()), (anchor: from, head: to));
    expect(Me.of(roomB.states.entries.firstWhere((each) => each.key != roomB.clientId).value['user']), Me(name: owner, hue: 'rose'));
    await docB.edit([const CrdtEdit(0, insert: '> ')], base: docB.rev);
    expect(await docB.crdt.caretIndexes(adasCaret()), (anchor: from + 2, head: to + 2));

    // What was typed live is still posted to the log by a pass, so a device that was not in the room reads it.
    await until(() => docA.words == docB.words, 'the two to agree');
    final merged = docA.words;
    await ada.sync();
    await ben.sync();
    final laptop = device('ada\'s laptop');
    await laptop.account.signIn(owner, 'correct horse');
    await laptop.engine.syncNow();
    await until(() => laptop.notes['t1']?.body == merged, 'the laptop to read what was typed live', within: const Duration(seconds: 20));

    // Ada closes the note: her caret is gone from Ben's room the moment her connection leaves it.
    roomA.close();
    ada.live!.presence.announce(org.id, null);
    await until(() => roomB.states.length == 1 && roomB.others == 0, 'Ada gone from the note\'s room');
    await until(() => ben.live!.presence.presenceIn(org.id).every((seen) => seen.at == null), 'Ada editing nothing on Ben\'s dashboard');
    roomB.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
