import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/capture/append_body.dart';
import 'package:ghost_md/capture/place.dart';

/// Where a take's words go inside the note they are for (lib/capture/place.dart), case for case with the web's
/// `capture/place.test.ts`.

const house = '# House TODOs\n\n- [ ] Fix the gutter\n';
const jobs = '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n';

void main() {
  group('the kind of place a note has for the words', () {
    test('is the end of a note’s own Speak, byte for byte, unless its title says what it holds', () {
      expect(placingFor('# Daily Life\n\n- Walked\n\nSome words.', own: true), end);
      // A title that is about tasks is not a list of them.
      expect(placingFor('# Task Management\n\nHow I keep on top of work.', own: true), end);
      expect(placingFor('# Task list\n', own: true), const PlacingLists(task: true, heading: null, fresh: PlacingFresh.task));
      expect(placingFor(house, own: true), const PlacingLists(task: true, heading: null, fresh: null));
      expect(placingFor('# Groceries\n\n- Eggs', own: true), const PlacingLists(task: false, heading: null, fresh: null));
    });

    test('is the end for a move, or words asked for as a paragraph', () {
      expect(placingFor(house, move: true), end);
      expect(placingFor(house, said: const Said(paragraph: true)), end);
    });

    test('is the note’s lists, a new one when its title or the command says which, or the end', () {
      expect(placingFor(jobs), const PlacingLists(task: true, heading: null, fresh: null));
      expect(placingFor(jobs, said: const Said(task: true), heading: 'Kitchen'), const PlacingLists(task: true, heading: 'Kitchen', fresh: null));
      expect(placingFor('# House TODOs\n'), const PlacingLists(task: true, heading: null, fresh: PlacingFresh.task));
      expect(placingFor('# Packing list\n'), const PlacingLists(task: false, heading: null, fresh: PlacingFresh.bullet));
      expect(placingFor('# Daily Life\n\nWords.'), end);
      expect(placingFor('# Daily Life\n\nWords.', said: const Said(task: true)), const PlacingLists(task: true, heading: null, fresh: PlacingFresh.task));
    });

    test('reads the title and the lists after the front matter', () {
      expect(placingFor('---\ntitle: Chores\nbook: false\n---\nWords.'), const PlacingLists(task: true, heading: null, fresh: PlacingFresh.task));
    });
  });

  group('the take as items', () {
    test('makes each sentence a thing, with the sentences that carry one on under it', () {
      final read = itemsOf('Call an electrician to fix the light sockets. Because the switch sparks. Ask about the porch light too.');
      expect(read.items, [
        TakeItem(text: 'Call an electrician to fix the light sockets.', more: ['Because the switch sparks.']),
        TakeItem(text: 'Ask about the porch light too.'),
      ]);
      expect(read.after, <String>[]);
    });

    test('takes list lines as they are, strips the words that join items, and keeps what is not an item for the end', () {
      final read = itemsOf('- Milk\n- Eggs\n  free range\n\nAnd also bread.\n\n## Later\n\n| a | b |');
      expect(read.items, [
        TakeItem(text: 'Milk'),
        TakeItem(text: 'Eggs', more: ['free range']),
        TakeItem(text: 'bread.'),
      ]);
      expect(read.after, ['## Later', '| a | b |']);
    });

    test('keeps a long thought said first as a paragraph, and one said later under the item before it', () {
      final long = 'Word ${('word ' * 30).trim()}.';
      expect(itemsOf(long).items, <TakeItem>[]);
      expect(itemsOf(long).after, [long]);
      expect(itemsOf('Call Sam. $long').items, [
        TakeItem(text: 'Call Sam.', more: [long]),
      ]);
      expect(itemsOf('Call Sam. $long').after, <String>[]);
    });
  });

  group('writing the words in', () {
    Placing lists(String base, [Said said = const Said(), String? heading]) => placingFor(base, said: said, heading: heading);

    test('writes Matt’s to-do into House TODOs’ list, after its last item', () {
      expect(
        placeTake(house, 'Call an electrician to fix the light sockets.', lists(house)),
        const Placed(
          body: '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call an electrician to fix the light sockets\n',
          blocks: ['- [ ] Call an electrician to fix the light sockets'],
          spot: 'in its to-do list',
        ),
      );
    });

    test('starts a to-do list in a to-do note that has none', () {
      expect(placeTake('# House TODOs\n', 'Call an electrician.', lists('# House TODOs\n')).body, '# House TODOs\n\n- [ ] Call an electrician\n');
    });

    test('puts an item under the heading it shares words with, not one that only shares a verb', () {
      final placed = placeTake(jobs, 'Call an electrician to fix the light sockets.', lists(jobs));
      expect(
        placed.body,
        '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call an electrician to fix the light sockets\n',
      );
      expect(placed.spot, 'under Electrical');
    });

    test('puts it under a heading said for it, whatever it would otherwise fit', () {
      // "Call Sam" shares nothing with either list, and would go to Kitchen, the first with something still to do.
      expect(placeTake(jobs, 'Call Sam.', lists(jobs)).body, contains('- [ ] Fix tap\n- [ ] Call Sam\n\n## Electrical'));
      expect(
        placeTake(jobs, 'Call Sam.', lists(jobs, const Said(), 'electrical')).body,
        '# Home jobs\n\n## Kitchen\n- [ ] Fix tap\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call Sam\n',
      );
    });

    test('keeps related things said together in one list, and sends one that plainly fits another there', () {
      const base = '# Home\n\n## Electrical\n- [ ] Rewire porch light\n\n## Garden\n- [ ] Mow the lawn\n';
      final placed = placeTake(base, 'Call an electrician about the porch light. Get a spare fuse. And for the garden, trim the hedge.', lists(base));
      expect(
        placed.body,
        '# Home\n\n## Electrical\n- [ ] Rewire porch light\n- [ ] Call an electrician about the porch light\n- [ ] Get a spare fuse\n\n## Garden\n- [ ] Mow the lawn\n- [ ] For the garden, trim the hedge\n',
      );
      expect(placed.blocks, ['- [ ] Call an electrician about the porch light\n- [ ] Get a spare fuse', '- [ ] For the garden, trim the hedge']);
    });

    test('with nothing to go by, goes to the first to-do list with something still to do, else the last list', () {
      const base = '# Plans\n\n- [x] Done thing\n\n- [ ] Open thing\n\n- plain\n';
      expect(placeTake(base, 'Zebra crossing.', lists(base)).body, '# Plans\n\n- [x] Done thing\n\n- [ ] Open thing\n- [ ] Zebra crossing\n\n- plain\n');
      const plain = '# Plans\n\n- one\n\n1. two\n';
      expect(placeTake(plain, 'Zebra.', lists(plain)).body, '# Plans\n\n- one\n\n1. two\n2. Zebra\n');
    });

    test('keeps only to-do lists for a to-do, and writes in each list’s own style', () {
      const base = '# Mixed\n\n* [ ] Starred to-do\n\nShopping:\n- eggs\n';
      expect(placeTake(base, 'Call Sam.', lists(base, const Said(task: true))).body, '# Mixed\n\n* [ ] Starred to-do\n* [ ] Call Sam\n\nShopping:\n- eggs\n');
      const numbered = 'Steps\n\n  1) Build\n  2) Test\n';
      expect(placeTake(numbered, 'Ship it. Celebrate.', lists(numbered)).body, 'Steps\n\n  1) Build\n  2) Test\n  3) Ship it\n  4) Celebrate\n');
    });

    test('puts what is not an item after the lists, at the end', () {
      expect(placeTake(house, 'Call Sam.\n\n## Later', lists(house)).body, '# House TODOs\n\n- [ ] Fix the gutter\n- [ ] Call Sam\n\n## Later\n');
    });

    test('writes the end exactly as appendBody does, and nothing for nothing said', () {
      expect(placeTake('# Daily Life\n\nWords.\n', 'More words.', end).body, appendBody('# Daily Life\n\nWords.\n', 'More words.'));
      expect(placeTake(house, '', lists(house)), const Placed(body: house, blocks: [], spot: null));
    });

    test('goes on from a line left open: a paragraph on the same line, anything else under it, the line alone for nothing said', () {
      const entry = '---\ntitle: "2026-09-28 14.05"\ndate: 2026-09-28T14:05\n---\n# Monday 28 September\n\n';
      const at = PlacingEnd(lead: '**14:05** ');
      expect(
        placeTake(entry, 'Walked along the river after lunch.\n\nThen home.', at),
        const Placed(
          body: '$entry**14:05** Walked along the river after lunch.\n\nThen home.',
          blocks: ['**14:05** Walked along the river after lunch.\n\nThen home.'],
          spot: null,
        ),
      );
      expect(placeTake(entry, '- Bread\n- Milk', at).body, '$entry**14:05**\n\n- Bread\n- Milk');
      expect(placeTake(entry, '## Later\n\nWords.', at).body, '$entry**14:05**\n\n## Later\n\nWords.');
      expect(placeTake(entry, '', at), const Placed(body: '$entry**14:05**', blocks: [], spot: null));
      // An entry of only its time: the words follow the front matter.
      expect(placeTake('---\ntitle: "2026-09-28 14.05"\n---\n', 'Coffee.', at).body, '---\ntitle: "2026-09-28 14.05"\n---\n\n**14:05** Coffee.');
    });

    test('adds a card to a board’s lane', () {
      const board = '# Launch\n\n```board\nTo do: write-copy\nDoing: pricing-page\n```\n\n- [ ] Write the copy ^write-copy\n- [ ] Pricing page ^pricing-page\n';
      final placing = placingFor(board, lane: 'Doing', own: true);
      expect(placing, const PlacingLane(lane: 'Doing'));
      final placed = placeTake(board, 'Fix the login bug.', placing);
      expect(placed.body, matches(RegExp(r'\nDoing: fix-[a-z-]+, pricing-page\n')));
      expect(placed.body, matches(RegExp(r'\n- \[ \] Fix the login bug \^fix-[a-z-]+\n')));
      expect(placed.spot, 'in Doing');
    });
  });
}
