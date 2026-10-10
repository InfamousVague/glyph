import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_nav.dart';
import 'package:ghost_md/book/book_spot.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/book/entry_starts.dart';
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/canvas/json_canvas.dart' as json_canvas;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/fields/field_picker.dart';
import 'package:ghost_md/editor/markdown_view.dart';
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/notes/ticket_mark.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import 'support.dart';

/// The index view: the chapters as rows that open their notes, a chapter not written yet said so, the three edits
/// written back to the body, and the two ways to add one. And the bar and the foot a chapter wears. The web's
/// `book/BookView.test.tsx`, case for case; its last case (whose film cards a notebook's own words draw) waits for
/// the film card, which this view does not take a mode for.

final String book = bookNoteBody('Field guide', ['Introduction', 'Trees', 'Birds']);

List<String> chapterTitles(String body) => [for (final c in chaptersOf(body)) c.title];

/// The rows' chapters, as the index draws them: what each says to a screen reader.
List<String?> rows(WidgetTester tester) => [
      for (var i = 0; find.byKey(ValueKey('book-chapter-$i')).evaluate().isNotEmpty; i += 1) tester.widget<GlacierPressable>(find.byKey(ValueKey('book-chapter-$i'))).semanticLabel,
    ];

String canvasBody(String title) => json_canvas.canvasNoteBody(title, json_canvas.Canvas(nodes: const [], edges: const []));

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));

  Future<void> show(
    WidgetTester tester, {
    String? body,
    String title = 'Field guide',
    bool Function(String title)? known,
    ValueChanged<String>? open,
    List<String> titles = const [],
    ValueChanged<String>? onChange,
    String? Function(String title)? bodyOf,
    ValueChanged<String>? openCanvas,
    void Function(String title, String template)? openNew,
    bool readOnly = false,
    void Function(String title, String? status)? setStatus,
    void Function(String title, NoteTemplate? template)? openTicket,
    List<NoteTemplate> ticketTemplates = const [],
    String? spot,
    ScrollController? scroll,
  }) =>
      pumpView(
        tester,
        BookView(
          body: body ?? book,
          title: title,
          known: known ?? (_) => true,
          open: open ?? (_) {},
          titles: () => titles,
          onChange: onChange ?? (_) {},
          bodyOf: bodyOf,
          openCanvas: openCanvas,
          openNew: openNew,
          readOnly: readOnly,
          setStatus: setStatus,
          openTicket: openTicket,
          ticketTemplates: ticketTemplates,
          spot: spot,
          clock: () => probeNow,
        ),
        scroll: scroll,
      );

  group('the index view', () {
    testWidgets('lists the chapters numbered, opens one on a tap, and says which is not written yet', (tester) async {
      final opened = <String>[];
      await show(tester, known: (t) => t != 'Birds', open: opened.add);
      expect(rows(tester), ['Introduction', 'Trees', 'Birds, not written yet']);
      for (final (i, number) in ['1', '2', '3'].indexed) {
        expect(find.descendant(of: find.byKey(ValueKey('book-row-$i')), matching: find.text(number)), findsOneWidget);
      }
      await press(tester, 'Trees');
      expect(opened, ['Trees']);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-2')), matching: find.text('Birds')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-2')), matching: find.text('not written yet')), findsOneWidget);
      await away(tester);
    });

    testWidgets('moves a chapter, takes one out, and writes each change into the body', (tester) async {
      final written = <String>[];
      await show(tester, onChange: written.add);
      await press(tester, 'Move Birds up');
      expect(chapterTitles(written[0]), ['Introduction', 'Birds', 'Trees']);
      await press(tester, 'Take Trees out of the notebook');
      expect(chapterTitles(written[1]), ['Introduction', 'Birds']);
      // The first cannot go up, the last cannot go down.
      expect(disabled(tester, 'Move Introduction up'), isTrue);
      expect(disabled(tester, 'Move Birds down'), isTrue);
      await away(tester);
    });

    testWidgets('writes a chapter dragged by its grip to where it is let go', (tester) async {
      final written = <String>[];
      await show(tester, onChange: written.add);
      final row = tester.getSize(find.byKey(const ValueKey('book-row-0'))).height;
      // Past the middles of the two rows under it: the last place.
      await dragGrip(tester, find.byKey(const ValueKey('book-grip-0')), 2.25 * row);
      expect(written, hasLength(1));
      expect(chapterTitles(written[0]), ['Trees', 'Birds', 'Introduction']);
      await away(tester);
    });

    testWidgets('adds a new chapter as a canvas when asked, opening it as one, and offers that only where a canvas can be made', (tester) async {
      final written = <String>[], opened = <String>[], canvases = <String>[];
      await show(tester, onChange: written.add, open: opened.add, openCanvas: canvases.add);
      await press(tester, 'Add a page');
      await tester.enterText(find.byKey(const ValueKey('book-page-title')), 'Trail map');
      await tester.pump();
      await press(tester, 'Add as a canvas');
      expect(chapterTitles(written[0]), ['Introduction', 'Trees', 'Birds', 'Trail map']);
      expect(canvases, ['Trail map']);
      expect(opened, isEmpty);
      await away(tester);
      await show(tester);
      await press(tester, 'Add a page');
      expect(button('Add as a canvas'), findsNothing);
      await away(tester);
    });

    testWidgets('offers what a new page starts with under its title, just the title unless a template is picked', (tester) async {
      final opened = <String>[];
      final made = <(String, String)>[];
      await show(tester, open: opened.add, openNew: (title, template) => made.add((title, template)));
      await press(tester, 'Add a page');
      List<GlacierPressable> choices() => [for (final start in pageStarts()) tester.widget<GlacierPressable>(find.byKey(ValueKey('book-start:${start.id}')))];
      expect([for (final start in pageStarts()) start.name], ['Just the title', for (final p in entryPresets) p.name]);
      for (final start in pageStarts()) {
        expect(find.descendant(of: find.byKey(ValueKey('book-start:${start.id}')), matching: find.text(start.name)), findsOneWidget);
      }
      expect(choices()[0].toggled, isTrue);
      // Just the title: the page opens as it always did.
      await tester.enterText(find.byKey(const ValueKey('book-page-title')), 'Rivers');
      await tester.pump();
      await press(tester, 'Add and open');
      expect(opened, ['Rivers']);
      expect(made, isEmpty);
      // A template picked: the page is made from it, and the next page starts from just the title again.
      await press(tester, 'Add a page');
      await tester.enterText(find.byKey(const ValueKey('book-page-title')), 'Monday');
      await tester.pump();
      await tester.ensureVisible(find.byKey(ValueKey('book-start:${entryPresets[2].id}')));
      await tester.tap(find.byKey(ValueKey('book-start:${entryPresets[2].id}')));
      await tester.pump();
      expect(choices()[3].toggled, isTrue);
      await press(tester, 'Add and open');
      expect(made, [('Monday', entryPresets[2].text)]);
      await press(tester, 'Add a page');
      expect(choices()[0].toggled, isTrue);
      // The arrows move the choice and the focus together.
      choices()[0].focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(choices()[1].toggled, isTrue);
      expect(choices()[1].focusNode!.hasFocus, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(choices()[4].toggled, isTrue);
      await away(tester);
    });

    testWidgets('closes Add a page on the back gesture before the notebook would be left, letting the choice go', (tester) async {
      await show(tester, openNew: (_, _) {});
      final stack = BackScope.of(tester.element(find.byType(BookView)));
      var left = 0;
      // Under the form's own handler: what leaving the notebook would run.
      expect(stack.depth, 0);
      await press(tester, 'Add a page');
      await tester.tap(find.byKey(ValueKey('book-start:${entryPresets[2].id}')));
      await tester.pump();
      expect(stack.depth, 1);
      if (!stack.goBack()) left += 1;
      await tester.pump();
      expect(find.byKey(const ValueKey('book-page-title')), findsNothing);
      expect(left, 0);
      expect(stack.depth, 0);
      await press(tester, 'Add a page');
      expect(tester.widget<GlacierPressable>(find.byKey(ValueKey('book-start:${justTheTitle.id}'))).toggled, isTrue);
      // Escape in the field closes the form too, and nothing more.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byKey(const ValueKey('book-page-title')), findsNothing);
      await away(tester);
    });

    testWidgets('adds a new chapter by name and opens it, and adds a note already written from the library', (tester) async {
      final written = <String>[], opened = <String>[];
      await show(tester, onChange: written.add, open: opened.add, titles: ['Field guide', 'Trees', 'Rivers', 'Mountains']);
      await press(tester, 'Add a page');
      expect(find.text('Page title'), findsOneWidget);
      await tester.enterText(find.byKey(const ValueKey('book-page-title')), 'Rivers');
      await tester.pump();
      await press(tester, 'Add and open');
      expect(chapterTitles(written[0]), ['Introduction', 'Trees', 'Birds', 'Rivers']);
      expect(opened, ['Rivers']);

      await press(tester, 'Add a note you have');
      // The book itself and the chapters already in it are not offered; several can be ticked and added at once.
      List<String> offered() => [for (final w in tester.widgetList<GlacierPressable>(find.byWidgetPredicate((w) => w is GlacierPressable && '${w.key}'.contains('book-pick:')))) w.semanticLabel!];
      expect(offered(), ['Rivers', 'Mountains']);
      await press(tester, 'Mountains');
      await press(tester, 'Rivers');
      expect(button('Add 2 notes'), findsOneWidget);
      await press(tester, 'Add 2 notes');
      final all = chapterTitles(written[1]);
      expect(all.sublist(all.length - 2), ['Mountains', 'Rivers']);
      await away(tester);
    });

    testWidgets('says so when no note outside the notebook has that name, or every note is in it already', (tester) async {
      await show(tester, titles: ['Field guide', 'Trees', 'Rivers']);
      await press(tester, 'Add a note you have');
      await tester.enterText(find.byKey(const ValueKey('book-find')), 'zzz');
      await tester.pump();
      expect(find.text('No note by that name outside the notebook.'), findsOneWidget);
      await away(tester);
      await show(tester, titles: ['Field guide', 'Trees']);
      await press(tester, 'Add a note you have');
      expect(find.text('Every note is in the notebook already.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('marks a chapter that is a canvas, and a canvas it offers to add, with the canvas mark', (tester) async {
      final bodies = <String, String>{'Trees': '# Trees\n\nWords.', 'Birds': canvasBody('Birds'), 'Rivers': canvasBody('Rivers'), 'Mountains': '# Mountains'};
      await show(tester, known: bodies.containsKey, titles: ['Rivers', 'Mountains'], bodyOf: (t) => bodies[t]);
      bool marked(Finder within) => find.descendant(of: within, matching: find.byType(CanvasMark)).evaluate().isNotEmpty;
      // Introduction has no note yet, so nothing says what it is; Birds is a canvas.
      expect([for (var i = 0; i < 3; i += 1) marked(find.byKey(ValueKey('book-row-$i')))], [false, false, true]);
      expect(button('Birds, a canvas'), findsOneWidget);
      await press(tester, 'Add a note you have');
      expect([marked(find.byKey(const ValueKey('book-pick:Rivers'))), marked(find.byKey(const ValueKey('book-pick:Mountains')))], [true, false]);
      await away(tester);
    });

    testWidgets('read-only, draws the same numbered index with nothing to move, take out or add, and still reads straight through', (tester) async {
      final opened = <String>[];
      await show(tester, known: (t) => t != 'Birds', open: opened.add, readOnly: true);
      expect(rows(tester), ['Introduction', 'Trees', 'Birds, not written yet']);
      for (final label in ['Move Birds up', 'Take Trees out of the notebook', 'Add a page', 'Add a note you have']) {
        expect(button(label), findsNothing);
      }
      expect(find.byKey(const ValueKey('book-grip-0')), findsNothing);
      await press(tester, 'Trees');
      expect(opened, ['Trees']);
      expect(button('Read straight through'), findsOneWidget);
      await away(tester);
    });

    testWidgets('says so when the book has no chapters', (tester) async {
      await show(tester, body: bookNoteBody('Trip'), title: 'Trip');
      expect(find.textContaining('No pages yet'), findsOneWidget);
      await away(tester);
    });
  });

  group('a notebook of tickets (docs/DESIGN.md §157)', () {
    final keyed = withNotebookKey(bookNoteBody('Ghost.md', ['Fix the login loop', 'Write the docs']), 'GHO');
    const bodies = <String, String>{
      'Fix the login loop': '---\ntype: ticket\nid: GHO-12\nstatus: In progress\n---\n# Fix the login loop\n',
      'Write the docs': '# Write the docs\n',
    };
    final bug = builtIns.firstWhere((one) => one.kind == TemplateId.bug);
    final feature = builtIns.firstWhere((one) => one.kind == TemplateId.feature);

    testWidgets('offers New ticket only with a key, and puts the ticket’s line in the index before the app makes it', (tester) async {
      final written = <String>[];
      final tickets = <(String, NoteTemplate?)>[];
      await show(tester, body: keyed, title: 'Ghost.md', onChange: written.add, openTicket: (title, template) => tickets.add((title, template)), ticketTemplates: [bug, feature]);
      await press(tester, 'New ticket');
      await tester.enterText(find.byKey(const ValueKey('book-ticket-title')), 'Session cookie expires');
      await tester.pump();
      // Just the title, then the tickets' templates, each said in its sentence; no canvas for a ticket.
      expect(find.descendant(of: find.byKey(const ValueKey('book-starts')), matching: find.text('Just the title')), findsOneWidget);
      expect(find.text('GHO-…, “Session cookie expires” and its status, and nothing under them'), findsOneWidget);
      expect(find.text(bug.sentence), findsOneWidget);
      expect(find.text(feature.sentence), findsOneWidget);
      expect(tester.widgetList<GlacierPressable>(find.byWidgetPredicate((w) => w is GlacierPressable && '${w.key}'.contains('book-start:'))), hasLength(3));
      expect(button('Add as a canvas'), findsNothing);
      await tester.tap(find.byKey(ValueKey('book-start:${bug.id}')));
      await tester.pump();
      await press(tester, 'Add and open');
      expect(chapterTitles(written[0]), ['Fix the login loop', 'Write the docs', 'Session cookie expires']);
      expect(tickets, [('Session cookie expires', bug)]);
      await away(tester);
      await show(tester, body: bookNoteBody('Plain'), title: 'Plain', openTicket: (_, _) {});
      expect(button('New ticket'), findsNothing);
      await away(tester);
    });

    testWidgets('reads each page’s words once, however often the index is built, and again when they change', (tester) async {
      final pages = {...bodies};
      await show(tester, body: keyed, title: 'Ghost.md', bodyOf: (title) => pages[title]);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-0')), matching: find.textContaining('In progress')), findsWidgets);
      final read = BookViewState.debugPageReads;
      // Built again with the words it had, as the note's screen builds it at every change of its own.
      await show(tester, body: keyed, title: 'Ghost.md', bodyOf: (title) => pages[title]);
      await show(tester, body: keyed, title: 'Ghost.md', bodyOf: (title) => pages[title]);
      expect(BookViewState.debugPageReads, read);
      // One page's words changed: that page alone is read again, and its row says what it now says.
      pages['Fix the login loop'] = pages['Fix the login loop']!.replaceFirst('In progress', 'Done');
      await show(tester, body: keyed, title: 'Ghost.md', bodyOf: (title) => pages[title]);
      expect(BookViewState.debugPageReads, read + 1);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-0')), matching: find.textContaining('Done')), findsWidgets);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-0')), matching: find.textContaining('In progress')), findsNothing);
      await away(tester);
    });

    testWidgets('says a page that is a ticket its key and status on its row, and nothing on a page of words', (tester) async {
      await show(tester, body: keyed, title: 'Ghost.md', bodyOf: (title) => bodies[title]);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-0')), matching: find.byType(TicketMark)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-0')), matching: find.textContaining('GHO-12')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-0')), matching: find.textContaining('In progress')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-1')), matching: find.byType(TicketMark)), findsNothing);
      await away(tester);
    });

    testWidgets('changes a ticket’s status from its row: a pill that opens the workflow’s sheet (docs/DESIGN.md §169)', (tester) async {
      final set = <(String, String?)>[];
      await show(tester, body: keyed, title: 'Ghost.md', bodyOf: (title) => bodies[title], setStatus: (title, status) => set.add((title, status)));
      // The key stays on the row's title; the status is a button of its own beside it, and a page of words has none.
      expect(find.byType(TicketStatusButton), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('book-row-0')), matching: find.textContaining('GHO-12')), findsOneWidget);
      await tester.tap(find.byType(TicketStatusButton));
      await settle(tester);
      final picker = tester.widget<FieldPicker>(find.byType(FieldPicker));
      expect(picker.label, 'Status');
      expect(picker.record, 'GHO-12 · Fix the login loop');
      await tester.tap(find.byKey(const ValueKey('status:In review')));
      await settle(tester);
      expect(set, [('Fix the login loop', 'In review')]);
      expect(find.byType(FieldPicker), findsNothing);
      await away(tester);
    });

    testWidgets('draws the status as words, not a button, where the index cannot change it', (tester) async {
      await show(tester, body: keyed, title: 'Ghost.md', bodyOf: (title) => bodies[title], readOnly: true, setStatus: (_, _) {});
      expect(find.byType(TicketStatusButton), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('book-index-list')), matching: find.textContaining('In progress')), findsOneWidget);
      await away(tester);
    });
  });

  group('reading straight through', () {
    testWidgets('draws the chapters one after another, says which is a canvas or not written, and goes back to the index', (tester) async {
      const bodies = <String, String>{
        'Introduction': '# Introduction\n\nStart here.',
        'Trees': '{"nodes":[{"id":"a","type":"text","text":"a","x":0,"y":0,"width":10,"height":10}],"edges":[]}',
      };
      await show(tester, known: (t) => t != 'Birds', bodyOf: (t) => bodies[t]);
      await press(tester, 'Read straight through');
      final handle = tester.ensureSemantics();
      for (final title in ['Introduction', 'Trees', 'Birds']) {
        expect(button('Open $title'), findsOneWidget);
      }
      // The chapter's words without the heading that names it.
      expect(tester.widget<MarkdownView>(find.byKey(const ValueKey('book-read-body-0'))).markdown, 'Start here.');
      expect(find.text('A canvas: open it to see the cards.'), findsOneWidget);
      expect(find.text('Not written yet.'), findsOneWidget);
      // The rail names every chapter; Index goes back to the rows.
      expect([for (var i = 0; i < 3; i += 1) tester.widget<GlacierPressable>(find.byKey(ValueKey('book-rail-$i'))).semanticLabel], ['1 Introduction', '2 Trees', '3 Birds']);
      handle.dispose();
      await press(tester, 'Index');
      expect(rows(tester), ['Introduction', 'Trees, a canvas', 'Birds, not written yet']);
      await away(tester);
    });
  });

  group('where the book was left', () {
    testWidgets('keeps the index as the spot while the index is shown, and the read-through while that is', (tester) async {
      await show(tester, spot: 'book');
      expect(readBookSpot('book'), const IndexSpot());
      await press(tester, 'Read straight through');
      expect(readBookSpot('book'), isA<ReadingSpot>());
      await press(tester, 'Index');
      expect(readBookSpot('book'), const IndexSpot());
      await away(tester);
    });

    testWidgets('opens reading straight through where it was left, scrolled back to the chapter and the line', (tester) async {
      writeBookSpot('book', const ReadingSpot('Trees', 120));
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      // Each chapter long enough that the page has somewhere to scroll to.
      await show(tester, spot: 'book', scroll: scroll, bodyOf: (t) => '# $t\n\n${List.filled(40, 'Words.').join('\n\n')}');
      expect(tester.state<BookViewState>(find.byType(BookView)).reading, isTrue);
      await tester.pump();
      await tester.pump();
      // Trees's section, 120 into it, is at the top of the page.
      // (Its title stands `var(--glacier-space-6)`, 26.77px, under the section's top.)
      final title = tester.getTopLeft(find.byKey(const ValueKey('book-read-title-1'))).dy;
      expect(scroll.offset, greaterThan(500));
      expect(title, closeTo(-120 + 26.77, 0.5));
      final was = scroll.offset;
      await tester.pump(const Duration(milliseconds: 150));
      expect(scroll.offset, was);
      // Back at the index and reading again, it starts where the page is, not at the old place.
      await press(tester, 'Index');
      scroll.jumpTo(0);
      await tester.pump();
      await press(tester, 'Read straight through');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(scroll.offset, 0);
      await away(tester);
    });

    testWidgets('writes the read-through’s place as scrolling settles', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await show(tester, spot: 'book', scroll: scroll, bodyOf: (t) => '# $t\n\n${List.filled(40, 'Words.').join('\n\n')}');
      await press(tester, 'Read straight through');
      expect(readBookSpot('book'), const ReadingSpot('Introduction', 0));
      final trees = tester.getTopLeft(find.byKey(const ValueKey('book-read-title-1'))).dy;
      scroll.jumpTo(trees + 300);
      await tester.pump(const Duration(milliseconds: 100));
      expect(readBookSpot('book'), const ReadingSpot('Introduction', 0));
      await tester.pump(saveAfter);
      final spot = readBookSpot('book');
      expect(spot, isA<ReadingSpot>());
      expect((spot! as ReadingSpot).title, 'Trees');
      expect((spot as ReadingSpot).offset, greaterThan(200));
      await away(tester);
    });
  });

  group('the bar a chapter wears', () {
    testWidgets('names the book and the place, and opens the neighbours and the book', (tester) async {
      final place = bookOf([makeNote('b', body: book)], 'Trees')!;
      final opened = <String>[];
      await pumpView(tester, BookBar(place: place, open: opened.add));
      expect(find.text('Field guide'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      await press(tester, 'Previous page: Introduction');
      await press(tester, 'Next page: Birds');
      await press(tester, 'Open the notebook Field guide');
      expect(opened, ['Introduction', 'Birds', 'Field guide']);
      await away(tester);
    });

    testWidgets('has no way past the ends', (tester) async {
      await pumpView(tester, BookBar(place: bookOf([makeNote('b', body: book)], 'Introduction')!, open: (_) {}));
      expect(disabled(tester, 'First page'), isTrue);
      expect(disabled(tester, 'Next page: Trees'), isFalse);
      await away(tester);
      await pumpView(tester, BookBar(place: bookOf([makeNote('b', body: book)], 'Birds')!, open: (_) {}));
      expect(disabled(tester, 'Last page'), isTrue);
      await away(tester);
    });
  });

  group('the foot a chapter wears', () {
    testWidgets('names the chapters either side under the page and opens them', (tester) async {
      final opened = <String>[];
      await pumpView(tester, BookFoot(place: bookOf([makeNote('b', body: book)], 'Trees')!, open: opened.add));
      final handle = tester.ensureSemantics();
      expect(find.bySemanticsLabel('Previous and next page'), findsOneWidget);
      handle.dispose();
      expect([for (final word in ['Previous', 'Introduction', 'Next', 'Birds']) find.text(word).evaluate().length], [1, 1, 1, 1]);
      await press(tester, 'Previous: Introduction');
      await press(tester, 'Next: Birds');
      expect(opened, ['Introduction', 'Birds']);
      await away(tester);
    });

    testWidgets('has only Next on the first chapter, only Previous on the last, and nothing for a book of one', (tester) async {
      List<String?> steps() => [for (final w in tester.widgetList<GlacierPressable>(find.descendant(of: find.byType(BookFoot), matching: find.byType(GlacierPressable)))) w.semanticLabel];
      await pumpView(tester, BookFoot(place: bookOf([makeNote('b', body: book)], 'Introduction')!, open: (_) {}));
      expect(steps(), ['Next: Trees']);
      await away(tester);
      await pumpView(tester, BookFoot(place: bookOf([makeNote('b', body: book)], 'Birds')!, open: (_) {}));
      expect(steps(), ['Previous: Trees']);
      await away(tester);
      final one = bookOf([makeNote('b', body: bookNoteBody('Short', ['Only']))], 'Only')!;
      await pumpView(tester, BookFoot(place: one, open: (_) {}));
      expect(steps(), isEmpty);
      expect(BookFoot.has(one), isFalse);
      expect(tester.getSize(find.byType(BookFoot)).height, 0);
      await away(tester);
    });
  });

  test('the sheet’s kit is the one the status sheet is drawn with', () {
    // A guard for the import above: the status sheet's rows are lib/sheet/kit.dart's.
    expect(SheetRow, isNotNull);
  });
}
