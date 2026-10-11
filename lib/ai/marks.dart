/// The AI's marks on a note, kept with it. A port of `src/app/ai/marks.ts`.
///
/// Matt chose marks that stay until Keep, Revert, Clear marks, or typing on the line - leaving the note keeps them
/// for next time. Each note's changes are kept on the device with a hash of the body they belong to; opened again,
/// the marks go back on only when the body still hashes the same, since a note edited elsewhere in between (another
/// device, Claude, a file) has words the positions no longer point at. A reset clears the key with every other
/// `glyph-` one.
///
/// What differs: a kept record is read as the JSON it is and each change through `AiChange.fromJson`, so a record
/// whose changes are not all changes answers no marks where the page would hand the editor whatever was there.
library;

import '../core/stored.dart';
import '../format/body_hash.dart';
import 'ai_changes.dart';
import 'support/note_sheet.dart';

const String _key = 'glyph-ai-marks';

/// Per note, its marks and the hash of the body they were made on (`{hash, changes}`). Read afresh each time rather
/// than shared: what [loadMarks] answers goes back into an editor, which is given a list of its own.
final NoteSheet<Object> _sheet = NoteSheet<Object>(
  () => stored.read<Sheet<Object>>(_key, <String, Object>{}, (raw) => sheetOf<Object>(raw)),
  (value) => stored.write(_key, value),
);

/// The marks on a note as it now reads. None clears what was kept.
void saveMarks(String noteId, String body, List<AiChange> changes) {
  _sheet.update(
    noteId,
    (_) => changes.isNotEmpty ? <String, Object?>{'hash': bodyHash(body), 'changes': <Object?>[for (final c in changes) c.toJson()]} : null,
  );
}

/// The marks kept for a note, if the body is still the one they were made on.
List<AiChange>? loadMarks(String noteId, String body) {
  final kept = _sheet.read()[noteId];
  if (kept is! Map) return null;
  final changes = kept['changes'];
  if (kept['hash'] != bodyHash(body) || changes is! List) return null;
  final out = <AiChange>[];
  for (final raw in changes) {
    final change = AiChange.fromJson(raw);
    if (change == null) return null;
    out.add(change);
  }
  return out;
}

/// Whether a note has marks kept, for a card to wear a dot.
bool hasMarks(String noteId) => _sheet.read().containsKey(noteId);

/// A note is gone: so are its marks.
void forgetMarks(String noteId) => _sheet.forget(noteId);
