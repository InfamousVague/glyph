// Ghost in a Google Meet, on a device (lib/meet/meet_in.dart): a sync pass filing each take - opened with the
// account's pair, its sound kept as the note's recording, the note written and marked a meeting, its write-up asked
// for, and only then the take taken off the service - once, however often the pass runs; a device that cannot keep the
// sound leaving the take a day for one that can; a later pass naming the speakers once the write-up has come; and
// quiet against a service with no meeting routes. Over the service in memory and the fake crypto.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/enc_key.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/meet/meet_api.dart' show MeetBooking;
import 'package:ghost_md/meet/meet_in.dart';
import 'package:ghost_md/meet/meet_note.dart';
import 'package:ghost_md/sync/engine.dart';
import 'package:ghost_md/sync/notes.dart' show LocalNotes;
import 'package:ghost_md/sync/prefs.dart' show pickSynced;

import '../account_ui/support.dart';
import 'support.dart';

/// What the device was asked: a tape kept, a write-up.
class FakeMeetDevice implements MeetDevice {
  FakeMeetDevice({this.ms = 90000});

  /// What [keepTape] answers: the tape's length, or null for a sound this device cannot keep.
  final int? ms;
  final Map<String, Uint8List> tapes = {};
  final List<String> writeUps = [];

  @override
  Future<int?> keepTape(String noteId, Uint8List audio, String mime) async {
    if (ms != null) tapes[noteId] = audio;
    return ms;
  }

  @override
  void writeUp(String noteId) => writeUps.add(noteId);
}

const String takeId = 'AbCdEfGhIjKlMnOpQrStUv';
const int day = 24 * 3600 * 1000;

const List<Map<String, Object?>> captions = [
  {'at': 1000, 'speaker': 'Sam Lee', 'text': 'Good morning everyone.'},
  {'at': 11000, 'speaker': 'Daniel', 'text': 'The pricing page is drafted.'},
];

Future<({Device device, FakeMeet meet})> made() async {
  final meet = FakeMeet();
  final service = await FakeService.start(seed: seeded);
  final device = await Device.make(service: service, publishing: true, fetcher: meet.over(service.fetcher));
  return (device: device, meet: meet);
}

/// A take waiting on the service for [device]'s account, arrived at [at].
Future<void> recorded(({Device device, FakeMeet meet}) d, {String id = takeId, int at = 1792161900000, List<int> audio = const [1, 2, 3, 4]}) async {
  final kept = await ensureEncryptionKey(EncryptionKeyContext(token: d.device.account.session!.token, accountKey: (await d.device.account.accountKey())!, keys: d.device.keys, api: d.device.api, crypto: d.device.service.crypto));
  final sealed = await sealedTake(d.device.service.crypto, kept.pub, id, gmt1(captions: captions, audio: audio));
  d.meet.takes[id] = (meeting: 'm1', at: at, wrapped: sealed.wrapped, sealed: sealed.sealed);
}

MeetPassContext context(({Device device, FakeMeet meet}) d, {MeetDevice? device, int now = 1792162000000}) => MeetPassContext(
      token: d.device.account.session!.token,
      api: d.device.api,
      crypto: d.device.service.crypto,
      pair: () async => (await d.device.keys.encryptionKey())!,
      notes: d.device.notes,
      prefs: preferences,
      kept: d.device.kept,
      now: () => now,
      device: () => device,
    );

