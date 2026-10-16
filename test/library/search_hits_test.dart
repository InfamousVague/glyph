import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/search_hits.dart';

import 'support.dart';

/// What a search finds and in what order (lib/core/search_hits.dart): the port's own, past the page's one rule.
void main() {
  final rules = makeNote('rules', body: '# Claude rules\n\nNever co-author commits.', updatedAt: 5);
  final tasks = makeNote('tasks', body: '# Task Management\n\n- [ ] Ask **Claude** to move the ticket when it is done\n- [ ] Tidy', updatedAt: 9);
  final book = makeNote('book', body: '# The Book\n\nNothing about it here.', updatedAt: 7);
  final clause = makeNote('clause', body: '# Contract\n\nThe second clause is the long one.', updatedAt: 8);
  final all = [tasks, clause, book, rules];

  test('puts a note found by its name over one found by its words, and leaves out what has neither', () {
    expect(ids(findNotes(all, 'claude').map((one) => one.note)), ['rules', 'tasks', 'clause']);
    expect(findNotes(all, '  '), isEmpty);
    expect(findNotes(all, 'kettle'), isEmpty);
  });

  test('forgives a slip in a word of four letters or more, and a word still being typed', () {
    expect(ids(findNotes(all, 'cluade').map((one) => one.note)), contains('rules'));
    expect(ids(findNotes(all, 'calud').map((one) => one.note)), contains('rules'));
    expect(ids(findNotes(all, 'managment').map((one) => one.note)), ['tasks']);
    // Three letters are found as written or not at all.
    expect(findNotes(all, 'bok'), isEmpty);
  });

  test('wants every word, each found where it is nearest', () {
    expect(ids(findNotes(all, 'task claude').map((one) => one.note)), ['tasks']);
    expect(findNotes(all, 'task kettle'), isEmpty);
  });

  test('says what it matched: the letters in the name, and the line of the note they stand in', () {
    final byName = findNotes(all, 'claude').first;
    expect(byName.byName, isTrue);
    expect(byName.snippet, isNull);
    expect(marksIn('Claude rules', byName.needles), [(0, 6)]);

    final byWords = findNotes(all, 'claude')[1];
    final snippet = byWords.snippet!;
    expect(snippet.text, 'Ask Claude to move the ticket when it is done');
    expect([for (final (from, to) in snippet.marks) snippet.text.substring(from, to)], ['Claude']);

    // A near word is marked as the note has it.
    final near = findNotes(all, 'cluade').firstWhere((one) => one.note.id == 'tasks');
    expect([for (final (from, to) in near.snippet!.marks) near.snippet!.text.substring(from, to)], ['Claude']);
  });

  test('cuts a long line around what it matched', () {
    final long = makeNote('long', body: '# Notes\n\n${'word ' * 40}needle ${'more ' * 60}');
    final snippet = findNotes([long], 'needle').single.snippet!;
    expect(snippet.text.startsWith('…'), isTrue);
    expect(snippet.text.endsWith('…'), isTrue);
    expect(snippet.text.length, lessThan(150));
    expect(snippet.text, contains('needle'));
  });

  test('finds a note by one of its aliases as near as by its name, above one that only says the word', () {
    final trip = makeNote('trip', body: '---\naliases: [Lisbon]\n---\n# Portugal\n\nTen days.', updatedAt: 1);
    final diary = makeNote('diary', body: '# Diary\n\nLisbon was hot.', updatedAt: 9);
    final found = findNotes([diary, trip], 'lisbon');
    expect([for (final one in found) one.note.id], ['trip', 'diary']);
    // Not by its name: the row shows the line that says the alias.
    expect(found.first.byName, isFalse);
  });
}
