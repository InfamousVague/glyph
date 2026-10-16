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
