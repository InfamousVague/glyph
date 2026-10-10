// A new note's blank page in the app put together: the names it can be given, the template cards and the ghost are
// a block INSIDE the editor, after its first line (docs/PARITY.md, Differs 22). Ghost.md's editor/nameChips.ts draws
// them as a block decoration at the end of line 1 (`Decoration.widget({ block: true, side: 1 }).range(line.to)`),
// so a second line made on the blank page is under the names and cards, not over them.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/items/blank_offers.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/notes/new_sheet.dart';
import 'package:ghost_md/notes/template_cards.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('the names and cards are a block after line 1 in the editor: a second line is under them, and they go at the first word', (tester) async {
    await pumpApp(
      tester,
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: SampleLibrary.seeded(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.widget<NewSheet>(find.byType(NewSheet)).onNote();
    await settle(tester);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    final view = screen.view!;
    expect(blankOffersShown(view.state), isFalse, reason: 'a phone: not until the keyboard is up');
    // The keyboard comes up: the page is ready for words.
    tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
    await settle(tester, 2);
    expect(screen.offersShown, isTrue);
    expect(blankOffersShown(view.state), isTrue, reason: 'the editor draws the block');
    final chip = find.byKey(const ValueKey('name-day'));
    final first = view.coordsAtPos(0)!;
    final names = tester.getRect(chip);
    // `.cm-blankOffers { padding-block-start: 0.75rem }` under line 1.
    expect(names.top, greaterThan(first.bottom));
    expect(names.top - first.bottom, lessThan(24));
    expect(find.byType(TemplateCards), findsOneWidget);

    // Enter on the blank page: the new line is under the names and the cards, and the names have not moved.
    view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: '\n'), selection: EditorSelection.single(1)));
    await settle(tester, 2);
    expect(screen.offersShown, isTrue, reason: 'still no words');
    expect(tester.getRect(chip).top, closeTo(names.top, 0.5), reason: 'the block is after line 1, wherever the note ends');
    final second = view.coordsAtPos(1);
    final cards = tester.getRect(find.byType(TemplateCards));
    expect(second == null || second.top >= cards.bottom, isTrue, reason: 'line 2 is under the block: $second against $cards');

    // A word in line 1 and the block is gone, whatever the screen offers.
    view.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'W')));
    await settle(tester, 2);
    expect(blankOffersShown(view.state), isFalse);
    expect(chip, findsNothing);
    expect(find.byType(TemplateCards), findsNothing);

    tester.view.resetViewInsets();
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  });

  test('the block is after the first line under the front matter, and only while that line has no words', () {
    EditorState offered(String doc) {
      final state = EditorState.create(doc: doc, extensions: blankOffers((context) => const SizedBox()));
      return state.update(TransactionSpec(effects: setBlankOffers.of(true))).state;
    }

    expect(blankOffersShown(EditorState.create(doc: '', extensions: blankOffers((context) => const SizedBox()))), isFalse, reason: 'not until the screen offers');
    expect(blankOffersShown(offered('')), isTrue);
    expect(blankOffersShown(offered('\n\n')), isTrue);
    expect(blankOffersShown(offered('words')), isFalse);
    expect(blankOffersShown(offered('\nwords under an empty first line')), isTrue);
    // A note that begins with front matter: its first line is the one after the fence.
    expect(blankOffersShown(offered('---\nlocation: 1,2\n---\n')), isTrue);
    expect(blankOffersShown(offered('---\nlocation: 1,2\n---\nwords')), isFalse);
    expect(blankOffersShown(offered('---\nlocation: 1,2\n---')), isFalse, reason: 'no line after the fence to stand under');
    // The words arriving take it away, and their going brings it back, with nothing told again.
    final typed = offered('').update(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'W')));
    expect(blankOffersShown(typed.state), isFalse);
    expect(blankOffersShown(typed.state.update(TransactionSpec(changes: const ChangeSpec(from: 0, to: 1))).state), isTrue);
    expect(blankOffered(typed.state), isTrue);
  });
}
