/// A whole Notion brought into the library (Matt, 2026-11-04: "Add functionality in the notion plugin to import a
/// whole notion into ghost since we should have 1 to 1 functionality"). docs/NOTION_IMPORT.md is the contract; the
/// Notion plugin's page starts it (lib/plugins/notion/notion_import_job.dart) with the plugin's own sign-in.
///
/// **What comes in** is everything Notion shows the sign-in: the pages and databases the person picked on Notion's
/// consent page, and everything under them. Notion's API shows nothing else, so "the whole Notion" is the person's
/// top-level pages picked there.
///
/// **The shape** is Notion's own tree as folders (docs/TEAMSPACES.md, "Folder + index.md"):
///
/// - A page with sub-pages is a folder whose `index.md` is the page, its sub-pages inside in Notion's order (the
///   page's `order:`). A page with none is `<Title>.md`.
/// - A database is a folder too, its `index.md` a notebook (`book: true`) whose index lists its rows as `[[links]]`
///   and whose ```query blocks show them live as a table, and as a board where it has a status
///   (lib/importer/notion/notion_properties.dart). Each row is a note in the folder, its properties its front matter.
/// - Each page's blocks are its Markdown (notion_markdown.dart), its icon `icon:`, its cover `banner:`.
/// - Links between pages are `[[Title]]`, a title made unique across the import (`Plan`, `Plan 2`) so each link
///   opens the one page it meant.
///
/// **Again.** Every note says where it came from in its own front matter: `notion-id:` (the page's id),
/// `notion-url:` and `notion-edited:` (Notion's `last_edited_time` when it was written). That is the map from Notion
/// to the library, kept in the files (docs/MARKDOWN_FIRST.md): a second run reads it from the notes, writes again in
/// place each page whose `last_edited_time` has moved (the same note, where the person has since put it), leaves
/// the rest as they are without asking Notion for their blocks, and makes what is new. Nothing is deleted: a page
/// gone from Notion stays, and the report counts it. An import stopped part way is finished by running it again.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' show sha1;

import '../../core/banner.dart' show bannerValue;
import '../../core/front_matter.dart' show frontMatterValue, libraryKeys, quotedTitle;
import '../../core/note.dart';
import '../../core/shared_files.dart' show SharedBytes, sharedFileMarkdown;
import '../../core/title_key.dart' show titleKey;
import '../../core/workspaces.dart' show Workspace;
import '../import_paths.dart' show cleanStem;
import '../import_report.dart';
import '../import_target.dart';
import '../task_lines.dart' show headingTitle, linkTitle;
import 'notion_markdown.dart';
import 'notion_properties.dart';
import 'notion_source.dart';

/// The workspace a first import makes, where none is chosen.
const String notionWorkspaceName = 'Notion';

/// What the import found to bring: how many pages (rows among them) and databases.
typedef NotionShared = ({int pages, int databases});

/// How much of the person's Notion the sign-in can see: one pass of the search, counted.
Future<NotionShared> notionShared(NotionReader notion) async {
  var pages = 0, databases = 0;
  for (final found in await notion.search()) {
    if (_gone(found)) continue;
    found['object'] == 'database' ? databases += 1 : pages += 1;
  }
  return (pages: pages, databases: databases);
}

bool _gone(Map<String, Object?> found) => found['archived'] == true || found['in_trash'] == true;

/// One page or database, as the import places it.
class _Item {
  _Item(this.json) : id = notionIdOf('${json['id']}') ?? '${json['id']}', database = json['object'] == 'database';

  final Map<String, Object?> json;
  final String id;
  final bool database;

  /// Its parent among what was found (a page or a database), or null for one at the top.
  String? parent;

  /// A block it sits in (a column, a toggle), whose page is learned as that page's blocks are read.
  String? inBlock;

  /// Its sub-pages, databases and (for a database) rows, in Notion's order.
  final List<String> children = [];

  late String title;

  String get edited => '${json['last_edited_time'] ?? ''}';
  String get created => '${json['created_time'] ?? ''}';
  int? get createdAt => DateTime.tryParse(created)?.millisecondsSinceEpoch;
  int? get updatedAt => DateTime.tryParse(edited)?.millisecondsSinceEpoch;

