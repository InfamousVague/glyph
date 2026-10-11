// A spoken command's write and its undo through the real Rust core, on the Mac: lib/core/core_library.dart over
// native/target/debug/libghost_core.dylib (tool/build-native.sh host), asking `apply_command_mutation` and
// `undo_command_mutation` (native/src/dispatch.rs over `src-tauri/src/library/mutations.rs`). What the two do is
// Rust's to test, and its own tests came with it; this holds that the request Dart sends is one the core takes
// (`ApplyCommandRequest` refuses a field it does not name) and that each answer is read as what it is, by the web's
// own cases (test/library/command_cases.dart), and that the undo is in the file.
//
// One process has one core (dispatch.rs `CORE`), so every case here shares one library, and makes its ids its own.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/command_mutations.dart';
import 'package:ghost_md/core/core_library.dart';
import 'package:ghost_md/core/native/core.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/core/note.dart';

import '../library/command_cases.dart';

const _library = 'native/target/debug/libghost_core.dylib';

void main() {
  final built = File(_library).existsSync();
  final skip = built ? null : 'the Mac\'s core is not built: run tool/build-native.sh host (wanted $_library)';

  late Directory root;
  late String data;
  late GhostCore core;
  late CoreLibrary library;
  var cases = 0;

  setUpAll(() async {
    if (!built) return;
    // Resolved, as the phone's directory is: /var is a link on a Mac, and the core answers paths as it was told.
    root = Directory(Directory.systemTemp.createTempSync('ghost-core-commands-').resolveSymbolicLinksSync());
    data = '${root.path}/data';
    core = await GhostCore.open(libraryPath: File(_library).absolute.path);
    await core.init(dataDir: data, cacheDir: '${root.path}/cache');
    library = CoreLibrary(core.invoke, resume: false, log: (_) {});
    await library.load();
  });

  tearDownAll(() async {
    if (!built) return;
    library.dispose();
    await core.close();
    root.deleteSync(recursive: true);
  });

  setUp(() {
    cases += 1;
  });

  group('a command’s write, and its undo, through the real core', () {
    commandCases(() async => library, id: (name) => '$name-$cases', skip: skip);

    test('are in the note’s file: the words added, taken out again, and a made note’s file gone', () async {
      final id = await core.newId(), other = await core.newId(), m1 = await core.newId(), m2 = await core.newId();
      final note = await library.createNote('# Work\n', id: id);
      final file = File('$data/Library/${note.path}');
      final applied = await library.applyCommandMutation(CommandMutationRequest(mutationId: m1, noteId: id, kind: 'append', beforeRevision: note.revision, beforeBody: note.body, afterBody: '# Work\n\n- Call Sam\n', source: note.source));
      expect(applied.status, 'applied');
      expect(file.readAsStringSync(), endsWith('---\n# Work\n\n- Call Sam\n'));
      expect(library.noteOf(id)!.body, '# Work\n\n- Call Sam\n');

      expect((await library.undoCommandMutation(m1)).status, 'undone');
      expect(file.readAsStringSync(), endsWith('---\n# Work\n'));
      expect((library.noteOf(id)!.body, library.noteOf(id)!.revision), ('# Work\n', 3));

      final made = await library.applyCommandMutation(CommandMutationRequest(mutationId: m2, noteId: other, kind: 'create', beforeRevision: null, beforeBody: null, afterBody: '# Shopping list\n\n- Oat milk\n', source: NoteSource.capture));
      final path = (made as CommandMutationResultApplied).note.path!;
      expect(File('$data/Library/$path').existsSync(), isTrue);
      expect(library.noteOf(other), isNotNull);
      expect((await library.undoCommandMutation(m2)).status, 'undone');
      expect(File('$data/Library/$path').existsSync(), isFalse);
      expect(library.noteOf(other), isNull);
    }, skip: skip);

    test('are refused whole by the core for an id that could not name a file', () async {
      final id = await core.newId();
      await library.createNote('# Plain\n', id: id);
      const bad = CommandMutationRequest(mutationId: 'm/1', noteId: 'n', kind: 'create', beforeRevision: null, beforeBody: null, afterBody: 'x', source: NoteSource.capture);
      await expectLater(library.applyCommandMutation(bad), throwsA(isA<CoreError>().having((e) => e.message, 'message', 'a command mutation needs plain bounded ids')));
    }, skip: skip);
  });
}
