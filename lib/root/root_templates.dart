part of 'ghost_root.dart';

/// A place's own template, and New from template… (Matt, 2026-10-30, of a list of plain-Markdown features: "add all
/// 12"; lib/notes/place_templates.dart says where each is written). What the root does with them: which template a
/// note made in a folder or a notebook starts from, the two ways to set one (a folder's menu and sheet, a notebook's
/// More sheet, which writes its own), and the picker that makes a note from any of them.
///
/// One of the files `_GhostRootState` is written in (lib/root/ghost_root.dart says which).
extension _RootTemplates on _GhostRootState {
  /// Every template a place can use: your own, a Templates notebook's pages, or the ones built in where there is none.
  List<NoteTemplate> get _allTemplates => _reads.ownTemplates ?? builtIns;

  /// Your own templates' pages, by the template's id, which is its page's note id.
  Map<String, String> get _templatePages => {
    for (final template in _reads.ownTemplates ?? const <NoteTemplate>[])
      if (_library.noteOf(template.id) case final page?) template.id: page.body,
  };

  /// Who makes a note, for `{{author}}`: the account's name, or nothing signed out.
  String get _author => _services?.session?.handle ?? '';

  /// The template a note made in folder [folderId], or in the chosen folder where it is left out, starts from; null
  /// for none.
  NoteTemplate? _folderTemplate(String? folderId) => folderTemplate(_workspaces.value.list, folderId ?? _workspaces.value.current?.id, _allTemplates, _templatePages);

  /// The template a page made in [notebook] starts from: its own `page-template:`; null for none.
  NoteTemplate? _notebookTemplate(String notebook) => templateNamed(_allTemplates, notebookTemplateName(notebook));

  /// New from template…, on the + and in the command search: one of the templates chosen, and a note made from it in
  /// [into], or where a new note goes.
  Future<void> _newFromTemplate([String? into]) async {
    final context = _shell.currentContext ?? this.context;
    final chosen = await chooseTemplate(context, title: 'New from template', templates: _allTemplates);
    final template = chosen?.template;
    if (!mounted || template == null) return;
    _new(into, template);
  }

  /// Set template… on a folder: one of the templates, or None, written into the pages' `folders:`. A built-in has no
  /// page to write it in until your Templates notebook is made, which this makes first, as Your templates does.
  Future<void> _setFolderTemplate(Workspace folder) async {
    final context = _shell.currentContext ?? this.context;
    final list = _workspaces.value.list;
    final own = ownFolderTemplate(list, folder.id, _allTemplates, _templatePages);
    final above = own == null ? _folderTemplate(folder.id) : null;
    final chosen = await chooseTemplate(
      context,
      title: 'Template for ${folder.name}',
      note: above != null ? 'New notes here start from ${above.name}, the template of the folder it is in, until it has its own.' : 'Every new note made in ${folder.name} starts from it.',
      templates: _allTemplates,
      none: true,
      chosen: own,
    );
    if (!mounted || chosen == null) return;
    var template = chosen.template;
    if (template != null && _reads.ownTemplates == null) {
      await _seedTemplates();
      template = templateNamed(_reads.ownTemplates ?? const <NoteTemplate>[], template.name);
      if (template == null) return;
    }
    final path = folderPathName(list, folder.id);
    for (final MapEntry(key: id, value: body) in _templatePages.entries) {
      final next = withTemplateFolder(body, path, id == template?.id);
      if (next != body) await _library.save(id, next).then<void>((_) {}, onError: (Object _) {});
    }
    await _library.refresh().catchError((Object _) {});
    if (mounted) _say(this.context, template == null ? 'New notes in ${folder.name} start blank.' : 'New notes in ${folder.name} start from ${template.name}.');
  }

  /// Your Templates notebook made where there is none, its pages first, and nothing opened.
  Future<void> _seedTemplates() async {
    final plan = seedPlan(outOfTrash(_library.value, _trash.value));
    if (plan.open != null) return;
    for (final template in plan.pages.reversed) {
      await _library.createNote(templatePageBody(template));
    }
    await _library.createNote(plan.index!);
    await _library.refresh();
  }

