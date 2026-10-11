// A port of the state cases of src/app/editor/aiChanges.test.ts. What the web's cases ask of the drawn page (the
// `.cm-aiAdded` mark, the struck-through words, the pills) is not here: the drawing is the editor's AI surface.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_changes.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/state.dart';

/// A state and a dispatch: what the web's test has an `EditorView` for.
class TestView implements StateCommandTarget {
  TestView(this.state);

  @override
  EditorState state;

  void Function(List<AiChange> changes)? onMarks;

  @override
  void dispatch(Dispatchable tr) {
    final start = state;
    state = switch (tr) {
      Transaction() => tr.state,
      TransactionSpec() => state.update(tr).state,
    };
    final now = changedMarks(start, state);
    if (now != null) onMarks?.call(now);
  }
}

TestView open(String doc, [void Function(List<AiChange> changes)? onMarks]) =>
    TestView(EditorState.create(doc: doc, extensions: aiChangesState()))..onMarks = onMarks;

AiChange change({String id = 'c1', String runId = 'r1', int from = 0, int to = 0, String removed = '', bool block = true}) =>
    AiChange(id: id, runId: runId, from: from, to: to, removed: removed, block: block);

void main() {
  group('the AI’s changes, tracked', () {
    test('marks added words, draws the words that went, and tells the note when the marks change', () {
      final told = <int>[];
      final v = open('# Trip\nCall the plumber.\n', (changes) => told.add(changes.length));
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 7, to: 24, removed: 'call plumber')])));
      expect(told, [1]);
      // Skipped: `.cm-aiAdded`, `.cm-aiGoneBlock` and `.cm-aiPill` are drawn DOM. What they are drawn from:
      final marked = v.state.field(aiChangesField).single;
      expect(v.state.doc.sliceString(marked.from, marked.to), 'Call the plumber.');
      expect(marked.removed, 'call plumber');
    });

    test('keeps a change: the marks go and the words stay', () {
      final v = open('a\nb\n');
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 2, to: 3)])));
      keepChanges(v, ['c1']);
      expect(v.state.field(aiChangesField), isEmpty);
      expect(v.state.doc.toString(), 'a\nb\n');
    });

    test('reverts a line the AI added, a line it took away, and a line it rewrote', () {
      final v = open('a\nNEW\nc\n');
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 2, to: 5)])));
      revertChanges(v, ['c1']);
      expect(v.state.doc.toString(), 'a\nc\n');
      expect(v.state.field(aiChangesField), isEmpty);

      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(id: 'c2', from: 2, to: 2, removed: 'b')])));
      revertChanges(v, ['c2']);
      expect(v.state.doc.toString(), 'a\nb\nc\n');

      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(id: 'c3', from: 2, to: 3, removed: 'bee')])));
      revertChanges(v, ['c3']);
      expect(v.state.doc.toString(), 'a\nbee\nc\n');
    });

    test('reverts words within a line, with and without words to put back', () {
      final v = open('Call the plumber on Thursday.\n');
      v.dispatch(
        TransactionSpec(
          effects: addAiChanges.of([
            change(id: 'w1', from: 0, to: 4, removed: 'call', block: false),
            change(id: 'w2', from: 16, to: 28, removed: ' thursday', block: false),
          ]),
        ),
      );
      // Skipped: `.cm-aiGone`'s text is drawn DOM.
      revertChanges(v, ['w1', 'w2']);
      expect(v.state.doc.toString(), 'call the plumber thursday.\n');
    });

    test('maps its marks through typing elsewhere, and keeps a change whose line the person types on', () {
      final v = open('a\nb\nc\n');
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 4, to: 5)])));
      v.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'xx'), userEvent: 'input.type'));
      expect(v.state.field(aiChangesField)[0].from, 6);
      expect(v.state.field(aiChangesField)[0].to, 7);
      v.dispatch(const TransactionSpec(changes: ChangeSpec(from: 7, insert: '!'), userEvent: 'input.type'));
      expect(v.state.field(aiChangesField), isEmpty);
      expect(v.state.doc.toString(), 'xxa\nb\nc!\n');
    });

    test('leaves the marks alone for the AI’s own edits', () {
      final v = open('a\nb\n');
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 2, to: 3)])));
      v.dispatch(TransactionSpec(changes: const ChangeSpec(from: 3, insert: '\nc'), annotations: aiEdit.of(AiEdit.land)));
      expect(v.state.field(aiChangesField).length, 1);
    });

    test('shares one pair of pills across changes on neighbouring lines from one run', () {
      final v = open('a\nb\nc\n\n\ne\n');
      final changes = [change(id: '1', from: 0, to: 1), change(id: '2', from: 2, to: 3), change(id: '3', from: 7, to: 8), change(id: '4', runId: 'r2', from: 4, to: 5)];
      v.dispatch(TransactionSpec(effects: addAiChanges.of(changes)));
      final groups = groupChanges(v.state.doc, v.state.field(aiChangesField));
      expect(groups.map((g) => g.ids).toList(), [
        ['1', '2', '4'].sublist(0, 2),
        ['4'],
        ['3'],
      ]);
      // Skipped: the count of `.cm-aiPills` is drawn DOM; one pair is drawn per group.
      expect(groups.length, 3);
    });

    test('keeps the landing bookmark, moving it with the person’s typing and remembering what they touched', () {
      final v = open('a\nb\nc\n');
      v.dispatch(TransactionSpec(effects: setLanding.of(const LandingSpot(runId: null, start: 2, cursor: 2, oldEnd: 6))));
      v.dispatch(const TransactionSpec(changes: ChangeSpec(from: 0, insert: 'X'), userEvent: 'input.type'));
      expect(v.state.field(landingField), const Landing(runId: null, start: 3, cursor: 3, oldEnd: 7, touched: [(from: 0, to: 1)]));
      v.dispatch(TransactionSpec(changes: const ChangeSpec(from: 5, insert: 'yy'), annotations: aiEdit.of(AiEdit.land)));
      expect(v.state.field(landingField)?.touched, [(from: 0, to: 1)]);
      v.dispatch(TransactionSpec(effects: setLanding.of(null)));
      expect(v.state.field(landingField), isNull);
    });
  });

  // Not in the web's file: the parts of the port its cases do not reach.
  group('the state half, beside the web’s cases', () {
    test('keeps every change at once, and puts a closed note’s marks back', () {
      final v = open('a\nb\n');
      v.dispatch(TransactionSpec(effects: addAiChanges.of([change(from: 0, to: 1), change(id: 'c2', from: 2, to: 3)])));
      keepAllChanges(v);
      expect(v.state.field(aiChangesField), isEmpty);
      v.dispatch(TransactionSpec(effects: restoreAiChanges.of([change(id: 'c2', from: 2, to: 3), change(from: 0, to: 1)])));
      expect(v.state.field(aiChangesField).map((c) => c.id).toList(), ['c1', 'c2']);
    });

    test('says whether the person wrote in a stretch while the run was on', () {
      const landing = Landing(runId: 'r', start: 0, cursor: 0, oldEnd: 9, touched: [(from: 2, to: 4)]);
      expect(touchedIn(landing, 0, 2), isFalse);
      expect(touchedIn(landing, 3, 3), isTrue);
      expect(touchedIn(landing, 4, 8), isFalse);
      expect(touchedIn(landing, 1, 3), isTrue);
    });

    test('a change goes to JSON and back', () {
      final c = change(from: 2, to: 5, removed: 'old', block: false);
      expect(AiChange.fromJson(c.toJson()), c);
      expect(AiChange.fromJson({'id': 'c'}), isNull);
    });
  });
}
