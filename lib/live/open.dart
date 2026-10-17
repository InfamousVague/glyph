/// An open note's editor made live: the one door a note's desk uses. A port of `src/app/core/live/open.ts`
/// (`goLive`), `src/app/editor/useLiveNote.ts` and `src/app/editor/useTeamNote.ts` between them.
///
/// **A team's note** (filed in an organization's workspace) is bound to its document (docs/SHARED.md, S5;
/// lib/team/doc.dart): every keystroke a change of the CRDT, which the next pass posts to the team, and every
/// update the pass applies put into the editor by the binding. What the editor holds when the binding is made is
/// reconciled into the document first, so words typed before it was ready are a change and not a loss. And live
/// (S6; lib/live/team.dart): the note's room is held while it is open, so a member's typing arrives as it is made
/// and their caret and selection are drawn in their colour with their handle on it; and the organization's own
/// room is told this device is editing this note, with the caret as it moves, for the dashboard's "editing
/// Roadmap" and its Jump to cursor. Opened at a `jump`, a member's caret, the selection is put there once the
/// document is bound. Nothing of this needs the live-typing switch: a team's notes are live by being the team's.
///
/// **A note of the account's own** is live only with the switch on (lib/live/enabled.dart, on unless turned off):
/// the note open on another device too, typed into on either and arriving a character at a time. It says nothing
/// on screen of the account's own devices: the typing arriving is the sign. Claude, typing into it through the
/// account's connector, has its caret drawn with its name (docs/CLAUDE_LIVE.md; lib/live/session.dart `AiCarets`).
/// Open, live or not, the note is said in the account's own presence room (lib/live/presence.dart), as a team's is
/// in its organization's.
///
/// Every bound editor is put in [LiveServices.bound] while it is, for Follow (lib/live/follow.dart).
///
/// What differs:
/// - The page's two hooks are one [NoteLive] made with the account, and [NoteLive.open] answers an [OpenLive] to
///   close; a note filed into an organization, or taken out of one, while it is open is closed and opened again by
///   it, as the hooks' effects run again.
/// - **A canvas is not bound** as words on the page either; its structure is lib/team/canvas.dart's, edited
///   through the canvas's view, which is handed the [TeamBinding] ([OpenLive.team]).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/canvas_body.dart';
import '../core/note_text.dart';
import '../core/workspaces.dart';
import '../editor/editor.dart';
import '../team/doc.dart';
import 'editor_binding.dart';
import 'hub.dart';
import 'live.dart';
import 'presence.dart';
import 'session.dart';
import 'team.dart';

/// How often at most the organization's room hears where the caret or the pointer is: its exact place matters only
/// to a jump (`CARET_EVERY_MS`).
const Duration caretEvery = Duration(milliseconds: 400);

/// A team note as its screen holds it: its document, its room (null without the key), and whose it is
/// (`TeamBinding`).
class TeamBinding {
  const TeamBinding({required this.doc, required this.room, required this.orgId});
  final TeamDoc doc;
  final TeamRoom? room;
  final String orgId;
}

/// What makes notes live, for a desk.
class NoteLive {
  NoteLive({required this.live, required this.docs, required this.workspaces, required this.hasUnsynced, required this.keepCopy});

  final LiveServices live;
  final TeamDocs docs;
  final WorkspaceStore workspaces;

  /// Whether the saved note has changes the pass sync has not sent: asked of the saved one, not the editor's
  /// words, since the saved one is what the pass compares. A note not saved has nothing unsent.
  final Future<bool> Function(String noteId) hasUnsynced;

  /// This device's own words, kept beside the room's as a note of their own: a conflict makes a copy, never a
  /// loss.
  final Future<void> Function(String words) keepCopy;

  /// The organization a note is filed in, or null for a note that is not a team's (`isTeamNote`).
  String? orgOf(String noteId) {
    final space = workspaces.workspaceOf(noteId);
    return space == null ? null : orgIdOf(space.id);
  }

