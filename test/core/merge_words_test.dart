// A note's words changed on two sides since they last agreed, put together line by line (lib/core/merge_words.dart):
// what a meeting's summary from one device and its transcript from another become (Matt, 2026-10-29: "make it so the
// transcripts and meeting summaries are shown in one file"), and what is never guessed at.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/merge_words.dart';
import 'package:ghost_md/core/summary_text.dart';

const String filed = '# Engineering Standup\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06. It is being written up on your device.\n\n## Captions\n\n**Sam Lee (0:04):** Morning.\n';
const String section = '## Summary\n\nThe team agreed to ship today.\n\n- [ ] Matt: ship the build';
const String heard = '# Engineering Standup\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06.\n\n## Transcript\n\n**Sam Lee (0:04):** Morning.';

void main() {
  test('a meeting’s summary written on one side and its transcript landed on the other: both, the summary under the title, the transcript below', () {
    final summarized = withSummary(filed, section);
    final merged = mergedWords(filed, heard, summarized);
    expect(merged, '# Engineering Standup\n\n$section\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06.\n\n## Transcript\n\n**Sam Lee (0:04):** Morning.');
    // Either way round.
    expect(mergedWords(filed, summarized, heard), merged);
    expect(summarySection(merged!)?.text, section);
  });

  test('one side unchanged: the other’s words; both the same: those', () {
    expect(mergedWords('a\nb', 'a\nb', 'a\nc'), 'a\nc');
    expect(mergedWords('a\nb', 'a\nc', 'a\nb'), 'a\nc');
    expect(mergedWords('a\nb', 'a\nc', 'a\nc'), 'a\nc');
  });

  test('changes at different lines both stand; the same change on both sides goes in once', () {
    expect(mergedWords('one\ntwo\nthree\nfour', 'ONE\ntwo\nthree\nfour', 'one\ntwo\nthree\nFOUR'), 'ONE\ntwo\nthree\nFOUR');
    expect(mergedWords('one\ntwo\nthree', 'one\nTWO\nthree\nmine', 'one\nTWO\nthree'), 'one\nTWO\nthree\nmine');
  });

  test('two changes to the same lines, or two different lines put in at one place, are a clash, never a guess', () {
    expect(mergedWords('one\ntwo\nthree', 'one\nmine\nthree', 'one\ntheirs\nthree'), isNull);
    expect(mergedWords('one\nthree', 'one\nmine\nthree', 'one\ntheirs\nthree'), isNull);
    // A line put in strictly inside a run the other side rewrote.
    expect(mergedWords('a\nb\nc\nd', 'a\nX\nY\nd', 'a\nb\nnew\nc\nd'), isNull);
  });

  test('withSummaryOf: a clash keeps its own words, with the other side’s summary where they have none', () {
    final summarized = withSummary(filed, section);
    expect(summarySection(withSummaryOf(heard, summarized))?.text, section);
    expect(withSummaryOf(heard, summarized), contains('## Transcript'));
    expect(withSummaryOf(heard, heard), heard);
    // A summary of its own stays: the other side's is never put over it.
    final own = withSummary(heard, '## Summary\n\nMine.');
    expect(withSummaryOf(own, summarized), own);
  });

  // The Testing session's review, 2026-10-29: two neighbouring hunks, one ending where the other begins, are not a
  // clash here, where git's diff3 would call them one. A table whose two neighbouring rows are edited one on each side.
  test('a table’s two neighbouring rows, one edited on each side: both edits, each row once, the table whole', () {
    const base = '# Plan\n\n| Who | What |\n| --- | --- |\n| Sam | the press list |\n| Matt | the build |\n| Ana | the venue |\n';
    const mine = '# Plan\n\n| Who | What |\n| --- | --- |\n| Sam | the press list, by Friday |\n| Matt | the build |\n| Ana | the venue |\n';
    const theirs = '# Plan\n\n| Who | What |\n| --- | --- |\n| Sam | the press list |\n| Matt | the build, signed |\n| Ana | the venue |\n';
    expect(mergedWords(base, mine, theirs), '# Plan\n\n| Who | What |\n| --- | --- |\n| Sam | the press list, by Friday |\n| Matt | the build, signed |\n| Ana | the venue |\n');
    // The same row edited on both sides is the one clash.
    expect(mergedWords(base, mine, mine.replaceFirst('by Friday', 'by Monday')), isNull);
    // A row put in between the two edited rows on one side, and a row edited beside it on the other.
    const added = '# Plan\n\n| Who | What |\n| --- | --- |\n| Sam | the press list |\n| Lee | the slides |\n| Matt | the build |\n| Ana | the venue |\n';
    expect(mergedWords(base, mine, added), '# Plan\n\n| Who | What |\n| --- | --- |\n| Sam | the press list, by Friday |\n| Lee | the slides |\n| Matt | the build |\n| Ana | the venue |\n');
  });

  test('the diff rebuilds either side exactly: a line put in at an end on one side and any edits on the other give those edits with the line (500 random notes)', () {
    final random = Random(29);
    String note(int lines) => [for (var i = 0; i < lines; i += 1) random.nextInt(4) == 0 ? '' : 'line ${random.nextInt(12)}'].join('\n');
    var merged = 0;
    for (var i = 0; i < 500; i += 1) {
      final base = note(random.nextInt(40));
      final lines = base.split('\n');
      final edited = <String>[];
      for (final line in lines) {
        final roll = random.nextInt(10);
        if (roll == 0) continue;
        if (roll == 1) edited.add('new ${random.nextInt(5)}');
        edited.add(roll == 2 ? 'changed ${random.nextInt(5)}' : line);
      }
      if (random.nextBool()) edited.add('tail ${random.nextInt(3)}');
      final other = edited.join('\n');
      final atEnd = mergedWords(base, other, '$base\nUNIQUE');
      if (atEnd != null) {
        expect(atEnd, '$other\nUNIQUE', reason: 'base ${jsonish(base)}, other ${jsonish(other)}');
        merged += 1;
      }
      final atTop = mergedWords(base, other, 'UNIQUE\n$base');
      if (atTop != null) expect(atTop, 'UNIQUE\n$other', reason: 'base ${jsonish(base)}, other ${jsonish(other)}');
    }
    expect(merged, greaterThan(250), reason: 'most of them merge');
  });

  // The Testing session's review, 2026-10-29: the transcript's side of a meeting drops `## Captions` and puts
  // `## Transcript` in, both thousands of lines. The versions' diff would hold its whole trace for that, about
  // (n+m)² × 8 bytes; this one holds two rows of the diagonals.
  test('a 4,000-line captions to transcript swap on one side and a summary on the other: merged, in bounded memory and time', () {
    String turns(String heading, String Function(int i) words) => '$heading\n\n${[for (var i = 0; i < 2000; i += 1) words(i)].join('\n\n')}';
    final captions = turns('## Captions', (i) => '**Speaker ${i % 7} (${i ~/ 60}:${(i % 60).toString().padLeft(2, '0')}):** caption words number $i, as Meet heard them.');
    final transcript = turns('## Transcript', (i) => '**Speaker ${i % 7} (${i ~/ 60}:${(i % 60).toString().padLeft(2, '0')}):** what Whisper heard, part $i.');
    final base = '# Engineering Standup\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06. It is being written up on your device.\n\n$captions\n';
    final mine = '# Engineering Standup\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06.\n\n$transcript\n';
    final theirs = withSummary(base, section);
    expect(base.split('\n').length, greaterThan(4000));
    final clock = Stopwatch()..start();
    final merged = mergedWords(base, mine, theirs);
    clock.stop();
    final n = base.split('\n').length, m = mine.split('\n').length;
    // What the versions' diff would have held: a row of 2(n+m)+2 four-byte integers for each of D ≈ the lines changed.
    final trace = (n + m) * (2 * (n + m) + 2) * 4;
    // ignore: avoid_print
    print('merge of $n and $m lines: ${clock.elapsedMilliseconds} ms, the diffs held at most $mergeDiffPeakBytes bytes (the versions’ diff up to ~${trace ~/ 1000000} MB)');
    expect(merged, '# Engineering Standup\n\n$section\n\nGhost was in this meeting on 29 Oct, 09:28 to 10:06.\n\n$transcript\n');
    expect(mergeDiffPeakBytes, lessThan(1 << 20), reason: 'linear in the lines: under a megabyte');
    expect(clock.elapsed, lessThan(const Duration(seconds: 10)), reason: 'generous for a loaded machine');
  });

  test('a merge past its work answers null quickly, and the fallback keeps the summary', () {
    // Thirty thousand lines changed every one, with blank lines between them in common: hundreds of millions of steps
    // to diff whole, stopped at the budget.
    String every(String word) => [for (var i = 0; i < 15000; i += 1) '$word $i\n'].join('\n');
    final base = '# Notes\n\n${every('was')}';
    final mine = '# Notes\n\n${every('now')}';
    final theirs = withSummary(base, section);
    final clock = Stopwatch()..start();
    expect(mergedWords(base, mine, theirs), isNull);
    clock.stop();
    // ignore: avoid_print
    print('stopped at the budget after ${clock.elapsedMilliseconds} ms, holding at most $mergeDiffPeakBytes bytes');
    expect(clock.elapsed, lessThan(const Duration(seconds: 20)));
    expect(summarySection(withSummaryOf(mine, theirs))?.text, section);
    // And more lines than a side may have is not looked at.
    final huge = List.filled(mergeLinesMost + 1, 'x').join('\n');
    expect(mergedWords('a', huge, 'b'), isNull);
  });
}

String jsonish(String text) => text.replaceAll('\n', r'\n');
