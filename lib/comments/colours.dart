/// Whose colour a comment wears (docs/SHARED.md, S7, S8). A port of `src/app/core/comments/colours.ts`.
///
/// In an organization's workspace, each member's colour there, as the member rows carry it - the account's own from
/// the kept list at once, the others' once the organization has been read this session; anywhere else, and for
/// anyone the rows do not name, the app's ink.
///
/// The members are read with the organization the first time a note of it is open, and kept for the session in
/// memory: a colour is not a secret (S7), but nothing here needs it after the app closes, and the next session
/// reads it fresh. Read best effort: offline, the others are ink until it can be read.
///
/// What differs: the page's hook `useCommentColours(noteId)` gathers four things itself - the note's workspace, the
/// kept list of organizations, the session and what was read. Here the rule is [commentColours], a function of
/// those four, and what was read is [MemberColours], which is given the organization's read (`fetchOrg`, reduced
/// to each member's handle and colour) and whether anyone is signed in. The gathering is ui/note_colours.dart's
/// (`NoteColours`), over the account's services: it asks [MemberColours.read] for the note's organization and
/// calls [commentColours] with what it holds.
library;

import 'package:flutter/foundation.dart';

import '../core/workspaces.dart' show workspaceHues;

/// An organization's members' colours, by handle: what `fetchOrg(id).members` says of each.
typedef MembersRead = Future<Map<String, String?>> Function(String orgId);

/// Each organization's members' colours, by handle, as read this session (`read`, `readMemberColours`,
/// `forgetMemberColours`). Tells its listeners when an organization has been read.
class MemberColours extends ChangeNotifier {
  MemberColours({required bool Function() signedIn, required MembersRead fetch})
      : _signedIn = signedIn,
        _fetch = fetch;

  final bool Function() _signedIn;
  final MembersRead _fetch;
  final Map<String, Map<String, String?>> _read = {};

  /// The organizations asked for, so a note opened twice asks once.
  final Set<String> _asked = {};

  /// What was read of [orgId]'s members; null until it has been.
  Map<String, String?>? of(String? orgId) => orgId == null ? null : _read[orgId];

  /// Reads an organization's members' colours, once a session; a failure is forgotten so the next note asks again
  /// (`readMemberColours`). [fetch] stands in for the one this was made with.
  Future<void> read(String orgId, [MembersRead? fetch]) async {
    if (_asked.contains(orgId) || !_signedIn()) return;
    _asked.add(orgId);
    try {
      final members = await (fetch ?? _fetch)(orgId);
      _read[orgId] = Map.unmodifiable(members);
      notifyListeners();
    } catch (_) {
      _asked.remove(orgId);
    }
  }

  /// Nothing read: for a test, or for signing out (`forgetMemberColours`).
  void forget() {
    _asked.clear();
    if (_read.isEmpty) return;
    _read.clear();
    notifyListeners();
  }
}

/// A colour as a hue the stylesheets know, `ink` for none or one this build does not (`hueOf`).
String hueOf(String? colour) => colour != null && workspaceHues.contains(colour) ? colour : 'ink';

/// Who wears what in a note: a lookup by handle, and a key that changes when any answer would, to redraw by
/// (`CommentColours`).
@immutable
class CommentColours {
  const CommentColours({required this.of, required this.key});

  /// The hue [handle]'s comments wear: one of the workspace hues.
  final String Function(String handle) of;
  final String key;
}

/// The colours for the comments in a note (`useCommentColours`, as a function of what it gathers): [orgId] is the
/// organization whose workspace the note is filed in, or null for none; [handle] the account's own; [mine] the
/// account's colour in that organization, from the kept list; [theirs] what was read of its members
/// ([MemberColours.of]).
CommentColours commentColours({required String? orgId, String? handle, String? mine, Map<String, String?>? theirs}) {
  if (orgId == null) return CommentColours(of: (_) => 'ink', key: '');
  String of(String who) {
    // Your own from the kept list, which a change of your colour updates at once; the others' as the rows said.
    if (handle != null && handle.isNotEmpty && who == handle && mine != null && mine.isNotEmpty) return hueOf(mine);
    return hueOf(theirs?[who]);
  }

  final rows = [for (final MapEntry(:key, :value) in (theirs ?? const <String, String?>{}).entries) '$key:${value ?? ''}'].join(',');
  return CommentColours(of: of, key: '$orgId|${handle ?? ''}:${mine ?? ''}|$rows');
}
