/// A spoken note's tape: the playhead the page follows (a clock stands in for the audio, `fake_player.dart`, which
/// is what lets this run at all), the phrases lit as they are heard, and the strip's Remove, which asks first on a
/// note whose voice memos play from the recording. `src/app/tapes/tapes.test.tsx`, case for case.
///
/// What differs: the web mocked the summary queue and the refining queue; the strip is handed them here
/// (`TapeQueue`). A button is found by its semantics label where the web found it by its `aria-label`, and a
/// phrase's `data-current` and `data-past` are read off its widget. The cassette is painted, not an svg: where the
/// web read a reel's radius or its turn from the drawing, these read what the cassette was given and ask the same
/// geometry (`tape.dart`), and the one case about the svg's own nodes is skipped.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/tapes/note_tape.dart';
import 'package:ghost_md/tapes/player.dart';
import 'package:ghost_md/tapes/shelf.dart';
import 'package:ghost_md/tapes/tape.dart';
import 'package:ghost_md/tapes/tape_art.dart';
import 'package:ghost_md/tapes/transcript_words.dart';

import 'package:glacier/glacier.dart' show HapticKind;

import '../support/render.dart';
import 'fake_player.dart';

const phrases = [
  Segment(text: 'Pack the tent.', startMs: 0, endMs: 1000),
  Segment(text: 'And the stove.', startMs: 1000, endMs: 2000),
  Segment(text: 'Leave at six.', startMs: 2000, endMs: 3000),
];

final int _made = DateTime(2026, 9, 26, 9).millisecondsSinceEpoch;

Note makeNote(String id, String body, {int? recordingMs, List<Segment>? segments, NoteSource source = NoteSource.editor}) =>
    Note(id: id, body: body, createdAt: _made, updatedAt: _made, recordingMs: recordingMs, segments: segments, source: source);

