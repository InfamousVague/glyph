// The + beside the line's list (lib/editor/plus/add_list.dart): its rows, where it goes against the +'s row (never
// over it, and on one side of the Fold's crease), what closes it and what does not, the page behind More, the step
// that asks which note, and that a press on it never takes the editor's focus. The cases of
// tauri/src/app/editor/AddList.test.tsx, one for one: those about where it goes are asked of `placeList` with the
// sizes that file gave jsdom (a 256-wide card of 44px rows, More held at its foot), and its real sizes are held to
// the page in plus_reference_test.dart.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/plus/plus.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:glacier/glacier.dart';

import 'support.dart';

/// How much of the card is not the rows that scroll: More held at its foot, and the padding round it.
const double held = 44 + 4;

/// The +'s row, where the list is placed from: the gutter's width and a row's height.
Rect rowAt(double top, [double left = 0, double width = 22.4, double height = 27]) => Rect.fromLTWH(left, top, width, height);

/// Where a card of `rows` rows goes on a screen `width` by `height`.
ListPlace? placed(Rect row, {double width = 412, double height = 915, int rows = 8, double statusBar = 0, bool opened = false, double? paneRight}) =>
    placeList(row: row, viewTop: 0, viewBottom: height, statusBar: statusBar, natural: rows * 44.0 + 8, chrome: held, full: 256, window: width, opened: opened, paneRight: paneRight);

late EditorView view;
late PlusController plus;
late DateTime now;
int pictures = 0, places = 0, videos = 0;

AddConfig config({bool picture = true, bool place = true, bool video = false, bool titles = true, bool localOnly = false}) => AddConfig(
  onPicture: picture ? () => pictures += 1 : null,
  onPlace: place ? () => places += 1 : null,
  onVideo: video ? () => videos += 1 : null,
  titles: titles ? () => const <String>['Lisbon', 'Lisbon, day two', 'Porto'] : null,
  canvases: () => const <String>['Cabin weekend'],
  own: 'Lisbon, day two',
  localOnly: localOnly,
  boards: true,
  databases: true,
  tickets: true,
  blanks: true,
);

/// The editor over `Lunch` and an empty line, its + shown, and the list opened the way `by` says.
Future<void> open(WidgetTester tester, {AddConfig? with_, PlusBy? by = PlusBy.touch, String doc = 'Lunch\n', int? caret, Size size = const Size(390, 844), bool coarse = true}) async {
  pictures = places = videos = 0;
  now = DateTime(2026, 9, 28, 14, 5);
  plus = PlusController();
  view = editorOf(doc, plus.extension, caret: caret);
  await pumpPlus(tester, view, controller: plus, config: with_ ?? config(), clock: () => now, coarse: coarse, size: size);
  await tester.pump(settle);
  await tester.pump();
  if (by != null) await reopen(tester, by);
}

