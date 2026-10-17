// The dock, the same on every page (docs/DOCK.md, lib/shell/page_dock.dart): the pill, its order (Claude first, the
// settings-type ring last), what each ring is called, a press running the page's own action, the tip on a desktop,
// the home page's dock as it was with Settings at its foot, and the pages of notes and Settings with theirs. A note's
// dock is test/note/note_dock_test.dart's; an organization's, test/orgs_ui/organization_dock_test.dart's.
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/art.dart' show Lucide;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/smart_notebooks.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_icons.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/notes/collection_screen.dart';
import 'package:ghost_md/settings/settings_sheet.dart';
import 'package:ghost_md/shell/page_dock.dart';
import 'package:ghost_md/shell/screen.dart' show CollectionKind;
import 'package:glacier/glacier.dart';

import '../support/render.dart';
import 'dock_support.dart';

void main() {
  setUpAll(loadAppFonts);

  group('the dock', () {
    testWidgets('is Claude, the page’s rings and the foot, in that order, each a button called by its words', (tester) async {
      final asked = <String>[];
      final semantics = tester.ensureSemantics();
      await pumpApp(
        tester,
        home: Align(
          alignment: Alignment.bottomRight,
          child: PageDock(
            claude: fakeClaude(asked)(() => 'Plan'),
            actions: [
              DockAction(id: 'search', label: 'Search and commands', glyph: HomeGlyph.magnifier, motion: DockMotion.lean, onPressed: () => asked.add('search')),
              DockAction(id: 'speak', label: 'Speak a voice note', glyph: HomeGlyph.mic, ink: true, onPressed: () => asked.add('speak')),
            ],
            foot: DockAction(id: 'settings', label: 'Settings', icon: Lucide.settings, onPressed: () => asked.add('settings')),
          ),
        ),
      );
      expect(dockOrder(tester), ['claude', 'search', 'speak', 'settings']);
      for (final label in ['Ask Claude', 'Search and commands', 'Speak a voice note', 'Settings']) {
        expect(tester.getSemantics(find.bySemanticsLabel(label)).flagsCollection.isButton, isTrue, reason: label);
      }
      await tester.tap(find.byKey(const ValueKey('dock-claude')));
      await tester.tap(find.byKey(const ValueKey('dock-search')));
      await tester.tap(find.byKey(const ValueKey('dock-speak')));
      await tester.tap(find.byKey(const ValueKey('dock-settings')));
      expect(asked, ['claude Plan', 'search', 'speak', 'settings']);
      // The rings are one column, each the size of the others, a gap apart.
      final t = GlacierTheme.of(tester.element(find.byType(PageDock)));
      final ring = t.len('app-ring');
      final rects = [for (final id in dockOrder(tester)) tester.getRect(find.byKey(ValueKey('dock-$id')))];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].left, closeTo(rects[0].left, 0.01));
        expect(rects[i].width, closeTo(ring, 0.01));
        expect(rects[i].top - rects[i - 1].bottom, closeTo(t.space(2), 0.01));
      }
      semantics.dispose();
      await done(tester);
    });

    testWidgets('says a ring’s words beside it on a desktop while the pointer rests on it, and not on a phone', (tester) async {
      Widget dock() => Align(
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: PageDock(foot: DockAction(id: 'settings', label: 'Settings', icon: Lucide.settings, onPressed: () {})),
            ),
          );
      await pumpApp(tester, home: dock());
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      addTearDown(mouse.removePointer);
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('dock-settings'))));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('dock-tip')), findsNothing, reason: 'a phone has no pointer to rest');

      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await pumpApp(tester, home: dock());
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      await mouse.moveTo(tester.getCenter(find.byKey(const ValueKey('dock-settings'))));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('dock-tip')), findsNothing, reason: 'not at once');
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.descendant(of: find.byKey(const ValueKey('dock-tip')), matching: find.text('Settings')), findsOneWidget);
      // At the ring's start side, since the dock stands at the end.
      expect(tester.getRect(find.byKey(const ValueKey('dock-tip'))).right, lessThan(tester.getRect(find.byKey(const ValueKey('dock-settings'))).left));
      await mouse.moveTo(Offset.zero);
      await tester.pump();
      expect(find.byKey(const ValueKey('dock-tip')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
      await done(tester);
    });

    testWidgets('a view offers its rings to the page’s dock, and they go with it', (tester) async {
      final offers = DockOffers();
      addTearDown(offers.dispose);
      final shown = ValueNotifier<bool>(true);
      var pressed = 0;
      await pumpApp(
        tester,
        home: DockOfferScope(
          offers: offers,
          child: ValueListenableBuilder<bool>(
            valueListenable: shown,
            builder: (context, on, _) => on ? DockOffer(actions: [DockAction(id: 'canvas-fit', label: 'Fit', icon: Lucide.maximize, onPressed: () => pressed += 1)], child: const SizedBox()) : const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      expect([for (final action in offers.actions) action.id], ['canvas-fit']);
      offers.actions.single.onPressed!();
      expect(pressed, 1);
      shown.value = false;
      await tester.pump();
      await tester.pump();
      expect(offers.actions, isEmpty);
      await done(tester);
    });
  });

  group('the home page’s dock', () {
    HomeScreen home({VoidCallback? onSettings, List<String>? asked}) => HomeScreen(
          notes: const [],
          workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage()),
          gists: const {},
          onOpen: (_) {},
          onNew: () => asked?.add('new'),
          onCapture: () => asked?.add('speak'),
          onSearch: () => asked?.add('search'),
          onAllNotes: () {},
          onSettings: onSettings,
          claude: fakeClaude(asked ?? [])(null),
        );

    testWidgets('is as it was, with Settings at its foot: the same rings, moved up a ring to make room', (tester) async {
      await pumpApp(tester, home: home());
      expect(dockOrder(tester), ['claude', 'search', 'add', 'speak']);
      final before = {for (final id in dockOrder(tester)) id: tester.getRect(find.byKey(ValueKey('dock-$id')))};

      final asked = <String>[];
      await pumpApp(tester, home: home(onSettings: () => asked.add('settings'), asked: asked));
      expect(dockOrder(tester), ['claude', 'search', 'add', 'speak', 'settings']);
      final t = GlacierTheme.of(tester.element(find.byType(PageDock)));
      final step = t.len('app-ring') + t.space(2);
      for (final id in before.keys) {
        final now = tester.getRect(find.byKey(ValueKey('dock-$id')));
        expect(now.size, before[id]!.size, reason: id);
        expect(now.left, closeTo(before[id]!.left, 0.01), reason: id);
        expect(now.top, closeTo(before[id]!.top - step, 0.01), reason: id);
      }
      // Settings stands where Speak stood, nearest the thumb's corner.
      expect(tester.getRect(find.byKey(const ValueKey('dock-settings'))), before['speak']);
      await tester.tap(find.byKey(const ValueKey('dock-settings')));
      await tester.tap(find.byKey(const ValueKey('dock-search')));
      await tester.tap(find.byKey(const ValueKey('dock-add')));
      await tester.tap(find.byKey(const ValueKey('dock-speak')));
      expect(asked, ['settings', 'search', 'new', 'speak']);
      expect(find.bySemanticsLabel('Settings'), findsOneWidget);
      await done(tester);
    });

    testWidgets('stands out to the start of the chat down the right of a wide window', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800), home: home(onSettings: () {}));
      final rested = tester.getRect(find.byType(PageDock));
      windowEndCover.value = 420;
      addTearDown(() => windowEndCover.value = 0);
      await tester.pump();
      final moved = tester.getRect(find.byType(PageDock));
      expect(moved.left, closeTo(rested.left - 420, 0.01));
      expect(moved.top, closeTo(rested.top, 0.01));
      expect(moved.width, closeTo(rested.width, 0.01));
      windowEndCover.value = 0;
      await tester.pump();
      expect(tester.getRect(find.byType(PageDock)).left, closeTo(rested.left, 0.01));
      await done(tester);
    });
  });

  group('a page of notes’ dock', () {
    testWidgets('All notes: Claude, Search, +, Speak and Settings, at the bottom end corner, each the app’s own', (tester) async {
      final asked = <String>[];
      await pumpApp(
        tester,
        home: AllNotesScreen(
          notes: const [],
          workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage()),
          gists: const {},
          stored: MemoryStored(),
          onOpen: (_) {},
          onBack: () {},
          dock: notesDock(asked),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(dockOrder(tester), ['claude', 'search', 'add', 'speak', 'settings']);
      await pressAll(tester);
      expect(asked, ['claude', 'search', 'new', 'speak', 'settings']);
      expectInCorner(tester);
      await done(tester);
    });

    testWidgets('the Tags page, a tag’s and a smart notebook’s: the same dock', (tester) async {
      final prefs = PreferencesStore()..startWithoutStorage();
      final smart = SmartNotebookStore(prefs: prefs);
      addTearDown(smart.dispose);
      for (final kind in CollectionKind.values) {
        final asked = <String>[];
        await pumpApp(
          tester,
          home: CollectionScreen(
            kind: kind,
            name: kind == CollectionKind.tag ? 'work' : '',
            notes: const [],
            workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage()).value,
            smart: smart,
            onOpen: (_) {},
            onBack: () {},
            onTag: (_) {},
            stored: MemoryStored(),
            dock: notesDock(asked),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(dockOrder(tester), ['claude', 'search', 'add', 'speak', 'settings'], reason: kind.name);
        await pressAll(tester);
        expect(asked, ['claude', 'search', 'new', 'speak', 'settings'], reason: kind.name);
        expectInCorner(tester);
      }
      await done(tester);
    });

    testWidgets('rides over the keyboard while a search is typed, where a note’s steps aside', (tester) async {
      await pumpApp(
        tester,
        home: AllNotesScreen(notes: const [], workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage()), gists: const {}, stored: MemoryStored(), onOpen: (_) {}, onBack: () {}, dock: notesDock([])),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final rested = tester.getRect(find.byKey(const ValueKey('dock-settings')));
      tester.view.viewInsets = FakeViewPadding(bottom: 300 * tester.view.devicePixelRatio);
      await tester.pump(const Duration(milliseconds: 500));
      expect(dockShown(tester), isTrue);
      final t = GlacierTheme.of(tester.element(find.byType(PageDock)));
      expect(tester.getRect(find.byType(PageDock)).bottom, closeTo(844 - 300 - t.space(4), 0.01));
      tester.view.resetViewInsets();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getRect(find.byKey(const ValueKey('dock-settings'))), rested);
      await done(tester);
    });

    testWidgets('moves out to the start of the chat down the right of a wide window, and back when it goes', (tester) async {
      await pumpApp(
        tester,
        size: const Size(1280, 800),
        home: AllNotesScreen(notes: const [], workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage()), gists: const {}, stored: MemoryStored(), onOpen: (_) {}, onBack: () {}, dock: notesDock([])),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final rested = tester.getRect(find.byKey(const ValueKey('dock-settings')));
      windowEndCover.value = 420;
      addTearDown(() => windowEndCover.value = 0);
      await tester.pump();
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('dock-settings'))).right, closeTo(rested.right - 420, 0.01));
      windowEndCover.value = 0;
      await tester.pump();
      expect(tester.getRect(find.byKey(const ValueKey('dock-settings'))), rested);
      await done(tester);
    });
  });

  group('Settings’ dock', () {
    testWidgets('is Claude alone, over Settings', (tester) async {
      final asked = <String>[];
      await pumpApp(
        tester,
        home: BackScope(
          stack: BackStack(),
          child: SettingsSheet(open: true, onClose: () {}, dock: PageDockSeam(claude: fakeClaude(asked))),
        ),
      );
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(dockOrder(tester), ['claude']);
      await tester.tap(find.byKey(const ValueKey('dock-claude')));
      expect(asked, ['claude']);
      expectInCorner(tester);
      await done(tester);
    });
  });
}
