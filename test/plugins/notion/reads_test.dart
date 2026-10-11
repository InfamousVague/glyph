import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/plugins/types.dart';

import 'support.dart';

/// How the note's pills read their tasks from Notion (details.dart `notionDetails`), with Notion itself stood in
/// for by recorded answers: a read that fails is tried again after a while, as a stale answer is, rather than
/// never. The web app's `reads.test.ts`, and what a read keeps for writing back.
const String url = 'https://www.notion.so/Ship-it-3df522a4563081dc91a2cfa7d6be2ba6';
const String id = '3df522a4563081dc91a2cfa7d6be2ba6';

Map<String, Object?> page(String status, {Map<String, Object?>? parent, String title = 'Ship it'}) => {
      'id': '3df522a4-5630-81dc-91a2-cfa7d6be2ba6',
      'url': url,
      'last_edited_time': '2026-09-18T18:04:53.000Z',
      'parent': ?parent,
      'properties': {
        'Title': {
          'type': 'title',
          'title': [
            {'plain_text': title},
          ],
        },
        'Status': {
          'type': 'status',
          'status': {'name': status},
        },
      },
    };

void main() {
  late Phone phone;
  late int clock;

  setUp(() async {
    phone = Phone(account: accountJson())..use();
    clock = DateTime.parse('2026-09-18T18:10:00Z').millisecondsSinceEpoch;
    notionNow = () => clock;
    // The provider learns Notion is usable a moment after it loads.
    await warmNotionDetails();
  });

  tearDown(() {
    resetNotionDetails();
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  group('reading a task again after a failure', () {
    test('does not ask again at once, but does once a stale answer would be read again', () async {
      phone.answer = (request) async => json(500, {'message': 'The network is not back yet.'});
      notionDetails.want(url);
      await pumpEventQueue();
      expect(notionDetails.peek(url), isA<MarkFailed>().having((e) => e.message, 'message', 'The network is not back yet.'));
      expect(phone.asked, [
        {'method': 'GET', 'path': 'pages/$id', 'body': null},
      ]);

      // Straight after, from the next line scrolled past or the next keystroke: not again.
      notionDetails.want(url);
      await pumpEventQueue();
      expect(phone.requests, hasLength(1));

      // A while later, from the note's own minute-by-minute read: again, and this time it answers.
      clock += 60000;
      phone.answer = (request) async => json(200, page('Done'));
      notionDetails.want(url);
      await pumpEventQueue();
      final entry = notionDetails.peek(url);
      expect(entry, isA<MarkReady>());
      expect((entry! as MarkReady).details.status, const MarkStatus('Done', Stage.done));
      expect((entry as MarkReady).details.readAt, clock);
    });
  });

  group('a task read', () {
    test('asks nothing of Notion until the app is known to reach it', () async {
      resetNotionDetails();
      phone.answer = (request) async => json(200, page('Done'));
      notionDetails.want(url);
      expect(phone.requests, isEmpty);
      await pumpEventQueue();
      // Now it is known, and the pills were told to ask again.
      notionDetails.want(url);
      await pumpEventQueue();
      expect(phone.requests, hasLength(1));
    });

    test('reads its board’s statuses once, takes its stage from them, and keeps the answer for a note opened offline', () async {
      phone.answer = (request) async {
        if (request.url.path.endsWith('/databases/db1')) {
          return json(200, {
            'properties': {
              'Status': {
                'type': 'status',
                'status': {
                  'options': [
                    {'id': 'o1', 'name': 'Queued'},
                    {'id': 'o2', 'name': 'Parked'},
                    {'id': 'o3', 'name': 'Live'},
                  ],
                  'groups': [
                    {
                      'name': 'To-do',
                      'option_ids': ['o1'],
                    },
                    {
                      'name': 'In progress',
                      'option_ids': ['o2'],
                    },
                    {
                      'name': 'Complete',
                      'option_ids': ['o3'],
                    },
                  ],
                },
              },
            },
          });
        }
        return json(200, page('Live', parent: {'type': 'database_id', 'database_id': 'db1'}));
      };
      notionDetails.want(url);
      await pumpEventQueue();
      expect((notionDetails.peek(url)! as MarkReady).details.status, const MarkStatus('Live', Stage.done), reason: '"Live" is done on this board, whatever its name suggests');
      notionDetails.want(url, fresh: true);
      await pumpEventQueue();
      expect([for (final asked in phone.asked) asked['path']], ['pages/$id', 'databases/db1', 'pages/$id'], reason: 'the board is read once');
      final kept = phone.storedJson('glyph-notion-tasks')! as Map;
      expect(kept.keys, [id]);
      expect((kept[id] as Map)['title'], 'Ship it');

      // What can be done with it: reopen (it is done), and its words as its title.
      final actions = notionDetails.actions(url, 'Ship it today');
      expect([for (final a in actions) (a.id, a.label, a.busyLabel, a.icon)], [
        ('reopen', 'Reopen in Notion', 'Reopening…', MarkActionIcon.reopen),
        ('rename', 'Use these words as its title', 'Renaming…', MarkActionIcon.rename),
      ]);
      expect([for (final a in notionDetails.actions(url, ' Ship it ')) a.id], ['reopen'], reason: 'the same words are no rename');

      phone.requests.clear();
      expect(await actions[0].run(), 'Reopened in Notion.');
      expect(phone.asked.first, {
        'method': 'PATCH',
        'path': 'pages/$id',
        'body': {
          'properties': {
            'Status': {
              'status': {'name': 'Queued'},
            },
          },
        },
      });
      expect(phone.asked[1]['path'], 'pages/$id', reason: 'read again, to show what the write did');

      phone.requests.clear();
      expect(await actions[1].run(), 'Renamed in Notion.');
      expect(phone.asked.first, {
        'method': 'PATCH',
        'path': 'pages/$id',
        'body': {
          'properties': {
            'Title': {
              'title': [
                {
                  'type': 'text',
                  'text': {'content': 'Ship it today'},
                },
              ],
            },
          },
        },
      });
    });

    test('reads an ordinary link to a Notion page as its own, and no other address', () {
      expect(notionDetails.reads(url), isTrue);
      expect(notionDetails.reads('https://team.notion.site/Plan-3df522a4563081dc91a2cfa7d6be2ba6'), isTrue);
      expect(notionDetails.reads('https://app.notion.com/p/3df522a4563081dc91a2cfa7d6be2ba6'), isTrue);
      expect(notionDetails.reads('https://www.notion.so/pricing'), isFalse);
      expect(notionDetails.reads('https://notnotion.so/3df522a4563081dc91a2cfa7d6be2ba6'), isFalse);
      expect(notionDetails.reads('https://example.com/3df522a4563081dc91a2cfa7d6be2ba6'), isFalse);
      expect(notionDetails.reads('not a url'), isFalse);
    });

    test('opens the task in the browser, and forgets everything at a sign-out', () async {
      phone.answer = (request) async => json(200, page('Done'));
      notionDetails.want(url);
      await pumpEventQueue();
      await notionDetails.open(url);
      expect(phone.opened, [url]);
      forgetTaskDetails();
      expect(notionDetails.peek(url), isNull);
      expect(phone.kept.getItem('glyph-notion-tasks'), isNull);
      expect(notionDetails.actions(url, 'words'), isEmpty);
    });
  });
}
