import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/tabs.dart';

/// `notes/openTabs.test.ts`, `notes/tabGroups.test.ts` and `notes/tabDrag.test.ts`, case for case.
void main() {
  group('the open notes', () {
    test('adds a note once, at the end, and drops the oldest past the limit', () {
      expect(addOpen([], 'a'), ['a']);
      expect(addOpen(['a', 'b'], 'c'), ['a', 'b', 'c']);
      expect(addOpen(['a', 'b'], 'a'), ['a', 'b']);
      expect(addOpen(['a', 'b', 'c'], 'd', most: 3), ['b', 'c', 'd']);
      expect(mostTabs, 8);
    });

    test('closes one, and lands on the next, then the one before, then nowhere', () {
      expect(closeOpen(['a', 'b', 'c'], 'b'), ['a', 'c']);
      expect(afterClose(['a', 'b', 'c'], 'b'), 'c');
      expect(afterClose(['a', 'b'], 'b'), 'a');
      expect(afterClose(['a'], 'a'), isNull);
      // A note already gone: the last one open, or nowhere.
      expect(afterClose(['a', 'b'], 'gone'), 'b');
      expect(afterClose([], 'gone'), isNull);
    });

    test('keeps only the ids that are still notes, in order', () {
      expect(openOnly(['a', 'b', 'c'], {'c', 'a'}), ['a', 'c']);
      expect(openOnly(['a'], {}), isEmpty);
    });
  });

  group('moving within a book', () {
    test('opens the page in the book’s tab, uses the page’s own tab if it has one, and adds where there is no tab to take', () {
      expect(swapOpen(['a', 'book', 'c'], 'book', 'page'), ['a', 'page', 'c']);
      // The page already has a tab: the book's closes and the page's is the one.
      expect(swapOpen(['a', 'book', 'page'], 'book', 'page'), ['a', 'page']);
      expect(swapOpen(['a', 'c'], 'book', 'page'), ['a', 'c', 'page']);
      expect(swapOpen(['a', 'book'], 'book', 'book'), ['a', 'book']);
    });
  });

  group('dragging a tab', () {
    const shown = ['a', 'b', 'c', 'd'];

    test('moves one along the row', () => expect(moveOpen(shown, shown, 'a', 2), ['b', 'c', 'a', 'd']));
    test('moves one back down the row', () => expect(moveOpen(shown, shown, 'd', 0), ['d', 'a', 'b', 'c']));
    test('changes nothing when it lands where it started', () => expect(moveOpen(shown, shown, 'b', 1), shown));

    test('holds a drop past either end at the end', () {
      expect(moveOpen(shown, shown, 'b', 99), ['a', 'c', 'd', 'b']);
      expect(moveOpen(shown, shown, 'c', -4), ['c', 'a', 'b', 'd']);
    });

    test('keeps ids that are no longer notes, after the row', () {
      expect(moveOpen(['a', 'ghost', 'b', 'c'], ['a', 'b', 'c'], 'c', 0), ['c', 'a', 'b', 'ghost']);
    });

    test('ignores a tab that is not in the row', () => expect(moveOpen(shown, shown, 'nope', 0), shown));
  });

  group('tab groups', () {
    TabGroups two() => const TabGroups(
          list: [TabGroup(id: 'g1', name: 'Trip', hue: 'sea'), TabGroup(id: 'g2', name: 'Work', hue: 'ember')],
          of: {'b': 'g1', 'd': 'g1', 'c': 'g2'},
        );
    List<String> idsOf(TabGroups groups) => [for (final g in groups.list) g.id];

    test('draws a group together, where its first tab stands', () {
      // b and d are one group: d is drawn beside b, not three places along.
      expect(displayOrder(['a', 'b', 'c', 'd', 'e'], two()), ['a', 'b', 'd', 'c', 'e']);
      expect(displayOrder(['a', 'b'], TabGroups.none), ['a', 'b']);
    });

    test('makes a new group around one tab, in a colour no other group wears', () {
      final made = newGroup(two(), 'a', id: 'g3');
      expect(made.groups.of['a'], 'g3');
      final group = made.groups.list.firstWhere((g) => g.id == made.id);
      expect(group.name, 'Group');
      expect(['sea', 'ember', 'ink'], isNot(contains(group.hue)));
      // Named by the clock when nobody says.
      expect(newGroup(two(), 'a').id, startsWith('g-'));
    });

    test('moves a tab into another group rather than leaving it in two', () {
      final groups = joinGroup(two(), 'c', 'g1');
      expect(groups.of['c'], 'g1');
      // g2 had only c in it, so it goes.
      expect(idsOf(groups), ['g1']);
      // A group that is not there takes nothing.
      expect(joinGroup(two(), 'c', 'nope'), two());
    });

    test('lets a tab leave, and drops a group left empty', () {
      final groups = leaveGroup(two(), 'c');
      expect(groups.of['c'], isNull);
      expect(idsOf(groups), ['g1']);
    });

    test('renames, recolours and folds a group', () {
      var groups = renameGroup(two(), 'g1', '  Weekend   away ');
      expect(groups.list.first.name, 'Weekend away');
      // An empty name is no name: the old one stays.
      expect(renameGroup(groups, 'g1', '   ').list.first.name, 'Weekend away');
      // Forty characters and no more.
      expect(renameGroup(groups, 'g1', 'x' * 60).list.first.name.length, 40);
      groups = recolourGroup(groups, 'g1', 'violet');
      expect(groups.list.first.hue, 'violet');
      groups = toggleGroup(groups, 'g1');
      expect(groups.list.first.collapsed, isTrue);
      expect(toggleGroup(groups, 'g1').list.first.collapsed, isFalse);
    });

    test('ungroups without closing anything', () {
      final groups = ungroup(two(), 'g1');
      expect(idsOf(groups), ['g2']);
      expect(groups.of, {'c': 'g2'});
    });

    test('forgets closed tabs, and any group they leave empty', () {
      final groups = pruneGroups(two(), ['a', 'b']);
      expect(groups.of, {'b': 'g1'});
      expect(idsOf(groups), ['g1']);
    });

    test('lists a group in the order its tabs are drawn', () => expect(membersOf(two(), 'g1', ['d', 'a', 'b']), ['d', 'b']));

    group('where a dragged tab lands', () {
      test('joins a group when dropped between two of its tabs', () => expect(afterMove(two(), ['b', 'a', 'd'], 'a').of['a'], 'g1'));

      test('stays in its group while moved about inside it, or to its edge', () {
        expect(afterMove(two(), ['a', 'd', 'b', 'e'], 'd').of['d'], 'g1');
        expect(afterMove(two(), ['a', 'b', 'd', 'e'], 'd').of['d'], 'g1');
      });

      test('leaves its group when dropped among tabs of none', () => expect(afterMove(two(), ['b', 'a', 'd', 'e'], 'd').of['d'], isNull));

      // At the end of g1, beside ungrouped e: an ungrouped tab stays ungrouped.
      test('does not join a group it was only dropped next to', () => expect(afterMove(two(), ['b', 'd', 'a', 'e'], 'a').of['a'], isNull));
    });

    test('tells groups that say the same thing from a change', () {
      expect(sameGroups(two(), two()), isTrue);
      expect(sameGroups(two(), renameGroup(two(), 'g1', 'Away')), isFalse);
      expect(sameGroups(two(), leaveGroup(two(), 'b')), isFalse);
      expect(sameGroups(TabGroups.none, const TabGroups(list: [], of: {})), isTrue);
    });

    test('are kept as the preference keeps them, a fold included, and read back to their shape', () {
      final folded = toggleGroup(two(), 'g1');
      expect(TabGroups.fromJson(folded.toJson()), folded);
      expect(folded.toJson()['list'], [
        {'id': 'g1', 'name': 'Trip', 'hue': 'sea', 'collapsed': true},
        {'id': 'g2', 'name': 'Work', 'hue': 'ember'},
      ]);
      // `readTabGroups` (core/preferences.ts): a group without a name is none, and a tab pointing at it is in none.
      expect(
        TabGroups.fromJson({
          'list': [
            {'id': 'g', 'name': 'Trip', 'hue': 'sea'},
            {'id': 'h', 'hue': 'moss'},
            'junk',
          ],
          'of': {'a': 'g', 'b': 'h', 'c': 3},
        }),
        const TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea')], of: {'a': 'g'}),
      );
      expect(TabGroups.fromJson(null), TabGroups.none);
      expect(TabGroups.fromJson({'list': 'no'}), TabGroups.none);
      expect(two().groupOf('b')?.name, 'Trip');
      expect(two().groupOf('a'), isNull);
    });
  });

  group('where a dragged tab has reached', () {
    // Three tabs a hundred pixels wide from the left edge; the dragged one is never among them.
    const three = [RowStop(left: 0, width: 100, tabs: 1), RowStop(left: 100, width: 100, tabs: 1), RowStop(left: 200, width: 100, tabs: 1)];

    test('is how many middles it has passed', () {
      expect(placeAt(three, 10), 0);
      expect(placeAt(three, 50), 0);
      expect(placeAt(three, 51), 1);
      expect(placeAt(three, 260), 3);
    });

    test('passes every tab of a folded group at once, and none of a chip that is not counting any', () {
      final folded = [three[0], const RowStop(left: 100, width: 40, tabs: 3), const RowStop(left: 140, width: 100, tabs: 1)];
      expect(placeAt(folded, 125), 4);
      expect(placeAt(const [RowStop(left: 0, width: 40, tabs: 0)], 30), 0);
    });
  });

  group('the group a dragged tab is over', () {
    const row = [
      DropSpot(left: 0, right: 100),
      DropSpot(left: 110, right: 150, group: 'g'),
      DropSpot(left: 150, right: 250, group: 'g'),
      DropSpot(left: 260, right: 290),
    ];

    test('is the group of the tab or chip under it, and none over a loose tab or the +', () {
      expect(groupAt(row, 50), (settled: true, group: null));
      expect(groupAt(row, 120), (settled: true, group: 'g'));
      expect(groupAt(row, 200), (settled: true, group: 'g'));
      expect(groupAt(row, 270), (settled: true, group: null));
    });

    test('is none past either end of the row', () {
      expect(groupAt(row, -5), (settled: true, group: null));
      expect(groupAt(row, 300), (settled: true, group: null));
    });

    test('is as it was in the gap between two things, and in a row with nothing else in it', () {
      expect(groupAt(row, 105).settled, isFalse);
      expect(groupAt(const [], 10).settled, isFalse);
    });
  });

  group('a flick carrying on', () {
    test('goes on at the speed it left at, a fifteenth slower each frame', () {
      final one = coasted(100, 1, 16.67, 1000);
      expect(one.left, closeTo(116.67, 0.005));
      expect(one.pace, closeTo(14 / 15, 0.005));
      expect(one.done, isFalse);
    });

    test('counts a stalled frame as four at most', () => expect(coasted(100, 1, 1000, 10000).left, closeTo(100 + 16.67 * 4, 0.005)));

    test('stops when it is too slow to see, and at either end of the row', () {
      expect(coasted(100, 0.02, 16.67, 1000).done, isTrue);
      expect(coasted(990, 1, 16.67, 1000).done, isTrue);
      expect(coasted(10, -1, 16.67, 1000).done, isTrue);
    });
  });
}