void main() {
  test('a take becomes one note, its sound kept as its tape, marked a meeting and written up; then it goes', () async {
    final d = await made();
    await recorded(d);
    final phone = FakeMeetDevice();
    expect(await syncMeet(context(d, device: phone)), 1);
    final id = meetNoteId(takeId);
    final note = d.device.notes.held[id]!;
    expect(note.body, startsWith('# Launch sync\n\nGhost was in this meeting on '));
    expect(note.body, contains('It is being written up on your device.\n\n## Captions\n\n**Sam Lee (0:01):** Good morning everyone.\n\n**Daniel (0:11):** The pricing page is drafted.\n'));
    expect(note.body, isNot(contains('## Transcript')), reason: 'the write-up would take words under it as the transcript');
    expect((note.createdAt, note.updatedAt, note.recordingMs, note.source), (1792159200000, 1792162000000, 90000, NoteSource.capture));
    expect(phone.tapes[id], [1, 2, 3, 4]);
    expect(phone.writeUps, [id]);
    expect(preferences.value.meetings[id], 1792159200000);
    // The meeting it was of, kept against it, so Settings › Meetings opens it (and every device, with the settings).
    expect(meetingNotesOf(preferences.value), {'m1': id});
    expect(pickSynced(preferences.value.toJson())[meetingNotesKey], {'m1': id});
    expect(d.device.kept.read<Object?>(pendingKey, null, (raw) => raw), [id]);
    expect(d.meet.takes, isEmpty);
    expect(d.meet.calls, ['GET meet/takes', 'GET meet/takes/$takeId', 'DELETE meet/takes/$takeId']);
  });

  test('a take filed already is not filed twice: a pass cut short, or a second device, writes one note', () async {
    final d = await made();
    await recorded(d);
    final phone = FakeMeetDevice();
    expect(await syncMeet(context(d, device: phone)), 1);
    // The service never heard: the take is there again.
    await recorded(d);
    expect(await syncMeet(context(d, device: phone)), 0);
    expect(d.device.notes.held, hasLength(1));
    expect(phone.writeUps, hasLength(1));
    expect(d.meet.takes, isEmpty);
    expect(d.meet.calls.where((c) => c.startsWith('GET meet/takes/')), hasLength(1), reason: 'a filed take is not fetched again');
  });

  test('a take filed by a build that kept no meeting against it has its meeting kept the next time it is seen', () async {
    final d = await made();
    await recorded(d);
    final id = meetNoteId(takeId);
    d.device.keep(id, '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n');
    preferences.update((was) => was.copyWith(meetings: {id: 1792159200000}));
    expect(await syncMeet(context(d, device: FakeMeetDevice())), 0);
    expect(meetingNotesOf(preferences.value), {'m1': id});
    expect(d.meet.takes, isEmpty);
  });

  group('which note a meeting became', () {
    const start = 1792159200000;
    MeetBooking booking(String id, String state, {int at = start}) => MeetBooking.fromJson({'id': id, 'title': 'T', 'startsAt': at, 'endsAt': at + 3600000, 'state': state})!;
    Note ghost(String id) => Note(id: id, body: '# Retro\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n', createdAt: 0, updatedAt: 0);
    Note mine(String id) => Note(id: id, body: '# Meeting, 18 Oct 14:02\n\nMy own recording.\n', createdAt: 0, updatedAt: 0);

    test('the one kept against it, while it is still here', () {
      final notes = {'n': ghost('n')};
      expect(meetingNoteFor(booking('a', 'done'), filed: {'a': 'n'}, meetings: const {}, notes: notes), 'n');
      expect(meetingNoteFor(booking('a', 'done'), filed: {'a': 'gone'}, meetings: const {}, notes: notes), isNull, reason: 'deleted, or in the trash');
    });

    test('kept against nothing, Ghost’s note whose recording began while a meeting done was on, the nearest', () {
      final notes = {'early': ghost('early'), 'near': ghost('near'), 'own': mine('own'), 'later': ghost('later'), 'other': ghost('other')};
      final meetings = {'early': start - 30 * 60000, 'near': start + 60000, 'own': start, 'later': start + 2 * 3600000, 'other': start + 30000};
      expect(meetingNoteFor(booking('a', 'done'), filed: {'b': 'other'}, meetings: meetings, notes: notes), 'near', reason: 'a person’s own recording, and one kept against another meeting, are not it');
      expect(meetingNoteFor(booking('a', 'in_call'), filed: const {}, meetings: meetings, notes: notes), isNull, reason: 'only a meeting that is done has a note');
      expect(meetingNoteFor(booking('a', 'done', at: start + 10 * 3600000), filed: const {}, meetings: meetings, notes: notes), isNull, reason: 'none while it was on');
    });

    test('the map keeps only meetings whose notes are still meetings', () {
      var prefs = const Preferences(meetings: {'n1': 1, 'n2': 2});
      prefs = withMeetingNote(prefs, 'a', 'n1');
      prefs = withMeetingNote(prefs, 'b', 'n2');
      expect(meetingNotesOf(prefs), {'a': 'n1', 'b': 'n2'});
      prefs = withMeetingNote(prefs.copyWith(meetings: const {'n2': 2, 'n3': 3}), 'c', 'n3');
      expect(meetingNotesOf(prefs), {'b': 'n2', 'c': 'n3'});
      expect(withMeetingNote(prefs, '', 'n9'), same(prefs));
    });
  });

  test('the take stays on the service when its note could not be written', () async {
    final d = await made();
    await recorded(d);
    final ctx = context(d, device: FakeMeetDevice());
    final failing = MeetPassContext(token: ctx.token, api: ctx.api, crypto: ctx.crypto, pair: ctx.pair, notes: _Refusing(), prefs: ctx.prefs, kept: ctx.kept, now: ctx.now, device: ctx.device);
    await expectLater(syncMeet(failing), throwsA(isA<StateError>()));
    expect(d.meet.takes.keys, [takeId]);
  });

  test('a device that cannot keep the sound leaves the take a day for one that can, then files the captions', () async {
    final d = await made();
    await recorded(d, at: 1792161900000);
    expect(await syncMeet(context(d, now: 1792161900000 + 60000)), 0, reason: 'an iPhone, a minute after');
    expect(d.meet.takes.keys, [takeId]);
    expect(await syncMeet(context(d, device: FakeMeetDevice(ms: null), now: 1792161900000 + 3600000)), 0, reason: 'a sound this Mac could not read, an hour after');
    expect(d.meet.takes.keys, [takeId]);
    expect(await syncMeet(context(d, now: 1792161900000 + day + 1)), 1);
    final note = d.device.notes.held[meetNoteId(takeId)]!;
    expect(note.body, contains('This is from Meet’s captions: the recording could not be kept on this device.\n\n## Transcript\n\n**Sam Lee:** Good morning everyone.\n\n**Daniel:** The pricing page is drafted.\n'));
    expect(note.recordingMs, isNull);
    expect(preferences.value.meetings, contains(note.id));
    expect(d.device.kept.read<Object?>(pendingKey, null, (raw) => raw), isNull, reason: 'nothing to write up');
    expect(d.meet.takes, isEmpty);
  });

  test('a take with no sound is filed from its captions at once', () async {
    final d = await made();
    await recorded(d, audio: const []);
    final phone = FakeMeetDevice();
    expect(await syncMeet(context(d, device: phone)), 1);
    expect(d.device.notes.held[meetNoteId(takeId)]!.body, contains('No sound came with it'));
    expect(phone.writeUps, isEmpty);
    expect(d.meet.takes, isEmpty);
  });

  test('a take that will not open is left for a newer app', () async {
    final d = await made();
    await recorded(d);
    final waiting = d.meet.takes[takeId]!;
    d.meet.takes[takeId] = (meeting: waiting.meeting, at: waiting.at, wrapped: waiting.wrapped, sealed: Uint8List.fromList([...waiting.sealed]..[20] ^= 1));
    expect(await syncMeet(context(d, device: FakeMeetDevice())), 0);
    expect(d.device.notes.held, isEmpty);
    expect(d.meet.takes.keys, [takeId]);
  });

  test('once the write-up has come, a later pass names the speakers and stops waiting', () async {
    final d = await made();
    await recorded(d);
    await syncMeet(context(d, device: FakeMeetDevice()));
    final id = meetNoteId(takeId);
    expect(await syncMeet(context(d, device: FakeMeetDevice())), 0, reason: 'the write-up has not come yet');
    final filed = d.device.notes.held[id]!;
    // What the write-up leaves: Whisper's words under ## Transcript, its phrases beside the note.
    d.device.notes.held[id] = Note(
      id: id,
      body: '${filed.body.trimRight()}\n\n## Transcript\n\nGood morning everyone. The pricing page is drafted.\n',
      createdAt: filed.createdAt,
      updatedAt: filed.updatedAt,
      recordingMs: 90000,
      segments: const [Segment(startMs: 0, endMs: 3000, text: 'Good morning everyone.'), Segment(startMs: 10200, endMs: 12500, text: 'The pricing page is drafted.')],
    );
    expect(await syncMeet(context(d, device: FakeMeetDevice(), now: 5)), 1);
    final named = d.device.notes.held[id]!;
    expect(named.body, endsWith('.\n\n## Transcript\n\n**Sam Lee:** Good morning everyone.\n\n**Daniel:** The pricing page is drafted.\n'));
    expect(named.body, isNot(contains('## Captions')));
    expect(named.body, isNot(contains('being written up')));
    expect((named.updatedAt, named.recordingMs, named.segments?.length), (5, 90000, 2));
    expect(d.device.kept.read<Object?>(pendingKey, null, (raw) => raw), isEmpty);
    expect(await syncMeet(context(d, device: FakeMeetDevice())), 0, reason: 'named once');
  });

  test('the sync pass runs the step before the notes, which then send the meeting on', () async {
    final d = await made();
    await recorded(d);
    final phone = FakeMeetDevice();
    meetDevice = phone;
    addTearDown(() => meetDevice = null);
    final dev = d.device;
    final engine = SyncEngine(account: AccountDoor(dev.account), api: dev.api, crypto: dev.service.crypto, keys: dev.keys, prefs: preferences, notes: dev.notes, files: dev.files, feed: dev.feed, orgs: dev.orgs, orgKeys: dev.orgKeys, kept: dev.kept, meetIn: syncMeet);
    addTearDown(engine.dispose);
    await engine.syncNow();
    expect(engine.status.value.phase, 'idle', reason: '${engine.status.value.message}');
    final id = meetNoteId(takeId);
    expect(dev.notes.held, contains(id));
    expect(phone.writeUps, [id]);
    expect(d.meet.takes, isEmpty);
    expect(dev.service.notes.keys, contains(id), reason: 'sent on, sealed, as any new note');
  });

  test('a service with no meeting routes is quiet', () async {
    final d = await made();
    d.meet.routes = false;
    expect(await syncMeet(context(d, device: FakeMeetDevice())), 0);
    expect(d.meet.calls, ['GET meet/takes']);
  });
}

/// A library that will not take a note.
class _Refusing implements LocalNotes {
  @override
  Future<List<Note>> list() async => const [];
  @override
  Future<Note?> get(String id) async => null;
  @override
  Future<Note> apply(Note note) async => throw StateError('The library is not open.');
  @override
  Future<void> remove(String id) async {}
}
