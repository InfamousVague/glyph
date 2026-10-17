/// A note's editor bound to its live document, and unbound again (docs/LIVE.md, "The binding"). What
/// `src/app/editor/liveBinding.ts` gets from y-codemirror.next (`yCollab`): every change of the editor a change of
/// the document, every change that reaches the document from elsewhere put into the editor, and, with a team
/// note's room, the others' carets and selections drawn in their colours with their handles on them and this
/// editor's selection said for theirs (docs/SHARED.md, S6).
///
/// The editor is brought to the document's words first, read now rather than when the session said it was ready:
/// another device may have typed in between, and the binding assumes the two start equal.
///
/// What differs from the page:
/// - **The document is a call away** (lib/team/crdt.dart), where y-codemirror's is in the editor's own thread. A
///   key pressed while an update is on its way to the core was made against words the document has left; the
///   document carries it over (lib/team/text_log.dart), and the editor maps what arrives over what it has typed
///   and is not yet answered for ([LiveBinding], as CodeMirror's own collaboration does). Should the two ever
///   differ once nothing is on its way, the editor is brought to the document's words.
/// - **Undo is the document's own while the editor is bound**, as the page's is (`new Y.UndoManager(session.text)`
///   handed to `yCollab`, with `yUndoManagerKeymap`): the undo slot (lib/editor/state/undo_slot.dart) holds the
///   document's undo and y-codemirror's keys in place of the history, which leaves the state, so nothing typed
///   before the binding can be taken back after it, and comes back empty when the editor is unbound, when the
///   document's steps are gone too. The document follows this editor's own changes and no one else's, groups those
///   less than half a second apart into one step, and puts a run back where its letters stood among what the
///   others wrote since (native/src/crdt.rs, yrs's `UndoManager`; held to Yjs by test/live/undo_beside_others_
///   test.dart). An undo is asked of the document and answered a moment later ([LiveBinding.undo]): its change is
///   put into the editor as the document made it, the way a member's is, and the selection kept with the step is
///   put back and scrolled to as y-codemirror's is, unless this person has typed or moved the caret meanwhile.
/// - **A selection across lines** is washed as y-codemirror washes it: the first line from where it starts, the
///   last to where it ends, and the lines between whole (an empty one among them too), each of those a line's own
///   ground under the member's hue.
/// - **A caret is placed a moment after it is heard** (its relative position is the core's to place), and rides
///   the editor's own changes meanwhile.
/// - The caret's colour is the member's hue at the lightness this paper needs (the kit's `[data-hue]`), read from
///   the `hue` their presence carries; the CSS strings beside it (`color`, `colorLight`) are the page's to read.
/// - **A personal note's carets are the AIs' alone** (docs/CLAUDE_LIVE.md): its room is the session's [CaretRoom]
///   (lib/live/session.dart `AiCarets`), which holds only the entries that say `ai: true` and says nothing of this
///   editor's own caret. Follow (lib/live/follow.dart) reads the carets as they are placed ([LiveBinding.carets])
///   and hears this person's own scrolls, taps and keys ([LiveBinding.touched]) to stop.
/// - **Claude's words rise out of smoke** with Ghostly typing on ([LiveBinding.smoke]; docs/CLAUDE_LIVE.md): a
///   change that arrives while an AI's caret is in the room wears the recorder's `heard` (lib/editor/marks/
///   wisp_motion.dart), which the note's arrivals (lib/editor/ai/wisp_arrivals.dart) draw out of smoke letter by
///   letter. An update does not say whose it is; with an AI typing in the room, it is the AI's.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor/editor.dart';
import '../editor/input/input.dart' show liveUndoWithKeys, localUndoWithKeys;
import '../editor/items/inline_box.dart';
import '../editor/looks/look.dart';
import '../editor/looks/sheets.dart';
import '../editor/marks/wisp_motion.dart' show WispKind, wisp;
import '../editor/view/line.dart' show EditorRunScope;
import '../team/crdt.dart';
import '../team/doc.dart';
import '../team/text_log.dart';
import 'live_text.dart';
import 'team.dart';

/// Where the binding is put in an editor's extensions: empty until a note is bound, as the page's `undoSlot` is
/// the editor's own undo until it is. One compartment serves every editor.
final Compartment liveSlot = Compartment();

