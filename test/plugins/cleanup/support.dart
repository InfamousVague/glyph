// What Cleanup's tests share (docs/CLEANUP.md): an invented library with a personal folder to clean up and an
// organization's, and a scripted AI that answers by the titles it is shown, never a real one. Nobody in it is real.
import 'dart:async';
import 'dart:convert';

import 'package:ghost_md/core/note.dart';
import 'package:ghost_md/core/sample_library.dart';
import 'package:ghost_md/core/trash.dart';
import 'package:ghost_md/core/workspaces.dart';
import 'package:ghost_md/plugins/cleanup/cleanup.dart';

const int cleanupNow = 1792160400000; // 2026-10-16.

Note cleanupNote(String id, String body, {int days = 1, int revision = 1, int? archivedAt}) =>
    Note(id: id, body: body, createdAt: cleanupNow - (days + 1) * 86400000, updatedAt: cleanupNow - days * 86400000, revision: revision, archivedAt: archivedAt);

/// The notes: Work's (a call with no title, invoices, a standup and its shared copy, a messy note, an empty idea, a
/// note others link to), Work › Clients' brief, Home's trip that links the packing list, and the organization's two.
List<Note> cleanupNotes() => [
      cleanupNote('kiln-call', '# Untitled\n\nCall with the Kiln shop about the spring menu prices. They want the new menu by Friday.\n\n- [ ] Send the draft', days: 2),
      cleanupNote('invoice', '# October invoices\n\n- [ ] The bakery\n- [ ] The bike shop', days: 3),
      cleanupNote('standup', '# Standup\n\nShipped the reading view. Next we build the map and then the sync fixes.\n\n- [ ] Fix sync', days: 4),
      cleanupNote('standup-copy', '# Standup (shared)\n\nShipped the reading view. Next we build the map and then the sync fixes.\n\n- [ ] Fix sync\n- [ ] Ask Sam about the map tiles', days: 5),
      cleanupNote('messy', '# Plan\n\n#\n\n### Steps\n\n* one\n- two\n\n## Empty\n\n## Done\n\nAll good.', days: 6),
      cleanupNote('idea', '# Idea\n', days: 90),
      cleanupNote('packing', '# Packing list\n\n- [ ] Boots', days: 7),
      cleanupNote('brief', '# Kiln brief\n\nThe Kiln shop wants a new spring menu.', days: 8),
      cleanupNote('trip', '# Weekend by the coast\n\nSee [[Packing list]].', days: 9),
      cleanupNote('team-plan', '# Team plan\n\nThe goals for the first quarter, agreed on Monday.', days: 2),
      cleanupNote('team-standup', '# Untitled\n\nWhat the team shipped this week: the reading view.', days: 3),
      cleanupNote('old', '# Last year\n\nKept for the record.', days: 300, archivedAt: cleanupNow - 100 * 86400000),
    ];

const OrgLike cleanupOrg = OrgLike(id: 'o1', name: 'Ghost.md', hue: 'sea');

/// The library, the folders and the Trash: Work (with Clients inside), Home, and the organization's workspace with
/// Plans inside it.
class CleanupWorld {
  CleanupWorld() {
    workspaces.ensureOrgWorkspace(cleanupOrg);
    plansId = workspaces.addWorkspace('Plans', 'ink', 'org-o1')!.id;
    for (final id in ['kiln-call', 'invoice', 'standup', 'standup-copy', 'messy', 'idea', 'packing', 'old']) {
      workspaces.fileNote(id, 'work');
    }
    workspaces.fileNote('brief', 'clients');
    workspaces.fileNote('trip', 'home');
    workspaces.fileNote('team-plan', plansId);
    workspaces.fileNote('team-standup', 'org-o1');
  }

  final SampleLibrary library = SampleLibrary(cleanupNotes(), clock: () => cleanupNow);
  final MemoryTrash trash = MemoryTrash();
  late final WorkspaceStore workspaces = WorkspaceStore(
    storage: MemoryWorkspaceStorage(const WorkspaceSheet(list: [
      Workspace(id: 'work', name: 'Work'),
      Workspace(id: 'clients', name: 'Clients', parent: 'work'),
      Workspace(id: 'home', name: 'Home'),
    ])),
    trash: trash,
  );
  late final String plansId;

  CleanupScope scope(String folderId) => cleanupScope(folderId: folderId, workspaces: workspaces, library: library, trash: trash)!;

  CleanupService service({List<CleanupAi>? ais, bool localOnly = false, CleanupRecords? records}) => CleanupService(
        library: library,
        workspaces: workspaces,
        trash: trash,
        records: records ?? CleanupRecords(),
        localOnly: () => localOnly,
        ais: () async => ais ?? [scriptedAi((_, _) => '{}')],
        clock: () => DateTime.fromMillisecondsSinceEpoch(cleanupNow),
      );
}

/// The refs a batch's prompt gives its notes, by title: `“Standup” → n3`. A note with no title is `(no title)`.
Map<String, String> noteRefs(String prompt) => {
      for (final m in RegExp(r'^\[(n\d+)\] (?:“(.*)”|\(no title\)) ·', multiLine: true).allMatches(prompt)) m.group(2) ?? '(no title)': m.group(1)!,
    };

/// The refs a batch's prompt gives its folders, by path: `Work › Clients → f1`.
Map<String, String> folderRefs(String prompt) => {
      for (final m in RegExp(r'^- (f\d+): (.+)$', multiLine: true).allMatches(prompt)) m.group(2)!: m.group(1)!,
    };

/// Each ask a scripted AI was asked.
class Asked {
  Asked(this.system, this.prompt, this.maxTokens);
  final String system;
  final String prompt;
  final int maxTokens;
}

/// An AI that answers [answer] for each ask, and keeps what it was asked in [asked]. Never a real one.
CleanupAi scriptedAi(String Function(String system, String prompt) answer, {String id = 'fake', String name = 'Fake AI', bool local = false, List<Asked>? asked, Future<void>? hold}) => CleanupAi(
      id: id,
      name: name,
      local: local,
      model: 'fake-1',
      ask: (system, prompt, {required maxTokens}) {
        asked?.add(Asked(system, prompt, maxTokens));
        var cancelled = false;
        final done = Future<String>(() async {
          if (hold != null) await hold;
          if (cancelled) throw StateError('cancelled');
          return answer(system, prompt);
        });
        return CleanupAsking(done, () => cancelled = true);
      },
    );

/// The JSON an AI answers with.
String answerJson(Map<String, Object?> plan) => jsonEncode(plan);
