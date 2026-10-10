import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart' hide WorkspaceSheet;
import 'package:ghost_md/notes/floating_card.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/notes/note_peek.dart';
import 'package:ghost_md/notes/notes_drawer.dart';
import 'package:ghost_md/notes/org_mark.dart';
import 'package:ghost_md/notes/tree.dart';
import 'package:ghost_md/sheet/css.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:glacier/glacier.dart';

import '../support/icons.dart';
import '../support/render.dart';
import 'support.dart';

/// The notes drawer and the card it floats in (notes/notes_drawer.dart, notes/floating_card.dart):
/// `notes/NotesDrawer.test.tsx` case for case, the card's own rules, where everything sits against the web page, and
/// the pictures.
void main() {
  setUpAll(loadAppFonts);
  final library = SidebarLibrary.load();

  final card = find.byKey(const ValueKey('floating-card'));
  Finder button(String label) => find.bySemanticsLabel(label);

  late MemoryStored local;
  late WorkspaceStore spaces;
  setUp(() {
    local = MemoryStored();
    spaces = library.store();
  });

  /// The page with the drawer over it, opened and shut by the icon at its corner and by whatever the drawer says.
  Future<List<String>> show(
    WidgetTester tester, {
    bool open = true,
    bool compact = true,
    Set<String>? closed,
    bool trashOpen = false,
    String? activeId,
    VoidCallback? onCommands,
    void Function(String)? onOpen,
    Size size = const Size(390, 844),
    String theme = 'light',
    bool bare = true,
    Widget? under,
  }) async {
    writeCompact(compact, local);
    if (closed != null) writeClosed(closed, local);
    writeTrashOpen(trashOpen, local);
    final said = <String>[];
    var shown = open;
    await pumpPage(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PageUnder(
          onSidebar: () {
            said.add('icon');
            setState(() => shown = !shown);
          },
          children: [
            ?under,
            NotesDrawer(
              open: shown,
              notes: library.notes,
              trashed: library.trashed,
              activeId: activeId,
              workspaces: spaces,
              stored: local,
              onOpen: onOpen ?? (_) {},
              onNew: () => said.add('new'),
              onClose: () {
                said.add('close');
                setState(() => shown = false);
              },
              onCommands: onCommands,
              onSettings: () => said.add('settings'),
              onSpeak: () => said.add('speak'),
              onRestore: (_) {},
              onDestroy: (_) {},
              onEmptyTrash: () => said.add('empty'),
              onOrganization: (id) => said.add('org $id'),
              onTrashNotes: (_) {},
            ),
          ],
        ),
      ),
      size: size,
      theme: theme,
      bare: bare,
    );
    await settle(tester);
    return said;
  }

  group('the notes drawer', () {
    testWidgets('draws nothing while it is shut', (tester) async {
      await show(tester, open: false);
      expect(card, findsNothing);
      expect(tester.getSize(find.byType(NotesDrawer)), Size.zero);
      expect(find.byType(FloatingCard), findsNothing);
      await away(tester);
    });

    testWidgets('is a card at the left that closes on a press outside, but not on its own icon', (tester) async {
      final handle = tester.ensureSemantics();
      final said = await show(tester);
      final node = tester.getSemantics(find.bySemanticsLabel('Your notes').first);
      expect(node.role, SemanticsRole.dialog);
      // `aria-modal="false"`: the page beside it is still read.
      expect(node.flagsCollection.scopesRoute, isFalse);
      expect(find.bySemanticsLabel('Weekend trip'), findsOneWidget);
      expect(tester.getRect(card).left, lessThan(195));
      // A press on the card is not a press outside it.
      await tester.tapAt(tester.getRect(card).center);
      await tester.tap(button('Show each note drawn small'));
      await tester.pump();
      expect(said, isEmpty);
      // Its own icon is left to close it: one press, one close, and it stays shut.
      await tester.tap(find.byKey(const ValueKey('sidebar-icon')));
      await tester.pump();
      expect(said, ['icon']);
      expect(card, findsNothing);
      await tester.tap(find.byKey(const ValueKey('sidebar-icon')));
      await settle(tester);
      expect(card, findsOneWidget);
      // Anywhere else, as the press goes down.
      final press = await tester.startGesture(const Offset(370, 800));
      await tester.pump();
      expect(said.last, 'close');
      expect(card, findsNothing);
      await press.up();
      handle.dispose();
      await away(tester);
    });

    testWidgets('leaves the page beside it live: the press that closes it is still the page’s', (tester) async {
      var pressed = 0;
      final said = await show(
        tester,
        under: Positioned(right: 10, bottom: 10, child: GestureDetector(key: const ValueKey('beside'), behavior: HitTestBehavior.opaque, onTap: () => pressed += 1, child: const SizedBox(width: 40, height: 40))),
      );
      await tester.tap(find.byKey(const ValueKey('beside')));
      await tester.pump();
      expect(said, ['close']);
      expect(pressed, 1);
      await away(tester);
    });

    testWidgets('closes on Escape, on the back gesture, and on its own close, and before it opens the palette', (tester) async {
      var commands = 0;
      final said = await show(tester, onCommands: () => commands += 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(said, ['close']);
      // Shut: Escape and the gesture are nothing of the drawer's.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.binding.handlePopRoute();
      expect(said, ['close']);

      await tester.tap(find.byKey(const ValueKey('sidebar-icon')));
      await settle(tester);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(said, ['close', 'icon', 'close']);

      await tester.tap(find.byKey(const ValueKey('sidebar-icon')));
      await settle(tester);
      await tester.tap(button('Close'));
      await tester.pump();
      expect(said.last, 'close');
      expect(said.where((s) => s == 'close'), hasLength(3));

      await tester.tap(find.byKey(const ValueKey('sidebar-icon')));
      await settle(tester);
      await tester.tap(button('Search and commands'));
      await tester.pump();
      expect(said.where((s) => s == 'close'), hasLength(4));
      expect(commands, 1);
      await away(tester);
    });

    testWidgets('opens the note tapped, and hands the tree’s other presses on', (tester) async {
      final opened = <String>[];
      final said = await show(tester, onOpen: opened.add);
      await tester.tap(find.text('Groceries'));
      expect(opened, ['groceries']);
      await tester.tap(button('New note'));
      await tester.tap(find.text('Speak'));
      await tester.tap(button('Settings'));
      await tester.tap(button('Ghost, organization settings'));
      expect(said, ['new', 'speak', 'settings', 'org o1']);
      await away(tester);
    });

    testWidgets('keeps a sheet it opened as its own: a press in the sheet does not close the drawer under it', (tester) async {
      final said = await show(tester);
      await tester.tap(button('New workspace'));
      await settle(tester);
      expect(find.byType(Sheet), findsOneWidget);
      // On the sheet, well outside the card's box.
      await tester.tap(find.text('COLOUR'));
      await tester.tapAt(const Offset(370, 830));
      await tester.pump();
      expect(said, isEmpty);
      // The back gesture takes the newest thing first: the sheet, then the drawer.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(Sheet), findsNothing);
      expect(card, findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(card, findsNothing);
      // The sheet's scrim, like the sheet, is the drawer's own.
      await tester.tap(find.byKey(const ValueKey('sidebar-icon')));
      await settle(tester);
      await tester.tap(button('Rename, recolour or delete Work'));
      await settle(tester);
      await tester.tapAt(const Offset(370, 200));
      await tester.pump();
      expect(find.byType(Sheet), findsNothing);
      expect(card, findsOneWidget);
      await away(tester);
    });
  });

  group('the card', () {
    testWidgets('is glass: the page blurred behind a tint, a hairline round it, a shadow under it, corners that clip', (tester) async {
      await show(tester);
      final t = tester.element(card).tokens;
      final blur = tester.widget<BackdropFilter>(find.descendant(of: card, matching: find.byType(BackdropFilter)));
      // `--app-float-blur: blur(20px)`
      expect(blur.filter.toString(), ui.ImageFilter.blur(sigmaX: 20, sigmaY: 20).toString());
      final box = tester.widget<DecoratedBox>(find.descendant(of: find.byType(BackdropFilter), matching: find.byType(DecoratedBox)).first).decoration as BoxDecoration;
      // `color-mix(in srgb, var(--glacier-bg) 88%, var(--glacier-text) 4%)`, which the page computed as
      // color(srgb 0.952345 0.95252 0.952536 / 0.92).
      expect([box.color!.r, box.color!.g, box.color!.b], everyElement(closeTo(0.9525, 0.001)));
      expect(box.color!.a, closeTo(0.92, 0.001));
      expect((box.border! as Border).top, BorderSide(color: t.color('glacier-border-subtle')));
      expect(tester.widget<ClipRRect>(find.descendant(of: card, matching: find.byType(ClipRRect)).first).borderRadius, BorderRadius.circular(16));
      // `--app-float-shadow: 0 16px 40px rgb(0 0 0 / 34%)`
      final shadow = t.cssShadows('app-float-shadow').single;
      expect([shadow.offset, shadow.blur, shadow.color.a], [const Offset(0, 16), 40.0, closeTo(0.34, 0.001)]);
      await away(tester);
    });

    testWidgets('grows out of its icon as it opens, and is simply there when less motion is asked for', (tester) async {
      await pumpPage(tester, PageUnder(children: [FloatingCard(label: 'A card', toggle: sidebarToggle, onClose: () {}, child: const SizedBox(height: 200))]));
      Matrix4 moved() => tester.widget<Transform>(find.descendant(of: card, matching: find.byType(Transform)).first).transform;
      double strength() => tester.widget<FadeTransition>(find.descendant(of: card, matching: find.byType(FadeTransition))).opacity.value;
      // `from { opacity: 0; transform: translateY(-6px) scale(0.97) }`, from the top left.
      expect(strength(), 0);
      expect([moved().getTranslation().y, moved().entry(0, 0), moved().entry(1, 1)], [closeTo(-6, 1e-6), closeTo(0.97, 1e-6), closeTo(0.97, 1e-6)]);
      expect(tester.widget<Transform>(find.descendant(of: card, matching: find.byType(Transform)).first).alignment, Alignment.topLeft);
      await tester.pump(const Duration(milliseconds: 90));
      expect(strength(), inExclusiveRange(0.5, 1));
      await tester.pump(const Duration(milliseconds: 90));
      expect(strength(), 1);
      expect(moved(), Matrix4.identity());
      await away(tester);

      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpPage(tester, PageUnder(children: [FloatingCard(label: 'A card', toggle: sidebarToggle, onClose: () {}, child: const SizedBox(height: 200))]));
      expect(strength(), 1);
      await away(tester);
    });

    testWidgets('hangs at the start or the end, a set width or a wider one, never the window’s', (tester) async {
      Future<Rect> at(Size size, {FloatingCardSide side = FloatingCardSide.start, bool wide = false, bool bare = true}) async {
        await pumpPage(tester, PageUnder(children: [FloatingCard(side: side, wide: wide, label: 'A card', toggle: sidebarToggle, onClose: () {}, child: const SizedBox(height: 200))]), size: size, bare: bare);
        await settle(tester);
        return tester.getRect(card);
      }

      // The web page's, at 390 x 844: the drawer's card 13.39, 55.34, 320 wide; the bell's 13.39, 55.34, 363.22 wide,
      // its far edge 13.39 from the window's.
      near(await at(const Size(390, 844)), [13.39, 55.34, 320, 202], what: 'start');
      near(await at(const Size(390, 844), side: FloatingCardSide.end), [390 - 13.39 - 320, 55.34, 320, 202], what: 'end');
      near(await at(const Size(390, 844), side: FloatingCardSide.end, wide: true), [13.39, 55.34, 363.22, 202], what: 'wide');
      expect(tester.widget<Transform>(find.descendant(of: card, matching: find.byType(Transform)).first).alignment, Alignment.topRight);
      // A narrow phone: `min(20rem, calc(100vw - var(--glacier-space-10)))`.
      final narrow = await at(const Size(320, 700));
      final t = tester.element(card).tokens;
      expect(narrow.width, closeTo(320 - t.space(10), 0.01));
      expect(narrow.width, lessThan(320));
      // A phone's own bars: under the status bar and the tab row, in from a notch at the side.
      final phone = await at(const Size(390, 844), bare: false);
      expect(phone.top, closeTo(55.34 + 36, 0.5));
      // A desktop window: 26rem for the bell's, 20rem for the drawer's, hung from the bar by the same tokens.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final desk = await at(const Size(1280, 800), side: FloatingCardSide.end, wide: true);
      final wide = tester.element(card).tokens;
      expect([desk.width, desk.right], [416, closeTo(1280 - wide.space(3), 0.01)]);
      expect(desk.top, closeTo(wide.len('app-safe-top') + wide.space(2), 0.01));
      expect((await at(const Size(1280, 800))).width, 320);
      await away(tester);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('is as tall as what is in it, and no taller than the window leaves below the bar, where it scrolls inside', (tester) async {
      await show(tester, compact: false, closed: {}, trashOpen: true);
      final t = tester.element(card).tokens;
      // `calc(100dvh - var(--app-safe-top) - var(--app-safe-bottom) - var(--glacier-space-2) - var(--glacier-space-3))`:
      // 775.27 on the web page, where its card measured 775.25.
      final most = 844 - t.len('app-safe-top') - t.space(2) - t.space(3);
      expect(tester.getRect(card).height, closeTo(most, 0.01));
      expect(most, closeTo(775.25, 0.1));
      final scroller = tester.state<ScrollableState>(find.descendant(of: card, matching: find.byType(Scrollable)));
      expect(scroller.position.maxScrollExtent, greaterThan(0));
      // The tools stay at the top and the foot at the bottom while the notes scroll between.
      final foot = tester.getRect(find.byKey(const ValueKey('tree-foot')));
      expect(foot.bottom, closeTo(tester.getRect(card).bottom - 1, 0.01));
      await tester.drag(find.text('Groceries'), const Offset(0, -300));
      await tester.pump();
      expect(scroller.position.pixels, greaterThan(100));
      expect(tester.getRect(find.byKey(const ValueKey('tree-foot'))), foot);
      // The keyboard takes its height from what is left.
      tester.view.viewInsets = const FakeViewPadding(bottom: 300 * 2);
      await tester.pump();
      expect(tester.getRect(card).height, closeTo(most - 300, 0.01));
      await away(tester);
    });
  });

  // What the web page measured at 390 x 844 (Chromium, getBoundingClientRect, 2026-10-07) over the same library, with
  // every folder and the trash open. Left, top, width, height.
  group('where it sits, names only', () {
    testWidgets('is the web page’s, to the half pixel', (tester) async {
      await show(tester, closed: {}, trashOpen: true, onCommands: () {});
      Rect boxOf(String text) => tester.getRect(find.ancestor(of: find.text(text), matching: find.byType(Container)).first);

      /// A folder's box as the page has it: its name's row and everything under it. The list lays a folder out as
      /// its parts (its name, then its notes as a list that builds the rows near the screen), so the box is theirs
      /// together.
      Rect folderBox(String id) {
        var box = tester.getRect(find.byKey(ValueKey('folder-row-$id')));
        final under = find.descendant(
          of: find.byKey(ValueKey('folder-$id')),
          matching: find.byWidgetPredicate((w) => (w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('note-row-')) || (w is Text && w.data == 'Nothing here yet.')),
        );
        for (final part in under.evaluate()) {
          box = box.expandToInclude(tester.getRect(find.byElementPredicate((e) => e == part)));
        }
        return box;
      }

      near(tester.getRect(card), [13.39, 55.34, 320, 629.83], what: 'the card');
      // The tools: 32.13 square, 4.46 apart, the close at the far end.
      near(tester.getRect(button('New note')), [27.78, 65.27, 32.13, 32.13], what: 'New note');
      near(tester.getRect(button('New workspace')), [64.36, 65.27, 32.13, 32.13], what: 'New workspace');
      near(tester.getRect(button('Search and commands')), [100.94, 65.27, 32.13, 32.13], what: 'Search');
      near(tester.getRect(button('Show each note drawn small')), [137.52, 65.27, 32.13, 32.13], what: 'names only');
      near(tester.getRect(button('Fold every folder')), [174.09, 65.27, 32.13, 32.13], what: 'fold');
      near(tester.getRect(button('Close')), [286.88, 65.27, 32.13, 32.13], what: 'Close');
      near(tester.getRect(byLucide(Lucide.squarePen)), [35.34, 72.83, 17, 17], what: 'its mark');

      // A workspace's folder: the chevron, its colour, its name, how many, and More.
      near(tester.getRect(byLucide(Lucide.chevronRight).at(0)), [27.53, 112.47, 15, 15], what: 'the chevron');
      near(tester.getRect(find.byKey(const ValueKey('folder-hue')).at(0)), [47.95, 116.66, 6.63, 6.63], what: 'the hue');
      final work = tester.getRect(find.text('Work'));
      expect([work.left, work.top, work.height], [closeTo(60, 0.5), closeTo(112.47, 0.5), 15]);
      // The count's box is 280.09, 112.47, 13.83 x 15 with 6.03 of padding before the digit.
      final count = tester.getRect(find.text('2').first);
      expect([count.left, count.right, count.top, count.height], [closeTo(280.09 + 6.03, 0.5), closeTo(280.09 + 13.83, 0.5), closeTo(112.47, 0.5), 15]);
      near(tester.getRect(button('Rename, recolour or delete Work')), [298.14, 107.31, 25.33, 25.33], what: 'More');
      near(tester.getRect(byLucide(Lucide.ellipsis).at(0)), [302.8, 111.97, 16, 16], what: 'its dots');

      // Its notes, in from its name on the guide: 26.83 a row.
      near(tester.getRect(find.byKey(const ValueKey('note-row-launch'))), [45.09, 132.64, 278.38, 26.83], what: 'Launch week');
      near(tester.getRect(find.byKey(const ValueKey('kind-mark')).at(0)), [54.69, 139.05, 14, 14], what: 'its kind');
      near(tester.getRect(find.ancestor(of: find.text('Launch week'), matching: find.byType(CssLines))), [76.69, 137.75, 237.19, 16.61], what: 'its name');
      near(tester.getRect(find.byKey(const ValueKey('note-row-standup'))), [45.09, 159.47, 278.38, 26.83], what: 'Monday standup');
      near(folderBox('work'), [23.31, 107.31, 300.16, 78.98], what: 'the folder');
      near(folderBox('home'), [23.31, 187.3, 300.16, 52.16], what: 'Home');

      // An empty folder, and an organization's.
      near(folderBox('garden'), [23.31, 240.45, 300.16, 39.33], what: 'Garden');
      near(tester.getRect(find.text('Nothing here yet.').at(0)), [36.33, 267.78, 287.14, 12], what: 'Nothing here yet');
      near(folderBox('org-o1'), [23.31, 283.78, 300.16, 39.33], what: 'Ghost');
      // The mark is 10.84 square with 4.22 after it.
      near(tester.getRect(find.byType(OrgMark)), [60, 291.02, 10.84 + 4.22, 10.84], what: 'the mark');
      expect(tester.getRect(find.text('Ghost')).left, closeTo(80.48, 0.5));

      // The notes filed in none.
      near(tester.getRect(find.byKey(const ValueKey('note-row-long'))), [23.31, 327.11, 300.16, 26.83], what: 'the long name');
      near(tester.getRect(find.ancestor(of: find.textContaining('A note whose name'), matching: find.byType(CssLines))), [54.91, 332.22, 258.97, 16.61], what: 'on one line');
      near(tester.getRect(find.byKey(const ValueKey('note-row-packing'))), [23.31, 353.94, 300.16, 26.83], what: 'Packing list');
      near(tester.getRect(find.byKey(const ValueKey('note-row-portugal'))), [23.31, 380.77, 300.16, 26.83], what: 'Portugal');
      near(tester.getRect(find.byKey(const ValueKey('note-row-cabin'))), [23.31, 407.59, 300.16, 26.83], what: 'the canvas');
      near(tester.getRect(find.byKey(const ValueKey('note-row-blank'))), [23.31, 434.42, 300.16, 26.83], what: 'Untitled');

      // The archive, which has no More, and the trash, which has Empty.
      near(folderBox('archive'), [23.31, 462.25, 300.16, 51.45], what: 'the archive');
      near(tester.getRect(byLucide(Lucide.archive)), [47.95, 467.56, 14, 14], what: 'its mark');
      expect(tester.getRect(find.text('Archive')).left, closeTo(67.38, 0.5));
      near(tester.getRect(find.byKey(const ValueKey('note-row-old'))), [45.09, 486.88, 278.38, 26.83], what: 'Old plans');
      near(tester.getRect(find.byKey(const ValueKey('folder-trash'))), [23.31, 514.7, 300.16, 99.66], what: 'the trash');
      near(boxOf('Empty'), [281.42, 518.52, 42.05, 17], what: 'Empty');
      near(tester.getRect(find.byKey(const ValueKey('trash-row-torn'))), [45.09, 540.33, 278.38, 36.52], what: 'a thrown note');
      near(tester.getRect(find.ancestor(of: find.text('Torn page'), matching: find.byType(CssLines))), [54.69, 550.28, 200.55, 16.61], what: 'its name');
      near(tester.getRect(button('Restore Torn page')), [260.83, 545.92, 25.33, 25.33], what: 'Restore');
      near(tester.getRect(button('Delete Torn page for good')), [291.75, 545.92, 25.33, 25.33], what: 'Delete for good');
      near(tester.getRect(byLucide(Lucide.rotateCcw).at(0)), [265.98, 551.08, 15, 15], what: 'its mark');
      near(tester.getRect(find.byKey(const ValueKey('trash-row-scrap'))), [45.09, 577.84, 278.38, 36.52], what: 'the other');

      // The foot.
      near(tester.getRect(find.byKey(const ValueKey('tree-foot'))), [14.39, 633.2, 318, 50.97], what: 'the foot');
      near(boxOf('Speak'), [27.78, 644.5, 87.89, 29.38], what: 'Speak');
      near(tester.getRect(byLucide(Lucide.mic)), [40.5, 651.19, 16, 16], what: 'its mic');
      near(tester.getRect(button('Settings')), [286.88, 643.13, 32.13, 32.13], what: 'Settings');
      await away(tester);
    });

    // Colours the page computed: the tools and marks `oklch(0.56 0 0)` (--app-ink-3), a count `oklch(0.8 0 0)`
    // (--app-ink-4), an untitled note `oklch(0.56 0 0)` (--glacier-text-subtle), a thrown note's name
    // `oklch(0.36 0 0)` (--app-ink-2), Speak `oklch(0.995 0 0)` on `oklch(0.16 0 0)`.
    testWidgets('is in the web page’s inks and weights', (tester) async {
      await show(tester, closed: {}, trashOpen: true);
      final t = tester.element(card).tokens;
      TextStyle style(String text) => tester.widget<Text>(find.text(text).first).style!;
      expect([style('Work').fontSize, style('Work').fontWeight, style('Work').color], [closeTo(12.0553, 0.001), FontWeight.w600, t.color('app-ink')]);
      expect([style('2').fontWeight, style('2').color], [FontWeight.w500, t.color('app-ink-4')]);
      expect(style('2').fontFeatures, contains(const FontFeature.tabularFigures()));
      expect([style('Launch week').fontSize, style('Launch week').fontWeight, style('Launch week').height], [closeTo(12.7787, 0.001), FontWeight.w500, 1.3]);
      expect(style('Untitled').color, t.color('glacier-text-subtle'));
      expect([style('Torn page').color, style('Nothing here yet.').color], [t.color('app-ink-2'), t.color('app-ink-4')]);
      expect([style('Nothing here yet.').fontSize, style('Empty').fontSize], everyElement(closeTo(10.0208, 0.001)));
      expect([style('Speak').fontSize, style('Speak').fontWeight, style('Speak').color], [closeTo(13.3948, 0.001), FontWeight.w600, t.color('app-paper')]);
      expect(tester.widget<AppIcon>(byLucide(Lucide.squarePen)).color, t.color('app-ink-3'));
      expect(tester.widget<AppIcon>(byLucide(Lucide.chevronRight).first).color, t.color('app-ink-3'));
      await away(tester);
    });

    // At 1280 x 800 on a desktop the page's card is 320 wide at 15.8 from the window's edge; inside it (from the
    // card's own corner): the first tool 16.79, 11.53, 37.92 square; a folder's toggle from 11.53, 61.05, 25.19 tall;
    // a row 27.78 tall; Empty 43.17 x 17.13; the foot 318 x 59.98 with Speak 92.06 x 31.16 in it.
    testWidgets('on a desktop is the web page’s, from the card’s own corner', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await show(tester, size: const Size(1280, 800), onCommands: () {});
      final at = tester.getRect(card);
      final t = tester.element(card).tokens;
      Rect inCard(Finder f) => tester.getRect(f).shift(-at.topLeft);
      expect([at.left, at.width, at.height], [closeTo(15.8, 0.05), 320, closeTo(558.28, 0.5)]);
      expect(at.top, closeTo(t.len('app-safe-top') + t.space(2), 0.01));
      near(inCard(button('New note')), [16.79, 11.53, 37.92, 37.92], what: 'New note');
      near(inCard(button('Close')), [265.28, 11.53, 37.92, 37.92], what: 'Close');
      near(inCard(button('Rename, recolour or delete Work')), [283.14, 60.98, 25.33, 25.33], what: 'More');
      near(inCard(find.byKey(const ValueKey('note-row-launch'))), [33.31, 86.31, 275.16, 27.78], what: 'a row');
      near(inCard(find.byKey(const ValueKey('note-row-long'))), [11.53, 283.95, 296.94, 27.78], what: 'a loose row');
      near(inCard(find.ancestor(of: find.text('Empty'), matching: find.byType(Container)).first), [265.29, 454.08, 43.17, 17.13], what: 'Empty');
      near(inCard(find.byKey(const ValueKey('tree-foot'))), [1, 497.3, 318, 59.98], what: 'the foot');
      near(inCard(find.ancestor(of: find.text('Speak'), matching: find.byType(Container)).first), [16.79, 512.2, 92.06, 31.16], what: 'Speak');
      await away(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  // The same page with each note drawn small. The web draws the note in its own editor there, which this port does
  // not have yet (notes/note_peek.dart), so a row's height is the web's only down to its name: what is asserted is
  // what does not depend on the drawing.
  group('where it sits, each note drawn small', () {
    testWidgets('is the web page’s down to each note’s name, with the stand-in for its drawing under it', (tester) async {
      await show(tester, compact: false, closed: {}, trashOpen: true);
      final t = tester.element(card).tokens;
      // The first row: 1px under its folder's name, 8 x 9.6 of padding, its name in semibold on a 16.61 line.
      final row = tester.getRect(find.byKey(const ValueKey('note-row-launch')));
      expect([row.left, row.top, row.width], [closeTo(45.09, 0.5), closeTo(133.64, 0.5), closeTo(278.38, 0.5)]);
      near(tester.getRect(find.ancestor(of: find.text('Launch week'), matching: find.byType(CssLines))), [54.69, 141.64, 259.19, 16.61], what: 'its name');
      expect(tester.widget<Text>(find.text('Launch week')).style!.fontWeight, FontWeight.w600);
      // The page's peek starts 165.09 down: the name, the grid's 2.4, and `.rowPeek`'s 4.46.
      final peek = tester.getRect(find.byType(NotePeek).first);
      expect([peek.left, peek.top, peek.width], [closeTo(54.69, 0.5), closeTo(165.09, 0.5), closeTo(259.19, 0.5)]);
      expect(tester.renderObject<RenderEditorLine>(find.descendant(of: find.byType(NotePeek).first, matching: find.byType(EditorLine)).first).spec.look.base.fontSize, closeTo(10.8194, 0.001));
      expect(row.bottom, closeTo(peek.bottom + 8, 0.01));
      // A long name wraps onto a second line and no further: 280.97 x 33.22 on the page.
      final long = tester.getRect(find.ancestor(of: find.textContaining('A note whose name'), matching: find.byType(CssLines)));
      expect([long.width, long.height], [closeTo(280.97, 0.5), closeTo(33.22, 0.05)]);
      // A page of a book says which, 2.4 under its name: the mark 12 square, the name 3.34 after it, 14 tall.
      final name = tester.getRect(find.ancestor(of: find.text('Packing list'), matching: find.byType(CssLines)));
      final book = tester.getRect(byLucide(Lucide.book));
      final title = tester.getRect(find.text('Portugal').first);
      expect([book.left, book.top, book.size], [closeTo(32.91, 0.5), closeTo(name.bottom + 2.4 + 1, 0.01), const Size(12, 12)]);
      expect([title.left, title.top, title.width, title.height], [closeTo(48.23, 0.5), closeTo(name.bottom + 2.4, 0.01), closeTo(44.09, 0.5), 14]);
      expect(tester.widget<Text>(find.text('Portugal').first).style!.color, t.color('glacier-text-muted'));
      // Rows are 1px apart, the margins of two meeting as one.
      final next = tester.getRect(find.byKey(const ValueKey('note-row-standup')));
      expect(next.top, closeTo(row.bottom + 1, 0.01));
      // A canvas and a note with nothing in it draw nothing under their names. They are further down than the card
      // is tall, and the list builds only the rows near the screen: the list is scrolled to them.
      await tester.scrollUntilVisible(find.byKey(const ValueKey('note-row-blank')), 200, scrollable: find.descendant(of: card, matching: find.byType(Scrollable)));
      await tester.pump();
      expect(find.descendant(of: find.byKey(const ValueKey('note-row-cabin')), matching: find.byType(NotePeek)), findsNothing);
      expect(tester.getRect(find.byKey(const ValueKey('note-row-blank'))).height, closeTo(16 + 16.61, 0.05));
      await away(tester);
    });

    testWidgets('rings the open note rather than filling it', (tester) async {
      await show(tester, compact: false, activeId: 'groceries');
      final t = tester.element(card).tokens;
      BoxDecoration ring(String id) => tester.widget<DecoratedBox>(find.descendant(of: find.byKey(ValueKey('note-row-$id')), matching: find.byType(DecoratedBox)).at(1)).decoration as BoxDecoration;
      final open = ring('groceries').border! as Border;
      // `inset 0 0 0 var(--app-line) color-mix(in oklch, var(--app-ink) 55%, transparent)`
      expect([open.top.width, open.top.color], [1.5, t.colorOf('color-mix(in oklch, var(--app-ink) 55%, transparent)')]);
      expect(ring('groceries').borderRadius, BorderRadius.circular(t.radius('md')));
      expect(ring('launch').border, isNull);
      await away(tester);
    });
  });

  group('the pictures', () {
    for (final theme in ['light', 'dark']) {
      for (final (name, size, desktop) in [('phone', const Size(390, 844), false), ('wide', const Size(1280, 800), true)]) {
        /// A desktop has a mouse, which is what hides a folder's More until its row is pointed at.
        Future<TestGesture?> mouse(WidgetTester tester) async {
          if (!desktop) return null;
          final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(900, 700));
          await tester.pump();
          return mouse;
        }

        for (final compact in [true, false]) {
          testWidgets('the drawer, ${compact ? 'names only' : 'each note drawn small'}, $name, $theme', (tester) async {
            if (desktop) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
            final pointer = await mouse(tester);
            await show(tester, compact: compact, activeId: 'groceries', size: size, theme: theme, onCommands: () {});
            await shot(tester, 'drawer-${compact ? 'compact' : 'full'}-$name-$theme');
            await pointer?.removePointer();
            debugDefaultTargetPlatformOverride = null;
          });
        }

        testWidgets('a folder shut and the trash asking, $name, $theme', (tester) async {
          if (desktop) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final pointer = await mouse(tester);
          await show(tester, closed: {archiveFolder, 'work'}, trashOpen: true, size: size, theme: theme, onCommands: () {});
          await tester.tap(find.text('Empty'));
          await tester.pump();
          expect(find.text('Delete 2 for good?'), findsOneWidget);
          await shot(tester, 'drawer-asking-$name-$theme', settle: const Duration(milliseconds: 400));
          await pointer?.removePointer();
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }

    testWidgets('the drawer on a phone with its bars, light', (tester) async {
      await show(tester, bare: false, onCommands: () {});
      await shot(tester, 'drawer-compact-phone-bars-light');
    });
  });
}