  /// The title as Notion has it: a database's `title`, a page's title property.
  String get notionTitle {
    if (database) return notionPlain(json['title']);
    final properties = json['properties'];
    if (properties is Map) {
      for (final value in properties.values) {
        if (value is Map && value['type'] == 'title') return notionPlain(value['title']);
      }
    }
    return '';
  }
}

/// What one page's Markdown asked of the import as it was written.
class _Writing implements NotionWriting {
  _Writing(this._titles, this._run, this._notion, this._said);

  final Map<String, String> _titles;
  final ImportRun _run;
  final NotionReader _notion;
  final _Said _said;

  @override
  String? titleOf(String id) => _titles[id];

  @override
  Future<String?> keep(String url, {required String name, String caption = '', bool picture = false}) async {
    final uri = Uri.tryParse(url);
    final bytes = uri == null ? null : await _notion.download(uri);
    if (bytes == null) {
      _run.report.missing += 1;
      return null;
    }
    if (picture) {
      final ref = await _run.picture(bytes);
      if (ref != null) return ImportRun.pictureMarkdown(ref, caption);
    }
    return sharedFileMarkdown(name, await _run.file(SharedBytes(bytes), name));
  }

  @override
  void leftOut(String type) => _said.leftOut[type] = (_said.leftOut[type] ?? 0) + 1;

  @override
  void unresolved(String words) {
    final clean = words.trim();
    _said.unresolved.add(clean.isEmpty ? 'Untitled' : clean);
  }
}

/// What the report says at the end, gathered across pages.
class _Said {
  final Map<String, int> leftOut = {};
  final Set<String> unresolved = {};
  int icons = 0;
  int covers = 0;
  int unreadable = 0;

  /// Pages that went wrong as they were written, by title: left out, the rest brought in.
  final List<String> failed = [];

  /// Pages changed in Notion and in Ghost.md both, by title: Ghost.md's kept.
  final List<String> both = [];
}