  /// The note in [view] made live, for as long as the answer is not closed. [jump] is a member's caret to open at
  /// (the dashboard's Jump to cursor); [onTeam] is told the team's binding once it is made, and null when it goes.
  OpenLive open(EditorViewLike view, String noteId, {Map<String, Object?>? jump, void Function(TeamBinding? team)? onTeam}) => OpenLive._(this, view, noteId, jump, onTeam);
}

/// One open note, live or not: closed with its editor.
class OpenLive {
  OpenLive._(this._of, this._view, this.noteId, this._jump, this._onTeam) {
    _org = _of.orgOf(noteId);
    _of.workspaces.addListener(_refiled);
    _of.live.enabled.addListener(_switched);
    _start();
  }

  final NoteLive _of;
  final EditorViewLike _view;
  final String noteId;
  Map<String, Object?>? _jump;
  final void Function(TeamBinding? team)? _onTeam;

  String? _org;
  bool _closed = false;

  /// What undoes the way the note is open now; each start has its own.
  void Function()? _stop;
  int _starts = 0;

  /// The team's binding, once made: for a canvas to draw and edit through.
  TeamBinding? team;

  /// How many other devices have a note of the account's own open right now. Nothing on the page shows it.
  final ValueNotifier<int> peers = ValueNotifier<int>(0);

  void _refiled() {
    final now = _of.orgOf(noteId);
    if (now == _org || _closed) return;
    _org = now;
    _restart();
  }

  void _switched() {
    // It takes effect on the next note opened: a note already open keeps working the way it opened.
  }

  void _restart() {
    _stop?.call();
    _stop = null;
    _leaveAccount?.call();
    _leaveAccount = null;
    _start();
  }

  /// What says nowhere in the account's own room again, for a personal note.
  void Function()? _leaveAccount;

  void _start() {
    final run = _starts += 1;
    bool gone() => _closed || run != _starts;
    final org = _org;
    if (org == null) _leaveAccount = _tellAccount();
    // Without a document the note is still itself, synced by the pass from its words; and a note that could not go
    // live (no network, no account key) works as it always has.
    unawaited((org != null ? _team(org, gone) : _own(gone)).catchError((Object failure) {
      debugPrint('[ghost] the note could not be made live: $failure');
    }));
  }

  String get _words => _view.state.doc.toString();

  /// `useTeamNote`.
  Future<void> _team(String orgId, bool Function() gone) async {
    final held = await _of.docs.doc(noteId, seedWords: _words);
    if (gone() || held == null) return;
    await held.reconcile(_words);
    if (gone()) return;
    final room = _of.live.rooms.openTeamRoom(orgId, noteId, held);
    // A canvas is its structure, edited through the view: its editor, which shows its JSON behind the view switch,
    // stays the note's own and reaches the team by the pass, not by the binding.
    final binding = isCanvasBody(_words) ? null : (LiveBinding(_view, held, room: room, positions: held.crdt, smoke: () => _of.live.prefs.value.wisp)..bind());
    final made = team = TeamBinding(doc: held, room: room, orgId: orgId);
    _onTeam?.call(made);
    final leave = _tellWhere(orgId, room);
    if (binding != null) _of.live.bound.put(noteId, binding);
    _stop = () {
      leave();
      team = null;
      _onTeam?.call(null);
      if (binding != null) _of.live.bound.take(noteId, binding);
      binding?.unbind();
    };
    final jump = _jump;
    if (jump != null && binding != null) {
      _jump = null;
      // Opened at a member's caret: the selection put there, and the place scrolled to the middle. A caret the
      // document cannot place any more (its words gone) is left alone.
      final place = await held.crdt.caretIndexes(jump);
      if (gone() || place == null) return;
      final limit = _view.state.doc.length;
      final anchor = place.anchor.clamp(0, limit), head = place.head.clamp(0, limit);
      _view.dispatch(TransactionSpec(selection: EditorSelection.single(anchor, head), effects: EditorViewLike.scrollIntoView(anchor, y: ScrollStrategy.center)));
      _view.focus();
    }
  }

