import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/notes/note_templates.dart';
import 'package:ghost_md/notes/own_templates.dart';
import 'package:ghost_md/notes/place_templates.dart';

import '../core/make_note.dart';

/// A notebook's and a folder's own template (lib/notes/place_templates.dart; Matt, 2026-10-30, of a list of
/// plain-Markdown features: "add all 12"): where each is written, which one a new note made there starts from, the
/// folder's taken from the folder it is in, a template said by a word of its name, and the placeholders filled.
void main() {
  const folders = [
    Workspace(id: 'work', name: 'Work'),
    Workspace(id: 'clients', name: 'Clients', parent: 'work'),
    Workspace(id: 'acme', name: 'Acme', parent: 'clients'),
    Workspace(id: 'kiln', name: 'Kiln'),
  ];
  const bug = NoteTemplate(id: 'page-bug', name: 'Bug report', sentence: '', words: '# {{title}}\n\n## Steps\n');
  const meeting = NoteTemplate(id: 'page-meeting', name: 'A meeting', sentence: '', words: '# Meeting\n\nWith ');
  const templates = [bug, meeting];

  group('a notebook', () {
    test('names its template as a link in its own front matter, and takes it off with none', () {
      const book = '---\ntitle: "Kiln"\nbook: true\n---\n# Kiln\n\n';
      final named = withNotebookTemplate(book, 'Bug report');
      expect(named, contains('page-template: "[[Bug report]]"'));
      expect(notebookTemplateName(named), 'Bug report');
      expect(withNotebookTemplate(named, null), book);
      expect(notebookTemplateName('---\nbook: true\npage-template: A meeting\n---\n'), 'A meeting', reason: 'a name written by hand, no link');
      expect(placeTemplate(notebook: named, templates: templates), bug);
    });
  });

  group('a folder', () {
    const page = '---\ntitle: "Bug report"\ntemplates: page\n---\n# {{title}}\n';

    test('is named on the template’s page, from the top, and taken out again; the other folders stay', () {
      final once = withTemplateFolder(page, 'Work/Clients', true);
      expect(once, contains('folders: [Work/Clients]'));
      final twice = withTemplateFolder(once, 'Kiln', true);
      expect(templateFolders(twice), ['Work/Clients', 'Kiln']);
      expect(templateFolders(withTemplateFolder(twice, 'work/clients', false)), ['Kiln']);
      expect(withTemplateFolder(withTemplateFolder(twice, 'Kiln', false), 'Work/Clients', false), page);
    });

    test('a folder with none takes the template of the folder it is in, the nearest first', () {
      final pages = {'page-bug': withTemplateFolder(page, 'Work', true), 'page-meeting': withTemplateFolder(page, 'Work/Clients', true)};
      expect(folderTemplate(folders, 'acme', templates, pages), meeting, reason: 'Clients is nearer than Work');
      expect(folderTemplate(folders, 'clients', templates, pages), meeting);
      expect(folderTemplate(folders, 'work', templates, pages), bug);
      expect(folderTemplate(folders, 'kiln', templates, pages), isNull);
      expect(ownFolderTemplate(folders, 'acme', templates, pages), isNull, reason: 'its own, not its parents’');
      expect(placeTemplate(folders: folders, folderId: 'acme', templates: templates, pages: pages), meeting);
    });

    test('a folder named by its name alone is that folder wherever it sits', () {
      final pages = {'page-bug': withTemplateFolder(page, 'Clients', true)};
      expect(folderTemplate(folders, 'clients', templates, pages), bug);
      expect(folderTemplate(folders, 'acme', templates, pages), bug, reason: 'inside Clients');
    });
  });

  test('a template said by a word of its name', () {
    expect(templateSaid(builtIns, 'bug')?.name, 'Bug report');
    expect(templateSaid(builtIns, 'meeting')?.name, 'A meeting');
    expect(templateSaid(builtIns, 'feature')?.name, 'Feature');
    expect(templateSaid(builtIns, 'Bug report')?.name, 'Bug report');
    expect(templateSaid(builtIns, 'spaceship'), isNull);
  });

  test('a template asked for in a place: a notebook by its title, else a folder, else nothing', () {
    final notes = [
      makeNote('kiln-book', body: '---\ntitle: "Kiln"\nbook: true\npage-template: "[[A meeting]]"\n---\n# Kiln\n\n'),
      makeNote('templates', body: templatesNotebookBody(['Bug report'])),
    ];
    final inBook = templateForPlace(word: 'bug', place: 'kiln', notes: notes, folders: folders, templates: templates)!;
    expect(inBook.template, bug);
    expect(inBook.notebook?.id, 'kiln-book');
    expect(templateForPlace(word: 'note', place: 'Kiln', notes: notes, folders: folders, templates: templates)!.template, meeting, reason: 'a plain note is the notebook’s own');
    final inFolder = templateForPlace(word: 'meeting', place: 'Clients', notes: const [], folders: folders, templates: templates)!;
    expect(inFolder.folder?.id, 'clients');
    expect(templateForPlace(word: 'bug', place: 'Mars', notes: notes, folders: folders, templates: templates), isNull);
    expect(templateForPlace(word: 'spaceship', place: 'Kiln', notes: notes, folders: folders, templates: templates), isNull);
  });

  test('the placeholders are filled, {{author}} the account’s and {{cursor}} where the caret goes, then taken out', () {
    const template = NoteTemplate(id: 'own', name: 'Standup', sentence: '', words: '---\ntype: ticket\n---\n# {{title}}\n\nBy {{author}} on {{date:YYYY-MM-DD}} at {{time}}\n\n## Notes\n\n- {{cursor}}\n\n## Next\n\n- ');
    final at = DateTime(2026, 10, 30, 9, 5);
    final filled = fillNoteTemplate(template, at, {}, title: 'Kiln sync', author: 'Matt');
    expect(filled.body, '---\ntype: ticket\n---\n# Kiln sync\n\nBy Matt on 2026-10-30 at 09:05\n\n## Notes\n\n- \n\n## Next\n\n- ');
    expect(filled.body.substring(0, filled.caret), endsWith('## Notes\n\n- '), reason: 'the caret at {{cursor}}, not at the first open line');
    expect(filled.body, isNot(contains('{{')));
    // No {{cursor}}: the first line left open, as before.
    final plain = fillNoteTemplate(const NoteTemplate(id: 'x', name: 'x', sentence: '', words: '# {{title}}\n\nBy {{author}}\n\n- '), at, {}, author: '');
    expect(plain.body, '# \n\nBy \n\n- ');
    expect(plain.caret, 2);
  });
}
