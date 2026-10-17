/// Claude typing into an open note (docs/CLAUDE_APP.md, "Typing as Claude writes"): the words a tool's input
/// carries put into the note's editor as they stream, a few letters a frame, at Claude's caret, with the note kept
/// scrolled to it while it is followed.
///
/// The note's editor stays its one writer (lib/root/note_desk.dart): what is typed here is an ordinary change of the
/// editor's, saved by the note's own saving, carried to the note's live document where it is bound (so another
/// device with the note open sees it arrive too), and undone by the person's undo like their own. It is said as
/// Claude's (`userEvent: 'claude.type'`), and rises out of smoke where Ghostly typing is on and the note draws
/// arrivals.
///
/// Claude's caret is drawn as a member's is (lib/live/editor_binding.dart [RemoteCaretWidget]), in Claude's colour
/// with its name on it, from a field of its own ([claudeTyping]) that rides every change, the person's included: what
/// they type above Claude's words moves Claude along, and Claude goes on where it was. A press or a key of theirs
/// in the note stops the following, never the typing.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' hide Decoration;

import '../editor/editor.dart';
import '../editor/marks/wisp_motion.dart' show WispKind, wisp;
import '../live/editor_binding.dart' show RemoteCaretWidget;

/// The hue Claude's caret is drawn in, the presence's own for an AI (docs/CLAUDE_LIVE.md, "Who Claude is").
const String claudeHue = 'violet';

/// Where Claude's caret is in an editor: the place, or null for none.
final StateEffectType<int?> setClaudeCaret = StateEffect.define<int?>();

class _Caret {
  const _Caret(this.at, this.touches);

  final int? at;

  /// How many presses and keys of the person's own the editor has heard.
  final int touches;
}

/// Counts the person's own doings in an editor; bumped by [_observers].
final StateEffectType<void> _touched = StateEffect.define<void>();

final StateField<_Caret> _caret = StateField.define<_Caret>(
  create: (_) => const _Caret(null, 0),
  update: (value, tr) {
    var at = value.at, touches = value.touches;
    if (at != null && tr.docChanged) at = tr.changes.mapPos(at, 1);
    for (final effect in tr.effects) {
      final set = setClaudeCaret.cast(effect);
      if (set != null) at = set.value;
      if (_touched.cast(effect) != null) touches += 1;
    }
    if (at == value.at && touches == value.touches) return value;
    return _Caret(at, touches);
  },
  provide: (field) => EditorViewLike.decorations.compute(<Object>[field], (state) {
    final at = state.field(field).at;
    if (at == null) return Decoration.none;
    final place = at.clamp(0, state.doc.length);
    return Decoration.set(<Range<Decoration>>[Decoration.widget(widget: const RemoteCaretWidget('Claude', claudeHue), side: 1).range(place)], true);
  }),
);

/// A press or a key of the person's own, said to the field a frame later (an observer may not dispatch while the
/// view handles the event).
final Extension _observers = EditorViewLike.eventObservers(EditorEventHandlers(
  pointerDown: (_, view) {
    _sayTouched(view);
    return false;
  },
  keyDown: (_, view) {
    _sayTouched(view);
    return false;
  },
));

void _sayTouched(EditorViewLike view) {
  if (view.state.fieldOrNull(_caret)?.at == null) return;
  scheduleMicrotask(() {
    try {
      view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[_touched.of(null)]));
    } catch (_) {
      // The editor went first.
    }
  });
}

/// What an editor needs for Claude to type into it: the caret's field and what hears the person. Every note's
/// editor has it (lib/root/note_desk.dart), so a note opened for Claude is ready the moment it is.
final Extension claudeTyping = Extension.list(<Extension>[_caret, _observers]);

/// Where Claude's caret is in [state], or null.
int? claudeCaretOf(EditorState state) => state.fieldOrNull(_caret)?.at;

/// How many presses and keys of the person's own [state]'s editor has heard while Claude's caret was in it.
int claudeTouchesOf(EditorState state) => state.fieldOrNull(_caret)?.touches ?? 0;

/// Claude's caret put at [at] in [view] and scrolled to the middle of the page: a note opened to follow Claude,
/// where Claude last typed. Said as Claude's, so it is not taken for the person's doing.
void showClaudeCaret(EditorViewLike view, int at) {
  try {
    final place = at.clamp(0, view.state.doc.length);
    view.dispatch(TransactionSpec(
      effects: <StateEffect<Object?>>[setClaudeCaret.of(place), EditorViewLike.scrollIntoView(place, y: ScrollStrategy.center)],
      userEvent: 'claude.type',
    ));
    SchedulerBinding.instance.ensureVisualUpdate();
  } catch (_) {
    // The editor went first.
  }
}

/// Claude's caret taken out of [view]: the run is over.
void clearClaudeCaret(EditorViewLike view) {
  try {
    if (claudeCaretOf(view.state) == null) return;
    view.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[setClaudeCaret.of(null)], userEvent: 'claude.type'));
  } catch (_) {
    // The editor went first.
  }
}

/// Claude typing into one editor, for one tool call.
class NoteTyper {
  /// [follow] says whether the note is followed (kept scrolled to the caret); [smoke] whether words rise out of
  /// smoke. [frame] is how often letters are put in; a test's clock may make it anything.
  /// [open] says whether the editor is still the note's on screen; once it is not, what is left is kept for the
  /// tool to write behind it ([left], at [lastAt]).
  /// [onTouched] is told once when the person first presses or types in the note while it is followed.
  NoteTyper(this.view, {required this.follow, required this.smoke, required this.open, this.onTouched, this.frame = const Duration(milliseconds: 16)});

  final VoidCallback? onTouched;
  bool _toldTouched = false;

