/// Whose colour a comment wears in one note, gathered where the page's hook gathered it (`useCommentColours`,
/// `src/app/core/comments/colours.ts`): the note's workspace, the kept list of organizations, the session and what
/// was read of the organization's members this session. lib/comments/colours.dart is the rule; this is the
/// gathering, which waited for the organizations (docs/STAGE7.md, piece H).
///
/// What differs: the members read this session are one [MemberColours] to an account's services
/// ([memberColoursOf]), made the first time a note asks and forgotten when the account signs out, where the page
/// kept a module's store.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../account/ui_state.dart';
import '../../core/workspaces.dart' show orgOfWorkspace;
import '../colours.dart';

final Expando<MemberColours> _read = Expando<MemberColours>('member colours');

/// What was read of each organization's members' colours this session, for [services]' account.
MemberColours memberColoursOf(AccountServices services) => _read[services] ??= () {
      final colours = MemberColours(
        signedIn: () => services.signedIn,
        fetch: (orgId) async {
          final org = await services.orgs!.fetchOrg(orgId);
          return {for (final member in org.members) member.handle: member.colour};
        },
      );
      // Another account's members are not this one's (`forgetMemberColours`).
      services.account.addListener(() {
        if (!services.signedIn) colours.forget();
      });
      return colours;
    }();

/// The organization a note is filed in, or null for a note that is not a team's.
String? orgOfNote(AccountServices? services, String noteId) {
  final spaces = services?.workspaces;
  final space = spaces?.workspaceOf(noteId);
  return space == null ? null : orgOfWorkspace(spaces!.value.list, space.id);
}

/// The colours for the comments in one note, followed as it is filed, the list changes and the members are read.
/// [onChange] is told whenever an answer may have changed; [now] is the answer as it stands.
class NoteColours {
  NoteColours(this.services, this.noteId, {required this.onChange}) {
    final services = this.services;
    if (services == null) return;
    _heard = Listenable.merge(<Listenable?>[services.changes, memberColoursOf(services), services.workspaces])..addListener(_changed);
  }

  final AccountServices? services;
  final String noteId;
  final VoidCallback onChange;
  Listenable? _heard;
  CommentColours? _now;

  void _changed() {
    _now = null;
    onChange();
  }

  CommentColours get now => _now ??= _gather();

  CommentColours _gather() {
    final services = this.services;
    final orgId = orgOfNote(services, noteId);
    if (services == null || orgId == null) return commentColours(orgId: null);
    final read = memberColoursOf(services);
    // Read with the organization the first time a note of it is open; best effort, and once a session.
    if (services.orgs != null) unawaited(read.read(orgId));
    return commentColours(orgId: orgId, handle: services.session?.handle, mine: services.orgs?.orgRow(orgId)?.colour, theirs: read.of(orgId));
  }

  void dispose() => _heard?.removeListener(_changed);
}
