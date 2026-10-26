import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/palette.dart';

/// Simple mode's palette (GHST-103; Matt, 2026-10-17: "fancy features hidden behind more"): the same doings given,
/// the same world, and `PaletteWorld.simple` deciding which rows are offered. The rule is the palette's own, so it
/// is one test rather than a check of what the root passes.
void main() {
  final calls = <String>[];
  PaletteDoing doing() => PaletteDoing(
        openNote: (id) => calls.add('openNote $id'),
        newNote: () => calls.add('newNote'),
        newNotebook: () => calls.add('newNotebook'),
        newJournal: () => calls.add('newJournal'),
        newEntry: (id) => calls.add('newEntry $id'),
        speak: () => calls.add('speak'),
        speakInto: (id) => calls.add('speakInto $id'),
        closeTab: (id) => calls.add('closeTab $id'),
        showList: () => calls.add('showList'),
        browseNotes: () => calls.add('browseNotes'),
        back: () => calls.add('back'),
        forward: () => calls.add('forward'),
        settings: () => calls.add('settings'),
        cheatSheet: () => calls.add('cheatSheet'),
        guide: () => calls.add('guide'),
        academy: () => calls.add('academy'),
        notifications: () => calls.add('notifications'),
        organizations: () => calls.add('organizations'),
        chooseWorkspace: (id) => calls.add('chooseWorkspace $id'),
        fileNote: (id, workspace) => calls.add('fileNote $id $workspace'),
        setView: (view) => calls.add('setView $view'),
        setTheme: (theme) => calls.add('setTheme $theme'),
        pin: (id, pinned) => calls.add('pin $id $pinned'),
        archive: (id) => calls.add('archive $id'),
        remove: (id) => calls.add('remove $id'),
        noteAi: (id, kind) => calls.add('noteAi $id $kind'),
        groupTab: (id) => calls.add('groupTab $id'),
        joinTabGroup: (id, group) => calls.add('joinTabGroup $id $group'),
        leaveTabGroup: (id) => calls.add('leaveTabGroup $id'),
        graph: () => calls.add('graph'),
        localGraph: (id) => calls.add('localGraph $id'),
        noteLinks: (id) => calls.add('noteLinks $id'),
        today: () => calls.add('today'),
        askClaude: () => calls.add('askClaude'),
        tags: () => calls.add('tags'),
        market: () => calls.add('market'),
        openSmart: (id) => calls.add('openSmart $id'),
      );

  const spaces = [(id: 'w1', name: 'Home'), (id: 'w2', name: 'Work')];
  const smart = [(id: 's1', name: 'Unfinished')];
  const groups = [(id: 'g1', name: 'Trip')];

  /// A busy world: a note open in a tab, another tab in a group, a journal, workspaces, a smart notebook, a trail.
  PaletteWorld world({required bool simple}) => PaletteWorld(
        notes: const [PaletteNote(id: 'n1', title: 'Weekend trip'), PaletteNote(id: 'n2', title: 'Groceries'), PaletteNote(id: 'n3', title: 'Standup')],
        journals: const [PaletteNote(id: 'j1', title: 'Diary', journal: true)],
        tabs: const [PaletteNote(id: 'n1', title: 'Weekend trip'), PaletteNote(id: 'n2', title: 'Groceries')],
        workspaces: spaces,
        workspace: 'w1',
        note: const PaletteNote(id: 'n1', title: 'Weekend trip'),
        filedIn: 'w2',
        canBack: true,
        canForward: true,
        theme: 'dark',
        tabGroups: groups,
        smartNotebooks: smart,
        simple: simple,
      );

  List<String> ids(PaletteWorld world) => [for (final command in paletteCommands(world, doing())) command.descriptor.id];

  test('keeps what simple mode has a place for', () {
    final list = ids(world(simple: true));
    expect(list, containsAll(['new', 'speak', 'list', 'notes', 'today', 'tab:n2', 'tab:close:n2', 'back', 'open:n3', 'theme:light', 'settings', 'cheatsheet', 'academy', 'guide']));
    // The note's own: its view, its pin, archive, delete, close, speaking into it, and filing it in a folder it has.
    expect(list, containsAll(['note:speak', 'note:view', 'note:pin', 'note:archive', 'note:delete', 'note:close', 'note:file:w1', 'note:unfile']));
  });

  test('leaves out what simple mode has no page or icon for', () {
    final list = ids(world(simple: true));
    for (final gone in ['notebook', 'journal', 'entry:j1', 'graph', 'ask-claude', 'tags', 'market', 'smart:s1', 'space:all', 'space:w2', 'notifications', 'organizations', 'forward', 'note:links', 'note:graph', 'tab:group:new', 'tab:group:g1']) {
      expect(list, isNot(contains(gone)), reason: '$gone is advanced');
    }
  });

  test('is the whole list in advanced, from the same world and doings', () {
    final list = ids(world(simple: false));
    expect(list, containsAll(['notebook', 'journal', 'entry:j1', 'graph', 'ask-claude', 'tags', 'market', 'smart:s1', 'space:all', 'space:w2', 'notifications', 'organizations', 'forward', 'note:links', 'note:graph', 'tab:group:new', 'tab:group:g1']));
    // And nothing simple mode keeps is lost on the way.
    expect(list, containsAll(ids(world(simple: true))));
  });

  test('keeps the keys of what remains', () {
    final list = paletteCommands(world(simple: true), doing());
    String? shortcut(String id) => list.firstWhere((command) => command.descriptor.id == id).descriptor.shortcut;
    expect(shortcut('new'), '⌘N');
    expect(shortcut('today'), '⇧⌘D');
  });

  // Matt, 2026-10-26: "Make the plugins a dedicated "Market" section in the app". Found by what it holds.
  test('offers the Market in advanced, found by plugins, themes and fonts, and opens it', () {
    for (final word in ['market', 'plugins', 'themes', 'fonts']) {
      final hits = [for (final command in paletteCommands(world(simple: false), doing())) if (command.descriptor.id == 'market' && '${command.descriptor.label} ${command.descriptor.keywords}'.toLowerCase().contains(word)) command];
      expect(hits, hasLength(1), reason: word);
    }
    calls.clear();
    paletteCommands(world(simple: false), doing()).singleWhere((command) => command.descriptor.id == 'market').run();
    expect(calls, ['market']);
  });
}