/// The slot, for an editor's list of extensions.
Extension liveBindingSlot() => liveSlot.of(const Extension.list(<Extension>[]));

/// Another member's caret in this editor's words.
@immutable
class RemoteCaret {
  const RemoteCaret({required this.client, required this.name, required this.hue, required this.anchor, required this.head, this.ai = false});

  final int client;
  final String name;

  /// Whether it is an AI's (`user.ai`): what Follow looks for.
  final bool ai;

  /// One of the app's hues, or null for ink.
  final String? hue;
  final int anchor;
  final int head;

  @override
  bool operator ==(Object other) => other is RemoteCaret && other.client == client && other.name == name && other.hue == hue && other.anchor == anchor && other.head == head && other.ai == ai;

  @override
  int get hashCode => Object.hash(client, name, hue, anchor, head, ai);

  @override
  String toString() => 'RemoteCaret($name${hue == null ? '' : ' in $hue'}: $anchor to $head)';
}

/// The carets as last placed.
final StateEffectType<List<RemoteCaret>> setRemoteCarets = StateEffect.define<List<RemoteCaret>>();

String _hueClass(String? hue) => 'cm-yHue-${hueAngles.containsKey(hue) ? hue : 'ink'}';

class _Carets {
  const _Carets(this.carets);

  final List<RemoteCaret> carets;

  static DecorationSet _decorate(EditorState state, List<RemoteCaret> carets) {
    if (carets.isEmpty) return Decoration.none;
    final doc = state.doc;
    final ranges = <Range<Decoration>>[];
    for (final caret in carets) {
      final anchor = caret.anchor.clamp(0, doc.length), head = caret.head.clamp(0, doc.length);
      final start = anchor < head ? anchor : head, end = anchor < head ? head : anchor;
      if (end > start) {
        // y-codemirror's `yRemoteSelections`: on one line, its words; over several, the first line from where it
        // starts and the last to where it ends, and every line between washed whole, an empty one among them too.
        final wash = Decoration.mark(className: 'cm-ySelection ${_hueClass(caret.hue)}');
        final first = doc.lineAt(start), last = doc.lineAt(end);
        if (first.number == last.number) {
          ranges.add(wash.range(start, end));
        } else {
          if (first.to > start) ranges.add(wash.range(start, first.to));
          if (end > last.from) ranges.add(wash.range(last.from, end));
          final whole = Decoration.line(className: 'cm-yLineSelection ${_hueClass(caret.hue)}');
          for (var n = first.number + 1; n < last.number; n += 1) {
            ranges.add(whole.range(doc.line(n).from));
          }
        }
      }
      ranges.add(Decoration.widget(widget: RemoteCaretWidget(caret.name, caret.hue), side: head - anchor > 0 ? -1 : 1).range(head));
    }
    return Decoration.set(ranges, true);
  }
}

final StateField<_Carets> _carets = StateField.define<_Carets>(
  create: (_) => const _Carets(<RemoteCaret>[]),
  update: (value, tr) {
    for (final effect in tr.effects) {
      final set = setRemoteCarets.cast(effect);
      if (set != null) return _Carets(set.value);
    }
    if (!tr.docChanged || value.carets.isEmpty) return value;
    // Until they are placed again, each rides the change: words typed before it move it along.
    return _Carets(<RemoteCaret>[
      for (final caret in value.carets) RemoteCaret(client: caret.client, name: caret.name, hue: caret.hue, ai: caret.ai, anchor: tr.changes.mapPos(caret.anchor, 1), head: tr.changes.mapPos(caret.head, 1)),
    ]);
  },
  provide: (field) => EditorViewLike.decorations.compute(<Object>[field], (state) => _Carets._decorate(state, state.field(field).carets)),
);

/// The carets drawn in an editor now, for a test and for whoever asks.
List<RemoteCaret> remoteCaretsOf(EditorState state) => state.fieldOrNull(_carets)?.carets ?? const <RemoteCaret>[];

/// A member's colour on this paper: their hue as the kit's `[data-hue]` draws it, or the page's ink.
Color memberColour(Tokens t, String? hue) => hueAngles.containsKey(hue) ? t.child(attrs: {'hue': hue!}).colorOf('var(--app-space, var(--app-ink))') : t.color('app-ink');

