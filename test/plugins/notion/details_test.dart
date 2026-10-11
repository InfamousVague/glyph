import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/plugins/types.dart';

/// Reading a Notion task back (lib/plugins/notion/details.dart): the web app's `details.test.ts`, case for case,
/// over the same page as Notion answers one.
final int now = DateTime.parse('2026-09-14T16:00:00Z').millisecondsSinceEpoch;

Map<String, Object?> page() => {
      'id': '3db522a4-5630-8129-8304-c129ce6004e4',
      'url': 'https://www.notion.so/The-update-banner-3db522a4563081298304c129ce6004e4',
      'last_edited_time': '2026-09-14T15:50:00.000Z',
      'parent': {'type': 'database_id', 'database_id': '9b64668a-b87b-46b5-8acb-4c7d4a2b7e5e'},
      'properties': {
        'Title': {
          'type': 'title',
          'title': [
            {'plain_text': 'The update banner'},
            {'plain_text': ' needs colour'},
          ],
        },
        'Status': {
          'type': 'status',
          'status': {'id': 'opt-progress', 'name': 'In progress'},
        },
        'Priority': {
          'type': 'select',
          'select': {'name': 'P1'},
        },
        'Type': {
          'type': 'select',
          'select': {'name': 'Bug'},
        },
        'Area': {
          'type': 'multi_select',
          'multi_select': [
            {'name': 'Editor'},
            {'name': 'Android'},
          ],
        },
        'Due': {
          'type': 'date',
          'date': {'start': '2026-09-20', 'end': null},
        },
        'Assignee': {'type': 'people', 'people': <Object?>[]},
        'Notes': {'type': 'rich_text', 'rich_text': <Object?>[]},
        'Link': {'type': 'url', 'url': null},
        'Created': {'type': 'created_time'},
      },
    };

/// [page] with some properties replaced.
Map<String, Object?> pageWith(Map<String, Object?> properties, {bool trashed = false}) {
  final made = page();
  return {
    ...made,
    'properties': {...made['properties']! as Map<String, Object?>, ...properties},
    if (trashed) 'in_trash': true,
  };
}

