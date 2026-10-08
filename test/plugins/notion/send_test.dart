import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/host.dart';
import 'package:ghost_md/plugins/notion/notion.dart';
import 'package:ghost_md/plugins/types.dart';
import 'package:glacier/glacier.dart' show setHapticsEnabled;

import 'support.dart';

/// Sending a list item to Notion: what happens when the same words are sent twice, and when the line they were on
/// has moved by the time Notion answers (Matt: "i click it once and it says sending then nothing happens then i
/// click it again and it fully processes creating the ticket"). The web app's `send.test.ts`, case for case.
///
/// The page's test stubbed the client; here the client is the real one and Notion is recorded: each `POST pages`
/// is answered with the next task's address, and what was made is read from the requests.
Board boardOf(String id, String title) => Board(id: id, title: title, url: 'https://notion.so/$id', titleProperty: 'Name');

/// A note in memory, as the editor would give it: the plugin reads it and writes lines back.
class Note implements NoteEditing {
  Note(String body) : lines = body.split('\n');
  final List<String> lines;
  final List<String> said = [];

  @override
  String get noteId => 'note-1';

  @override
  String body() => lines.join('\n');

  @override
  bool replaceLine(bool Function(String text, int line) find, String Function(String text) next) {
    for (var n = 1; n <= lines.length; n += 1) {
      final text = lines[n - 1];
      if (find(text, n)) {
        lines[n - 1] = next(text);
        return true;
      }
    }
    return false;
  }

  @override
  void say(String message) => said.add(message);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Phone phone;

  /// The titles of the tasks made, in order, and the board each went to.
  List<String> made() => [for (final asked in phone.asked) ((((asked['body']! as Map)['properties'] as Map)['Name'] as Map)['title'] as List).map((t) => ((t as Map)['text'] as Map)['content']).join()];
  List<String> madeOn() => [for (final asked in phone.asked) ((asked['body']! as Map)['parent'] as Map)['database_id'] as String];

  /// Sends [text] the way the pill does, through the plugin's own suggestion for that line.
  Future<void> sendItemsFor(Note note, String text) {
    final lines = note.body().split('\n');
    final offered = notionPlugin.suggest!('note-1', note.body()).where((s) => lines[s.line - 1].contains(text));
    if (offered.isEmpty) throw StateError('nothing offered for $text');
    expect((offered.first.label, offered.first.busyLabel), ('Notion', 'Sending'));
    return offered.first.run(note);
  }

  setUp(() async {
    setHapticsEnabled(false);
    phone = Phone(account: accountJson())..use();
    var n = 0;
    phone.answer = (request) async {
      n += 1;
      return FetchResponse.json(200, {'id': 'id-$n', 'url': 'https://notion.so/task-$n'});
    };
    linkBoard('note-1', boardOf('b', 'Jobs'));
    await notionAvailable();
  });

  tearDown(() {
    setHapticsEnabled(true);
    forgetSent();
    resetNotionClient();
    usePluginGround(PluginGround());
  });

  group('sending an item to Notion', () {
    test('makes the task and marks the line with it', () async {
      final note = Note('# Jobs\n\n- [ ] Book the cabin\n- [ ] Call Sam');
      await sendItemsFor(note, 'Book the cabin');
      expect(made(), ['Book the cabin']);
      expect(madeOn(), ['b']);
      expect(note.lines[2], '- [ ] Book the cabin [notion](https://notion.so/task-1)');
      expect(note.said.join(' '), contains('Sent 1 task'));
    });

    test('makes one task however often the same words are sent', () async {
      final note = Note('- [ ] Book the cabin');
      await sendItemsFor(note, 'Book the cabin');
      // The line is marked, so a second press would not normally be possible; the words are sent again all the same.
      note.lines[0] = '- [ ] Book the cabin';
      await sendItemsFor(note, 'Book the cabin');
      expect(made(), ['Book the cabin'], reason: 'the same words must not become two tasks');
      expect(note.lines[0], '- [ ] Book the cabin [notion](https://notion.so/task-1)');
    });

    test('makes a new task when the same words go to another board', () async {
      final note = Note('- [ ] Book the cabin');
      await sendItemsFor(note, 'Book the cabin');
      // Undone, and the note linked to another board: the words are that board's to have, not a link to the first one's.
      note.lines[0] = '- [ ] Book the cabin';
      linkBoard('note-1', boardOf('c', 'Home'));
      await sendItemsFor(note, 'Book the cabin');
      expect(made(), ['Book the cabin', 'Book the cabin']);
      expect(madeOn(), ['b', 'c']);
      expect(note.lines[0], '- [ ] Book the cabin [notion](https://notion.so/task-2)');
      expect(note.said.last, 'Sent 1 task to Home.');
    });

    test('marks the line it was on when the words have changed since', () async {
      final note = Note('- [ ] Book the cabin');
      final run = sendItemsFor(note, 'Book the cabin');
      // The person keeps typing while Notion answers.
      note.lines[0] = '- [ ] Book the cabin for Friday';
      await run;
      expect(made(), ['Book the cabin']);
      expect(note.lines[0], '- [ ] Book the cabin for Friday [notion](https://notion.so/task-1)');
      expect(note.said.join(' '), isNot(contains('isn’t marked')));
    });

    test('gives each task its own item when a line above them goes while Notion answers', () async {
      final note = Note('- [ ] One\n- [ ] Two\n- [ ] Three');
      final run = notionPlugin.noteActions.firstWhere((a) => a.id == 'notion-send-list').run(note);
      // The first item is deleted while its task is made: the others move up a line each.
      note.lines.removeAt(0);
      await run;
      expect(made(), ['One', 'Two', 'Three']);
      expect(note.lines, ['- [ ] Two [notion](https://notion.so/task-2)', '- [ ] Three [notion](https://notion.so/task-3)'], reason: 'no item may take the link of the one before it');
      expect(note.said.join(' '), contains('isn’t marked'));
    });

    test('says so when the task was made and the line is gone, rather than nothing at all', () async {
      final note = Note('- [ ] Book the cabin');
      final run = sendItemsFor(note, 'Book the cabin');
      note.lines[0] = 'the whole line is different words now';
      await run;
      expect(made(), ['Book the cabin']);
      expect(note.said.join(' '), contains('isn’t marked'));
    });
  });

