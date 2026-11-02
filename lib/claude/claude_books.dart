/// The app's own Claude over notebooks, tickets and the Trash (Matt, 2026-10-27: "please increase the functionality of
/// the Claude in app to better prevent this"). On his Fold, asked to make a HelloTrade notebook of tickets from a
/// meeting, Claude wrote each ticket's front matter by hand through create_note, the create was cut off mid-way, and
/// three notes named "book: true", "type: ticket" and "ticket" were left that it could neither take back nor file into
/// the organization. These tools do it the app's way:
///
/// - **create_notebook**: a notebook ([bookNoteBody]) with its ticket key (`HT`), made in a folder, an organization's
///   included: a note made new for the team shares nothing that was the person's alone.
/// - **create_ticket**: a ticket in a notebook as the app makes one ([newTicketBody]): its next key (`HT-4`), the
///   notebook's first open status, the fields given (status, assignee, due, priority), its page put in the notebook's
///   index and filed where the notebook is.
/// - **trash_note**: to the Trash, from where the person brings it back. Only a note of the person's own: a team's note
///   taken away is taken from every member for good (an organization's deletes skip the Trash; 2026-10-26, 108 team
///   notes), and no run asks the person first, so a team's note, even one Claude made, is the person's to remove.
///
/// And create_note's `folder`, which files the note it makes there, an organization's too, by the same rule.
///
/// Docs (Matt, 2026-10-31: "There should be a specific type of notebook for docs that we made, add it to the Claude
/// and other AI connector so they can make docs on ghost"): a notebook that says `type: docs`, its `## ` parts and its
/// numbered pages (lib/core/docs_book.dart), made and grown by two tools of their own, for every provider alike:
///
/// - **create_docs**: the index and every page, in one call, filed together where asked (an organization's folder
///   makes them the team's, as a notebook is). Every title is checked before anything is made, and the index is made
///   first, so a page cut off is a page "not written yet" in it rather than a note in no book.
/// - **add_doc_page**: one page, filed where its docs are, and its line put under its part, numbered in.
library;

import 'dart:convert';

import '../core/docs_book.dart';
import '../core/note_text.dart' show sameTitle;
import '../plugins/projects/suite.dart' show projectPluginOn, projectSuite, ticketsTool;
import 'claude_folders.dart';

/// The notes Claude made since the app opened: what trash_note may take from an organization, and what a cut-off
/// create leaves behind to be taken back.
final Set<String> claudeMade = <String>{};

