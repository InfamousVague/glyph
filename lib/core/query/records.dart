/// What a query reads: every note as a record, and every to-do in them as a record of its own (../glyph
/// docs/QUERIES.md, docs/DESIGN.md §159). A port of `src/app/core/query/records.ts`. Matt asked for "notion and jira
/// like features … like tickets and such", and a query is the database view over them; this is the database.
///
/// A note is one record, and a ticket is a note whose front matter says `type: ticket` (properties.dart), read with
/// its ticket's fields. A to-do is a record too: any list item with a box (item_syntax.dart `taskBox`), outside the
/// front matter and fenced code, with its note, its line and its fields (task_fields.dart). Every reading here is
/// the shared grammar's, never a second parser of it: the box is item_syntax's, the words item_links' and boards' (a
/// mark, a counter and an anchor are not what a to-do says), the fields task_fields', the properties and the ticket
/// properties', the tags tags.dart's outside quiet words (blanks_syntax.dart `quietRanges`), a notebook's pages
/// book.dart's. So a query reads a note the way everything else in the app reads it.
///
/// A note's reading depends only on its words, so it is kept by the note's id until its words change
/// ([RecordCache]): the editor builds the library on every keystroke in the open note, and every other note is read
/// once. What depends on the other notes - the notebook a note is a page of, the workflow its statuses are in, the
/// notes its links name - is put together each time, which is a lookup per note. Pure: the notes are given, and so
/// is the cache.
///
/// What differs: `Library` is [QueryLibrary], since the app's own library is lib/core/library.dart. A [QueryNote] is
/// made from the app's `Note` with [QueryNote.of]. A record's kind is a [RecordKind]. A workflow is one list shared
/// by every record that moves through it, as on the web, and run.dart tells two workflows apart by which list it is.
library;

import '../blanks_syntax.dart' show quietRanges;
import '../boards/fence.dart' show fencedLines;
import '../boards/items.dart' show cardText, itemOnLine;
import '../book.dart' show chaptersOf, isBookBody;
import '../days.dart' show isoDay;
import '../front_matter.dart' show frontMatterEnd;
import '../item_links.dart' show itemWords;
import '../item_syntax.dart' show jsTrim, lineWords, taskBox;
import '../note.dart' show Note;
import '../note_text.dart' show noteTitle;
import '../properties.dart';
import '../tags.dart' show tagsIn;
import '../task_fields.dart' show TaskFields, fieldsOf, withoutFields;
import '../title_key.dart' show titleKey;

/// A note as a query reads it: the store's `Note` has these and more (`QueryNote`).
class QueryNote {
  const QueryNote({required this.id, required this.body, required this.createdAt, required this.updatedAt});

  /// The app's note, as a query reads it.
  QueryNote.of(Note note) : this(id: note.id, body: note.body, createdAt: note.createdAt, updatedAt: note.updatedAt);

  final String id;
  final String body;

  /// Milliseconds since the epoch.
  final int createdAt;
  final int updatedAt;

  QueryNote withBody(String next) => QueryNote(id: id, body: next, createdAt: createdAt, updatedAt: updatedAt);
}

/// A note, a ticket (a note with `type: ticket`), or a to-do in a note (`RecordKind`).
enum RecordKind { note, ticket, task }

class QueryRecord {
  const QueryRecord({
    required this.kind,
    required this.noteId,
    required this.line,
    required this.source,
    required this.title,
    required this.text,
    required this.done,
    required this.anchor,
    required this.notebook,
    required this.books,
    required this.workflow,
    required this.tags,
    required this.created,
    required this.updated,
    required this.props,
    required this.ticket,
    required this.fields,
    required this.linksTo,
    required this.linkKeys,
    required this.haystack,
  });

  final RecordKind kind;
  final String noteId;

  /// A to-do's line in its note, counting from 0; -1 for a note.
  final int line;

  /// A to-do's line as it is written, to find it again where the note has moved under it; '' for a note.
  final String source;

  /// The note's title (note_text.dart `noteTitle`): a to-do's is its note's.
  final String title;

