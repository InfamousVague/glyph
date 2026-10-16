import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/link_index.dart';
import 'package:ghost_md/core/note.dart';

import 'make_note.dart';

/// Which notes link to which (lib/core/link_index.dart): what one note's words are read as, which note a name
/// means, what links to a note and what says its name without linking it, the graph, and the index kept with a
/// library that changes, timed over 2,000 notes.
void main() {
  LinkIndex indexOf(List<Note> notes) => LinkIndex.build([for (final note in notes) (id: note.id, body: note.body, path: note.path, updatedAt: note.updatedAt)]);
  String? Function(String) bodies(List<Note> notes) => (id) => notes.where((note) => note.id == id).firstOrNull?.body;

  group('a note read', () {
    test('every way a link is written', () {
      const body = '# A\n\nSee [[Lisbon]], [[the coast|the sea]], [[Packing#Shoes]] and [[Packing#^charger]].\n\n![[Lisbon]]\n\n[notes](Inbox/Day%20one.md) and [site](https://attack.fm/x.md)';
      final links = linksIn(body);
      expect([for (final link in links) link.target], ['Lisbon', 'the coast', 'Packing', 'Packing', 'Lisbon', 'Day one']);
      expect(links[1].label, 'the sea');
      expect(links[2].anchor, 'Shoes');
      expect(links[3].anchor, '^charger');
      expect(links[4].embed, isTrue);
      expect(links[5].path, 'inbox/day one');
      expect(body.substring(links[0].from, links[0].to), '[[Lisbon]]');
    });

    test('no link inside code, and none for a place in the note itself', () {
      const body = '# A\n\n`[[Not a link]]` and [[#^here]]\n\n```\n[[Nor this]]\n```\n\n[[Yes]]';
      expect([for (final link in linksIn(body)) link.target], ['Yes']);
    });

    test('its names: title, aliases and a ticket key; its words with the links and code blanked', () {
      final facts = LinkFacts.read('t', '---\ntype: ticket\nid: GHO-12\naliases: [Sign in]\n---\n# Fix the loop\n\nIt loops `forever` on [[Login]].');
      expect(facts.title, 'Fix the loop');
      expect(facts.nameKeys.toList(), ['fix the loop', 'sign in', 'gho 12']);
      expect(facts.words, containsAll(['fix', 'the', 'loop', 'it', 'loops', 'on']));
      expect(facts.words, isNot(contains('login')));
      expect(facts.words, isNot(contains('forever')));
      expect(facts.words, isNot(contains('gho')));
    });

    test('a place on a long line: cut round it, and still marked where it is', () {
      final body = '# A\n\n- ${'words ' * 40}then Lisbon at last${' and more' * 30}';
      final place = placeIn(body, body.indexOf('Lisbon'), body.indexOf('Lisbon') + 6);
      expect(place.text.length, lessThan(150));
      expect(place.text, startsWith('…'));
      expect(place.text.substring(place.mark!.$1, place.mark!.$2), 'Lisbon');
      expect(place.line, 2);
    });

    test('the plain text keeps every place where it was', () {
      const body = '---\ntitle: x\n---\nSay [[Lisbon]] at https://a.b/c ^name';
      final plain = plainText(body);
      expect(plain.length, body.length);
      expect(plain.substring(plain.indexOf('Say')), 'Say${' ' * 12}at${' ' * 20}');
    });
  });

  group('which note a name means', () {
    test('a title, then a ticket key, then an alias; the newest of two titles; a person\'s note before a template\'s page', () {
      final index = indexOf([
        makeNote('old', body: '# Lisbon', updatedAt: 1),
        makeNote('new', body: '# Lisbon', updatedAt: 2),
        makeNote('page', body: '---\ntemplates: page\n---\n# Meeting', updatedAt: 9),
        makeNote('meeting', body: '# Meeting', updatedAt: 1),
        makeNote('ticket', body: '---\ntype: ticket\nid: GHO-12\n---\n# Fix it'),
        makeNote('alias', body: '---\naliases: [Porto, Lisbon]\n---\n# Portugal'),
      ]);
      expect(index.resolve('lisbon'), 'new');
      expect(index.resolve('meeting'), 'meeting');
      expect(index.resolve('gho 12'), 'ticket');
      expect(index.resolve('porto'), 'alias');
      expect(index.resolve('nowhere'), isNull);
    });
  });

  group('what links to a note', () {
    final notes = [
      makeNote('lisbon', body: '---\naliases: [The capital]\n---\n# Lisbon\n\nTrams.'),
      makeNote('packing', body: '# Packing\n\n- [ ] The charger for [[Lisbon]]\n- [ ] Shoes'),
      makeNote('coast', body: '# The coast\n\nAfter [[the capital|Lisbon]] we drove west.\n\n![[Lisbon]]'),
      makeNote('diary', body: '# Diary\n\nLisbon was hot. The capital at night was better.\n\n[[Packing]] list done.'),
      makeNote('trams', body: '# Trams\n\nThe Lisbon trams are old. [[Lisbon trip]] is another note.'),
      makeNote('self', body: '# Lisbon\n\nA second note called Lisbon.', updatedAt: -1),
    ];

    test('every note that links to it, by title or alias, embeds too, with the line round each link', () {
      final index = indexOf(notes);
      final back = index.backlinksOf('lisbon', bodies(notes));
      expect([for (final link in back) link.id], ['packing', 'coast']);
      expect(back.first.links.single.text, 'The charger for [[Lisbon]]');
      expect(back.first.links.single.mark, ('The charger for '.length, 'The charger for [[Lisbon]]'.length));
      expect(back.first.links.single.line, 2);
      expect([for (final place in back.last.links) place.embed], [false, true]);
      expect(index.backlinkCount('lisbon'), 2);
      expect(index.backlinkCount('packing'), 1);
    });

    test('the notes that say its name or an alias as words and do not link it', () {
      final index = indexOf(notes);
      final mentions = index.mentionsOf('lisbon', bodies(notes));
      expect([for (final mention in mentions) mention.id], ['diary', 'trams']);
      expect(mentions.first.places.first.text, 'Lisbon was hot. The capital at night was better.');
      expect(mentions.first.places.first.mark, (0, 6));
      // The words inside another note's link are that link's, not a mention.
      expect(mentions.last.places, hasLength(1));
      // A note of the same name is not a mention of itself, nor are the notes that link it.
      expect(mentions.any((mention) => mention.id == 'self' || mention.id == 'packing'), isFalse);
    });

    test('a note renamed: the links that used its old title wait, and its new title is linked from the notes that use it', () {
      final index = indexOf(notes);
      index.put(LinkFacts.read('lisbon', '# Lisboa\n\nTrams.'));
      // The other note called Lisbon is what [[Lisbon]] means now.
      expect(index.backlinkCount('lisbon'), 0);
      expect(index.backlinkCount('self'), 2);
      index.put(LinkFacts.read('diary', '# Diary\n\n[[Lisboa]] was hot.'));
      expect(index.backlinkCount('lisbon'), 1);
    });

    test('a Markdown link to the note\'s file, by its path or beside it', () {
      final index = indexOf([
        const Note(id: 'day', body: '# Day one', createdAt: 0, updatedAt: 0, path: 'Inbox/Day one.md'),
        const Note(id: 'from', body: '# From\n\n[the day](Day%20one.md) and [again](<Inbox/Day one.md>)', createdAt: 0, updatedAt: 0, path: 'Inbox/From.md'),
      ]);
      expect(index.linksTo('from', 'day'), hasLength(2));
      expect(index.backlinkCount('day'), 1);
    });
  });

  group('the graph', () {
    test('each pair once, and a note\'s neighbours one and two links away', () {
      final index = indexOf([
        makeNote('a', body: '# A\n[[B]] [[B]]'),
        makeNote('b', body: '# B\n[[A]] [[C]]'),
        makeNote('c', body: '# C\n[[D]]'),
        makeNote('d', body: '# D'),
        makeNote('e', body: '# E alone'),
      ]);
      final graph = index.graph();
      expect(graph.ids, ['a', 'b', 'c', 'd', 'e']);
      expect(graph.from.length, 3);
      expect(graph.degrees, [1, 2, 2, 1, 0]);
      expect(graph.around('a', 1).ids, ['a', 'b']);
      expect(graph.around('a', 2).ids, ['a', 'b', 'c']);
      expect(graph.around('a', 2).from.length, 2);
    });
  });

  group('kept with the library', () {
    test('reads only the notes that changed, and lets a note go when it is gone', () async {
      final library = ValueNotifier<List<Note>>([
        makeNote('a', body: '# A\n[[B]]'),
        makeNote('b', body: '# B'),
      ]);
      final indexer = LinkIndexer(notes: () => library.value, changes: library);
      expect(indexer.ready, isTrue);
      expect(indexer.index.backlinkCount('b'), 1);
      library.value = [library.value[0], library.value[1].copyWith(body: '# B\n[[A]]')];
      expect(indexer.lastChange?.read, 1);
      expect(indexer.index.backlinkCount('a'), 1);
      // A pin is no edit: the same words in another object, and nothing read.
      library.value = [library.value[0].copyWith(starred: true), library.value[1]];
      expect(indexer.lastChange?.read, 1);
      library.value = [library.value[1]];
      expect(indexer.index.factsOf('a'), isNull);
      expect(indexer.index.backlinkCount('a'), 0);
      indexer.dispose();
    });

    test('a library larger than a few notes is read by a worker isolate, and what changed meanwhile after it', () async {
      final notes = [for (var i = 0; i < 100; i += 1) makeNote('n$i', body: '# Note $i\n\n[[Note ${(i + 1) % 100}]]')];
      final library = ValueNotifier<List<Note>>(notes);
      final indexer = LinkIndexer(notes: () => library.value, changes: library, inlineUpTo: 10);
      expect(indexer.ready, isFalse);
      library.value = [...notes.sublist(1), notes[0].copyWith(body: '# Note 0\n\n[[Note 5]]')];
      final done = Completer<void>();
      void heard() {
        if (indexer.ready && !done.isCompleted && indexer.index.backlinkCount('n5') == 2) done.complete();
      }

      indexer.addListener(heard);
      await done.future.timeout(const Duration(seconds: 20));
      expect(indexer.index.length, 100);
      expect(indexer.index.backlinkCount('n1'), 0);
      indexer.dispose();
    });

    test('one note changed in a library of 2,000 is read in well under a second', () async {
      // Notes of a few hundred words each, linking to each other and mentioning each other's titles.
      final words = 'the cabin by the lake in october with ana and sam and the dog walking past the old mill road'.split(' ');
      String body(int i) {
        final out = StringBuffer('# Note $i\n\n');
        for (var line = 0; line < 30; line += 1) {
          for (var w = 0; w < 10; w += 1) {
            out
              ..write(words[(i * 7 + line * 3 + w) % words.length])
              ..write(' ');
          }
          out.writeln(line % 5 == 0 ? '[[Note ${(i * 31 + line) % 2000}]]' : 'note ${(i + line) % 2000}');
        }
        return out.toString();
      }

      final notes = [for (var i = 0; i < 2000; i += 1) makeNote('n$i', body: body(i), updatedAt: i)];
      final library = ValueNotifier<List<Note>>(notes);
      final built = Stopwatch()..start();
      final indexer = LinkIndexer(notes: () => library.value, changes: library, inlineUpTo: 4000);
      built.stop();
      expect(indexer.index.length, 2000);

      final changed = [...notes];
      changed[1234] = notes[1234].copyWith(body: '${notes[1234].body}\n[[Note 7]] and more words', updatedAt: 99999);
      final once = Stopwatch()..start();
      library.value = changed;
      once.stop();
      expect(indexer.lastChange?.read, 1);
      expect(indexer.lastChange?.looked, 2000);
      expect(indexer.index.linkingTo('n7'), contains('n1234'));
      final asked = Stopwatch()..start();
      final back = indexer.index.backlinksOf('n7', indexer.bodyOf);
      final mentions = indexer.index.mentionsOf('n7', indexer.bodyOf);
      asked.stop();
      expect(back, isNotEmpty);
      // ignore: avoid_print
      print('2,000 notes: read whole in ${built.elapsedMilliseconds} ms; one changed in ${once.elapsedMicroseconds} µs; '
          'a note\'s ${back.length} links and ${mentions.length} mentions in ${asked.elapsedMilliseconds} ms');
      expect(once.elapsed, lessThan(const Duration(milliseconds: 100)));
      expect(asked.elapsed, lessThan(const Duration(milliseconds: 500)));
      indexer.dispose();
    });
  });
}
