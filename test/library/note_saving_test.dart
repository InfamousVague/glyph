import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/core_library.dart';
import 'package:ghost_md/core/library.dart';
import 'package:ghost_md/core/note.dart';

import 'support.dart';

/// Saving the open note ([NoteSaving]), against a fake of the library: the cases of the web's
/// `editor/useNoteSaving.test.tsx`. A save that conflicts because the phone's write-up appended the transcript is
/// made again over it, with the editor handed the result; any other conflict stops the saving as it always has; and
/// a note the write-up changed while nothing here was unsaved is adopted whole.
const String transcript = '## Transcript\n\nWe settled the date.\n\nSam owns the press list.';

void main() {
  late FakeCore core;
  late CoreLibrary library;
  late List<String> handed;
  late List<String> said;

  setUp(() {
    final it = libraryOver();
    core = it.core;
    library = it.library;
    handed = [];
    said = [];
  });

  NoteSaving open(Note note) {
    final saving = NoteSaving(library, note, onExternalChange: handed.add, lifecycle: false, log: said.add);
    addTearDown(saving.dispose);
    return saving;
  }

  Future<String> stored(String id) async => (await library.get(id))!.body;

  group('the transcript, read out of a body', () {
    test('is the section from its heading to the end, put back in place or on the end', () {
      const body = '# Meeting\n\nMy notes.\n\n## Transcript\n\nWe talked.\n';
      expect(transcriptOf(body), '## Transcript\n\nWe talked.');
      expect(transcriptOf('# Meeting\n\nNo such section.'), isNull);
      // A heading that only starts that way is not the section.
      expect(transcriptOf('## Transcript of the call\n\nWords.'), isNull);
      expect(withoutTranscript(body), '# Meeting\n\nMy notes.');
      expect(withTranscript('# Meeting\n', transcript), '# Meeting\n\n$transcript');
      expect(withTranscript(body, transcript), '# Meeting\n\nMy notes.\n\n$transcript');
      expect(withTranscript('', transcript), transcript);
    });
  });

  group('a save that meets the transcript from the phone', () {
    test('is made again over the transcript, and the editor is handed the words with it', () async {
      final note = await library.createNote('# Meeting, 26 Sep 14:05\n', source: NoteSource.capture, id: 'm1');
      final saving = open(note);
      // Rust appends the transcript under the note while it is open: the revision moves on.
      core.writeBehind('m1', withTranscript(note.body, transcript));
      // Typed here since, on the old revision.
      saving.onChange('# Meeting, 26 Sep 14:05\n\nMy own line.\n');
      await saving.settled();
      final rebased = withTranscript('# Meeting, 26 Sep 14:05\n\nMy own line.\n', transcript);
      expect(await stored('m1'), rebased);
      expect(handed, [rebased]);
      expect(saving.body, rebased);
      // Saving carries on from the new revision: the next words land.
      saving.onChange(saving.body.replaceFirst('My own line.', 'My own line, kept.'));
      await saving.settled();
      expect(await stored('m1'), contains('My own line, kept.'));
      expect(saving.writable, isTrue);
    });

    test('keeps the words typed while the save was out, and puts the transcript under them', () async {
      final note = await library.createNote('# Meeting, 26 Sep 14:05\n', source: NoteSource.capture, id: 'm1');
      final saving = open(note);
      core.writeBehind('m1', withTranscript(note.body, transcript));
      saving.onChange('# Meeting, 26 Sep 14:05\n\nFirst.\n');
      saving.flush();
      // More typed before the store answers the conflict: the words in hand have moved on.
      saving.onChange('# Meeting, 26 Sep 14:05\n\nFirst. Second.\n');
      final carried = withTranscript('# Meeting, 26 Sep 14:05\n\nFirst. Second.\n', transcript);
      // They are not handed back (they are the editor's own), but they carry the transcript for the next save.
      await untilTrue(() => saving.body == carried);
      expect(handed, isEmpty);
      await saving.settled();
      expect(await stored('m1'), carried);
    });
  });

  group('any other conflict', () {
    test('stops the saving, as it always has', () async {
      final note = await library.createNote('# Plan\n\nOne.\n', id: 'n1');
      final saving = open(note);
      core.writeBehind('n1', '# Plan\n\nOne, changed elsewhere.\n');
      saving.onChange('# Plan\n\nOne, changed here.\n');
      await saving.settled();
      expect(said.single, startsWith('[glyph] editor save stopped:'));
      expect(await stored('n1'), '# Plan\n\nOne, changed elsewhere.\n');
      expect(handed, isEmpty);
      expect(saving.writable, isFalse);
      saving.onChange('# Plan\n\nOne, changed here again.\n');
      await saving.settled();
      expect(await stored('n1'), '# Plan\n\nOne, changed elsewhere.\n');
    });

    test('is a note deleted while it was open, which a save does not bring back', () async {
      final note = await library.createNote('# Plan\n', id: 'n1');
      final saving = open(note);
      await library.destroy('n1');
      saving.onChange('# Plan\n\nStill typing.\n');
      await saving.settled();
      expect(await library.get('n1'), isNull);
      expect(saving.writable, isFalse);
    });
  });

  group('a conflict that has a transcript in it and another writer’s words too', () {
    test('stops, since rebasing would drop the other writer’s words', () async {
      final note = await library.createNote('# Plan\n\nOne.\n', id: 'n1');
      final saving = open(note);
      final theirs = withTranscript('# Plan\n\nOne, changed elsewhere.\n', transcript);
      core.writeBehind('n1', theirs);
      saving.onChange('# Plan\n\nOne, changed here.\n');
      await saving.settled();
      expect(said.single, startsWith('[glyph] editor save stopped:'));
      expect(await stored('n1'), theirs);
      expect(handed, isEmpty);
    });
  });

  group('a note the write-up changed', () {
    test('is not adopted over a save that is on its way, which then lands through its own rebase', () async {
      final note = await library.createNote('# Meeting, 26 Sep 14:05\n', source: NoteSource.capture, id: 'm1');
      final saving = open(note);
      core.writeBehind('m1', withTranscript(note.body, transcript));
      final behind = (await library.get('m1'))!;
      saving.onChange('# Meeting, 26 Sep 14:05\n\nJust typed.\n');
      saving.flush();
      // Flushed, not yet answered: taking the stored note now would hand the editor words without "Just typed."
      expect(saving.adopt(behind), isFalse);
      expect(saving.body, '# Meeting, 26 Sep 14:05\n\nJust typed.\n');
      await saving.settled();
      expect(await stored('m1'), withTranscript('# Meeting, 26 Sep 14:05\n\nJust typed.\n', transcript));
      // Saving carries on.
      saving.onChange(saving.body.replaceFirst('Just typed.', 'Just typed, and more.'));
      await saving.settled();
      expect(await stored('m1'), contains('Just typed, and more.'));
    });

    test('is adopted whole when nothing here is unsaved, and left to the next save when something is', () async {
      final note = await library.createNote('# Meeting, 26 Sep 14:05\n', source: NoteSource.capture, id: 'm1');
      final saving = open(note);
      // The screen's own first look at the store finds the note as it was opened.
      await pumpEventQueue();
      core.writeBehind('m1', withTranscript(note.body, transcript));
      final behind = (await library.get('m1'))!;
      expect(saving.adopt(behind), isTrue);
      expect(saving.body, behind.body);
      expect(handed, [behind.body]);
      // The revision came with it: a save from here now lands.
      saving.onChange('${behind.body}\n\nAnd mine.');
      await saving.settled();
      expect(await stored('m1'), '${behind.body}\n\nAnd mine.');
      // With words waiting to be saved, nothing is taken: the save's own rebase looks after it.
      core.writeBehind('m1', withTranscript('${behind.body}\n\nAnd mine.', '$transcript\n\nMore was said.'));
      final again = (await library.get('m1'))!;
      saving.onChange('${saving.body}\n\nTyped since.');
      expect(saving.adopt(again), isFalse);
      expect(handed, hasLength(1));
    });
  });

  group('a note opened again', () {
    test('is read again, and taken as the store has it while nothing is typed yet', () async {
      final note = await library.createNote('# Journal\n', id: 'j1');
      // Typed in on another screen, after the list this copy came from was read.
      core.writeBehind('j1', '# Journal\n\nYesterday’s words.\n');
      final saving = open(note);
      await untilTrue(() => saving.body == '# Journal\n\nYesterday’s words.\n');
      expect(handed, ['# Journal\n\nYesterday’s words.\n']);
      // So the next keystroke's save is from the revision the store has, and lands.
      saving.onChange('${saving.body}\nToday’s.\n');
      await saving.settled();
      expect(await stored('j1'), '# Journal\n\nYesterday’s words.\n\nToday’s.\n');
      expect(saving.writable, isTrue);
    });

    test('waits for the last screen on it to finish saving before it reads', () async {
      final note = await library.createNote('# Page\n', id: 'p1');
      final first = NoteSaving(library, note, lifecycle: false, log: said.add);
      first.onChange('# Page\n\nTyped, then left at once.\n');
      // Leaving flushes; the next screen opens with the list's copy, which has not caught up.
      first.dispose();
      final second = open(note);
      await untilTrue(() => second.body == '# Page\n\nTyped, then left at once.\n');
      second.onChange('${second.body}More.\n');
      await second.settled();
      expect(await stored('p1'), '# Page\n\nTyped, then left at once.\nMore.\n');
      expect(said, isEmpty);
    });
  });

  group('the debounce', () {
    test('saves a little after the last keystroke, once, and says the title and the blank page as they change', () async {
      final note = await library.createNote('', id: 'd1');
      final saving = NoteSaving(library, note, lifecycle: false, debounce: const Duration(milliseconds: 20), log: said.add);
      addTearDown(saving.dispose);
      expect((saving.title, saving.blank), ('', true));
      var told = 0;
      saving.addListener(() => told += 1);
      saving.onChange('# G');
      saving.onChange('# Gr');
      saving.onChange('# Groceries');
      expect((saving.title, saving.blank), ('Groceries', false));
      expect(told, 3);
      expect(core.asked('update_note'), 0);
      await untilTrue(() => core.asked('update_note') == 1);
      await saving.settled();
      expect(core.asked('update_note'), 1);
      expect(await stored('d1'), '# Groceries');
      // A change to the words under the title tells nobody.
      saving.onChange('# Groceries\n\nmilk');
      expect(told, 3);
    });

    test('reads the list again as the screen goes, once its last save has landed', () async {
      final note = await library.createNote('# One', id: 'a');
      final saving = NoteSaving(library, note, lifecycle: false, log: said.add);
      saving.onChange('# One\n\nmore');
      saving.dispose();
      await untilTrue(() => library.noteOf('a')!.body == '# One\n\nmore');
    });
  });
}

Future<void> untilTrue(bool Function() done) async {
  for (var turn = 0; turn < 200 && !done(); turn += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(done(), isTrue);
}
