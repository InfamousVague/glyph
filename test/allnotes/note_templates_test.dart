import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note_text.dart';
import 'package:ghost_md/notes/note_templates.dart';

/// The eight templates a new note can start from (lib/notes/note_templates.dart), case for case with the web's
/// `notes/noteTemplates.test.ts`: each filled exactly as it will be written at 14:05 on Monday 28 September 2026 in
/// en-GB, with its caret (`|`).
void main() {
  final at = DateTime(2026, 9, 28, 14, 5);
  NoteTemplate template(TemplateId id) => builtIns.firstWhere((one) => one.kind == id);
  FilledTemplate fill(TemplateId id, {List<String> taken = const [], String? nextId}) => fillNoteTemplate(template(id), at, {for (final t in taken) titleKey(t)}, nextId: nextId);
  String made(TemplateId id, {List<String> taken = const [], String? nextId}) {
    final filled = fill(id, taken: taken, nextId: nextId);
    return '${filled.body.substring(0, filled.caret)}|${filled.body.substring(filled.caret)}';
  }

  test('are in this order, each with its name and its fixed sentence', () {
    expect(builtIns.every((one) => one.id == one.kind!.name), isTrue);
    expect([for (final one in builtIns) (one.id, one.name, one.sentence)], [
      ('day', 'A day', 'Named for today, with a to-do to start.'),
      ('meeting', 'A meeting', 'Named for this minute, with who was there, notes and to-dos.'),
      ('checklist', 'A checklist', 'A name to type, then a to-do.'),
      ('book', 'Notes on a book', 'Its title, who wrote it, notes and quotes.'),
      ('map', 'A map at the top', 'Where you are, drawn large above the words.'),
      ('reading', 'A page to read', 'A large title, a lead line and a column set for reading.'),
      ('bug', 'Bug report', 'A ticket: how to make it happen, what should, and what did.'),
      ('feature', 'Feature', 'A ticket: the problem, the proposal, and when it is done.'),
    ]);
  });

  test('make each note exactly, with the caret in its first open line', () {
    expect(made(TemplateId.day), '# 2026-09-28\n\nMonday 28 September\n\n- [ ] |');
    expect(made(TemplateId.meeting), '# Meeting 2026-09-28 14.05\n\nWith |\n\n## Notes\n\n- \n\n## To do\n\n- [ ] ');
    expect(made(TemplateId.checklist), '# |\n\n- [ ] ');
    expect(made(TemplateId.book), '# |\n\nBy \n\n## Notes\n\n- \n\n## Quotes\n\n> ');
    expect(made(TemplateId.map), '---\nlook: map\n---\n# |\n\nMonday 28 September, 14:05.\n');
    expect(made(TemplateId.reading), '---\nlook: reading\n---\n# |\n');
    expect(made(TemplateId.bug, nextId: 'GHO-13'), '---\ntype: ticket\nid: GHO-13\nstatus: To do\n---\n# |\n\n## Steps to reproduce\n\n1. \n\n## Expected\n\n## Actual\n');
    expect(made(TemplateId.feature, nextId: 'GHO-14'), '---\ntype: ticket\nid: GHO-14\nstatus: To do\n---\n# |\n\n## Problem\n\n## Proposal\n\n## Done when\n\n- [ ] ');
  });

  test('make a ticket with no id where the note is made with no key, and keep its front matter out of the words', () {
    expect(made(TemplateId.bug), '---\ntype: ticket\nstatus: To do\n---\n# |\n\n## Steps to reproduce\n\n1. \n\n## Expected\n\n## Actual\n');
    expect(fill(TemplateId.feature).words, '# \n\n## Problem\n\n## Proposal\n\n## Done when\n\n- [ ] ');
    // A notebook's New ticket names it as it is made.
    final named = fillNoteTemplate(template(TemplateId.bug), at, const {}, nextId: 'GHO-2', title: 'Login loop');
    expect(named.title, 'Login loop');
    expect(named.body.startsWith('---\ntype: ticket\nid: GHO-2\nstatus: To do\n---\n# Login loop\n'), isTrue);
  });

  test('name a note by its heading, or by nothing where the heading is left open', () {
    expect(fill(TemplateId.day).title, '2026-09-28');
    expect(fill(TemplateId.meeting).title, 'Meeting 2026-09-28 14.05');
    expect(fill(TemplateId.checklist).title, '');
    // The record keeps the words after the front matter: the look is not a word.
    expect(fill(TemplateId.reading).words, '# \n');
  });

  test('give a taken name " (2)" before the caret is measured, so it lands where it would have', () {
    expect(made(TemplateId.meeting, taken: ['Meeting 2026-09-28 14.05']), '# Meeting 2026-09-28 14.05 (2)\n\nWith |\n\n## Notes\n\n- \n\n## To do\n\n- [ ] ');
    final second = fill(TemplateId.meeting, taken: ['Meeting 2026-09-28 14.05']);
    expect(second.words.startsWith('# Meeting 2026-09-28 14.05 (2)\n'), isTrue);
    expect(second.renamed, isTrue);
    expect(made(TemplateId.day, taken: ['2026-09-28', '2026-09-28 (2)']), '# 2026-09-28 (3)\n\nMonday 28 September\n\n- [ ] |');
    expect(fill(TemplateId.day).renamed, isFalse);
    // An open heading has no name, and is never taken.
    expect(fill(TemplateId.checklist, taken: ['']).renamed, isFalse);
  });

  test('hold no spoiler, effect, whole line of emphasis or journal’s name, and no words in a to-do', () {
    for (final one in builtIns) {
      expect(RegExp(r'\|\||==|~~|\{\{journal\}\}').hasMatch(one.words), isFalse);
      for (final line in one.words.split('\n')) {
        expect(RegExp(r'^\s*[*_][^*_].*[*_]\s*$').hasMatch(line), isFalse);
        expect(RegExp(r'^- \[ \] \S').hasMatch(line), isFalse);
      }
      // Its shape shows in the first five lines a card shows.
      expect(fill(one.kind!).words.split('\n').take(5).join().trim(), isNotEmpty);
    }
  });

  group('the engine under them (core/template.ts)', () {
    test('writes a stamp in Moment’s tokens, words in brackets kept, and the ISO week', () {
      expect(formatStamp(at, 'YYYY-MM-DD'), '2026-09-28');
      expect(formatStamp(at, 'dddd [at] HH:mm'), 'Monday at 14:05');
      expect(formatStamp(at, 'Do MMMM YY, h:mm a'), '28th September 26, 2:05 pm');
      expect(formatStamp(at, 'ddd D MMM, hh A'), 'Mon 28 Sept, 02 PM');
      expect(formatStamp(at, 'GGGG-[W]WW'), '2026-W40');
      // 1 January 2021, a Friday, is in 2020's week 53; 30 December 2024 is in 2025's week 1.
      expect(formatStamp(DateTime(2021, 1, 1), 'GGGG-[W]WW'), '2020-W53');
      expect(formatStamp(DateTime(2024, 12, 30), 'GGGG-[W]W'), '2025-W1');
    });

    test('fills the placeholders it knows, and leaves any other as it was typed', () {
      expect(fillTemplate('{{date}} {{time}} {{weekday}} {{title}}|{{journal}}', at: at, title: 'T', journal: 'J'), 'Monday 28 September 14:05 Monday T|J');
      expect(fillTemplate('{{constructor}} {{toString}} {{nope:YYYY}}', at: at), '{{constructor}} {{toString}} {{nope:YYYY}}');
      expect(fillTemplate('{{ date:YYYY }}', at: at), '2026');
      // Outside front matter the next id is filled with nothing where there is none.
      expect(fillTemplate('See {{next-id}}.', at: at), 'See .');
    });

    test('finds the first line left open', () {
      expect(firstOpenAt('# \n\n- [ ] '), 2);
      expect(firstOpenAt('# Named\n\nWith \n'), '# Named\n\nWith '.length);
      expect(firstOpenAt('# Named\n\n> '), '# Named\n\n> '.length);
      expect(firstOpenAt('# Named\n\nwords'), '# Named\n\nwords'.length);
    });

    test('reads and writes a look, one key in the front matter', () {
      expect(lookOf('---\nlook: Reading\n---\n# A'), Look.reading);
      expect(lookOf('---\nlook: poster\n---\n# A'), isNull);
      expect(lookOf('# A'), isNull);
      expect(withLook('# A', Look.map), '---\nlook: map\n---\n# A');
      expect(withLook('---\ntitle: "A"\nlook: map\n---\n# A', Look.reading), '---\ntitle: "A"\nlook: reading\n---\n# A');
      expect(withLook('---\nlook: map\n---\n# A', null), '# A');
    });
  });
}
