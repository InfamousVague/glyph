// What the tests of undo in a live note share (docs/PARITY.md, Differs 26): Ghost.md itself to ask, and this app's
// own members to ask the same of.
//
// [Page] is the web app: tool/yjs_undo.mjs under Node, which is its editor (CodeMirror under jsdom) bound to its
// live document by its own `bindLive` (../glyph/src/app/editor/liveBinding.ts: Yjs 13's `UndoManager` behind
// y-codemirror), driven a step at a time. [Member] is this app's: a team note's document in the REAL core
// (tool/build-native.sh host), an editor with the app's own input layer, and the binding between them
// (lib/live/editor_binding.dart). [Both] does each step to the two and holds every answer of the one to the other:
// the words of every member's editor and document, letter for letter, and whether each has a step to take back or
// put in again.
//
// The members here are told each other's updates by the test, in the order and at the moment it chooses, so a case
// can say exactly what one had heard when the other wrote. Client ids are this app's own, given to the page, since
// which of two letters written at one spot at one moment comes first is by them. The clock is the test's: both
// sides are told the time with every step, so the half second that groups typing is the same on both.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/input/input.dart';
import 'package:ghost_md/editor/input/keymap.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/live/editor_binding.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';

/// Why the page cannot be asked here, or null when it can.
String? get pageSkip {
  if (!Directory('../glyph/node_modules/yjs').existsSync() || !Directory('../glyph/node_modules/y-codemirror.next').existsSync()) return '../glyph has no node_modules for the page\'s editor to load';
  if (!Directory('../glyph/node_modules/jsdom').existsSync()) return '../glyph has no node_modules/jsdom for the page\'s editor to stand in';
  try {
    if (Process.runSync('node', ['--version']).exitCode != 0) return '`node` did not run';
  } on ProcessException {
    return '`node` is not on the PATH';
  }
  return null;
}

/// Ghost.md's editor and its live document, under Node (tool/yjs_undo.mjs).
class Page {
  Page._(this._process, this._lines, this.hello, this._errors);

  static Future<Page> start() async {
    final process = await Process.start('node', ['--experimental-transform-types', '--no-warnings', 'tool/yjs_undo.mjs']);
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    final lines = StreamIterator(process.stdout.transform(utf8.decoder).transform(const LineSplitter()));
    if (!await lines.moveNext()) fail('the page never came up (${await process.exitCode}):\n$errors');
    final hello = (jsonDecode(lines.current) as Map).cast<String, Object?>();
    expect(hello['ready'], isTrue, reason: 'the page said $hello\n$errors');
    return Page._(process, lines, hello, errors);
  }

  final Process _process;
  final StreamIterator<String> _lines;
  final StringBuffer _errors;

  /// What it said as it came up: the versions of Yjs, y-codemirror and CodeMirror it is.
  final Map<String, Object?> hello;
  int _id = 0;

  Future<Map<String, Object?>> ask(Map<String, Object?> command) async {
    final id = _id += 1;
    _process.stdin.writeln(jsonEncode({...command, 'id': id}));
    await _process.stdin.flush();
    if (!await _lines.moveNext()) fail('the page went away during ${command['do']}:\n$_errors');
    final said = (jsonDecode(_lines.current) as Map).cast<String, Object?>();
    if (said['error'] != null) fail('the page failed at $command:\n${said['error']}');
    expect(said['id'], id);
    return said;
  }

  Future<void> close() async {
    try {
      _process.stdin.writeln(jsonEncode({'do': 'close'}));
      await _process.stdin.flush();
    } catch (_) {
      _process.kill();
    }
    await _process.exitCode.timeout(const Duration(seconds: 5), onTimeout: () {
      _process.kill();
      return -1;
    });
  }
}

/// A member as a test reads one, the page's or this app's: the editor's words, the document's, the selection, and
/// whether there is a step to take back and one to put in again.
@immutable
class Seen {
  const Seen({required this.words, required this.text, required this.anchor, required this.head, required this.canUndo, required this.canRedo});

  factory Seen.ofPage(Map<String, Object?> said) =>
      Seen(words: said['words'] as String, text: said['text'] as String, anchor: said['anchor'] as int, head: said['head'] as int, canUndo: (said['undo'] as int) > 0, canRedo: (said['redo'] as int) > 0);

  final String words;
  final String text;
  final int anchor;
  final int head;
  final bool canUndo;
  final bool canRedo;

