import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/app/widgets.dart';
import 'package:ghost_md/capture/place.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/capture/ui/capture_screen.dart';

import '../support/render.dart';
import 'support/harness.dart';

/// `src/app/capture/CaptureScreen.test.tsx`, case for case, its first six groups: the stop's own transcript, the
/// card after Done, the card of things to say, a note's own Speak, ending a recording, and the recorder's own lines.
/// The tape's cases are in `capture_sound_test.dart`, the live reader's in `capture_live_test.dart`, a meeting's in
/// `capture_meeting_test.dart`.
///
/// What a case finds by role and name on the web it finds here by what is drawn: the line at the top by its words
/// under [CaptureScreen.whereKey], a card by its heading, Done and Discard by their keys.
void main() {
  setUpAll(loadAppFonts);

  group('native stop transcript handoff', () {
    testWidgets('offers the full stop-time append to Go and never creates a note from a truncated phrase event', (tester) async {
      final capture = Capture(tester);
      capture.notes.create('go', 'Go');
      await capture.open();
      // The terminal words never arrive as a committed event.
      await capture.say('add to the note labeled Go pack', 0);
      await capture.done();

      // The full stop result, not the take's event-only segments, reaches the classifier. A confirmation is offered
      // before any mutation happens.
      await capture.until(() => capture.hasCard('Add to Go'));
      expect(capture.notes.bodies, ['Go']);

      await capture.tap(capture.inCard('Add to Go', 'Add'));
      await capture.untilFinished();
      expect(capture.finished, hasLength(1));
      expect(capture.notes.all, hasLength(1));
      expect(capture.notes.bodies.single, startsWith('Go'));
      expect(capture.notes.bodies.single, contains('Pack sunscreen'));
      expect(capture.notes.bodies.single.toLowerCase(), isNot(contains('add to the note labeled')));
      await capture.close();
    });

    testWidgets('keeps a native-only terminal suffix when the stopped recording is an ordinary note', (tester) async {
      final capture = Capture(tester)..stopSays('Weekend plans include packing sunscreen');
      await capture.open();
      await capture.say('Weekend plans include packing', 0);
      await capture.doneAndFinished();
      expect(capture.notes.all, hasLength(1));
      expect(capture.notes.bodies.single, contains('sunscreen'));
      await capture.close();
    });
  });

  group('the card after Done', () {
    testWidgets('waits for its tap however long it is up, so the finished take can still be answered', (tester) async {
      final capture = Capture(tester);
      capture.notes.create('go', 'Go');
      var ticks = 0;
      capture.positionMs = () {
        ticks += 1;
        return 2600;
      };
      await capture.open();
      await capture.done();
      await capture.until(() => capture.hasCard('Add to Go'));

      // A minute on, well past the twenty seconds a spoken question was once given, and ticked through.
      final before = ticks;
      await tester.pump(const Duration(seconds: 60));
      await capture.until(() => ticks > before + 1);
      expect(capture.hasCard('Add to Go'), isTrue);
      await capture.tap(capture.inCard('Add to Go', 'Cancel'));
      await capture.untilFinished();
      expect(capture.finished.single, (note: null, locked: false, review: null, ask: null, landing: null));
      expect(capture.notes.bodies, ['Go']);
      await capture.close();
    });

    testWidgets('takes Discard as its Cancel, rather than leaving the finished take with no way out', (tester) async {
      final capture = Capture(tester);
      capture.notes.create('go', 'Go');
      await capture.open();
      await capture.done();
      await capture.until(() => capture.hasCard('Add to Go'));
      // The microphone is off by now: the card no longer says a spoken yes or no will do.
      expect(capture.textOf(capture.card('Add to Go')), isNot(contains('say “yes”')));
      await capture.discard();
      await capture.untilFinished();
      expect(capture.finished.single, (note: null, locked: false, review: null, ask: null, landing: null));
      expect(capture.notes.bodies, ['Go']);
      await capture.close();
    });

    testWidgets('opens the note a confirmed card wrote to, with the lines it put in', (tester) async {
      final capture = Capture(tester);
      capture.notes.create('go', 'Go');
      await capture.open();
      await capture.done();
      await capture.until(() => capture.hasCard('Add to Go'));
      await capture.tap(find.descendant(of: capture.card('Add to Go'), matching: find.byType(AppPill)));
      await capture.untilFinished();
      final done = capture.finished.single;
      expect(done.note?.id, 'go');
      expect(done.note?.body, contains('Pack sunscreen'));
      final landing = done.landing!;
      expect((landing.noteId, landing.title), ('go', 'Go'));
      expect(landing.made, isEmpty);
      expect(landing.blocks, [contains('Pack sunscreen')]);
      await capture.close();
    });

    testWidgets('keeps each place the card showed as one item when it is confirmed', (tester) async {
      final capture = Capture(tester)..stopSays('Add to my note labeled Go a list with Parkersburg West Virginia and Marietta Ohio.');
      capture.notes.create('go', '# Go\n');
      await capture.open();
      await capture.done();
      await capture.until(() => capture.hasCard('Add to Go'));
      await capture.tap(capture.inCard('Add to Go', 'Add'));
      await capture.untilFinished();
      expect(capture.notes.body('go'), '# Go\n\n- Parkersburg, West Virginia\n- Marietta, Ohio\n');
      await capture.close();
    });

    testWidgets('makes the new list a confirmed card offered, with its items, and opens it', (tester) async {
      final capture = Capture(tester)..stopSays('Make a new list called comic books with Batman and Superman.');
      await capture.open();
      await capture.done();
      await capture.until(() => capture.hasCard('Create Comic Books'));
      expect(capture.notes.all, isEmpty);
      await capture.tap(capture.inCard('Create Comic Books', 'Create'));
      await capture.untilFinished();
      expect(capture.notes.bodies, ['Comic Books\n\n- Batman\n- Superman\n']);
      final id = capture.notes.all.single.id;
      final done = capture.finished.single;
      expect(done.note?.id, id);
      expect(done.locked, isFalse);
      final landing = done.landing!;
      expect((landing.noteId, landing.title), (id, 'Comic Books'));
      expect(landing.blocks, isEmpty);
      expect(landing.made, [id]);
      await capture.close();
    });
  });

  group('things to say', () {
    testWidgets('shows the card until the first words, naming one of their notes and no ask on a new recording, then tips one at a time', (tester) async {
      final capture = Capture(tester);
      capture.notes.create('groceries', 'Groceries');
      await capture.open();
      await capture.until(() => capture.hasSayCard);
      // The command said bare: no "Hey Ghost" before it.
      await capture.until(() => capture.textOf(capture.sayCard).contains('Add … to Groceries'));
      final card = capture.textOf(capture.sayCard);
      expect(card, isNot(contains('Hey Ghost')));
      expect(card, contains('Bullet point'));
      // A new recording is not a note yet: an ask said into it would not run, so none is offered.
      expect(card, isNot(contains('Fix the spelling')));
      await capture.say('Milk and eggs', 0);
      await capture.until(() => !capture.hasSayCard);
      await capture.close();
    });

    testWidgets('offers the asks on a note’s own Speak, and never names that note as somewhere to send the take', (tester) async {
      final capture = Capture(tester);
      capture.notes.create('groceries', 'Groceries');
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.hasSayCard);
      await capture.until(() => capture.textOf(capture.sayCard).contains('Fix the spelling'));
      final card = capture.textOf(capture.sayCard);
      expect(card, isNot(contains('to Groceries')));
      expect(card, contains('Make a list called'));
      await capture.close();
    });
  });

  group('a note’s own Speak', () {
    testWidgets('says where the words are going, and writes them under the note’s own text at Done', (tester) async {
      final capture = Capture(tester)..stopSays('Oat milk too.');
      capture.notes.create('daily', '# Daily Life\n\n- Walked');
      await capture.open(noteId: 'daily');
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Oat milk too.', 0);
      final done = await capture.doneAndFinished();
      expect((done.note?.id, done.note?.body), ('daily', '# Daily Life\n\n- Walked\n\nOat milk too.'));
      expect(capture.notes.bodies, ['# Daily Life\n\n- Walked\n\nOat milk too.']);
      await capture.close();
    });

    testWidgets('goes where its opener says rather than where the title would send it: a journal entry’s time line', (tester) async {
      const entry = '---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n# Monday 28 September\n';
      final capture = Capture(tester)..stopSays('Walked along the river.');
      capture.notes.create('entry', entry);
      await capture.open(noteId: 'entry', placing: const PlacingEnd(lead: '**14:05** '));
      await capture.until(() => capture.isWhere('Adding to “2026-09-28 14.05”'));
      await capture.say('Walked along the river.', 0);
      await capture.doneAndFinished();
      expect(capture.notes.body('entry'), '$entry\n**14:05** Walked along the river.');
      await capture.close();
    });

    // Changed on purpose (docs/DESIGN.md §126): a note whose title says it is a list takes what is said as its items.
    testWidgets('writes into the list of a note whose title says it is one', (tester) async {
      final capture = Capture(tester)..stopSays('Oat milk too.');
      capture.notes.create('groceries', '# Groceries\n\n- Eggs');
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say('Oat milk too.', 0);
      await capture.doneAndFinished();
      expect(capture.notes.bodies, ['# Groceries\n\n- Eggs\n- Oat milk too']);
      await capture.close();
    });

    testWidgets('opens the note with the run on it when what was said is an ask about the note', (tester) async {
      final capture = Capture(tester)..stopSays('Hey Ghost, fix the spelling.');
      capture.notes.create('groceries', '# Groceries\n\n- Eggs');
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say('Hey Ghost, fix the spelling.', 0);
      final done = await capture.doneAndFinished();
      expect((done.locked, done.review, done.ask, done.landing), (false, null, const SpokenAsk(kind: 'fix'), null));
      expect(done.note?.id, 'groceries');
      expect(capture.notes.bodies, ['# Groceries\n\n- Eggs']);
      await capture.close();
    });

    // Without the keyword a run is the whole phrase and nothing more (docs/DESIGN.md §136): a sentence that opens
    // with one is the note's words, where it let the recording go and rewrote the note.
    testWidgets('appends a sentence that opens with a run’s words, said without the keyword, and runs nothing', (tester) async {
      final capture = Capture(tester)..stopSays(null);
      capture.notes.create('daily', '# Daily Life\n\nWent for a walk.');
      await capture.open(noteId: 'daily');
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Fix the spelling of Kowalski on the sign.', 0);
      final done = await capture.doneAndFinished();
      expect(done.ask, isNull);
      expect(capture.notes.body('daily'), '# Daily Life\n\nWent for a walk.\n\nFix the spelling of Kowalski on the sign.');
      await capture.close();
    });

    // What the live reader's gate kept as words is words at Done too (docs/DESIGN.md §136): no card offers to send
    // them to a note called Work, whose Cancel would let the recording go.
    testWidgets('appends a sentence the live reader kept as words, said without the keyword, and offers no card at Done', (tester) async {
      final capture = Capture(tester)..stopSays(null);
      capture.notes.create('daily', '# Daily Life\n\nWent for a walk.');
      capture.notes.create('work', '# Work\n\nNotes.');
      await capture.open(noteId: 'daily');
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Add call the plumber to work.', 0);
      await capture.doneAndFinished();
      expect(capture.hasCard('Add to Work'), isFalse);
      expect(capture.notes.body('daily'), '# Daily Life\n\nWent for a walk.\n\nAdd call the plumber to work.');
      expect(capture.notes.body('work'), '# Work\n\nNotes.');
      await capture.close();
    });

    // Changed on purpose (docs/DESIGN.md §126): nothing is stored mid-take, so what was said before New note is
    // written at Done with the rest, and Discard would take it back too.
    testWidgets('carries on in a new note from New note, leaving what was said so far where it was said', (tester) async {
      final capture = Capture(tester)..stopSays('For the soup. Call Sam.');
      capture.notes.create('groceries', '# Groceries\n\n- Eggs');
      await capture.open(noteId: 'groceries');
      await capture.until(() => capture.isWhere('Adding to “Groceries”'));
      await capture.say('For the soup.', 0);
      await capture.tap(capture.topAction);
      await capture.until(() => !capture.isWhere('Adding to “Groceries”'));
      expect(capture.notes.body('groceries'), '# Groceries\n\n- Eggs');
      await capture.say('Call Sam.', 3000);
      await capture.doneAndFinished();
      expect(capture.notes.bodies..sort(), ['# Call Sam', '# Groceries\n\n- Eggs\n- For the soup']);
      await capture.close();
    });
  });

  group('ending a recording', () {
    testWidgets('leaves nothing behind on Discard', (tester) async {
      final capture = Capture(tester);
      await capture.open();
      await capture.say('Pick up the parcel.', 0);
      await capture.discard();
      await capture.untilFinished();
      expect(capture.finished.single, (note: null, locked: false, review: null, ask: null, landing: null));
      expect(capture.cancels, 1);
      expect(capture.notes.all, isEmpty);
      await capture.close();
    });

    testWidgets('lays out a switched-on plugin’s formatting when it is said, as bold is', (tester) async {
      final capture = Capture(tester)..stopSays('The gate code is spoiler four four one seven end spoiler.');
      await capture.open();
      await capture.say('The gate code is spoiler four four one seven end spoiler.', 0);
      await capture.doneAndFinished();
      expect(capture.notes.bodies, [contains('||four four one seven||')]);
      await capture.close();
    });

    testWidgets('leaves nothing behind on Done when nothing was said', (tester) async {
      final capture = Capture(tester)..stopSays(null);
      await capture.open();
      final done = await capture.doneAndFinished();
      expect(done, (note: null, locked: false, review: null, ask: null, landing: null));
      expect(capture.notes.all, isEmpty);
      await capture.close();
    });

    testWidgets('leaves nothing behind when all that was heard is a cue said alone, as Whisper echoing its prompt makes', (tester) async {
      final capture = Capture(tester)..stopSays('Bullet point.');
      await capture.open();
      await capture.say('Bullet point.', 0);
      final done = await capture.doneAndFinished();
      expect(done, (note: null, locked: false, review: null, ask: null, landing: null));
      expect(capture.notes.all, isEmpty);
      await capture.close();
    });

    testWidgets('saves an ask a new recording cannot carry out as a note of its words, without the keyword, and says why', (tester) async {
      final capture = Capture(tester)..stopSays(null);
      await capture.open();
      await capture.say('Hey Ghost, make a book called trips.', 0);
      await capture.doneAndFinished();
      expect(capture.notes.bodies, ['# Make a book called trips']);
      expect(capture.says("isn't something a recording can do, so the words are saved as a note"), isTrue);
      await capture.close();
    });

    // Changed on purpose (docs/DESIGN.md §136): a person who did not say the keyword did not say it was a command,
    // so the words are saved as the note, the reason set on the recorder's line, where nothing was saved.
    testWidgets('saves a bare command that names no note as its words, with the reason', (tester) async {
      final capture = Capture(tester)..stopSays('Add to shopping, oat milk.');
      capture.notes.create('work', 'Work');
      await capture.open();
      await capture.say('Add to shopping, oat milk.', 0);
      final done = await capture.doneAndFinished();
      expect(done.note?.body, '# Add to shopping, oat milk');
      expect(capture.notes.bodies..sort(), ['# Add to shopping, oat milk', 'Work']);
      expect(capture.says('No note called “shopping”, so the words are saved as a note.'), isTrue);
      await capture.close();
    });

    // A sentence the live reader's gate kept as words opens a fresh recording: at Done it is the note, never a card
    // for a note called Bowl whose Cancel would let the recording go (docs/DESIGN.md §136).
    testWidgets('saves a fresh recording that opens with a sentence the gate kept as words, with no card', (tester) async {
      final capture = Capture(tester)..stopSays('Add the flour to the bowl. Then stir it for a minute.');
      capture.notes.create('bowl', '# Bowl\n\nBlue.');
      await capture.open();
      await capture.say('Add the flour to the bowl.', 0);
      await capture.say('Then stir it for a minute.', 1000);
      await capture.doneAndFinished();
      expect(capture.hasCard('Add to Bowl'), isFalse);
      expect(capture.notes.body('bowl'), '# Bowl\n\nBlue.');
      expect(capture.notes.bodies..sort(), ['# Add the flour to the bowl\n\nThen stir it for a minute.', '# Bowl\n\nBlue.']);
      await capture.close();
    });

    // After the keyword it was said to be a command: the live reader keeps its words here with its own chip.
    testWidgets('keeps a keyworded command that names no note as its words, with the live reader’s chip', (tester) async {
      final capture = Capture(tester)..stopSays('Hey Ghost, add to shopping, oat milk.');
      capture.notes.create('work', 'Work');
      await capture.open();
      await capture.say('Hey Ghost, add to shopping, oat milk.', 0);
      await capture.doneAndFinished();
      expect(capture.notes.bodies..sort(), ['# Oat milk', 'Work']);
      expect(capture.says('No note called “shopping”, so the words stay here.'), isTrue);
      await capture.close();
    });
  });

  group('the recorder’s own lines', () {
    testWidgets('says nothing was recorded, and why, when it could not start', (tester) async {
      final capture = Capture(tester)..configured = false;
      await capture.open(wait: false);
      await capture.until(() => capture.says('Nothing was recorded.'));
      expect(capture.screenText, contains('test capture session was not configured'));
      expect(tester.widget<AppPill>(find.byKey(CaptureScreen.doneKey)).onPressed, isNull);
      await capture.close();
    });

    testWidgets('shows what the pipeline has done when the top line is tapped', (tester) async {
      final capture = Capture(tester);
      await capture.open();
      await capture.say('Hello.', 0);
      await capture.tap(capture.where('New note'));
      await capture.until(() => capture.says('On-device Whisper · heard 0.0 s · 0 guesses · 1 phrase'));
      await capture.close();
    });
  });
}
