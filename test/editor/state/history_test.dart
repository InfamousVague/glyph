// Undo history: 90 random sessions replayed against what CodeMirror's own history did with them
// (fixtures/history.json), then its behaviours one at a time, after @codemirror/commands' test-history.ts.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';

import 'support.dart';

/// A state that commands change in place, with a clock the test moves.
class Session {
  Session(String doc, {List<Extension> extensions = const <Extension>[], HistoryConfig config = const HistoryConfig(), EditorSelection? selection})
    : state = EditorState.create(doc: doc, selection: selection, extensions: Extension.list(<Extension>[history(config), ...extensions]));

  EditorState state;
  int time = 1000;

  StateCommandTarget get target => StateCommandTarget(state, (tr) => state = tr.state);

  bool run(StateCommand command) => command(target);

  /// Types `text` at `from` (the end by default), `gap` milliseconds after the last thing.
  void type(String text, {int? from, int? to, int gap = 100, String? userEvent = 'input.type', List<Annotation<Object?>> annotations = const <Annotation<Object?>>[], Object? effects}) {
    time += gap;
    final at = from ?? state.doc.length;
    state = state.update(
      TransactionSpec(
        changes: ChangeSpec(from: at, to: to ?? at, insert: text),
        annotations: <Annotation<Object?>>[Transaction.time.of(time), ...annotations],
        userEvent: userEvent,
        effects: effects,
      ),
    ).state;
  }

  void select(int anchor, [int? head, int gap = 100, String? userEvent]) {
    time += gap;
    state = state.update(TransactionSpec(selection: EditorSelection.single(anchor, head), annotations: Transaction.time.of(time), userEvent: userEvent)).state;
  }

  String get doc => state.doc.toString();
}

Object? withoutNulls(Object? json) {
  if (json is Map) {
    return <String, Object?>{
      for (final e in json.entries)
        if (e.value != null) e.key as String: withoutNulls(e.value),
    };
  }
  if (json is List) return <Object?>[for (final e in json) withoutNulls(e)];
  return json;
}

