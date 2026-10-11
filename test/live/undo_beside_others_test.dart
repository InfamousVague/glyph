// Undo in a live note, beside another member's writing (docs/PARITY.md, Differs 26).
//
// Ghost.md swaps CodeMirror's history for Yjs's own in a live note (editor/liveBinding.ts: `new Y.UndoManager(
// session.text)`, handed to y-codemirror's `yCollab`, with `yUndoManagerKeymap`), which takes back this person's
// own letters by what they are in the document. This app keeps the editor's own history (lib/live/editor_binding.dart:
// what arrives is kept out of it, `addToHistory` false, and the history maps over it, as CodeMirror's own
// collaboration does).
//
// These are the cases, each with what Yjs's UndoManager answers for it (asked of Yjs 13 itself, the web app's own,
// two documents and a sync between them: the words after `yjs:` below). Where this person TYPED and takes it back,
// the editor's history answers the same, letter for letter: whatever they typed goes, and nothing of the other
// member's does. Where a run of this person's was DELETED and the other member then wrote at that very place, the
// two can part, and so can a redo of typing taken back: Yjs keeps the letters taken out where they stood (as
// tombstones) and puts each back there, before, among or after what the other wrote; the editor's history knows the
// run only by where it was, hears "X at 3" in every one of those, and puts the run back whole after X. Every letter
// of both is there either way, in another order. The tests hold what is true of each case, so a change to either
// shows.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';

/// An editor's state with its history, what this person does to it, and what arrives from another member.
class Note {
  Note(String doc) : state = EditorState.create(doc: doc, extensions: history());

  EditorState state;

  void mine(int from, int to, String insert) => state = state.update(TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: insert), userEvent: 'input.type')).state;

  /// As lib/live/editor_binding.dart puts in what another member wrote: out of the history.
  void theirs(int from, int to, String insert) =>
      state = state.update(TransactionSpec(changes: ChangeSpec(from: from, to: to, insert: insert), annotations: <Annotation<Object?>>[Transaction.remote.of(true), Transaction.addToHistory.of(false)])).state;

  void undoIt() => undo(StateCommandTarget(state, (tr) => state = tr.state));

  void redoIt() => redo(StateCommandTarget(state, (tr) => state = tr.state));

  String get words => state.doc.toString();
}

void main() {
  test('their letter inside the run I typed stays, and my run goes (yjs: 01234X56789)', () {
    final note = Note('0123456789')
      ..mine(5, 5, 'abc')
      ..theirs(6, 6, 'X')
      ..undoIt();
    expect(note.words, '01234X56789');
  });

  test('their letter at the end of the run I typed, written at the same moment, stays (yjs: 01234X56789)', () {
    final note = Note('0123456789')
      ..mine(5, 5, 'abc')
      ..theirs(8, 8, 'X');
    expect(note.words, '01234abcX56789');
    note.undoIt();
    expect(note.words, '01234X56789');
  });

  test('a letter of mine they deleted is not deleted twice (yjs: 0123456789)', () {
    final note = Note('0123456789')
      ..mine(5, 5, 'abc')
      ..theirs(6, 7, '')
      ..undoIt();
    expect(note.words, '0123456789');
  });

  test('a word I replaced comes back, and what they added to it stays (yjs: the cats sat)', () {
    final note = Note('the cat sat')
      ..mine(4, 7, 'dog')
      ..theirs(7, 7, 's');
    expect(note.words, 'the dogs sat');
    note.undoIt();
    expect(note.words, 'the cats sat');
  });

  test('WHERE THE TWO CAN DIFFER: a run I deleted, with a letter of theirs where it was, comes back whole after the letter', () {
    // What the editor hears is the same in all four: my run gone, then X where it was.
    final note = Note('0123456789')
      ..mine(3, 6, '')
      ..theirs(3, 3, 'X');
    expect(note.words, '012X6789');
    note.undoIt();
    expect(note.words, '012X3456789');
    // yjs, by where X stands among the letters taken out:
    //   written once they had heard of my deleting (the usual way):  012345X6789   after the run
    //   written at the same moment, between 2 and 3:                 012X3456789   as here
    //   written at the same moment, between 3 and 4:                 0123X456789   inside the run
    //   written at the same moment, between 5 and 6:                 012345X6789   after the run
  });

  test('WHERE THE TWO DIFFER: typing I took back and put back again goes after what they wrote there meanwhile (yjs: 01234abcX56789)', () {
    final note = Note('0123456789')
      ..mine(5, 5, 'abc')
      ..undoIt()
      ..theirs(5, 5, 'X');
    expect(note.words, '01234X56789');
    note.redoIt();
    expect(note.words, '01234Xabc56789');
  });
}