/// A member's caret: a bar in their colour as tall as the line's words, their handle riding on it. y-codemirror's
/// `YRemoteCaretWidget` as editor/NoteScreen.module.css draws it: two pixels wide and taking no room, the handle
/// always shown (a phone has no hover), no dot.
class RemoteCaretWidget extends EditorWidget {
  const RemoteCaretWidget(this.name, this.hue);

  final String name;
  final String? hue;

  @override
  bool eq(RemoteCaretWidget other) => other.name == name && other.hue == hue;

  /// A press on a caret is a press on the words under it.
  @override
  bool takesPointer(PointerEvent event) => false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final run = EditorRunScope.maybeOf(context)?.look;
    final em = run?.fontSize ?? t.len('app-body');
    final above = run?.ascent ?? em, below = run?.descent ?? 0.25 * em;
    return Semantics(
      label: '$name is here',
      excludeSemantics: true,
      child: InlineBox(
        above: above,
        below: below,
        child: SizedBox(
          width: 0,
          height: above + below,
          child: CustomPaint(painter: _CaretPainter(colour: memberColour(t, hue), paper: t.color('app-paper'), name: name, label: t.textAt(0.62 * em, weight: 'medium'), em: em)),
        ),
      ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  _CaretPainter({required this.colour, required this.paper, required this.name, required this.label, required this.em});

  final Color colour;
  final Color paper;
  final String name;
  final TextStyle label;
  final double em;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = colour;
    // '.cm-ySelectionCaret': { borderInlineWidth: '2px', marginInline: '-1px' }
    canvas.drawRect(Rect.fromLTWH(-1, 0, 2, size.height), paint);
    // '.cm-ySelectionInfo': { top: '-1.25em', padding: '0.05em 0.4em', borderRadius: '3px', fontSize: '0.62em',
    //   lineHeight: 1.4, color: 'var(--app-paper)' }, on the caret's own colour, its left edge the caret's.
    final small = 0.62 * em;
    final words = TextPainter(text: TextSpan(text: name, style: label.copyWith(color: paper, height: 1.4, fontSize: small)), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    final box = Rect.fromLTWH(-1, -1.25 * small, words.width + 0.8 * small, words.height + 0.1 * small);
    canvas.drawRRect(RRect.fromRectAndRadius(box, const Radius.circular(3)), paint);
    words.paint(canvas, Offset(box.left + 0.4 * small, box.top + 0.05 * small));
    words.dispose();
  }

  @override
  bool shouldRepaint(_CaretPainter old) => old.colour != colour || old.paper != paper || old.name != name || old.em != em || old.label != label;
}

/// `ySelection`'s wash, a quarter of the member's colour (a fifth of the ink): one rule a hue, on a run of words
/// and on a whole line alike. And y-codemirror's own rule for a line washed whole, as much of it as reaches the
/// page: `.cm-yLineSelection { padding: 0; margin: 0px 2px 0px 4px }`, whose margin stands (the line is that much
/// narrower, and its words that much in) and whose padding the note's own rule for a line's gutter is written over.
final LookSheet _theme = LookSheet('live/editor_binding.dart', <LookRule>[
  for (final hue in <String?>[null, ...hueAngles.keys])
    LookRule(_hueClass(hue), (p, e) {
      final colour = memberColour(e.t, hue);
      final wash = colour.withValues(alpha: colour.a * (hue == null ? 0.20 : 0.24));
      p.background = (_) => wash;
    }),
  LookRule('cm-yLineSelection', classes: 2, (p, e) {
    p
      ..marginStart = 4
      ..marginEnd = 2;
  }),
]);

final Extension _themed = baseTheme(_theme);

/// The others' carets in an editor: the field that holds them ([setRemoteCarets]) and what draws them. What a
/// bound team note's editor is given; here for a picture of them too.
final Extension remoteCarets = Extension.list(<Extension>[_carets, _themed]);

/// The notes whose editors are bound on this device now, by note id: where Follow (lib/live/follow.dart) finds the
/// editor of the note an AI is in, to keep its caret in view. Told as each comes and goes.
class BoundEditors extends ChangeNotifier {
  final Map<String, LiveBinding> _bound = {};

  /// The binding of [noteId]'s editor, or null while it is not open and bound here.
  LiveBinding? of(String noteId) => _bound[noteId];

  /// Every bound editor now, by note id.
  Map<String, LiveBinding> get all => Map.unmodifiable(_bound);

  void put(String noteId, LiveBinding binding) {
    if (identical(_bound[noteId], binding)) return;
    _bound[noteId] = binding;
    notifyListeners();
  }

  void take(String noteId, LiveBinding binding) {
    if (!identical(_bound[noteId], binding)) return;
    _bound.remove(noteId);
    notifyListeners();
  }
}

/// How long a caret rests before it is said to the room, and before the others' are placed again.
const Duration _caretRest = Duration(milliseconds: 40);

/// A change of the editor's on its way to the document, as the editor made it and as it stands over what has
/// arrived since.
class _Flight {
  _Flight(this.made);
  ChangeSet made;
}

/// One editor bound to one live document.
class LiveBinding implements NoteUndo {
  /// [text] is the document; [room] and [positions], a team note's room (or a personal note's AIs) and its
  /// document in the core, bring the carets. Nothing is bound until [bind]. [now] is a test's clock, in
  /// milliseconds.
  LiveBinding(this.view, this.text, {this.room, this.positions, this.smoke, int Function()? now}) : _now = now ?? _wallClock;

  final EditorViewLike view;
  final LiveText text;
  final CaretRoom? room;
  final CrdtDoc? positions;

  /// Whether words an AI types arrive out of smoke: Ghostly typing (`preferences.wisp`), read as each arrives.
  final bool Function()? smoke;

  /// The others' carets as last placed in the editor: what Follow keeps in view.
  final ValueNotifier<List<RemoteCaret>> carets = ValueNotifier<List<RemoteCaret>>(const <RemoteCaret>[]);

  /// Counts this person's own doings in the editor (a press, which a scroll by a finger begins with, a key, and
  /// what they type): what stops Follow.
  final ValueNotifier<int> touched = ValueNotifier<int>(0);

  /// The time a key is pressed or an undo asked for, which the document's undo groups typing by (Yjs reads the
  /// clock as each change is made; here the document is reached a moment later, so the time goes with the change).
  final int Function() _now;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  bool _bound = false;
  int _base = 0;

  /// The editor's changes handed to the document and not yet answered for, each as the editor made it.
  final List<_Flight> _inflight = [];
  void Function()? _stopSplices;
  void Function()? _stopRoom;
  Timer? _sayCaret;
  Timer? _placeCarets;
  bool _placing = false;
  bool _placeAgain = false;
  Map<String, Object?>? _saidCaret;

  /// The stretches of one change told so far, as one change of the editor's words, until its last is told.
  ChangeSet? _gathered;

  /// Whether a stretch of the change being told did not fit the editor's words: the rest are passed over, and
  /// the editor is brought to the document's words at its last.
  bool _lost = false;

  /// How many changes and moves of this person's own the editor has seen: a caret is put back after an undo only
  /// if this has not moved since it was asked for.
  int _moves = 0;

  /// Settles once every undo and redo asked for so far has been answered and put into the editor.
  Future<void> _steps = Future<void>.value();

  bool get bound => _bound;

  @override
  bool get canUndo => _bound && text.undoState.canUndo;

  @override
  bool get canRedo => _bound && text.undoState.canRedo;

  static final List<Annotation<Object?>> _fromElsewhere = <Annotation<Object?>>[Transaction.remote.of(true), Transaction.addToHistory.of(false)];

  /// The same, for words an AI typed: out of a brief, light smoke that clears at once ([WispKind.typed]), as the
  /// app's own Claude's do. The connector already sends them a few words at a time at its pace
  /// (docs/CLAUDE_LIVE.md, "Streaming"); they are not held back here, since the editor must hold the document's
  /// words for the next change from the room to fit.
  static final List<Annotation<Object?>> _fromAi = <Annotation<Object?>>[..._fromElsewhere, wisp.of(WispKind.typed)];

  /// Whether a change that arrived is an AI's to draw out of smoke: Ghostly typing on, words put in, and an AI's
  /// caret in the room (the connector says it before each run of words it types).
  bool _smoky(ChangeSet change) {
    if (!(smoke?.call() ?? false) || change.empty) return false;
    var inserts = false;
    change.iterChanges((fromA, toA, fromB, toB, inserted) => inserts = inserts || inserted.length > 0);
    if (!inserts) return false;
    final room = this.room;
    if (room == null) return false;
    for (final MapEntry(key: client, value: said) in room.states.entries) {
      if (client != room.clientId && said['cursor'] is Map && Me.of(said['user'])?.ai == true) return true;
    }
    return false;
  }

  /// Binds: the editor brought to the document's words, then each following the other (`bindLive`).
  void bind() {
    if (_bound) return;
    _bound = true;
    _base = text.rev;
    final document = text;
    if (document is TeamDoc) document.editing = true;
    final found = spliceBetween(view.state.doc.toString(), text.words);
    view.dispatch(TransactionSpec(
      changes: found == null ? null : Change(from: found.at, to: found.at + found.removed, insert: found.inserted),
      effects: <StateEffect<Object?>>[
        liveSlot.reconfigure(Extension.list(<Extension>[EditorViewLike.updateListener.of(_heard), _observers, if (room != null) remoteCarets])),
        // liveBinding.ts: CodeMirror's undo swapped for the document's, with its keys.
        undoSlot.reconfigure(liveUndoWithKeys(this)),
      ],
      annotations: _fromElsewhere,
    ));
    // A new undo with nothing in it, before anything typed from here on reaches the document.
    unawaited(text.openUndo().then<void>((_) {}, onError: (Object _) {}));
    _gathered = null;
    _lost = false;
    _stopSplices = text.onSplice(_arrived);
    _stopRoom = room?.onChange(_placeSoon);
    _saySoon();
    _placeSoon();
  }

  /// A press or a key of this person's in the editor, heard and passed on: whatever it does, it is theirs.
  late final Extension _observers = EditorViewLike.eventObservers(EditorEventHandlers(
    pointerDown: (_, _) {
      _touch();
      return false;
    },
    keyDown: (_, _) {
      _touch();
      return false;
    },
  ));

  void _touch() {
    if (_bound) touched.value += 1;
  }

  /// Unbinds: the editor is the note's own again (`unbindLive`). Its words stay as they are.
  void unbind() {
    if (!_bound) return;
    _bound = false;
    final document = text;
    if (document is TeamDoc) document.editing = false;
    _stopSplices?.call();
    _stopRoom?.call();
    _sayCaret?.cancel();
    _placeCarets?.cancel();
    _inflight.clear();
    // The document's steps go with the binding, as the page's `Y.UndoManager` does with its editor's plugin.
    unawaited(text.closeUndo().catchError((Object _) {}));
    try {
      // unbindLive: `undoSlot.reconfigure(localUndo())`, a history with nothing in it.
      view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[liveSlot.reconfigure(const Extension.list(<Extension>[])), undoSlot.reconfigure(localUndoWithKeys())]));
    } catch (_) {
      // The editor went first (its note closed): nothing left to unbind.
    }
  }

