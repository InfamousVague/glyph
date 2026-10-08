import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/render.dart';
import 'support.dart';

/// Pictures of the All notes page over the library the web page was measured over, at the sizes and in the themes
/// its own pictures were taken in (Chromium at 390x844 and 1000x800, at 2), for looking at beside them:
/// `flutter test --no-pub --update-goldens test/allnotes/all_notes_shots_test.dart`, then open
/// `test/allnotes/shots/all-*.png`.
void main() {
  setUpAll(loadAppFonts);

  for (final theme in ['dark', 'light']) {
    testWidgets('the page on a phone, $theme', (tester) async {
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: allNotesWorkspaces(), asked: Asked()), theme: theme);
      await shot(tester, 'all-phone-$theme');
    });

    testWidgets('the page on a wide window, $theme', (tester) async {
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: allNotesWorkspaces(), asked: Asked()), size: const Size(1000, 800), split: true, theme: theme);
      await shot(tester, 'all-wide-$theme');
    });

    testWidgets('a search that found nothing, $theme', (tester) async {
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: allNotesWorkspaces(), asked: Asked()), theme: theme);
      await settle(tester);
      await tester.enterText(find.byType(EditableText), 'zzzz');
      await settle(tester);
      await loadPictures(tester);
      await shot(tester, 'all-phone-nothing-$theme');
    });
  }

  testWidgets('a workspace with nothing in it, on a phone', (tester) async {
    final spaces = allNotesWorkspaces()..chooseWorkspace('spare');
    await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: Asked()));
    await settle(tester);
    await loadPictures(tester);
    await shot(tester, 'all-phone-spare');
  });

  testWidgets('a workspace with nothing in it, wide', (tester) async {
    final spaces = allNotesWorkspaces()..chooseWorkspace('spare');
    await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: Asked()), size: const Size(1000, 800), split: true);
    await settle(tester);
    await loadPictures(tester);
    await shot(tester, 'all-wide-spare');
  });

  testWidgets('the archive shown, a workspace chosen, by name', (tester) async {
    final spaces = allNotesWorkspaces()..chooseWorkspace('work');
    await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: Asked()));
    await settle(tester);
    await tester.tap(find.text('Archived · 1'));
    await tester.tap(find.text('A to Z'));
    await shot(tester, 'all-phone-work-archive');
  });

  testWidgets('with the smoke under the bar, scrolled', (tester) async {
    await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: allNotesWorkspaces(), asked: Asked(), wisp: true));
    await settle(tester);
    tester.state<ScrollableState>(find.descendant(of: find.byKey(const ValueKey('all-notes-scroll')), matching: find.byType(Scrollable)).first).position.jumpTo(260);
    await tester.pump();
    await shot(tester, 'all-phone-scrolled-wisp');
  });

  testWidgets('only the tapes', (tester) async {
    await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: allNotesWorkspaces(), asked: Asked(), tapes: true));
    await shot(tester, 'all-phone-tapes');
  });
}
