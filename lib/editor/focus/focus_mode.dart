/// Focus mode: every block of the note dimmed but the one being written, and the line being written kept in the
/// middle of the page. Matt, 2026-10-27: "build ... focus mode", from docs/ideas/CUSTOMIZATION_AND_SOUNDS.md, idea
/// 14: "Dim every paragraph but the one being written, with a typewriter scroll that keeps the line in the middle".
///
/// [focusMode] is one extension with two halves, each asked of its [FocusModeHooks] as it is used, so that the
/// switch in Settings, in a note's More sheet or in the palette takes effect in the note already open, with no
/// editor made again:
/// - **The dimming** is [FocusDim], a view plugin and an [EntryShade]: the editor's sliver paints every entry (a line,
///   or a table, a board or a picture drawn over several) through a layer of the opacity it answers
///   (lib/editor/view/entry_shade.dart). The block the caret is in, or every block a selection touches, keeps its
///   ink; the rest are drawn at [focusDimOpacity]. A block is the leaf block of the parse round the caret
///   ([focusBlockAt]): a paragraph (a list item's words are its paragraph, a quote's lines theirs), a heading, a
///   code block, a table. On a blank line it is the line alone. Only while the editor has the keyboard's focus:
///   a note being read is drawn whole.
/// - **The fade.** As the caret moves into another block, the one it left dims and the one it is in brightens over
///   [focusFadeMs], at the pace Settings › Appearance › Motion sets; with the device's reduce motion asked for they
///   change at once. Only the opacity moves: nothing is laid out again for a frame of it.
/// - **The typewriter scroll** ([FocusModeHooks.typewriter]) is a transaction extender: every change that would
///   scroll the caret into view by the least move (typing, deleting, a key that moves the caret) scrolls it to the
///   middle instead. The middle is the middle of the room the page leaves (lib/editor/view/sliver.dart `reveal`,
///   `ScrollStrategy.center`): the scroll margins are the header's glass above and the soft keyboard and the foot's
///   blur below, so on a phone or a Fold the line stands in the middle of what is left over the keyboard, never
///   under it. A tap or a drag that puts the caret somewhere (`select.pointer`) is left where it is put: the page
///   does not jump from under a finger. The room under the last line, so that the last line can come up to the
///   middle too, is the note's screen's (lib/note/note_screen.dart).
library;

import 'package:flutter/animation.dart' show Curves;
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../editor.dart';
import '../syntax/tree.dart' show SyntaxNode;
import '../view/entry_shade.dart';
import '../view/syntax_tree.dart' show syntaxTree;

/// What focus mode asks, each as it is used: whether the page dims, whether the caret's line is kept in the middle,
/// and what to listen to for either changing. [still] (reduce motion) and [pace] (the Motion setting) are read as
/// the editor is made, as the wisp's are (lib/editor/marks/wisp_motion.dart `wispStill`, `wispPace`).
@immutable
class FocusModeHooks {
  const FocusModeHooks({required this.dim, required this.typewriter, this.changes, this.still = false, this.pace = 1});

  final bool Function() dim;
  final bool Function() typewriter;
  final Listenable? changes;
  final bool still;
  final double pace;
}

/// How much of its ink a block away from the caret keeps: enough to read back over, little enough to fall away.
const double focusDimOpacity = 0.3;

/// How long a block takes to dim or brighten at the normal pace, ms: a glance, not a wait.
const double focusFadeMs = 180;

/// A stretch of the document, by position.
typedef FocusBlock = ({int from, int to});

/// The block [pos] is in: the innermost leaf block of the parse round it (a paragraph, a heading, a code block, a
/// table), or its line where it is in none (a blank line).
FocusBlock focusBlockAt(EditorState state, int pos) {
  final tree = syntaxTree(state);
  // Leaning forward first, so a caret at a block's start is in it; then back, so one at its end is too.
  for (final side in const [1, -1]) {
    for (SyntaxNode? node = tree.resolveInner(pos, side); node != null; node = node.parent) {
      if (node.type.isA('LeafBlock')) return (from: node.from, to: node.to);
    }
  }
  final line = state.doc.lineAt(pos);
  return (from: line.from, to: line.to);
}

/// The lines a selection's blocks cover: from the block of its start to the block of its end.
({int first, int last}) focusLinesOf(EditorState state, SelectionRange range) {
  final start = focusBlockAt(state, range.from);
  final end = range.empty ? start : focusBlockAt(state, range.to);
  return (first: state.doc.lineAt(start.from).number, last: state.doc.lineAt(end.to).number);
}