/// Brings in everything [notion] can see through [target]: into the workspace [into] where it is given (a sync
/// again, or a folder the person chose), else a new one called [named]. [progress] hears each page as it is done,
/// of how many; [stopped] is asked between pages, and a run stopped keeps what it wrote. Throws, in the app's
/// words, what stopped it before anything was written ([NotionImportFailure]).
///
/// [found] in place of the search is a sync's few pages (lib/importer/notion/notion_import.dart [syncNotion]): the
/// rest of the library's Notion notes are taken as they are, their titles kept for links and their folders for
/// what goes in them. [newest] hears the newest `last_edited_time` among what was read, the sync's next mark.
Future<ImportReport> importNotion(NotionReader notion, ImportTarget target, {Workspace? into, String named = notionWorkspaceName, void Function(ImportProgress progress)? progress, bool Function()? stopped, List<Map<String, Object?>>? found, void Function(String newest)? newest}) async {
  final partial = found != null;
  progress?.call((done: 0, total: 0, on: null));
  final items = <String, _Item>{};
  final order = <String>[];
  void add(Map<String, Object?> json) {
    if (_gone(json) || (json['object'] != 'page' && json['object'] != 'database')) return;
    final item = _Item(json);
    if (!items.containsKey(item.id)) order.add(item.id);
    items[item.id] = item;
  }

  for (final each in found ?? await notion.search()) {
    add(each);
  }
  final said = _Said();
  // Each database's rows, in its own order: the search finds rows too, but not always all of them.
  for (final db in [for (final id in order) items[id]!].where((item) => item.database)) {
    if (stopped?.call() ?? false) break;
    try {
      for (final row in await notion.rows(db.json['id'] as String)) {
        add(row);
        final id = notionIdOf('${row['id']}');
        if (id != null && items.containsKey(id) && !db.children.contains(id)) db.children.add(id);
      }
    } on NotionImportFailure catch (failure) {
      if (failure.status == 401) rethrow;
      said.unreadable += 1;
    }
  }

  // Who is under whom: a page's or a database's parent where it is among what was found.
  for (final item in items.values) {
    final parent = item.json['parent'];
    if (parent is! Map) continue;
    final kind = parent['type'];
    final id = notionIdOf('${parent[kind]}');
    if (kind == 'block_id') {
      item.inBlock = id;
    } else if ((kind == 'page_id' || kind == 'database_id') && id != null && items.containsKey(id) && id != item.id) {
      item.parent = id;
      final under = items[id]!.children;
      if (!under.contains(item.id)) under.add(item.id);
    }
  }

  // What an import before this one made, by the Notion id each note says it came from.
  final made = <String, Note>{};
  for (final note in target.library.value) {
    final id = notionIdOf(frontMatterValue(note.body, 'notion-id'));
    if (id != null) made[id] = note;
  }

  final mark = [for (final item in items.values) item.edited].fold<String>('', (a, b) => b.compareTo(a) > 0 ? b : a);
  if (mark.isNotEmpty) newest?.call(mark);

  // A title for each, unique across the import, the oldest page keeping the plain one. A sync's other pages keep
  // the titles they have, and links to them read those.
  final byAge = [...items.values]..sort((a, b) => a.created == b.created ? a.id.compareTo(b.id) : a.created.compareTo(b.created));
  final used = <String>{};
  final titles = <String, String>{};
  if (partial) {
    for (final MapEntry(key: id, value: note) in made.entries) {
      if (items.containsKey(id)) continue;
      final title = frontMatterValue(note.body, 'title');
      if (title == null || title.isEmpty) continue;
      titles[id] = title;
      used.add(titleKey(title));
    }
  }
  for (final item in byAge) {
    var title = linkTitle(headingTitle(item.notionTitle));
    if (titleKey(title).isEmpty) title = 'Untitled';
    var unique = title;
    for (var n = 2; used.contains(titleKey(unique)); n += 1) {
      unique = '$title $n';
    }
    used.add(titleKey(unique));
    item.title = unique;
    titles[item.id] = unique;
  }

  final run = target.begin('Notion', named: named, into: into);
  final report = run.report;
  final folders = <String>{};
  final childDir = <String, String>{};
  final done = <String>{};
  final total = items.length;
  var count = 0;

  /// A folder of [title]'s in [dir] that this import has not given out: `<dir>/<Title>`, or ` 2` after it.
  String folderIn(String dir, String title) {
    final base = '$dir/${cleanStem(title)}';
    var folder = base;
    for (var n = 2; folders.contains(folder.toLowerCase()) || !run.paths.free('$folder/index.md'); n += 1) {
      folder = '$base $n';
    }
    folders.add(folder.toLowerCase());
    return folder;
  }

  Future<void> write(_Item item) async {
    done.add(item.id);
    final had = made[item.id];
    final parentDir = item.parent == null ? (_dirOfParent(item, made) ?? run.paths.root) : (childDir[item.parent] ?? run.paths.root);
    var blocks = const <Map<String, Object?>>[];
    final sameEdit = had != null && frontMatterValue(had.body, 'notion-edited') == item.edited;
    final unchanged = sameEdit && !item.database;
    // Edited in Ghost.md since it came in: its words are not what was written (`notion-hash:`). Never written over:
    // where Notion changed it too, it is said ("changed in both; kept Ghost's").
    final hash = had == null ? null : frontMatterValue(had.body, 'notion-hash');
    if (had != null && hash != null && notionHashOf(had.body) != hash) {
      final kept = had.path;
      if (kept != null && _folderPage(kept)) childDir[item.id] = kept.substring(0, kept.lastIndexOf('/'));
      if (sameEdit) {
        report.unchanged += 1;
      } else {
        report.conflicts += 1;
        said.both.add(item.title);
      }
      return;
    }
    if (!item.database && !unchanged) {
      try {
        blocks = await notion.tree(item.json['id'] as String);
      } on NotionImportFailure catch (failure) {
        if (failure.status == 401) rethrow;
        said.unreadable += 1;
      }
      // The sub-pages and databases its blocks hold, in the order they are there: a page inside a column or a toggle
      // is its page's, and Notion's order is the order on the page.
      final inside = <String>[];
      void walk(List<Map<String, Object?>> list) {
        for (final block in list) {
          final type = block['type'];
          if (type == 'child_page' || type == 'child_database') {
            final id = notionIdOf('${block['id']}');
            if (id != null) inside.add(id);
          }
          final under = block['children'];
          if (under is List) walk([for (final each in under) if (each is Map) each.cast<String, Object?>()]);
        }
      }

      walk(blocks);
      for (final id in inside) {
        final child = items[id];
        if (child == null || child.id == item.id) continue;
        if (child.parent == null && child.inBlock != null && !done.contains(id)) {
          child.parent = item.id;
          if (!item.children.contains(id)) item.children.add(id);
        }
      }
      final ordered = [for (final id in inside) if (item.children.contains(id)) id];
      final rest = [for (final id in item.children) if (!ordered.contains(id)) id];
      item.children
        ..clear()
        ..addAll([...ordered, ...rest]);
    }

    final folder = item.database || item.children.isNotEmpty;
    String path;
    final kept = had?.path;
    if (kept != null) {
      final parts = kept.split('/');
      final dir = parts.sublist(0, parts.length - 1).join('/');
      final asFolder = _folderPage(kept);
      if (folder && !asFolder) {
        path = run.paths.placeIn(folderIn(dir, item.title), 'index');
      } else {
        path = kept;
        run.paths.hold(kept);
      }
      if (folder) childDir[item.id] = path.substring(0, path.lastIndexOf('/'));
    } else if (folder) {
      final dir = folderIn(parentDir, item.title);
      path = run.paths.placeIn(dir, 'index');
      childDir[item.id] = dir;
    } else {
      path = run.paths.placeIn(parentDir, item.title, original: '${item.title}.md');
    }

    if (unchanged && path == kept) {
      report.unchanged += 1;
      return;
    }

    final writing = _Writing(titles, run, notion, said);
    final head = <String>['title: ${quotedTitle(item.title, 'Untitled')}'];
    if (item.database) head.add('book: true');
    final icon = item.json['icon'];
    if (icon is Map) {
      if (icon['type'] == 'emoji' && icon['emoji'] is String) {
        head.add('icon: ${icon['emoji']}');
      } else if (icon['type'] == 'custom_emoji' && icon['custom_emoji'] is Map && (icon['custom_emoji'] as Map)['name'] is String) {
        head.add('icon: ":${(icon['custom_emoji'] as Map)['name']}:"');
      } else {
        said.icons += 1;
      }
    }
    final cover = item.json['cover'];
    final hadBanner = sameEdit ? frontMatterValue(had.body, 'banner') : null;
    if (hadBanner != null && hadBanner.contains('](image/')) {
      // The same cover as before: not fetched again.
      head.add('banner: "$hadBanner"');
    } else if (cover is Map) {
      final kind = cover['type'];
      var url = cover[kind] is Map ? '${(cover[kind] as Map)['url'] ?? ''}' : '';
      if (url.startsWith('/')) url = 'https://www.notion.so$url';
      final uri = Uri.tryParse(url);
      final bytes = uri == null || url.isEmpty ? null : await notion.download(uri);
      final ref = bytes == null ? null : await run.picture(bytes);
      if (ref != null) {
        head.add('banner: ${bannerValue(ref.substring('image/'.length))}');
      } else {
        said.covers += 1;
      }
    }
    // A row's properties, by its database's schema (or its own, where the database was not shared).
    final parent = item.parent == null ? null : items[item.parent];
    final inDatabase = item.json['parent'] is Map && (item.json['parent'] as Map)['type'] == 'database_id';
    if (!item.database && ((parent?.database ?? false) || inDatabase)) {
      final schema = parent != null && parent.database ? schemaOf(parent.json) : schemaOfRow(item.json);
      head.addAll(await propertyLines(item.json, schema, writing, files: (url, name) async {
        final uri = Uri.tryParse(url);
        final bytes = uri == null ? null : await notion.download(uri);
        if (bytes == null) {
          report.missing += 1;
          return null;
        }
        return sharedFileMarkdown(name, await run.file(SharedBytes(bytes), name));
      }));
    }
    if (item.children.isNotEmpty && !item.database) head.add('order: ${yamlList([for (final id in item.children) titles[id]!])}');
    head
      ..add('notion-id: ${item.json['id']}')
      ..add('notion-url: ${yamlScalar('${item.json['url'] ?? ''}')}')
      ..add('notion-edited: ${item.edited}');

    final String words;
    if (item.database) {
      final description = richMarkdown(item.json['description'], writing).trim();
      final rows = [for (final id in item.children) if (!items[id]!.database) titles[id]!];
      final within = [for (final id in item.children) if (items[id]!.database) titles[id]!];
      words = [
        if (description.isNotEmpty) description,
        ...databaseQueries(item.title, schemaOf(item.json)),
        if (within.isNotEmpty) within.map((title) => '[[$title]]').join('\n\n'),
        if (rows.isNotEmpty) '## Rows\n\n${rows.map((title) => '- [[$title]]').join('\n')}',
      ].join('\n\n');
    } else {
      words = await blocksMarkdown(blocks, writing);
    }
    final written = '---\n${head.join('\n')}\n---\n# ${item.title}\n${words.isEmpty ? '' : '\n$words\n'}';
    // What was written, as a hash beside it: a later run knows the note was edited here when its words no longer
    // match (notionHashOf leaves its own line and the library's keys out).
    final body = written.replaceFirst('notion-edited: ${item.edited}\n', 'notion-edited: ${item.edited}\nnotion-hash: ${notionHashOf(written)}\n');
    if (had != null && had.body == body && had.path == path) {
      report.unchanged += 1;
      return;
    }
    await run.note(body: body, path: path, createdAt: item.createdAt, updatedAt: item.updatedAt, notebook: item.database, id: had?.id);
  }

  try {
    // Top down, so each folder is made before what goes in it: what is at the top first, in the order found.
    final queue = [for (final id in order) if (items[id]!.parent == null && items[id]!.inBlock == null) id];
    var waiting = [for (final id in order) if (items[id]!.parent == null && items[id]!.inBlock != null) id];
    while (true) {
      while (queue.isNotEmpty) {
        if (stopped?.call() ?? false) break;
        final item = items[queue.removeAt(0)]!;
        if (done.contains(item.id)) continue;
        // One page that goes wrong is left out and named; the rest still come in. Notion refusing the sign-in still
        // stops it all.
        try {
          await write(item);
        } on NotionImportFailure catch (failure) {
          if (failure.status == 401) rethrow;
          said.failed.add(item.title);
        } catch (_) {
          said.failed.add(item.title);
        }
        count += 1;
        progress?.call((done: count, total: total, on: item.title));
        queue.insertAll(0, [for (final id in item.children) if (!done.contains(id)) id]);
      }
      if (stopped?.call() ?? false) break;
      // In a block no page that was read holds (its page unchanged, or not shared): at the top.
      waiting = [for (final id in waiting) if (!done.contains(id)) id];
      final rest = [for (final id in order) if (!done.contains(id)) id];
      if (rest.isEmpty) break;
      final next = waiting.isNotEmpty ? waiting.first : rest.first;
      items[next]!.parent = null;
      queue.add(next);
    }

    final gone = made.keys.where((id) => !items.containsKey(id)).length;
    if (said.leftOut.isNotEmpty) {
      report.skipped.add([for (final MapEntry(:key, :value) in said.leftOut.entries) '$value ${value == 1 ? key : _plural(key)}'].join(', '));
    }
    if (said.unresolved.isNotEmpty) {
      final names = said.unresolved.take(4).join(', ');
      final more = said.unresolved.length > 4 ? ' and ${said.unresolved.length - 4} more' : '';
      report.skipped.add('links to ${said.unresolved.length == 1 ? 'a page' : '${said.unresolved.length} pages'} Notion didn’t share, left as words: $names$more');
    }
    if (said.failed.isNotEmpty) {
      final names = said.failed.take(5).map((title) => '“$title”').join(', ');
      final more = said.failed.length > 5 ? ' and ${said.failed.length - 5} more' : '';
      report.skipped.add('${said.failed.length == 1 ? 'a page' : '${said.failed.length} pages'} that went wrong as ${said.failed.length == 1 ? 'it was' : 'they were'} written: $names$more');
    }
    if (said.unreadable > 0) report.skipped.add('${said.unreadable} ${said.unreadable == 1 ? 'page' : 'pages'} Notion wouldn’t read out');
    if (said.icons > 0) report.skipped.add('${said.icons} ${said.icons == 1 ? 'icon that is a picture' : 'icons that are pictures'}');
    if (said.covers > 0) report.skipped.add('${said.covers} ${said.covers == 1 ? 'cover' : 'covers'} from a site Ghost.md doesn’t fetch from');
    if (said.both.isNotEmpty) report.skipped.add('${said.both.length == 1 ? '1 page' : '${said.both.length} pages'} changed in both; kept Ghost’s: ${said.both.take(4).map((t) => '“$t”').join(', ')}${said.both.length > 4 ? ' and ${said.both.length - 4} more' : ''}');
    if (!partial && gone > 0) report.skipped.add('nothing deleted: $gone ${gone == 1 ? 'page' : 'pages'} no longer in Notion stayed here');
    if (!partial) report.skipped.add('comments, which stay in Notion');
  } finally {
    run.finish();
  }
  return report;
}

