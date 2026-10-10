import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/canvas/json_canvas.dart';
import 'package:ghost_md/core/sample_library.dart';

import 'samples.dart';

/// Whether a note is a canvas (lib/canvas/json_canvas.dart `isCanvasBody`) is asked of every note a list holds,
/// so it decodes nothing: a note of words is told by its first character, and one that opens with a brace is
/// walked once as JSON. It was `canvasOf(body) != null`, the whole canvas decoded and built, and the answer must
/// not have moved: here it is held to that, for texts chosen to be awkward JSON and for some thousands made by
/// spoiling a real canvas a character at a time.
void main() {
  void same(String body) {
    final said = body.length > 120 ? '${body.substring(0, 120)}…' : body;
    expect(isCanvasBody(body), canvasOf(body) != null, reason: said.replaceAll('\n', r'\n'));
  }

  group('whether a note is a canvas, with nothing decoded', () {
    test('answers as the decoded canvas does, for JSON chosen to be awkward', () {
      const texts = [
        '',
        '{',
        '}',
        '{}',
        '[]',
        '{ }',
        'null',
        '"nodes"',
        '{"nodes":[]}',
        '{"edges":[]}',
        '{"nodes":[],"edges":[]}',
        ' \n\t{"nodes":[]}\n ',
        ' {"nodes":[]} ',
        '﻿{"nodes":[]}',
        '{ "nodes":[]}',
        '{"nodes":{}}',
        '{"nodes":null}',
        '{"nodes":"[]"}',
        '{"nodes":1,"edges":[]}',
        '{"nodes":[],"nodes":1}',
        '{"nodes":1,"nodes":[]}',
        '{"edges":[],"edges":{}}',
        '{"other":{"nodes":[]}}',
        '{"other":[{"nodes":[]}]}',
        '{"other":[],"more":{"edges":[]}}',
        r'{"nodes":[]}',
        r'{"n\odes":[]}',
        r'{"nodes\n":[]}',
        '{"Nodes":[]}',
        '{"nodes" : [ ] }',
        '{"nodes":[],}',
        '{,"nodes":[]}',
        '{"nodes":[,]}',
        '{"nodes":[1,]}',
        '{"nodes":[1 2]}',
        '{"nodes":[]"edges":[]}',
        '{"nodes"[]}',
        '{"nodes":}',
        '{nodes:[]}',
        "{'nodes':[]}",
        '{"nodes":[]} x',
        '{"nodes":[]}{}',
        '{"nodes":[]}}',
        '{"nodes":[]',
        '{"nodes":[}',
        '{"nodes":[[[[[]]]]]}',
        '{"nodes":[{"a":{"b":[{"c":null}]}}]}',
        '{"nodes":[true,false,null]}',
        '{"nodes":[tru]}',
        '{"nodes":[truee]}',
        '{"nodes":[nul]}',
        '{"nodes":[0,-0,1,-1,10,1.5,-1.5e3,1E+2,1e-2,0.0]}',
        '{"nodes":[01]}',
        '{"nodes":[-]}',
        '{"nodes":[+1]}',
        '{"nodes":[1.]}',
        '{"nodes":[.5]}',
        '{"nodes":[1e]}',
        '{"nodes":[1e+]}',
        '{"nodes":[0x10]}',
        '{"nodes":[1e999]}',
        '{"nodes":[123456789012345678901234567890]}',
        '{"nodes":["a\tb"]}',
        '{"nodes":["a\nb"]}',
        r'{"nodes":["a\tb\n\r\b\f\/\\\""]}',
        r'{"nodes":["é😀\uZZZZ"]}',
        r'{"nodes":["\u12"]}',
        r'{"nodes":["\x41"]}',
        '{"nodes":["unclosed]}',
        '{"nodes":[""]}',
        '{"":[],"nodes":[]}',
        '{"nodes":[] // a comment\n}',
        '{"nodes":[] }',
        '{"nodes":[\u000b]}',
        '{"nodes":[\u000c]}',
        '{?what to call this}',
        '{?} for {?which city}',
        '{ not a canvas }',
        '{"nodes": oops}',
      ];
      for (final text in texts) {
        same(text);
        same('---\ntitle: "A canvas"\n---\n$text');
        same('---\ntitle: "A canvas"\n---\n$text\n');
        same('---\ntitle: "A canvas"\n---');
        same('---\nA rule, then words\n---\n$text');
      }
    });

    test('answers as the decoded canvas does, for every note of the seeded library and the starter notes', () {
      var canvases = 0;
      for (final note in [...seedLibrary(), ...starterNotes(seedNow)]) {
        same(note.body);
        if (isCanvasBody(note.body)) canvases += 1;
      }
      expect(canvases, greaterThan(0));
    });

    test('answers as the decoded canvas does, for a canvas spoiled a character at a time', () {
      final whole = [specSample, canvasNoteBody('Plans', parseCanvas(specSample)!), '{"nodes":[{"id":"a","type":"text","x":0,"y":0,"width":10,"height":10,"text":"one \\"two\\" \\u00e9"}],"edges":[]}'];
      const strays = ['{', '}', '[', ']', '"', ',', ':', '\\', ' ', '\n', '0', '1', '-', '.', 'e', 't', 'n', 'x', ' ', '\t'];
      final random = Random(20261010);
      var yes = 0, no = 0;
      for (var i = 0; i < 6000; i += 1) {
        var text = whole[random.nextInt(whole.length)];
        final spoils = random.nextInt(3);
        for (var n = 0; n < spoils; n += 1) {
          final at = random.nextInt(text.length);
          switch (random.nextInt(4)) {
            case 0:
              text = text.substring(0, at) + text.substring(at + 1);
            case 1:
              text = text.substring(0, at) + strays[random.nextInt(strays.length)] + text.substring(at);
            case 2:
              text = text.substring(0, at) + strays[random.nextInt(strays.length)] + text.substring(at + 1);
            default:
              // A stretch taken out whole: a value, a key, a closing brace.
              final to = min(text.length, at + random.nextInt(12));
              text = text.substring(0, at) + text.substring(to);
          }
          if (text.isEmpty) break;
        }
        same(text);
        canvasOf(text) != null ? yes += 1 : no += 1;
      }
      // Chance must make both: canvases that are still canvases, and ones that are not any more.
      expect(yes, greaterThan(1500), reason: '$yes $no');
      expect(no, greaterThan(1500), reason: '$yes $no');
    });

    test('walks as deep as a canvas goes without running out of room', () {
      final deep = '{"nodes":${'[' * 20000}${']' * 20000}}';
      expect(isCanvasBody(deep), isTrue);
      expect(isCanvasBody('{"nodes":${'[' * 20000}${']' * 19999}}'), isFalse);
    });

    test('reads a key the way a decoder does', () {
      expect((jsonDecode(r'{"nodes":[]}') as Map).containsKey('nodes'), isTrue);
      expect(isCanvasBody(r'{"nodes":[]}'), isTrue);
    });
  });
}
