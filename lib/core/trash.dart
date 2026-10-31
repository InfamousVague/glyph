/// The trash. A port of `src/app/core/trash.ts` (Matt: "Send deleted notes to a trash folder where we can empty it to
/// perma delete notes or restore notes").
///
/// Deleting a note puts it here rather than ending it: it leaves every list, tab, search and link at once, and waits
/// in the sidebar's Trash folder to be restored, deleted for good, or emptied with the rest. The note itself is
/// untouched until the trash is emptied; only then is it deleted from the library. One that has waited
/// [trashKeeps] (thirty days) is deleted for good by itself, the next time the app looks ([expiredInTrash]; the
/// port's own, 2026-10-23), unless it is an organization's.
///
/// What differs: the web keeps which note went in and when as a preference (`preferences().trash`), which syncs.
/// Here it is [Trash], an interface that can be listened to (the web's `useTrash`): the app's is the preference
/// (lib/core/kept_trash.dart), and [MemoryTrash] is one for this run, for a test. The module's functions are its
/// methods, under the web's own names.
library;

import 'package:flutter/foundation.dart';

import 'note.dart';

/// Notes in the trash, by id: when each went in, in milliseconds (`Trash`).
typedef TrashHeld = Map<String, int>;

/// The trash (`core/trash.ts`): which notes are in it and when each went in. Its value is the held map (`trash()`),
/// never changed in place, so a listener can compare one with the next.
abstract class Trash implements ValueListenable<TrashHeld> {
  /// Whether the note is in the trash (`isTrashed`).
  bool isTrashed(String id);

  /// Into the trash, at [now] or this moment (`trashNote`).
  void trashNote(String id, [int? now]);

  /// Out of the trash, back to wherever it was: its workspace, pin and archive were never touched (`restoreNote`).
  void restoreNote(String id);

  /// The trash no longer holding these: restored, or deleted for good and gone from the library (`forget`).
  void forget(Iterable<String> ids);
}

/// [Trash] held in memory for this run. The app's is the preference (lib/core/kept_trash.dart).
class MemoryTrash extends ValueNotifier<TrashHeld> implements Trash {
  MemoryTrash([TrashHeld held = const {}, int Function()? clock])
      : _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch),
        super(Map.unmodifiable(held));

  final int Function() _clock;

  @override
  bool isTrashed(String id) => value.containsKey(id);

  @override
  void trashNote(String id, [int? now]) => value = Map.unmodifiable({...value, id: now ?? _clock()});

  @override
  void restoreNote(String id) => forget([id]);

  @override
  void forget(Iterable<String> ids) {
    if (!ids.any(value.containsKey)) return;
    final next = {...value};
    ids.forEach(next.remove);
    value = Map.unmodifiable(next);
  }
}

/// Whether [note] is in the trash: in the held map, or its file under the library's `.trash/` folder
/// ([Note.inTrash]; Matt, 2026-10-31: "a `.trash/` folder, as Obsidian does"). The files' word counts too, so a note
/// whose file another device or a restored backup put in the trash is never shown live while the map catches up
/// (lib/core/trash_files.dart).
bool trashedNote(Note note, TrashHeld held) => held.containsKey(note.id) || note.inTrash;

/// The notes that are not in the trash: everything the app shows outside the Trash folder (`outOfTrash`).
List<Note> outOfTrash(Iterable<Note> notes, TrashHeld held) => [
      for (final note in notes)
        if (!trashedNote(note, held)) note,
    ];

/// The notes in the trash, the most recently thrown away first (`inTrash`); one the map has no time for (its file
/// alone says it is trashed) sorts last.
List<Note> inTrash(Iterable<Note> notes, TrashHeld held) {
  final found = [
    for (final note in notes)
      if (trashedNote(note, held)) note,
  ];
  // A merge sort keeps two thrown away in the same millisecond in the order they were given, as the page's sort does.
  mergeSort<Note>(found, compare: (a, b) => (held[b.id] ?? 0).compareTo(held[a.id] ?? 0));
  return found;
}

/// How long a note waits in the trash before it is deleted for good (Matt, 2026-10-23: "add a "trash" section in the
/// app where deleted notes go before getting perma deleted"). The port's own: the web's trash kept a note until it
/// was emptied. Thirty days, as the Trash's foot says (lib/notes/trash_sheet.dart).
const Duration trashKeeps = Duration(days: 30);

/// The notes in the trash whose time there is up at [now] (milliseconds), the longest there first: what the purge
/// deletes for good ([trashKeeps]). [kept] says of a note that it waits for a person's own Empty however long it
/// has been there: an organization's, whose deleting for good deletes it for every member (lib/team/sync.dart's
/// push), which no timer should do on one member's behalf.
List<Note> expiredInTrash(Iterable<Note> notes, TrashHeld held, int now, {bool Function(String id)? kept}) {
  final due = [
    for (final note in notes)
      if (held[note.id] case final at? when now - at >= trashKeeps.inMilliseconds && !(kept?.call(note.id) ?? false)) note,
  ];
  mergeSort<Note>(due, compare: (a, b) => (held[a.id] ?? 0).compareTo(held[b.id] ?? 0));
  return due;
}

/// How long [at] (milliseconds) has left in the trash at [now], in whole days, rounded up, and never less than
/// none: "in 29 days" for a note thrown away a day ago.
int trashDaysLeft(int at, int now) {
  final left = trashKeeps.inMilliseconds - (now - at);
  if (left <= 0) return 0;
  return (left / Duration.millisecondsPerDay).ceil();
}
