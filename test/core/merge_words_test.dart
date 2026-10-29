// A note's words changed on two sides since they last agreed, put together line by line (lib/core/merge_words.dart):
// what a meeting's summary from one device and its transcript from another become (Matt, 2026-10-29: "make it so the
// transcripts and meeting summaries are shown in one file"), and what is never guessed at.
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
}
