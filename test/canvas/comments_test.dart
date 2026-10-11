import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/comments.dart';
import 'package:ghost_md/canvas/edits.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/comments/format.dart' show Stamp;

import 'samples.dart';

/// A canvas's threads: started, replied to, resolved, reopened, taken off, and read for the card and the rounds.
/// `src/app/canvas/comments.test.ts`, case for case.
void main() {
  final canvas = Canvas(
    nodes: [
      CanvasNode.text(id: 'book', x: 0, y: 0, width: 260, height: 100, text: '# Book the cabin\n\nBy Friday.'),
      CanvasNode.link(id: 'site', x: 0, y: 160, width: 260, height: 100, url: 'https://attack.fm/glyph'),
      CanvasNode.group(id: 'g', x: -40, y: -40, width: 600, height: 400, label: 'Before'),
      CanvasNode.file(id: 'note', x: 300, y: 0, width: 260, height: 100, file: 'Plans/Cabin trip.md'),
    ],
    edges: const [],
  );
  const matt = Stamp(by: 'matt', at: '2026-10-05T14:00:00Z');
  const sam = Stamp(by: 'sam', at: '2026-10-05T14:05:00Z');

  group('a canvas’s threads', () {
    test('starts one on a card with the words trimmed, replies under it, resolves, reopens and takes it off', () {
      final started = withThread(canvas, 'book', matt, '  Which Friday?  ', 'c1')!;
      expect(started.comments, [isRecord({'id': 'c1', 'node': 'book', 'by': 'matt', 'at': matt.at, 'text': 'Which Friday?', 'replies': <Object?>[]})]);
      expect(withThread(canvas, 'nobody', matt, 'x'), isNull);
      expect(withThread(canvas, 'book', matt, '   '), isNull);
      final replied = withReply(started, 'c1', sam, 'The 10th.')!;
      expect(replied.comments![0].replies, [CanvasReply.of(by: 'sam', at: sam.at, text: 'The 10th.')]);
      expect(withReply(started, 'c9', sam, 'x'), isNull);
      final resolved = resolvedThread(replied, 'c1', sam)!;
      expect(resolved.comments![0].resolved, (by: 'sam', at: sam.at));
      expect(reopenedThread(resolved, 'c1')!.comments![0].resolved, isNull);
      expect(reopenedThread(resolved, 'c1')!.comments![0].fields.containsKey('resolved'), isFalse);
      expect(withoutThread(resolved, 'c1')!.comments, isNull);
      expect(withoutThread(canvas, 'c1'), isNull);
      // The canvas itself is never changed in place.
      expect(canvas.comments, isNull);
    });

    test('draws the threads as the card wants them, oldest first, and a card’s own apart', () {
      final two = withThread(withThread(canvas, 'site', sam, 'Dead link?', 'c2')!, 'book', matt, 'Which Friday?', 'c1')!;
      expect(threadsOf(two).map((thread) => thread.id), ['c1', 'c2']);
      final first = threadsOf(two)[0];
      expect((first.id, first.head, first.replies, first.resolved), ('c1', (by: 'matt', at: matt.at, words: 'Which Friday?'), first.replies, null));
      expect(first.replies, isEmpty);
      expect(threadsOn(two, 'site').map((thread) => thread.id), ['c2']);
      expect(threadsOn(two, 'g'), isEmpty);
    });

    test('marks a card by who started its first open thread and how many are open, hollow once all are resolved', () {
      final one = withThread(canvas, 'book', matt, 'A', 'c1')!;
      final two = withThread(one, 'book', sam, 'B', 'c2')!;
      expect(markOf(two, 'book'), (count: 2, open: 2, by: 'matt'));
      expect(markOf(two, 'site'), isNull);
      final first = resolvedThread(two, 'c1', sam)!;
      expect(markOf(first, 'book'), (count: 2, open: 1, by: 'sam'));
      final all = resolvedThread(first, 'c2', matt)!;
      expect(markOf(all, 'book'), (count: 2, open: 0, by: 'matt'));
    });

    test('quotes what a card says: its first line, its name, its address or its note’s title', () {
      expect(quoteOf(canvas, 'book'), '# Book the cabin');
      expect(quoteOf(canvas, 'g'), 'Before');
      expect(quoteOf(canvas, 'site'), 'https://attack.fm/glyph');
      expect(quoteOf(canvas, 'note'), 'Cabin trip');
      expect(quoteOf(canvas, 'nobody'), isNull);
      final long = Canvas(nodes: [canvas.nodes[0].put({'text': 'x' * 120})], edges: const []);
      expect(quoteOf(long, 'book'), hasLength(90));
    });

    test('gives a thread an id the canvas has not used, and lets a card’s threads go with the card', () {
      final one = withThread(canvas, 'book', matt, 'A', 'c1')!;
      final ids = <String>{};
      var roll = 0;
      double random() => ((roll += 7) % 36) / 36;
      for (var i = 0; i < 5; i += 1) {
        ids.add(freshThreadId(one, random));
      }
      expect(ids.contains('c1'), isFalse);
      expect(ids.every((id) => RegExp(r'^c[0-9a-z]{4,}$').hasMatch(id)), isTrue);
      final two = withThread(one, 'site', sam, 'B', 'c2')!;
      expect(withoutNode(two, 'book').comments, [two.comments![1]]);
      expect(withoutNode(withoutNode(two, 'book'), 'site').comments, isNull);
    });
  });
}
