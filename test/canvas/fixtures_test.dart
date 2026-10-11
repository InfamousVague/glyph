import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/comments.dart';
import 'package:ghost_md/canvas/edits.dart';
import 'package:ghost_md/canvas/geometry.dart';
import 'package:ghost_md/canvas/how_canvas.dart';
import 'package:ghost_md/canvas/js.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/canvas/lines.dart';
import 'package:ghost_md/canvas/map_detail.dart';
import 'package:ghost_md/canvas/sample_canvas.dart';
import 'package:ghost_md/canvas/viewport.dart';
import 'package:ghost_md/comments/format.dart' show Stamp;

/// The canvas's pure files against what the web's own answer (tool/canvas_fixtures.mjs, which runs
/// `../glyph/src/app/canvas/*.ts` in Node): the file a canvas is written as, byte for byte, after reading and
/// after every kind of edit; every line's path, string for string; and the small functions' answers.

final Map<String, dynamic> fixture = jsonDecode(File('test/canvas/fixtures/canvas.json').readAsStringSync()) as Map<String, dynamic>;

double d(Object? value) => (value! as num).toDouble();

/// One edit by name: tool/canvas_fixtures.mjs `apply`.
Canvas apply(Canvas canvas, List<dynamic> op) {
  final a = op.sublist(1);
  CanvasNode node(Object? id) => canvas.nodeOf(id! as String)!;
  CanvasEdge edge(Object? id) => canvas.edges.firstWhere((e) => e.id == id);
  Stamp stamp(int at) => Stamp(by: a[at] as String, at: a[at + 1] as String);
  switch (op[0] as String) {
    case 'text':
      return withNode(canvas, newTextNode(d(a[0]), d(a[1]), a[2] as String));
    case 'file':
      return withNode(canvas, newFileNode(a[0] as String, d(a[1]), d(a[2]), a[3] as String));
    case 'picture':
      return withNode(canvas, newPictureNode(a[0] as String, d(a[1]), d(a[2]), a[3] as String));
    case 'link':
      final made = newLinkNode(a[0] as String, d(a[1]), d(a[2]), a[3] as String);
      return made == null ? canvas : withNode(canvas, made);
    case 'place':
      final card = newTextNode(d(a[0]), d(a[1]), a[3] as String);
      final dot = a[2] as bool ? atDot(card.x, card.y) : (x: card.x, y: card.y);
      final at = clearSpot(canvas, dot.x, dot.y);
      return withNode(canvas, card.put({'x': at.x, 'y': at.y}));
    case 'started':
      return withNode(canvas, newTextNode(d(a[0]), d(a[1]), a[3] as String).put({'text': a[2], 'height': 180.0}));
    case 'move':
      return movedWithHeld(canvas, node(a[0]), d(a[1]), d(a[2]));
    case 'resize':
      return withNode(canvas, resizedBy(node(a[0]), Handle.values.byName(a[1] as String), d(a[2]), d(a[3]), a[4] as bool));
    case 'size':
      return withNode(canvas, resizedNode(node(a[0]), d(a[1]), d(a[2])));
    case 'colour':
      return withNode(canvas, colouredNode(node(a[0]), a[1] as String?));
    case 'name':
      return withNode(canvas, labelledGroup(node(a[0]), a[1] as String));
    case 'write':
      return withNode(canvas, node(a[0]).put({'text': a[1]}));
    case 'edge':
      return withEdge(canvas, newEdge(a[0] as String, a[1] as String, a[2] as String));
    case 'label':
      return withEdge(canvas, labelledEdge(edge(a[0]), a[1] as String));
    case 'unedge':
      return withoutEdge(canvas, a[0] as String);
    case 'remove':
      return withoutNode(canvas, a[0] as String);
    case 'copy':
      final copy = duplicated(canvas, node(a[0]), a[1] as String);
      return node(a[0]).isGroup ? withGroup(canvas, copy) : withNode(canvas, copy);
    case 'group':
      return withGroup(canvas, newGroupNode(a[0] == null ? null : node(a[0]), d(a[1]), d(a[2]), a[3] as String));
    case 'thread':
      return withThread(canvas, a[0] as String, stamp(1), a[3] as String, a[4] as String) ?? canvas;
    case 'reply':
      return withReply(canvas, a[0] as String, stamp(1), a[3] as String) ?? canvas;
    case 'resolve':
      return resolvedThread(canvas, a[0] as String, stamp(1)) ?? canvas;
    case 'reopen':
      return reopenedThread(canvas, a[0] as String) ?? canvas;
    case 'unthread':
      return withoutThread(canvas, a[0] as String) ?? canvas;
  }
  throw StateError('no edit called ${op[0]}');
}

Map<String, Object?> pathsOf(Canvas canvas) => {
  for (final entry in edgePaths(canvas).entries)
    entry.key: {
      'd': entry.value.d,
      'fromHead': entry.value.fromHead,
      'toHead': entry.value.toHead,
      'mid': [jsNumber(entry.value.mid.x), jsNumber(entry.value.mid.y)],
      'lines': entry.value.lines,
    },
};

List<Object?> bars(List<MapBar> list) => [
  for (final b in list) [jsNumber(b.x), jsNumber(b.y), jsNumber(b.width), jsNumber(b.height), b.strong],
];
List<Object?> viewOut(CameraView v) => [jsNumber(v.x), jsNumber(v.y), jsNumber(v.scale)];
List<Object?>? boxOut(Box? b) => b == null ? null : [jsNumber(b.x), jsNumber(b.y), jsNumber(b.width), jsNumber(b.height)];

