// Who is on a team's page (lib/team/presence.dart, presence_avatars.dart; docs/TEAMSPACES.md, "Presence"): the
// organizations' rooms read by page, this account and the AIs left out, each member once with since when; the
// avatars in the header of every version of the header toolbar and in simple mode's, three and then +N, a press
// listing who; the dot beside a sidebar row. And two devices over the relay in memory with the real crypto and the
// real awareness (test/live/support.dart): a page shows the other member as they open it, not as they move their
// caret, and stops as they close it or their app goes behind another, with nothing of the page said in the clear.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/presence.dart';
import 'package:ghost_md/live/team.dart';
import 'package:ghost_md/note/note_tools.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:ghost_md/shell/top_bar_tools.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/presence_avatars.dart';

import '../live/support.dart';
import '../notes/bar_support.dart';
import '../support/render.dart';

/// The rooms as a test has them: who each organization's room has, and the word that it changed.
class _Rooms extends ChangeNotifier {
  Map<String, List<Seen>> rooms = {};

  void set(Map<String, List<Seen>> next) {
    rooms = next;
    notifyListeners();
  }
}

Seen _on(String handle, String? note, {int client = 1, String? hue, bool ai = false, Map<String, Object?>? cursor}) =>
    Seen(handle: handle, hue: hue, client: client, ai: ai, at: note == null ? null : Whereabouts(note: note, title: 'Roadmap', cursor: cursor));

PresentMember _member(String name, {String? hue}) => PresentMember(id: name.toLowerCase(), name: name, hue: hue, since: DateTime(2026, 10, 31, 9), org: 'o1');

