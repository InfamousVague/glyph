import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/journal.dart' show defaultTemplate, entryPlaceOf, placeSentence, templateOf, templateSentence;
import 'package:ghost_md/book/template_picker.dart' show TemplatePicker;
import 'package:ghost_md/core/book.dart' show guideTitle, isJournalBody;
import 'package:ghost_md/core/front_matter.dart' show frontMatterValue;
import 'package:ghost_md/art/art.dart';
import 'package:ghost_md/core/geotag.dart';
import 'package:ghost_md/core/look.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/untouched.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:ghost_md/note/note_place.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/note/note_settings.dart';
import 'package:ghost_md/note/note_tools.dart';
import 'package:ghost_md/note/pinch_zoom.dart';
import 'package:ghost_md/note/version_history.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/shell/screen.dart';
import 'package:ghost_md/shell/top_bar_tools.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'support.dart';

/// A note's screen, case for case with the web's `editor/NoteScreen.test.tsx` where the case is about something this
/// screen draws or does (the others are listed, with why, in the piece's report). "Typing" is a change dispatched to
/// the editor's view, as CodeMirror's own input is.
void main() {
  setUpAll(loadAppFonts);

  void type(NoteScreenState screen, String text, {int? at}) {
    final view = screen.view!;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: at ?? view.state.doc.length, insert: text), userEvent: 'input.type'));
  }

  String doc(NoteScreenState screen) => screen.view!.state.doc.toString();
  void undoIn(NoteScreenState screen) => undo(StateCommandTarget(screen.view!.state, (tr) => screen.view!.dispatch(tr)));
  List<String> saves(NoteWorld world) => [
        for (final sent in world.core.sent)
          if (sent.command == 'update_note') sent.args['body']! as String,
      ];
  List<String> labels(WidgetTester tester) => [for (final tool in tester.widgetList<NoteToolButton>(find.byType(NoteToolButton))) tool.label];

  // A new id for every note: the saving keeps each note's last writes by its id for the next screen on it to wait
  // on (lib/core/library.dart), and a write left unanswered when one test's clock stops would hold up the next's.
  var made = 0;
  late String n;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body, {String? id}) async {
    final note = (await tester.runAsync(() => seedNote(world, id ?? 'n${made += 1}', body)))!;
    if (id == null) n = note.id;
    return note;
  }

  Future<void> more(WidgetTester tester) async {
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> press(WidgetTester tester, String row) async {
    await tester.ensureVisible(find.text(row));
    await tester.pump();
    await tester.tap(find.text(row));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  group('saving what is typed', () {
    testWidgets('saves once, 400 ms after the last keystroke, with every keystroke in it', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Day\n'));
      type(screen, 'o');
      await tester.pump(const Duration(milliseconds: 200));
      type(screen, 'n');
      await tester.pump(const Duration(milliseconds: 399));
      expect(saves(world), isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      await tester.pump();
      expect(saves(world), ['# Day\non']);
      await closeNote(tester);
      expect(saves(world), ['# Day\non'], reason: 'the waiting save does not save again');
    });

    testWidgets('saves what is waiting when the screen is taken down, and nothing when nothing was typed', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Day\n'));
      await closeNote(tester);
      expect(saves(world), isEmpty);
      final again = await pumpNote(tester, world, (await tester.runAsync<Note?>(() => world.library.get(n)))!);
      expect(again, isNot(same(screen)));
      type(again, 'left');
      await closeNote(tester);
      expect(saves(world), ['# Day\nleft']);
    });

    testWidgets('carries the revision each save came back with into the next', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, 'a'));
      type(screen, 'b');
      await tester.pump(const Duration(milliseconds: 450));
      type(screen, 'c');
      await tester.pump(const Duration(milliseconds: 450));
      final revisions = [
        for (final sent in world.core.sent)
          if (sent.command == 'update_note') sent.args['expectedRevision'],
      ];
      expect(saves(world), ['ab', 'abc']);
      expect(revisions[1], isNot(revisions[0]));
      expect(screen.saveStopped, isFalse);
      await closeNote(tester);
    });

    testWidgets('stops saving after a write is refused, rather than writing over the note that won, and says so on the note', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Mine\n'));
      // Another writer's words, under the open note: not a transcript, so nothing to rebase over.
      world.core.writeBehind(n, '# Theirs\n\nTheir words.\n');
      type(screen, 'x');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(screen.saveStopped, isTrue);
      expect(find.text(saveStoppedWords), findsOneWidget);
      final before = world.core.asked('update_note');
      type(screen, 'y');
      await tester.pump(const Duration(milliseconds: 600));
      expect(world.core.asked('update_note'), before, reason: 'nothing more is written from here');
      await closeNote(tester);
    });

    testWidgets('opens on the words the store has when the copy it was given is older', (tester) async {
      final world = NoteWorld();
      final old = await seeded(tester, world, '# Old\n');
      world.core.writeBehind(old.id, '# Newer\n');
      final screen = await pumpNote(tester, world, old);
      await tester.pump(const Duration(milliseconds: 100));
      expect(doc(screen), '# Newer\n');
      expect(screen.title, 'Newer');
      await closeNote(tester);
      expect(saves(world), isEmpty, reason: 'words taken from the store are not a change to save');
    });

    testWidgets('saves before the back gesture leaves, before talking into the note, and before it is archived', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, 'a'), speak: true);
      type(screen, 'b');
      screen.leave();
      await tester.pump();
      expect(saves(world), ['ab']);
      expect(world.asked, ['back']);
      type(screen, 'c');
      await more(tester);
      await press(tester, 'Talk into this note');
      expect(saves(world).last, 'abc');
      expect(world.asked.last, 'speak $n');
      type(screen, 'd');
      await more(tester);
      await press(tester, 'Archive');
      expect(saves(world).last, 'abcd');
      expect(world.asked.last, 'archive $n');
      expect(find.byType(NoteSettings), findsNothing, reason: 'the sheet closes');
      await closeNote(tester);
    });

    testWidgets('saves before a pin, and pins and unpins from its own record of the note', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, 'a'));
      type(screen, 'b');
      screen.togglePin();
      await tester.pump();
      expect(saves(world), ['ab']);
      // The app is handed the note as it stood, to toggle: unpinned, then pinned.
      screen.togglePin();
      await tester.pump();
      expect(world.asked, ['pin $n false', 'pin $n true']);
      await more(tester);
      expect(find.text('Pin to the top'), findsOneWidget);
      await closeNote(tester);
    });

    testWidgets('a note in the Trash is read and not written', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Thrown\n'), readOnly: true, speak: true);
      expect(screen.view!.state.readOnly, isTrue);
      // Its tools are the view switch and More: nothing pins, archives or talks into a note in the Trash.
      expect(labels(tester), ['Showing the marks. Show the formatted note.', 'More for this note']);
      screen.view!.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: 'x')));
      await tester.pump(const Duration(seconds: 1));
      await closeNote(tester);
      expect(saves(world), isEmpty);
    });
  });

  group("the note's tools", () {
    testWidgets('are the view switch and More, with nothing brought out that has no way to be done', (tester) async {
      final world = NoteWorld();
      await pumpNote(tester, world, await seeded(tester, world, '# Day\n'));
      expect(labels(tester), ['Version history', 'Pin to the top', 'Archive', 'Showing the marks. Show the formatted note.', 'More for this note']);
      await closeNote(tester);
    });

    testWidgets('are drawn in the top bar when it offers a place, and in the note’s own header when there is none', (tester) async {
      final world = NoteWorld();
      final note = await seeded(tester, world, '# Day\n');
      await pumpNote(tester, world, note);
      // In the bar: the buttons are under the bar's slot, not under the screen.
      expect(find.descendant(of: find.byType(NoteScreen), matching: find.byType(NoteToolButton)), findsNothing);
      expect(find.byType(NoteMore), findsOneWidget);
      await closeNote(tester);
      await pumpNote(tester, world, note, bar: false);
      expect(TopBarTools.maybeOf(tester.element(find.byType(NoteScreen))), isNull);
      expect(find.descendant(of: find.byType(NoteScreen), matching: find.byType(NoteToolButton)), findsWidgets);
      expect(labels(tester).last, 'More for this note');
      await closeNote(tester);
    });

    testWidgets('switch between the two views from the header, for a note of words, a canvas and a book', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Day\n'));
      await tester.tap(find.bySemanticsLabel('Showing the marks. Show the formatted note.'));
      await tester.pump();
      await tester.pump();
      expect(world.prefs.value.noteView, 'formatted');
      expect(find.bySemanticsLabel('Showing the formatted note. Show the marks.'), findsOneWidget);
      expect(screen.view!.state.facet(formattedView), isTrue);
      await closeNote(tester);

      const canvas = '---\ntitle: "Plan"\n---\n{"nodes":[{"id":"a","type":"text","text":"hi","x":0,"y":0,"width":100,"height":50}],"edges":[]}';
      // The three views that take the page are the app's to give (lib/root/note_desk.dart): handed the body.
      Widget Function(BuildContext, String, ValueChanged<String>) drawn(String what) => (context, body, onChange) => SizedBox(height: 40, child: Text('$what of ${body.length}'));
      // A notebook's view is a sliver of the page, where the other two are boxes.
      final views = NoteSeams(canvas: drawn('canvas'), book: (context, body, onChange) => SliverToBoxAdapter(child: drawn('notebook')(context, body, onChange)), journal: drawn('journal'));
      await pumpNote(tester, world, await seeded(tester, world, canvas), seams: views);
      expect(find.text('canvas of ${canvas.length}'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Showing the canvas. Show its JSON.'));
      await tester.pump();
      await tester.pump();
      expect(find.text('canvas of ${canvas.length}'), findsNothing);
      expect(find.bySemanticsLabel('Showing the canvas as JSON. Show the canvas.'), findsOneWidget);
      expect(world.prefs.value.noteView, 'formatted', reason: 'a canvas has its own switch, not the preference every note shares');
      await closeNote(tester);

      await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\ntitle: "Guide"\n---\n- [[One]]\n'), seams: views);
      expect(find.textContaining('notebook of '), findsOneWidget);
      expect(find.bySemanticsLabel('Showing the index. Show its Markdown.'), findsOneWidget);
      await closeNote(tester);

      await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\njournal: true\ntitle: "Days"\n---\n- [[One]]\n'), seams: views);
      expect(find.textContaining('journal of '), findsOneWidget);
      await closeNote(tester);

      // Not given, nothing is drawn in their place.
      await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\ntitle: "Bare"\n---\n- [[One]]\n'));
      expect(find.textContaining('notebook of '), findsNothing);
      await closeNote(tester);
    });

    test('bring out as many of the spare ones as the row has room for, first first', () {
      // The page at 390: three rings and three gaps of room beside the switch (33.02 wide, 4.46 apart).
      expect(toolsThatFit(room: 4 + 33.02 + 3 * 37.48 + 0.01, always: 1, spare: 7, ring: 33.02, gap: 4.46), 3);
      expect(toolsThatFit(room: 4 + 33.02 + 3 * 37.48 - 0.1, always: 1, spare: 7, ring: 33.02, gap: 4.46), 2);
      expect(toolsThatFit(room: 2000, always: 2, spare: 7, ring: 33.02, gap: 4.46), 7);
      expect(toolsThatFit(room: 10, always: 2, spare: 7, ring: 33.02, gap: 4.46), 0);
      expect(toolsThatFit(room: double.infinity, always: 2, spare: 7, ring: 33.02, gap: 4.46), 0);
    });

    test('say what the switch is showing and what a press shows', () {
      expect(viewSwitchWords(NoteKind.words, page: false), (label: 'Showing the marks. Show the formatted note.', title: 'Markdown'));
      expect(viewSwitchWords(NoteKind.canvas, page: true).title, 'Canvas');
      expect(viewSwitchWords(NoteKind.book, page: false).label, 'Showing the index as Markdown. Show the index.');
    });
  });

  group('the More sheet from the note', () {
    testWidgets('makes a board of the list, says how many, and is offered only where there is a list', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Jobs\n\n- [ ] paint\n- [x] sand\n'));
      await more(tester);
      await press(tester, 'Make a board');
      expect(find.byType(NoteSettings), findsNothing);
      expect(doc(screen), contains('```board'));
      expect(world.asked.last, 'say 2 items are now cards, 1 in Done.');
      undoIn(screen);
      expect(doc(screen), '# Jobs\n\n- [ ] paint\n- [x] sand\n', reason: 'one change, so one Undo puts the note back');
      await closeNote(tester);

      await pumpNote(tester, world, await seeded(tester, world, '# Words\n\nNo list here.\n'));
      await more(tester);
      expect(find.text('Make a board'), findsNothing);
      await closeNote(tester);
    });

    testWidgets('keeps a book’s name typed in the More sheet, saved like typing', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\ntitle: "Guide"\n---\n- [[One]]\n'));
      await more(tester);
      expect(find.text('What this notebook is called'), findsNothing, reason: 'the field holds the name');
      // The Name, over the notebook's Ticket key.
      await tester.enterText(find.descendant(of: find.byType(SheetField).first, matching: find.byType(EditableText)), 'Manual');
      await tester.pump(const Duration(milliseconds: 450));
      expect(screen.title, 'Manual');
      expect(saves(world).last, '---\ntitle: "Manual"\nbook: true\n---\n- [[One]]\n');
      await closeNote(tester);
    });

    // Missing 6 (docs/PARITY.md): More › Ticket key (NoteSettings.tsx `TicketKeyField`, NoteScreen.tsx `ticketKey`).
    // Until it was here a notebook made in the port got a key only by typing `key:`, and New ticket stayed out of
    // reach.
    testWidgets('gives a notebook its ticket key from the More sheet: written while what is typed is a key, said why not while it is not, taken off when cleared', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\ntitle: "Manual"\n---\n- [[One]]\n'));
      await more(tester);
      final key = find.descendant(of: find.byType(SheetField).at(1), matching: find.byType(EditableText));
      expect(tester.widget<SheetField>(find.byType(SheetField).at(1)).label, 'Ticket key');
      expect(find.text('Give it a key, and New ticket numbers its tickets, like a Jira project.'), findsOneWidget);
      await tester.enterText(key, 'gho');
      await tester.pump(const Duration(milliseconds: 450));
      expect(frontMatterValue(screen.body, 'key'), 'GHO');
      expect(saves(world).last, contains('key: GHO'));
      expect(find.text('Its tickets are numbered GHO-1, GHO-2 and on. [[GHO-1]] links to the first.'), findsOneWidget);
      // Not a key: said, and the notebook keeps the one it has.
      await tester.enterText(key, '2go');
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('A key starts with a letter, like GHO.'), findsOneWidget);
      expect(frontMatterValue(screen.body, 'key'), 'GHO');
      await tester.enterText(key, 'g');
      await tester.pump();
      expect(find.text('Two letters at least, like GHO.'), findsOneWidget);
      // Cleared: the key is taken off.
      await tester.enterText(key, '');
      await tester.pump(const Duration(milliseconds: 450));
      expect(frontMatterValue(screen.body, 'key'), isNull);
      expect(find.text('Give it a key, and New ticket numbers its tickets, like a Jira project.'), findsOneWidget);
      await closeNote(tester);

      // A journal has no ticket key, nor has a note of words.
      await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\njournal: true\ntitle: "Diary"\n---\n'));
      await more(tester);
      expect(find.byType(SheetField), findsOneWidget);
      await closeNote(tester);
    });

    // Missing 5 (docs/PARITY.md): More › Journal and its page (NoteSettings.tsx `JournalPage`, NoteScreen.tsx
    // `journalRows`): a notebook kept as a journal, what its entries start with, the place switch, and a journal made
    // a notebook again.
    testWidgets('keeps a notebook as a journal from its More sheet, and makes a journal a notebook again; never the Guide', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\ntitle: "Diary"\n---\n- [[One]]\n'));
      await more(tester);
      expect(find.text('New pages start dated, from a template.'), findsOneWidget);
      await press(tester, 'Keep it as a journal');
      // Its page: what entries start with, a draft until it is kept.
      expect(find.byType(TemplatePicker), findsOneWidget);
      expect(find.text('Entries you have written stay as they are.'), findsNothing);
      expect(isJournalBody(screen.body), isFalse);
      await press(tester, 'Make it a journal');
      expect(isJournalBody(screen.body), isTrue);
      expect(templateOf(screen.body), defaultTemplate);
      // New notes are tagged by default, so its entries keep where they were written, and the row says both.
      expect(entryPlaceOf(screen.body), isTrue);
      expect(find.text('${templateSentence(defaultTemplate)} $placeSentence'), findsOneWidget);
      expect(find.text('Keep it as a journal'), findsNothing);
      // A journal has no ticket key.
      expect(find.byType(SheetField), findsOneWidget);

      // The journal's own page: a change is written as it is made, and it can be made a notebook again.
      await press(tester, 'Journal');
      expect(find.text('Entries you have written stay as they are.'), findsOneWidget);
      tester.widget<TemplatePicker>(find.byType(TemplatePicker)).onPlace(false);
      await tester.pump();
      expect(entryPlaceOf(screen.body), isFalse);
      await press(tester, 'Make it a notebook again');
      expect(isJournalBody(screen.body), isFalse);
      expect((frontMatterValue(screen.body, 'template'), frontMatterValue(screen.body, 'entry-place')), (null, null));
      expect(screen.body, contains('- [[One]]'), reason: 'its entries stay as pages');
      expect(find.text('Keep it as a journal'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 450));
      await closeNote(tester);

      // The Guide is a manual, not a diary: neither row, nor a ticket key.
      await pumpNote(tester, world, await seeded(tester, world, '---\nbook: true\ntitle: "$guideTitle"\n---\n- [[One]]\n'));
      await more(tester);
      expect(find.text('Keep it as a journal'), findsNothing);
      expect(find.byType(SheetField), findsOneWidget);
      await closeNote(tester);
    });

    // Missing 7 (docs/PARITY.md): More › AI › Fill the blanks, with its count and who is asked, and the dot on the
    // run that is on (NoteSettings.tsx `fillHint`, `aria-pressed={running === words.id}` and `.chosen`).
    testWidgets('offers Fill the blanks in a note that has one, with how many and that nothing leaves; and marks the run that is on', (tester) async {
      final world = NoteWorld();
      String? running;
      final seams = NoteSeams(onAi: (view, kind, [instruction]) => world.asked.add('ai $kind'), aiRunning: () => running);
      await pumpNote(tester, world, await seeded(tester, world, '# Packing\n\nThe lens weighs {?how much does a 70-200 f/2.8 weigh} and the body {?how much does a Z8 weigh}.\n'), seams: seams);
      await more(tester);
      SheetRow row(String id) => tester.widget<SheetRow>(find.byKey(ValueKey('ai:$id')));
      expect(find.text('Fill the blanks'), findsOneWidget);
      expect(find.text('Answers the 2 questions written {?like this}. Nothing leaves the phone.'), findsOneWidget);
      expect([for (final id in ['format', 'summarize', 'fill']) row(id).on], [false, false, false]);
      await press(tester, 'Fill the blanks');
      expect(world.asked.last, 'ai fill');
      // A run is on: its row is pressed, with the dot at its end, and no other.
      running = 'summarize';
      await more(tester);
      expect([for (final id in ['format', 'summarize', 'fill']) row(id).on], [false, true, false]);
      await closeNote(tester);

      // No blank in the note, no row.
      await pumpNote(tester, world, await seeded(tester, world, '# Packing\n\nThe lens.\n'), seams: seams);
      await more(tester);
      expect(find.byKey(const ValueKey('ai:summarize')), findsOneWidget);
      expect(find.text('Fill the blanks'), findsNothing);
      await closeNote(tester);
    });

    test('Fill the blanks says how many it answers, and who is asked where some are looked up', () {
      expect(fillHint((count: 1, online: const [])), 'Answers the question written {?like this}. Nothing leaves the phone.');
      expect(fillHint((count: 3, online: const []), platform: TargetPlatform.macOS), 'Answers the 3 questions written {?like this}. Nothing leaves this Mac.');
      expect(fillHint((count: 2, online: const ['Open-Meteo'])), 'Answers the 2 questions written {?like this}. Some are looked up online: only their questions go, to Open-Meteo.');
      expect(
        fillHint((count: 4, online: const ['Wikipedia and Wikidata', 'Open-Meteo', 'Frankfurter'])),
        'Answers the 4 questions written {?like this}. Some are looked up online: only their questions go, to Wikipedia and Wikidata, Open-Meteo and Frankfurter.',
      );
    });

    testWidgets('changes the look as one undo step, Map only for a note with a place, and Plain takes it off', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Read me\n\nWords.\n'));
      await more(tester);
      expect(find.byKey(const ValueKey('look:Map')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('look:Reading')));
      await tester.pump();
      expect(doc(screen), '---\nlook: reading\n---\n# Read me\n\nWords.\n');
      undoIn(screen);
      expect(doc(screen), '# Read me\n\nWords.\n');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('look:Reading')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('look:Plain')));
      await tester.pump();
      expect(doc(screen), '# Read me\n\nWords.\n', reason: 'the key, and the block that held nothing else');
      await closeNote(tester);

      await pumpNote(tester, world, await seeded(tester, world, '---\nlocation: 38.7223,-9.1393\n---\n# There\n'));
      await more(tester);
      expect(find.byKey(const ValueKey('look:Map')), findsOneWidget);
      await closeNote(tester);
    });

    testWidgets('a look chosen makes a note the app gave its words to the person’s own, so it is not taken back', (tester) async {
      final world = NoteWorld();
      final note = await seeded(tester, world, '# Monday\n\n');
      world.untouched.remember(n, const UntouchedRecord(title: 'Monday', words: '# Monday\n\n', at: 1 << 52));
      final screen = await pumpNote(tester, world, note);
      expect(world.untouched.isUntouched(n, screen.body), isTrue);
      screen.chooseLook(Look.reading);
      await tester.pump();
      expect(world.untouched.recordOf(n), isNull);
      await closeNote(tester);
    });

    testWidgets('files the note from its Workspace page, and comes back to the sheet', (tester) async {
      final world = NoteWorld();
      final home = world.workspaces.addWorkspace('Home')!;
      await pumpNote(tester, world, await seeded(tester, world, '# Day\n'));
      await more(tester);
      expect(find.text('Not in one'), findsOneWidget);
      await press(tester, 'Workspace');
      expect(find.text('Notes in a workspace show together on the list. Filed in an organization’s, a note is the team’s.'), findsOneWidget);
      await press(tester, 'Home');
      expect(world.workspaces.workspaceOf(n)?.id, home.id);
      expect(find.text('Where it sits', findRichText: true), findsNothing);
      expect(find.text('WHERE IT SITS'), findsOneWidget, reason: 'back on the sheet, which says where it is filed');
      expect(find.text('Home'), findsOneWidget);
      await closeNote(tester);
    });

    testWidgets('keeps a history from its row, shows the timeline, and puts a version back through the editor', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Draft\n\nFirst words.\n'));
      await more(tester);
      await press(tester, 'Keep version history');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(world.versions.keepsVersions(n), isTrue);
      expect(find.byType(VersionHistory), findsOneWidget);
      expect(find.text('1 VERSION'), findsOneWidget, reason: 'the note as it was when the history began');
      // Written on, and a second version kept by hand, with a name.
      type(screen, 'More.\n');
      await tester.enterText(find.descendant(of: find.byType(SheetField), matching: find.byType(EditableText)), 'Longer');
      await tester.pump();
      await tester.tap(find.text('Save a version now'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(world.asked.last, 'say Version saved.');
      expect(find.text('2 VERSIONS'), findsOneWidget);
      expect(find.text('Longer'), findsOneWidget);
      // The first version opened: what going back to it changes, and Restore.
      await tester.ensureVisible(find.byKey(const ValueKey('version:1')));
      await tester.tap(find.byKey(const ValueKey('version:1')));
      await tester.pump();
      expect(find.text('THE NOTE AS IT BEGAN'), findsOneWidget);
      await press(tester, 'Restore version 1');
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      expect(doc(screen), '# Draft\n\nFirst words.\n');
      expect(world.asked.last, 'say Back to version 1.');
      expect(find.byType(NoteSettings), findsNothing);
      undoIn(screen);
      expect(doc(screen), '# Draft\n\nFirst words.\nMore.\n', reason: 'undone like any other change');
      final kept = (await tester.runAsync(() => world.versions.versionsOf(n)))!.versions;
      expect([for (final version in kept) version.label], [null, 'Longer', 'Back to version 1'], reason: 'the history only grows');
      await closeNote(tester);
    });

    testWidgets('moves to the Trash at once, saved first', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, 'a'));
      type(screen, 'b');
      await more(tester);
      await press(tester, 'Move to Trash');
      expect(saves(world), ['ab']);
      expect(world.asked.last, 'delete $n');
      await closeNote(tester);
    });

    test('says why an untagged note was not tagged, or what a press will do', () {
      NoteLocation location({LocateFailure? cannot, LocateFailure? refused, bool onPhone = true, bool asksName = true}) =>
          NoteLocation(tag: null, cannot: cannot, refused: refused, onPhone: onPhone, asksName: asksName, onAdd: () {}, onRemove: () {});
      expect(locationHint(location()), 'Where you are now, kept in the note. Its name is asked of OpenStreetMap once.');
      expect(locationHint(location(asksName: false)), 'Where you are now, kept in the note.');
      expect(locationHint(location(cannot: LocateFailure.localOnly)), startsWith('Local only is on.'));
      expect(locationHint(location(refused: LocateFailure.refused)), endsWith('Tap to ask again.'));
      expect(locationHint(location(refused: LocateFailure.refused, onPhone: false)), contains('in the browser’s settings'));
      expect(locationHint(location(refused: LocateFailure.blocked)), startsWith('Location is off for Ghost.md, so this note wasn’t tagged.'));
    });
  });

  group('where the note was written', () {
    NoteSeams withMap(List<String> asked) => NoteSeams(mapCard: (context, tag, {required header, required quiet, required arrive, required leave, onLeft}) => Text('map ${tagLabel(tag)}${header ? ' header' : ''}', textDirection: TextDirection.ltr));

    testWidgets('draws the map card at the top of a tagged note, follows a location typed by hand, and not over a canvas', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Here\n'), seams: withMap(world.asked));
      expect(find.textContaining('map '), findsNothing);
      screen.view!.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, insert: '---\nlocation: 38.7223,-9.1393\nplace: "Alfama, Lisbon"\nlook: map\n---\n')));
      await tester.pump();
      await tester.pump();
      expect(find.text('map Alfama, Lisbon header'), findsOneWidget);
      await closeNote(tester);

      const canvas = '---\nlocation: 38.7223,-9.1393\n---\n{"nodes":[{"id":"a","type":"text","text":"hi","x":0,"y":0,"width":100,"height":50}],"edges":[]}';
      await pumpNote(tester, world, await seeded(tester, world, canvas), seams: withMap(world.asked));
      expect(find.textContaining('map '), findsNothing);
      await closeNote(tester);
    });

    testWidgets('keeps the caret with the words when a tag is written above a note that had no front matter', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, 'Words'));
      expect(screen.view!.state.selection.main.head, 0);
      expect(screen.writeTag(const GeoTag(lat: 38.7223, lon: -9.1393)), isTrue);
      const block = '---\nlocation: 38.7223,-9.1393\n---\n';
      expect(doc(screen), '${block}Words');
      expect(screen.view!.state.selection.main.head, block.length, reason: 'at the start of the words, not in front of the new fence');
      undoIn(screen);
      expect(doc(screen), 'Words', reason: 'one undo step');
      await tester.pump(const Duration(milliseconds: 450));
      await closeNote(tester);
    });

    testWidgets('writes a canvas’s tag through the screen’s own saving, since its editor is hidden', (tester) async {
      final world = NoteWorld();
      const canvas = '{"nodes":[{"id":"a","type":"text","text":"hi","x":0,"y":0,"width":100,"height":50}],"edges":[]}';
      final screen = await pumpNote(tester, world, await seeded(tester, world, canvas));
      expect(screen.writeTag(const GeoTag(lat: 1.5, lon: 2.5)), isTrue);
      await tester.pump(const Duration(milliseconds: 450));
      expect(saves(world).last, '---\nlocation: 1.5000,2.5000\n---\n$canvas');
      await closeNote(tester);
    });
  });

  group('a new note’s blank page', () {
    final monday = DateTime(2026, 9, 28, 14, 5);

    testWidgets('has the ghost until the first word', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, world.library.create(''));
      expect(find.byType(Ghost), findsOneWidget);
      type(screen, 'W');
      await tester.pump();
      expect(find.byType(Ghost), findsNothing);
      await tester.pump(const Duration(milliseconds: 450));
      await closeNote(tester);
    });

    testWidgets('offers the four names on a fresh note, the day in words first, and leaves out a name another note has', (tester) async {
      final world = NoteWorld();
      final note = world.library.create('');
      world.untouched.markFresh(note.id);
      final screen = await pumpNote(tester, world, note, clock: () => monday, taken: {'2026 09 28'});
      expect(screen.offering, isTrue);
      expect([for (final offer in screen.names!) offer.name], ['Monday, 28 September 2026', '2026-09-28 14.05', '2026-W40']);
      await closeNote(tester);
    });

    testWidgets('names the note from a tap: its heading, the caret under it, one undo step, a record, and the tab says it', (tester) async {
      final world = NoteWorld();
      final note = world.library.create('');
      world.untouched.markFresh(note.id);
      final screen = await pumpNote(tester, world, note, clock: () => monday);
      screen.nameIt('2026-09-28');
      await tester.pump();
      expect(doc(screen), '# 2026-09-28\n\n');
      expect(screen.view!.state.selection.main.head, '# 2026-09-28\n\n'.length);
      expect(screen.title, '2026-09-28');
      expect(find.text('2026-09-28'), findsOneWidget, reason: 'the tab');
      expect(world.untouched.recordOf(note.id)?.title, '2026-09-28');
      expect(world.untouched.isUntouched(note.id, screen.body), isTrue);
      expect(screen.offering, isFalse, reason: 'it has words now');
      undoIn(screen);
      await tester.pump();
      expect(doc(screen), '');
      expect(screen.offering, isTrue, reason: 'back to a blank page with the names on it');
      await tester.pump(const Duration(milliseconds: 450));
      await closeNote(tester);
    });

    testWidgets('goes at the first letter, and a fresh note typed in and emptied never offers them again', (tester) async {
      final world = NoteWorld();
      final note = world.library.create('');
      world.untouched.markFresh(note.id);
      final screen = await pumpNote(tester, world, note);
      type(screen, 'W');
      await tester.pump();
      expect(screen.offering, isFalse);
      screen.view!.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, to: 1, insert: '')));
      await tester.pump();
      expect(doc(screen), '');
      expect(screen.offering, isFalse);
      expect(screen.names, isNull);
      // And a chip pressed after its first letter names nothing.
      type(screen, 'W');
      screen.nameIt('2026-09-28');
      expect(doc(screen), 'W');
      await tester.pump(const Duration(milliseconds: 450));
      await closeNote(tester);
    });

    testWidgets('never offers a name on an old note emptied by hand, so nothing can take it away', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, 'Old words'));
      screen.view!.dispatch(TransactionSpec(changes: const ChangeSpec(from: 0, to: 9, insert: '')));
      await tester.pump();
      expect(screen.offering, isFalse);
      await tester.pump(const Duration(milliseconds: 450));
      await closeNote(tester);
    });

    testWidgets('follows a named note’s words from then on: typed in, its record goes', (tester) async {
      final world = NoteWorld();
      final note = world.library.create('');
      world.untouched.markFresh(note.id);
      final screen = await pumpNote(tester, world, note);
      screen.nameIt('Plans');
      await tester.pump();
      type(screen, 'mine');
      await tester.pump();
      expect(world.untouched.recordOf(note.id), isNull, reason: 'on the keystroke, not when the save lands');
      await tester.pump(const Duration(milliseconds: 450));
      await closeNote(tester);
    });

    testWidgets('puts the caret where a note just made asked for it', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, '# Entry\n\n**14:05** '), caret: const Caret.end());
      expect(screen.view!.state.selection.main.head, '# Entry\n\n**14:05** '.length);
      await closeNote(tester);
      final read = await pumpNote(tester, world, (await tester.runAsync<Note?>(() => world.library.get(n)))!);
      expect(read.view!.state.selection.main.head, 0, reason: 'a note opened to be read keeps its caret where it was');
      await closeNote(tester);
    });
  });

  group('where the note opens', () {
    final long = [for (var n = 1; n <= 120; n++) 'Line $n of the note.'].join('\n');

    testWidgets('lands on a line a link pointed at: the caret on it, and the page scrolled to put it under the header', (tester) async {
      final world = NoteWorld();
      final screen = await pumpNote(tester, world, await seeded(tester, world, long), at: 'line:80');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 500));
      final view = screen.view!;
      final line = view.state.doc.line(80);
      expect(view.state.selection.main.head, line.to);
      final seen = view.coordsAtPos(line.from)!;
      final header = tester.getRect(find.byType(NoteScreen)).top + tester.element(find.byType(NoteScreen)).tokens.len('app-safe-top');
      expect(seen.top, closeTo(header + 12, 2), reason: 'twelve under the header');
      await closeNote(tester);
      expect(const NotePlaces().readPlace(n), isNull);
      expect(NotePlaces(world.device).readPlace(n), isNull, reason: 'a note opened at an item keeps no place of its own');
    });

    testWidgets('lands on an item by its anchor', (tester) async {
      final world = NoteWorld();
      final body = '$long\n- [ ] Ask Sam ^ask-sam\n$long';
      final screen = await pumpNote(tester, world, await seeded(tester, world, body), at: '^ask-sam');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      final view = screen.view!;
      final line = view.state.doc.line(121);
      expect(line.text, '- [ ] Ask Sam ^ask-sam');
      expect(view.state.selection.main.head, line.from + '- [ ] Ask Sam'.length, reason: 'the end of the item’s words, before its anchor');
      await closeNote(tester);
    });

    testWidgets('remembers where it was left, and opens there again', (tester) async {
      final world = NoteWorld();
      final note = await seeded(tester, world, long);
      final screen = await pumpNote(tester, world, note);
      final scroller = find.descendant(of: find.byType(NoteScreen), matching: find.byType(Scrollable)).first;
      // The person's own scroll.
      await tester.drag(scroller, const Offset(0, -900));
      await tester.pump(const Duration(milliseconds: 500));
      final left = placeOf(screen.view!, tester.state<ScrollableState>(scroller).position)!;
      expect(left.pos, greaterThan(0));
      expect(NotePlaces(world.device).readPlace(n), left, reason: 'written as scrolling settles');
      await closeNote(tester);

      final again = await pumpNote(tester, world, note);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 300));
      final position = tester.state<ScrollableState>(find.descendant(of: find.byType(NoteScreen), matching: find.byType(Scrollable)).first).position;
      expect(position.pixels, greaterThan(100));
      expect(placeOf(again.view!, position), left, reason: 'the same line at the top, as far into it');
      await closeNote(tester);
    });
  });

  group('two fingers', () {
    testWidgets('pinch the text larger, hold the page still, and the size is kept for the next note', (tester) async {
      final world = NoteWorld();
      final note = await seeded(tester, world, '# Title\n\n${[for (var n = 1; n <= 60; n++) 'Line $n.'].join('\n')}');
      final screen = await pumpNote(tester, world, note);
      final before = screen.view!.look!.env.body;
      final one = await tester.startGesture(const Offset(150, 400), kind: PointerDeviceKind.touch);
      final two = await tester.startGesture(const Offset(250, 400), kind: PointerDeviceKind.touch);
      await tester.pump();
      await two.moveTo(const Offset(300, 400));
      await tester.pump();
      await tester.pump();
      expect(screen.view!.look!.env.body, closeTo(before * 1.5, 0.01));
      await one.up();
      await two.up();
      await tester.pump();
      expect(readZoom(world.device), closeTo(1.5, 0.001));
      await closeNote(tester);

      final next = await pumpNote(tester, world, note);
      expect(next.view!.look!.env.body, closeTo(before * 1.5, 0.01));
      await closeNote(tester);
    });
  });
}
