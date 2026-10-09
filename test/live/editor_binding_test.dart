// A note's editor bound to its live document (lib/live/editor_binding.dart) with the real CRDT: two editors, two
// devices, one team note over a relay in memory, each typing while the other's keys arrive; the others' carets
// placed and drawn; and an account's own note the same way.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/live/editor_binding.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/team.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';

import 'support.dart';

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

  EditorView editor(String words) => EditorView(wholeDocument: true, state: EditorState.create(doc: words, extensions: Extension.list(<Extension>[undoSlot.of(localUndo()), liveBindingSlot()])))..setFocused(true);
  void type(EditorView view, int at, String insert, {int remove = 0}) => view.dispatch(TransactionSpec(changes: Change(from: at, to: at + remove, insert: insert), selection: EditorSelection.single(at + insert.length), userEvent: 'input.type'));
  String words(EditorView view) => view.state.doc.toString();

  Future<({TeamDoc doc, TeamRoom room, EditorView view, LiveBinding binding})> member(Relay relay, Object key, String name, String? hue, Object from) async {
    final docs = TeamDocs(crdt: crdt, store: MemoryDocs(), rest: const Duration(days: 1));
    final doc = from is String ? (await docs.doc('n1', seedWords: from))! : await docs.adopt('n1', from as dynamic, 0);
    final hub = LiveHub(LiveHubDeps(url: 'ws://relay.test/live', token: () => 't', crypto: crypto, crdt: crdt, connect: relay.line));
    final room = TeamRoom('o1', 'n1', Me(name: name, hue: hue), RoomDeps(key: key as dynamic, crypto: crypto, crdt: crdt, doc: doc, hold: hub.holdRoom, release: hub.releaseRoom));
    relay.waits.add(room.sent);
    final view = editor(doc.words);
    final binding = LiveBinding(view, doc, room: room, positions: doc.crdt)..bind();
    return (doc: doc, room: room, view: view, binding: binding);
  }

  /// Everything in flight landed, the carets said and placed.
  Future<void> quiet(Relay relay) async {
    for (var i = 0; i < 4; i += 1) {
      await relay.settled();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    await relay.settled();
  }

  test('two editors on one team note: each one\'s keys in the other as they are made, keys pressed while the other\'s arrive kept where they were meant, and an undo that takes back only this person\'s', () async {
    final relay = Relay();
    final key = await crypto.newOrgKey();
    final a = await member(relay, key, 'matt', 'rose', 'Hello world');
    final b = await member(relay, key, 'sam', 'sea', await a.doc.snapshot());
    await quiet(relay);

    type(a.view, 5, ',');
    await quiet(relay);
    expect(words(b.view), 'Hello, world');
    type(b.view, 12, ' 👻');
    await quiet(relay);
    expect(words(a.view), 'Hello, world 👻');

    // Both at once, at both ends and at one spot, a burst of keys each: neither has heard the other when it types.
    for (final (i, letter) in 'abc'.split('').indexed) {
      type(a.view, i, letter);
      type(b.view, words(b.view).length, letter.toUpperCase());
      type(a.view, words(a.view).indexOf('world'), '<');
      type(b.view, words(b.view).indexOf('world'), '>');
    }
    await quiet(relay);
    expect(words(a.view), words(b.view));
    expect(words(a.view), a.doc.words);
    expect(words(b.view), b.doc.words);
    expect(words(a.view), startsWith('abcHello, '));
    expect(words(a.view), endsWith('world 👻ABC'));
    expect(RegExp('[<>]').allMatches(words(a.view)), hasLength(6));

    // A key pressed here between an update being handed to the core and its words coming back.
    final before = words(a.view);
    type(b.view, 0, 'Oh. ');
    await relay.settled();
    type(a.view, words(a.view).length, '!');
    type(a.view, words(a.view).length, '?');
    await quiet(relay);
    expect(words(a.view), 'Oh. $before!?');
    expect(words(b.view), 'Oh. $before!?');

    // Undo is this person's: sam's "Oh. " stays, and what matt just typed goes, from both.
    undo(a.view);
    await quiet(relay);
    expect(words(a.view), 'Oh. $before');
    expect(words(b.view), 'Oh. $before');

    // Words that reach the note without the editor (a pass, a capture) arrive in it as a change.
    await a.doc.reconcile('${a.doc.words}\nadded elsewhere');
    await quiet(relay);
    expect(words(a.view), endsWith('ABC\nadded elsewhere'));
    expect(words(b.view), words(a.view));

    // Unbound, the editor is the note's own again and the document hears no more of it.
    b.binding.unbind();
    type(b.view, 0, 'x');
    await quiet(relay);
    expect(words(a.view), isNot(startsWith('x')));
    a.binding.unbind();
    a.room.close();
    b.room.close();
  }, skip: coreSkip);

  test('each member\'s caret and selection are placed in the other\'s editor in their colour with their handle, ride what is typed before them, and go with their connection', () async {
    final relay = Relay();
    final key = await crypto.newOrgKey();
    final a = await member(relay, key, 'matt', 'rose', 'Hello world\nsecond line\nthird');
    final b = await member(relay, key, 'sam', null, await a.doc.snapshot());
    await quiet(relay);

    a.view.dispatch(TransactionSpec(selection: EditorSelection.single(6, 11)));
    b.view.dispatch(TransactionSpec(selection: EditorSelection.single(28, 14)));
    await quiet(relay);
    expect(remoteCaretsOf(b.view.state), [const RemoteCaret(client: 0, name: 'matt', hue: 'rose', anchor: 6, head: 11)].map((c) => isA<RemoteCaret>().having((r) => (r.name, r.hue, r.anchor, r.head), 'caret', (c.name, c.hue, c.anchor, c.head))));
    expect([for (final c in remoteCaretsOf(a.view.state)) (c.name, c.hue, c.anchor, c.head)], [('sam', null, 28, 14)]);

    // Drawn: a wash over matt's selection in rose and his caret at its head, after it; sam's across two lines, a
    // wash a line, his caret before his selection.
    List<String> drawn(EditorView view) {
      final out = <String>[];
      for (final source in view.state.facet(EditorViewLike.decorations)) {
        final set = EditorViewLike.resolveDecorations(source, view);
        final cursor = set.iter();
        while (cursor.value != null) {
          final value = cursor.value!;
          final widget = value.spec.widget;
          out.add(widget is RemoteCaretWidget ? '${cursor.from} caret ${widget.name} ${widget.hue} side ${value.spec.side}' : '${cursor.from}-${cursor.to} ${value.spec.className}');
          cursor.next();
        }
      }
      return out;
    }

    expect(drawn(b.view), ['6-11 cm-ySelection cm-yHue-rose', '11 caret matt rose side -1']);
    expect(drawn(a.view), ['14 caret sam null side 1', '14-23 cm-ySelection cm-yHue-ink', '24-28 cm-ySelection cm-yHue-ink']);

    // Words typed before a caret move it along at once, and it is placed again where the document has it.
    type(b.view, 0, '>> ');
    expect([for (final c in remoteCaretsOf(b.view.state)) (c.anchor, c.head)], [(9, 14)]);
    await quiet(relay);
    expect([for (final c in remoteCaretsOf(b.view.state)) (c.anchor, c.head)], [(9, 14)]);
    // sam's own caret is after what he typed now, and matt's editor has it there.
    expect([for (final c in remoteCaretsOf(a.view.state)) (c.anchor, c.head)], [(3, 3)]);

    // matt's connection leaves the room: his caret is gone from sam's editor.
    a.binding.unbind();
    a.room.close();
    await quiet(relay);
    expect(remoteCaretsOf(b.view.state), isEmpty);
    expect(drawn(b.view), isEmpty);
    b.binding.unbind();
    b.room.close();
  }, skip: coreSkip);

  testWidgets('a member\'s caret is a bar in their colour that takes no room, their handle on it', (tester) async {
    // Built as the editor builds an inline widget; the bar and the label are paint.
    const caret = RemoteCaretWidget('matt', 'rose');
    expect(caret.eq(const RemoteCaretWidget('matt', 'rose')), isTrue);
    expect(caret.eq(const RemoteCaretWidget('matt', 'sea')), isFalse);
    expect(caret.takesPointer(const PointerDownEvent()), isFalse);
  });
}
