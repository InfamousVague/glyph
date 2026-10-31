// This device's stores as the pass is handed them (lib/sync/local.dart): the library's notes by the core's own
// commands, and the recordings, pictures and versions files. The last two groups are the web's own cases about its
// device files, from `src/app/core/sync/engine.test.tsx` ("asks the phone for a tape's fingerprint…", "files a
// recording that arrived by sync…"), said of `KeptFiles`.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/stored.dart';
import 'package:ghost_md/core/versions_store.dart';
import 'package:ghost_md/sync/local.dart';
import 'package:ghost_md/sync/notes.dart';

import '../library/fake_core.dart';

class _Bytes implements DeviceBytes {
  final Map<String, Uint8List> held = {};
  final List<String> written = [];

  /// What the device's digest answers, or throws.
  Object? Function() digestAnswer = () => '';

  @override
  Future<Uint8List?> read(FileKind kind, String name) async => held['${kind.name}/$name'];

  @override
  Future<void> write(FileKind kind, String name, Uint8List bytes) async {
    written.add('${kind.name}/$name');
    held['${kind.name}/$name'] = bytes;
  }

  @override
  Future<String?> recordingSha256(String name) async => digestAnswer() as String?;
}

void main() {
  group('the library’s notes', () {
    final asked = <(String, Map<String, Object?>)>[];
    Object? answer;
    Future<Object?> invoke(String command, [Map<String, Object?> args = const {}]) async {
      asked.add((command, args));
      return answer;
    }

    setUp(asked.clear);

    test('are listed, read, written and deleted by the core’s own commands', () async {
      final notes = LibraryNotes(invoke);
      answer = [
        {'id': 'a', 'body': 'words', 'createdAt': 1, 'updatedAt': 2, 'source': 'editor', 'starred': false, 'path': 'Inbox/words.md'},
      ];
      final listed = await notes.list();
      expect((listed.single.id, listed.single.path, listed.single.segments), ('a', 'Inbox/words.md', null));
      answer = {'id': 'a', 'body': 'words', 'createdAt': 1, 'updatedAt': 2, 'segments': <Object?>[], 'formatted': 'Words.'};
      expect((await notes.get('a'))?.formatted, 'Words.');
      answer = null;
      expect(await notes.get('gone'), isNull);
      await notes.remove('a');
      expect(asked.map((each) => each.$1), ['list_notes', 'get_note', 'get_note', 'delete_note']);
      expect(asked.last.$2, {'id': 'a'});
    });

    test('move a note’s file to the path the service has for its id, never copying it (a restore that lagged a filing)', () async {
      // A Library folder restored from a clone has `Inbox/Plan.md`; the account's copy of the same note was filed into
      // Work since. On the first pass the service's path wins and the file moves (apply_note, library/mod.rs; the
      // critic, docs/MARKDOWN_FIRST.md §12): one file, at the path every other device has.
      final core = FakeCore()..seed('a', '# Plan\n\nwords', path: 'Inbox/Plan.md');
      final notes = LibraryNotes(core.invoke);
      final theirs = (await notes.get('a'))!.copyWith(path: () => 'workspaces/Work/Plan.md');
      final applied = await notes.apply(theirs);
      expect(applied.path, 'workspaces/Work/Plan.md');
      expect(core.files, ['workspaces/Work/Plan.md']);
      expect((await notes.list()).length, 1);
    });

    test('write a note exactly as given, whole: its times, its phrases, its formatted version, its folder', () async {
      final notes = LibraryNotes(invoke);
      const whole = Note(
        id: 'a',
        body: 'spoken',
        createdAt: 1,
        updatedAt: 2,
        source: NoteSource.capture,
        starred: true,
        archivedAt: 3,
        recordingMs: 900,
        segments: [Segment(text: 'spoken', startMs: 0, endMs: 900)],
        formatted: 'Spoken.',
        formattedFor: 7,
        formattedModel: 'qwen3.5-4b',
        path: 'workspaces/Home/spoken.md',
      );
      answer = {'id': 'a', 'body': 'spoken', 'createdAt': 1, 'updatedAt': 2};
      await notes.apply(whole);
      expect(asked.single.$1, 'store_apply');
      expect(asked.single.$2['note'], {
        'id': 'a',
        'body': 'spoken',
        'createdAt': 1,
        'updatedAt': 2,
        'source': 'capture',
        'starred': true,
        'archivedAt': 3,
        'recordingMs': 900,
        'segments': [
          {'text': 'spoken', 'startMs': 0, 'endMs': 900},
        ],
        'formatted': 'Spoken.',
        'formattedFor': 7,
        'formattedModel': 'qwen3.5-4b',
        'path': 'workspaces/Home/spoken.md',
        'revision': 1,
      });
      // A core that wrote and did not say how is an error, not a note.
      answer = null;
      await expectLater(notes.apply(whole), throwsA(isA<CoreError>()));
    });
  });

  group('this device’s files', () {
    test('are the versions files where they live, owed until sent, and everything else as bytes', () async {
      final kept = MemoryStored();
      final versions = VersionsStore(null, kept: kept);
      final bytes = _Bytes();
      final files = KeptFiles(versions: versions, bytes: bytes);
      expect(await files.read(FileKind.versions, 'n1'), isNull);
      // A versions file from the account is not owed back to it.
      await files.write(FileKind.versions, 'n1', utf8.encode('a versions file ✓'));
      expect(utf8.decode((await files.read(FileKind.versions, 'n1'))!), 'a versions file ✓');
      expect(files.owed(), isEmpty);
      // One this device added to is, until it is sent.
      await versions.writeVersionsFile('n1', 'kept here');
      expect(files.owed(), ['n1']);
      files.settled('n1');
      expect(files.owed(), isEmpty);
      expect(bytes.written, isEmpty);

      await files.write(FileKind.recording, 'n1', Uint8List.fromList([0xfb, 0xff]));
      await files.write(FileKind.image, 'p.jpg', Uint8List.fromList([1]));
      expect(bytes.written, ['recording/n1', 'image/p.jpg']);
      expect(await files.read(FileKind.recording, 'n1'), [0xfb, 0xff]);
      expect(await files.read(FileKind.image, 'p.jpg'), [1]);
      expect(await files.read(FileKind.image, 'never.jpg'), isNull);
    });

    test('ask the device for a tape’s fingerprint, and read the file where it cannot say rather than calling it gone', () async {
      final bytes = _Bytes();
      final files = KeptFiles(versions: VersionsStore(null, kept: MemoryStored()), bytes: bytes);
      bytes.digestAnswer = () => 'ab' * 32;
      expect((await files.digest('n1'))?.sha, 'ab' * 16);
      bytes.digestAnswer = () => '';
      final none = await files.digest('n1');
      expect(none, isNotNull);
      expect(none?.sha, isNull);
      // A call that failed is not "no tape": remembered as one, the note would travel without its tape's fingerprint
      // for good.
      bytes.digestAnswer = () => throw const CoreError('the phone was busy');
      expect(await files.digest('n1'), isNull);
      // A device that hashes nothing says so by answering nothing.
      bytes.digestAnswer = () => null;
      expect(await files.digest('n1'), isNull);
    });
  });
}
