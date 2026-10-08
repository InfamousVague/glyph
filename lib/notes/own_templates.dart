/// Your own templates (docs/DESIGN.md §144, slice 2): the templates a new note's blank page offers, kept as notes,
/// the pages of a notebook called Templates. A port of `src/app/notes/ownTemplates.ts`.
///
/// **The notebook** is found by its key, `templates: true` beside `book: true`, never by its name, so it can be
/// renamed. The blank page's last card, Your templates, makes it the first time, with the built-ins as its pages
/// (the pages first, then the index, so a second press after a first one cut short makes only what is missing), and
/// opens it. From then on the blank page's cards are its pages, in its index's order: two made on two devices are
/// read oldest first, and a page named twice is offered once.
///
/// **A page is marked**, `templates: page`, by the seed and by Add a page in the notebook, and only a marked note is
/// ever a page. **A page** is named by its `title:`, since its first line is the template's own heading,
/// `# {{title}}`; its words after the front matter are the template. Only `look:` passes from a page to a note made
/// from it, and a ticket's page passes its ticket's keys too. A page whose words are still a built-in's says that
/// one's sentence and keeps its rules; any other says `One of your own.` Pure.
///
/// What differs: `propertiesOf` and the ticket's keys (`core/properties.ts`) are read here, since lib/core has only
/// the half the home page needed. `templatePages` was ported with the home page too (lib/core/book.dart); this one is
/// the web's, word for word, and the tests hold the two to the same answer.
library;

import '../core/book.dart';
import '../core/front_matter.dart';
import '../core/note.dart';
import '../core/note_text.dart';
import '../core/properties.dart';
import 'note_templates.dart';

/// The notebook's name when it is made. It is found by its key, so a new name is kept (`TEMPLATES_TITLE`).
const String templatesTitle = 'Templates';

/// A page's sentence when its words are its own (`OWN_SENTENCE`).
const String ownSentence = 'One of your own.';

/// The Your templates card's sentence (`YOUR_TEMPLATES_SENTENCE`).
const String yourTemplatesSentence = 'Change these or write your own. They are notes in a notebook.';

final RegExp _yes = RegExp(r'^(true|yes)$', caseSensitive: false);
final RegExp _page = RegExp(r'^page$', caseSensitive: false);

/// Whether a note is a Templates notebook: `templates: true` beside `book: true` (`isTemplatesBody`).
bool isTemplatesBody(String body) {
  final said = frontMatterValue(body, 'templates');
  return isBookBody(body) && said != null && _yes.hasMatch(said);
}

/// Whether a note is a template's page: marked `templates: page`, and not a notebook (`isTemplatePageBody`).
bool isTemplatePageBody(String body) => !isBookBody(body) && _page.hasMatch(frontMatterValue(body, 'templates') ?? '');

/// A new Templates notebook's body, its pages named in order (`templatesNotebookBody`).
String templatesNotebookBody(List<String> pages) => withFrontMatterValue(bookNoteBody(templatesTitle, pages), 'templates', 'true');

/// A built-in's page: its name as its `title:`, its mark, its own keys and its look beside them, and its words
/// (`templatePageBody`).
String templatePageBody(NoteTemplate template) {
  final lines = template.words.split('\n');
  final end = frontMatterEnd(lines);
  final own = end > 1 ? [for (final line in lines.sublist(1, end - 1)) '$line\n'] : const <String>[];
  final named = '---\ntitle: ${quotedTitle(template.name, template.name)}\ntemplates: page\n${own.join()}---\n${lines.sublist(end).join('\n')}';
  final look = template.look;
  return look != null ? withLook(named, look) : named;
}

/// A ticket's own keys, in the order a new ticket writes them (`core/properties.ts` `TICKET_PROPERTIES`).
const List<String> ticketPropertyKeys = ['type', 'id', 'status', 'assignee', 'priority', 'due', 'start', 'estimate', 'blocked-by', 'parent', 'labels'];

final RegExp _propertyLine = RegExp(r'^([\w.-]+)[ \t]*:(.*)$');

/// Every property in the note's front matter, in order: its key and the line it is on (`core/properties.ts`
/// `propertiesOf`, less the value, which nothing here reads).
List<({String key, int line})> _propertiesOf(List<String> lines) {
  final end = frontMatterEnd(lines);
  return [
    for (var line = 1; line < end - 1; line += 1)
      if (_propertyLine.firstMatch(lines[line]) case final said?) (key: said.group(1) ?? '', line: line),
  ];
}

/// A page's ticket keys as they are written, for the block a ticket's template opens with; none for a page that is
/// not a ticket (`ticketBlock`).
String _ticketBlock(String body) {
  if (!isTicket(body)) return '';
  final lines = body.split('\n');
  final kept = _propertiesOf(lines).where((property) => ticketPropertyKeys.contains(property.key.toLowerCase())).toList();
  return kept.isEmpty ? '' : '---\n${kept.map((property) => lines[property.line]).join('\n')}\n---\n';
}

