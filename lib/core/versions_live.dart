/// The open note's editor, as the version history needs it from outside the note. A port of
/// `src/app/core/versions/live.ts`.
///
/// The history in the aside (lib/aside/aside_history.dart) sits beside the note rather than in it, but what it
/// compares a version with is the words as they are in the editor now, and a version is put back through the
/// editor, as one change to undo, saved the way typing is (lib/note/note_screen.dart `restoreVersion`). So the note
/// on screen says here how to do both, for as long as it is on screen.
///
/// What differs: `useLiveNote` is [liveNotes], a listenable told as notes open and close, with [liveNote] to ask.
library;

import 'package:flutter/foundation.dart';

import 'versions_file.dart' show Version;

@immutable
class LiveNote {
  const LiveNote({required this.current, required this.restore});

  /// The words in the editor now.
  final String Function() current;

  /// Puts a version's words into the note, through the editor.
  final void Function(String text, Version version) restore;
}

final Map<String, LiveNote> _live = <String, LiveNote>{};

class _Told extends ChangeNotifier {
  void tell() => notifyListeners();
}

final _Told _told = _Told();

/// Told as a note's editor comes on screen and as it goes (`useLiveNote`'s store).
Listenable get liveNotes => _told;

/// Note [noteId]'s editor is on screen; answers the way to say it has gone.
VoidCallback liveNoteOpened(String noteId, LiveNote note) {
  _live[noteId] = note;
  _told.tell();
  return () {
    if (!identical(_live[noteId], note)) return;
    _live.remove(noteId);
    _told.tell();
  };
}

/// Note [noteId]'s editor, while it is on screen.
LiveNote? liveNote(String noteId) => _live[noteId];
