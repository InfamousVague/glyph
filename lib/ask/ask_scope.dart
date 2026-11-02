/// Which notes a question is asked of (docs/ASK_THE_ORG.md, "Scope"; Matt, 2026-11-02: "'Ask the org' with receipts:
/// questions answered only from your notes, every claim linked to the note and line it came from"): your own, one
/// organization's, or one folder's, and never two of them at once. The scope is one value, the notes are filtered by
/// it before anything is read, and the answer's citations are held to the same filter (ask_answer.dart).
library;

import 'package:flutter/foundation.dart';

import '../core/note.dart';
import '../core/workspaces.dart';

/// What kind of scope: personal, an organization, a folder.
enum AskScopeKind { mine, org, folder }

/// One scope (see the library's doc).
@immutable
class AskScope {
  const AskScope._(this.kind, this.name, {this.orgId, this.workspaceId});

  /// Every note filed in no organization.
  const AskScope.mine() : this._(AskScopeKind.mine, 'my notes');

  /// The notes of the organization [orgId], called [name].
  const AskScope.org(String orgId, String name) : this._(AskScopeKind.org, name, orgId: orgId);

  /// The notes in the folder [workspaceId] and the folders under it; [orgId] the organization it is in, or null.
  const AskScope.folder(String workspaceId, String name, {String? orgId}) : this._(AskScopeKind.folder, name, workspaceId: workspaceId, orgId: orgId);

  final AskScopeKind kind;

  /// What the sheet calls it: "my notes", "HelloTrade", "Clients".
  final String name;

  /// The organization, for [AskScopeKind.org], and for a folder inside one.
  final String? orgId;

  /// The folder, for [AskScopeKind.folder].
  final String? workspaceId;

  /// "Ask my notes", "Ask HelloTrade".
  String get title => 'Ask $name';

  /// "my notes", "HelloTrade's notes", "the Clients folder".
  String get whose => switch (kind) {
        AskScopeKind.mine => 'your notes',
        AskScopeKind.org => '$name’s notes',
        AskScopeKind.folder => 'the $name folder',
      };

  /// A key for the sheet's chips and its tests: `mine`, `org:o1`, `folder:w-abc`.
  String get key => switch (kind) {
        AskScopeKind.mine => 'mine',
        AskScopeKind.org => 'org:$orgId',
        AskScopeKind.folder => 'folder:$workspaceId',
      };

  @override
  bool operator ==(Object other) => other is AskScope && other.key == key;

  @override
  int get hashCode => key.hashCode;

  @override
  String toString() => 'AskScope($key)';
}

/// What a scope is read against: which organization a note is in, and which folder it is filed in.
class AskWorld {
  const AskWorld({required this.orgOf, required this.folderOf, this.folders = const []});

  /// The workspaces as they are: the organization of a note is its folder's, walking up ([orgOfWorkspace]).
  factory AskWorld.of(Workspaces workspaces, {String? Function(Note note)? orgOfPath}) {
    final list = workspaces.list;
    return AskWorld(
      orgOf: (note) {
        final filed = workspaces.of[note.id];
        if (filed != null) return orgOfWorkspace(list, filed);
        return orgOfPath?.call(note);
      },
      folderOf: (note) => workspaces.of[note.id],
      folders: list,
    );
  }

  /// The organization [note] is in, or null for a personal note.
  final String? Function(Note note) orgOf;

  /// The workspace [note] is filed in, or null.
  final String? Function(Note note) folderOf;

  /// The workspaces, for a folder's family.
  final List<Workspace> folders;
}

/// Whether [note] may be read for a question asked of [scope]: not trashed or archived, and in the scope. A folder in
/// an organization keeps to that organization, so a note filed there whose organization reads otherwise is left out.
bool inAskScope(Note note, AskScope scope, AskWorld world) {
  if (note.inTrash || (note.archivedAt ?? 0) != 0) return false;
  final org = world.orgOf(note);
  switch (scope.kind) {
    case AskScopeKind.mine:
      return org == null;
    case AskScopeKind.org:
      return org != null && org == scope.orgId;
    case AskScopeKind.folder:
      final filed = world.folderOf(note);
      if (filed == null || !workspaceFamily(world.folders, scope.workspaceId!).contains(filed)) return false;
      return org == scope.orgId;
  }
}

/// The notes of [notes] a question asked of [scope] reads (see [inAskScope]).
List<Note> notesInScope(Iterable<Note> notes, AskScope scope, AskWorld world) => [
      for (final note in notes)
        if (inAskScope(note, scope, world)) note,
    ];

/// The scopes the sheet offers: My notes, then each organization this account is in ([orgs], id and name).
List<AskScope> askScopes(List<({String id, String name})> orgs) => [const AskScope.mine(), for (final org in orgs) AskScope.org(org.id, org.name)];

/// The folders the sheet offers behind More: every workspace that is not an organization's own, named with its
/// parents ("Work › Clients"), each keeping the organization it is in.
List<AskScope> askFolders(List<Workspace> list) => [
      for (final w in list)
        if (!isOrgWorkspace(w.id)) AskScope.folder(w.id, workspacePathName(list, w.id), orgId: orgOfWorkspace(list, w.id)),
    ];