/// What a book tool refuses, said back to Claude.
class ClaudeBookProblem implements Exception {
  const ClaudeBookProblem(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The library and the workspaces as the book tools reach them; the app's is in lib/root/root_claude.dart.
abstract interface class ClaudeShelf {
  /// A new notebook named [title], with ticket key [key] where given and [about] under its heading, filed in
  /// [workspaceId] where given. Answers its id.
  Future<String> notebook({required String title, String? key, String? about, String? workspaceId});

  /// A notebook by its id or exact title: its id, title and ticket key, or null where there is no such notebook.
  ({String id, String title, String? key})? findNotebook(String asked);

  /// A ticket in the notebook [notebookId]: made as the app makes one, with [fields] set, [details] under its
  /// heading, filed where the notebook is and put in its index. Answers its id and its key (null in a notebook with no
  /// key).
  Future<({String id, String? key})> ticket({required String notebookId, required String title, required List<(String, String)> fields, String? details});

  /// Files the note [id], just made, in [workspaceId].
  void fileNew(String id, String workspaceId);

  /// Whether [id] is the team's: filed in an organization's workspace or a folder under it.
  bool isTeams(String id);

  /// The note's title, or null where there is no such note.
  String? titleOf(String id);

  /// Moves the note [id] to the Trash.
  Future<void> trash(String id);

  /// A new note of [body], the person's own until it is filed ([fileNew]). Answers its id.
  Future<String> make(String body);

  /// The note [id]'s words changed by [change], through its screen where it is open.
  Future<void> change(String id, String Function(String body) change);

  /// Docs ([isDocsBody]) by their id or exact title: their id and title, or null where there are none.
  ({String id, String title})? findDocs(String asked);

  /// Whether a note out of the Trash and the archive is called [title], as a link matches one.
  bool hasNote(String title);

  /// The folder the note [id] is filed in, or null for none.
  String? workspaceOf(String id);
}

/// The book tools' names.
abstract final class ClaudeBookTool {
  static const notebook = 'create_notebook';
  static const ticket = 'create_ticket';
  static const trash = 'trash_note';
  static const docs = 'create_docs';
  static const docPage = 'add_doc_page';
  static const Set<String> all = {notebook, ticket, trash, docs, docPage};
}

Map<String, Object?> _string(String description) => {'type': 'string', 'description': description};

Map<String, Object?> _tool(String name, String description, Map<String, Object?> properties, List<String> required) => {
      'name': name,
      'description': description,
      'input_schema': {'type': 'object', 'properties': properties, 'required': required},
    };

/// An object of [properties] and nothing else: the docs tools' input and each part and page in it.
Map<String, Object?> _shut(Map<String, Object?> properties, List<String> required) => {
      'type': 'object',
      'properties': properties,
      'required': required,
      'additionalProperties': false,
    };

/// A page as create_docs and add_doc_page take one.
final Map<String, Object?> _pageFields = {
  'title': _string('The page’s title, short and unique in the account: its `# ` heading and what a [[link]] to it says. No [ ] | or #.'),
  'body': _string('The page in markdown, under its title: a line saying what it is for, then `## ` sections. Link other pages as [[Their title]].'),
  'icon': _string('An emoji for the page, like 📦. Optional.'),
};

/// The book tools, as the API is told them.
final List<Map<String, Object?>> claudeBookTools = [
  _tool(
    ClaudeBookTool.notebook,
    'A new notebook: a note whose pages are listed in it, in order. With `ticket_key` (2 to 6 capital letters, like HT) every ticket made in it is numbered HT-1, HT-2 and on. Made in `folder` where given, an organization’s included (a new notebook for the team is the team’s). Use this, never create_note, to make a notebook.',
    {
      'title': _string('Its name.'),
      'ticket_key': _string('The tickets’ prefix, like HT. Leave out for a notebook without tickets.'),
      'folder': _string('Where it goes: a folder’s id or its path from list_folders, like “HelloTrade › Tickets”. Left out, it is the person’s own, in no folder.'),
      'about': _string('A line or two under its heading saying what it is for.'),
    },
    const ['title'],
  ),
  _tool(
    ClaudeBookTool.ticket,
    'A ticket in a notebook, made as the app makes one: the notebook’s next key (HT-4), its first open status unless `status` says another, the fields given, its page added to the notebook and filed where the notebook is. Use this, never create_note, for a ticket. Make one and check it with read_note before making many.',
    {
      'notebook': _string('The notebook’s id, or its exact title.'),
      'title': _string('What the ticket is, in a few words. It is the page’s title.'),
      'status': _string('Its status, one of the notebook’s (To do, In progress, In review, Done, unless it says others).'),
      'assignee': _string('Who does it: a name, or a handle like @matt.'),
      'due': _string('When it is due, as YYYY-MM-DD.'),
      'priority': _string('Highest, High, Medium, Low or Lowest.'),
      'details': _string('Markdown under its heading: what is to be done, where it came from (a [[Meeting note]] link), and anything said about it.'),
      'turn_on_tickets': {
        'type': 'boolean',
        'description': 'Only once the person has said yes: turns the Tickets plugin on where the notebook is (for them, or for its organization) before making the ticket. Tickets is off until it is turned on, and create_ticket says so.',
      },
    },
    const ['notebook', 'title'],
  ),
  _tool(
    ClaudeBookTool.trash,
    'Moves a note of the person’s own to the Trash, from where they can bring it back. An organization’s note is refused, even one you made: taking it away takes it from every member. For one of those, tell the person which note and why, and they remove it. Say what you moved and why.',
    {'id': _string('The note’s id.')},
    const ['id'],
  ),
  {
    'name': ClaudeBookTool.docs,
    'description':
        'New docs (a guide, a handbook, a manual, a wiki): a notebook marked as docs, its index made of parts, each a `## ` heading with its pages numbered under it, and every page made as a note of its own. Made in `folder` where given, an organization’s included (docs made for the team are the team’s). Use this, never create_note, for docs. One topic a page; grow them later with add_doc_page.',
    'input_schema': _shut(
      {
        'title': _string('The docs’ name, like “Onboarding handbook”.'),
        'about': _string('A line or two under its heading: what the docs cover and who they are for.'),
        'parts': {
          'type': 'array',
          'description': 'The parts in order, each with its pages in order.',
          'minItems': 1,
          'items': _shut({
            'title': _string('The part’s heading, like “Getting started”.'),
            'pages': {'type': 'array', 'minItems': 1, 'items': _shut(_pageFields, const ['title', 'body'])},
          }, const ['title', 'pages']),
        },
        'folder': _string('Where they go: a folder’s id or its path from list_folders, like “HelloTrade › Docs”. Left out, they are the person’s own, in no folder.'),
      },
      const ['title', 'parts'],
    ),
  },
  {
    'name': ClaudeBookTool.docPage,
    'description':
        'A page added to docs made with create_docs: made as a note of its own, filed where the docs are, and its line put in the docs’ index under `part`, numbered in (a part the docs have not got is added at the end). Use this, never create_note and an edit of the index, to add to docs.',
    'input_schema': _shut(
      {
        'docs': _string('The docs’ id, or their exact title.'),
        'part': _string('The part it goes in, by its heading, like “Getting started”.'),
        ..._pageFields,
        'position': {'type': 'integer', 'minimum': 1, 'description': 'Its place in the part, from 1. Left out, it goes last.'},
      },
      const ['docs', 'part', 'title', 'body'],
    ),
  },
];

/// What the system prompt says of them, docs included ([claudeDocsSystem]).
const String claudeBookSystem =
    'Notebooks and tickets: make a notebook with create_notebook and its tickets with create_ticket, never by writing their front matter yourself through create_note. Make one ticket and read it back before making the rest. A note you made that came out wrong can go to the Trash with trash_note. When a note does start with front matter, the `---` block comes first and the `# Title` heading after it.\n\n$claudeDocsSystem';

/// Writing docs, as the system prompt says it: the paragraph the connector's instructions carry too
/// (mcp/docs.ts `DOCS_INSTRUCTIONS`), in this app's tools' names.
const String claudeDocsSystem =
    'Writing docs on Ghost.md: when asked for docs, a guide, a handbook, a manual or a wiki, make them with create_docs: a notebook marked as docs whose index is parts (`## ` headings) of numbered pages. One topic a page; parts group the pages a reader takes together; page titles short and unique, since they are what [[links]] name. Open each page with a line saying what it is for, use `## ` headings inside it for its outline, and link the other pages as [[Their title]]. Grow docs with add_doc_page, never by writing `book:` or `type: docs` front matter through create_note. Docs for a team go in the organization’s folder.';

/// A page create_docs is given, read and checked.
typedef _DocsPage = ({String title, String body, String? icon});

/// The parts create_docs is given, read and checked: each part's heading and its pages, every title one a link can
/// name, none twice, and none a note already has.
List<({String title, List<_DocsPage> pages})> _docsPlan(Object? asked, ClaudeShelf shelf) {
  if (asked is! List || asked.isEmpty) throw const ClaudeBookProblem('Give `parts`: at least one, each with a `title` and its `pages`.');
  final seen = <String>[];
  final plan = <({String title, List<_DocsPage> pages})>[];
  for (final part in asked) {
    if (part is! Map) throw const ClaudeBookProblem('Each part is an object with a `title` and its `pages`.');
    final heading = (part['title'] as String? ?? '').trim();
    if (heading.isEmpty || heading.contains('\n')) throw const ClaudeBookProblem('Each part needs a `title` on one line: its heading.');
    final pages = part['pages'];
    if (pages is! List || pages.isEmpty) throw ClaudeBookProblem('The part “$heading” needs `pages`: at least one.');
    final read = <_DocsPage>[];
    for (final page in pages) {
      if (page is! Map) throw ClaudeBookProblem('Each page of “$heading” is an object with a `title` and a `body`.');
      final title = (page['title'] as String? ?? '').trim();
      final problem = docsTitleProblem(title);
      if (problem != null) throw ClaudeBookProblem(problem);
      if (seen.any((other) => sameTitle(other, title))) throw ClaudeBookProblem('Two pages are called “$title”: a link names one note, so give each page its own title.');
      if (shelf.hasNote(title)) throw ClaudeBookProblem('There is already a note called “$title”. Give the page another title, or link that note from a page.');
      seen.add(title);
      final icon = (page['icon'] as String?)?.trim();
      read.add((title: title, body: page['body'] as String? ?? '', icon: icon == null || icon.isEmpty ? null : icon));
    }
    plan.add((title: heading, pages: read));
  }
  if (seen.length > 60) throw const ClaudeBookProblem('That is more than 60 pages in one call: make the docs with the first parts, then add the rest with add_doc_page.');
  return plan;
}

/// Answers the book tools over a [ClaudeShelf], the folders resolving where things go.
class ClaudeBooks {
  ClaudeBooks(this.shelf, this.folders);

  final ClaudeShelf shelf;
  final ClaudeFolders? folders;

  String? _workspace(Object? asked) {
    final key = (asked as String?)?.trim() ?? '';
    if (key.isEmpty) return null;
    final folders = this.folders;
    if (folders == null) throw const ClaudeBookProblem('Folders cannot be reached here: leave out `folder`.');
    try {
      return folders.resolve(key).id;
    } on ClaudeFolderProblem catch (problem) {
      throw ClaudeBookProblem(problem.message);
    }
  }

  /// Files a note create_note just made in the folder asked for, by the same rule. Answers where.
  String? fileNew(String id, Object? folder) {
    final workspace = _workspace(folder);
    if (workspace == null) return null;
    shelf.fileNew(id, workspace);
    return workspace;
  }

  /// Answers [tool] with [input]: what it says back to Claude, and the step the sheet shows.
  Future<({String said, String step, String? noteId})> answer(String tool, Map<String, Object?> input) async {
    switch (tool) {
      case ClaudeBookTool.notebook:
        final title = (input['title'] as String? ?? '').trim();
        if (title.isEmpty) throw const ClaudeBookProblem('Give the notebook a `title`.');
        if (shelf.findNotebook(title) != null) throw ClaudeBookProblem('There is already a notebook called “$title”. Use it, or name this one differently.');
        final key = (input['ticket_key'] as String?)?.trim().toUpperCase();
        if (key != null && key.isNotEmpty && !RegExp(r'^[A-Z][A-Z0-9]{1,5}$').hasMatch(key)) throw const ClaudeBookProblem('`ticket_key` is 2 to 6 capital letters or digits, starting with a letter, like HT.');
        final workspace = _workspace(input['folder']);
        final id = await shelf.notebook(title: title, key: key == null || key.isEmpty ? null : key, about: (input['about'] as String?)?.trim(), workspaceId: workspace);
        claudeMade.add(id);
        // A notebook of tickets where Tickets is off is a plain notebook until it is on (docs/PM_PLUGINS.md).
        final ticketsOff = key != null && key.isNotEmpty && !projectPluginOn(ticketsTool, noteId: id);
        return (
          said: jsonEncode({
            'id': id,
            'title': title,
            if (key != null && key.isNotEmpty) 'ticket_key': key,
            if (ticketsOff) 'tickets_off': 'The Tickets plugin is off here: its tickets show as plain notes, and create_ticket asks before it turns Tickets on. Tell the person.',
            'done': true,
          }),
          step: 'Made the notebook $title',
          noteId: id,
        );
      case ClaudeBookTool.ticket:
        final asked = (input['notebook'] as String? ?? '').trim();
        final title = (input['title'] as String? ?? '').trim();
        if (asked.isEmpty || title.isEmpty) throw const ClaudeBookProblem('Give the `notebook` and the ticket’s `title`.');
        final book = shelf.findNotebook(asked);
        if (book == null) throw ClaudeBookProblem('No notebook “$asked”. Make it with create_notebook, or list notes to find its id.');
        // Tickets is a plugin, off until turned on for the person or for the team (docs/PM_PLUGINS.md): where it is
        // off, nothing is made until the person says to turn it on.
        if (!projectPluginOn(ticketsTool, noteId: book.id)) {
          if (input['turn_on_tickets'] != true) {
            final where = projectSuite.whereWords(noteId: book.id);
            throw ClaudeBookProblem('The Tickets plugin is off${where.isEmpty ? ' for the person' : where}, so a ticket would show as a plain note. Nothing was made. Tell the person, and offer to turn Tickets on${where.isEmpty ? '' : where}; if they say yes, call create_ticket again with `turn_on_tickets: true`.');
          }
          await projectSuite.turnOn(const [ticketsTool], noteId: book.id);
        }
        final fields = <(String, String)>[
          for (final field in const ['status', 'assignee', 'due', 'priority'])
            if ((input[field] as String?)?.trim().isNotEmpty ?? false) (field, (input[field]! as String).trim()),
        ];
        final made = await shelf.ticket(notebookId: book.id, title: title, fields: fields, details: (input['details'] as String?)?.trim());
        claudeMade.add(made.id);
        final named = made.key == null ? title : '${made.key} $title';
        return (said: jsonEncode({'id': made.id, 'key': made.key, 'title': title, 'notebook': book.title, 'done': true}), step: 'Made the ticket $named', noteId: made.id);
      case ClaudeBookTool.trash:
        final id = (input['id'] as String? ?? '').trim();
        final title = id.isEmpty ? null : shelf.titleOf(id);
        if (title == null) throw const ClaudeBookProblem('No such note. List or search to find its id.');
        if (shelf.isTeams(id)) {
          throw ClaudeBookProblem('“$title” is the team’s: taking it away would take it from every member. Tell the person which note and why, and ask them to remove it themselves.');
        }
        await shelf.trash(id);
        claudeMade.remove(id);
        return (said: jsonEncode({'id': id, 'title': title, 'trashed': true}), step: 'Moved ${title.isEmpty ? 'a note' : title} to the Trash', noteId: null);
      case ClaudeBookTool.docs:
        final title = (input['title'] as String? ?? '').trim();
        final named = title.isEmpty ? 'Give the docs a `title`.' : docsTitleProblem(title);
        if (named != null) throw ClaudeBookProblem(named);
        if (shelf.hasNote(title)) throw ClaudeBookProblem('There is already a note called “$title”. Add to it with add_doc_page if it is docs, or name these differently.');
        final plan = _docsPlan(input['parts'], shelf);
        final workspace = _workspace(input['folder']);
        // The index first: a page cut off after it is a page not written yet in the docs, not a note in no book.
        final index = docsBookBody(title, about: (input['about'] as String?)?.trim(), parts: [for (final part in plan) DocsPart(part.title, [for (final page in part.pages) page.title])]);
        final id = await shelf.make(index);
        if (workspace != null) shelf.fileNew(id, workspace);
        claudeMade.add(id);
        final made = <Map<String, Object?>>[];
        for (final part in plan) {
          final pages = <Map<String, String>>[];
          for (final page in part.pages) {
            final pageId = await shelf.make(docsPageBody(page.title, page.body, icon: page.icon));
            if (workspace != null) shelf.fileNew(pageId, workspace);
            claudeMade.add(pageId);
            pages.add({'id': pageId, 'title': page.title});
          }
          made.add({'title': part.title, 'pages': pages});
        }
        final count = plan.fold<int>(0, (sum, part) => sum + part.pages.length);
        return (said: jsonEncode({'id': id, 'title': title, 'parts': made, 'done': true}), step: 'Made the docs $title, $count page${count == 1 ? '' : 's'}', noteId: id);
      case ClaudeBookTool.docPage:
        final asked = (input['docs'] as String? ?? '').trim();
        final part = (input['part'] as String? ?? '').trim();
        final title = (input['title'] as String? ?? '').trim();
        if (asked.isEmpty || part.isEmpty) throw const ClaudeBookProblem('Give the `docs` and the `part` the page goes in.');
        if (part.contains('\n')) throw const ClaudeBookProblem('`part` is a heading, on one line.');
        final problem = docsTitleProblem(title);
        if (problem != null) throw ClaudeBookProblem(problem);
        final docs = shelf.findDocs(asked);
        if (docs == null) throw ClaudeBookProblem('No docs “$asked”. Make them with create_docs, or list notes to find their id.');
        if (shelf.hasNote(title)) throw ClaudeBookProblem('There is already a note called “$title”. Give the page another title.');
        final position = (input['position'] as num?)?.toInt();
        if (position != null && position < 1) throw const ClaudeBookProblem('`position` counts from 1.');
        final pageId = await shelf.make(docsPageBody(title, input['body'] as String? ?? '', icon: (input['icon'] as String?)?.trim()));
        final space = shelf.workspaceOf(docs.id);
        if (space != null) shelf.fileNew(pageId, space);
        claudeMade.add(pageId);
        await shelf.change(docs.id, (index) => withDocsPage(index, part, title, position: position));
        return (said: jsonEncode({'id': pageId, 'title': title, 'docs': docs.title, 'part': part, 'done': true}), step: 'Added $title to ${docs.title}', noteId: pageId);
    }
    throw ClaudeBookProblem('There is no tool called $tool.');
  }
}
