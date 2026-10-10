// What a letter typed and a caret moved cost in an open note, over the list of extensions the app really gives its
// editor (lib/root/note_desk.dart): the app itself is drawn, a note opened in it, and the work is COUNTED, not timed,
// so the test says the same thing on a loaded machine as on an idle one.
//
// What is counted (lib/editor/state/text.dart `DocWork`, in a debug build only):
// - lines handed out by the document (`Doc.line`, `Doc.lineAt`): what a walk of the note costs, a line at a time;
// - lines read by the kept facts (`LineFact`): what is put to a pattern;
// - whole documents made into a string, and how often one was asked for;
// - things worked out from a whole document (`DocMemo`);
// and beside them the lines projected (`LineProjection.builds`) and laid out (`RenderEditorLine.layouts`).
//
// Two notes, the same words at the top: the twelve thousand letters the measured walk types in
// (lib/perf/perf_seed.dart "Bench long", made here the same way), and those with 370 kB of plain paragraphs after
// them. A keystroke at the same place in each must cost the same: the work is the screen's and the changed line's,
// and none of it is the note's length. Before the facts were kept with the document's tree, each of some twenty
// extensions read every line of the note for every letter, and half of them for every move of the caret: this
// test's long note would have counted about two hundred thousand lines for a letter, where it counts under two
// thousand.
//
// test/editor/input/budget_test.dart stays beside this one: it holds the keyboard's own client to its rules over
// the editor's base stack (three lines shown to the keyboard, nothing pushed for a letter, one line laid out), and
// times a keystroke there, which is why it can fail under load; the cost of typing in the app is held here.
import 'package:flutter/widgets.dart' hide Decoration;
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/preferences.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/editor_widget.dart' show Editor;
import 'package:ghost_md/editor/view/editor_view.dart';
import 'package:ghost_md/editor/view/line.dart';
import 'package:ghost_md/editor/view/projection.dart';
import 'package:ghost_md/root/ghost_root.dart';
import 'package:ghost_md/root/note_desk.dart';
import 'package:ghost_md/shell/app_shell.dart';

import '../editor/input/support.dart' show FakeIme;
import '../support/render.dart';

/// lib/perf/perf_seed.dart's "Bench long": the sample note under its name, and its words said again under headings
/// of their own, to twelve thousand letters.
String benchLong() {
  final again = sampleNoteBody.replaceFirst(RegExp(r'^---\n[\s\S]*?\n---\n'), '').replaceFirst(RegExp(r'^# .*\n', multiLine: true), '');
  final lines = sampleNoteBody.split('\n');
  for (var at = 0; at < lines.length; at += 1) {
    if (lines[at].startsWith('# ')) {
      lines[at] = '# Bench long';
      break;
    }
  }
  final more = StringBuffer(lines.join('\n'));
  for (var part = 2; more.length < 12000; part += 1) {
    more
      ..write('\n\n## Again, part $part\n\n')
      ..write(again);
  }
  return more.toString();
}

/// [body] with plain paragraphs after it, to [length] letters: a long note whose length is all that differs.
String padded(String body, int length) {
  const words = 'The quick brown fox jumps over the lazy dog, and then the dog, who was not as lazy as all that, gets up and has a word with the fox.';
  final more = StringBuffer(body);
  while (more.length < length) {
    more
      ..write('\n\n')
      ..write(words);
  }
  return more.toString();
}

/// What one thing done in the editor counted.
class Counted {
  Counted(this.lines, this.reads, this.strings, this.chars, this.asked, this.memos, this.projected, this.laidOut);

  final int lines, reads, strings, chars, asked, memos, projected, laidOut;

  @override
  String toString() => 'lines $lines, fact reads $reads, strings $strings ($chars letters), asked $asked, memos $memos, projected $projected, laid out $laidOut';
}

