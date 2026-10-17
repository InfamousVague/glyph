// Claude, live (docs/CLAUDE_LIVE.md), with the real crypto, the real CRDT and its awareness over a relay in memory:
// the account's own presence room (lib/live/presence.dart, team.dart), an AI's entry gathered from it and from an
// organization's and never taken for a member, Claude's caret in a personal note while the account's other device's
// stays hidden (lib/live/session.dart, editor_binding.dart), and Follow keeping that caret in view until Stop or the
// person's own doing (lib/live/follow.dart).
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/crypto_api.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/marks/wisp_motion.dart' show WispKind, wisp;
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/live/editor_binding.dart';
import 'package:ghost_md/live/enabled.dart';
import 'package:ghost_md/live/follow.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/presence.dart';
import 'package:ghost_md/live/session.dart';
import 'package:ghost_md/live/team.dart';
import 'package:ghost_md/live/transport.dart';
import 'package:ghost_md/live/wire.dart';
import 'package:ghost_md/team/crdt.dart';

import 'support.dart';

const Me claude = Me(name: 'Claude', hue: 'violet', ai: true, via: 'matt');

void main() {
  late GhostCore core;
  late CoreCrypto crypto;
  late Crdt crdt;

  setUpAll(() async {
    if (!coreBuilt) return;
    core = await openCore();
    crypto = CoreCrypto(core.invoke);
    crdt = Crdt(core.invoke);
  });
  tearDownAll(() async {
    if (coreBuilt) await core.close();
  });

  Future<SealKey> accountKey() async => crypto.settle(await crypto.newAccountKey());

  LiveHub hubOn(Relay relay) => LiveHub(LiveHubDeps(url: 'ws://relay.test/live', token: () => 't', crypto: crypto, crdt: crdt, connect: relay.line));

  /// A room of someone else's on the relay: another device, or the connector.
  TeamRoom room(Relay relay, SealKey key, String? org, Me me) {
    final hub = hubOn(relay);
    final made = TeamRoom(org, presenceRoom, me, RoomDeps(key: key, crypto: crypto, crdt: crdt, hold: hub.holdRoom, release: hub.releaseRoom));
    relay.waits.add(made.sent);
    return made;
  }

  Future<void> quiet(Relay relay) async {
    for (var i = 0; i < 5; i += 1) {
      await relay.settled();
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    await relay.settled();
  }

  group('live typing for personal notes', () {
    test('is on unless this device turned it off, and one turned on by hand while it was a trial stays on', () {
      final kept = MemoryStored();
      final live = LiveEnabled(kept);
      expect((live.value, kept.readText(liveFlagKey)), (true, null));
      var told = 0;
      live.addListener(() => told += 1);
      live.set(false);
      expect((live.value, kept.readText(liveFlagKey), told), (false, '0', 1));
      live.set(true);
      expect((live.value, kept.readText(liveFlagKey), told), (true, '1', 2));
      expect(LiveEnabled(MemoryStored()..writeText(liveFlagKey, '1')).value, isTrue);
      expect(LiveEnabled(MemoryStored()..writeText(liveFlagKey, '0')).value, isFalse);
    });
  });

  group('the account\'s own presence room', () {
    test('is held while signed in, sealed under the account key for the room, says this device\'s personal note, and gathers the AI there and in an organization\'s, never as a member', () async {
      final relay = Relay();
      final account = await accountKey();
      final org = await crypto.newOrgKey();
      final changes = ChangeNotifier();
      var signedIn = true;
      final lines = <RelayLine>[];
      final hubA = LiveHub(LiveHubDeps(url: 'ws://relay.test/live', token: () => 't', crypto: crypto, crdt: crdt, connect: (events) => relay.line(events)..also(lines.add)));
      final rooms = TeamRooms(
        hub: hubA,
        crypto: crypto,
        crdt: crdt,
        orgKeyOf: (_) => org,
        handle: () => signedIn ? 'matt' : null,
        colourIn: (_) => 'rose',
        accountKey: () async => account,
        accountColour: () => 'rose',
        tick: null,
      );
      final presence = Presence(rooms);
      // Said before the room came: a personal note open.
      presence.announceAccount(const Whereabouts(note: 'p1', title: 'Groceries'));
      final stop = presence.watch(PresenceWatch(signedIn: () => signedIn, localOnly: () => false, joined: () => ['o1'], hasKey: (_) => true, changes: [changes]));
      await quiet(relay);
      expect(presence.holdsAccount, isTrue);
      expect(hubA.heldRooms()..sort(), ['o1/presence', 'presence']);

      // What this device says there is sealed under the account key for the room `presence` (`live:presence`), and
      // opens under nothing else.
      final said = lines.single.sent.firstWhere((frame) => frame.startsWith('presence:')).substring('presence:'.length);
      expect((await openEnvelope(crypto, account, presenceRoom, said)).kind, Kind.presence);
      await expectLater(openEnvelope(crypto, account, 'p1', said), throwsA(anything));
      await expectLater(openTeamEnvelope(crypto, org, 'o1', presenceRoom, said), throwsA(anything));

      // The account's phone, and its connector: Claude editing the note, here and (on no note) in the organization's.
      final phone = room(relay, account, null, const Me(name: 'matt', hue: 'rose'));
      final connector = room(relay, account, null, claude);
      final inOrg = room(relay, org, 'o1', claude);
      connector.setField('at', const Whereabouts(note: 'p1', title: 'Groceries', doing: 'editing').toJson());
      await quiet(relay);

      expect([for (final each in presence.accountPresence()) (each.handle, each.ai, each.via)]..sort((a, b) => a.$1.compareTo(b.$1)), [('Claude', true, 'matt'), ('matt', false, null)]);
      expect([for (final each in presence.presenceIn('o1')) (each.handle, each.ai, each.at)], [('Claude', true, null)]);
      final ais = presence.aisOnline();
      expect([for (final ai in ais) (ai.name, ai.via, ai.hue, ai.doing, ai.at?.note, ai.org, ai.words)], [('Claude', 'matt', 'violet', 'editing', 'p1', null, 'editing Groceries')]);
      // The phone hears where this device is.
      final mine = phone.states.entries.firstWhere((each) => each.key != phone.clientId && (each.value['user'] as Map?)?['name'] == 'matt').value;
      expect((mine['at'] as Map)['title'], 'Groceries');

      // Reading another note in the organization: the room that says it is on a note is the one kept.
      connector.setField('at', null);
      inOrg.setField('at', const Whereabouts(note: 't1', title: 'Roadmap', doing: 'reading').toJson());
      await quiet(relay);
      expect([for (final ai in presence.aisOnline()) (ai.doing, ai.at?.note, ai.org, ai.words)], [('reading', 't1', 'o1', 'reading Roadmap')]);

      // Gone from both rooms, it is not online.
      connector.close();
      inOrg.close();
      await quiet(relay);
      expect(presence.aisOnline(), isEmpty);

      // Signed out, the room goes.
      signedIn = false;
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      changes.notifyListeners();
      expect(presence.holdsAccount, isFalse);
      expect(presence.accountPresence(), isEmpty);
      stop();
      phone.close();
    }, skip: coreSkip);
  });

  group('a personal note with Claude in it', () {
    EditorView editor(String words, List<int> scrolled, List<String> smoky) => EditorView(
          wholeDocument: true,
          state: EditorState.create(
            doc: words,
            extensions: Extension.list(<Extension>[
              undoSlot.of(localUndo()),
              liveBindingSlot(),
              EditorViewLike.updateListener.of((update) {
                for (final tr in update.transactions) {
                  if (tr.annotation(wisp) == WispKind.typed) smoky.add(tr.changes.toString());
                  for (final effect in tr.effects) {
                    final target = EditorViewLike.scrollIntoViewEffect.cast(effect);
                    if (target != null) scrolled.add(target.value.range.head);
                  }
                }
              }),
            ]),
          ),
        )..setFocused(true);

    ({LiveSession session, RelayLine line}) device(Relay relay, SealKey key, String words) {
      late final LiveSession session;
      final line = relay.line(LiveEvents(
        ready: (_) {},
        joined: (room, first, peers, org) => session.joined(first, peers),
        peers: (room, peers, org, left) => session.peersChanged(peers, left),
        message: (room, from, data, org) => session.message(from, data),
        down: (_) {},
      ));
      session = LiveSession('p1', words, SessionDeps(transport: line, key: key, crypto: crypto, crdt: crdt, hasUnsynced: (_) async => false, keepCopy: (_, _) async {}, schedule: (run, ms) => null), SessionListener(ready: (_) {}, peers: (_) {}));
      relay.waits.add(session.sent);
      return (session: session, line: line);
    }

    /// Who a device is and where its caret is, said in the note's room as y-codemirror says it.
    Future<CrdtRoom> say(({LiveSession session, RelayLine line}) on, SealKey key, Me who, int at) async {
      final doc = await on.session.document;
      final aware = await crdt.room(doc.clientId);
      await aware.setField('user', who.toJson());
      final place = await doc.relative(at);
      await aware.setField('cursor', {'anchor': place, 'head': place});
      on.line.send('p1', await sealEnvelope(crypto, key, 'p1', Envelope(Kind.presence, await aware.encode([doc.clientId]))));
      return aware;
    }

    test('draws Claude\'s caret with its name, never the account\'s other device\'s, and Follow keeps it in view until Stop or the person\'s own doing', () async {
      final relay = Relay();
      final key = await accountKey();
      final phone = device(relay, key, 'Groceries\n- milk\n- eggs');
      await quiet(relay);
      final mac = device(relay, key, 'Groceries\n- milk\n- eggs');
      final connector = device(relay, key, '');
      await quiet(relay);
      expect([phone.session.state, mac.session.state, connector.session.state], everyElement(SessionState.ready));

      final scrolled = <int>[];
      final smoky = <String>[];
      final view = editor(phone.session.words, scrolled, smoky);
      final binding = LiveBinding(view, phone.session, room: phone.session.carets, positions: await phone.session.document, smoke: () => true)..bind();

      // The Mac says its caret (as a web device would), and Claude says its own at the end of "milk".
      await say(mac, key, const Me(name: 'matt', hue: 'rose'), 2);
      final aware = await say(connector, key, claude, 16);
      await quiet(relay);
      expect([for (final caret in remoteCaretsOf(view.state)) (caret.name, caret.ai, caret.hue, caret.head)], [('Claude', true, 'violet', 16)]);
      expect(binding.carets.value.map((caret) => caret.name), ['Claude']);

      // Follow: the note opened for it, and Claude's caret scrolled to the middle.
      final online = ValueNotifier<List<AiOnline>>([AiOnline(name: 'Claude', client: 1, hue: 'violet', via: 'matt', at: const Whereabouts(note: 'p1', title: 'Groceries', doing: 'editing'))]);
      final bound = BoundEditors();
      final follow = FollowAi(online: () => online.value, changes: online, bound: bound);
      final opened = <String>[];
      final notices = <String>[];
      follow
        ..open = (ai, note) {
          opened.add(note);
          bound.put(note, binding);
          return true;
        }
        ..onEditing = ((ai) => notices.add(ai.at!.title))
        ..shown = (() => null);
      follow.start();
      // Claude was editing when first heard, and nobody followed: the notice.
      expect(notices, ['Groceries']);
      follow.follow(follow.ais.single);
      expect(opened, ['p1']);
      expect((follow.following?.name, scrolled.last), ('Claude', 16));

      // Claude types on: its caret moves, and the page with it.
      await connector.session.edit([const CrdtEdit(16, insert: ' and bread')], base: connector.session.rev);
      final moved = await (await connector.session.document).relative(26);
      connector.line.send('p1', await sealEnvelope(crypto, key, 'p1', Envelope(Kind.presence, (await aware.setField('cursor', {'anchor': moved, 'head': moved}))!)));
      await quiet(relay);
      expect(phone.session.words, 'Groceries\n- milk and bread\n- eggs');
      expect(scrolled.last, 26);
      // With Ghostly typing on, Claude's words arrived out of smoke (the recorder's `heard`).
      expect(smoky, hasLength(1));

      // Stop, from the bar.
      follow.stop();
      expect(follow.isFollowing, isFalse);

      // Followed again, a press in the note is the person's own: Follow stops.
      follow.follow(follow.ais.single);
      expect(follow.isFollowing, isTrue);
      for (final observer in view.eventObservers) {
        observer.pointerDown?.call(const PointerDownEvent(), view);
      }
      expect(follow.isFollowing, isFalse);

      // And typing.
      follow.follow(follow.ais.single);
      view.dispatch(TransactionSpec(changes: const Change(from: 0, insert: '# '), userEvent: 'input.type'));
      expect(follow.isFollowing, isFalse);

      // Claude moves to another note while nobody follows: a notice for it, once.
      online.value = [AiOnline(name: 'Claude', client: 1, hue: 'violet', via: 'matt', at: const Whereabouts(note: 'p2', title: 'Plan', doing: 'editing'))];
      online.value = [AiOnline(name: 'Claude', client: 1, hue: 'violet', via: 'matt', at: const Whereabouts(note: 'p2', title: 'Plan', doing: 'editing', cursor: {'anchor': 1}))];
      expect(notices, ['Groceries', 'Plan']);
      // Followed there, it follows to the next note; and gone, Follow ends.
      follow.follow(follow.ais.single);
      expect(opened.last, 'p2');
      online.value = [AiOnline(name: 'Claude', client: 1, hue: 'violet', via: 'matt', at: const Whereabouts(note: 'p3', title: 'Next', doing: 'editing'))];
      expect(opened.last, 'p3');
      online.value = const [];
      expect(follow.isFollowing, isFalse);

      // The connector leaves the room: its caret goes with it.
      connector.session.close();
      await quiet(relay);
      expect(remoteCaretsOf(view.state), isEmpty);
      follow.dispose();
      binding.unbind();
      phone.session.close();
      mac.session.close();
    }, skip: coreSkip);
  });
}

extension<T> on T {
  T also(void Function(T it) run) {
    run(this);
    return this;
  }
}
