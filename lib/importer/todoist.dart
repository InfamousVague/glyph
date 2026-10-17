/// Todoist brought into the library (Settings › Import › Todoist): with an API token, or a project's CSV export
/// (lib/importer/todoist_csv.dart). docs/INTEGRATIONS.md §4 is the contract.
///
/// Each project becomes a note, `# Work`, its description under it, its tasks with no section first and then each
/// section as a `## heading` with its own. A task is a to-do (lib/importer/task_lines.dart):
///
///     - [ ] Call the client #client-work ⏫ 🔁 every friday 📅 2026-10-23
///       Ask about the dates.
///       - [ ] Book the room
///
/// - **Priority**: the API's 4 is the app's p1 (Todoist counts the other way in its API), so 4, 3, 2 and 1 are ⏫,
///   🔼, 🔽 and none.
/// - **Due**: its day, `📅 YYYY-MM-DD` (a time of day is left out); a recurring one keeps its day and adds
///   `🔁` and Todoist's own words for it (`every friday`). A deadline beside a due date is `[deadline:: …]`; a
///   deadline alone is the `📅`.
/// - **Labels**: `#tags`, a space a `-` (evernote.dart `tagMark`).
/// - **Sub-tasks** indented under their parent, in Todoist's order; a **description** indented under its task.
/// - **Completed** tasks, when asked for, ticked with `✅` the day they were done, where they were.
///
/// With a token the projects are a notebook, "Todoist", whose index lists them, a sub-project under its parent,
/// and whose pages are in its folder: `workspaces/Imported from Todoist 2026-10-17/Todoist/Work.md`. The token is
/// used for this one import and kept nowhere: not in the preferences, not in the report, not in a note.
///
/// **The API** is Todoist's unified API v1 (`https://api.todoist.com/api/v1`, which replaced REST v2 and Sync v9):
/// `GET /projects`, `/sections` and `/tasks` (the open ones), each a page of up to 200 `results` with a
/// `next_cursor` to ask the next page by (`cursor=`), and `GET /tasks/completed/by_completion_date`, whose pages
/// are `items`, over at most three months at a time (`since`, `until`), so the last year is asked in four.
/// `Authorization: Bearer <token>`. Labels come with each task by name, so `/labels` is not asked. Comments and
/// attachments are not brought (one request a task), and the report says so.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/book.dart' show bookNoteBody;
import '../core/title_key.dart';
import 'import_report.dart';
import 'import_target.dart';
import 'task_lines.dart';

/// A project, as both the API and a CSV export give one.
class TodoistProject {
  TodoistProject({required this.id, required this.name, this.description = '', this.parentId, this.order = 0, this.inbox = false});
  final String id;
  final String name;
  final String description;
  final String? parentId;
  final int order;
  final bool inbox;
}

class TodoistSection {
  TodoistSection({required this.id, required this.projectId, required this.name, this.description = '', this.order = 0});
  final String id;
  final String projectId;
  final String name;
  final String description;
  final int order;
}

class TodoistTask {
  TodoistTask({
    required this.id,
    required this.projectId,
    required this.content,
    this.description = '',
    this.priority = 1,
    this.dueDay,
    this.dueWords,
    this.recurring = false,
    this.deadline,
    this.labels = const [],
    this.parentId,
    this.sectionId,
    this.order = 0,
    this.completedAt,
    this.comments = const [],
  });

  final String id;
  final String projectId;
  final String content;
  final String description;

  /// The API's scale: 4 is the most urgent (the app's p1), 1 none.
  final int priority;

  /// The due day, `YYYY-MM-DD`; null for none, or for one given in words a day could not be read from.
  final String? dueDay;

  /// Todoist's own words for the due date (`every friday`, `today at 11:00`).
  final String? dueWords;
  final bool recurring;
  final String? deadline;
  final List<String> labels;
  final String? parentId;
  final String? sectionId;
  final int order;

  /// The day it was done, `YYYY-MM-DD`; null while it is open.
  final String? completedAt;

  /// A CSV export's `note` rows under the task: its comments, kept as text under it.
  final List<String> comments;

  bool get done => completedAt != null;
}

/// Todoist's priority as the app's sign: 4 ⏫, 3 🔼, 2 🔽, 1 (or anything else) none.
String? todoistPriority(int priority) => switch (priority) {
      4 => '⏫',
      3 => '🔼',
      2 => '🔽',
      _ => null,
    };

