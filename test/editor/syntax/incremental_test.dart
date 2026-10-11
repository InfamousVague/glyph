import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/editor/syntax/language.dart';
import 'package:ghost_md/editor/syntax/tree.dart';

import 'support.dart';

/// The reparse after an edit: Lezer's incremental parse (`FragmentCursor`, `TreeFragment.applyChanges`), which
/// lifts every block the edit left alone out of the tree before it.
///
/// Two things are held. The tree is the one a parse from nothing gives, after every one of a long run of edits each
/// made on the tree of the one before; and the blocks really are lifted, which is what makes a keystroke in a long
/// note cost what its own paragraph costs.
void main() {
  final fixture = TreeFixture('glyph_corpus.json');
  final glyph = glyphMarkdown(fixture.formats);
  final chapters = [
    for (final one in fixture.cases)
      if ((one['name'] as String).endsWith('.md')) one['doc'] as String,
  ];

  /// A note of about [size] code units: the guidebook's chapters one after another, round and round.
  String noteOf(int size) {
    final out = StringBuffer();
    for (var i = 0; out.length < size; i++) {
      out
        ..write(chapters[i % chapters.length])
        ..write('\n\n');
    }
    return out.toString();
  }

  test('the change between two texts is the one range that differs', () {
    expect(ChangedRange.between('one two', 'one two'), isNull);
    final typed = ChangedRange.between('one two', 'one, two')!;
    expect([typed.fromA, typed.toA, typed.fromB, typed.toB], [3, 3, 3, 4]);
    final cut = ChangedRange.between('aaa', 'aa')!;
    expect([cut.fromA, cut.toA, cut.fromB, cut.toB], [2, 3, 2, 2]);
    final swapped = ChangedRange.between('a quick fox', 'a slow fox')!;
    expect([swapped.fromA, swapped.toA, swapped.fromB, swapped.toB], [2, 7, 2, 6]);
  });

  test('fragments are cut at a change and moved by its size', () {
    final tree = glyph.parse(noteOf(4000));
    final fragments = TreeFragment.applyChanges(TreeFragment.addTree(tree), [const ChangedRange(2000, 2010, 2000, 2003)]);
    expect(fragments.length, 2);
    expect([fragments[0].from, fragments[0].to, fragments[0].offset, fragments[0].openStart, fragments[0].openEnd], [0, 2000, 0, false, true]);
    expect([fragments[1].from, fragments[1].to, fragments[1].offset, fragments[1].openStart, fragments[1].openEnd], [2003, tree.length - 7, 7, true, false]);
    // A stretch too short to be worth keeping is dropped: Lezer's `minGap`.
    expect(TreeFragment.applyChanges(TreeFragment.addTree(tree), [const ChangedRange(100, 101, 100, 101)]).single.from, 101);
  });

  test('a reparse after any edit is the tree a parse from nothing gives', () {
    final random = Random(20261007);
    const typed = ['a', ' ', '\n', '\n\n', '*', '**', '`', '```\n', '> ', '- ', '1. ', '#', '# ', '|', '||', '==', '🔥🔥', '[', '](x)', '    ', '\t', '---\n', '<div>\n', '| a | b |\n| - | - |\n', '~~~\n'];
    var edits = 0, lifted = 0;
    final failures = <String>[];
    for (var c = 0; c < chapters.length; c++) {
      var text = chapters[c];
      var tree = glyph.parse(text);
      for (var n = 0; n < 40; n++) {
        final at = random.nextInt(text.length + 1);
        final int from, to;
        final String insert;
        switch (random.nextInt(5)) {
          case 0: // Type something.
            from = to = at;
            insert = typed[random.nextInt(typed.length)];
          case 1: // Backspace.
            from = max(0, at - 1);
            to = at;
            insert = '';
          case 2: // Cut a stretch, sometimes across lines.
            from = at;
            to = min(text.length, at + random.nextInt(120));
            insert = '';
          case 3: // Paste a stretch from elsewhere in the note.
            from = to = at;
            final start = random.nextInt(text.length + 1);
            insert = text.substring(start, min(text.length, start + random.nextInt(200)));
          default: // Type over a selection.
            from = at;
            to = min(text.length, at + random.nextInt(12));
            insert = typed[random.nextInt(typed.length)];
        }
        final after = text.substring(0, from) + insert + text.substring(to);
        final parse = glyph.startParse(
          after,
          fragments: TreeFragment.applyChanges(TreeFragment.addTree(tree), [ChangedRange(from, to, from, from + insert.length)]),
        );
        final again = parse.parseToEnd();
        edits += 1;
        lifted += parse.reused;
        final difference = firstDifference(flat(again), flat(glyph.parse(after)));
        if (difference != null) failures.add('chapter $c, edit $n ($from-$to -> ${insert.length}): $difference');
        expect(again.length, after.length);
        text = after;
        tree = again;
      }
    }
    // ignore: avoid_print
    print('reparse: ${edits - failures.length} of $edits edits gave the tree a whole parse gives; $lifted blocks lifted from the tree before');
    expect(failures, isEmpty, reason: failures.take(10).join('\n'));
    expect(lifted, greaterThan(edits * 10));
  });

  test('several changes at once are one reparse', () {
    final text = noteOf(30000);
    final tree = glyph.parse(text);
    // Three places far apart, as a find-and-replace makes.
    final a = text.indexOf('the', 1000), b = text.indexOf('the', 12000), c = text.indexOf('the', 25000);
    final after = '${text.substring(0, a)}THAT${text.substring(a + 3, b)}${text.substring(b + 3, c)}those **few**${text.substring(c + 3)}';
    final again = glyph.reparse(tree, after, [
      ChangedRange(a, a + 3, a, a + 4),
      ChangedRange(b, b + 3, b + 1, b + 1),
      ChangedRange(c, c + 3, c - 2, c - 2 + 13),
    ]);
    expect(firstDifference(flat(again), flat(glyph.parse(after))), isNull);
  });

  test('a keystroke in a long note lifts every block but its own', () {
    final text = noteOf(380000);
    final tree = glyph.parse(text);
    final blocks = tree.children.length;
    final at = text.indexOf('the ', 190000);
    final after = '${text.substring(0, at)}x${text.substring(at)}';
    final parse = glyph.startParse(after, fragments: TreeFragment.applyChanges(TreeFragment.addTree(tree), [ChangedRange(at, at, at, at + 1)]));
    final again = parse.parseToEnd();
    expect(firstDifference(flat(again), flat(glyph.parse(after))), isNull);
    expect(again.children.length, blocks);
    // The blocks lifted are the very objects of the tree before, not copies of them.
    final old = Set<Tree>.identity()..addAll(tree.children);
    final kept = again.children.where(old.contains).length;
    expect(kept, greaterThan(blocks - 12));
    expect(parse.reused, greaterThanOrEqualTo(kept));
  });

  test('a keystroke in a 380 kB note reparses in well under five milliseconds', () {
    final text = noteOf(380000);
    final whole = Stopwatch()..start();
    var tree = glyph.parse(text);
    whole.stop();

    // Typing a word, a character at a time, in the middle of the note; then the same at its top and at its end.
    final times = <String, List<int>>{};
    for (final place in ['middle', 'top', 'end']) {
      var doc = text;
      tree = glyph.parse(doc);
      var at = switch (place) {
        'middle' => doc.indexOf('the ', 190000),
        'top' => doc.indexOf('the '),
        _ => doc.lastIndexOf('the '),
      };
      final taken = times[place] = [];
      // The first passes warm the code up, as a note open for a second has.
      for (var n = 0; n < 260; n++) {
        final after = '${doc.substring(0, at)}${'ghostly '[n % 8]}${doc.substring(at)}';
        final watch = Stopwatch()..start();
        final again = glyph.reparse(tree, after, [ChangedRange(at, at, at, at + 1)]);
        watch.stop();
        if (n >= 60) taken.add(watch.elapsedMicroseconds);
        doc = after;
        tree = again;
        at += 1;
      }
      taken.sort();
    }
    String said(List<int> taken) => 'median ${(taken[taken.length ~/ 2] / 1000).toStringAsFixed(3)} ms, worst ${(taken.last / 1000).toStringAsFixed(3)} ms';
    // ignore: avoid_print
    print(
      'a ${text.length} code unit note (${tree.children.length} blocks, ${Platform.version.split(' ').first}): '
      'whole parse ${whole.elapsedMilliseconds} ms; a keystroke in the middle ${said(times['middle']!)}, '
      'at the top ${said(times['top']!)}, at the end ${said(times['end']!)}',
    );
    for (final taken in times.values) {
      expect(taken[taken.length ~/ 2], lessThan(5000));
    }
  });

  test('and in a note that is one long list, where the items are lifted from inside the list', () {
    // One block at the top level: the reuse has to reach into it, which Lezer's context hash is for.
    final out = StringBuffer();
    for (var i = 0; out.length < 380000; i++) {
      out.write('- [${i % 3 == 0 ? 'x' : ' '}] Item $i with **words** and a [link](https://ghostmarkdown.com/$i) #tag\n');
      if (i % 7 == 0) out.write('  - a nested one, ==marked==\n    with a second line\n');
    }
    var doc = out.toString();
    var tree = glyph.parse(doc);
    expect(tree.children.length, 1);
    var at = doc.indexOf('words', 190000);
    final taken = <int>[];
    var lifted = 0;
    for (var n = 0; n < 260; n++) {
      final after = '${doc.substring(0, at)}${'ghostly '[n % 8]}${doc.substring(at)}';
      final watch = Stopwatch()..start();
      final parse = glyph.startParse(after, fragments: TreeFragment.applyChanges(TreeFragment.addTree(tree), [ChangedRange(at, at, at, at + 1)]));
      final again = parse.parseToEnd();
      watch.stop();
      if (n >= 60) taken.add(watch.elapsedMicroseconds);
      lifted = parse.reused;
      doc = after;
      tree = again;
      at += 1;
    }
    expect(firstDifference(flat(tree), flat(glyph.parse(doc))), isNull);
    taken.sort();
    final items = tree.children.single.children.length;
    // ignore: avoid_print
    print('one list of $items items, ${doc.length} code units: a keystroke median ${(taken[taken.length ~/ 2] / 1000).toStringAsFixed(3)} ms, worst ${(taken.last / 1000).toStringAsFixed(3)} ms, $lifted items lifted');
    expect(lifted, greaterThan(items - 12));
    expect(taken[taken.length ~/ 2], lessThan(5000));
  });
}
