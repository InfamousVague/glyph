import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/meet/meeting_mark.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/mail/mail_note.dart' show mailNoteId;
import 'package:ghost_md/watch/watch_link.dart';
import 'package:ghost_md/watch/watch_notes.dart';

import 'fakes.dart';

void main() {
  late Directory dir;
  late FakeHost host;
  late FakeStore store;
  late List<(String, int)> listened;
  late Heard Function(String id) answer;
  late List<String> summaries, writeUps;
  late Map<String, int> meetings;
  late Preferences prefs;
  late bool held;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('watch-notes');
    host = FakeHost();
    store = FakeStore();
    listened = [];
    answer = (_) => const HeardWords([Segment(startMs: 0, endMs: 2000, text: 'Buy oat milk on the way home.')]);
    summaries = [];
    writeUps = [];
    meetings = {};
    prefs = const Preferences();
    held = false;
  });
  tearDown(() => dir.deleteSync(recursive: true));

  WatchTake take(String id, {int at = 1760000000000, int ms = 4200, bool file = true}) {
    final wav = File('${dir.path}/$id.wav');
    if (file) wav.writeAsBytesSync([82, 73, 70, 70, ...List.filled(60, 0)]);
    return WatchTake(id: id, recordedAt: at, durationMs: ms, watch: 'Galaxy Watch9', wav: wav.path);
  }

  WatchNotes notesOver({bool canWriteUp = true}) => WatchNotes(
        host: host,
        store: store,
        listen: (id, ms) async {
          listened.add((id, ms));
          return answer(id);
        },
        preferences: () => prefs,
        held: () => held,
        enqueueSummary: summaries.add,
        writeUp: canWriteUp ? writeUps.add : null,
        markMeeting: (id, at) => meetings[id] = at,
        retry: const Duration(milliseconds: 20),
      );

  test('a take is made a voice note: its recording kept, its words heard and written as dictation, dated on the watch', () async {
    host.takes.add(take('t1'));
    final notes = notesOver();
    expect(await notes.kick(), 1);

    final id = watchNoteId('t1');
    final note = store.notes[id]!;
    expect(note.body, watchNoteBody(const [Segment(startMs: 0, endMs: 2000, text: 'Buy oat milk on the way home.')], 1760000000000));
    expect(note.body, contains('Buy oat milk on the way home.'));
    expect(note.createdAt, 1760000000000);
    expect(note.recordingMs, 4200);
    expect(note.segments, const [Segment(startMs: 0, endMs: 2000, text: 'Buy oat milk on the way home.')]);
    expect(note.source, NoteSource.capture);
    expect(store.recordings[id], endsWith('/t1.wav'));
    expect(listened, [(id, 4200)]);
    expect(host.doneIds, ['t1']);
    expect(summaries, isEmpty);
    expect(writeUps, isEmpty);
    notes.dispose();
  });

  test('spoken cues shape the note as they do one recorded on the phone', () {
    final body = watchNoteBody(const [
      Segment(startMs: 0, endMs: 1500, text: 'Shopping list.'),
      Segment(startMs: 1600, endMs: 3000, text: 'New paragraph. Bullet point eggs.'),
    ], 0);
    // A short first sentence is the title, and "bullet point" an item, as in a note dictated on the phone.
    expect(body, '# Shopping list\n\n- Eggs\n');
  });

  test('nothing heard still keeps the tape, under the time it was recorded', () async {
    answer = (_) => const HeardWords([]);
    host.takes.add(take('quiet'));
    final notes = notesOver();
    expect(await notes.kick(), 1);
    final note = store.notes[watchNoteId('quiet')]!;
    expect(note.body, startsWith('# Watch recording, '));
    expect(note.body, contains('Nothing was heard in this recording.'));
    expect(meetingMarkOf(note.body), isNull, reason: 'a short take is no meeting');
    expect(note.recordingMs, 4200);
    notes.dispose();
  });

  test('a take is one note however often it comes: one already made only leaves the inbox', () async {
    host.takes.add(take('t1'));
    final notes = notesOver();
    await notes.kick();
    final first = store.notes[watchNoteId('t1')];
    // The watch sent it again before it heard back, and the phone forgot it had it.
    host.takes.add(take('t1'));
    expect(await notes.kick(), 0);
    expect(store.notes, hasLength(1));
    expect(store.notes[watchNoteId('t1')], same(first));
    expect(host.doneIds, ['t1', 't1']);
    expect(listened, hasLength(1));
    notes.dispose();
  });

  test('a pass cut short after the recording was kept goes on from there', () async {
    final id = watchNoteId('t1');
    // The WAV already moved to the note's recording, and the app stopped before the note was written.
    store.recordings[id] = 'kept before';
    host.takes.add(take('t1', file: false));
    final notes = notesOver();
    expect(await notes.kick(), 1);
    expect(store.recordings[id], 'kept before');
    expect(store.notes[id], isNotNull);
    notes.dispose();
  });

  test('a take whose sound is nowhere is let go, not made an empty note', () async {
    host.takes.add(take('lost', file: false));
    final notes = notesOver();
    expect(await notes.kick(), 0);
    expect(store.notes, isEmpty);
    expect(host.doneIds, ['lost']);
    notes.dispose();
  });

  test('words that cannot be heard yet leave the take waiting, and it is made once they can', () async {
    answer = (_) => const HeardLater('the voice engine is busy');
    host.takes.add(take('t1'));
    final notes = notesOver();
    expect(await notes.kick(), 0);
    expect(store.notes, isEmpty);
    expect(host.doneIds, isEmpty);
    expect(store.recordings, contains(watchNoteId('t1')), reason: 'the recording is the note-to-be’s already');

    answer = (_) => const HeardWords([Segment(startMs: 0, endMs: 900, text: 'Later.')]);
    // Tried again on its own a moment later.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(store.notes[watchNoteId('t1')]?.body, '# Later\n');
    expect(host.doneIds, ['t1']);
    notes.dispose();
  });

  test('nothing is heard while the recorder holds the phone', () async {
    held = true;
    host.takes.add(take('t1'));
    final notes = notesOver();
    expect(await notes.kick(), 0);
    expect(listened, isEmpty);
    held = false;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(store.notes, hasLength(1));
    notes.dispose();
  });

  test('a long voice note asks for its summary only when Settings says long voice notes are summarised', () async {
    prefs = const Preferences(summaries: 'long');
    host.takes.add(take('long', ms: longNoteMs + 1));
    host.takes.add(take('short', ms: longNoteMs - 1, at: 1760000000001));
    final notes = notesOver();
    expect(await notes.kick(), 2);
    expect(summaries, [watchNoteId('long')]);

    prefs = const Preferences(summaries: 'meetings');
    host.takes.add(take('long2', ms: longNoteMs + 1));
    await notes.kick();
    expect(summaries, [watchNoteId('long')]);
    notes.dispose();
  });

  test('a take past ten minutes is written up as a meeting, not heard here', () async {
    host.takes.add(take('talk', ms: meetingFromMs + 1));
    final notes = notesOver();
    expect(await notes.kick(), 1);
    final id = watchNoteId('talk');
    expect(listened, isEmpty);
    // Marked a meeting in its own words (lib/meet/meeting_mark.dart), the title under the mark.
    expect(withMeetingMark(store.notes[id]!.body, null), startsWith('# Watch recording, '));
    expect(meetingMarkOf(store.notes[id]!.body)?.kind, 'phone');
    expect(store.notes[id]!.recordingMs, meetingFromMs + 1);
    expect(meetings, {id: 1760000000000});
    expect(writeUps, [id]);
    expect(host.doneIds, ['talk']);
    notes.dispose();
  });

  test('where nothing writes up, a long take is heard as a voice note', () async {
    host.takes.add(take('talk', ms: meetingFromMs + 1));
    final notes = notesOver(canWriteUp: false);
    expect(await notes.kick(), 1);
    expect(listened, hasLength(1));
    expect(meetings, isEmpty);
    notes.dispose();
  });

  test('a take that fails is tried three times and does not hold up the ones after it', () async {
    host.takes.add(take('bad', at: 1));
    host.takes.add(take('good', at: 2));
    var calls = 0;
    answer = (id) {
      calls += 1;
      if (id == watchNoteId('bad')) throw StateError('broken');
      return const HeardWords([Segment(startMs: 0, endMs: 10, text: 'Fine.')]);
    };
    final notes = WatchNotes(
      host: host,
      store: store,
      listen: (id, ms) async => answer(id),
      preferences: () => prefs,
      retry: const Duration(hours: 1),
    );
    expect(await notes.kick(), 1);
    expect(store.notes.keys, [watchNoteId('good')]);
    await notes.kick();
    await notes.kick();
    await notes.kick();
    expect(calls, 1 + 3, reason: 'the bad take three times, then left for the next run');
    expect(host.takes.map((t) => t.id), ['bad']);
    notes.dispose();
  });

  test('a take arriving while the app runs is made at once', () async {
    final notes = notesOver()..start();
    await pumpEventQueue();
    host.arrive(take('fresh'));
    await pumpEventQueue();
    for (var i = 0; i < 20 && store.notes.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(store.notes.keys, [watchNoteId('fresh')]);
    notes.dispose();
  });

  test('the note id is the take’s own, and never a mail’s', () {
    expect(watchNoteId('abc'), watchNoteId('abc'));
    expect(watchNoteId('abc'), isNot(watchNoteId('abd')));
    expect(watchNoteId('abc'), isNot(mailNoteId('abc')));
    expect(watchNoteId('abc'), matches(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
  });

  test('the phone’s answers are read as the bridge writes them', () {
    expect(
      WatchTake.fromJson({'id': 'a', 'recordedAt': 5, 'durationMs': 4200, 'watch': 'Galaxy Watch9', 'bytes': 99, 'wav': '/data/watch/inbox/a.wav'}),
      const WatchTake(id: 'a', recordedAt: 5, durationMs: 4200, watch: 'Galaxy Watch9', wav: '/data/watch/inbox/a.wav'),
    );
    expect(WatchTake.fromJson({'recordedAt': 5}), isNull);
    expect(WatchTake.fromJson('nonsense'), isNull);

    final status = WatchStatus.fromJson({
      'watches': [
        {'name': 'Galaxy Watch9', 'nearby': true},
        {'name': 'TAG Heuer Connected', 'nearby': false},
        {'nearby': true},
      ],
      'last': {'id': 'a', 'recordedAt': 1, 'durationMs': 42000, 'watch': 'Galaxy Watch9', 'receivedAt': 7},
      'waiting': 2,
    });
    expect(status.watches, [(name: 'Galaxy Watch9', nearby: true), (name: 'TAG Heuer Connected', nearby: false)]);
    expect((status.lastAt, status.lastWatch, status.lastMs, status.waiting), (7, 'Galaxy Watch9', 42000, 2));
    expect(status.any, isTrue);
    expect(WatchStatus.fromJson({'watches': [], 'last': null, 'waiting': 0}).any, isFalse);
    expect(WatchStatus.fromJson(null).any, isFalse);
  });
}
