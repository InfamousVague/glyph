import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_parts.dart';
import 'package:ghost_md/home/note_card.dart';
import 'package:ghost_md/notes/workspace_bar.dart';
import 'package:ghost_md/sheet/sheet.dart';

import '../core/make_note.dart';
import '../support/render.dart';
import 'support.dart';

/// The All notes page (lib/notes/all_notes_screen.dart): what it does, case for case with the web's
/// `notes/AllNotesScreen.test.tsx`, and where things stand, held to what the web page measured.
///
/// The numbers are `getBoundingClientRect`s read from the web app's dev server in Chromium (the Fold's own engine),
/// dark, over the library in support.dart at the same moment: 390x844 for a phone and 1000x800 for a wide window,
/// both with a finger's pointer. WebKit differs in one place, said in the screen's own doc: its order words are 23px
/// tall, not 20, and everything under them 3px or 6px further down.
void main() {
  setUpAll(loadAppFonts);

  Finder key(String name) => find.byKey(ValueKey(name));

  /// A mark said to a screen reader by that name: a card's pin, its archive, an organization's.
  Finder said(String label) => find.byWidgetPredicate((widget) => widget is Semantics && widget.properties.label == label);

  /// Whether [rect] is where the web page had it, to half a pixel each way.
  void at(Rect rect, double left, double top, double width, double height, {double within = 0.5, String? reason}) {
    expect(rect.left, closeTo(left, within), reason: '${reason ?? ''} left');
    expect(rect.top, closeTo(top, within), reason: '${reason ?? ''} top');
    expect(rect.width, closeTo(width, within), reason: '${reason ?? ''} width');
    expect(rect.height, closeTo(height, within), reason: '${reason ?? ''} height');
  }

  List<String> cards(WidgetTester tester) => [for (final card in tester.widgetList<NoteCard>(find.byType(NoteCard))) card.note.id];

  Future<void> show(WidgetTester tester, List<Note> notes, {Asked? asked, bool tapes = false, Stored? stored, bool spaces = false, Size size = const Size(390, 844), bool split = false}) async {
    await pumpAllNotes(tester, AllNotes(notes: notes, workspaces: allNotesWorkspaces(any: spaces), asked: asked ?? Asked(), tapes: tapes, stored: stored), size: size, split: split);
    await settle(tester);
  }

  Future<void> type(WidgetTester tester, String words) async {
    await tester.enterText(find.byType(EditableText), words);
    await settle(tester);
  }

  group('the page', () {
    testWidgets('draws every note as a card, the last touched first, and opens the one tapped', (tester) async {
      final asked = Asked();
      await show(tester, [makeNote('a', body: '# Apples', updatedAt: 1), makeNote('b', body: '# Bread', updatedAt: 2), makeNote('c', body: '', updatedAt: 3)], asked: asked);
      expect(cards(tester), ['c', 'b', 'a']);
      expect(find.text('Untitled'), findsOneWidget);
      expect(find.text('3 notes'), findsOneWidget);
      // Drawn dense: each card is the grid's smaller one.
      expect(tester.widgetList<NoteCard>(find.byType(NoteCard)).every((card) => card.dense), isTrue);
      await tester.tap(key('card-c'));
      expect(asked.said, ['open c']);
      await away(tester);
    });

    testWidgets('narrows to the words typed, and says when nothing has them', (tester) async {
      await show(tester, [makeNote('a', body: '# Apples\n\nfor the pie', updatedAt: 3), makeNote('b', body: '# Bread', updatedAt: 2), makeNote('c', body: '# Cake\n\napples in it', updatedAt: 1)]);
      await type(tester, 'apples');
      expect(cards(tester), ['a', 'c']);
      expect(find.text('2 of 3'), findsOneWidget);
      await type(tester, 'apples pie');
      expect(cards(tester), ['a']);
      await type(tester, 'kettle');
      expect(cards(tester), isEmpty);
      expect(find.text('Nothing has “kettle”.'), findsOneWidget);
      expect(find.text('Try fewer words.'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Clear the search'));
      await settle(tester);
      expect(tester.widget<EditableText>(find.byType(EditableText)).controller.text, '');
      expect(cards(tester).length, 3);
      // The field keeps the keyboard, as the page's does.
      expect(tester.widget<EditableText>(find.byType(EditableText)).focusNode.hasFocus, isTrue);
      await away(tester);
    });

    testWidgets('orders by name when asked, and remembers the choice', (tester) async {
      final kept = MemoryStored();
      await show(tester, [makeNote('a', body: '# pear', updatedAt: 3), makeNote('b', body: '# Apple', updatedAt: 2), makeNote('c', body: '# Mango', updatedAt: 1)], stored: kept);
      expect(cards(tester), ['a', 'b', 'c']);
      await tester.tap(find.text('A to Z'));
      await settle(tester);
      expect(cards(tester), ['b', 'c', 'a']);
      expect(kept.getItem('glyph-all-notes-sort'), 'title');
      await away(tester);
      // Opened again, it is in the order it was left in.
      await show(tester, [makeNote('a', body: '# pear', updatedAt: 3), makeNote('b', body: '# Apple', updatedAt: 2)], stored: kept);
      expect(cards(tester), ['b', 'a']);
      await away(tester);
    });

    testWidgets('keeps the archive out until its word is pressed, then marks each archived card', (tester) async {
      await show(tester, [makeNote('a', body: '# Kept', updatedAt: 2), makeNote('b', body: '# Gone', updatedAt: 1, archivedAt: 5)]);
      expect(cards(tester), ['a']);
      expect(said('Archived'), findsNothing);
      await tester.tap(find.text('Archived · 1'));
      await settle(tester);
      expect(cards(tester), ['a', 'b']);
      expect(find.text('2 notes'), findsOneWidget);
      expect(said('Archived'), findsOneWidget);
      await away(tester);
    });

    testWidgets('shows only the notes with a tape while its Tapes word is on, typed ones included, and opens with it on when asked', (tester) async {
      final notes = [
        makeNote('s', body: '# Spoken', source: NoteSource.capture, recordingMs: 40000, updatedAt: 3),
        makeNote('t', body: '# Typed then spoken', recordingMs: 12000, updatedAt: 2),
        makeNote('p', body: '# Plain', updatedAt: 1),
      ];
      await show(tester, notes);
      expect(cards(tester), ['s', 't', 'p']);
      await tester.tap(find.text('Tapes · 2'));
      await settle(tester);
      expect(cards(tester), ['s', 't']);
      expect(find.text('2 notes'), findsOneWidget);
      await type(tester, 'typed');
      expect(find.text('1 of 2'), findsOneWidget);
      await away(tester);
      // From the home page's Tapes heading, its "See all": the page opens with the word already on.
      await show(tester, notes, tapes: true);
      expect(cards(tester), ['s', 't']);
      await away(tester);
      // No Tapes word at all where nothing has a recording, and no Archived word with nothing archived.
      await show(tester, [makeNote('p', body: '# Plain')]);
      expect(key('tapes-word'), findsNothing);
      expect(key('archive-word'), findsNothing);
      await away(tester);
    });

    testWidgets('marks a pinned card, and draws a book as its index', (tester) async {
      await show(tester, [makeNote('p', body: '# Packing', starred: true), makeNote('b', body: bookNoteBody('Trip', ['Packing', 'Route']))]);
      expect(said('Pinned'), findsOneWidget);
      expect(find.text('2 pages'), findsOneWidget);
      await away(tester);
    });

    testWidgets('goes home from its arrow, and says a blank page with nothing in it', (tester) async {
      final asked = Asked();
      await show(tester, const [], asked: asked);
      expect(find.text('A blank page.'), findsOneWidget);
      expect(find.text('Write it, or tap Speak and say it.'), findsOneWidget);
      expect(find.text('0 notes'), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Back to home'));
      expect(asked.said, ['back']);
      await away(tester);
    });

    testWidgets('hints at what this device can do: the side key, Speak, or the + alone', (tester) async {
      for (final (sideKey, speaks, hint) in [(true, true, 'Write it, or hold the side key and say it.'), (false, true, 'Write it, or tap Speak and say it.'), (false, false, 'Tap + to write it.')]) {
        await pumpAllNotes(tester, AllNotes(notes: const [], workspaces: allNotesWorkspaces(any: false), asked: Asked(), sideKey: sideKey, speaks: speaks));
        await settle(tester);
        expect(find.text(hint), findsOneWidget);
        await away(tester);
      }
    });

    testWidgets('says nothing of an empty library while the notes are still being read', (tester) async {
      await pumpAllNotes(tester, AllNotes(notes: const [], workspaces: allNotesWorkspaces(any: false), asked: Asked(), loading: true));
      await settle(tester);
      expect(find.text('A blank page.'), findsNothing);
      await away(tester);
    });
  });

  group('the workspaces', () {
    testWidgets('choose which notes, a tap on the one chosen opens its sheet, and the + a new one', (tester) async {
      final spaces = allNotesWorkspaces();
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: Asked()));
      await settle(tester);
      expect(find.text('19 notes'), findsOneWidget);
      await tester.tap(key('space-work'));
      await settle(tester);
      expect(spaces.value.current?.id, 'work');
      expect(find.text('9 notes'), findsOneWidget);
      expect(cards(tester).take(3), ['prd11', 'standup', 'open-tickets']);
      // Its own archive and tapes: the launch post is filed under Work, and both tapes.
      expect(find.text('Archived · 1'), findsOneWidget);
      expect(find.text('Tapes · 2'), findsOneWidget);
      // The one already chosen: its sheet, to rename or remove.
      await tester.tap(key('space-work'));
      await settle(tester);
      expect(find.byType(Sheet), findsOneWidget);
      expect(find.text('Work'), findsWidgets);
      await tester.pageBack().catchError((Object _) {});
      await away(tester);

      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: allNotesWorkspaces(), asked: Asked()));
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('New workspace'));
      await settle(tester);
      expect(find.byType(Sheet), findsOneWidget);
      expect(find.text('New workspace'), findsWidgets);
      await away(tester);
    });

    testWidgets('say so of one with nothing in it, and are not drawn at all where there are none', (tester) async {
      final spaces = allNotesWorkspaces()..chooseWorkspace('spare');
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: Asked()));
      await settle(tester);
      expect(find.text('Nothing in Spare yet.'), findsOneWidget);
      expect(find.text('0 notes'), findsOneWidget);
      await away(tester);
      await show(tester, allNotesLibrary());
      expect(find.byType(WorkspaceBar), findsNothing);
      await away(tester);
    });

    testWidgets('an organization’s is opened by a second tap, and wears its mark', (tester) async {
      final asked = Asked();
      final spaces = allNotesWorkspaces()..ensureOrgWorkspace(const OrgLike(id: 'acme', name: 'Acme', hue: 'violet'));
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: asked));
      await settle(tester);
      expect(said('Organization'), findsOneWidget);
      await tester.tap(find.text('Acme'));
      await settle(tester);
      expect(spaces.value.current?.name, 'Acme');
      await tester.tap(find.text('Acme'));
      await settle(tester);
      expect(asked.said, ['organization acme']);
      expect(find.byType(Sheet), findsNothing);
      await away(tester);
    });
  });

  group('a note’s menu and the pull', () {
    testWidgets('is asked for by a mouse’s right-click and by a long press, for the card it was on', (tester) async {
      final asked = Asked();
      await show(tester, [makeNote('a', body: '# Apples', updatedAt: 2), makeNote('b', body: '# Bread', updatedAt: 1)], asked: asked);
      final mouse = await tester.startGesture(tester.getCenter(key('card-b')), kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.up();
      await tester.pump();
      expect(asked.said, ['menu b']);
      await tester.longPress(key('card-a'));
      await tester.pump();
      expect(asked.said, ['menu b', 'menu a']);
      await away(tester);
    });

    testWidgets('a pull down from the top asks for a refresh', (tester) async {
      final asked = Asked();
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: allNotesWorkspaces(), asked: asked, refresh: true));
      await settle(tester);
      final finger = await tester.startGesture(const Offset(195, 300));
      for (var i = 0; i < 12; i += 1) {
        await finger.moveBy(const Offset(0, 20));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await finger.up();
      await tester.pump(const Duration(milliseconds: 100));
      expect(asked.said, ['refresh']);
      await tester.pump(const Duration(seconds: 2));
      await away(tester);
    });
  });

  group('another workspace, order, archive or tapes glides the page back to its top', () {
    testWidgets('from where it was, holding its place while the shorter list is laid out', (tester) async {
      final spaces = allNotesWorkspaces();
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: Asked()));
      await settle(tester);
      final position = tester.state<ScrollableState>(find.descendant(of: key('all-notes-scroll'), matching: find.byType(Scrollable)).first).position;
      position.jumpTo(900);
      await tester.pump();
      // Home: three cards, far too short a page to be 900 down. It holds, then glides.
      spaces.chooseWorkspace('home');
      await tester.pump();
      // The tally is above the window while the page is held where it was: there, and not on the screen.
      expect(find.text('3 notes', skipOffstage: false), findsOneWidget);
      expect(position.pixels, closeTo(900, 1), reason: 'held where it was for the first frame');
      // The glide's clock starts at its first frame.
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 200));
      expect(position.pixels, inExclusiveRange(0, 900));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(position.pixels, 0);
      // The room it borrowed is given back: the page is as long as its three cards again.
      expect(position.maxScrollExtent, lessThan(200));
      await away(tester);
    });
  });

  group('where things stand on a phone (Chromium, 390x844, dark)', () {
    testWidgets('the bar, the pills, the line of words and the first card', (tester) async {
      await show(tester, allNotesLibrary(), spaces: true);
      // The bar: the arrow a gutter less a space in, the search to the other gutter, both under the tab bar's room.
      at(tester.getRect(key('all-notes-back')), 13.39, 56.34, 35.7, 35.7, reason: 'back');
      at(tester.getRect(key('all-notes-search')), 58.02, 55.34, 309.67, 37.7, reason: 'search');
      at(tester.getRect(key('all-notes-search-mark')), 72.41, 66.19, 16, 16, reason: 'its mark');
      at(tester.getRect(key('all-notes-field')), 97.33, 56.34, 264.91, 35.7, reason: 'the field');
      expect(tester.getRect(key('all-notes-bar')).bottom, closeTo(101.97, 0.5), reason: 'the bar is 101.97 tall');
      // The pills, out to the window's edges, each an even ring round its word.
      at(tester.getRect(key('workspace-bar')), 0, 119.84, 390, 36, reason: 'the row');
      at(tester.getRect(find.ancestor(of: find.text('All'), matching: find.byType(Container)).first), 22.31, 121.84, 34.31, 32, reason: 'All');
      at(tester.getRect(key('space-work')), 65.55, 121.84, 51.78, 32, reason: 'Work');
      at(tester.getRect(key('space-home')), 126.25, 121.84, 55.88, 32, reason: 'Home');
      at(tester.getRect(key('space-spare')), 191.05, 121.84, 55.52, 32, reason: 'Spare');
      at(tester.getRect(key('space-add')), 255.48, 121.84, 32, 32, reason: '+');
      // The line of words wraps on a phone: the order and Tapes, then the tally and Archived together.
      at(tester.getRect(key('all-notes-controls')), 22.31, 178.16, 345.38, 44.45, reason: 'controls');
      at(tester.getRect(key('sort-newest')), 22.31, 178.16, 77.06, 20, reason: 'Newest');
      at(tester.getRect(key('sort-title')), 103.83, 178.16, 66.52, 20, reason: 'A to Z');
      at(tester.getRect(key('tapes-word')), 183.73, 178.16, 105.72, 20, reason: 'Tapes');
      at(tester.getRect(find.descendant(of: key('tapes-word'), matching: find.byType(CustomPaint)).first), 198.13, 181.13, 14.06, 14.06, reason: 'the cassette');
      at(tester.getRect(key('all-notes-counts')), 22.31, 202.61, 345.38, 20, reason: 'counts');
      at(tester.getRect(key('all-notes-tally')), 22.31, 204.61, 56.03, 16, reason: 'the tally');
      at(tester.getRect(key('archive-word')), 246.23, 202.61, 121.45, 20, reason: 'Archived');
      // The first card, a space under the line. (Its height is the card's own: see the last group.)
      final first = tester.getRect(key('card-prd11'));
      expect([first.left, first.top, first.width], [closeTo(22.31, 0.5), closeTo(236, 0.5), closeTo(345.38, 0.5)]);
      await away(tester);
    });

    testWidgets('the search with words in it: the x at its end, and the field giving it room', (tester) async {
      await show(tester, allNotesLibrary(), spaces: true);
      await type(tester, 'cabin');
      at(tester.getRect(key('all-notes-field')), 97.33, 56.34, 241.98, 35.7, reason: 'the field');
      at(tester.getRect(key('all-notes-clear')), 348.23, 67.19, 14, 14, reason: 'the x');
      at(tester.getRect(key('all-notes-tally')), 22.31, 204.61, 46.23, 16, reason: '2 of 19');
      expect(find.text('2 of 19'), findsOneWidget);
      expect(cards(tester), ['weekend', 'cabin-canvas']);
      await away(tester);
    });

    testWidgets('with no workspaces, tapes or archive: one line, the tally taking the rest of it', (tester) async {
      await show(tester, [for (final note in allNotesLibrary()) Note(id: note.id, body: note.body, createdAt: note.createdAt, updatedAt: note.updatedAt, starred: note.starred)]);
      at(tester.getRect(key('all-notes-controls')), 22.31, 133.23, 345.38, 20, reason: 'controls');
      at(tester.getRect(key('sort-newest')), 22.31, 133.23, 77.06, 20, reason: 'Newest');
      at(tester.getRect(key('all-notes-counts')), 183.73, 135.23, 183.95, 16, reason: 'counts');
      at(tester.getRect(key('all-notes-tally')), 183.73, 135.23, 56.03, 16, reason: '20 notes');
      expect(tester.getRect(key('card-prd11')).top, closeTo(166.63, 0.5));
      await away(tester);
    });

    testWidgets('by name: a canvas’s card, with nothing to draw small, and the next a space under it', (tester) async {
      await show(tester, allNotesLibrary(), spaces: true);
      await tester.tap(key('sort-title'));
      await settle(tester);
      at(tester.getRect(key('card-cabin-canvas')), 22.31, 236, 345.38, 71.81, reason: 'the canvas');
      expect(tester.getRect(key('card-prd11')).top, closeTo(321.2, 0.5));
      await away(tester);
    });

    testWidgets('a workspace with nothing in it: the ghost over its words', (tester) async {
      final spaces = allNotesWorkspaces()..chooseWorkspace('spare');
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: Asked()));
      await settle(tester);
      at(tester.getRect(key('all-notes-controls')), 22.31, 178.16, 345.38, 20, reason: 'controls');
      at(tester.getRect(key('all-notes-tally')), 183.73, 180.16, 47.34, 16, reason: '0 notes');
      at(tester.getRect(key('all-notes-empty')), 22.31, 211.55, 345.38, 483.58, reason: 'the empty page');
      at(tester.getRect(find.descendant(of: key('all-notes-ghost'), matching: find.byType(Image))), 22.31, 238.31, 335.11, 320.7, reason: 'the ghost, 38% of the height');
      at(tester.getRect(find.ancestor(of: find.text('Nothing in Spare yet.'), matching: find.byType(CssLines)).first), 22.31, 581.33, 345.38, 40.55, reason: 'the lead');
      final hint = tester.getRect(find.text('Write it, or tap Speak and say it.'));
      expect([hint.left, hint.top], [closeTo(22.31, 0.5), closeTo(635.27, 0.5)]);
      await away(tester);
    });

    testWidgets('a search that found nothing: the looking ghost, and where to look', (tester) async {
      await show(tester, allNotesLibrary(), spaces: true);
      await type(tester, 'zzzz');
      at(tester.getRect(key('all-notes-empty')), 22.31, 236, 345.38, 507.72, reason: 'the empty page');
      at(tester.getRect(find.descendant(of: key('all-notes-ghost'), matching: find.byType(Image))), 22.31, 262.77, 186.03, 320.69, reason: 'the ghost');
      expect(tester.getRect(find.text('Nothing has “zzzz”.')).top, closeTo(605.77, 0.5));
      // Two lines of 24.17 in a column of 28 noughts.
      final hint = tester.getRect(find.ancestor(of: find.text('Try fewer words, or look in the archive.'), matching: find.byType(ConstrainedBox)).first);
      at(hint, 22.31, 659.7, 283.63, 48.31, reason: 'the hint');
      await away(tester);
    });
  });

  group('where things stand on a wide window (Chromium, 1000x800, dark)', () {
    testWidgets('the bar, the pills, one line of words, and four cards across', (tester) async {
      await show(tester, allNotesLibrary(), spaces: true, size: const Size(1000, 800), split: true);
      at(tester.getRect(key('all-notes-back')), 15.05, 73.22, 40.11, 40.11, reason: 'back');
      at(tester.getRect(key('all-notes-search')), 65.17, 72.22, 909.77, 42.11, reason: 'search');
      at(tester.getRect(key('all-notes-field')), 107.22, 73.22, 861.72, 40.11, reason: 'the field');
      at(tester.getRect(key('workspace-bar')), 0, 144.05, 1000, 36.63, reason: 'the row');
      at(tester.getRect(key('space-work')), 70.66, 146.05, 53.75, 32.63, reason: 'Work, taller than 2rem at this size');
      at(tester.getRect(key('space-add')), 270.08, 146.36, 32, 32, reason: '+, in the middle of the row');
      at(tester.getRect(key('all-notes-controls')), 25.06, 205.73, 949.88, 20, reason: 'controls');
      at(tester.getRect(key('tapes-word')), 198.63, 205.73, 112.06, 20, reason: 'Tapes');
      at(tester.getRect(key('all-notes-counts')), 325.72, 205.73, 649.22, 20, reason: 'counts');
      at(tester.getRect(key('all-notes-tally')), 325.72, 207.73, 58.25, 16, reason: 'the tally');
      at(tester.getRect(key('archive-word')), 846.53, 205.73, 128.41, 20, reason: 'Archived, at the line’s end');
      // Four to a row, a space apart, one height.
      final row = [for (final id in ['prd11', 'standup', 'flat', 'open-tickets']) tester.getRect(key('card-$id'))];
      expect([for (final card in row) card.left], [closeTo(25.06, 0.5), closeTo(266.28, 0.5), closeTo(507.52, 0.5), closeTo(748.73, 0.5)]);
      expect(row.every((card) => (card.top - 240.77).abs() < 0.5 && (card.width - 226.19).abs() < 0.5 && card.height == row.first.height), isTrue);
      expect(tester.getRect(key('card-sprint')).left, closeTo(25.06, 0.5));
      await away(tester);
    });

    testWidgets('the empty page: the ghost beside its words, three fifths to two, the words in the middle of its height', (tester) async {
      final spaces = allNotesWorkspaces()..chooseWorkspace('spare');
      await pumpAllNotes(tester, AllNotes(notes: allNotesLibrary(), workspaces: spaces, asked: Asked()), size: const Size(1000, 800), split: true);
      await settle(tester);
      at(tester.getRect(key('all-notes-empty')), 25.06, 240.77, 949.88, 430.17, reason: 'the empty page');
      at(tester.getRect(find.descendant(of: key('all-notes-ghost'), matching: find.byType(Image))), 25.06, 270.84, 376.16, 359.98, reason: 'the ghost, 45% of the height');
      final lead = tester.getRect(find.ancestor(of: find.text('Nothing in Spare yet.'), matching: find.byType(CssLines)).first);
      at(lead, 607.02, 406.95, 367.92, 47.03, reason: 'the lead');
      final hint = tester.getRect(find.text('Write it, or tap Speak and say it.'));
      expect([hint.left, hint.top], [closeTo(607.02, 0.5), closeTo(469.02, 0.5)]);
      await away(tester);
    });

    testWidgets('a search that found nothing, its hint on two lines', (tester) async {
      await show(tester, allNotesLibrary(), spaces: true, size: const Size(1000, 800), split: true);
      await type(tester, 'zzzz');
      at(tester.getRect(find.descendant(of: key('all-notes-ghost'), matching: find.byType(Image))), 25.06, 270.84, 208.83, 360, reason: 'the ghost');
      expect(tester.getRect(find.text('Nothing has “zzzz”.')).top, closeTo(394.13, 0.5));
      at(tester.getRect(find.ancestor(of: find.text('Try fewer words, or look in the archive.'), matching: find.byType(ConstrainedBox)).first), 607.02, 456.19, 300.77, 51.38, reason: 'the hint');
      await away(tester);
    });
  });

  group('what the page builds, and when', () {
    List<Note> many(int count) => [for (var i = 0; i < count; i += 1) makeNote('n$i', body: '# Note $i\n\nWhat note $i says, on a line of its own.\n\n- one\n- two', updatedAt: 100000 - i)];

    /// Every card the page has, read by going down it a screen at a time: it builds only the ones near the screen.
    Future<List<String>> down(WidgetTester tester) async {
      final position = tester.state<ScrollableState>(find.descendant(of: key('all-notes-scroll'), matching: find.byType(Scrollable)).first).position;
      final found = <String>[];
      while (true) {
        for (final id in cards(tester)) {
          if (!found.contains(id)) found.add(id);
        }
        if (position.pixels >= position.maxScrollExtent) break;
        position.jumpTo((position.pixels + position.viewportDimension * 0.5).clamp(0.0, position.maxScrollExtent));
        await tester.pump();
      }
      position.jumpTo(0);
      await tester.pump();
      return found;
    }

    testWidgets('only the cards near the screen, on a phone and across a wide window, and every one as it is scrolled to', (tester) async {
      await show(tester, many(240));
      expect(find.text('240 notes'), findsOneWidget);
      expect(tester.widgetList<NoteCard>(find.byType(NoteCard, skipOffstage: false)).length, inInclusiveRange(4, 30));
      expect(await down(tester), [for (var i = 0; i < 240; i += 1) 'n$i']);
      await away(tester);
      // Four across: a row of the grid is built whole, its cards one height.
      await show(tester, many(240), size: const Size(1000, 800), split: true);
      final built = tester.widgetList<NoteCard>(find.byType(NoteCard, skipOffstage: false)).length;
      expect(built, inInclusiveRange(12, 60));
      expect(built % 4, 0);
      expect({for (var i = 0; i < 4; i += 1) tester.getRect(key('card-n$i')).height}.length, 1, reason: 'a row of cards is one height');
      expect({for (var i = 0; i < 4; i += 1) tester.getRect(key('card-n$i')).top}.length, 1);
      expect(await down(tester), [for (var i = 0; i < 240; i += 1) 'n$i']);
      await away(tester);
    });

    testWidgets('no card again for the search field’s caret or the same notes handed over again, and every card for a new search', (tester) async {
      final notes = ValueNotifier<List<Note>>(many(40));
      final spaces = allNotesWorkspaces(any: false);
      final stored = MemoryStored();
      await pumpAllNotes(tester, ValueListenableBuilder<List<Note>>(valueListenable: notes, builder: (context, notes, _) => AllNotes(notes: notes, workspaces: spaces, asked: Asked(), stored: stored)));
      await settle(tester);
      NoteCard card(String id) => tester.widget<NoteCard>(key('card-$id'));
      final first = card('n0');
      // The same notes in a new list, and the page's own callbacks made anew: the cards are the ones it made.
      notes.value = [...notes.value];
      await tester.pump();
      expect(identical(card('n0'), first), isTrue);
      // The field takes the keyboard: the page is built for it, and no card is.
      await tester.tap(find.byType(EditableText));
      await tester.pump();
      expect(identical(card('n0'), first), isTrue);
      // Words typed: another list, and its cards.
      await type(tester, 'note 1');
      expect(cards(tester).first, 'n1');
      expect(find.text('13 of 40'), findsOneWidget);
      await type(tester, '');
      expect(identical(card('n0'), first), isFalse);
      await away(tester);
    });
  });

  group('a dense card’s preview', () {
    testWidgets('is clipped to 4.2 lines, as the page’s grid clips it', (tester) async {
      // NoteCard.module.css `.item[data-dense] .peek { max-block-size: calc(1.6em * 4.2) }`: lib/home/note_card.dart
      // hands lib/home/note_peek.dart its `dense`. Measured on the page, at 390: the sign-in ticket's card is 194.8
      // tall and the standup's 157.89 (they were up to two lines taller here while the card kept the word to itself).
      await show(tester, allNotesLibrary(), spaces: true);
      expect(tester.getRect(key('card-prd11')).height, closeTo(194.8, 2));
      expect(tester.getRect(key('card-standup')).height, closeTo(157.89, 2));
      await away(tester);
      // A note of four lines or fewer is the page's height already: Flat, 154.38.
      await show(tester, [for (final note in allNotesLibrary()) if (note.id == 'flat') note]);
      at(tester.getRect(key('card-flat')), 22.31, 166.63, 345.38, 154.38, reason: 'Flat');
      await away(tester);
    });
  });
}
