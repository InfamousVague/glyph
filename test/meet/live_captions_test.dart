// A meeting's captions while Ghost is in it, on the device (lib/meet/live_captions.dart, lib/meet/live_transcript.dart;
// Matt, 2026-10-30: "If possible add real time transcriptions for meetings"): each frame the relay hands over opened
// with the account's pair, in order and once, a gap caught up from the frames the service keeps, the meeting's note
// made at its first caption the same on every device and never written as the captions come; the take filed into that
// note in one edit, the person's words kept and the live words handed over; a meeting whose take never comes settled
// once. Over the service in memory and the fake crypto.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/enc_key.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/meet/live_captions.dart';
import 'package:ghost_md/meet/live_transcript.dart';
import 'package:ghost_md/meet/meet_api.dart';
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/meet/meet_note.dart';
import 'package:ghost_md/meet/meeting_mark.dart';
import 'package:ghost_md/sync/notes.dart' show LocalNotes;

import '../account_ui/support.dart';
import 'support.dart';

/// The device's notes, every write counted.
class CountedNotes implements LocalNotes {
  CountedNotes(this.inner);
  final LocalNotes inner;
  final List<String> writes = [];

  @override
  Future<List<Note>> list() => inner.list();
  @override
  Future<Note?> get(String id) => inner.get(id);
  @override
  Future<Note> apply(Note note) {
    writes.add(note.id);
    return inner.apply(note);
  }

  @override
  Future<void> remove(String id) => inner.remove(id);
}

class _Phone implements MeetDevice {
  final List<String> writeUps = [];
  @override
  Future<int?> keepTape(String noteId, Uint8List audio, String mime) async => 90000;
  @override
  void writeUp(String noteId) => writeUps.add(noteId);
}

const String meeting = 'm1';
const int now = 1792160000000;

