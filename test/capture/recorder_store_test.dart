import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/place.dart' show placingFor;
import 'package:ghost_md/capture/recorder.dart';
import 'package:ghost_md/capture/take_writer.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';

/// The recorder's store over the app's library (lib/capture/recorder.dart `LibraryRecorderStore`): a command's write
/// is the library's own `applyCommandMutation`, so the id `writeInto` answers (the web's `capture/takeWriter.test.ts`,
/// "goes onto the note as it is when written") is one the library's `undoCommandMutation` takes back, which is what
/// a landing's Undo asks of it for a note other than the one that opens (`editor/useLanding.ts`). The library here
/// is the one in memory, the browser half of `core/store.ts`; test/native/command_mutations_test.dart crosses the
/// real core.
void main() {
  const house = '# House TODOs\n\n- [ ] Fix the gutter\n';

  late SampleLibrary library;
  late LibraryRecorderStore store;

  TakeWriter writer() => TakeWriter(
        TakeWriterHost(markdown: (_) => '', hasWords: () => false, candidates: () => const [], targetChanged: (_) {}),
        store: store,
      );

  setUp(() {
    library = SampleLibrary(const []);
    var ids = 0;
    store = LibraryRecorderStore(library, newId: () => 'id-${ids += 1}');
  });

  group('words a recording wrote into another note', () {
    test('are kept by the library as a command’s change, and its undo takes out exactly them', () async {
      await store.createNote('house', house);
      final written = await writer().writeInto('house', 'Call Sam.', placingFor(house), () => '# Call Sam');
      expect(written.own, false);
      expect(written.blocks, ['- [ ] Call Sam']);
      expect((await store.getNote('house'))!.body, '$house- [ ] Call Sam\n');

      final undone = await library.undoCommandMutation(written.mutationId!);
      expect(undone.status, 'undone');
      expect((await store.getNote('house'))!.body, house);
      expect((await library.undoCommandMutation(written.mutationId!)).status, 'already-undone');
    });

    test('are left by the undo once the note has changed since, and the note is answered as it is', () async {
      await store.createNote('house', house);
      final written = await writer().writeInto('house', 'Call Sam.', placingFor(house), () => '# Call Sam');
      final typed = await store.updateNote('house', '$house- [ ] Call Sam tomorrow\n', written.saved.revision);
      final refused = await library.undoCommandMutation(written.mutationId!);
      expect(refused.status, 'conflict');
      expect((await store.getNote('house'))!.body, typed.body);
    });

    test('have nothing to undo where they became a note of their own', () async {
      final written = await writer().writeInto('gone', 'Call Sam.', placingFor(house), () => '# Call Sam');
      expect((written.own, written.mutationId), (true, null));
      expect(library.value.single.body, '# Call Sam');
    });
  });

  group('a command’s change through the store', () {
    test('is refused for a note that moved on since its preview, and a new note is made only where there is none', () async {
      final made = await store.createNote('house', house);
      final moved = await store.updateNote('house', '$house- [ ] Typed\n', made.revision);
      final stale = await store.applyCommandMutation(CommandMutationRequest(mutationId: 'm1', noteId: 'house', kind: 'append', beforeRevision: made.revision, beforeBody: made.body, afterBody: '$house- [ ] Voice\n', source: made.source));
      expect(stale.status, 'conflict');
      expect((stale as CommandMutationResultConflict).current?.body, moved.body);

      const create = CommandMutationRequest(mutationId: 'm2', noteId: 'list', kind: 'create', beforeRevision: null, beforeBody: null, afterBody: '# Groceries', source: NoteSource.capture);
      final applied = await store.applyCommandMutation(create);
      expect(applied.status, 'applied');
      expect((applied as CommandMutationResultApplied).note.source, NoteSource.capture);
      expect((await store.applyCommandMutation(create)).status, 'conflict');
      // The list a command made goes with its undo.
      expect((await library.undoCommandMutation('m2')).status, 'undone');
      expect(await store.getNote('list'), isNull);
    });
  });
}