void main() {
  group('reading a Notion task back', () {
    test('finds the page id at the end of any Notion address', () {
      expect(pageIdOf('https://www.notion.so/The-update-banner-3db522a4563081298304c129ce6004e4'), '3db522a4563081298304c129ce6004e4');
      expect(pageIdOf('https://app.notion.com/p/3db522a4563081298304c129ce6004e4?pvs=4'), '3db522a4563081298304c129ce6004e4');
      expect(pageIdOf('https://www.notion.so/attackfm/3db522a4-5630-8129-8304-c129ce6004e4'), '3db522a4563081298304c129ce6004e4');
      expect(pageIdOf('https://example.com/nothing-here'), isNull);
      expect(pageIdOf('not a url'), isNull);
    });

    test('takes the stage from the board’s own status groups', () {
      final stages = stagesOf({
        'properties': {
          'Status': {
            'type': 'status',
            'status': {
              'options': [
                {'id': 'opt-new', 'name': 'Not started'},
                {'id': 'opt-progress', 'name': 'Shipping soon'},
                {'id': 'opt-done', 'name': 'Shipped'},
              ],
              'groups': [
                {
                  'name': 'To-do',
                  'option_ids': ['opt-new'],
                },
                {
                  'name': 'In progress',
                  'option_ids': ['opt-progress'],
                },
                {
                  'name': 'Complete',
                  'option_ids': ['opt-done'],
                },
              ],
            },
          },
        },
      });
      expect(stages['opt-progress'], Stage.doing);
      expect(stages['shipped'], Stage.done);
      final details = detailsOf(
        pageWith({
          'Status': {
            'type': 'status',
            'status': {'id': 'opt-done', 'name': 'Shipped'},
          },
        }),
        stages,
        now,
      );
      expect(details.status, const MarkStatus('Shipped', Stage.done));
    });

    test('guesses a stage from the name when the board couldn’t be read', () {
      expect(guessStage('Not started'), Stage.todo);
      expect(guessStage('Backlog'), Stage.todo);
      expect(guessStage('In review'), Stage.doing);
      expect(guessStage('Done'), Stage.done);
    });

    test('gives the pill the status, priority and due date, and the card every property with a value', () {
      final details = detailsOf(page(), null, now);
      expect(details.title, 'The update banner needs colour');
      expect(details.status, const MarkStatus('In progress', Stage.doing));
      expect(details.brief, ['P1', 'Due Sep 20']);
      expect([for (final f in details.fields) f.label], ['Status', 'Priority', 'Type', 'Area', 'Due']);
      expect(details.fields.firstWhere((f) => f.label == 'Area').value, 'Editor, Android');
      expect(details.editedAt, DateTime.parse('2026-09-14T15:50:00.000Z').millisecondsSinceEpoch);
      expect(details.readAt, now);
      expect(details.gone, isFalse);
      // As the page keeps one: no `gone` at all for a live task.
      expect(details.toJson().containsKey('gone'), isFalse);
    });

    test('says a task is overdue until it is done', () {
      final late = {
        'Due': {
          'type': 'date',
          'date': {'start': '2026-09-10'},
        },
      };
      expect(detailsOf(pageWith(late), null, now).brief, ['P1', 'Overdue Sep 10']);
      final done = {
        ...late,
        'Status': {
          'type': 'status',
          'status': {'name': 'Done'},
        },
      };
      expect(detailsOf(pageWith(done), null, now).brief, ['P1', 'Due Sep 10']);
    });

    test('reads a board with a Done checkbox and no status, and a task in the trash', () {
      final checkbox = {
        'id': 'x',
        'properties': {
          'Name': {
            'type': 'title',
            'title': [
              {'plain_text': 'Buy milk'},
            ],
          },
          'Done': {'type': 'checkbox', 'checkbox': true},
        },
      };
      expect(detailsOf(checkbox, null, now).status, const MarkStatus('Done', Stage.done));
      expect(detailsOf(pageWith(const {}, trashed: true), null, now).gone, isTrue);
      final bare = detailsOf({'id': 'y'}, null, now);
      expect([bare.title, bare.status, bare.brief, bare.fields], ['Untitled', null, isEmpty, isEmpty]);
    });

    // Not in the web's file: the values its `valueText` writes that the page above has none of.
    test('writes every other kind of value as the page does', () {
      final details = detailsOf(
        {
          'id': 'z',
          'properties': {
            'When': {
              'type': 'date',
              'date': {'start': '2025-03-04', 'end': '2025-03-09'},
            },
            'At': {
              'type': 'date',
              'date': {'start': '2026-09-20T15:05:00'},
            },
            'Who': {
              'type': 'people',
              'people': [
                {'name': 'Matt'},
                {'id': 'no-name'},
                {'name': 'Sam'},
              ],
            },
            'Flag': {'type': 'checkbox', 'checkbox': true},
            'Off': {'type': 'checkbox', 'checkbox': false},
            'Points': {'type': 'number', 'number': 3.0},
            'Share': {'type': 'number', 'number': 0.5},
            'Mail': {'type': 'email', 'email': 'a@b.c'},
            'Notes': {
              'type': 'rich_text',
              'rich_text': [
                {'plain_text': 'w' * 200},
              ],
            },
            'Sum': {
              'type': 'formula',
              'formula': {'number': 4},
            },
          },
        },
        null,
        now,
      );
      final values = {for (final f in details.fields) f.label: f.value};
      expect(values['When'], 'Mar 4, 2025 – Mar 9, 2025');
      expect(values['At'], 'Sep 20, 3:05 PM');
      expect(values['Who'], 'Matt, Sam');
      expect(values['Flag'], 'Yes');
      expect(values.containsKey('Off'), isFalse);
      expect(values['Points'], '3');
      expect(values['Share'], '0.5');
      expect(values['Mail'], 'a@b.c');
      expect(values['Notes'], '${'w' * 139}…');
      expect(values.containsKey('Sum'), isFalse);
      // A due time is the pill's day alone.
      expect(detailsOf({'id': 'q', 'properties': {'Due': {'type': 'date', 'date': {'start': '2026-09-20T15:05:00'}}}}, null, now).brief, ['Due Sep 20']);
    });
  });
}
