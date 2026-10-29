// Review pictures of the app's running work (docs/ACTIVITY.md): the ring with three jobs, the tray with a running, a
// waiting and a failed row and Today, and a result chip; on a phone and the Mac, light and dark, vivid and Calm.
//
// Not held: `FEATURE_SHOTS=1 flutter test --update-goldens test/activity/activity_shots_test.dart` writes them into
// build/feature-shots/activity/, and into build/feature-shots/activity-idle/ the ring with nothing running (Matt,
// 2026-10-29: "Keep the activity indicator always showing just have it gray put when nothing is happening") at home and
// on a note, its tray, the bar's ••• with every note by folder and a new note at its top ("Put the all files folder
// icon under the more menu as well as the + button in the header"), and a sync filling ("Also don't spin the progress
// bar on the sync just make it fill as it's being synced").
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/activity/activity_ring.dart';
import 'package:ghost_md/app/ghost_app.dart' show GhostApp;
import 'package:ghost_md/art/lucide.g.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/note/note_tools.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/placeholders.dart';
import 'package:ghost_md/shell/top_bar_tools.dart';

import '../notes/bar_support.dart';
import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  const folder = '../../build/feature-shots/activity';
  const idleFolder = '../../build/feature-shots/activity-idle';
  const phone = (name: 'phone', size: Size(390, 844), mobile: true, fine: false);
  const mac = (name: 'mac', size: Size(1280, 800), mobile: false, fine: true);

  late DateTime now;
  late Activity record;
  setUp(() {
    now = DateTime(2026, 10, 29, 16, 20);
    record = Activity(clock: () => now, store: () => MemoryStored());
    useActivity(record);
  });
  tearDown(() => useActivity(Activity()));

  /// The day so far, and two before it.
  void today() {
    now = DateTime(2026, 10, 27, 11);
    record.begin('old1', kind: JobKind.ai, title: 'Summary of Retro').done(tally: const JobTally('summary', 'summaries'));
    record.begin('old2', kind: JobKind.images, title: 'Header images').done(tally: const JobTally('banner', 'banners', 8));
    now = DateTime(2026, 10, 29, 9);
    for (var i = 0; i < 3; i += 1) {
      record.begin('s$i', kind: JobKind.ai, title: ['Summary of Standup', 'Summary of Design review', 'Summary of 1:1 with Ana'][i]).done(tally: const JobTally('summary', 'summaries'));
    }
    record.begin('run', kind: JobKind.images, title: 'Making header images').done(tally: const JobTally('banner', 'banners', 12));
    record.begin('sync', kind: JobKind.sync, title: 'Syncing').done(tally: const JobTally('note synced', 'notes synced', 40));
    now = DateTime(2026, 10, 29, 16, 20);
  }

  /// Three running: a banner run here, a summary on the Mac, a voice-over here.
  void three() {
    record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', onStop: () {}, estimate: const JobEstimate(credits: 72, provider: 'Lovart', count: 12, one: 'header image', many: 'header images'))
      ..progress(done: 5, total: 12)
      ..update(spent: 30);
    record.elsewhere('summary-handoff', [Job(id: 'summary:n1', kind: JobKind.ai, title: 'Summary of Standup', line: 'Writing the summary', steps: '2 of 3 parts', device: 'mac', deviceName: 'Mac', startedAt: now, onOpen: () {})]);
    record.begin('voice-over:n2', kind: JobKind.audio, title: 'Reading “Trip notes” aloud', line: 'Reading in Elara’s voice', personStarted: true, onOpen: () {}).progress(done: 1, total: 3, steps: '2 of 3 parts');
  }

  /// The tray's mix: running, waiting and failed.
  void mix() {
    today();
    record.begin('lovart-banners', kind: JobKind.images, title: 'Making header images', onStop: () {}, estimate: const JobEstimate(credits: 72, provider: 'Lovart', count: 12, one: 'header image', many: 'header images'))
      ..progress(done: 5, total: 12)
      ..update(spent: 30);
    record.begin('model:qwen', kind: JobKind.downloads, title: 'Downloading Qwen 3.5 4B').waiting(WaitingOn.wifi);
    record.elsewhere('summary-handoff', [Job(id: 'summary:n1', kind: JobKind.ai, title: 'Summary of Standup', line: 'Writing the summary', steps: '2 of 3 parts', device: 'mac', deviceName: 'Mac', startedAt: now)]);
    record.begin('voice-over:n2', kind: JobKind.audio, title: 'Reading “Trip notes” aloud').failed('Your ElevenLabs credits are used up for now.', fix: JobFix(JobFixKind.topUp, () {}));
  }

  Future<void> pumpShell(WidgetTester tester, ({String name, Size size, bool mobile, bool fine}) window, {required String theme, required bool calm, bool note = true}) async {
    final sheet = await appSheet(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 100));
    await pumpApp(
      tester,
      size: window.size,
      prefs: Preferences(theme: theme, calm: calm),
      home: AppShell(
        sheet: sheet,
        notes: library,
        workspaces: spaces,
        openNotes: const ['weekend', 'groceries', 'standup'],
        mobile: window.mobile,
        finePointer: window.fine,
        organizations: const [OrgLike(id: 'o1', name: 'Attic Press', hue: 'moss')],
        onNew: () {},
        onSearch: () {},
        onSettings: () {},
        onOrganizations: () {},
        onDeleteNote: (_) {},
        noteBuilder: (context, shell, screen) => _StandInNote(note: screen.note),
        homeBuilder: (context, shell) => HomePlaceholder(notes: shell.notes, onOpen: shell.openNote, onAllNotes: shell.showAllNotes),
        asideBuilder: (context, shell) => const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    if (note) {
      tester.state<AppShellState>(find.byType(AppShell)).openNote('groceries');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> picture(WidgetTester tester, String name, {String into = folder}) async {
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await expectLater(find.byType(GhostApp), matchesGoldenFile('$into/$name.png'));
  }

  for (final window in [phone, mac]) {
    for (final theme in ['light', 'dark']) {
      final look = '${window.name}-$theme';
      Future<void> idle(WidgetTester tester, Future<void> Function() body) async {
        if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          await body();
        } finally {
          debugDefaultTargetPlatformOverride = null;
          debugDisableShadows = true;
        }
      }

      for (final note in [false, true]) {
        testWidgets('a picture: the idle ring, grey, ${note ? 'on a note' : 'at home'}, $look', (tester) async {
          await idle(tester, () async {
            await pumpShell(tester, window, theme: theme, calm: false, note: note);
            await picture(tester, 'idle-${note ? 'note' : 'home'}-$look', into: idleFolder);
          });
        }, skip: !shots);
      }

      testWidgets('a picture: the idle ring’s tray, $look', (tester) async {
        await idle(tester, () async {
          await pumpShell(tester, window, theme: theme, calm: false, note: false);
          await tester.tap(find.byKey(ActivityRing.key_));
          await picture(tester, 'idle-tray-$look', into: idleFolder);
        });
      }, skip: !shots);

      testWidgets('a picture: the bar’s ••• with every note by folder and a new note, $look', (tester) async {
        await idle(tester, () async {
          await pumpShell(tester, window, theme: theme, calm: false, note: false);
          await tester.tap(find.byKey(const ValueKey('header:overflow')).last);
          await picture(tester, 'more-menu-$look', into: idleFolder);
        });
      }, skip: !shots);

      testWidgets('a picture: a sync filling, 12 of 40, $look', (tester) async {
        await idle(tester, () async {
          record.begin('sync', kind: JobKind.sync, title: 'Syncing').progress(fraction: 12 / 40, steps: '12 of 40');
          await pumpShell(tester, window, theme: theme, calm: false, note: false);
          await tester.tap(find.byKey(ActivityRing.key_));
          await picture(tester, 'sync-filling-$look', into: idleFolder);
        });
      }, skip: !shots);
    }
  }

  for (final window in [phone, mac]) {
    for (final theme in ['light', 'dark']) {
      for (final calm in [false, true]) {
        final look = '${window.name}-$theme${calm ? '-calm' : ''}';
        testWidgets('a picture: the ring with three jobs, $look', (tester) async {
          if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            three();
            await pumpShell(tester, window, theme: theme, calm: calm);
            await picture(tester, 'ring-$look');
          } finally {
            debugDefaultTargetPlatformOverride = null;
            debugDisableShadows = true;
          }
        }, skip: !shots);

        testWidgets('a picture: the tray, running, waiting and failed, and Today, $look', (tester) async {
          if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            mix();
            await pumpShell(tester, window, theme: theme, calm: calm);
            await tester.tap(find.byKey(ActivityRing.key_));
            await picture(tester, 'tray-$look');
          } finally {
            debugDefaultTargetPlatformOverride = null;
            debugDisableShadows = true;
          }
        }, skip: !shots);

        testWidgets('a picture: a result chip, $look', (tester) async {
          if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await pumpShell(tester, window, theme: theme, calm: calm, note: false);
            record.begin('banner:n9', kind: JobKind.images, title: 'Header image for Trip notes').done(result: JobResult('Banner ready', onOpen: () {}));
            record.begin('summary:n8', kind: JobKind.ai, title: 'Summary of Standup').done(result: JobResult('Summarized “Standup”', action: 'Open', onOpen: () {}));
            await picture(tester, 'chip-$look');
          } finally {
            debugDefaultTargetPlatformOverride = null;
            debugDisableShadows = true;
          }
        }, skip: !shots);
      }
    }
  }
}

class _StandInNote extends StatefulWidget {
  const _StandInNote({required this.note});
  final Note note;

  @override
  State<_StandInNote> createState() => _StandInNoteState();
}

class _StandInNoteState extends State<_StandInNote> {
  late final ValueNotifier<NoteToolsModel> _model = ValueNotifier(NoteToolsModel(
    kind: NoteKind.words,
    page: true,
    switchable: true,
    onSwitch: () {},
    onMore: () {},
    more: false,
    actions: [
      ToolAction(id: 'share', label: 'Share', icon: Lucide.share2, onPress: () {}),
      ToolAction(id: 'history', label: 'Version history', icon: Lucide.history, onPress: () {}),
      ToolAction(id: 'bookmark', label: 'Bookmark this line', icon: Lucide.bookmark, on: false, onPress: () {}),
      ToolAction(id: 'speak', label: 'Talk into this note', icon: Lucide.mic, onPress: () {}),
    ],
  ));
  late final Widget _tools = NoteTools(model: _model);
  late final Widget _more = NoteMore(onMore: () {});

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TopBarFill(tools: _tools, tail: _more, model: _model, child: NotePlaceholder(note: widget.note));
}