  @override
  String toString() => '"$words"${text == words ? '' : ' (document "$text")'} caret $anchor${head == anchor ? '' : '-$head'}${canUndo ? ' undo' : ''}${canRedo ? ' redo' : ''}';
}

/// One member in this app: a team note's document, an editor, and the binding.
class Member {
  Member._(this.name, this.docs, this.doc, this.view);

  final String name;
  final TeamDocs docs;
  final TeamDoc doc;
  final EditorView view;
  LiveBinding? binding;

  /// The updates this member made that each other has not been told yet, in order.
  final Map<String, List<Uint8List>> outbox = {};

  /// Every update this member made.
  final List<Uint8List> made = [];

  int get client => doc.crdt.clientId;

  bool get bound => binding?.bound ?? false;

  Seen get seen {
    final main = view.state.selection.main;
    return Seen(words: view.state.doc.toString(), text: doc.words, anchor: main.anchor, head: main.head, canUndo: canUndoNote(view.state), canRedo: canRedoNote(view.state));
  }

  void bind(int Function() now) => binding = LiveBinding(view, doc, now: now)..bind();

  void unbind() => binding?.unbind();

  /// Everything asked of the document is done and in the editor, and nothing typed is on its way.
  Future<void> quiet() async {
    for (var round = 0; round < 50; round += 1) {
      await doc.settled();
      await binding?.undone();
      await Future<void>.delayed(Duration.zero);
      await doc.settled();
      if (view.state.doc.toString() == doc.words || !bound) break;
    }
    await binding?.undone();
    await doc.settled();
    await Future<void>.delayed(Duration.zero);
  }
}

/// The page and this app, side by side: every step done to both, and the two held to each other.
class Both {
  Both(this.page, this.core);

  final Page page;
  final GhostCore core;

  /// The time both are told.
  int clock = 1000;
  final Map<String, Member> members = {};

  /// Every step taken, for a failure to say how it came about.
  final List<String> steps = [];

  /// How many steps of each kind were held to the page since this was made, and how many of the undos and redos
  /// among them changed the words: what a run of drawn scenarios says it covered.
  final Map<String, int> held = {};

  /// Whether the selection is held to the page's as well as the words (a case whose changes from elsewhere are
  /// each one stretch: a longer change reaches this app's editor as one long stretch, which moves a caret inside
  /// it differently, and is not the undo's doing).
  bool carets = false;

  /// The client id the next document opened here is given, counted up or down from there; null leaves each to
  /// the core, which draws one as Yjs does. Which of two letters written at one spot at one moment comes first is
  /// by these, so a scenario is run with the first member's the lower and again with it the higher.
  int? nextClient;
  int clientStep = 1;

  Crdt get _crdt => Crdt((command, [args = const <String, Object?>{}]) {
        final given = nextClient;
        if (command != 'crdt_open' || given == null || args.containsKey('clientId')) return core.invoke(command, args);
        nextClient = given + clientStep;
        return core.invoke(command, {...args, 'clientId': given});
      });

  EditorView _editor(String words) =>
      EditorView(wholeDocument: true, state: EditorState.create(doc: words, extensions: Extension.list(<Extension>[editorInput(), liveBindingSlot()])))..setFocused(true);

  Member _member(String who, TeamDocs docs, TeamDoc doc) {
    final one = Member._(who, docs, doc, _editor(doc.words));
    doc.onUpdate((update) {
      one.made.add(update);
      for (final queue in one.outbox.values) {
        queue.add(update);
      }
    });
    for (final other in members.values) {
      other.outbox[who] = [];
      one.outbox[other.name] = [];
    }
    return members[who] = one;
  }

  /// A new note, begun by [who] with [words].
  Future<Member> open(String who, String words) async {
    await page.ask({'do': 'reset'});
    for (final one in members.values) {
      one.unbind();
      await one.docs.forget();
    }
    members.clear();
    steps
      ..clear()
      ..add('$who opens "$words"');
    final docs = TeamDocs(crdt: _crdt, store: MemoryDocs(), rest: const Duration(days: 1));
    final one = _member(who, docs, (await docs.doc('n1', seedWords: words))!);
    await page.ask({'do': 'open', 'who': who, 'client': one.client, 'words': words});
    await _same('open');
    return one;
  }

  /// [who] joins, with [from]'s document as it stands.
  Future<Member> join(String who, String from) async {
    steps.add('$who joins from $from');
    final docs = TeamDocs(crdt: _crdt, store: MemoryDocs(), rest: const Duration(days: 1));
    final one = _member(who, docs, await docs.adopt('n1', await members[from]!.doc.snapshot(), 0));
    await page.ask({'do': 'open', 'who': who, 'client': one.client, 'from': from});
    await _same('join');
    return one;
  }

