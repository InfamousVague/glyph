// The lander. A port of src/app/ai/land.test.ts, case for case. The page's `EditorView` is a state and a dispatch
// (ai_changes_test.dart `TestView`): the lander draws nothing.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/ai_changes.dart';
import 'package:ghost_md/ai/land.dart';
import 'package:ghost_md/editor/state/change.dart';
import 'package:ghost_md/editor/state/state.dart';

import 'ai_changes_test.dart' show TestView;

TestView open(String doc, {required int start, required int cursor, required int oldEnd}) {
  final view = TestView(EditorState.create(doc: doc, extensions: aiChangesState()));
  view.dispatch(TransactionSpec(effects: setLanding.of(LandingSpot(runId: null, start: start, cursor: cursor, oldEnd: oldEnd))));
  return view;
}

const quiet = LanderOptions(wisp: false, haptic: false);
Lander make(TestView v, String id) => Lander(v, id, quiet, v.state.doc.toString());
List<({int from, int to, String removed, bool block})> marks(TestView v) => [for (final c in v.state.field(aiChangesField)) (from: c.from, to: c.to, removed: c.removed, block: c.block)];

void main() {
  group('the lander', () {
    test('lands a rewrite of the whole note line by line: kept lines stay, dropped lines are struck, new ones are marked', () {
      const doc = 'trip\n\ncall the plumber thursday\neggs and coffee\nold thing\n';
      final v = open(doc, start: 0, cursor: 0, oldEnd: doc.length);
      final lander = make(v, 'r1');
      lander.land(['# Trip']);
      expect(v.state.doc.toString(), '# Trip\n\ncall the plumber thursday\neggs and coffee\nold thing\n');
      // The title made a heading: the one line rewritten, its old word kept beside the new ones.
      expect(marks(v), [(from: 0, to: 6, removed: 'trip', block: false)]);
      lander.land(['# Trip', '']);
      expect(v.state.doc.toString(), '# Trip\n\ncall the plumber thursday\neggs and coffee\nold thing\n');
      lander.land(['# Trip', '', '- [ ] Call the plumber, before Thursday.']);
      expect(v.state.doc.toString(), '# Trip\n\n- [ ] Call the plumber, before Thursday.\neggs and coffee\nold thing\n');
      // The rewritten line: only the words that differ carry marks, the old ones kept beside them.
      final inline = marks(v).where((m) => !m.block && m.from >= 8).toList();
      expect(inline, isNotEmpty);
      expect([for (final m in inline) m.removed.trim()].where((r) => r.isNotEmpty), ['call', 'thursday']);
      lander.land(['# Trip', '', '- [ ] Call the plumber, before Thursday.', '- [ ] Eggs and coffee.']);
      expect(v.state.doc.toString(), '# Trip\n\n- [ ] Call the plumber, before Thursday.\n- [ ] Eggs and coffee.\nold thing\n');
      lander.finish(['# Trip', '', '- [ ] Call the plumber, before Thursday.', '- [ ] Eggs and coffee.']);
      expect(v.state.doc.toString(), '# Trip\n\n- [ ] Call the plumber, before Thursday.\n- [ ] Eggs and coffee.\n');
      final struck = marks(v).firstWhere((m) => m.removed == 'old thing');
      expect((struck.block, struck.from, struck.to), (true, v.state.doc.length, v.state.doc.length));
      expect(v.state.field(landingField), isNull);
    });

    test('lands lines the model added before old ones, and strikes what it passed over', () {
      const doc = 'a\nb\nc\n';
      final v = open(doc, start: 0, cursor: 0, oldEnd: doc.length);
      final lander = make(v, 'r2');
      lander.land(['# Title', 'b']);
      expect(v.state.doc.toString(), '# Title\nb\nc\n');
      expect(marks(v), [(from: 0, to: 7, removed: '', block: true), (from: 8, to: 8, removed: 'a', block: true)]);
      lander.finish(['# Title', 'b']);
      expect(v.state.doc.toString(), '# Title\nb\n');
      expect([for (final m in marks(v)) m.removed], ['', 'a', 'c']);
    });

    test('adds under the note, and above it, on lines of their own', () {
      final v = open('a\nb', start: 3, cursor: 3, oldEnd: 3);
      final lander = make(v, 'r3');
      lander.land(['c', 'd']);
      expect(v.state.doc.toString(), 'a\nb\nc\nd\n');
      lander.finish(['c', 'd']);
      expect(v.state.doc.toString(), 'a\nb\nc\nd\n');
      expect(marks(v), [(from: 4, to: 5, removed: '', block: true), (from: 6, to: 7, removed: '', block: true)]);

      final above = open('# Note\nwords\n', start: 0, cursor: 0, oldEnd: 0);
      final top = make(above, 'r4');
      top.land(['# Summary', 'Two things.', '']);
      top.finish(['# Summary', 'Two things.', '']);
      expect(above.state.doc.toString(), '# Summary\nTwo things.\n\n# Note\nwords\n');
    });

    test('never strikes or rewrites what the person typed while it ran, and counts the model’s line it dropped', () {
      const doc = 'a\nb\nc\n';
      final v = open(doc, start: 0, cursor: 0, oldEnd: doc.length);
      final lander = make(v, 'r5');
      lander.land(['a']);
      // The person writes over line b while the model works.
      v.dispatch(const TransactionSpec(changes: ChangeSpec(from: 2, to: 3, insert: 'b, mine now'), userEvent: 'input.type'));
      lander.land(['a', 'b, the model’s', 'c']);
      expect(v.state.doc.toString(), 'a\nb, mine now\nc\n');
      expect(lander.dropped, 1);
      lander.finish(['a', 'b, the model’s', 'c']);
      expect(v.state.doc.toString(), 'a\nb, mine now\nc\n');
    });

    test('reads the finished text over the landed lines, so a late tidy-up lands as a small change', () {
      const doc = 'x\n';
      final v = open(doc, start: 0, cursor: 0, oldEnd: doc.length);
      final lander = make(v, 'r6');
      lander.land(['* one', '* two']);
      expect(v.state.doc.toString(), '* one\n* two\nx\n');
      lander.finish(['- one', '- two']);
      expect(v.state.doc.toString(), '- one\n- two\n');
      expect([for (final m in marks(v).where((m) => !m.block)) m.removed.trim()], ['*', '*']);
    });

    test('leaves what landed when the run is abandoned', () {
      const doc = 'a\nb\n';
      final v = open(doc, start: 0, cursor: 0, oldEnd: doc.length);
      final lander = make(v, 'r7');
      lander.land(['A']);
      lander.abandon();
      expect(v.state.doc.toString(), 'A\nb\n');
      expect(v.state.field(landingField), isNull);
    });
  });
}
