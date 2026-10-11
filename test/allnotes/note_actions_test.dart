import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/swipe.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/note_actions.dart';
import 'package:glacier/glacier.dart';

import '../core/make_note.dart';
import '../support/render.dart';

/// Pin, archive, the trash and the delete for good, each with its words and its Undo (lib/notes/note_actions.dart),
/// after the web's `notes/useNoteActions.test.tsx`: the delete that is deferred rather than done and undone, hidden
/// at once, gone from the library when its Undo runs out, and made final the moment anything could outlive the toast.
/// What the web's cases say of a note's gist, runs, marks, summary and a meeting's write-up is said here of the
/// callbacks those are left to.
void main() {
  setUpAll(loadAppFonts);

  final apples = makeNote('a', body: '# Apples');
  final bread = makeNote('b', body: '# Bread');
  final cheese = makeNote('c', body: '# Cheese');

  ({NoteActions actions, SampleLibrary library, MemoryTrash trash, WorkspaceStore spaces, List<NoteToast> said, List<String> forgot, List<String> heard, List<HapticKind> felt}) rig({bool withTrash = true}) {
    final library = SampleLibrary([apples, bread]);
    final trash = MemoryTrash();
    final spaces = WorkspaceStore(storage: MemoryWorkspaceStorage());
    final said = <NoteToast>[];
    final forgot = <String>[];
    final heard = <String>[];
    final felt = <HapticKind>[];
    final actions = NoteActions(
      library: library,
      workspaces: spaces,
      trash: withTrash ? trash : null,
      say: said.add,
      haptic: ([kind = HapticKind.light]) => felt.add(kind),
      onForget: forgot.add,
      onTrashed: (note) => heard.add('trashed ${note.id}'),
      onRestored: (note) => heard.add('restored ${note.id}'),
    );
    return (actions: actions, library: library, trash: trash, spaces: spaces, said: said, forgot: forgot, heard: heard, felt: felt);
  }

  group('deleting for good', () {
    testWidgets('hides the note at once, and removes it, its filing and its place in the trash only when the Undo runs out', (tester) async {
      final it = rig();
      final space = it.spaces.addWorkspace('Kitchen')!;
      it.spaces.fileNote('a', space.id);
      it.trash.trashNote('a');
      var told = 0;
      it.actions.addListener(() => told += 1);
      it.actions.destroy(apples);
      expect(it.actions.hidden, {'a'});
      expect(told, 1);
      expect(it.said.last.message, 'Deleted “Apples” for good.');
      expect(it.said.last.duration, const Duration(milliseconds: 5000));
      await tester.pump(const Duration(milliseconds: 4999));
      expect(it.library.noteOf('a'), isNotNull);
      expect(it.forgot, isEmpty);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump();
      expect(it.library.noteOf('a'), isNull);
      expect(it.spaces.workspaceOf('a'), isNull);
      expect(it.forgot, ['a']);
      expect(it.trash.isTrashed('a'), isFalse);
      expect(it.actions.hidden, isEmpty);
      it.actions.dispose();
    });

    testWidgets('keeps the note when Undo is pressed in time', (tester) async {
      final it = rig();
      it.actions.destroy(apples);
      it.said.last.undo!();
      expect(it.actions.hidden, isEmpty);
      await tester.pump(const Duration(seconds: 10));
      expect(it.library.noteOf('a'), isNotNull);
      expect(it.forgot, isEmpty);
      expect(it.felt, [HapticKind.warning, HapticKind.success]);
      it.actions.dispose();
    });

    testWidgets('makes the first final when a second is deleted, since only one Undo is on screen', (tester) async {
      final it = rig();
      it.actions.destroy(apples);
      it.actions.destroy(bread);
      await tester.pump();
      expect(it.library.noteOf('a'), isNull);
      expect(it.library.noteOf('b'), isNotNull);
      expect(it.actions.hidden, {'b'});
      // The first one's Undo, pressed late, undoes nothing of the second.
      it.said.first.undo!();
      expect(it.actions.hidden, {'b'});
      await tester.pump(const Duration(seconds: 6));
      it.actions.dispose();
    });

    testWidgets('is made final when the app goes to the background, or the list asks for it', (tester) async {
      final it = rig();
      it.actions.destroy(apples);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(it.library.noteOf('a'), isNull);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

      it.actions.destroy(bread);
      await it.actions.flushDeletes();
      expect(it.library.noteOf('b'), isNull);
      it.actions.dispose();
    });

    testWidgets('is made final when the screen that asked for it goes', (tester) async {
      final it = rig();
      it.actions.destroy(apples);
      it.actions.dispose();
      await tester.pump();
      expect(it.library.noteOf('a'), isNull);
    });
  });

  group('the trash', () {
    test('takes a note with an Undo that brings it back, and gives it back with words of its own', () {
      final it = rig();
      it.actions.remove(apples);
      expect(it.trash.isTrashed('a'), isTrue);
      // The note itself is untouched: only the trash deletes.
      expect(it.library.noteOf('a'), isNotNull);
      expect(it.heard, ['trashed a']);
      expect(it.said.last.message, 'Moved “Apples” to the Trash.');
      it.said.last.undo!();
      expect(it.trash.isTrashed('a'), isFalse);
      expect(it.heard, ['trashed a', 'restored a']);
      it.trash.trashNote('b');
      it.actions.restore(bread);
      expect(it.trash.isTrashed('b'), isFalse);
      expect(it.said.last.message, '“Bread” is back in your notes.');
      expect(it.said.last.undo, isNull);
      it.actions.dispose();
    });

    test('empties at once, and says how many went', () async {
      final it = rig();
      it.trash.trashNote('a');
      it.trash.trashNote('b');
      it.spaces.fileNote('a', it.spaces.addWorkspace('Kitchen')!.id);
      await it.actions.emptyTrash([apples, bread]);
      expect(it.library.noteOf('a'), isNull);
      expect(it.library.noteOf('b'), isNull);
      expect(it.trash.isTrashed('a'), isFalse);
      expect(it.spaces.workspaceOf('a'), isNull);
      expect(it.forgot, ['a', 'b']);
      expect(it.said.last.message, 'Deleted 2 notes for good.');
      await it.actions.emptyTrash([cheese]);
      expect(it.said.last.message, 'Deleted 1 note for good.');
      it.actions.dispose();
    });

    test('names a note by its title only while the title is short enough to read in a line', () {
      final it = rig();
      final long = makeNote('long', body: '# A title far too long to fit in the one line a toast has');
      it.actions.remove(long);
      expect(it.said.last.message, 'Moved the note to the Trash.');
      it.trash.trashNote('long');
      it.actions.restore(long);
      expect(it.said.last.message, 'The note is back in your notes.');
      expect(noteLabel(makeNote('n', body: '')), 'the note');
      it.actions.dispose();
    });

    test('with no trash to wait in, takes the note out of the library and hands it back by Undo, filed where it was', () {
      final it = rig(withTrash: false);
      it.spaces.fileNote('a', it.spaces.addWorkspace('Kitchen')!.id);
      it.actions.remove(apples);
      expect(it.library.noteOf('a'), isNull);
      expect(it.spaces.workspaceOf('a'), isNull);
      expect(it.said.last.message, 'Moved “Apples” to the Trash.');
      it.said.last.undo!();
      expect(it.library.noteOf('a'), isNotNull);
      expect(it.spaces.workspaceOf('a')?.name, 'Kitchen');
      it.actions.dispose();
    });
  });

  group('pin and archive', () {
    test('pin at once, and archive with an Undo that brings it back', () {
      final it = rig();
      it.actions.pin(apples);
      expect(it.library.noteOf('a')!.starred, isTrue);
      expect(it.said, isEmpty);
      it.actions.pin(it.library.noteOf('a')!);
      expect(it.library.noteOf('a')!.starred, isFalse);
      it.actions.archive(bread, archived: true);
      expect(it.library.noteOf('b')!.archivedAt, isNotNull);
      expect(it.said.last.message, 'Archived “Bread”.');
      it.said.last.undo!();
      expect(it.library.noteOf('b')!.archivedAt, isNull);
      it.actions.archive(bread, archived: false);
      expect(it.said.last.message, '“Bread” is back in your notes.');
      it.actions.dispose();
    });

    test('a swipe is one of the three', () {
      final it = rig();
      it.actions.swipe(apples, NoteSwipe.pin);
      it.actions.swipe(apples, NoteSwipe.archive);
      it.actions.swipe(bread, NoteSwipe.delete);
      expect(it.library.noteOf('a')!.starred, isTrue);
      expect(it.library.noteOf('a')!.archivedAt, isNotNull);
      expect(it.trash.isTrashed('b'), isTrue);
      it.actions.dispose();
    });
  });

  testWidgets('says it in the kit’s toast, with Undo as its action', (tester) async {
    final library = SampleLibrary([apples]);
    late NoteActions actions;
    await pumpApp(
      tester,
      home: Builder(
        builder: (context) {
          actions = NoteActions(library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage()), trash: MemoryTrash(), say: NoteActions.toaster(context));
          return const SizedBox.expand();
        },
      ),
    );
    actions.archive(apples, archived: true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Archived “Apples”.'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(library.noteOf('a')!.archivedAt, isNull);
    actions.dispose();
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
  });
}
