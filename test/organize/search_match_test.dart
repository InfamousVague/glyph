import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_marks.dart';
import 'package:ghost_md/core/search_hits.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/home/home_layout.dart';
import 'package:ghost_md/notes/all_notes.dart';

import '../core/make_note.dart';

/// What a search with operators finds (lib/core/search_match.dart through lib/core/search_hits.dart `findNotes` and
/// lib/notes/all_notes.dart `browseNotes`).
void main() {
  int day(int d) => DateTime(2026, 10, d, 12).millisecondsSinceEpoch;

  final garden = makeNote('garden', body: '# Garden plan\n\nFerns by the shed. #garden #home/outside\n\n- [ ] Buy compost\n- [x] Dig the bed', createdAt: day(2), updatedAt: day(14));
  final trip = makeNote('trip', body: '---\ntags: [travel, Home]\n---\n# Weekend trip\n\nPack the rain jacket.\n\n![a view](img_1.jpg)\n\nSee [[Garden plan]].', createdAt: day(5), updatedAt: day(15), starred: true);
  final code = makeNote('code', body: '# Snippets\n\n```\n#notatag\n- [ ] not a todo\n```\n\n`#nope` and https://example.com', createdAt: day(9), updatedAt: day(9));
  final done = makeNote('done', body: '# Errands\n\n- [x] Post office\n- [X] Bank', createdAt: day(1), updatedAt: day(3), archivedAt: day(4));
  final ticket = makeNote('ticket', body: '---\ntype: ticket\nid: GHO-3\nstatus: Done\n---\n# Fix login', createdAt: day(10), updatedAt: day(12));
  final memo = makeNote('memo', body: '# Call notes\n\n- ![voice 0:12](tape:12000-19500)', createdAt: day(11), updatedAt: day(11), recordingMs: 30000);
  final book = makeNote('book', body: '---\nbook: true\n---\n# Field guide\n\n- [[Ferns]]\n- [[Mosses]]', createdAt: day(1), updatedAt: day(1));
  final ferns = makeNote('ferns', body: '# Ferns\n\nShade lovers.', createdAt: day(6), updatedAt: day(6));
  final all = [garden, trip, code, done, ticket, memo, book, ferns];

  final spaces = Workspaces(
    list: const [Workspace(id: 'w-home', name: 'Home'), Workspace(id: 'w-yard', name: 'Yard', parent: 'w-home'), Workspace(id: 'w-work', name: 'Work')],
    of: const {'garden': 'w-yard', 'trip': 'w-home', 'ticket': 'w-work'},
  );
  final now = DateTime(2026, 10, 16, 15);
  final scope = SearchScope(notes: all, workspaces: spaces, now: now);

  List<String> found(String query, {Iterable<Note>? among}) => ids(findNotes(among ?? all, query, scope: scope).map((one) => one.note));

  setUp(NoteMarks.debugForget);

  test('reads tags from the words and the front matter, never from code, and counts the to-dos with words', () {
    final marks = NoteMarks.read(garden.body);
    expect(marks.tags, {'garden', 'home/outside'});
    expect(marks.openTodos, 1);
    expect(marks.doneTodos, 1);
    expect(NoteMarks.read(trip.body).tags, {'travel', 'home'});
    expect(NoteMarks.read(trip.body).picture, isTrue);
    expect(NoteMarks.read(trip.body).link, isTrue);
    final quiet = NoteMarks.read(code.body);
    expect(quiet.tags, isEmpty);
    expect(quiet.openTodos, 0);
    expect(quiet.link, isTrue);
    expect(NoteMarks.read(memo.body).picture, isFalse);
    expect(NoteMarks.read(memo.body).clip, isTrue);
    expect(NoteMarks.read('# A\n\n- [ ] ').openTodos, 0);
  });

  test('tag: finds the tag and the tags under it, and -tag: leaves them out', () {
    expect(found('tag:home'), unorderedEquals(['garden', 'trip']));
    expect(found('tag:home/outside'), ['garden']);
    expect(found('#travel'), ['trip']);
    expect(found('tag:home -tag:travel'), ['garden']);
    expect(found('tag:hom'), isEmpty);
  });

  test('in: a workspace takes the folders inside it; a notebook its pages', () {
    expect(found('in:home'), unorderedEquals(['garden', 'trip']));
    expect(found('in:yard'), ['garden']);
    expect(found('in:"field guide"'), ['ferns']);
    // A name being typed already narrows.
    expect(found('in:wor'), ['ticket']);
    expect(found('-in:home is:ticket'), ['ticket']);
  });

  test('is: and has:', () {
    expect(found('is:pinned'), ['trip']);
    expect(found('is:todo'), ['garden']);
    expect(found('has:todo'), ['garden']);
    // Every to-do ticked, or a ticket done.
    expect(found('is:done', among: all.where((n) => n.archivedAt == null)), ['ticket']);
    expect(found('is:done'), unorderedEquals(['ticket', 'done']));
    expect(found('is:ticket'), ['ticket']);
    expect(found('has:image'), ['trip']);
    expect(found('has:link'), unorderedEquals(['trip', 'code', 'book']));
    expect(found('has:recording'), ['memo']);
    expect(found('-has:link is:todo'), ['garden']);
    expect(found('is:notebook'), ['book']);
  });

  test('dates: made before and after, changed in a span', () {
    expect(found('before:2026-10-02'), unorderedEquals(['done', 'book']));
    expect(found('after:2026-10-11'), ['memo']);
    expect(found('updated:<3d'), unorderedEquals(['garden', 'trip']));
    expect(found('updated:2026-10-09'), ['code']);
  });

  test('an exact phrase, a word left out, and the words still ranked among what the operators let through', () {
    expect(found('"rain jacket"'), ['trip']);
    expect(found('"jacket rain"'), isEmpty);
    expect(found('ferns -shed'), ['ferns', 'book']);
    // The words rank as they always did: a name over words.
    expect(found('ferns'), ['ferns', 'garden', 'book']);
    expect(found('ferns tag:garden'), ['garden']);
    // An exact phrase is marked as a word is.
    final one = findNotes(all, '"rain jacket"', scope: scope).single;
    expect(one.snippet!.text, 'Pack the rain jacket.');
  });

  test('operators alone list every note they let through, pinned first among equals, then the newest', () {
    expect(found('tag:home'), ['trip', 'garden']);
    expect(found('is:archived'), ['done']);
  });

  test('the home page looks in the archive only for is:archived', () {
    List<String> home(String query) => ids(homeFound(all, query, HomeFilter.all, scope: scope).map((one) => one.note));
    expect(home('errands'), isEmpty);
    expect(home('errands is:archived'), ['done']);
    expect(home('is:archived'), ['done']);
  });

  test('All notes runs the same operators, its words held as it holds them', () {
    List<String> browse(String query, {bool archived = false}) => ids(browseNotes(all, Browse(query: query, archived: archived), scope: scope));
    expect(browse('tag:home'), ['trip', 'garden']);
    expect(browse('is:archived'), ['done']);
    expect(browse('post is:done', archived: true), ['done']);
    expect(browse('in:"field guide"'), ['ferns']);
    expect(browse('fern'), ['garden', 'ferns', 'book']);
  });

  test('marks are read once for the words a note has', () {
    final before = NoteMarks.debugReadings;
    findNotes(all, 'tag:garden', scope: scope);
    final once = NoteMarks.debugReadings - before;
    findNotes(all, 'tag:garden is:todo', scope: scope);
    findNotes(all, 'tag:home', scope: scope);
    expect(NoteMarks.debugReadings - before, once);
    findNotes([garden.copyWith(body: '${garden.body} #more')], 'tag:more', scope: scope);
    expect(NoteMarks.debugReadings - before, once + 1);
  });

  test('over four hundred notes a letter typed with operators costs what one without does, give or take', () {
    final many = [
      for (var i = 0; i < 400; i += 1)
        makeNote(
          'n$i',
          body: '# Note $i about ${i.isEven ? 'gardens' : 'travel'}\n\n${'Some words to look through, line after line. ' * 12}\n\n- [${i % 3 == 0 ? 'x' : ' '}] a thing to do #${i % 5 == 0 ? 'work/clients' : 'home'}\n\n${i % 7 == 0 ? '![p](img.jpg)' : ''}',
          createdAt: day(1 + i % 14),
          updatedAt: day(2 + i % 14),
          starred: i % 11 == 0,
        ),
    ];
    final wide = SearchScope(notes: many, workspaces: spaces);
    // Read once, as the search field taking the keyboard reads ahead (lib/core/search_ahead.dart); the marks the
    // first operator reads.
    findNotes(many, 'gar', scope: wide);
    final cold = Stopwatch()..start();
    findNotes(many, 'tag:work is:todo has:image', scope: wide);
    // ignore: avoid_print
    print("the first operator over 400 notes, with every note read for its marks: ${(cold.elapsedMicroseconds / 1000).toStringAsFixed(2)} ms");
    double typed(List<String> letters) {
      final clock = Stopwatch()..start();
      for (final query in letters) {
        findNotes(many, query, scope: wide);
      }
      return clock.elapsedMicroseconds / letters.length / 1000;
    }

    final plain = typed(['g', 'ga', 'gar', 'gard', 'garde', 'garden', 'gardens']);
    final operators = typed(['tag:work g', 'tag:work ga', 'tag:work gar', 'tag:work is:todo gard', 'tag:work is:todo garde', 'tag:work is:todo has:image garden', 'in:home -tag:home updated:<7d gardens']);
    // ignore: avoid_print
    print('a letter over 400 notes: ${plain.toStringAsFixed(2)} ms plain, ${operators.toStringAsFixed(2)} ms with operators');
    expect(operators, lessThan(plain * 2 + 2));
  });
}

