import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/folder_drag.dart';
import 'package:ghost_md/notes/folder_strip.dart';
import 'package:ghost_md/notes/icon_browser.dart';
import 'package:ghost_md/notes/note_menu.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:glacier/glacier.dart';

import '../library/support.dart' show FakeCore, libraryOver, makeNote;
import '../support/render.dart';

/// Notes and folders carried onto folders (lib/notes/folder_drag.dart; Matt, 2026-10-20: "also allow clicking and
/// dragging files into folders and folders into folders"): the rules, the move at the library, and the drag on the
/// icon view, the folder strip, the sidebar and a note's menu. Nobody in it is real.
void main() {
  setUpAll(loadAppFonts);
  tearDown(() => folderCarrying.value = null);

  const ghost = 'org-ghost', hello = 'org-hello';

  /// Two organizations with folders, and the personal ones: Ghost.md › Clients › Acme, HelloTrade › Designs, Work ›
  /// Kiln, Home.
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
        notes: {'plan': ghost, 'brief': 'clients', 'sketch': 'designs', 'todo': 'work'},
      );

  WorkspaceStore storeOf() => WorkspaceStore(storage: MemoryWorkspaceStorage(sheet()));

  List<Note> notes() => [
        makeNote('plan', body: '# Plan'),
        makeNote('brief', body: '# Brief'),
        makeNote('sketch', body: '# Sketch'),
        makeNote('todo', body: '# Todo'),
        makeNote('loose', body: '# Loose'),
      ];

  FolderCarry note(String id) => FolderCarry.note(id, id[0].toUpperCase() + id.substring(1));
  FolderCarry folder(WorkspaceStore store, String id) => FolderCarry.folder(id, store.value.list.firstWhere((w) => w.id == id).name);

  group('the rules', () {
    test('a note moves among the personal folders, or among one organization’s, and across only once asked', () {
      final store = storeOf();
      FolderLanding at(String id, String? to) => folderVerdict(store, note(id), to).landing;
      // Personal: to another personal folder, or to the top; into an organization once asked.
      expect(at('todo', 'home'), FolderLanding.moves);
      expect(at('todo', 'kiln'), FolderLanding.moves);
      expect(at('todo', null), FolderLanding.moves);
      expect(at('todo', 'work'), FolderLanding.stays);
      expect(at('todo', 'clients'), FolderLanding.asks);
      expect(at('todo', ghost), FolderLanding.asks);
      // Filed nowhere is personal: into a personal folder at once, into a team's once asked.
      expect(at('loose', 'home'), FolderLanding.moves);
      expect(at('loose', null), FolderLanding.stays);
      expect(at('loose', 'acme'), FolderLanding.asks);
      // The team's: to another of its organization's folders, or to the organization's own workspace, at once; out to
      // a personal folder or to the top once asked; never straight into another organization.
      expect(at('brief', 'acme'), FolderLanding.moves);
      expect(at('brief', ghost), FolderLanding.moves);
      expect(at('plan', 'clients'), FolderLanding.moves);
      expect(at('brief', 'work'), FolderLanding.asks);
      expect(at('brief', null), FolderLanding.refused);
      expect(at('brief', 'designs'), FolderLanding.refused);
      expect(at('sketch', hello), FolderLanding.moves);
      // What each asks, in the words of what the sync then does.
      FolderAsk ask(String id, String? to) => folderVerdict(store, note(id), to).ask!;
      expect(ask('todo', 'clients').title, 'Move “Todo” to Ghost.md › Clients?');
      expect(ask('todo', 'clients').note, 'Everyone in Ghost.md will be able to read and edit it.');
      expect(ask('brief', 'work').title, 'Move “Brief” to Work?');
      expect(ask('brief', 'work').note, 'It will no longer be shared with Ghost.md: it is taken out of the team and deleted for everyone else in Ghost.md. You keep it.');
      // Filed nowhere is no evidence it left the team (ddeb6141): out of it, a note goes into a folder of the person's.
      expect(folderVerdict(store, note('brief'), null).why, '“Brief” is Ghost.md’s: to take it out of the team, move it into one of your own folders.');
      expect(folderVerdict(store, note('brief'), 'designs').why, '“Brief” is Ghost.md’s. Move it into one of your own folders first; once that has synced, it can go into HelloTrade.');
      // Moves that need no asking ask nothing.
      expect(folderVerdict(store, note('brief'), 'acme').ask, isNull);
    });

    test('a folder carried across an organization’s edge asks, saying how many notes go with it', () {
      final store = WorkspaceStore(
        storage: MemoryWorkspaceStorage(WorkspaceSheet(list: sheet().list, notes: {...sheet().notes, 'a': 'work', 'b': 'kiln', 'c': 'work'})),
      );
      FolderVerdict at(String id, String? to) => folderVerdict(store, folder(store, id), to);
      // Work and Kiln inside it hold Todo, A, B and C.
      expect(at('work', hello).landing, FolderLanding.asks);
      expect(at('work', hello).ask!.title, 'Move Work and its 4 notes to HelloTrade?');
      expect(at('work', hello).ask!.note, 'Everyone in HelloTrade will be able to read and edit them.');
      expect(at('kiln', 'designs').ask!.title, 'Move Kiln and its note to HelloTrade › Designs?');
      expect(at('kiln', 'designs').ask!.note, 'Everyone in HelloTrade will be able to read and edit it.');
      expect(at('home', ghost).ask!.title, 'Move Home to Ghost.md?');
      expect(at('home', ghost).ask!.note, 'Everyone in Ghost.md will be able to read and edit the notes you put in it.');
      // Out of an organization, to the top or a personal folder; and into another.
      expect(at('clients', null).ask!.title, 'Move Clients and its note to the top of your own notes?');
      expect(at('clients', null).ask!.note, 'It will no longer be shared with Ghost.md: it is taken out of the team and deleted for everyone else in Ghost.md. You keep it.');
      expect(at('acme', 'home').ask!.title, 'Move Acme to Home?');
      expect(at('acme', 'home').ask!.note, 'It has no notes, so nothing is taken from anyone in Ghost.md.');
      expect(at('designs', 'work').ask!.title, 'Move Designs and its note to Work?');
      // From one organization into another: an empty folder once asked; one with notes in it never straight across.
      expect(at('acme', 'designs').ask!.note, 'It has no notes, so nothing is taken from anyone in Ghost.md. Everyone in HelloTrade will be able to read and edit the notes you put in it.');
      expect(at('clients', hello).why, 'Clients holds Ghost.md’s notes. Move it into one of your own folders first; once that has synced, it can go into HelloTrade.');
      // Still never into itself, and an organization's own workspace never at all.
      expect(at('work', 'kiln').landing, FolderLanding.refused);
      expect(at(ghost, 'work').landing, FolderLanding.refused);
    });

    test('a folder moves into another of its own space, never into itself or one inside it, and across only once asked', () {
      final store = storeOf();
      FolderVerdict at(String id, String? to) => folderVerdict(store, folder(store, id), to);
      expect(at('kiln', 'home').landing, FolderLanding.moves);
      expect(at('kiln', null).landing, FolderLanding.moves);
      expect(at('kiln', 'work').landing, FolderLanding.stays);
      expect(at('home', 'kiln').landing, FolderLanding.moves);
      // Into itself, or a folder inside it.
      expect(at('work', 'work').why, 'A folder can’t go inside itself.');
      expect(at('work', 'kiln').why, 'A folder can’t go inside itself.');
      expect(at('clients', 'acme').why, 'A folder can’t go inside itself.');
      // Within its organization, up to its workspace, at once; to the top, out to a personal folder or into another
      // once asked.
      expect(at('acme', ghost).landing, FolderLanding.moves);
      expect(at('clients', ghost).landing, FolderLanding.stays);
      expect(at('acme', null).landing, FolderLanding.asks);
      expect(at('acme', 'work').landing, FolderLanding.asks);
      expect(at('acme', 'designs').landing, FolderLanding.asks);
      expect(at('clients', 'designs').landing, FolderLanding.refused);
      expect(at('kiln', 'clients').landing, FolderLanding.asks);
      // An organization's own workspace is never moved.
      expect(at(ghost, 'work').why, 'An organization’s workspace stays at the top.');
    });

    test('Move to lists where each may go, the top first, never where it is', () {
      final store = storeOf();
      expect(folderDestinations(store, note('todo')).map((d) => d.name), ['Out of every folder', 'Work › Kiln', 'Home']);
      expect(folderDestinations(store, note('brief')).map((d) => d.id), [ghost, 'acme']);
      expect(folderDestinations(store, folder(store, 'kiln')).map((d) => d.name), ['The top level', 'Home']);
      expect(folderDestinations(store, folder(store, 'acme')).map((d) => d.name), ['Ghost.md']);
      expect(folderDestinations(store, folder(store, ghost)), isEmpty);
    });

    test('a move says where to, and its Undo puts it back', () {
      final store = storeOf();
      final moved = moveCarried(store, note('brief'), 'acme')!;
      expect(moved.said, 'Moved “Brief” to Ghost.md › Clients › Acme');
      expect(store.value.of['brief'], 'acme');
      moved.undo!();
      expect(store.value.of['brief'], 'clients');
      final out = moveCarried(store, note('todo'), null)!;
      expect(out.said, 'Took “Todo” out of Work');
      expect(store.value.of['todo'], isNull);
      out.undo!();
      expect(store.value.of['todo'], 'work');
      final up = moveCarried(store, folder(store, 'kiln'), null)!;
      expect(up.said, 'Moved Kiln to the top level');
      expect(store.value.list.firstWhere((w) => w.id == 'kiln').parent, isNull);
      up.undo!();
      expect(store.value.list.firstWhere((w) => w.id == 'kiln').parent, 'work');
      // A refused move moves nothing; nor does one across an organization's edge that was not asked about.
      expect(moveCarried(store, note('brief'), 'work'), isNull);
      expect(moveCarried(store, folder(store, 'work'), 'kiln'), isNull);
      expect(moveCarried(store, folder(store, 'work'), 'kiln', asked: true), isNull);
      expect(moveCarried(store, folder(store, 'kiln'), 'clients'), isNull);
      expect(store.value.of['brief'], 'clients');
      expect(store.value.list.firstWhere((w) => w.id == 'kiln').parent, 'work');
    });

    test('a move across an organization’s edge, once asked, is the note’s filing alone, says so, and has no Undo', () {
      final store = storeOf();
      final into = moveCarried(store, note('todo'), 'clients', asked: true)!;
      expect(into.said, 'Moved “Todo” to Ghost.md › Clients');
      expect(into.undo, isNull);
      expect(store.value.of['todo'], 'clients');
      expect(store.orgOf('clients'), 'ghost');
      // Never straight on into another, asked or not.
      expect(moveCarried(store, note('todo'), 'designs', asked: true), isNull);
      expect(store.value.of['todo'], 'clients');
      // Nor out to the top level, where it would still be the team's.
      expect(moveCarried(store, note('todo'), null, asked: true), isNull);
      final out = moveCarried(store, note('todo'), 'home', asked: true)!;
      expect(out.said, 'Moved “Todo” to Home');
      expect(store.value.of['todo'], 'home');
      // Nothing else moved, nothing was lost: every other filing is as it was.
      expect(store.value.of, {'plan': ghost, 'brief': 'clients', 'sketch': 'designs', 'todo': 'home'});
    });

    test('a folder carried across takes its notes and its folders, and leaves its trashed notes on the side they were on', () {
      final trash = MemoryTrash();
      final store = WorkspaceStore(
        storage: MemoryWorkspaceStorage(WorkspaceSheet(list: sheet().list, notes: {...sheet().notes, 'a': 'kiln', 'gone': 'kiln', 'old': 'acme'})),
        trash: trash,
      );
      trash.trashNote('gone', 5);
      trash.trashNote('old', 5);
      final into = moveCarried(store, folder(store, 'work'), hello, asked: true)!;
      expect(into.said, 'Moved Work to HelloTrade');
      expect(into.undo, isNull);
      expect(store.value.list.firstWhere((w) => w.id == 'work').parent, hello);
      // Todo and A are HelloTrade's now, Kiln with them; Gone, in the trash, stays the account's, at the top.
      expect(store.orgOf('work'), 'hello');
      expect(store.orgOf('kiln'), 'hello');
      expect(store.value.of['todo'], 'work');
      expect(store.value.of['a'], 'kiln');
      expect(store.value.of.containsKey('gone'), isFalse);
      // Clients out of Ghost.md, to the top: Brief goes with it; Old, trashed in Acme, stays in Ghost.md's workspace.
      moveCarried(store, folder(store, 'clients'), null, asked: true);
      expect(store.value.list.firstWhere((w) => w.id == 'clients').parent, isNull);
      expect(store.orgOf('acme'), isNull);
      expect(store.value.of['brief'], 'clients');
      expect(store.value.of['old'], ghost);
      expect(store.value.of['plan'], ghost);
    });

    test('a note moved keeps its id, its words and its file’s name: only its folder changes', () async {
      final core = FakeCore()
        ..seed('brief', '# Brief\n\nFor the team.', path: 'orgs/Ghost.md/Clients/Brief.md')
        ..seed('trip', '# Trip\n\nTrains at 9.', path: 'workspaces/Work/Trip.md');
      final it = libraryOver(core);
      await it.library.load();
      late final WorkspaceStore store;
      final folders = NoteFolders(it.library, log: it.said.add, workspaces: () => store.value.list);
      store = WorkspaceStore(
        storage: MemoryWorkspaceStorage(WorkspaceSheet(list: sheet().list, notes: const {'brief': 'clients', 'trip': 'work'})),
        onFiled: folders.fileNotesInFolder,
      );
      final before = {for (final id in ['brief', 'trip']) id: (await it.library.get(id))!};
      moveCarried(store, const FolderCarry.note('brief', 'Brief'), 'acme');
      moveCarried(store, const FolderCarry.note('trip', 'Trip'), 'home');
      await folders.fileNotesInFolder(const [], null);
      expect(core.files, ['orgs/Ghost.md/Clients/Acme/Brief.md', 'workspaces/Home/Trip.md']);
      for (final id in ['brief', 'trip']) {
        final after = (await it.library.get(id))!;
        expect(after.id, before[id]!.id);
        expect(after.body, before[id]!.body);
        expect(after.createdAt, before[id]!.createdAt);
        expect(after.path!.split('/').last, before[id]!.path!.split('/').last);
      }
      // A folder carried into another takes its notes' files with it, words untouched.
      moveCarried(store, const FolderCarry.folder('kiln', 'Kiln'), 'home');
      store.fileNote('trip', 'kiln');
      await folders.fileNotesInFolder(const [], null);
      expect(core.files, ['orgs/Ghost.md/Clients/Acme/Brief.md', 'workspaces/Home/Kiln/Trip.md']);
      expect((await it.library.get('trip'))!.body, '# Trip\n\nTrains at 9.');
    });
  });

  group('on screen', () {
    Future<void> page(WidgetTester tester, Widget child, {Size size = const Size(900, 900)}) async {
      await pumpApp(tester, size: size, prefs: const AppPreferences(theme: 'light'), home: BackScope(child: Align(alignment: Alignment.topLeft, child: child)));
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

    /// A finger's carry: held until it lifts, then along to [to], where it is let go. Answers what [during] saw
    /// while it was held over [to].
    Future<T?> hold<T>(WidgetTester tester, String from, String to, {T Function()? during}) async {
      final gesture = await tester.startGesture(centre(tester, from));
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(0, 4));
      await tester.pump();
      await gesture.moveTo(centre(tester, to));
      await tester.pump();
      await tester.pump();
      final seen = during?.call();
      await gesture.up();
      await tester.pump();
      return seen;
    }

    /// A mouse's carry: pressed, moved, let go.
    Future<T?> drag<T>(WidgetTester tester, String from, String to, {T Function()? during}) async {
      final gesture = await tester.startGesture(centre(tester, from), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
      await gesture.moveTo(centre(tester, to));
      await tester.pump();
      await tester.pump();
      final seen = during?.call();
      await gesture.up();
      await tester.pump();
      return seen;
    }

    /// Whether the drop zone [key] draws itself refusing what is held over it: the forbidden pointer, faded.
    bool refusing(String key) => find
        .descendant(of: find.byKey(ValueKey(key)), matching: find.byWidgetPredicate((w) => w is MouseRegion && w.cursor == SystemMouseCursors.forbidden))
        .evaluate()
        .isNotEmpty;

    /// Whether the drop zone [key] wears the ring of one that takes it.
    bool taking(String key) {
      final ring = find.descendant(of: find.byKey(ValueKey(key)), matching: find.byKey(const ValueKey('drop-ring')));
      final decoration = (ring.evaluate().first.widget as DecoratedBox).decoration as BoxDecoration;
      return decoration.border != null && !refusing(key);
    }

    Widget icons(WorkspaceStore store, List<String> opened, {String? chosen}) => ListenableBuilder(
          listenable: store,
          builder: (context, _) => SizedBox(
            width: 600,
            child: IconBrowser(
              folders: folderTiles(store.value.list, store.value.of, notes(), chosen),
              notes: [for (final n in notes()) if (store.value.of[n.id] == chosen) n],
              onFolder: (_) {},
              onOpen: opened.add,
              store: store,
            ),
          ),
        );

    testWidgets('a finger holds a note’s tile and carries it onto a folder’s: filed there, said in a toast whose Undo puts it back', (tester) async {
      final store = storeOf();
      final opened = <String>[];
      await page(tester, icons(store, opened));
      final lit = await hold(tester, 'tile-note-loose', 'tile-folder-home', during: () => (pill: find.byKey(const ValueKey('carry-pill')).evaluate().length, taking: taking('drop-home')));
      // While held over it: the pill follows the finger, and Home wears the ring of a folder that takes it.
      expect(lit!.pill, 1);
      expect(lit.taking, isTrue);
      expect(store.value.of['loose'], 'home');
      expect(find.text('Moved “Loose” to Home'), findsOneWidget);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(store.value.of['loose'], isNull);
      // A tap still opens, and moves nothing.
      await tester.tap(find.byKey(const ValueKey('tile-note-loose')));
      await tester.pump();
      expect(opened, ['loose']);
      expect(store.value.of['loose'], isNull);
      await down(tester);
    });

    testWidgets('a mouse drags a folder’s chip onto another’s, and onto the line above to go back up', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final store = WorkspaceStore(storage: MemoryWorkspaceStorage(WorkspaceSheet(list: [...sheet().list, const Workspace(id: 'studio', name: 'Studio', parent: 'work')], notes: sheet().notes)));
      var chosen = 'work';
      await page(
        tester,
        StatefulBuilder(
          builder: (context, set) => ListenableBuilder(
            listenable: store,
            builder: (context, _) => SizedBox(
              width: 600,
              child: FolderStrip(list: store.value.list, of: store.value.of, notes: notes(), chosen: chosen, onChoose: (id) => set(() => chosen = id), store: store),
            ),
          ),
        ),
      );
      // Studio onto Kiln: inside it.
      await drag(tester, 'folder-chip-studio', 'folder-chip-kiln');
      expect(store.value.list.firstWhere((w) => w.id == 'studio').parent, 'kiln');
      expect(find.text('Moved Studio to Work › Kiln'), findsOneWidget);
      // In Kiln, Studio's chip onto Work on the line above: back up a level.
      await tester.tap(find.byKey(const ValueKey('folder-chip-kiln')));
      await tester.pump();
      expect(find.byKey(const ValueKey('folder-chip-studio')), findsOneWidget);
      await drag(tester, 'folder-chip-studio', 'crumb-work');
      expect(store.value.list.firstWhere((w) => w.id == 'studio').parent, 'work');
      debugDefaultTargetPlatformOverride = null;
      await down(tester);
    });

    Widget tree(WorkspaceStore store) => SizedBox(
          width: 320,
          height: 900,
          // Names only, so every row is on the screen.
          child: NoteTree(notes: notes(), activeId: null, onOpen: (_) {}, onNew: () {}, workspaces: store, stored: MemoryStored()..writeText('glyph-tree-compact', '1')),
        );

    testWidgets('the sidebar refuses a folder into itself or one inside it, saying why, and moves a team note within its organization at once', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final store = storeOf();
      await page(tester, tree(store));
      // Work onto Kiln, inside it: refused, drawn refusing while held there.
      expect(await drag(tester, 'folder-row-work', 'folder-row-kiln', during: () => refusing('drop-kiln')), isTrue);
      expect(store.value.list.firstWhere((w) => w.id == 'work').parent, isNull);
      expect(find.text('A folder can’t go inside itself.'), findsOneWidget);
      // A team note into another of its organization's folders: filed at once, nothing asked, and the folder it went
      // to opens. (Across an organization's line it asks: test/notes/folder_ask_test.dart.)
      await tester.pump(const Duration(seconds: 6));
      expect(await drag(tester, 'note-row-brief', 'folder-row-acme', during: () => taking('drop-acme')), isTrue);
      expect(store.value.of['brief'], 'acme');
      expect(find.text('Moved “Brief” to Ghost.md › Clients › Acme'), findsOneWidget);
      expect(find.byKey(const ValueKey('move-ask')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
      await down(tester);
    });

    testWidgets('while a personal folder is carried, the top level stands over the sidebar’s tools, and takes it', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final store = storeOf();
      await page(tester, tree(store));
      expect(find.byKey(const ValueKey('drop-top')), findsNothing);
      // An organization's folder is offered it too, as a move out of the organization that asks first.
      final gesture = await tester.startGesture(centre(tester, 'folder-row-acme'), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(0, 12));
      await tester.pump();
      expect(find.byKey(const ValueKey('drop-top')), findsOneWidget);
      await gesture.up();
      await tester.pump();
      // Kiln, inside Work: the top level is offered while it is carried, and it lands there.
      final kiln = await tester.startGesture(centre(tester, 'folder-row-kiln'), kind: PointerDeviceKind.mouse);
      await kiln.moveBy(const Offset(0, 12));
      await tester.pump();
      expect(find.byKey(const ValueKey('drop-top')), findsOneWidget);
      await kiln.moveTo(centre(tester, 'drop-top'));
      await tester.pump();
      await kiln.up();
      await tester.pump();
      expect(store.value.list.firstWhere((w) => w.id == 'kiln').parent, isNull);
      expect(find.text('Moved Kiln to the top level'), findsOneWidget);
      expect(find.byKey(const ValueKey('drop-top')), findsNothing);
      debugDefaultTargetPlatformOverride = null;
      await down(tester);
    });

    testWidgets('a note’s menu offers Move to, the folders it may go to, and moves it as a drag would', (tester) async {
      final store = storeOf();
      final menu = NoteMenuController();
      await page(
        tester,
        SizedBox(
          width: 900,
          height: 900,
          child: Stack(
            children: [
              const Positioned.fill(child: SizedBox.expand()),
              NoteMenuHost(controller: menu, notes: notes(), coarse: true, onOpen: (_) {}, onPin: (_) {}, onArchive: (_, _) {}, onDelete: (_) {}, workspaces: store),
            ],
          ),
        ),
      );
      menu.open('todo', const Offset(20, 20));
      for (var i = 0; i < 6; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final rows = [for (final item in tester.widgetList<GlacierMenuItem>(find.byType(GlacierMenuItem))) (item.child as Text).data!];
      expect(rows, containsAllInOrder(['Archive', 'Out of every folder', 'Work › Kiln', 'Home', 'Delete']));
      expect(rows, isNot(contains('Ghost.md')));
      await tester.tap(find.text('Home'));
      await tester.pump();
      expect(store.value.of['todo'], 'home');
      expect(find.text('Moved “Todo” to Home'), findsOneWidget);
      await down(tester);
    });

    testWidgets('a screen reader is offered Move to… on a tile, a menu of where it may go', (tester) async {
      final handle = tester.ensureSemantics();
      final store = storeOf();
      await page(tester, icons(store, []));
      final action = CustomSemanticsAction.getIdentifier(const CustomSemanticsAction(label: 'Move to…'));
      final node = tester.getSemantics(find.byKey(const ValueKey('tile-note-loose')));
      SemanticsNode? withAction = node;
      while (withAction != null && !(withAction.getSemanticsData().customSemanticsActionIds?.contains(action) ?? false)) {
        withAction = withAction.parent;
      }
      expect(withAction, isNotNull);
      withAction!.owner!.performAction(withAction.id, SemanticsAction.customAction, action);
      for (var i = 0; i < 4; i += 1) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final rows = [for (final item in tester.widgetList<GlacierMenuItem>(find.byType(GlacierMenuItem))) (item.child as Text).data!];
      expect(rows, ['Work', 'Work › Kiln', 'Home']);
      await tester.tap(find.text('Work › Kiln'));
      await tester.pump();
      expect(store.value.of['loose'], 'kiln');
      handle.dispose();
      await down(tester);
    });
  });
}
