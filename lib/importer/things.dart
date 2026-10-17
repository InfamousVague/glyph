/// Things 3 brought into the library (Settings › Import › Things): on a Mac from Things' own database
/// (lib/importer/things_database.dart), anywhere from the text Things copies (lib/importer/things_paste.dart).
/// docs/INTEGRATIONS.md §4 is the contract.
///
/// - **An area** becomes a notebook whose index lists its projects, and whose pages are in its folder:
///   `workspaces/Imported from Things 2026-10-17/Work.md` and `…/Work/Launch.md`. The to-dos an area holds outside
///   any project are a page of their own, first in it, "Work to-dos".
/// - **A project** becomes a page, `# Launch`, its tags, its own When and deadline, its notes, its to-dos outside
///   any heading, then each **heading** as a `## heading` with its to-dos. A project in no area is a note at the
///   top of the workspace; the Inbox's to-dos are a note, "Inbox", and those in neither a project nor an area
///   (Anytime's and Someday's loose ones) one called "To-dos".
/// - **A to-do** is `- [ ]` (lib/importer/task_lines.dart) with its tags as `#tags`, its deadline `📅`, its When
///   date `⏳`, its notes indented under it and its checklist indented under those, `- [ ]` each.
/// - **Done and cancelled** to-dos (Things' Logbook) only when asked for: ticked, with `✅` or `❌` and the day.
///   Without, they are left out and counted. To-dos in the trash, or in a project or a heading in it, are always
///   left out; so are repeating to-dos' templates, the rules Things makes each repeat from (the repeats it has
///   made are ordinary to-dos, and come in).
library;

import '../core/book.dart' show bookNoteBody;
import '../core/title_key.dart';
import 'evernote.dart' show tagMark;
import 'import_report.dart';
import 'import_target.dart';
import 'task_lines.dart';

/// Things' kinds of row (`TMTask.type`).
enum ThingsKind { todo, project, heading }

/// Things' states (`TMTask.status`): 0 open, 2 cancelled, 3 done.
enum ThingsStatus { open, cancelled, done }

/// Where Things lists a to-do with no project and no area (`TMTask.start`): 0 the Inbox, 1 Anytime, 2 Someday.
enum ThingsStart { inbox, anytime, someday }

class ThingsArea {
  ThingsArea({required this.id, required this.title, this.order = 0});
  final String id;
  final String title;
  final int order;
}

class ThingsCheck {
  ThingsCheck({required this.title, this.status = ThingsStatus.open, this.order = 0, this.stopped});
  final String title;
  final ThingsStatus status;
  final int order;

  /// The day it was ticked, `YYYY-MM-DD`.
  final String? stopped;
}

/// A to-do, a project or a heading.
class ThingsItem {
  ThingsItem({
    required this.id,
    required this.kind,
    required this.title,
    this.status = ThingsStatus.open,
    this.start = ThingsStart.anytime,
    this.notes = '',
    this.area,
    this.project,
    this.heading,
    this.when,
    this.deadline,
    this.stopped,
    this.order = 0,
    this.tags = const [],
    this.checklist = const [],
    this.trashed = false,
    this.repeating = false,
  });

  final String id;
  final ThingsKind kind;
  final String title;
  final ThingsStatus status;
  final ThingsStart start;
  final String notes;
  final String? area;
  final String? project;
  final String? heading;

  /// Days, `YYYY-MM-DD`: when it is to be done (Things' When), its deadline, and when it was done or cancelled.
  final String? when;
  final String? deadline;
  final String? stopped;
  final int order;
  final List<String> tags;
  final List<ThingsCheck> checklist;
  final bool trashed;

  /// A repeating to-do's template (`rt1_recurrenceRule` set): the rule, not a to-do.
  final bool repeating;
}

/// What a Things database holds.
class ThingsLibrary {
  ThingsLibrary({required this.areas, required this.items});
  final List<ThingsArea> areas;
  final List<ThingsItem> items;
}

/// One note the import writes: where it goes, what it is called, and its body.
class ThingsPage {
  ThingsPage({required this.title, required this.body, this.area, this.tasks = 0});

  /// The area it is a page of; null for a note at the top.
  final String? area;
  final String title;
  final String body;
  final int tasks;
}

TaskLine _line(ThingsItem todo, int depth) => TaskLine(
      words: todo.title,
      depth: depth,
      done: todo.status == ThingsStatus.done,
      cancelled: todo.status == ThingsStatus.cancelled,
      tags: todo.tags,
      scheduled: todo.when,
      due: todo.deadline,
      doneOn: todo.status == ThingsStatus.done ? todo.stopped : null,
      cancelledOn: todo.status == ThingsStatus.cancelled ? todo.stopped : null,
      notes: todo.notes.trim().isEmpty ? null : thingsNotesText(todo.notes),
    );