Future<void> reopen(WidgetTester tester, [PlusBy by = PlusBy.touch]) async {
  switch (by) {
    case PlusBy.touch:
      await tester.tap(find.byType(PlusButton));
    case PlusBy.pointer:
      await tester.tap(find.byType(PlusButton), kind: PointerDeviceKind.mouse);
    case PlusBy.keyboard:
      plusOf(view).press(PlusBy.keyboard);
    case PlusBy.slash:
      expect(sendKey(view, LogicalKeyboardKey.slash, character: '/'), isTrue);
  }
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

AddListState listOf(WidgetTester tester) => tester.state<AddListState>(find.byType(AddList));
bool get closed => plus.opening == null;
List<String> words(WidgetTester tester) => listOf(tester).words;
Finder rowSaying(String text) => find.ancestor(of: find.text(text), matching: find.byWidgetPredicate((widget) => widget.runtimeType.toString() == '_RowView'));
Finder get scrolling => find.byType(SingleChildScrollView).last;
bool scrolls(String text) => find.descendant(of: scrolling, matching: find.text(text)).evaluate().isNotEmpty;

Future<void> press(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text));
  await tester.tap(find.text(text));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> key(WidgetTester tester, PlusKey key) async {
  plus.keys.current?.call(key);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// The words of the row that is lit.
String? lit(WidgetTester tester) {
  final list = listOf(tester);
  return list.active >= 0 && list.active < list.words.length ? list.words[list.active] : null;
}

const String time = '28 Sept 2026, 14:05';

void main() {
  setUpAll(loadAppFonts);

  group('the list', () {
    plusTest('holds the first page in a browser, less the video, and More', (tester) async {
      await open(tester);
      expect(words(tester), ['A picture', 'A place', time, 'A table', 'A board', 'A database', 'A note', 'A to-do', 'More']);
      expect(find.ancestor(of: find.byType(AddCard), matching: find.byWidgetPredicate((w) => w is Semantics && w.properties.label == 'Add to this note')), findsOneWidget);
    });

    plusTest('holds A video second where the screen adds films, and a press on it is the screen’s', (tester) async {
      await open(tester, with_: config(video: true));
      expect(words(tester).take(3), ['A picture', 'A video', 'A place']);
      await press(tester, 'A video');
      expect(videos, 1);
      expect(closed, isTrue);
    });

    plusTest('holds no row the screen cannot do', (tester) async {
      await open(tester, with_: config(picture: false, place: false, titles: false));
      expect(words(tester).where((row) => !RegExp(r'\d').hasMatch(row)), ['A table', 'A board', 'A database', 'A to-do', 'More']);
    });

    plusTest('holds no row whose block the editor does not draw yet, unless the screen says it does', (tester) async {
      await open(tester, with_: AddConfig(onPicture: () {}));
      expect(words(tester), ['A picture', time, 'A table', 'A to-do', 'More']);
      await press(tester, 'More');
      expect(words(tester), isNot(anyOf(contains('Make this a ticket'), contains('A blank for the AI'), contains('A canvas'))));
      expect(words(tester), containsAll(['A heading', 'A diagram', 'A formula', 'A footnote', 'A tag', 'A counter', 'A sum']));
    });

    plusTest('writes the time its row says, even pressed after the minute has turned and before the row has', (tester) async {
      await open(tester);
      now = DateTime(2026, 9, 28, 14, 5, 59, 900);
      await reopen(tester); // the × closes
      await reopen(tester);
      expect(find.text(time), findsOneWidget);
      // The clock moves on; the row's minute timer has not fired yet.
      now = DateTime(2026, 9, 28, 14, 6, 0, 50);
      await tester.tap(find.text(time));
      await tester.pump();
      expect(view.state.doc.toString(), 'Lunch\n$time');
    });

    plusTest('turns the time row at the minute, and writes what it turns to', (tester) async {
      await open(tester);
      now = DateTime(2026, 9, 28, 14, 5, 59, 900);
      await reopen(tester);
      await reopen(tester);
      now = DateTime(2026, 9, 28, 14, 6, 0, 100);
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('28 Sept 2026, 14:06'), findsOneWidget);
      await tester.tap(find.text('28 Sept 2026, 14:06'));
      await tester.pump();
      expect(view.state.doc.toString(), 'Lunch\n28 Sept 2026, 14:06');
    });

    plusTest('dims the place under Local only, says why, and adds nothing when it is pressed', (tester) async {
      await open(tester, with_: config(localOnly: true));
      expect(find.descendant(of: rowSaying('A place'), matching: find.text('Local only is on.')), findsOneWidget);
      expect(tester.getSemantics(rowSaying('A place')).flagsCollection.isEnabled.toString(), 'Tristate.isFalse');
      await press(tester, 'A place');
      expect(places, 0);
      expect(closed, isFalse);
    });

    plusTest('wears the mark that lets its rows off the app’s tap tick, since each says its own', (tester) async {
      await open(tester);
      final own = tester.widgetList<HapticTarget>(find.ancestor(of: find.byType(AddCard), matching: find.byType(HapticTarget)));
      expect(own.any((target) => target.kind == null), isTrue);
    });

    plusTest('keeps the editor’s focus and caret: its press is taken from the page', (tester) async {
      await open(tester);
      final caret = view.state.selection.main.head;
      final gesture = await tester.startGesture(tester.getCenter(find.text('A table')));
      await tester.pump();
      expect(view.hasFocus, isTrue);
      expect(view.state.selection.main.head, caret);
      expect(find.byType(AddList), findsOneWidget);
      // Nothing of the list holds the keyboard's focus.
      expect(find.descendant(of: find.byType(AddCard), matching: find.byWidgetPredicate((w) => w is Focus && w.focusNode?.hasFocus == true)), findsNothing);
      await gesture.cancel();
    });
  });

  group('where it goes', () {
    test('opens below the +’s row when there is room there', () {
      final at = placed(rowAt(100))!;
      expect(at.y, 100 + 27 + 6);
      expect(at.x, closeTo(22.4, 1e-9));
    });

    test('opens above the row when the keyboard leaves no room below', () {
      final at = placed(rowAt(700))!;
      expect(at.y + 8 * 44 + 8, 700 - 6);
    });

    test('takes the larger side when neither holds it all, over the header when that is above, scrolls, and never covers the row', () {
      final at = placed(rowAt(240), height: 500)!;
      final height = at.cap! + held;
      // Above is 234 - 8 = 226, the header's 60 included, and below 492 - 273 = 219: above is larger, and the list
      // keeps off the row.
      expect(at.y, 8);
      expect(height, 226);
      expect(at.y + height, lessThanOrEqualTo(240 - 6));
    });

    plusTest('keeps More in sight however little room there is: it is held at the foot, and only the rows above it scroll', (tester) async {
      // A phone in split screen with the keyboard up (412 by 360), the + where the editor keeps the caret: above is
      // 164 - 8 = 156 and below 352 - 203 = 149, and seven rows and More (360) fit neither. It takes above, capped
      // at 156, which leaves 108 for the rows that scroll.
      final at = placed(rowAt(170), height: 360)!;
      expect(at.y, 8);
      expect(at.cap, 108);
      // Drawn: More is in the card and not among the rows that scroll; A to-do is.
      await open(tester);
      expect(find.descendant(of: find.byType(AddCard), matching: find.text('More')), findsOneWidget);
      expect(scrolls('More'), isFalse);
      expect(scrolls('A to-do'), isTrue);
      // On More, Back is held at the top the same way.
      await press(tester, 'More');
      expect(scrolls('Back'), isFalse);
      expect(find.descendant(of: find.byType(AddCard), matching: find.text('Back')), findsOneWidget);
    });

    test('fits above whole on the phone with the keyboard up, where the header used to leave it three rows', () {
      // 412 by 579 with the keyboard up, a 32px status bar, the + at 444: above is 444 - 6 - 40 = 398, which holds
      // the 360 it needs.
      final at = placed(rowAt(444), height: 579, statusBar: 32)!;
      expect(at.y, 444 - 6 - 360);
      expect(at.cap, isNull);
    });

    test('goes over the header and the tabs when it opens above, as far as the status bar', () {
      // 412 by 520, the + at 299: above is 299 - 6 - 40 = 253 and below 512 - 332 = 180.
      final at = placed(rowAt(299), height: 520, statusBar: 32)!;
      expect(at.y, 40);
      expect(at.cap! + held, 253);
    });

    test('never goes under a taller inset', () {
      // 1280 by 400, an inset of 44px, the + at 330: above is 330 - 6 - 52 = 272 and below 392 - 363 = 29.
      final at = placed(rowAt(330), width: 1280, height: 400, statusBar: 44)!;
      expect(at.y, 52);
      expect(at.cap! + held, 272);
    });

    test('keeps to one side of the opened Fold’s crease: at the text when it fits before it', () {
      final at = placed(rowAt(200, 0, 24.5), width: 880, height: 790, opened: true)!;
      expect((at.x, at.width), (24.5, 256.0));
    });

    test('starts past the crease when the docked sidebar leaves too little before it', () {
      expect(placed(rowAt(200, 300, 24.5), width: 880, height: 790, opened: true)!.x, 456);
    });

    test('crosses it only when neither side has room', () {
      expect(placed(rowAt(200, 375.5, 24.5), width: 880, height: 790, opened: true, paneRight: 600)!.x, 400);
    });

    plusTest('is drawn where those sums put it: under the +’s row, at the text’s edge', (tester) async {
      await open(tester);
      final row = tester.getRect(find.byType(PlusButton));
      final card = listOf(tester).cardRect!;
      expect(card.top, closeTo(row.bottom + 6, 0.01));
      expect(card.left, closeTo(row.right, 0.01));
      expect(card.width, closeTo(256, 0.001));
    });
  });

  group('what closes it', () {
    plusTest('a row chosen, first, and then the row does what it says', (tester) async {
      await open(tester);
      await press(tester, 'A table');
      expect(closed, isTrue);
      expect(find.byType(AddList), findsNothing);
      expect(view.state.doc.toString(), 'Lunch\n\n| Column | Column |\n| --- | --- |\n| Cell | Cell |');
      expect(plusOpen(view), isFalse);
    });

    plusTest('a press outside it, a wheel outside it, the back gesture, and Escape', (tester) async {
      await open(tester);
      await tester.tapAt(const Offset(350, 700));
      await tester.pump();
      expect(closed, isTrue);
      await reopen(tester);
      expect(closed, isFalse);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(350, 700)));
      await tester.sendEventToBinding(mouse.scroll(const Offset(0, 20)));
      await tester.pump();
      expect(closed, isTrue);
      await reopen(tester);
      expect(closed, isFalse);
      expect(BackScope.of(tester.element(find.byType(AddList))).goBack(), isTrue);
      await tester.pump();
      expect(closed, isTrue);
      await reopen(tester);
      await key(tester, PlusKey.escape);
      expect(closed, isTrue);
    });

    plusTest('not a press on the + itself, which is the ×’s to answer', (tester) async {
      await open(tester);
      final gesture = await tester.startGesture(tester.getCenter(find.byType(PlusButton)));
      await tester.pump();
      expect(closed, isFalse);
      // Let go, it is the ×: the list closes by its own press.
      await gesture.up();
      await tester.pump();
      expect(closed, isTrue);
    });

    plusTest('not a scroll: the keyboard rising scrolls the note, and the list follows the + instead', (tester) async {
      // An empty line in the middle of a long note, scrolled into view.
      final before = '${List<String>.generate(60, (i) => 'Line $i').join('\n')}\n';
      await open(tester, doc: '$before\n${List<String>.generate(60, (i) => 'More $i').join('\n')}', caret: before.length, by: null);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
      scroll.jumpTo(1300);
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byType(PlusButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(closed, isFalse);
      final was = listOf(tester).cardRect!;
      scroll.jumpTo(1400);
      await tester.pump();
      await tester.pump();
      expect(closed, isFalse);
      final row = tester.getRect(find.byType(PlusButton));
      final card = listOf(tester).cardRect!;
      expect(card.top, closeTo(was.top - 100, 0.01));
      expect(card.top, closeTo(row.bottom + 6, 0.01));
      // Once the + has left the screen, it closes.
      scroll.jumpTo(0);
      await tester.pump();
      await tester.pump();
      expect(closed, isTrue);
    });

    plusTest('not a scroll of its own rows, which keep where they are scrolled to', (tester) async {
      await open(tester, doc: '${List<String>.generate(14, (i) => 'Line ${i + 1}').join('\n')}\n');
      final list = listOf(tester);
      final was = list.cardRect!;
      expect(tester.renderObject<RenderAddCard>(find.byType(AddCard)).cap, isNotNull);
      await tester.drag(find.text('A table'), const Offset(0, -30));
      await tester.pump();
      await tester.pump();
      expect(closed, isFalse);
      expect(tester.state<ScrollableState>(find.descendant(of: scrolling, matching: find.byType(Scrollable))).position.pixels, greaterThan(0));
      expect(list.cardRect, was);
    });
  });

  group('driven from the editor’s keys', () {
    plusTest('lights a row and moves it, names it to the editor, and chooses it with Enter', (tester) async {
      await open(tester, by: PlusBy.pointer, coarse: false);
      expect(lit(tester), 'A picture');
      expect(plusMenuOf(view.state)?.active, 'add-picture');
      await key(tester, PlusKey.down);
      await key(tester, PlusKey.down);
      expect(lit(tester), time);
      expect(plusMenuOf(view.state)?.active, 'add-time');
      await key(tester, PlusKey.up);
      expect(lit(tester), 'A place');
      await key(tester, PlusKey.up);
      await key(tester, PlusKey.up);
      expect(lit(tester), 'More');
      await key(tester, PlusKey.enter);
      expect(words(tester).first, 'Back');
    });

    plusTest('rings the lit row only once a key has moved it, never where the pointer lit it', (tester) async {
      await open(tester, by: PlusBy.pointer, coarse: false);
      expect(lit(tester), 'A picture');
      expect(listOf(tester).keyed, isFalse);
      await key(tester, PlusKey.down);
      expect(listOf(tester).keyed, isTrue);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.moveTo(tester.getCenter(find.text('A table')));
      await tester.pump();
      expect(lit(tester), 'A table');
      expect(listOf(tester).keyed, isFalse);
    });

    plusTest('goes into More with Right, and leaves Right on any other row to the editor', (tester) async {
      await open(tester, by: PlusBy.pointer, coarse: false);
      expect(plus.keys.current!(PlusKey.right), isFalse);
      expect(words(tester), contains('A to-do'));
      await key(tester, PlusKey.up);
      expect(lit(tester), 'More');
      expect(plus.keys.current!(PlusKey.right), isTrue);
      await tester.pump();
      expect(words(tester).first, 'Back');
    });

    plusTest('lights the first row of a page turned to, wherever the keys were on the page before', (tester) async {
      await open(tester, by: PlusBy.pointer, coarse: false);
      await key(tester, PlusKey.up);
      await key(tester, PlusKey.enter);
      expect(lit(tester), 'Back');
      await key(tester, PlusKey.down);
      await key(tester, PlusKey.down);
      await key(tester, PlusKey.left);
      expect(lit(tester), 'A picture');
    });

    plusTest('goes back from More with Left, and closes on Left at the top, leaving the key to the editor', (tester) async {
      await open(tester, by: PlusBy.pointer, coarse: false);
      await press(tester, 'More');
      expect(words(tester), contains('A heading'));
      expect(plus.keys.current!(PlusKey.left), isTrue);
      await tester.pump();
      expect(words(tester), contains('A to-do'));
      // At the top Left is not the list's: the editor's handler closes the list and the caret takes the key.
      expect(sendKey(view, LogicalKeyboardKey.arrowLeft), isFalse);
      await tester.pump();
      expect(closed, isTrue);
    });

    plusTest('through the view’s own key handlers, as the input layer sends them', (tester) async {
      await open(tester, by: PlusBy.pointer, coarse: false);
      expect(sendKey(view, LogicalKeyboardKey.arrowDown), isTrue);
      await tester.pump();
      expect(lit(tester), 'A place');
      expect(sendKey(view, LogicalKeyboardKey.escape), isTrue);
      await tester.pump();
      expect(closed, isTrue);
    });
  });

  group('from the keyboard on the + itself', () {
    plusTest('puts the focus in the list, on its first row', (tester) async {
      await open(tester, by: PlusBy.keyboard);
      await tester.pump();
      final focus = FocusManager.instance.primaryFocus!;
      expect(focus.debugLabel, 'add-list');
      expect(listOf(tester).active, 0);
      // Enter chooses the row the focus is on.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(closed, isTrue);
      expect(view.state.doc.toString(), contains('| Column | Column |'));
    });

    plusTest('goes back from More with Left while the focus is in the list, and not while it is in a field', (tester) async {
      await open(tester, by: PlusBy.keyboard);
      await press(tester, 'More');
      expect(words(tester).first, 'Back');
      await tester.pump();
      expect(await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft), isTrue);
      await tester.pump();
      expect(words(tester), contains('A to-do'));
      expect(closed, isFalse);
      await press(tester, 'A note');
      await tester.pump();
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'add-list field');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(find.byType(EditableText), findsOneWidget);
      expect(listOf(tester).page, 'note');
    });
  });

  group('More', () {
    plusTest('turns the list over to the rest, with Back at its top', (tester) async {
      await open(tester);
      await press(tester, 'More');
      expect(words(tester).take(4), ['Back', 'A heading', 'A bulleted list', 'A numbered list']);
      await press(tester, 'A heading');
      expect(closed, isTrue);
      expect(view.state.doc.toString(), 'Lunch\n## ');
    });

    plusTest('goes back to the first page with Back, and does not close', (tester) async {
      await open(tester);
      await press(tester, 'More');
      await press(tester, 'Back');
      expect(closed, isFalse);
      expect(words(tester), ['A picture', 'A place', time, 'A table', 'A board', 'A database', 'A note', 'A to-do', 'More']);
    });

    plusTest('goes back a page with the phone’s back gesture, and closes from the first page', (tester) async {
      await open(tester);
      await press(tester, 'More');
      final stack = BackScope.of(tester.element(find.byType(AddList)));
      stack.goBack();
      await tester.pump();
      expect(closed, isFalse);
      expect(words(tester), contains('A to-do'));
      stack.goBack();
      await tester.pump();
      expect(closed, isTrue);
    });

    plusTest('opens at its top, whatever the page before was scrolled to', (tester) async {
      await open(tester, doc: '${List<String>.generate(14, (i) => 'Line ${i + 1}').join('\n')}\n');
      final position = tester.state<ScrollableState>(find.descendant(of: scrolling, matching: find.byType(Scrollable))).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pump();
      expect(position.pixels, greaterThan(0));
      await press(tester, 'More');
      expect(tester.state<ScrollableState>(find.descendant(of: scrolling, matching: find.byType(Scrollable))).position.pixels, 0);
    });
  });

  group('A board', () {
    plusTest('opens the two ways to start a board from the first page', (tester) async {
      await open(tester);
      await press(tester, 'A board');
      expect(words(tester), ['Back', 'Fresh columns', 'From your tickets']);
    });

    plusTest('writes a fresh board of columns at once', (tester) async {
      await open(tester);
      await press(tester, 'A board');
      await press(tester, 'Fresh columns');
      expect(closed, isTrue);
      expect(view.state.doc.toString(), contains('```board'));
    });

    plusTest('writes a ticket board from the library, and turns back to the first page with Back', (tester) async {
      await open(tester);
      await press(tester, 'A board');
      await press(tester, 'Back');
      expect(closed, isFalse);
      expect(words(tester), contains('A to-do'));
      await press(tester, 'A board');
      await press(tester, 'From your tickets');
      expect(closed, isTrue);
      expect(view.state.doc.toString(), 'Lunch\n\n```query\nfrom: tickets\nshow: board\n```\n');
    });
  });

  group('A database', () {
    plusTest('opens the ready-made databases from the first page, and one chosen is written and drawn at once', (tester) async {
      await open(tester);
      await press(tester, 'A database');
      expect(words(tester).take(3), ['Back', 'To-dos due this week', 'Overdue to-dos']);
      expect(words(tester).last, 'Write your own');
      await press(tester, 'A ticket board');
      expect(closed, isTrue);
      expect(view.state.doc.toString(), 'Lunch\n\n```query\nfrom: tickets\nshow: board\n```\n');
    });

    plusTest('goes back to the first page with Back and the back gesture', (tester) async {
      await open(tester);
      await press(tester, 'A database');
      await press(tester, 'Back');
      expect(closed, isFalse);
      expect(words(tester), contains('A to-do'));
      await press(tester, 'A database');
      BackScope.of(tester.element(find.byType(AddList))).goBack();
      await tester.pump();
      expect(words(tester), contains('A to-do'));
      expect(closed, isFalse);
    });

    plusTest('offers Make this a ticket only in a note that is not one', (tester) async {
      await open(tester);
      await press(tester, 'More');
      expect(words(tester), contains('Make this a ticket'));
      await key(tester, PlusKey.escape);
      view.dispatch(TransactionSpec(changes: ChangeSpec(from: 0, insert: '---\ntype: ticket\n---\n')));
      view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length)));
      await tester.pump(settle * 2);
      await tester.pump();
      await reopen(tester);
      await press(tester, 'More');
      expect(words(tester), isNot(contains('Make this a ticket')));
    });
  });

  group('the / command palette', () {
    plusTest('opens straight onto a filter field and the whole flat list, steps and all', (tester) async {
      await open(tester, by: PlusBy.slash);
      expect(find.text('Type to filter'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus!.debugLabel, 'add-list field');
      final all = words(tester);
      expect(all, containsAll(['A board', 'A database', 'A diagram', 'A formula']));
      expect(all, isNot(contains('More')));
    });

    plusTest('narrows the list as the filter is typed', (tester) async {
      await open(tester, by: PlusBy.slash);
      await tester.enterText(find.byType(EditableText), 'formula');
      await tester.pump();
      expect(words(tester), ['A formula']);
      await tester.enterText(find.byType(EditableText), 'nothing at all');
      await tester.pump();
      expect(words(tester), isEmpty);
      expect(find.text('Nothing by that name.'), findsOneWidget);
    });

    plusTest('writes the match on Enter, at the caret', (tester) async {
      await open(tester, by: PlusBy.slash);
      await tester.enterText(find.byType(EditableText), 'divider');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(closed, isTrue);
      expect(view.state.doc.toString(), contains('---'));
    });

    plusTest('moves the lit row with Up and Down from the field, and Escape closes it', (tester) async {
      await open(tester, by: PlusBy.slash);
      expect(lit(tester), 'A picture');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(lit(tester), 'A place');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(closed, isTrue);
    });
  });

  group('A note', () {
    plusTest('asks which, by part of its title, and writes the link where the caret was', (tester) async {
      await open(tester);
      await press(tester, 'A note');
      expect(find.text('Type part of its title'), findsOneWidget);
      expect(find.text('Which note?'), findsOneWidget);
      await tester.enterText(find.byType(EditableText), 'lis');
      await tester.pump();
      // Its own title is not offered.
      expect(find.text('Lisbon, day two'), findsNothing);
      await press(tester, 'Lisbon');
      expect(view.state.doc.toString(), 'Lunch\n[[Lisbon]]');
      expect(closed, isTrue);
    });

    plusTest('goes back to the list with its Back, held above the field', (tester) async {
      await open(tester);
      await press(tester, 'A note');
      expect(scrolls('Back'), isFalse);
      await press(tester, 'Back');
      expect(closed, isFalse);
      expect(find.byType(EditableText), findsNothing);
      expect(words(tester), contains('A note'));
    });

    plusTest('says when nothing is called that', (tester) async {
      await open(tester);
      await press(tester, 'A note');
      await tester.enterText(find.byType(EditableText), 'zzz');
      await tester.pump();
      expect(find.text('No note by that name.'), findsOneWidget);
    });

    plusTest('frames a canvas the same way, on a line of its own', (tester) async {
      await open(tester);
      await press(tester, 'More');
      await press(tester, 'A canvas');
      expect(find.text('Which canvas?'), findsOneWidget);
      await press(tester, 'Cabin weekend');
      expect(view.state.doc.toString(), 'Lunch\n\n![[Cabin weekend]]\n');
      expect(closed, isTrue);
    });
  });
}
