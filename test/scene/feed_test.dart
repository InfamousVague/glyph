import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/ai/kinds.dart';
import 'package:ghost_md/ai/review_stage.dart';
import 'package:ghost_md/ai/runs.dart';
import 'package:ghost_md/scene/feed.dart';
import 'package:ghost_md/scene/steps.dart';

import 'support.dart' as support;

/// What scrolls through the phone: the transcript's phrases, the note's lines, the thought and the findings, each
/// line by an absolute index that never moves. The cases of `src/app/scene/feed.test.ts`, by name.

/// The web's `run(over)` of this file: generating unless a case says otherwise, as the part the feed reads.
FeedRun run({RunKind kind = RunKind.review, RunPhase phase = RunPhase.generating, List<String> lines = const <String>[], String partial = '', String thought = '', int promptTokens = 0, int promptTokensDone = 0}) =>
    FeedRun.of(support.run(kind: kind, phase: phase, lines: lines, partial: partial, thought: thought, promptTokens: promptTokens, promptTokensDone: promptTokensDone));

const heard = 'Groceries for the week. Milk, eggs and coffee. Hey Ghost, add a task call the plumber about the seat bar. Then the garden.';
const body = '# Groceries\n\n- Milk, eggs and coffee\n- [ ] Call the plumber about the seat bar\n\nThen the garden.';

