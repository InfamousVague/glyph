import 'dart:ui' show Tristate;

import 'package:flutter/foundation.dart' show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart' hide WorkspaceSheet;
import 'package:ghost_md/notes/book_place_mark.dart';
import 'package:ghost_md/notes/note_peek.dart';
import 'package:ghost_md/notes/note_tree.dart';
import 'package:ghost_md/notes/org_mark.dart';
import 'package:ghost_md/notes/tree.dart';
import 'package:ghost_md/sheet/css.dart';
import 'package:ghost_md/sheet/sheet.dart';
import 'package:glacier/glacier.dart';

import '../support/icons.dart';
import '../support/render.dart';
import '../support/editor_text.dart';
import 'support.dart';

/// The sidebar's tree (notes/note_tree.dart): `notes/NoteTree.test.tsx` case for case, then what that file leaves to
/// the eye - each tool's callback, what a screen reader is told, the docked form, and the seams this port adds.
Note makeNote(String id, {String? body, int updatedAt = 0, bool starred = false, int? archivedAt}) =>
    Note(id: id, body: body ?? '# $id', createdAt: 0, updatedAt: updatedAt, starred: starred, archivedAt: archivedAt);

void main() {
  setUpAll(loadAppFonts);

  late MemoryStored local;
  late WorkspaceStore spaces;
  setUp(() {
    local = MemoryStored();
    spaces = WorkspaceStore();
  });

  /// The tree as the docked sidebar holds it: in a column 320 wide, the window's height.
  Future<void> show(WidgetTester tester, NoteTree tree, {Size size = const Size(390, 844)}) => pumpPage(
        tester,
        BackScope(child: Align(alignment: Alignment.topLeft, child: SizedBox(width: 320, child: tree))),
        size: size,
      );

  NoteTree tree({
    List<Note> notes = const [],
    String? activeId,
    List<Note> trashed = const [],
    void Function(String)? onOpen,
    VoidCallback? onNew,
    VoidCallback? onCommands,
    VoidCallback? onSettings,
    VoidCallback? onSpeak,
    VoidCallback? onClose,
    VoidCallback? onBrowseFiles,
    VoidCallback? onEmptyTrash,
    void Function(Note)? onRestore,
    void Function(Note)? onDestroy,
    void Function(String)? onOrganization,
    void Function(String, Offset)? onNoteMenu,
    List<Widget> notices = const [],
    Widget? emptyArt,
    NotePeekBuilder peek = NotePeek.plain,
  }) =>
      NoteTree(
        notes: notes,
        activeId: activeId,
        trashed: trashed,
        onOpen: onOpen ?? (_) {},
        onNew: onNew ?? () {},
        onCommands: onCommands,
        onSettings: onSettings,
        onSpeak: onSpeak,
        onClose: onClose,
        onBrowseFiles: onBrowseFiles,
        onEmptyTrash: onEmptyTrash,
        onRestore: onRestore,
        onDestroy: onDestroy,
        onOrganization: onOrganization,
        onNoteMenu: onNoteMenu,
        notices: notices,
        emptyArt: emptyArt,
        peek: peek,
        workspaces: spaces,
        stored: local,
      );

  final rowKeys = find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('note-row-'));

  /// The names on the notes' rows, top to bottom.
  List<String> rows(WidgetTester tester) => [
        for (final row in rowKeys.evaluate()) tester.widget<Text>(find.descendant(of: find.byElementPredicate((e) => e == row), matching: find.byType(Text)).first).data!,
      ];

  Finder button(String label) => find.bySemanticsLabel(label);
  Finder folder(String name) => find.ancestor(of: find.text(name), matching: find.byType(GlacierPressable)).first;
  bool expanded(WidgetTester tester, String name) => tester.getSemantics(folder(name)).flagsCollection.isExpanded == Tristate.isTrue;
  final kinds = find.byKey(const ValueKey('kind-mark'));

  group('the sidebar, names only', () {
    testWidgets('lists each note as its kind and its name, no drawing, and keeps the choice on the device', (tester) async {
      final notes = [makeNote('b', body: bookNoteBody('Trip', ['Packing'])), makeNote('p', body: '# Packing\n\n- [ ] Tent'), makeNote('c', body: '---\ntitle: "Map"\n---\n{"nodes":[],"edges":[]}')];
      await show(tester, tree(notes: notes));
      expect(kinds, findsNothing);
      expect(find.byType(NotePeek), findsWidgets);
      await tester.tap(button('Show names only'));
      await tester.pump();
      // One mark per note, and no note drawn small.
      expect(kinds, findsNWidgets(3));
      expect(find.byType(NotePeek), findsNothing);
      expect(local.getItem('glyph-tree-compact'), '1');
      // A book, a page of words, a canvas.
      expect([for (final icon in tester.widgetList<AppIcon>(find.descendant(of: kinds, matching: find.byType(AppIcon)))) icon.icon], unorderedEquals([Lucide.bookOpen, Lucide.fileText, Lucide.workflow]));
      // Names only has no room for the book a page is in.
      expect(find.byType(BookPlaceMark), findsNothing);
      await tester.tap(button('Show each note drawn small'));
      await tester.pump();
      expect(kinds, findsNothing);
      expect(local.getItem('glyph-tree-compact'), '0');
      // Drawn small, a page of a book says which book, and which page in full to whoever asks.
      final mark = tester.widget<BookPlaceMark>(find.byType(BookPlaceMark));
      expect(mark.said, 'Page 1 of Trip');
      expect(find.descendant(of: find.byType(BookPlaceMark), matching: find.text('Trip')), findsOneWidget);
      await away(tester);
    });

    testWidgets('opens as it was left: names only, where the device said so', (tester) async {
      writeCompact(true, local);
      await show(tester, tree(notes: [makeNote('a', body: '# Apples\n\nRed ones.')]));
      expect(kinds, findsOneWidget);
      expect(button('Show each note drawn small'), findsOneWidget);
      await away(tester);
    });

    testWidgets('offers Browse files only where the device can show the folder', (tester) async {
      await show(tester, tree());
      expect(button('Browse files'), findsNothing);
      var browsed = 0;
      await show(tester, tree(onBrowseFiles: () => browsed += 1));
      await tester.tap(button('Browse files'));
      expect(browsed, 1);
      await away(tester);
    });
  });

  group('the sidebar’s folders', () {
    testWidgets('puts each workspace’s notes in its folder, folds one shut and remembers it, and folds or opens them all', (tester) async {
      final handle = tester.ensureSemantics();
      final kitchen = spaces.addWorkspace('Kitchen')!;
      spaces.fileNote('a', kitchen.id);
      await show(tester, tree(notes: [makeNote('a', body: '# Apples'), makeNote('b', body: '# Bread')], activeId: 'b'));
      expect(rows(tester), ['Apples', 'Bread']);
      // `aria-current="page"` on the open note's row, and a ring round it.
      final open = tester.getSemantics(find.ancestor(of: find.text('Bread'), matching: find.byType(GlacierPressable)).first);
      expect(open.flagsCollection.isSelected, Tristate.isTrue);
      expect(tester.getSemantics(find.ancestor(of: find.text('Apples'), matching: find.byType(GlacierPressable)).first).flagsCollection.isSelected, isNot(Tristate.isTrue));
      expect(expanded(tester, 'Kitchen'), isTrue);
      await tester.tap(find.text('Kitchen'));
      await tester.pump();
      expect(expanded(tester, 'Kitchen'), isFalse);
      expect(rows(tester), ['Bread']);
      expect(local.read<List<Object?>>('glyph-tree-closed', const []), contains(kitchen.id));
      await tester.tap(button('Open every folder'));
      await tester.pump();
      expect(rows(tester), ['Apples', 'Bread']);
      await tester.tap(button('Fold every folder'));
      await tester.pump();
      expect(rows(tester), ['Bread']);
      handle.dispose();
      await away(tester);
    });

    testWidgets('says how many notes a folder holds, and that an empty one is', (tester) async {
      final kitchen = spaces.addWorkspace('Kitchen')!;
      spaces.addWorkspace('Garden');
      spaces
        ..fileNote('a', kitchen.id)
        ..fileNote('b', kitchen.id);
      await show(tester, tree(notes: [makeNote('a'), makeNote('b'), makeNote('c')]));
      expect(find.descendant(of: folder('Kitchen'), matching: find.text('2')), findsOneWidget);
      expect(find.descendant(of: folder('Garden'), matching: find.text('0')), findsOneWidget);
      expect(find.text('Nothing here yet.'), findsOneWidget);
      // No folder, no tool to fold them with.
      spaces
        ..removeWorkspace(kitchen.id)
        ..removeWorkspace(spaces.value.list[0].id);
      await tester.pump();
      expect(button('Fold every folder'), findsNothing);
      expect(rows(tester), ['a', 'b', 'c']);
      await away(tester);
    });

    // An organization's workspace (docs/TEAMS.md, D5): marked, and its menu is the organization's own screen.
    testWidgets('marks an organization’s folder, whose menu opens the organization rather than the workspace sheet', (tester) async {
      final handle = tester.ensureSemantics();
      spaces.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Ghost', hue: 'sea'));
      spaces.addWorkspace('Kitchen');
      final opened = <String>[];
      await show(tester, tree(notes: [makeNote('a', body: '# Apples')], onOrganization: opened.add));
      expect(find.byType(OrgMark), findsOneWidget);
      expect(find.descendant(of: folder('Ghost'), matching: find.byType(OrgMark)), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Organization')), findsWidgets);
      await tester.tap(button('Ghost, organization settings'));
      await tester.pump();
      expect(opened, ['o1']);
      expect(find.byType(Sheet), findsNothing);
      await tester.tap(button('Rename, recolour or delete Kitchen'));
      await tester.pump();
      expect(tester.widget<Sheet>(find.byType(Sheet)).label, 'Kitchen');
      handle.dispose();
      await away(tester);
    });

    testWidgets('with no organization screen to open, an organization’s menu falls back to its sheet', (tester) async {
      spaces.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Ghost'));
      await show(tester, tree(notes: [makeNote('a')]));
      await tester.tap(button('Ghost, organization settings'));
      await tester.pump();
      expect(tester.widget<Sheet>(find.byType(Sheet)).label, 'Ghost');
      expect(find.textContaining('Notes filed here are the team’s'), findsOneWidget);
      await away(tester);
    });

    testWidgets('makes a workspace from its tool, which the tree then shows', (tester) async {
      await show(tester, tree(notes: [makeNote('a')]));
      await tester.tap(button('New workspace'));
      await settle(tester);
      expect(tester.widget<Sheet>(find.byType(Sheet)).label, 'New workspace');
      await tester.enterText(find.byType(EditableText), 'Garden');
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.byType(Sheet), findsNothing);
      expect(spaces.value.list.single.name, 'Garden');
      expect(find.text('Garden'), findsOneWidget);
      await away(tester);
    });

    testWidgets('wears each workspace’s colour on its dot, and ink where it has none', (tester) async {
      spaces.addWorkspace('Work', 'moss');
      spaces.addWorkspace('Garden');
      await show(tester, tree(notes: [makeNote('a')]));
      final dots = find.byKey(const ValueKey('folder-hue'));
      final t = tester.element(find.byType(NoteTree)).tokens;
      Color fill(int at) => (tester.widget<Container>(dots.at(at)).decoration! as BoxDecoration).color!;
      // ink.css `[data-hue='moss'] { --app-space: oklch(var(--app-hue-lift) var(--app-hue-chroma) 150) }`
      expect(fill(0), t.child(attrs: {'hue': 'moss'}).color('app-space'));
      expect(fill(1), t.color('app-ink'));
      expect(fill(0), isNot(fill(1)));
      await away(tester);
    });

    testWidgets('keeps the archive shut until it is opened', (tester) async {
      await show(tester, tree(notes: [makeNote('a', body: '# Apples'), makeNote('z', body: '# Old', archivedAt: 1)]));
      expect(rows(tester), ['Apples']);
      expect(expanded(tester, 'Archive'), isFalse);
      await tester.tap(find.text('Archive'));
      await tester.pump();
      expect(rows(tester), ['Apples', 'Old']);
      await away(tester);
    });

    testWidgets('says there are no notes yet when there are none, under whatever is drawn for it', (tester) async {
      await show(tester, tree());
      expect(find.text('No notes yet.'), findsOneWidget);
      await show(tester, tree(emptyArt: const SizedBox(key: ValueKey('ghost'), width: 60, height: 80)));
      final t = tester.element(find.byType(NoteTree)).tokens;
      final art = tester.getRect(find.byKey(const ValueKey('ghost')));
      // `.emptyArt { margin-block-end: var(--glacier-space-3) }`
      expect(tester.getRect(find.text('No notes yet.')).top, closeTo(art.bottom + t.space(3), 0.01));
      await away(tester);
    });
  });

  group('the trash', () {
    final trashed = [makeNote('t1', body: '# Torn'), makeNote('t2', body: '')];

    testWidgets('is shut until opened, and brings a note back or deletes it for good from its row', (tester) async {
      final restored = <Note>[], destroyed = <Note>[], openedNotes = <String>[];
      await show(tester, tree(trashed: trashed, onRestore: restored.add, onDestroy: destroyed.add, onOpen: openedNotes.add));
      expect(button('Restore Torn'), findsNothing);
      // The trash alone is not "no notes".
      expect(find.text('No notes yet.'), findsNothing);
      await tester.tap(find.text('Trash'));
      await tester.pump();
      expect(local.getItem('glyph-tree-trash-open'), '1');
      await tester.tap(button('Restore Torn'));
      await tester.tap(button('Delete Untitled for good'));
      expect(restored, [trashed[0]]);
      expect(destroyed, [trashed[1]]);
      // Not a way into the note.
      await tester.tap(find.text('Torn'));
      expect(openedNotes, isEmpty);
      await away(tester);
    });

    testWidgets('empties only on a second press, asked on the button itself, and stops asking after a few seconds', (tester) async {
      var emptied = 0;
      await show(tester, tree(trashed: trashed, onEmptyTrash: () => emptied += 1));
      final t = tester.element(find.byType(NoteTree)).tokens;
      Color ink(String text) => tester.widget<Text>(find.text(text)).style!.color!;
      expect(ink('Empty'), t.color('app-ink-3'));
      await tester.tap(find.text('Empty'));
      await tester.pump();
      expect(emptied, 0);
      // Asking: the kit's danger ink, the one colour a Delete may wear.
      expect(ink('Delete 2 for good?'), t.color('glacier-danger-text'));
      await tester.pump(const Duration(milliseconds: 4000));
      expect(find.text('Empty'), findsOneWidget);
      await tester.tap(find.text('Empty'));
      await tester.pump();
      await tester.tap(find.text('Delete 2 for good?'));
      await tester.pump();
      expect(emptied, 1);
      expect(find.text('Empty'), findsOneWidget);
      await away(tester);
    });

    testWidgets('has no Empty and no buttons where nothing was given to do with them', (tester) async {
      writeTrashOpen(true, local);
      await show(tester, tree(trashed: trashed));
      expect(find.text('Empty'), findsNothing);
      expect(find.text('Torn'), findsOneWidget);
      expect(button('Restore Torn'), findsNothing);
      expect(button('Delete Torn for good'), findsNothing);
      await away(tester);
    });
  });

  group('the sidebar’s tools and foot', () {
    testWidgets('carries what is waiting over the foot, and Speak and Settings in it', (tester) async {
      var spoke = 0, settings = 0;
      await show(tester, tree(onSpeak: () => spoke += 1, onSettings: () => settings += 1, notices: const [Text('An update')]));
      final notices = tester.getRect(find.byKey(const ValueKey('tree-notices')));
      final foot = tester.getRect(find.byKey(const ValueKey('tree-foot')));
      expect(find.descendant(of: find.byKey(const ValueKey('tree-notices')), matching: find.text('An update')), findsOneWidget);
      expect(notices.bottom, foot.top);
      // Docked, it fills its column: the foot is at the window's foot.
      expect(foot.bottom, 844);
      await tester.tap(find.text('Speak'));
      await tester.tap(button('Settings'));
      expect([spoke, settings], [1, 1]);
      await away(tester);
    });

    testWidgets('has no foot with nothing to put in it, and nothing where nothing is waiting', (tester) async {
      await show(tester, tree(notes: [makeNote('a')]));
      expect(find.byKey(const ValueKey('tree-foot')), findsNothing);
      expect(find.byKey(const ValueKey('tree-notices')), findsNothing);
      await away(tester);
    });

    testWidgets('tells each tool’s press to its own callback, and is a pop-up only when it can be closed', (tester) async {
      final handle = tester.ensureSemantics();
      final pressed = <String>[];
      final opened = <String>[];
      await show(tester, tree(notes: [makeNote('a', body: '# Apples')], onNew: () => pressed.add('new'), onCommands: () => pressed.add('commands'), onOpen: opened.add));
      expect(button('Close'), findsNothing);
      final t = tester.element(find.byType(NoteTree)).tokens;
      // Docked, under the app's bar: `padding-block-start: var(--app-safe-top)`.
      expect(tester.getRect(button('New note')).top, closeTo(t.len('app-safe-top') + t.space(2), 0.01));
      await tester.tap(button('New note'));
      await tester.tap(button('Search and commands'));
      await tester.tap(find.text('Apples'));
      expect(pressed, ['new', 'commands']);
      expect(opened, ['a']);
      // Named for a screen reader, as a toolbar and a list are.
      expect(find.bySemanticsLabel('Notes'), findsOneWidget);
      expect(find.bySemanticsLabel('Your notes'), findsOneWidget);
      expect(tester.getSemantics(button('New note')).flagsCollection.isButton, isTrue);

      await show(tester, tree(notes: [makeNote('a')], onClose: () => pressed.add('close')));
      expect(tester.getRect(button('New note')).top, closeTo(t.space(2), 0.01));
      await tester.tap(button('Close'));
      expect(pressed.last, 'close');
      // Without a palette there is no way into it.
      expect(button('Search and commands'), findsNothing);
      handle.dispose();
      await away(tester);
    });
  });

  group('what this port asks of its caller', () {
    testWidgets('draws each note small with whatever it is handed, and nothing for a note with nothing to draw', (tester) async {
      final asked = <String>[];
      Widget? peek(BuildContext context, String body) {
        asked.add(body);
        return body.contains('Red') ? const SizedBox(key: ValueKey('drawn'), height: 40) : null;
      }

      await show(tester, tree(notes: [makeNote('a', body: '# Apples\n\nRed ones.'), makeNote('b', body: '# Bread')], peek: peek));
      expect(asked.toSet(), {'# Apples\n\nRed ones.', '# Bread'});
      expect(find.byKey(const ValueKey('drawn')), findsOneWidget);
      final t = tester.element(find.byType(NoteTree)).tokens;
      final title = tester.getRect(find.byType(CssLines).first);
      // `gap: 0.15em` in the row's grid, then `.rowPeek { margin-block-start: var(--glacier-space-1) }`.
      expect(tester.getRect(find.byKey(const ValueKey('drawn'))).top, closeTo(title.bottom + 0.15 * 16 + t.space(1), 0.01));
      await away(tester);
    });

    testWidgets('by default draws the note small under its name, in the editor’s own lines; a canvas and a bare title, nothing', (tester) async {
      expect(peekWords('# Packing\n\n- [ ] Passport\n- [x] Charger\n\n## Later\n\n```js\nlet x\n```\n1. Tent ^t1'), 'Passport Charger Later let x Tent');
      expect(peekWords('# Only a title'), '');
      await show(tester, tree(notes: [makeNote('p', body: '# Packing\n\n- [ ] Passport'), makeNote('t', body: '# Only a title'), makeNote('c', body: '---\ntitle: "Map"\n---\n{"nodes":[],"edges":[]}')]));
      expect(find.byType(NotePeek), findsOneWidget);
      // The to-do as the note draws it: its dash, its box and its word.
      final line = editorLine(tester, 'Passport');
      final t = tester.element(find.byType(NoteTree)).tokens;
      expect(line.spec.projection.display, '- [ ] Passport');
      // `.peek`: the note's own face, at 0.62 of the body's size on this text scale, in the third ink (a list's
      // words are in the first, `.list`).
      final own = line.spec.look.base.style;
      expect(own.fontSize, closeTo(t.fontSize('lg') * 0.62 * t.number('app-text-scale'), 1e-9));
      expect([own.fontFamily, own.color], ['Maple Mono', t.color('app-ink-3')]);
      await away(tester);
    });

    testWidgets('tells a mouse’s right-click on a row which note and where, and a finger’s press nothing', (tester) async {
      final asked = <(String, Offset)>[];
      await show(tester, tree(notes: [makeNote('a', body: '# Apples')], onNoteMenu: (id, at) => asked.add((id, at))));
      final at = tester.getCenter(find.text('Apples'));
      final mouse = await tester.startGesture(at, kind: PointerDeviceKind.mouse, buttons: kSecondaryMouseButton);
      await mouse.up();
      expect(asked, [('a', at)]);
      final finger = await tester.startGesture(at);
      await finger.up();
      final primary = await tester.startGesture(at, kind: PointerDeviceKind.mouse);
      await primary.up();
      await mouse.removePointer();
      await primary.removePointer();
      expect(asked, hasLength(1));
      await away(tester);
    });

    testWidgets('hides a folder’s More until its row is pointed at on a desktop, and never on a phone, with a mouse or without', (tester) async {
      // `@media (hover: hover)`, which is about the screen's own pointer: a phone's page answers by its touch
      // screen with a mouse joined to it too (shell/wide_screen.dart `mousePointer`).
      spaces.addWorkspace('Kitchen');
      await show(tester, tree(notes: [makeNote('a')]));
      double shown() => tester.widget<Opacity>(find.ancestor(of: byLucide(Lucide.ellipsis), matching: find.byType(Opacity)).first).opacity;
      // A finger has no hover: always there.
      expect(shown(), 1);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(380, 800));
      await tester.pump();
      await mouse.moveTo(tester.getCenter(find.text('a')));
      await tester.pump();
      expect(shown(), 1, reason: 'a mouse on a phone: the page’s question is still the touch screen’s');
      // A desktop: there once its row is pointed at.
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await show(tester, tree(notes: [makeNote('a'), makeNote('b')]));
      await mouse.moveTo(tester.getCenter(find.text('a')));
      await tester.pump();
      expect(shown(), 0);
      await mouse.moveTo(tester.getCenter(find.text('Kitchen')));
      await tester.pump();
      expect(shown(), 1);
      await mouse.removePointer();
      debugDefaultTargetPlatformOverride = null;
      await away(tester);
    });
  });

  group('what the tree builds, and when', () {
    testWidgets('its list once for the same notes, whoever builds it again, and again for a note that changed', (tester) async {
      final notes = ValueNotifier<List<Note>>([for (var i = 0; i < 12; i += 1) makeNote('n$i', body: '# Note $i\n\nWords under it.', updatedAt: 100 - i)]);
      final opened = <String>[];
      await pumpPage(
        tester,
        BackScope(
          child: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 320,
              // New callbacks at every build, as whoever holds the sidebar hands them.
              child: ValueListenableBuilder<List<Note>>(valueListenable: notes, builder: (context, notes, _) => tree(notes: notes, activeId: 'n1', onOpen: (id) => opened.add(id))),
            ),
          ),
        ),
        size: const Size(390, 844),
      );
      Widget row(String id) => tester.widget(find.byKey(ValueKey('note-row-$id')));
      final first = row('n0');
      // The same notes, in a new list: the rows are the ones it made.
      notes.value = [...notes.value];
      await tester.pump();
      expect(identical(row('n0'), first), isTrue);
      // Read again from the library: new notes that say what the old said.
      notes.value = [for (final note in notes.value) note.copyWith()];
      await tester.pump();
      expect(identical(row('n0'), first), isTrue);
      // A row still opens its note through whoever holds the tree now.
      await tester.tap(find.text('Note 2'));
      expect(opened, ['n2']);
      // A note renamed: the list is made again, and says so.
      notes.value = [for (final note in notes.value) note.id == 'n0' ? note.copyWith(body: '# Renamed') : note];
      await tester.pump();
      expect(identical(row('n0'), first), isFalse);
      expect(find.text('Renamed'), findsOneWidget);
      // And for names only, which is the tree's own to change.
      final before = row('n3');
      await tester.tap(button('Show names only'));
      await tester.pump();
      expect(identical(row('n3'), before), isFalse);
      await away(tester);
    });
  });
}