// The run log (lib/ai/log.dart). A port of `src/app/ai/log.test.ts`, case for case.

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/log.dart';
import 'package:ghost_md/core/stored.dart';

RunRecord record(String id, [String noteId = 'n', int at = 0]) =>
    RunRecord(id: id, noteId: noteId, kind: RunKind.format, instruction: null, model: 'qwen3.5-4b', at: at, ms: 1000, outputTokens: 5, outcome: RunOutcome.done, message: null, truncated: false);

void main() {
  setUp(() => useStored(MemoryStored()));

  group('the run log', () {
    test('keeps a note’s runs newest first, a handful at most', () {
      for (var i = 0; i < 10; i += 1) {
        recordRun(record('r$i', 'n', i));
      }
      final kept = runsOf('n');
      expect(kept.length, 8);
      expect(kept[0].id, 'r9');
      expect(kept[7].id, 'r2');
      expect(runsOf('other'), isEmpty);
    });

    test('replaces a record written twice, and keeps notes apart', () {
      recordRun(record('r1', 'a'));
      recordRun(record('r1', 'a').copyWith(outcome: RunOutcome.stopped));
      recordRun(record('r2', 'b'));
      expect([for (final r in runsOf('a')) r.outcome], [RunOutcome.stopped]);
      expect([for (final r in runsOf('b')) r.id], ['r2']);
    });

    test('remembers the words before and after a run that changed the note, until it is undone', () {
      recordRun(record('r1'));
      recordChange('n', 'r1', 'before', 'after');
      expect(runsOf('n')[0].before, 'before');
      expect(runsOf('n')[0].after, 'after');
      recordUndone('n', 'r1');
      expect(runsOf('n')[0].before, isNull);
      // A run the log never had is left alone.
      recordChange('n', 'nope', 'b', 'a');
      expect(runsOf('n').length, 1);
    });

    test('forgets a deleted note', () {
      recordRun(record('r1'));
      forgetRuns('n');
      expect(runsOf('n'), isEmpty);
    });
  });
}