  /// A to-do's words as a reader shows them, its fields, mark, counters and anchor taken out; a note's words.
  final String text;

  /// A to-do's box, ticked or not; null for a note.
  final bool? done;

  /// A to-do's anchor (docs/BOARDS.md), to land on it; null where it has none, and for a note.
  final String? anchor;

  /// The title of the notebook the note is a page of (book.dart), the first where it is in several; or null.
  final String? notebook;

  /// The title keys of every notebook the note is a page of, for `from: [[A notebook]]`.
  final List<String> books;

  /// The workflow the record's status moves through: its notebook's `statuses:`, or the default.
  final List<String> workflow;

  /// Its tags, lower case and without the `#`: a note's are every tag in its words, its front matter's `tags:` and a
  /// ticket's `labels:`; a to-do's are its own words' and its note's front matter's.
  final List<String> tags;

  /// When the note was made and last changed, as days (days.dart).
  final String created;
  final String updated;

  /// A note's front matter by key in lower case, its values with their quotes off; empty for a to-do.
  final Map<String, String> props;

  /// A ticket's properties as properties.dart reads them; null for anything else.
  final Ticket? ticket;

  /// A to-do's fields as task_fields.dart reads them; null for a note.
  final TaskFields? fields;

  /// The ids of the notes the note's `[[links]]` name, by title or a ticket's key: for `from: [[A note]]`.
  final Set<String> linksTo;

  /// The title keys its `[[links]]` name, found or not: for `from: [[A note not written yet]]`.
  final List<String> linkKeys;

  /// What `"words"` in `from:` look through, lower case: a note's title and words, a to-do's words.
  final String haystack;
}

/// A note in the library, as `from: [[…]]` finds one: by its title, or a ticket by its key (`LibraryNote`).
class LibraryNote {
  const LibraryNote({required this.id, required this.title, required this.key, required this.book, required this.statuses});
  final String id;
  final String title;
  final String key;

  /// A notebook (book.dart): its pages are what `[[it]]` names.
  final bool book;

  /// A notebook's workflow, its `statuses:`; null for a note that is not a notebook.
  final List<String>? statuses;
}

/// Every record, and the notes by title and by ticket key (`Library`).
class QueryLibrary {
  const QueryLibrary({required this.records, required this.byTitle, required this.byTicket});
  final List<QueryRecord> records;

  /// Each note by its title key, the first of a shared title winning, as a `[[link]]` finds it.
  final Map<String, LibraryNote> byTitle;

  /// Each ticket by its key, `GHO-12`.
  final Map<String, LibraryNote> byTicket;
}

/// A to-do as its note's words have it, before the library puts it together.
class _ReadTask {
  const _ReadTask({required this.line, required this.source, required this.text, required this.done, required this.anchor, required this.fields, required this.tags, required this.haystack});
  final int line;
  final String source;
  final String text;
  final bool done;
  final String? anchor;
  final TaskFields fields;
  final List<String> tags;
  final String haystack;
}

/// A note as its words have it (`ReadNote`): what the cache keeps.
class ReadNote {
  const ReadNote._({
    required this.title,
    required this.key,
    required this.props,
    required this.ticket,
    required this.ticketId,
    required this.book,
    required this.chapters,
    required this.statuses,
    required this.tags,
    required this.frontTags,
    required this.links,
    required this.words,
    required this.haystack,
    required List<_ReadTask> tasks,
  }) : _tasks = tasks;

  final String title;
  final String key;
  final Map<String, String> props;
  final bool ticket;
  final String? ticketId;
  final bool book;

  /// A notebook's pages, by title key.
  final List<String> chapters;
  final List<String>? statuses;
  final List<String> tags;
  final List<String> frontTags;
  final List<String> links;
  final String words;
  final String haystack;
  final List<_ReadTask> _tasks;
}

/// Notes read, by id, kept while their words stay the same (`RecordCache`).
class RecordCache {
  final Map<String, ({String body, ReadNote note})> read = {};
}

