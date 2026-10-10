/// A notebook as a list reads it: a note whose front matter says `book: true`, its index a list of `[[links]]` to its
/// pages. The reading half of `src/app/book/book.ts` ([isBookBody], [isJournalBody], [bookNoteBody], [chaptersOf],
/// [bookIndex], [placeOf]), with the readers of other modules the home page asks beside them:
/// `guidebook/guidebook.ts` [guidePages] and [isGuideBook], and `notes/ownTemplates.ts` [templatePages].
///
/// What differs: of the index's writers only [withChapter], for the sync merge of two copies of one notebook
/// (lib/sync/notes.dart `mergedIndex`) and a journal's entry (lib/book/journal.dart `withEntry`), and
/// [withChapterRenamed], for a page renamed (lib/book/follow_rename.dart), are here; their fellows come with the
/// notebook's own screen. The journal's readers that were written here first (`book/journal.ts` `entryPages` and
/// `stampOf`, `book/journalMonths.ts` `journalCards`) are in lib/book/journal.dart and journal_months.dart now, and
/// this file hands them on.
library;

import 'package:flutter/foundation.dart';
import 'front_matter.dart';
import 'note.dart';
import 'note_facts.dart';
import 'note_text.dart';

export '../book/journal.dart' show entryPages, stampOf;
export '../book/journal_months.dart' show JournalCard, journalCards;

/// One line of a notebook's index (`Chapter`).
@immutable
class Chapter {
  const Chapter({required this.title, required this.depth, required this.line});
  final String title;

  /// 0 for a chapter, 1 for a chapter indented under the one before.
  final int depth;

  /// The line of the body it is on.
  final int line;
}

final RegExp _item = RegExp('^(\\s*)($listMarker)\\s+(?:$taskBoxPattern\\s+)?(.*)\$');
final RegExp _link = RegExp(r'^\[\[([^\]\n|#]{1,120})(?:[#|][^\]\n]*)?\]\]');
final RegExp _figure = RegExp(r'\d');

/// Whether a front matter value says yes: `true` or `yes`, in any case (`/^(true|yes)$/i`).
bool saysYes(String? said) {
  if (said == null) return false;
  final length = said.length;
  if (length != 3 && length != 4) return false;
  final low = said.toLowerCase();
  // The pattern folds ASCII's case alone: a dotless or a long letter that lower-cases to one of these is not it.
  return (low == 'true' || low == 'yes') && said.codeUnitAt(0) < 0x80 && said.codeUnitAt(1) < 0x80 && said.codeUnitAt(2) < 0x80 && said.codeUnitAt(length - 1) < 0x80;
}

/// Whether a note is a book: its front matter says so.
bool isBookBody(String body) => saysYes(frontMatterValue(body, 'book'));

/// Whether a notebook is a journal: `journal: true` beside `book: true`.
bool isJournalBody(String body) {
  final span = frontMatterSpan(body);
  return saysYes(frontMatterValueIn(body, span, 'book')) && saysYes(frontMatterValueIn(body, span, 'journal'));
}

/// The body of a new book note, named, with any chapters given in order.
String bookNoteBody(String title, [List<String> chapters = const []]) {
  final named = quotedTitle(title, 'Notebook');
  final index = chapters.map((chapter) => '- [[${chapter.trim()}]]').join('\n');
  return '---\ntitle: $named\nbook: true\n---\n# ${named.substring(1, named.length - 1)}\n\n$index${index.isEmpty ? '' : '\n'}';
}

/// The chapters of a book, in the index's order: every list item that starts with a link. An index that numbers its
/// chapters is that numbered list; a bullet list beside it at the top level is about the book, not in it.
List<Chapter> chaptersOf(String body) {
  final found = <(Chapter, bool)>[];
  final lines = body.split('\n');
  for (var n = frontMatterEnd(lines); n < lines.length; n += 1) {
    final item = _item.firstMatch(lines[n]);
    if (item == null) continue;
    final link = _link.firstMatch(item.group(3) ?? '');
    if (link == null) continue;
    found.add((
      Chapter(title: link.group(1)!.trim(), depth: (item.group(1) ?? '').length >= 2 ? 1 : 0, line: n),
      _figure.hasMatch(item.group(2) ?? ''),
    ));
  }
  final numbers = found.any((c) => c.$2);
  return [
    for (final (chapter, ordered) in found)
      if (!numbers || ordered || chapter.depth == 1) chapter,
  ];
}

final RegExp _numbered = RegExp(r'^\s*(\d+)([.)])');

/// The body with a chapter added: after [after] where that chapter is in the index, else last (`withChapter`).
String withChapter(String body, String title, [String? after]) {
  final clean = title.trim();
  if (clean.isEmpty) return body;
  final lines = body.split('\n');
  final chapters = chaptersOf(body);
  if (chapters.any((c) => sameTitle(c.title, clean))) return body;
  // After the one named where it is in the index, else after the last: a name the index does not have is not a
  // reason to start a second list under the first, which a numbered index would not count.
  Chapter? place;
  if (after != null && after.isNotEmpty) {
    for (final c in chapters) {
      if (sameTitle(c.title, after)) {
        place = c;
        break;
      }
    }
  }
  place ??= chapters.isEmpty ? null : chapters.last;
  if (place != null) {
    final indent = place.depth == 1 ? '  ' : '';
    // In the index's own style: a numbered index goes on numbering, or the new chapter would be a bullet it skips.
    final marker = _numbered.firstMatch(place.line < lines.length ? lines[place.line] : '');
    final lead = marker != null ? '${int.parse(marker.group(1)!) + 1}${marker.group(2)}' : '-';
    lines.insert(place.line + 1, '$indent$lead [[$clean]]');
    return lines.join('\n');
  }
  // No index yet: the first chapter goes at the end, after a blank line, and the body ends with a newline.
  while (lines.isNotEmpty && lines.last.trim().isEmpty) {
    lines.removeLast();
  }
  lines.addAll(['', '- [[$clean]]', '']);
  return lines.join('\n').replaceFirst(RegExp(r'^\n'), '');
}