  /// Where this device is, for the organization's dashboard (`tellWhere`): this note, by its title as it is now,
  /// and the caret as the note's room hears it move, at most every [caretEvery]. The last place stands while the
  /// editor is not being typed in. Answers the way to stop, which says nowhere.
  void Function() _tellWhere(String orgId, TeamRoom? room) {
    Map<String, Object?>? cursor;
    Spot? pointer;
    Timer? timer;
    void tell() {
      final words = _words;
      _of.live.presence.announce(orgId, Whereabouts(note: noteId, title: noteTitle(words), kind: isCanvasBody(words) ? 'canvas' : 'note', cursor: cursor, pointer: pointer));
    }

    tell();
    void heard() {
      final said = room?.local ?? const <String, Object?>{};
      final caret = said['cursor'], spot = Spot.of(said['pointer']);
      var moved = false;
      if (caret is Map && '$caret' != '$cursor') {
        cursor = {'anchor': caret['anchor'], 'head': caret['head']};
        moved = true;
      }
      if (spot != null && (spot.x != pointer?.x || spot.y != pointer?.y)) {
        pointer = spot;
        moved = true;
      }
      if (moved) {
        timer ??= Timer(caretEvery, () {
          timer = null;
          tell();
        });
      }
    }

    final stop = room?.onChange(heard);
    return () {
      timer?.cancel();
      stop?.call();
      room?.close();
      _of.live.presence.announce(orgId, null);
    };
  }

  /// This personal note, said in the account's own room (docs/CLAUDE_LIVE.md, "Presence rooms"): by its title as
  /// it is when opened. Answers the way to stop, which says nowhere.
  void Function() _tellAccount() {
    final words = _words;
    _of.live.presence.announceAccount(Whereabouts(note: noteId, title: noteTitle(words), kind: isCanvasBody(words) ? 'canvas' : 'note'));
    return () => _of.live.presence.announceAccount(null);
  }

  /// `useLiveNote` and `goLive`. Bound with the AIs' carets ([LiveSession.carets]) placed in the session's
  /// document, once it is made.
  Future<void> _own(bool Function() gone) async {
    if (!_of.live.enabled.value) return;
    LiveSession? session;
    LiveBinding? binding;
    var asked = false;
    void bind() {
      final ready = session;
      if (ready == null || binding != null || asked || ready.state != SessionState.ready || gone()) return;
      asked = true;
      unawaited(ready.document.then((doc) {
        if (binding != null || ready.state != SessionState.ready || gone()) return;
        final made = binding = LiveBinding(_view, ready, room: ready.carets, positions: doc, smoke: () => _of.live.prefs.value.wisp)..bind();
        _of.live.bound.put(noteId, made);
        // Opened at Claude's caret (the chip's Open): put there as a team note's jump is.
        final jump = _jump;
        if (jump == null) return;
        _jump = null;
        unawaited(doc.caretIndexes(jump).then((place) {
          if (gone() || place == null || !made.bound) return;
          final limit = _view.state.doc.length;
          final anchor = place.anchor.clamp(0, limit), head = place.head.clamp(0, limit);
          _view.dispatch(TransactionSpec(selection: EditorSelection.single(anchor, head), effects: EditorViewLike.scrollIntoView(anchor, y: ScrollStrategy.center)));
          _view.focus();
        }, onError: (Object _) {}));
      }, onError: (Object _) {}));
    }

    final opened = await _of.live.hub.openLive(
      noteId,
      _words,
      SessionListener(ready: (_) => bind(), peers: (count) => peers.value = count),
      SyncHooks(hasUnsynced: _of.hasUnsynced, keepCopy: (_, words) => _of.keepCopy(words)),
    );
    if (opened == null) return;
    if (gone()) {
      _of.live.hub.closeLive(noteId);
      return;
    }
    session = opened;
    // Ready before the session was in hand: bound now.
    bind();
    _stop = () {
      final made = binding;
      if (made != null) _of.live.bound.take(noteId, made);
      made?.unbind();
      _of.live.hub.closeLive(noteId);
      peers.value = 0;
    };
  }

  /// Unbinds the editor, leaves the room, and lets the connection go with the last note.
  void close() {
    if (_closed) return;
    _closed = true;
    _of.workspaces.removeListener(_refiled);
    _of.live.enabled.removeListener(_switched);
    _stop?.call();
    _stop = null;
    _leaveAccount?.call();
    _leaveAccount = null;
  }
}