  /// This person's last step taken back: asked of the document (y-undomanager.js `undo`), whose answer is put
  /// into the editor when it comes. Keys pressed before it was asked are in the document before it, and keys
  /// pressed after it are carried over it.
  @override
  void undo() => _step(false);

  /// The last step taken back put in again (y-undomanager.js `redo`).
  @override
  void redo() => _step(true);

  /// Settles once every undo and redo asked for so far is in the editor: what a test waits on.
  Future<void> undone() => _steps;

  void _step(bool redo) {
    if (!_bound) return;
    final asked = _moves;
    final done = text.undoStep(redo: redo, now: _now()).then<void>((done) {
      if (done == null || !_bound) return;
      final caret = done.caret;
      // y-undomanager.js on `stack-item-popped`: the selection kept with the step is put back and scrolled to.
      // Not when this person has typed or moved the caret since they asked: the caret is where they put it.
      if (!done.changed || caret == null || asked != _moves) return;
      final limit = view.state.doc.length;
      final anchor = caret.anchor.clamp(0, limit), head = caret.head.clamp(0, limit);
      // `fromYRange`, dispatched as `{selection: range}`: a caret keeps its side for the scroll alone.
      final range = anchor == head ? EditorSelection.cursor(head, caret.assoc) : EditorSelection.range(anchor, head);
      try {
        view.dispatch(TransactionSpec(selection: EditorSelection.single(anchor, head), effects: EditorViewLike.scrollIntoView(head, range: range)));
      } catch (_) {
        // The editor went first: the words are the document's either way.
      }
    }, onError: (Object _) {});
    _steps = _steps.then((_) => done);
  }

