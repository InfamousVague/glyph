import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/home/library_home.dart';

import '../support/render.dart';
import 'support.dart';

/// The home page over a library (lib/home/library_home.dart): its swipes done to the library, each with the Undo
/// the web's `notes/useNoteActions.ts` offers, and its + making a note where the page is.
void main() {
  setUpAll(loadAppFonts);

  Future<void> away(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  }

  Future<void> swipe(WidgetTester tester, String card, double dx) async {
    final gesture = await tester.startGesture(tester.getCenter(find.byKey(ValueKey(card))));
    await gesture.moveBy(Offset(dx.sign * 30, 0));
    await tester.pump();
    await gesture.moveBy(Offset(dx - dx.sign * 30, 0));
    await tester.pump();
    await gesture.up();
    await settle(tester);
  }

  testWidgets('pins at once, archives and deletes with an Undo that puts the note back where it was', (tester) async {
    final it = seeded();
    final opened = <String>[];
    await pumpHome(tester, LibraryHome(library: it.library, workspaces: it.workspaces, onOpen: opened.add, onAllNotes: () {}, clock: () => 1790586000000));
    await settle(tester);

    await swipe(tester, 'card-flat', 110);
    expect(it.library.noteOf('flat')!.starred, isTrue);

    await swipe(tester, 'card-standup', -110);
    expect(it.library.noteOf('standup')!.archivedAt, isNotNull);
    expect(find.text('Archived “Monday standup”.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(it.library.noteOf('standup')!.archivedAt, isNull);

    // Deleted: gone from the library and from its workspace, until Undo.
    expect(it.workspaces.workspaceOf('prd11')?.name, 'Work');
    await swipe(tester, 'card-prd11', -240);
    expect(it.library.noteOf('prd11'), isNull);
    expect(it.workspaces.workspaceOf('prd11'), isNull);
    expect(find.text('Moved “Fix the sign-in loop” to the Trash.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(it.library.noteOf('prd11'), isNotNull);
    expect(it.workspaces.workspaceOf('prd11')?.name, 'Work');
    await away(tester);
  });

  testWidgets('its + makes a note, files it in the workspace the page is in, and opens it', (tester) async {
    final it = seeded();
    it.workspaces.chooseWorkspace('home');
    final opened = <String>[];
    await pumpHome(tester, LibraryHome(library: it.library, workspaces: it.workspaces, onOpen: opened.add, onAllNotes: () {}));
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Write a note'));
    await settle(tester);
    expect(opened.length, 1);
    expect(it.library.noteOf(opened.single)!.body, '');
    expect(it.workspaces.workspaceOf(opened.single)?.name, 'Home');
    expect(it.library.value.length, 21);
    await away(tester);
  });
}
