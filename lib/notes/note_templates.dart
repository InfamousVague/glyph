/// The templates a new note can start from (docs/DESIGN.md §144). A port of `src/app/notes/noteTemplates.ts`, with
/// `core/look.ts` ([Look], [lookOf], [withLook]).
///
/// Matt: "When making a new note also offer a few templates to chose from with cards showing how they look (map
/// header, typography focus, etc)", and then where: "cards on the blank page". So a new note's blank page draws a
/// card for each under its names (lib/notes/template_cards.dart), and a card's tap turns the blank note into that
/// template.
///
/// Eight, in code: A day, A meeting, A checklist, Notes on a book, A map at the top (`look: map`), A page to read
/// (`look: reading`), and two that make a ticket, a Bug report and a Feature, whose words open with the ticket's own
/// front matter. A name that is taken gets " (2)", as a journal's entry does. And the one rule for the caret: fill,
/// settle the name, and only then measure. Pure.
///
/// What differs:
/// - **The names of days and months are English, in the phone's own order once it has said which, and in the order
///   en-GB writes them until then** (lib/core/template.dart, which says why).
/// - The parts of the web's core this stood on were written here first, and have since gone to their own files,
///   which this one hands on so its callers read as they did: `core/template.ts` and `core/stamp.ts` are
///   lib/core/template.dart ([fillTemplate], [formatStamp], [firstOpenAt], [longDay], [clockTime]),
///   `core/frontMatter.ts` `withFrontMatterValue` is in lib/core/properties.dart, and `book/journal.ts`
///   `uniqueTitle` in lib/book/journal.dart.
library;

import 'package:flutter/foundation.dart';

import '../book/journal.dart' show uniqueTitle;
import '../core/front_matter.dart';
import '../core/properties.dart' show withFrontMatterValue;
import '../core/template.dart' show cursorMark, fillTemplate, firstOpenAt;

export '../book/journal.dart' show uniqueTitle;
export '../core/properties.dart' show withFrontMatterValue;
export '../core/template.dart' show clockTime, fillTemplate, firstOpenAt, formatStamp, longDay;

// ---- core/look.ts -------------------------------------------------------------------------------------------------

/// How a note looks (`Look`): one flat key in its front matter, `look:`, with two values.
enum Look { map, reading }

/// The note's look, or null for the usual one: `look:` read in any case, and anything but the two taken as none
/// (`lookOf`).
Look? lookOf(String body) {
  if (!body.startsWith('---') && !body.startsWith('+++')) return null;
  return switch (frontMatterValue(body, 'look')?.trim().toLowerCase()) { 'map' => Look.map, 'reading' => Look.reading, _ => null };
}

/// The body with its look set, or (null) taken off, and a block that held nothing else with it (`withLook`).
String withLook(String body, Look? look) => withFrontMatterValue(body, 'look', look?.name);

// ---- notes/noteTemplates.ts ---------------------------------------------------------------------------------------

/// Which built-in a template is (`TemplateId`).
enum TemplateId { day, meeting, checklist, book, map, reading, bug, feature }

/// A template a new note can start from (`NoteTemplate`).
@immutable
class NoteTemplate {
  const NoteTemplate({required this.id, this.kind, required this.name, required this.sentence, required this.words, this.look});

  /// A built-in's name for itself, or your own template's page's note id (lib/notes/own_templates.dart).
  final String id;

  /// Which built-in it is, or is still word for word, whose rules it keeps: A day's taken name, a map's place.
  final TemplateId? kind;

  /// The card's name.
  final String name;

  /// What it makes, in one fixed sentence, under the name.
  final String sentence;

  /// Its words, with the placeholders a journal's template takes.
  final String words;

  /// How a note made from it looks, written into its front matter; null for the usual look.
  final Look? look;

  @override
  bool operator ==(Object other) => other is NoteTemplate && other.id == id && other.kind == kind && other.name == name && other.sentence == sentence && other.words == words && other.look == look;

  @override
  int get hashCode => Object.hash(id, kind, name, sentence, words, look);
}

/// A ticket's front matter as its template writes it (`TICKET_KEYS`).
const String _ticketKeys = '---\ntype: ticket\nid: "{{next-id}}"\nstatus: To do\n---\n';

