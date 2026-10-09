// The Flutter app's live code and the WEB app's, typing in the same note at once through the REAL relay on
// 127.0.0.1: a Dart device (lib/live over the Rust core's yrs and its awareness) and a web device (tool/web_live.mjs:
// ../glyph/src/app/core/live with its own Yjs, its own y-protocols and its own WebCrypto, under Node), in a team
// note's room and in a room of one account's own.
//
//   tool/local-server.sh start
//   GHOST_E2E_API=http://127.0.0.1:<port>/api flutter test --no-pub test/live/web_test.dart
//
// Skipped unless GHOST_E2E_API is set (and names 127.0.0.1), the Mac's core is built, `node` is on the PATH and
// ../glyph has its node_modules. The Node side refuses any host but 127.0.0.1, for its requests and its sockets.
//
// What this proves: the two clients agree on the relay's frames, on the seal of a live message (`live:<note>`
// under the account key, `live:org:<org>:<room>` under the organization key), on the kinds and their payloads
// (a state vector asked, the difference answered; a seed and a whole document), on the CRDT's updates as they are
// typed, and on the awareness's (who a device is, its colours, its caret as relative positions), in BOTH directions.
// The web side is its live modules driven as its editor drives them; not y-codemirror and not a browser.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/session.dart';
import 'package:ghost_md/live/team.dart';
import 'package:ghost_md/team/crdt.dart';

import '../e2e/world.dart';
import 'local_server_test.dart' show until;
import 'support.dart';
import 'web_device.dart';

