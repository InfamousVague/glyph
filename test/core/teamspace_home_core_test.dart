// An organization's home page found and made (lib/core/page_tree.dart `teamspaceHomeIn`, `spaceOfOrg`,
// `PageMover.createHome`; docs/TEAMSPACES.md, "Teamspace home"): the dashboard finds it among the notes as the tree
// does, without building the tree, and Create the home page writes `orgs/<Org>/Home.md` from the template over the
// library's own move, filed in the organization's workspace so the team has it.
import 'package:flutter_test/flutter_test.dart';
import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/note_folders.dart';
import 'package:ghost_md/core/page_tree.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/orgs/orgs.dart' show OrgRow;

import '../library/support.dart';

Note at(String id, String path, [String body = '# Page\n']) => Note(id: id, body: body, createdAt: 0, updatedAt: 0, path: path);

void main() {
  const acme = Workspace(id: 'org-acme', name: 'Acme', hue: 'sea');

  test('the home page is found as the tree finds it, and the space by its organization', () {
    final space = spaceOfOrg(const [acme], 'acme')!;
    expect(space.folder, 'orgs/Acme');
    expect(spaceOfOrg(const [acme], 'beta'), isNull);
    final notes = [at('a', 'orgs/Acme/Plan.md'), at('h', 'orgs/Acme/Home.md'), at('x', 'orgs/Acme/Sub/Home.md')];
    expect(teamspaceHomeIn(notes, space)?.id, 'h');
    expect(teamspaceHomeIn([at('t', 'orgs/Acme/Welcome.md', '---\ntype: teamspace\n---\n# Welcome\n')], space)?.id, 't');
    expect(teamspaceHomeIn([at('a', 'orgs/Acme/Plan.md')], space), isNull);
    final tree = PageTree.build(notes, workspaces: const [acme]);
    expect(tree.homeOf(space)?.id, teamspaceHomeIn(notes, space)?.id, reason: 'the same answer as the tree');
  });

  test('Create the home page writes Home.md from the template in the organization’s folder, filed in it', () async {
    final (:core, :library, waits: _, said: _) = libraryOver();
    await library.load();
    late final WorkspaceStore workspaces;
    final folders = NoteFolders(library, workspaces: () => workspaces.value.list);
    workspaces = WorkspaceStore(onFiled: folders.fileNotesInFolder);
    workspaces.ensureOrgWorkspace(const OrgRow(id: 'acme', name: 'Acme', role: 'owner', state: 'member'));
    final space = spaceOfOrg(workspaces.value.list, 'acme')!;
    final made = await PageMover(library: library, workspaces: workspaces).createHome(space, docs: DocsMode.read);
    expect(made, isNotNull);
    expect(made!.path, 'orgs/Acme/Home.md');
    expect(core.files, contains('orgs/Acme/Home.md'));
    expect(workspaces.workspaceOf(made.id)?.id, 'org-acme');
    final settings = TeamspaceSettings.of(made.body);
    expect((settings.isTeamspace, settings.docs), (true, DocsMode.read));
    expect(await PageMover(library: library, workspaces: workspaces).createHome(const Space.personal()), isNull);
  });
}