  /// Following again (Watch): the person's earlier presses no longer stop the scrolling.
  void rewatch() {
    if (!alive) return;
    _touchesAtStart = claudeTouchesOf(view.state);
    _toldTouched = false;
  }

  final EditorViewLike view;
  final bool Function() follow;
  final bool Function() smoke;
  final bool Function() open;
  final Duration frame;

  /// What could not be typed because the note was closed under Claude, and where its caret last was.
  final StringBuffer _left = StringBuffer();
  int? _lastAt;
  String get left => _left.toString();
  int? get lastAt => _lastAt;

  /// Whether every word reached the editor.
  bool get whole => _left.isEmpty && _broken == false;
  bool _broken = false;

  final StringBuffer _waiting = StringBuffer();
  Timer? _ticker;
  Completer<void>? _drained;
  bool _done = false;
  int _touchesAtStart = 0;

  /// Whether the person has pressed or typed in the note since Claude began: following stops then.
  bool get touched => claudeTouchesOf(view.state) > _touchesAtStart;

  /// Whether the editor can still be typed into.
  /// [open] asked at most every quarter second: on screen it is a look through the whole tree.
  bool _openNow = true;
  DateTime? _openAsked;

  bool _stillOpen() {
    final now = DateTime.now();
    final asked = _openAsked;
    if (asked == null || now.difference(asked) >= const Duration(milliseconds: 250)) {
      _openAsked = now;
      _openNow = open();
    }
    return _openNow;
  }

  bool get alive {
    try {
      return !_broken && _stillOpen() && view.state.fieldOrNull(_caret) != null;
    } catch (_) {
      return false;
    }
  }

  /// Where the caret is now.
  int? get at => alive ? claudeCaretOf(view.state) : null;

  /// Puts the caret at [at] (and remembers it as [lastAt]), taking out [to] − [at] letters there first (an old
  /// passage being replaced).
  void begin(int at, {int? to}) {
    if (!alive) {
      _broken = true;
      return;
    }
    final limit = view.state.doc.length;
    final from = at.clamp(0, limit), end = (to ?? at).clamp(from, limit);
    _touchesAtStart = claudeTouchesOf(view.state);
    _lastAt = from;
    _dispatch(
      changes: end > from ? Change(from: from, to: end) : null,
      effects: <StateEffect<Object?>>[setClaudeCaret.of(from), if (follow()) _scrollTo(from)],
      smoky: false,
    );
  }

  /// More of Claude's words, put in at the pace the frames allow.
  void type(String text) {
    if (text.isEmpty || _done) return;
    if (_broken) {
      _left.write(text);
      return;
    }
    _waiting.write(text);
    _ticker ??= Timer.periodic(frame, (_) => _tick());
  }

  /// Settles once everything given to [type] is in.
  Future<void> drained() {
    if (_waiting.isEmpty) return Future<void>.value();
    return (_drained ??= Completer<void>()).future;
  }

  /// Puts everything waiting in at once (Stop, or a test).
  void flush() {
    if (_waiting.isEmpty) return;
    final text = _waiting.toString();
    _waiting.clear();
    _put(text);
    _settled();
  }

  /// Ends the call: what waits is put in. The caret stays where Claude last typed (Matt: "If we follow Claude I
  /// also want to see a cursor where Claude last typed"), until the run ends ([clearClaudeCaret]) or Claude types
  /// somewhere else in this note.
  Future<void> end() async {
    await drained();
    _done = true;
    _ticker?.cancel();
    _ticker = null;
  }

  void _tick() {
    if (_waiting.isEmpty) {
      _ticker?.cancel();
      _ticker = null;
      _settled();
      return;
    }
    final text = _waiting.toString();
    // A hand's pace for a short wait; for a long one, enough a frame that the words never fall more than about
    // half a second behind Claude.
    var take = text.length <= 24 ? 2 : (text.length / 30).ceil();
    if (take > text.length) take = text.length;
    // Never half of a letter.
    if (take < text.length) {
      final unit = text.codeUnitAt(take - 1);
      if (unit >= 0xD800 && unit <= 0xDBFF) take += 1;
    }
    _waiting.clear();
    _waiting.write(text.substring(take));
    _put(text.substring(0, take));
    if (_waiting.isEmpty) _settled();
  }

  void _settled() {
    final waiting = _drained;
    _drained = null;
    if (waiting != null && !waiting.isCompleted) waiting.complete();
  }

  void _put(String text) {
    final at = this.at;
    if (at == null) {
      _broken = true;
      _left.write(text);
      _left.write(_waiting.toString());
      _waiting.clear();
      return;
    }
    final place = at.clamp(0, view.state.doc.length);
    _lastAt = place + text.length;
    if (follow() && touched && !_toldTouched) {
      _toldTouched = true;
      onTouched?.call();
    }
    _dispatch(
      changes: Change(from: place, insert: text),
      effects: <StateEffect<Object?>>[setClaudeCaret.of(place + text.length), if (follow() && !touched) _scrollTo(place + text.length)],
      smoky: true,
    );
  }

  StateEffect<Object?> _scrollTo(int at) => EditorViewLike.scrollIntoView(at, y: ScrollStrategy.center);

  void _dispatch({ChangeSpec? changes, required List<StateEffect<Object?>> effects, required bool smoky}) {
    try {
      view.dispatch(TransactionSpec(
        changes: changes,
        effects: effects,
        annotations: <Annotation<Object?>>[if (smoky && changes != null && smoke()) wisp.of(WispKind.heard)],
        userEvent: 'claude.type',
      ));
      SchedulerBinding.instance.ensureVisualUpdate();
    } catch (_) {
      // The editor went while Claude was typing: what is left is written by the tool's own fallback.
    }
  }
}