  /// The editor changed: what was typed here goes into the document, as the edits it was.
  void _heard(ViewUpdate update) {
    if (!_bound) return;
    for (final tr in update.transactions) {
      final mine = tr.annotation(Transaction.remote) != true;
      if (mine && (tr.docChanged || tr.selection != null)) _moves += 1;
      // A selection the app set (a note opened at a place) is not this person's doing; a press or a key is heard
      // as it lands ([_observers]), and typing is.
      if (mine && tr.docChanged) _touch();
      if (tr.docChanged && mine) _typed(tr);
    }
    // y-undomanager.js `update`: the selection is stored, as positions in the document, whenever an update sets one
    // and is not the binding's own (a change that arrived, an undo's); the step the next change begins keeps it.
    // After this update's own changes, as the page's undo plugin runs after its sync plugin.
    if (update.transactions.isNotEmpty && update.transactions.first.annotation(Transaction.remote) != true && update.transactions.any((tr) => tr.selection != null)) {
      final main = update.state.selection.main;
      unawaited(text.keepCaret(CrdtCaret(main.anchor, main.head, main.assoc), base: _base).catchError((Object _) {}));
    }
    if (update.docChanged || update.transactions.any((tr) => tr.selection != null) || update.focusChanged) _saySoon();
    if (update.docChanged) _placeSoon();
  }