RecordCache recordCache() => RecordCache();

/// A note link's target as a page names it: the title, a `#heading` or `|words` after it not part of it.
final RegExp _link = RegExp(r'\[\[([^\]\n|#]{1,120})(?:[#|][^\]\n]*)?\]\]');

/// The tags in [text] outside its quiet words, lower case, without the `#`.
List<String> _tagsOf(String text) {
  final quiet = quietRanges(text);
  return [
    for (final tag in tagsIn(text))
      if (!quiet.any((q) => tag.from >= q.from && tag.from < q.to)) tag.name,
  ];
}

final RegExp _hashes = RegExp(r'^#+');

/// Tags written as a front matter list, `tags: [bug, ui]` or `tags: bug, ui`, without their `#`, lower case.
List<String> _listedTags(String? value) => [
      for (final tag in propertyList(value))
        if (jsTrim(tag.replaceFirst(_hashes, '')).toLowerCase() case final clean when clean.isNotEmpty) clean,
    ];

/// Each once, in order.
List<String> _unique(Iterable<String> items) => <String>{...items}.toList();

ReadNote _readNote(String body) {
  final lines = body.split('\n');
  final front = frontMatterEnd(lines);
  final props = <String, String>{};
  for (final property in propertiesOf(body)) {
    props.putIfAbsent(property.key.toLowerCase(), () => property.value);
  }
  final frontTags = _unique([..._listedTags(props['tags']), ..._listedTags(props['tag']), ..._listedTags(props['labels'])]);
  final fenced = fencedLines(lines);
  final tasks = <_ReadTask>[];
  final links = <String>[];
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    // A link in the front matter is one too (`blocked-by: "[[GHO-9]]"`), as Obsidian reads it; one in code is code.
    if (!fenced.contains(index + 1)) {
      for (final found in _link.allMatches(line)) {
        links.add(jsTrim(found.group(1)!));
      }
    }
    if (index < front || fenced.contains(index + 1)) continue;
    final box = taskBox(line);
    if (box == null) continue;
    // What it says leaves its fields out (item_links.dart `itemWords`); its fields are read from its line's own words.
    final words = itemWords(line) ?? '';
    final fields = fieldsOf(lineWords(line));
    final text = cardText(withoutFields(words));
    // A box with nothing after it is a to-do still to be written, not one to list.
    if (text.isEmpty && jsTrim(words).isEmpty) continue;
    tasks.add(_ReadTask(line: index, source: line, text: text, done: box.done, anchor: itemOnLine(line)?.id, fields: fields, tags: _tagsOf(words), haystack: text.toLowerCase()));
  }
  final words = jsTrim(lines.sublist(front).join('\n'));
  final title = noteTitle(body);
  final book = isBookBody(body);
  return ReadNote._(
    title: title,
    key: titleKey(title),
    props: props,
    ticket: isTicket(body),
    ticketId: ticketIdOf(body),
    book: book,
    chapters: book ? [for (final chapter in chaptersOf(body)) titleKey(chapter.title)] : const [],
    statuses: book ? statusesOf(body) : null,
    tags: _unique([..._tagsOf(body), ...frontTags]),
    frontTags: frontTags,
    links: links,
    words: words,
    haystack: '$title\n$words'.toLowerCase(),
    tasks: tasks,
  );
}

/// A note read, from the cache while its words are the same.
ReadNote _readOf(QueryNote note, RecordCache cache) {
  final kept = cache.read[note.id];
  if (kept != null && kept.body == note.body) return kept.note;
  final read = _readNote(note.body);
  cache.read[note.id] = (body: note.body, note: read);
  return read;
}

const Map<String, String> _noProps = {};