  /// [who]'s editor is bound to their document. Where the two held other words, the page writes the whole note
  /// into its editor, which leaves its caret at the start, and this app writes the stretch that differs, which
  /// leaves its caret where it was: so the selection is not held to the page's here, and is again from the next
  /// step that puts it somewhere.
  Future<void> bind(String who) => _step('$who binds', {'do': 'bind', 'who': who}, () async => members[who]!.bind(() => clock), selection: false);

  Future<void> unbind(String who) => _step('$who unbinds', {'do': 'unbind', 'who': who}, () async => members[who]!.unbind());

  /// A key of [who]'s: [remove] code units gone at [at], [insert] put there, the caret after it.
  Future<void> type(String who, int at, String insert, {int remove = 0, int after = 0}) {
    clock += after;
    return _step('$who types "$insert" at $at${remove > 0 ? ' over $remove' : ''} (t=$clock)', {'do': 'type', 'who': who, 'at': at, 'remove': remove, 'insert': insert, 'now': clock}, () async {
      members[who]!.view.dispatch(TransactionSpec(changes: Change(from: at, to: at + remove, insert: insert), selection: EditorSelection.single(at + insert.length), userEvent: 'input.type'));
    });
  }

  Future<void> select(String who, int anchor, [int? head]) => _step('$who selects $anchor${head == null ? '' : '-$head'}', {'do': 'select', 'who': who, 'anchor': anchor, 'head': head ?? anchor}, () async {
        members[who]!.view.dispatch(TransactionSpec(selection: EditorSelection.single(anchor, head ?? anchor)));
      });

  /// The key, or with [by] `input` the undo a keyboard or a menu sends (what the editor's widget answers
  /// `UndoTextIntent` with, and the page `beforeinput`'s historyUndo).
  Future<void> undo(String who, {int after = 0, String by = 'key'}) => _undo(who, false, after, by);

  Future<void> redo(String who, {int after = 0, String by = 'key'}) => _undo(who, true, after, by);

  Future<void> _undo(String who, bool redo, int after, String by) {
    clock += after;
    return _step('$who ${redo ? 'redoes' : 'undoes'} by $by (t=$clock)', {'do': redo ? 'redo' : 'undo', 'who': who, 'now': clock, 'by': by}, () async {
      final view = members[who]!.view;
      switch (by) {
        case 'input':
          runCommand(view, redo ? redoNote : undoNote);
        case 'shift':
          expect(runKey(view, 'Shift-Ctrl-z'), isTrue, reason: 'the key is bound');
        default:
          expect(runKey(view, redo ? 'Ctrl-y' : 'Ctrl-z'), isTrue, reason: 'the key is bound');
      }
    });
  }

  /// Words that reach [who]'s note without the editor: a capture, a pass.
  Future<void> reconcile(String who, String words) => _step('$who is reconciled to "$words"', {'do': 'reconcile', 'who': who, 'words': words}, () async {
        await members[who]!.doc.reconcile(words);
      });

  /// The next [count] updates [from] made reach [to], in order: all that wait, left out.
  Future<void> deliver(String from, String to, [int? count]) async {
    final queue = members[from]!.outbox[to]!;
    final taken = queue.sublist(0, count == null || count > queue.length ? queue.length : count);
    queue.removeRange(0, taken.length);
    await _step('$from\'s next ${taken.length} reach $to', {'do': 'deliver', 'from': from, 'to': to, 'count': taken.length}, () async {
      if (taken.isNotEmpty) await members[to]!.doc.applyRemote(taken);
    });
  }

  /// Everything every member made reaches every other, until nothing waits.
  Future<void> everyone() async {
    for (var round = 0; round < 3; round += 1) {
      for (final from in members.keys.toList()) {
        for (final to in members.keys.toList()) {
          if (from != to && members[from]!.outbox[to]!.isNotEmpty) await deliver(from, to);
        }
      }
    }
  }

  Future<void> _step(String what, Map<String, Object?> command, Future<void> Function() here, {bool selection = true}) async {
    steps.add(what);
    final kind = command['do'] as String, who = members[command['who'] ?? command['to']];
    final before = who?.doc.words;
    await page.ask(command);
    await here();
    await _same(what, selection: selection);
    held[kind] = (held[kind] ?? 0) + 1;
    if ((kind == 'undo' || kind == 'redo') && who != null && who.bound && who.doc.words != before) held['$kind that changed the words'] = (held['$kind that changed the words'] ?? 0) + 1;
  }

