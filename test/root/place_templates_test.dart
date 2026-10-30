import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/core/library.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/editor/tickets/tickets.dart' show TicketPanel;
import 'package:ghost_md/notes/folder_drag.dart';
import 'package:ghost_md/notes/icon_browser.dart' show browseViewsKey;
import 'package:ghost_md/notes/own_templates.dart';
import 'package:ghost_md/notes/template_choice.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../commands/support.dart' show type;
import '../library/support.dart' show FakeCore, libraryOver;
import '../support/render.dart';

/// A folder's and a notebook's own template in the app put together (lib/root/root_templates.dart; Matt, 2026-10-30,
/// of a list of plain-Markdown features: "add all 12"): New note in a folder with a template starts from it, its
/// placeholders filled; the + and the command search's New from template… make a note from the one chosen; a
/// notebook's new page starts from its page-template; and a folder's Set template… writes the page's folders:.
void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });
  tearDown(() => debugChooseTemplate = null);

  const bugPage = '---\ntitle: "Bug report"\ntemplates: page\nfolders: [Home]\n---\n# {{title}}\n\nOn {{date:YYYY-MM-DD}} at {{time}}, by {{author}}\n\n## Steps\n\n1. {{cursor}}\n';
  const meetingPage = '---\ntitle: "Standup"\ntemplates: page\n---\n# Standup {{date:YYYY-MM-DD}}\n\n## Done\n\n- \n';
  const kiln = '---\ntitle: "Kiln"\nbook: true\nkey: KLN\npage-template: "[[Bug report]]"\n---\n# Kiln\n\n- [[Seeds]]\n- [[Ship the beta]]\n';

  late NoteLibrary library;
  late WorkspaceStore store;

  Future<void> open(WidgetTester tester, {String? chosen}) async {
    final core = FakeCore()
      ..seed('templates', templatesNotebookBody(['Bug report', 'Standup']))
      ..seed('bug', bugPage)
      ..seed('standup', meetingPage)
      ..seed('kiln', kiln)
      ..seed('beta', '---\ntype: ticket\nid: KLN-1\nstatus: In progress\n---\n# Ship the beta\n')
      ..seed('seeds', '# Seeds\n\nTomatoes.', path: 'workspaces/Home/Seeds.md');
    final it = libraryOver(core);
    library = it.library;
    await tester.runAsync(library.load);
    store = WorkspaceStore(storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [Workspace(id: 'home', name: 'Home'), Workspace(id: 'away', name: 'Away')], notes: {'seeds': 'home'})))..chooseWorkspace(chosen);
    final kept = MemoryStored()..writeText(browseViewsKey, '{"home":"icons","away":"icons"}');
    await pumpApp(tester, size: const Size(900, 1000), prefs: const Preferences(theme: 'light'), home: GhostRoot(launch: false, library: library, workspaces: store, stored: kept));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i += 1) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> close(WidgetTester tester) async {
    folderCarrying.value = null;
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  }

  Finder key(String value) => find.byKey(ValueKey(value));

  /// The notes made since [before], by id.
  List<String> madeSince(Set<String> before) => [for (final note in library.value) if (!before.contains(note.id)) note.id];

  String bodyOf(String id) => library.noteOf(id)!.body;

  final today = DateTime.now();
  final day = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

  testWidgets('New note in a folder with a template starts from it, filled, and is filed there', (tester) async {
    await open(tester, chosen: 'home');
    final before = {for (final note in library.value) note.id};
    await tester.tap(key('tile-note-new'));
    await settle(tester);
    final made = madeSince(before).single;
    expect(store.value.of[made], 'home');
    expect(bodyOf(made), startsWith('# \n\nOn $day at '));
    expect(bodyOf(made), contains('## Steps\n\n1. '));
    expect(bodyOf(made), isNot(contains('{{')));
    expect(bodyOf(made), isNot(contains('folders:')), reason: 'the page’s own keys stay on the page');
    await close(tester);
  });

  testWidgets('a folder with none makes a blank note, as before', (tester) async {
    await open(tester, chosen: 'away');
    final before = {for (final note in library.value) note.id};
    await tester.tap(key('tile-note-new'));
    await settle(tester);
    expect(bodyOf(madeSince(before).single), '');
    await close(tester);
  });

  testWidgets('the dock’s + offers New from template…, and makes the note from the one chosen', (tester) async {
    await open(tester, chosen: 'away');
    var offered = <String>[];
    debugChooseTemplate = (title, templates) async {
      offered = [for (final template in templates) template.name];
      return (template: templates.firstWhere((each) => each.name == 'Standup'));
    };
    await tester.tap(find.bySemanticsLabel('Write a note'));
    await settle(tester);
    final before = {for (final note in library.value) note.id};
    await tester.tap(key('new-template'));
    await settle(tester);
    expect(offered, ['Bug report', 'Standup'], reason: 'your templates, in the notebook’s order');
    final made = madeSince(before).single;
    expect(bodyOf(made), '# Standup $day\n\n## Done\n\n- \n');
    expect(store.value.of[made], 'away');
    await close(tester);
  });

  testWidgets('the command search has New from template…', (tester) async {
    await open(tester);
    debugChooseTemplate = (title, templates) async => (template: templates.firstWhere((each) => each.name == 'Bug report'));
    tester.state<CommandBarState>(find.byType(CommandBar)).show();
    await settle(tester);
    await type(tester, 'from template');
    final before = {for (final note in library.value) note.id};
    await tester.tap(find.text('New from template…', findRichText: true).last);
    await settle(tester);
    expect(bodyOf(madeSince(before).single), contains('## Steps'));
    await close(tester);
  });

  testWidgets('a notebook with a page-template starts a new page from it, its title the page’s, numbered by its key', (tester) async {
    await open(tester);
    tester.state<AppShellState>(find.byType(AppShell)).openNote('kiln');
    await settle(tester);
    // Add a page, Just the title: in a notebook with a template, that template.
    await tester.tap(key('book-add-page'));
    await settle(tester);
    expect(find.text('Bug report'), findsWidgets, reason: 'the first way to start is the notebook’s template');
    await tester.enterText(find.descendant(of: key('book-page-title'), matching: find.byType(EditableText)), 'Login loop');
    await tester.pump();
    final before = {for (final note in library.value) note.id};
    await tester.tap(key('book-add-open'));
    await settle(tester);
    final made = madeSince(before).single;
    expect(bodyOf(made), startsWith('# Login loop\n\nOn $day at '));
    expect(bodyOf(made), contains('## Steps'));
    await close(tester);
  });

  testWidgets('Add sub-ticket on a ticket’s panel makes one in its notebook, numbered, its parent the ticket, its line after it', (tester) async {
    await open(tester);
    tester.state<AppShellState>(find.byType(AppShell)).openNote('beta');
    await settle(tester);
    final before = {for (final note in library.value) note.id};
    // The panel's Add sub-ticket, as its sheet's Add calls it (the sheet itself: test/editor/tickets/sub_tickets_test.dart).
    final panel = tester.widget<TicketPanel>(find.byType(TicketPanel));
    expect(panel.options!.subTickets!(), isEmpty);
    panel.options!.addSubTicket!('Fix login');
    await settle(tester);
    final made = madeSince(before).single;
    expect(bodyOf(made), contains('parent: "[[KLN-1]]"'));
    expect(bodyOf(made), contains('id: KLN-2'));
    expect(bodyOf(made), contains('# Fix login'));
    expect(bodyOf(made), contains('## Steps'), reason: 'from the notebook’s template');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await settle(tester);
    expect(bodyOf('kiln'), contains('- [[Ship the beta]]\n- [[Fix login]]'));
    await close(tester);
  });
}
