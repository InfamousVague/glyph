// A shared meeting (lib/share/share_audio.dart): its turns as the page draws them, its recording sealed a part at a
// time under the share's key and read back as the page reads it, and the share following the meeting's edits with the
// words alone, the recording going again only when it grew (Matt, 2026-10-29: "Update the web version of the meeting
// transcripts to include the casette tape and the per user transcript so we can listen along").

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/bytes.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/share/share.dart';
import 'package:ghost_md/share/share_audio.dart';
import 'package:ghost_md/tapes/tape_art.dart' show tapeHue;

import 'support.dart';

/// A meeting Ghost was in, written up: its transcript timed and named, and Whisper's phrases beside it.
Note meeting(String id, {int ms = 90000, List<Segment>? segments, String? transcript}) => Note(
      id: id,
      body: '# Launch sync\n\nGhost was in this meeting on 18 Oct, 14:00 to 14:45.\n\n## Summary\nWhat the call settled.\n\n- Launch moves.\n\n${transcript ?? '## Transcript\n\n**Sam Lee (0:00):** Good morning everyone, let us start with the launch. The checklist is first.\n\n**Ana (0:05):** Thanks, the pricing page is drafted.'}\n',
      createdAt: 1000,
      updatedAt: 1000,
      recordingMs: ms,
      segments: segments ?? const [Segment(startMs: 0, endMs: 2000, text: ' Good morning everyone, let us start with the launch.'), Segment(startMs: 2000, endMs: 4800, text: 'The checklist is first.'), Segment(startMs: 5000, endMs: 7000, text: 'Thanks, the pricing page is drafted.')],
    );

/// This device, with a meeting recorded on it.
class Here {
  Here(this.service, {ShareRecordings? recordings, PreferencesStore? prefs}) : prefs = prefs ?? (PreferencesStore()..startWithoutStorage()) {
    account = SignedAccount();
    account.signIn(service);
    shares = Shares(account: account, api: apiOf(service), crypto: service.crypto, prefs: this.prefs, pictures: Pictures(), listNotes: () async => notes, recordings: recordings);
  }
  final FakeService service;
  final PreferencesStore prefs;
  final List<Note> notes = [];
  late final SignedAccount account;
  late final Shares shares;

  List<String> get puts => [for (final call in service.calls) if (call.startsWith('PUT shares/') && !call.contains('/audio')) call];
  List<String> get parts => [for (final call in service.calls) if (call.startsWith('PUT shares/') && call.contains('/audio/')) call];

  ShareEntry entry(String noteId) => prefs.value.shares[noteId]!;

  /// What the service holds for a note's share, opened as a reader would.
  Future<Shared> held(String noteId) => openShare(service.crypto, service.shares[entry(noteId).id]!.blob, entry(noteId).key);

  /// The recording the service holds for a note's share, opened as the page opens it, by what the words name.
  Future<Uint8List> heard(String noteId) async {
    final words = (await held(noteId)).meeting!['audio'];
    final audio = SharedAudio.fromJson(words)!;
    final framed = (await apiOf(service).callBytes('GET', 'shares/${entry(noteId).id}/audio')).bytes;
    return openShareAudio(service.crypto, framed, entry(noteId).key, audio);
  }
}

