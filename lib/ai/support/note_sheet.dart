/// A record per note, kept on the device under one key: what the app remembers about each note between visits. A
/// port of `src/app/core/noteSheet.ts`.
///
/// The AI keeps several things this way: the home page's gist (format/results.dart), the run log with its Undo
/// (ai/log.dart), the AI's marks still on a note (ai/marks.dart) and a summary's kept text (ai/summary_keep.dart).
/// Each hands over its own read and write through core/stored.dart, naming its `glyph-` key at the call. Storage
/// that refuses is a device that cannot remember: the sheet reads as empty and a write is silence.
///
/// What differs: a sheet is a `Map<String, V>`, and "no record" is null where the page said `undefined`. `identical`
/// stands for the page's `===` on what [NoteSheet.update]'s function answers. Kept under lib/ai until lib/core has a
/// note_sheet.dart of its own.
library;

/// Every note's record, by note id (`Sheet`).
typedef Sheet<V> = Map<String, V>;

/// A sheet as read: only an object of notes is one, and anything else another build or a half-written store left is
/// an empty one (`sheetOf`). [one] reads a single record, answering null for one to leave out; without it every
/// value of type [V] is kept.
Sheet<V> sheetOf<V>(Object? value, [V? Function(Object? raw)? one]) {
  if (value is! Map) return <String, V>{};
  final sheet = <String, V>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) continue;
    final read = one != null ? one(entry.value) : (entry.value is V ? entry.value as V : null);
    if (read != null) sheet[key] = read;
  }
  return sheet;
}

/// The sheet `read` answers and `write` keeps (`NoteSheet`, `noteSheet`).
class NoteSheet<V extends Object> {
  NoteSheet(this._read, this._write);

  final Sheet<V> Function() _read;
  final void Function(Sheet<V> sheet) _write;

  /// Every note's record, as last kept. What it answers may be shared between readers: a change goes through
  /// [update].
  Sheet<V> read() => _read();

  /// One note's record worked out from the one kept (null when there is none) and kept: answering null takes the
  /// note's record away, and answering the record it was given leaves the sheet as it is, unwritten.
  void update(String noteId, V? Function(V? was) fn) {
    final sheet = _read();
    final was = sheet[noteId];
    final next = fn(was);
    if (identical(next, was)) return;
    // A copy: a read may be shared by every reader, and is never changed in place.
    final copy = {...sheet};
    if (next == null) {
      copy.remove(noteId);
    } else {
      copy[noteId] = next;
    }
    _write(copy);
  }

  /// A note is gone: so is its record.
  void forget(String noteId) => update(noteId, (_) => null);
}
