import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/command.dart';
import 'package:ghost_md/capture/route.dart';
import 'package:ghost_md/capture/understand.dart';

import 'support/shapes.dart';

/// The command model's answer, read (lib/capture/understand.dart), case for case with the web's
/// `capture/understand.test.ts`.

const notes = [
  Candidate(id: 'g', title: 'Groceries'),
  Candidate(id: 'h', title: 'HelloTrade'),
  Candidate(id: 'b', title: 'AttackFM Bugbash'),
];

void main() {
  group('the command model’s answer', () {
    test('becomes a plan on one of the person’s notes', () {
      expect(
        readCommandAnswer('{"action":"add","note":"Groceries","text":"oat milk.","item":true,"task":false}', notes),
        PlanPlace<Candidate>(note: notes[0], text: 'oat milk', how: PlacementHow.item, task: false, many: false),
      );
      expect(readCommandAnswer('{"action":"switch","note":"HelloTrade"}', notes), PlanMove<Candidate>(note: notes[1]));
      expect(readCommandAnswer('{"action":"new"}', notes), const PlanNew<Candidate>());
      expect(
        readCommandAnswer('{"action":"table","note":"","columns":["bug","owner"]}', notes),
        const PlanTable<Candidate>(note: null, columns: ['bug', 'owner']),
      );
    });

    test('a task is an item, and a plain add leaves the words where they fit', () {
      expect(
        readCommandAnswer('{"action":"add","note":"HelloTrade","text":"ship the page","item":false,"task":true}', notes),
        matchObject({'how': 'item', 'task': true}),
      );
      expect(readCommandAnswer('{"action":"add","note":"HelloTrade","text":"ship the page"}', notes), matchObject({'how': 'leave', 'task': false}));
    });

    test('finds the note again by title, forgiving a slip and refusing one made up', () {
      expect(readCommandAnswer('{"action":"add","note":"groceries","text":"eggs"}', notes)?.kind, 'place');
      expect(readCommandAnswer('{"action":"add","note":"Attack FM bug bash","text":"eggs"}', notes), matchObject({'note': notes[2]}));
      expect(readCommandAnswer('{"action":"add","note":"Holiday plans","text":"eggs"}', notes), isNull);
      expect(readCommandAnswer('{"action":"switch","note":""}', notes), isNull);
      expect(readCommandAnswer('{"action":"table","note":"Nowhere","columns":[]}', notes), isNull);
    });

    test('is no plan when it is not a command or not JSON', () {
      expect(readCommandAnswer('{"action":"none"}', notes), isNull);
      expect(readCommandAnswer('{"action":"add","note":"Groceries","text":""}', notes), isNull);
      expect(readCommandAnswer('Sure! I will add that.', notes), isNull);
      expect(readCommandAnswer('{"action": "add", "note": "Groceries"', notes), isNull);
    });

    test('reads past a fence, thinking, or words around the object', () {
      expect(readCommandAnswer('```json\n{"action":"new"}\n```', notes), const PlanNew<Candidate>());
      expect(readCommandAnswer('<think>they want a new one {maybe}</think>\n{"action":"new"}', notes), const PlanNew<Candidate>());
      expect(
        readCommandAnswer('Here: {"action":"add","note":"Groceries","text":"a {braced} thing"} done', notes),
        matchObject({'text': 'a {braced} thing'}),
      );
    });
  });

  group('the question', () {
    test('lists the titles, then what was said', () {
      expect(commandMessage(' add eggs to groceries ', ['Groceries', 'HelloTrade']), 'Notes:\n- Groceries\n- HelloTrade\n\nCommand: add eggs to groceries');
      expect(commandMessage('new note', []), contains('(none)'));
    });
  });
}
