/// The trash's two records kept in step: the synced map of which note went in when ([Trash], the preference in
/// lib/core/kept_trash.dart) and the files, which since 2026-10-31 move into the library's `.trash/` folder
/// (library/trash.rs; Matt: "Trash: a `.trash/` folder, as Obsidian does"). The map is still written for a release,
/// so an old build agrees with a new one about what is in the trash (docs/MARKDOWN_FIRST.md §9, slice 4); the files
/// are what a backup of the library carries and what every other app sees.
///
/// Three rules, and nothing else moves a file for the trash:
///
/// 1. **The map leads while the app runs.** A note that appears in the map (trashed here, on another device, or on
///    an old build that only knows the map) has its file moved into `.trash/` ([NoteLibrary.putInTrash]); one that
///    leaves it (restored anywhere, or deleted for good) has its file moved back ([NoteLibrary.takeFromTrash], which
///    does nothing for a note that is gone). Both are moves the library makes idempotent, so the preference landing
///    whole from disk, or the same note trashed on two devices, costs a call and changes nothing.
/// 2. **The files win once, when the notes are first read.** A note whose file is in `.trash/` and which the map
///    does not know - a library restored from a backup or a clone, a file another app put there, a trash made on a
///    device whose settings never arrived - is put in the map now, so the Trash shows it and the thirty days start
///    from this reading. And a note the map holds whose file is still live is moved in: settings that landed before
///    the notes were read, or an old build's trashing.
/// 3. **A note is never shown live while its file is in the trash**, whatever the map says (lib/core/trash.dart
///    `trashedNote`, lib/shell/visible_notes.dart): the moves are asynchronous and the map may lag the files.
///
/// Rule 2 runs once and not on every read, on purpose: while the app runs a note arriving by sync with a `.trash/`
/// path is another device's trashing, whose map entry is on its way, and adopting it here as this device's own
/// change would make this device's entry win the settings merge over that device's later restore (lib/sync/prefs.dart
/// `_mergedEntries`: what both changed stays as it is here), and the note would stay in the trash on both.
///
/// Team notes: an organization's deletes skip the trash as they always have (lib/team/sync.dart removes a row another
/// member deleted outright), and a member's trashed copy is put to the team at the path it had, so no other member's
/// file moves.
library;

import 'package:flutter/foundation.dart';

import 'library.dart';
import 'trash.dart';

/// Keeps the library's `.trash/` folder in step with a [Trash] (see the library doc). Made once the two exist, and
/// disposed of with them.
class TrashFiles {
  TrashFiles({required this.library, required this.trash, void Function(String message)? log}) : _log = log ?? debugPrint {
    _held = trash.value;
    trash.addListener(_trashChanged);
    library.addListener(_libraryChanged);
    _libraryChanged();
  }

  final NoteLibrary library;
  final Trash trash;
  final void Function(String message) _log;

  /// The map as it was last heard, to tell what came in and what left.
  late TrashHeld _held;

  /// Whether the files-win pass (rule 2) has run.
  bool _reconciled = false;

  /// Whether the files-win pass is putting notes in the map just now: its own entries need no move.
  bool _adopting = false;

  /// Each note's moves, one after another, so a trash and its Undo inside the toast land in that order.
  final Map<String, Future<void>> _moves = {};

  /// Every move asked for so far, settled: for a test, and for whoever must know the files are where the map says.
  Future<void> settled() => Future.wait(_moves.values.toList());

  /// Whether the files-win pass has run.
  bool get reconciled => _reconciled;

  void _trashChanged() {
    final now = trash.value, was = _held;
    _held = now;
    if (_adopting) return;
    for (final id in now.keys) {
      if (!was.containsKey(id)) _move(id, into: true);
    }
    for (final id in was.keys) {
      if (!now.containsKey(id)) _move(id, into: false);
    }
  }

  void _libraryChanged() {
    if (_reconciled || library.loading) return;
    _reconcile();
  }

  /// Rule 2: the files' word taken once, and the map's word made good on the files.
  void _reconcile() {
    _reconciled = true;
    final held = trash.value;
    final adopt = <String>[];
    for (final note in library.value) {
      if (note.inTrash) {
        if (!held.containsKey(note.id)) adopt.add(note.id);
      } else if (held.containsKey(note.id) && note.path != null) {
        _move(note.id, into: true);
      }
    }
    if (adopt.isEmpty) return;
    _adopting = true;
    try {
      for (final id in adopt) {
        trash.trashNote(id);
      }
    } finally {
      _adopting = false;
    }
  }

  void _move(String id, {required bool into}) {
    final after = _moves[id] ?? Future<void>.value();
    _moves[id] = after.then((_) => into ? library.putInTrash(id) : library.takeFromTrash(id)).catchError((Object error) {
      _log('[glyph] the trash could not move a note\'s file ($id, ${into ? 'in' : 'out'}): $error');
    });
  }

  void dispose() {
    trash.removeListener(_trashChanged);
    library.removeListener(_libraryChanged);
  }
}
