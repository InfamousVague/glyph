import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/note/note_editor.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'support.dart';

/// What the note's screen tells its editor of the page over it (`NoteEditorSpec`), for the line being typed to be
/// kept as far over the keyboard as the page keeps it (Editor.tsx `footClearAt`: a third of the page less its own top
/// padding).
///
/// The page: the Tauri app on a phone's emulator at 2.625, a note sixteen lines long being typed in with the keyboard
/// up, 2026-10-09. `[data-scrolls]` was 420px tall with a `padding-top` of 155.625 (`.header:empty ~ .page`: the
/// header's 142, `--glacier-space-1` and `--glacier-space-2`), so the clearance was 88.125px and the last line's
/// foot stood 90.35 over the keyboard. The port took the third of the page less the header's 142.06 (92.6, cut to the
/// smoke's 93), and its line stood 15 device pixels higher.
void main() {
  setUpAll(loadAppFonts);

  testWidgets('the page’s own top padding is what a third of the page is taken under, not the header alone', (tester) async {
    final world = NoteWorld();
    final note = (await tester.runAsync(() => seedNote(world, 'foot-clear', '# Day\n')))!;
    await pumpNote(tester, world, note);
    final t = tester.element(find.byType(NoteEditorHost)).tokens;
    final spec = tester.widget<NoteEditorHost>(find.byType(NoteEditorHost)).spec;
    // Under a bar that holds the note's tools the header is empty, and the page keeps the room its padding was.
    final header = t.len('app-safe-top');
    expect(spec.headClear, closeTo(header, 1e-6));
    expect(spec.pageHead, closeTo(header.roundToDouble() + t.space(1) + t.space(2), 1e-6));
    await closeNote(tester);
  });
}
