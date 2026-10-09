// An editor's change carried over what reached the words from elsewhere while it was being made
// (lib/team/text_log.dart), and a team document taking both in the order they were asked (lib/team/doc.dart).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/native/ghost_core.dart';
import 'package:ghost_md/team/crdt.dart';
import 'package:ghost_md/team/doc.dart';
import 'package:ghost_md/team/docs.dart';
import 'package:ghost_md/team/text_log.dart';

import '../team_sync/support.dart';

String applied(String words, List<CrdtEdit> edits) {
  for (final edit in edits) {
    words = words.substring(0, edit.index) + edit.insert + words.substring(edit.index + edit.remove);
  }
  return words;
}

void main() {
  test('the stretch between two wordings is one, and never half a character', () {
    expect(spliceBetween('same', 'same'), isNull);
    expect(spliceBetween('Hello', 'Hello world'), (at: 5, removed: 0, inserted: ' world'));
    expect(spliceBetween('a big cat', 'a cat'), (at: 2, removed: 4, inserted: ''));
    // 😀 and 😁 share their first half: the whole character goes and comes.
    expect(spliceBetween('a😀b', 'a😁b'), (at: 1, removed: 2, inserted: '😁'));
    expect(spliceBetween('😀😀', '😀'), (at: 2, removed: 2, inserted: ''));
  });

  test('a change here is moved over a change that came first: after words put before it, in front of words put at its own place', () {
    const came = TextSplice(rev: 1, at: 2, removed: 0, inserted: 'XY');
    expect(applied('abXYcdef', carryOver([const CrdtEdit(4, insert: '!')], came)), 'abXYcd!ef');
    expect(applied('abXYcdef', carryOver([const CrdtEdit(2, insert: '!')], came)), 'ab!XYcdef');
    expect(applied('abXYcdef', carryOver([const CrdtEdit(0, insert: '!')], came)), '!abXYcdef');
    // A stretch taken here that starts where the words were put does not take them too.
    expect(applied('abXYcdef', carryOver([const CrdtEdit(2, remove: 2)], came)), 'abXYef');
    // Two edits of one change, the second against the words the first left.
    expect(applied('abXYcdef', carryOver([const CrdtEdit(0, insert: '>'), const CrdtEdit(7, insert: '<')], came)), '>abXYcdef<');
    // Words gone from elsewhere under a caret: the key lands where they were.
    const gone = TextSplice(rev: 1, at: 1, removed: 4, inserted: '');
    expect(applied('af', carryOver([const CrdtEdit(3, insert: '!')], gone)), 'a!f');
    expect(applied('af', carryOver([const CrdtEdit(2, remove: 4)], gone)), 'a');
  });

  test('a log carries a change over everything since the words it was made against, and refuses words too old', () {
    final log = TextLog();
    expect(log.record('abc', 'abc'), isNull);
    expect(log.record('abc', 'Xabc')?.rev, 1);
    expect(log.record('Xabc', 'XabcY')?.rev, 2);
    expect(log.carry([const CrdtEdit(1, insert: '!')], 2), [isA<CrdtEdit>().having((e) => e.index, 'index', 1)]);
    expect(applied('XabcY', log.carry([const CrdtEdit(1, insert: '!')], 0)), 'Xa!bcY');
    var words = 'XabcY';
    for (var i = 0; i < 300; i += 1) {
      log.record(words, words = '$words.');
    }
    expect(() => log.carry([const CrdtEdit(0, insert: '!')], 0), throwsStateError);
  });

  test('whatever order they are carried in, a change here and a change from elsewhere arrive at words that hold both', () {
    final random = Random(7);
    for (var round = 0; round < 500; round += 1) {
      const base = 'abcdefghij';
      final at = random.nextInt(base.length + 1), gone = random.nextInt(base.length - at + 1);
      final splice = TextSplice(rev: 1, at: at, removed: gone, inserted: 'XYZ'.substring(0, random.nextInt(4)));
      final from = random.nextInt(base.length + 1);
      final edit = CrdtEdit(from, remove: random.nextInt(base.length - from + 1), insert: '!?'.substring(0, random.nextInt(3)));
      final after = applied(base, [CrdtEdit(splice.at, remove: splice.removed, insert: splice.inserted)]);
      final carried = carryOver([edit], splice).single;
      expect(carried.index + carried.remove, lessThanOrEqualTo(after.length), reason: '$edit over $splice');
      final out = applied(after, [carried]);
      expect(out, contains(edit.insert));
      // Nothing the other side kept and this side did not take is lost.
      for (var i = 0; i < base.length; i += 1) {
        final keptThere = i < splice.at || i >= splice.at + splice.removed, keptHere = i < edit.index || i >= edit.index + edit.remove;
        if (keptThere && keptHere) expect(out, contains(base[i]), reason: '$edit over $splice lost ${base[i]}');
      }
    }
  });

  group('a team note\'s document', () {
    late GhostCore core;
    late Crdt crdt;
    setUpAll(() async {
      if (!coreBuilt) return;
      core = await openCore();
      crdt = Crdt(core.invoke);
    });
    tearDownAll(() async {
      if (coreBuilt) await core.close();
    });

    test('takes a key pressed while an update was on its way to the core, where the editor meant it', () async {
      final mine = TeamDocs(crdt: crdt, store: MemoryDocs(), rest: const Duration(days: 1));
      final theirs = TeamDocs(crdt: crdt, store: MemoryDocs(), rest: const Duration(days: 1));
      final a = (await mine.doc('n', seedWords: 'Hello world'))!;
      final b = await theirs.adopt('n', await a.snapshot(), 0);
      final made = <int>[];
      a.onUpdate((update) => made.add(update.length));
      final heard = <String>[];
      a.onSplice((splice) => heard.add('${splice.rev}@${splice.at}+${splice.inserted}'));
      // Sam typed at the start; the update is handed to the core, and before its words come back a key is pressed
      // here at the end of the words this editor still shows.
      final theirUpdate = (await b.edit([const CrdtEdit(0, insert: 'Oh. ')])).update!;
      final base = a.rev;
      final arriving = a.applyRemote([theirUpdate]);
      final typed = a.edit([const CrdtEdit(11, insert: '!')], base: base);
      await Future.wait([arriving, typed]);
      expect(a.words, 'Oh. Hello world!');
      expect(heard, ['1@0+Oh. ']);
      expect(a.rev, 1);
      // What was typed here is a change for the room and the service; what arrived is not.
      expect(made, hasLength(1));
      expect(await a.pending(), hasLength(2));
      await b.applyRemote(await a.pending());
      expect(b.words, 'Oh. Hello world!');
      // A reconcile is a change made here and a change of the words from elsewhere, both.
      expect(await a.reconcile('Oh. Hello, world!'), isTrue);
      expect(made, hasLength(2));
      expect(heard.last, '2@9+,');
      await mine.forget();
      await theirs.forget();
    }, skip: coreSkip);
  });
}
