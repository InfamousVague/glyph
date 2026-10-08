/// Undo, in a slot live sync can swap: the port of ../glyph `src/app/editor/undoSlot.ts`.
///
/// A note on its own undoes with the editor's history (`history.dart`). A note live on two devices will undo with
/// the live document's own undo instead, which takes back this person's typing and leaves the other device's
/// alone. One compartment serves every editor: a [Compartment] is a key, and each editor's state keeps its own
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
