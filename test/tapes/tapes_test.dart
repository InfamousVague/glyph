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

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/preferences.dart';
import 'package:ghost_md/core/locale_dates.dart';
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

  // Matt, 2026-10-24: "when clicking on meetings it doesn't load the transcript". The transcript is read with the tape
  // still, so it stands on what the note's words keep where the phrases do not carry the meeting.
  group('the transcript, read', () {
    const meet = '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n\n## Summary\n\n- Pricing is drafted.\n\n'
        '## Transcript\n\n**Sam Lee:** Good morning everyone. Let\'s start with the launch checklist.\n\n**Daniel:** Thanks. The pricing page is drafted and the copy is with legal.';

    test('the transcript a note keeps is its paragraphs under the heading, and phrases carry it when they are at least half its words', () {
      expect(writtenTranscript(meet), ['**Sam Lee:** Good morning everyone. Let\'s start with the launch checklist.', '**Daniel:** Thanks. The pricing page is drafted and the copy is with legal.']);
      expect(writtenTranscript('# Trip\n\nPack the tent.'), isNull);
      expect(writtenTranscript('# Trip\n\n## Transcript\n'), isNull);
      expect(captionsKept('# M\n\n## Captions\n\n**Sam (0:04):** Hi.\n\n## Later\n\nNo.'), ['**Sam (0:04):** Hi.']);
      final written = writtenTranscript(meet);
      expect(phrasesWhole(const [Segment(text: 'Go.', startMs: 0, endMs: 500)], written), isFalse, reason: 'a 13-minute meeting\'s one live phrase');
      expect(phrasesWhole(const [Segment(text: 'Good morning everyone. Let\'s start with the launch checklist.', startMs: 0, endMs: 4000), Segment(text: 'Thanks. The pricing page is drafted.', startMs: 4000, endMs: 8000)], written), isTrue);
      expect(phrasesWhole(const [], written), isFalse);
      expect(phrasesWhole(phrases, null), isTrue, reason: 'nothing written to tell by');
    });

    testWidgets('shows the transcript the note keeps, named, where it has no phrases or only a live word', (tester) async {
      for (final segments in [const <Segment>[], const [Segment(text: 'Go.', startMs: 0, endMs: 500)]]) {
        await probe(tester, makeNote('t', meet, recordingMs: 780000, segments: segments));
        expect(find.text('Sam Lee: Good morning everyone. Let\'s start with the launch checklist.', findRichText: true), findsOneWidget);
        expect(find.text('Daniel: Thanks. The pricing page is drafted and the copy is with legal.', findRichText: true), findsOneWidget);
        expect(find.text('Go.'), findsNothing);
        expect(find.byType(TranscriptPhrase), findsNothing, reason: 'untimed: nothing to take the tape to');
        await away(tester);
      }
    });

    testWidgets('reads its phrases in the second ink until the tape moves, then lights them as they are heard', (tester) async {
      await probe(tester, makeNote('t', '# Trip', recordingMs: 3000, segments: phrases));
      expect(tester.widgetList<TranscriptPhrase>(find.byType(TranscriptPhrase)).map((p) => p.reading), everyElement(isTrue));
      await tape.toggle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widgetList<TranscriptPhrase>(find.byType(TranscriptPhrase)).map((p) => p.reading), everyElement(isFalse));
      await away(tester);
    });

    testWidgets('says the write-up is to come first, over Meet\'s captions where there are any, and a skeleton where there are none', (tester) async {
      const waiting = '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45. It is being written up on your device.\n\n## Captions\n\n**Sam Lee (0:04):** Good morning everyone.\n';
      tape = tapeOf(makeNote('t', waiting, recordingMs: 780000, segments: const []));
      await pumpApp(tester, home: TranscriptWords(key: UniqueKey(), tape: tape, writeUp: 'Writing up… 42%'));
      expect(find.text('Writing up… 42%'), findsOneWidget);
      expect(find.text('Sam Lee (0:04): Good morning everyone.', findRichText: true), findsOneWidget);
      expect(find.text('No words were kept with this recording.'), findsNothing);
      await away(tester);
      tape = tapeOf(makeNote('u', '# Launch sync', recordingMs: 780000, segments: const []));
      await pumpApp(tester, home: TranscriptWords(key: UniqueKey(), tape: tape, writeUp: 'Writing up…'));
      expect(find.text('Writing up…'), findsOneWidget);
      expect(find.bySemanticsLabel('Loading the transcript'), findsWidgets);
      expect(find.text('No words were kept with this recording.'), findsNothing);
      await away(tester);
    });
  });

  // Matt, 2026-10-25: "the transcript for the meeting should highlight the section of audio that's playing". Lit by
  // the phrases where they carry the meeting, by the captions' own times where they do not, and never by a time
  // made up.
  group('the transcript, lit as it is heard', () {
    List<TranscriptLight> phraseLights(WidgetTester tester) => [for (final phrase in tester.widgetList<TranscriptPhrase>(find.byType(TranscriptPhrase))) phrase.light];
    List<TranscriptLight> paragraphLights(WidgetTester tester) => [for (final paragraph in tester.widgetList<WrittenParagraph>(find.byType(WrittenParagraph))) paragraph.light];
    const r = TranscriptLight.reading, p = TranscriptLight.past, c = TranscriptLight.current, n = TranscriptLight.coming;

    // Three timed turns, and a paragraph that is more words of the second.
    const captions = '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45. It is being written up on your device.\n\n## Captions\n\n'
        '**Sam Lee (0:00):** Good morning everyone.\n\n**Daniel (0:02):** The pricing page is drafted.\n\nAnd the copy is with legal.\n\n(0:04) Who has the press note?\n';

    /// [ms] of the tape played, a frame for each of the clock's ticks, as a phone draws them.
    Future<void> run(WidgetTester tester, int ms) async {
      for (var i = 0; i < ms ~/ 100; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    ScrollPosition scrolled(WidgetTester tester) => tester.state<ScrollableState>(find.descendant(of: find.byType(TranscriptWords), matching: find.byType(Scrollable))).position;

    /// [count] phrases of a second each, enough to scroll.
    List<Segment> many(int count) => [for (var i = 0; i < count; i++) Segment(text: 'Phrase number $i of the meeting, said aloud.', startMs: i * 1000, endMs: (i + 1) * 1000)];

    test('the line lit is the last begun at the playhead, by halves, and stays lit through the quiet after it', () {
      const starts = [0, 1000, 2000, 5000];
      expect(litAt(starts, 0), 0);
      expect(litAt(starts, 999), 0);
      expect(litAt(starts, 1000), 1);
      expect(litAt(starts, 4999), 2, reason: 'a silence after the third phrase: it stays lit');
      expect(litAt(starts, 90000), 3);
      expect(litAt(const [500], 100), -1, reason: 'before the first');
      expect(litAt(const [], 100), -1);
      final hour = [for (var i = 0; i < 3600; i++) i * 1000];
      expect(litAt(hour, 1234567), 1234);
      expect(paragraphStartMs('**Sam Lee (0:04):** Hi.'), 4000);
      expect(paragraphStartMs('**Sam Lee (1:02:03):** Hi.'), 3723000);
      expect(paragraphStartMs('(12:40) Hi.'), 760000);
      expect(paragraphStartMs('**Sam Lee:** Hi.'), isNull);
      expect(paragraphStartMs('Hi (0:04).'), isNull);
    });

    testWidgets('lights nothing before the tape has moved, follows the playhead through the phrases, and nothing once it has played to its end', (tester) async {
      await probe(tester, makeNote('t', '# Trip', recordingMs: 3000, segments: phrases));
      expect(phraseLights(tester), [r, r, r], reason: 'never played: the first phrase is not lit as if heard');
      expect(tester.widget<TranscriptPhrase>(find.byType(TranscriptPhrase).first).current, isFalse);
      await tape.toggle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(phraseLights(tester), [c, n, n]);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(phraseLights(tester), [p, c, n]);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(phraseLights(tester), [p, p, c]);
      await tester.pump(const Duration(milliseconds: 1000));
      expect(tape.playing, isFalse);
      expect(phraseLights(tester), [r, r, r], reason: 'played to its end, it rests at its start');
      await away(tester);
    });

    testWidgets('keeps the line lit while paused, and through a quiet between phrases', (tester) async {
      const gaps = [Segment(text: 'Pack the tent.', startMs: 0, endMs: 800), Segment(text: 'And the stove.', startMs: 1000, endMs: 1400), Segment(text: 'Leave at six.', startMs: 2500, endMs: 3000)];
      await probe(tester, makeNote('t', '# Trip', recordingMs: 3000, segments: gaps));
      await tape.toggle();
      await tester.pump(const Duration(milliseconds: 1800));
      expect(tape.current, -1, reason: 'no phrase is under the playhead');
      expect(phraseLights(tester), [p, c, n], reason: 'the one last begun stays lit');
      await tape.toggle();
      await tester.pump(const Duration(seconds: 2));
      expect(tape.playing, isFalse);
      expect(tape.at, greaterThan(0));
      expect(phraseLights(tester), [p, c, n]);
      await away(tester);
    });

    testWidgets('lights the captions by the times they were kept with, a paragraph without one with the turn before it', (tester) async {
      tape = tapeOf(makeNote('t', captions, recordingMs: 6000, segments: const []));
      await pumpApp(tester, home: TranscriptWords(key: UniqueKey(), tape: tape, writeUp: 'Writing up… 42%'));
      expect(paragraphLights(tester), [r, r, r, r]);
      expect(find.text('Sam Lee (0:00): Good morning everyone.', findRichText: true), findsOneWidget);
      await tape.toggle();
      await tester.pump(const Duration(milliseconds: 500));
      expect(paragraphLights(tester), [c, n, n, n]);
      await tester.pump(const Duration(milliseconds: 2000));
      expect(paragraphLights(tester), [p, c, c, n], reason: 'from 0:02 to 0:04, the turn and the words after it');
      await tester.pump(const Duration(milliseconds: 2000));
      expect(paragraphLights(tester), [p, p, p, c]);
      await tape.toggle();
      await tester.pump(const Duration(seconds: 1));
      expect(paragraphLights(tester), [p, p, p, c], reason: 'paused: the last stays lit');
      await away(tester);
    });

    testWidgets('takes the tape to a timed paragraph that is tapped, and lights it', (tester) async {
      tape = tapeOf(makeNote('t', captions, recordingMs: 6000, segments: const []));
      await pumpApp(tester, home: TranscriptWords(key: UniqueKey(), tape: tape, writeUp: 'Writing up…'));
      await tester.tap(find.text('And the copy is with legal.'));
      await tester.pump();
      expect(tape.at, 2000, reason: 'the start of the turn it is part of');
      expect(paragraphLights(tester), [p, c, c, n]);
      await tester.tap(find.text('(0:04) Who has the press note?', findRichText: true));
      await tester.pump();
      expect(tape.at, 4000);
      await away(tester);
    });

    testWidgets('leaves a transcript written with no times unlit, and not to be tapped, while the tape plays', (tester) async {
      const untimed = '# Launch sync\n\n## Transcript\n\n**Sam Lee:** Good morning everyone.\n\n**Daniel:** The pricing page is drafted.\n';
      await probe(tester, makeNote('t', untimed, recordingMs: 6000, segments: const []));
      await tape.toggle();
      await tester.pump(const Duration(milliseconds: 2500));
      expect(tape.playing, isTrue);
      expect(paragraphLights(tester), [r, r]);
      expect(tester.widgetList<WrittenParagraph>(find.byType(WrittenParagraph)).map((w) => w.onPressed), everyElement(isNull));
      await tester.tap(find.text('Daniel: The pricing page is drafted.', findRichText: true));
      await tester.pump();
      expect(tape.at, inInclusiveRange(2500, 2600), reason: 'nothing to take the tape to');
      await away(tester);
    });

    testWidgets('keeps the line being heard in view while it plays, stops when scrolled by hand, and follows again from Follow or a tapped line', (tester) async {
      await probe(tester, makeNote('t', '# Meeting', recordingMs: 200000, segments: many(200)));
      expect(find.text('Follow'), findsNothing);
      await tape.toggle();
      await run(tester, 30000);
      await run(tester, 600);
      final lit = find.text('Phrase number ${tape.at ~/ 1000} of the meeting, said aloud.');
      final view = tester.getRect(find.byType(TranscriptWords));
      expect(scrolled(tester).pixels, greaterThan(0), reason: 'followed');
      expect((tester.getCenter(lit).dy - view.center.dy).abs(), lessThan(view.height / 4), reason: 'the lit line about the middle');
      expect(find.text('Follow'), findsNothing);

      // Scrolled back up by hand: the line being heard is left to go on without the view.
      await tester.drag(find.byType(TranscriptWords), const Offset(0, 400));
      await run(tester, 600);
      final left = scrolled(tester).pixels;
      await run(tester, 5000);
      await run(tester, 600);
      expect(scrolled(tester).pixels, left, reason: 'not followed while it is read elsewhere');
      expect(find.text('Follow'), findsOneWidget);
      expect(find.bySemanticsLabel('Follow the tape'), findsOneWidget);

      // Follow: back to the line being heard, and kept there.
      await tester.tap(find.text('Follow'));
      await tester.pump();
      await run(tester, 600);
      expect(find.text('Follow'), findsNothing);
      final now = find.text('Phrase number ${tape.at ~/ 1000} of the meeting, said aloud.');
      expect((tester.getCenter(now).dy - view.center.dy).abs(), lessThan(view.height / 4));
      final following = scrolled(tester).pixels;
      await run(tester, 3000);
      await run(tester, 600);
      expect(scrolled(tester).pixels, greaterThan(following), reason: 'followed again');

      // Scrolled away again, then a line tapped: the tape goes there and is followed from it.
      await tester.drag(find.byType(TranscriptWords), const Offset(0, 300));
      await run(tester, 600);
      expect(find.text('Follow'), findsOneWidget);
      final tapped = tester.widgetList<TranscriptPhrase>(find.byType(TranscriptPhrase)).firstWhere((p) => tester.getCenter(find.byWidget(p)).dy > view.top + 100 && tester.getCenter(find.byWidget(p)).dy < view.bottom - 100);
      await tester.tap(find.byWidget(tapped));
      await tester.pump();
      expect(tape.at, tapped.segment.startMs);
      await run(tester, 600);
      expect(find.text('Follow'), findsNothing);
      await away(tester);
    });

    testWidgets('builds again only the lines whose light moved, over an hour of phrases', (tester) async {
      await probe(tester, makeNote('t', '# Meeting', recordingMs: 3600000, segments: many(3600)));
      final phrasesBuilt = <int>[];
      var built = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        built += 1;
        final widget = element.widget;
        if (widget is TranscriptPhrase) phrasesBuilt.add(widget.segment.startMs ~/ 1000);
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);

      // The first Play: every phrase goes from read to waiting to be heard, once.
      await tape.toggle();
      await tester.pump(const Duration(milliseconds: 50));
      expect(phrasesBuilt.length, 3600);

      // Ticks inside one phrase: nothing of the transcript is built.
      phrasesBuilt.clear();
      built = 0;
      await tester.pump(const Duration(milliseconds: 300));
      expect(tape.at, inInclusiveRange(300, 400));
      expect(phrasesBuilt, isEmpty);
      expect(built, lessThan(20), reason: 'the first line\'s fade finishing, and nothing more; $built built');

      // Into the next phrase: the two whose light moved, and nothing else of the hour.
      phrasesBuilt.clear();
      built = 0;
      await tester.pump(const Duration(milliseconds: 700));
      expect(tape.at ~/ 1000, 1);
      expect(phrasesBuilt..sort(), [0, 1]);
      expect(built, lessThan(80), reason: 'the transcript\'s frame, and two lines with their buttons; $built built');

      // Taken far on: what lies between is now heard, and is built so, once.
      phrasesBuilt.clear();
      tape.seek(1800500);
      await tester.pump();
      expect(phrasesBuilt.toSet().length, phrasesBuilt.length);
      expect(phrasesBuilt.length, 1800);
      await away(tester);
    });
  });

  group('the day a tape was recorded (tapes/tapeDate.ts)', () {
    tearDown(() => toldLocale = null);

    test('is the day and then the month until the phone has said', () {
      expect(tapeDate(_made), '26 Sep');
    });

    test('has the month first on an American phone', () {
      toldLocale = DateLocale.enUS;
      expect(tapeDate(_made), 'Sep 26');
    });

    test('has the day first on a British phone, and Sept', () {
      toldLocale = DateLocale.enGB;
      expect(tapeDate(_made), '26 Sept');
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
      // A meeting Claude writes up: held by Local only, and failed in Claude's words (lib/ai/summary_claude.dart).
      await strip(tester, summary: summary(), queue: const TapeQueue(pending: true, claudeHeld: true));
      expect(said('The summary waits for Claude: Local only is on.'), findsOneWidget);
      await strip(tester, summary: summary(), queue: const TapeQueue(failed: true, failedWhy: 'The API key was refused. Check it in Settings › Claude.'));
      expect(said('The summary didn’t come. The API key was refused. Check it in Settings › Claude.'), findsOneWidget);
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

  // Matt, 2026-10-24: "give the cassettes different colors from the color token palette as well with different
  // opacities on different parts of the cassete to build depth".
  group('the cassette’s colour', () {
    test('is one of the palette’s hues, the same for a note every time, from its id alone', () {
      // FNV-1a of "a" is 0xe40c292c, which is 4 of six: so the hash is the same on a phone, a desktop and the web.
      expect(tapeHue('a'), 'blue');
      expect(tapeHue('mt-standup'), tapeHue('mt-standup'));
      expect([for (var i = 0; i < 60; i += 1) tapeHue('note-$i')], everyElement(isIn(tapeHues)));
    });

    test('differs from note to note, most of the time', () {
      final hues = [for (var i = 0; i < 600; i += 1) tapeHue('n${i * 7919}')];
      for (final hue in tapeHues) {
        expect(hues.where((h) => h == hue).length, inInclusiveRange(60, 140), reason: hue);
      }
      var same = 0;
      for (var i = 1; i < hues.length; i += 1) {
        if (hues[i] == hues[i - 1]) same += 1;
      }
      expect(same, lessThan(hues.length / 4));
    });

    testWidgets('the note’s tape wears its note’s hue', (tester) async {
      tape = tapeOf(makeNote('t', '# Trip', recordingMs: 65000, segments: phrases));
      await pumpApp(tester, home: NoteTape(note: makeNote('t', '# Trip'), title: 'Trip', tape: tape, onRemove: () {}, hasMemos: false));
      expect(tester.widget<TapeArt>(find.byType(TapeArt)).hue, tapeHue('t'));
      await away(tester);
    });

    // Pictures in light and dark, of the tape at the top of a note, every hue, and simple mode's muted ones, written
    // to build/feature-shots/tapes/ to be looked at, not held as goldens.
    for (final theme in ['light', 'dark']) {
      testWidgets('pictures, $theme', (tester) async {
        tape = tapeOf(makeNote('mt-standup', '# Standup', recordingMs: 4 * 60000, segments: phrases));
        tape.seek(95000);
        const titles = ['Standup', 'Sprint retro', 'Quarterly planning with the whole design team', 'Client call', 'Trip', 'Interview'];
        Widget art(int i, {bool muted = false}) =>
            TapeArt(positionMs: 40000 + i * 50000, title: titles[i], titleLines: 2, hue: tapeHues[i], muted: muted);
        Widget pair(Widget a, Widget b) => Row(children: [Expanded(child: a), const SizedBox(width: 16), Expanded(child: b)]);
        await pumpApp(
          tester,
          prefs: AppPreferences(theme: theme),
          home: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                NoteTape(note: makeNote('mt-standup', '# Standup'), title: 'Standup', tape: tape, onRemove: () {}, hasMemos: false),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    children: [
                      for (var i = 0; i < 6; i += 2) ...[pair(art(i), art(i + 1)), const SizedBox(height: 12)],
                      pair(art(0, muted: true), art(3, muted: true)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
        tape.player.dispose();
        await _snap(tester, 'tapes-$theme');
        debugDisableShadows = true;
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });
}

/// The screen as it is, written to build/feature-shots/tapes/[name].png (test/home/meeting_shelf_test.dart `_snap`).
Future<void> _snap(WidgetTester tester, String name) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  final boundary = tester.binding.renderViews.first;
  final bytes = await tester.runAsync(() async {
    final layer = boundary.debugLayer! as OffsetLayer;
    final image = await layer.toImage(boundary.paintBounds);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  File('build/feature-shots/tapes/$name.png')
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!);
}
