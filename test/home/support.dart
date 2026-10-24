import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/widgets.dart';
import 'package:ghost_md/calendar/event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/swipe.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_layout.dart';
import 'package:ghost_md/home/home_organizations.dart';
import 'package:ghost_md/home/home_screen.dart';
import 'package:ghost_md/app/style_sheets.dart';
import 'package:ghost_md/shell/root_stamps.dart';
import 'package:ghost_md/tapes/player.dart' show TapePlayer;
import 'package:glacier/glacier.dart';

import '../support/render.dart';

/// What a test's home page was asked to do, in order: `open flat`, `new`, `swipe pin flat`.
class Asked {
  final List<String> said = [];
}

/// The home page over a library, alive: its swipes pin, archive and delete in the library, as the app's would, and
/// everything that leaves the page is written down in [asked].
class Home extends StatefulWidget {
  const Home({
    super.key,
    required this.library,
    required this.workspaces,
    required this.asked,
    this.layout = HomeLayout.spotlight,
    this.speak = false,
    this.search = true,
    this.swipes = true,
    this.refresh = false,
    this.organizations,
    this.now,
    this.loading = false,
    this.recording,
    this.sideKey = false,
    this.ghost,
    this.headerEdge,
    this.dockHalo,
    this.notices = const [],
    this.tapePlayer,
    this.events,
    this.simple = false,
    this.talk = false,
    this.meetings = const {},
  });

  /// What the shelf's cassettes play under a resting mouse.
  final TapePlayer? tapePlayer;

  /// Which notes are meetings, as the root hands them from the preferences (GHST-112's shelf).
  final Map<String, num> meetings;

  /// Talk to Claude on the dock, as the root hands it where Claude is on and the build can hear (GHST-104).
  final bool talk;

  /// The calendars' events, as the root hands them.
  final ValueListenable<List<CalendarEvent>>? events;

  /// Simple mode (GHST-103), as the root says it.
  final bool simple;

  /// The notices above the notes, as the root hands them.
  final List<Widget> notices;
  final SampleLibrary library;
  final WorkspaceStore workspaces;
  final Asked asked;
  final HomeLayout layout;
  final bool speak;
  final bool search;
  final bool swipes;
  final bool refresh;
  final List<HomeOrg>? organizations;
  final int? now;
  final bool loading;
  final String? recording;
  final bool sideKey;
  final HomeGhostBuilder? ghost;
  final HomeEdgeBuilder? headerEdge;
  final HomeDockHaloBuilder? dockHalo;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  @override
  Widget build(BuildContext context) {
    final asked = widget.asked.said;
    return ValueListenableBuilder<List<Note>>(
      valueListenable: widget.library,
      builder: (context, notes, _) => HomeScreen(
        notes: notes,
        loading: widget.loading,
        workspaces: widget.workspaces,
        layout: widget.layout,
        clock: () => widget.now ?? seedNow,
        sideKey: widget.sideKey,
        recording: widget.recording,
        onOpen: (id) => asked.add('open $id'),
        onNew: () => asked.add('new'),
        onCapture: widget.speak ? () => asked.add('speak') : null,
        onSearch: widget.search ? () => asked.add('search') : null,
        onAllNotes: () => asked.add('all notes'),
        onSwipe: widget.swipes
            ? (note, action) {
                asked.add('swipe ${action.name} ${note.id}');
                switch (action) {
                  case NoteSwipe.pin:
                    widget.library.pin(note.id, pinned: !note.starred);
                  case NoteSwipe.archive:
                    widget.library.archive(note.id, archived: true);
                  case NoteSwipe.delete:
                    widget.library.delete(note.id);
                }
              }
            : null,
        notices: widget.notices,
        onRefresh: widget.refresh
            ? () async {
                asked.add('refresh');
                await widget.library.refresh();
              }
            : null,
        onManageWorkspace: (which) => asked.add(which == null ? 'new workspace' : 'edit ${which.name}'),
        onNewOrganization: widget.organizations == null ? null : () => asked.add('new organization'),
        onOrganization: widget.organizations == null ? null : (id) => asked.add('organization $id'),
        onNoteMenu: (id, at) => asked.add('menu $id'),
        organizations: widget.organizations ?? const [],
        ghost: widget.ghost,
        headerEdge: widget.headerEdge,
        dockHalo: widget.dockHalo,
        simple: widget.simple,
        claudeTalk: widget.talk ? const SizedBox(key: ValueKey('fake-talk'), width: 44, height: 44) : null,
        meetings: widget.meetings,
        onAllTapes: () => asked.add('all tapes'),
        onOpenTape: (id) => asked.add('open $id at its tape'),
        tapePlayer: widget.tapePlayer,
      ),
    );
  }
}

/// The seeded library and its workspaces, as the store screenshots have them.
({SampleLibrary library, WorkspaceStore workspaces, Asked asked}) seeded({bool workspaces = true}) => (
      library: SampleLibrary.seeded(clock: () => seedNow),
      workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(workspaces ? seedWorkspaces() : const WorkspaceSheet())),
      asked: Asked(),
    );

/// The page on a screen with no notch and no home bar, as the web page was measured: [pumpApp], then the insets
/// taken away. [split] stamps the root as the shell does on a window wide enough for two panes (`data-split`), which
/// is where app.css gives the bar its line and the air under it.
Future<void> pumpHome(WidgetTester tester, Widget home, {Size size = const Size(430, 932), String theme = 'dark', double ratio = 3, bool insets = false, bool split = false}) async {
  final sheet = split ? await tester.runAsync(() => loadTokenSheet(more: appStyleSheets)) : null;
  await pumpApp(tester, home: sheet == null ? home : RootStamps(sheet: sheet, stamps: const {'split': 'on'}, child: home), size: size, prefs: AppPreferences(theme: theme), ratio: ratio);
  if (!insets) {
    tester.view.padding = FakeViewPadding.zero;
    tester.view.viewPadding = FakeViewPadding.zero;
    await tester.pump();
  }
}

/// Past every entrance: the cards and rows arrive over about half a second.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i += 1) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
