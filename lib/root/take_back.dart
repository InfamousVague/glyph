import 'dart:async';

import '../book/book_view.dart' show withoutChapter;
import '../core/library.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/trash.dart';
import '../core/untouched.dart';

/// An entry nobody has written in, taken back once it is left (docs/DESIGN.md §142): the promise a new note keeps,
/// that a note opened and left leaves nothing behind, kept for an entry that had words from birth. And the same for
/// a new note given words from its blank page, a template or a name (§144), whose record has no journal: the note
/// goes, and there is no line to take out. A port of `App.tsx`'s `stays`, `lineOut`, `takeBack` and the effect that
/// runs them.
///
/// **A take-back is a delete with no Trash and no toast**, since nothing of the person's is lost. So every condition
/// is the web's own, in its order:
/// - A note [stays] while it is the note on screen, while a capture is aimed at it, and while its tab is open behind
///   another note, a capture or a meeting: a tab switched, a link followed, a recording of something else. Asked
///   before the store is read and again after, since the person may have come back to it meanwhile.
/// - An entry still being made ([making]) is left alone until it is on screen.
/// - The store not answering is the next look's.
/// - A note already gone has only its line taken out, and its record forgotten.
/// - A new note given its words on its blank page gets them from its screen's save, which a note left at once may
///   still be making: the store has no words yet, so the next look decides.
/// - In the Trash, it is left there with its line, so Undo brings both back; its record goes.
/// - Touched (its words are not the record's, or it has a recording, a pin or an archive: core/untouched.dart), it is
///   the person's, and only its record goes.
/// - Only then is it deleted, with its line, its tab and its record.
///
/// Looked at ([look]) whenever the screen or the open tabs change, and at launch. Never on a screen's unmount: that
/// is also a tab switch and the entry's own mic starting a capture.
///
/// What differs: the page's refs are this object's fields, and what it asks of the app comes in by the constructor.
/// A place waiting for the note's first words (`setPendingTag(id, null)`) is [forgetTag], which nothing gives yet:
/// no note here keeps a place.
class TakeBack {
  TakeBack({
    required this.library,
    required this.trash,
    required this.untouched,
    required this.stays,
    required this.writeJournal,
    required this.dropTab,
    this.forgetTag,
  });

  final NoteLibrary library;
  final Trash trash;
  final UntouchedNotes untouched;

  /// Whether the note is still somewhere the person has not left it (`stays`).
  final bool Function(String id) stays;

  /// A change to a journal's index: through its screen when it is open, else a write from what the store has
  /// (`writeJournal`).
  final Future<void> Function(String journalId, String Function(String body) change) writeJournal;

  /// The note's tab out of the row (`tabs.drop`).
  final void Function(String id) dropTab;

  /// The place waiting for the note's first words, let go (`setPendingTag(id, null)`).
  final void Function(String id)? forgetTag;

  /// Entries being made now: the take-back leaves them alone until they are on screen (`making`). The journal's
  /// pages' own set in the app (lib/book/journal_view.dart `JournalPages.making`).
  Set<String> making = {};
  final Set<String> _takingBack = {};

  /// Every record looked at once: the ones left are read fresh and, untouched, taken back. Answers when every
  /// take-back it began is over, for a test; the app does not wait.
  Future<void> look() {
    final began = <Future<void>>[];
    for (final MapEntry(key: id, value: record) in untouched.records().entries) {
      if (making.contains(id) || _takingBack.contains(id) || stays(id)) continue;
      _takingBack.add(id);
      began.add(_takeBack(id, record).whenComplete(() => _takingBack.remove(id)));
    }
    return Future.wait(began).then<void>((_) {}, onError: (Object _) {});
  }

  /// An entry's line out of its journal, unless another note is named by it now: then the line is that note's too,
  /// and taking it out would leave a written entry out of its journal. Left in when the store does not answer, the
  /// lesser harm: a line with an entry's name and no note is not drawn (`lineOut`).
  Future<void> _lineOut(String id, UntouchedRecord record) async {
    final journalId = record.journalId;
    if (journalId == null) return;
    final List<Note> all;
    try {
      await library.refresh();
      all = library.value;
    } catch (_) {
      return;
    }
    if (all.any((note) => note.id != id && sameTitle(noteTitle(note.body), record.title))) return;
    await writeJournal(journalId, (body) => withoutChapter(body, record.title));
  }

  Future<void> _takeBack(String id, UntouchedRecord record) async {
    final Note? fresh;
    try {
      fresh = await library.get(id);
    } catch (_) {
      // The store did not answer: the next look.
      return;
    }
    if (stays(id) || making.contains(id)) return;
    if (fresh == null) {
      await _lineOut(id, record);
      untouched.forget(id);
      return;
    }
    // A new note given its words on its blank page gets them from its screen's save, which a note left at once may
    // still be making: the store has no words yet, so the next look decides. The screen forgets the record of a note
    // emptied on it, so a record with no words in the store is only ever that.
    if (record.journalId == null && !trash.isTrashed(id) && wordsOf(fresh.body).trim().isEmpty) return;
    if (trash.isTrashed(id) || !untouched.isUntouched(id, fresh.body, recordingMs: fresh.recordingMs, starred: fresh.starred, archivedAt: fresh.archivedAt)) {
      untouched.forget(id);
      return;
    }
    await library.destroy(id);
    await _lineOut(id, record);
    forgetTag?.call(id);
    dropTab(id);
    untouched.forget(id);
    await library.refresh();
  }
}