  /// One change of this person's own, into the document as the edits it was.
  void _typed(Transaction tr) {
    final edits = <CrdtEdit>[];
    final made = <Change>[];
    tr.changes.iterChanges((fromA, toA, fromB, toB, inserted) {
      // Only what differs: a change that writes the whole note again (words put in from outside the editor, a
      // paste over a selection of the same words) is the stretch that changed, as `applyTextDiff` makes it.
      final found = spliceBetween(tr.startState.doc.sliceString(fromA, toA), inserted.toString());
      if (found == null) return;
      edits.add(CrdtEdit(fromB + found.at, remove: found.removed, insert: found.inserted));
      made.add(Change(from: fromA + found.at, to: fromA + found.at + found.removed, insert: found.inserted));
    });
    if (edits.isEmpty) return;
    final flight = _Flight(ChangeSet.of(made, tr.startState.doc.length));
    _inflight.add(flight);
    unawaited(text.edit(edits, base: _base, now: _now()).then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
      _inflight.remove(flight);
      _settled();
    }));
  }

  /// A change reached the document that is not this editor's typing (an update from elsewhere, an undo of the
  /// document's own): into the editor, over what was typed here meanwhile. A change of several stretches is told
  /// one stretch at a time and put into the editor as one change, when its last has come ([TextSplice.more]).
  void _arrived(TextSplice splice) {
    if (!_bound) return;
    _base = splice.rev;
    if (_lost) {
      // A stretch before this one did not fit: the document's words stand, once the change is whole.
      if (!splice.more) _mend();
      return;
    }
    final gathered = _gathered;
    // The words the splice was made in: the document's before it, which is the editor's (with the stretches
    // gathered so far) before what is in flight.
    final length = _inflight.isNotEmpty ? _inflight.first.made.length : gathered?.newLength ?? view.state.doc.length;
    if (length != text.words.length - splice.inserted.length + splice.removed) {
      // Not the words it was made in: the document's stand, now and again once what is in flight is answered for.
      _lost = true;
      if (!splice.more) _mend();
      return;
    }
    try {
      var arrived = ChangeSet.of(Change(from: splice.at, to: splice.at + splice.removed, insert: splice.inserted), length);
      for (final flight in _inflight) {
        final mine = flight.made;
        flight.made = mine.map(arrived, true);
        arrived = arrived.map(mine);
      }
      final whole = gathered == null ? arrived : gathered.compose(arrived);
      if (splice.more) {
        _gathered = whole;
        return;
      }
      _gathered = null;
      view.dispatch(TransactionSpec(changes: whole, annotations: _smoky(whole) ? _fromAi : _fromElsewhere));
    } catch (_) {
      // Not the words it was made in after all: the document's stand.
      _lost = true;
      if (!splice.more) _mend();
      return;
    }
    _settled();
  }

  /// A change that did not fit the editor's words: what was gathered of it and what was in flight are let go, and
  /// the editor is brought to the document's words.
  void _mend() {
    _lost = false;
    _gathered = null;
    _inflight.clear();
    _heal();
  }

  /// Nothing typed here is on its way: the editor and the document hold the same words, or the editor is brought
  /// to the document's.
  void _settled() {
    if (!_bound || _inflight.isNotEmpty) return;
    if (view.state.doc.length != text.words.length || view.state.doc.toString() != text.words) _heal();
  }

  void _heal() {
    final found = spliceBetween(view.state.doc.toString(), text.words);
    if (found == null) return;
    view.dispatch(TransactionSpec(changes: Change(from: found.at, to: found.at + found.removed, insert: found.inserted), annotations: _fromElsewhere));
  }

  void _saySoon() {
    if (room == null || positions == null || !room!.saysCaret) return;
    _sayCaret?.cancel();
    _sayCaret = Timer(_caretRest, () => unawaited(_say()));
  }

  /// This editor's selection, said in the room as positions that hold in every member's copy. The last place
  /// stands while the editor is not being typed in, as on the page.
  Future<void> _say() async {
    final room = this.room, positions = this.positions;
    if (!_bound || room == null || positions == null || !view.hasFocus) return;
    // Once the document holds what the editor does: a position is asked of the document's words.
    await text.settled();
    if (!_bound || _inflight.isNotEmpty) return _saySoon();
    final selection = view.state.selection.main;
    try {
      final cursor = <String, Object?>{'anchor': await positions.relative(selection.anchor), 'head': await positions.relative(selection.head)};
      if (!_bound || '$cursor' == '$_saidCaret') return;
      _saidCaret = cursor;
      room.setField('cursor', cursor);
    } catch (_) {
      // The document went first.
    }
  }

  void _placeSoon() {
    if (room == null || positions == null) return;
    _placeCarets?.cancel();
    _placeCarets = Timer(_caretRest, () => unawaited(_place()));
  }

  /// The others' carets, placed in this copy of the document and handed to the editor.
  Future<void> _place() async {
    final room = this.room, positions = this.positions;
    if (!_bound || room == null || positions == null) return;
    if (_placing) {
      _placeAgain = true;
      return;
    }
    _placing = true;
    try {
      await text.settled();
      final placed = <RemoteCaret>[];
      for (final MapEntry(key: client, value: said) in room.states.entries) {
        if (client == room.clientId) continue;
        final cursor = said['cursor'];
        if (cursor is! Map || cursor['anchor'] == null || cursor['head'] == null) continue;
        final at = await positions.caretIndexes(cursor);
        if (at == null) continue;
        final who = Me.of(said['user']);
        placed.add(RemoteCaret(client: client, name: who?.name ?? 'Anonymous', hue: who?.hue, ai: who?.ai ?? false, anchor: at.anchor, head: at.head));
      }
      if (!_bound) return;
      // Placed in the document's words; while keys are on their way the editor is a little ahead, and they are
      // placed again once it is not.
      if (_inflight.isNotEmpty) _placeAgain = true;
      placed.sort((a, b) => a.client.compareTo(b.client));
      final now = remoteCaretsOf(view.state);
      if (now.length != placed.length || !List.generate(now.length, (i) => now[i] == placed[i]).every((same) => same)) {
        view.dispatch(TransactionSpec(effects: setRemoteCarets.of(placed), annotations: _fromElsewhere));
      }
      carets.value = List.unmodifiable(placed);
    } catch (_) {
      // The document or the editor went first.
    } finally {
      _placing = false;
      if (_placeAgain && _bound) {
        _placeAgain = false;
        _placeSoon();
      }
    }
  }
}
