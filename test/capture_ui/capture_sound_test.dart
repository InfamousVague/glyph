import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/widgets.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/place.dart';
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/editor/media/clip_refs.dart' show tapeIdOf, withTapeId;

import '../support/render.dart';
import 'support/harness.dart';

/// `src/app/capture/CaptureScreen.test.tsx`, "the sound of a recording", case for case.
///
/// The tape. The stand-in session keeps its sound, as Whisper does on a binary that keeps recordings: `stop` is told
/// which note's id to keep it under and whether to add it to the end of that note's tape, and answers the tape's
/// whole length. What Done stores against the tape - the note's phrases, the better words' job - must be on that
/// timeline.
void main() {
  setUpAll(loadAppFonts);

  final eggs = seg('Eggs.', 0);

  /// A note with thirty seconds of tape already, from an earlier recording.
  void taped(Capture capture) {
    capture.notes.create('groceries', '# Groceries\n\n- Eggs');
    capture.notes.record('groceries', 30000, [eggs]);
  }

  group('the sound of a recording', () {
    testWidgets('hands the better words the time line a journal’s entry goes on from, so they keep its time', (tester) async {
      const entry = '---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n# Monday 28 September\n';
      final capture = Capture(tester)..keeping(4000, 'Walked along the river.');
      capture.notes.create('entry', entry);
      await capture.open(noteId: 'entry', placing: const PlacingEnd(lead: '**14:05** '));
      await capture.until(() => capture.isWhere('Adding to “2026-09-28 14.05”'));
      await capture.say('Walked along the river.', 0);
      await capture.doneAndFinished();
      // The take names its tape in the entry's front matter (lib/editor/media/clip_refs.dart); the words under it are these.
      expect(withTapeId(capture.notes.body('entry')!, null), '$entry\n**14:05** Walked along the river.');
      expect(tapeIdOf(capture.notes.body('entry')!), isNotNull);
      expect(capture.refines, hasLength(1));
      final job = capture.refines.single;
      expect((job.id, job.baseBody, job.placing), ('entry', entry, const PlacingEnd(lead: '**14:05** ')));
      await capture.close();
    });

    testWidgets('goes on the end of a continued note’s tape, and the take’s phrases after the ones it had', (tester) async {
      final capture = Capture(tester)..keeping(33000, 'Oat milk too.');
      taped(capture);
      capture.tapes.setTapeId('groceries', 'earlier');
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say('Oat milk too.', 1000);
      await capture.doneAndFinished();

      expect(capture.stops, [const StopOptions(recordAs: 'groceries', append: true)]);
      final stored = capture.notes.note('groceries')!;
      expect(stored.recordingMs, 33000);
      expect(stored.segments, [eggs, seg('Oat milk too.', 31000)]);
      expect(capture.refines, hasLength(1));
      final job = capture.refines.single;
      expect((job.id, job.fromMs, job.recordingMs, job.baseBody, job.titled), ('groceries', 30000, 33000, '# Groceries\n\n- Eggs', false));
      expect(job.priorSegments, [eggs]);
      expect(job.skip, isEmpty);
      expect(job.keywordAt, isEmpty);
      // The same tape, so the voice memos already in the note play against it still.
      expect(capture.tapes.tapeId('groceries'), 'earlier');
      await capture.close();
    });

    testWidgets('marks a phrase of words and then the keyword for the better words, on the tape’s timeline', (tester) async {
      final capture = Capture(tester)..keeping(33000, null);
      taped(capture);
      capture.notes.create('work', '# Work\n\n- Email Jo');
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say('The heating is fixed, hey Ghost, add call Sam to Work.', 1000);
      await capture.doneAndFinished();

      expect(capture.notes.body('work'), contains('- Call Sam'));
      expect(capture.refines, hasLength(1));
      final job = capture.refines.single;
      expect((job.id, job.fromMs), ('groceries', 30000));
      expect(job.keywordAt, [const Span(startMs: 31000, endMs: 31900)]);
      await capture.close();
    });

    testWidgets('runs no review for a take over three minutes, says why at Done, and asks for its summary only when Settings says so', (tester) async {
      final capture = Capture(tester)
        ..review = true
        ..keeping(200000, null);
      await capture.open();
      await capture.say('A long meeting about the launch.', 1000);
      await capture.done();
      await capture.until(() => capture.says('Long recording. The better words come later.'));
      expect(capture.finished, isEmpty);
      await capture.untilFinished(1, 4000);
      // No review, and the better words from the queue instead.
      expect(capture.finished[0].review, isNull);
      expect(capture.refines, hasLength(1));
      expect(capture.summaries, isEmpty);
      await capture.close();

      capture.prefs = capture.prefs.copyWith(summaries: 'long');
      capture.keeping(200000, null);
      await capture.open();
      await capture.say('A long meeting about the launch.', 1000);
      await capture.done();
      await capture.until(() => capture.says('Long recording. The better words come later. The summary comes later.'));
      await capture.untilFinished(2, 4000);
      expect(capture.summaries, [(capture.finished[1].note!.id, 'recording')]);
      await capture.close();

      // A short take keeps its review, and is never summarized on its own.
      capture.keeping(20000, null);
      await capture.open();
      await capture.say('A short note.', 1000);
      await capture.done();
      await capture.untilFinished(3);
      expect(capture.finished[2].review?.noteId, capture.finished[2].note!.id);
      expect(capture.summaries, hasLength(1));
      await capture.close();
    });

    testWidgets('starts the file afresh on a note whose recording was removed, rather than playing after the removed sound', (tester) async {
      final capture = Capture(tester)..keeping(2000, 'Oat milk too.');
      capture.notes.create('groceries', '# Groceries\n\n- Eggs');
      capture.notes.record('groceries', 0, []);
      capture.tapes.setTapeId('groceries', 'removed');
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say('Oat milk too.', 1000);
      await capture.doneAndFinished();

      expect(capture.stops, [const StopOptions(recordAs: 'groceries', append: false)]);
      expect(capture.notes.note('groceries')?.segments, [seg('Oat milk too.', 1000)]);
      final job = capture.refines[0];
      expect((job.fromMs, job.recordingMs), (0, 2000));
      expect(job.priorSegments, isEmpty);
      // A new tape, so a voice memo left from the removed one does not play against this sound.
      expect(capture.tapes.tapeId('groceries'), isNot('removed'));
      expect(capture.tapes.tapeId('groceries'), isNotNull);
      await capture.close();
    });

    testWidgets('is the new note’s after New note, with what was said before it left out of the better words', (tester) async {
      final capture = Capture(tester)..keeping(4000, 'Call Sam.');
      taped(capture);
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say('For the soup.', 0);
      await capture.tap(capture.topAction);
      await capture.until(() => !capture.isWhere('Adding to “Groceries”'));
      await capture.say('Call Sam.', 3000);
      final done = await capture.doneAndFinished();

      final made = done.note!;
      expect(made.id, isNot('groceries'));
      expect(capture.stops, [StopOptions(recordAs: made.id, append: false)]);
      expect(capture.notes.note(made.id)?.segments, [seg('Call Sam.', 3000)]);
      // The stretch said for the soup went to Groceries as words: the better words over this tape must not write it
      // again.
      final job = capture.refines[0];
      expect((job.id, job.fromMs, job.titled), (made.id, 0, true));
      expect(job.skip, [const Span(startMs: 0, endMs: 900)]);
      // The continued note's own tape is as it was; the words said for it are in it.
      final groceries = capture.notes.note('groceries')!;
      expect((groceries.body, groceries.recordingMs), ('# Groceries\n\n- Eggs\n- For the soup', 30000));
      expect(groceries.segments, [eggs]);
      await capture.close();
    });

    for (final (what, transcript) in const [('nothing was said', null), ('all that was heard is a cue said alone', 'Bullet point.')]) {
      testWidgets('stays counted on a continued note’s tape when $what, so the next take lines up with its sound', (tester) async {
        final capture = Capture(tester)..keeping(33000, transcript);
        taped(capture);
        await capture.open(noteId: 'groceries');
        await capture.until(() => capture.isWhere('Adding to “Groceries”'));
        if (transcript != null) await capture.say(transcript, 1000);
        final done = await capture.doneAndFinished();
        expect(done, (note: null, locked: false, review: null, ask: null, landing: null));

        // The stop put three seconds on the end of the note's file; the note says so, and its words and phrases are
        // as they were.
        final groceries = capture.notes.note('groceries')!;
        expect((groceries.body, groceries.recordingMs), ('# Groceries\n\n- Eggs', 33000));
        expect(groceries.segments, [eggs]);
        expect(capture.backend.discarded, isEmpty);
        expect(capture.refines, isEmpty);
        await capture.close();
      });

      testWidgets('goes when $what into a new recording, with the note that is not made', (tester) async {
        final capture = Capture(tester)..keeping(3000, transcript);
        await capture.open();
        if (transcript != null) await capture.say(transcript, 0);
        final done = await capture.doneAndFinished();
        expect(done, (note: null, locked: false, review: null, ask: null, landing: null));

        final recordedAs = capture.stops.single?.recordAs;
        expect(recordedAs, isA<String>());
        expect(capture.backend.discarded, [recordedAs]);
        expect(capture.notes.all, isEmpty);
        await capture.close();
      });
    }

    /// Speaks `transcript` into Groceries, which has thirty seconds of tape, and presses Done.
    Future<Capture> intoGroceries(WidgetTester tester, String transcript, {void Function(Capture capture)? first}) async {
      final capture = Capture(tester)..keeping(33000, transcript);
      first?.call(capture);
      taped(capture);
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say(transcript, 1000);
      await capture.done();
      return capture;
    }

    testWidgets('stays on a continued note’s tape when what was said into it is an instruction for the AI', (tester) async {
      final capture = await intoGroceries(tester, 'Hey Ghost, fix the spelling.');
      await capture.untilFinished();
      expect(capture.stops, [const StopOptions(recordAs: 'groceries', append: true)]);
      // The file is the whole of Groceries' recording, not the take's: it stays, three seconds longer, words as they
      // were.
      expect(capture.backend.discarded, isEmpty);
      final groceries = capture.notes.note('groceries')!;
      expect((groceries.body, groceries.recordingMs), ('# Groceries\n\n- Eggs', 33000));
      expect(groceries.segments, [eggs]);
      await capture.close();
    });

    // A table for a note there is none of: the one command the live reader leaves alone that the reader at Done
    // refuses (a bare "add to the camping list eggs and milk" is the note's words now, §136).
    testWidgets('stays on a continued note’s tape when what was said into it is a command that is refused', (tester) async {
      final capture = await intoGroceries(tester, 'Hey Ghost, add a table to the camping list.');
      await capture.untilFinished();
      expect(capture.finished.single, (note: null, locked: false, review: null, ask: null, landing: null));
      expect(capture.backend.discarded, isEmpty);
      final groceries = capture.notes.note('groceries')!;
      expect(groceries.recordingMs, 33000);
      expect(groceries.segments, [eggs]);
      await capture.close();
    });

    testWidgets('stays on a continued note’s tape when a command said into it is confirmed onto another note', (tester) async {
      final capture = await intoGroceries(tester, 'add to the note labeled Go pack sunscreen', first: (capture) => capture.notes.create('go', 'Go'));
      await capture.until(() => capture.hasCard('Add to Go'));
      await capture.tap(find.descendant(of: capture.card('Add to Go'), matching: find.byType(AppPill)));
      await capture.untilFinished();
      // Moving the file would have moved the whole of Groceries' tape onto Go.
      expect(capture.backend.reassigned, isEmpty);
      expect(capture.backend.discarded, isEmpty);
      final groceries = capture.notes.note('groceries')!;
      expect(groceries.recordingMs, 33000);
      expect(groceries.segments, [eggs]);
      expect(capture.notes.note('go')?.recordingMs ?? 0, 0);
      await capture.close();
    });

    testWidgets('stays on a continued note’s tape when the command card after Done is cancelled', (tester) async {
      final capture = await intoGroceries(tester, 'add to the note labeled Go pack sunscreen', first: (capture) => capture.notes.create('go', 'Go'));
      await capture.until(() => capture.hasCard('Add to Go'));
      await capture.tap(capture.inCard('Add to Go', 'Cancel'));
      await capture.untilFinished();
      expect(capture.finished.single, (note: null, locked: false, review: null, ask: null, landing: null));
      expect(capture.backend.discarded, isEmpty);
      final groceries = capture.notes.note('groceries')!;
      expect(groceries.recordingMs, 33000);
      expect(groceries.segments, [eggs]);
      await capture.close();
    });

    testWidgets('keeps a phrase taken back out of the tape’s words and marks its stretch for the better words, the sound kept', (tester) async {
      final capture = Capture(tester)..keeping(36000, null);
      taped(capture);
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say('For the soup.', 1000);
      await capture.say('Oat milk too.', 2500);
      await capture.say('Scratch that.', 4000);
      await capture.doneAndFinished();

      final stored = capture.notes.note('groceries')!;
      expect(withTapeId(stored.body, null), '# Groceries\n\n- Eggs\n- For the soup');
      expect(tapeIdOf(stored.body), isNotNull, reason: 'the tape named in the note (lib/editor/media/clip_refs.dart)');
      expect(stored.recordingMs, 36000);
      expect(stored.segments, [eggs, seg('For the soup.', 31000)]);
      expect(capture.refines, hasLength(1));
      final job = capture.refines.single;
      expect((job.id, job.fromMs), ('groceries', 30000));
      // The phrase that went, and the take-back itself: replaced by the live phrases inside them, which is none.
      expect(job.skip, [const Span(startMs: 32500, endMs: 33400), const Span(startMs: 34000, endMs: 34900)]);
      expect(job.live, [seg('For the soup.', 31000)]);
      await capture.close();
    });

    testWidgets('reads a take-back only the stop heard, and names it in the note’s toast', (tester) async {
      final capture = Capture(tester)..keeping(4000, "Hey Ghost, add a note to house to do's. Call Sam. Buy fuses. Scratch that.");
      capture.notes.create('house', '# House TODOs\n\n- [ ] Fix the gutter\n');
      await capture.open();
      await capture.say("Hey Ghost, add a note to house to do's.", 0);
      await capture.say('Call Sam.', 1000);
      await capture.say('Buy fuses.', 2000);
      final done = await capture.doneAndFinished();
      expect(withTapeId(capture.notes.body('house')!, null), '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
      expect(tapeIdOf(capture.notes.body('house')!), isNotNull);
      expect(done.note?.id, 'house');
      expect(done.note?.segments, [seg('Call Sam.', 1000)]);
      final landing = done.landing!;
      expect(landing.noteId, 'house');
      expect(landing.blocks, ['- [ ] Call Sam']);
      expect(landing.tookBack, ['Buy fuses']);
      await capture.close();
    });

    testWidgets('moves a new recording’s sound to the note a confirmed command went to, as before', (tester) async {
      final capture = Capture(tester)..keeping(3000, 'add to the note labeled Go pack sunscreen');
      capture.notes.create('go', 'Go');
      await capture.open();
      await capture.say('add to the note labeled Go pack sunscreen', 0);
      await capture.done();
      await capture.until(() => capture.hasCard('Add to Go'));
      await capture.tap(find.descendant(of: capture.card('Add to Go'), matching: find.byType(AppPill)));
      await capture.untilFinished();
      final recordedAs = capture.stops.single!.recordAs!;
      expect(capture.backend.reassigned, [(recordedAs, 'go', false)]);
      expect(capture.notes.note('go')?.recordingMs, 3000);
      await capture.close();
    });
  });
}
