import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_facts.dart' show NoteFacts;
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/page_tree.dart';
import 'package:ghost_md/core/query/read.dart' show readQuery;
import 'package:ghost_md/core/query/fence.dart' show queryFencesIn;
import 'package:ghost_md/core/workspaces.dart';

import '../library/support.dart';

/// The page tree (lib/core/page_tree.dart; docs/TEAMSPACES.md): folders and their `index.md` pages, `order:`,
/// notebooks' chapters, breadcrumbs, reading order, the spaces, a teamspace's settings, a drag's plans and their
/// writing, and what 5,000 notes cost.
void main() {
  var clock = 0;
  Note at(String id, String path, [String? body]) => Note(id: id, body: body ?? '# ${path.split('/').last.replaceAll('.md', '')}\n', createdAt: 0, updatedAt: clock += 1, path: path);

  List<String> titles(Iterable<PageNode> nodes) => [for (final n in nodes) n.title];

  const work = Workspace(id: 'w-work', name: 'Work');
  const home = Workspace(id: 'w-home', name: 'Home');
  const acme = Workspace(id: 'org-acme', name: 'Acme', hue: 'sea');
  const clients = Workspace(id: 'w-clients', name: 'Clients', parent: 'org-acme');
  final spaces = [home, work, acme, clients];

  group('the hierarchy', () {
    final notes = [
      at('loose', 'Inbox/Loose.md'),
      at('plan', 'workspaces/Work/Plan/index.md', '# Plan\n\nThe plan.'),
      at('step1', 'workspaces/Work/Plan/Step one.md'),
      at('step2', 'workspaces/Work/Plan/Step two.md'),
      at('deep', 'workspaces/Work/Plan/Sub/Deep.md'),
      at('standup', 'workspaces/Work/Standup.md'),
      at('trip', 'workspaces/Home/Trip.md'),
      at('vault', 'Projects/Garden.md'),
      at('top', 'Top.md'),
      at('gone', '.trash/Inbox/Gone.md'),
      Note(id: 'archived', body: '# Old', createdAt: 0, updatedAt: 0, path: 'Inbox/Old.md', archivedAt: 5),
      const Note(id: 'draft', body: '', createdAt: 0, updatedAt: 0),
    ];
    final tree = PageTree.build(notes, workspaces: spaces);
    final personal = tree.spaces.first;

    test('Personal is the inbox, then the workspaces in their order, then the rest by title', () {
      expect(titles(tree.rootsOf(personal)), ['Inbox', 'Home', 'Work', 'Projects', 'Top']);
      expect(tree.rootsOf(personal).first.isPlainFolder, isTrue);
    });

    test("a folder's index.md is the folder's page, and its children are the folder's notes and folders", () {
      final plan = tree.nodeOf('plan')!;
      expect((plan.folder, plan.isFolder, plan.isPlainFolder), ('workspaces/Work/Plan', true, false));
      expect(titles(plan.children), ['Step one', 'Step two', 'Sub']);
      final sub = plan.children.last;
      expect((sub.isPlainFolder, sub.folder), (true, 'workspaces/Work/Plan/Sub'));
      expect(titles(sub.children), ['Deep']);
      expect(identical(tree.folderNode('workspaces/Work/Plan'), plan), isTrue);
      expect(titles(tree.folderNode('workspaces/Work')!.children), ['Plan', 'Standup']);
    });

    test('the trash, the archive and drafts are not in it', () {
      expect([tree.nodeOf('gone'), tree.nodeOf('archived'), tree.nodeOf('draft')], [null, null, null]);
      expect(titles(tree.folderNode('Inbox')!.children), ['Loose']);
    });

    test('depth, parent and breadcrumbs', () {
      final deep = tree.nodeOf('deep')!;
      expect(deep.depth, 3);
      expect(titles(deep.ancestors), ['Work', 'Plan', 'Sub']);
      expect(deep.parent!.title, 'Sub');
      expect(tree.folderNode('workspaces/Work')!.parent, isNull);
      expect(tree.folderNode('workspaces/Work')!.depth, 0);
    });

    test('previous and next follow reading order, depth first, plain folders passed over', () {
      expect(titles(tree.readingOrder(personal)), ['Inbox', 'Loose', 'Home', 'Trip', 'Work', 'Plan', 'Step one', 'Step two', 'Sub', 'Deep', 'Standup', 'Projects', 'Garden', 'Top']);
      final standup = tree.nodeOf('standup')!;
      expect(standup.previous!.title, 'Deep');
      expect(standup.next!.title, 'Garden');
      expect(tree.nodeOf('loose')!.previous, isNull);
      expect(tree.nodeOf('top')!.next, isNull);
      expect(tree.nodeOf('step2')!.next!.title, 'Deep', reason: 'Sub is a plain folder');
    });

    test('a folder with no index.md takes a note named as itself for its page', () {
      final named = PageTree.build([at('p', 'Inbox/Plan/Plan.md'), at('c', 'Inbox/Plan/Child.md')]);
      final plan = named.nodeOf('p')!;
      expect(plan.folder, 'Inbox/Plan');
      expect(titles(plan.children), ['Child']);
    });

    test('a workspace with no notes yet is a folder of its own', () {
      final empty = PageTree.build(const [], workspaces: [work]);
      expect(titles(empty.rootsOf(empty.spaces.first)), ['Inbox', 'Work']);
    });

    test("an icon is the page's icon:, an emoji, a shortcode or an icon's name", () {
      final icons = PageTree.build([
        at('a', 'Inbox/A.md', '---\nicon: 🚀\n---\n# A\n'),
        at('b', 'Inbox/B.md', '---\nicon: ":tada:"\n---\n# B\n'),
        at('c', 'Inbox/C.md', '---\nicon: book-open\n---\n# C\n'),
        at('d', 'Inbox/D.md'),
      ]);
      expect(icons.nodeOf('a')!.icon!.emoji, '🚀');
      expect(icons.nodeOf('b')!.icon!.emoji, '🎉');
      expect((icons.nodeOf('c')!.icon!.emoji, icons.nodeOf('c')!.icon!.name), (null, 'book-open'));
      expect(icons.nodeOf('d')!.icon, isNull);
    });
  });

  group('order:', () {
    PageTree withOrder(String order) => PageTree.build([
          at('plan', 'Inbox/Plan/index.md', '---\n$order\n---\n# Plan\n'),
          at('a', 'Inbox/Plan/Alpha.md'),
          at('b', 'Inbox/Plan/Beta.md'),
          at('c', 'Inbox/Plan/Gamma.md'),
          at('d', 'Inbox/Plan/Docs/Readme.md'),
        ]);

    test('names first in its order, the rest by title, folders and notes together', () {
      expect(titles(withOrder('order: [Gamma, Docs]').nodeOf('plan')!.children), ['Gamma', 'Docs', 'Alpha', 'Beta']);
    });

    test('read written across, with commas, as lines, as links and as file names', () {
      expect(titles(withOrder('order: Beta, Gamma').nodeOf('plan')!.children), ['Beta', 'Gamma', 'Alpha', 'Docs']);
      expect(titles(withOrder('order:\n  - Docs\n  - "Beta"').nodeOf('plan')!.children), ['Docs', 'Beta', 'Alpha', 'Gamma']);
      expect(titles(withOrder('order: ["[[Gamma]]", "[[Alpha]]"]').nodeOf('plan')!.children), ['Gamma', 'Alpha', 'Beta', 'Docs']);
      expect(titles(withOrder('order: [Gamma.md, Nothing, Gamma]').nodeOf('plan')!.children), ['Gamma', 'Alpha', 'Beta', 'Docs']);
    });

    test('a drop gives the whole folder its order, and the page written with it reads back so', () {
      final tree = withOrder('title: Plan');
      final plan = tree.nodeOf('plan')!;
      final beta = tree.nodeOf('b')!;
      final order = orderAfterDrop(plan.children, beta, 0);
      expect(order, ['Beta', 'Alpha', 'Docs', 'Gamma']);
      expect(orderAfterDrop(plan.children, beta, 99), ['Alpha', 'Docs', 'Gamma', 'Beta']);
      final body = withPageOrder(plan.note!.body, order);
      expect(body, '---\ntitle: Plan\norder: [Beta, Alpha, Docs, Gamma]\n---\n# Plan\n');
      final again = PageTree.build([for (final n in [plan.note!, tree.nodeOf('a')!.note!, beta.note!, tree.nodeOf('c')!.note!, tree.nodeOf('d')!.note!]) n.id == 'plan' ? n.copyWith(body: body) : n]);
      expect(titles(again.nodeOf('plan')!.children), ['Beta', 'Alpha', 'Docs', 'Gamma']);
    });

    test('a list written as lines is replaced whole, and quoted where a title needs it', () {
      expect(withPageOrder('---\norder:\n  - A\n  - B\nicon: x\n---\nwords', ['B', 'Q4, the rest']), '---\norder: [B, "Q4, the rest"]\nicon: x\n---\nwords');
      expect(frontMatterList('---\norder: [B, "Q4, the rest"]\n---\n', 'order'), ['B', 'Q4, the rest']);
      expect(withPageOrder('# Plan\n', const []), '# Plan\n');
      expect(folderPageBody('Plan', order: ['A']), '---\norder: [A]\n---\n# Plan\n');
    });
  });

  group('notebooks', () {
    final book = '---\nbook: true\n---\n# Book\n\n- [[One]]\n- [[Two]]\n  - [[Two a]]\n- [[Nowhere]]\n- [[Book]]\n';
    final tree = PageTree.build([
      at('book', 'Inbox/Book.md', book),
      at('one', 'Inbox/One.md'),
      at('two', 'workspaces/Work/Two.md'),
      at('twoa', 'Inbox/Two a.md'),
      at('other', 'Inbox/Other.md'),
      at('far', 'orgs/Acme/One more.md'),
    ], workspaces: spaces);

    test("a notebook's chapters are its children in the index's order, an indented one under the one before", () {
      final node = tree.nodeOf('book')!;
      expect(node.isNotebook, isTrue);
      expect(titles(node.children), ['One', 'Two']);
      expect(titles(tree.nodeOf('two')!.children), ['Two a']);
      expect(tree.nodeOf('twoa')!.depth, 3);
      expect(titles(tree.nodeOf('twoa')!.ancestors), ['Inbox', 'Book', 'Two']);
      expect(tree.nodeOf('one')!.isChapter, isTrue);
    });

    test('a chapter is drawn under its notebook only, wherever its file is', () {
      expect(titles(tree.folderNode('Inbox')!.children), ['Book', 'Other']);
      expect(tree.folderNode('workspaces/Work')!.children, isEmpty);
    });

    test('a notebook never holds itself, nor a page above it, nor one in another space', () {
      final loop = PageTree.build([
        at('a', 'Inbox/A/index.md', '---\nbook: true\n---\n# A\n\n- [[B]]\n'),
        at('b', 'Inbox/A/B.md', '---\nbook: true\n---\n# B\n\n- [[A]]\n'),
      ]);
      expect(titles(loop.nodeOf('a')!.children), ['B']);
      expect(loop.nodeOf('b')!.children, isEmpty);
      final cross = PageTree.build([at('k', 'Inbox/K.md', '---\nbook: true\n---\n# K\n\n- [[Deal]]\n'), at('deal', 'orgs/Acme/Deal.md')], workspaces: spaces);
      expect(cross.nodeOf('k')!.children, isEmpty);
      expect(cross.nodeOf('deal')!.parent, isNull);
    });
  });

  group('spaces', () {
    final tree = PageTree.build([
      at('home', 'orgs/Acme/Home.md', '---\ntitle: Home\ntype: teamspace\ndocs: read\npins: ["[[Onboarding]]", "[[Roadmap]]"]\nicon: 🏠\n---\n# Acme\n'),
      at('onboard', 'orgs/Acme/Onboarding.md'),
      at('deal', 'orgs/Acme/Clients/Deal.md'),
      at('lost', 'orgs/Gone/Lost.md'),
      at('mine', 'Inbox/Mine.md'),
    ], workspaces: spaces);

    test('Personal, then each organization this device has a workspace for', () {
      expect(tree.spaces, const [Space.personal(), Space.organization(orgId: 'acme', name: 'Acme', folder: 'orgs/Acme', hue: 'sea')]);
      expect([for (final s in tree.spaces) s.id], [personalSpaceId, 'org-acme']);
      expect(tree.spaces.last.homePath, 'orgs/Acme/Home.md');
    });

    test("an organization's roots are its folder, its Home.md the space's home and no row", () {
      final org = tree.spaces.last;
      expect(titles(tree.rootsOf(org)), ['Clients', 'Onboarding']);
      expect(tree.homeOf(org)!.id, 'home');
      expect(tree.spaceRoot(org)!.note!.id, 'home');
      expect(tree.nodeOf('home'), same(tree.spaceRoot(org)));
      expect(tree.nodeOf('onboard')!.parent, isNull);
      expect(tree.containerOf(tree.nodeOf('onboard')!), same(tree.spaceRoot(org)));
      expect(tree.spaceOf('deal'), org);
      expect(tree.homeOf(tree.spaces.first), isNull);
    });

    test('an organization this device does not know is in no space yet', () {
      expect(tree.nodeOf('lost'), isNull);
      expect(titles(tree.rootsOf(tree.spaces.first)), ['Inbox', 'Home', 'Work'], reason: 'orgs/ is never Personal');
    });

    test('a home page is found by type: teamspace where its file was renamed after its title', () {
      final renamed = PageTree.build([at('h', 'orgs/Acme/Acme.md', '---\ntype: teamspace\n---\n# Acme\n'), at('x', 'orgs/Acme/X.md')], workspaces: spaces);
      expect(renamed.homeOf(renamed.spaces.last)!.id, 'h');
      expect(titles(renamed.rootsOf(renamed.spaces.last)), ['Clients', 'X']);
    });

    test("the home page's settings, and the defaults", () {
      final org = tree.spaces.last;
      final settings = tree.settingsOf(org);
      expect((settings.isTeamspace, settings.docs, settings.icon!.emoji), (true, DocsMode.read, '🏠'));
      expect(settings.pinned, ['Onboarding', 'Roadmap']);
      expect(tree.settingsOf(tree.spaces.first), TeamspaceSettings.personal);
      expect(TeamspaceSettings.personal.docs, DocsMode.edit);
      expect(TeamspaceSettings.of(null), const TeamspaceSettings());
      expect(TeamspaceSettings.of('---\ndocs: maybe\n---\n').docs, DocsMode.edit);
      expect(TeamspaceSettings.of('---\ndocs: Edit\n---\n').docs, DocsMode.edit);
      expect(TeamspaceSettings.of('---\npinned: ["[[A]]", "[[B]]"]\n---\n').pinned, ['A', 'B'], reason: "Matt's key, read where it is a list");
      expect(TeamspaceSettings.of('---\npinned: true\n---\n').pinned, isEmpty, reason: "the library's pin is no list");
      expect(TeamspaceSettings.of('---\npins:\n  - "[[A]]"\n  - B\n---\n').pinned, ['A', 'B']);
    });

    test("a new organization's home page reads back as its settings, and its queries read", () {
      final body = teamspaceHomeBody('Acme');
      final settings = TeamspaceSettings.of(body);
      expect((settings.isTeamspace, settings.docs, settings.icon!.emoji), (true, DocsMode.edit, '🏠'));
      expect(TeamspaceSettings.of(teamspaceHomeBody('Acme', docs: DocsMode.read)).docs, DocsMode.read);
      // With no project tools chosen, no plugins: and only the recent changes (docs/PM_PLUGINS.md).
      expect(settings.plugins, isEmpty);
      expect(body, isNot(contains('plugins:')));
      expect(queryFencesIn(body), hasLength(1));
      final ticketed = teamspaceHomeBody('Acme', plugins: ['gantt', 'time-tracking']);
      expect(ticketed, contains('plugins: [tickets, gantt, time-tracking]\n'), reason: 'what a tool needs is written with it, in the suite’s order');
      expect(TeamspaceSettings.of(ticketed).plugins, {'tickets', 'gantt', 'time-tracking'});
      final fences = queryFencesIn(ticketed);
      expect(fences, hasLength(2), reason: 'the open tickets, with Tickets on');
      for (final fence in fences) {
        expect(readQuery(fence.body).problem, isNull, reason: fence.body);
      }
      final made = PageTree.build([at('h', 'orgs/Acme/Home.md', body)], workspaces: spaces);
      expect(made.nodeOf('h')!.title, 'Home', reason: 'titled Home, so the app names its file Home.md');
    });

    test('a home page’s plugins: are the team’s project tools, written and read back', () {
      final home = teamspaceHomeBody('Acme');
      final on = withProjectPlugins(home, ['planning', 'boards']);
      expect(on, contains('plugins: [tickets, planning, boards]\n'));
      expect(TeamspaceSettings.of(on).plugins, {'tickets', 'planning', 'boards'});
      // Every other line as it was.
      expect(on.replaceFirst('plugins: [tickets, planning, boards]\n', ''), home);
      expect(withProjectPlugins(on, const []), home, reason: 'none takes the key off');
      // A list written by hand under the key, a dependent without Tickets, and a word that is no tool's.
      const byHand = '---\ntype: teamspace\nplugins:\n  - planning\n  - gantt\n  - sparkles\n---\n# Acme\n';
      expect(TeamspaceSettings.of(byHand).plugins, {'gantt'}, reason: 'Planning stands on Tickets, which is not on');
      expect(withProjectPlugins(byHand, ['gantt']), '---\ntype: teamspace\nplugins: [gantt]\n---\n# Acme\n');
    });
  });

  group('a move into another page', () {
    final tree = PageTree.build([
      at('plan', 'workspaces/Work/Plan.md'),
      at('spec', 'workspaces/Work/Spec.md'),
      at('docs', 'workspaces/Work/Docs/index.md', '# Docs\n'),
      at('readme', 'workspaces/Work/Docs/Spec.md'),
      at('loose', 'Inbox/Loose.md'),
      at('deal', 'orgs/Acme/Deal.md'),
    ], workspaces: spaces);
    PageNode node(String id) => tree.nodeOf(id)!;

    test('into a plain note: the note becomes its folder\'s index.md first, then the file goes in beside it', () {
      final plan = planMoveInto(tree, node('spec'), node('plan'));
      expect(plan.ok, isTrue);
      expect(plan.folder, 'workspaces/Work/Plan');
      expect(plan.moves, const [
        PageMove('plan', 'workspaces/Work/Plan.md', 'workspaces/Work/Plan/index.md'),
        PageMove('spec', 'workspaces/Work/Spec.md', 'workspaces/Work/Plan/Spec.md'),
      ]);
    });

    test("into a folder's page, a name taken there is given the next free one", () {
      expect(planMoveInto(tree, node('spec'), node('docs')).moves, const [PageMove('spec', 'workspaces/Work/Spec.md', 'workspaces/Work/Docs/Spec 2.md')]);
      expect(planMoveInto(tree, node('loose'), tree.folderNode('workspaces/Work')!).moves, const [PageMove('loose', 'Inbox/Loose.md', 'workspaces/Work/Loose.md')]);
    });

    test("a plain note whose folder name has a page already gets the next folder's name", () {
      final taken = PageTree.build([at('p', 'Inbox/Plan.md'), at('pi', 'Inbox/Plan/index.md', '# Plan proper\n'), at('x', 'Inbox/X.md')]);
      expect(planMoveInto(taken, taken.nodeOf('x')!, taken.nodeOf('p')!).moves.first.to, 'Inbox/Plan 2/index.md');
    });

    test('what is refused', () {
      expect(planMoveInto(tree, node('docs'), node('plan')).refused, MoveRefusal.isFolder);
      expect(planMoveInto(tree, node('plan'), node('plan')).refused, MoveRefusal.intoItself);
      expect(planMoveInto(tree, node('deal'), node('plan')).refused, MoveRefusal.acrossSpaces);
      expect(planMoveInto(tree, node('readme'), node('docs')).refused, MoveRefusal.alreadyThere);
      expect(planMoveInto(tree, node('loose'), tree.spaceRoot(tree.spaces.first)!).refused, MoveRefusal.noFolder);
      final book = PageTree.build([at('b', 'Inbox/B.md', '---\nbook: true\n---\n# B\n\n- [[C]]\n'), at('c', 'Inbox/C.md')]);
      expect(planMoveInto(book, book.nodeOf('b')!, book.nodeOf('c')!).refused, MoveRefusal.intoItself);
    });

    test('the top of an organization is its folder', () {
      final org = PageTree.build([at('a', 'orgs/Acme/Clients/A.md'), at('b', 'orgs/Acme/B.md')], workspaces: spaces);
      expect(planMoveInto(org, org.nodeOf('a')!, org.spaceRoot(org.spaces.last)!).moves, const [PageMove('a', 'orgs/Acme/Clients/A.md', 'orgs/Acme/A.md')]);
    });
  });

  group('the mover', () {
    Future<({FakeCore core, PageMover mover, WorkspaceStore workspaces, ValueListenable<List<Note>> notes})> over(void Function(FakeCore core) seed) async {
      final (:core, :library, waits: _, said: _) = libraryOver();
      seed(core);
      await library.load();
      late final WorkspaceStore workspaces;
      final folders = NoteFolders(library, workspaces: () => workspaces.value.list);
      workspaces = WorkspaceStore(onFiled: folders.fileNotesInFolder);
      return (core: core, mover: PageMover(library: library, workspaces: workspaces), workspaces: workspaces, notes: library);
    }

    Future<void> settle() async {
      for (var i = 0; i < 6; i += 1) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('makes a plain note a folder page, moves the page in beside it with its versions, and files both there', () async {
      final (:core, :mover, :workspaces, :notes) = await over((core) {
        core
          ..seed('plan', '# Plan\n', path: 'workspaces/Work/Plan.md')
          ..seed('spec', '# Spec\n', path: 'workspaces/Work/Spec.md');
      });
      final workId = workspaces.addWorkspace('Work')!.id;
      workspaces.fileNotes(['plan', 'spec'], workId);
      await settle();
      await core.invoke('versions_write', {'id': 'spec', 'text': 'v1 2026-10-31T00:00:00Z matt 0\n'});
      final tree = PageTree.build(notes.value, workspaces: workspaces.value.list);
      final plan = planMoveInto(tree, tree.nodeOf('spec')!, tree.nodeOf('plan')!);
      expect(await mover.run(plan), isTrue);
      await settle();
      expect(core.files, ['workspaces/Work/Plan/Spec.md', 'workspaces/Work/Plan/index.md']);
      expect(core.versionsFiles.keys, ['workspaces/Work/Plan/Spec.versions']);
      final folder = workspaces.workspaceOf('spec')!;
      expect((folder.name, folder.parent, workspaces.workspaceOf('plan')), ('Plan', workId, folder));
      final after = PageTree.build(notes.value, workspaces: workspaces.value.list);
      expect(titles(after.nodeOf('plan')!.children), ['Spec']);
      expect(await mover.run(plan), isFalse, reason: 'the plan is stale once its notes moved');
    });

    test("writes a folder's order over its page, and makes a plain folder's page to hold it", () async {
      final (:core, :mover, :workspaces, :notes) = await over((core) {
        core
          ..seed('plan', '# Plan\n', path: 'Inbox/Plan/index.md')
          ..seed('a', '# A\n', path: 'Inbox/Plan/A.md')
          ..seed('b', '# B\n', path: 'Inbox/Plan/B.md')
          ..seed('c', '# C\n', path: 'Inbox/Box/C.md')
          ..seed('d', '# D\n', path: 'Inbox/Box/D.md');
      });
      var tree = PageTree.build(notes.value);
      final plan = tree.nodeOf('plan')!;
      expect(await mover.setOrder(plan, orderAfterDrop(plan.children, tree.nodeOf('b')!, 0)), isTrue);
      final box = tree.folderNode('Inbox/Box')!;
      expect(await mover.setOrder(box, orderAfterDrop(box.children, tree.nodeOf('d')!, 0)), isTrue);
      await settle();
      tree = PageTree.build(notes.value);
      expect(titles(tree.nodeOf('plan')!.children), ['B', 'A']);
      expect(titles(tree.folderNode('Inbox/Box')!.children), ['D', 'C']);
      expect(tree.folderNode('Inbox/Box')!.isPlainFolder, isFalse);
      expect(core.files, contains('Inbox/Box/index.md'));
      expect(workspaces.value.list, isEmpty, reason: 'a folder under the inbox is no workspace');
      expect(await mover.setOrder(tree.spaceRoot(tree.spaces.first)!, const ['Inbox']), isFalse);
    });
  });

  group('the watch', () {
    test("tells its listeners when the tree's shape changes, and keeps the tree through an edit of words", () {
      final notes = ValueNotifier<List<Note>>([at('a', 'Inbox/A.md', '# A\n\nwords'), at('b', 'Inbox/B.md')]);
      final workspaces = ValueNotifier<Workspaces>(const Workspaces());
      final watch = PageTreeWatch(notes, workspaces);
      var told = 0;
      watch.addListener(() => told += 1);
      expect(watch.debugBuilt, 0, reason: 'built when asked');
      final first = watch.value;
      expect(titles(first.rootsOf(first.spaces.first).first.children), ['A', 'B']);

      notes.value = [notes.value.first.copyWith(body: '# A\n\nother words'), notes.value.last];
      expect((told, identical(watch.value, first), watch.debugBuilt), (0, true, 1));

      notes.value = [notes.value.first.copyWith(body: '# Z\n\nother words'), notes.value.last];
      expect(told, 1);
      expect(titles(watch.value.folderNode('Inbox')!.children), ['B', 'Z']);

      notes.value = [...notes.value, at('c', 'Inbox/C.md')];
      workspaces.value = const Workspaces(list: [work]);
      expect(told, 3);
      expect(titles(watch.value.rootsOf(watch.value.spaces.first)), ['Inbox', 'Work']);
      watch.dispose();
    });
  });

  test('5,000 notes in 300 folders across three spaces', () {
    final notes = <Note>[];
    final orgs = [acme, const Workspace(id: 'org-beta', name: 'Beta')];
    for (var i = 0; i < 5000; i += 1) {
      final folder = switch (i % 3) {
        0 => 'workspaces/Work/F${i % 100}',
        1 => 'orgs/Acme/T${i % 100}/S${i % 7}',
        _ => 'orgs/Beta/D${i % 100}',
      };
      final page = i < 300;
      final body = page ? '---\norder: [N${i + 300}, N${i + 600}]\nicon: 📄\n---\n# Folder $i\n' : (i % 250 == 0 ? '---\nbook: true\n---\n# N$i\n\n- [[N${i + 3}]]\n- [[N${i + 6}]]\n' : '# N$i\n\nwords $i');
      notes.add(Note(id: 'n$i', body: body, createdAt: 0, updatedAt: i, path: page ? '$folder/index.md' : '$folder/N$i.md'));
    }
    final all = [work, ...orgs];
    NoteFacts.debugForget();
    final cold = Stopwatch()..start();
    final tree = PageTree.build(notes, workspaces: all);
    cold.stop();
    final warm = Stopwatch()..start();
    PageTree.build(notes, workspaces: all);
    warm.stop();
    final rows = [for (final space in tree.spaces) tree.readingOrder(space).length].fold(0, (a, b) => a + b);
    // ignore: avoid_print
    print('page tree: 5,000 notes, $rows rows, built in ${cold.elapsedMilliseconds} ms cold, ${warm.elapsedMilliseconds} ms with facts kept');
    expect(tree.spaces, hasLength(3));
    expect(rows, greaterThan(5000));
    expect(tree.nodeOf('n4999'), isNotNull);
    // Generous, for a loaded machine: the point is that it is not seconds.
    expect(cold.elapsedMilliseconds, lessThan(3000));
  });
}
