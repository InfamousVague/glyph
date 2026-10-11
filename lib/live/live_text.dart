/// A live document's words as an editor is bound to them (lib/live/editor_binding.dart): what `Y.Text` is to
/// y-codemirror, said for a document that is a call away.
///
/// A team note's document is one ([TeamDoc], lib/team/doc.dart), and so is an account's own note while it is live
/// ([LiveSession], session.dart). Both number the changes that reach the words from elsewhere
/// (lib/team/text_log.dart), and take an editor's own change with the number its words were at.
library;

import '../team/crdt.dart';
import '../team/text_log.dart';

export '../team/crdt.dart' show CrdtCaret, CrdtChange, CrdtEdit, CrdtUndone, UndoState;
export '../team/text_log.dart' show TextSplice;

/// The words, and the two ways they change.
abstract interface class LiveText {
  /// The document's words now, as far as this device has heard.
  String get words;

  /// How many changes from elsewhere they have taken.
  int get rev;

  /// An editor's own changes, in order, as one; [base] is the [rev] its words were at when it made them. [now] is
  /// when they were made, in milliseconds: the undo makes one step of changes less than half a second apart, and
  /// the document may be reached a moment after the key.
  Future<Object?> edit(List<CrdtEdit> edits, {int? base, int? now});

  /// Where the bound editor's selection stands, in its words as they were at [base]: kept by the document as
  /// positions that stay with their characters, and given to the undo step the next change begins, so taking
  /// that step back puts the selection back (y-codemirror's `_storeSelection`).
  Future<void> keepCaret(CrdtCaret caret, {int? base});

  /// The bound editor's undo begins, with nothing in it: `new Y.UndoManager(session.text)`, as
  /// `src/app/editor/liveBinding.ts` makes one each time an editor is bound. From here until [closeUndo] it follows
  /// [edit] and nothing else.
  Future<UndoState> openUndo();

  /// The undo is let go and its steps with it: the editor is unbound.
  Future<void> closeUndo();

  /// What the bound editor's undo holds, as far as the document has said: whether there is a step to take back
  /// and one to put in again. [UndoState.none] while no editor is bound.
  UndoState get undoState;

  /// The last step the bound editor made taken back, or with [redo] the last one taken back put in again: the
  /// document's own undo, which leaves what the others wrote alone and puts a run back where its letters stood.
  /// What it does to the words is told to [onSplice]'s listeners, as the stretches it was, before this settles,
  /// and goes out like any change made here. [now] is [edit]'s. Null when the document is gone.
  Future<CrdtUndone?> undoStep({required bool redo, int? now});

  /// Told each change from elsewhere, in order. Answers the way to stop hearing.
  void Function() onSplice(void Function(TextSplice splice) listener);

  /// Settles once everything asked of the document so far is done.
  Future<void> settled();
}