/// Whether [path] is a folder's page: its `index.md`, or the note named as its folder (`Plan/Plan.md`).
bool _folderPage(String path) {
  final parts = path.split('/');
  return parts.last == 'index.md' || (parts.length >= 2 && parts.last == '${parts[parts.length - 2]}.md');
}

/// Where a page goes whose parent is not among what is written now but is a note here already (a sync's new
/// sub-page under a page that did not change): in that page's folder, else beside it.
String? _dirOfParent(_Item item, Map<String, Note> made) {
  final parent = item.json['parent'];
  if (parent is! Map) return null;
  final id = notionIdOf('${parent[parent['type']]}');
  final path = id == null ? null : made[id]?.path;
  if (path == null || !path.contains('/')) return null;
  return path.substring(0, path.lastIndexOf('/'));
}

/// A note's words as the import wrote them, hashed: the front matter's `notion-hash:` and the keys the library
/// writes of its own (front_matter.dart `libraryKeys`: id, created, updated…) left out, and the trailing space.
String notionHashOf(String body) {
  final lines = body.split('\n');
  final kept = <String>[];
  var front = lines.isNotEmpty && lines.first.trim() == '---';
  for (var i = 0; i < lines.length; i += 1) {
    final line = lines[i];
    if (front && i > 0) {
      if (line.trim() == '---') {
        front = false;
      } else {
        final key = RegExp(r'^\s*([\w.-]+)\s*:').firstMatch(line)?.group(1)?.toLowerCase();
        if (key == 'notion-hash' || libraryKeys.contains(key)) continue;
      }
    }
    kept.add(line);
  }
  return sha1.convert(utf8.encode(kept.join('\n').trimRight())).toString().substring(0, 16);
}

