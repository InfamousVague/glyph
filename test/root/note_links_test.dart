// The links between notes in the app put together (lib/root/ghost_root.dart over lib/links): the Links tool and its
// count, the More sheet's Links page with "Linked from" and "Mentioned in" and a mention linked and taken back, the
// Outline page with the note's length, Copy link to this line, the side panel's tabs on an opened Fold, an embed in
// the real editor, and the graph from the palette. Pictures go to build/feature-shots/links/ with --update-goldens.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart';
import 'package:ghost_md/aside/aside.dart';
import 'package:ghost_md/commands/command_bar.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/media/note_embeds.dart' show DrawnNoteEmbed;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/links/graph_view.dart';
import 'package:ghost_md/links/links_panel.dart';
import 'package:ghost_md/links/outline.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../support/render.dart';

/// Notes over the seeded library that link to Packing, name it without a link, and give it an outline.
const String _packing = '# Packing\n\nWhat goes in the bag for Portugal.\n\n## Clothes\n\n- [ ] Shoes for the hills ^shoes\n- [ ] A coat\n- [ ] Two shirts\n- [ ] A hat for the sun\n- [ ] Socks\n\n## Papers\n\nPassports and the ferry tickets.\n\nThe booking for the flat, printed, and the car hire on the phone.\n\n### Copies\n\nOne set on paper, one in the cloud.\n\n## For the coast\n\nSun cream.\n\nA towel each, and the book Ana lent.\n\nThe small bag for the beach.';
const String _diary = '# Diary\n\nPacking took all evening. The packing list is long.\n';
const String _ferry = '# The ferry\n\nNine from Cais do Sodré. See [[Packing#Papers]] for the tickets.\n\n![[Packing#Clothes]]\n';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  late MemoryStored device;

  Future<SampleLibrary> open(WidgetTester tester, {Size size = const Size(430, 932), String theme = 'dark'}) async {
    final library = SampleLibrary.seeded();
    await pumpApp(
      tester,
      size: size,
      ratio: 3,
      prefs: Preferences(theme: theme),
      home: GhostRoot(launch: false, library: library, stored: device = MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    library.value = [
      for (final note in library.value)
        if (note.id == 'packing') note.copyWith(body: _packing) else note,
    ];
    await library.createNote(_diary, id: 'diary');
    await library.createNote(_ferry, id: 'ferry');
    await tester.pump();
    return library;
  }

  Future<void> close(WidgetTester tester) async {
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
  }

  Future<void> picture(WidgetTester tester, String name) async {
    if (!autoUpdateGoldenFiles) return;
    Directory('build/feature-shots/links').createSync(recursive: true);
    await expectLater(find.byType(GhostApp), matchesGoldenFile('../../build/feature-shots/links/$name.png'));
  }

  testWidgets('a note wears how many notes link to it, and its Links page has them, and the notes that only name it', (tester) async {
    final library = await open(tester);
    tester.state<AppShellState>(find.byType(AppShell)).openNote('packing');
    await settle(tester);
    // Portugal's index and The ferry link here.
    expect(find.bySemanticsLabel('Linked from 2 notes'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Linked from 2 notes'));
    await settle(tester);
    expect(find.byType(LinksPanel), findsOneWidget);
    expect(find.text('LINKED FROM 2 NOTES'), findsOneWidget);
    expect(find.text('Nine from Cais do Sodré. See [[Packing#Papers]] for the tickets.'), findsOneWidget);
    expect(find.text('Portugal'), findsWidgets);
    // Diary says "Packing" twice and links it nowhere.
    expect(find.text('Diary'), findsOneWidget);
    expect(find.text('Packing took all evening. The packing list is long.'), findsNWidgets(2));
    await picture(tester, 'links-panel-phone');

    await tester.tap(find.bySemanticsLabel('Link this mention in Diary').first);
    await settle(tester);
    expect(library.noteOf('diary')!.body, '# Diary\n\n[[Packing]] took all evening. The packing list is long.\n');
    expect(find.text('Linked in Diary.'), findsOneWidget);
    // Now Diary links here: it moved up, and the one mention left is its other.
    expect(find.text('LINKED FROM 3 NOTES'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await settle(tester);
    expect(library.noteOf('diary')!.body, _diary);
    await close(tester);
  });

  testWidgets('the Outline page: the headings by level, the note\'s length, and a heading gone to', (tester) async {
    await open(tester);
    tester.state<AppShellState>(find.byType(AppShell)).openNote('packing');
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await settle(tester);
    expect(find.text('Links'), findsOneWidget);
    expect(find.text('Copy link to this line'), findsOneWidget);
    expect(find.text('Local graph'), findsOneWidget);
    expect(find.textContaining(RegExp(r'^\d+ words, \d+ characters, a minute to read$')), findsOneWidget);
    await tester.tap(find.text('Outline'));
    await settle(tester);
    expect(find.byType(OutlineList), findsOneWidget);
    for (final heading in ['Packing', 'Clothes', 'Papers', 'Copies', 'For the coast']) {
      expect(find.bySemanticsLabel(heading), findsWidgets);
    }
    await picture(tester, 'outline-phone');
    await tester.tap(find.bySemanticsLabel('For the coast'));
    await settle(tester);
    expect(find.byType(OutlineList), findsNothing, reason: 'the sheet closes and the page goes to the heading');
    await close(tester);
  });

  testWidgets('Copy link to this line names a line that has no name, and copies the link to it', (tester) async {
    final library = await open(tester);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.state<AppShellState>(find.byType(AppShell)).openNote('packing');
    await settle(tester);
    final screen = tester.state<NoteScreenState>(find.byType(NoteScreen));
    final view = screen.view!;
    final line = view.state.doc.line(view.state.doc.toString().split('\n').indexOf('Passports and the ferry tickets.') + 1);
    view.dispatch(TransactionSpec(selection: EditorSelection.single(line.from + 3)));
    await tester.pump();
    await tester.tap(find.bySemanticsLabel('More for this note'));
    await settle(tester);
    await tester.tap(find.text('Copy link to this line'));
    await settle(tester, 12);
    expect(copied, '[[Packing#^passports-ferry-tickets]]');
    expect(view.state.doc.toString(), contains('Passports and the ferry tickets. ^passports-ferry-tickets'));
    await close(tester);
    expect(library.noteOf('packing')!.body, contains('^passports-ferry-tickets'));
  });

  testWidgets('an embed in a note is drawn in the editor the app puts together', (tester) async {
    await open(tester);
    tester.state<AppShellState>(find.byType(AppShell)).openNote('ferry');
    await settle(tester);
    expect(find.byType(DrawnNoteEmbed), findsOneWidget);
    await picture(tester, 'embed-in-app-phone');
    await close(tester);
  });

  testWidgets('on an opened Fold the side panel has the note\'s Links and its Outline', (tester) async {
    await open(tester, size: const Size(900, 1000));
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.openNote('packing');
    await settle(tester);
    showAsideTab(AsideTab.links, device);
    shell.showAside();
    await settle(tester);
    expect(find.byType(LinksPanel), findsOneWidget);
    expect(find.bySemanticsLabel('Outline'), findsWidgets);
    await picture(tester, 'links-aside-fold');
    await tester.tap(find.bySemanticsLabel('Outline').first);
    await settle(tester);
    expect(find.byType(LiveOutline), findsOneWidget);
    expect(tester.widget<OutlineList>(find.byType(OutlineList)).current, 0);
    // The page scrolled to Papers: the outline marks it.
    final live = tester.widget<LiveOutline>(find.byType(LiveOutline));
    final papers = outlineOf(live.view.state.doc).indexWhere((heading) => heading.text == 'Papers');
    scrollToHeading(live.view, live.page, outlineOf(live.view.state.doc)[papers].from, animate: false);
    await settle(tester, 3);
    expect(tester.widget<OutlineList>(find.byType(OutlineList)).current, papers);
    await picture(tester, 'outline-aside-fold');
    await close(tester);
  });

  for (final (name, size) in const [('phone', Size(430, 932)), ('fold', Size(900, 1000))]) {
    testWidgets('the graph of the notes from the palette, and a note\'s local graph, $name', (tester) async {
      await open(tester, size: size);
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      tester.state<CommandBarState>(find.byType(CommandBar)).show();
      await settle(tester, 4);
      await tester.enterText(find.descendant(of: find.byType(CommandBar), matching: find.byType(EditableText)), 'graph');
      await settle(tester, 6);
      await tester.tap(find.text('Graph of your notes', findRichText: true).last);
      await settle(tester, 6);
      expect(find.byType(GraphScreen), findsOneWidget);
      expect(find.textContaining(RegExp(r'^2\d notes, \d+ links$')), findsOneWidget);
      await picture(tester, 'graph-whole-$name');
      await tester.tap(find.bySemanticsLabel('Close the graph'));
      await settle(tester, 4);
      expect(find.byType(GraphScreen), findsNothing);

      shell.openNote('packing');
      await settle(tester);
      await tester.tap(find.bySemanticsLabel('More for this note'));
      await settle(tester);
      await tester.tap(find.text('Local graph'));
      await settle(tester, 6);
      expect(find.text('Around Packing'), findsOneWidget);
      expect(find.text('3 notes, 2 links'), findsOneWidget);
      // A note opened from it: the graph goes, and the note is open.
      final graph = tester.state<GraphViewState>(find.byType(GraphView));
      final at = graph.positions!;
      final ferry = tester.widget<GraphView>(find.byType(GraphView)).graph.ids.indexOf('ferry');
      final t = graph.transform;
      final where = tester.getTopLeft(find.byType(GraphView)) + Offset(at[2 * ferry] * t.scale + t.shift.dx, at[2 * ferry + 1] * t.scale + t.shift.dy);
      await picture(tester, 'graph-local-$name');
      await tester.tapAt(where);
      await settle(tester, 6);
      expect(find.byType(GraphScreen), findsNothing);
      expect(shell.shown, 'ferry');
      await close(tester);
    });
  }
}