/// The eight built in, in the order the cards are drawn (`BUILT_INS`).
const List<NoteTemplate> builtIns = [
  NoteTemplate(id: 'day', kind: TemplateId.day, name: 'A day', sentence: 'Named for today, with a to-do to start.', words: '# {{date:YYYY-MM-DD}}\n\n{{date}}\n\n- [ ] '),
  NoteTemplate(
    id: 'meeting',
    kind: TemplateId.meeting,
    name: 'A meeting',
    sentence: 'Named for this minute, with who was there, notes and to-dos.',
    // "Meeting" outside the braces, so its M is not read as a month.
    words: '# Meeting {{date:YYYY-MM-DD HH.mm}}\n\nWith \n\n## Notes\n\n- \n\n## To do\n\n- [ ] ',
  ),
  NoteTemplate(id: 'checklist', kind: TemplateId.checklist, name: 'A checklist', sentence: 'A name to type, then a to-do.', words: '# {{title}}\n\n- [ ] '),
  NoteTemplate(id: 'book', kind: TemplateId.book, name: 'Notes on a book', sentence: 'Its title, who wrote it, notes and quotes.', words: '# {{title}}\n\nBy \n\n## Notes\n\n- \n\n## Quotes\n\n> '),
  NoteTemplate(id: 'map', kind: TemplateId.map, name: 'A map at the top', sentence: 'Where you are, drawn large above the words.', words: '# {{title}}\n\n{{date}}, {{time}}.\n', look: Look.map),
  NoteTemplate(id: 'reading', kind: TemplateId.reading, name: 'A page to read', sentence: 'A large title, a lead line and a column set for reading.', words: '# {{title}}\n', look: Look.reading),
  NoteTemplate(
    id: 'bug',
    kind: TemplateId.bug,
    name: 'Bug report',
    sentence: 'A ticket: how to make it happen, what should, and what did.',
    words: '$_ticketKeys# {{title}}\n\n## Steps to reproduce\n\n1. \n\n## Expected\n\n## Actual\n',
  ),
  NoteTemplate(
    id: 'feature',
    kind: TemplateId.feature,
    name: 'Feature',
    sentence: 'A ticket: the problem, the proposal, and when it is done.',
    words: '$_ticketKeys# {{title}}\n\n## Problem\n\n## Proposal\n\n## Done when\n\n- [ ] ',
  ),
];

/// A day's sentence on a day that already has a note by its name (`DAY_TAKEN_SENTENCE`).
const String dayTakenSentence = 'Today has a note by this name. This makes a second.';

/// Who makes a note, for a template's `{{author}}` wherever one is filled: the account's name, told by the root once
/// it has an account; nothing until then.
String Function()? templateAuthor;

/// A template filled for a note made now (`FilledTemplate`).
@immutable
class FilledTemplate {
  const FilledTemplate({required this.words, required this.body, required this.title, required this.caret, required this.renamed});

  /// The words after the front matter, the name settled: what the note's untouched record keeps.
  final String words;

  /// The whole note, its look in a front matter block of its own where it has one.
  final String body;

  /// Its name: its heading's words, or empty for an open heading.
  final String title;

  /// Where the caret goes in [body]: the first line left open.
  final int caret;

  /// Its name was taken, and it was given " (2)" or the next number free.
  final bool renamed;
}

/// The heading a note's words start with, and its words (`FIRST_HEADING`).
final RegExp _firstHeading = RegExp(r'^(#{1,6} +)(.*)$');

/// [template] filled for a note made at [at], among notes whose title keys are [taken]: filled, then its name
/// settled, then measured, so the caret and the record are both the final words' (`fillNoteTemplate`). [nextId] is
/// the next ticket key where the note is made, and [title] the name it is made with, where it has one already. A
/// template's own front matter is kept in front of the words, never counted among them.
///
/// `{{author}}` is [author], or [templateAuthor]'s where it is left out; a `{{cursor}}` the template has is where the caret goes, ahead of the first line left
/// open, and is taken out of the words.
FilledTemplate fillNoteTemplate(NoteTemplate template, DateTime at, Set<String> taken, {String? nextId, String title = '', String? author}) {
  final filled = fillTemplate(template.words, at: at, nextId: nextId, title: title, author: author ?? templateAuthor?.call() ?? '', cursor: cursorMark);
  final start = frontMatterOffset(filled);
  final front = filled.substring(0, start);
  var words = filled.substring(start);
  final newline = words.indexOf('\n');
  final first = newline < 0 ? words : words.substring(0, newline);
  final heading = _firstHeading.firstMatch(first);
  final named = heading?.group(2)?.replaceAll(cursorMark, '').trim() ?? '';
  var name = named;
  if (heading != null && named.isNotEmpty && !heading.group(2)!.contains(cursorMark)) {
    name = uniqueTitle(named, taken);
    if (name != named) words = '${heading.group(1)}$name${newline < 0 ? '' : words.substring(newline)}';
  }
  // The first `{{cursor}}` is the caret's, and every one is taken out.
  final marked = words.indexOf(cursorMark);
  words = words.replaceAll(cursorMark, '');
  final look = template.look;
  final body = look != null ? withLook(front + words, look) : front + words;
  return FilledTemplate(words: words, body: body, title: name, caret: frontMatterOffset(body) + (marked >= 0 ? marked : firstOpenAt(words)), renamed: name != named);
}
