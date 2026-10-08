import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart' as book;
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/notes/own_templates.dart';

import '../core/make_note.dart';

/// Your own templates (lib/notes/own_templates.dart), case for case with the web's `notes/ownTemplates.test.ts`.
void main() {
  final day = builtIns[0];
  final map = builtIns.firstWhere((one) => one.kind == TemplateId.map);

  /// The eight built-ins' pages, and a notebook naming them, made at [at].
  List<Note> seeded([int at = 1000, String id = 'tpl']) => [
        makeNote(id, body: templatesNotebookBody([for (final one in builtIns) one.name]), createdAt: at + 10),
        for (final (i, template) in builtIns.indexed) makeNote('$id-${template.kind!.name}', body: templatePageBody(template), createdAt: at + i),
      ];
  Note withBody(Note note, String body) => note.copyWith(body: body);

  group('the Templates notebook', () {
    test('is found by its key beside book: true, never by its name', () {
      final body = templatesNotebookBody(['A day']);
      expect(isTemplatesBody(body), isTrue);
      expect(noteTitle(body), 'Templates');
      expect(isTemplatesBody(body.replaceFirst('title: "Templates"', 'title: "Starts"')), isTrue);
      expect(isTemplatesBody('---\ntitle: "Templates"\nbook: true\n---\n# Templates\n'), isFalse);
      expect(isTemplatesBody('---\ntemplates: true\n---\n# Not a notebook\n'), isFalse);
      // Said, and said yes: a notebook marked false, or a page's mark, is not one.
      expect(isTemplatesBody(body.replaceFirst('templates: true', 'templates: false')), isFalse);
      expect(isTemplatesBody(body.replaceFirst('templates: true', 'templates: page')), isFalse);
    });

    test('names a built-in’s page by its title, marks it, keeps its look beside it, and a new page leaves its heading open', () {
      expect(templatePageBody(day), '---\ntitle: "A day"\ntemplates: page\n---\n# {{date:YYYY-MM-DD}}\n\n{{date}}\n\n- [ ] ');
      expect(templatePageBody(map), '---\ntitle: "A map at the top"\ntemplates: page\nlook: map\n---\n# {{title}}\n\n{{date}}, {{time}}.\n');
      expect(newTemplatePageBody('A walk'), '---\ntitle: "A walk"\ntemplates: page\n---\n# {{title}}\n\n');
      expect(noteTitle(templatePageBody(map)), 'A map at the top');
      expect(isTemplatePageBody(templatePageBody(day)), isTrue);
      expect(isTemplatePageBody('# A day\n'), isFalse);
      expect(isTemplatePageBody(templatesNotebookBody(['A day'])), isFalse);
    });
  });

  group('the templates it holds', () {
    test('are none without a notebook, and its pages in its index’s order with one', () {
      expect(templatesOf([makeNote('n', body: '# A day')]), isNull);
      final notes = seeded();
      expect([for (final one in templatesOf(notes)!) one.name], [for (final one in builtIns) one.name]);
      final reordered = [for (final note in notes) note.id == 'tpl' ? withBody(note, templatesNotebookBody(['A page to read', 'A day'])) : note];
      expect([for (final one in templatesOf(reordered)!) one.name], ['A page to read', 'A day']);
    });

    test('keep a built-in’s sentence and rules while their words are its own, and say they are yours once changed', () {
      final notes = seeded();
      final first = templatesOf(notes)![0];
      expect((first.id, first.kind, first.sentence, first.look), ('tpl-day', TemplateId.day, day.sentence, null));
      final changed = [for (final note in notes) note.id == 'tpl-day' ? withBody(note, '${note.body}Water the plants.') : note];
      final own = templatesOf(changed)![0];
      expect((own.kind, own.sentence), (null, ownSentence));
    });

    test('pass on a page’s look and its words, never its name, its place or a key the app does not know', () {
      final page = makeNote('p', body: '---\ntitle: "A walk"\nlocation: 51.5074,-0.1278\nplace: "London"\nlook: map\nmood: calm\n---\n# {{title}}\n\nWhere.\n');
      final template = templateOf(page);
      expect(template.name, 'A walk');
      expect(template.look, Look.map);
      expect(template.words, '# {{title}}\n\nWhere.\n');
      expect(lookOf(template.words), isNull);
    });

    test('pass on a ticket’s keys with its words, so a Bug report’s page still makes a ticket and is still a Bug report', () {
      final bug = builtIns.firstWhere((one) => one.kind == TemplateId.bug);
      final body = templatePageBody(bug);
      // One block, the page's own keys and the ticket's together, so the page reads as one note anywhere.
      expect(body, '---\ntitle: "Bug report"\ntemplates: page\ntype: ticket\nid: "{{next-id}}"\nstatus: To do\n---\n# {{title}}\n\n## Steps to reproduce\n\n1. \n\n## Expected\n\n## Actual\n');
      final read = templateOf(makeNote('bug', body: body));
      expect((read.kind, read.words, read.sentence), (TemplateId.bug, bug.words, bug.sentence));
      // A page that is no ticket passes no `status:` of its own.
      expect(templateOf(makeNote('p', body: '---\ntitle: "Mood"\ntemplates: page\nstatus: calm\n---\n# {{title}}\n')).words, '# {{title}}\n');
    });

    test('read two notebooks made on two devices oldest first, and a page named twice once', () {
      final one = seeded(1000, 'one');
      final two = [makeNote('two', body: templatesNotebookBody(['A walk', 'A day']), createdAt: 5000), makeNote('walk', body: newTemplatePageBody('A walk'), createdAt: 5001)];
      expect([for (final template in templatesOf([...two, ...one])!) template.name], [for (final template in builtIns) template.name, 'A walk']);
    });
  });

  group('the pages kept apart', () {
    test('are every page a Templates notebook names, and not the notebook or anything else', () {
      final notes = [...seeded(), makeNote('mine', body: '# A walk\n\n- [ ] Shoes')];
      final apart = ownTemplatePages(notes);
      expect(apart.toList()..sort(), [for (final template in builtIns) 'tpl-${template.kind!.name}']..sort());
      expect(apart.contains('tpl'), isFalse);
      expect(ownTemplatePages([makeNote('mine', body: '# A day')]), isEmpty);
      // The home page's own port of the same rule (lib/core/book.dart) answers the same.
      expect(book.templatePages(notes), apart);
    });
  });

  group('a note of the person’s named like a page', () {
    final mine = makeNote('mine', body: '# Notes on a book\n\n- [ ] Return Middlemarch to the library', createdAt: 500);

    test('is never taken for the page: the seed makes the page beside it, and the card is the page’s', () {
      final plan = seedPlan([mine]);
      expect([for (final one in plan.pages) one.kind], TemplateId.values);
      final notes = [...seeded(), mine];
      final card = templatesOf(notes)!.firstWhere((one) => one.name == 'Notes on a book');
      expect((card.id, card.kind), ('tpl-book', TemplateId.book));
      expect(ownTemplatePages(notes).contains('mine'), isFalse);
    });

    test('stays the person’s when it is newer than the page, and the page stays apart', () {
      final later = Note(id: mine.id, body: mine.body, createdAt: 9000, updatedAt: mine.updatedAt);
      final notes = [later, ...seeded()];
      expect(templatesOf(notes)!.firstWhere((one) => one.name == 'Notes on a book').id, 'tpl-book');
      final apart = ownTemplatePages(notes);
      expect(apart.contains('mine'), isFalse);
      expect(apart.contains('tpl-book'), isTrue);
    });

    test('keeps every page of a name apart, as two devices’ seeds leave them', () {
      final notes = [...seeded(1000, 'one'), ...seeded(5000, 'two')];
      final apart = ownTemplatePages(notes);
      expect(apart.contains('one-day') && apart.contains('two-day'), isTrue);
      // The cards are the older notebook's pages, each name once.
      expect([for (final one in templatesOf(notes)!.where((one) => one.name == 'A day')) one.id], ['one-day']);
    });
  });

  group('the seed', () {
    test('opens a notebook there is, makes all eight and the notebook the first time, and only what is missing after a cut', () {
      final notes = seeded();
      expect(seedPlan(notes).open, same(notes[0]));
      final first = seedPlan(const []);
      expect(first.open, isNull);
      expect([for (final one in first.pages) one.kind], TemplateId.values);
      // Cut short after three pages: those are there, so only the rest and the notebook.
      final again = seedPlan(seeded().sublist(1, 4));
      expect([for (final one in again.pages) one.kind], [TemplateId.book, TemplateId.map, TemplateId.reading, TemplateId.bug, TemplateId.feature]);
      expect(again.index, templatesNotebookBody([for (final one in builtIns) one.name]));
    });
  });
}