/// A task as a to-do at [depth].
TaskLine todoistTaskLine(TodoistTask task, int depth) {
  final due = task.dueDay ?? (task.dueWords == null ? task.deadline : null);
  final deadline = task.deadline != null && due != task.deadline ? task.deadline : null;
  final inWords = task.dueDay == null && !task.recurring && (task.dueWords?.trim().isNotEmpty ?? false) ? task.dueWords!.trim() : null;
  final notes = [task.description.trim(), for (final comment in task.comments) comment.trim()].where((text) => text.isNotEmpty).join('\n');
  return TaskLine(
    words: task.content,
    depth: depth,
    done: task.done,
    tags: task.labels,
    priority: todoistPriority(task.priority),
    recurs: task.recurring ? task.dueWords : null,
    due: due,
    doneOn: task.completedAt,
    fields: {'when': ?inWords, 'deadline': ?deadline},
    notes: notes.isEmpty ? null : notes,
  );
}

/// A project's note: its name as the heading, its description, its tasks with no section, then each section's.
/// [counted] hears each to-do written.
String todoistProjectBody(TodoistProject project, List<TodoistSection> sections, List<TodoistTask> tasks, {void Function()? counted}) {
  final out = <String>['# ${headingTitle(project.name)}'];
  if (project.description.trim().isNotEmpty) out.add(project.description.trim());
  final ids = {for (final task in tasks) task.id};
  final children = <String?, List<TodoistTask>>{};
  for (final task in tasks) {
    // A sub-task whose parent was not brought (a parent done and not asked for) stands at the top.
    final parent = task.parentId != null && ids.contains(task.parentId) ? task.parentId : null;
    children.putIfAbsent(parent, () => []).add(task);
  }
  for (final list in children.values) {
    list.sort((a, b) => a.order.compareTo(b.order));
  }
  final seen = <String>{};
  List<String> tree(TodoistTask task, int depth) {
    if (!seen.add(task.id)) return const [];
    counted?.call();
    return [
      ...taskLines(todoistTaskLine(task, depth)),
      for (final child in children[task.id] ?? const <TodoistTask>[]) ...tree(child, depth + 1),
    ];
  }

  final sectionIds = {for (final section in sections) section.id};
  final top = children[null] ?? const <TodoistTask>[];
  final loose = [for (final task in top) if (task.sectionId == null || !sectionIds.contains(task.sectionId)) ...tree(task, 0)];
  if (loose.isNotEmpty) out.add(loose.join('\n'));
  final ordered = [...sections]..sort((a, b) => a.order.compareTo(b.order));
  for (final section in ordered) {
    out.add('## ${headingTitle(section.name)}');
    if (section.description.trim().isNotEmpty) out.add(section.description.trim());
    final lines = [for (final task in top) if (task.sectionId == section.id) ...tree(task, 0)];
    if (lines.isNotEmpty) out.add(lines.join('\n'));
  }
  return '${out.join('\n\n')}\n';
}

// ---- the API ------------------------------------------------------------------------------------------------------

/// What a request to Todoist answered.
typedef TodoistAnswer = ({int status, String body});

/// Asks [uri] with [headers]: the device's own HTTP client, or a test's stand-in.
typedef TodoistFetch = Future<TodoistAnswer> Function(Uri uri, Map<String, String> headers);

/// Where the API is.
const String todoistApi = 'https://api.todoist.com/api/v1';

/// The most a page holds.
const int todoistPage = 200;

/// The most pages one list is followed for: 100,000 of anything, far past what any account holds.
const int todoistMostPages = 500;

/// A GET over `dart:io`, a minute at most.
Future<TodoistAnswer> todoistHttpFetch(Uri uri, Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(uri);
    headers.forEach(request.headers.set);
    final response = await request.close().timeout(const Duration(seconds: 60));
    final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 60));
    return (status: response.statusCode, body: body);
  } finally {
    client.close(force: true);
  }
}

/// The API, over one token.
class TodoistApi {
  TodoistApi(this._token, {TodoistFetch? fetch}) : _fetch = fetch ?? todoistHttpFetch;

  final String _token;
  final TodoistFetch _fetch;