void main() {
  setUpAll(loadAppFonts);

  /// Opens a note of [body] in the app, puts the caret in a paragraph a third of the way down the bench note, and
  /// answers what a letter, a move of the caret and a new line each counted, through the keyboard's own client and
  /// with the frame after.
  Future<({Counted letter, Counted caret, Counted enter, int length, int lines})> measure(WidgetTester tester, String body) async {
    final library = SampleLibrary(<Note>[...seedLibrary(seedNow), Note(id: 'bench', body: body, createdAt: seedNow, updatedAt: seedNow)]);
    await pumpApp(
      tester,
      size: const Size(1280, 820),
      prefs: const Preferences(theme: 'light'),
      home: GhostRoot(launch: false, library: library, workspaces: WorkspaceStore(storage: MemoryWorkspaceStorage(seedWorkspaces())), clock: () => seedNow),
    );
    await tester.pump(const Duration(milliseconds: 100));
    tester.state<AppShellState>(find.byType(AppShell)).openNote('bench');
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final desk = tester.state<NoteDeskState>(find.byType(NoteDesk));
    final EditorView view = tester.widget<Editor>(find.byType(Editor)).view;
    final doc = view.state.doc;
    // The same place in either note: a paragraph's words, a third of the way down the bench note's own lines.
    var at = -1;
    for (var n = 100; n <= doc.lines; n++) {
      final line = doc.line(n);
      if (line.text.length > 60 && RegExp(r'^[A-Za-z]').hasMatch(line.text) && !line.text.contains('[')) {
        at = line.from + 20;
        break;
      }
    }
    expect(at, greaterThan(0), reason: 'a paragraph to type in');
    view.dispatch(TransactionSpec(selection: EditorSelection.single(at), scrollIntoView: true));
    await tester.pump();
    await tester.pump();
    desk.editor.focus();
    await tester.pump();
    await tester.pump();
    final ime = FakeIme(tester);
    expect(desk.editor.attached, isTrue);
    expect(view.hasFocus, isTrue, reason: 'the editor has the keyboard');

    Future<Counted> counting(Future<void> Function() act) async {
      // Past whatever the last thing left to settle (the + beside the line, the save's timer).
      await tester.pump(const Duration(milliseconds: 600));
      DocWork.reset();
      LineProjection.builds = 0;
      final laidOut = RenderEditorLine.layouts;
      await act();
      await tester.pump();
      return Counted(DocWork.lines, DocWork.reads, DocWork.strings, DocWork.stringChars, DocWork.asked, DocWork.memos, LineProjection.builds, RenderEditorLine.layouts - laidOut);
    }

    // A letter first, uncounted: what is read once for a document and kept is read.
    await ime.type('a');
    final letter = await counting(() => ime.type('b'));
    final caret = await counting(() => ime.select(ime.caret - 3));
    final enter = await counting(() => ime.enter());
    expect(view.state.doc.length, doc.length + 3);

    final result = (letter: letter, caret: caret, enter: enter, length: doc.length, lines: doc.lines);
    // Home first, and the timers a note's screen leaves (its place, its save).
    tester.state<AppShellState>(find.byType(AppShell)).backToList();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    debugDisableShadows = true;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 2));
    return result;
  }

  testWidgets('a letter, a move of the caret and a new line cost the screen and the line, not the note', (tester) async {
    final bench = benchLong();
    final short = await measure(tester, bench);
    final long = await measure(tester, padded(bench, 380000));
    // ignore: avoid_print
    print(
      'the note of ${short.length} letters, ${short.lines} lines:\n'
      '  a letter: ${short.letter}\n  the caret: ${short.caret}\n  a new line: ${short.enter}\n'
      'the note of ${long.length} letters, ${long.lines} lines:\n'
      '  a letter: ${long.letter}\n  the caret: ${long.caret}\n  a new line: ${long.enter}',
    );
    expect(short.length, inInclusiveRange(12000, 13000));
    expect(long.length, greaterThan(380000));
    expect(long.lines, greaterThan(short.lines + 5000));

    for (final (name, note) in <(String, ({Counted letter, Counted caret, Counted enter, int length, int lines}))>[('short', short), ('long', long)]) {
      // A LETTER. One string of the note (the parser's, which every other reader shares) and a few asked for by
      // name: the parser, the save, the +'s question whether this is a note of words, and the plugins' offers.
      expect(note.letter.strings, lessThanOrEqualTo(3), reason: '$name: the note is made a string once for a letter (and the letter itself, twice)');
      expect(note.letter.chars, lessThanOrEqualTo(note.length + 64), reason: '$name: one string of the note, not several');
      expect(note.letter.asked, lessThanOrEqualTo(8), reason: '$name: who asks for the whole note as a string on a letter is a short list; a new asker is a reader of the whole note');
      // The kept facts read the leaf the letter made: thirty-two lines at most for each.
      expect(note.letter.reads, lessThanOrEqualTo(2000), reason: '$name: a fact reads the changed leaf, not the note');
      expect(note.letter.lines, lessThanOrEqualTo(2500), reason: '$name: lines are handed out for the screen, not for the note');
      expect(note.letter.projected, lessThanOrEqualTo(2), reason: '$name: a letter projects its own line');
      expect(note.letter.laidOut, lessThanOrEqualTo(2), reason: '$name: and lays it out');

      // THE CARET. Nothing of the note is read at all.
      expect(note.caret.strings, 0, reason: '$name: a caret makes no string of the note');
      expect(note.caret.asked, lessThanOrEqualTo(1), reason: '$name: only the plugins\' offers ask for the note on a caret\'s move');
      expect(note.caret.reads, 0, reason: '$name: a caret reads no line for a fact');
      expect(note.caret.memos, 0, reason: '$name: and works nothing out from the note');
      expect(note.caret.lines, lessThanOrEqualTo(1200), reason: '$name: a caret hands out the screen\'s lines at most');
      expect(note.caret.projected, lessThanOrEqualTo(2), reason: '$name: the line the caret left and the one it came to');
      expect(note.caret.laidOut, lessThanOrEqualTo(2), reason: '$name: a caret lays out the lines it shows marks on');

      // A NEW LINE: a letter's cost, and the lines below moved down.
      expect(note.enter.chars, lessThanOrEqualTo(note.length + 64), reason: '$name: one string of the note for a new line');
      expect(note.enter.reads, lessThanOrEqualTo(4000), reason: '$name: a new line reads the leaves it made');
      expect(note.enter.lines, lessThanOrEqualTo(3500), reason: '$name: a new line hands out the screen\'s lines');
      expect(note.enter.projected, lessThanOrEqualTo(4), reason: '$name: a new line projects the two lines it made of one');
    }

    // And none of it is the note's length: the long note counts what the short one does.
    expect(long.letter.lines, lessThanOrEqualTo(short.letter.lines + 200), reason: 'a letter in a note thirty times as long hands out no more lines');
    expect(long.letter.reads, lessThanOrEqualTo(short.letter.reads + 400), reason: 'and reads no more for its facts');
    expect(long.caret.lines, lessThanOrEqualTo(short.caret.lines + 200), reason: 'nor does a caret');
    expect(long.enter.lines, lessThanOrEqualTo(short.enter.lines + 300), reason: 'nor a new line');
  });
}
