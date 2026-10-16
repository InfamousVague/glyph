import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_marks.dart';
import 'package:ghost_md/core/tag_index.dart';

import '../core/make_note.dart';

/// The library's tags (lib/core/tag_index.dart): counted, as a tree, and renamed across notes.
void main() {
  setUp(NoteMarks.debugForget);

  final a = makeNote('a', body: '# Garden\n\nFerns #garden #work/clients/acme', updatedAt: 3);
  final b = makeNote('b', body: '---\ntags: [work, Home]\n---\n# Trip\n\nPack. #work/clients', updatedAt: 2);
  final c = makeNote('c', body: '# Code\n\n`#work` and\n```\n#work\n```\n#travel', updatedAt: 1);
  final old = makeNote('old', body: '# Old\n\n#work', archivedAt: 9);

  test('counts each tag over the notes a list shows, the archive left out', () {
    final index = tagIndex([a, b, c, old]);
    expect(index.names.toSet(), {'garden', 'work/clients/acme', 'work', 'home', 'work/clients', 'travel'});
    expect(index.countOf('work'), 2);
    expect(ids(index.notesUnder('work/clients')), ['a', 'b']);
    expect(ids(index.notesUnder('work/clients/acme')), ['a']);
    expect(index.countOf('travel'), 1);
  });

  test('a tree of tags inside tags, each counting a note once, sorted by count or by name', () {
    final index = tagIndex([a, b, c]);
    final byCount = index.tree();
    expect([for (final node in byCount) '${node.name} ${node.count}'], ['work 2', 'garden 1', 'home 1', 'travel 1']);
    final work = byCount.first;
    expect(work.own, 1);
    expect([for (final node in work.children) '${node.label} ${node.count} ${node.own}'], ['clients 2 1']);
    expect(work.children.single.children.single.name, 'work/clients/acme');
    expect(work.children.single.children.single.depth, 2);
    final byName = index.tree(TagSort.name);
    expect([for (final node in byName) node.name], ['garden', 'home', 'travel', 'work']);
    // Made once for each order.
    expect(identical(index.tree(), byCount), isTrue);
  });

  test('a rename reaches every #tag and every tag under it, keeping the rest as written, never in code', () {
    expect(renameTagIn(a.body, 'work', 'office'), '# Garden\n\nFerns #garden #office/clients/acme');
    expect(renameTagIn('#Work/Clients and #WORK and #workshop', 'work', 'office'), '#office/Clients and #office and #workshop');
    expect(renameTagIn(c.body, 'work', 'office'), c.body);
    expect(identical(renameTagIn(c.body, 'garden', 'yard'), c.body), isTrue);
    // A tag under another, renamed alone.
    expect(renameTagIn('#work/clients/acme #work', 'work/clients', 'clients'), '#clients/acme #work');
  });

  test('a rename reaches the front matter’s tags lists, flow or plain, with or without their #', () {
    expect(renameTagIn(b.body, 'work', 'office'), '---\ntags: [office, Home]\n---\n# Trip\n\nPack. #office/clients');
    expect(renameTagIn('---\ntag: work, #work/x, home\n---\nWords', 'work', 'job'), '---\ntag: job, #job/x, home\n---\nWords');
    expect(renameTagIn('---\nlabels: work\n---\nWords', 'work', 'job'), '---\nlabels: work\n---\nWords');
  });

  test('says which notes a rename changes, the archive’s too', () {
    final changes = tagRenames([a, b, c, old], 'work', 'office');
    expect([for (final one in changes) one.note.id], ['a', 'b', 'old']);
    expect(changes.last.body, '# Old\n\n#office');
  });

  test('a name a tag can have', () {
    expect(isTagName('office'), isTrue);
    expect(isTagName('work/clients'), isTrue);
    expect(isTagName('2026'), isFalse);
    expect(isTagName('two words'), isFalse);
    expect(isTagName('work/'), isFalse);
    expect(isTagName(''), isFalse);
    expect(tidyTagName('  #Office '), 'Office');
  });
}
