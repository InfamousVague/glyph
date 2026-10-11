import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/boards.dart';

/// Lanes: a lane found by the name said, a to-do added to it ("add … to Doing" on a board's own Speak), and an item
/// moved into it, which nothing in the app asks for now (tauri/docs/DESIGN.md §127). Case for case with the web's
/// `core/boards/lanes.test.ts`.
///
/// lib/core/boards/lanes.dart, reached as every caller reaches it: through the room's door, lib/core/boards.dart.
void main() {
  group('lanes, by voice', () {
    // Matt: "add voice commands and cues for adding to swimlanes on the board".
    final doc = [
      '# Launch',
      '',
      '```board height=18',
      'To do: ship-page',
      'In progress:',
      'Waiting on Sam: photos',
      'Done: pick-date',
      '```',
      '',
      '- [ ] Ship the pricing page ^ship-page',
      '- [ ] Get the photos back ^photos',
      '- [x] Pick a launch date ^pick-date',
      '- [ ] Email the beta list',
      '- A thought with no box',
      '',
      '```md',
      '- [ ] Fix the login button in an example',
      '```',
    ].join('\n');

    test('lists every board’s lanes, with where each board opens', () {
      expect(lanesOf(doc), const [
        Lane(name: 'To do', board: 3, column: 0),
        Lane(name: 'In progress', board: 3, column: 1),
        Lane(name: 'Waiting on Sam', board: 3, column: 2),
        Lane(name: 'Done', board: 3, column: 3),
      ]);
      expect(lanesOf('- [ ] No board here'), isEmpty);
    });

    test('finds the lane a name says, however it is said', () {
      final lanes = lanesOf(doc);
      String? named(String spoken) => matchLane(spoken, lanes)?.lane.name;
      expect(named('todo'), 'To do');
      expect(named('the to-do column'), 'To do');
      expect(named('In Progress lane'), 'In progress');
      expect(named('waiting'), 'Waiting on Sam');
      expect(named('finished'), 'Done');
      expect(named('done swimlane'), 'Done');
      expect(named('groceries'), isNull);
      expect(matchLane('done', lanes)?.score, 1);
    });

    test('adds a to-do to a lane: the line under the board’s last item, the card at the top of the lane', () {
      final lane = matchLane('in progress', lanesOf(doc))!.lane;
      final added = addToLane(doc, lane, 'Call Sam about the copy')!;
      expect(added.line, '- [ ] Call Sam about the copy ^call-sam-about');
      final lines = added.body.split('\n');
      expect(lines.sublist(2, 8), ['```board height=18', 'To do: ship-page', 'In progress: call-sam-about', 'Waiting on Sam: photos', 'Done: pick-date', '```']);
      expect(lines[12], '- [ ] Call Sam about the copy ^call-sam-about');
      expect(addToLane(doc, lane, '  '), isNull);
    });

    test('moves an item on the board to a lane, and ticks it going into Done', () {
      final lanes = lanesOf(doc);
      final moved = moveToLane(doc, 'the pricing page', matchLane('done', lanes)!.lane)!;
      expect(moved.item, (id: 'ship-page', text: 'Ship the pricing page', line: 10));
      expect(moved.ticked, isTrue);
      expect(moved.body, contains('To do:\nIn progress:\nWaiting on Sam: photos\nDone: pick-date, ship-page\n'));
      expect(moved.body, contains('- [x] Ship the pricing page ^ship-page\n'));
    });

    test('unticks an item taken out of Done, and leaves a box alone between other lanes', () {
      final lanes = lanesOf(doc);
      final back = moveToLane(doc, 'launch date', matchLane('in progress', lanes)!.lane)!;
      expect(back.ticked, isFalse);
      expect(back.body, contains('- [ ] Pick a launch date ^pick-date'));
      expect(back.body, contains('In progress: pick-date\n'));
      final across = moveToLane(doc, 'photos back', matchLane('to do', lanes)!.lane)!;
      expect(across.ticked, isNull);
      expect(across.body, contains('To do: ship-page, photos\nIn progress:\nWaiting on Sam:\n'));
    });

    test('names an item not yet on the board and puts it there, a box or none', () {
      final lanes = lanesOf(doc);
      final email = moveToLane(doc, 'email beta list', matchLane('waiting', lanes)!.lane)!;
      expect((email.item.id, email.item.line), ('email-beta-list', 13));
      expect(email.body, contains('- [ ] Email the beta list ^email-beta-list\n'));
      expect(email.body, contains('Waiting on Sam: photos, email-beta-list\n'));
      // An item with no box goes into Done without a tick, since there is nothing to tick.
      final thought = moveToLane(doc, 'a thought with no box', matchLane('done', lanes)!.lane)!;
      expect(thought.ticked, isNull);
      expect(thought.body, contains('- A thought with no box ^thought-no-box\n'));
    });

    test('finds nothing in a block of code, nothing for words that match no item, and nothing for a lane that is gone', () {
      final lanes = lanesOf(doc);
      expect(moveToLane(doc, 'fix the login button', lanes[0]), isNull);
      expect(moveToLane(doc, 'water the plants', lanes[0]), isNull);
      final renamed = doc.replaceFirst('In progress:', 'Doing:');
      expect(moveToLane(renamed, 'pricing page', lanes[1]), isNull);
      expect(addToLane(renamed, lanes[1], 'Anything'), isNull);
    });
  });
}
