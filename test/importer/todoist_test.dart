import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/book.dart' show chaptersOf, isBookBody;
import 'package:ghost_md/importer/import_report.dart';
import 'package:ghost_md/importer/import_target.dart';
import 'package:ghost_md/importer/task_lines.dart';
import 'package:ghost_md/importer/todoist.dart';

import 'support.dart';

/// Todoist's API v1 as fixtures/todoist/ has it: the projects over two pages (the Inbox, Work, Work's sub-project
/// and Home), Work's two sections out of order, its tasks with every priority, a recurring due date, a deadline
/// beside a due date and one alone, labels with a space, a description of two paragraphs, sub-tasks two deep, and
/// a task whose words break across lines; and two completed tasks, one a sub-task of an open one.
class FakeTodoist {
  final List<Uri> asked = [];
  final List<Map<String, String>> headers = [];
  int status = 200;

  Future<TodoistAnswer> call(Uri uri, Map<String, String> sent) async {
    asked.add(uri);
    headers.add(sent);
    if (status != 200) return (status: status, body: '{"error":"Unauthorized"}');
    final page = switch ((uri.path, uri.queryParameters['cursor'])) {
      ('/api/v1/projects', null) => 'projects-1',
      ('/api/v1/projects', 'page-2') => 'projects-2',
      ('/api/v1/sections', null) => 'sections',
      ('/api/v1/tasks', null) => 'tasks',
      ('/api/v1/tasks/completed/by_completion_date', null) => 'completed',
      _ => throw StateError('not a page: $uri'),
    };
    return (status: 200, body: File(fixture('todoist/$page.json')).readAsStringSync());
  }
}