void main() {
  late Device device;
  late FakeMeet meet;
  late String pub;
  late CountedNotes notes;
  late LiveTranscripts store;

  setUp(() async {
    meet = FakeMeet();
    final service = await FakeService.start(seed: seeded);
    device = await Device.make(service: service, publishing: true, fetcher: meet.over(service.fetcher));
    final kept = await ensureEncryptionKey(EncryptionKeyContext(token: device.account.session!.token, accountKey: (await device.account.accountKey())!, keys: device.keys, api: device.api, crypto: device.service.crypto));
    pub = kept.pub;
    notes = CountedNotes(device.notes);
    store = LiveTranscripts();
    preferences.value = const Preferences();
  });

  LiveCaptions captions({String? title = 'Launch sync'}) => LiveCaptions(
        store: store,
        hooks: LiveCaptionsHooks(
          open: (m, n, wrapped, data) async => openLive(device.service.crypto, (await device.keys.encryptionKey())!, meeting: m, n: n, wrapped: wrapped, data: data),
          catchUp: (m, after) => MeetApi(device.api).live(device.account.session!.token, m, after: after),
          noteFor: (m) => liveNoteFor(m, notes: notes, prefs: preferences, kept: device.kept, title: title, now: now),
          ended: (noteId) => markLiveNoteEnded(device.kept, noteId, now),
        ),
      );

  /// A frame as the relay hands it over: kept (`seq`) or the line being said alone (`partial`).
  Future<Map<String, Object?>> frame({int? seq, int? partial, List<Map<String, Object?>> lines = const [], Map<String, Object?>? saying, bool keep = true}) async {
    final n = seq != null ? '$seq' : 'p$partial';
    final sealed = await sealedLive(device.service.crypto, pub, meeting, n, lines: lines, partial: saying);
    if (seq != null && keep) (meet.live[meeting] ??= []).add({'seq': seq, 'wrapped': sealed.wrapped, 'data': sealed.data});
    return {'t': 'captions', 'meeting': meeting, 'seq': ?seq, 'partial': ?partial, 'wrapped': sealed.wrapped, 'data': sealed.data};
  }

  Map<String, Object?> line(int at, String speaker, String text) => {'at': at, 'speaker': speaker, 'text': text};

  final liveId = meetLiveNoteId(meeting);

  test('the captions stream into the meeting’s live words: named, timed turns, in order, each once', () async {
    final live = captions();
    await live.heard(await frame(seq: 1, lines: [line(4000, 'Sam Lee', 'Good morning everyone.')], saying: line(15000, 'Daniel', 'Thanks')));
    expect(store.isLive(liveId), isTrue);
    expect(store.of(liveId)!.turns, [(speaker: 'Sam Lee', startMs: 4000, text: 'Good morning everyone.'), (speaker: 'Daniel', startMs: 15000, text: 'Thanks')]);
    expect(store.of(liveId)!.saying, const LiveLine(at: 15000, speaker: 'Daniel', text: 'Thanks'));
    // The line being said grows: only it changes.
    await live.heard(await frame(partial: 1, saying: line(15000, 'Daniel', 'Thanks. The pricing page')));
    expect(store.of(liveId)!.turns.last.text, 'Thanks. The pricing page');
    expect(store.of(liveId)!.lines, hasLength(1));
    // Finished, then a frame said again (a socket that came back), and an old partial: each once.
    final second = await frame(seq: 2, lines: [line(15000, 'Daniel', 'Thanks. The pricing page is drafted.')]);
    await live.heard(second);
    await live.heard(second);
    await live.heard(await frame(partial: 1, saying: line(15000, 'Daniel', 'stale')));
    expect(store.of(liveId)!.turns, [(speaker: 'Sam Lee', startMs: 4000, text: 'Good morning everyone.'), (speaker: 'Daniel', startMs: 15000, text: 'Thanks. The pricing page is drafted.')]);
    expect(store.of(liveId)!.saying, isNull);
  });

  test('a gap is caught up from the frames the service keeps; a device that comes in mid-meeting has the words so far', () async {
    // Three frames went while this device was away.
    for (var n = 1; n <= 3; n++) {
      await frame(seq: n, lines: [line(n * 10000, n.isOdd ? 'Sam Lee' : 'Priya', 'Line $n.')]);
    }
    final live = captions();
    await live.heard(await frame(seq: 4, lines: [line(40000, 'Sam Lee', 'Line 4.')]));
    expect([for (final l in store.of(liveId)!.lines) l.text], ['Line 1.', 'Line 2.', 'Line 3.', 'Line 4.']);
    expect(meet.calls.where((c) => c.startsWith('GET meet/m1/live')), hasLength(1));
    // The line being said first, mid-meeting, on a device that knows nothing yet: caught up too.
    final other = LiveTranscripts();
    final fresh = LiveCaptions(store: other, hooks: captions().hooks);
    await fresh.heard(await frame(partial: 9, saying: line(50000, 'Priya', 'And')));
    expect(other.of(liveId)!.lines, hasLength(4));
    expect(other.of(liveId)!.saying?.text, 'And');
  });

  test('a frame that will not open is let go: moved to another place in its meeting, or to another meeting', () async {
    final live = captions();
    // Not kept by the service, so a catch-up has nothing to bring.
    final good = await frame(seq: 1, lines: [line(1000, 'Sam Lee', 'Hello.')], keep: false);
    // Moved to the second place: its contexts are the first's.
    await live.heard({...good, 'seq': 2});
    expect(store.of(liveId)?.lines ?? const [], isEmpty);
    await live.heard({...good, 'meeting': 'another'});
    expect(store.of(meetLiveNoteId('another'))?.lines ?? const [], isEmpty);
    expect(store.of(liveId)?.lines ?? const [], isEmpty);
  });

  test('the note is made once, at the first caption, the same words on every device, marked a meeting, and never written as the captions come', () async {
    final live = captions();
    for (var n = 1; n <= 20; n++) {
      await live.heard(await frame(seq: n, lines: [line(n * 3000, 'Sam Lee', 'Line $n.')]));
    }
    expect(notes.writes, [liveId], reason: 'one write, the note made; nothing as the captions came');
    final note = (await notes.get(liveId))!;
    expect(note.body, liveNoteBody('Launch sync'));
    expect(note.body, '# Launch sync\n\n$liveLine\n');
    // No `meeting:` mark yet (lib/meet/meeting_mark.dart): its start would be this device's clock, and the words must
    // be the same on every device; the take's filing writes it.
    expect(meetingMarkOf(note.body), isNull);
    expect(note.body, isNot(contains('## Captions')));
    expect(preferences.value.meetings[liveId], now);
    expect(meetingNotesOf(preferences.value), {meeting: liveId});
    // A second device makes the very same note.
    expect(liveNoteBody('Launch sync'), note.body);
    expect(meetLiveNoteId(meeting), liveId);
    expect(liveNoteBody(null), '# A meeting\n\n$liveLine\n', reason: 'no date nor time: nothing a device would say its own way');
  });

  test('a note the person deleted is not made again by the next caption', () async {
    final live = captions();
    await live.heard(await frame(seq: 1, lines: [line(1000, 'Sam Lee', 'Hello.')]));
    await notes.remove(liveId);
    final again = captions();
    await again.heard(await frame(seq: 2, lines: [line(2000, 'Sam Lee', 'Again.')]));
    expect(await notes.get(liveId), isNull);
  });

  test('the end: the words stay, not live, and the take is filed into the note in one edit, the person’s words kept', () async {
    final live = captions();
    await live.heard(await frame(seq: 1, lines: [line(1000, 'Sam Lee', 'Good morning everyone.')]));
    // The person writes in the meeting's note while it runs.
    final made = (await notes.get(liveId))!;
    await notes.apply(made.copyWith(body: '${made.body}\nMy own notes: ask about pricing.\n'));
    notes.writes.clear();
    await live.heard({'t': 'captions', 'meeting': meeting, 'ended': true});
    expect(store.of(liveId)!.live, isFalse);
    expect(store.of(liveId)!.lines, hasLength(1), reason: 'shown until the take is filed');
    expect(liveNotesMade(device.kept)[liveId]?['ended'], now);
    // The take comes.
    final kept = await ensureEncryptionKey(EncryptionKeyContext(token: device.account.session!.token, accountKey: (await device.account.accountKey())!, keys: device.keys, api: device.api, crypto: device.service.crypto));
    final sealed = await sealedTake(device.service.crypto, kept.pub, 'AbCdEfGhIjKlMnOpQrStUv', gmt1(captions: [line(1000, 'Sam Lee', 'Good morning everyone.'), line(11000, 'Daniel', 'The pricing page is drafted.')]));
    meet.takes['AbCdEfGhIjKlMnOpQrStUv'] = (meeting: meeting, at: now, wrapped: sealed.wrapped, sealed: sealed.sealed);
    final phone = _Phone();
    liveTranscripts.heard(liveId, from: LiveFrom.bot, lines: const [LiveLine(at: 1000, speaker: 'Sam Lee', text: 'Good morning everyone.')]);
    final filed = await syncMeet(MeetPassContext(
      token: device.account.session!.token,
      api: device.api,
      crypto: device.service.crypto,
      pair: () async => (await device.keys.encryptionKey())!,
      notes: notes,
      prefs: preferences,
      kept: device.kept,
      now: () => now + 60000,
      device: () => phone,
    ));
    expect(filed, 1);
    expect(notes.writes, [liveId], reason: 'one edit of the one note');
    expect(await notes.get(meetNoteId('AbCdEfGhIjKlMnOpQrStUv')), isNull, reason: 'no second note of the meeting');
    final note = (await notes.get(liveId))!;
    expect(withMeetingMark(note.body, null), startsWith('# Launch sync\n\nGhost was in this meeting on '));
    expect(meetingMarkOf(note.body)?.booking, meeting, reason: 'the take’s mark, once');
    expect(note.body, contains('It is being written up on your device.\n\nMy own notes: ask about pricing.\n\n## Captions\n\n**Sam Lee (0:01):** Good morning everyone.\n\n**Daniel (0:11):** The pricing page is drafted.\n'));
    expect(note.body, isNot(contains(liveLine)));
    expect((note.createdAt, note.recordingMs), (now, 90000));
    expect(phone.writeUps, [liveId]);
    expect(liveTranscripts.of(liveId), isNull, reason: 'the live words handed over to the take’s');
    expect(meet.takes, isEmpty);
  });

  test('a meeting whose take never came is settled once an hour after it ended, the same words on every device', () async {
    final live = captions();
    await live.heard(await frame(seq: 1, lines: [line(1000, 'Sam Lee', 'Hello.')]));
    await live.heard({'t': 'captions', 'meeting': meeting, 'ended': true});
    Future<({String body, Future<void> Function(String body) write})?> read(String id) async {
      final note = await notes.get(id);
      return note == null ? null : (body: note.body, write: (String body) async => notes.apply(note.copyWith(body: body)).then((_) {}));
    }

    expect(await settleLiveNotes(kept: device.kept, note: read, now: now + 30 * 60000, store: store), 0, reason: 'not yet');
    expect(await settleLiveNotes(kept: device.kept, note: read, now: now + liveSettleAfterMs, waiting: {liveId}, store: store), 0, reason: 'its take is waiting');
    expect(await settleLiveNotes(kept: device.kept, note: read, now: now + liveSettleAfterMs, store: store), 1);
    final body = (await notes.get(liveId))!.body;
    expect(body, '# Launch sync\n\n$liveLineNoTake\n');
    expect(withoutTake(liveNoteBody('Launch sync')), body, reason: 'every device writes the same words');
    expect(store.of(liveId), isNull);
    expect(await settleLiveNotes(kept: device.kept, note: read, now: now + 2 * liveSettleAfterMs, store: store), 0, reason: 'once');
  });

  test('the live turns follow the meeting’s rules: a speaker’s run, a new turn after three seconds’ pause or a minute', () {
    final lines = [
      const LiveLine(at: 0, speaker: 'Sam Lee', text: 'one.'),
      const LiveLine(at: 2000, speaker: 'Sam Lee', text: 'two.'),
      const LiveLine(at: 9000, speaker: 'Sam Lee', text: 'after a pause.'),
      const LiveLine(at: 10000, speaker: 'Daniel', text: 'mine.'),
      const LiveLine(at: 12000, text: 'nobody named.'),
    ];
    expect(liveTurns(lines), [
      (speaker: 'Sam Lee', startMs: 0, text: 'One. Two.'),
      (speaker: 'Sam Lee', startMs: 9000, text: 'After a pause.'),
      (speaker: 'Daniel', startMs: 10000, text: 'Mine.'),
      (speaker: null, startMs: 12000, text: 'Nobody named.'),
    ]);
    // A minute of one voice is two turns.
    final long = [for (var i = 0; i < 31; i++) LiveLine(at: i * 2500, text: 'phrase $i.')];
    expect(liveTurns(long).length, 2);
    expect(handedOver(liveNoteBody('T'), '# T\n\nGhost was in this meeting.\n\n## Captions\n\nx\n'), '# T\n\nGhost was in this meeting.\n\n## Captions\n\nx\n', reason: 'nothing of the person’s: the take’s note as it is');
  });
}
