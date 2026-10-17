// The pace Claude's words are let into a note at (lib/claude/typing_pacer.dart): a reader's rate while the stream
// keeps up, rising smoothly so it is never more than about two seconds behind, whole words, a word still arriving
// held for its end, everything at once on a flush, and the words that come out exactly the words that went in.
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/claude/typing_pacer.dart';

const Duration _frame = Duration(milliseconds: 16);

/// A paragraph of ordinary words, [count] of them.
String _words(int count, {int seed = 1}) {
  final random = math.Random(seed);
  const pool = ['the', 'quick', 'note', 'Claude', 'writes', 'in', 'markdown', '**bold**', 'a', 'list:', '- item', '[[Weekend plan]]', 'and', 'then', 'more.'];
  return [for (var i = 0; i < count; i++) pool[random.nextInt(pool.length)]].join(' ');
}

/// What a pacer let out, frame by frame: each piece and the moment it went.
class _Run {
  final List<({Duration at, String text})> out = [];
  String get text => out.map((piece) => piece.text).join();
}

/// Asks [pacer] every frame from [from] until [until], or until it is empty when [untilEmpty].
void _tick(TypingPacer pacer, _Run run, Duration from, Duration until, {bool untilEmpty = false}) {
  for (var now = from; now <= until; now += _frame) {
    final text = pacer.release(now);
    if (text.isNotEmpty) run.out.add((at: now, text: text));
    if (untilEmpty && pacer.isEmpty) return;
  }
}