/// A to-do's lines: itself, its notes, its checklist. [counted] hears each to-do and checklist item.
List<String> thingsTodoLines(ThingsItem todo, {bool done = false, void Function()? counted}) {
  counted?.call();
  final out = taskLines(_line(todo, 0));
  final checks = [...todo.checklist]..sort((a, b) => a.order.compareTo(b.order));
  for (final check in checks) {
    if (!done && check.status != ThingsStatus.open) continue;
    counted?.call();
    out.addAll(taskLines(TaskLine(
      words: check.title,
      depth: 1,
      done: check.status == ThingsStatus.done,
      cancelled: check.status == ThingsStatus.cancelled,
      doneOn: check.status == ThingsStatus.done ? check.stopped : null,
      cancelledOn: check.status == ThingsStatus.cancelled ? check.stopped : null,
    )));
  }
  return out;
}

/// Things' notes as text: the plain text it keeps, or the words of the `<note>` some versions keep it in.
String thingsNotesText(String notes) {
  final trimmed = notes.trim();
  if (!trimmed.startsWith('<note')) return notes;
  final inner = trimmed.replaceFirst(RegExp(r'^<note[^>]*>'), '').replaceFirst(RegExp(r'</note>$'), '');
  return inner
      .replaceAll(RegExp(r'<br\s*/?>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

/// What a body of to-dos says about one container: its heading, its tags, its own dates, its notes, then the
/// to-dos with no heading and each heading's.
String thingsBody({
  required String title,
  List<String> tags = const [],
  String? when,
  String? deadline,
  String notes = '',
  required List<ThingsItem> todos,
  List<(ThingsItem, List<ThingsItem>)> headings = const [],
  bool done = false,
  void Function()? counted,
}) {
  final out = <String>['# ${headingTitle(title)}'];
  final marks = [for (final tag in tags) ?tagMark(tag)];
  final dates = [if (when != null) '⏳ $when', if (deadline != null) '📅 $deadline'];
  if (marks.isNotEmpty || dates.isNotEmpty) out.add([...marks, ...dates].join(' '));
  final text = thingsNotesText(notes).trim();
  if (text.isNotEmpty) out.add(text);
  List<String> lines(List<ThingsItem> list) => [for (final todo in list) ...thingsTodoLines(todo, done: done, counted: counted)];
  final loose = lines(todos);
  if (loose.isNotEmpty) out.add(loose.join('\n'));
  for (final (heading, under) in headings) {
    out.add('## ${headingTitle(heading.title)}');
    final listed = lines(under);
    if (listed.isNotEmpty) out.add(listed.join('\n'));
  }
  return '${out.join('\n\n')}\n';
}

/// What an import of [library] writes, and what it leaves out (for the report). [done] brings the Logbook's done
/// and cancelled to-dos too.
({List<ThingsPage> pages, List<String> skipped}) thingsPages(ThingsLibrary library, {bool done = false}) {
  final byId = {for (final item in library.items) item.id: item};
  bool gone(ThingsItem item) {
    // In the trash itself, or under a project or a heading that is.
    if (item.trashed) return true;
    final heading = item.heading == null ? null : byId[item.heading];
    if (heading != null && heading.trashed) return true;
    final project = item.project ?? heading?.project;
    return project != null && (byId[project]?.trashed ?? false);
  }

  var trashed = 0, logged = 0, repeating = 0;
  bool wanted(ThingsItem item) {
    if (item.repeating) {
      if (item.kind == ThingsKind.todo) repeating += 1;
      return false;
    }
    if (gone(item)) {
      if (item.kind == ThingsKind.todo) trashed += 1;
      return false;
    }
    if (!done && item.status != ThingsStatus.open) {
      if (item.kind == ThingsKind.todo) logged += 1;
      return false;
    }
    return true;
  }

  int byOrder(ThingsItem a, ThingsItem b) => a.order.compareTo(b.order);
  final todos = [for (final item in library.items) if (item.kind == ThingsKind.todo && wanted(item)) item]..sort(byOrder);
  final projects = [for (final item in library.items) if (item.kind == ThingsKind.project && wanted(item)) item]..sort(byOrder);
  // A heading in a project is kept with its project whatever its own state: it is a heading, not a to-do.
  final headings = [for (final item in library.items) if (item.kind == ThingsKind.heading && !item.trashed && !item.repeating) item]..sort(byOrder);
  final areaIds = {for (final area in library.areas) area.id};

  // Where a to-do belongs: its heading's project when it is under a heading, else its own project.
  String? projectOf(ThingsItem todo) => todo.heading != null ? (byId[todo.heading]?.project ?? todo.project) : todo.project;

  final pages = <ThingsPage>[];
  var counted = 0;
  void count() => counted += 1;
  ThingsPage projectPage(ThingsItem project) {
    counted = 0;
    final own = [for (final todo in todos) if (projectOf(todo) == project.id && (todo.heading == null || byId[todo.heading] == null)) todo];
    final under = [
      for (final heading in headings)
        if (heading.project == project.id) (heading, [for (final todo in todos) if (todo.heading == heading.id) todo]),
    ];
    final body = thingsBody(title: project.title, tags: project.tags, when: project.when, deadline: project.deadline, notes: project.notes, todos: own, headings: under, done: done, counted: count);
    return ThingsPage(title: project.title, body: body, area: project.area != null && areaIds.contains(project.area) ? project.area : null, tasks: counted);
  }

  final areas = [...library.areas]..sort((a, b) => a.order.compareTo(b.order));
  for (final area in areas) {
    final loose = [for (final todo in todos) if (todo.area == area.id && projectOf(todo) == null) todo];
    if (loose.isNotEmpty) {
      counted = 0;
      final title = '${headingTitle(area.title)} to-dos';
      pages.add(ThingsPage(title: title, area: area.id, body: thingsBody(title: title, todos: loose, done: done, counted: count), tasks: counted));
    }
    for (final project in projects) {
      if (project.area == area.id) pages.add(projectPage(project));
    }
  }
  for (final project in projects) {
    if (project.area == null || !areaIds.contains(project.area)) pages.add(projectPage(project));
  }
  // The to-dos in no project and no area: the Inbox's, then the rest (a to-do in a project that is not brought,
  // done or in the trash, is that project's and left with it).
  final homeless = [for (final todo in todos) if (projectOf(todo) == null && (todo.area == null || !areaIds.contains(todo.area))) todo];
  final inbox = [for (final todo in homeless) if (todo.start == ThingsStart.inbox) todo];
  final rest = [for (final todo in homeless) if (todo.start != ThingsStart.inbox) todo];
  for (final (title, list) in [('Inbox', inbox), ('To-dos', rest)]) {
    if (list.isEmpty) continue;
    counted = 0;
    pages.add(ThingsPage(title: title, body: thingsBody(title: title, todos: list, done: done, counted: count), tasks: counted));
  }
  // A to-do whose project is not brought (that project done, or in the trash) goes with it, unsaid: it is counted
  // where the project is.
  final skipped = [
    if (logged > 0) logged == 1 ? 'one done or cancelled to-do, from the Logbook' : '$logged done or cancelled to-dos, from the Logbook',
    if (trashed > 0) trashed == 1 ? 'one to-do in the trash' : '$trashed to-dos in the trash',
    if (repeating > 0) repeating == 1 ? 'the rule of one repeating to-do (its repeats are here)' : 'the rules of $repeating repeating to-dos (their repeats are here)',
  ];
  return (pages: pages, skipped: skipped);
}

/// Writes [library] through [target]: each area a notebook of its pages. [progress] hears each page; [stopped] is
/// asked between them.
Future<ImportReport> importThingsLibrary(ThingsLibrary library, ImportTarget target, {bool done = false, void Function(ImportProgress progress)? progress, bool Function()? stopped}) async {
  final made = thingsPages(library, done: done);
  final run = target.begin('Things');
  final report = run.report;
  try {
    final areas = {for (final area in library.areas) area.id: area};
    final chapters = <String, List<String>>{};
    final seen = <String, Set<String>>{};
    var written = 0;
    for (final page in made.pages) {
      if (stopped?.call() ?? false) break;
      final area = page.area == null ? null : areas[page.area];
      final title = headingTitle(page.title);
      final folders = area == null ? const <String>[] : [headingTitle(area.title)];
      await run.note(body: page.body, path: run.paths.place(folders, title, original: '$title.md'));
      report.tasks += page.tasks;
      if (area != null) {
        final link = linkTitle(title);
        if (link.isNotEmpty && (seen[area.id] ??= {}).add(titleKey(link))) (chapters[area.id] ??= []).add(link);
      }
      written += 1;
      progress?.call((done: written, total: made.pages.length, on: title));
    }
    for (final area in [...library.areas]..sort((a, b) => a.order.compareTo(b.order))) {
      final pages = chapters[area.id];
      if (pages == null) continue;
      final title = headingTitle(area.title);
      await run.note(body: bookNoteBody(title, pages), path: run.paths.place(const [], title, original: '$title.md'), notebook: true);
    }
    report.skipped.addAll(made.skipped);
  } finally {
    run.finish();
  }
  return report;
}
