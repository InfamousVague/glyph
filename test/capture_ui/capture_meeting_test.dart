import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/meet/meeting_mark.dart';
import 'package:ghost_md/core/summary_text.dart' show dateTitled;

import '../support/render.dart';
import 'support/harness.dart';

/// `src/app/capture/CaptureScreen.test.tsx`, "a meeting", case for case: the recorder as a meeting (the Mac), and
/// "Meeting instead" on the card of things to say.
void main() {
  setUpAll(loadAppFonts);

  const nothing = (note: null, locked: false, review: null, ask: null, landing: null);
  Finder meetingInstead(Capture capture) => find.descendant(of: capture.sayCard, matching: find.text('Meeting instead'));

  group('a meeting', () {
    testWidgets(
        'is recorded, not read: the top line says Meeting, no card of things to say, the phrases are the transcript, and Done writes the date-titled note as a meeting with its better words and summary to come',
        (tester) async {
      // The stop keeps the audio, as the Mac's engine does.
      final capture = Capture(tester)..keeping(200000, null);
      await capture.open(meeting: true);
      expect(capture.isWhere('Meeting'), isTrue);
      expect(capture.hasSayCard, isFalse);
      // A cue is words here, and a command is words.
      await capture.say('we settled the date.', 1000);
      await capture.say('heading the launch.', 2400);
      await capture.say('hey Ghost, add call Sam to House TODOs.', 4000);
      expect(capture.hasSayCard, isFalse);
      await capture.done();
      await capture.until(() => capture.says('Keep Ghost.md open while it is written up.'));
      await capture.untilFinished(1, 4000);
      final saved = capture.finished.single.note!;
      expect(dateTitled(saved.body), isTrue);
      // Marked a meeting in its own words (lib/meet/meeting_mark.dart), the words under the mark.
      expect(meetingMarkOf(saved.body)?.kind, 'phone');
      expect(withMeetingMark(saved.body, null), matches(RegExp(r'^# Meeting, .+\n\n## Transcript\n\n\(0:\d\d\) We settled the date\. Heading the launch\. Hey Ghost, add call Sam to House TODOs\.$')));
      expect(saved.source, NoteSource.capture);
      expect(saved.recordingMs, 200000);
      expect(capture.prefs.meetings[saved.id], isA<num>());
      expect(capture.tapes.tapeId(saved.id), isNotNull);
      expect(capture.refines, hasLength(1));
      final job = capture.refines.single;
      expect((job.id, job.fromMs, job.recordingMs, job.meeting, job.titled), (saved.id, 0, 200000, true, false));
      expect(capture.summaries, [(saved.id, 'meeting')]);
      // No review, however short: a meeting is nobody's dictation.
      expect(capture.finished.single.review, isNull);
      // Nothing was written to any other note.
      expect([for (final note in capture.notes.all) note.id], [saved.id]);
      await capture.close();
    });

    testWidgets('queues no summary with summaries off, and leaves nothing behind when nothing was said', (tester) async {
      final capture = Capture(tester)..keeping(200000, null);
      capture.prefs = capture.prefs.copyWith(summaries: 'off');
      await capture.open(meeting: true);
      await capture.say('Words.', 1000);
      await capture.done();
      await capture.untilFinished(1, 4000);
      expect(capture.summaries, isEmpty);
      expect(capture.refines, hasLength(1));
      await capture.close();

      capture.keeping(3000, null);
      await capture.open(meeting: true);
      await capture.done();
      await capture.untilFinished(2);
      expect(capture.finished[1], nothing);
      expect(capture.backend.discarded, hasLength(1));
      expect(capture.notes.all.where((note) => !dateTitled(note.body) || note.body.contains('Words.')), hasLength(1));
      await capture.close();
    });

    testWidgets('is offered on the card as "Meeting instead" where a meeting can be recorded, not on a note’s own Speak, and on the Mac turns this recorder into the meeting', (tester) async {
      final capture = Capture(tester);
      capture.notes.create('groceries', 'Groceries');
      await capture.open(offersMeeting: true);
      await capture.until(() => capture.hasSayCard);
      await capture.tap(meetingInstead(capture));
      expect(capture.meetings, 0);
      expect(capture.isWhere('Meeting'), isTrue);
      expect(capture.hasSayCard, isFalse);
      await capture.close();

      await capture.open(noteId: 'groceries', offersMeeting: true);
      await capture.until(() => capture.hasSayCard);
      expect(meetingInstead(capture), findsNothing);
      await capture.close();

      await capture.open();
      await capture.until(() => capture.hasSayCard);
      expect(meetingInstead(capture), findsNothing);
      await capture.close();
    });

    testWidgets('on a phone lets the microphone go first - the take cancelled, its sound discarded - and hands over to the service', (tester) async {
      final capture = Capture(tester)..android = true;
      await capture.open(offersMeeting: true);
      await capture.until(() => capture.hasSayCard);
      await capture.tap(meetingInstead(capture));
      await capture.until(() => capture.meetings == 1);
      expect(capture.cancels, 1);
      expect(capture.backend.discarded, hasLength(1));
      expect(capture.finished, isEmpty);
      await capture.until(() => capture.notes.all.isEmpty);
      await capture.close();
    });
  });
}