void main() {
  setUpAll(loadAppFonts);
  setUp(() => useStored(MemoryStored()));

  late Tape tape;

  /// The tape of [note] over the clock, stopped when the test is over.
  Tape tapeOf(Note note, {Future<Note?> Function(String id)? getNote}) {
    final made = Tape(note, player: FakeTapePlayer(lengths: {note.id: note.recordingMs ?? 0}), getNote: getNote, haptic: ([HapticKind kind = HapticKind.light]) {});
    addTearDown(made.dispose);
    return made;
  }

  Finder button(String label) => find.bySemanticsLabel(label).first;
  Finder said(String words) => find.textContaining(words, findRichText: true);

  Future<void> away(WidgetTester tester) async {
    // The clock is a timer of the test's, and the binding wants none left; and its own switch for shadows back.
    tape.player.dispose();
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
  }

  /// `<Probe note={…} />`: the note's tape, and its words under it.
  Future<void> probe(WidgetTester tester, Note note, {Future<Note?> Function(String id)? getNote}) async {
    tape = tapeOf(note, getNote: getNote);
    await pumpApp(tester, home: TranscriptWords(key: UniqueKey(), tape: tape));
  }

  group('the tape, playing', () {
    testWidgets('fetches the phrases of a note the list loaded without them, and says so while it waits', (tester) async {
      await probe(tester, makeNote('t', '# Trip', recordingMs: 3000), getNote: (id) => Future.delayed(const Duration(milliseconds: 10), () => makeNote(id, '# Trip', recordingMs: 3000, segments: phrases)));
      expect(find.bySemanticsLabel('Loading the transcript'), findsWidgets);
      // The note is read again by id for its phrases.
      await tester.pump(const Duration(milliseconds: 10));
      await tester.pump();
      expect(tape.segments?.map((s) => s.text), ['Pack the tent.', 'And the stove.', 'Leave at six.']);
      expect(find.bySemanticsLabel('Loading the transcript'), findsNothing);
      await away(tester);
    });

    testWidgets('runs on a clock in a browser, lights the phrase under the playhead, and stops at the end', (tester) async {
      await probe(tester, makeNote('t', '# Trip', recordingMs: 3000, segments: phrases));
      // `tape.web`: there is no browser here, and the clock is the player the tape was given.
      expect(tape.player, isA<FakeTapePlayer>());
      expect(tape.length, 3000);
      expect(tape.current, 0);
      await tape.toggle();
      expect(tape.playing, isTrue);
      await tester.pump(const Duration(milliseconds: 1500));
      expect(tape.current, 1);
      final lit = [for (final phrase in tester.widgetList<TranscriptPhrase>(find.byType(TranscriptPhrase))) (phrase.segment.text, phrase.current, phrase.past)];
      expect(lit, [('Pack the tent.', false, true), ('And the stove.', true, false), ('Leave at six.', false, false)]);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(tape.playing, isFalse);
      expect(tape.at, 0);
      await away(tester);
    });

    testWidgets('goes to a phrase that is tapped', (tester) async {
      await probe(tester, makeNote('t', '# Trip', recordingMs: 3000, segments: phrases));
      await tester.tap(find.text('Leave at six.'));
      await tester.pump();
      expect(tape.at, 2000);
      expect(tape.current, 2);
      await away(tester);
    });

    testWidgets('says when a recording kept no words', (tester) async {
      await probe(tester, makeNote('t', '# Trip', recordingMs: 3000, segments: const []));
      expect(find.text('No words were kept with this recording.'), findsOneWidget);
      expect(find.byType(Text), findsOneWidget);
      await away(tester);
    });
  });

  group('the tape at the top of a note', () {
    Future<void> strip(WidgetTester tester, {bool hasMemos = false, VoidCallback? onRemove, int recordingMs = 65000, TapeSummary? summary, TapeQueue queue = const TapeQueue()}) async {
      tape = tapeOf(makeNote('t', '# Trip', recordingMs: recordingMs, segments: phrases));
      await pumpApp(
        tester,
        home: Align(
          alignment: Alignment.topCenter,
          child: NoteTape(key: UniqueKey(), note: makeNote('t', '# Trip'), title: 'Trip', tape: tape, onSpeak: () {}, onRemove: onRemove ?? () {}, hasMemos: hasMemos, summary: summary, queue: queue),
        ),
      );
    }

    TapeSummary summary({void Function(bool replace)? ask, bool Function()? edited, bool behind = false}) => TapeSummary(ask: ask ?? (_) {}, edited: edited ?? () => false, behind: behind);

    Future<void> press(WidgetTester tester, String label) async {
      await tester.tap(button(label));
      await tester.pump();
    }

    testWidgets('is not there for a note with nothing recorded', (tester) async {
      await strip(tester, recordingMs: 0);
      expect(find.bySemanticsLabel('Recording'), findsNothing);
      expect(find.byType(TapeArt), findsNothing);
      expect(find.byType(Text), findsNothing);
      await away(tester);
    });

    testWidgets('winds an hour-long tape over its whole length in playback, rather than sitting full from the fifth minute', (tester) async {
      await strip(tester, recordingMs: 3600000);
      double takeup() {
        final art = tester.widget<TapeArt>(find.byType(TapeArt));
        return packRadii(art.positionMs, art.lengthMs).takeup;
      }

      // Still, the whole recording is on the right reel.
      expect(takeup(), closeTo(packMaxR, 0.005));
      // Five minutes in, a five-minute tape would be full; an hour's is a twelfth wound.
      tape.seek(300000);
      await tester.pump();
      expect(takeup(), closeTo(packRadii(300000, 3600000).takeup, 0.005));
      expect(takeup(), lessThan(packMaxR / 2));
      await away(tester);
    });

    testWidgets('says how long the recording is, and plays and pauses it', (tester) async {
      await strip(tester);
      expect(said('0:00 / 1:05'), findsOneWidget);
      await press(tester, 'Play');
      expect(button('Pause'), findsOneWidget);
      await away(tester);
    });

    testWidgets('removes a recording at once where no voice memo plays from it', (tester) async {
      var removed = 0;
      await strip(tester, onRemove: () => removed += 1);
      await press(tester, "Remove this note's recording");
      expect(removed, 1);
      await away(tester);
    });

    testWidgets('has a Summarize word only where there is a model, which asks the queue for the recording’s summary', (tester) async {
      await strip(tester);
      expect(find.bySemanticsLabel('Summarize the recording'), findsNothing);
      final asked = <bool>[];
      await strip(tester, summary: summary(ask: asked.add));
      final word = button('Summarize the recording');
      expect(find.descendant(of: word, matching: find.text('Summarize')), findsOneWidget);
      expect(tester.getSemantics(word), isSemantics(label: 'Summarize the recording', tooltip: 'The recording, summarized under the title.'));
      await press(tester, 'Summarize the recording');
      expect(asked, [false]);
      expect(said('Summary is from before the last take.'), findsNothing);
      await away(tester);
    });

    testWidgets('asks before replacing a summary that was edited, replaces on Replace, and leaves it on Keep mine', (tester) async {
      final asked = <bool>[];
      await strip(tester, summary: summary(ask: asked.add, edited: () => true));
      await press(tester, 'Summarize the recording');
      expect(asked, isEmpty);
      expect(said('You edited the summary. Replace it?'), findsOneWidget);
      await press(tester, 'Keep the summary as you edited it');
      expect(asked, isEmpty);
      expect(said('You edited the summary. Replace it?'), findsNothing);
      await press(tester, 'Summarize the recording');
      await tester.pump(const Duration(milliseconds: 8000));
      expect(said('You edited the summary. Replace it?'), findsNothing);
      await press(tester, 'Summarize the recording');
      await press(tester, 'Replace the summary you edited');
      expect(asked, [true]);
      await away(tester);
    });

    testWidgets('says when the summary is from before the last take, when one is on its way, when a model is missing, and when it did not come', (tester) async {
      await strip(tester, summary: summary(behind: true));
      expect(said('Summary is from before the last take.'), findsOneWidget);
      await strip(tester, summary: summary(behind: true), queue: const TapeQueue(pending: true));
      var word = button('Summarize the recording');
      expect(find.descendant(of: word, matching: find.text('Summarizing')), findsOneWidget);
      expect(tester.getSemantics(word), isSemantics(hasEnabledState: true, isEnabled: false));
      expect(said('Summary is from before the last take.'), findsNothing);
      // Queued behind the note's better words: not "Summarizing" yet, and the strip says what it waits for.
      await strip(tester, summary: summary(), queue: const TapeQueue(pending: true, refining: true));
      word = button('Summarize the recording');
      expect(find.descendant(of: word, matching: find.text('Summarize')), findsOneWidget);
      expect(tester.getSemantics(word), isSemantics(hasEnabledState: true, isEnabled: false));
      expect(said('The summary comes after the better words.'), findsOneWidget);
      await strip(tester, summary: summary(), queue: const TapeQueue(needsModel: true));
      expect(said('Needs a model.'), findsOneWidget);
      await strip(tester, summary: summary(), queue: const TapeQueue(failed: true));
      expect(said('The summary didn’t come.'), findsOneWidget);
      await away(tester);
    });

    testWidgets('asks first where voice memos play from it, keeps it on Keep, and stops asking after a while', (tester) async {
      var removed = 0;
      await strip(tester, onRemove: () => removed += 1, hasMemos: true);
      await press(tester, "Remove this note's recording");
      expect(removed, 0);
      expect(said('The voice memos in this note play from this recording.'), findsOneWidget);
      await press(tester, "Keep this note's recording");
      expect(said('The voice memos in this note play from this recording.'), findsNothing);
      await press(tester, "Remove this note's recording");
      await tester.pump(const Duration(milliseconds: 5000));
      expect(button("Remove this note's recording"), findsOneWidget);
      await press(tester, "Remove this note's recording");
      await press(tester, 'Remove the recording and stop its voice memos');
      expect(removed, 1);
      await away(tester);
    });

    testWidgets('is the cassette beside its time, Play and its words, over the transcript: the picture', (tester) async {
      tape = tapeOf(makeNote('t', '# Trip', recordingMs: 65000, segments: phrases));
      tape.seek(1200);
      final note = makeNote('t', '# Trip');
      await pumpApp(
        tester,
        prefs: const AppPreferences(theme: 'light'),
        home: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              NoteTape(note: note, title: 'A weekend in the mountains, planned', tape: tape, onSpeak: () {}, onRemove: () {}, hasMemos: false, summary: summary(behind: true)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [const TapeMark(), const SizedBox(width: 8), TapeWords(note: makeNote('t', '# Trip', recordingMs: 65000), em: 14, dot: true), Text(tapeDate(note.createdAt))]),
              ),
              Expanded(child: TranscriptWords(tape: tape)),
            ],
          ),
        ),
      );
      // `minmax(0, 9.5rem)`: the cassette is 152 wide and keeps its drawing's shape.
      expect(tester.getSize(find.byType(TapeArt)), const Size(152, 152 * 204 / 320));
      expect(tester.widget<TapeArt>(find.byType(TapeArt)).title, 'A weekend in the moun…');
      expect(tester.widget<TapeArt>(find.byType(TapeArt)).side, '26 SEP');
      expect(find.text('26 Sep'), findsOneWidget);
      tape.player.dispose();
      await shot(tester, 'note-tape-light');
    });
  });

  group('the cassette', () {
    Future<void> show(WidgetTester tester, Widget art) => pumpApp(tester, home: Align(alignment: Alignment.topLeft, child: SizedBox(width: 240, child: art)));

    Future<void> gone(WidgetTester tester) async {
      debugDisableShadows = true;
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('turns its reels, frame by frame, while it plays', (tester) async {
      // The reels' angles are the painter's own; what can be seen from here is that a frame is always asked for.
      await show(tester, const TapeArt(positionMs: 30000, playing: true, title: 'Trip'));
      for (var frame = 0; frame < 10; frame += 1) {
        expect(tester.binding.hasScheduledFrame, isTrue);
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gone(tester);
    });

    testWidgets('draws its label bare, with the A mark and no words, and gives each cassette its own label mask', (tester) async {}, skip: true); // The label is painted on a canvas: there are no text nodes to list and no mask ids to share (test/home/home_parts_test.dart holds its picture).

    test('winds a longer tape over its own length, so an hour is not full from the fifth minute', () {
      double takeup(TapeArt art) => packRadii(art.positionMs, art.lengthMs).takeup;
      final fiveMinutes = takeup(const TapeArt(positionMs: 300000));
      final anHour = takeup(const TapeArt(positionMs: 300000, lengthMs: 3600000));
      expect(anHour, lessThan(fiveMinutes));
      // Left unsaid, the tape is the five-minute one, and five minutes fills it.
      expect(fiveMinutes, packRadii(300000).takeup);
      expect(fiveMinutes, closeTo(packMaxR, 0.005));
    });

    test('turns the reels over the radii its length gives: the nearly empty take-up of an hour turns faster than a full one', () {
      // Ten frames of 16 ms, as the cassette asks the geometry for them (`reelTurn` with what it was given).
      double turned(TapeArt art) => reelTurn(art.positionMs, 16, art.lengthMs).takeup * 10;
      final anHour = turned(const TapeArt(positionMs: 300000, lengthMs: 3600000, playing: true));
      final full = turned(const TapeArt(positionMs: 300000, playing: true));
      expect(full, greaterThan(0));
      expect(anHour, greaterThan(full * 1.5));
    });

    testWidgets('does not turn for someone who asked for less motion', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await show(tester, const TapeArt(positionMs: 30000, playing: true, title: 'Trip'));
      await tester.pump(const Duration(seconds: 1));
      expect(tester.binding.hasScheduledFrame, isFalse);
      await gone(tester);
    });
  });
}