/// The library a query reads: every note given as a record, a ticket read as one, and every to-do in them. The notes
/// are the caller's to choose (the editor's leaves out the Trash, the archive, the Guide and the templates' pages);
/// the open note is given as its editor has it, so a query reads what is typed.
QueryLibrary libraryOf(List<QueryNote> notes, [RecordCache? cache]) {
  final kept = cache ?? recordCache();
  final read = [for (final note in notes) (note: note, read: _readOf(note, kept))];
  // The cache keeps only the notes there are: a note deleted is let go.
  final ids = {for (final note in notes) note.id};
  kept.read.removeWhere((id, _) => !ids.contains(id));

  final byTitle = <String, LibraryNote>{};
  final byTicket = <String, LibraryNote>{};
  for (final (:note, read: one) in read) {
    final entry = LibraryNote(id: note.id, title: one.title, key: one.key, book: one.book, statuses: one.statuses);
    if (one.key.isNotEmpty) byTitle.putIfAbsent(one.key, () => entry);
    final ticketId = one.ticketId;
    if (one.ticket && ticketId != null) byTicket.putIfAbsent(ticketId, () => entry);
  }
  // Each page's notebooks, in the order the notebooks come: the first is the one its title is shown with.
  final booksOf = <String, List<LibraryNote>>{};
  for (final (:note, read: one) in read) {
    if (!one.book) continue;
    final titled = byTitle[one.key];
    final notebook = titled != null && titled.id == note.id ? titled : LibraryNote(id: note.id, title: one.title, key: one.key, book: true, statuses: one.statuses);
    for (final chapter in one.chapters) {
      if (chapter.isEmpty || chapter == one.key) continue;
      final list = booksOf.putIfAbsent(chapter, () => []);
      if (!list.any((each) => each.id == notebook.id)) list.add(notebook);
    }
  }

  final records = <QueryRecord>[];
  for (final (:note, read: one) in read) {
    final books = booksOf[one.key] ?? const <LibraryNote>[];
    final notebook = books.isEmpty ? null : books.first;
    final workflow = notebook?.statuses ?? defaultStatuses;
    final linksTo = <String>{};
    for (final link in one.links) {
      final found = byTitle[titleKey(link)] ?? byTicket[issueKeyOf(link) ?? ''];
      if (found != null) linksTo.add(found.id);
    }
    final bookKeys = [for (final book in books) book.key];
    final created = isoDay(DateTime.fromMillisecondsSinceEpoch(note.createdAt));
    final updated = isoDay(DateTime.fromMillisecondsSinceEpoch(note.updatedAt));
    final linkKeys = [
      for (final link in one.links)
        if (titleKey(link) case final key when key.isNotEmpty) key,
    ];
    records.add(QueryRecord(
      kind: one.ticket ? RecordKind.ticket : RecordKind.note,
      noteId: note.id,
      line: -1,
      source: '',
      title: one.title,
      text: one.words,
      done: null,
      anchor: null,
      notebook: notebook?.title,
      books: bookKeys,
      workflow: workflow,
      tags: one.tags,
      created: created,
      updated: updated,
      props: one.props,
      ticket: one.ticket ? ticketOf(note.body, workflow) : null,
      fields: null,
      linksTo: linksTo,
      linkKeys: linkKeys,
      haystack: one.haystack,
    ));
    for (final task in one._tasks) {
      records.add(QueryRecord(
        kind: RecordKind.task,
        noteId: note.id,
        line: task.line,
        source: task.source,
        title: one.title,
        text: task.text,
        done: task.done,
        anchor: task.anchor,
        notebook: notebook?.title,
        books: bookKeys,
        workflow: workflow,
        tags: _unique([...task.tags, ...one.frontTags]),
        created: created,
        updated: updated,
        props: _noProps,
        ticket: null,
        fields: task.fields,
        linksTo: linksTo,
        linkKeys: linkKeys,
        haystack: task.haystack,
      ));
    }
  }
  return QueryLibrary(records: records, byTitle: byTitle, byTicket: byTicket);
}

/// The note `[[title]]` names in the library: by its title, as a link finds it, or a ticket by its key, as
/// `[[GHO-12]]` does (docs/DESIGN.md §157). Null where it names none.
LibraryNote? noteNamed(QueryLibrary library, String title) => library.byTitle[titleKey(title)] ?? library.byTicket[issueKeyOf(title) ?? ''];