/// Focus mode, asking [hooks] as it goes. See the library's note.
Extension focusMode(FocusModeHooks hooks) {
  final plugin = ViewPlugin.define<FocusDim>(
    (view) => FocusDim(view, hooks),
    provide: (plugin) => entryShades.of((view) => view.plugin<FocusDim>(plugin)),
  );
  return Extension.list(<Extension>[
    plugin,
    EditorState.transactionExtender.of((tr) {
      if (!tr.scrollIntoView || tr.isUserEvent('select.pointer') || !hooks.dim() || !hooks.typewriter()) return null;
      final head = tr.newSelection.main.head;
      // The least move's own margin of 5 is no use in the middle: the line is centred in the room the page leaves.
      return TransactionSpec(effects: EditorViewLike.scrollIntoView(head, y: ScrollStrategy.center, yMargin: 0));
    }),
  ]);
}

/// The dimming: which lines keep their ink, and the fade between one block and the next.
class FocusDim extends PluginValue with ChangeNotifier implements EntryShade {
  FocusDim(this.view, this.hooks) {
    hooks.changes?.addListener(_asked);
    _lit = _blockNow(view.state);
    _litLines = _linesOf(view.state, _lit);
  }

  final EditorViewLike view;
  final FocusModeHooks hooks;

  /// The stretch that keeps its ink now, and the one that did before the fade under way; null for none dimmed.
  FocusBlock? _lit, _was;
  ({int first, int last})? _litLines, _wasLines;

  /// How far the fade has come, 0 to 1.
  double _t = 1;
  Ticker? _ticker;
  bool _gone = false;

  /// The lines that keep their ink now, first and last; null while nothing is dimmed.
  ({int first, int last})? get litLines => _litLines;

  /// Whether a fade is under way.
  bool get fading => _t < 1;

  @override
  bool get dims => _lit != null || (_was != null && _t < 1);

  FocusBlock? _blockNow(EditorState state) {
    if (!hooks.dim() || !view.hasFocus) return null;
    final lines = focusLinesOf(state, state.selection.main);
    return (from: state.doc.line(lines.first).from, to: state.doc.line(lines.last).to);
  }

  static ({int first, int last})? _linesOf(EditorState state, FocusBlock? block) {
    if (block == null) return null;
    final doc = state.doc;
    final from = block.from.clamp(0, doc.length), to = block.to.clamp(from, doc.length);
    return (first: doc.lineAt(from).number, last: doc.lineAt(to).number);
  }

  @override
  void update(ViewUpdate update) {
    if (update.docChanged && _was != null) {
      // The block being left follows the words it was round, so lines that move under a fade keep their place in it.
      final was = _was!;
      _was = (from: update.changes.mapPos(was.from, -1), to: update.changes.mapPos(was.to, 1));
      _wasLines = _linesOf(update.state, _was);
    }
    if (update.docChanged || update.selectionSet || update.focusChanged) _move(update.state);
  }

  /// A switch was turned: dimmed or drawn whole from here, with the same fade.
  void _asked() {
    if (!_gone) _move(view.state);
  }

  void _move(EditorState state) {
    final next = _blockNow(state);
    final lines = _linesOf(state, next);
    if (lines == _litLines) {
      _lit = next;
      return;
    }
    _was = _lit;
    _wasLines = _litLines;
    _lit = next;
    _litLines = lines;
    final ms = focusFadeMs * hooks.pace;
    if (hooks.still || ms <= 0) {
      _settle();
    } else {
      _t = 0;
      _ticker ??= Ticker((elapsed) => _tick(elapsed, ms));
      if (_ticker!.isActive) _ticker!.stop();
      _ticker!.start();
    }
    notifyListeners();
  }

  void _tick(Duration elapsed, double ms) {
    _t = (elapsed.inMicroseconds / 1000 / ms).clamp(0.0, 1.0);
    if (_t >= 1) {
      _ticker?.stop();
      _settle();
    }
    notifyListeners();
  }

  void _settle() {
    _t = 1;
    _was = null;
    _wasLines = null;
  }

  static double _level(({int first, int last})? lit, int first, int last) {
    if (lit == null) return 1;
    return first <= lit.last && last >= lit.first ? 1 : focusDimOpacity;
  }

  @override
  double opacityOf(int first, int last) {
    final to = _level(_litLines, first, last);
    if (_t >= 1) return to;
    final from = _level(_wasLines, first, last);
    return from + (to - from) * Curves.easeOut.transform(_t);
  }

  @override
  void destroy() {
    _gone = true;
    hooks.changes?.removeListener(_asked);
    _ticker?.dispose();
    _ticker = null;
    dispose();
  }
}
