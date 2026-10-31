/// One note's mentions, as its desk holds them (lib/root/note_desk.dart): the editor's extension, the picker and
/// who can be named, from where the note is filed. A team's note names its organization's members, each in the hue
/// they wear there, as the comments' colours have it (lib/comments/ui/note_colours.dart); a note of the person's own
/// names only them, in the quiet ink.
library;

import 'package:flutter/foundation.dart';

import '../../account/ui_state.dart';
import '../../comments/colours.dart' show CommentColours, hueOf;
import '../../comments/ui/note_colours.dart' show memberColoursOf, orgOfNote;
import '../../editor/editor.dart';
import '../../editor/items/mentions.dart';
import '../mention_syntax.dart' show handleKey;
import 'mention_picker.dart';

class NoteMentions {
  NoteMentions({required this.services, required this.noteId, required this.colours, required this.view, DateTime Function()? today}) : _today = today ?? DateTime.now;

  final AccountServices? services;
  final String noteId;

  /// Whose colour is whose in this note, as its comments wear them.
  final CommentColours Function() colours;
  final EditorViewLike? Function() view;
  final DateTime Function() _today;

  /// This account's handle, signed in; null signed out.
  String? get me => services?.session?.handle;

  /// The organization the note is filed in, or null for a note of the person's own.
  String? get orgId => orgOfNote(services, noteId);

  /// The members of the note's organization, as read this session: by handle, with the colour each wears.
  Map<String, String?> get _members {
    final services = this.services, org = orgId;
    if (services == null || org == null) return const {};
    return memberColoursOf(services).of(org) ?? const {};
  }

  /// The hue a person wears here: a member's, or yours in a team's note; null for anyone else and in a note of your own.
  String? hue(String handle) {
    final org = orgId;
    if (org == null) return null;
    final key = handleKey(handle);
    final mine = me;
    final known = (mine != null && handleKey(mine) == key) || _members.keys.any((member) => handleKey(member) == key);
    if (!known) return null;
    final match = _members.keys.firstWhere((member) => handleKey(member) == key, orElse: () => handle);
    return hueOf(colours().of(match));
  }

  /// Who the picker offers (see the header).
  List<MentionPerson> people() {
    if (orgId == null) return const [];
    return [for (final handle in _members.keys) (handle: handle, hue: hue(handle))];
  }

  /// The handle a bare day is signed with: yours in a team's note (`@matt @2026-11-06`, so whose day it is stands in
  /// the words; docs/MARKDOWN_FIRST.md §11 decision 18), none in a note of your own.
  String? owner() => orgId == null ? null : me;

  late final MentionPicker picker = MentionPicker(people: people, me: () => me, today: _today, owner: owner);

  /// The editor's extension: the chips always, the picker where the note can be written.
  Extension extension({required bool readOnly}) => mentions(MentionHooks(hue: hue, today: _today, picking: readOnly ? null : picker, owner: owner));

  /// The chips drawn again in the colours as they are now.
  void recolour() {
    final editor = view();
    if (editor == null) return;
    try {
      editor.dispatch(TransactionSpec(effects: <StateEffect<Object?>>[refreshMentions.of(0)]));
    } catch (failure) {
      debugPrint('[mentions] not drawn again: $failure');
    }
  }

  void dispose() => picker.dispose();
}
