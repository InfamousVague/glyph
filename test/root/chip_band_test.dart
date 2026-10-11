// A chip tapped in a note (docs/PARITY.md, Differs 18): the note's own band opens at the chip, on that field's page.
// Ghost.md's ContextMenu.tsx hears the tap (`useFieldTaps`) and does `setFields({ page, line, back: false, refocus })`
// and `setOpen` at the chip; this app hung a menu of the kit's from the chip instead and never called the band's
// `openFields`.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/band/band.dart';
import 'package:ghost_md/editor/items/field_chips.dart' show FieldChip;
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:glacier/glacier.dart' show GlacierMenu;

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a tapped due day opens the band at the chip on the day\'s page, with no Back, and a press there writes the day', (tester) async {
    final library = SampleLibrary.seeded();
    final made = library.create('# Chores\n\n- [ ] Pay the rent 📅 2026-09-20 ⏫\n- [ ] Call Sam\n');
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.openNote(made.id);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    final controller = tester.widget<ContextBand>(find.byType(ContextBand)).controller;
    expect(controller.isOpen, isFalse);

    final due = find.byWidgetPredicate((w) => w is FieldChip && w.look.key == 'due');
    final chip = tester.getRect(due);
    await tester.tap(due);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.isOpen, isTrue, reason: 'the band, not a menu of its own');
    expect(find.byType(GlacierMenu), findsNothing);
    expect(controller.page, BandPage.fields);
    expect(controller.fields!.page, const FieldDatePage('due'));
    expect(controller.fields!.line, 3);
    expect(controller.fields!.back, isFalse, reason: 'a chip\'s page has nothing to go back to');
    expect(controller.held!.x, closeTo(chip.center.dx, 6));
    expect(controller.held!.y, closeTo(chip.top, 6));
    expect(view.state.selection.main.head, controller.held!.from, reason: 'the caret stays where it was');
    // The day's choices are the band's rows, and a press writes the day and closes it.
    for (final label in const <String>['Today', 'Tomorrow', 'Next week', 'Remove']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Back'), findsNothing);
    await tester.tap(find.text('Remove'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(view.state.doc.line(3).text, '- [ ] Pay the rent ⏫');
    expect(controller.isOpen, isFalse);

    // The priority's chip opens the band on the priorities.
    await tester.tap(find.byWidgetPredicate((w) => w is FieldChip && w.look.key == 'priority'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.fields!.page, isA<FieldPriorityPage>());
    controller.close();
    await tester.pump(const Duration(milliseconds: 300));

    shell.backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });
}
