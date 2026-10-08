/// What every block drawn in place of its markdown shares: a table, a diagram, a canvas's frame and a board. Ports
/// `src/app/editor/drawnBlock.ts`.
///
/// Each is drawn while the caret is elsewhere and steps aside for its lines while the caret is in them, and a tap
/// on the drawing puts the caret there. So each needs to know, from inside a state field, whether the view has
/// focus: block decorations have to come from a state field, not a view plugin, and a field cannot ask the view.
/// Focus is therefore kept in a field of its own from `focusChangeEffect`, shared by every kind of block.
///
/// What differs:
/// - `openOnPress(view, element, at)` added a `mousedown` listener to a DOM element; [openOnPress] here answers
///   the handler for a widget's own `GestureDetector` (or `Listener`) to call.
/// - `isDrawnBlock(target)` asked the DOM whether a press landed inside `.cm-board, .cm-mermaid, ...`; here a
///   block widget that answers a press itself says so by implementing [DrawnBlock], and [isDrawnBlock] asks the
///   widget the view found under the point (`EditorHit.block`).
library;

import '../state/selection.dart';
import '../state/state.dart';
import 'plugin.dart';
import 'widget.dart';

final StateEffectType<bool> _setFocus = StateEffect.define<bool>();

/// Whether the view has focus, as the last focus change said: false until it is first focused.
final StateField<bool> _focusField = StateField.define<bool>(
  create: (_) => false,
  update: (focused, tr) {
    for (final effect in tr.effects) {
      final told = _setFocus.cast(effect);
      if (told != null) return told.value;
    }
    return focused;
  },
);

/// The focus field and what feeds it: installed by each drawn block, held once.
final Extension trackFocus = Extension.list(<Extension>[_focusField, EditorViewLike.focusChangeEffect.of((state, focusing) => _setFocus.of(focusing))]);

/// Whether the view has focus, for a state field that has to decide what to draw.
bool focused(EditorState state) => state.fieldOrNull(_focusField) ?? false;

/// Whether `tr` is the view gaining or losing focus, which moves every drawn block's decision.
bool focusMoved(Transaction tr) => tr.effects.any((effect) => effect.isOf(_setFocus));

/// Whether the caret is in `from`-`to`, edges included, in a focused view: the block's lines are shown there, to
/// be typed in, rather than its drawing. A view with no caret (never focused, or left) draws every block.
bool caretIn(EditorState state, int from, int to) => focused(state) && state.selection.ranges.any((range) => range.to >= from && range.from <= to);

/// A press on a drawn block puts the caret at `at`, the block's first line, so the drawing steps aside and its
/// markdown can be edited. A view that cannot be edited keeps the drawing: there is nothing to type. Answers
/// whether the press was taken.
bool openOnPress(EditorViewLike view, int at) {
  if (!view.state.facet(EditorViewLike.editable)) return false;
  view.dispatch(TransactionSpec(selection: EditorSelection.single(at)));
  view.focus();
  return true;
}

/// A block widget that answers a press itself (a board, a diagram, a place's map card, a film's card, a query's
/// answer) rather than standing for lines of text, which the note's own press-and-hold menu is about.
abstract interface class DrawnBlock {}

/// Whether a press landed on a drawn block that answers it itself.
bool isDrawnBlock(EditorWidget? target) => target is DrawnBlock;