void main() {
  group('the rooms read by page', () {
    late _Rooms rooms;
    late DateTime now;
    late PagePresence pages;
    var told = 0;
    setUp(() {
      rooms = _Rooms();
      now = DateTime(2026, 10, 31, 10);
      told = 0;
      pages = PagePresence(read: () => rooms.rooms, changes: rooms, self: () => 'matt', clock: () => now)..addListener(() => told += 1);
    });
    tearDown(() => pages.dispose());

    test('puts each member on the page their device has open, once each, in the colour they wear, and nobody on a page nobody has open', () {
      rooms.set({
        'o1': [_on('ana', 'n1', client: 1, hue: 'sea'), _on('ana', 'n1', client: 2, hue: 'sea'), _on('sam', 'n2', client: 3)],
        'o2': [_on('lee', 'n3', client: 4, hue: 'rose')],
      });
      expect(pages.value.keys.toSet(), {'n1', 'n2', 'n3'});
      expect([for (final m in pages.presenceOn('n1')) (m.id, m.name, m.hue, m.org, m.initial)], [('ana', 'ana', 'sea', 'o1', 'A')]);
      expect([for (final m in pages.presenceOn('n3')) (m.name, m.org)], [('lee', 'o2')]);
      expect(pages.presenceOn('nobody-here'), isEmpty);
      expect(told, 1);
    });

    test('leaves out this account, on any of its devices and however it is spelt, an AI, and a device on no page', () {
      rooms.set({
        'o1': [_on('Matt', 'n1', client: 1), _on('matt', 'n1', client: 2), _on('Claude', 'n1', client: 3, ai: true), _on('ana', null, client: 4), _on('sam', 'n1', client: 5)],
      });
      expect([for (final m in pages.presenceOn('n1')) m.name], ['sam']);
      expect(pages.value.keys, ['n1']);
    });

    test('keeps since when each member came while they stay, in the order they came, and is told only when who is where is different', () {
      rooms.set({'o1': [_on('sam', 'n1', client: 1)]});
      final came = now;
      now = now.add(const Duration(minutes: 5));
      rooms.set({'o1': [_on('sam', 'n1', client: 1), _on('ana', 'n1', client: 2)]});
      expect([for (final m in pages.presenceOn('n1')) (m.name, m.since)], [('sam', came), ('ana', now)]);
      expect(told, 2);
      // A caret moving is said in the room and changes nothing here.
      now = now.add(const Duration(minutes: 1));
      rooms.set({'o1': [_on('sam', 'n1', client: 1, cursor: {'anchor': 'a', 'head': 'b'}), _on('ana', 'n1', client: 2)]});
      expect(told, 2);
      expect(pages.presenceOn('n1').first.since, came);
      // A colour picked while there is.
      rooms.set({'o1': [_on('sam', 'n1', client: 1, hue: 'moss'), _on('ana', 'n1', client: 2)]});
      expect(told, 3);
      expect(pages.presenceOn('n1').first.hue, 'moss');
    });

    test('lets a member go the moment their room does (they closed the page, their app went behind another, or the awareness forgot them unheard), and one who comes back is new', () {
      rooms.set({'o1': [_on('sam', 'n1', client: 1)]});
      rooms.set({'o1': [_on('sam', null, client: 1)]});
      expect(pages.presenceOn('n1'), isEmpty);
      expect(pages.value, isEmpty);
      now = now.add(const Duration(minutes: 2));
      rooms.set({'o1': [_on('sam', 'n1', client: 1)]});
      expect(pages.presenceOn('n1').single.since, now);
      // The room let go whole: signed out, local-only, or the organization left.
      rooms.set({});
      expect(pages.value, isEmpty);
      expect(told, 4);
    });

    test('moves a member from page to page, on whichever of their devices is on each', () {
      rooms.set({'o1': [_on('sam', 'n1', client: 1)]});
      rooms.set({'o1': [_on('sam', 'n2', client: 1)]});
      expect(pages.presenceOn('n1'), isEmpty);
      expect([for (final m in pages.presenceOn('n2')) m.name], ['sam']);
      rooms.set({'o1': [_on('sam', 'n2', client: 1), _on('sam', 'n1', client: 2)]});
      expect([for (final m in pages.presenceOn('n1')) m.name], ['sam']);
      expect([for (final m in pages.presenceOn('n2')) m.name], ['sam']);
    });

    test('hears no more once let go', () {
      pages.dispose();
      rooms.set({'o1': [_on('sam', 'n1')]});
      expect(told, 0);
      pages = PagePresence(read: () => rooms.rooms, changes: rooms, self: () => null);
      expect([for (final m in pages.presenceOn('n1')) m.name], ['sam']);
    });

    test('says who is here in words', () {
      expect(presenceWords([]), 'Nobody else is here');
      expect(presenceWords([_member('ana')]), 'ana is here');
      expect(presenceWords([_member('ana'), _member('sam')]), 'ana and sam are here');
      expect(presenceWords([_member('ana'), _member('sam'), _member('lee')]), 'ana, sam and lee are here');
      expect(presenceWords([_member('ana'), _member('sam'), _member('lee'), _member('jo')]), 'ana, sam and 2 others are here');
    });
  });

  group('drawn', () {
    setUpAll(loadAppFonts);

    /// A test that draws with the app's real shadows (pumpApp turns them on), and puts the binding's own switch back.
    void drawnTest(String description, Future<void> Function(WidgetTester tester) body) => testWidgets(description, (tester) async {
          await body(tester);
          debugDisableShadows = true;
        });

    Future<void> pumpOn(WidgetTester tester, Widget child, {PagePresence? presence}) async {
      await pumpApp(tester, home: PagePresenceScope(presence: presence, child: Center(child: child)));
    }

    drawnTest('three rounds and then +N, the first on top, and a press lists everyone', (tester) async {
      final five = [_member('ana', hue: 'sea'), _member('sam', hue: 'rose'), _member('lee'), _member('jo', hue: 'moss'), _member('kit')];
      await pumpOn(tester, PresenceAvatars(noteId: 'n1', members: five, coarse: false));
      for (final id in ['ana', 'sam', 'lee']) {
        expect(find.byKey(PresenceAvatars.avatarKey(id)), findsOneWidget, reason: id);
      }
      expect(find.byKey(PresenceAvatars.avatarKey('jo')), findsNothing);
      expect(find.descendant(of: find.byKey(PresenceAvatars.moreKey), matching: find.text('+2')), findsOneWidget);
      expect(find.text('A'), findsOneWidget);
      // Overlapping, the later ones further along.
      expect(tester.getRect(find.byKey(PresenceAvatars.avatarKey('sam'))).left, greaterThan(tester.getRect(find.byKey(PresenceAvatars.avatarKey('ana'))).left));
      expect(tester.getRect(find.byKey(PresenceAvatars.avatarKey('sam'))).overlaps(tester.getRect(find.byKey(PresenceAvatars.avatarKey('ana')))), isTrue);
      expect(find.bySemanticsLabel('ana, sam and 3 others are here'), findsOneWidget);

      expect(find.byKey(PresenceAvatars.listKey), findsNothing);
      await tester.tap(find.byKey(PresenceAvatars.avatarsKey));
      await tester.pumpAndSettle();
      expect(find.byKey(PresenceAvatars.listKey), findsOneWidget);
      for (final member in five) {
        expect(find.byKey(PresenceAvatars.lineKey(member.id)), findsOneWidget, reason: member.name);
      }
      expect(find.text('5 here now'), findsOneWidget);
    });

    drawnTest('two are two rounds and no +N; nobody is nothing at all', (tester) async {
      await pumpOn(tester, PresenceAvatars(noteId: 'n1', members: [_member('ana'), _member('sam')]));
      expect(find.byKey(PresenceAvatars.avatarKey('ana')), findsOneWidget);
      expect(find.byKey(PresenceAvatars.avatarKey('sam')), findsOneWidget);
      expect(find.byKey(PresenceAvatars.moreKey), findsNothing);
      await pumpOn(tester, const PresenceAvatars(noteId: 'n1', members: [], end: 8));
      expect(find.byKey(PresenceAvatars.avatarsKey), findsNothing);
      expect(tester.getSize(find.byType(PresenceAvatars)), Size.zero);
    });

    drawnTest('hear the scope for their own page: the avatars and the sidebar\'s dot come and go with the room, and the row\'s name stays itself', (tester) async {
      final rooms = _Rooms();
      final pages = PagePresence(read: () => rooms.rooms, changes: rooms, self: () => 'matt');
      addTearDown(pages.dispose);
      await pumpOn(
        tester,
        presence: pages,
        const SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PresenceAvatars(noteId: 'n1'),
              PresenceMarked(noteId: 'n1', child: _Name()),
              PresenceMarked(noteId: 'n2', child: Text('Elsewhere')),
            ],
          ),
        ),
      );
      final name = tester.state(find.byType(_Name));
      expect(find.byKey(PresenceAvatars.avatarsKey), findsNothing);
      expect(find.byKey(PresenceDot.keyOf('n1')), findsNothing);

      rooms.set({'o1': [_on('ana', 'n1', client: 1, hue: 'sea'), _on('sam', 'n1', client: 2), _on('matt', 'n2', client: 3)]});
      await tester.pump();
      expect(find.byKey(PresenceAvatars.avatarKey('ana')), findsOneWidget);
      expect(find.byKey(PresenceAvatars.avatarKey('sam')), findsOneWidget);
      expect(find.byKey(PresenceDot.keyOf('n1')), findsOneWidget);
      expect(find.bySemanticsLabel('ana and sam are here'), findsWidgets);
      // This account's own other device on n2 is not someone else there.
      expect(find.byKey(PresenceDot.keyOf('n2')), findsNothing);
      expect(identical(tester.state(find.byType(_Name)), name), isTrue, reason: 'the name keeps its state as the dot comes');
      // The dot after the name, on its line.
      expect(tester.getRect(find.byKey(PresenceDot.keyOf('n1'))).left, greaterThan(tester.getRect(find.byType(_Name)).left));

      rooms.set({'o1': [_on('ana', null, client: 1), _on('sam', 'n2', client: 2)]});
      await tester.pump();
      expect(find.byKey(PresenceAvatars.avatarsKey), findsNothing);
      expect(find.byKey(PresenceDot.keyOf('n1')), findsNothing);
      expect(find.byKey(PresenceDot.keyOf('n2')), findsOneWidget);
      expect(identical(tester.state(find.byType(_Name)), name), isTrue, reason: 'and as it goes');
    });

    drawnTest('draw nothing where there is no scope: a build with no account, signed out', (tester) async {
      await pumpOn(tester, const Column(mainAxisSize: MainAxisSize.min, children: [PresenceAvatars(noteId: 'n1'), PresenceDot(noteId: 'n1'), PresenceMarked(noteId: 'n1', child: Text('Roadmap'))]));
      expect(find.byKey(PresenceAvatars.avatarsKey), findsNothing);
      expect(find.byKey(PresenceDot.keyOf('n1')), findsNothing);
      expect(find.text('Roadmap'), findsOneWidget);
    });

    drawnTest('simple mode\'s header has them before its ⋯, and keeps its row as it was while nobody is there', (tester) async {
      await pumpOn(tester, SizedBox(width: 360, child: NoteSimpleHeader(backLabel: 'Notes', onBack: () {}, onMore: () {}, presence: PresenceAvatars(noteId: 'n1', members: [_member('ana')], end: 8))));
      expect(find.byKey(PresenceAvatars.avatarKey('ana')), findsOneWidget);
      expect(tester.getRect(find.byKey(PresenceAvatars.avatarsKey)).right, lessThan(tester.getRect(find.byType(NoteMore)).left));
      await pumpOn(tester, SizedBox(width: 360, child: NoteSimpleHeader(backLabel: 'Notes', onBack: () {}, onMore: () {}, presence: const PresenceAvatars(noteId: 'n1', members: [], end: 8))));
      expect(find.byKey(PresenceAvatars.avatarsKey), findsNothing);
      expect(tester.getRect(find.byType(NoteMore)).right, tester.getRect(find.byType(NoteSimpleHeader)).right);
    });

    group('in the bar', () {
        for (final window in const [(name: 'phone', size: Size(390, 844), mobile: true, fine: false), (name: 'mac', size: Size(1280, 800), mobile: false, fine: true)]) {
          drawnTest(window.name, (tester) async {
            final rooms = _Rooms()..rooms = {'o1': [_on('ana', 'groceries', client: 1, hue: 'sea'), _on('sam', 'groceries', client: 2)]};
            final pages = PagePresence(read: () => rooms.rooms, changes: rooms, self: () => 'matt');
            addTearDown(pages.dispose);
            final shell = GlobalKey<AppShellState>();
            final sheet = await appSheet(tester);
            await pumpApp(
              tester,
              size: window.size,
              home: PagePresenceScope(
                presence: pages,
                child: AppShell(
                  key: shell,
                  sheet: sheet,
                  notes: library,
                  workspaces: spaces,
                  openNotes: const ['weekend', 'groceries'],
                  mobile: window.mobile,
                  finePointer: window.fine,
                  onNew: () {},
                  onSearch: () {},
                  onSettings: () {},
                  onDeleteNote: (_) {},
                  // As the root hands it (lib/root/root_parts.dart): the avatars for the note on screen, while anyone is on it.
                  barChip: (
                    changes: pages,
                    build: (context) {
                      final id = shell.currentState?.shown;
                      return id == null || pages.presenceOn(id).isEmpty ? null : PresenceAvatars(key: ValueKey('presence:$id'), noteId: id);
                    },
                  ),
                  noteBuilder: (context, shell, screen) => _StandInNote(note: screen.note),
                  homeBuilder: (context, shell) => HomePlaceholder(notes: shell.notes, onOpen: shell.openNote, onAllNotes: shell.showAllNotes),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 300));
            expect(find.byKey(PresenceAvatars.avatarsKey), findsNothing, reason: 'nobody else is on the home page');

            shell.currentState!.openNote('groceries');
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull);
            expect(find.byKey(PresenceAvatars.avatarKey('ana')), findsOneWidget);
            expect(find.byKey(PresenceAvatars.avatarKey('sam')), findsOneWidget);
            final at = tester.getRect(find.byKey(PresenceAvatars.avatarsKey));
            expect(at.left >= 0 && at.right <= window.size.width && at.bottom < 160, isTrue, reason: 'in the bar, at $at');

            // Another note, which nobody else has open: gone from the bar.
            shell.currentState!.openNote('weekend');
            await tester.pump(const Duration(milliseconds: 400));
            await tester.pump(const Duration(milliseconds: 100));
            expect(find.byKey(PresenceAvatars.avatarsKey), findsNothing);
            // And someone opens it.
            rooms.set({'o1': [_on('ana', 'weekend', client: 1, hue: 'sea')]});
            await tester.pump();
            expect(find.byKey(PresenceAvatars.avatarKey('ana')), findsOneWidget);
            expect(find.byKey(PresenceAvatars.avatarKey('sam')), findsNothing);
            expect(tester.takeException(), isNull);
          });
        }
    });
  });

  group('two devices in an organization', () {
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

    LiveHub hubOn(Relay relay) => LiveHub(LiveHubDeps(url: 'ws://relay.test/live', token: () => 't', crypto: crypto, crdt: crdt, connect: relay.line));

    test('shows the other member on the page they open, not their caret moving, and lets them go as they close it or their app goes behind another; nothing of the page in the clear', () async {
      final relay = Relay();
      final key = await crypto.newOrgKey();
      final changes = ChangeNotifier();
      Future<void> settle() async {
        for (var i = 0; i < 5; i += 1) {
          await relay.settled();
          await pumpEventQueue();
        }
      }

      // matt's device: the app's own presence, read by page.
      final hubA = hubOn(relay);
      final rooms = TeamRooms(hub: hubA, crypto: crypto, crdt: crdt, orgKeyOf: (_) => key, handle: () => 'matt', colourIn: (_) => 'rose', tick: null);
      final presence = Presence(rooms);
      final stop = presence.watch(PresenceWatch(signedIn: () => true, localOnly: () => false, joined: () => ['o1'], hasKey: (_) => true, changes: [changes], account: false));
      final pages = PagePresence.of(presence, handle: () => 'matt');
      var told = 0;
      pages.addListener(() => told += 1);

      // sam opens Roadmap on theirs, as lib/live/open.dart says it.
      TeamRoom join(String handle, String? hue, {bool ai = false}) {
        final hub = hubOn(relay);
        final room = TeamRoom('o1', presenceRoom, Me(name: handle, hue: hue, ai: ai, via: ai ? 'sam' : null), RoomDeps(key: key, crypto: crypto, crdt: crdt, hold: hub.holdRoom, release: hub.releaseRoom));
        relay.waits.add(room.sent);
        return room;
      }

      const roadmap = 'note-roadmap-7f3a', title = 'Quarterly roadmap';
      final sam = join('sam', 'sea');
      final samLine = relay.lines.last;
      sam.setField('at', const Whereabouts(note: roadmap, title: title).toJson());
      // matt's own phone, on the same page, and an AI through sam's connector: neither is someone else here.
      final phone = join('matt', 'rose')..setField('at', const Whereabouts(note: roadmap, title: title).toJson());
      final claude = join('Claude', 'violet', ai: true)..setField('at', const Whereabouts(note: roadmap, title: title).toJson());
      await settle();
      expect([for (final m in pages.presenceOn(roadmap)) (m.name, m.hue, m.org)], [('sam', 'sea', 'o1')]);
      expect(pages.value.keys, [roadmap]);
      final first = told;
      expect(first, greaterThan(0));

      // Nothing of the page said in the clear: not its id, not its title.
      for (final line in relay.lines) {
        for (final frame in line.sent) {
          expect(frame.contains(roadmap) || frame.contains(title), isFalse, reason: frame);
        }
      }

      // sam's caret moves: said in the room, nothing for the page.
      sam.setField('at', const Whereabouts(note: roadmap, title: title, cursor: {'anchor': 'x', 'head': 'y'}).toJson());
      await settle();
      expect(told, first);
      expect(pages.presenceOn(roadmap), hasLength(1));

      // sam closes the note: nowhere, at once.
      sam.setField('at', null);
      await settle();
      expect(pages.presenceOn(roadmap), isEmpty);

      // Back on it, then their app goes behind another: its socket goes, the relay says that connection left.
      sam.setField('at', const Whereabouts(note: roadmap, title: title).toJson());
      await settle();
      expect([for (final m in pages.presenceOn(roadmap)) m.name], ['sam']);
      samLine.close();
      await settle();
      expect(pages.presenceOn(roadmap), isEmpty);
      expect(pages.value, isEmpty);

      pages.dispose();
      stop();
      phone.close();
      claude.close();
      sam.close();
    }, skip: coreSkip);
  });
}