  /// Every row of the list at [path], page after page: `results` (or [key]) and `next_cursor`.
  Future<List<Map<String, Object?>>> list(String path, {Map<String, String> query = const {}, String key = 'results'}) async {
    final rows = <Map<String, Object?>>[];
    String? cursor;
    for (var page = 0; page < todoistMostPages; page += 1) {
      final uri = Uri.parse('$todoistApi$path').replace(queryParameters: {...query, 'limit': '$todoistPage', 'cursor': ?cursor});
      final TodoistAnswer answer;
      try {
        answer = await _fetch(uri, {'Authorization': 'Bearer $_token', 'Accept': 'application/json'});
      } on SocketException {
        throw StateError('Todoist could not be reached. Check the connection and try again.');
      } on TimeoutException {
        throw StateError('Todoist took too long to answer. Try again in a while.');
      } on HttpException {
        throw StateError('Todoist could not be reached. Check the connection and try again.');
      }
      if (answer.status == 401 || answer.status == 403) {
        throw StateError('Todoist did not take that token. Copy it again from Todoist › Settings › Integrations › Developer.');
      }
      if (answer.status == 429) throw StateError('Todoist asked to wait: too many requests. Try again in a few minutes.');
      if (answer.status < 200 || answer.status >= 300) throw StateError('Todoist answered ${answer.status}, so nothing was imported.');
      final Object? json;
      try {
        json = jsonDecode(answer.body);
      } on FormatException {
        throw StateError('Todoist answered with something that is not its data.');
      }
      if (json is! Map) throw StateError('Todoist answered with something that is not its data.');
      rows.addAll([for (final row in (json[key] as List? ?? const [])) if (row is Map) row.cast<String, Object?>()]);
      final next = json['next_cursor'];
      if (next is! String || next.isEmpty) break;
      cursor = next;
    }
    return rows;
  }
}

String _string(Object? said) => said is String ? said : (said == null ? '' : '$said');
String? _id(Object? said) => said == null ? null : (_string(said).isEmpty ? null : _string(said));
int _int(Object? said, [int fallback = 0]) => said is num ? said.toInt() : (int.tryParse(_string(said)) ?? fallback);

TodoistProject todoistProjectFrom(Map<String, Object?> json) => TodoistProject(
      id: _string(json['id']),
      name: _string(json['name']),
      description: _string(json['description']),
      parentId: _id(json['parent_id']),
      order: _int(json['child_order'] ?? json['order']),
      inbox: json['inbox_project'] == true || json['is_inbox_project'] == true,
    );

TodoistSection todoistSectionFrom(Map<String, Object?> json) => TodoistSection(
      id: _string(json['id']),
      projectId: _string(json['project_id']),
      name: _string(json['name']),
      description: _string(json['description']),
      order: _int(json['section_order'] ?? json['order']),
    );

TodoistTask todoistTaskFrom(Map<String, Object?> json) {
  final due = json['due'] is Map ? (json['due'] as Map).cast<String, Object?>() : null;
  final deadline = json['deadline'] is Map ? (json['deadline'] as Map).cast<String, Object?>() : null;
  final completed = _id(json['completed_at']);
  return TodoistTask(
    id: _string(json['id']),
    projectId: _string(json['project_id']),
    content: _string(json['content']),
    description: _string(json['description']),
    priority: _int(json['priority'], 1),
    dueDay: isoDayOf(_id(due?['date'])),
    dueWords: _id(due?['string']),
    recurring: due?['is_recurring'] == true,
    deadline: isoDayOf(_id(deadline?['date'])),
    labels: [for (final label in (json['labels'] as List? ?? const [])) ?_id(label)],
    parentId: _id(json['parent_id']),
    sectionId: _id(json['section_id']),
    order: _int(json['child_order'] ?? json['order']),
    completedAt: _doneDay(completed),
  );
}

/// The day a task was completed, in the device's own time as Todoist shows it: `2026-10-15T22:30:00.000000Z` is
/// the 16th east of Greenwich.
String? _doneDay(String? said) {
  if (said == null) return null;
  final at = DateTime.tryParse(said);
  return at == null ? isoDayOf(said) : isoDay(at.toLocal());
}

/// A UTC moment as the completed tasks' `since` and `until` take one: `2026-07-17T00:00:00Z`.
String todoistMoment(DateTime at) {
  final utc = at.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}

/// How far back completed tasks are asked for, in windows Todoist allows (three months at most).
const int todoistDoneWindows = 4;
const Duration todoistDoneWindow = Duration(days: 90);

