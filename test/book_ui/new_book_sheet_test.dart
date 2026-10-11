import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/book/book_view.dart' show CanvasMark;
import 'package:ghost_md/book/journal.dart';
import 'package:ghost_md/book/new_book_sheet.dart';
import 'package:ghost_md/book/template_picker.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/location.dart' show LocateFailure;
import 'package:ghost_md/core/preferences.dart' as core;
import 'package:ghost_md/editor/view/view_mode.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// The New notebook sheet: a name, notes picked as pages in the order they are tapped, moved and left out, and one
/// note made with exactly that index. Closed without making it, nothing is written. And a journal from the same
/// sheet. The web's `book/NewBookSheet.test.tsx`, case for case.

/// What the sheet was last asked to make.
class Made {
  /// Each as "name: page, page".
  final List<String> books = [];

  /// The page the sheet is over, built once; the sheet is handed to it again as the app builds again.
  final ValueNotifier<Widget> host = ValueNotifier<Widget>(const SizedBox.shrink());
  bool up = false;
  final List<(String, String, bool)> journals = [];
  int closed = 0;
  int asked = 0;
  LocateFailure? answer;
}

void main() {
  setUpAll(loadAppFonts);
  setUp(() {
    core.preferences.startWithoutStorage();
    core.preferences.value = core.Preferences.defaults;
  });

  /// The sheet over a page, built again by [again] as the app builds it again.
  Future<void> show(
    WidgetTester tester,
    Made made, {
    bool open = true,
    List<String> titles = const [],
    bool journals = false,
    NewBookKind kind = NewBookKind.notebook,
    bool Function(String title)? isCanvas,
    core.Preferences Function(core.Preferences now)? prefs,
  }) async {
    if (!made.up) {
      made.up = true;
      await pumpPage(
        tester,
        BackScope(
          child: ValueListenableBuilder<Widget>(valueListenable: made.host, builder: (context, sheet, _) => sheet),
        ),
        size: const Size(390, 1600),
      );
      // The device's own choices, made before the sheet is opened: drawing the app put the defaults back.
      if (prefs != null) core.preferences.update(prefs);
    }
    made.host.value = NewBookSheet(
      open: open,
      onClose: () => made.closed += 1,
      titles: titles,
      kind: kind,
      isCanvas: isCanvas,
      onCreate: (title, pages) => made.books.add('$title: ${pages.join(', ')}'),
      // A new function on every build, as the app hands one.
      onCreateJournal: journals ? (title, template, place) => made.journals.add((title, template, place)) : null,
      device: EntryPlaceDevice(
        ask: () async {
          made.asked += 1;
          return made.answer;
        },
      ),
      clock: () => probeNow,
    );
    await tester.pump();
    await settle(tester);
  }

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pump();
    await tester.tap(find.byKey(key));
    await tester.pump();
  }

  /// Words typed into the field whose label says [label].
  Future<void> type(WidgetTester tester, String label, String value) async {
    final field = find.descendant(of: find.byWidgetPredicate((w) => w is SheetField && w.label == label), matching: find.byType(EditableText));
    await tester.enterText(field, value);
    await tester.pump();
  }

  /// The row that makes the book: its words, then a hint that says what it will make.
  SheetRow make(WidgetTester tester) => tester.widget<SheetRow>(find.byKey(const ValueKey('book-make')));
  List<String> pages(WidgetTester tester) => [
    for (final w in tester.widgetList(find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('book-page:')))) (w.key! as ValueKey<String>).value.substring('book-page:'.length),
  ];
  String preview(WidgetTester tester) => [
    if (find.text('Where you are, with the map, at the top.').evaluate().isNotEmpty) 'Where you are, with the map, at the top.',
    if (find.byType(EntryPreviewPage).evaluate().isNotEmpty) tester.widget<EntryPreviewPage>(find.byType(EntryPreviewPage)).words,
    if (find.text('An empty page.').evaluate().isNotEmpty) 'An empty page.',
  ].join('\n');

  group('the New notebook sheet', () {
    testWidgets('is nothing while closed, and makes nothing when closed', (tester) async {
      final made = Made();
      await show(tester, made, open: false, titles: ['A']);
      expect(find.byType(Sheet), findsNothing);
      expect(made.books, isEmpty);
      await away(tester);
    });

    testWidgets('marks a note that is a canvas with the canvas mark, in the list and among the pages', (tester) async {
      await show(tester, Made(), titles: ['Packing', 'Route map'], isCanvas: (t) => t == 'Route map');
      expect(find.byType(CanvasMark), findsOneWidget);
      expect(find.descendant(of: find.byKey(const ValueKey('book-pick:Route map')), matching: find.byType(CanvasMark)), findsOneWidget);
      await press(tester, 'Route map');
      expect(find.byType(CanvasMark), findsNWidgets(2));
      expect(find.descendant(of: find.byKey(const ValueKey('book-page:Route map')), matching: find.byType(CanvasMark)), findsOneWidget);
      await away(tester);
    });

    testWidgets('says where its pages come from, in a notebook’s words, and that it may start empty', (tester) async {
      await show(tester, Made());
      expect(find.textContaining("Pick any now, or add them later from the notebook's index."), findsOneWidget);
      expect(find.text('No notes yet: the notebook starts empty, and pages can be added from its index.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('needs a name before it will make the book', (tester) async {
      final made = Made();
      await show(tester, made);
      expect(make(tester).disabled, isTrue);
      await type(tester, 'Name', 'Trip');
      expect(make(tester).disabled, isFalse);
      await tapKey(tester, const ValueKey('book-make'));
      expect(made.books, ['Trip: ']);
      await away(tester);
    });

    testWidgets('picks pages in the order tapped, finds by name, moves and leaves out, and makes the book with that index', (tester) async {
      final made = Made();
      await show(tester, made, titles: ['Packing', 'Days', 'Who comes', 'Food']);
      await type(tester, 'Name', 'Cabin trip');
      await press(tester, 'Days');
      await press(tester, 'Packing');
      await press(tester, 'Food');
      expect(pages(tester), ['Days', 'Packing', 'Food']);
      // A second tap takes it out; a search narrows the list.
      await press(tester, 'Food');
      expect(pages(tester), ['Days', 'Packing']);
      await type(tester, 'Find a note', 'who');
      expect([for (final w in tester.widgetList<GlacierPressable>(find.byWidgetPredicate((w) => w is GlacierPressable && '${w.key}'.contains('book-pick:')))) w.semanticLabel], ['Who comes']);
      await press(tester, 'Move Packing up');
      expect(pages(tester), ['Packing', 'Days']);
      expect(disabled(tester, 'Move Packing up'), isTrue);
      expect(pages(tester), ['Packing', 'Days']);
      expect(make(tester).disabled, isFalse);
      await tapKey(tester, const ValueKey('book-make'));
      expect(made.books, ['Cabin trip: Packing, Days']);
      expect(made.closed, 1);
      await away(tester);
    });

    testWidgets('closes on a back gesture while open, and holds none while closed', (tester) async {
      final made = Made();
      await show(tester, made);
      final stack = BackScope.of(tester.element(find.byType(NewBookSheet)));
      expect(stack.goBack(), isTrue);
      expect(made.closed, 1);
      await show(tester, made, open: false);
      expect(stack.goBack(), isFalse);
      expect(made.closed, 1);
      await away(tester);
    });

    testWidgets('moves a page dragged by its grip, and leaves one out by its cross', (tester) async {
      final made = Made();
      await show(tester, made, titles: ['Packing', 'Days', 'Food']);
      await type(tester, 'Name', 'Trip');
      for (final title in ['Packing', 'Days', 'Food']) {
        await press(tester, title);
      }
      final row = tester.getSize(find.byKey(const ValueKey('book-page:Packing'))).height;
      // Food, from the bottom to above Packing's middle: the first page.
      await tester.ensureVisible(find.byKey(const ValueKey('book-page-grip:Food')));
      await tester.pump();
      await dragGrip(tester, find.byKey(const ValueKey('book-page-grip:Food')), -2.25 * row);
      expect(pages(tester), ['Food', 'Packing', 'Days']);
      await press(tester, 'Leave Packing out');
      expect(pages(tester), ['Food', 'Days']);
      await tapKey(tester, const ValueKey('book-make'));
      expect(made.books, ['Trip: Food, Days']);
      await away(tester);
    });
  });

  group('a journal from the New notebook sheet', () {
    GlacierSwitch placeSwitch(WidgetTester tester) => tester.widget<GlacierSwitch>(find.byKey(const ValueKey('template-place-switch')));
    Future<void> flip(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const ValueKey('template-place-switch')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('template-place-switch')));
      await settle(tester);
    }

    testWidgets('offers Notebook or Journal only where a journal can be made, and Journal swaps the pages for the template', (tester) async {
      final made = Made();
      await show(tester, made, titles: ['Packing']);
      expect(find.byKey(const ValueKey('book-kind')), findsNothing);
      await show(tester, made, titles: ['Packing'], journals: true);
      expect(
        [for (final kind in NewBookKind.values) (tester.widget<GlacierPressable>(find.byKey(ValueKey('book-kind:${kind.name}'))).semanticLabel, tester.widget<GlacierPressable>(find.byKey(ValueKey('book-kind:${kind.name}'))).toggled)],
        [('Notebook', true), ('Journal', false)],
      );
      await press(tester, 'Journal');
      expect(tester.widget<Sheet>(find.byType(Sheet)).label, 'New journal');
      expect(find.text('New journal'), findsOneWidget);
      expect(find.text('Diary'), findsOneWidget);
      expect(find.byKey(const ValueKey('book-found')), findsNothing);
      expect(find.text('EACH ENTRY STARTS WITH'), findsOneWidget);
      expect(find.text('Make the notebook'), findsNothing);
      await away(tester);
    });

    testWidgets('opens on Journal from the palette, needs a name, and makes the journal with its template and place', (tester) async {
      final made = Made();
      await show(tester, made, journals: true, kind: NewBookKind.journal);
      expect(make(tester).disabled, isTrue);
      expect(find.text('Empty, ready for its first entry.'), findsOneWidget);
      await type(tester, 'Name', 'Diary');
      await tapKey(tester, const ValueKey('template:todos'));
      await tapKey(tester, const ValueKey('book-make'));
      expect(made.journals, [('Diary', entryPresets[3].text, true)]);
      expect(made.closed, 1);
      await away(tester);
    });

    testWidgets('shows the page an entry would start as, following the choice and your own template', (tester) async {
      await show(tester, Made(), journals: true, kind: NewBookKind.journal);
      await type(tester, 'Name', 'Diary');
      expect(preview(tester), matches(RegExp(r'Where you are, with the map, at the top\.[\s\S]*\d\d:\d\d')));
      await tapKey(tester, const ValueKey('template:morning'));
      expect(preview(tester), contains('What is on your mind this morning?'));
      await tapKey(tester, const ValueKey('template:own'));
      final box = find.descendant(of: find.byKey(const ValueKey('template-box')), matching: find.byType(EditableText));
      // Your own starts from what was chosen, to change.
      expect(tester.widget<EditableText>(box).controller.text, entryPresets[2].text);
      await tester.enterText(box, 'Dear {{journal}}, ');
      await tester.pump();
      expect(preview(tester), contains('Dear Diary,'));
      await tester.enterText(box, '');
      await tester.pump();
      expect(preview(tester), contains('An empty page.'));
      expect(find.text('Words inside a format go in square brackets, as in {{date:D MMMM [at] HH:mm}}.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('draws the preview in the view a new note opens in, marks and all where they show', (tester) async {
      await show(tester, Made(), journals: true, kind: NewBookKind.journal);
      // Settings' Show as it comes: the marks are the page's, as the entry will open with them.
      expect(tester.widget<EntryPreviewPage>(find.byType(EntryPreviewPage)).display, NoteView.mixed);
      expect(preview(tester), matches(RegExp(r'\*\*\d\d:\d\d\*\*')));
      await away(tester);
      await show(
        tester,
        Made(),
        journals: true,
        kind: NewBookKind.journal,
        prefs: (now) => now.copyWith(noteView: 'formatted'),
      );
      expect(tester.widget<EntryPreviewPage>(find.byType(EntryPreviewPage)).display, NoteView.formatted);
      await away(tester);
    });

    testWidgets('puts a placeholder in at the caret', (tester) async {
      await show(tester, Made(), journals: true, kind: NewBookKind.journal);
      await tapKey(tester, const ValueKey('template:own'));
      final box = find.descendant(of: find.byKey(const ValueKey('template-box')), matching: find.byType(EditableText));
      await tester.enterText(box, 'At  today.');
      await tester.pump();
      tester.widget<EditableText>(box).controller.selection = const TextSelection.collapsed(offset: 3);
      await tapKey(tester, const ValueKey('template-chip:{{time}}'));
      final controller = tester.widget<EditableText>(box).controller;
      expect(controller.text, 'At {{time}} today.');
      expect(controller.selection.start, 11);
      await away(tester);
    });

    testWidgets('starts its place switch on this device’s Tag new notes alone, and asks from the press it is turned on with', (tester) async {
      final made = Made();
      await show(tester, made, journals: true, kind: NewBookKind.journal, prefs: (now) => now.copyWith(tagNewNotes: false));
      expect(placeSwitch(tester).checked, isFalse);
      expect(preview(tester), isNot(contains('Where you are')));
      await flip(tester);
      expect(made.asked, 1);
      // Off asks nothing.
      await flip(tester);
      expect(made.asked, 1);
      await type(tester, 'Name', 'Log');
      await tapKey(tester, const ValueKey('book-make'));
      expect(made.journals, [('Log', entryPresets[0].text, false)]);
      await away(tester);
    });

    testWidgets('keeps what was chosen while the app draws again with the sheet up, as a sync or the phone’s prompt answered makes it', (tester) async {
      final made = Made();
      await show(tester, made, titles: ['Packing'], journals: true);
      await press(tester, 'Journal');
      await tapKey(tester, const ValueKey('template:morning'));
      await flip(tester);
      // The app's next build hands a new function for the same making.
      await show(tester, made, titles: ['Packing'], journals: true);
      expect(tester.widget<Sheet>(find.byType(Sheet)).label, 'New journal');
      expect(placeSwitch(tester).checked, isFalse);
      expect(preview(tester), contains('What is on your mind this morning?'));
      await away(tester);
    });

    test('says under the switch what keeping a place means here, or why entries made here keep none', () {
      const browser = 'Allow location for this site in the browser’s settings';
      expect(entryPlaceHint(asksName: true), 'Each entry keeps where you are. Its name is asked of OpenStreetMap once.');
      expect(entryPlaceHint(asksName: false), 'Each entry keeps where you are.');
      expect(entryPlaceHint(cannot: LocateFailure.localOnly, asksName: true), 'Local only is on, so entries made here keep no place.');
      expect(entryPlaceHint(cannot: LocateFailure.mac, refused: LocateFailure.refused, asksName: true), 'This Mac can’t say where it is. Entries made on the phone keep theirs.');
      expect(entryPlaceHint(cannot: LocateFailure.unavailable, asksName: true), 'Update Ghost.md to keep where entries were written.');
      expect(entryPlaceHint(cannot: LocateFailure.none, asksName: true), 'This browser can’t say where you are.');
      expect(entryPlaceHint(refused: LocateFailure.blocked, asksName: true, allowWhere: browser), 'Ghost.md wasn’t allowed to know where you are. Allow location for this site in the browser’s settings, then turn this on again.');
      expect(entryPlaceHint(refused: LocateFailure.refused, asksName: true), 'Ghost.md wasn’t allowed to know where you are. Allow location for Ghost.md in the phone’s settings, then turn this on again.');
      expect(entryPlaceHint(asksName: true), isNot(matches(RegExp('[;—–…]'))));
    });

    testWidgets('says a refusal of the press under the switch', (tester) async {
      final made = Made()..answer = LocateFailure.refused;
      await show(tester, made, journals: true, kind: NewBookKind.journal, prefs: (now) => now.copyWith(tagNewNotes: false));
      await flip(tester);
      expect(find.textContaining('Ghost.md wasn’t allowed to know where you are.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('fills the preview with the day as the port says it', (tester) async {
      await show(tester, Made(), journals: true, kind: NewBookKind.journal);
      expect(preview(tester), matches(RegExp(r'(Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday) \d{1,2} [A-Z][a-z]+')));
      await away(tester);
    });
  });
}
