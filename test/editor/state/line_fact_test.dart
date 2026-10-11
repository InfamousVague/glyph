// What is read from a document's lines and kept with the tree (lib/editor/state/text.dart `LineFact`, `DocMemo`),
// held to the plain scan it stands in for: after any run of changes, the lines that have a fact are the lines a
// walk of the whole document finds, and a change in a long document reads the lines of the leaf it made, not the
// document.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/state/text.dart';
import 'package:ghost_md/editor/view/lines.dart';

/// The lines a walk of the whole document finds: number, start, words and what was read.
List<(int, int, String, String)> walked(Doc doc, String? Function(String) read) {
  final found = <(int, int, String, String)>[];
  for (var n = 1; n <= doc.lines; n++) {
    final line = doc.line(n);
    final fact = read(line.text);
    if (fact != null) found.add((n, line.from, line.text, fact));
  }
  return found;
}

List<(int, int, String, String)> kept(List<FactLine<String>> lines) => [for (final line in lines) (line.number, line.from, line.text, line.fact)];

String? shout(String text) => text.contains('!') ? text.toUpperCase() : null;

/// The fenced lines as lib/editor/view/lines.dart read them before the fences were kept: every line, in order.
List<bool> fencedByWalk(Doc doc) {
  final fenced = <bool>[];
  final marker = RegExp(r'^\s*(```|~~~)');
  String? fence;
  for (var n = 1; n <= doc.lines; n++) {
    final found = marker.firstMatch(doc.line(n).text)?.group(1);
    fenced.add(fence != null || found != null);
    if (found != null) fence = fence == null ? found : (fence == found ? null : fence);
  }
  return fenced;
}

void main() {
  const words = ['plain words', 'a shout!', '', '```', '~~~', '  ```dart', 'more!', '- [ ] a task', '> quoted', 'the end of it!'];

  test('the lines that have a fact are the lines a walk finds, through any changes', () {
    final random = Random(7);
    final fact = LineFact<String>(shout);
    var doc = Doc.of([for (var i = 0; i < 900; i++) words[random.nextInt(words.length)]]);
    expect(kept(fact.of(doc)), walked(doc, shout));
    for (var round = 0; round < 400; round++) {
      final from = random.nextInt(doc.length + 1);
      final to = min(doc.length, from + (random.nextInt(4) == 0 ? random.nextInt(200) : random.nextInt(3)));
      final insert = switch (random.nextInt(5)) {
        0 => '',
        1 => '!',
        2 => 'x',
        3 => '\n${words[random.nextInt(words.length)]}\n',
        _ => [for (var i = 0; i < random.nextInt(60); i++) words[random.nextInt(words.length)]].join('\n'),
      };
      doc = doc.replace(from, to, Doc.of(insert.split('\n')));
      // Asked in a different way each round, so each way is held to the walk and none leans on another's keeping.
      final want = walked(doc, shout);
      switch (round % 3) {
        case 0:
          expect(kept(fact.of(doc)), want, reason: 'round $round');
        case 1:
          final first = 1 + random.nextInt(doc.lines), last = min(doc.lines, first + random.nextInt(80));
          expect(kept(fact.between(doc, first, last)), [for (final line in want) if (line.$1 >= first && line.$1 <= last) line], reason: 'round $round, lines $first to $last');
        default:
          for (var i = 0; i < 20; i++) {
            final number = 1 + random.nextInt(doc.lines);
            expect(fact.at(doc, number), shout(doc.line(number).text), reason: 'round $round, line $number');
          }
      }
      expect(fact.nowhere(doc), want.isEmpty);
      expect(fencedByWalk(doc), [for (var n = 1; n <= doc.lines; n++) docLineInFence(doc, n)], reason: 'round $round, the fences');
    }
  });

  test('a document with no such line, and a line asked for outside it', () {
    final fact = LineFact<String>(shout);
    final doc = Doc.of(['one', 'two', 'three']);
    expect(fact.of(doc), isEmpty);
    expect(fact.nowhere(doc), isTrue);
    expect(fact.at(doc, 0), isNull);
    expect(fact.at(doc, 4), isNull);
    expect(fact.between(doc, 3, 1), isEmpty);
    expect(fact.of(Doc.empty), isEmpty);
    expect(docLineInFence(doc, 9), isFalse);
  });

  test('a change in a long document reads the lines of one leaf, and the string is made once', () {
    final fact = LineFact<String>(shout);
    var doc = Doc.of([for (var i = 0; i < 20000; i++) i % 97 == 0 ? 'line $i!' : 'line $i']);
    DocWork.reset();
    expect(fact.of(doc).length, 207);
    expect(DocWork.reads, 20000, reason: 'the first asking reads every line once');
    DocWork.reset();
    fact.of(doc);
    fact.at(doc, 9000);
    fact.between(doc, 100, 5000);
    expect(DocWork.reads, 0, reason: 'asked again, nothing is read');

    for (var round = 0; round < 50; round++) {
      final at = doc.line(1 + (round * 397) % doc.lines).from;
      doc = doc.replace(at, at, Doc.of(['x']));
      DocWork.reset();
      final found = fact.of(doc);
      expect(DocWork.reads, lessThanOrEqualTo(64), reason: 'a letter typed reads its leaf (round $round)');
      expect(found.length, 207);
      expect(DocWork.lines, 0, reason: 'and hands out no line');
    }

    // What asks only about the screen reads only the leaves the screen is in.
    final fresh = Doc.of([for (var i = 0; i < 20000; i++) 'line $i!']);
    DocWork.reset();
    expect(fact.between(fresh, 9000, 9040).length, 41);
    expect(DocWork.reads, lessThanOrEqualTo(96));
    expect(fact.at(fresh, 3), 'LINE 2!');
    expect(DocWork.reads, lessThanOrEqualTo(128));

    DocWork.reset();
    final whole = fresh.toString();
    expect(identical(fresh.toString(), whole), isTrue);
    expect(DocWork.strings, 1);
    expect(DocWork.stringChars, fresh.length);
  });

  test('what is worked out from a document is worked out once for it', () {
    var made = 0;
    final memo = DocMemo<List<int>>((doc) {
      made += 1;
      return [doc.lines];
    });
    final doc = Doc.of(['a', 'b']);
    expect(memo.of(doc), [2]);
    expect(identical(memo.of(doc), memo.of(doc)), isTrue);
    expect(made, 1);
    expect(memo.of(doc.replace(0, 0, Doc.of(['', '']))), [3]);
    expect(made, 2);
  });
}