void main() {
  group('the pace Claude types at', () {
    test('lets a short passage out at a reader\'s pace, a word at a time, when the stream keeps up', () {
      final pacer = TypingPacer();
      // Sixty letters at once, which a reader's pace can type within the time allowed: no hurry.
      final words = 'Pack the bags, book the early train and water the plants now ';
      pacer.add(words, Duration.zero);
      final run = _Run();
      _tick(pacer, run, Duration.zero, const Duration(seconds: 5), untilEmpty: true);
      expect(run.text, words);
      final took = run.out.last.at.inMilliseconds / 1000;
      // At sixty letters a second, 61 letters take about a second.
      expect(took, closeTo(words.length / pacerRestRate, 0.12));
      // Every piece is a word and the spaces after it.
      for (final piece in run.out) {
        expect(piece.text.trim(), isNot(contains(' ')), reason: '"${piece.text}" is more than one word');
        expect(piece.text, endsWith(' '));
      }
      // And at a steady rate: no gap between words longer than a long word takes.
      for (var i = 1; i < run.out.length; i++) {
        expect((run.out[i].at - run.out[i - 1].at).inMilliseconds, lessThanOrEqualTo(200));
      }
    });

    test('speeds up smoothly under a backlog and is never more than about two seconds behind', () {
      final pacer = TypingPacer();
      final words = _words(400);
      pacer.add(words, Duration.zero);
      final run = _Run();
      final rates = <double>[];
      for (var now = Duration.zero; now <= const Duration(seconds: 10) && !pacer.isEmpty; now += _frame) {
        final text = pacer.release(now);
        if (text.isNotEmpty) run.out.add((at: now, text: text));
        rates.add(pacer.rate);
      }
      expect(run.text, words);
      // A couple of thousand letters at once are all in within about two seconds.
      expect(run.out.last.at, lessThanOrEqualTo(const Duration(milliseconds: 2500)));
      expect(rates.reduce(math.max), greaterThan(pacerRestRate * 5));
      // The rate rises over a few frames, never jumping from a reader's pace to the catch-up at once.
      expect(rates.first, lessThan(rates.reduce(math.max) / 4));
      for (var i = 1; i < rates.length; i++) {
        expect(rates[i] - rates[i - 1], lessThan(rates.reduce(math.max) * 0.1), reason: 'frame $i');
      }
    });

    test('keeps within about two seconds of a stream faster than a reader, letter by letter, however long it runs', () {
      final pacer = TypingPacer();
      final words = _words(600, seed: 7);
      // The stream hands over 300 letters a second in bursts of about forty, every eighth of a second.
      final arrived = <int, Duration>{};
      final run = _Run();
      var sent = 0;
      var now = Duration.zero;
      var released = 0;
      var worst = Duration.zero;
      while (released < words.length) {
        if (sent < words.length && now.inMilliseconds % 125 < _frame.inMilliseconds) {
          final piece = words.substring(sent, math.min(words.length, sent + 38));
          pacer.add(piece, now);
          for (var i = sent; i < sent + piece.length; i++) {
            arrived[i] = now;
          }
          sent += piece.length;
          if (sent >= words.length) pacer.finish();
        }
        final text = pacer.release(now);
        if (text.isNotEmpty) {
          run.out.add((at: now, text: text));
          for (var i = released; i < released + text.length; i++) {
            final behind = now - arrived[i]!;
            if (behind > worst) worst = behind;
          }
          released += text.length;
        }
        now += _frame;
        expect(now, lessThan(const Duration(seconds: 60)));
      }
      expect(run.text, words);
      expect(worst, lessThanOrEqualTo(const Duration(milliseconds: 2500)));
      // And it really did slow the stream down to a reader's sight of it at first: not all at once.
      expect(run.out.length, greaterThan(100));
    });

    test('never splits a word, holds one still arriving for its end, and lets it go once nothing more is coming', () {
      final pacer = TypingPacer();
      pacer.add('Hello wor', Duration.zero);
      final run = _Run();
      _tick(pacer, run, Duration.zero, const Duration(milliseconds: 200));
      expect(run.text, 'Hello ');
      // More of the word comes before it has waited long: it goes whole.
      pacer.add('ld and', const Duration(milliseconds: 210));
      _tick(pacer, run, const Duration(milliseconds: 216), const Duration(milliseconds: 400));
      expect(run.text, 'Hello world ');
      // Nothing more is coming: the last word goes as it is.
      pacer.finish();
      _tick(pacer, run, const Duration(milliseconds: 416), const Duration(milliseconds: 500));
      expect(run.text, 'Hello world and');
      expect(pacer.isEmpty, isTrue);
    });

    test('lets a word still arriving go as it is when the stream has gone quiet a while', () {
      final pacer = TypingPacer();
      pacer.add('Thinking', Duration.zero);
      final run = _Run();
      _tick(pacer, run, Duration.zero, pacerWordWait - _frame);
      expect(run.text, isEmpty);
      _tick(pacer, run, pacerWordWait, pacerWordWait + const Duration(milliseconds: 200));
      expect(run.text, 'Thinking');
    });

    test('lets a word longer than a piece go in pieces, never half a letter', () {
      final pacer = TypingPacer();
      final long = 'https://example.com/${'😀' * 30}/end ';
      pacer.add(long, Duration.zero);
      final run = _Run();
      _tick(pacer, run, Duration.zero, const Duration(seconds: 5), untilEmpty: true);
      expect(run.text, long);
      for (final piece in run.out) {
        expect(piece.text.length, lessThanOrEqualTo(pacerLongestPiece + 2));
        final last = piece.text.codeUnitAt(piece.text.length - 1);
        expect(last >= 0xD800 && last <= 0xDBFF, isFalse, reason: 'half a letter at the end of "${piece.text}"');
      }
    });

    test('lets everything out at once on a flush, and starts again from a reader\'s pace', () {
      final pacer = TypingPacer();
      final words = _words(200, seed: 3);
      pacer.add(words, Duration.zero);
      final run = _Run();
      _tick(pacer, run, Duration.zero, const Duration(milliseconds: 300));
      expect(run.text.length, lessThan(words.length));
      final rest = pacer.flush();
      expect(run.text + rest, words);
      expect(pacer.isEmpty, isTrue);
      expect(pacer.flush(), isEmpty);
      // A quiet spell banks nothing: the next words start at a reader's pace.
      pacer.add('one two three ', const Duration(seconds: 30));
      expect(pacer.rate, pacerRestRate);
      expect(pacer.release(const Duration(seconds: 30)), isEmpty);
      expect(pacer.release(const Duration(seconds: 30) + const Duration(milliseconds: 70)), 'one ');
    });

    test('lets out exactly the words that went in, however the stream cuts them', () {
      final random = math.Random(11);
      for (var round = 0; round < 20; round++) {
        final pacer = TypingPacer();
        final words = '${_words(80, seed: round)}\n\n## Heading ${'é' * 5} 🎉🎉\n- [ ] one\n\ttabbed${' ' * 3}end';
        final run = _Run();
        var sent = 0;
        var now = Duration.zero;
        while (sent < words.length || !pacer.isEmpty) {
          if (sent < words.length && random.nextInt(3) == 0) {
            final size = math.min(words.length - sent, 1 + random.nextInt(30));
            pacer.add(words.substring(sent, sent + size), now);
            sent += size;
            if (sent == words.length) pacer.finish();
          }
          final text = pacer.release(now);
          if (text.isNotEmpty) run.out.add((at: now, text: text));
          now += _frame;
          if (round.isOdd && now > const Duration(seconds: 2) && sent == words.length) run.out.add((at: now, text: pacer.flush()));
        }
        expect(run.text, words, reason: 'round $round');
      }
    });
  });
}
