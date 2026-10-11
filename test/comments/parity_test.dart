import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/comments/format.dart';

/// The Dart port held to the web's own module: `fixtures/web_comments.json` is what `core/comments/format.ts`
/// answered (fixtures/web_comments.mjs, run under Node against tauri/, 2026-10-07) for thirty seeded notes grown
/// an operation at a time, a dozen fences written by hand, and its ids and stamps. For every step the port has to
/// read the note as the page read it and answer the very edits the page answered - the comments are in the
/// markdown two apps share, and in a team note the edits are what the CRDT merges.
void main() {
  final web = jsonDecode(File('test/comments/fixtures/web_comments.json').readAsStringSync()) as Map<String, dynamic>;

  Object? commentJson(Comment c) => {'by': c.by, 'at': c.at, 'words': c.words, 'line': c.line};
  Object? readJson(NoteComments read) {
    final fence = read.fence;
    return {
      'fence': fence == null ? null : {'open': fence.open, 'close': fence.close, 'from': fence.from, 'to': fence.to},
      'threads': [
        for (final t in read.threads)
          {
            'id': t.id,
            'head': commentJson(t.head),
            'replies': t.replies.map(commentJson).toList(),
            'resolved': t.resolved == null ? null : {'by': t.resolved!.by, 'at': t.resolved!.at, 'line': t.resolved!.line},
            'from': t.from,
            'to': t.to,
          },
      ],
      'anchors': [
        for (final a in read.anchors) {'id': a.id, 'from': a.from, 'to': a.to, 'wash': a.wash == null ? null : {'from': a.wash!.from, 'to': a.wash!.to}},
      ],
      'strays': read.strays,
    };
  }

  Object? editsJson(List<Edit>? edits) => edits == null ? null : [for (final e in edits) {'from': e.from, 'to': e.to, 'insert': e.insert}];
  Stamp stampOf(Object? raw) => Stamp(by: (raw as Map)['by'] as String, at: raw['at'] as String);

  test('reads every note as the page does, and answers the page’s edits for every operation', () {
    final notes = (web['notes'] as List).cast<Map<String, dynamic>>();
    expect(notes, hasLength(30));
    var steps = 0, changed = 0, quirk = 0;
    for (final (i, note) in notes.indexed) {
      var body = note['first'] as String;
      for (final (j, step) in (note['steps'] as List).cast<Map<String, dynamic>>().indexed) {
        final why = 'note $i, step $j (${step['op']}) on ${jsonEncode(body)}';
        final read = readComments(body);
        expect(readJson(read), step['read'], reason: why);
        final counts = threadCounts(read.threads);
        expect({'threads': counts.threads, 'open': counts.open}, step['counts'], reason: why);
        expect(countWords(read.threads), step['said'], reason: why);
        expect({for (final MapEntry(:key, :value) in countsBy(read.threads).entries) key: {'comments': value.comments, 'replies': value.replies}}, step['by'], reason: why);
        final id = step['id'] as String;
        final edits = switch (step['op']) {
          'line' => addThread(body, Target.line(step['line'] as int), stampOf(step['stamp']), step['words'] as String, id),
          'span' => addThread(body, Target.span(step['from'] as int, step['to'] as int), stampOf(step['stamp']), step['words'] as String, id),
          'reply' => addReply(body, id, stampOf(step['stamp']), step['words'] as String),
          'resolve' => resolveThread(body, id, stampOf(step['stamp'])),
          'reopen' => reopenThread(body, id),
          'delete' => deleteThread(body, id),
          final other => fail('An operation the port does not know: $other'),
        };
        expect(editsJson(edits), step['edits'], reason: why);
        final after = edits == null ? body : applyEdits(body, edits);
        expect(after, step['after'], reason: why);
        steps += 1;
        if (edits != null) changed += 1;
        if (step.containsKey('page')) quirk += 1;
        body = after;
      }
      expect(body, note['last']);
      expect(readJson(readComments(body)), note['read'], reason: 'note $i, at the end');
      expect(withoutAnchors(body), note['bare'], reason: 'note $i, without its anchors');
    }
    // Enough of them did something, and the page's own `applyEdits` differs only where the header says it does.
    expect(steps, greaterThan(250));
    expect(changed, greaterThan(150));
    expect(quirk, inInclusiveRange(1, 20));
  });

  test('reads a fence written by hand as the page does: other marks, indents, strays, a thread said twice, CRLF', () {
    final hand = (web['hand'] as List).cast<Map<String, dynamic>>();
    expect(hand, hasLength(12));
    for (final each in hand) {
      expect(readJson(readComments(each['body'] as String)), each['read'], reason: jsonEncode(each['body']));
    }
  });

  test('makes the page’s ids from the same rolls, and its stamps from the same moments', () {
    for (final each in (web['ids'] as List).cast<Map<String, dynamic>>()) {
      final tails = (each['tails'] as List).cast<String>();
      var i = 0;
      expect(freshId(each['body'] as String, () => int.parse(tails[i++ % tails.length], radix: 36) / 36), each['id'], reason: jsonEncode(each['body']));
    }
    for (final each in (web['stamps'] as List).cast<Map<String, dynamic>>()) {
      expect(stampNow(DateTime.fromMillisecondsSinceEpoch(each['at'] as int)), each['stamp']);
    }
  });
}
