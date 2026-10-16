import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/commands/palette.dart';

/// `commands/palette.test.ts`, case for case: what the palette offers when, what each row says, and what it runs.
/// The doings are the web test's, all of them given, so the lists are the web's; a recorder stands in for `vi.fn()`.
class Calls {
  final List<String> said = [];
  void call(String what) => said.add(what);
}

PaletteDoing doing(
  Calls calls, {
  bool speaking = true,
  bool newJournal = false,
  bool newEntry = false,
  bool noteAi = false,
  bool tabGroups = false,
  bool links = false,
}) =>
    PaletteDoing(
      openNote: (id) => calls('openNote $id'),
      newNote: () => calls('newNote'),
      newNotebook: () => calls('newNotebook'),
      newJournal: newJournal ? () => calls('newJournal') : null,
      newEntry: newEntry ? (id) => calls('newEntry $id') : null,
      speak: speaking ? () => calls('speak') : null,
      speakInto: speaking ? (id) => calls('speakInto $id') : null,
      closeTab: (id) => calls('closeTab $id'),
      showList: () => calls('showList'),
      browseNotes: () => calls('browseNotes'),
      back: () => calls('back'),
      forward: () => calls('forward'),
      settings: () => calls('settings'),
      cheatSheet: () => calls('cheatSheet'),
      guide: () => calls('guide'),
      academy: () => calls('academy'),
      notifications: () => calls('notifications'),
      organizations: () => calls('organizations'),
      chooseWorkspace: (id) => calls('chooseWorkspace $id'),
      fileNote: (id, workspace) => calls('fileNote $id $workspace'),
      setView: (view) => calls('setView $view'),
      setTheme: (theme) => calls('setTheme $theme'),
      pin: (id, pinned) => calls('pin $id $pinned'),
      archive: (id) => calls('archive $id'),
      remove: (id) => calls('remove $id'),
      noteAi: noteAi ? (id, kind) => calls('noteAi $id $kind') : null,
      groupTab: tabGroups ? (id) => calls('groupTab $id') : null,
      joinTabGroup: tabGroups ? (id, group) => calls('joinTabGroup $id $group') : null,
      leaveTabGroup: tabGroups ? (id) => calls('leaveTabGroup $id') : null,
      graph: links ? () => calls('graph') : null,
      localGraph: links ? (id) => calls('localGraph $id') : null,
      noteLinks: links ? (id) => calls('noteLinks $id') : null,
    );

PaletteNote n(String id, String title, {bool journal = false, bool entry = false, int blanks = 0}) => PaletteNote(id: id, title: title, journal: journal, entry: entry, blanks: blanks);

List<String> ids(List<PaletteCommand> commands) => [for (final command in commands) command.descriptor.id];
PaletteCommand? of(List<PaletteCommand> commands, String id) {
  for (final command in commands) {
    if (command.descriptor.id == id) return command;
  }
  return null;
}

void run(List<PaletteCommand> commands, String id) => of(commands, id)?.run();