void main() {
  group('phrases', () {
    test('split at sentence ends, and about every fourteen words where there are none', () {
      expect(phrasesOf(heard), ['Groceries for the week.', 'Milk, eggs and coffee.', 'Hey Ghost, add a task call the plumber about the seat bar.', 'Then the garden.']);
      final long = [for (var i = 0; i < 30; i += 1) 'word${i + 1}'].join(' ');
      final runs = phrasesOf(long);
      expect([for (final r in runs) r.split(' ').length], [14, 16]);
      expect(runs.join(' '), long);
    });

    test('keep a numbered line together and join a phrase of a word or two to the next', () {
      expect(thoughtLines('1. Words. The two transcripts disagree in a few places. 2. Structure. The heading names the note.'), [
        '1. Words. The two transcripts disagree in a few places.',
        '2. Structure. The heading names the note.',
      ]);
      expect(phrasesOf('Thinking Process:\n\nFirst, the words. Is "seat bar" right? Probably not.'), ['Thinking Process: First, the words.', 'Is "seat bar" right?', 'Probably not.']);
    });

    test('leave a thought’s sentence whole, and cut only one past thirty words, at a clause end', () {
      const twenty = 'The slower model heard "seek bar" where the fast one heard "seat bar", a seek bar is the scrubber in a player, so seek is right.';
      expect(thoughtLines(twenty), [twenty]);
      // Past thirty words the sentence is cut at its semicolons and colons, never every fourteen words.
      const long = 'The slower model heard "seek bar" where the fast one heard "seat bar"; a seek bar is the scrubber in a player, so "seek" is right, and the task says the same words: the two agree once the spelling is put right.';
      expect(thoughtLines(long), [
        'The slower model heard "seek bar" where the fast one heard "seat bar";',
        'a seek bar is the scrubber in a player, so "seek" is right, and the task says the same words:',
        'the two agree once the spelling is put right.',
      ]);
      // With no clause end, a long sentence is one line and left to wrap.
      final plain = [for (var i = 0; i < 40; i += 1) 'word${i + 1}'].join(' ');
      expect(thoughtLines(plain), [plain]);
    });

    test('drop the note’s blank lines and its Markdown marks', () {
      expect(noteLines(body), ['Groceries', 'Milk, eggs and coffee', 'Call the plumber about the seat bar', 'Then the garden.']);
      expect(noteLines('## Two\n> quoted\n1. first\n* [x] done\n- - nested'), ['Two', 'quoted', 'first', 'done', 'nested']);
    });
  });

  group('the feed', () {
    test('shows the transcript through the stages, the head at the listen’s share of it', () {
      ReviewStage stage(int percent) => ReviewStage(what: 'Listening again', detail: '', percent: percent);
      final feed = feedOf(stage: stage(50), run: null, heard: heard, body: body);
      expect(feed.mode, FeedMode.transcript);
      expect([for (final l in feed.lines) l.at], [0, 1, 2, 3]);
      expect(feed.current, 2);
      expect(feedOf(stage: stage(0), run: null, heard: heard, body: body).current, 0);
      expect(feedOf(stage: stage(100), run: null, heard: heard, body: body).current, 3);
      // Comparing, and a run not yet reading: every phrase, the head at the last.
      expect(feedOf(stage: const ReviewStage(what: 'Comparing', detail: '', percent: null), run: null, heard: heard, body: body).current, 3);
      final loading = feedOf(stage: null, run: run(phase: RunPhase.loading), heard: heard, body: body);
      expect(loading.mode, FeedMode.transcript);
      expect(loading.current, 3);
      expect(feedOf(stage: null, run: null, heard: '', body: body), const Feed(lines: <FeedLine>[], current: null, mode: FeedMode.transcript));
    });

    test('walks the transcript again and then the note’s lines while the model reads, by its share of the prompt', () {
      Feed reading(int done) => feedOf(stage: null, run: run(phase: RunPhase.prefill, promptTokens: 1000, promptTokensDone: done), heard: heard, body: body);
      final feed = reading(0);
      expect(feed.mode, FeedMode.reading);
      expect(feed.lines.length, 8);
      expect(feed.lines[4], const FeedLine(at: 4, text: 'Groceries'));
      expect(feed.current, 0);
      expect(reading(500).current, 4);
      expect(reading(1000).current, 7);
      // Before the first tick there is no share: the head stays at the top.
      expect(feedOf(stage: null, run: run(phase: RunPhase.prefill), heard: heard, body: body).current, 0);
    });

    test('wraps the thought by sentence, the tail the line under the pen', () {
      final feed = feedOf(stage: null, run: run(thought: 'The two transcripts disagree in a few places. The slower model heard "seek bar" where the fast'), heard: heard, body: body);
      expect(feed.mode, FeedMode.thought);
      expect(feed.lines, const [
        FeedLine(at: 0, text: 'The two transcripts disagree in a few places.'),
        FeedLine(at: 1, text: 'The slower model heard "seek bar" where the fast'),
      ]);
      expect(feed.current, 1);
    });

    test('reads the findings’ words out of the JSON as it is written, the open one typing in, and never the JSON', () {
      const thought = 'One sentence of thought.';
      const partial = '[{"check": "words", "what": "“seek bar”, not “seat bar”", "why": "It fits."}, {"check": "structure", "what": "The to-dos are a li';
      final feed = feedOf(stage: null, run: run(thought: thought, partial: partial), heard: heard, body: body);
      expect(feed.mode, FeedMode.findings);
      expect(feed.lines, const [
        FeedLine(at: 0, text: 'One sentence of thought.'),
        FeedLine(at: 1, text: '“seek bar”, not “seat bar”', strong: true),
        FeedLine(at: 2, text: 'The to-dos are a li', strong: true),
      ]);
      expect(feed.current, 2);
      expect(feed.lines.any((l) => l.text.contains('{') || l.text.contains('"check"')), isFalse);
      // Lines the engine finished, and the last complete finding with nothing open: the head on the last finding.
      final done = feedOf(stage: null, run: run(thought: thought, lines: ['[{"what": "One", "why": "x"},'], partial: ' {"what": "Two", "why": "y"}]'), heard: heard, body: body);
      expect(done.lines.sublist(1), const [
        FeedLine(at: 1, text: 'One', strong: true),
        FeedLine(at: 2, text: 'Two', strong: true),
      ]);
      expect(done.current, 2);
    });

    test('unescapes a finding’s words and gives the open one as the pen line', () {
      final open = findingsSoFar(r'[{"what": "Say \"hello\" here", "why": "x"}, {"what": "Then the g');
      expect(open.done, ['Say "hello" here']);
      expect(open.open, 'Then the g');
      final closed = findingsSoFar('[{"what": "A"}, {"what": "B"}]');
      expect(closed.done, ['A', 'B']);
      expect(closed.open, isNull);
      final none = findingsSoFar('[{"check": "words", ');
      expect(none.done, isEmpty);
      expect(none.open, isNull);
    });

    test('shows another kind’s prose as it lands', () {
      final feed = feedOf(stage: null, run: run(kind: RunKind.summarize, lines: ['## Summary', 'The point.'], partial: 'And the'), heard: heard, body: body);
      expect(feed.mode, FeedMode.prose);
      expect([for (final l in feed.lines) l.text], ['## Summary', 'The point.', 'And the']);
      expect(feed.current, 2);
    });

    test('keeps every line’s key as the window slides', () {
      final many = [for (var i = 0; i < 60; i += 1) 'Sentence number ${i + 1} here.'].join(' ');
      Feed at(int percent) => feedOf(stage: ReviewStage(what: 'Listening again', detail: '', percent: percent), run: null, heard: many, body: '');
      final early = paneWindow(at(10));
      expect(early.length, paneLines);
      expect(early[0].at, 0);
      final mid = paneWindow(at(50));
      expect(mid.length, paneLines);
      // Sixteen before the head (line 30), the head, and seven after.
      expect(mid[0].at, 14);
      expect(mid[16].at, 30);
      expect(mid.last.at, 37);
      // The lines kept between two windows keep their keys.
      final next = paneWindow(at(52));
      for (final line in next) {
        if (line.at >= 14 && line.at <= 37) expect(mid.firstWhere((m) => m.at == line.at).text, line.text);
      }
      final late = paneWindow(at(100));
      expect(late.last.at, 59);
      expect(late.length, paneLines);
      // A streaming mode keeps the newest.
      final thought = [for (var i = 0; i < 40; i += 1) 'Thought ${i + 1} is here.'].join(' ');
      final stream = paneWindow(feedOf(stage: null, run: run(thought: thought), heard: '', body: ''));
      expect(stream.length, paneLines);
      expect(stream.last.at, 39);
    });
  });
}