/// A note's words after its front matter (`core/untouched.ts` `wordsOf`).
String wordsOf(String body) => body.substring(frontMatterOffset(body));

/// A page added to the notebook by name: marked, its heading left open for the name a note is given
/// (`newTemplatePageBody`).
String newTemplatePageBody(String name) => '---\ntitle: ${quotedTitle(name, 'A template')}\ntemplates: page\n---\n# {{title}}\n\n';

List<Note> _oldestFirst(Iterable<Note> notes) {
  final list = notes.toList();
  // Stable, as the page's sort is: two made in the same moment keep the order they were given in.
  for (var i = 1; i < list.length; i += 1) {
    final each = list[i];
    var at = i - 1;
    while (at >= 0 && list[at].createdAt > each.createdAt) {
      list[at + 1] = list[at];
      at -= 1;
    }
    list[at + 1] = each;
  }
  return list;
}

/// The Templates notebooks, oldest first.
List<Note> _notebooks(Iterable<Note> notes) => _oldestFirst(notes.where((note) => note.archivedAt == null && isTemplatesBody(note.body)));

/// The marked pages by their title's key, oldest first: never a note of the person's, whatever it is called.
Map<String, List<Note>> _pagesByTitle(Iterable<Note> notes) {
  final map = <String, List<Note>>{};
  for (final page in _oldestFirst(notes.where((note) => note.archivedAt == null && isTemplatePageBody(note.body)))) {
    final key = titleKey(noteTitle(page.body));
    if (key.isNotEmpty) map.putIfAbsent(key, () => []).add(page);
  }
  return map;
}

/// A page as a template: its name, its words after the front matter (a ticket's keys in front of them), and its look
/// alone; a built-in's rules where its words are one's (`templateOf`).
NoteTemplate templateOf(Note page) {
  final words = _ticketBlock(page.body) + wordsOf(page.body);
  final look = lookOf(page.body);
  NoteTemplate? builtIn;
  for (final one in builtIns) {
    if (one.words.trim() == words.trim() && one.look == look) {
      builtIn = one;
      break;
    }
  }
  final title = noteTitle(page.body);
  return NoteTemplate(id: page.id, kind: builtIn?.kind, name: title.isNotEmpty ? title : 'A template', sentence: builtIn?.sentence ?? ownSentence, words: words, look: look);
}

/// The templates the blank page offers from your notebook, in its order; null where there is no Templates notebook
/// (`templatesOf`).
List<NoteTemplate>? templatesOf(Iterable<Note> notes) {
  final books = _notebooks(notes);
  if (books.isEmpty) return null;
  final pages = _pagesByTitle(notes);
  final seen = <String>{};
  final out = <NoteTemplate>[];
  for (final book in books) {
    for (final chapter in chaptersOf(book.body)) {
      final key = titleKey(chapter.title);
      final page = pages[key]?.first;
      if (key.isEmpty || seen.contains(key) || page == null) continue;
      seen.add(key);
      out.add(templateOf(page));
    }
  }
  return out;
}

/// The marked pages a Templates notebook's index names, kept out of the lists a person's own notes are in: every one
/// of a name, so a second device's seed leaves no page of its own in Recent (`templatePages`).
Set<String> ownTemplatePages(Iterable<Note> notes) {
  final ids = <String>{};
  final books = _notebooks(notes);
  if (books.isEmpty) return ids;
  final pages = _pagesByTitle(notes);
  for (final book in books) {
    for (final chapter in chaptersOf(book.body)) {
      for (final page in pages[titleKey(chapter.title)] ?? const <Note>[]) {
        ids.add(page.id);
      }
    }
  }
  return ids;
}

/// What Your templates still has to make (`seedPlan`): the notebook to open where there is one ([open]), or the
/// built-ins' pages no marked page has made yet ([pages]) and the notebook ([index]).
class SeedPlan {
  const SeedPlan.open(Note this.open)
      : pages = const [],
        index = null;
  const SeedPlan.make({required this.pages, required String this.index}) : open = null;

  /// The notebook there is, to open.
  final Note? open;

  /// The pages still to make, where there is no notebook.
  final List<NoteTemplate> pages;

  /// The notebook's body, to make after its pages.
  final String? index;
}

/// What Your templates still has to make: the notebook to open where there is one, or the built-ins' pages no marked
/// page has made yet, and the notebook. A first press cut short leaves pages and no notebook: the next makes only the
/// notebook, naming the pages already there. A note of the person's by a page's name is not a page, so the seed makes
/// that page beside it (`seedPlan`).
SeedPlan seedPlan(Iterable<Note> notes) {
  final books = _notebooks(notes);
  if (books.isNotEmpty) return SeedPlan.open(books.first);
  final pages = _pagesByTitle(notes);
  return SeedPlan.make(
    pages: [
      for (final template in builtIns)
        if (!pages.containsKey(titleKey(template.name))) template,
    ],
    index: templatesNotebookBody([for (final template in builtIns) template.name]),
  );
}
