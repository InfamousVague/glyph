/// Undo, in a slot live sync can swap: the port of ../glyph `src/app/editor/undoSlot.ts`.
///
/// A note on its own undoes with the editor's history (`history.dart`). A note live on two devices, or a team's,
/// undoes with the live document's own undo instead ([noteUndo]), which takes back this person's typing and leaves
/// the other device's alone. One compartment serves every editor: a [Compartment] is a key, and each editor's state keeps its own
/// value under it.
///
/// The web file's `localUndo()` also carries `keymap.of(historyKeymap)`; here the keys are the input piece's
/// (`lib/editor/input/`), which binds them to [undo] and [redo].
library;

import 'history.dart';
import 'state.dart';

/// The compartment the editor puts its undo in: `undoSlot.of(localUndo())`.
final Compartment undoSlot = Compartment();

/// Undo for a note on its own: the editor's history.
Extension localUndo() => history();

/// Undo for a note whose editor is bound to its live document: the document's own (lib/live/editor_binding.dart),
/// which is what y-codemirror's `yCollab` puts in the slot in place of the history (`Y.UndoManager`, behind its
/// `yUndoManagerFacet`). The document is a call away, so both are asked and answered a moment later.
abstract interface class NoteUndo {
  /// Asks the document to take this editor's last step back.
  void undo();

  /// Asks it to put the last step taken back in again.
  void redo();

  /// Whether there is a step to take back, as far as the document has said: y-codemirror's `undoDepth` above zero.
  bool get canUndo;

  /// Whether there is one to put in again: its `redoDepth`.
  bool get canRedo;
}

/// The live document's undo, while the slot holds one: y-codemirror's `yUndoManagerFacet`, which reads the last given.
final Facet<NoteUndo, NoteUndo?> noteUndo = Facet.define<NoteUndo, NoteUndo?>(combine: (values) => values.isEmpty ? null : values.last);

/// y-undomanager.js `undo`: `state.facet(yUndoManagerFacet).undo() || true`. The key is taken whether or not there
/// was a step, so it never falls through to another undo.
bool undoLive(StateCommandTarget target) {
  target.state.facet(noteUndo)?.undo();
  return true;
}

/// y-undomanager.js `redo`.
bool redoLive(StateCommandTarget target) {
  target.state.facet(noteUndo)?.redo();
  return true;
}

/// Undo as the note has it now: its live document's while its editor is bound to one, else the editor's history.
/// For an undo that does not come by the slot's keys (the keyboard's own, a menu's): on the page that arrives as
/// `beforeinput`'s `historyUndo`, which CodeMirror's history and y-codemirror each answer with their own.
bool undoNote(StateCommandTarget target) => target.state.facet(noteUndo) != null ? undoLive(target) : undo(target);

/// Redo as the note has it now.
bool redoNote(StateCommandTarget target) => target.state.facet(noteUndo) != null ? redoLive(target) : redo(target);

/// Whether the note has a step to take back, whichever undo it has: for a menu's Undo.
bool canUndoNote(EditorState state) => state.facet(noteUndo)?.canUndo ?? undoDepth(state) > 0;

/// Whether it has one to put in again: for a menu's Redo.
bool canRedoNote(EditorState state) => state.facet(noteUndo)?.canRedo ?? redoDepth(state) > 0;
