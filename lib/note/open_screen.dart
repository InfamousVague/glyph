/// The screen a note is open in, for whoever must ask it rather than write its note behind it.
///
/// On the page a note's screen is handed what was asked of it as a prop (`rename`, editor/NoteScreen.tsx), and
/// writes it itself: the note being read is its screen's, whose live words are what its next save writes, so a
/// write to the store from outside would be flushed away by the next keystroke. Here the screen's state has the
/// method ([NoteScreenState.renameHere]) and the asker finds the state.
library;

import 'package:flutter/widgets.dart';

import 'note_screen.dart';

/// The screen [noteId] is open in, somewhere under [root]; null where it is not open there.
NoteScreenState? openNoteScreen(BuildContext? root, String noteId) {
  NoteScreenState? found;
  void visit(Element element) {
    if (found != null) return;
    if (element case StatefulElement(state: final NoteScreenState state) when state.widget.note.id == noteId) {
      found = state;
      return;
    }
    element.visitChildren(visit);
  }

  root?.visitChildElements(visit);
  return found;
}
