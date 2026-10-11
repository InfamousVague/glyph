import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_nav.dart';
import 'package:ghost_md/book/book_spot.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/book/stuck_head.dart';
import 'package:ghost_md/book/entry_starts.dart';
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/book/tickets.dart';
import 'package:ghost_md/canvas/json_canvas.dart' as json_canvas;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/fields/field_picker.dart';
import 'package:ghost_md/editor/markdown_view.dart';
import 'package:ghost_md/editor/view/line.dart' show EditorLine;
import 'package:ghost_md/note/page_head.dart';
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/notes/ticket_mark.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/editor_text.dart';
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

/// A page of about thirty thousand letters, of the kinds of line a page has: headings, paragraphs that wrap by
/// different amounts, and lists.
String longWords() {
  final out = StringBuffer();
  for (var i = 0; i < 120; i += 1) {
    if (i % 12 == 0) out.writeln('## Part ${i ~/ 12 + 1}\n');
    if (i % 5 == 3) {
      out.writeln('- one thing\n- another, longer than the first by a good many words, so that it wraps at a phone’s width\n');
    } else {
      out.writeln('Paragraph $i of the long page. ${List.filled(3 + i % 7, 'The path runs north from the harbour and bends.').join(' ')}\n');
    }
  }
  return out.toString();
}

/// The screen as it is drawn, pixel for pixel.
Future<({int width, int height, Uint8List data})> _picture(WidgetTester tester) async {
  final boundary = tester.allRenderObjects.whereType<RenderRepaintBoundary>().first;
  return (await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    return (width: image.width, height: image.height, data: data!.buffer.asUint8List());
  }))!;
}

