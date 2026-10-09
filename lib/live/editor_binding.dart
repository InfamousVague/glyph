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
/// - **Undo stays the editor's own** (lib/editor/state/undo_slot.dart `localUndo`), where the page swaps it for
///   `Y.UndoManager`: what arrives is kept out of the history (`addToHistory` false) and the history maps over
///   it, so an undo takes back this person's typing and leaves the others' alone, which is what the page's does.
/// - **A selection across lines** is washed line by line over its words; y-codemirror washes the lines between
///   the first and the last whole, to the page's edge, and an empty line among them is washed there and not here.
/// - **A caret is placed a moment after it is heard** (its relative position is the core's to place), and rides
///   the editor's own changes meanwhile.
/// - The caret's colour is the member's hue at the lightness this paper needs (the kit's `[data-hue]`), read from
///   the `hue` their presence carries; the CSS strings beside it (`color`, `colorLight`) are the page's to read.
library;

import 'dart:async';

import 'package:flutter/widgets.dart' hide Decoration;
import 'package:glacier/glacier.dart';

import '../editor/editor.dart';
import '../editor/items/inline_box.dart';
import '../editor/looks/look.dart';
import '../editor/looks/sheets.dart';
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
  const RemoteCaret({required this.client, required this.name, required this.hue, required this.anchor, required this.head});

  final int client;
  final String name;

  /// One of the app's hues, or null for ink.
  final String? hue;
  final int anchor;
  final int head;

  @override
  bool operator ==(Object other) => other is RemoteCaret && other.client == client && other.name == name && other.hue == hue && other.anchor == anchor && other.head == head;

  @override
  int get hashCode => Object.hash(client, name, hue, anchor, head);

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
        final wash = Decoration.mark(className: 'cm-ySelection ${_hueClass(caret.hue)}');
        final first = doc.lineAt(start).number, last = doc.lineAt(end).number;
        for (var n = first; n <= last; n += 1) {
          final line = doc.line(n);
          final from = n == first ? start : line.from, to = n == last ? end : line.to;
          if (to > from) ranges.add(wash.range(from, to));
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
      for (final caret in value.carets) RemoteCaret(client: caret.client, name: caret.name, hue: caret.hue, anchor: tr.changes.mapPos(caret.anchor, 1), head: tr.changes.mapPos(caret.head, 1)),
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

/// `ySelection`'s wash, a quarter of the member's colour (a fifth of the ink): one rule a hue.
final LookSheet _theme = LookSheet('live/editor_binding.dart', <LookRule>[
  for (final hue in <String?>[null, ...hueAngles.keys])
    LookRule(_hueClass(hue), (p, e) {
      final colour = memberColour(e.t, hue);
      final wash = colour.withValues(alpha: colour.a * (hue == null ? 0.20 : 0.24));
      p.background = (_) => wash;
    }),
]);

final Extension _themed = baseTheme(_theme);

/// How long a caret rests before it is said to the room, and before the others' are placed again.
const Duration _caretRest = Duration(milliseconds: 40);

/// A change of the editor's on its way to the document, as the editor made it and as it stands over what has
/// arrived since.
class _Flight {
  _Flight(this.made);
  ChangeSet made;
}

/// One editor bound to one live document.
class LiveBinding {
  /// [text] is the document; [room] and [positions], a team note's room and its document in the core, bring the
  /// carets. Nothing is bound until [bind].
  LiveBinding(this.view, this.text, {this.room, this.positions});

  final EditorViewLike view;
  final LiveText text;
  final TeamRoom? room;
  final CrdtDoc? positions;

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

  bool get bound => _bound;

  static final List<Annotation<Object?>> _fromElsewhere = <Annotation<Object?>>[Transaction.remote.of(true), Transaction.addToHistory.of(false)];

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
      effects: liveSlot.reconfigure(Extension.list(<Extension>[EditorViewLike.updateListener.of(_heard), if (room != null) _carets, if (room != null) _themed])),
      annotations: _fromElsewhere,
    ));
    _stopSplices = text.onSplice(_arrived);
    _stopRoom = room?.onChange(_placeSoon);
    _saySoon();
    _placeSoon();
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
    try {
      view.dispatch(TransactionSpec(effects: liveSlot.reconfigure(const Extension.list(<Extension>[]))));
    } catch (_) {
      // The editor went first (its note closed): nothing left to unbind.
    }
  }

  /// The editor changed: what was typed here goes into the document, as the edits it was.
  void _heard(ViewUpdate update) {
    if (!_bound) return;
    for (final tr in update.transactions) {
      if (!tr.docChanged || tr.annotation(Transaction.remote) == true) continue;
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
      if (edits.isEmpty) continue;
      final flight = _Flight(ChangeSet.of(made, tr.startState.doc.length));
      _inflight.add(flight);
      unawaited(text.edit(edits, base: _base).then<void>((_) {}, onError: (Object _) {}).whenComplete(() {
        _inflight.remove(flight);
        _settled();
      }));
    }
    if (update.docChanged || update.transactions.any((tr) => tr.selection != null) || update.focusChanged) _saySoon();
    if (update.docChanged) _placeSoon();
  }

  /// A change reached the document from elsewhere: into the editor, over what was typed here meanwhile.
  void _arrived(TextSplice splice) {
    if (!_bound) return;
    _base = splice.rev;
    // The words the splice was made in: the document's before it, which is the editor's before what is in flight.
    final length = _inflight.isEmpty ? view.state.doc.length : _inflight.first.made.length;
    if (length != text.words.length - splice.inserted.length + splice.removed) {
      // Not the words it was made in: the document's stand, now and again once what is in flight is answered for.
      _inflight.clear();
      _heal();
      return;
    }
    ChangeSet arrived;
    try {
      arrived = ChangeSet.of(Change(from: splice.at, to: splice.at + splice.removed, insert: splice.inserted), length);
      for (final flight in _inflight) {
        final mine = flight.made;
        flight.made = mine.map(arrived, true);
        arrived = arrived.map(mine);
      }
      view.dispatch(TransactionSpec(changes: arrived, annotations: _fromElsewhere));
    } catch (_) {
      // Not the words it was made in after all: the document's stand.
      _inflight.clear();
      _heal();
      return;
    }
    _settled();
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
    if (room == null || positions == null) return;
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
        placed.add(RemoteCaret(client: client, name: who?.name ?? 'Anonymous', hue: who?.hue, anchor: at.anchor, head: at.head));
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
