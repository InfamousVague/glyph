import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_nav.dart';
import 'package:ghost_md/book/book_view.dart';
import 'package:ghost_md/book/journal_months.dart';
import 'package:ghost_md/book/journal_view.dart';
import 'package:ghost_md/book/new_book_sheet.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;
import 'package:ghost_md/core/preferences.dart' as core;
import 'package:ghost_md/core/sample_library.dart' show exampleNotebookBody;
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/notes/ticket_mark.dart';
import 'package:ghost_md/sheet/css.dart' show CssLines;
import 'package:ghost_md/sheet/kit.dart';
import 'package:glacier/glacier.dart' show GlacierContext;

import '../support/render.dart' show pumpApp;
import 'support.dart';

/// The notebook's pages held to the web page's own rectangles (tool/book_reference.mjs wrote them from Chromium
/// drawing ../glyph over the same notes, at the same minute), to half a pixel, and a picture of each
/// (test/book_ui/shots) to look at beside the page's (test/book_ui/fixtures/web).
///
/// A rectangle is asked from the view's own corner on both sides: the page's view starts under its header, this
/// one at the top of the test's page.
void main() {
  setUpAll(loadAppFonts);

  const phone = Size(390, 844);
  const desk = Size(1280, 800);

  Widget fieldGuide() => BookView(body: ProbeLibrary.book, title: 'Field guide', known: ProbeLibrary.known, bodyOf: ProbeLibrary.bodyOf, open: (_) {}, openNew: (_, _) {}, openCanvas: (_) {}, titles: ProbeLibrary.titles, onChange: (_) {}, clock: () => probeNow);
  final tickets = [for (final one in builtIns) if (one.kind == TemplateId.bug || one.kind == TemplateId.feature) one];
  Widget ghostMd() => BookView(body: ProbeLibrary.keyed, title: 'Ghost.md', known: ProbeLibrary.known, bodyOf: ProbeLibrary.bodyOf, open: (_) {}, openNew: (_, _) {}, openCanvas: (_) {}, openTicket: (_, _) {}, ticketTemplates: tickets, setStatus: (_, _) {}, titles: ProbeLibrary.titles, onChange: (_) {}, clock: () => probeNow);
  Widget diary({bool newEntry = true}) => JournalView(body: ProbeLibrary.journal, noteOf: ProbeLibrary.titled, known: ProbeLibrary.known, open: (_) {}, onChange: (_) {}, onNewEntry: newEntry ? (_) {} : null, clock: () => probeNow);

  /// What [finder] finds, held to the [at]th thing the page called [name]. [from] moves both sides to a corner of
  /// their own, for a thing measured from something other than the view.
  // Every rectangle of a page is asked before any is refused, so one run says all that is off.
  final misses = <String>[];
  void held(WidgetTester tester, Measured web, String name, int at, Finder finder, {Offset from = Offset.zero, Offset webFrom = Offset.zero, double by = 0.5}) {
    final got = tester.getRect(finder).shift(-from);
    final want = web.rect(name, at);
    final wanted = [want[0] - webFrom.dx, want[1] - webFrom.dy, want[2], want[3]];
    final has = [got.left, got.top, got.width, got.height];
    if ([for (var i = 0; i < 4; i += 1) (has[i] - wanted[i]).abs() > by].contains(true)) {
      misses.add('$name $at: ${[for (final n in has) n.toStringAsFixed(2)]} against ${[for (final n in wanted) n.toStringAsFixed(2)]}');
    }
  }

  /// Takes the page down and says what was off.
  Future<void> done(WidgetTester tester) async {
    await away(tester);
    debugDefaultTargetPlatformOverride = null;
    final said = misses.join('\n');
    misses.clear();
    expect(said, isEmpty);
  }

  group('a notebook’s index', () {
    testWidgets('at a phone’s width, to half a pixel', (tester) async {
      await pumpView(tester, fieldGuide());
      final web = Measured.load('index-390');
      held(tester, web, 'book', 0, find.byType(BookView));
      held(tester, web, 'preface', 0, find.byKey(const ValueKey('book-words-before')));
      held(tester, web, 'preface', 1, find.byKey(const ValueKey('book-words-after')));
      for (var i = 0; i < 5; i += 1) {
        held(tester, web, 'rows', i, find.byKey(ValueKey('book-row-$i')));
        held(tester, web, 'chapters', i, find.byKey(ValueKey('book-chapter-$i')));
        held(tester, web, 'grips', i, find.byKey(ValueKey('book-grip-$i')));
        held(tester, web, 'titles', i, find.descendant(of: find.byKey(ValueKey('book-chapter-$i')), matching: find.byType(Row)).first);
        held(tester, web, 'numbers', i, find.ancestor(of: find.descendant(of: find.byKey(ValueKey('book-row-$i')), matching: find.text(web.text('numbers', i))), matching: find.byType(SizedBox)).first);
        // The three tools, each 26.66 square.
        for (var n = 0; n < 3; n += 1) {
          final tool = find.descendant(of: find.byKey(ValueKey('book-row-$i')), matching: find.byWidgetPredicate((w) => w is Container && w.constraints?.maxWidth == 2 * 13.3333)).at(n);
          held(tester, web, 'tool', i * 3 + n, tool);
        }
      }
      held(tester, web, 'waiting', 0, find.text('not written yet'));
      held(tester, web, 'canvasMarks', 0, find.descendant(of: find.byType(CanvasMark), matching: find.byType(CustomPaint)).first);
      held(tester, web, 'actions', 0, find.byKey(const ValueKey('book-add-page')));
      held(tester, web, 'actions', 1, find.byKey(const ValueKey('book-add-existing')));
      held(tester, web, 'actions', 2, find.byKey(const ValueKey('book-read')));
      await done(tester);
    });

    testWidgets('on a wide window, where the page’s sizes are larger', (tester) async {
      await pumpView(tester, fieldGuide(), size: desk);
      final web = Measured.load('index-1280');
      // The page's words over and under the index stand a paragraph's room taller there: the split layout's rule
      // for the room under a note (`.app-split .editor .cm-editor .cm-content`) outranks the preface's own, which
      // is the wide layouts' to carry (stage 10). So the index is held from its own first row, and the buttons
      // from the first of them.
      final rows = tester.getRect(find.byKey(const ValueKey('book-row-0'))).topLeft;
      final webRows = Offset(web.rect('rows')[0], web.rect('rows')[1]);
      for (var i = 0; i < 5; i += 1) {
        held(tester, web, 'rows', i, find.byKey(ValueKey('book-row-$i')), from: rows, webFrom: webRows);
        held(tester, web, 'chapters', i, find.byKey(ValueKey('book-chapter-$i')), from: rows, webFrom: webRows);
        held(tester, web, 'grips', i, find.byKey(ValueKey('book-grip-$i')), from: rows, webFrom: webRows);
      }
      final adds = tester.getRect(find.byKey(const ValueKey('book-add-page'))).topLeft;
      final webAdds = Offset(web.rect('actions')[0], web.rect('actions')[1]);
      held(tester, web, 'actions', 1, find.byKey(const ValueKey('book-add-existing')), from: adds, webFrom: webAdds);
      held(tester, web, 'actions', 2, find.byKey(const ValueKey('book-read')), from: adds, webFrom: webAdds);
      expect(tester.getRect(find.byKey(const ValueKey('book-add-page'))).left, closeTo(web.rect('actions')[0], 0.5));
      await done(tester);
    });

    testWidgets('with Add a page open', (tester) async {
      await pumpView(tester, fieldGuide());
      await press(tester, 'Add a page');
      await tester.enterText(find.byKey(const ValueKey('book-page-title')), 'Rivers of the north');
      await tester.pump();
      final web = Measured.load('add-page-390', from: 'index-390');
      held(tester, web, 'add', 0, find.byKey(const ValueKey('book-add')));
      held(tester, web, 'field', 0, find.byKey(const ValueKey('book-page-title')));
      held(tester, web, 'starts', 0, find.byKey(const ValueKey('book-starts')));
      held(tester, web, 'startsTitle', 0, find.ancestor(of: find.text('START WITH'), matching: find.byType(CssLines)).first);
      for (final (i, id) in ['title', 'stamped', 'time', 'morning', 'todos'].indexed) {
        held(tester, web, 'start', i, find.byKey(ValueKey('book-start:$id')));
      }
      held(tester, web, 'actions', 0, find.byKey(const ValueKey('book-add-open')));
      held(tester, web, 'actions', 1, find.byKey(const ValueKey('book-add-canvas')));
      held(tester, web, 'quiet', 0, button('Cancel'));
      await done(tester);
    });

    testWidgets('with Add a note you have open and one picked', (tester) async {
      await pumpView(tester, fieldGuide());
      await press(tester, 'Add a note you have');
      await press(tester, 'Rivers');
      final web = Measured.load('add-existing-390', from: 'index-390');
      held(tester, web, 'field', 0, find.byKey(const ValueKey('book-find')));
      held(tester, web, 'picker', 0, find.byKey(const ValueKey('book-picker')));
      for (final (i, title) in ['Rivers', 'Ghost.md', 'Fix the login loop'].indexed) {
        held(tester, web, 'pick', i, find.byKey(ValueKey('book-pick:$title')));
        held(tester, web, 'pickMark', i, find.descendant(of: find.byKey(ValueKey('book-pick:$title')), matching: find.byType(PickMark)));
      }
      held(tester, web, 'actions', 0, find.byKey(const ValueKey('book-add-picked')));
      held(tester, web, 'quiet', 0, button('Cancel'));
      await done(tester);
    });

    testWidgets('read straight through', (tester) async {
      await pumpView(tester, fieldGuide());
      await press(tester, 'Read straight through');
      final web = Measured.load('reading-390');
      held(tester, web, 'actions', 0, find.byKey(const ValueKey('book-index')));
      for (var i = 0; i < 4; i += 1) {
        // Each pill of the rail is a fifth of a pixel narrower here than there, which by the fourth is 0.52.
        held(tester, web, 'railItems', i, find.byKey(ValueKey('book-rail-$i')), by: i < 3 ? 0.5 : 0.6);
        held(tester, web, 'readTitleButton', i, find.byKey(ValueKey('book-read-title-$i')));
      }
      for (var i = 0; i < 3; i += 1) {
        held(tester, web, 'readBody', i, find.byKey(ValueKey('book-read-body-$i')));
      }
      held(tester, web, 'readNote', 0, find.text('Not written yet.'));
      held(tester, web, 'readNote', 1, find.text('A canvas: open it to see the cards.'));
      held(tester, web, 'book', 0, find.byType(BookView));
      await done(tester);
    });

    testWidgets('of tickets, with New ticket open', (tester) async {
      await pumpView(tester, ghostMd());
      final web = Measured.load('tickets-390');
      for (var i = 0; i < 2; i += 1) {
        held(tester, web, 'rows', i, find.byKey(ValueKey('book-row-$i')));
        held(tester, web, 'chapters', i, find.byKey(ValueKey('book-chapter-$i')));
      }
      held(tester, web, 'statusButtons', 0, find.byType(TicketStatusButton));
      held(tester, web, 'marks', 0, find.byKey(const ValueKey('book-ticket-0')));
      held(tester, web, 'actions', 0, find.byKey(const ValueKey('book-add-page')));
      held(tester, web, 'actions', 1, find.byKey(const ValueKey('book-new-ticket')));
      held(tester, web, 'actions', 2, find.byKey(const ValueKey('book-add-existing')));
      await press(tester, 'New ticket');
      await tester.enterText(find.byKey(const ValueKey('book-ticket-title')), 'Session cookie expires');
      await tester.pump();
      final form = Measured.load('new-ticket-390', from: 'tickets-390');
      for (final (i, id) in ['title', tickets[0].id, tickets[1].id].indexed) {
        held(tester, form, 'start', i, find.byKey(ValueKey('book-start:$id')));
      }
      held(tester, form, 'actions', 0, find.byKey(const ValueKey('book-add-open')));
      held(tester, form, 'quiet', 0, button('Cancel'));
      await done(tester);
    });
  });

  group('the bar and the foot a page wears', () {
    testWidgets('in the Fold’s narrowest pane the bar’s mark, name and count all give way, as the page’s do', (tester) async {
      // The page, in the Tauri app on an emulator at the Fold's unfolded size (704 x 933 at 2.625), the sidebar
      // and the aside docked and the note 164px between them, on the Example project's third page, 2026-10-09:
      // `getBoundingClientRect`, less the pane's left edge and the bar's top. The sides' columns are nothing there
      // (`minmax(0, 1fr)`) and the middle has the 107px the bar's padding and gaps leave.
      final book = Note(id: 'book', body: exampleNotebookBody(), createdAt: 0, updatedAt: 0);
      final place = BookPlace(book: book, title: 'Example project', chapters: chaptersOf(book.body), at: 2, journal: false);
      final errors = <String>[];
      final was = FlutterError.onError;
      FlutterError.onError = (details) => errors.add(details.toString().split('\n').take(8).join('\n'));
      await pumpApp(
        tester,
        size: const Size(704, 933),
        ratio: 2.625,
        measuredAt: 2.625,
        home: Builder(
          builder: (context) => ColoredBox(
            color: context.tokens.color('glacier-bg'),
            child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 164, child: BookBar(place: place, open: (_) {}))),
          ),
        ),
      );
      await tester.pump();
      FlutterError.onError = was;
      expect(errors, isEmpty);
      void near(double here, double page, String what, [double within = 0.6]) => expect(here, closeTo(page, within), reason: '$what: page $page, here ${here.toStringAsFixed(2)}');
      final bar = tester.getRect(find.byType(BookBar));
      near(bar.height, 70.1, 'the bar’s height', 1);
      final middle = tester.getRect(find.byKey(const ValueKey('book-bar-book')));
      near(middle.left, 28.5, 'the middle’s left');
      near(middle.width, 107.0, 'the middle’s width');
      near(middle.height, 59.8, 'the middle’s height', 1);
      final mark = tester.getRect(find.descendant(of: find.byKey(const ValueKey('book-bar-book')), matching: find.byType(FittedBox)));
      near(mark.left, 35.3, 'the mark’s left');
      near(mark.width, 7.9, 'the mark, squeezed', 1);
      final name = tester.getRect(find.text('Example project'));
      near(name.left, 48.0, 'the name’s left', 1);
      near(name.width, 55.6, 'the name, cut', 1.5);
      final count = tester.getRect(find.text('3 of 3'));
      near(count.left, 108.4, 'the count’s left', 1);
      near(count.width, 20.3, 'the count, wrapped', 1.5);
      near(count.height, 50.3, 'its three lines', 1);
      debugDisableShadows = true;
    });

    testWidgets('at a phone’s width', (tester) async {
      final place = bookOf(ProbeLibrary.notes, 'Trees')!;
      await pumpView(tester, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [BookBar(place: place, open: (_) {}), BookFoot(place: place, open: (_) {})]));
      final web = Measured.load('page-390', root: 'foot');
      // The bar, from its own corner (the page's is the second thing its stylesheet's class names).
      final webBar = Offset(web.rect('bar', 1)[0], web.rect('bar', 1)[1]);
      final bar = tester.getRect(find.byType(BookBar)).topLeft;
      held(tester, web, 'bar', 1, find.byType(BookBar), from: bar, webFrom: webBar);
      held(tester, web, 'ends', 0, find.byKey(const ValueKey('book-bar-prev')), from: bar, webFrom: webBar);
      held(tester, web, 'middle', 0, find.byKey(const ValueKey('book-bar-book')), from: bar, webFrom: webBar);
      held(tester, web, 'ends', 1, find.byKey(const ValueKey('book-bar-next')), from: bar, webFrom: webBar);
      held(tester, web, 'bookTitle', 0, find.text('Field guide'), from: bar, webFrom: webBar);
      held(tester, web, 'count', 0, find.text('2 of 5'), from: bar, webFrom: webBar);
      // The foot, from its rule's corner: its margin is over that.
      final foot = tester.getRect(find.byKey(const ValueKey('book-foot-prev'))).topLeft;
      final webFoot = Offset(web.rect('steps', 2)[0], web.rect('steps', 2)[1]);
      held(tester, web, 'steps', 2, find.byKey(const ValueKey('book-foot-prev')), from: foot, webFrom: webFoot);
      held(tester, web, 'steps', 3, find.byKey(const ValueKey('book-foot-next')), from: foot, webFrom: webFoot);
      held(tester, web, 'stepTitles', 0, find.descendant(of: find.byType(BookFoot), matching: find.text('Introduction')), from: foot, webFrom: webFoot);
      held(tester, web, 'stepTitles', 1, find.descendant(of: find.byType(BookFoot), matching: find.text('Oaks')), from: foot, webFrom: webFoot);
      // From the foot's margin box to its last pixel: 17.85 over the rule, and 109.17 of rule, steps and room.
      expect(tester.getSize(find.byType(BookFoot)).height, closeTo(17.85 + web.rect('foot')[3], 0.5));
      expect(tester.getRect(find.byKey(const ValueKey('book-foot-prev'))).left, closeTo(web.rect('steps', 2)[0] + web.origin.dx, 0.5));
      await done(tester);
    });
  });

  group('a journal', () {
    testWidgets('at a phone’s width, to half a pixel', (tester) async {
      await pumpView(tester, diary());
      final web = Measured.load('journal-390', root: 'journal');
      held(tester, web, 'journal', 0, find.byType(JournalView));
      held(tester, web, 'actions', 0, find.byKey(const ValueKey('journal-new-entry')));
      for (final (i, key) in ['2026-10', '2026-09', '2026-08'].indexed) {
        held(tester, web, 'months', i, find.byKey(ValueKey('journal-month:$key')));
      }
      held(tester, web, 'months', 3, find.byKey(const ValueKey('journal-unwritten')));
      for (final (i, entry) in ProbeLibrary.entries.take(5).indexed) {
        final row = find.byKey(ValueKey('journal-entry:${entryTitleOf(entry)}'));
        held(tester, web, 'entries', i, row);
        held(tester, web, 'dates', i, find.descendant(of: row, matching: find.text(web.text('dates', i))).first);
        held(tester, web, 'weekdays', i, find.descendant(of: row, matching: find.text(web.text('weekdays', i))));
      }
      held(tester, web, 'folded', 0, find.byKey(const ValueKey('journal-folded:2026-07')));
      held(tester, web, 'folded', 1, find.byKey(const ValueKey('journal-folded:2026-06')));
      held(tester, web, 'plannedTitle', 0, find.byKey(const ValueKey('journal-planned:Packing list')));
      await done(tester);
    });

    testWidgets('with New entry’s choice open', (tester) async {
      await pumpView(tester, diary());
      await press(tester, 'New entry');
      await settle(tester);
      final web = Measured.load('journal-choose-390', root: 'journal');
      held(tester, web, 'choose', 0, find.byKey(const ValueKey('journal-choose')));
      held(tester, web, 'chooseTitle', 0, find.ancestor(of: find.text('START THE ENTRY WITH'), matching: find.byType(CssLines)).first);
      for (final (i, id) in ['usual', 'time', 'morning', 'todos', 'empty'].indexed) {
        held(tester, web, 'start', i, find.byKey(ValueKey('journal-start:$id')));
      }
      held(tester, web, 'usual', 0, find.ancestor(of: find.text('Usual'), matching: find.byType(DecoratedBox)).first);
      held(tester, web, 'months', 0, find.byKey(const ValueKey('journal-month:2026-10')));
      await done(tester);
    });

    testWidgets('on a wide window a row is one line', (tester) async {
      await pumpView(tester, diary(), size: desk);
      final web = Measured.load('journal-1280', root: 'journal');
      held(tester, web, 'journal', 0, find.byType(JournalView));
      for (final (i, entry) in ProbeLibrary.entries.take(5).indexed) {
        final row = find.byKey(ValueKey('journal-entry:${entryTitleOf(entry)}'));
        held(tester, web, 'entries', i, row);
        // The day's figures stand half a pixel lower here: the two engines put the baseline the day and its weekday
        // share a fraction apart.
        held(tester, web, 'dates', i, find.descendant(of: row, matching: find.text(web.text('dates', i))).first, by: 0.6);
        held(tester, web, 'weekdays', i, find.descendant(of: row, matching: find.text(web.text('weekdays', i))));
      }
      await done(tester);
    });
  });

  group('the New notebook sheet', () {
    // The page was measured in a browser, where the sheet is a window in the middle of the screen (`data-platform=
    // 'desktop'`), 289.84 wide inside its padding at this width; so it is here.
    Future<void> sheet(WidgetTester tester, {String theme = 'light'}) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pumpPage(
        tester,
        BackScope(child: NewBookSheet(open: true, onClose: () {}, titles: const ['Introduction', 'Trees', 'Oaks', 'Route map', 'Rivers', 'Fix the login loop', 'Write the docs'], isCanvas: (t) => t == 'Route map', onCreate: (_, _) {}, onCreateJournal: (_, _, _) {}, clock: () => probeNow)),
        size: const Size(390, 1400),
        theme: theme,
      );
      await settle(tester);
    }

    testWidgets('with three pages chosen, from its title’s corner', (tester) async {
      await sheet(tester);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('book-name')), matching: find.byType(EditableText)), 'Cabin trip');
      for (final title in ['Trees', 'Route map', 'Rivers']) {
        await press(tester, title);
      }
      final web = Measured.load('sheet-pages-390', root: 'title');
      // The probe's Chromium draws `--app-line` (1.5px) one pixel thick: it is asked for two device pixels to the
      // logical one and snaps a border as if it had one. A phone draws it 1.5 (or 1.33 at three), as this does. So
      // what has such a line in it (the name's rule, the choice's ring) is half a pixel larger a line here, and each
      // block under them is held from its own corner.
      void at(String name, int i, Finder finder, {required Finder corner, required String webCorner, int webAt = 0, double by = 0.5}) =>
          held(tester, web, name, i, finder, from: tester.getRect(corner).topLeft, webFrom: Offset(web.rect(webCorner, webAt)[0], web.rect(webCorner, webAt)[1]), by: by);
      final title = find.byType(SheetTitle);
      at('title', 0, title, corner: title, webCorner: 'title');
      at('fields', 0, find.byKey(const ValueKey('book-name')), corner: title, webCorner: 'title', by: 0.6);
      final kind = find.byKey(const ValueKey('book-kind'));
      at('choice', 0, kind, corner: kind, webCorner: 'choice', by: 1.1);
      at('radios', 0, find.byKey(const ValueKey('book-kind:notebook')), corner: kind, webCorner: 'choice', by: 0.6);
      at('radios', 1, find.byKey(const ValueKey('book-kind:journal')), corner: kind, webCorner: 'choice', by: 0.6);
      final pages = find.byKey(const ValueKey('book-pages'));
      at('pages', 0, pages, corner: pages, webCorner: 'pages');
      at('page', 2, find.byKey(const ValueKey('book-page:Trees')), corner: pages, webCorner: 'pages');
      at('page', 3, find.byKey(const ValueKey('book-page:Route map')), corner: pages, webCorner: 'pages');
      at('page', 4, find.byKey(const ValueKey('book-page:Rivers')), corner: pages, webCorner: 'pages');
      at('pageTitle', 0, find.descendant(of: find.byKey(const ValueKey('book-page:Trees')), matching: find.byType(Expanded)).first, corner: pages, webCorner: 'pages');
      at('grips', 1, find.byKey(const ValueKey('book-page-grip:Trees')), corner: pages, webCorner: 'pages');
      at('fields', 1, find.byKey(const ValueKey('book-find')), corner: pages, webCorner: 'pages', by: 0.6);
      final found = find.byKey(const ValueKey('book-found'));
      tester.state<ScrollableState>(find.descendant(of: found, matching: find.byType(Scrollable))).position.jumpTo(0);
      await tester.pump();
      at('found', 0, found, corner: found, webCorner: 'found');
      for (final (i, title) in ['Introduction', 'Trees', 'Oaks'].indexed) {
        at('pick', i, find.byKey(ValueKey('book-pick:$title')), corner: found, webCorner: 'found');
        at('pickMark', i, find.descendant(of: find.byKey(ValueKey('book-pick:$title')), matching: find.byType(PickMark)), corner: found, webCorner: 'found');
      }
      at('rows', 0, find.byKey(const ValueKey('book-make')), corner: found, webCorner: 'found');
      await done(tester);
    });

    testWidgets('with Journal chosen, and your own template', (tester) async {
      core.preferences.startWithoutStorage();
      await sheet(tester);
      await tester.enterText(find.descendant(of: find.byKey(const ValueKey('book-name')), matching: find.byType(EditableText)), 'Cabin trip');
      await press(tester, 'Journal');
      final web = Measured.load('sheet-journal-390', root: 'sheet');
      // From the first row of the choice, which the page's sheet has at the same place under its name.
      Offset corner(Measured m) => Offset(m.rect('rows')[0], m.rect('rows')[1]);
      var from = tester.getRect(find.byKey(const ValueKey('template:stamped'))).topLeft;
      void at(Measured m, String name, int i, Finder finder) => held(tester, m, name, i, finder, from: from, webFrom: corner(m));
      for (final (i, id) in ['stamped', 'time', 'morning', 'todos', 'own'].indexed) {
        at(web, 'rows', i, find.byKey(ValueKey('template:$id')));
      }
      at(web, 'headings', 0, find.text('EACH ENTRY STARTS WITH'));
      at(web, 'preview', 0, find.byKey(const ValueKey('template-preview')));
      at(web, 'where', 0, find.text('Where you are, with the map, at the top.'));
      at(web, 'previewPage', 0, find.byKey(const ValueKey('template-page')));
      at(web, 'groups', 1, find.byKey(const ValueKey('template-place')));
      at(web, 'rows', 6, find.byKey(const ValueKey('book-make')));
      await tester.tap(find.byKey(const ValueKey('template:own')));
      await tester.pump();
      final own = Measured.load('sheet-own-390', root: 'sheet');
      from = tester.getRect(find.byKey(const ValueKey('template-box'))).topLeft;
      Offset box(Measured m) => Offset(m.rect('box')[0], m.rect('box')[1]);
      void under(String name, int i, Finder finder) => held(tester, own, name, i, finder, from: from, webFrom: box(own));
      under('box', 0, find.byKey(const ValueKey('template-box')));
      // A chip's ring is `--app-line` too: half a pixel a side wider here (see the sheet's first case).
      for (final (i, chip) in ['{{date}}', '{{time}}', '{{weekday}}'].indexed) {
        held(tester, own, 'chip', i, find.byKey(ValueKey('template-chip:$chip')), from: from, webFrom: box(own), by: 1.1);
      }
      under('rule', 0, find.textContaining('Words inside a format'));
      under('preview', 0, find.byKey(const ValueKey('template-preview')));
      await done(tester);
    });
  });

  group('pictures, beside the page’s', () {
    for (final theme in ['light', 'dark']) {
      testWidgets('the index, $theme', (tester) async {
        await pumpView(tester, fieldGuide(), theme: theme);
        await shot(tester, 'index-390-$theme');
      });
      testWidgets('Add a page, $theme', (tester) async {
        await pumpView(tester, fieldGuide(), theme: theme);
        await press(tester, 'Add a page');
        await tester.enterText(find.byKey(const ValueKey('book-page-title')), 'Rivers of the north');
        await shot(tester, 'add-page-390-$theme');
      });
      testWidgets('Add a note you have, $theme', (tester) async {
        await pumpView(tester, fieldGuide(), theme: theme);
        await press(tester, 'Add a note you have');
        await press(tester, 'Rivers');
        await shot(tester, 'add-existing-390-$theme');
      });
      testWidgets('reading straight through, $theme', (tester) async {
        await pumpView(tester, fieldGuide(), theme: theme);
        await press(tester, 'Read straight through');
        await shot(tester, 'reading-390-$theme');
      });
      testWidgets('tickets, $theme', (tester) async {
        await pumpView(tester, ghostMd(), theme: theme);
        await press(tester, 'New ticket');
        await tester.enterText(find.byKey(const ValueKey('book-ticket-title')), 'Session cookie expires');
        await shot(tester, 'new-ticket-390-$theme');
      });
      testWidgets('the bar and the foot, $theme', (tester) async {
        final place = bookOf(ProbeLibrary.notes, 'Trees')!;
        final entry = inTimeOrder(bookOf(ProbeLibrary.notes, '2026-10-07 21.40')!, ProbeLibrary.titled);
        await pumpView(
          tester,
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [BookBar(place: place, open: (_) {}), BookFoot(place: place, open: (_) {}), BookBar(place: entry, open: (_) {}), BookFoot(place: entry, open: (_) {})]),
          theme: theme,
        );
        await shot(tester, 'page-390-$theme');
      });
      testWidgets('a journal, $theme', (tester) async {
        await pumpView(tester, diary(), theme: theme);
        await shot(tester, 'journal-390-$theme');
      });
      testWidgets('a journal’s choice, $theme', (tester) async {
        await pumpView(tester, diary(), theme: theme);
        await press(tester, 'New entry');
        await shot(tester, 'journal-choose-390-$theme');
      });
      testWidgets('the sheet, $theme', (tester) async {
        await pumpPage(
          tester,
          BackScope(child: NewBookSheet(open: true, onClose: () {}, titles: const ['Introduction', 'Trees', 'Oaks', 'Route map', 'Rivers'], isCanvas: (t) => t == 'Route map', onCreate: (_, _) {}, onCreateJournal: (_, _, _) {}, clock: () => probeNow)),
          size: const Size(390, 1100),
          theme: theme,
        );
        await settle(tester);
        for (final title in ['Trees', 'Route map', 'Rivers']) {
          await press(tester, title);
        }
        await shot(tester, 'sheet-pages-390-$theme');
      });
      testWidgets('the sheet on Journal, $theme', (tester) async {
        await pumpPage(
          tester,
          BackScope(child: NewBookSheet(open: true, kind: NewBookKind.journal, onClose: () {}, titles: const [], onCreate: (_, _) {}, onCreateJournal: (_, _, _) {}, clock: () => probeNow)),
          size: const Size(390, 1500),
          theme: theme,
        );
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('template:own')));
        await shot(tester, 'sheet-own-390-$theme');
      });
    }
    testWidgets('the index and a journal on a wide window', (tester) async {
      await pumpView(tester, Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [fieldGuide(), diary()]), size: const Size(1280, 1500));
      await shot(tester, 'wide-1280-light');
    });
  });

  test('the sizes the page was measured at', () => expect([phone, desk], [const Size(390, 844), const Size(1280, 800)]));
}

/// An entry's name, from its note.
String entryTitleOf(Note entry) => noteTitle(entry.body);
