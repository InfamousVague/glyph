import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart' hide matches;
import 'package:ghost_md/core/book.dart';
import 'package:ghost_md/core/canvas_body.dart';
import 'package:ghost_md/core/front_matter.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/core/properties.dart';
import 'package:ghost_md/core/sample_library.dart';

import 'make_note.dart';

/// What a note's body says about it (lib/core/note_text.dart, front_matter.dart, book.dart, properties.dart,
/// canvas_body.dart): the web's cases for a title (`core/noteTitle.test.ts`, with its shared fixture's rows), front
/// matter and a short address, then the web's own answers over the seeded library.
void main() {
  group('a note’s lines without its front matter', () {
    test('puts the front matter’s title first, where it has one', () {
      expect(withoutFrontMatter(['---', 'title: "Plan"', 'id: x', '---', '', 'Words']), ['Plan', '', 'Words']);
      expect(withoutFrontMatter(['---', 'id: x', '---', '# Plan']), ['# Plan']);
    });

    test('keeps every line of a note whose opening rule is not front matter', () {
      const ruled = ['---', 'Some words here', '---', 'Real title'];
      expect(withoutFrontMatter(ruled), ruled);
      expect(noteTitle(ruled.join('\n')), '---');
    });
  });

  group('a title with a blank in it (docs/DESIGN.md §145)', () {
    // The rows of the web's `core/titles.fixture.json`: a first line, and what `noteTitle` answers for it.
    const rows = {
      '# {?}': '',
      '# {?a title}': '',
      '{?}': '',
      '{?how long to boil an egg}': 'how long to boil an egg',
      '# {?who wrote Dune}': 'who wrote Dune',
      '# Trip to {?capital of Japan}': 'Trip to',
      '# Trip to Tokyo': 'Trip to Tokyo',
      '# Trip to ??Tokyo??(Qwen3.5 4B from memory, 2026-09-28. Asked: capital of Japan)': 'Trip to Tokyo',
      '# {?} for {?which city}': 'for',
      '# Doubts ??four hundred??(check with Sam)': 'Doubts ??four hundred??(check with Sam)',
    };

    test('reads every row of the shared fixture', () {
      for (final row in rows.entries) {
        expect(noteTitle('${row.key}\n\nSome words under it.'), row.value, reason: row.key);
      }
    });

    test('is untitled until a title blank fills, and never shows a fill’s bracket', () {
      expect(noteTitle('# {?}\n\nBook the cabin for the second week of October.'), '');
      expect(noteTitle('# Trip to ??Tokyo??(Qwen3.5 4B from memory, 2026-09-28. Asked: capital of Japan) §§'), 'Trip to Tokyo');
    });
  });

  group('a title otherwise', () {
    test('is the first line of words: under a picture, without its hashes, a comment’s anchor or the bookmark', () {
      expect(noteTitle('![a photo](image/a.jpg)\n\nThe walk'), 'The walk');
      expect(noteTitle('## Plans[^c1] §§\nwords'), 'Plans');
      expect(noteTitle('---\ntitle: "Cabin weekend, laid out"\n---\n{"nodes":[]}'), 'Cabin weekend, laid out');
      expect(noteTitle(''), '');
    });

    test('is matched as it is said, not as it is typed', () {
      expect(titleKey('  The Oaks!  '), 'the oaks');
      expect(sameTitle('The Oaks!', 'the oaks'), isTrue);
      expect(sameTitle('!!', '??'), isFalse);
    });
  });

  group('front matter', () {
    test('ends at its closing fence, and is none where a line of words stands in it or it never closes', () {
      expect(frontMatterEnd(['---', 'a: 1', '', '---', 'words']), 4);
      expect(frontMatterEnd(['---', 'some words', '---']), 0);
      expect(frontMatterEnd(['---', ...List.filled(60, 'a: 1'), '---']), 0);
      expect(frontMatterEnd(['words']), 0);
      expect(frontMatterOffset('---\na: 1\n---\nwords'), 13);
    });

    test('reads a key in any case, with its quotes off as YAML takes them', () {
      const body = '---\nTitle: "A \\"quoted\\" name"\nwho: \'it\'\'s Sam\'\nplain: yes\n---\n';
      expect(frontMatterValue(body, 'title'), 'A "quoted" name');
      expect(frontMatterValue(body, 'who'), "it's Sam");
      expect(frontMatterValue(body, 'plain'), 'yes');
      expect(frontMatterValue(body, 'missing'), isNull);
      expect(frontMatterValue('no front matter', 'title'), isNull);
      expect(quotedTitle('A "name"', 'x'), '"A \'name\'"');
      expect(quotedTitle('  ', 'Notebook'), '"Notebook"');
    });
  });

  group('an address, shortened (core/shortUrl.ts)', () {
    test('keeps the host and the ends of a long path', () {
      expect(shortUrl('https://www.notion.so/attackfm/Launch-plan-9f2b3c'), 'notion.so/att…b3c');
      expect(shortUrl('https://attack.fm/glyph'), 'attack.fm/glyph');
      expect(shortUrl('https://attack.fm/'), 'attack.fm');
      expect(shortenUrls('See https://www.notion.so/attackfm/Launch-plan-9f2b3c today'), 'See notion.so/att…b3c today');
    });
  });

  group('a search (notes/allNotes.ts `matches`)', () {
    test('wants every word somewhere in the note, whatever the case, and reads a priority’s sign as its name', () {
      final note = makeNote('n', body: '# Trip\n\n- [ ] Packing list ⏫\n??Tokyo??(Qwen3.5 4B from memory, 2026-09-28. Asked: capital of Japan)');
      expect(matches(note, 'trip PACKING'), isTrue);
      expect(matches(note, 'trip boots'), isFalse);
      expect(matches(note, 'high priority'), isTrue);
      expect(matches(note, 'tokyo'), isTrue);
      // A filled blank's hidden bracket is not the note's words.
      expect(matches(note, 'memory'), isFalse);
      expect(matches(note, '   '), isTrue);
    });
  });

  group('a list item’s lead and anchor (core/itemSyntax.ts)', () {
    test('reads a bullet, a number, a to-do and a choice', () {
      expect(listLead('words'), isNull);
      expect(listLead('- Milk')!.wordsAt, 2);
      expect(listLead('  12) Step')!.marker, '12)');
      expect(taskBox('- [x] Done'), (at: 2, done: true));
      expect(taskBox('1. [ ] Open'), (at: 3, done: false));
      expect(taskBox('- [ ]glued'), isNull);
      expect(listLead('- (x) Cabin')!.picked, isTrue);
      expect(listLead('1. ( ) Pick')!.picked, isNull);
    });

    test('takes an item’s anchor off with the space before it, and leaves a superscript alone', () {
      expect(withoutAnchor('- [ ] Ship it ^ship'), '- [ ] Ship it');
      expect(withoutAnchor('- [ ] Ship it ^ship [3/8]'), '- [ ] Ship it [3/8]');
      expect(withoutAnchor('E = mc^2^'), 'E = mc^2^');
      expect(anchorSpan('- Ask Sam ^ask-sam')!.id, 'ask-sam');
    });
  });

  group('a note drawn small (notes/peek.ts `peekMarkdown`)', () {
    test('is the note after its title, a board’s fence left out and the blank lines closed up', () {
      expect(peekMarkdown('# Title\n\n\nFirst\n\n\nSecond'), 'First\n\nSecond');
      expect(peekMarkdown('---\ntitle: "T"\n---\n# T\nwords'), '# T\nwords');
      expect(peekMarkdown('# Plan\n\n```board\nNow: a\n```\n\n- [ ] Do it ^a'), '- [ ] Do it');
      expect(peekMarkdown('# Code\n\n```js\nconst a = 1;\n```'), '```js\nconst a = 1;\n```');
      expect(peekMarkdown('# Long\n${List.generate(30, (i) => 'line $i').join('\n')}').split('\n').length, peekSourceLines);
    });
  });

  group('a ticket (core/properties.ts)', () {
    test('is a note whose front matter says so, with its key and its status placed', () {
      const body = '---\ntype: Ticket\nid: gho-12\nstatus: In review\nassignee: "@Sam"\n---\n# Fix it';
      expect(isTicket(body), isTrue);
      final ticket = ticketOf(body)!;
      expect([ticket.id, ticket.status, ticket.category, ticket.assignee], ['GHO-12', 'In review', StatusCategory.doing, 'Sam']);
      expect(ticketOf('# A note'), isNull);
    });

    test('places a status by its words, then by its notebook’s workflow', () {
      expect(statusCategory('Done'), StatusCategory.done);
      expect(statusCategory("Won't do"), StatusCategory.done);
      expect(statusCategory('All done'), StatusCategory.done);
      expect(statusCategory('Backlog'), StatusCategory.todo);
      expect(statusCategory(null), StatusCategory.todo);
      expect(statusCategory('In QA'), StatusCategory.doing);
      const workflow = ['Ideas', 'Shaping', 'Live'];
      expect([for (final s in workflow) statusCategory(s, workflow)], [StatusCategory.todo, StatusCategory.doing, StatusCategory.done]);
      expect(statusCategory('Shaping'), StatusCategory.todo);
      expect(statusesOf('---\nbook: true\nstatuses: [Ideas, Building, ideas, Live]\n---\n'), ['Ideas', 'Building', 'Live']);
      expect(statusesOf(null), defaultStatuses);
    });

    test('reads a list across, with commas, and a note link as itself', () {
      expect(propertyList('["[[GHO-9]]", "[[GHO-10]]"]'), ['[[GHO-9]]', '[[GHO-10]]']);
      expect(propertyList('Matt, Claude'), ['Matt', 'Claude']);
      expect(propertyList('[[GHO-9]]'), ['[[GHO-9]]']);
      expect(propertyList('[bug, ui]'), ['bug', 'ui']);
      expect(propertyList(''), isEmpty);
    });
  });

  group('a canvas (canvas/jsonCanvas.ts)', () {
    test('is JSON with nodes or edges under its front matter, and counts the cards that are cards', () {
      expect(isCanvasBody('{"nodes":[],"edges":[]}'), isTrue);
      expect(isCanvasBody('{}'), isFalse);
      expect(isCanvasBody('# Words'), isFalse);
      expect(isCanvasBody('{ not json'), isFalse);
      const body = '---\ntitle: "Map"\n---\n{"nodes":[{"id":"a","type":"text","text":"hi","x":0,"y":0,"width":10,"height":10},'
          '{"id":"a","type":"text","text":"twice","x":0,"y":0,"width":10,"height":10},{"id":"b","type":"file","x":0,"y":0,"width":1,"height":1},'
          '{"id":"c","type":"group","x":0,"y":0,"width":1,"height":1}]}';
      expect(canvasCardCount(body), 2);
    });
  });

  group('over the seeded library, as the web app answers', () {
    final web = jsonDecode(File('test/core/fixtures/web_library.json').readAsStringSync()) as Map<String, dynamic>;
    final read = web['read'] as Map<String, dynamic>;
    final notes = seedLibrary();
    final index = bookIndex(notes);

    test('titles each note, draws it small, and counts a canvas’s cards as the web does', () {
      for (final note in notes) {
        final said = read[note.id] as Map<String, dynamic>;
        expect(noteTitle(note.body), said['title'], reason: note.id);
        expect(peekMarkdown(note.body), said['peek'], reason: note.id);
        expect(canvasCardCount(note.body), said['cards'], reason: note.id);
      }
    });

    test('finds each page’s notebook, and a notebook’s pages, as the web does', () {
      for (final note in notes) {
        final said = read[note.id] as Map<String, dynamic>;
        final place = placeOf(index, note);
        expect(place?.title, said['book'], reason: note.id);
        expect(place?.at, said['at'], reason: note.id);
        expect([for (final c in chaptersOf(note.body)) c.title], said['chapters'], reason: note.id);
      }
    });

    test('reads each ticket, in its notebook’s workflow, as the web does', () {
      for (final note in notes) {
        final said = (read[note.id] as Map<String, dynamic>)['ticket'] as Map<String, dynamic>?;
        final place = placeOf(index, note);
        final ticket = ticketOf(note.body, place == null ? null : statusesOf(place.book.body));
        expect(ticket == null ? null : {'id': ticket.id, 'status': ticket.status, 'category': ticket.category.name, 'assignee': ticket.assignee}, said, reason: note.id);
      }
    });

    test('finds the notes a search finds on the web', () {
      for (final entry in (web['searched'] as Map<String, dynamic>).entries) {
        expect([for (final n in notes) if (matches(n, entry.key)) n.id], entry.value, reason: entry.key);
      }
    });

    test('says a journal’s card as the web does', () {
      final at = DateTime.fromMillisecondsSinceEpoch(seedNow);
      final journal = exampleJournal(at);
      final cards = journalCards([...notes, makeNote('j', body: journal.journal, createdAt: seedNow), makeNote('e', body: journal.entry, createdAt: seedNow)]);
      final said = (web['journalCards'] as Map<String, dynamic>)['j'] as Map<String, dynamic>;
      expect(cards.keys, ['j']);
      expect(cards['j']!.count, said['count']);
      expect([for (final entry in cards['j']!.newest) {'title': entry.title, 'when': entry.when}], said['newest']);
      expect(entryPages([makeNote('j', body: journal.journal), makeNote('e', body: journal.entry), ...notes]), {'e'});
    });
  });
}
