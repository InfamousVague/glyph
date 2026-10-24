// The note sync pass (lib/sync/notes.dart) between two devices on the service in memory. A port of
// `src/app/core/sync/notes.test.ts`, case for case: the rules a person would feel break - a note typed on one
// arriving on the other, an edit made on both kept twice rather than lost, a deletion never taking words written
// since, a push that lost a race merged and sent again, a blank note not sent, a note live on two devices left to
// the live session, and a recording sent once and fetched by the other.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/account/api.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart' show Preferences;
import 'package:ghost_md/core/summary_text.dart';
import 'package:ghost_md/core/versions_file.dart';
import 'package:ghost_md/sync/notes.dart';

import 'support.dart';

/// Two devices on one account.
Future<({FakeService api, Device phone, Device mac})> pair() async {
  final api = await FakeService.start(seed: testAccount);
  return (api: api, phone: deviceOf(api), mac: deviceOf(api));
}

void main() {
  setUp(forgetPictureAsks);

  group('a note on two devices', () {
    test('arrives on the other device, and so does an edit to it', () async {
      final (api: _, :phone, :mac) = await pair();
      final one = note('a', '# Groceries\n\nmilk', createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      expect(await mac.run(), Outcome(changed: 1));
      expect(said(mac.notes['a']), said(one));

      mac.notes['a'] = edited(one, '# Groceries\n\nmilk\neggs', 2);
      await mac.run();
      await phone.run();
      expect(phone.notes['a']?.body, '# Groceries\n\nmilk\neggs');
    });

    test('does not come back to the device that wrote it as a change', () async {
      final (api: _, :phone, mac: _) = await pair();
      phone.notes['a'] = note('a', 'words');
      await phone.run();
      expect(await phone.run(), Outcome());
    });

    test('keeps both versions when both devices changed the words, the other device’s keeping the id', () async {
      final (api: _, :phone, :mac) = await pair();
      final one = note('a', 'shared', createdAt: 1, updatedAt: 1, path: 'Inbox/shared.md', recordingMs: 900);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      phone.notes['a'] = edited(one, 'the phone’s words', 2);
      mac.notes['a'] = edited(one, 'the Mac’s words', 3);
      await phone.run();
      expect((await mac.run()).conflicts, 1);

      expect(mac.notes['a']?.body, 'the phone’s words');
      final copy = mac.notes.values.firstWhere((n) => n.id != 'a');
      expect(copy.body, 'the Mac’s words');
      // The copy is the words: its recording is filed under the note's id, which the other version keeps.
      expect((copy.recordingMs, copy.segments, copy.path), (null, null, null));
      // And the copy reaches the phone too, so neither device loses a word.
      await phone.run();
      expect(bodies(phone), ['the Mac’s words', 'the phone’s words']);
    });

    test('takes the other device’s pin or archive without a copy, when only those changed on both', () async {
      final (api: _, :phone, :mac) = await pair();
      final one = note('a', 'words', createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      phone.notes['a'] = one.copyWith(starred: true);
      mac.notes['a'] = one.copyWith(archivedAt: () => 5);
      await phone.run();
      expect((await mac.run()).conflicts, 0);
      expect(mac.notes.length, 1);
      expect(mac.notes['a']?.starred, isTrue);
    });
  });

  group('a deletion', () {
    test('takes the note off the other device when it had not changed there', () async {
      final (api: _, :phone, :mac) = await pair();
      phone.notes['a'] = note('a', 'words');
      await phone.run();
      await mac.run();
      phone.notes.remove('a');
      await phone.run();
      expect((await mac.run()).changed, 1);
      expect(mac.notes.containsKey('a'), isFalse);
    });

    test('never takes words written since on the other device: they stand, and come back to the first', () async {
      final (api: _, :phone, :mac) = await pair();
      final one = note('a', 'words', createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      phone.notes.remove('a');
      await phone.run();
      mac.notes['a'] = edited(one, 'words written after', 4);
      await mac.run();
      expect(mac.notes['a']?.body, 'words written after');
      await phone.run();
      expect(phone.notes['a']?.body, 'words written after');
    });
  });

  group('a push that lost a race', () {
    /// The Mac, with [meanwhile] run by another device just before the Mac's first write of note `a` reaches the
    /// service: after its pull, so the push is refused with what won.
    Future<({FakeService api, Device phone, Device mac})> racing(Future<void> Function(FakeService api) meanwhile) async {
      final api = await FakeService.start(seed: testAccount);
      var raced = false;
      Future<FetchResponse> fetcher(FetchRequest request) async {
        if (!raced && request.method == 'PUT' && request.url.path.endsWith('/v1/notes/a')) {
          raced = true;
          await meanwhile(api);
        }
        return api.fetcher(request);
      }

      return (api: api, phone: deviceOf(api), mac: deviceOf(api, fetcher: fetcher));
    }

    test('keeps its own words as a copy when what won changed them too, and sends the copy on the next pass', () async {
      final one = note('a', 'first', createdAt: 1, updatedAt: 1);
      final (:api, :phone, :mac) = await racing((service) => service.deviceWrites(edited(one, 'written elsewhere', 2)));
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      mac.notes['a'] = edited(one, 'the Mac’s edit', 3);
      expect((await mac.run()).conflicts, 1);
      expect(mac.notes['a']?.body, 'written elsewhere');
      expect(bodies(mac), contains('the Mac’s edit'));
      await mac.run();
      await phone.run();
      expect(bodies(phone), ['the Mac’s edit', 'written elsewhere']);
      expect(api.notes.length, 2);
    });

    test('sends its edit again from the deletion’s revision when what won was a deletion', () async {
      final one = note('a', 'first', createdAt: 1, updatedAt: 1);
      final (:api, :phone, :mac) = await racing((service) async {
        await apiOf(service).call('DELETE', 'notes/a', token: service.signedIn(), body: {'base': service.notes['a']!.rev});
      });
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      mac.notes['a'] = edited(one, 'the Mac’s edit', 3);
      api.calls.clear();
      await mac.run();
      expect(api.calls.where((call) => call == 'PUT notes/a'), hasLength(2));
      expect(((await api.stored('a'))?['note'] as Map?)?['body'], 'the Mac’s edit');
      await phone.run();
      expect(phone.notes['a']?.body, 'the Mac’s edit');
    });
  });

  group('what is not sent', () {
    test('a note opened and left empty, until it has words', () async {
      final (:api, :phone, :mac) = await pair();
      phone.notes['a'] = note('a', '   ');
      await phone.run();
      expect(api.notes.containsKey('a'), isFalse);
      phone.notes['a'] = note('a', 'now words');
      await phone.run();
      await mac.run();
      expect(mac.notes['a']?.body, 'now words');
    });

    test('a note live on two devices right now, neither pushed nor merged until the session ends', () async {
      final (:api, :phone, :mac) = await pair();
      final live = <String>{};
      final one = note('a', 'words', createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      live.add('a');
      phone.notes['a'] = edited(one, 'typed live', 2);
      final before = api.notes['a']?.rev;
      await phone.run(sharedLive: live.contains);
      expect(api.notes['a']?.rev, before);
      await api.deviceWrites(edited(one, 'from a third device', 3));
      await phone.run(sharedLive: live.contains);
      expect(phone.notes['a']?.body, 'typed live');
      live.remove('a');
      await phone.run(sharedLive: live.contains);
      expect(api.notes['a']?.rev, isNot(before));
    });
  });

  group('a versions file', () {
    String keep(String? file, String text, int at, [String? label]) => withVersion(file, 'a', text, at: at, by: 'matt', label: label)!;
    List<String> texts(Device device) => [for (final v in readFile(device.versions['a'] ?? '')?.versions ?? const <Version>[]) v.text];

    test('goes with its note and is fetched by the other device', () async {
      final (:api, :phone, :mac) = await pair();
      phone.notes['a'] = note('a', 'one', createdAt: 1, updatedAt: 1);
      phone.keepVersions('a', keep(null, 'one', 1));
      await phone.run();
      expect(api.files.containsKey(fileId(FileKind.versions, 'a')), isTrue);
      expect(phone.owed, isEmpty);
      await mac.run();
      expect(texts(mac), ['one']);
    });

    test('goes on its own when a version is named by hand, with no change to the words', () async {
      final (api: _, :phone, :mac) = await pair();
      phone.notes['a'] = note('a', 'one', createdAt: 1, updatedAt: 1);
      phone.keepVersions('a', keep(null, 'one', 1));
      await phone.run();
      await mac.run();
      phone.keepVersions('a', keep(phone.versions['a'], 'one', 2, 'Sent to Sam'));
      await phone.run();
      expect(phone.owed, isEmpty);
      // The words did not move, and the note went again with its file, so the Mac fetched the name with it.
      await mac.run();
      expect(readFile(mac.versions['a']!)!.versions[0].label, 'Sent to Sam');
      phone.notes['a'] = edited(phone.notes['a']!, 'one\ntwo', 3);
      phone.keepVersions('a', keep(phone.versions['a'], 'one\ntwo', 3));
      await phone.run();
      await mac.run();
      expect([for (final v in readFile(mac.versions['a']!)!.versions) (v.text, v.label)], [('one', 'Sent to Sam'), ('one\ntwo', null)]);
    });

    test('kept on both devices at once is one timeline on both, with every version of each', () async {
      final (api: _, :phone, :mac) = await pair();
      phone.notes['a'] = note('a', 'one', createdAt: 1, updatedAt: 1);
      phone.keepVersions('a', keep(null, 'one', 1));
      await phone.run();
      await mac.run();
      // Each keeps a version of its own before hearing of the other's.
      phone.keepVersions('a', keep(phone.versions['a'], 'one\nphone', 5));
      mac.keepVersions('a', keep(mac.versions['a'], 'one\nmac', 4));
      await phone.run();
      await mac.run();
      await phone.run();
      expect(texts(mac), ['one', 'one\nmac', 'one\nphone']);
      expect(texts(phone), texts(mac));
    });
  });

  group('a recording', () {
    test('goes with its note, once, and is fetched by the other device', () async {
      final (:api, :phone, :mac) = await pair();
      final tape = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3]);
      final one = note('a', 'spoken', createdAt: 1, updatedAt: 1, recordingMs: 1200);
      phone.notes['a'] = one;
      phone.tapes['a'] = tape;
      await phone.run();
      final id = fileId(FileKind.recording, 'a')!;
      expect(api.files.containsKey(id), isTrue);
      await mac.run();
      expect(mac.tapes['a'], tape);

      // An edit to the words sends the note again, and not the recording, whose bytes did not move.
      api.calls.clear();
      phone.notes['a'] = edited(one, 'spoken, and edited', 2);
      await phone.run();
      expect(api.calls, contains('PUT notes/a'));
      expect(api.calls.any((call) => call.startsWith('PUT recordings/$id')), isFalse);
      expect(mark(phone.notes['a']!), phone.state.notes['a']?.mark);
    });
  });

  group('a recording that stays on this device', () {
    final tape = Uint8List.fromList([82, 73, 70, 70, 1, 2, 3]);

    test('is one over the service’s limit, decided from its length without reading a byte: the note goes with its phrases and no digest', () async {
      final (:api, :phone, :mac) = await pair();
      // Two hours and a half is over it; a two-hour meeting is not (GHST-112: 35 minutes was, until 2026-10-23).
      const forty = 150 * 60000;
      expect(recordingBytes(forty), greaterThan(recordingSyncLimit));
      expect(recordingStaysHere('a', forty, const {}, syncMeetingRecordings: false), isTrue);
      expect(recordingStaysHere('a', 120 * 60000, const {}, syncMeetingRecordings: false), isFalse);
      expect(recordingStaysHere('a', 40 * 60000, const {}, syncMeetingRecordings: false), isFalse);
      expect(longestSyncedSaid, '2 h 19 min');
      // And given the time a two-hour meeting takes at a megabit a second, where five minutes gave up on it.
      expect(fileWaitFor(recordingBytes(120 * 60000)), greaterThan(const Duration(minutes: 30)));
      const segments = [Segment(text: 'a long one', startMs: 0, endMs: 900)];
      phone.notes['a'] = note('a', 'a long one', createdAt: 1, updatedAt: 1, recordingMs: forty, segments: segments);
      phone.tapes['a'] = tape;
      await phone.run();
      expect(phone.files.tapeReads, 0);
      expect(api.calls.any((call) => call.startsWith('PUT recordings/')), isFalse);
      await mac.run();
      expect(mac.notes['a']?.recordingMs, forty);
      expect(mac.notes['a']?.segments, segments);
      expect(mac.tapes.containsKey('a'), isFalse);
    });

    test('is a meeting’s while meeting recordings stay on the phone, and goes once the setting says so', () async {
      final (:api, :phone, :mac) = await pair();
      phone.notes['m'] = note('m', '# Meeting, 26 Sep 14:05', createdAt: 1, updatedAt: 1, recordingMs: 60000);
      phone.tapes['m'] = tape;
      await phone.run(meetings: {'m': 1}, syncMeetingRecordings: false);
      expect(api.files.containsKey(fileId(FileKind.recording, 'm')), isFalse);
      await mac.run();
      expect(mac.notes['m']?.recordingMs, 60000);
      expect(mac.tapes.containsKey('m'), isFalse);
      // Switched on: the next pass sends it, though the words did not change.
      await phone.run(meetings: {'m': 1}, syncMeetingRecordings: true);
      expect(api.files.containsKey(fileId(FileKind.recording, 'm')), isTrue);
      await mac.run();
      expect(mac.tapes['m'], tape);
      // A recording that is not a meeting's goes as it always did, setting or no setting.
      expect(
        stayedHere([note('m', '', recordingMs: 60000), note('r', '', recordingMs: 60000), note('big', '', recordingMs: 150 * 60000)], meetings: {'m': 1}, syncMeetingRecordings: false),
        2,
      );
    });

    test('is not a meeting’s by default: a meeting’s audio goes to the other devices unless the switch is off (GHST-112)', () async {
      final (:api, :phone, :mac) = await pair();
      phone.notes['m'] = note('m', '# Meeting, 23 Oct 10:00', createdAt: 1, updatedAt: 1, recordingMs: 60000);
      phone.tapes['m'] = tape;
      // The app's own default, and a context handed no switch at all, alike.
      expect(Preferences.defaults.syncMeetingRecordings, isTrue);
      await phone.run(meetings: {'m': 1});
      expect(api.files.containsKey(fileId(FileKind.recording, 'm')), isTrue);
      await mac.run();
      expect(mac.tapes['m'], tape);
      expect(stayedHere([note('m', '', recordingMs: 60000)], meetings: {'m': 1}, syncMeetingRecordings: true), 0);
    });

    test('is a meeting’s, held back only while the switch is off, and the next meeting after it goes once it is on again', () async {
      final (:api, :phone, :mac) = await pair();
      phone.notes['m1'] = note('m1', '# Meeting one', createdAt: 1, updatedAt: 1, recordingMs: 60000);
      phone.tapes['m1'] = tape;
      await phone.run(meetings: {'m1': 1}, syncMeetingRecordings: false);
      expect(api.files.keys.where((id) => id.startsWith('r-')), isEmpty);
      final two = Uint8List.fromList([82, 73, 70, 70, 9, 9]);
      phone.notes['m2'] = note('m2', '# Meeting two', createdAt: 2, updatedAt: 2, recordingMs: 30000);
      phone.tapes['m2'] = two;
      await phone.run(meetings: {'m1': 1, 'm2': 2}, syncMeetingRecordings: true);
      expect(api.files.keys.where((id) => id.startsWith('r-')).toList()..sort(), [fileId(FileKind.recording, 'm1'), fileId(FileKind.recording, 'm2')]);
      await mac.run();
      expect(mac.tapes['m1'], tape);
      expect(mac.tapes['m2'], two);
    });

    test('is hashed once per length, not on every push: a ticked to-do no longer costs an hour’s audio read three times', () async {
      final (api: _, :phone, mac: _) = await pair();
      final one = note('a', 'spoken', createdAt: 1, updatedAt: 1, recordingMs: 1200);
      phone.notes['a'] = one;
      phone.tapes['a'] = tape;
      await phone.run();
      expect(phone.files.tapeReads, 1);
      final kept = phone.state.files[fileId(FileKind.recording, 'a')!]!;
      expect(kept.forMs, 1200);
      expect(kept.sha, isA<String>());
      phone.notes['a'] = edited(one, 'spoken, and edited', 2);
      await phone.run();
      expect(phone.files.tapeReads, 1);
      // The tape changed only when its length did: an Add to it.
      phone.notes['a'] = note('a', 'spoken, and edited', createdAt: 1, updatedAt: 3, recordingMs: 2400);
      phone.tapes['a'] = Uint8List.fromList([...tape, 4, 5]);
      await phone.run();
      expect(phone.files.tapeReads, 2);
      expect(phone.state.files[fileId(FileKind.recording, 'a')!]?.forMs, 2400);
    });

    test('takes the phone’s own digest where there is one, reading the bytes only to send them, and remembers a tape that was not there', () async {
      final (:api, phone: _, mac: _) = await pair();
      final asked = <String>[];
      RecordingDigest? answer = RecordingDigest('abcd' * 8);
      final phone = deviceOf(api, digest: (name) async {
        asked.add(name);
        return answer;
      });
      final one = note('a', 'spoken', createdAt: 1, updatedAt: 1, recordingMs: 1200);
      phone.notes['a'] = one;
      phone.tapes['a'] = tape;
      await phone.run();
      expect(asked, ['a']);
      expect(phone.files.tapeReads, 1);
      expect(api.files.containsKey(fileId(FileKind.recording, 'a')), isTrue);
      // Hashed at this length: not asked again, not read again.
      phone.notes['a'] = edited(one, 'spoken, and edited', 2);
      await phone.run();
      expect(asked, ['a']);
      expect(phone.files.tapeReads, 1);
      // A tape the phone says is not there is remembered at this length, and not asked about on every push.
      answer = const RecordingDigest.none();
      phone.notes['b'] = note('b', 'gone', createdAt: 1, updatedAt: 1, recordingMs: 900);
      await phone.run();
      await phone.run();
      expect(asked, ['a', 'b']);
      expect(phone.state.files[fileId(FileKind.recording, 'b')!], const FileMark(rev: 0, forMs: 900));
      // A binary that cannot say: the bytes are read and hashed here, as before.
      answer = null;
      phone.notes['c'] = note('c', 'here', createdAt: 1, updatedAt: 1, recordingMs: 900);
      phone.tapes['c'] = tape;
      await phone.run();
      expect(api.files.containsKey(fileId(FileKind.recording, 'c')), isTrue);
    });
  });

  // GHST-112; Matt, 2026-10-24: "tapes that have been transcribed on another device and summarized it should show the
  // transcript still across all devices". A write-up or a better pass rewrites the phrases after the words went, and
  // nothing a list read carries moves with them.
  group('a recording’s phrases', () {
    const live = [Segment(text: 'Go.', startMs: 0, endMs: 4060)];
    const written = [Segment(text: 'Okay, everyone is here.', startMs: 0, endMs: 3000), Segment(text: 'First, the raise.', startMs: 3000, endMs: 6000)];

    test('rewritten after the note went, go again and land on the other device', () async {
      final (api: _, :phone, :mac) = await pair();
      phone.notes['m'] = note('m', '# Meeting\n\n## Transcript\n\nGo.', createdAt: 1, updatedAt: 1, recordingMs: 60000, segments: live);
      await phone.run();
      await mac.run();
      expect(mac.notes['m']?.segments, live);
      // The write-up: the same words and length, better phrases.
      phone.notes['m'] = phone.notes['m']!.copyWith(segments: written);
      await phone.run();
      await mac.run();
      expect(mac.notes['m']?.segments, written);
      // Settled: nothing goes again.
      final before = phone.state.notes['m']!.rev;
      await phone.run();
      expect(phone.state.notes['m']!.rev, before);
    });

    test('a note that came with none keeps the ones this device has, and sends them', () async {
      final (api: _, :phone, :mac) = await pair();
      mac.notes['m'] = note('m', '# Meeting', createdAt: 1, updatedAt: 1, recordingMs: 60000);
      await mac.run();
      phone.notes['m'] = note('m', '# Meeting', createdAt: 1, updatedAt: 1, recordingMs: 60000, segments: written);
      await phone.run();
      expect(phone.notes['m']?.segments, written);
      await phone.run();
      await mac.run();
      expect(mac.notes['m']?.segments, written);
    });

    test('summarized on a device that never had them, stay where they are and go back to it', () async {
      final (api: _, :phone, :mac) = await pair();
      phone.notes['m'] = note('m', '# Meeting\n\n## Transcript\n\nOkay.', createdAt: 1, updatedAt: 1, recordingMs: 60000, segments: written);
      await phone.run();
      // The Mac had the note from a build that sent it bare, and summarizes it.
      mac.notes['m'] = note('m', '# Meeting\n\n## Summary\n\n- The raise.\n\n## Transcript\n\nOkay.', createdAt: 1, updatedAt: 2, recordingMs: 60000);
      mac.state.notes['m'] = phone.state.notes['m']!;
      await mac.run();
      await phone.run();
      expect(phone.notes['m']?.body, contains('## Summary'));
      expect(phone.notes['m']?.segments, written, reason: 'a note that came with none keeps the phrases here');
      await mac.run();
      expect(mac.notes['m']?.segments, written, reason: 'and the device that summarized it has them now');
    });

    test('rewritten here and not sent yet, stand over older ones from the service', () async {
      final (api: _, :phone, :mac) = await pair();
      phone.notes['m'] = note('m', '# Meeting', createdAt: 1, updatedAt: 1, recordingMs: 60000, segments: live);
      await phone.run();
      await mac.run();
      // The Mac edits the words; the phone rewrites the phrases before it hears of that.
      mac.notes['m'] = edited(mac.notes['m']!, '# Meeting\n\nAgenda', 2);
      await mac.run();
      phone.notes['m'] = phone.notes['m']!.copyWith(segments: written);
      await phone.run();
      expect(phone.notes['m']?.body, '# Meeting\n\nAgenda');
      expect(phone.notes['m']?.segments, written);
      await mac.run();
      expect(mac.notes['m']?.segments, written);
    });

    test('are not read again for a note edited longer ago than the window', () async {
      final (api: _, :phone, mac: _) = await pair();
      phone.notes['m'] = note('m', '# Meeting', createdAt: 1, updatedAt: 1, recordingMs: 60000, segments: live);
      await phone.run();
      final rev = phone.state.notes['m']!.rev;
      phone.clock = 1 + phrasesWindow.inMilliseconds;
      phone.notes['m'] = phone.notes['m']!.copyWith(segments: written);
      await phone.run();
      expect(phone.state.notes['m']!.rev, rev);
    });

    test('a fingerprint says how many and what, and nothing for a note with none', () {
      expect(phrasesMark(note('a', '', recordingMs: 900)), isNull);
      expect(phrasesMark(note('a', '', recordingMs: 900, segments: const [])), isNull);
      expect(phrasesMark(note('a', '', segments: live)), isNull);
      expect(phrasesMark(note('a', '', recordingMs: 900, segments: live)), startsWith('1-'));
      expect(phrasesMark(note('a', '', recordingMs: 900, segments: written)), isNot(phrasesMark(note('b', 'other', recordingMs: 900, segments: live))));
      expect(phrasesMark(note('a', '', recordingMs: 900, segments: written)), phrasesMark(note('b', 'other', recordingMs: 60000, segments: written)));
      expect(NoteMark.fromJson(const NoteMark(rev: 3, mark: 'm', phrases: '2-x').toJson()), const NoteMark(rev: 3, mark: 'm', phrases: '2-x'));
      expect(NoteMark.fromJson({'rev': 3, 'mark': 'm'}), const NoteMark(rev: 3, mark: 'm'));
    });
  });

  group('one note that cannot be sent', () {
    test('is counted with why, and the others still go; it is sent again next time', () async {
      final (:api, phone: _, mac: _) = await pair();
      var failing = true;
      Future<FetchResponse> fetcher(FetchRequest request) async {
        if (failing && request.method == 'PUT' && request.url.path.endsWith('/notes/b')) return FetchResponse.json(413, {'error': 'That note is too big.'});
        return api.fetcher(request);
      }

      final phone = deviceOf(api, fetcher: fetcher);
      for (final id in ['a', 'b', 'c']) {
        phone.notes[id] = note(id, 'words $id', createdAt: 1, updatedAt: 1);
      }
      final first = await phone.run();
      expect((first.unsent, first.reason), (1, 'That note is too big.'));
      // The refused one never reached the service; the ones after it did.
      expect(api.calls.where((call) => call.startsWith('PUT notes/')), ['PUT notes/a', 'PUT notes/c']);
      failing = false;
      final second = await phone.run();
      expect((second.unsent, second.reason), (0, null));
      expect(api.calls.where((call) => call.startsWith('PUT notes/')).last, 'PUT notes/b');
    });

    test('is not a lapsed session, which still ends the pass', () async {
      final (:api, phone: _, mac: _) = await pair();
      Future<FetchResponse> fetcher(FetchRequest request) async {
        if (request.method == 'PUT' && request.url.path.contains('/notes/')) return FetchResponse.json(401, {'error': 'Sign in again.'});
        return api.fetcher(request);
      }

      final phone = deviceOf(api, fetcher: fetcher);
      phone.notes['a'] = note('a', 'words', createdAt: 1, updatedAt: 1);
      await expectLater(phone.run(), throwsA(isA<ApiError>().having((e) => e.status, 'status', 401)));
    });
  });

  group('a summary on both devices', () {
    test('keeps one note, this device’s section on the other’s words, and no copy', () async {
      final (api: _, :phone, :mac) = await pair();
      final one = note('a', '# Plan\n\nwords', createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      const mine = '## Summary\nThe phone’s line.\n\n- One.';
      const theirs = '## Summary\nThe Mac’s line.\n\n- Two.';
      phone.notes['a'] = edited(one, withSummary(one.body, mine), 2);
      mac.notes['a'] = edited(one, withSummary(one.body, theirs), 3);
      await phone.run();
      final outcome = await mac.run();
      expect((outcome.conflicts, outcome.changed), (0, 1));
      expect(mac.notes.length, 1);
      expect(mac.notes['a']?.body, withSummary(one.body, theirs));
      // The merged note is what the Mac sends next, so the phone comes to hold it too.
      await phone.run();
      expect(phone.notes['a']?.body, withSummary(one.body, theirs));
      expect(phone.notes.length, 1);
    });
  });

  group('a notebook on two devices', () {
    const diary = '---\ntitle: "Diary"\nbook: true\njournal: true\n---\n# Diary\n\nOn the train, mostly.\n\n- [[2026-09-27 21.40]]\n';

    test('keeps one note when both added a line to its index: theirs, and this device’s line after the one it followed', () async {
      final (api: _, :phone, :mac) = await pair();
      final one = note('a', diary, createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      phone.notes['a'] = edited(one, '$diary- [[2026-09-28 08.10]]\n', 2);
      mac.notes['a'] = edited(one, '$diary- [[2026-09-28 14.05]]\n', 3);
      await phone.run();
      final outcome = await mac.run();
      expect((outcome.conflicts, outcome.changed), (0, 1));
      expect(mac.notes.length, 1);
      // The Mac's line goes after the line it followed on the Mac; a journal's view orders by time whatever the
      // lines say.
      final merged = '${diary.replaceFirst('- [[2026-09-27 21.40]]\n', '- [[2026-09-27 21.40]]\n- [[2026-09-28 14.05]]\n')}- [[2026-09-28 08.10]]\n';
      expect(mac.notes['a']?.body, merged);
      // What the Mac merged is what it sends next, so the phone holds it too.
      await phone.run();
      expect(phone.notes['a']?.body, merged);
      expect(phone.notes.length, 1);
    });

    test('merges the first line two devices each added to an empty index too', () async {
      final (api: _, :phone, :mac) = await pair();
      const empty = '---\ntitle: "Log"\nbook: true\njournal: true\n---\n# Log\n\n';
      final one = note('a', empty, createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      phone.notes['a'] = edited(one, '$empty- [[One]]\n', 2);
      mac.notes['a'] = edited(one, '$empty- [[Two]]\n', 3);
      await phone.run();
      expect((await mac.run()).conflicts, 0);
      expect(mac.notes['a']?.body, '$empty- [[One]]\n- [[Two]]\n');
    });

    test('still keeps a copy when the words around the index changed on both sides', () async {
      final (api: _, :phone, :mac) = await pair();
      final one = note('a', diary, createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      phone.notes['a'] = edited(one, diary.replaceFirst('On the train, mostly.', 'On the bus.'), 2);
      mac.notes['a'] = edited(one, '$diary- [[2026-09-28 14.05]]\n', 3);
      await phone.run();
      expect((await mac.run()).conflicts, 1);
    });

    test('reads the blank lines round the index as one, however many a line taken out left', () {
      const head = '---\ntitle: "Log"\nbook: true\njournal: true\n---\n# Log\n\n';
      // Here a line was added; there the only line was taken out by hand, and the blank lines either side of it
      // kept.
      final merged = mergedIndex('$head- [[A]]\n- [[B]]\n\nAfter the list.\n', '$head\n\n\nAfter the list.\n');
      expect(merged, isNotNull);
      expect(merged, contains('- [[B]]'));
    });

    test('merges only notebooks: a note with a list of links changed on both sides is kept twice', () async {
      final (api: _, :phone, :mac) = await pair();
      const list = '# Reading\n\n- [[One]]\n';
      final one = note('a', list, createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      phone.notes['a'] = edited(one, '$list- [[Two]]\n', 2);
      mac.notes['a'] = edited(one, '$list- [[Three]]\n', 3);
      await phone.run();
      expect((await mac.run()).conflicts, 1);
    });
  });

  // A note filed in an organization's workspace is the team's (docs/SHARED.md, S1): the organization channel carries
  // it, not this feed.
  group('a team’s note and the account’s feed', () {
    test('is deleted from the feed once it is the team’s, and a row of it in the feed is passed over', () async {
      final (api: _, :phone, :mac) = await pair();
      phone.notes['a'] = note('a', '# Roadmap');
      await phone.run();
      await mac.run();
      expect(mac.notes['a']?.body, '# Roadmap');
      // Filed in a team on the phone: the account's row goes, so the mac takes the note from the team instead.
      final team = {'a'};
      phone.notes['a'] = edited(phone.notes['a']!, '# Roadmap\n- for the team', 5);
      await phone.run(teamNote: team.contains);
      expect(phone.state.notes['a'], isNull);
      await mac.run();
      expect(mac.notes.containsKey('a'), isFalse);
      // On the mac the note is the team's too now (the organization channel brought it): the deletion, and any row
      // of it the feed still holds, are passed over, and the note is not sent as the account's own.
      mac.notes['a'] = note('a', '# Roadmap\n- for the team');
      await mac.run(teamNote: team.contains);
      expect(mac.notes['a']?.body, '# Roadmap\n- for the team');
      expect(mac.state.notes['a'], isNull);
      // Nothing of it was sent again: the feed holds one row, the deletion.
      expect(phone.state.notes['a'], isNull);
    });
  });

  group('this device’s own notes are never applied from the list', () {
    test('a copy kept for a conflict is the note as its file has it, phrases and all, not as the list has it', () async {
      // The library's list has no phrases and no formatted version (docs/STAGE3.md, the first trap): the pass asks
      // `get` before it applies a note of this device's own.
      final (api: _, :phone, :mac) = await pair();
      final one = note('a', 'shared', createdAt: 1, updatedAt: 1);
      phone.notes['a'] = one;
      await phone.run();
      await mac.run();
      phone.notes['a'] = edited(one, 'the phone’s words', 2);
      const phrases = [Segment(text: 'the Mac’s words', startMs: 0, endMs: 700)];
      final whole = Note(id: 'a', body: 'the Mac’s words', createdAt: 1, updatedAt: 3, segments: phrases, formatted: 'The Mac’s words.', formattedFor: 9);
      final listing = _ListsBare(mac.local, {'a': whole});
      await phone.run();
      await syncNotes(SyncContext(token: mac.token, key: mac.key, notes: listing, files: mac.files, state: mac.state, save: mac.save, api: mac.api, crypto: mac.crypto));
      final copy = mac.notes.values.firstWhere((n) => n.id != 'a');
      expect((copy.body, copy.formatted, copy.formattedFor), ('the Mac’s words', 'The Mac’s words.', 9));
    });
  });
}

/// A device's notes as the library gives them: whole from `get`, and without what only `get` answers from `list`.
class _ListsBare implements LocalNotes {
  _ListsBare(this._under, this._whole) {
    for (final entry in _whole.entries) {
      _under.held[entry.key] = entry.value;
    }
  }
  final DeviceNotes _under;
  final Map<String, Note> _whole;

  @override
  Future<List<Note>> list() async => [
        for (final n in _under.held.values)
          Note(id: n.id, body: n.body, createdAt: n.createdAt, updatedAt: n.updatedAt, starred: n.starred, archivedAt: n.archivedAt, recordingMs: n.recordingMs, formattedFor: n.formattedFor, path: n.path),
      ];

  @override
  Future<Note?> get(String id) => _under.get(id);

  @override
  Future<Note> apply(Note note) => _under.apply(note);

  @override
  Future<void> remove(String id) => _under.remove(id);
}