/// How many of the two pictures' pixels differ.
int _differing(({int width, int height, Uint8List data}) a, ({int width, int height, Uint8List data}) b) {
  if (a.width != b.width || a.height != b.height) return a.width * a.height;
  var count = 0;
  for (var i = 0; i < a.data.length; i += 4) {
    if (a.data[i] != b.data[i] || a.data[i + 1] != b.data[i + 1] || a.data[i + 2] != b.data[i + 2] || a.data[i + 3] != b.data[i + 3]) count += 1;
  }
  return count;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));
  tearDown(() => BookViewState.longPage = 1500);

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

    // Differs 21 (docs/PARITY.md): the notebook's own words took no taps, so a link in a preface did not open
    // (book/BookView.tsx `BookWords`: `wiki={{ known, open }}`, "so a link in them opens").
    testWidgets('opens a link between notes in the notebook\'s own words on a tap, and nothing on a tap beside it', (tester) async {
      final opened = <String>[];
      await show(
        tester,
        body: '---\ntitle: "Field guide"\nbook: true\n---\nStart with [[Trees]] and keep a list in [[Sightings]].\n\n1. [[Introduction]]\n2. [[Trees]]\n',
        known: (title) => title != 'Sightings',
        open: opened.add,
      );
      final preface = find.byKey(const ValueKey('book-words-before'));
      expect(preface, findsOneWidget);
      await tester.tapAt(editorTextRect(tester, 'Start with').center);
      await tester.pump();
      expect(opened, isEmpty, reason: 'the words beside a link are only read');
      await tester.tapAt(editorTextRect(tester, 'Trees').center);
      await tester.pump();
      expect(opened, ['Trees']);
      // One still to be written opens too, which is how it gets written.
      await tester.tapAt(editorTextRect(tester, 'Sightings').center);
      await tester.pump();
      expect(opened, ['Trees', 'Sightings']);
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
    testWidgets('draws a long notebook a screenful with the view and the rest in the frames after, and a page the rail asks for at once', (tester) async {
      // Twenty pages of fifteen hundred letters: two of them are a screenful and more (the first frame's), and the
      // rest follow in the frames after.
      final titles = [for (var i = 1; i <= 20; i += 1) 'Page $i'];
      final long = List.filled(150, 'Nine words.').join(' ');
      final bodies = {for (final title in titles) title: '# $title\n\n$long'};
      List<int> drawn() => [
        for (var i = 0; i < titles.length; i += 1)
          if (find.byKey(ValueKey('book-read-title-$i'), skipOffstage: false).evaluate().isNotEmpty) i,
      ];
      // Under twenty rows, the way in is under the window's foot.
      Future<void> read() async {
        await tester.ensureVisible(find.text('Read straight through', skipOffstage: false));
        await tester.pump();
        await tester.tap(find.text('Read straight through'));
        await tester.pump();
      }

      await show(tester, body: bookNoteBody('Long', titles), title: 'Long', bodyOf: (t) => bodies[t]);
      await read();
      expect(drawn(), [0, 1]);
      final first = tester.widget(find.byKey(const ValueKey('book-read-title-0'), skipOffstage: false));
      // The rail names every page from the first frame.
      expect(find.byKey(const ValueKey('book-rail-19'), skipOffstage: false), findsOneWidget);
      // At least a page more each frame (how many more is by the clock: more after a quick frame), in order.
      for (var frame = 0, had = 2; had < titles.length; frame += 1) {
        await tester.pump();
        expect(drawn().length, greaterThan(had), reason: 'frame ${frame + 2} draws more pages');
        expect(drawn(), [for (var i = 0; i < drawn().length; i += 1) i]);
        had = drawn().length;
      }
      expect(drawn().length, 20);
      // The pages already drawn are not made again by the frames that add to them: the first's title is the widget
      // it was.
      expect(identical(tester.widget(find.byKey(const ValueKey('book-read-title-0'), skipOffstage: false)), first), isTrue);
      // Back at the index and in again: the rail is asked for the last page while the pages are still coming, and
      // every page up to it is drawn the frame after (a frame draws as many as it has time for, by their letters).
      await tester.ensureVisible(find.text('Index', skipOffstage: false));
      await tester.pump();
      await press(tester, 'Index');
      await read();
      expect(drawn(), [0, 1]);
      await tester.ensureVisible(find.byKey(const ValueKey('book-rail-19'), skipOffstage: false));
      await tester.pump();
      expect(drawn().length, lessThan(12));
      await tester.tap(find.byKey(const ValueKey('book-rail-19')));
      await tester.pump();
      expect(drawn().length, 20);
      await settle(tester);
      await away(tester);
    });

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

  group('a long page read straight through', () {
    const titles = ['Long one', 'After', 'Last'];
    final bodies = {
      'Long one': '# Long one\n\n${longWords()}',
      'After': '# After\n\n${List.filled(40, 'Words.').join('\n\n')}',
      'Last': '# Last\n\n${List.filled(40, 'Words.').join('\n\n')}',
    };
    final long = bookNoteBody('Long', titles);

    Future<void> read(WidgetTester tester, {ScrollController? scroll, String? spot}) async {
      await show(tester, body: long, title: 'Long', bodyOf: (t) => bodies[t], scroll: scroll, spot: spot);
      if (spot == null) await press(tester, 'Read straight through');
      // Every page is there: the rest follow the first frame's.
      for (var i = 0; i < 6; i += 1) {
        await tester.pump();
      }
    }

    /// How many of the long page's lines are built.
    int lines(WidgetTester tester) => find.descendant(of: find.byKey(const ValueKey('book-read-body-0')), matching: find.byType(EditorLine), skipOffstage: false).evaluate().length;

    testWidgets('lays out the lines near the window and not the page, and is drawn as the page drawn whole is', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      // Whole: a box, every line of it built and laid out with the view.
      BookViewState.longPage = 1 << 30;
      await read(tester, scroll: scroll);
      expect(tester.widget<MarkdownView>(find.byKey(const ValueKey('book-read-body-0'))).markdown, startsWith('## Part 1'));
      final every = lines(tester);
      expect(every, greaterThan(100));
      final whole = await _picture(tester);
      // Down the page by whole pixels, in steps short enough that every line above the window has been in it.
      for (final at in [300.0, 600.0]) {
        scroll.jumpTo(at);
        await tester.pump();
      }
      final wholeDown = await _picture(tester);
      await away(tester);

      // As it is: the long page's lines a sliver of the note's page.
      BookViewState.longPage = 1500;
      await read(tester, scroll: scroll);
      expect(find.byKey(const ValueKey('book-read-body-0')), findsOneWidget);
      expect(tester.widget(find.byKey(const ValueKey('book-read-body-0'))), isNot(isA<MarkdownView>()));
      // A window of 844 and what the page keeps ready under it: a few paragraphs of a hundred and more.
      expect(lines(tester), lessThan(every ~/ 4));
      expect(lines(tester), greaterThan(3));
      expect(_differing(await _picture(tester), whole), 0);
      // The title over it opens the page, as a short page's does; the lines say nothing to a screen reader.
      final handle = tester.ensureSemantics();
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Paragraph')), findsNothing);
      expect(button('Open Long one'), findsOneWidget);
      handle.dispose();
      for (final at in [300.0, 600.0]) {
        scroll.jumpTo(at);
        await tester.pump();
      }
      expect(lines(tester), lessThan(every ~/ 4));
      expect(_differing(await _picture(tester), wholeDown), 0);
      await away(tester);
    });

    testWidgets('goes to the page after it from the rail and arrives at its top, though how far that is was a guess', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await read(tester, scroll: scroll);
      // Where the page after the long one is reckoned to be before the long one's lines have been laid out.
      // (Its title stands `var(--glacier-space-6)`, 26.77px, under the section's top.)
      final title = tester.renderObject<RenderBox>(find.byKey(const ValueKey('book-read-title-1'), skipOffstage: false));
      double reckoned() => RenderAbstractViewport.of(title).getOffsetToReveal(title, 0).offset - 26.77;
      final guess = reckoned();
      await tester.tap(find.byKey(const ValueKey('book-rail-1')));
      await tester.pump();
      for (var i = 0; i < 12; i += 1) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      // The guess was off by more than a line, so a scroll that stopped where it was first sent would be seen to.
      expect((reckoned() - guess).abs(), greaterThan(20));
      expect(scroll.offset, closeTo(reckoned(), 0.5));
      expect(tester.getTopLeft(find.byKey(const ValueKey('book-read-title-1'))).dy, closeTo(26.77, 0.5));
      await away(tester);
    });

    testWidgets('is drawn whole where the book was left in it, and the book left after it opens at its place', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      writeBookSpot('book', const ReadingSpot('Long one', 3000));
      await read(tester, scroll: scroll, spot: 'book');
      await tester.pump(const Duration(milliseconds: 150));
      // The line it was left at is where it was measured to be: every line above it laid out.
      expect(find.byKey(const ValueKey('book-read-body-0')), findsOneWidget);
      expect(tester.widget(find.byKey(const ValueKey('book-read-body-0'))), isA<MarkdownView>());
      expect(tester.getTopLeft(find.byKey(const ValueKey('book-read-title-0'))).dy, closeTo(-3000 + 26.77, 0.5));
      await away(tester);

      // Left in the page after the long one: that page's top is under the window's foot when the view opens, and
      // the long page over it is not laid out.
      useStored(MemoryStored());
      writeBookSpot('book', const ReadingSpot('After', 120));
      await read(tester, scroll: scroll, spot: 'book');
      await tester.pump(const Duration(milliseconds: 150));
      expect(tester.widget(find.byKey(const ValueKey('book-read-body-0'), skipOffstage: false)), isNot(isA<MarkdownView>()));
      expect(tester.getTopLeft(find.byKey(const ValueKey('book-read-title-1'))).dy, closeTo(-120 + 26.77, 0.5));
      final was = scroll.offset;
      await tester.pump(const Duration(milliseconds: 150));
      expect(scroll.offset, was);
      await away(tester);
    });
  });

  // Differs 21 (docs/PARITY.md): `.readBar { position: sticky; top: 0; z-index: 2 }` (BookView.module.css). The way
  // back to the index and the rail went up with the first chapter and were gone for the rest of the notebook.
  group('the way back and the rail, reading straight through', () {
    String words(String t) => '# $t\n\n${List.filled(40, 'Words.').join('\n\n')}';
    Finder bar() => find.byKey(const ValueKey('book-read-bar'));

    testWidgets('stay at the top of the page as the chapters go under them, and are pressed there', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await show(tester, scroll: scroll, bodyOf: words);
      await press(tester, 'Read straight through');
      // Where it stands with the page at its top: under the notebook's own padding, where its room is kept.
      final stood = tester.getRect(bar());
      expect(stood.top, greaterThan(0));
      expect(tester.renderObject<RenderStuckHead>(find.byType(StuckHead)).shift, 0);
      scroll.jumpTo(900);
      await tester.pump();
      final stuck = tester.getRect(bar());
      expect(stuck.top, closeTo(0, 0.01));
      expect(stuck.size, stood.size);
      // Over the chapter that is under it now, and pressed where it is drawn: the rail's third page is scrolled to.
      final before = scroll.offset;
      await tester.tap(find.byKey(const ValueKey('book-rail-2')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.offset, greaterThan(before));
      expect(tester.getRect(bar()).top, closeTo(0, 0.01));
      // And Index, from the middle of the notebook, goes back to the rows.
      await tester.tap(button('Index'));
      await tester.pump();
      expect(rows(tester), ['Introduction', 'Trees', 'Birds']);
      await away(tester);
    });

    testWidgets('come to rest under the room the page keeps at its top, and go up with the notebook\'s foot', (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await pumpSlivers(
        tester,
        [
          // The page's own padding under its header, and what the view is told of it.
          const SliverToBoxAdapter(child: SizedBox(height: 58)),
          PageHead(
            height: 58,
            child: BookView(body: book, title: 'Field guide', known: (_) => true, open: (_) {}, titles: () => const [], onChange: (_) {}, bodyOf: words, clock: () => probeNow),
          ),
          // The page goes on under the notebook.
          const SliverToBoxAdapter(child: SizedBox(height: 1200)),
        ],
        scroll: scroll,
      );
      await press(tester, 'Read straight through');
      for (var i = 0; i < 6; i += 1) {
        await tester.pump();
      }
      scroll.jumpTo(700);
      await tester.pump();
      expect(tester.getRect(bar()).top, closeTo(58, 0.01));
      // Past the notebook's end the bar has gone up with it: its foot is never under the notebook's own.
      scroll.jumpTo(scroll.offset + bookRect(tester).bottom - 20);
      await tester.pump();
      final end = bookRect(tester).bottom;
      expect(end, closeTo(20, 0.01));
      expect(tester.getRect(bar()).bottom, closeTo(end, 0.01));
      await away(tester);
    });

    // The read-through is slivers, and a long page's lines are a sliver of their own: the bar is none of the first
    // run's, and is still there when that run has gone and a long page's lines are going under it.
    testWidgets('are still there over a long page\'s lines, when the first run has gone', (tester) async {
      const titles = ['Short', 'Long one', 'Last'];
      final bodies = {
        'Short': '# Short\n\n${List.filled(10, 'Words.').join('\n\n')}',
        'Long one': '# Long one\n\n${longWords()}',
        'Last': '# Last\n\n${List.filled(40, 'Words.').join('\n\n')}',
      };
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      await show(tester, body: bookNoteBody('Long', titles), title: 'Long', bodyOf: (t) => bodies[t], scroll: scroll);
      await press(tester, 'Read straight through');
      for (var i = 0; i < 6; i += 1) {
        await tester.pump();
      }
      final stood = tester.getRect(bar());
      // Into the long page: its title has gone past the top, and so has the whole of the first run.
      await tester.ensureVisible(find.byKey(const ValueKey('book-read-title-1'), skipOffstage: false));
      await tester.pump();
      scroll.jumpTo(scroll.offset + 600);
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('book-read-body-1')), matching: find.byType(EditorLine)), findsWidgets);
      final run = tester.renderObject<RenderSliver>(find.byKey(const ValueKey('book-read-run-bar'), skipOffstage: false));
      expect(run.geometry!.visible, isFalse, reason: 'the first run is off the page');
      final stuck = tester.getRect(bar());
      expect(stuck.top, closeTo(0, 0.01));
      expect(stuck.size, stood.size);
      // Pressed there: Index goes back to the rows.
      await tester.tap(button('Index'));
      await tester.pump();
      expect(rows(tester), ['Short', 'Long one', 'Last']);
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