void main() {
  group('the file, byte for byte', () {
    for (final each in (fixture['parse'] as List).cast<Map<String, dynamic>>()) {
      test('reads and writes back: ${each['name']}', () {
        final canvas = parseCanvas(each['text'] as String);
        expect(canvas == null ? null : serializeCanvas(canvas), each['out']);
      });
    }

    test('writes the example canvases as the web makes them, and as notes', () {
      final made = fixture['made'] as Map<String, dynamic>;
      expect(serializeCanvas(sampleCanvas()), made['sample']);
      expect(serializeCanvas(sampleCanvas('view.jpg')), made['samplePicture']);
      expect(serializeCanvas(howCanvas()), made['how']);
      expect(sampleCanvasBody(), made['sampleBody']);
      expect(sampleCanvasBody('view.jpg'), made['samplePictureBody']);
      expect(howCanvasBody(), made['howBody']);
      for (final each in (made['titled'] as List).cast<Map<String, dynamic>>()) {
        expect(canvasNoteBody(each['title'] as String, Canvas(nodes: const [], edges: const [])), each['body']);
      }
    });

    test('knows a canvas note, and writes a canvas into one keeping its front matter', () {
      final view = parseCanvas(((fixture['parse'] as List)[1] as Map)['text'] as String)!;
      for (final each in (fixture['notes'] as List).cast<Map<String, dynamic>>()) {
        final body = each['body'] as String;
        expect(isCanvasBody(body), each['isCanvas'], reason: body);
        expect(withCanvas(body, view), each['written'], reason: body);
      }
    });
  });

  group('every edit, and every line after it', () {
    for (final run in (fixture['edits'] as List).cast<Map<String, dynamic>>()) {
      test('${run['name']}: ${(run['steps'] as List).length} edits', () {
        var canvas = switch (run['made']) {
          'sample' => sampleCanvas('view.jpg'),
          'how' => howCanvas(),
          _ => parseCanvas(run['base'] as String)!,
        };
        var n = 0;
        for (final step in (run['steps'] as List).cast<Map<String, dynamic>>()) {
          canvas = apply(canvas, step['op'] as List);
          expect(serializeCanvas(canvas), step['out'], reason: 'step $n ${step['op']}');
          expect(pathsOf(canvas), step['paths'], reason: 'the lines after step $n ${step['op']}');
          n += 1;
        }
      });
    }
  });

  test('draws every line of the crowded canvases string for string', () {
    var lines = 0;
    for (final each in (fixture['paths'] as List).cast<Map<String, dynamic>>()) {
      final canvas = parseCanvas(each['text'] as String)!;
      expect(pathsOf(canvas), each['paths'], reason: each['text'] as String);
      // In the edges' order, as the web's Map is.
      expect(edgePaths(canvas).keys.toList(), (each['paths'] as Map).keys.toList());
      lines += (each['paths'] as Map).length;
    }
    expect(lines, greaterThan(400));
  });

  test('answers the small functions as the web does', () {
    for (final call in (fixture['calls'] as List).cast<List<dynamic>>()) {
      final a = call[1] as List;
      final want = call[2];
      final Object? got = switch (call[0] as String) {
        'brokenInto' => brokenInto(a[0] as String, a[1] as int),
        'wordBars' => bars(wordBars(a[0] as String, d(a[1]), d(a[2]))),
        'noteBars' => bars(noteBars(a[0] as String, d(a[1]), d(a[2]))),
        'roundedBox' => roundedBox(d(a[0]), d(a[1]), d(a[2]), d(a[3]), d(a[4])),
        'bounds' => boxOut(bounds(parseCanvas(a[0] as String)!)),
        'fitted' => viewOut(fitted(parseCanvas(a[0] as String)!, d(a[1]), d(a[2]))),
        'fittedTo' => viewOut(fittedTo(BoxOf(d(a[0]), d(a[1]), d(a[2]), d(a[3])), d(a[4]), d(a[5]))),
        'zoomedAt' => viewOut(zoomedAt(CameraView(x: d(a[0]), y: d(a[1]), scale: d(a[2])), d(a[3]), d(a[4]), d(a[5]))),
        'shown' => boxOut(shown(CameraView(x: d(a[0]), y: d(a[1]), scale: d(a[2])), d(a[3]), d(a[4]))),
        'heldBy' => () {
          final canvas = parseCanvas(a[0] as String)!;
          return [for (final n in heldBy(canvas, canvas.nodeOf(a[1] as String)!)) n.id];
        }(),
        'clearSpot' => () {
          final at = clearSpot(parseCanvas(a[0] as String)!, d(a[1]), d(a[2]));
          return [jsNumber(at.x), jsNumber(at.y)];
        }(),
        'sidesOf' => () {
          final canvas = parseCanvas(a[0] as String)!;
          final sides = sidesOf(canvas.nodeOf(a[1] as String)!, canvas.nodeOf(a[2] as String)!);
          return [sides.from.name, sides.to.name];
        }(),
        'quoteOf' => quoteOf(parseCanvas(a[0] as String)!, a[1] as String),
        'onGrid' => jsNumber(onGrid(d(a[0]))),
        _ => throw StateError('no call ${call[0]}'),
      };
      expect(got, want, reason: '${call[0]}(${jsonEncode(a)})');
    }
  });
}
