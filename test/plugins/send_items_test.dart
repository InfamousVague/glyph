import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/plugins/send_items.dart';

import 'support.dart';

/// The rules of sending a note's list items somewhere (lib/plugins/send_items.dart). The page holds them through
/// its two users, `src/app/plugins/notion/send.test.ts` and `src/app/plugins/github/send.test.ts`; here they are
/// held on [ItemSender] itself, with a `make` of the test's own for the service, and each case is named for the web
/// case whose rule it is. What a plugin says afterwards ("Sent 1 task to Home.", "isn't marked") is that plugin's,
/// and is in its own tests.

void main() {
  late List<String> made;
  var now = 0;
  late ItemSender sender;

  Future<String> make(String text) async {
    made.add(text);
    return 'https://tasks.test/${made.length}';
  }

  setUp(() {
    made = [];
    now = DateTime.utc(2026, 10, 8, 12).millisecondsSinceEpoch;
    sender = ItemSender('tasks', now: () => now);
  });

  group('sending an item', () {
    test('makes the task and marks the line with it', () async {
      final note = TestNote('# Jobs\n\n- [ ] Book the cabin\n- [ ] Call Sam');
      final sent = await sender.send([(text: 'Book the cabin', line: 3)], 'b', note, make);
      expect(made, ['Book the cabin']);
      expect(note.lines[2], '- [ ] Book the cabin [tasks](https://tasks.test/1)');
      expect(note.lines[3], '- [ ] Call Sam');
      expect((sent!.sent, sent.marked), (1, 1));
      expect(note.said, isEmpty);
    });

    test('makes one task however often the same words are sent', () async {
      final note = TestNote('- [ ] Book the cabin');
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      // The line is marked, so a second press would not normally be possible; the words are sent again all the same.
      note.lines[0] = '- [ ] Book the cabin';
      final again = await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      expect(made, ['Book the cabin'], reason: 'the same words must not become two tasks');
      expect(note.lines[0], '- [ ] Book the cabin [tasks](https://tasks.test/1)');
      expect((again!.sent, again.marked), (0, 1));
    });

    test('knows the same words whatever their case and the space round them', () async {
      final note = TestNote('- [ ] Book the cabin');
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      note.lines[0] = '- [ ] book the CABIN';
      await sender.send([(text: ' book the CABIN ', line: 1)], 'b', note, make);
      expect(made, ['Book the cabin']);
    });

    test('makes a new task when the same words go to another board', () async {
      final note = TestNote('- [ ] Book the cabin');
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      // Undone, and the note linked to another board: the words are that board's to have, not a link to the first one's.
      note.lines[0] = '- [ ] Book the cabin';
      await sender.send([(text: 'Book the cabin', line: 1)], 'c', note, make);
      expect(made, ['Book the cabin', 'Book the cabin']);
      expect(note.lines[0], '- [ ] Book the cabin [tasks](https://tasks.test/2)');
    });

    test('makes a new task when the same words are sent from another note', () async {
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', TestNote('- [ ] Book the cabin'), make);
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', TestNote('- [ ] Book the cabin', noteId: 'note-2'), make);
      expect(made, hasLength(2));
    });

    test('remembers a send for five minutes, after which the words are a person meaning it', () async {
      final note = TestNote('- [ ] Book the cabin');
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      note.lines[0] = '- [ ] Book the cabin';
      now += sentFor.inMilliseconds;
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      expect(made, hasLength(1), reason: 'five minutes exactly is still a second press');
      note.lines[0] = '- [ ] Book the cabin';
      now += sentFor.inMilliseconds + 1;
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      expect(made, hasLength(2));
      expect(note.lines[0], '- [ ] Book the cabin [tasks](https://tasks.test/2)');
    });

    test('forgets what it sent when asked, for the tests of its plugins', () async {
      final note = TestNote('- [ ] Book the cabin');
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      sender.forget();
      note.lines[0] = '- [ ] Book the cabin';
      await sender.send([(text: 'Book the cabin', line: 1)], 'b', note, make);
      expect(made, hasLength(2));
    });

    test('marks the line it was on when the words have changed since', () async {
      final note = TestNote('- [ ] Book the cabin');
      final answer = Completer<String>();
      final run = sender.send([(text: 'Book the cabin', line: 1)], 'b', note, (text) {
        made.add(text);
        return answer.future;
      });
      // The person keeps typing while the service answers.
      note.lines[0] = '- [ ] Book the cabin for Friday';
      answer.complete('https://tasks.test/1');
      final sent = await run;
      expect(made, ['Book the cabin']);
      expect(note.lines[0], '- [ ] Book the cabin for Friday [tasks](https://tasks.test/1)');
      expect((sent!.sent, sent.marked), (1, 1));
    });

    test('gives each task its own item when a line above them goes while the service answers', () async {
      final note = TestNote('- [ ] One\n- [ ] Two\n- [ ] Three');
      final first = Completer<void>();
      final run = sender.send([(text: 'One', line: 1), (text: 'Two', line: 2), (text: 'Three', line: 3)], 'b', note, (text) async {
        if (text == 'One') await first.future;
        return make(text);
      });
      // The first item is deleted while its task is made: the others move up a line each.
      note.lines.removeAt(0);
      first.complete();
      final sent = await run;
      expect(made, ['One', 'Two', 'Three']);
      expect(note.lines, ['- [ ] Two [tasks](https://tasks.test/2)', '- [ ] Three [tasks](https://tasks.test/3)'], reason: 'no item may take the link of the one before it');
      // Three made, two marked: the plugin says the one that isn't.
      expect((sent!.sent, sent.marked), (3, 2));
    });

    test('says so when the task was made and the line is gone, rather than nothing at all', () async {
      final note = TestNote('- [ ] Book the cabin');
      final answer = Completer<String>();
      final run = sender.send([(text: 'Book the cabin', line: 1)], 'b', note, (text) {
        made.add(text);
        return answer.future;
      });
      note.lines[0] = 'the whole line is different words now';
      answer.complete('https://tasks.test/1');
      final sent = await run;
      expect(made, ['Book the cabin']);
      expect(note.lines, ['the whole line is different words now']);
      // Made and not marked is what the plugin reads to say "isn't marked".
      expect((sent!.sent, sent.marked), (1, 0));
    });

    test('finds an item by its words alone when the line it was on was not known', () async {
      final note = TestNote('intro\n- [ ] Book the cabin');
      final sent = await sender.send([(text: 'Book the cabin', line: null)], 'b', note, make);
      expect(note.lines[1], '- [ ] Book the cabin [tasks](https://tasks.test/1)');
      expect(sent!.marked, 1);
      // With neither its words nor a line to go by, it is made and left unmarked.
      final other = TestNote('- [ ] Something else');
      final lost = await sender.send([(text: 'Call Sam', line: null)], 'b', other, make);
      expect((lost!.sent, lost.marked), (1, 0));
      expect(other.lines, ['- [ ] Something else']);
    });

    test('sends a whole list, each item once, and says how many', () async {
      final note = TestNote('- [ ] One\n- [ ] Two\n- [x] Done already');
      final items = [(text: 'One', line: 1), (text: 'Two', line: 2)];
      final sent = await sender.send(items, 'o/r', note, make);
      expect(made, ['One', 'Two']);
      expect((sent!.sent, sent.marked), (2, 2));
      expect(note.lines, ['- [ ] One [tasks](https://tasks.test/1)', '- [ ] Two [tasks](https://tasks.test/2)', '- [x] Done already']);
      final again = await sender.send(items, 'o/r', note, make);
      expect(made, ['One', 'Two']);
      expect(again!.sent, 0);
    });

    test('says the service’s refusal and stops there', () async {
      final note = TestNote('- [ ] One\n- [ ] Two');
      final sent = await sender.send([(text: 'One', line: 1), (text: 'Two', line: 2)], 'o/r', note, (text) {
        made.add(text);
        return Future.error(Exception('GitHub didn’t accept that token.'));
      });
      expect(sent, isNull);
      expect(note.said, ['GitHub didn’t accept that token.']);
      expect(note.lines, ['- [ ] One', '- [ ] Two']);
      expect(made, ['One'], reason: 'nothing is asked after a refusal');
    });

    test('keeps what was made before a refusal marked, and does not make it again on the next press', () async {
      final note = TestNote('- [ ] One\n- [ ] Two');
      final items = [(text: 'One', line: 1), (text: 'Two', line: 2)];
      var refuse = true;
      Future<String> flaky(String text) => text == 'Two' && refuse ? Future.error(Exception('Slow down.')) : make(text);
      expect(await sender.send(items, 'b', note, flaky), isNull);
      expect(note.lines, ['- [ ] One [tasks](https://tasks.test/1)', '- [ ] Two']);
      refuse = false;
      note.lines[0] = '- [ ] One';
      final sent = await sender.send(items, 'b', note, flaky);
      expect(made, ['One', 'Two']);
      expect((sent!.sent, sent.marked), (1, 2));
    });

    test('marks with its plugin’s own name, before a board’s anchor', () async {
      final note = TestNote('- [ ] Book the cabin');
      await ItemSender('github').send([(text: 'Book the cabin', line: 1)], 'o/r', note, (_) async => 'https://github.com/o/r/issues/1');
      expect(note.lines[0], '- [ ] Book the cabin [github](https://github.com/o/r/issues/1)');
    });
  });
}
