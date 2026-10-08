/// The trash. A port of `src/app/core/trash.ts` (Matt: "Send deleted notes to a trash folder where we can empty it to
/// perma delete notes or restore notes").
///
/// Deleting a note puts it here rather than ending it: it leaves every list, tab, search and link at once, and waits
/// in the sidebar's Trash folder to be restored, deleted for good, or emptied with the rest. The note itself is
/// untouched until the trash is emptied; only then is it deleted from the library.
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

/// The notes that are not in the trash: everything the app shows outside the Trash folder (`outOfTrash`).
List<Note> outOfTrash(Iterable<Note> notes, TrashHeld held) => [
      for (final note in notes)
        if (!held.containsKey(note.id)) note,
    ];

/// The notes in the trash, the most recently thrown away first (`inTrash`).
List<Note> inTrash(Iterable<Note> notes, TrashHeld held) {
  final found = [
    for (final note in notes)
      if (held.containsKey(note.id)) note,
  ];
  // A merge sort keeps two thrown away in the same millisecond in the order they were given, as the page's sort does.
  mergeSort<Note>(found, compare: (a, b) => (held[b.id] ?? 0).compareTo(held[a.id] ?? 0));
  return found;
}
