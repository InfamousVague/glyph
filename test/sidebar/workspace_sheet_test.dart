import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/workspaces.dart' hide WorkspaceSheet;
import 'package:ghost_md/notes/org_mark.dart';
import 'package:ghost_md/notes/workspace_sheet.dart';
import 'package:ghost_md/notes/workspace_swatch.dart';
import 'package:ghost_md/sheet/kit.dart';
import 'package:ghost_md/sheet/sheet.dart';

import '../support/render.dart';
import 'support.dart';

/// A workspace's sheet (notes/workspace_sheet.dart): the sheet's cases of `notes/WorkspaceSheet.test.tsx`, what it
/// asks of its caller where the web asked the trash, its three states where the web page has them, and the pictures.
void main() {
  setUpAll(loadAppFonts);
  final library = SidebarLibrary.load();

  final panel = find.byKey(const ValueKey('sheet-panel'));
  Finder row(String label) => find.widgetWithText(SheetRow, label);
  String? dialog(WidgetTester tester) => find.byType(Sheet).evaluate().isEmpty ? null : tester.widget<Sheet>(find.byType(Sheet)).label;

  /// The sheet as a screen holds it: up for a new workspace or for one that exists, and gone when it closes.
  Future<void> show(
    WidgetTester tester,
    WorkspaceStore store, {
    Workspace? editing,
    void Function(String orgId)? onOrganization,
    List<String> Function(String id)? notesIn,
    void Function(List<String> ids)? onTrashNotes,
    VoidCallback? onClose,
    Size size = const Size(390, 844),
    String theme = 'light',
    bool bare = true,
  }) async {
    var open = true;
    await pumpPage(
      tester,
      StatefulBuilder(
        builder: (context, setState) => PageUnder(
          children: [
            if (open)
              WorkspaceManageSheet(
                store: store,
                editing: editing,
                onOrganization: onOrganization,
                notesIn: notesIn,
                onTrashNotes: onTrashNotes,
                onClose: () {
                  onClose?.call();
                  setState(() => open = false);
                },
              ),
          ],
        ),
      ),
      size: size,
      theme: theme,
      bare: bare,
    );
    await settle(tester);
  }

  group('the workspace sheet', () {
    testWidgets('makes a workspace in the colour chosen for it, and chooses it', (tester) async {
      final store = WorkspaceStore()..addWorkspace('Kitchen');
      await show(tester, store);
      expect(dialog(tester), 'New workspace');
      expect(find.text('Notes filed in a workspace show together. A note made while one is chosen goes there.'), findsOneWidget);
      // No name, nothing to add.
      expect(tester.widget<SheetRow>(row('Add')).disabled, isTrue);
      await tester.tap(find.text('Add'));
      expect(store.value.list, hasLength(1));
      await tester.enterText(find.byType(EditableText), 'Garden');
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Moss'));
      await tester.pump();
      // A new one wears its colour when it is made, not before.
      expect(store.value.list, hasLength(1));
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(dialog(tester), isNull);
      expect([store.value.current?.name, store.value.current?.hue], ['Garden', 'moss']);
      await away(tester);
    });

    testWidgets('opens on its name, with the words capitalised as they are typed and Enter for Add', (tester) async {
      final store = WorkspaceStore();
      await show(tester, store);
      final field = tester.widget<EditableText>(find.byType(EditableText));
      expect(field.focusNode.hasFocus, isTrue);
      expect([field.textCapitalization, field.textInputAction], [TextCapitalization.words, TextInputAction.done]);
      await tester.enterText(find.byType(EditableText), '  Pantry ');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(dialog(tester), isNull);
      expect(store.value.current?.name, 'Pantry');
      await away(tester);
    });

    testWidgets('renames one, recolours it as the colour is tapped, and deletes it', (tester) async {
      final store = WorkspaceStore();
      final kitchen = store.addWorkspace('Kitchen')!;
      store.chooseWorkspace(kitchen.id);
      await show(tester, store, editing: kitchen);
      expect(dialog(tester), 'Kitchen');
      expect(find.textContaining('Notes filed in a workspace'), findsNothing);
      // The same name is not a rename.
      expect(tester.widget<SheetRow>(row('Rename')).disabled, isTrue);
      await tester.tap(find.bySemanticsLabel('Sea'));
      await tester.pump();
      expect(store.value.list[0].hue, 'sea');
      expect(dialog(tester), 'Kitchen');
      await tester.enterText(find.byType(EditableText), 'Pantry');
      await tester.pump();
      expect(tester.widget<SheetRow>(row('Rename')).disabled, isFalse);
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(store.value.list[0].name, 'Pantry');
      expect(dialog(tester), isNull);

      await show(tester, store, editing: store.value.list[0]);
      await tester.tap(find.text('Delete workspace'));
      await tester.pump();
      // Asked first: with no notes in it, only whether to delete it.
      expect(store.value.list, hasLength(1));
      expect(dialog(tester), 'Delete Pantry');
      expect(find.text('Delete Pantry?'), findsOneWidget);
      expect(find.text('There are no notes in it.'), findsOneWidget);
      expect(row('Delete, keep the notes'), findsNothing);
      await tester.tap(find.text('Delete workspace'));
      await tester.pump();
      expect(store.value.list, isEmpty);
      expect(dialog(tester), isNull);
      await away(tester);
    });

    testWidgets('asks what becomes of the notes: kept and unfiled, or moved to the Trash with it', (tester) async {
      final store = WorkspaceStore();
      final kitchen = store.addWorkspace('Kitchen')!;
      store
        ..fileNote('n1', kitchen.id)
        ..fileNote('n2', kitchen.id);
      final trashed = <String>[];
      var closed = 0;
      await show(tester, store, editing: kitchen, onTrashNotes: trashed.addAll, onClose: () => closed += 1);
      await tester.tap(find.text('Delete workspace'));
      await tester.pump();
      expect(find.text('What happens to its 2 notes?'), findsOneWidget);
      // Cancel goes back, and nothing is gone.
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      expect(store.value.list, hasLength(1));
      expect([dialog(tester), closed], ['Kitchen', 0]);
      await tester.tap(find.text('Delete workspace'));
      await tester.pump();
      await tester.tap(find.text('Delete, and move the notes to Trash'));
      await tester.pump();
      expect(store.value.list, isEmpty);
      expect(trashed..sort(), ['n1', 'n2']);
      expect(closed, 1);
      await away(tester);
    });

    testWidgets('keeps the notes, unfiled, when asked to', (tester) async {
      final store = WorkspaceStore();
      final kitchen = store.addWorkspace('Kitchen')!;
      store.fileNote('n1', kitchen.id);
      final trashed = <String>[];
      await show(tester, store, editing: kitchen, onTrashNotes: trashed.addAll);
      await tester.tap(find.text('Delete workspace'));
      await tester.pump();
      expect(find.text('What happens to its 1 note?'), findsOneWidget);
      await tester.tap(find.text('Delete, keep the notes'));
      await tester.pump();
      expect(store.value.list, isEmpty);
      expect(store.workspaceOf('n1'), isNull);
      expect(trashed, isEmpty);
      await away(tester);
    });

    testWidgets('asks its caller which notes a delete is about, and cannot move them where there is no trash to move them to', (tester) async {
      final store = WorkspaceStore();
      final kitchen = store.addWorkspace('Kitchen')!;
      store
        ..fileNote('n1', kitchen.id)
        ..fileNote('n2', kitchen.id);
      // One of the two is in the trash already, which only the caller knows.
      await show(tester, store, editing: kitchen, notesIn: (id) => id == kitchen.id ? ['n2'] : []);
      await tester.tap(find.text('Delete workspace'));
      await tester.pump();
      expect(find.text('What happens to its 1 note?'), findsOneWidget);
      expect(tester.widget<SheetRow>(row('Delete, and move the notes to Trash')).disabled, isTrue);
      await tester.tap(find.text('Delete, and move the notes to Trash'));
      await tester.pump();
      expect(store.value.list, hasLength(1));
      await away(tester);
    });
  });

  /// An organization's workspace (docs/TEAMS.md, D5): managed on the organization's own screen.
  group('an organization’s workspace', () {
    testWidgets('has no name, swatch or Remove in its sheet, only the way to the organization’s settings', (tester) async {
      final store = WorkspaceStore();
      final ghost = store.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Ghost', hue: 'sea'));
      final opened = <String>[];
      var closed = 0;
      final handle = tester.ensureSemantics();
      await show(tester, store, editing: ghost, onOrganization: opened.add, onClose: () => closed += 1);
      expect(dialog(tester), 'Ghost');
      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(WorkspaceSwatch), findsNothing);
      expect(row('Delete workspace'), findsNothing);
      expect(row('Rename'), findsNothing);
      expect(find.textContaining('Notes filed here are the team’s'), findsOneWidget);
      // The mark stands before the name, in the title's own line.
      expect(tester.getSemantics(find.byType(OrgMark)).label, contains('Organization'));
      final mark = tester.getRect(find.byType(OrgMark));
      expect(mark.left, closeTo(tester.getRect(find.byType(SheetTitle)).left, 0.01));
      // `inline-size: 0.9em` of the title's 19.39px, then `margin-inline-end: 0.35em`.
      expect(mark.width, closeTo(19.3897 * (0.9 + 0.35), 0.01));
      await tester.tap(find.text('Organization settings'));
      await tester.pump();
      expect([opened, closed], [['o1'], 1]);
      handle.dispose();
      await away(tester);
    });

    testWidgets('with no organization screen to go to, cannot be pressed', (tester) async {
      final store = WorkspaceStore();
      final ghost = store.ensureOrgWorkspace(const OrgLike(id: 'o1', name: 'Ghost'));
      await show(tester, store, editing: ghost);
      expect(tester.widget<SheetRow>(row('Organization settings')).disabled, isTrue);
      await away(tester);
    });
  });

  // What the web page measured at 390 x 844 (Chromium, getBoundingClientRect, 2026-10-07) with the sheet opened from
  // the home page's filters over the same workspaces. One number differs by design: the field's underline is
  // `--app-line`, 1.5px, which that browser drew at 1px while emulating a phone's screen, so everything over the
  // field sits 0.5px higher here than there. (Opened from the pop-up sidebar, the page's sheet is trapped inside the
  // card, 318px wide: see sheet/sheet.dart.)
  group('where it sits', () {
    const line = 0.5;

    testWidgets('a new workspace: the web page’s, to the half pixel', (tester) async {
      await show(tester, library.store());
      near(tester.getRect(panel), [0, 438.73 - line, 390, 405.27 + line], what: 'the sheet');
      near(tester.getRect(find.byKey(const ValueKey('sheet-grip'))), [22.31, 448.66 - line, 345.38, 30.78], what: 'the grip');
      near(tester.getRect(find.byType(SheetTitle)), [22.31, 483.89 - line, 345.38, 24], what: 'the title');
      near(tester.getRect(find.textContaining('Notes filed in a workspace')), [22.31, 525.73 - line, 345.38, 32], what: 'the note');
      near(tester.getRect(find.byType(SheetGroup).at(0)), [22.31, 571.13 - line, 345.38, 137.63 + line], what: 'the name’s group');
      near(tester.getRect(find.text('NAME')), [40.16, 584.52 - line, 309.69, 14], what: 'the label');
      near(tester.getRect(find.byType(EditableText)), [40.16, 602.97 + 8.93 - line, 309.69, 20], what: 'the input’s line');
      near(tester.getRect(row('Add')), [22.31, 655.2, 345.38, 53.55], by: 0.1, what: 'Add');
      near(tester.getRect(find.text('Add')), [40.16, 672.47, 30.97, 20], by: 0.1, what: 'Add’s word');
      near(tester.getRect(find.text('COLOUR')), [22.31, 722.14, 345.38, 14], by: 0.1, what: 'the heading');
      near(tester.getRect(find.byType(SheetGroup).at(1)), [22.31, 745.06, 345.38, 63.23], by: 0.1, what: 'the swatch’s group');
      for (final (name, left) in [('Ink', 40.16), ('Ember', 86.44), ('Amber', 132.72), ('Moss', 179.0), ('Sea', 225.28), ('Violet', 271.56), ('Rose', 317.84)]) {
        near(tester.getRect(find.bySemanticsLabel(name)), [left, 758.45, 32, 32], by: 0.1, what: name);
      }
      await away(tester);
    });

    testWidgets('one that exists, and the question about its notes: the web page’s', (tester) async {
      final store = library.store();
      await show(tester, store, editing: store.value.list[0], onTrashNotes: (_) {});
      near(tester.getRect(panel), [0, 405.95 - line, 390, 438.05 + line], what: 'the sheet');
      near(tester.getRect(find.byType(SheetTitle)), [22.31, 451.11 - line, 345.38, 24], what: 'the title');
      near(tester.getRect(row('Rename')), [22.31, 577.03, 345.38, 53.55], by: 0.1, what: 'Rename');
      near(tester.getRect(find.byType(SheetGroup).at(2)), [22.31, 743.52, 345.38, 64.78], by: 0.1, what: 'Delete’s group');
      expect(tester.getRect(find.text('Delete workspace')).topLeft, within(distance: 0.1, from: const Offset(40.16, 756.91)));
      near(tester.getRect(find.text('Asks what happens to its notes first.')), [40.16, 778.91, 229.17, 16], by: 0.1, what: 'its hint');

      await tester.tap(find.text('Delete workspace'));
      await tester.pump();
      near(tester.getRect(panel), [0, 491.8, 390, 352.2], by: 0.1, what: 'the question');
      near(tester.getRect(find.byType(SheetTitle)), [22.31, 536.95, 345.38, 24], by: 0.1, what: 'its title');
      near(tester.getRect(find.text('What happens to its 2 notes?')), [22.31, 578.8, 345.38, 16], by: 0.1, what: 'its note');
      near(tester.getRect(find.byType(SheetGroup)), [22.31, 608.19, 345.38, 200.11], by: 0.1, what: 'its group');
      near(tester.getRect(row('Delete, keep the notes')), [22.31, 608.19, 345.38, 64.78], by: 0.1, what: 'keep');
      // Two lines of hint: 1 + 13.39 + 20 + 2 + 32 + 13.39.
      near(tester.getRect(row('Delete, and move the notes to Trash')), [22.31, 672.97, 345.38, 81.78], by: 0.1, what: 'trash');
      near(tester.getRect(find.textContaining('They can be restored')), [40.16, 709.36, 309.69, 32], by: 0.1, what: 'its hint');
      near(tester.getRect(row('Cancel')), [22.31, 754.75, 345.38, 53.55], by: 0.1, what: 'Cancel');
      await away(tester);
    });

    // At 1280 x 800 on a desktop the page's sheet is a window: 544 wide from x 368, centred, its title 27.33 in.
    testWidgets('on a desktop, a window in the middle: the web page’s', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      final store = library.store();
      await show(tester, store, size: const Size(1280, 800));
      near(tester.getRect(panel), [368, 183.17 - 0.25, 544, 433.64 + line], what: 'the window');
      near(tester.getRect(find.byType(SheetTitle)), [395.33, 210.5 - 0.25, 489.34, 26], what: 'the title');
      near(tester.getRect(find.textContaining('Notes filed in a workspace')), [395.33, 257.56 - 0.25, 489.34, 34], what: 'the note');
      near(tester.getRect(row('Add')), [395.33, 401.28 + 0.25, 489.34, 63.22], what: 'Add');
      near(tester.getRect(find.bySemanticsLabel('Rose')), [831.61, 520.63 + 0.25, 32, 32], what: 'Rose');
      await away(tester);

      await show(tester, store, editing: store.value.list[0], onTrashNotes: (_) {}, size: const Size(1280, 800));
      await tester.tap(find.text('Delete workspace'));
      await tester.pump();
      near(tester.getRect(panel), [368, 221.14, 544, 357.72], by: 0.1, what: 'the question');
      near(tester.getRect(row('Delete, keep the notes')), [395.33, 328.33, 489.34, 71.59], by: 0.1, what: 'keep');
      near(tester.getRect(row('Cancel')), [395.33, 472.52, 489.34, 63.22], by: 0.1, what: 'Cancel');
      await away(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('the pictures', () {
    for (final theme in ['light', 'dark']) {
      for (final (name, size, desktop) in [('phone', const Size(390, 844), false), ('wide', const Size(1280, 800), true)]) {
        testWidgets('a new workspace, $name, $theme', (tester) async {
          if (desktop) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          await show(tester, library.store(), size: size, theme: theme, bare: desktop);
          // As the web's picture was taken: nothing being typed.
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await shot(tester, 'workspace-new-$name-$theme');
          debugDefaultTargetPlatformOverride = null;
        });

        testWidgets('one that exists, $name, $theme', (tester) async {
          if (desktop) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final store = library.store();
          await show(tester, store, editing: store.value.list[0], size: size, theme: theme, bare: desktop);
          FocusManager.instance.primaryFocus?.unfocus();
          await tester.pump();
          await shot(tester, 'workspace-edit-$name-$theme');
          debugDefaultTargetPlatformOverride = null;
        });

        testWidgets('the question about its notes, $name, $theme', (tester) async {
          if (desktop) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final store = library.store();
          await show(tester, store, editing: store.value.list[0], onTrashNotes: (_) {}, size: size, theme: theme, bare: desktop);
          await tester.tap(find.text('Delete workspace'));
          await tester.pump();
          await shot(tester, 'workspace-delete-$name-$theme');
          debugDefaultTargetPlatformOverride = null;
        });
      }
    }

    testWidgets('an organization’s, phone, light', (tester) async {
      final store = library.store();
      await show(tester, store, editing: store.value.list[3], onOrganization: (_) {}, bare: false);
      await shot(tester, 'workspace-org-phone-light');
    });
  });
}
