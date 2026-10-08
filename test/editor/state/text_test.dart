// Doc, the port of CodeMirror's Text: held to the real library by fixtures/text.json, to a plain string by random
// edits, and to the clock on a 400 kB note.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/editor.dart';

import 'support.dart';

List<Object?> lineJson(Line l) => <Object?>[l.from, l.to, l.number, l.text];

void main() {
  final data = fixture('text');

  group('against CodeMirror', () {
    final cases = data['cases'] as List;
    for (var c = 0; c < cases.length; c++) {
      final lines = (cases[c]['lines'] as List).cast<String>();
      test('a document of ${lines.length} lines', () {
        final doc = Doc.of(lines);
        expect(doc.length, cases[c]['length']);
        expect(doc.lines, lines.length);
        for (final op in cases[c]['ops'] as List) {
          switch (op['k'] as String) {
            case 'lineAt':
              expect(lineJson(doc.lineAt(op['pos'] as int)), op['r']);
            case 'line':
              expect(lineJson(doc.line(op['n'] as int)), op['r']);
            case 'slice':
              final from = op['from'] as int, to = op['to'] as int;
              expect(doc.sliceString(from, to), op['r']);
              expect(doc.sliceString(from, to, '\r\n'), op['sep']);
              expect(doc.slice(from, to).toJson(), op['sub']);
            case 'replace':
              final replaced = doc.replace(op['from'] as int, op['to'] as int, Doc.of((op['ins'] as List).cast<String>()));
              expect(replaced.lines, op['lines']);
              expect(replaced.length, op['length']);
              expect(checksum(replaced.toString()), op['sum']);
              expect(replaced.eq(doc), op['eq']);
            case 'iterRange':
              expect(drain(doc.iterRange(op['from'] as int, op['to'] as int)), op['r']);
            case 'iterLines':
              final got = drain(doc.iterLines(op['from'] as int?, op['to'] as int?));
              if (op['r'] != null) expect(got, op['r']);
              if (op['sum'] != null) expect(checksum(got.join('|')), op['sum']);
            case 'iter':
              final got = drain(doc.iter(op['dir'] as int));
              if (op['r'] != null) expect(got, op['r']);
              expect(checksum(got.join()), op['sum']);
          }
        }
      });
    }

    test('400 edits to a 5,000-line document, the tree rebalancing as it goes', () {
      final big = data['big'] as Map<String, dynamic>;
      var doc = Doc.of((big['lines'] as List).cast<String>());
      for (final e in big['edits'] as List) {
        doc = doc.replace(e['from'] as int, e['to'] as int, Doc.of((e['ins'] as List).cast<String>()));
        expect(doc.lines, e['lines']);
        expect(doc.length, e['length']);
        expect(lineJson(doc.lineAt(e['pos'] as int)), e['at']);
        if (e['sum'] != null) expect(checksum(doc.toString()), e['sum']);
      }
    });
  });

  group('Doc', () {
    test('needs a line, and the empty one is shared', () {
      expect(() => Doc.of(<String>[]), throwsRangeError);
      expect(identical(Doc.of(<String>['']), Doc.empty), isTrue);
      expect(Doc.empty.length, 0);
      expect(Doc.empty.lines, 1);
      expect(Doc.ofString('a\r\nb\rc\nd').toJson(), <String>['a', 'b', 'c', 'd']);
    });

    test('refuses positions and lines outside it', () {
      final doc = Doc.ofString('one\ntwo');
      expect(() => doc.lineAt(-1), throwsRangeError);
      expect(() => doc.lineAt(8), throwsRangeError);
      expect(() => doc.line(0), throwsRangeError);
      expect(() => doc.line(3), throwsRangeError);
      expect(doc.lineAt(3).number, 1);
      expect(doc.lineAt(4).number, 2);
      expect(doc.line(2).length, 3);
    });

    test('counts in UTF-16 units, as the web app does', () {
      final doc = Doc.ofString('a😀b\né');
      expect(doc.length, 6);
      expect(doc.sliceString(1, 3), '😀');
      expect(doc.lineAt(5).from, 5);
    });

    test('walks its lines in a for loop', () {
      final doc = Doc.ofString('a\n\nb');
      expect(doc.iterLines().rest.toList(), <String>['a', '', 'b']);
      expect(doc.iter().rest.toList(), <String>['a', '\n', '\n', 'b']);
      expect(doc.iterLines(2, 4).rest.toList(), <String>['', 'b']);
    });

    test('a cursor skips forward', () {
      final doc = Doc.of(<String>[for (var i = 0; i < 200; i++) 'line $i']);
      final text = doc.toString();
      final iter = doc.iter();
      iter.next(500);
      final rest = StringBuffer(iter.value);
      while (!iter.next().done) {
        rest.write(iter.value);
      }
      expect(rest.toString(), text.substring(500));
    });

    test('eq skips what two documents share', () {
      final doc = Doc.of(<String>[for (var i = 0; i < 3000; i++) 'line $i']);
      final at = doc.line(100).from;
      final a = doc.replace(at, at + 4, Doc.ofString('LINE'));
      final b = doc.replace(at, at + 4, Doc.ofString('LINE'));
      expect(a.eq(b), isTrue);
      expect(a.eq(doc), isFalse);
      expect(a.replace(at, at + 4, Doc.ofString('line')).eq(doc), isTrue);
    });
  });

  group('against a plain string', () {
    for (final seed in <int>[1, 2, 3, 4]) {
      test('600 random edits, seed $seed', () {
        final r = Random(seed);
        var text = randomLines(r, 1 + r.nextInt(300), 20).join('\n');
        var doc = Doc.ofString(text);
        for (var i = 0; i < 600; i++) {
          final from = r.nextInt(text.length + 1);
          final to = min(text.length, from + const <int>[0, 0, 1, 3, 40, 900][r.nextInt(6)]);
          final insert = randomLines(r, const <int>[1, 1, 1, 2, 5, 70][r.nextInt(6)], 12).join('\n');
          text = text.replaceRange(from, to, insert);
          doc = doc.replace(from, to, Doc.ofString(insert));
          expect(doc.length, text.length);
          if (i % 25 == 0) {
            expect(doc.toString(), text);
            final lines = text.split('\n');
            expect(doc.lines, lines.length);
            final n = 1 + r.nextInt(lines.length);
            expect(doc.line(n).text, lines[n - 1]);
            final pos = r.nextInt(text.length + 1);
            final line = doc.lineAt(pos);
            expect(text.substring(line.from, line.to), line.text);
            expect(line.from == 0 || text[line.from - 1] == '\n', isTrue);
            expect(line.to == text.length || text[line.to] == '\n', isTrue);
            final a = r.nextInt(text.length + 1), b = a + r.nextInt(text.length - a + 1);
            expect(doc.sliceString(a, b), text.substring(a, b));
            expect(doc.slice(a, b).toString(), text.substring(a, b));
            // Backwards, the pieces come last first, each still reading forwards.
            expect(drain(doc.iterRange(b, a)).reversed.join(), text.substring(a, b));
          }
        }
        expect(doc.toString(), text);
        expect(doc.iterLines().rest.toList(), text.split('\n'));
      });
    }
  });

  group('a 400 kB note', () {
    // About 8,000 lines of prose: the size docs/STAGE4.md asks the editor to stay quick at.
    String note() {
      final r = Random(9);
      const words = <String>['ghost', 'markdown', 'note', 'the', 'a', 'writes', 'reads', '#tag', '[3/8]', '**bold**', 'and', 'quietly'];
      final lines = <String>[];
      var size = 0;
      while (size < 400 * 1024) {
        final line = <String>[for (var i = 3 + r.nextInt(12); i > 0; i--) words[r.nextInt(words.length)]].join(' ');
        lines.add(line);
        size += line.length + 1;
      }
      return lines.join('\n');
    }

    test('typing, line lookups and slices stay far under a frame', () {
      final text = note();
      final build = Stopwatch()..start();
      var doc = Doc.ofString(text);
      build.stop();
      expect(doc.length, text.length);

      final r = Random(10);
      const rounds = 20000;
      final x = Doc.ofString('x');
      // Warm the code up, then measure.
      for (var i = 0; i < 2000; i++) {
        doc = doc.replace(r.nextInt(doc.length), r.nextInt(doc.length), Doc.empty).replace(0, 0, Doc.empty);
      }
      doc = Doc.ofString(text);

      final typing = Stopwatch()..start();
      var at = doc.length ~/ 2;
      for (var i = 0; i < rounds; i++) {
        doc = doc.replace(at, at, x);
        at++;
      }
      typing.stop();

      final scattered = Stopwatch()..start();
      for (var i = 0; i < rounds; i++) {
        final pos = r.nextInt(doc.length);
        doc = doc.replace(pos, min(doc.length, pos + 1), x);
      }
      scattered.stop();

      final lookups = Stopwatch()..start();
      var sum = 0;
      for (var i = 0; i < rounds; i++) {
        sum += doc.lineAt(r.nextInt(doc.length)).number;
        sum += doc.line(1 + r.nextInt(doc.lines)).from;
      }
      lookups.stop();

      final slices = Stopwatch()..start();
      for (var i = 0; i < rounds; i++) {
        final pos = r.nextInt(doc.length - 200);
        sum += doc.sliceString(pos, pos + 200).length;
      }
      slices.stop();

      final whole = Stopwatch()..start();
      final out = doc.toString();
      whole.stop();
      expect(out.length, doc.length);
      expect(sum, greaterThan(0));

      double us(Stopwatch s, int n) => s.elapsedMicroseconds / n;
      final state = EditorState.create(doc: doc);
      final transactions = Stopwatch()..start();
      var s = state;
      for (var i = 0; i < 5000; i++) {
        final pos = s.doc.length ~/ 3 + i;
        s = s.update(TransactionSpec(changes: ChangeSpec(from: pos, insert: 'y'), selection: EditorSelection.single(pos + 1))).state;
      }
      transactions.stop();

      // ignore: avoid_print
      print(
        'Doc at ${(text.length / 1024).round()} kB, ${doc.lines} lines: build ${build.elapsedMilliseconds} ms; '
        'typing ${us(typing, rounds).toStringAsFixed(2)} us/edit; scattered edit ${us(scattered, rounds).toStringAsFixed(2)} us; '
        'lineAt+line ${us(lookups, rounds).toStringAsFixed(2)} us; 200-unit slice ${us(slices, rounds).toStringAsFixed(2)} us; '
        'toString ${whole.elapsedMilliseconds} ms; a typed transaction ${us(transactions, 5000).toStringAsFixed(2)} us',
      );
      // Generous bounds, so a slow machine under load does not fail them: a frame is 8,333 us at 120 Hz.
      expect(us(typing, rounds), lessThan(300));
      expect(us(scattered, rounds), lessThan(300));
      expect(us(lookups, rounds), lessThan(100));
      expect(us(transactions, 5000), lessThan(500));
    });

    test('an edit copies a path, not the note', () {
      final doc = Doc.ofString(note());
      final edited = doc.replace(1000, 1000, Doc.ofString('x'));
      // Every child of the root but the one the edit is in is the same object.
      final before = doc.children!, after = edited.children!;
      expect(after.length, before.length);
      var shared = 0;
      for (var i = 0; i < before.length; i++) {
        if (identical(before[i], after[i])) shared++;
      }
      expect(shared, before.length - 1);
    });
  });
}