  /// A page made inside a notebook with a template of its own, from a link or Add a page's Just the title: the
  /// notebook's template filled for it, its title the page's, so its line in the index still finds it.
  String? _pageFromTemplate(String title, String notebook) {
    final template = _notebookTemplate(notebook);
    if (template == null) return null;
    final filled = fillNoteTemplate(template, DateTime.now(), _takenTitles, title: title, author: _author, nextId: nextTicketId(notebook, [for (final note in _library.value) note.body]));
    final named = filled.title.isEmpty || filled.title != title ? withHeading(filled.body, title) : filled.body;
    return isTicket(named) ? newTicketBody(title, id: ticketIdOf(named), statuses: statusesOf(notebook), words: named) : named;
  }

  /// "New bug in Kiln", said (lib/capture/template_ask.dart): the template the word names, or the place's own for
  /// "new note in Kiln", filled for a note in the notebook or folder of that name; the note's line in the notebook's
  /// index, or its filing in the folder, once it is made. Null where no template answers or no place has the name.
  ({String body, void Function(String noteId) file})? _voiceFromTemplate(String word, String place, String title) {
    final found = templateForPlace(word: word, place: place, notes: _shown, folders: _workspaces.value.list, templates: _allTemplates, pages: _templatePages);
    if (found == null) return null;
    final (:template, :notebook, :folder) = found;
    final now = DateTime.now();
    final nextId = notebook == null ? null : nextTicketId(notebook.body, [for (final note in _library.value) note.body]);
    final filled = fillNoteTemplate(template, now, _takenTitles, nextId: nextId, title: title, author: _author);
    if (notebook != null) {
      final book = notebook;
      // A page of a notebook is found by its line in the index, so it has a name: the one said, else the template's
      // and the minute.
      final named = title.trim().isNotEmpty ? title.trim() : (filled.title.isNotEmpty ? filled.title : '${template.name} ${formatStamp(now, 'YYYY-MM-DD HH.mm')}');
      final headed = withHeading(filled.body, named);
      final body = isTicket(headed) ? newTicketBody(named, id: ticketIdOf(headed) ?? nextId, statuses: statusesOf(book.body), words: headed) : headed;
      return (
        body: body,
        file: (id) {
          final now = _library.noteOf(book.id)?.body ?? book.body;
          final next = withChapter(now, named);
          if (next != now) unawaited(_library.save(book.id, next).then<void>((_) {}, onError: (Object _) {}));
        },
      );
    }
    return (body: filled.body, file: (id) => _workspaces.fileNote(id, folder!.id));
  }

  /// A sub-ticket of [parent], from its panel's Add sub-ticket: in the parent's notebook, numbered by its key and
  /// started from its template where it has one, its `parent:` the parent's key; opened in the parent's place, so Back
  /// returns to it.
  void _newSubTicket(String parentId, String title) {
    final named = title.trim();
    final parent = _library.noteOf(parentId);
    if (parent == null || named.isEmpty) return;
    final entry = _reads.entries.where((each) => each.note.id == parentId).firstOrNull;
    if (entry == null) return;
    final notebook = entry.notebook;
    final id = notebook == null ? null : nextTicketId(notebook.body, [for (final note in _library.value) note.body]);
    final template = notebook == null ? null : _notebookTemplate(notebook.body);
    final words = template == null ? null : fillNoteTemplate(template, DateTime.now(), _takenTitles, nextId: id, title: named, author: _author).body;
    final body = subTicketBody(named, entry, id: id, statuses: entry.statuses, words: words == null ? null : withHeading(words, named));
    _showMade(body, within: true);
    // Its line in the notebook's index, after the parent's, as a page's is.
    if (notebook != null) {
      final next = withChapter(notebook.body, named, entry.title);
      if (next != notebook.body) unawaited(_library.save(notebook.id, next).then<void>((_) {}, onError: (Object _) {}));
    }
  }
}

final RegExp _headingLine = RegExp(r'^#{1,6} +.*$', multiLine: true);

/// [body] with its first heading [title], or one put in front of its words where it has none: a page's heading is its
/// line in the notebook's index.
String withHeading(String body, String title) {
  final start = frontMatterOffset(body);
  final words = body.substring(start);
  final first = _headingLine.firstMatch(words);
  if (first != null && words.substring(0, first.start).trim().isEmpty) return body.substring(0, start) + words.replaceRange(first.start, first.end, '# $title');
  return '${body.substring(0, start)}# $title\n\n$words';
}
