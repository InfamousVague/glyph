// A meeting's Transcript while Ghost is still in it (lib/meet/ui/live_transcript_view.dart; Matt, 2026-10-30: "If
// possible add real time transcriptions for meetings"), on the note desk: the captions the relay hands over, sealed
// and opened as the device opens them (lib/meet/live_captions.dart over the fake crypto and the service's kept frames
// in memory), filling the meeting's Transcript with named, timed turns and a Live badge; the Note view's Live
// transcript pill; following the newest words until the person scrolls up, and Back to live; the end handing over to
// the take's transcript; Simple, calm.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/queries/queries.dart' show queriesWatchMidnight;
import 'package:ghost_md/meet/live_captions.dart';
import 'package:ghost_md/meet/live_transcript.dart';
import 'package:ghost_md/meet/meet_api.dart';
import 'package:ghost_md/meet/speakers.dart' show captionsHeading;
import 'package:ghost_md/meet/ui/live_transcript_view.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/shell/app_shell.dart';
import 'package:ghost_md/tapes/transcript_words.dart';

import '../meet/support.dart';
import '../support/fake_crypto.dart';
import '../support/render.dart';

const String meeting = 'standup';
final String noteId = meetLiveNoteId(meeting);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    queriesWatchMidnight = false;
  });
  setUp(() => useStored(MemoryStored()));
  tearDown(liveTranscripts.clear);

  late SampleLibrary library;
  late FakeCrypto crypto;
  late FakeMeet service;
  late LiveCaptions captions;
  late String pub;

  Future<void> settle(WidgetTester tester, [int beats = 8]) async {
    for (var i = 0; i < beats; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  AppShellState shellOf(WidgetTester tester) => tester.state<AppShellState>(find.byType(AppShell));

  /// The app with the meeting's note as its first caption made it, open at it.
  Future<void> open(WidgetTester tester, {String experience = 'advanced'}) async {
    library = SampleLibrary.seeded();
    crypto = FakeCrypto();
    service = FakeMeet();
    await tester.runAsync(() async {
      final pair = await crypto.newEncryptionKey();
      pub = await crypto.encryptionPublicKeyOf(pair);
      final api = Api(base: 'http://127.0.0.1:9/api', fetcher: service.over((_) async => FetchResponse.json(404, {'error': 'no such route'})));
      captions = LiveCaptions(
        hooks: LiveCaptionsHooks(
          open: (m, n, wrapped, data) => openLive(crypto, pair, meeting: m, n: n, wrapped: wrapped, data: data),
          catchUp: (m, after) => MeetApi(api).live('token', m, after: after),
          noteFor: (m) async => noteId,
        ),
      );
      await library.apply(Note(id: noteId, body: liveNoteBody('Engineering Standup'), createdAt: seedNow - 600000, updatedAt: seedNow - 600000, source: NoteSource.capture));
    });
    await pumpApp(
      tester,
      prefs: Preferences(theme: 'light', meetings: {noteId: seedNow - 600000}, experience: experience),
      home: GhostRoot(launch: false, library: library, stored: MemoryStored(), workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    shellOf(tester).openNote(noteId);
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    shellOf(tester).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
  }

  var seq = 0;

  /// The bot's next batch, sealed by the service and handed over by the relay.
  Future<void> said(WidgetTester tester, List<(int, String, String)> lines, {(int, String, String)? saying}) async {
    await tester.runAsync(() async {
      seq += 1;
      final sealed = await sealedLive(
        crypto,
        pub,
        meeting,
        '$seq',
        lines: [for (final (at, who, text) in lines) {'at': at, 'speaker': who, 'text': text}],
        partial: saying == null ? null : {'at': saying.$1, 'speaker': saying.$2, 'text': saying.$3},
      );
      (service.live[meeting] ??= []).add({'seq': seq, 'wrapped': sealed.wrapped, 'data': sealed.data});
      await captions.heard({'t': 'captions', 'meeting': meeting, 'seq': seq, 'wrapped': sealed.wrapped, 'data': sealed.data});
    });
    await settle(tester, 4);
  }

  List<String> heads(WidgetTester tester) => [
        for (final turn in tester.widgetList<TranscriptTurn>(find.byType(TranscriptTurn))) '${turn.turn.speaker} ${turn.turn.startMs}: ${turn.turn.text}',
      ];

  setUp(() => seq = 0);

  testWidgets('the captions stream into the Transcript: named, timed turns as they come, a Live badge; the Note view has the pill', (tester) async {
    await open(tester);
    // Ghost has just joined: the note is Note and Transcript, and the Note view shows the way to the live words.
    await said(tester, [(4000, 'Sam Lee', 'Good morning everyone. Let’s start with the launch checklist.')]);
    expect(find.byKey(const ValueKey('meeting-view')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-transcript-pill')), findsOneWidget);
    expect(find.byType(Editor), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('live-transcript-pill')));
    await settle(tester);
    expect(find.byType(LiveTranscriptView), findsOneWidget);
    expect(find.byType(LiveBadge), findsOneWidget);
    expect(find.byKey(const ValueKey('live-transcript-pill')), findsNothing, reason: 'on the Transcript already');
    expect(heads(tester), ['Sam Lee 4000: Good morning everyone. Let’s start with the launch checklist.']);
    expect(find.text('Sam Lee · 0:04', findRichText: true), findsOneWidget);
    // More come, and the line being said.
    await said(tester, [(15000, 'Daniel', 'Thanks. The pricing page is drafted.')], saying: (24000, 'Priya', 'And the release notes'));
    expect(heads(tester), [
      'Sam Lee 4000: Good morning everyone. Let’s start with the launch checklist.',
      'Daniel 15000: Thanks. The pricing page is drafted.',
      'Priya 24000: And the release notes',
    ]);
    expect(tester.widget<TranscriptTurn>(find.byType(TranscriptTurn).last).light, TranscriptLight.coming, reason: 'the line being said, lighter');
    // Nothing of it written into the note as it came.
    expect(library.noteOf(noteId)!.body, liveNoteBody('Engineering Standup'));
    await close(tester);
  });

  testWidgets('it follows the newest words until the person scrolls up; Back to live takes it down again', (tester) async {
    await open(tester);
    await said(tester, [for (var i = 0; i < 40; i++) (i * 8000, i.isEven ? 'Sam Lee' : 'Daniel', 'Line $i of the meeting, long enough to take a line or two of the page on a phone.')]);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('meeting-view')), matching: find.text('Transcript')));
    await settle(tester);
    final scroll = find.byKey(const ValueKey('live-transcript'));
    ScrollPosition position() => tester.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable))).position;
    expect(position().pixels, closeTo(position().maxScrollExtent, 1), reason: 'at the newest words');
    expect(find.byKey(const ValueKey('back-to-live')), findsNothing);
    await tester.drag(scroll, const Offset(0, 400));
    await settle(tester);
    expect(find.byKey(const ValueKey('back-to-live')), findsOneWidget);
    final read = position().pixels;
    // A new line does not move the page under the person reading back.
    await said(tester, [(400000, 'Sam Lee', 'One more.')]);
    expect(position().pixels, read);
    await tester.tap(find.byKey(const ValueKey('back-to-live')));
    await settle(tester);
    expect(find.byKey(const ValueKey('back-to-live')), findsNothing);
    expect(position().pixels, closeTo(position().maxScrollExtent, 1));
    await said(tester, [(408000, 'Daniel', 'And another.')]);
    expect(position().pixels, closeTo(position().maxScrollExtent, 1), reason: 'following again');
    await close(tester);
  });

  testWidgets('the end: the badge goes, it says the transcript is coming, and the take’s takes its place', (tester) async {
    await open(tester);
    await said(tester, [(4000, 'Sam Lee', 'Good morning everyone.')]);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('meeting-view')), matching: find.text('Transcript')));
    await settle(tester);
    await tester.runAsync(() => captions.heard({'t': 'captions', 'meeting': meeting, 'ended': true}));
    await settle(tester);
    expect(find.byType(LiveBadge), findsNothing);
    expect(find.text('The meeting has ended. Its transcript is on its way.'), findsOneWidget);
    expect(heads(tester), hasLength(1), reason: 'the words stay until the take comes');
    // The take filed into the note (meet_in.dart syncMeet), its captions in turns, and the live words handed over.
    final filed = '# Engineering Standup\n\nGhost was in this meeting on 30 Oct, 09:30 to 09:45. It is being written up on your device.\n\n$captionsHeading\n\n**Sam Lee (0:04):** Good morning everyone.\n\n**Daniel (0:15):** The pricing page is drafted.\n';
    await tester.runAsync(() => library.apply(library.noteOf(noteId)!.copyWith(body: handedOver(library.noteOf(noteId)!.body, filed), updatedAt: seedNow)));
    liveTranscripts.forget(noteId);
    await settle(tester);
    expect(find.byType(LiveTranscriptView), findsNothing);
    expect(find.byType(TranscriptWords), findsOneWidget);
    expect(find.text('Daniel · 0:15', findRichText: true), findsOneWidget);
    await close(tester);
  });

  testWidgets('Simple mode shows it, calm: the badge and the pill wear the ink, no colour', (tester) async {
    await open(tester, experience: 'simple');
    await said(tester, [(4000, 'Sam Lee', 'Good morning everyone.')]);
    expect(tester.widget<LiveTranscriptPill>(find.byType(LiveTranscriptPill)).simple, isTrue);
    await tester.tap(find.byKey(const ValueKey('live-transcript-pill')));
    await settle(tester);
    expect(tester.widget<LiveBadge>(find.byType(LiveBadge)).simple, isTrue);
    expect(heads(tester), hasLength(1));
    await close(tester);
  });
}
