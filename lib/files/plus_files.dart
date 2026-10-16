/// What the + beside the line does with A file and Scan a document (lib/editor/plus/add_rows.dart): the place is
/// kept where the caret was, the device's picker or scanner is opened (lib/files/files_kit.dart `pick`, `scan`),
/// and the file's line is written there on a line of its own once it is kept, as a film's is: one Undo, the caret
/// after it, a blank line first under words. A note left meanwhile, or a place written over, takes nothing.
library;

import '../editor/commands/inserts.dart' show insertLineAt, releaseSpot, reserveSpot, spotAt;
import '../editor/editor.dart';
import '../editor/media/images.dart' show failureWords;
import '../notes/note_templates.dart' show formatStamp;
import 'attachment_store.dart';
import 'files_kit.dart';

/// A scan's name, for the moment it was made: "Scan 2026-10-16 14.05.pdf", the minute as a journal entry names it,
/// with nothing a drive's file names refuse.
String scanName(DateTime at) => 'Scan ${formatStamp(at, 'YYYY-MM-DD HH.mm')}.pdf';

/// Brings a file in by [get] and writes its line where the caret was when it was asked. [still] says whether the
/// note is still the one it was asked for; [say] is told a failure's sentence; [landed] that the line is written.
Future<void> putFileIn(EditorViewLike editor, Future<KeptAttachment?> Function() get, {required bool Function() still, required void Function(String message) say, void Function()? landed}) async {
  final kept = reserveSpot(editor.state);
  editor.dispatch(kept.tr);
  final spot = kept.spot;
  try {
    final file = await get();
    if (file == null || !still() || spotAt(editor.state, spot) == null) return;
    editor.dispatch(insertLineAt(editor.state, spot, file.markdown, userEvent: 'input.plus.drawn', apart: true).tr);
    landed?.call();
  } catch (failure) {
    if (still()) say(failureWords(failure));
  } finally {
    if (still()) editor.dispatch(releaseSpot(editor.state, spot));
  }
}

/// The home screen's quick action, Scan a document (the launcher's shortcuts are `feat/reminders`'): opens the
/// scanner and answers the words of a new note holding what was scanned, named for the minute, or null when the
/// person left the scanner or this device cannot scan. Throws a [StateError] with a sentence when the scan could
/// not be kept. Whoever calls it makes the note with these words and opens it.
Future<String?> scanToNewNote({DateTime? at, FilesKit? kit}) async {
  final files = kit ?? FilesKit.current;
  if (files == null || !files.scans) return null;
  final when = at ?? DateTime.now();
  final name = scanName(when);
  final scan = await files.scan(name: name);
  if (scan == null) return null;
  return '# ${name.substring(0, name.length - 4)}\n\n${scan.markdown}\n';
}
