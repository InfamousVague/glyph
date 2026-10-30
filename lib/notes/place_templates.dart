/// The template a notebook or a folder starts its new notes from (Matt, 2026-10-30, of a list of plain-Markdown
/// features: "add all 12"). New ticket was already one such: a ticket's template filled for the notebook it is made
/// in. This makes any template a place's own, for every new note made there.
///
/// **The templates are your templates**, the pages of the Templates notebook (own_templates.dart): plain notes, one
/// a page, their words the note to make with Obsidian's double-brace placeholders. Not a `Templates` folder in each
/// workspace, nor a `_template` note in each notebook: there is one place a person keeps their patterns, the blank
/// page's cards and New ticket already read it, it syncs as every note does, and Obsidian's own Templates plugin
/// keeps one folder of them in the same way. A `_template` page would be a page of the notebook in its index and in
/// every list, and the same meeting template copied into five notebooks would be five to keep in step.
///
/// **Which one a place uses** is written where the place can hold a word:
///
/// - a notebook is a note, so its own front matter names it, as a link any Markdown app follows to the page:
///
///       page-template: "[[Bug report]]"
///
///   (`template:` is a journal's own template, its words whole; a notebook kept as a journal keeps that.)
/// - a folder is no note, and keeps nothing but its name, its colour and where it sits, so the template's page names
///   the folders it is for, by their names from the top, `/` between:
///
///       folders: [Kiln, Work/Clients]
///
///   A folder with none takes the one of the folder it is in, so a template set on Work is every folder inside it's
///   too until one of them has its own.
///
/// A notebook's is asked first, then its folder's. A place's template that is gone (the page deleted, or renamed)
/// makes the note as it was made before. Pure.
library;

import '../core/book.dart' show isBookBody;
import '../core/front_matter.dart';
import '../core/note.dart';
import '../core/note_text.dart' show noteTitle;
import '../core/properties.dart';
import '../core/title_key.dart' show titleKey;
import '../core/workspaces.dart';
import 'note_templates.dart';
import '../capture/template_ask.dart' show plainNotes;
import 'own_templates.dart' show isTemplatesBody;

/// The key a notebook names its pages' template by.
const String pageTemplateKey = 'page-template';

/// The key a template's page names its folders by.
const String foldersKey = 'folders';

/// The template a notebook's front matter names, by its name or as a link; null for none.
String? notebookTemplateName(String notebook) {
  final said = frontMatterValue(notebook, pageTemplateKey);
  if (said == null || said.trim().isEmpty) return null;
  final links = linkTargets(said);
  final name = links.isNotEmpty ? links.first : said.trim();
  return name.isEmpty ? null : name;
}

/// The notebook with [template] as its pages' template, as a link to its page; null takes it off.
String withNotebookTemplate(String notebook, String? template) => withProperty(notebook, pageTemplateKey, template == null || template.trim().isEmpty ? null : '[[${template.trim()}]]');

/// A folder as a template's page names it: its name and its parents' from the top, `/` between ("Work/Clients").
String folderPathName(List<Workspace> all, String id) => workspacePath(all, id).map((w) => w.name.trim()).join('/');

/// The folders a template's page names.
List<String> templateFolders(String page) => propertyList(frontMatterValue(page, foldersKey)).map((name) => name.trim()).where((name) => name.isNotEmpty).toList();

/// Whether [said], as a page's `folders:` writes it, is the folder [path] ("Work/Clients"): the whole path in any
/// case, or a name alone that is the folder's own.
bool _namesFolder(String said, String path) {
  final want = _pathKey(said);
  if (want.isEmpty) return false;
  if (want == _pathKey(path)) return true;
  return !said.contains('/') && want == _pathKey(path.split('/').last);
}

String _pathKey(String path) => path.split('/').map((part) => titleKey(part.trim())).where((part) => part.isNotEmpty).join('/');

/// The page with [path] among its folders, or taken out of them; any other folder's name as it was.
String withTemplateFolder(String page, String path, bool on) {
  final kept = [for (final said in templateFolders(page)) if (!_namesFolder(said, path)) said];
  final next = on ? [...kept, path] : kept;
  return withProperty(page, foldersKey, next.isEmpty ? null : next);
}

/// A template named in a place: the one of [templates] whose name is [name], in any case; null for none.
NoteTemplate? templateNamed(Iterable<NoteTemplate> templates, String? name) {
  if (name == null) return null;
  final key = titleKey(name);
  if (key.isEmpty) return null;
  for (final template in templates) {
    if (titleKey(template.name) == key) return template;
  }
  return null;
}