void main() {
  group('what the palette offers', () {
    test('always offers the things that need nothing', () {
      final list = ids(paletteCommands(const PaletteWorld(), doing(Calls())));
      expect(list, containsAll(['new', 'notebook', 'speak', 'list', 'settings', 'cheatsheet', 'academy', 'guide', 'notifications', 'organizations']));
      // Nothing about a note, a tab or a workspace, because there are none.
      expect(list.any((id) => id.startsWith('note:') || id.startsWith('tab:') || id.startsWith('space:')), isFalse);
    });

    // The iPhone app records nothing yet: App hands no speaking, and none is offered.
    test('offers no speaking where nothing records', () {
      final list = ids(paletteCommands(PaletteWorld(note: n('n1', 'Weekend trip')), doing(Calls(), speaking: false)));
      expect(list, isNot(contains('speak')));
      expect(list, isNot(contains('note:speak')));
      expect(list, containsAll(['new', 'note:view']));
    });

    test("offers a note's own commands only over a note", () {
      final list = ids(paletteCommands(PaletteWorld(note: n('n1', 'Weekend trip'), pinned: true), doing(Calls())));
      expect(list, containsAll(['note:speak', 'note:view', 'note:pin', 'note:archive', 'note:delete', 'note:close']));
    });

    test('says which way a toggle goes, so the label is never a lie', () {
      String label(PaletteWorld world, String id) => of(paletteCommands(world, doing(Calls())), id)!.descriptor.label;
      expect(label(PaletteWorld(note: n('n1', 'A'), pinned: true), 'note:pin'), 'Unpin it from the top');
      expect(label(PaletteWorld(note: n('n1', 'A')), 'note:pin'), 'Pin it to the top');
      expect(label(PaletteWorld(note: n('n1', 'A'), view: 'mixed'), 'note:view'), 'Show it formatted');
      expect(label(PaletteWorld(note: n('n1', 'A'), view: 'formatted'), 'note:view'), 'Show the marks');
    });

    test('never offers what is already so', () {
      const spaces = [(id: 'w1', name: 'Home'), (id: 'w2', name: 'Work')];
      final list = ids(paletteCommands(PaletteWorld(workspaces: spaces, workspace: 'w1', note: n('n1', 'A'), filedIn: 'w2', theme: 'dark'), doing(Calls())));
      // The workspace being shown, and the one the note is already filed in.
      expect(list, isNot(contains('space:w1')));
      expect(list, contains('space:w2'));
      expect(list, isNot(contains('note:file:w2')));
      expect(list, contains('note:file:w1'));
      // The theme it is already on.
      expect(list, isNot(contains('theme:dark')));
      expect(list, contains('theme:light'));
    });

    test('offers the tabs and the trail only when there are any', () {
      final quiet = ids(paletteCommands(const PaletteWorld(), doing(Calls())));
      expect(quiet, isNot(contains('back')));
      expect(quiet, isNot(contains('forward')));

      final busy = ids(paletteCommands(PaletteWorld(tabs: [n('n1', 'A'), n('n2', 'B')], note: n('n1', 'A'), canBack: true, canForward: true), doing(Calls())));
      // The note on screen is not offered as somewhere to go, but the other tab is.
      expect(busy, isNot(contains('tab:n1')));
      expect(busy, containsAll(['tab:n2', 'tab:close:n2', 'back', 'forward']));
    });

    test('offers every note by name, up to a limit, and not the ones already open', () {
      final many = [for (var i = 0; i < mostNotes + 10; i += 1) n('n$i', 'Note $i')];
      final list = ids(paletteCommands(PaletteWorld(notes: many, tabs: [many[0]], note: many[1]), doing(Calls())));
      final byName = list.where((id) => id.startsWith('open:')).toList();
      expect(byName, isNot(contains('open:n0')));
      expect(byName, isNot(contains('open:n1')));
      expect(byName.length, lessThanOrEqualTo(mostNotes));
      expect(byName, contains('open:n2'));
    });

    test('finds any note by name once something is typed, however long ago it changed', () {
      // Forty-five newer notes on top, as adding Ghost.md: The Guide leaves a library.
      final notes = [for (var i = 0; i < 45; i += 1) n('g$i', 'Chapter $i'), n('mine', 'Groceries')];
      List<String> byName(String query) => ids(paletteCommands(PaletteWorld(notes: notes), doing(Calls()), query)).where((id) => id.startsWith('open:')).toList();
      expect(byName(''), isNot(contains('open:mine')));
      expect(byName('groc'), ['open:mine']);
      expect(byName('Open GROCERIES'), ['open:mine']);
      expect(byName('groceries list'), isEmpty);
    });

    test('matches a note the way the kit does, on its group and keywords too, and still offers forty at most', () {
      final many = [for (var i = 0; i < mostNotes + 10; i += 1) n('n$i', 'Note $i')];
      expect(notesByName(many, 'go to'), hasLength(mostNotes));
      expect(notesByName(many, 'by name').first.id, 'n0');
      expect(notesByName(many, '  '), many.sublist(0, mostNotes));
      expect(notesByName([n('u', '')], 'untitled'), [n('u', '')]);
    });

    test('runs what it says it runs', () {
      final calls = Calls();
      final list = paletteCommands(PaletteWorld(note: n('n1', 'A'), workspaces: const [(id: 'w1', name: 'Home')], notes: [n('n9', 'B')]), doing(calls));
      run(list, 'note:speak');
      run(list, 'note:file:w1');
      run(list, 'open:n9');
      run(list, 'theme:light');
      run(list, 'note:view');
      run(list, 'academy');
      run(list, 'notebook');
      expect(calls.said, ['speakInto n1', 'fileNote n1 w1', 'openNote n9', 'setTheme light', 'setView formatted', 'academy', 'newNotebook']);
    });

    test('names a notebook as a notebook, and still finds it by the word book', () {
      final made = of(paletteCommands(const PaletteWorld(), doing(Calls())), 'notebook')!.descriptor;
      expect(made.label, 'New notebook');
      expect(made.keywords, contains('book'));
    });

    test('says Speak an entry for a journal’s mic, which is still its own Talk into this note', () {
      final calls = Calls();
      PaletteCommand on(bool journal) => of(paletteCommands(PaletteWorld(note: n('j', 'Diary', journal: journal)), doing(calls)), 'note:speak')!;
      expect(on(false).descriptor.label, 'Talk into this note');
      expect(on(true).descriptor.label, 'Speak an entry');
      expect(on(true).descriptor.keywords, contains('diary'));
      on(true).run();
      expect(calls.said, ['speakInto j']);
    });

    test('offers a new entry in each of up to three journals, the one written in last first', () {
      final calls = Calls();
      final journals = [for (final (i, title) in ['Diary', 'Dreams', 'Garden', 'Travel'].indexed) n('j$i', title, journal: true)];
      final entries = paletteCommands(PaletteWorld(journals: journals), doing(calls, newEntry: true)).where((c) => c.descriptor.id.startsWith('entry:')).toList();
      expect([for (final c in entries) c.descriptor.label], ['New entry in Diary', 'New entry in Dreams', 'New entry in Garden']);
      expect(entries[0].descriptor.keywords, contains('diary'));
      entries[1].run();
      expect(calls.said, ['newEntry j1']);
      // With nowhere to make one, none.
      expect(paletteCommands(PaletteWorld(journals: journals), doing(Calls())).any((c) => c.descriptor.id.startsWith('entry:')), isFalse);
    });

    test('leaves a journal’s entries out of the notes offered before a word is typed, and finds them when typed for', () {
      final notes = [n('e1', '2026-09-28 14.05', entry: true), n('n1', 'Groceries')];
      expect([for (final note in notesByName(notes)) note.id], ['n1']);
      expect([for (final note in notesByName(notes, '2026-09-28')) note.id], ['e1']);
    });

    test('opens the New notebook sheet on Journal, found by a diary’s words, where the app offers it', () {
      expect(of(paletteCommands(const PaletteWorld(), doing(Calls())), 'journal'), isNull);
      final calls = Calls();
      final made = of(paletteCommands(const PaletteWorld(), doing(calls, newJournal: true)), 'journal')!;
      expect(made.descriptor.label, 'New journal');
      expect(made.descriptor.group, 'Notes');
      expect(made.descriptor.keywords, contains('diary'));
      made.run();
      expect(calls.said, ['newJournal']);
    });

    test('gives every command its own id, so the palette can tell them apart', () {
      final list = ids(paletteCommands(
        PaletteWorld(notes: [n('n1', 'A'), n('n2', 'B')], tabs: [n('n1', 'A')], workspaces: const [(id: 'w1', name: 'Home')], note: n('n2', 'B')),
        doing(Calls()),
      ));
      expect(list.toSet().length, list.length);
    });

    test("offers a phone its tab's groups, where a finger has no right-click", () {
      final calls = Calls();
      final acts = doing(calls, tabGroups: true);
      final tab = n('n1', 'A');
      const groups = [(id: 'g1', name: 'Trip'), (id: 'g2', name: 'Work')];
      final loose = ids(paletteCommands(PaletteWorld(note: tab, tabs: [tab], tabGroups: groups), acts));
      expect(loose, containsAll(['tab:group:new', 'tab:group:g1', 'tab:group:g2']));
      expect(loose, isNot(contains('tab:group:leave')));
      // In a group already: not offered its own group, but offered the way out.
      final grouped = paletteCommands(PaletteWorld(note: tab, tabs: [tab], tabGroups: groups, tabGroup: 'g1'), acts);
      expect(ids(grouped), isNot(contains('tab:group:g1')));
      expect(ids(grouped), contains('tab:group:leave'));
      run(grouped, 'tab:group:g2');
      run(grouped, 'tab:group:leave');
      expect(calls.said, ['joinTabGroup n1 g2', 'leaveTabGroup n1']);
      // A note that isn't open as a tab has no tab to group.
      expect(ids(paletteCommands(PaletteWorld(note: tab, tabGroups: groups), acts)).any((id) => id.startsWith('tab:group')), isFalse);
    });

    test('names a note with no title rather than offering a blank line', () {
      final list = paletteCommands(PaletteWorld(notes: [n('n1', '')]), doing(Calls()));
      expect(of(list, 'open:n1')?.descriptor.label, 'Open Untitled');
    });
  });

  group('the AI on the note on screen (docs/DESIGN.md §145)', () {
    test('offers Fix spelling, Make a list and Continue, and Fill the blanks only with a blank for the model', () {
      final calls = Calls();
      final plain = ids(paletteCommands(PaletteWorld(note: n('n1', 'A')), doing(calls, noteAi: true)));
      expect(plain, containsAll(['note:fix', 'note:shape', 'note:continue']));
      expect(plain, isNot(contains('note:fill')));
      final blanks = paletteCommands(PaletteWorld(note: n('n1', 'A', blanks: 2)), doing(calls, noteAi: true));
      run(blanks, 'note:fill');
      run(blanks, 'note:fix');
      expect(calls.said, ['noteAi n1 fill', 'noteAi n1 fix']);
    });

    test('offers none of them where the app gives no way to run them', () {
      expect(ids(paletteCommands(PaletteWorld(note: n('n1', 'A', blanks: 2)), doing(Calls()))), isNot(contains('note:fill')));
    });
  });

  // Not in palette.test.ts: the doings the web requires and this port lets be absent, each leaving its command out.
  group('the links between notes (lib/links)', () {
    test('the graph of every note among the notes, and a note\'s links and its local graph over it', () {
      final calls = Calls();
      final world = PaletteWorld(notes: [n('a', 'Lisbon')], note: n('a', 'Lisbon'));
      final commands = paletteCommands(world, doing(calls, links: true));
      expect(ids(commands), containsAll(['graph', 'note:links', 'note:graph']));
      expect(of(commands, 'graph')!.descriptor.label, 'Graph of your notes');
      expect(of(commands, 'note:links')!.descriptor.label, 'Links to this note');
      of(commands, 'graph')!.run();
      of(commands, 'note:graph')!.run();
      of(commands, 'note:links')!.run();
      expect(calls.said, ['graph', 'localGraph a', 'noteLinks a']);
      // Without them, no rows: and none of a note's with no note on screen.
      expect(ids(paletteCommands(world, doing(Calls()))), isNot(contains('graph')));
      expect(ids(paletteCommands(const PaletteWorld(), doing(Calls(), links: true))), isNot(contains('note:graph')));
    });
  });

  group('what is not ported yet', () {
    test('has no command, and everything else is as it was', () {
      final calls = Calls();
      final bare = PaletteDoing(
        openNote: (id) => calls('openNote $id'),
        newNote: () => calls('newNote'),
        closeTab: (_) {},
        showList: () {},
        browseNotes: () {},
        back: () {},
        forward: () {},
        settings: () {},
        chooseWorkspace: (_) {},
        fileNote: (_, _) {},
        setTheme: (_) {},
        pin: (_, _) {},
        archive: (_) {},
        remove: (_) {},
      );
      final list = ids(paletteCommands(PaletteWorld(note: n('n1', 'A'), theme: 'dark'), bare));
      expect(list, ['note:pin', 'note:archive', 'note:delete', 'note:close', 'new', 'list', 'notes', 'theme:system', 'theme:light', 'theme:dawn', 'theme:boreal', 'theme:ember', 'settings']);
    });

    test('the whole list, in the web app’s order, with everything given', () {
      final tab = n('t1', 'Tab');
      final list = ids(paletteCommands(
        PaletteWorld(
          notes: [n('a', 'Apples'), tab],
          journals: [n('j', 'Diary', journal: true)],
          tabs: [tab, n('t2', 'Other')],
          workspaces: const [(id: 'w1', name: 'Home'), (id: 'w2', name: 'Work')],
          workspace: 'w1',
          note: n('t1', 'Tab', blanks: 1),
          filedIn: 'w2',
          canBack: true,
          canForward: true,
          tabGroups: const [(id: 'g1', name: 'Trip'), (id: 'g2', name: 'Work')],
          tabGroup: 'g1',
        ),
        doing(Calls(), newJournal: true, newEntry: true, noteAi: true, tabGroups: true),
      ));
      expect(list, [
        'note:speak', 'note:view', 'note:fix', 'note:shape', 'note:continue', 'note:fill', 'note:pin', 'note:archive', 'note:delete', 'note:close', //
        'note:file:w1', 'note:unfile', 'tab:group:new', 'tab:group:g2', 'tab:group:leave', //
        'new', 'notebook', 'journal', 'entry:j', 'speak', 'list', 'notes', //
        'tab:t2', 'tab:close:t2', 'back', 'forward', //
        'space:all', 'space:w2', //
        'open:a', //
        'theme:system', 'theme:light', 'theme:dawn', 'theme:boreal', 'theme:ember', //
        'settings', 'notifications', 'organizations', 'cheatsheet', 'academy', 'guide',
      ]);
    });
  });
}