/// A row's name with a state of its own, to see it kept.
class _Name extends StatefulWidget {
  const _Name();

  @override
  State<_Name> createState() => _NameState();
}

class _NameState extends State<_Name> {
  @override
  Widget build(BuildContext context) => const Text('Roadmap');
}

/// A note's screen that hands the bar its tools, as the real one does.
class _StandInNote extends StatefulWidget {
  const _StandInNote({required this.note});
  final Note note;

  @override
  State<_StandInNote> createState() => _StandInNoteState();
}

class _StandInNoteState extends State<_StandInNote> {
  late final ValueNotifier<NoteToolsModel> _model = ValueNotifier(NoteToolsModel(
    kind: NoteKind.words,
    page: true,
    switchable: true,
    onSwitch: () {},
    onMore: () {},
    more: false,
    actions: [
      ToolAction(id: 'share', label: 'Share', icon: Lucide.share2, onPress: () {}),
      ToolAction(id: 'history', label: 'Version history', icon: Lucide.history, onPress: () {}),
      ToolAction(id: 'comment', label: 'Comment', icon: Lucide.messageSquarePlus, onPress: () {}),
    ],
  ));
  late final Widget _tools = NoteTools(model: _model);
  late final Widget _more = NoteMore(onMore: () {});

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TopBarFill(tools: _tools, tail: _more, model: _model, child: NotePlaceholder(note: widget.note));
}
