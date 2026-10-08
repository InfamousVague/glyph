/// The notes this device gave words to and nobody has written in yet (docs/DESIGN.md §142, §144): what lets one left
/// untouched be taken back. A port of `src/app/core/untouched.ts`.
///
/// A journal's entry, a new note turned into a template from its blank page, and a new note named from one of the
/// names under its first line are each one. The record is written first, before the words, and a note whose words
/// are still the words it was given, left, is taken back. Kept in the device's own memory under the key the journal
/// wrote first, `glyph-entry-drafts`; at most twenty, none older than a week; never synced.
///
/// **Fresh.** A take-back is a delete with no Trash and no toast, so a record may be written only for a note this
/// run is making and nobody has written in: one made in this run ([UntouchedNotes.markFresh]), until its words are
/// first anything but empty or the app's own. Kept in memory and nowhere else.
///
/// What differs: the page's module functions are the methods of one [UntouchedNotes] over a [Stored], the app's
/// being [untouchedNotes]; a test makes its own over a [MemoryStored].
library;

import 'front_matter.dart';
import 'stored.dart';

/// What was written for a note as it was given its words (`UntouchedRecord`).
class UntouchedRecord {
  const UntouchedRecord({this.journalId, required this.title, required this.words, required this.at});

  /// The journal it is an entry of; null for a new note given words from its blank page.
  final String? journalId;
  final String title;

  /// Its words as they were made, after the front matter: while they are still these, nobody has written in it.
  final String words;

  /// When it was made, in ms.
  final int at;

  static UntouchedRecord? _read(Object? value) {
    if (value is! Map) return null;
    final journalId = value['journalId'], title = value['title'], words = value['words'], at = value['at'];
    if ((journalId != null && journalId is! String) || title is! String || words is! String || at is! num) return null;
    return UntouchedRecord(journalId: journalId as String?, title: title, words: words, at: at.toInt());
  }

  Map<String, Object?> _json() => {if (journalId != null) 'journalId': journalId, 'title': title, 'words': words, 'at': at};
}

const String _key = 'glyph-entry-drafts';
const int _keep = 20;
const int _weekMs = 7 * 24 * 60 * 60000;

/// A note's words after its front matter: what a record compares (`wordsOf`).
String wordsOf(String body) => body.substring(frontMatterOffset(body));

/// The records, and the notes made in this run (`core/untouched.ts`).
class UntouchedNotes {
  UntouchedNotes({Stored? kept, int Function()? clock})
      : _kept = kept,
        _clock = clock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final Stored? _kept;
  final int Function() _clock;
  Stored get _device => _kept ?? stored;

  /// Every record kept, by the note's id: none of another build's shape, and none older than a week
  /// (`untouchedRecords`).
  Map<String, UntouchedRecord> records() {
    final all = _device.read<Map<String, Object?>>(_key, const {}, (raw) => raw is Map ? raw.cast<String, Object?>() : null);
    final now = _clock();
    final kept = <String, UntouchedRecord>{};
    for (final entry in all.entries) {
      final record = UntouchedRecord._read(entry.value);
      if (record != null && now - record.at <= _weekMs) kept[entry.key] = record;
    }
    return kept;
  }

  void _writeAll(Map<String, UntouchedRecord> records) {
    final newest = records.entries.toList()..sort((a, b) => b.value.at.compareTo(a.value.at));
    final kept = newest.take(_keep);
    _device.write(_key, kept.isEmpty ? null : {for (final entry in kept) entry.key: entry.value._json()});
  }

  /// Keeps the record of a note just being given words (`rememberUntouched`).
  void remember(String id, UntouchedRecord record) => _writeAll({...records(), id: record});

  /// The note's record, or null (`untouchedRecord`).
  UntouchedRecord? recordOf(String id) => records()[id];

  /// The words an untouched entry is taken as having now (`setUntouchedWords`).
  void setWords(String id, String words) {
    final all = records();
    final record = all[id];
    if (record == null) return;
    _writeAll({...all, id: UntouchedRecord(journalId: record.journalId, title: record.title, words: words, at: record.at)});
  }

  /// The note is the person's now, or gone: nothing is kept for it (`forgetUntouched`).
  void forget(String id) {
    final all = records();
    if (!all.containsKey(id)) return;
    all.remove(id);
    _writeAll(all);
  }

  /// Whether the note [id] is still as this device made it: a record, words that are still the record's (a place or
  /// a look written into its front matter is not a word), and no recording, pin or archive, each of which is a
  /// person's doing (`isUntouched`).
  bool isUntouched(String id, String body, {int? recordingMs, bool starred = false, int? archivedAt}) {
    final record = recordOf(id);
    if (record == null) return false;
    if ((recordingMs ?? 0) != 0 || starred || (archivedAt ?? 0) != 0) return false;
    return wordsOf(body).trim() == record.words.trim();
  }

  /// The new notes made in this run that have had no words of the person's own.
  final Set<String> _fresh = {};

  /// A note just made: nobody has written in it (`markFresh`).
  void markFresh(String id) => _fresh.add(id);

  /// Whether the note was made in this run and has had no words of the person's own (`isFresh`).
  bool isFresh(String id) => _fresh.contains(id);

  /// The note has had words of the person's own: it is never offered a name or a template again (`spoilFresh`).
  void spoilFresh(String id) => _fresh.remove(id);

  /// What a change to a fresh note's words does to it: words that are empty, or the app's own, leave it fresh;
  /// anything else is the person's, and spoils it (`keepFresh`).
  void keepFresh(String id, String body) {
    if (!_fresh.contains(id)) return;
    if (wordsOf(body).trim().isEmpty || isUntouched(id, body)) return;
    _fresh.remove(id);
  }
}

/// The app's own.
final UntouchedNotes untouchedNotes = UntouchedNotes();
