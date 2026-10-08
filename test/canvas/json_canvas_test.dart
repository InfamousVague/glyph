import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/core/note_text.dart' show noteTitle;

import 'samples.dart';

/// The format read leniently and written exactly, and the note a canvas is: front matter naming it, then the JSON.
/// `src/app/canvas/jsonCanvas.test.ts` and `jsonCanvas.comments.test.ts`, case for case.
void main() {
  group('reading a JSON Canvas', () {
    test('reads every node and edge the spec describes, and rounds a position to the pixel', () {
      final canvas = parseCanvas(specSample)!;
      expect(canvas.nodes.map((n) => n.type.name), ['group', 'text', 'file', 'link']);
      expect(canvas.nodes[3], holds({'id': 'l1', 'y': 150, 'url': 'https://attack.fm/glyph', 'color': '#ff8800'}));
      expect(canvas.nodes[2], holds({'file': 'Plans/Cabin trip.md', 'subpath': '#^friday'}));
      expect(canvas.edges, [
        isRecord({'id': 'e1', 'fromNode': 't1', 'toNode': 'f1', 'fromSide': 'right', 'toSide': 'left', 'label': 'then'}),
        isRecord({'id': 'e2', 'fromNode': 't1', 'toNode': 'l1', 'toEnd': 'none', 'color': '2'}),
      ]);
    });

    test('leaves out what is not a node, an edge to a node that is not there, and a second node with the same id', () {
      final canvas = parseCanvas('''{
        "nodes": [
          { "id": "a", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "one" },
          { "id": "a", "type": "text", "x": 5, "y": 5, "width": 10, "height": 10, "text": "again" },
          { "id": "b", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10 },
          { "id": "c", "type": "sticker", "x": 0, "y": 0, "width": 10, "height": 10 },
          { "id": "d", "type": "link", "x": "0", "y": 0, "width": 10, "height": 10, "url": "https://x" },
          { "id": "e", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "", "color": "9" }
        ],
        "edges": [
          { "id": "ok", "fromNode": "a", "toNode": "e", "fromSide": "middle" },
          { "id": "gone", "fromNode": "a", "toNode": "zz" },
          { "id": "ok", "fromNode": "e", "toNode": "a" }
        ]
      }''')!;
      expect(canvas.nodes.map((n) => n.id), ['a', 'e']);
      expect(canvas.nodes[0], holds({'text': 'one'}));
      expect(canvas.nodes[1].fields.containsKey('color'), isFalse);
      expect(canvas.edges, [isRecord({'id': 'ok', 'fromNode': 'a', 'toNode': 'e'})]);
    });

    test('is not a canvas when it is not JSON, not an object, or an object with neither nodes nor edges', () {
      expect(parseCanvas('# A note'), isNull);
      expect(parseCanvas('[1, 2]'), isNull);
      expect(parseCanvas('{}'), isNull);
      expect(parseCanvas('{"nodes": []}'), Canvas(nodes: const [], edges: const []));
    });

    test('writes back what it read, in the spec’s shape, and nothing it did not', () {
      final canvas = parseCanvas(specSample)!;
      final again = parseCanvas(serializeCanvas(canvas));
      expect(again, canvas);
      expect(serializeCanvas(canvas).endsWith('\n'), isTrue);
      expect(serializeCanvas(canvas), isNot(contains('undefined')));
      expect(serializeCanvas(canvas), isNot(contains('null')));
    });
  });

  group('a canvas as a note', () {
    final sample = parseCanvas(specSample)!;
    final canvas = Canvas(nodes: [CanvasNode.text(id: 'a', x: 0, y: 0, width: 100, height: 50, text: 'hi')], edges: const []);

    test('is front matter naming it, then the canvas; the note is titled by the front matter', () {
      final body = canvasNoteBody('Cabin plan: the weekend', canvas);
      expect(body.startsWith('---\ntitle: "Cabin plan: the weekend"\n---\n{'), isTrue);
      expect(noteTitle(body), 'Cabin plan: the weekend');
      expect(canvasOf(body), canvas);
      expect(isCanvasBody(body), isTrue);
    });

    test('is read without front matter too, and a note of words is never one', () {
      expect(canvasOf(serializeCanvas(canvas)), canvas);
      expect(isCanvasBody('# Groceries\n\n- milk'), isFalse);
      expect(isCanvasBody('---\ntitle: Plans\n---\n# Plans\n\n{ not a canvas }'), isFalse);
      expect(isCanvasBody(''), isFalse);
    });

    test('has front matter as the list reads it, and a rule with words under it is not that', () {
      expect(isCanvasBody('---\nA rule, then words\n---\n{ "nodes": [] }'), isFalse);
      const titled = '---\ntitle: "Plan"\n\ntags: [trip]\n---\n{ "nodes": [] }';
      expect(isCanvasBody(titled), isTrue);
      expect(withCanvas(titled, canvas).startsWith('---\ntitle: "Plan"\n\ntags: [trip]\n---\n{'), isTrue);
    });

    test('puts the canvas back into its note and keeps the front matter as it was', () {
      const body = '---\ntitle: "Cabin"\ntags: [trip]\n---\n{ "nodes": [] }\n';
      final next = withCanvas(body, sample);
      expect(next.startsWith('---\ntitle: "Cabin"\ntags: [trip]\n---\n'), isTrue);
      expect(canvasOf(next), sample);
      expect(noteTitle(next), 'Cabin');
      // A body with no front matter is the canvas alone.
      expect(canvasOf(withCanvas('{ "nodes": [] }', sample)), sample);
    });
  });

  group('what a node keeps', () {
    test('keeps a group’s picture and how it is laid, a 3-digit hex colour, and an anchor that is one; drops what is not', () {
      final canvas = parseCanvas('''{ "nodes": [
        { "id": "g", "type": "group", "x": 0, "y": 0, "width": 10, "height": 10, "background": "sky.png", "backgroundStyle": "ratio", "color": "#f80" },
        { "id": "h", "type": "group", "x": 0, "y": 0, "width": 10, "height": 10, "background": "", "backgroundStyle": "stretch", "label": "" },
        { "id": "f", "type": "file", "x": 0, "y": 0, "width": 10, "height": 10, "file": "Trip.md", "subpath": "^friday" },
        { "id": "e", "type": "file", "x": 0, "y": 0, "width": 10, "height": 10, "file": "" },
        { "id": "u", "type": "link", "x": 0, "y": 0, "width": 10, "height": 10, "url": "" },
        { "id": "c", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "hi", "color": "#ff88" }
      ] }''')!;
      expect(canvas.nodes.map((n) => n.id), ['g', 'h', 'f', 'c']);
      expect(canvas.nodes[0], isRecord({'id': 'g', 'type': 'group', 'x': 0, 'y': 0, 'width': 10, 'height': 10, 'color': '#f80', 'background': 'sky.png', 'backgroundStyle': 'ratio'}));
      expect(canvas.nodes[1], isRecord({'id': 'h', 'type': 'group', 'x': 0, 'y': 0, 'width': 10, 'height': 10}));
      expect(canvas.nodes[2].fields.containsKey('subpath'), isFalse);
      expect(canvas.nodes[3].fields.containsKey('color'), isFalse);
    });

    test('keeps only the sides and ends the spec names on a line, and a line with no words has no label', () {
      final canvas = parseCanvas('''{
        "nodes": [
          { "id": "a", "type": "text", "x": 0, "y": 0, "width": 10, "height": 10, "text": "a" },
          { "id": "b", "type": "text", "x": 50, "y": 0, "width": 10, "height": 10, "text": "b" }
        ],
        "edges": [{ "id": "e", "fromNode": "a", "toNode": "b", "fromSide": "top", "toSide": "under", "fromEnd": "arrow", "toEnd": "dot", "label": "", "color": "7" }]
      }''')!;
      expect(canvas.edges, [isRecord({'id': 'e', 'fromNode': 'a', 'toNode': 'b', 'fromSide': 'top', 'fromEnd': 'arrow'})]);
    });
  });

  group('front matter a canvas note may have', () {
    final canvas = Canvas(nodes: [CanvasNode.text(id: 'a', x: 0, y: 0, width: 100, height: 50, text: 'hi')], edges: const []);
    final json = serializeCanvas(canvas);

    test('reads a canvas under +++ fences, and keeps them when it writes', () {
      final body = '+++\ntitle: "Plan"\n+++\n$json';
      expect(canvasOf(body), canvas);
      expect(withCanvas(body, Canvas(nodes: const [], edges: const [])).startsWith('+++\ntitle: "Plan"\n+++\n{'), isTrue);
    });

    test('is not a canvas under a fence that never closes, or closes past the fortieth line', () {
      expect(isCanvasBody('---\ntitle: "Plan"\n$json'), isFalse);
      final long = ['---', for (var i = 0; i < 40; i += 1) 'key$i: $i', '---', json].join('\n');
      expect(isCanvasBody(long), isFalse);
      final fits = ['---', for (var i = 0; i < 37; i += 1) 'key$i: $i', '---', json].join('\n');
      expect(canvasOf(fits), canvas);
    });
  });

  // jsonCanvas.comments.test.ts
  group('a canvas’s threads in its JSON', () {
    const withThreads = '''{
  "nodes": [
    { "id": "book", "type": "text", "x": 0, "y": 0, "width": 260, "height": 100, "text": "# Book the cabin" }
  ],
  "edges": [],
  "comments": [
    { "id": "c1", "node": "book", "by": "matt", "at": "2026-10-05T14:00:00Z", "text": "Which Friday?", "replies": [ { "by": "sam", "at": "2026-10-05T14:05:00Z", "text": "The 10th." } ], "resolved": { "by": "sam", "at": "2026-10-05T14:06:00Z" } },
    { "id": "c2", "node": "gone", "by": "lee", "at": "2026-10-05T14:07:00Z", "text": "On a card that is not there", "replies": [] },
    { "id": "c3", "node": "book", "by": "lee", "at": "2026-10-05T14:08:00Z", "text": "Open, with a reply that is not one and no resolved", "replies": [ { "by": "x" }, 4 ], "resolved": { "by": 1 } },
    { "id": "c1", "node": "book", "by": "twice", "at": "2026-10-05T14:09:00Z", "text": "The same id again", "replies": [] }
  ]
}''';

    test('reads the threads on cards that are there, drops what is not a thread, and keeps the first of an id', () {
      final canvas = parseCanvas(withThreads)!;
      expect(canvas.comments?.map((thread) => thread.id), ['c1', 'c3']);
      expect(
        canvas.comments?[0],
        isRecord({
          'id': 'c1',
          'node': 'book',
          'by': 'matt',
          'at': '2026-10-05T14:00:00Z',
          'text': 'Which Friday?',
          'replies': [
            {'by': 'sam', 'at': '2026-10-05T14:05:00Z', 'text': 'The 10th.'},
          ],
          'resolved': {'by': 'sam', 'at': '2026-10-05T14:06:00Z'},
        }),
      );
      expect(canvas.comments?[1], isRecord({'id': 'c3', 'node': 'book', 'by': 'lee', 'at': '2026-10-05T14:08:00Z', 'text': 'Open, with a reply that is not one and no resolved', 'replies': <Object?>[]}));
    });

    test('writes them after the edges, and nothing at all for a canvas without any', () {
      final canvas = parseCanvas(withThreads)!;
      final written = serializeCanvas(canvas);
      expect(written.indexOf('"comments"'), greaterThan(written.indexOf('"edges"')));
      expect(parseCanvas(written), canvas);
      expect(serializeCanvas(Canvas(nodes: canvas.nodes, edges: const [])), isNot(contains('comments')));
      expect(serializeCanvas(Canvas(nodes: canvas.nodes, edges: const [], comments: const [])), isNot(contains('comments')));
      expect(withCanvas('---\ntitle: "Plan"\n---\n{}\n', canvas), contains('"comments": ['));
    });
  });
}
