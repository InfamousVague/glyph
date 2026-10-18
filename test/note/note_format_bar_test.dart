// Where the note's screen stands simple mode's Format bar (lib/note/note_screen.dart, lib/note/format_bar.dart,
// GHST-103): nowhere in advanced; on a phone a strip above the soft keyboard the page ends above; on a wide window
// with the keyboard down a pill at the foot to the dock's start; on an iPhone the keyboard bar's own row, beside
// Done.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/iphone_page.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/editor/band/style_items.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/note/format_bar.dart';
import 'package:ghost_md/shell/page_dock.dart';
import 'package:glacier/glacier.dart';

import '../shell/dock_support.dart';
import '../support/render.dart';
import 'support.dart';

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  var made = 0;
  Future<Note> seeded(WidgetTester tester, NoteWorld world, String body) async => (await tester.runAsync(() => seedNote(world, 'format${made += 1}', body)))!;

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  const six = <String>['Bold', 'Italic', 'Heading', 'List', 'To-do', 'Link'];

  void expectSix(WidgetTester tester, {required bool shown}) {
    for (final word in six) {
      expect(find.bySemanticsLabel(word), shown ? findsOneWidget : findsNothing, reason: word);
    }
  }

  void keyboard(WidgetTester tester, double height) => tester.view.viewInsets = FakeViewPadding(bottom: height * tester.view.devicePixelRatio);

  testWidgets('advanced has no Format bar, keyboard up or down, narrow or wide', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, '# Plan\n\nWords.'), dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expectSix(tester, shown: false);
    keyboard(tester, 300);
    await settle(tester);
    expectSix(tester, shown: false);
    expect(find.byType(FormatBar), findsNothing);
    await closeNote(tester);
    await done(tester);

    await pumpNote(tester, world, await seeded(tester, world, '# Plan\n\nWords.'), size: const Size(1200, 800), dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(find.byType(FormatBar), findsNothing);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('on a phone in simple mode: nothing with the keyboard down, a strip just above it while it is up, the page ending above the strip', (tester) async {
    final world = NoteWorld();
    world.prefs.value = world.prefs.value.choosing('simple');
    final screen = await pumpNote(tester, world, await seeded(tester, world, 'buy milk'), dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(find.byType(FormatBar), findsNothing);

    keyboard(tester, 300);
    await settle(tester);
    expectSix(tester, shown: true);
    final strip = tester.getRect(find.byKey(FormatBar.stripKey));
    // Pinned on the keyboard's top, across the screen, the bar's height.
    expect(strip.bottom, closeTo(844 - 300, 0.01));
    expect(strip.height, closeTo(formatBarHeight, 0.01));
    expect(strip.left, 0);
    expect(strip.right, 390);
    // The dock has stepped aside, as it does for the keyboard, so the strip is the one thing over the keys.
    expect(dockShown(tester), isFalse);
    expect(find.byKey(FormatBar.pillKey), findsNothing);

    // A press edits the note, as the Style page's row would. (Whether the editor keeps its focus is not asked here:
    // the editor takes no focus in this rig even when asked outright; the bar's rings cannot ask for it, which
    // test/editor/band/format_bar_test.dart reads.)
    final view = screen.view!;
    view.dispatch(TransactionSpec(selection: EditorSelection.single(4, 8)));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('Bold'));
    await settle(tester);
    expect(view.state.doc.toString(), 'buy **milk**');

    tester.view.resetViewInsets();
    await settle(tester);
    expect(find.byType(FormatBar), findsNothing);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('on a wide window in simple mode: a pill at the foot to the dock’s start, and the strip instead while the keyboard is up', (tester) async {
    final world = NoteWorld();
    world.prefs.value = world.prefs.value.choosing('simple');
    const window = Size(1200, 800);
    await pumpNote(tester, world, await seeded(tester, world, '# Plan\n\nWords.'), size: window, dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expectSix(tester, shown: true);
    final pill = find.byKey(FormatBar.pillKey);
    expect(pill, findsOneWidget);
    expect(find.byKey(FormatBar.stripKey), findsNothing);
    final dock = tester.getRect(find.byType(PageDock));
    final rect = tester.getRect(pill);
    final t = GlacierTheme.of(tester.element(pill));
    // On the dock's own step up from the bottom, and to its start with a step between.
    expect(rect.bottom, closeTo(dock.bottom, 0.01));
    expect(rect.right, closeTo(dock.left - t.space(2), 0.01));
    expect(rect.height, closeTo(t.len('app-ring') + 2 * (t.space(2) + t.len('glacier-hairline')), 0.01));

    keyboard(tester, 300);
    await settle(tester);
    expect(find.byKey(FormatBar.pillKey), findsNothing);
    expect(find.byKey(FormatBar.stripKey), findsOneWidget);
    tester.view.resetViewInsets();
    await settle(tester);
    expect(find.byKey(FormatBar.pillKey), findsOneWidget);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('a note that cannot be written has no bar', (tester) async {
    final world = NoteWorld();
    world.prefs.value = world.prefs.value.choosing('simple');
    await pumpNote(tester, world, await seeded(tester, world, 'buy milk'), size: const Size(1200, 800), readOnly: true, dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(find.byType(FormatBar), findsNothing);
    await closeNote(tester);
    await done(tester);
  });

  testWidgets('on an iPhone the keyboard’s bar carries the six at its start, Done at its end, and no strip stands in the page', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final world = NoteWorld();
    world.prefs.value = world.prefs.value.choosing('simple');
    // The screen alone under the app (which puts the iPhone's page over everything, lib/app/ghost_app.dart): the
    // shell's own doings on iOS are not what is asked here.
    await pumpNote(tester, world, await seeded(tester, world, 'buy milk'), size: const Size(402, 874), bar: false, dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(find.byType(IPhoneKeyboardBar), findsNothing);

    keyboard(tester, 335);
    await settle(tester);
    final bar = find.byType(IPhoneKeyboardBar);
    expect(bar, findsOneWidget);
    expect(find.descendant(of: bar, matching: find.byKey(FormatBar.rowKey)), findsOneWidget);
    expect(find.byKey(FormatBar.stripKey), findsNothing);
    expectSix(tester, shown: true);
    // The six at the start, Done at the end, on one row.
    final bold = tester.getRect(find.byKey(FormatBar.keyOf(formatBarTools().first)));
    final doneButton = tester.getRect(find.byKey(IPhoneKeyboardBar.doneKey));
    final row = tester.getRect(bar);
    expect(bold.left, lessThan(doneButton.left));
    expect(doneButton.right, closeTo(row.right, 0.01));
    expect(bold.top, greaterThanOrEqualTo(row.top));
    expect(bold.bottom, lessThanOrEqualTo(row.bottom + 0.01));

    // The keyboard gone, the bar and the six go with it.
    tester.view.resetViewInsets();
    await settle(tester);
    expect(find.byType(IPhoneKeyboardBar), findsNothing);
    expectSix(tester, shown: false);
    await closeNote(tester);
    await done(tester);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('switching to simple while a note is open brings the bar, and back to advanced takes it', (tester) async {
    final world = NoteWorld();
    await pumpNote(tester, world, await seeded(tester, world, 'buy milk'), size: const Size(1200, 800), dock: PageDockSeam(claude: fakeClaude([])));
    await settle(tester);
    expect(find.byType(FormatBar), findsNothing);
    world.prefs.value = world.prefs.value.choosing('simple');
    await settle(tester);
    expect(find.byKey(FormatBar.pillKey), findsOneWidget);
    world.prefs.value = world.prefs.value.choosing('advanced');
    await settle(tester);
    expect(find.byType(FormatBar), findsNothing);
    await closeNote(tester);
    await done(tester);
  });
}