final RegExp _chapterLink = RegExp(r'\[\[([^\]\n|#]{1,120})([#|][^\]\n]*)?\]\]');

/// The body with a chapter's link renamed: every index line whose link names [from] names [to] instead, its
/// `#heading` or `|alias` and whatever follows kept. A page is listed by its title, so a page renamed was a page lost
/// from its notebook until this (Matt, 2026-09-29: "when changing the title of a page it gets removed from the
/// journal / notebook"). Lines that only mention it in passing are left, as [chaptersOf] leaves them
/// (`withChapterRenamed`).
String withChapterRenamed(String body, String from, String to) {
  final clean = to.trim();
  if (clean.isEmpty || sameTitle(from, clean)) return body;
  final lines = body.split('\n');
  for (final chapter in chaptersOf(body)) {
    if (!sameTitle(chapter.title, from)) continue;
    lines[chapter.line] = lines[chapter.line].replaceFirstMapped(_chapterLink, (m) => '[[$clean${m.group(2) ?? ''}]]');
  }
  return lines.join('\n');
}

/// Where a note stands in a book: the book, its chapters, and which one this is (`BookPlace`).
@immutable
class BookPlace {
  const BookPlace({required this.book, required this.title, required this.chapters, required this.at, required this.journal});
  final Note book;
  final String title;
  final List<Chapter> chapters;
  final int at;

  /// The book is a journal: its pages are entries.
  final bool journal;
}

/// Every page's book at once, by the page's title as it is matched: one pass over the books rather than one per row.
/// A page in two books is marked with the first.
///
/// Each note is read through its kept facts (note_facts.dart), and the index itself is kept by the notes it was
/// made from: asked again for the very same notes, in a new list or not, it is the one already made. Not to be
/// changed.
Map<String, BookPlace> bookIndex(Iterable<Note> notes) => notes is List<Note> ? _indexes.of(notes, () => _bookIndex(notes)) : _bookIndex(notes);

final NotesMemo<Map<String, BookPlace>> _indexes = NotesMemo<Map<String, BookPlace>>();

Map<String, BookPlace> _bookIndex(Iterable<Note> notes) {
  final places = <String, BookPlace>{};
  for (final note in notes) {
    final facts = NoteFacts.of(note);
    if (!facts.isBook) continue;
    final title = facts.title;
    final own = facts.key;
    final chapters = facts.chapters;
    final keys = facts.chapterKeys;
    final journal = facts.isJournal;
    for (var at = 0; at < chapters.length; at += 1) {
      final key = keys[at];
      if (key.isEmpty || key == own || places.containsKey(key)) continue;
      places[key] = BookPlace(book: note, title: title, chapters: chapters, at: at, journal: journal);
    }
  }
  return Map<String, BookPlace>.unmodifiable(places);
}

/// The book a note is a page of, from the index: null for a note in none, or for a book itself.
BookPlace? placeOf(Map<String, BookPlace> index, Note note) {
  final facts = NoteFacts.of(note);
  if (facts.isBook) return null;
  return index[facts.key];
}

// ---- pages that are not the person's notes (guidebook/guidebook.ts, notes/ownTemplates.ts) ------------------------

/// The Guide's own title (`GUIDE_TITLE`).
const String guideTitle = 'Ghost.md: The Guide';

/// The pages of Ghost.md: The Guide, by id.
Set<String> guidePages(List<Note> notes) {
  final index = bookIndex(notes);
  final pages = <String>{};
  for (final note in notes) {
    final place = index[NoteFacts.of(note).key];
    if (place != null && sameTitle(place.title, guideTitle)) pages.add(note.id);
  }
  return pages;
}

/// The Guide's own book note: the book by the Guide's title.
bool isGuideBook(Note note) {
  final facts = NoteFacts.of(note);
  return facts.isBook && sameTitle(facts.title, guideTitle);
}

/// Whether a note is a Templates notebook: `templates: true` beside `book: true`.
bool isTemplatesBook(String body) {
  final span = frontMatterSpan(body);
  return saysYes(frontMatterValueIn(body, span, 'book')) && saysYes(frontMatterValueIn(body, span, 'templates'));
}

final RegExp _page = RegExp(r'^page$', caseSensitive: false);

/// Whether a note is a template's page: marked `templates: page`, and not a notebook.
bool isTemplatePage(String body) {
  final span = frontMatterSpan(body);
  return !saysYes(frontMatterValueIn(body, span, 'book')) && _page.hasMatch(frontMatterValueIn(body, span, 'templates') ?? '');
}

/// The marked pages a Templates notebook's index names, kept out of the lists a person's own notes are in.
Set<String> templatePages(List<Note> notes) {
  final ids = <String>{};
  final books = notes.where((note) => note.archivedAt == null && NoteFacts.of(note).isTemplatesBook).toList();
  if (books.isEmpty) return ids;
  final pages = <String, List<Note>>{};
  for (final note in notes) {
    if (note.archivedAt != null) continue;
    final facts = NoteFacts.of(note);
    if (!facts.isTemplatePage) continue;
    final key = facts.key;
    if (key.isNotEmpty) pages.putIfAbsent(key, () => []).add(note);
  }
  for (final book in books) {
    for (final key in NoteFacts.of(book).chapterKeys) {
      for (final page in pages[key] ?? const <Note>[]) {
        ids.add(page.id);
      }
    }
  }
  return ids;
}