/// What changed in Notion since [mark], brought into [into] as [importNotion] would (Matt, 2026-11-04: "we need a
/// way to sync changes and update in real time"): the search newest first down to [mark] ([NotionReader.since]),
/// then only the pages that are new or whose `last_edited_time` moved, with the database of a changed row so its
/// index lists it. Null where nothing had changed: one request, nothing written. [newest] hears the next mark.
Future<ImportReport?> syncNotion(NotionReader notion, ImportTarget target, {required Workspace into, required String mark, void Function(String newest)? newest, void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
  final recent = await notion.since(mark);
  final top = [for (final each in recent) '${each['last_edited_time'] ?? ''}'].fold<String>(mark, (a, b) => b.compareTo(a) > 0 ? b : a);
  if (top.compareTo(mark) > 0) newest?.call(top);
  final had = <String, String?>{};
  for (final note in target.library.value) {
    final id = notionIdOf(frontMatterValue(note.body, 'notion-id'));
    if (id != null) had[id] = frontMatterValue(note.body, 'notion-edited');
  }
  final changed = <Map<String, Object?>>[];
  final ids = <String>{};
  for (final each in recent) {
    if (_gone(each)) continue;
    final id = notionIdOf('${each['id']}');
    if (id == null || ids.contains(id)) continue;
    if (had.containsKey(id) && had[id] == '${each['last_edited_time'] ?? ''}') continue;
    ids.add(id);
    changed.add(each);
  }
  if (changed.isEmpty) return null;
  // A changed row's database, so its index and its queries list the row.
  for (final row in [...changed]) {
    final parent = row['parent'];
    if (parent is! Map || parent['type'] != 'database_id') continue;
    final db = notionIdOf('${parent['database_id']}');
    if (db == null || ids.contains(db) || !had.containsKey(db)) continue;
    ids.add(db);
    try {
      final json = await notion.database('${parent['database_id']}');
      if (json != null) changed.add(json);
    } on NotionImportFailure catch (failure) {
      if (failure.status == 401) rethrow;
    }
  }
  return importNotion(notion, target, into: into, found: changed, progress: progress, stopped: stopped);
}

String _plural(String kind) => switch (kind) {
      'table of contents' => 'tables of contents',
      'breadcrumb' => 'breadcrumbs',
      'template button' => 'template buttons',
      'block Notion doesn’t share with apps' => 'blocks Notion doesn’t share with apps',
      _ => '${kind}s',
    };
