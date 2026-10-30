// A meeting's note in two views, Note and Transcript (lib/note/meeting_view.dart; Matt, 2026-10-30: "Also use a
// button to switch to the transcript in the note don't show the transcript on the note section"), and its tape's
// Rebuild transcript ("some of the meeting transcripts still go into one giant block instead of maintaining the name
// (timestamp): prefix on each line please address"). The note is one file all the way through.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/find_bar/find_marks.dart' show searchIn;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/editor/view/transcript_fold.dart';
import 'package:ghost_md/note/note_screen.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/tapes/transcript_words.dart';

import '../support/render.dart';
import '../tapes/fake_player.dart';

const String _id = 'standup';
const String _above = '# Engineering Standup\n\n## Summary\n\nThe team agreed to ship today.\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06.';
const String _transcript = '## Transcript\n\n**Phil Mulliken (0:02):** Oh yeah, we can talk about it. I was discussing the matching engine with Kevin yesterday.\n\n**Matt (1:04):** Shipping the activity tray today.\n\n**Dana Reyes (2:10):** Compliance wants the audit export by Monday.';
const String _body = '$_above\n\n$_transcript\n';
const List<Segment> _phrases = [
  Segment(startMs: 2000, endMs: 30000, text: 'Oh yeah, we can talk about it. I was discussing the matching engine with Kevin yesterday.'),
  Segment(startMs: 64000, endMs: 90000, text: 'Shipping the activity tray today.'),
  Segment(startMs: 130000, endMs: 150000, text: 'Compliance wants the audit export by Monday.'),
];

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });
  setUp(() => useStored(MemoryStored()));

  late SampleLibrary library;
  late FakeTapePlayer player;

  Future<void> settle(WidgetTester tester, [int beats = 6]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

  /// The app with [body] filed as note [_id], a meeting where [meeting], its recording [ms] long with [segments].
  Future<void> open(WidgetTester tester, {String body = _body, bool meeting = true, int ms = 3 * 60000, List<Segment>? segments = _phrases, String experience = 'advanced'}) async {
    library = SampleLibrary.seeded();
    await tester.runAsync(() => library.apply(Note(id: _id, body: body, createdAt: seedNow - 3600000, updatedAt: seedNow - 3600000, source: NoteSource.capture, recordingMs: ms == 0 ? null : ms, segments: segments)));
    player = FakeTapePlayer(lengths: {_id: ms});
    await pumpApp(
      tester,
      prefs: Preferences(theme: 'light', meetings: meeting ? {_id: seedNow - 3600000} : const {}, experience: experience),
      home: GhostRoot(launch: false, library: library, stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow, tapePlayer: player),
    );
    await tester.pump(const Duration(milliseconds: 100));
    shellOf(tester).openNote(_id);
    await settle(tester, 8);
  }

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  EditorState editor(WidgetTester tester) => tester.state<NoteScreenState>(find.byType(NoteScreen)).view!.state;

  Future<void> choose(WidgetTester tester, String view) async {
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('meeting-view')), matching: find.text(view)));
    await settle(tester, 8);
  }

  String? saved() => library.noteOf(_id)?.body;

  testWidgets('a meeting opens at Note: the transcript is folded out of its words, Note and Transcript over them', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('meeting-view')), findsOneWidget);
    expect(find.byType(TranscriptWords, skipOffstage: false), findsNothing);
    expect(find.byType(Editor), findsOneWidget);
    final folds = transcriptFolds(editor(tester));
    expect(folds, hasLength(1));
    final doc = editor(tester).doc.toString();
    expect(doc.substring(folds.single.from), startsWith('## Transcript'), reason: 'still in the one file');
    await close(tester);
  });

  testWidgets('Transcript shows the turns, each its speaker and time over its words, and is remembered for the note', (tester) async {
    await open(tester);
    await choose(tester, 'Transcript');
    expect(find.byType(TranscriptWords), findsOneWidget);
    expect(find.byType(TranscriptTurn), findsNWidgets(3));
    expect(find.text('Phil Mulliken · 0:02', findRichText: true), findsOneWidget);
    expect(find.text('Matt · 1:04', findRichText: true), findsOneWidget);
    expect(find.text('Shipping the activity tray today.'), findsOneWidget);
    expect(find.byType(Editor), findsNothing);
    await close(tester);
    // Opened again: Transcript, as it was left.
    await open(tester);
    expect(find.byType(TranscriptWords), findsOneWidget);
    await choose(tester, 'Note');
    expect(find.byType(TranscriptWords, skipOffstage: false), findsNothing);
    await close(tester);
  });

  testWidgets('an edit in the Note view keeps the transcript byte for byte', (tester) async {
    await open(tester);
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    // Typed at the end of the note, past where the words show: it goes on the meeting's line.
    view.dispatch(TransactionSpec(selection: EditorSelection.single(view.state.doc.length), userEvent: 'select.pointer'));
    final at = view.state.selection.main.head;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: at, insert: ' Notes follow.'), userEvent: 'input.type'));
    await settle(tester, 12);
    // Select all and type over it.
    view.dispatch(TransactionSpec(selection: EditorSelection.single(0, view.state.doc.length), userEvent: 'select'));
    final all = view.state.selection.main;
    view.dispatch(TransactionSpec(changes: ChangeSpec(from: all.from, to: all.to, insert: '# Standup'), userEvent: 'input.type'));
    await settle(tester, 12);
    final body = saved()!;
    expect(body.substring(body.indexOf('## Transcript')), '$_transcript\n');
    expect(body, startsWith('# Standup\n'));
    await close(tester);
  });

  testWidgets('a find\'s match in the transcript opens the Transcript view at its turn', (tester) async {
    await open(tester);
    final view = tester.state<NoteScreenState>(find.byType(NoteScreen)).view!;
    searchIn(view, 'audit export');
    await settle(tester, 8);
    expect(find.byType(TranscriptWords), findsOneWidget);
    expect(find.text('Compliance wants the audit export by Monday.'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a search\'s hit on a line of the transcript opens the Transcript view', (tester) async {
    await open(tester);
    shellOf(tester).backToList();
    await settle(tester);
    final line = _body.split('\n').indexWhere((l) => l.contains('Shipping')) + 1;
    shellOf(tester).openNote(_id, at: 'line:$line');
    await settle(tester, 12);
    expect(find.byType(TranscriptWords), findsOneWidget);
    await close(tester);
  });

  testWidgets('a turn tapped plays the recording from its time, and is lit while it plays', (tester) async {
    await open(tester);
    await choose(tester, 'Transcript');
    await tester.tap(find.text('Shipping the activity tray today.'));
    await tester.pump();
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(player.calls, containsAllInOrder(<String>['load $_id', 'seek 64000', 'play']), reason: 'from the turn\'s time');
    final lit = tester.widgetList<TranscriptTurn>(find.byType(TranscriptTurn)).where((turn) => turn.light == TranscriptLight.current).toList();
    expect(lit.single.turn.speaker, 'Matt');
    await tester.tap(find.bySemanticsLabel('Pause the recording'));
    await tester.pump();
    await close(tester);
  });

  testWidgets('a note that is no meeting is as it was: no fold, no Note and Transcript', (tester) async {
    await open(tester, body: '# Notes on transcripts\n\nA heading of my own below.\n\n## Transcript\n\nWords I typed.\n', meeting: false, ms: 0, segments: null);
    expect(find.byKey(const ValueKey('meeting-view')), findsNothing);
    expect(transcriptFolds(editor(tester)), isEmpty);
    await close(tester);
  });

  testWidgets('a meeting with no recording here still has its Transcript, to read', (tester) async {
    await open(tester, ms: 0, segments: null);
    await choose(tester, 'Transcript');
    expect(find.byType(TranscriptTurn), findsNWidgets(3));
    await close(tester);
  });

  testWidgets('Rebuild transcript writes the one block in turns from the kept phrases, the summary untouched', (tester) async {
    const block = '$_above\n\n## Transcript\n\nOh yeah, we can talk about it. I was discussing the matching engine with Kevin yesterday. Shipping the activity tray today. Compliance wants the audit export by Monday.\n';
    await open(tester, body: block);
    await choose(tester, 'Transcript');
    await tester.tap(find.bySemanticsLabel('Rebuild the transcript from its kept phrases and captions'));
    await settle(tester, 12);
    final body = saved()!;
    expect(body.substring(0, body.indexOf('## Transcript')), '$_above\n\n', reason: 'the summary and the line, byte for byte');
    expect(body.substring(body.indexOf('## Transcript')), '## Transcript\n\n(0:02) Oh yeah, we can talk about it. I was discussing the matching engine with Kevin yesterday.\n\n(1:04) Shipping the activity tray today.\n\n(2:10) Compliance wants the audit export by Monday.\n');
    expect(find.byType(TranscriptTurn), findsNWidgets(3));
    await close(tester);
  });

  testWidgets('in Simple mode Rebuild waits behind the strip\'s More, which opens in place', (tester) async {
    await open(tester, experience: 'simple');
    await choose(tester, 'Transcript');
    expect(find.bySemanticsLabel('Rebuild the transcript from its kept phrases and captions'), findsNothing);
    await tester.tap(find.bySemanticsLabel('More for the recording'));
    await settle(tester, 2);
    expect(find.bySemanticsLabel('Rebuild the transcript from its kept phrases and captions'), findsOneWidget);
    await close(tester);
  });
}
