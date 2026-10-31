import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/meet/live_transcript.dart';
import 'package:ghost_md/meet/meeting_mark.dart';

/// Which notes are meetings, written into the note (lib/meet/meeting_mark.dart): one flow map in the page's front
/// matter, read beside the preferences for a release.
void main() {
  const start = 1792159200000;
  Note note(String id, String body) => Note(id: id, body: body, createdAt: 0, updatedAt: 0);

  group('the mark', () {
    test('is one line, `meeting: {start: <ISO>, …}`, written and read back whole', () {
      const mark = MeetingMark(startMs: start, kind: 'meet', booking: 'm1', app: 'w-ab12cd');
      final body = withMeetingMark('# Launch sync\n\nwords\n', mark);
      expect(body, '---\nmeeting: {start: 2026-10-16T14:00:00.000Z, kind: meet, booking: m1, app: w-ab12cd}\n---\n# Launch sync\n\nwords\n');
      expect(meetingMarkOf(body), mark);
      expect(meetingMarkOf(withMeetingMark(body, null)), isNull);
      expect(withMeetingMark(body, null), '# Launch sync\n\nwords\n');
      // Replaced in place where there is one; other keys stay.
      final ticket = withMeetingMark('---\nstatus: Done\n---\n# Plan\n', const MeetingMark(startMs: start));
      expect(ticket, '---\nstatus: Done\nmeeting: {start: 2026-10-16T14:00:00.000Z}\n---\n# Plan\n');
      expect(withMeetingMark(ticket, const MeetingMark(startMs: start, kind: 'phone')), contains('meeting: {start: 2026-10-16T14:00:00.000Z, kind: phone}\n'));
    });

    test('reads nothing from a value that is not a map with a start, and drops a word the line cannot carry', () {
      expect(meetingMarkOf('---\nmeeting: true\n---\n# A\n'), isNull);
      expect(meetingMarkOf('---\nmeeting: {kind: meet}\n---\n# A\n'), isNull);
      expect(meetingMarkOf('---\nmeeting: {start: yesterday}\n---\n# A\n'), isNull);
      expect(meetingMarkOf('# A\n'), isNull);
      expect(const MeetingMark(startMs: start, booking: 'has, comma').value, '{start: 2026-10-16T14:00:00.000Z}');
    });
  });

  group('read both ways', () {
    test('is the preferences’ meetings and every note that says so, the preferences’ time first', () {
      final prefs = Preferences.defaults.copyWith(meetings: {'a': 1, 'b': 2});
      final notes = [
        note('a', withMeetingMark('# A\n', const MeetingMark(startMs: 99))),
        note('c', withMeetingMark('# C\n', const MeetingMark(startMs: start))),
        note('d', '# D\n\nnot a meeting\n'),
      ];
      expect(meetingsOf(prefs, notes), {'a': 1, 'b': 2, 'c': start});
      expect(identical(meetingsOf(prefs, [notes[2]]), prefs.meetings), isTrue, reason: 'no note adds one: the preferences’ own map');
      expect(bookingsOf([note('c', withMeetingMark('# C\n', const MeetingMark(startMs: start, booking: 'm1')))]), {'m1': 'c'});
    });
  });

  group('a live note with the mark', () {
    test('keeps the mark out of the person’s words when the take is handed over', () {
      final live = withMeetingMark(liveNoteBody('Launch sync'), const MeetingMark(startMs: start, booking: 'm1'));
      final written = '$live\nmy own line\n';
      expect(personsWords(written), 'my own line');
      final filed = withMeetingMark('# Launch sync\n\nGhost was in this meeting.\n\n## Captions\n\n**Sam (0:01):** Hi.\n', const MeetingMark(startMs: start, kind: 'meet', booking: 'm1'));
      final handed = handedOver(written, filed);
      expect(handed, startsWith('---\nmeeting: {start: 2026-10-16T14:00:00.000Z, kind: meet, booking: m1}\n---\n# Launch sync\n'));
      expect(handed, contains('\n\nmy own line\n\n## Captions\n'));
      expect(handed.indexOf('---\nmeeting'), handed.lastIndexOf('---\nmeeting'), reason: 'the mark once, the take’s');
    });
  });
}
