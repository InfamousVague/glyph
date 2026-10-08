import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/engine.dart';
import 'package:ghost_md/capture/place.dart';
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/capture/take_types.dart';
import 'package:ghost_md/capture/ui/capture_cards.dart';
import 'package:ghost_md/core/book.dart' show bookNoteBody;
import 'package:ghost_md/core/canvas_body.dart' show isCanvasBody;
import 'package:ghost_md/core/note.dart';

import '../support/render.dart';
import 'support/harness.dart';

/// `src/app/capture/CaptureScreen.test.tsx`, "adding to a note as it is said", case for case.
///
/// Matt: "add a note to house to do's, the note is call an electrician to fix the light sockets" made a new note.
/// The recorder must find House TODOs, switch to it, write the to-do into its list as it is said, store nothing
/// before Done, write it once at Done with no second card, and hand House TODOs back to be opened.
void main() {
  setUpAll(loadAppFonts);

  const house = '# House TODOs\n\n- [ ] Fix the gutter\n';
  const called = '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n';
  const nothing = (note: null, locked: false, review: null, ask: null, landing: null);

  /// A recorder open, whose stop answers no transcript (the group's `beforeEach`).
  Future<Capture> recording(WidgetTester tester, {String? noteId, Placing? placing, void Function(Capture capture)? first}) async {
    final capture = Capture(tester)..stopSays(null);
    first?.call(capture);
    await capture.open(noteId: noteId, placing: placing);
    return capture;
  }

  /// The card asking which note, whatever its heading says after these words.
  bool choiceStarting(Capture capture, String words) =>
      find.byWidgetPredicate((widget) => widget is NoteChoiceCard<Note> && widget.card.heading.startsWith(words)).evaluate().isNotEmpty;

  group('adding to a note as it is said', () {
    testWidgets('switches to House TODOs, writes the to-do into its list as it is said, and opens it at Done', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('house', house);
        capture.notes.create('daily', '# Daily Life\n\nWent for a walk.');
      });
      await capture.say("Hey Ghost, add a note to house to do's.", 0);
      await capture.until(() => capture.isWhere('Adding to “House TODOs”'));
      expect(capture.screenText, contains('Say the note for House TODOs'));
      // What is being said for it shows in the chip, not on the page, until it is committed.
      await capture.partial('The note is call');
      expect(capture.screenText, contains('House TODOs: The note is call'));
      expect(capture.page(), isNot(contains('The note is call')));
      await capture.say('The note is call an electrician to fix the light sockets.', 1500);
      await capture.until(() => capture.page().contains('Call an electrician to fix the light sockets'));
      expect(capture.page(), isNot(contains('The note is')));
      // Drawn into the list, the line under the gutter, not on the note's end.
      final lines = capture.page().split('\n');
      final gutter = lines.indexWhere((line) => line.contains('Fix the gutter'));
      expect(lines[gutter + 1], contains('Call an electrician to fix the light sockets'));
      // Nothing is stored before Done.
      expect(capture.notes.body('house'), house);
      expect(capture.notes.all, hasLength(2));

      final done = await capture.doneAndFinished();
      expect(capture.anyCard, isFalse);
      expect(capture.notes.body('house'), called);
      expect(capture.notes.all, hasLength(2));
      expect((done.note?.id, done.note?.body), ('house', called));
      expect((done.locked, done.review, done.ask), (false, null, null));
      final landing = done.landing!;
      expect((landing.noteId, landing.title), ('house', 'House TODOs'));
      expect(landing.blocks, ['- [ ] Call an electrician to fix the light sockets']);
      expect(landing.others, isEmpty);
      expect(landing.made, isEmpty);
      await capture.close();
    });

    for (final said in const [
      'Hey Ghost, add a note to house chores, the note is call an electrician to fix the light sockets.',
      "Hey, like, add a note to house to do's, the note is call an electrician to fix the light sockets.",
      'Hey goes add a note to house to-dos. Call an electrician to fix the light sockets.',
    ]) {
      testWidgets('does the same said in one phrase: $said', (tester) async {
        final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
        await capture.say(said, 0);
        await capture.until(() => capture.isWhere('Adding to “House TODOs”'));
        await capture.doneAndFinished();
        expect(capture.notes.bodies, [called]);
        await capture.close();
      });
    }

    testWidgets('writes a phrase committed in the same moment as the switch into the note switched to', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.sayTogether([seg("Hey Ghost, add a note to house to do's.", 0), seg('Call Sam.', 1000)]);
      await capture.doneAndFinished();
      expect(capture.notes.bodies, ['# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n']);
      await capture.close();
    });

    testWidgets('keeps the item when the side key ends the recording straight after the command', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say('Hey Ghost, add call Sam to House TODOs.', 0);
      capture.screenOff!();
      await capture.untilFinished();
      expect(capture.notes.body('house'), '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
      await capture.close();
    });

    testWidgets('keeps the last words only the stop heard, and routes a command only the stop heard, with no card', (tester) async {
      final first = await recording(tester, first: (capture) => capture.notes.create('house', house));
      first.stopSays("Hey Ghost, add a note to house to do's. Call an electrician to fix the light sockets.");
      await first.say("Hey Ghost, add a note to house to do's.", 0);
      await first.say('Call an electrician to fix the light', 1500);
      await first.doneAndFinished();
      expect(first.notes.body('house'), called);
      await first.close();

      final second = Capture(tester)..keeping(3000, 'Hey Ghost, add call Sam to house to-dos.');
      second.notes.create('house', house);
      await second.open();
      final done = await second.doneAndFinished();
      expect(second.anyCard, isFalse);
      expect(second.notes.bodies, ['# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n']);
      final recordedAs = second.stops.single!.recordAs!;
      expect(second.backend.reassigned, [(recordedAs, 'house', false)]);
      expect(done.note?.id, 'house');
      await second.close();
    });

    testWidgets('sends a one-shot mid-take and carries on in the take’s own note', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say('Kevin owns the release.', 0);
      await capture.say('Hey Ghost, add call the electrician to House TODOs.', 1000);
      await capture.say('Next, the budget review is Friday.', 2000);
      expect(capture.isWhere('New note'), isTrue);
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('house'), '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call the electrician\n');
      expect(done.note?.body, '# Kevin owns the release\n\nNext, the budget review is Friday.');
      expect(done.landing?.noteId, done.note?.id);
      expect(done.landing?.others, hasLength(1));
      await capture.close();
    });

    testWidgets('sends a one-shot from a note’s own Speak, keeping both sentences there, and opens that note', (tester) async {
      final capture = await recording(tester, noteId: 'daily', first: (capture) {
        capture.notes.create('house', house);
        capture.notes.create('daily', '# Daily Life\n\nWent for a walk.');
      });
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Went for a run.', 0);
      await capture.say('Hey Ghost, add call Sam to House TODOs.', 1000);
      await capture.say('Then I made lunch.', 2000);
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('daily'), '# Daily Life\n\nWent for a walk.\n\nWent for a run. Then I made lunch.');
      expect(capture.notes.body('house'), contains('- [ ] Call Sam\n'));
      expect(done.note?.id, 'daily');
      await capture.close();
    });

    testWidgets('asks which note on a card, takes the words said after it as words, and moves them on a tap', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('s1', '# Signing in, and signing');
        capture.notes.create('s2', '# Signing the order');
      });
      await capture.say('Hey Ghost, add a note to signing.', 0);
      await capture.say('Check the form.', 1000);
      await capture.until(() => capture.hasCard('Add to which note?'));
      await capture.tap(capture.inCard('Add to which note?', 'Signing the order'));
      await capture.until(() => capture.isWhere('Adding to “Signing the order”'));
      await capture.doneAndFinished();
      expect(capture.notes.body('s2'), '# Signing the order\n\nCheck the form.');
      expect(capture.notes.all, hasLength(2));
      await capture.close();
    });

    testWidgets('keeps the words here when Done comes with the card still up', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('s1', '# Signing in, and signing');
        capture.notes.create('s2', '# Signing the order');
      });
      await capture.say('Hey Ghost, add call Sam to signing.', 0);
      await capture.until(() => capture.hasCard('Add to which note?'));
      await capture.doneAndFinished();
      expect(capture.notes.bodies..sort(), ['# Call Sam', '# Signing in, and signing', '# Signing the order']);
      await capture.close();
    });

    testWidgets('keeps words for a note there is none of here, and makes a named one from a card at Done', (tester) async {
      final first = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await first.say('Hey Ghost, add eggs to the moon base.', 0);
      await first.until(() => first.says('No note called “moon base”, so the words stay here.'));
      await first.doneAndFinished();
      expect(first.notes.bodies..sort(), ['# Eggs', house]);
      await first.close();

      final second = await recording(tester);
      await second.say('Hey Ghost, add a note to the moon base.', 0);
      await second.until(() => second.hasCard('No note called “moon base”'));
      await second.tap(second.inCard('No note called “moon base”', 'New note “Moon base”'));
      await second.say('Call Sam.', 1000);
      expect(second.notes.all, isEmpty);
      await second.doneAndFinished();
      expect(second.notes.bodies, ['Moon base\n\nCall Sam.']);
      await second.close();
    });

    testWidgets('stores nothing on Not this note, and Done makes the take a note of its own', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      await capture.until(() => capture.hasTopAction('Not this note'));
      await capture.tap(capture.topAction);
      await capture.until(() => capture.isWhere('New note'));
      expect(capture.notes.body('house'), house);
      await capture.doneAndFinished();
      expect(capture.notes.body('house'), house);
      expect(capture.notes.bodies..sort(), ['# Call Sam', house]);
      await capture.close();
    });

    testWidgets('stores nothing on Discard after a switch', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      await capture.until(() => capture.isWhere('Adding to “House TODOs”'));
      await capture.discard();
      await capture.untilFinished();
      expect(capture.finished.single, nothing);
      expect(capture.notes.bodies, [house]);
      await capture.close();
    });

    testWidgets('puts the item under the heading it fits, and says so', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('jobs', '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n'));
      await capture.say('Hey Ghost, add a note to home jobs, call an electrician.', 0);
      await capture.until(() => capture.says('under Electrical'));
      await capture.doneAndFinished();
      expect(capture.notes.body('jobs'), '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call an electrician\n');
      await capture.close();
    });

    testWidgets('writes onto the note as it is at Done when it changed while the take was said', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      final now = capture.notes.note('house')!;
      await capture.notes.updateNote('house', '$house- [ ] Clear the drains\n', now.revision);
      await capture.doneAndFinished();
      expect(capture.notes.body('house'), '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Clear the drains\n- [ ] Call Sam\n');
      await capture.close();
    });

    testWidgets('over the lock screen, names no note, raises no card, and shows none of the note', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.locked = true;
        capture.notes.create('house', house);
        capture.notes.create('s1', '# Signing in, and signing');
        capture.notes.create('s2', '# Signing the order');
      });
      await capture.say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      await capture.until(() => capture.isWhere('Adding to the note you named'));
      expect(capture.page(), isNot(contains('Fix the gutter')));
      await capture.say('Hey Ghost, add call Jo to signing.', 1000);
      expect(capture.hasCard('Add to which note?'), isFalse);
      await capture.doneAndFinished();
      expect(capture.notes.body('house'), contains('- [ ] Call Sam\n'));
      await capture.close();
    });

    testWidgets('queues an ask said mid-take on a note’s own Speak, and leaves one out of a switched take', (tester) async {
      final capture = await recording(tester, noteId: 'daily', first: (capture) => capture.notes.create('daily', '# Daily Life\n\nWent for a walk.'));
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Went for a run.', 0);
      await capture.say('Hey Ghost, fix the spelling.', 1000);
      final own = await capture.doneAndFinished();
      expect(own.ask, const SpokenAsk(kind: 'fix'));
      expect(capture.notes.body('daily'), '# Daily Life\n\nWent for a walk.\n\nWent for a run.');
      await capture.close();

      capture.notes.create('house', house);
      await capture.open();
      await capture.say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      await capture.say('Hey Ghost, fix the spelling.', 1000);
      await capture.until(() => capture.says("That can't run in the middle of a recording, so it was left out."));
      final routed = await capture.doneAndFinished();
      expect(routed.ask, isNull);
      expect(capture.notes.body('house'), '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
      await capture.close();
    });

    testWidgets('keeps the sound with the note switched to, on its tape, and hands the better words where the words went', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('house', house);
        capture.keeping(4000, null);
      });
      await capture.say("Hey Ghost, add a note to house to do's.", 0);
      await capture.say('Call Sam.', 1500);
      await capture.doneAndFinished();
      expect(capture.stops, [const StopOptions(recordAs: 'house', append: false)]);
      expect(capture.backend.reassigned, isEmpty);
      final stored = capture.notes.note('house')!;
      expect(stored.recordingMs, 4000);
      expect(stored.segments, [seg('Call Sam.', 1500)]);
      expect(capture.refines, hasLength(1));
      final job = capture.refines.single;
      expect((job.id, job.baseBody, job.savedBody, job.titled), ('house', house, '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n', false));
      // The command, and the phrase its words were read from: the better words put the live words there.
      expect(job.skip, [const Span(startMs: 0, endMs: 900), const Span(startMs: 1500, endMs: 2400)]);
      expect(job.placing, isA<PlacingLists>().having((placing) => placing.task, 'task', true));
      expect(job.live, [seg('Call Sam.', 1500)]);
      await capture.close();
    });

    testWidgets('never names a canvas, and keeps words for a book here', (tester) async {
      const canvas = '---\ntitle: "House plans"\n---\n{"nodes":[],"edges":[]}';
      expect(isCanvasBody(canvas), isTrue);
      final book = bookNoteBody('Field guide', ['Trees']);
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('canvas', canvas);
        capture.notes.create('book', book);
      });
      await capture.say('Hey Ghost, add Rivers to the field guide.', 0);
      await capture.until(() => capture.says('“Field guide” is a notebook, so the words stay here.'));
      await capture.say('Hey Ghost, add call Sam to house plans.', 1000);
      await capture.doneAndFinished();
      expect(capture.notes.body('canvas'), canvas);
      expect(capture.notes.body('book'), book);
      await capture.close();
    });

    testWidgets('runs no review for a take written into a note that was there, and does for a new one', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.review = true;
        capture.notes.create('house', house);
      });
      await capture.say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      await capture.until(() => capture.isWhere('Adding to “House TODOs”'));
      final routed = await capture.doneAndFinished();
      expect(routed.note?.id, 'house');
      expect(routed.review, isNull);
      await capture.close();

      await capture.open();
      await capture.say('Buy milk.', 0);
      final fresh = await capture.doneAndFinished();
      expect(fresh.review?.noteId, fresh.note!.id);
      await capture.close();
    });

    testWidgets('keeps words in the order they were said when a card settles after later ones', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('s1', '# Signing in, and signing');
        capture.notes.create('s2', '# Signing the order');
      });
      await capture.say('Kevin owns the release.', 0);
      await capture.say('Hey Ghost, add call Jo to signing.', 1000);
      await capture.until(() => capture.hasCard('Add to which note?'));
      await capture.say('The budget review is Friday.', 2000);
      final done = await capture.doneAndFinished();
      expect(done.note?.body, '# Kevin owns the release\n\nCall Jo. The budget review is Friday.');
      await capture.close();
    });

    testWidgets('sends the words said since a card mid-take to the note chosen on it, out of the take', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('s1', '# Signing in, and signing');
        capture.notes.create('s2', '# Signing the order');
      });
      await capture.say('Kevin owns the release.', 0);
      await capture.say('Hey Ghost, add a note to signing;', 1000);
      await capture.until(() => capture.hasCard('Add to which note?'));
      await capture.say('Check the form.', 2000);
      await capture.tap(capture.inCard('Add to which note?', 'Signing the order'));
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('s2'), '# Signing the order\n\nCheck the form.');
      expect(done.note?.body, '# Kevin owns the release');
      await capture.close();
    });

    testWidgets('goes back to a journal entry’s time line on Not this note, after the take was moved to another note', (tester) async {
      const entry = '---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n# Monday 28 September\n';
      final capture = await recording(tester, noteId: 'entry', placing: const PlacingEnd(lead: '**14:05** '), first: (capture) {
        capture.notes.create('entry', entry);
        capture.notes.create('house', house);
      });
      await capture.until(() => capture.isWhere('Adding to “2026-09-28 14.05”'));
      // A move is the one command that sends a note's own Speak elsewhere.
      await capture.say("Move this to house to do's.", 0);
      await capture.until(() => capture.hasTopAction('Not this note'));
      await capture.tap(capture.topAction);
      await capture.until(() => capture.isWhere('Adding to “2026-09-28 14.05”'));
      await capture.say('Walked along the river.', 2000);
      await capture.doneAndFinished();
      expect(capture.notes.body('house'), house);
      expect(capture.notes.body('entry'), '$entry\n**14:05** Walked along the river.');
      await capture.close();
    });

    testWidgets('takes a one-shot back into the take on its own Not this note', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say('Kevin owns the release.', 0);
      await capture.say('Hey Ghost, add call Sam to House TODOs.', 1000);
      await capture.until(() => find.byType(ListLanding).evaluate().isNotEmpty);
      expect(tester.widget<ListLanding>(find.byType(ListLanding)).title, 'House TODOs');
      await capture.tap(find.descendant(of: find.byType(ListLanding), matching: find.text('Not this note')));
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('house'), house);
      expect(done.note?.body, '# Kevin owns the release\n\nCall Sam.');
      await capture.close();
    });

    // Matt: "Id like sentences to be able to redact" (docs/DESIGN.md §130). The last thing said goes back into
    // smoke, the chip says what went with Undo, and "scratch that" never flashes onto the page while it is said.
    testWidgets('takes the last sentence back into smoke, with Undo in the chip that puts it back and writes the words', (tester) async {
      final capture = await recording(tester);
      await capture.say('Eggs.', 0);
      await capture.say('Call Sam.', 1000);
      await capture.until(() => capture.page().contains('Call Sam'));
      await capture.partial('Scratch');
      expect(capture.page(), isNot(contains('Scratch')));
      // Nor when the opener comes after words, which stay on the page while it is said.
      await capture.partial('The meeting is at three, scratch tha');
      expect(capture.page(), contains('The meeting is at three'));
      expect(capture.page(), isNot(contains('scratch')));
      await capture.say('Scratch that.', 2000);
      await capture.until(() => !capture.page().contains('Call Sam'));
      expect(capture.page(), isNot(contains('Scratch')));
      expect(capture.screenText, contains('Took back “Call Sam”'));
      await capture.tap(find.text('Undo'));
      await capture.until(() => capture.page().contains('Call Sam'));
      expect(capture.page(), contains('Scratch that.'));
      expect(find.text('Undo'), findsNothing);
      final done = await capture.doneAndFinished();
      expect(done.note?.body, '# Eggs\n\nCall Sam. Scratch that.');
      await capture.close();
    });

    testWidgets('says there is nothing to take back after New note is tapped', (tester) async {
      final capture = await recording(tester, noteId: 'daily', first: (capture) => capture.notes.create('daily', '# Daily Life\n\nWent for a walk.'));
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Went for a run.', 0);
      await capture.tap(capture.topAction);
      await capture.until(() => !capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Scratch that.', 1000);
      await capture.until(() => capture.says('Nothing to take back.'));
      await capture.close();
    });

    testWidgets('sends the sentence taken back to the note named, written at Done, and says what it took back at Done', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('groceries', '# Groceries\n\n- Eggs'));
      await capture.say('Kevin owns the release.', 0);
      await capture.say('Oat milk.', 1000);
      await capture.say('Scratch that, add it to groceries instead.', 2000);
      await capture.until(() => !capture.page().contains('Oat milk'));
      expect(capture.screenText, contains('Sent “Oat milk” to'));
      expect(capture.notes.body('groceries'), '# Groceries\n\n- Eggs');
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('groceries'), '# Groceries\n\n- Eggs\n- Oat milk');
      expect(done.note?.body, '# Kevin owns the release');
      final landing = done.landing!;
      expect(landing.noteId, done.note!.id);
      expect(landing.others, hasLength(1));
      expect(landing.into, ['Groceries']);
      expect(landing.tookBack, ['Oat milk']);
      await capture.close();
    });

    testWidgets('empties a one-shot of the enumeration taken back, so Done leaves the note as it was', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('groceries', '# Groceries\n\n- Eggs'));
      await capture.say('Kevin owns the release.', 0);
      await capture.say('Hey Ghost, add milk, bread and butter to groceries.', 1000);
      await capture.say('Scratch that.', 2000);
      expect(capture.screenText, contains('Took back “milk, bread, butter”'));
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('groceries'), '# Groceries\n\n- Eggs');
      expect(done.note?.body, '# Kevin owns the release');
      await capture.close();
    });

    testWidgets('still reads a command left for the reader at Done, over the phrases as the take kept them', (tester) async {
      final capture = await recording(tester);
      await capture.say('Hey Ghost, make a list called packing with sunscreen and towels.', 0);
      await capture.say('Bin bags.', 1000);
      await capture.say('Scratch that.', 2000);
      await capture.done();
      await capture.until(() => capture.hasCard('Create Packing'));
      final card = capture.textOf(capture.card('Create Packing')).toLowerCase();
      expect(card, contains('sunscreen'));
      expect(card, isNot(contains('bin bags')));
      await capture.tap(capture.inCard('Create Packing', 'Create'));
      await capture.untilFinished();
      expect(capture.notes.bodies, ['Packing\n\n- Sunscreen\n- Towels\n']);
      await capture.close();
    });

    testWidgets('reads a phrase said before the notes were read once they are', (tester) async {
      final letGo = Completer<void>();
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('house', house);
        capture.notes.held = letGo.future;
      });
      await capture.say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      expect(capture.isWhere('Adding to “House TODOs”'), isFalse);
      letGo.complete();
      capture.notes.held = null;
      await capture.until(() => capture.isWhere('Adding to “House TODOs”'));
      await capture.doneAndFinished();
      expect(capture.notes.body('house'), '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
      await capture.close();
    });

    testWidgets('stores nothing on Discard after New note, the part before it included', (tester) async {
      final capture = await recording(tester, noteId: 'daily', first: (capture) => capture.notes.create('daily', '# Daily Life\n\nWent for a walk.'));
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Went for a run.', 0);
      await capture.tap(capture.topAction);
      await capture.say('Call Sam.', 1000);
      await capture.discard();
      await capture.untilFinished();
      expect(capture.finished.single, nothing);
      expect(capture.notes.bodies, ['# Daily Life\n\nWent for a walk.']);
      await capture.close();
    });

    testWidgets('never writes a shared note over the lock screen', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.locked = true;
        capture.shared.add('house');
        capture.notes.create('house', house);
      });
      await capture.say("Hey Ghost, add a note to house to do's. Call Sam.", 0);
      await capture.until(() => capture.says('That note is shared, so the words stay here.'));
      await capture.doneAndFinished();
      expect(capture.notes.body('house'), house);
      expect(capture.notes.bodies..sort(), ['# Call Sam', house]);
      await capture.close();
    });

    testWidgets('offers no book on a card, and never writes into one', (tester) async {
      final b1 = bookNoteBody('HelloTrade: The Book', ['Intro']);
      final b2 = bookNoteBody('HelloTrade — The Book', ['From tap to fill']);
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('b1', b1);
        capture.notes.create('b2', b2);
        capture.notes.create('guide', '# HelloTrade: Frontend Developer Guide\n');
      });
      await capture.say('Hey Ghost, add a note to hello trade the book, check the glossary.', 0);
      await capture.until(() => capture.says('“HelloTrade — The Book” is a notebook, so the words stay here.'));
      expect(capture.hasCard('Add to which note?'), isFalse);
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('b1'), b1);
      expect(capture.notes.body('b2'), b2);
      expect(done.note?.body, '# Check the glossary');
      await capture.close();
    });

    testWidgets('carries out a second command said while the first waits for its name', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('s1', '# Signing in, and signing');
        capture.notes.create('s2', '# Signing the order');
        capture.notes.create('groceries', '# Groceries\n\n- Eggs\n');
      });
      await capture.say('Kevin owns the release.', 0);
      await capture.say('Hey Ghost, add to signing.', 1000);
      await capture.say('Hey Ghost, add milk to groceries.', 2000);
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('groceries'), '# Groceries\n\n- Eggs\n- Milk\n');
      expect(done.note?.body, '# Kevin owns the release');
      await capture.close();
    });

    testWidgets('keeps how people talk as words, where a mishearing of the keyword starts it', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('post', "# It's post");
        capture.notes.create('daily', '# Daily Life\n\nWent for a walk.');
      });
      await capture.say('Hey, like, put the parcel in the post.', 0);
      await capture.say('Then I went home.', 1000);
      final fresh = await capture.doneAndFinished();
      expect(capture.notes.body('post'), "# It's post");
      expect(fresh.note?.body, 'Hey, like, put the parcel in the post. Then I went home.');
      await capture.close();

      await capture.open(noteId: 'daily');
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Okay, like, make sure the door is locked.', 0);
      final own = await capture.doneAndFinished();
      expect(own.ask, isNull);
      expect(capture.notes.body('daily'), '# Daily Life\n\nWent for a walk.\n\nOkay, like, make sure the door is locked.');
      await capture.close();
    });

    testWidgets('queues a keyworded ask the take opened with once a later command is carried out, and never saves it as words', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say('Hey Ghost, fix the spelling.', 0);
      await capture.say('Buy milk.', 1000);
      await capture.say('Hey Ghost, add call Sam to House TODOs.', 2000);
      final done = await capture.doneAndFinished();
      expect(capture.notes.body('house'), '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n');
      expect(done.note?.body, '# Buy milk');
      expect(done.ask, const SpokenAsk(kind: 'fix'));
      await capture.close();
    });

    testWidgets('writes what is said after a second command into the note it named, not the first', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('house', house);
        capture.notes.create('daily', '# Daily Life\n\nWent for a walk.');
      });
      await capture.say("Hey Ghost, add a note to house to do's.", 0);
      await capture.say('Hey Ghost, add a note to daily life.', 1000);
      await capture.say('Went for a run.', 2000);
      await capture.doneAndFinished();
      expect(capture.notes.body('house'), house);
      expect(capture.notes.body('daily'), '# Daily Life\n\nWent for a walk.\n\nWent for a run.');
      await capture.close();
    });

    testWidgets('keeps every word of a name that matched nothing on Keep here', (tester) async {
      final capture = await recording(tester);
      await capture.say('Hey Ghost, add a note to moon base pack sunscreen and the tent.', 0);
      await capture.until(() => choiceStarting(capture, 'No note called'));
      final done = await capture.doneAndFinished();
      expect(done.note?.body, 'Moon base pack sunscreen and the tent.');
      await capture.close();
    });

    testWidgets('hands the better words a card’s new note under its title', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.keeping(3000, null));
      await capture.say('Hey Ghost, add a note to the moon base.', 0);
      await capture.until(() => capture.hasCard('No note called “moon base”'));
      await capture.tap(capture.inCard('No note called “moon base”', 'New note “Moon base”'));
      await capture.say('Call Sam.', 1000);
      await capture.doneAndFinished();
      final job = capture.refines[0];
      expect((job.baseBody, job.savedBody, job.titled), ('Moon base', 'Moon base\n\nCall Sam.', false));
      await capture.close();
    });

    testWidgets('keeps the better words of the take’s own note when a one-shot from it is undone', (tester) async {
      final capture = await recording(tester, first: (capture) {
        capture.notes.create('house', house);
        capture.keeping(3000, null);
      });
      await capture.say('Kevin owns the release.', 0);
      await capture.say('Hey Ghost, add call Sam to House TODOs.', 1000);
      final done = await capture.doneAndFinished();
      final landing = done.landing!;
      expect(landing.blocks, isEmpty);
      expect(landing.others, hasLength(1));
      expect(landing.fromMs, isNull);
      await capture.close();
    });

    testWidgets('says why nothing was added to a note named with nothing said for it, long enough to be read', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say("Hey Ghost, add a note to house to do's.", 0);
      await capture.done();
      await capture.until(() => capture.says('Nothing was said for House TODOs, so nothing was added.'));
      expect(capture.finished, isEmpty);
      await capture.untilFinished(1, 3000);
      expect(capture.finished.single, nothing);
      expect(capture.notes.body('house'), house);
      await capture.close();
    });

    testWidgets('reads only what was said after New note at Done, and writes what came before it first', (tester) async {
      final capture = await recording(tester, noteId: 'daily', first: (capture) {
        capture.notes.create('daily', '# Daily Life\n\nWent for a walk.');
        capture.notes.create('groceries', '# Groceries\n\n- Eggs\n');
      });
      await capture.until(() => capture.isWhere('Adding to “Daily Life”'));
      await capture.say('Kevin owns the release on Friday.', 0);
      await capture.tap(capture.topAction);
      // A new list by name is the reader at Done's ("add oat milk to groceries" would be carried out as it is said,
      // §136).
      await capture.say('Make a new list called packing with tent and stove.', 1000);
      await capture.done();
      await capture.until(() => capture.hasCard('Create Packing'));
      expect(capture.textOf(capture.card('Create Packing')), isNot(contains('Kevin')));
      expect(capture.notes.body('daily'), '# Daily Life\n\nWent for a walk.\n\nKevin owns the release on Friday.');
      await capture.tap(capture.inCard('Create Packing', 'Create'));
      await capture.untilFinished();
      expect(capture.notes.bodies, contains(startsWith('Packing\n\n- Tent\n- Stove')));
      await capture.close();
    });

    // A command needs no keyword (docs/DESIGN.md §136): said plainly at the start, it is carried out as it is said.
    testWidgets('switches to House TODOs for a command said without the keyword, writes the item live, and makes no note', (tester) async {
      final capture = await recording(tester, first: (capture) => capture.notes.create('house', house));
      await capture.say('Add call Sam to House TODOs.', 0);
      await capture.until(() => capture.isWhere('Adding to “House TODOs”'));
      await capture.until(() => capture.page().contains('Call Sam'));
      expect(capture.notes.body('house'), house);
      final done = await capture.doneAndFinished();
      expect(capture.anyCard, isFalse);
      expect(capture.notes.bodies, ['# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n']);
      expect(done.note?.id, 'house');
      await capture.close();
    });
  });
}