/// A template as a person says it: "bug" is Bug report, "meeting" A meeting, "feature" Feature. Its whole name, else
/// the one whose name's words hold the word said, a built-in's article left out; null for none or for two that would.
NoteTemplate? templateSaid(Iterable<NoteTemplate> templates, String said) {
  final exact = templateNamed(templates, said);
  if (exact != null) return exact;
  final words = titleKey(said).split(' ').where((word) => word.isNotEmpty && !_articles.contains(word)).toList();
  if (words.isEmpty) return null;
  final found = <NoteTemplate>[];
  for (final template in templates) {
    final name = titleKey(template.name).split(' ').where((word) => word.isNotEmpty && !_articles.contains(word)).toList();
    final holds = words.every((word) => name.any((each) => each == word || each == '${word}s' || (word.length > 2 && each.startsWith(word))));
    if (holds) found.add(template);
  }
  return found.length == 1 ? found.single : null;
}

const Set<String> _articles = {'a', 'an', 'the', 'new', 'report'};

/// What a template's page is for, by its id: the folders its `folders:` names. [pages] is every template's page, by
/// the id its template has (own_templates.dart `templateOf`).
typedef TemplatePages = Map<String, String>;

/// The template a new note made in folder [folderId] starts from: the folder's own, else the one of the folder it is
/// in, and so on to the top; null for none. [pages] is each own template's page body by its id.
NoteTemplate? folderTemplate(List<Workspace> all, String? folderId, List<NoteTemplate> templates, TemplatePages pages) {
  if (folderId == null) return null;
  final path = workspacePath(all, folderId);
  for (var depth = path.length; depth > 0; depth -= 1) {
    final name = path.sublist(0, depth).map((w) => w.name.trim()).join('/');
    for (final template in templates) {
      final page = pages[template.id];
      if (page == null) continue;
      if (templateFolders(page).any((said) => _namesFolder(said, name))) return template;
    }
  }
  return null;
}

/// The template a folder has set on itself (not one it takes from above), for its menu's tick.
NoteTemplate? ownFolderTemplate(List<Workspace> all, String folderId, List<NoteTemplate> templates, TemplatePages pages) {
  final path = folderPathName(all, folderId);
  for (final template in templates) {
    final page = pages[template.id];
    if (page != null && templateFolders(page).any((said) => _namesFolder(said, path))) return template;
  }
  return null;
}

/// The template a new note made in a place starts from: the notebook's, then the folder's; null for none.
NoteTemplate? placeTemplate({String? notebook, List<Workspace> folders = const [], String? folderId, required List<NoteTemplate> templates, TemplatePages pages = const {}}) {
  if (notebook != null) {
    final named = templateNamed(templates, notebookTemplateName(notebook));
    if (named != null) return named;
  }
  return folderTemplate(folders, folderId, templates, pages);
}

/// A template asked for by a word and a place, as a person says it ("new bug in Kiln"; lib/capture/template_ask.dart):
/// the notebook of that name, else the folder of that name or path, not an organization's own; and the template the
/// word names, or the place's own for a plain "note" ([plainWords]). Null where no place has the name or no template
/// answers.
({NoteTemplate template, Note? notebook, Workspace? folder})? templateForPlace({
  required String word,
  required String place,
  required Iterable<Note> notes,
  required List<Workspace> folders,
  required List<NoteTemplate> templates,
  TemplatePages pages = const {},
  Set<String> plainWords = plainNotes,
}) {
  final key = titleKey(place);
  if (key.isEmpty) return null;
  Note? notebook;
  for (final note in notes) {
    if ((note.archivedAt ?? 0) == 0 && isBookBody(note.body) && !isTemplatesBody(note.body) && titleKey(noteTitle(note.body)) == key) {
      notebook = note;
      break;
    }
  }
  final folder = notebook != null ? null : folders.where((w) => !isOrgWorkspace(w.id) && (titleKey(w.name) == key || titleKey(folderPathName(folders, w.id).replaceAll('/', ' ')) == key)).firstOrNull;
  if (notebook == null && folder == null) return null;
  final plain = plainWords.contains(word.trim().toLowerCase());
  final template = plain
      ? (notebook != null ? templateNamed(templates, notebookTemplateName(notebook.body)) : folderTemplate(folders, folder!.id, templates, pages))
      : templateSaid(templates, word);
  if (template == null) return null;
  return (template: template, notebook: notebook, folder: folder);
}
