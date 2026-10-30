// A meeting's transcript folded out of its note's words (lib/editor/view/transcript_fold.dart; Matt, 2026-10-30:
// "Also use a button to switch to the transcript in the note don't show the transcript on the note section"): drawn as
// nothing, never typed into, a person's edit leaving it byte for byte, the app's writes going through, and a find's
// match or a landing in it asking for the transcript.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';
import 'package:ghost_md/editor/view/transcript_fold.dart';

const String _summary = '# Engineering Standup\n\n## Summary\n\nShip today.\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06.';
const String _transcript = '## Transcript\n\n**Phil Mulliken (0:02):** Oh yeah, we can talk about it.\n\n**Matt (1:04):** Shipping the tray today.';
const String _body = '$_summary\n\n$_transcript\n';

EditorState _state(String doc, {bool meeting = true, List<int>? revealed}) => EditorState.create(
      doc: doc,
      extensions: transcriptFold(TranscriptFold(meeting: (_) => meeting, reveal: revealed == null ? null : revealed.add)),
    );

String _transcriptOf(String doc) => doc.substring(doc.indexOf('## Transcript'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a meeting\'s transcript and captions are folded, from their heading to the next level-2 heading', () {
    final folds = transcriptFolds(_state(_body));
    expect(folds, [(from: _body.indexOf('## Transcript'), to: _body.length)]);
    const captioned = '# Call\n\nGhost was in this meeting.\n\n## Captions\n\n**Sam (0:01):** Hi.\n\n## Notes\n\nMine.\n';
    final f = transcriptFolds(_state(captioned)).single;
    expect(captioned.substring(f.from, f.to), '## Captions\n\n**Sam (0:01):** Hi.\n');
    expect(captioned.substring(f.to), '\n## Notes\n\nMine.\n', reason: 'what follows is the note\'s');
  });

  test('a note that is no meeting is untouched, whatever its headings', () {
    expect(transcriptFolds(_state(_body, meeting: false)), isEmpty);
    // Nor is a transcript that is the note's first line: there is nothing before it to stand on.
    expect(transcriptFolds(_state('## Transcript\n\nWords.\n')), isEmpty);
  });

  test('a caret or a selection that would land in the fold lands before it', () {
    final state = _state(_body);
    final next = state.update(TransactionSpec(selection: EditorSelection.single(_body.length), userEvent: 'select.pointer')).state;
    expect(next.selection.main.head, _body.indexOf('## Transcript') - 2, reason: 'the end of the words, past the blank line');
    final all = state.update(TransactionSpec(selection: EditorSelection.single(0, _body.length), userEvent: 'select')).state;
    expect(all.selection.main.from, 0);
    expect(all.selection.main.to, _body.indexOf('## Transcript') - 2);
  });

  test('an edit in the note\'s words keeps the transcript byte for byte', () {
    var state = _state(_body);
    // Typed at the end of the words.
    state = state.update(TransactionSpec(selection: EditorSelection.single(_body.length), userEvent: 'select')).state;
    final at = state.selection.main.head;
    state = state.update(TransactionSpec(changes: ChangeSpec(from: at, insert: ' Noted.'), userEvent: 'input.type')).state;
    expect(_transcriptOf(state.doc.toString()), _transcriptOf(_body));
    expect(state.doc.toString(), contains('10:06. Noted.\n\n## Transcript'));
    // Select all and Delete: the words go, the transcript and the line break before it stay.
    state = state.update(TransactionSpec(changes: ChangeSpec(from: 0, to: state.doc.length), userEvent: 'delete.selection')).state;
    expect(state.doc.toString(), '\n$_transcript\n', reason: 'the line break before the heading kept, so it is still a heading');
    // A forward delete at the end of the words cannot join the heading to them.
    var s2 = _state(_body);
    final before = _body.indexOf('## Transcript') - 1;
    s2 = s2.update(TransactionSpec(changes: ChangeSpec(from: before, to: before + 1), userEvent: 'delete.forward')).state;
    expect(_transcriptOf(s2.doc.toString()), _transcriptOf(_body));
    expect(s2.doc.toString(), contains('\n## Transcript'));
    // A paste over a selection reaching into it changes only the words.
    var s3 = _state(_body);
    s3 = s3.update(TransactionSpec(changes: ChangeSpec(from: _body.indexOf('Ship'), to: _body.length - 5, insert: 'Pasted.'), userEvent: 'input.paste')).state;
    expect(s3.doc.toString(), startsWith('# Engineering Standup\n\n## Summary\n\nPasted.'));
    expect(s3.doc.toString(), endsWith('today.\n'), reason: 'the transcript\'s own words are not taken');
  });

  test('what the app writes goes through: a write-up landing, a rebuild, an undo', () {
    var state = _state(_body);
    final from = _body.indexOf('## Transcript');
    state = state.update(TransactionSpec(changes: ChangeSpec(from: from, to: _body.length, insert: '## Transcript\n\n(0:00) Rebuilt.\n'))).state;
    expect(_transcriptOf(state.doc.toString()), '## Transcript\n\n(0:00) Rebuilt.\n');
  });

  testWidgets('a landing in the fold, put there by the app, asks for the transcript at it; a person\'s caret does not', (tester) async {
    final revealed = <int>[];
    final state = _state(_body, revealed: revealed);
    final inside = _body.indexOf('Shipping');
    state.update(TransactionSpec(selection: EditorSelection.single(inside)));
    state.update(TransactionSpec(selection: EditorSelection.single(_body.length), userEvent: 'select.pointer'));
    await tester.pump();
    expect(revealed, [inside]);
  });
}
