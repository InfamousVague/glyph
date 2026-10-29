import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/folder_drag.dart';
import 'package:ghost_md/notes/folder_strip.dart';
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/workspace_bar.dart';

import '../library/support.dart' show makeNote;
import '../support/render.dart';

/// A note or a folder carried across an organization's edge asks first (lib/notes/folder_drag.dart `askToMove`;
/// Matt, 2026-10-29: "Allow dragging files into folders for orgs instead of sending the error message open a confirm
/// dialog"): into one, out of one, or from one into another, on every place a note or a folder is let go - the icon
/// view's tiles, the folder strip's chips and the line above them, the workspace pills, the sidebar's rows and its top
/// level - with a finger at a phone's size and a mouse at a Mac window's. Cancel, Escape and a tap outside leave
/// everything where it was; Move, or Return, moves it. A move inside one organization, or among the person's own
/// folders, asks nothing. Nobody in it is real.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => folderCarrying.value = null);

  const ghost = 'org-ghost', hello = 'org-hello';

  /// Ghost.md › Clients › Acme, HelloTrade › Designs, Work › Kiln, Home. Work holds three notes, Kiln one of them.
  WorkspaceSheet sheet() => const WorkspaceSheet(
        list: [
          Workspace(id: ghost, name: 'Ghost.md', hue: 'sea'),
          Workspace(id: 'clients', name: 'Clients', parent: ghost),
          Workspace(id: 'acme', name: 'Acme', parent: 'clients'),
          Workspace(id: hello, name: 'HelloTrade', hue: 'violet'),
          Workspace(id: 'designs', name: 'Designs', parent: hello),
          Workspace(id: 'work', name: 'Work'),
          Workspace(id: 'kiln', name: 'Kiln', parent: 'work'),
          Workspace(id: 'home', name: 'Home'),
        ],
        notes: {'plan': ghost, 'brief': 'clients', 'sketch': 'designs', 'todo': 'work', 'trip': 'work', 'kit': 'kiln'},
      );

  WorkspaceStore storeOf() => WorkspaceStore(storage: MemoryWorkspaceStorage(sheet()));

  List<Note> notes() => [
        for (final id in ['plan', 'brief', 'sketch', 'todo', 'trip', 'kit', 'loose']) makeNote(id, body: '# ${id[0].toUpperCase()}${id.substring(1)}'),
      ];

  const phone = Size(390, 844), mac = Size(1280, 860);

  Future<void> page(WidgetTester tester, Widget child, {required Size size, AppPreferences prefs = const AppPreferences(theme: 'light')}) async {
    await pumpApp(tester, size: size, prefs: prefs, home: BackScope(child: Align(alignment: Alignment.topLeft, child: child)));
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }

  Future<void> down(WidgetTester tester) async {
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  }

  Offset centre(WidgetTester tester, String key) => tester.getCenter(find.byKey(ValueKey(key)));

  /// Whether the drop zone [key] wears the ring of one that takes what is held over it.
  bool taking(String key) {
    final ring = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byKey(const ValueKey('drop-ring')));
    if (ring.evaluate().isEmpty) return false;
    final decoration = (ring.evaluate().first.widget as DecoratedBox).decoration as BoxDecoration;
    final refusing = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.forbidden)).evaluate().isNotEmpty;
    return decoration.border != null && !refusing;
  }

  /// A carry from [from] to [to]: a mouse's on a Mac, pressed, moved and let go; a finger's on a phone, held until it
  /// lifts first. Answers what [during] saw while it was held over [to]; the sheet, if one is asked, is up after.
  Future<T?> carry<T>(WidgetTester tester, String from, String to, {T Function()? during}) async {
    final mouse = defaultTargetPlatform == TargetPlatform.macOS;
    final gesture = await tester.startGesture(centre(tester, from), kind: mouse ? PointerDeviceKind.mouse : PointerDeviceKind.touch);
    if (!mouse) await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveBy(Offset(0, mouse ? 12 : 4));
    await tester.pump();
    await gesture.moveTo(centre(tester, to));
    await tester.pump();
    await tester.pump();
    final seen = during?.call();
    await gesture.up();
    // The sheet in, past its entrance.
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return seen;
  }

  Finder ask() => find.byKey(const ValueKey('move-ask'));

  Future<void> answer(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// All notes as it is laid out: the folder strip inside [chosen] (its chips and the line above them), the
  /// workspace pills, and the icon view at the top, its folders' tiles and the notes filed in none.
  Widget allNotes(WorkspaceStore store, {String chosen = ghost}) => ListenableBuilder(
        listenable: store,
        builder: (context, _) => SizedBox(
          width: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FolderStrip(list: store.value.list, of: store.value.of, notes: notes(), chosen: chosen, onChoose: (_) {}, store: store),
              WorkspaceBar(store: store, onManage: (_) {}),
              IconBrowser(
                folders: folderTiles(store.value.list, store.value.of, notes(), null),
                notes: [for (final n in notes()) if (store.value.of[n.id] == null) n],
                onFolder: (_) {},
                onOpen: (_) {},
                store: store,
              ),
            ],
          ),
        ),
      );

  Widget tree(WorkspaceStore store) => SizedBox(
        width: 320,
        height: 840,
        // Names only, so every row is on the screen.
        child: NoteTree(notes: notes(), activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: store, stored: MemoryStored()..writeText('glyph-tree-compact', '1')),
      );

  /// Each place a note is let go into an organization: the page, what is carried, where, and the zone drawn there.
  final targets = <({String name, bool sidebar, String chosen, String from, String to, String zone, String into, String title})>[
    (name: 'an icon view’s folder tile', sidebar: false, chosen: ghost, from: 'tile-note-loose', to: 'tile-folder-$ghost', zone: 'drop-$ghost', into: ghost, title: 'Move “Loose” to Ghost.md?'),
    (name: 'a folder strip’s chip', sidebar: false, chosen: ghost, from: 'tile-note-loose', to: 'folder-chip-clients', zone: 'drop-clients', into: 'clients', title: 'Move “Loose” to Ghost.md › Clients?'),
    (name: 'the line above the strip’s chips', sidebar: false, chosen: 'clients', from: 'tile-note-loose', to: 'crumb-$ghost', zone: 'drop-crumb-$ghost', into: ghost, title: 'Move “Loose” to Ghost.md?'),
    (name: 'a workspace pill', sidebar: false, chosen: ghost, from: 'tile-note-loose', to: 'space-$hello', zone: 'drop-space-$hello', into: hello, title: 'Move “Loose” to HelloTrade?'),
    (name: 'the sidebar’s folder row', sidebar: true, chosen: ghost, from: 'note-row-todo', to: 'folder-row-acme', zone: 'drop-acme', into: 'acme', title: 'Move “Todo” to Ghost.md › Clients › Acme?'),
  ];

  for (final (label, size, platform) in [('on a phone, by a finger', phone, TargetPlatform.android), ('on a Mac, by a mouse', mac, TargetPlatform.macOS)]) {
    group(label, () {
      for (final target in targets) {
        testWidgets('a personal note carried onto ${target.name} of an organization’s asks first: Cancel leaves it, Move files it there', (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
          final store = storeOf();
          final id = target.sidebar ? 'todo' : 'loose';
          final was = store.value.of[id];
          await page(tester, target.sidebar ? tree(store) : allNotes(store, chosen: target.chosen), size: size);
          // Held over it, it is drawn taking it, not refusing it.
          expect(await carry(tester, target.from, target.to, during: () => taking(target.zone)), isTrue);
          expect(ask(), findsOneWidget);
          expect(find.text(target.title), findsOneWidget);
          expect(find.text('Everyone in ${target.into == hello ? 'HelloTrade' : 'Ghost.md'} will be able to read and edit it.'), findsOneWidget);
          expect(find.text('Move'), findsOneWidget);
          expect(find.text('Cancel'), findsOneWidget);
          // Nothing moves while it asks, nor on Cancel.
          expect(store.value.of[id], was);
          await answer(tester, 'move-ask-no');
          expect(ask(), findsNothing);
          expect(store.value.of[id], was);
          // Again, and Move: filed there, the team's now, said in a toast with no Undo.
          await carry(tester, target.from, target.to);
          expect(ask(), findsOneWidget);
          await answer(tester, 'move-ask-yes');
          expect(ask(), findsNothing);
          expect(store.value.of[id], target.into);
          expect(store.orgOf(target.into), isNotNull);
          expect(find.textContaining('Moved “${id[0].toUpperCase()}${id.substring(1)}” to'), findsOneWidget);
          expect(find.text('Undo'), findsNothing);
          debugDefaultTargetPlatformOverride = null;
          await down(tester);
        });
      }

      testWidgets('a team note carried out to the person’s own folder asks, saying what it does; onto the top level or straight into another organization it is refused, saying how', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final store = storeOf();
        await page(tester, tree(store), size: size);
        // Out, to a personal folder.
        await carry(tester, 'note-row-brief', 'folder-row-home');
        expect(find.text('Move “Brief” to Home?'), findsOneWidget);
        expect(find.text('It will no longer be shared with Ghost.md: it is taken out of the team and deleted for everyone else in Ghost.md. You keep it.'), findsOneWidget);
        await answer(tester, 'move-ask-no');
        expect(store.value.of['brief'], 'clients');
        // Into another organization: refused, drawn refusing, and the toast says the way.
        expect(await carry(tester, 'note-row-brief', 'folder-row-designs', during: () => taking('drop-designs')), isFalse);
        expect(ask(), findsNothing);
        expect(find.text('“Brief” is Ghost.md’s. Move it into one of your own folders first; once that has synced, it can go into HelloTrade.'), findsOneWidget);
        expect(store.value.of['brief'], 'clients');
        await tester.pump(const Duration(seconds: 6));
        // The top level is not offered while a team note is carried: filed nowhere it would still be the team's.
        final held = await tester.startGesture(centre(tester, 'note-row-sketch'), kind: defaultTargetPlatform == TargetPlatform.macOS ? PointerDeviceKind.mouse : PointerDeviceKind.touch);
        if (defaultTargetPlatform != TargetPlatform.macOS) await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await held.moveBy(const Offset(0, 12));
        await tester.pump();
        expect(find.byKey(const ValueKey('drop-top')), findsNothing);
        await held.cancel();
        await tester.pump();
        // Out of HelloTrade into Home, Move pressed.
        await carry(tester, 'note-row-sketch', 'folder-row-home');
        expect(find.text('Move “Sketch” to Home?'), findsOneWidget);
        expect(find.text('It will no longer be shared with HelloTrade: it is taken out of the team and deleted for everyone else in HelloTrade. You keep it.'), findsOneWidget);
        await answer(tester, 'move-ask-yes');
        expect(store.value.of['sketch'], 'home');
        expect(find.text('Moved “Sketch” to Home'), findsOneWidget);
        // Nothing else moved.
        expect(store.value.of, {'plan': ghost, 'brief': 'clients', 'sketch': 'home', 'todo': 'work', 'trip': 'work', 'kit': 'kiln'});
        debugDefaultTargetPlatformOverride = null;
        await down(tester);
      });

      testWidgets('a folder carried into an organization asks how many notes go with it, and Move takes them all', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final store = storeOf();
        await page(tester, tree(store), size: size);
        await carry(tester, 'folder-row-work', 'folder-row-designs');
        expect(find.text('Move Work and its 3 notes to HelloTrade › Designs?'), findsOneWidget);
        expect(find.text('Everyone in HelloTrade will be able to read and edit them.'), findsOneWidget);
        await answer(tester, 'move-ask-no');
        expect(store.value.list.firstWhere((w) => w.id == 'work').parent, isNull);
        await carry(tester, 'folder-row-work', 'folder-row-designs');
        await answer(tester, 'move-ask-yes');
        expect(store.value.list.firstWhere((w) => w.id == 'work').parent, 'designs');
        // Its notes are filed where they were, in Work and Kiln, and are HelloTrade's with them.
        expect([for (final id in ['todo', 'trip', 'kit']) store.orgOf(store.value.of[id]!)], ['hello', 'hello', 'hello']);
        expect(find.text('Moved Work to HelloTrade › Designs'), findsOneWidget);
        debugDefaultTargetPlatformOverride = null;
        await down(tester);
      });

      testWidgets('a move inside one organization, or among the person’s own folders, asks nothing', (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final store = storeOf();
        await page(tester, tree(store), size: size);
        await carry(tester, 'note-row-brief', 'folder-row-acme');
        expect(ask(), findsNothing);
        expect(store.value.of['brief'], 'acme');
        expect(find.text('Moved “Brief” to Ghost.md › Clients › Acme'), findsOneWidget);
        await tester.pump(const Duration(seconds: 6));
        await carry(tester, 'note-row-todo', 'folder-row-home');
        expect(ask(), findsNothing);
        expect(store.value.of['todo'], 'home');
        await tester.pump(const Duration(seconds: 6));
        await carry(tester, 'folder-row-acme', 'folder-row-$ghost');
        expect(ask(), findsNothing);
        expect(store.value.list.firstWhere((w) => w.id == 'acme').parent, ghost);
        debugDefaultTargetPlatformOverride = null;
        await down(tester);
      });
    });
  }

  testWidgets('on a Mac, Return is Move and Escape is Cancel', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final store = storeOf();
    await page(tester, tree(store), size: mac);
    await carry(tester, 'note-row-todo', 'folder-row-clients');
    expect(ask(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump(const Duration(milliseconds: 300));
    expect(ask(), findsNothing);
    expect(store.value.of['todo'], 'work');
    await carry(tester, 'note-row-todo', 'folder-row-clients');
    expect(ask(), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(ask(), findsNothing);
    expect(store.value.of['todo'], 'clients');
    debugDefaultTargetPlatformOverride = null;
    await down(tester);
  });

  testWidgets('a tap outside the sheet leaves everything where it was', (tester) async {
    final store = storeOf();
    await page(tester, allNotes(store), size: phone);
    await carry(tester, 'tile-note-loose', 'tile-folder-$ghost');
    expect(ask(), findsOneWidget);
    await tester.tapAt(const Offset(195, 40));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ask(), findsNothing);
    expect(store.value.of.containsKey('loose'), isFalse);
    await down(tester);
  });

  testWidgets('in simple mode the same sheet asks the same', (tester) async {
    final store = storeOf();
    await page(tester, allNotes(store), size: phone, prefs: const AppPreferences(theme: 'light', experience: 'simple', experienceChosen: true));
    await carry(tester, 'tile-note-loose', 'tile-folder-$ghost');
    expect(find.text('Move “Loose” to Ghost.md?'), findsOneWidget);
    expect(find.text('Everyone in Ghost.md will be able to read and edit it.'), findsOneWidget);
    await answer(tester, 'move-ask-yes');
    expect(store.value.of['loose'], ghost);
    await down(tester);
  });

  testWidgets('the folder gone while the sheet is up: Move moves nothing', (tester) async {
    final store = storeOf();
    await page(tester, allNotes(store), size: phone);
    await carry(tester, 'tile-note-loose', 'folder-chip-clients');
    expect(find.text('Move “Loose” to Ghost.md › Clients?'), findsOneWidget);
    // Clients deleted on another device, its settings landing here while the sheet asks.
    store.removeWorkspace('clients');
    await tester.pump();
    await answer(tester, 'move-ask-yes');
    expect(ask(), findsNothing);
    expect(store.value.of.containsKey('loose'), isFalse);
    await down(tester);
  });
}
