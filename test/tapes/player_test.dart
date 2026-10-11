/// Why a tape did not play (`lib/tapes/player.dart` `whyNotPlayed`): its audio removed from this device by the
/// Tapes row, or left on the device that made it, or a reason nothing here knows. `src/app/tapes/useTape.test.ts`,
/// case for case; and after them what the web's hook did with its `<audio>` element and had no cases for, held here
/// over the seam: the end, a seek, a failure, another note, leaving.
///
/// What differs: `localStorage.clear()` is a fresh `MemoryStored`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/tapes/player.dart';
import 'package:glacier/glacier.dart' show HapticKind;

import 'fake_player.dart';

Note _note(String id, {int? recordingMs, List<Segment>? segments}) => Note(id: id, body: '# Trip', createdAt: 0, updatedAt: 0, recordingMs: recordingMs, segments: segments);

void main() {
  setUp(() => useStored(MemoryStored()));

  group('a tape that did not play', () {
    test('says its audio was removed when the Tapes row removed it here', () async {
      markAudioRemoved(['t1']);
      expect(await whyNotPlayed((id: 't1', recordingMs: 60000), (_) async => 200), audioRemovedLine);
    });

    test('says the recording is not on this device when its file answers 404: a meeting’s audio, or one over the sync limit', () async {
      final asked = <String>[];
      expect(
        await whyNotPlayed((id: 't2', recordingMs: 3600000), (id) async {
          asked.add(id);
          return 404;
        }),
        notOnThisDevice,
      );
      expect(asked, ['t2']);
    });

    test('otherwise only that it could not be played', () async {
      expect(await whyNotPlayed((id: 't3', recordingMs: 60000), (_) async => 500), couldNotPlay);
      expect(await whyNotPlayed((id: 't3', recordingMs: 60000), (_) async => null), couldNotPlay);
      expect(await whyNotPlayed((id: 't3', recordingMs: 60000), (_) async => throw StateError('offline')), couldNotPlay);
      // A note with no recording has no file to ask about.
      expect(await whyNotPlayed((id: 't4', recordingMs: 0), (_) async => 404), couldNotPlay);
    });
  });

  group('the tape over its player', () {
    const phrases = [Segment(text: 'Pack the tent.', startMs: 0, endMs: 1000), Segment(text: 'And the stove.', startMs: 1000, endMs: 2000)];
    void quiet([HapticKind kind = HapticKind.light]) {}

    test('loads the recording at the first Play and not before, gives Play its touch, and pauses on the second', () async {
      final player = FakeTapePlayer(lengths: {'t': 2000});
      final felt = <HapticKind>[];
      final tape = Tape(_note('t', recordingMs: 2000, segments: phrases), player: player, haptic: ([kind = HapticKind.light]) => felt.add(kind));
      expect(player.calls, isEmpty);
      await tape.toggle();
      expect(player.calls, ['load t', 'play']);
      expect(tape.playing, isTrue);
      expect(felt, [HapticKind.selection]);
      await tape.toggle();
      expect(player.calls.last, 'pause');
      expect(tape.playing, isFalse);
      tape.dispose();
    });

    test('starts from a phrase that was tapped before the first Play, and seeks the player once it has loaded', () async {
      final player = FakeTapePlayer(lengths: {'t': 2000});
      final tape = Tape(_note('t', recordingMs: 2000, segments: phrases), player: player, haptic: quiet);
      tape.seek(1000);
      expect(tape.at, 1000);
      expect(player.calls, isEmpty);
      await tape.toggle();
      expect(player.calls, ['load t', 'seek 1000', 'play']);
      tape.seek(0);
      expect(player.calls.last, 'seek 0');
      tape.dispose();
      expect(player.calls.last, 'pause');
    });

    test('says a recording that will not load could not be played, and then why', () async {
      final player = FakeTapePlayer(loadFails: true, here: false);
      final tape = Tape(_note('t', recordingMs: 2000, segments: phrases), player: player, haptic: quiet);
      final said = <String?>[];
      tape.addListener(() => said.add(tape.problem));
      await tape.toggle();
      await Future<void>.delayed(Duration.zero);
      expect(said, [couldNotPlay, notOnThisDevice]);
      expect(tape.playing, isFalse);
      // The audio the Tapes row removed says that instead.
      markAudioRemoved(['t']);
      await tape.toggle();
      await Future<void>.delayed(Duration.zero);
      expect(tape.problem, audioRemovedLine);
      tape.dispose();
    });

    test('says what the phone said when Play is refused, forgets it at the next Play, and says a break while playing', () async {
      final player = FakeTapePlayer(lengths: {'t': 2000}, playFails: StateError('The phone is on a call.'));
      final tape = Tape(_note('t', recordingMs: 2000, segments: phrases), player: player, haptic: quiet);
      await tape.toggle();
      expect(tape.problem, 'The phone is on a call.');
      player.playFails = null;
      await tape.toggle();
      expect(tape.problem, isNull);
      expect(tape.playing, isTrue);
      player.fail();
      expect(tape.playing, isFalse);
      expect(tape.problem, couldNotPlay);
      tape.dispose();
    });

    test('stops and starts over when it is handed another note, and keeps its place for the same note again', () async {
      final player = FakeTapePlayer(lengths: {'t': 2000, 'u': 5000});
      final tape = Tape(_note('t', recordingMs: 2000, segments: phrases), player: player, haptic: quiet);
      await tape.toggle();
      tape.seek(1000);
      // The same note, its recording removed and put back by Undo.
      tape.note = _note('t');
      expect(tape.length, 0);
      tape.note = _note('t', recordingMs: 2000);
      expect((tape.at, tape.playing, tape.segments), (1000, true, phrases));
      tape.note = _note('u', recordingMs: 5000, segments: const []);
      expect(player.calls.last, 'pause');
      expect((tape.length, tape.at, tape.playing, tape.segments), (5000, 0, false, const <Segment>[]));
      await tape.toggle();
      expect(player.calls.sublist(player.calls.length - 2), ['load u', 'play']);
      tape.dispose();
    });
  });
}
