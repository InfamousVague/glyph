import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/art/wisp.dart';

/// The plan behind words from smoke, case for case with the web app's art/wisp.test.ts.
void main() {
  // 100 ms a letter, no jitter.
  final steady = cadence(10, () => 0.5);

  group('words from smoke: the plan', () {
    test('splits a text into words and the gaps between them, and the join is the text', () {
      const text = 'Hold.\nTalk.  Done.';
      final tokens = tokenize(text);
      expect(tokens.map((t) => t.toString()).toList(), ['word:"Hold."', 'gap:"\n"', 'word:"Talk."', 'gap:"  "', 'word:"Done."']);
      expect(tokens.map((t) => t.text).join(), text);
      expect(tokenize(''), isEmpty);
    });

    test('keeps the words a new text still has, in order, and swaps the rest', () {
      final diff = diffWords(tokenize('Hold. Talk. Done.'), tokenize('Hold. Talk. Write.'));
      expect(diff.kept, {0: 0, 2: 2});
      expect(diff.gone, [4]);
      expect(diff.arriving, [4]);
    });

    test('treats a word that moved as leaving and arriving, not sliding', () {
      final diff = diffWords(tokenize('one two three'), tokenize('three one two'));
      // The longest run in order is "one two"; "three" leaves the end and arrives at the front.
      expect(diff.kept.length, 2);
      expect(diff.gone, [4]);
      expect(diff.arriving, [0]);
    });

    test('types arriving letters one at a time, pausing at gaps and after a full stop', () {
      final tokens = tokenize('Hold. Done.');
      final steps = arrivals(tokens, [0, 2], steady);
      expect(steps.map((s) => '${s.token}:${s.char}').toList(), ['0:0', '0:1', '0:2', '0:3', '0:4', '2:0', '2:1', '2:2', '2:3', '2:4']);
      final at = steps.map((s) => s.at).toList();
      expect(at, [...at]..sort());
      // After "." a long breath (five beats), then the gap before a capital adds one more.
      expect(at[5] - at[4], greaterThan((at[1] - at[0]) * 4));
      expect(at[5] - at[4], closeTo(100 + 500 + 100 + 80, 1e-9));
    });

    test('leaves kept words alone: only the arriving word takes time', () {
      final tokens = tokenize('Hold. Talk. Write.');
      final steps = arrivals(tokens, [4], steady);
      expect(steps.map((s) => s.token).toList(), [4, 4, 4, 4, 4, 4]);
      // The gap before it is a beat.
      expect(steps.first.at, greaterThan(0));
    });

    test('untypes a leaving word from its last letter, quicker than typing', () {
      final tokens = tokenize('Hold. Done.');
      final steps = departures(tokens, [2], 30);
      expect(steps.map((s) => '${s.char}@${s.at.toInt()}').toList(), ['4@0', '3@30', '2@60', '1@90', '0@120']);
    });

    test('plans a swap as out then in, and says how long each takes', () {
      final plan = planSwap('Hold. Talk. Done.', 'Hold. Talk. Write.', steady, 30);
      expect(plan.out.map((s) => s.token).toList(), [4, 4, 4, 4, 4]);
      expect(plan.arrive.map((s) => s.token).toList(), [4, 4, 4, 4, 4, 4]);
      expect(runLength(plan.out, 500), 120 + 500);
      expect(runLength(const [], 500), 0);
    });

    test('arrives everything the first time', () {
      final plan = planSwap('', 'Hold. Talk.', steady);
      expect(plan.diff.arriving, [0, 2]);
      expect(plan.out, isEmpty);
      expect(plan.arrive.length, 10);
    });

    test('paces a hand: a breath after a comma, longer at a line break', () {
      expect(steady('a', 'b'), closeTo(100, 1e-9));
      expect(steady(',', ' '), closeTo(350, 1e-9));
      expect(steady('\n', 'x'), closeTo(700, 1e-9));
      expect(steady(' ', 'T'), closeTo(180, 1e-9));
      expect(steady(' ', 't'), closeTo(100, 1e-9));
    });
  });
}