  /// The words of [who]'s editor, once the page's and this app's have been held to each other.
  String words(String who) => members[who]!.seen.words;

  Seen seen(String who) => members[who]!.seen;

  /// Every member here is as the page has them.
  Future<void> _same(String after, {bool selection = true}) async {
    for (final one in members.values) {
      await one.quiet();
    }
    for (final one in members.values) {
      final theirs = Seen.ofPage(await page.ask({'do': 'state', 'who': one.name}));
      final mine = one.seen;
      String said() => '${one.name} after "$after":\n  the page: $theirs\n  this app: $mine\nby these steps:\n  ${steps.join('\n  ')}';
      final dump = Platform.environment['GHOST_UNDO_DUMP'];
      if (mine.text != theirs.text && dump != null) {
        // Both documents whole, for whoever looks into why they part.
        File(dump).writeAsStringSync(jsonEncode({
          'who': one.name,
          'page': [for (final each in members.values) (await page.ask({'do': 'whole', 'who': each.name}))['update']],
          'app': [for (final each in members.values) toBase64Url(await each.doc.snapshot())],
          'steps': steps,
        }));
      }
      expect(mine.text, theirs.text, reason: 'the document of ${said()}');
      expect(mine.words, theirs.words, reason: 'the editor of ${said()}');
      // Bound, an editor holds its document's words; on its own it holds what was typed into it.
      if (one.bound) expect(mine.words, mine.text, reason: 'this app\'s editor and its document, ${said()}');
      expect((mine.canUndo, mine.canRedo), (theirs.canUndo, theirs.canRedo), reason: 'what can be taken back and put in again by ${said()}');
      if (carets && selection) expect((mine.anchor, mine.head), (theirs.anchor, theirs.head), reason: 'the selection of ${said()}');
    }
  }

  /// Each side reads the other's updates: a fresh Yjs document given everything this app's members made holds the
  /// words, and a fresh document in the core given everything the page's made does too.
  Future<void> readEachOther(String seededBy) async {
    await everyone();
    final words = members[seededBy]!.doc.words;
    for (final one in members.values) {
      expect(one.doc.words, words, reason: 'every member holds the same words once all is delivered\n  ${steps.join('\n  ')}');
    }
    // Yjs reads this app's: the first member's document as it was seeded is in its state, so the whole state of
    // each member is given.
    final ours = [for (final one in members.values) toBase64Url(await one.doc.snapshot())];
    expect((await page.ask({'do': 'read', 'updates': ours}))['text'], words, reason: 'Yjs reads what this app wrote');
    // And the core reads the page's: the document as it was seeded, then every update in the order it was made.
    final seed = fromBase64Url((await page.ask({'do': 'seed', 'who': seededBy}))['update'] as String);
    Future<String> read(List<Uint8List> updates) async {
      final reader = await _crdt.open();
      await reader.applyRemote([seed, ...updates]);
      final words = await reader.words();
      await reader.close();
      return words;
    }

    final made = [for (final update in (await page.ask({'do': 'made'}))['updates'] as List) fromBase64Url(update as String)];
    expect(await read(made), words, reason: 'this app reads what Yjs wrote\n  ${steps.join('\n  ')}');
    // GHOST_UNDO_OUT_OF_ORDER=1 also hands the core each member's updates in a block, so that one member's arrive
    // before those of the other's they were written over. Not asked by default: yrs 0.26 misreads some such orders
    // whatever the updates are (native/tests/yjs_vectors.rs, the ignored test), which is not the undo's doing.
    if (Platform.environment['GHOST_UNDO_OUT_OF_ORDER'] != null) {
      final blocks = <Uint8List>[];
      for (final one in members.values) {
        blocks.addAll([for (final update in (await page.ask({'do': 'made', 'who': one.name}))['updates'] as List) fromBase64Url(update as String)]);
      }
      final got = await read(blocks);
      final dump = Platform.environment['GHOST_UNDO_DUMP'];
      if (got != words && dump != null) File(dump).writeAsStringSync(jsonEncode({'words': words, 'read': got, 'updates': [toBase64Url(seed), for (final update in blocks) toBase64Url(update)], 'steps': steps}));
      expect(got, words, reason: 'this app reads what Yjs wrote, a member at a time\n  ${steps.join('\n  ')}');
    }
  }

  Future<void> close() async {
    for (final one in members.values) {
      one.unbind();
      await one.docs.forget();
    }
    members.clear();
  }
}