  // Not in the web's file: what index.tsx offers round the send, which its tests reach only through the app.
  group('what the plugin offers on a note', () {
    test('the swipe, the cog’s row and the quiet word only once a board is linked', () async {
      final action = notionPlugin.noteActions.single;
      final swipe = notionPlugin.itemAction!;
      expect((swipe.id, swipe.label, swipe.busyLabel), ('notion-send-item', 'Notion', 'Sending…'));
      expect((action.id, action.label), ('notion-send-list', 'Send list to Notion'));
      const body = '- [ ] One\n- [x] Done already\n- [ ] Two';
      expect(action.visible('note-1', body), isTrue);
      expect(swipe.available('note-1'), isTrue);
      expect(action.visible('other', body), isFalse);
      expect(swipe.available('other'), isFalse);
      expect(notionPlugin.suggest!('other', body), isEmpty);
      expect([for (final s in notionPlugin.suggest!('note-1', body)) s.line], [1, 3]);
      expect(action.hint('note-1', body), '2 items aren’t there yet. Each becomes a task and a link.');
      expect(action.hint('note-1', '- [ ] One'), '1 item isn’t there yet. Each becomes a task and a link.');
      expect(action.hint('note-1', '- [x] One'), 'Every item is already in Notion.');
      expect(action.enabled('note-1', body), isTrue);
      expect(action.enabled('note-1', '- [x] One'), isFalse);
    });

    test('the swipe sends the item by its words, and a refusal is said in Notion’s', () async {
      final note = Note('- [ ] One\n- [ ] Two');
      await notionPlugin.itemAction!.run('Two', note);
      expect(note.lines, ['- [ ] One', '- [ ] Two [notion](https://notion.so/task-1)']);
      expect(note.said, ['Sent 1 task to Jobs.']);

      phone.answer = (request) async => FetchResponse.json(404, {'message': 'Could not find database.'});
      await notionPlugin.itemAction!.run('One', note);
      expect(note.lines[0], '- [ ] One');
      expect(note.said.last, 'Notion can’t see that board. Share it with Ghost.md in Notion.');
    });

    test('the link on the cog says where tasks go, and names the board for the note’s mark', () async {
      final link = notionPlugin.noteLinks.single;
      expect((link.id, link.label), ('notion-board', 'Notion board'));
      expect(link.hint('note-1'), 'Tasks go to Jobs.');
      expect(link.linked!('note-1'), 'Jobs');
      expect(link.hint('other'), 'Choose where this note’s list items go as tasks.');
      expect(link.linked!('other'), isNull);
      expect(await link.unavailable!(), isNull);
      phone.generation = 11;
      expect(await link.unavailable!(), 'Needs the newest Ghost.md. Update it in Settings.');
    });

    test('the manifest says what the web’s says, word for word, and its marks are read by the plugin', () {
      final m = notionPlugin.manifest;
      expect((m.id, m.name, m.version, m.author, m.standard), ('notion', 'Notion', '1.0.0', 'Ghost.md', true));
      expect(m.description, 'Turns list items into tasks on your Notion boards: swipe an item, or send a whole list.');
      expect([for (final p in m.permissions) (p.kind, p.why)], [
        (Permission.notes, 'Turns a sent item’s words into a link to its task, in the note it came from.'),
        (Permission.network, 'Signs in through ghostmarkdown.com and sends tasks to Notion. Only the items you send go.'),
        (Permission.native, 'Keeps your Notion sign-in inside the app, where no page can read it.'),
      ]);
      expect(m.hosts, ['api.notion.com', 'ghostmarkdown.com']);
      expect([m.native!.generation, m.native!.commands], [12, ['notion_save_account', 'notion_account', 'notion_disconnect', 'notion_request']]);
      expect(m.storage, ['glyph-notion-links', 'glyph-notion-signin', 'glyph-notion-tasks']);
      expect(notionPlugin.icon, 'square-kanban');
      expect(notionPlugin.settings!.summary(), 'Boards for your lists');
      expect(notionPlugin.settings!.hue, 'graphite');
      expect(identical(notionPlugin.marks, notionDetails), isTrue);
      expect(jsonEncode([for (final s in notionPlugin.settings!.settings) [s.name, s.words]]), '[["Account","sign in connect oauth workspace"],["Boards","databases lists"]]');
    });
  });
}