void main() {
  group('against CodeMirror', () {
    final sessions = fixture('history')['sessions'] as List;
    test('${sessions.length} sessions of typing, pasting, selecting, remote changes, undo and redo', () {
      for (var n = 0; n < sessions.length; n++) {
        final s = sessions[n] as Map<String, dynamic>;
        final config = s['config'] as Map<String, dynamic>, withFlag = s['withFlag'] as bool;
        final setFlag = StateEffect.define<int>();
        final flag = StateField.define<int>(
          create: (_) => 0,
          update: (v, tr) {
            for (final e in tr.effects) {
              final set = setFlag.cast(e);
              if (set != null) v = set.value;
            }
            return v;
          },
        );
        final inverted = invertedEffects.of((tr) => <StateEffect<Object?>>[
          for (final e in tr.effects)
            if (e.isOf(setFlag)) setFlag.of(tr.startState.field(flag)),
        ]);
        var state = EditorState.create(
          doc: 'The quick brown fox\njumps over',
          extensions: Extension.list(<Extension>[
            history(HistoryConfig(minDepth: config['minDepth'] as int?, newGroupDelay: config['newGroupDelay'] as int?)),
            if (withFlag) ...<Extension>[flag, inverted],
          ]),
        );
        final done = <Object?>[];
        for (final op in s['ops'] as List) {
          final time = op['time'] as int;
          done.add(<String, Object?>{for (final k in (op as Map<String, dynamic>).keys) if (k != 'r') k: op[k]});
          switch (op['op'] as String) {
            case 'undo' || 'redo' || 'undoSelection' || 'redoSelection':
              final command = switch (op['op'] as String) {
                'undo' => undo,
                'redo' => redo,
                'undoSelection' => undoSelection,
                _ => redoSelection,
              };
              final ran = command(StateCommandTarget(state, (tr) => state = tr.state));
              expect(ran, op['ran'], reason: 'session $n after ${jsonEncode(done)}');
            case 'select':
              state = state.update(
                TransactionSpec(
                  selection: EditorSelection.single(op['anchor'] as int, op['head'] as int),
                  annotations: Transaction.time.of(time),
                  userEvent: op['userEvent'] as String?,
                ),
              ).state;
            case 'effect':
              state = state.update(TransactionSpec(effects: setFlag.of(op['v'] as int), annotations: Transaction.time.of(time))).state;
            case 'edit':
              state = state.update(
                TransactionSpec(
                  changes: ChangeSpec(from: op['from'] as int, to: op['to'] as int, insert: op['insert'] as String),
                  selection: op['sel'] == null ? null : EditorSelection.single(op['sel'] as int),
                  annotations: <Annotation<Object?>>[
                    Transaction.time.of(time),
                    if (op['isolate'] != null) isolateHistory.of(op['isolate'] as String),
                    if (op['remote'] == true) Transaction.addToHistory.of(false),
                  ],
                  userEvent: op['userEvent'] as String?,
                ),
              ).state;
          }
          expect(
            <String, Object?>{
              'doc': state.doc.toString(),
              'anchor': state.selection.main.anchor,
              'head': state.selection.main.head,
              'undo': undoDepth(state),
              'redo': redoDepth(state),
              'flag': withFlag ? state.field(flag) : null,
            },
            op['r'],
            reason: 'session $n (${jsonEncode(config)}) after ${jsonEncode(done)}',
          );
        }
        // The whole history, as CodeMirror serializes it: every step's changes, mapping and selections.
        final json = state.toJson(<String, StateField<Object?>>{'history': historyField})['history'];
        expect(withoutNulls(jsonDecode(jsonEncode(json))), withoutNulls(s['json']), reason: 'session $n: the history field');
      }
    });
  });

  group('history', () {
    test('allows to undo a change', () {
      final s = Session('one')..type(' two');
      expect(s.doc, 'one two');
      expect(s.run(undo), isTrue);
      expect(s.doc, 'one');
      expect(s.run(undo), isFalse);
    });

    test('allows to undo nearby changes in one change', () {
      final s = Session('')
        ..type('o')
        ..type('n')
        ..type('e');
      expect(undoDepth(s.state), 1);
      s.run(undo);
      expect(s.doc, '');
    });

    test('allows to redo a change, and a new change forgets what was undone', () {
      final s = Session('one')..type(' two');
      s.run(undo);
      expect(redoDepth(s.state), 1);
      expect(s.run(redo), isTrue);
      expect(s.doc, 'one two');
      expect(s.run(redo), isFalse);
      s.run(undo);
      s.type('!');
      expect(redoDepth(s.state), 0);
      expect(s.run(redo), isFalse);
    });

    test('puts the selection back where it was before the step, and after it on redo', () {
      final s = Session('one two', selection: EditorSelection.single(4, 7));
      s.time += 100;
      s.state = s.state.update(
        TransactionSpec(changes: const ChangeSpec(from: 4, to: 7, insert: 'x'), selection: EditorSelection.single(5), annotations: Transaction.time.of(s.time)),
      ).state;
      s.select(0, null, 2000);
      s.run(undo);
      expect(s.doc, 'one two');
      expect(<int>[s.state.selection.main.anchor, s.state.selection.main.head], <int>[4, 7]);
      s.run(redo);
      expect(s.doc, 'one x');
      expect(s.state.selection.main.head, 5);
    });

    test('starts a new group after the delay, at a distance, and for another kind of event', () {
      final s = Session('')
        ..type('a')
        ..type('b', gap: 499)
        ..type('c', gap: 500);
      expect(undoDepth(s.state), 2);
      s.run(undo);
      expect(s.doc, 'ab');

      final far = Session('one two three')
        ..type('x', from: 0)
        ..type('y', from: 12);
      expect(undoDepth(far.state), 2);

      final kinds = Session('')
        ..type('a')
        ..type('b', userEvent: 'input.paste')
        ..type('c', userEvent: 'input.type')
        ..type('d', userEvent: null)
        ..type('e', userEvent: 'delete.backward');
      // A paste never joins; typing after it starts over; an unnamed change joins, and so does a delete.
      expect(undoDepth(kinds.state), 2);
    });

    test('a composition always joins the step before it, however late', () {
      final s = Session('')
        ..type('k')
        ..type('ka', from: 0, to: 1, gap: 5000, userEvent: 'input.type.compose');
      expect(undoDepth(s.state), 1);
      s.run(undo);
      expect(s.doc, '');
    });

    test('newGroupDelay and joinToEvent configure the grouping; given twice, the stricter delay and either join win', () {
      final quick = Session('', config: const HistoryConfig(newGroupDelay: 50))
        ..type('a')
        ..type('b');
      expect(undoDepth(quick.state), 2);
      final never = Session('', config: HistoryConfig(joinToEvent: (_, _) => false))
        ..type('a')
        ..type('b');
      expect(undoDepth(never.state), 2);
      final always = Session('one two three', config: HistoryConfig(joinToEvent: (_, _) => true))
        ..type('x', from: 0)
        ..type('y', from: 12);
      expect(undoDepth(always.state), 1);
      final both = Session('one two three', extensions: <Extension>[history(const HistoryConfig(newGroupDelay: 5000)), history(HistoryConfig(newGroupDelay: 50, joinToEvent: (_, _) => true))])
        ..type('x', from: 0)
        ..type('y', from: 12, gap: 40)
        ..type('z', from: 12, gap: 60);
      expect(undoDepth(both.state), 2);
    });

    test('isolateHistory keeps a change apart: before it, after it, or both', () {
      final full = Session('')
        ..type('a')
        ..type('b', annotations: <Annotation<Object?>>[isolateHistory.of('full')])
        ..type('c');
      expect(undoDepth(full.state), 3);
      final before = Session('')
        ..type('a')
        ..type('b', annotations: <Annotation<Object?>>[isolateHistory.of('before')])
        ..type('c');
      expect(undoDepth(before.state), 2);
      before.run(undo);
      expect(before.doc, 'a');
      final after = Session('')
        ..type('a')
        ..type('b', annotations: <Annotation<Object?>>[isolateHistory.of('after')])
        ..type('c');
      expect(undoDepth(after.state), 2);
      after.run(undo);
      expect(after.doc, 'ab');
    });

    test('a change kept out of history is not a step, and the steps under it still undo the right text', () {
      final s = Session('one two')..type('!');
      s.type('zero ', from: 0, gap: 2000, annotations: <Annotation<Object?>>[Transaction.addToHistory.of(false)]);
      expect(s.doc, 'zero one two!');
      expect(undoDepth(s.state), 1);
      s.run(undo);
      expect(s.doc, 'zero one two');
      s.run(redo);
      expect(s.doc, 'zero one two!');
    });

    test('a remote change that deletes a step\'s text takes the step with it', () {
      final s = Session('abc')..type('XYZ');
      s.type('', from: 2, to: 6, gap: 2000, annotations: <Annotation<Object?>>[Transaction.addToHistory.of(false)]);
      expect(s.doc, 'ab');
      expect(undoDepth(s.state), 0);
      expect(s.run(undo), isFalse);
    });

    test('remote changes between two local steps: each step undoes its own text', () {
      final s = Session('hello')..type('A', from: 0);
      s.type('B', from: 6, gap: 2000);
      s.type('--', from: 3, gap: 2000, annotations: <Annotation<Object?>>[Transaction.addToHistory.of(false)]);
      expect(s.doc, 'Ahe--lloB');
      s.run(undo);
      expect(s.doc, 'Ahe--llo');
      s.run(undo);
      expect(s.doc, 'he--llo');
      s.run(redo);
      s.run(redo);
      expect(s.doc, 'Ahe--lloB');
    });

    test('tracks selection changes for undoSelection, and joins a run of the same kind', () {
      final s = Session('one two three')..type('!');
      s.select(3, null, 2000, 'select.pointer');
      s.select(7, null, 2000, 'select.pointer');
      expect(s.run(undoSelection), isTrue);
      expect(s.state.selection.main.head, 3);
      expect(s.run(undoSelection), isTrue);
      expect(s.state.selection.main.head, 0);
      expect(s.run(redoSelection), isTrue);
      expect(s.state.selection.main.head, 3);
      expect(s.doc, 'one two three!');
      // Selection history does not count as steps.
      expect(undoDepth(s.state), 1);

      final joined = Session('one two three');
      joined.select(1, null, 100, 'select');
      joined.select(2, null, 100, 'select');
      joined.select(3, null, 100, 'select');
      // Only where the caret was before the run is kept: the quick moves after it, all of one kind and shape, are
      // one move, undone together.
      expect(joined.run(undoSelection), isTrue);
      expect(joined.state.selection.main.head, 0);
      expect(joined.run(undoSelection), isFalse);
    });

    test('undoSelection undoes a change when there is no selection after it', () {
      final s = Session('one')..type(' two');
      expect(s.run(undoSelection), isTrue);
      expect(s.doc, 'one');
    });

    test('keeps at least minDepth steps and drops the oldest beyond it', () {
      final s = Session('', config: const HistoryConfig(minDepth: 10));
      for (var i = 0; i < 40; i++) {
        s.type('x', gap: 2000);
      }
      expect(undoDepth(s.state), lessThan(40));
      expect(undoDepth(s.state), greaterThanOrEqualTo(10));
      var undone = 0;
      while (s.run(undo)) {
        undone++;
      }
      expect(undone, greaterThanOrEqualTo(10));
      expect(s.doc.length, 40 - undone);
    });

    test('does nothing to a read-only state, but still undoes a selection there', () {
      final readOnly = Compartment();
      final s = Session('one', extensions: <Extension>[readOnly.of(EditorState.readOnlyFacet.of(false))])..type('!');
      s.select(1, null, 2000);
      s.state = s.state.update(TransactionSpec(effects: readOnly.reconfigure(EditorState.readOnlyFacet.of(true)))).state;
      expect(s.run(undo), isFalse);
      expect(s.doc, 'one!');
      expect(s.run(undoSelection), isTrue);
      expect(s.doc, 'one!');
    });

    test('says so in the transactions it makes', () {
      final s = Session('one')..type('!');
      Transaction? seen;
      undo(StateCommandTarget(s.state, (tr) => seen = tr));
      expect(seen!.isUserEvent('undo'), isTrue);
      expect(seen!.scrollIntoView, isTrue);
      final undone = seen!.state;
      redo(StateCommandTarget(undone, (tr) => seen = tr));
      expect(seen!.isUserEvent('redo'), isTrue);
    });

    test('undoes past a change filter', () {
      final s = Session('one', extensions: <Extension>[EditorState.changeFilter.of((tr) => tr.isUserEvent('input'))]);
      s.type('!');
      expect(s.doc, 'one!');
      expect(s.run(undo), isTrue);
      expect(s.doc, 'one');
    });

    test('supports transaction-level inverted effects', () {
      final set = StateEffect.define<int>();
      final field = StateField.define<int>(
        create: (_) => 0,
        update: (v, tr) {
          for (final e in tr.effects) {
            final found = set.cast(e);
            if (found != null) v = found.value;
          }
          return v;
        },
      );
      final invert = invertedEffects.of((tr) => <StateEffect<Object?>>[
        for (final e in tr.effects)
          if (e.isOf(set)) set.of(tr.startState.field(field)),
      ]);
      final s = Session('', extensions: <Extension>[field, invert]);
      s.time += 100;
      s.state = s.state.update(TransactionSpec(effects: set.of(10), annotations: Transaction.time.of(s.time))).state;
      s.type('x', gap: 2000, effects: set.of(20));
      expect(s.state.field(field), 20);
      expect(undoDepth(s.state), 2);
      s.run(undo);
      expect(s.state.field(field), 10);
      expect(s.doc, '');
      s.run(undo);
      expect(s.state.field(field), 0);
      s.run(redo);
      s.run(redo);
      expect(s.state.field(field), 20);
      expect(s.doc, 'x');
    });

    test('is absent without the extension', () {
      var state = EditorState.create(doc: 'x');
      expect(state.fieldOrNull(historyField), isNull);
      expect(undoDepth(state), 0);
      expect(redoDepth(state), 0);
      expect(undo(StateCommandTarget(state, (tr) => state = tr.state)), isFalse);
    });

    test('reads its JSON back and undoes from it', () {
      final s = Session('one')
        ..type(' two')
        ..type(' three', gap: 2000);
      s.run(undo);
      final fields = <String, StateField<Object?>>{'history': historyField};
      final json = jsonDecode(jsonEncode(s.state.toJson(fields)));
      var back = EditorState.fromJson(json, extensions: history(), fields: fields);
      expect(undoDepth(back), 1);
      expect(redoDepth(back), 1);
      redo(StateCommandTarget(back, (tr) => back = tr.state));
      expect(back.doc.toString(), 'one two three');
      undo(StateCommandTarget(back, (tr) => back = tr.state));
      undo(StateCommandTarget(back, (tr) => back = tr.state));
      expect(back.doc.toString(), 'one');
    });
  });

  group('the undo slot', () {
    test('holds the local history, and can be emptied or swapped', () {
      var state = EditorState.create(doc: 'one', extensions: undoSlot.of(localUndo()));
      state = state.update(const TransactionSpec(changes: ChangeSpec(from: 3, insert: '!'))).state;
      expect(undoDepth(state), 1);
      // Going live: the slot's history leaves, and the note's own undo has nothing to say.
      state = state.update(TransactionSpec(effects: undoSlot.reconfigure(const Extension.list(<Extension>[])))).state;
      expect(state.fieldOrNull(historyField), isNull);
      expect(undo(StateCommandTarget(state, (tr) => state = tr.state)), isFalse);
      // And back: a new history, starting empty.
      state = state.update(TransactionSpec(effects: undoSlot.reconfigure(localUndo()))).state;
      expect(undoDepth(state), 0);
      state = state.update(const TransactionSpec(changes: ChangeSpec(from: 0, insert: '>'))).state;
      expect(undoDepth(state), 1);
    });
  });
}
