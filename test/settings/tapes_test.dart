import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/settings/tapes.dart';
import 'package:ghost_md/settings/tapes_here.dart';
import 'package:ghost_md/tapes/player.dart' show markAudioRemoved;

/// The Tapes row's sums (lib/settings/tapes.dart): the room said from the tapes' lengths, which of them are on
/// this device, and which are old enough for the row to offer. The cases of `src/app/settings/tapes.ts` in
/// `RecordingPane.test.tsx` ("counts in gigabytes past one, and says when there are no tapes"), and then its
/// "counts only the audio that is on this device" over what asks each file here (lib/settings/tapes_here.dart). The
/// page's own cases are in `panes/panes_test.dart`, and the app's in `test/root/voice_test.dart`.
void main() {
  Note tape(String id, {int createdAt = 0, int? recordingMs = 1, int? archivedAt}) =>
      Note(id: id, body: '', createdAt: createdAt, updatedAt: 0, source: NoteSource.capture, recordingMs: recordingMs, archivedAt: archivedAt);

  test('counts in gigabytes past one, and never less than a megabyte once there is one', () {
    expect(tapeSize(2300000000), '2.3 GB');
    expect(tapeSize(117120000), '117 MB');
    expect(tapeSize(10), '1 MB');
    expect((tapeSize(410000000), tapeSize(200), tapeSize(1500000000)), ('410 MB', '1 MB', '1.5 GB'));
  });

  test('says the room from the lengths: 16 kHz, 16-bit, mono, so an hour is about 115 MB', () {
    expect(bytesPerMs, 16000 * 2 ~/ 1000);
    expect(tapeBytes([tape('a', recordingMs: 3600000)]), 115200000);
    // A typed note has no length, and a length that makes no sense takes no room.
    expect(tapeBytes([tape('a', recordingMs: 3600000), tape('typed', recordingMs: null), tape('odd', recordingMs: -5)]), 115200000);
    expect(tapeBytes(const []), 0);
  });

  test('counts only the tapes whose audio is here: a length, and not away', () {
    final tapes = [tape('a'), tape('b'), const Note(id: 'c', body: '', createdAt: 0, updatedAt: 0)];
    expect([for (final note in tapesHere(tapes, (id) => id == 'b')) note.id], ['a']);
    expect([for (final note in tapesHere(tapes, (_) => false)) note.id], ['a', 'b']);
  });

  test('old is more than a month, of a tape, not archived', () {
    const day = 24 * 60 * 60 * 1000;
    Note aged(String id, int days, {int? recordingMs = 60000, int? archivedAt}) => tape(id, createdAt: 100 * day - days * day, recordingMs: recordingMs, archivedAt: archivedAt);
    expect(oldMs, 30 * day);
    expect(
      [for (final note in oldTapes([aged('old', 31), aged('edge', 30), aged('typed', 40, recordingMs: 0), aged('gone', 40, archivedAt: 1)], 100 * day)) note.id],
      ['old'],
    );
  });

  group('the tapes on this device', () {
    setUp(() => useStored(MemoryStored()));

    /// Notes as the page's own test seeds them: an hour's meeting from two months ago, a minute's note from today,
    /// and a typed one.
    List<Note> seed() {
      final now = DateTime.now().millisecondsSinceEpoch;
      return [
        Note(id: 'old', body: '# Meeting, 26 Jul 14:05', createdAt: now - 60 * 24 * 60 * 60 * 1000, updatedAt: now, source: NoteSource.capture, recordingMs: 3600000),
        Note(id: 'new', body: '# Today', createdAt: now - 1000, updatedAt: now, source: NoteSource.capture, recordingMs: 60000),
        Note(id: 'typed', body: '# Typed', createdAt: now - 90 * 24 * 60 * 60 * 1000, updatedAt: now),
      ];
    }

    List<String> ids(Iterable<Note> notes) => [for (final note in notes) note.id];

    test('are every tape, where each file says it is here and where nothing can be asked', () async {
      final asked = <String>[];
      final here = TapesHere((id) async {
        asked.add(id);
        return true;
      });
      final notes = seed();
      await here.ask(notes);
      // Only a tape is asked after: a typed note has no file.
      expect(asked, ['old', 'new']);
      expect(ids(here.here(notes)), ['old', 'new']);
      expect(tapeSize(tapeBytes(here.here(notes))), '117 MB');

      final unasked = TapesHere(null);
      await unasked.ask(notes);
      expect(ids(unasked.here(notes)), ['old', 'new']);
    });

    test('count only the audio that is on this device: not what was removed, nor a synced tape whose audio stayed elsewhere', () async {
      // The Tapes row took the hour's audio away on an earlier visit; the minute's file says it is not here.
      markAudioRemoved(['old']);
      final asked = <String>[];
      var elsewhere = {'new'};
      final here = TapesHere((id) async {
        asked.add(id);
        return !elsewhere.contains(id);
      });
      final notes = seed();
      // Until its file has answered, the minute counts, as on the page until its HEAD does.
      expect(ids(here.here(notes)), ['new']);
      await here.ask(notes);
      expect(asked, ['new'], reason: 'what the row removed is not asked after');
      expect(here.here(notes), isEmpty);
      expect(tapeBytes(here.here(notes)), 0);
      expect(oldTapes(here.here(notes), DateTime.now().millisecondsSinceEpoch), isEmpty);
      // Asked again on a later visit, its audio here after all, it counts again.
      elsewhere = {};
      await here.ask(notes);
      expect(asked, ['new', 'new']);
      expect(ids(here.here(notes)), ['new']);
    });

    test('take a file that does not know, or cannot be asked, to be here', () async {
      final notes = seed();
      final unknown = TapesHere((_) async => null);
      await unknown.ask(notes);
      expect(ids(unknown.here(notes)), ['old', 'new']);
      final broken = TapesHere((id) => id == 'old' ? throw StateError('no phone') : Future<bool?>.error(StateError('no answer')));
      await broken.ask(notes);
      expect(ids(broken.here(notes)), ['old', 'new']);
    });
  });
}