void main() {
  const root = 'workspaces/Imported from Todoist 2026-10-16';

  group('an account', () {
    late ImportHarness it;
    late FakeTodoist todoist;
    late ImportReport report;
    setUp(() async {
      it = ImportHarness();
      todoist = FakeTodoist();
      report = await importTodoist('  secret-token \n', it.target(), fetch: todoist.call);
    });
    tearDown(() => it.dispose());

    test('is asked page by page, with the token as a bearer and nothing else of it kept', () {
      expect([for (final uri in todoist.asked) '${uri.path}${uri.queryParameters['cursor'] == null ? '' : ' ${uri.queryParameters['cursor']}'}'], [
        '/api/v1/projects',
        '/api/v1/projects page-2',
        '/api/v1/sections',
        '/api/v1/tasks',
      ]);
      expect(todoist.asked.every((uri) => uri.host == 'api.todoist.com' && uri.queryParameters['limit'] == '200'), isTrue);
      expect(todoist.headers.every((sent) => sent['Authorization'] == 'Bearer secret-token'), isTrue);
      for (final note in it.library.value) {
        expect(note.body, isNot(contains('secret-token')));
      }
    });

    test('counts what it brought and what it left', () {
      expect(report.notes, 4);
      expect(report.notebooks, 1);
      expect(report.tasks, 7);
      expect(report.skipped, ['comments and attachments, which stay in Todoist']);
      expect(importDoneSaid(report), 'Imported 4 notes, 7 to-dos and 1 notebook, in the workspace Imported from Todoist 2026-10-16.');
    });

    test('a project: its description, its loose tasks, then its sections in their order, each task with its fields', () {
      expect(it.at('$root/Todoist/Work.md')!.body, '''# Work

Everything for the office.

- [ ] Answer the board #Quick-wins #email ⏫ 📅 2026-10-20

## This week

- [ ] Call the client [deadline:: 2026-10-31] 🔼 🔁 every friday at 10 📅 2026-10-23
  Ask about the dates.
  And the budget.
  - [ ] Book the room 🔽 📅 2026-10-22
    - [ ] Ask for the big one

## Later

- [ ] Plan the offsite
''');
    });

    test('the Inbox in Todoist’s order, words on one line; a project with nothing in it is its name', () {
      expect(it.at('$root/Todoist/Inbox.md')!.body, '# Inbox\n\n- [ ] Ring the plumber\n- [ ] Buy milk\n');
      expect(it.at('$root/Todoist/Home.md')!.body, '# Home\n');
      expect(it.at('$root/Todoist/Client Acme 2026.md')!.body, '# Client: Acme [2026]\n');
    });

    test('the notebook lists the Inbox first, then each project with its sub-projects under it', () {
      final book = it.at('$root/Todoist.md')!.body;
      expect(isBookBody(book), isTrue);
      expect([for (final chapter in chaptersOf(book)) (chapter.title, chapter.depth)], [('Inbox', 0), ('Home', 0), ('Work', 0), ('Client: Acme 2026', 1)]);
      final id = it.workspaces.value.list.single.id;
      expect(report.noteIds.every((note) => it.workspaces.value.of[note] == id), isTrue);
      removeImport(it.workspaces, report);
      expect(it.trash.value.length, 5);
    });
  });

  test('completed tasks, asked for: the last year in windows of three months, ticked where they were', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final todoist = FakeTodoist();
    final report = await importTodoist('token', it.target(), done: true, fetch: todoist.call, now: DateTime.utc(2026, 10, 16, 12));
    final windows = [for (final uri in todoist.asked) if (uri.path.endsWith('by_completion_date')) (uri.queryParameters['since'], uri.queryParameters['until'])];
    expect(windows, [
      ('2026-07-18T12:00:00Z', '2026-10-16T12:00:00Z'),
      ('2026-04-19T12:00:00Z', '2026-07-18T12:00:00Z'),
      ('2026-01-19T12:00:00Z', '2026-04-19T12:00:00Z'),
      ('2025-10-21T12:00:00Z', '2026-01-19T12:00:00Z'),
    ]);
    expect(report.tasks, 9, reason: 'the same two each window, brought once');
    expect(report.skipped, contains('tasks completed more than a year ago'));
    final body = it.at('workspaces/Imported from Todoist 2026-10-16/Todoist/Work.md')!.body;
    expect(body, contains('## This week\n\n- [x] Send the agenda #email ✅ 2026-10-14\n- [ ] Call the client'));
    expect(body, contains('  And the budget.\n  - [x] Find the number ✅ 2026-10-15\n  - [ ] Book the room'));
  });

  test('a token Todoist refuses, said in the app’s words, and nothing made', () async {
    final it = ImportHarness();
    addTearDown(it.dispose);
    final todoist = FakeTodoist()..status = 401;
    await expectLater(importTodoist('wrong', it.target(), fetch: todoist.call), throwsA(isA<StateError>().having((e) => e.message, 'message', startsWith('Todoist did not take that token.'))));
    expect(it.workspaces.value.list, isEmpty);
    expect(it.library.value, isEmpty);
    await expectLater(importTodoist('   ', it.target(), fetch: todoist.call), throwsA(isA<StateError>()));
    expect(todoist.asked.length, 1, reason: 'an empty token is never sent');
    todoist.status = 429;
    await expectLater(importTodoist('token', it.target(), fetch: todoist.call), throwsA(isA<StateError>().having((e) => e.message, 'message', contains('too many requests'))));
  });

  test('priorities the API’s way round: 4 is p1', () {
    expect([for (final p in [4, 3, 2, 1, 0]) todoistPriority(p)], ['⏫', '🔼', '🔽', null, null]);
  });

  test('a due date only in words is kept in its words; a deadline alone is the due date', () {
    String line(TodoistTask task) => taskLines(todoistTaskLine(task, 0)).single;
    expect(line(TodoistTask(id: 'a', projectId: 'p', content: 'Pay rent', dueWords: 'next monday')), '- [ ] Pay rent [when:: next monday]');
    expect(line(TodoistTask(id: 'a', projectId: 'p', content: 'File taxes', deadline: '2027-01-31')), '- [ ] File taxes 📅 2027-01-31');
    expect(line(TodoistTask(id: 'a', projectId: 'p', content: 'Water plants', dueDay: '2026-10-18', dueWords: 'every 3 days', recurring: true)), '- [ ] Water plants 🔁 every 3 days 📅 2026-10-18');
    expect(line(TodoistTask(id: 'a', projectId: 'p', content: 'Read', labels: ['2024', 'to read'])), '- [ ] Read #tag-2024 #to-read');
  });

  test('a task read from the API', () {
    final task = todoistTaskFrom({
      'id': 9,
      'project_id': 'p',
      'content': 'x',
      'priority': 4,
      'due': {'date': '2026-10-20T09:30:00Z', 'string': 'Oct 20 9:30', 'is_recurring': false},
      'labels': ['a'],
      'child_order': 3,
      'completed_at': null,
    });
    expect((task.id, task.dueDay, task.priority, task.order, task.done), ('9', '2026-10-20', 4, 3, false));
  });
}
