import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/versions_diff.dart';

/// The change from one version to the next (lib/core/versions_diff.dart): the web's
/// `src/app/core/versions/diff.test.ts`, case for case, and `firstChange`, which the page tries through its log.
String? round(String before, String after) => applySteps(linesOf(before), diffLines(linesOf(before), linesOf(after)))?.join('\n');

void main() {
  group('the change from one version to the next', () {
    test('is only the lines that changed, with the rest kept in runs', () {
      final steps = diffLines(['# Plan', 'a', 'b', 'c', 'end'], ['# Plan', 'a', 'B', 'c', 'end']);
      expect(steps, const [Keep(2), Del('b'), Add('B'), Keep(2)]);
      expect(countSteps(steps), (added: 1, removed: 1));
    });

    test('turns any version into any other, exactly, trailing newline and blank lines included', () {
      const cases = [
        ('', '# New\n'),
        ('# New\n', ''),
        ('a\nb\nc', 'c\nb\na'),
        ('one\n\ntwo\n\n', '\none\ntwo\n\n\n'),
        ('x\ny\nz\nx\ny\nz', 'y\nz\nx\ny\nq\nz\nx'),
        ('same', 'same'),
      ];
      for (final (before, after) in cases) {
        expect(round(before, after), after, reason: jsonEncode([before, after]));
      }
    });

    test('finds the shortest change, as git does, on a note with lines moved about', () {
      final before = linesOf('a\nb\nc\na\nb\nb\na');
      final after = linesOf('c\nb\na\nb\na\nc');
      final steps = diffLines(before, after);
      // Myers' own example: five lines out and in, no fewer.
      final (:added, :removed) = countSteps(steps);
      expect(added + removed, 5);
      expect(applySteps(before, steps)?.join('\n'), after.join('\n'));
      // And the same script the page finds, step for step (asked of the web's module, 2026-10-07).
      expect(steps, const [Del('a'), Del('b'), Keep(1), Add('b'), Keep(2), Del('b'), Keep(1), Add('c')]);
    });

    test('refuses steps that do not fit the version they are applied to', () {
      expect(applySteps(['a', 'b'], const [Keep(1), Del('x')]), isNull);
      expect(applySteps(['a'], const [Keep(3)]), isNull);
      expect(applySteps(['a'], const [Keep(1), Del('a')]), isNull);
      expect(applySteps(['a'], const [Keep(-1)]), isNull);
      // A change written without its last keep still reads.
      expect(applySteps(['a', 'b', 'c'], const [Del('a')]), ['b', 'c']);
    });

    test('copes with a long note in good time', () {
      final before = [for (var i = 0; i < 4000; i += 1) 'line $i'];
      final after = [for (final (i, line) in before.indexed) i % 97 == 0 ? '$line changed' : line];
      final started = Stopwatch()..start();
      final steps = diffLines(before, after);
      expect(started.elapsedMilliseconds, lessThan(1000));
      expect(applySteps(before, steps), after);
    });
  });

  group('the first line a version changed', () {
    test('is the first put in or taken out that says anything, and nothing for blank lines alone', () {
      expect(firstChange(null, '# Plan\n- venue'), (kind: 'add', text: '# Plan'));
      expect(firstChange('# Plan\n- venue', '# Plan\n- venue (done)'), (kind: 'del', text: '- venue'));
      expect(firstChange('# Plan', '# Plan\n\n   \n  - indented  '), (kind: 'add', text: '- indented'));
      expect(firstChange('a\n\n', 'a'), isNull);
      expect(firstChange('same', 'same'), isNull);
      expect(linesFrom(null), isEmpty);
      expect(linesFrom(''), ['']);
    });
  });
}