void main() {
  group('a meeting’s turns', () {
    test('are its phrases, named from its transcript, a speaker’s run of them one turn', () {
      final read = meetingTurns(meeting('m1'));
      expect(read.speakers, ['Sam Lee', 'Ana']);
      expect(read.turns, hasLength(2));
      expect(read.turns[0].speaker, 0);
      expect(read.turns[0].phrases, [(startMs: 0, endMs: 2000, text: 'Good morning everyone, let us start with the launch.'), (startMs: 2000, endMs: 4800, text: 'The checklist is first.')]);
      expect(read.turns[1].speaker, 1);
      expect(read.turns[1].phrases.single, (startMs: 5000, endMs: 7000, text: 'Thanks, the pricing page is drafted.'));
    });

    test('are a phrase each where nobody is named: a recording made on the device', () {
      final read = meetingTurns(meeting('m2', transcript: '## Transcript\n\nGood morning everyone, let us start with the launch. The checklist is first. Thanks, the pricing page is drafted.'));
      expect(read.speakers, isEmpty);
      expect([for (final turn in read.turns) (turn.speaker, turn.phrases.single.startMs)], [(-1, 0), (-1, 2000), (-1, 5000)]);
    });

    test('are the written paragraphs where the phrases do not carry the words, timed to the next and the end, or plain', () {
      final timed = meetingTurns(meeting('m3', segments: const [], transcript: '## Transcript\n\n**Sam Lee (0:04):** Good morning.\n\nMore of it.\n\n**groups (1:02):** Thanks.'));
      expect(timed.speakers, ['Sam Lee'], reason: 'one of Meet’s icons is no name');
      expect([for (final turn in timed.turns) (turn.speaker, turn.phrases.single)], [
        (0, (startMs: 4000, endMs: 62000, text: 'Good morning. More of it.')),
        (-1, (startMs: 62000, endMs: 90000, text: 'Thanks.')),
      ]);
      final plain = meetingTurns(meeting('m4', segments: const [], transcript: '## Transcript\n\n**Sam Lee:** Good morning.\n\nThanks.'));
      expect([for (final turn in plain.turns) (turn.speaker, turn.phrases.single)], [
        (0, (startMs: -1, endMs: -1, text: 'Good morning.')),
        (-1, (startMs: -1, endMs: -1, text: 'Thanks.')),
      ]);
    });

    test('go to the page with how long it is, its cassette’s colour, when it was, and its recording once sent', () {
      final words = sharedMeeting(meeting('m5'), at: 77);
      expect(words['ms'], 90000);
      expect(words['hue'], tapeHue('m5'));
      expect(words['at'], 77);
      expect(words['speakers'], ['Sam Lee', 'Ana']);
      expect((words['turns'] as List).first, {
        's': 0,
        'p': [
          [0, 2000, 'Good morning everyone, let us start with the launch.'],
          [2000, 4800, 'The checklist is first.'],
        ],
      });
      expect(words.containsKey('audio'), isFalse);
      const audio = SharedAudio(upload: 'u', parts: 2, bytes: 5, mime: 'audio/wav', ms: 9, sent: '5:9');
      expect(sharedMeeting(meeting('m5'), at: 77, audio: audio)['audio'], {'upload': 'u', 'parts': 2, 'bytes': 5, 'mime': 'audio/wav', 'ms': 9, 'chunk': audioChunk});
    });
  });

  group('a shared recording', () {
    late FakeService service;
    setUp(() async => service = await FakeService.start(seed: testAccount));

    test('goes a megabyte at a time, each part sealed to its place, and opens whole with the share’s key', () async {
      final here = Here(service);
      final one = meeting('m1');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes, recording: false);
      final kept = here.entry('m1');
      final bytes = wav(audioChunk * 2 + 1234);
      final recording = ShareRecording(mime: 'audio/wav', bytes: bytes.length, read: (offset, length) async => Uint8List.sublistView(bytes, offset, offset + length));
      final seen = <double>[];
      final sent = await sendShareAudio(api: apiOf(service), token: here.account.session!.token, crypto: service.crypto, shareId: kept.id, key: kept.key, recording: recording, ms: 90000, progress: seen.add);
      expect((sent!.parts, sent.bytes, sent.mime, sent.ms, sent.sent), (3, bytes.length, 'audio/wav', 90000, '${bytes.length}:90000'));
      expect(seen, [1 / 3, 2 / 3, 1]);
      expect(here.parts, [for (var n = 0; n < 3; n += 1) 'PUT shares/${kept.id}/audio/${sent.upload}/$n']);
      // What the service holds is ciphertext: no part of it reads as the recording.
      final held = service.shareAudio[kept.id]!;
      expect(held.parts[0].sublist(29, 61), isNot(bytes.sublist(0, 32)));
      final framed = (await apiOf(service).callBytes('GET', 'shares/${kept.id}/audio')).bytes;
      expect(await openShareAudio(service.crypto, framed, kept.key, sent), bytes);
      // A part moved to another's place does not open, nor does a part of another upload, nor the words' key.
      final key = await service.crypto.importSealKey(fromBase64Url(kept.key));
      await expectLater(service.crypto.openBytes(key, held.parts[1], audioPartContext(sent.upload, 0, 3)), throwsA(anything));
      await expectLater(service.crypto.openBytes(key, held.parts[0], audioPartContext('another', 0, 3)), throwsA(anything));
      await expectLater(service.crypto.openBytes(key, held.parts[0], audioPartContext(sent.upload, 0, 2)), throwsA(anything), reason: 'the count is sealed too: a recording cut short is known');
      await expectLater(openShareAudio(service.crypto, Uint8List.sublistView(framed, 0, framed.length - held.parts[2].length - 4), kept.key, sent), throwsA(isA<FormatException>()));
    });

    test('longer than a share carries is refused before anything is read or sent', () async {
      final here = Here(service);
      final one = meeting('m1');
      here.notes.add(one);
      await here.shares.shareNote(one, here.notes, recording: false);
      final kept = here.entry('m1');
      var read = false;
      final long = ShareRecording(mime: 'audio/wav', bytes: shareAudioLimit, read: (offset, length) async => (read = true) ? Uint8List(length) : Uint8List(0));
      await expectLater(sendShareAudio(api: apiOf(service), token: here.account.session!.token, crypto: service.crypto, shareId: kept.id, key: kept.key, recording: long, ms: 1), throwsA(isA<Exception>()));
      expect(read, isFalse);
      expect(here.parts, isEmpty);
      expect(audioFits(shareAudioLimit - audioParts(shareAudioLimit) * 33), isTrue);
      expect(audioTooLong, contains('1 h 48 min'));
    });
  });

  group('a meeting’s share', () {
    late FakeService service;
    late HeldRecordings recordings;
    late Here here;
    final bytes = wav(audioChunk + 4000);

    setUp(() async {
      service = await FakeService.start(seed: testAccount);
      recordings = HeldRecordings({'m1': bytes});
      here = Here(service, recordings: recordings);
      here.prefs.update((now) => now.copyWith(meetings: {'m1': 555}));
      here.notes.add(meeting('m1'));
    });

    test('goes with its words first and the link at once, then its recording, then its words naming it', () async {
      final link = await here.shares.shareNote(here.notes[0], here.notes);
      expect(link, contains('#${here.entry('m1').id}.'));
      final first = await here.held('m1');
      expect(first.meeting!['speakers'], ['Sam Lee', 'Ana']);
      expect(first.meeting!['at'], 555);
      expect(first.meeting!.containsKey('audio'), isFalse, reason: 'the words went before the recording');
      await here.shares.audioSent('m1');
      expect(here.parts, hasLength(2));
      expect(here.puts, hasLength(2), reason: 'the words again, once it was all there');
      expect((await here.held('m1')).meeting!['audio'], containsPair('parts', 2));
      expect(await here.heard('m1'), bytes);
      expect(here.shares.recordingSent('m1'), isTrue);
      expect(here.shares.audioSending.value, isEmpty);
    });

    test('writes the words again after an edit, and never the recording, until the recording grows', () async {
      await here.shares.shareNote(here.notes[0], here.notes);
      await here.shares.audioSent('m1');
      final upload = SharedAudio.fromJson(here.entry('m1').audio)!.upload;
      here.notes[0] = here.notes[0].copyWith(body: '${here.notes[0].body}\nA line added after.\n');
      expect(await here.shares.refreshShares(), 1);
      await here.shares.audioSent('m1');
      expect(here.parts, hasLength(2), reason: 'the unchanged recording is not sent again');
      expect((await here.held('m1')).meeting!['audio'], containsPair('upload', upload));
      expect(await here.shares.refreshShares(), 0);
      // A take added: the recording is longer, and goes again whole as a new upload.
      final longer = wav(audioChunk * 2 + 10);
      recordings.held['m1'] = longer;
      here.notes[0] = Note(id: 'm1', body: here.notes[0].body, createdAt: 1000, updatedAt: 2000, recordingMs: 120000, segments: here.notes[0].segments);
      await here.shares.refreshShares();
      await here.shares.audioSent('m1');
      expect(here.parts, hasLength(5));
      final now = SharedAudio.fromJson(here.entry('m1').audio)!;
      expect((now.upload == upload, now.ms), (false, 120000));
      expect(await here.heard('m1'), longer);
    });

    test('turned off, takes the recording down and goes on without it; turned on, sends it again', () async {
      await here.shares.shareNote(here.notes[0], here.notes);
      await here.shares.audioSent('m1');
      await here.shares.shareWithRecording('m1', on: false);
      expect(service.shareAudio, isEmpty);
      expect((await here.held('m1')).meeting!.containsKey('audio'), isFalse);
      expect(here.entry('m1').toJson()['recording'], isFalse);
      expect(here.shares.sharingRecording('m1'), isFalse);
      // Kept through the settings being read again, as another device reads them, and nothing goes on a refresh.
      here.prefs.value = Preferences.fromJson(here.prefs.value.toJson());
      await here.shares.refreshShares();
      await here.shares.audioSent('m1');
      expect(here.parts, hasLength(2));
      await here.shares.shareWithRecording('m1', on: true);
      await here.shares.audioSent('m1');
      expect(here.parts, hasLength(4));
      expect(await here.heard('m1'), bytes);
    });

    test('shared with the recording left out, never sends it', () async {
      await here.shares.shareNote(here.notes[0], here.notes, recording: false);
      await here.shares.audioSent('m1');
      await here.shares.refreshShares();
      await here.shares.audioSent('m1');
      expect(here.parts, isEmpty);
      expect(recordings.reads, 0);
      expect((await here.held('m1')).meeting!['turns'], hasLength(2), reason: 'the transcript goes all the same');
    });

    test('from a device without the recording, goes on naming the one another device sent', () async {
      await here.shares.shareNote(here.notes[0], here.notes);
      await here.shares.audioSent('m1');
      final other = Here(service, prefs: here.prefs);
      other.notes.add(here.notes[0].copyWith(body: '${here.notes[0].body}\nEdited on the Mac.\n'));
      expect(await other.shares.refreshShares(), 1);
      await other.shares.audioSent('m1');
      expect((await other.held('m1')).pages.single.body, contains('Edited on the Mac.'));
      expect(await other.heard('m1'), bytes);
      expect(here.parts, hasLength(2));
    });

    test('stopped, takes its recording with it', () async {
      await here.shares.shareNote(here.notes[0], here.notes);
      await here.shares.audioSent('m1');
      await here.shares.stopSharing('m1');
      expect(service.shares, isEmpty);
      expect(service.shareAudio, isEmpty);
    });

    test('of a note that is no meeting carries no meeting, and digests as it always did', () async {
      final plain = note('n1', '# Words\n\nNo meeting.');
      here.notes.add(plain);
      await here.shares.shareNote(plain, here.notes);
      expect((await here.held('n1')).meeting, isNull);
      expect(here.entry('n1').sent, shareDigest(sharedOf(plain, here.notes)));
      expect(recordings.asked, isNot(contains('n1')));
    });

    test('too long to carry says so, and the words go without it', () async {
      final huge = _Huge();
      final long = Here(service, recordings: huge);
      long.prefs.update((now) => now.copyWith(meetings: {'m9': 1}));
      long.notes.add(meeting('m9'));
      await long.shares.shareNote(long.notes[0], long.notes);
      await long.shares.audioSent('m9');
      expect(long.shares.audioProblem('m9'), audioTooLong);
      expect(long.parts, isEmpty);
      expect(huge.reads, 0);
      expect((await long.held('m9')).meeting!['turns'], hasLength(2));
    });
  });
}

/// A recording past what a share carries, which must never be read.
class _Huge implements ShareRecordings {
  int reads = 0;
  @override
  Future<ShareRecording?> recordingOf(String noteId) async => ShareRecording(mime: 'audio/wav', bytes: shareAudioLimit + 1, read: (offset, length) async {
        reads += 1;
        return Uint8List(length);
      });
}