void main() {
  final base = Platform.environment['GHOST_E2E_API'] ?? '';
  final skip = webSkip(base) ?? coreSkip;
  late GhostCore core;
  late LocalWorld world;
  final devices = <Device>[];
  final webs = <WebDevice>[];

  setUpAll(() async {
    if (skip != null) return;
    world = LocalWorld(base);
    core = await openCore();
  });
  tearDownAll(() async {
    for (final each in webs) {
      await each.close();
    }
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

  Future<WebDevice> web(Map<String, Object?> job) async {
    final made = await WebDevice.start(base, {'rounds': e2eRounds, ...job});
    webs.add(made);
    return made;
  }

  test('a team note typed in by the Flutter app and the web app at once: each one\'s keys on the other as they are made, both typing into one spot kept, and each one\'s caret placed in the other\'s copy', () async {
    final owner = freshHandle('ada'), member = freshHandle('web');
    final ada = device('ada');
    await ada.account.signUp(owner, 'correct horse');
    final org = await ada.orgs.createOrg('Ghost');
    await ada.orgs.setOrgColour(org.id, 'sea');
    await ada.sync();
    ada.write('t1', '# Plan\n- a 😀');
    ada.workspaces.fileNote('t1', orgWorkspaceId(org.id));
    await ada.sync();
    // The member is made by a Dart device (the web client signs in, it does not sign up), invited, and let go of.
    final maker = device('the member\'s first device');
    await maker.account.signUp(member, 'the web member\'s password');
    await ada.orgs.inviteByHandle(org.id, member);
    await maker.engine.syncNotificationsNow();
    maker.feed.answerInvite(org.id, true);
    await maker.engine.syncNow();
    await until(() => maker.notes['t1'] != null, 'the member to be given the key and the note', within: const Duration(seconds: 20));
    await maker.close();

    // The note open in the Flutter app, as its editor opens it.
    final doc = (await ada.docs.doc('t1', seedWords: ada.notes['t1']!.body))!;
    doc.onWords((words) => ada.write('t1', words, at: 9));
    doc.onUpdate((_) => ada.write('t1', doc.words, at: 9));
    final room = ada.live!.rooms.openTeamRoom(org.id, 't1', doc)!;

    // And in the web app, as another member.
    final other = await web({'handle': member, 'password': 'the web member\'s password', 'team': {'note': 't1'}});
    expect(other.hello['words'], '# Plan\n- a 😀');
    await until(() => room.others == 1, 'the web device in the room');

    // Flutter types; the web has it as it is made.
    for (final letter in '\n- from Flutter 👻'.runes.map(String.fromCharCode)) {
      await doc.edit([CrdtEdit(doc.words.length, insert: letter)], base: doc.rev);
    }
    await other.until({'words': '# Plan\n- a 😀\n- from Flutter 👻'}, 'what Flutter typed');

    // The web types; Flutter has it as it is made.
    await other.ask({'do': 'type', 'at': 6, 'insert': ' (web)'});
    await until(() => doc.words == '# Plan (web)\n- a 😀\n- from Flutter 👻', 'what the web typed');
    // A whole emoji typed and taken back on the web, as its editor does it.
    await other.ask({'do': 'type', 'at': 0, 'insert': '🌍 '});
    await until(() => doc.words.startsWith('🌍 # Plan'), 'the web\'s emoji');
    await other.ask({'do': 'type', 'at': 0, 'remove': 3});
    await until(() => doc.words.startsWith('# Plan (web)'), 'the web\'s emoji taken back');

    // Both into one spot at the same moment: neither has heard the other.
    final at = doc.words.indexOf('- a');
    final mine = doc.edit([CrdtEdit(at, insert: 'FLUTTER ')], base: doc.rev);
    final theirs = other.ask({'do': 'type', 'at': at, 'insert': 'WEB '});
    await Future.wait([mine, theirs]);
    await until(() => doc.words.contains('FLUTTER ') && doc.words.contains('WEB '), 'both edits in Flutter');
    final merged = doc.words;
    await other.until({'words': merged}, 'the same words as Flutter holds');

    // Flutter's caret, said as relative positions the core made, placed by the web's own Yjs; with who it is and
    // the colours the page draws it in.
    final from = merged.indexOf('from'), to = from + 4;
    room.setField('cursor', {'anchor': await doc.crdt.relative(from), 'head': await doc.crdt.relative(to)});
    final seen = await other.until({'name': owner, 'caret': to}, 'Flutter\'s caret');
    final ada_ = ((seen['others'] as List).single as Map);
    expect(ada_['caret'], {'anchor': from, 'head': to});
    expect(ada_['user'], {'name': owner, 'hue': 'sea', 'color': 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 230)', 'colorLight': 'oklch(var(--app-hue-lift) var(--app-hue-chroma) 230 / 0.24)'});

    // The web's caret, as y-codemirror says it, placed by the core in Flutter's copy.
    final webAt = merged.indexOf('Plan');
    await other.ask({'do': 'cursor', 'anchor': webAt, 'head': webAt + 4});
    Map<String, Object?>? webs_() => room.states.entries.where((each) => each.key != room.clientId).map((each) => each.value).firstOrNull;
    await until(() => webs_()?['cursor'] != null, 'the web\'s caret in Flutter\'s room');
    expect(await doc.crdt.caretIndexes(webs_()!['cursor']), (anchor: webAt, head: webAt + 4));
    expect(Me.of(webs_()!['user'])?.name, member);
    // It rides what Flutter types before it.
    await doc.edit([const CrdtEdit(0, insert: '>> ')], base: doc.rev);
    expect(await doc.crdt.caretIndexes(webs_()!['cursor']), (anchor: webAt + 3, head: webAt + 7));
    await other.until({'name': owner, 'caret': to + 3}, 'Flutter\'s caret moved by what Flutter typed');

    // The web's pass posts what it typed to the note's log, as a page does a few seconds after a key; then it
    // leaves, and its caret is gone from Flutter's room with its connection.
    await other.ask({'do': 'sync'});
    await other.close();
    webs.remove(other);
    await until(() => room.states.length == 1 && room.others == 0, 'the web gone from Flutter\'s room');

    // What both typed is the team's by the pass, and a web device signing in afresh reads it from the service.
    await ada.sync();
    final later = await web({'handle': member, 'password': 'the web member\'s password', 'team': {'note': 't1'}});
    expect(later.hello['words'], doc.words);
    room.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('an emoji swapped for a near one by a web member (the web\'s applyTextDiff cuts it in two): the Flutter app takes the update, reads what every other member reads, and goes on typing with the team', () async {
    final handle = freshHandle('emoji');
    final ada = device('ada');
    await ada.account.signUp(handle, 'correct horse');
    final org = await ada.orgs.createOrg('Ghost');
    await ada.sync();
    ada.write('t1', 'mood 😀 today');
    ada.workspaces.fileNote('t1', orgWorkspaceId(org.id));
    await ada.sync();
    final doc = (await ada.docs.doc('t1', seedWords: ada.notes['t1']!.body))!;
    final room = ada.live!.rooms.openTeamRoom(org.id, 't1', doc)!;
    final writer = await web({'handle': handle, 'password': 'correct horse', 'team': {'note': 't1'}});
    final hearer = await web({'handle': handle, 'password': 'correct horse', 'team': {'note': 't1'}});
    await until(() => room.others == 2, 'both web devices in the room');

    // Words reach the note on the web without its editor (a capture, the connector, a sync of the library): 😀
    // made 😁, which share their first half. core/team/textDiff.ts keeps that half and swaps the second.
    final made = await writer.ask({'do': 'reconcile', 'words': 'mood 😁 today'});
    // The web device that made it holds half a character: U+FFFD, then a lone low surrogate.
    expect((made['text'] as String).codeUnits.sublist(5, 7), [0xFFFD, 0xDE01]);
    // Every other member reads U+FFFD twice: the other web device, by its own Yjs...
    const heard = 'mood \uFFFD\uFFFD today';
    await hearer.until({'words': heard}, 'the cut emoji as Yjs reads it');
    // ...and the Flutter app, which used to refuse the update and stop following the note.
    await until(() => doc.words == heard, 'the cut emoji in the Flutter app');

    // The note is still one note: Flutter types into it, a whole emoji where the broken one is, and both web
    // devices follow; the web types, and Flutter follows.
    await doc.edit([const CrdtEdit(5, remove: 2, insert: '😁')], base: doc.rev);
    await hearer.until({'words': 'mood 😁 today'}, 'Flutter\'s mending on the web device that heard');
    await hearer.ask({'do': 'type', 'at': 0, 'insert': 'My '});
    await until(() => doc.words == 'My mood 😁 today', 'the web\'s typing after the cut');
    // What Flutter holds is a document the web reads whole: a web device signing in afresh, by the service.
    doc.onUpdate((_) {});
    ada.write('t1', doc.words, at: 9);
    await hearer.ask({'do': 'sync'});
    await writer.ask({'do': 'sync'});
    await ada.sync();
    await ada.sync();
    final fresh = await web({'handle': handle, 'password': 'correct horse', 'team': {'note': 't1'}});
    expect(fresh.hello['words'], 'My mood 😁 today');
    room.close();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));

  test('a note of the account\'s own, live in the Flutter app and the web app: made by one and adopted by the other, both ways, and typed in by both', () async {
    final handle = freshHandle('own');
    final phone = device('phone');
    await phone.account.signUp(handle, 'correct horse');
    phone.live!.enabled.set(true);

    Future<({LiveSession session, List<String> ready})> open(String note, String words) async {
      final ready = <String>[];
      final session = await phone.live!.hub.openLive(note, words, SessionListener(ready: ready.add, peers: (_) {}), SyncHooks(hasUnsynced: (_) async => false, keepCopy: (_, _) async {}));
      return (session: session!, ready: ready);
    }

    // Made in Flutter, adopted by the web: the seed id and the whole document, sealed under the account key.
    final a = await open('note-a', 'Weekend trip 🌊');
    await until(() => a.ready.isNotEmpty, 'Flutter to make the document');
    final webA = await web({'handle': handle, 'password': 'correct horse', 'own': {'note': 'note-a', 'words': 'stale on the web'}});
    expect(webA.hello['shown'], 'Weekend trip 🌊');
    await a.session.edit([CrdtEdit(a.session.words.length, insert: ' to the coast')], base: a.session.rev);
    await webA.until({'words': 'Weekend trip 🌊 to the coast'}, 'what Flutter typed');
    await webA.ask({'do': 'type', 'at': 0, 'insert': '# '});
    await until(() => a.session.words == '# Weekend trip 🌊 to the coast', 'what the web typed');
    final at = a.session.words.indexOf('coast');
    await Future.wait([
      a.session.edit([CrdtEdit(at, insert: 'FLUTTER ')], base: a.session.rev),
      webA.ask({'do': 'type', 'at': at, 'insert': 'WEB '}),
    ]);
    await until(() => a.session.words.contains('FLUTTER ') && a.session.words.contains('WEB '), 'both edits in Flutter');
    await webA.until({'words': a.session.words}, 'the same words as Flutter holds');

    // Made on the web, adopted by Flutter.
    final webB = await web({'handle': handle, 'password': 'correct horse', 'own': {'note': 'note-b', 'words': 'Made on the web 🕸'}});
    expect(webB.hello['shown'], 'Made on the web 🕸');
    final b = await open('note-b', 'stale in Flutter');
    await until(() => b.ready.isNotEmpty, 'Flutter to adopt the web\'s document');
    expect(b.ready, ['Made on the web 🕸']);
    await b.session.edit([const CrdtEdit(0, insert: '> ')], base: b.session.rev);
    await webB.until({'words': '> Made on the web 🕸'}, 'what Flutter typed into the web\'s document');
    await webB.ask({'do': 'type', 'at': 2, 'remove': 4, 'insert': 'Typed'});
    await until(() => b.session.words == '> Typed on the web 🕸', 'what the web typed into its own');
    phone.live!.hub.closeLive('note-a');
    phone.live!.hub.closeLive('note-b');
  }, skip: skip, timeout: const Timeout(Duration(minutes: 3)));
}
