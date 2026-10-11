// Comments in a team's note (lib/comments/ui/note_comments.dart over lib/live/editor_binding.dart) with the real
// CRDT: two members' editors bound to one team note over a relay in memory. A comment is a few edits put through
// the editor as one change (`userEvent: 'input.comment'`), so it rides the team's document as typing does: the
// other member's note has the mark and the fence, their editor draws the round, and two replies written at once
// are both kept. (On the page: editor/useNoteComments.tsx, "in a team note a change the CRDT merges with everyone
// else's rather than the note written again".)
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/crypto.dart';
import 'package:ghost_md/account/crypto_api.dart' show SealKey;
import 'package:ghost_md/account/session.dart';
import 'package:ghost_md/comments/colours.dart';
import 'package:ghost_md/comments/format.dart';
import 'package:ghost_md/comments/ui/note_comments.dart';
import 'package:ghost_md/comments/ui/sheet.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/editor/comments/comments.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/live/editor_binding.dart';
import 'package:ghost_md/live/hub.dart';
import 'package:ghost_md/live/team.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';

import 'support.dart';

/// A member's handle, as the account would say it.
class _Stamps {
  _Stamps(this.by);
  final String by;
  int _tick = 0;

  /// A second later each time, so two stamps are never one.
  DateTime next() => DateTime.utc(2026, 10, 5, 9, 0, _tick += 1);
}

/// An account signed in as [handle], and nothing else of one.
class _Signed extends ChangeNotifier implements AccountSource {
  _Signed(this.handle);
  final String handle;

  @override
  Session? get session => Session(token: 't', handle: handle, accountId: 1);

  @override
  Future<SealKey?> accountKey() async => null;
}

typedef _Member = ({TeamDoc doc, TeamRoom room, EditorView view, LiveBinding binding, ScreenComments comments});

void main() {
  // An undo brings its change into view, which the view asks the scheduler for.
  TestWidgetsFlutterBinding.ensureInitialized();
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

  String words(EditorView view) => view.state.doc.toString();

  Future<_Member> member(Relay relay, Object key, String name, String? hue, Object from) async {
    final docs = TeamDocs(crdt: crdt, store: MemoryDocs(), rest: const Duration(days: 1));
    final doc = from is String ? (await docs.doc('n1', seedWords: from))! : await docs.adopt('n1', from as dynamic, 0);
    final hub = LiveHub(LiveHubDeps(url: 'ws://relay.test/live', token: () => 't', crypto: crypto, crdt: crdt, connect: relay.line));
    final room = TeamRoom('o1', 'n1', Me(name: name, hue: hue), RoomDeps(key: key as dynamic, crypto: crypto, crdt: crdt, doc: doc, hold: hub.holdRoom, release: hub.releaseRoom));
    relay.waits.add(room.sent);
    final stamps = _Stamps(name);
    late final EditorView view;
    final comments = ScreenComments(
      noteId: 'n1',
      view: () => view,
      say: (_) {},
      colours: () => commentColours(orgId: 'o1', theirs: const {'matt': 'rose', 'sam': 'sea'}),
      account: _Signed(name),
      now: stamps.next,
    );
    view = EditorView(
      wholeDocument: true,
      state: EditorState.create(doc: doc.words, extensions: Extension.list(<Extension>[undoSlot.of(localUndo()), liveBindingSlot(), noteComments(() => comments.hooks)])),
    )..setFocused(true);
    final binding = LiveBinding(view, doc, room: room, positions: doc.crdt)..bind();
    return (doc: doc, room: room, view: view, binding: binding, comments: comments);
  }

  Future<void> quiet(Relay relay) async {
    for (var i = 0; i < 4; i += 1) {
      await relay.settled();
      await Future<void>.delayed(const Duration(milliseconds: 60));
    }
    await relay.settled();
  }

  /// The rounds an editor draws, by thread.
  Map<String, String> rounds(EditorView view) {
    final found = <String, String>{};
    for (final set in view.decorations) {
      set.between(0, view.state.doc.length, (from, to, value) {
        final widget = value.spec.widget;
        if (widget is RoundWidget) found[widget.id] = widget.hue;
        return null;
      });
    }
    return found;
  }

  test('a comment, a reply and a resolution written by one member are in the other\'s note and drawn there, and two replies at once are both kept', () async {
    final relay = Relay();
    final key = await crypto.newOrgKey();
    final a = await member(relay, key, 'matt', 'rose', '# Plan\n\nBook the barn for Saturday\n');
    final b = await member(relay, key, 'sam', 'sea', await a.doc.snapshot());
    await quiet(relay);

    // Matt comments on two words.
    final from = words(a.view).indexOf('the barn');
    a.comments.start((from: from, to: from + 'the barn'.length));
    expect(a.comments.page, const NewPage('the barn'));
    a.comments.add('Which one?');
    await quiet(relay);
    final id = RegExp(r'\[\^(c[0-9a-z]{4})\]').firstMatch(words(a.view))!.group(1)!;
    expect(words(b.view), words(a.view));
    expect(words(b.view), '# Plan\n\nBook ==the barn==[^$id] for Saturday\n\n```comments\n$id matt 2026-10-05T09:00:02Z\nWhich one?\n```\n');
    // The document itself has it, not the editor alone: it is what a pass saves and the next member is seeded from.
    expect(b.doc.words, words(b.view));
    expect(a.doc.words, words(a.view));
    // Drawn in sam's editor in matt's colour.
    expect(rounds(b.view), {id: 'rose'});

    // Sam answers; matt's open card reads the thread again.
    a.comments.hooks.open(id);
    var redrawn = 0;
    a.comments.addListener(() => redrawn += 1);
    b.comments.reply(id, 'The big one.');
    await quiet(relay);
    expect(redrawn, greaterThan(0));
    expect(readComments(words(a.view)).threads.single.replies.map((reply) => '${reply.by}: ${reply.words}'), ['sam: The big one.']);

    // Both at once, neither having heard the other: both replies are kept, each whole, and the fence still reads.
    a.comments.reply(id, 'Booked it.');
    b.comments.reply(id, 'For six o\'clock.');
    await quiet(relay);
    expect(words(a.view), words(b.view));
    final thread = readComments(words(a.view)).threads.single;
    expect(thread.replies.map((reply) => reply.words).toSet(), {'The big one.', 'Booked it.', 'For six o\'clock.'});
    expect(readComments(words(a.view)).strays, isEmpty);

    // Resolved by sam: matt's note says who, and the wash goes there too.
    b.comments.resolve(id);
    await quiet(relay);
    expect(readComments(words(a.view)).threads.single.resolved?.by, 'sam');

    // Deleted by matt: the mark and the fence go from both. And his Undo puts it back, as the toast says.
    a.comments.delete(id);
    await quiet(relay);
    expect(words(b.view), '# Plan\n\nBook the barn for Saturday\n');
    expect(rounds(b.view), isEmpty);
    // The note is live, so it is the document's undo (lib/live/editor_binding.dart), as on the page.
    undoNote(a.view);
    await a.binding.undone();
    await quiet(relay);
    expect(words(b.view), words(a.view));
    expect(readComments(words(b.view)).threads.single.replies, hasLength(3));
    expect(rounds(b.view), {id: 'rose'});

    a.binding.unbind();
    b.binding.unbind();
    a.room.close();
    b.room.close();
  }, skip: coreSkip);
}
