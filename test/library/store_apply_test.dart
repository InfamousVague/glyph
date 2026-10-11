import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/core_library.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_json.dart';

import 'support.dart';

/// A note handed to the library as another device has it ([CoreLibrary.apply]): what `store_apply` is sent. The
/// cases of the web's `core/store.apply.test.ts`, and the trap docs/STAGE3.md names first.
void main() {
  /// A core that answers `store_apply` with the note it was sent, and writes down what that was.
  ({CoreLibrary library, List<({String command, Object? args})> sent}) echo() {
    final sent = <({String command, Object? args})>[];
    final library = CoreLibrary(
      (command, [args = const {}]) async {
        if (command == 'list_notes') return const <Object?>[];
        sent.add((command: command, args: args));
        return args['note'];
      },
      resume: false,
      wait: (_) async {},
      log: (_) {},
    );
    return (library: library, sent: sent);
  }

  group('a note applied on the core', () {
    test('always says whether it is pinned, though the note that came did not', () async {
      final it = echo();
      // As a browser stored one before it said the pin: no `starred` at all.
      final came = noteFromJson({'id': 'web-1', 'body': '# Made in a browser', 'createdAt': 1, 'updatedAt': 2, 'source': 'editor', 'revision': 1})!;
      await it.library.apply(came);
      expect(it.sent.single.command, 'store_apply');
      final note = (it.sent.single.args as Map)['note'] as Map;
      expect(note['starred'], isFalse);
      expect((note['id'], note['body'], note['createdAt'], note['updatedAt'], note['source'], note['revision']), ('web-1', '# Made in a browser', 1, 2, 'editor', 1));
      expect(note.containsKey('path'), isFalse);
    });

    test('keeps a pin that was there, and everything else as it came', () async {
      final it = echo();
      const note = Note(id: 'n-2', body: 'Pinned', createdAt: 1, updatedAt: 2, source: NoteSource.capture, starred: true, archivedAt: 5, recordingMs: 900, path: 'Inbox/Pinned.md');
      await it.library.apply(note);
      expect((it.sent.single.args as Map)['note'], noteToJson(note));
    });
  });

  group('what is kept beside a note', () {
    const segments = [Segment(text: 'hello', startMs: 0, endMs: 400)];

    test('survives a move when the note applied is the one fetched whole', () async {
      final it = libraryOver();
      await it.library.createNote('# Said', source: NoteSource.capture, id: 'a');
      await it.core.invoke('set_note_recording', {'id': 'a', 'recordingMs': 400, 'segments': [for (final s in segments) segmentToJson(s)]});
      final whole = (await it.library.get('a'))!;
      expect(whole.segments, segments);
      await it.library.apply(whole.copyWith(path: () => 'workspaces/Home/Said.md'));
      final after = (await it.library.get('a'))!;
      expect(after.path, 'workspaces/Home/Said.md');
      expect(after.segments, segments);
      expect(after.recordingMs, 400);
    });

    test('is lost by applying the list’s copy, which is why nothing here does', () async {
      final it = libraryOver();
      await it.library.createNote('# Said', source: NoteSource.capture, id: 'a');
      await it.core.invoke('set_note_recording', {'id': 'a', 'recordingMs': 400, 'segments': [for (final s in segments) segmentToJson(s)]});
      await it.library.refresh();
      final listed = it.library.noteOf('a')!;
      expect(listed.segments, isNull);
      expect(listed.recordingMs, 400);
      await it.library.apply(listed.copyWith(path: () => 'workspaces/Home/Said.md'));
      expect((await it.library.get('a'))!.segments, isNull);
    });
  });
}
