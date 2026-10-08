import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/main.dart';
import 'package:ghost_md/notes/all_notes_screen.dart';
import 'package:ghost_md/shell/root_stamps.dart';
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// The library the web page was measured over (the store screenshots' own, lib/core/sample_library.dart), with what
/// the All notes page has words for and that library lacks: two tapes (Monday standup, 12:34, and the call with Sam,
/// 6:12), one note in the archive (the launch post, an hour ago) and a second pinned (Groceries).
List<Note> allNotesLibrary() => [
      for (final note in seedLibrary(seedNow))
        switch (note.id) {
          'standup' => _with(note, recordingMs: 754000),
          'call-sam' => _with(note, recordingMs: 372000),
          'launch' => note.copyWith(archivedAt: () => seedNow - 3600000),
          'groceries' => note.copyWith(starred: true),
          _ => note,
        },
    ];

Note _with(Note note, {required int recordingMs}) =>
    Note(id: note.id, body: note.body, createdAt: note.createdAt, updatedAt: note.updatedAt, source: note.source, starred: note.starred, archivedAt: note.archivedAt, recordingMs: recordingMs);

/// The seeded workspaces and a third with nothing filed in it, Spare, in the app's own ink.
WorkspaceStore allNotesWorkspaces({bool any = true}) {
  final seeded = seedWorkspaces();
  return WorkspaceStore(
    storage: MemoryWorkspaceStorage(any ? WorkspaceSheet(list: [...seeded.list, const Workspace(id: 'spare', name: 'Spare', hue: 'ink')], notes: seeded.notes) : const WorkspaceSheet()),
  );
}

/// What a test's page was asked to do, in order: `open flat`, `back`, `menu flat`.
class Asked {
  final List<String> said = [];
}

/// The All notes page over [notes], alive: what leaves it is written down in [asked].
class AllNotes extends StatelessWidget {
  const AllNotes({super.key, required this.notes, required this.workspaces, required this.asked, this.tapes = false, this.stored, this.speaks = true, this.sideKey = false, this.wisp = false, this.refresh = false, this.loading = false});

  final List<Note> notes;
  final WorkspaceStore workspaces;
  final Asked asked;
  final bool tapes;
  final Stored? stored;
  final bool speaks;
  final bool sideKey;
  final bool wisp;
  final bool refresh;
  final bool loading;

  @override
  Widget build(BuildContext context) => AllNotesScreen(
        notes: notes,
        loading: loading,
        workspaces: workspaces,
        tapes: tapes,
        stored: stored ?? MemoryStored(),
        clock: () => seedNow,
        speaks: speaks,
        sideKey: sideKey,
        wisp: wisp,
        onOpen: (id) => asked.said.add('open $id'),
        onBack: () => asked.said.add('back'),
        onRefresh: refresh ? () async => asked.said.add('refresh') : null,
        onNoteMenu: (note, at) => asked.said.add('menu ${note.id}'),
        onOrganization: (id) => asked.said.add('organization $id'),
      );
}

/// The page on a screen with no notch and no home bar, as the web page was measured (Chromium, 390x844 and
/// 1000x800): [pumpApp], then the insets taken away. [split] stamps the root as the shell does on a window wide
/// enough for two panes (`data-split`), where app.css gives the bar its line and the air under it.
Future<void> pumpAllNotes(WidgetTester tester, Widget page, {Size size = const Size(390, 844), String theme = 'dark', double ratio = 2, bool split = false}) async {
  final sheet = split ? await tester.runAsync(() => loadTokenSheet(more: appStyleSheets)) : null;
  await pumpApp(tester, home: sheet == null ? page : RootStamps(sheet: sheet, stamps: const {'split': 'on'}, child: page), size: size, prefs: AppPreferences(theme: theme), ratio: ratio);
  tester.view.padding = FakeViewPadding.zero;
  tester.view.viewPadding = FakeViewPadding.zero;
  await tester.pump();
}

/// Past every entrance: the cards arrive over about half a second.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Takes the page down, and puts back the binding's switch for shadows that [pumpApp] turned on.
Future<void> away(WidgetTester tester) async {
  debugDisableShadows = true;
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 6));
}

/// Reads every picture on the page (the ghosts, which are assets) so a shot shows them: a test draws an asset only
/// once it has been decoded, which no pump of the test's clock waits for.
Future<void> loadPictures(WidgetTester tester) async {
  for (final element in find.byType(Image).evaluate().toList()) {
    final image = (element.widget as Image).image;
    await tester.runAsync(() => precacheImage(image, element));
  }
  await tester.pump();
}
