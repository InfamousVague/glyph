// Review pictures of the in-place marks (docs/ACTIVITY.md, In place): a note whose banner is being made, a meeting
// note writing its summary, a list with sync arrows, a tick and a red one, and a share row sending its recording; on a
// phone and the Mac, light and dark, vivid and Calm.
//
// Not held: `FEATURE_SHOTS=1 flutter test --update-goldens test/activity/in_place_shots_test.dart` writes them into
// build/feature-shots/activity-in-place/.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/ghost_app.dart' show GhostApp;
import 'package:ghost_md/core/back.dart';
import 'package:ghost_md/core/background_jobs.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/editor/ai/summary_writing.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/base.dart';
import 'package:ghost_md/editor/view/column.dart';
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/home/note_card.dart';
import 'package:ghost_md/note/note_banner.dart';
import 'package:ghost_md/share/ui/share_rows.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/shell/header_pane.dart';
import 'package:ghost_md/sync/notes.dart';
import 'package:ghost_md/sync/sync_marks.dart';
import 'package:glacier/glacier.dart';

import '../account_ui/support.dart' as account;
import '../notes/bar_support.dart';
import '../share/support.dart' show HeldRecordings;
import '../support/render.dart';

void main() {
  setUpAll(loadAppFonts);

  final shots = Platform.environment.containsKey('FEATURE_SHOTS');
  const folder = '../../build/feature-shots/activity-in-place';
  const phone = (name: 'phone', size: Size(390, 844), mobile: true);
  const mac = (name: 'mac', size: Size(1280, 800), mobile: false);

  late DateTime now;
  late Activity record;
  late NoteSyncMarks marks;
  setUp(() {
    now = DateTime(2026, 10, 29, 16, 20);
    record = Activity(clock: () => now, store: () => MemoryStored());
    useActivity(record);
    marks = NoteSyncMarks(clock: () => now)..syncing = (() => true);
    useNoteSyncMarks(marks);
  });
  tearDown(() {
    useActivity(Activity());
    useNoteSyncMarks(NoteSyncMarks());
  });

  /// A note's page under the shell's header: what the shell's own pages are, a list under the glass.
  Widget page(List<Widget> children) => Builder(
        builder: (context) {
          final t = context.tokens;
          return Stack(
            fit: StackFit.expand,
            children: [
              ListView(padding: EdgeInsets.fromLTRB(0, t.len('app-safe-top') + t.space(4), 0, t.space(6)), children: children),
              const HeaderPane(),
            ],
          );
        },
      );

  Future<void> pumpShell(WidgetTester tester, ({String name, Size size, bool mobile}) window, {required String theme, required bool calm, Widget Function(BuildContext context)? note, Widget Function(BuildContext context)? home, List<String> open = const ['weekend', 'groceries']}) async {
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
        openNotes: open,
        mobile: window.mobile,
        finePointer: !window.mobile,
        onNew: () {},
        onSearch: () {},
        onSettings: () {},
        onDeleteNote: (_) {},
        noteBuilder: (context, shell, screen) => note?.call(context) ?? const SizedBox.shrink(),
        homeBuilder: (context, shell) => home?.call(context) ?? const SizedBox.shrink(),
        asideBuilder: (context, shell) => const SizedBox.shrink(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    if (note != null) {
      tester.state<AppShellState>(find.byType(AppShell)).openNote('groceries');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> picture(WidgetTester tester, String name) async {
    for (var i = 0; i < 4; i += 1) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await expectLater(find.byType(GhostApp), matchesGoldenFile('$folder/$name.png'));
  }

  Widget words(BuildContext context, String title, String body) {
    final t = context.tokens;
    final gutter = t.len('app-gutter');
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: t.textAt(t.len('app-h1'), weight: 'bold', tracking: t.len('app-tracking-title', em: t.len('app-h1')))),
          SizedBox(height: t.space(3)),
          Text(body, style: t.textAt(t.len('app-body'), height: 1.6, color: t.color('app-ink-2'))),
        ],
      ),
    );
  }

  const meeting = '# Design review\n\n## Transcript\n\n**Ana (0:00):** Let\'s start with the onboarding flow.\n\n**Sam (0:42):** The second screen asks for too much at once.\n\n**Ana (1:15):** Agreed. Split it in two and ship on Friday.';

  for (final window in [phone, mac]) {
    for (final theme in ['light', 'dark']) {
      for (final calm in [false, true]) {
        final look = '${window.name}-$theme${calm ? '-calm' : ''}';

        testWidgets('a picture: a note whose banner is being made, $look', (tester) async {
          if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            await pumpShell(
              tester,
              window,
              theme: theme,
              calm: calm,
              note: (context) => page([
                const NoteBannerView(name: null, store: null, making: true),
                words(context, 'Cabin weekend', 'The drive up, the key under the third stone, the wood to split before dark. Bring the map of the coast path, and ask Sam about the stove.'),
              ]),
            );
            await picture(tester, 'banner-$look');
          } finally {
            debugDefaultTargetPlatformOverride = null;
            debugDisableShadows = true;
          }
        }, skip: !shots);

        testWidgets('a picture: a meeting note writing its summary, $look', (tester) async {
          if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          final view = EditorView(wholeDocument: true, state: EditorState.create(doc: meeting, extensions: noteExtensions(more: <Extension>[summaryWriting(SummaryWritingHooks(jobId: () => 'summary:n1', record: record))])));
          addTearDown(view.destroy);
          try {
            record.begin('summary:n1', kind: JobKind.ai, title: 'Summary of Design review', line: 'Writing the summary')
              ..progress(done: 2, total: 3, steps: '2 of 3 parts', line: 'Writing the summary')
              ..write('## Summary\n\nThe onboarding\'s second screen asks for too much at once: it is split in two, and the flow ships on Friday.\n\n- [ ] Sam: split the second screen');
            await pumpShell(tester, window, theme: theme, calm: calm, note: (context) => page([BackScope(child: EditorColumn(view: view))]));
            await picture(tester, 'summary-$look');
          } finally {
            debugDefaultTargetPlatformOverride = null;
            debugDisableShadows = true;
          }
        }, skip: !shots);

        testWidgets('a picture: a list with sync arrows, a tick and a red one, $look', (tester) async {
          if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            final shown = library.take(6).toList();
            // Groceries and Weekend trip changed here and wait; Monday standup was refused; Planning call has just gone.
            final waiting = {'groceries', 'weekend'};
            marks.account(SyncState(notes: {for (final note in library) note.id: NoteMark(rev: 1, mark: waiting.contains(note.id) || note.id == shown[1].id ? 'before' : mark(note))}));
            marks.failed(shown[1].id, 'That note is too big to sync: over 2 MB.');
            marks.sent(shown[0].id);
            await pumpShell(
              tester,
              window,
              theme: theme,
              calm: calm,
              home: (context) {
                final t = context.tokens;
                final width = window.mobile ? window.size.width - 2 * t.len('app-gutter') : 360.0;
                return page([
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: t.len('app-gutter')),
                    child: Wrap(spacing: t.space(3), runSpacing: t.space(3), children: [for (final (i, note) in shown.indexed) SizedBox(width: width, child: NoteCard(note: note, index: i, onOpen: (_) {}, now: now.millisecondsSinceEpoch))]),
                  ),
                ]);
              },
            );
            await tester.longPress(find.byKey(ValueKey('note-sync:${shown[1].id}')));
            await picture(tester, 'sync-list-$look');
          } finally {
            debugDefaultTargetPlatformOverride = null;
            debugDisableShadows = true;
          }
        }, skip: !shots);

        testWidgets('a picture: a share row sending its recording, $look', (tester) async {
          if (window == mac) debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
          try {
            final device = await account.Device.make(recordings: HeldRecordings({'m': Uint8List.fromList(List.filled(5000, 7))}));
            preferences.update((p) => p.copyWith(meetings: {'m': 1}, calm: calm));
            device.notes.held['m'] = const Note(id: 'm', body: '# Design review\n\n## Transcript\n\n**Ana (0:00):** Let\'s start.', createdAt: 0, updatedAt: 0, recordingMs: 60000);
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
            await tester.runAsync(() => device.shares!.shareNote(device.notes.held['m']!, device.notes.held.values.toList()));
            await tester.runAsync(() => device.shares!.audioSent('m'));
            await device.pump(tester, ShareRows(services: device.services, noteId: 'm'), size: window.size, dark: theme == 'dark');
            await account.settle(tester, 12);
            record.begin('share-audio:m', kind: JobKind.audio, title: 'Sharing the recording of Design review', line: 'Sending the recording').progress(fraction: 0.4);
            await tester.pump();
            await picture(tester, 'share-$look');
            await account.endSettings(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
            debugDisableShadows = true;
          }
        }, skip: !shots);
      }
    }
  }
}