/// Everything an account holds that the import brings: its projects, sections and open tasks, and (with [done])
/// what was completed in the last year.
Future<({List<TodoistProject> projects, List<TodoistSection> sections, List<TodoistTask> tasks})> fetchTodoist(TodoistApi api, {bool done = false, DateTime? now}) async {
  final projects = [for (final row in await api.list('/projects')) todoistProjectFrom(row)];
  final sections = [for (final row in await api.list('/sections')) todoistSectionFrom(row)];
  final tasks = [for (final row in await api.list('/tasks')) todoistTaskFrom(row)];
  if (done) {
    final seen = {for (final task in tasks) task.id};
    var until = (now ?? DateTime.now()).toUtc();
    for (var window = 0; window < todoistDoneWindows; window += 1) {
      final since = until.subtract(todoistDoneWindow);
      final rows = await api.list('/tasks/completed/by_completion_date', query: {'since': todoistMoment(since), 'until': todoistMoment(until)}, key: 'items');
      for (final row in rows) {
        final task = todoistTaskFrom(row);
        if (seen.add(task.id)) tasks.add(task.completedAt == null ? _completed(task, isoDay(until.toLocal())) : task);
      }
      until = since;
    }
  }
  return (projects: projects, sections: sections, tasks: tasks);
}

TodoistTask _completed(TodoistTask task, String day) => TodoistTask(
      id: task.id,
      projectId: task.projectId,
      content: task.content,
      description: task.description,
      priority: task.priority,
      dueDay: task.dueDay,
      dueWords: task.dueWords,
      recurring: task.recurring,
      deadline: task.deadline,
      labels: task.labels,
      parentId: task.parentId,
      sectionId: task.sectionId,
      order: task.order,
      completedAt: day,
    );

/// The projects in the index's order: the Inbox first, then each project with its sub-projects under it, each
/// level in Todoist's order. Each with how deep it sits.
List<(TodoistProject, int)> todoistProjectTree(List<TodoistProject> projects) {
  final ids = {for (final project in projects) project.id};
  final under = <String?, List<TodoistProject>>{};
  for (final project in projects) {
    under.putIfAbsent(project.parentId != null && ids.contains(project.parentId) ? project.parentId : null, () => []).add(project);
  }
  for (final list in under.values) {
    list.sort((a, b) => a.inbox != b.inbox ? (a.inbox ? -1 : 1) : a.order.compareTo(b.order));
  }
  final out = <(TodoistProject, int)>[];
  final seen = <String>{};
  void walk(String? parent, int depth) {
    for (final project in under[parent] ?? const <TodoistProject>[]) {
      if (!seen.add(project.id)) continue;
      out.add((project, depth));
      walk(project.id, depth + 1);
    }
  }

  walk(null, 0);
  return out;
}

/// The name of the notebook a token's import makes.
const String todoistNotebook = 'Todoist';

/// Imports the account behind [token] through [target]. [done] brings the last year's completed tasks too.
/// [progress] hears each project as its note is written; [stopped] is asked between them, and an import stopped
/// keeps what it made. Throws what went wrong, in the app's words, before anything is made.
Future<ImportReport> importTodoist(String token, ImportTarget target, {bool done = false, TodoistFetch? fetch, DateTime? now, void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
  final clean = token.trim();
  if (clean.isEmpty) throw StateError('Paste a Todoist API token first.');
  final account = await fetchTodoist(TodoistApi(clean, fetch: fetch), done: done, now: now);
  final run = target.begin('Todoist');
  final report = run.report;
  try {
    final tree = todoistProjectTree(account.projects);
    final pages = <(String, int)>[];
    final seen = <String>{};
    var made = 0;
    for (final (project, depth) in tree) {
      if (stopped?.call() ?? false) break;
      final body = todoistProjectBody(
        project,
        [for (final section in account.sections) if (section.projectId == project.id) section],
        [for (final task in account.tasks) if (task.projectId == project.id) task],
        counted: () => report.tasks += 1,
      );
      final title = headingTitle(project.name);
      await run.note(body: body, path: run.paths.place(const [todoistNotebook], title, original: '$title.md'));
      final link = linkTitle(title);
      if (link.isNotEmpty && seen.add(titleKey(link))) pages.add((link, depth));
      made += 1;
      progress?.call((done: made, total: tree.length, on: title));
    }
    if (pages.isNotEmpty) {
      final index = [for (final (link, depth) in pages) '${listIndent * (depth > 0 ? 1 : 0)}- [[$link]]'].join('\n');
      await run.note(body: '${bookNoteBody(todoistNotebook)}$index\n', path: run.paths.place(const [], todoistNotebook), notebook: true);
    }
    report.skipped.add('comments and attachments, which stay in Todoist');
    if (done) report.skipped.add('tasks completed more than a year ago');
  } finally {
    run.finish();
  }
  return report;
}
