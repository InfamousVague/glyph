import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/tabs.dart';
import 'package:ghost_md/shell/open_tabs.dart';

import '../core/make_note.dart';

/// `shell/useOpenTabs.test.tsx`, case for case: which note takes a tab, where closing one lands, and the two things
/// kept by whoever keeps the preferences - the row, and the groups over it.
void main() {
  final notes = [for (final id in ['a', 'b', 'c', 'd']) makeNote(id)];
  final all = {for (final n in notes) n.id};

  /// What was last handed to whoever keeps the row and the groups.
  List<String>? keptOpen;
  TabGroups? keptGroups;
  setUp(() {
    keptOpen = null;
    keptGroups = null;
  });

  OpenTabsController make({List<String> open = const [], TabGroups groups = TabGroups.none}) =>
      OpenTabsController(open: open, groups: groups, onOpenChanged: (next) => keptOpen = next, onGroupsChanged: (next) => keptGroups = next);

  /// A render: the note on screen, with the library as loaded.
  void show(OpenTabsController tabs, String? shown, {List<Note>? loaded, Set<String>? live}) => tabs.update(shown: shown, notes: loaded ?? notes, live: live ?? all);

  group('the open tabs', () {
    test('gives each note shown a tab, and hands the row to whoever keeps it', () {
      final tabs = make();
      show(tabs, null);
      expect(ids(tabs.tabs), isEmpty);
      show(tabs, 'a');
      show(tabs, 'b');
      show(tabs, 'a');
      expect(ids(tabs.tabs), ['a', 'b']);
      expect(keptOpen, ['a', 'b']);
    });

    test('opens the row as it was left, drawing only the tabs whose notes can be seen', () {
      final tabs = make(open: ['a', 'gone', 'b']);
      show(tabs, null, live: {'a', 'b'});
      expect(tabs.open, ['a', 'gone', 'b']);
      expect(ids(tabs.tabs), ['a', 'b']);
      expect(tabs.drawnIds, ['a', 'b']);
      // Nothing changed, so nothing was written.
      expect(keptOpen, isNull);
    });

    test('gives the next note shown the tab it is told to, once, and a tab of its own after that', () {
      final tabs = make();
      show(tabs, 'a');
      tabs.replaceNext('a');
      show(tabs, 'b');
      expect(ids(tabs.tabs), ['b']);
      show(tabs, 'c');
      expect(ids(tabs.tabs), ['b', 'c']);
    });

    test('forgets a request nothing read once no note is on screen', () {
      final tabs = make();
      show(tabs, 'a');
      // Asked for from the note already shown: no tab changes, so nothing reads it.
      tabs.replaceNext('a');
      show(tabs, null);
      show(tabs, 'b');
      expect(ids(tabs.tabs), ['a', 'b']);
    });

    test('answers where to land when the tab being read closes, and nothing when another does', () {
      final tabs = make(open: ['a', 'b', 'c']);
      show(tabs, 'b');
      expect(tabs.close(['a']), (leaves: false, to: null));
      expect(ids(tabs.tabs), ['b', 'c']);
      expect(tabs.close(['b']), (leaves: true, to: 'c'));
      show(tabs, 'c');
      expect(tabs.close(['c']), (leaves: true, to: null));
      expect(tabs.open, isEmpty);
      expect(keptOpen, isEmpty);
    });

    test('closes a whole group at once, landing past it when the tab being read was in it', () {
      final tabs = make(open: ['a', 'b', 'c', 'd']);
      show(tabs, 'b');
      expect(tabs.close(['b', 'c']), (leaves: true, to: 'd'));
      expect(tabs.open, ['a', 'd']);
    });

    test('lands on the tab before when the last of the row closes', () {
      final tabs = make(open: ['a', 'b']);
      show(tabs, 'b');
      expect(tabs.close(['b']), (leaves: true, to: 'a'));
    });

    test('drops a tab without asking where to go', () {
      final tabs = make(open: ['a', 'b']);
      show(tabs, 'a');
      tabs.drop('a');
      expect(tabs.open, ['b']);
      expect(keptOpen, ['b']);
    });

    test('moves a tab by the keys into the group it lands inside, and out of one it leaves', () {
      const groups = TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea')], of: {'a': 'g', 'b': 'g'});
      final tabs = make(open: ['a', 'b', 'c'], groups: groups);
      show(tabs, null);
      tabs.move('c', 1);
      expect(tabs.open, ['a', 'c', 'b']);
      expect(tabs.groups.of['c'], 'g');
      // A drag says for itself which group the tab is in, so the move leaves the groups alone.
      tabs.move('c', 2, grouped: true);
      expect(tabs.open, ['a', 'b', 'c']);
      expect(tabs.groups.of['c'], 'g');
      // And out again by the keys, past the group's end: among tabs of none it would leave, at its edge it stays.
      expect(keptGroups?.of['c'], 'g');
    });

    test('keeps no more than the row holds, the one opened longest ago going first', () {
      final many = [for (var i = 0; i < mostTabs + 2; i++) makeNote('n$i')];
      final tabs = make();
      for (final note in many) {
        tabs.update(shown: note.id, notes: many, live: {for (final n in many) n.id});
      }
      expect(tabs.open, hasLength(mostTabs));
      expect(tabs.open.first, 'n2');
    });

    test('tells its listeners once for each change, and not for a render that changed nothing', () {
      var told = 0;
      final tabs = make()..addListener(() => told += 1);
      show(tabs, 'a');
      expect(told, 1);
      show(tabs, 'a');
      expect(told, 1);
      tabs.setGroups(TabGroups.none);
      expect(told, 1);
    });
  });

  group('the tab groups', () {
    const groups = TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea')], of: {'a': 'g'});

    test('survive a first render with no note loaded, since they are measured against the row as kept', () {
      final tabs = make(open: ['a', 'b'], groups: groups);
      show(tabs, null, loaded: const [], live: const {});
      expect(tabs.groups, groups);
      expect(keptGroups, isNull);
    });

    test('lose a tab that closes, and a group left with nothing in it goes', () {
      final tabs = make(open: ['a', 'b'], groups: groups);
      show(tabs, null);
      tabs.close(['a']);
      expect(tabs.groups, TabGroups.none);
      expect(keptGroups, TabGroups.none);
    });

    test('follow a change made on another device', () {
      final tabs = make(open: ['a', 'b']);
      show(tabs, null);
      tabs.groupsFromElsewhere(groups);
      expect(tabs.groups, groups);
      // Drawn together, where the first of them stands.
      expect(ids(tabs.tabs), ['a', 'b']);
      // Theirs, so not written back to them.
      expect(keptGroups, isNull);
    });

    test('are drawn together, and the row follows a change made on another device', () {
      const trip = TabGroups(list: [TabGroup(id: 'g', name: 'Trip', hue: 'sea')], of: {'a': 'g', 'c': 'g'});
      final tabs = make(open: ['a', 'b', 'c'], groups: trip);
      show(tabs, null);
      expect(ids(tabs.tabs), ['a', 'c', 'b']);
      tabs.openFromElsewhere(['b', 'c']);
      expect(ids(tabs.tabs), ['b', 'c']);
      expect(tabs.groups.of, {'c': 'g'});
    });

    test('made with a group whose tab is not in the row as kept, drop it at once', () {
      final tabs = make(open: ['b'], groups: groups);
      expect(tabs.groups, TabGroups.none);
    });

    test('change when the person folds one, and are handed to whoever keeps them', () {
      final tabs = make(open: ['a', 'b'], groups: groups);
      show(tabs, null);
      tabs.setGroups(toggleGroup(groups, 'g'));
      expect(tabs.groups.list.single.collapsed, isTrue);
      expect(keptGroups?.list.single.collapsed, isTrue);
    });
  });
}
