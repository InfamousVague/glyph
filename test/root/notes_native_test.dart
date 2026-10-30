// Three of the plain-Markdown features in the app put together (Matt, 2026-10-30, "add all 12"): "Linked from" at
// the foot of a note's words, a team note among them with its organization's name, a press opening the note that
// links; none for a note nobody links to, nor a notebook's index; a section embed drawn again as its source changes;
// and a heading folded from the gutter, kept on this device for the note when it is opened again. A phone and a Mac.
import 'package:flutter/foundation.dart' show debugDefaultTargetPlatformOverride;
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/media/note_embeds.dart' show DrawnNoteEmbed;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/editor/view/section_folds.dart';
import 'package:ghost_md/links/backlinks_foot.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/screen.dart';

import '../support/editor_text.dart';
import '../support/render.dart';

const String packing = '# Packing\n\nWhat goes in the bag for Portugal.\n\n## Clothes\n\n- [ ] Shoes for the hills\n- [ ] A coat\n\n## Papers\n\nPassports and the ferry tickets.\n';
const String ferry = '# The ferry\n\nNine from Cais do Sodré. See [[Packing#Papers]] for the tickets.\n\n![[Packing#Clothes]]\n';
const String offsite = '# Team offsite\n\nEveryone brings what [[Packing|the list]] says.\n';

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

  setUp(() => useStored(MemoryStored()));

  Future<SampleLibrary> open(WidgetTester tester, {Size size = const Size(430, 932), MemoryStored? keep}) async {
    final library = SampleLibrary.seeded();
    final seeded = seedWorkspaces();
    // An organization's workspace, and the offsite filed in it: a team note.
    final sheet = WorkspaceSheet(list: [...seeded.list, Workspace(id: orgWorkspaceId('acme'), name: 'Acme')], notes: {...seeded.notes, 'offsite': orgWorkspaceId('acme')});
    await pumpApp(
      tester,
      size: size,
      ratio: 3,
      prefs: Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, stored: keep ?? MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(sheet)), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    library.value = [
      for (final note in library.value)
        if (note.id == 'packing') note.copyWith(body: packing) else note,
    ];
    await library.createNote(ferry, id: 'ferry');
    await library.createNote(offsite, id: 'offsite');
    await library.createNote('# Diary\n\nNobody links to this.\n', id: 'diary');
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

  /// The note's page scrolled to its foot.
  Future<void> toFoot(WidgetTester tester) async {
    final page = tester.state<ScrollableState>(find.descendant(of: find.byType(NoteScreen), matching: find.byType(Scrollable)).first).position;
    page.jumpTo(page.maxScrollExtent);
    await settle(tester, 3);
  }

  for (final (where, size) in const [('phone', Size(430, 932)), ('mac', Size(1280, 800))]) {
    testWidgets('"Linked from" under a note\'s words, a team note among them, a press opening the note that links, on a $where', (tester) async {
      if (where == 'mac') debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      await open(tester, size: size);
      final shell = tester.state<AppShellState>(find.byType(AppShell));
      shell.openNote('packing');
      await settle(tester);
      await toFoot(tester);
      expect(find.byType(BacklinksFoot), findsOneWidget);
      // Portugal's index, The ferry (by a heading and by an embed) and the team's offsite.
      expect(find.text('LINKED FROM 3 NOTES'), findsOneWidget);
      final foot = find.byType(BacklinksFoot);
      for (final title in ['Portugal', 'The ferry', 'Team offsite']) {
        expect(find.descendant(of: foot, matching: find.text(title)), findsOneWidget, reason: title);
      }
      expect(find.descendant(of: foot, matching: find.text('Acme')), findsOneWidget, reason: 'the team note says whose it is');
      expect(find.descendant(of: foot, matching: find.text('  +1')), findsOneWidget, reason: 'the ferry links twice');
      await tester.tap(find.descendant(of: foot, matching: find.text('Team offsite')));
      await settle(tester);
      expect((shell.screen as ScreenNote).note.id, 'offsite');
      await close(tester);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('no foot for a note nobody links to, nor for a notebook\'s index', (tester) async {
    await open(tester);
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.openNote('diary');
    await settle(tester);
    await toFoot(tester);
    expect(find.textContaining('LINKED FROM'), findsNothing);
    shell.openNote('portugal');
    await settle(tester);
    expect(find.byType(BacklinksFoot), findsNothing, reason: 'a notebook\'s index is no note of words');
    await close(tester);
  });

  testWidgets('a section embed is drawn again when its source changes', (tester) async {
    final library = await open(tester);
    tester.state<AppShellState>(find.byType(AppShell)).openNote('ferry');
    await settle(tester);
    expect(find.byType(DrawnNoteEmbed), findsOneWidget);
    expect(editorText('Shoes for the hills'), findsOneWidget);
    expect(find.text('Edit in source'), findsOneWidget);
    await library.save('packing', packing.replaceFirst('Shoes for the hills', 'Boots for the hills'));
    await settle(tester);
    expect(editorText('Boots for the hills'), findsOneWidget);
    expect(editorText('Shoes for the hills'), findsNothing);
    // Edit in source opens Packing.
    await tester.tap(find.text('Edit in source'));
    await settle(tester);
    expect((tester.state<AppShellState>(find.byType(AppShell)).screen as ScreenNote).note.id, 'packing');
    await close(tester);
  });

  testWidgets('a heading folded from its triangle stays folded on this device when the note is opened again', (tester) async {
    await open(tester);
    final shell = tester.state<AppShellState>(find.byType(AppShell));
    shell.openNote('packing');
    await settle(tester);
    var view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    final clothes = view.state.doc.toString().split('\n').indexOf('## Clothes') + 1;
    // Under a finger the triangle is there to tap.
    final triangle = find.byKey(ValueKey<String>('fold-gutter-$clothes'));
    expect(triangle, findsOneWidget);
    await tester.tapAt(tester.getCenter(triangle));
    await settle(tester);
    expect(editorText('Shoes for the hills'), findsNothing);
    expect(view.state.doc.toString(), packing, reason: 'nothing written');
    shell.openNote('diary');
    await settle(tester);
    shell.openNote('packing');
    await settle(tester);
    view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    expect(foldedOf(view.state), {view.state.doc.line(clothes).from});
    expect(editorText('Shoes for the hills'), findsNothing);
    expect(keptFolds('packing'), {'h2|Clothes|0': true}, reason: 'kept in the device\'s own storage, the app\'s memory');
    await close(tester);
  });
}
