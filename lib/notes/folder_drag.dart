/// Notes and folders carried onto folders (Matt, 2026-10-20: "also allow clicking and dragging files into folders and
/// folders into folders"). The port's own: the web app's sidebar only.
///
/// One rule and one move for every place a note or a folder is shown: a card, a row or a line on home and All notes,
/// a tile in the icon view, a chip in the folder strip, a row in the sidebar, a workspace's pill. What is carried is
/// a [FolderCarry]; it is picked up by a [FolderCarrySource] (a mouse drags at once, a finger holds first, so a tap
/// still opens and a finger's scroll still scrolls) and let go on a [FolderDropZone], which asks [folderVerdict]
/// whether it lands, draws itself taking it or refusing it while it is held over, and on the drop moves it
/// ([moveCarried]) and says so in a toast with Undo, or says in a toast why not.
///
/// **The rules** are the connector's and the in-app AI's (lib/claude/claude_folders.dart, mcp/folders.ts), and the
/// moves are theirs too, [WorkspaceStore.fileNote] and [WorkspaceStore.moveWorkspace], so a note's file follows its
/// filing and a team note's row is put again with the new path, exactly as when Claude moves it:
/// - A note moves freely among the personal folders and the top (filed nowhere), and among the folders of one
///   organization and its own workspace (GHST-107). Moving keeps its id, its words and its file's name: only its
///   folder changes (the incident of 2026-10-20, 33f600e7, was notes read as personal that were the team's).
/// - A folder moves only where [WorkspaceStore.canMove] lets it inside its own space: never inside itself or a folder
///   inside it, and an organization's own workspace never at all. Its top is the personal top for a personal folder
///   and the organization's workspace for one of an organization's.
/// - **Across an organization's edge it asks first** (Matt, 2026-10-29: "Allow dragging files into folders for orgs
///   instead of sending the error message open a confirm dialog"). Before, a drop into an organization or out of one
///   was refused with a toast that sent the person to the note's Workspace picker. Now it lands as
///   [FolderLanding.asks]: a sheet ([askToMove]) says what the move does, in the words of what the sync then
///   does, and only its Move moves. Into an organization the note is filed there, which is all the Workspace picker
///   does too ([WorkspaceStore.fileNote]): the engine reads a note filed under an organization's workspace as the
///   team's, seals it under the organization's key and puts its row for every member, and takes the account's own
///   row away (lib/sync/engine.dart, lib/team/sync.dart). Out of one, filed in a workspace this device knows outside
///   it, the team's row is deleted, which deletes the note on every other member's devices; the person's own devices
///   keep it (lib/team/sync.dart `_takeRow`). A folder carried across takes its notes with it, the same filing for
///   each, its trashed notes left on the side they were on ([moveCarried]). Nothing across the edge has an Undo:
///   going back crosses it again, and is asked again. Move to… still lists only the places a move needs no asking.
///   Straight from one organization into another is still refused, now saying how (out into a folder of the person's,
///   then in, [_betweenWhy]), except for a folder with no notes in it; and so is a team note let go on the top level,
///   since a note filed nowhere is no evidence it left the team (lib/sync/engine.dart `leftTeam`, ddeb6141), which
///   would keep its row and file it back.
///
/// **Move to…** is the same move for whoever does not drag: a screen reader's custom action on every source, which
/// lists where it may go in a menu at the thing itself, and a row in a note's menu (lib/notes/note_menu.dart). A
/// drag picked up is said aloud, and its landing is the toast's words, which the kit speaks.
library;

import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show KeyDownEvent, LogicalKeyboardKey;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/workspaces.dart';
import '../sheet/css.dart';
import '../sheet/kit.dart';
import '../sheet/sheet.dart';
import '../shell/pop_menu.dart';
import '../shell/wide_screen.dart' show mousePointer;

/// A note or a folder carried, by id, with its name for the lifted pill and the toast.
@immutable
class FolderCarry {
  const FolderCarry.note(this.id, this.label) : folder = false;
  const FolderCarry.folder(this.id, this.label) : folder = true;

  final String id;
  final String label;

  /// A workspace's folder; a note where false.
  final bool folder;

  @override
  bool operator ==(Object other) => other is FolderCarry && other.id == id && other.folder == folder && other.label == label;

  @override
  int get hashCode => Object.hash(id, folder, label);

  @override
  String toString() => 'FolderCarry(${folder ? 'folder' : 'note'} $id)';
}

/// What is being carried now, anywhere in the app, or null: the places that offer the top only while something is
/// carried listen to it.
final ValueNotifier<FolderCarry?> folderCarrying = ValueNotifier<FolderCarry?>(null);

/// What a drop would do.
enum FolderLanding {
  /// It moves there.
  moves,

  /// It moves there once the person says so: into an organization, out of one, or from one into another, which
  /// shares it with a team or takes it from one ([FolderVerdict.ask]).
  asks,

  /// It is there already: nothing happens, and nothing is said.
  stays,

  /// It may not go there, for [FolderVerdict.why].
  refused,
}

/// What a move across an organization's edge asks: its sheet's title, the line under it that says what happens,
/// and what the sheet is called for a screen reader.
@immutable
class FolderAsk {
  const FolderAsk({required this.title, required this.note, required this.label});

  /// "Move “Plan” to HelloTrade › Meetings?"
  final String title;

  /// "Everyone in HelloTrade will be able to read and edit it."
  final String note;
  final String label;

  @override
  String toString() => 'FolderAsk($title $note)';
}

/// A drop's answer: whether it lands, and why not where it does not.
@immutable
class FolderVerdict {
  const FolderVerdict._(this.landing, [this.why, this.ask]);

  static const FolderVerdict moves = FolderVerdict._(FolderLanding.moves);
  static const FolderVerdict stays = FolderVerdict._(FolderLanding.stays);
  const FolderVerdict.refused(String why) : this._(FolderLanding.refused, why);
  const FolderVerdict.asks(FolderAsk ask) : this._(FolderLanding.asks, null, ask);

  final FolderLanding landing;

  /// Why it is refused, in a line for the toast.
  final String? why;

  /// What is asked before it moves, for one that [FolderLanding.asks].
  final FolderAsk? ask;

  /// Whether it lands there, at once or once asked: a drop zone wears the ring of one that takes it.
  bool get takes => landing == FolderLanding.moves || landing == FolderLanding.asks;

  @override
  String toString() => 'FolderVerdict(${landing.name}${why == null ? '' : ': $why'}${ask == null ? '' : ': ${ask!.title}'})';
}

/// A name as a toast says it: in quotes, or [otherwise] when there is none or a long one.
String _quoted(String label, String otherwise) {
  final clean = label.trim();
  return clean.isNotEmpty && clean.length <= 28 ? '“$clean”' : otherwise;
}

/// An organization's name, from its workspace, for the toasts.
String _orgName(Workspaces spaces, String org) => spaces.list.where((w) => w.id == orgWorkspaceId(org)).firstOrNull?.name ?? 'the organization';

/// Where a workspace is, said whole: "HelloTrade › Designs"; the top for null.
String folderPlace(Workspaces spaces, String? id) => id == null ? 'the top level' : workspacePathName(spaces.list, id);

/// Whether [carry] dropped on [target] moves there, moves once asked, is there already, or is refused and why.
/// [target] is a workspace by id, or null for the top of the personal space: a note filed in none, a folder at the
/// top.
FolderVerdict folderVerdict(WorkspaceStore store, FolderCarry carry, String? target) {
  final spaces = store.value;
  if (target != null && !spaces.list.any((w) => w.id == target)) return const FolderVerdict.refused('That folder is gone.');
  final toOrg = target == null ? null : orgOfWorkspace(spaces.list, target);
  if (!carry.folder) {
    final filed = spaces.of[carry.id];
    final known = filed != null && spaces.list.any((w) => w.id == filed);
    final from = known ? filed : null;
    if (from == target) return FolderVerdict.stays;
    final fromOrg = from == null ? null : orgOfWorkspace(spaces.list, from);
    if (fromOrg == toOrg) return FolderVerdict.moves;
    // Unfiled is no evidence that it left (lib/sync/engine.dart `leftTeam`, ddeb6141): the team would keep its row and
    // file it back, so out of an organization a note goes into one of the person's own folders.
    if (fromOrg != null && target == null) return FolderVerdict.refused('${_quoted(carry.label, 'This note')} is ${_orgName(spaces, fromOrg)}’s: to take it out of the team, move it into one of your own folders.');
    if (fromOrg != null && toOrg != null) return FolderVerdict.refused(_betweenWhy(spaces, '${_quoted(carry.label, 'This note')} is ${_orgName(spaces, fromOrg)}’s', toOrg));
    return FolderVerdict.asks(_acrossAsk(spaces, carry, target, fromOrg: fromOrg, toOrg: toOrg, notes: 1));
  }
  final id = carry.id;
  final moving = spaces.list.where((w) => w.id == id).firstOrNull;
  if (moving == null) return const FolderVerdict.refused('That folder is gone.');
  if (isOrgWorkspace(id)) return const FolderVerdict.refused('An organization’s workspace stays at the top.');
  if (target != null && workspaceFamily(spaces.list, id).contains(target)) return const FolderVerdict.refused('A folder can’t go inside itself.');
  if (moving.parent == target) return FolderVerdict.stays;
  if (store.canMove(id, target)) return FolderVerdict.moves;
  if (store.canMove(id, target, acrossOrgs: true)) {
    final fromOrg = orgOfWorkspace(spaces.list, id);
    final notes = store.notesUnder(id).length;
    if (fromOrg != null && toOrg != null && notes > 0) return FolderVerdict.refused(_betweenWhy(spaces, '${moving.name} holds ${_orgName(spaces, fromOrg)}’s notes', toOrg));
    return FolderVerdict.asks(_acrossAsk(spaces, carry, target, fromOrg: fromOrg, toOrg: toOrg, notes: notes));
  }
  return FolderVerdict.refused('${moving.name} can’t go there.');
}

/// Why a note, or a folder with notes in it, does not go straight from one organization into another: [what] is
/// whose it is. Each team's copy of a note's document is kept on a device under the note's id alone (lib/team/doc.dart
/// `TeamDocs`), so one note in two teams' channels at once, the old team's deletion and the new team's row crossing
/// in a pass, shares a document between two logs: its words came out doubled on the person's other device, and its
/// place in the new team's log was the old one's (found by test/team_sync/move_across_test.dart's first run of it,
/// 2026-10-29). Out into one of the person's own folders first, synced, then in, is two moves the sync already carries.
String _betweenWhy(Workspaces spaces, String what, String toOrg) =>
    '$what. Move it into one of your own folders first; once that has synced, it can go into ${_orgName(spaces, toOrg)}.';

/// What a move across an organization's edge asks (see the library doc), [notes] being how many notes go with it:
/// one for a note, those under a folder for a folder. Into an organization, everyone in it reads and edits them;
/// out of one, its row is deleted for every other member and the person keeps theirs. From one to another only a
/// folder with no notes goes ([_betweenWhy]), which takes nothing from anyone.
FolderAsk _acrossAsk(Workspaces spaces, FolderCarry carry, String? target, {required String? fromOrg, required String? toOrg, required int notes}) {
  final label = carry.label.trim().isEmpty ? 'Untitled' : carry.label.trim();
  final what = carry.folder ? label : '“$label”';
  final with_ = !carry.folder || notes == 0 ? '' : (notes == 1 ? ' and its note' : ' and its $notes notes');
  final place = target != null ? workspacePathName(spaces.list, target) : 'the top of your own notes';
  // What the words are about: the note, or a folder's notes; a folder with none has only notes to come.
  final many = carry.folder && notes != 1;
  final none = carry.folder && notes == 0;
  final it = many ? 'they' : 'it', them = many ? 'them' : 'it';
  String cap(String word) => word[0].toUpperCase() + word.substring(1);
  final from = fromOrg == null ? null : _orgName(spaces, fromOrg);
  final to = toOrg == null ? null : _orgName(spaces, toOrg);
  final shared = to == null ? null : (none ? 'Everyone in $to will be able to read and edit the notes you put in it.' : 'Everyone in $to will be able to read and edit $them.');
  final String note;
  if (from == null) {
    note = shared!;
  } else if (none) {
    // Nothing in it to take from anyone: only the folder changes hands.
    note = to == null ? 'It has no notes, so nothing is taken from anyone in $from.' : 'It has no notes, so nothing is taken from anyone in $from. $shared';
  } else {
    note = '${cap(it)} will no longer be shared with $from: $it ${many ? 'are' : 'is'} taken out of the team and deleted for everyone else in $from. You keep $them.';
  }
  return FolderAsk(title: 'Move $what$with_ to $place?', note: note, label: 'Move $what');
}

/// Moves [carry] to [target] where [folderVerdict] lets it, with the store's own moves, the connector's and the AI's
/// (see the library doc): what the toast says, and the Undo that puts it back. Null where nothing moved. A move
/// across an organization's edge is made only when the caller has [asked] the person ([askToMove]), and has no Undo.
({String said, VoidCallback? undo})? moveCarried(WorkspaceStore store, FolderCarry carry, String? target, {bool asked = false}) {
  final landing = folderVerdict(store, carry, target).landing;
  final across = landing == FolderLanding.asks;
  if (landing != FolderLanding.moves && !(asked && across)) return null;
  final spaces = store.value;
  final where = folderPlace(spaces, target);
  if (!carry.folder) {
    final was = store.workspaceOf(carry.id)?.id;
    final name = _quoted(carry.label, 'the note');
    // The Workspace picker's own move, and the only one there is: the note filed there. Whose it is follows from
    // where it is filed (see the library doc).
    store.fileNote(carry.id, target);
    if (across) return (said: 'Moved $name to $where', undo: null);
    return (
      said: target == null ? 'Took $name out of ${folderPlace(spaces, was)}' : 'Moved $name to $where',
      // Back where it was, which is in the same organization or in none, so the same rule holds.
      undo: () => store.fileNote(carry.id, was),
    );
  }
  final was = spaces.list.firstWhere((w) => w.id == carry.id).parent;
  if (across) {
    // A trashed note filed under the folder stays on the side it was on, in the folder's old parent: the trash is
    // the account's own, so one thrown away and carried into a team would be every member's to read, and one carried
    // out would be deleted for them all.
    final held = store.trash?.value ?? const <String, int>{};
    final family = workspaceFamily(spaces.list, carry.id).toSet();
    final trashed = [
      for (final entry in spaces.of.entries)
        if (family.contains(entry.value) && held.containsKey(entry.key)) entry.key,
    ];
    if (trashed.isNotEmpty) store.fileNotes(trashed, was);
    store.moveWorkspace(carry.id, target, acrossOrgs: true);
    return (said: 'Moved ${carry.label} to ${target == null ? 'the top level' : where}', undo: null);
  }
  store.moveWorkspace(carry.id, target);
  return (said: 'Moved ${carry.label} to $where', undo: () => store.moveWorkspace(carry.id, was));
}

/// The app's toasts at [context], or null for a page under none (a test of its own), which says nothing.
GlacierToastController? _toasts(BuildContext context) {
  try {
    return GlacierToast.of(context);
  } on FlutterError {
    return null;
  }
}

/// Shows a toast where the app has its toasts.
void _toast(GlacierToastController? toasts, String message, {VoidCallback? undo}) {
  toasts?.toast(
    message: Text(message),
    duration: undo == null ? null : const Duration(milliseconds: 5000),
    action: undo == null ? null : GlacierToastAction(label: 'Undo', onPress: undo),
  );
}

/// Says [message] aloud to a screen reader.
void _announce(BuildContext context, String message) {
  final view = View.maybeOf(context);
  if (view == null) return;
  unawaited(SemanticsService.sendAnnouncement(view, message, Directionality.maybeOf(context) ?? TextDirection.ltr));
}

/// [carry] let go on [target]: moved, with a toast and its Undo; across an organization's edge, asked first
/// ([askToMove]) and moved only on its Move, with a toast and [onLanded] then; refused, with a toast that says why;
/// already there, nothing. Answers whether it moved now: one that asks answers false.
bool dropCarried(BuildContext context, WorkspaceStore store, FolderCarry carry, String? target, {VoidCallback? onLanded}) {
  final verdict = folderVerdict(store, carry, target);
  if (verdict.landing == FolderLanding.stays) return false;
  final fire = HapticsProvider.of(context);
  final toasts = _toasts(context);
  if (verdict.landing == FolderLanding.asks) {
    unawaited(() async {
      if (!await askToMove(context, verdict.ask!)) return;
      // Asked again of the store as it is now: what was carried, or where, may have gone or moved while the sheet
      // was up, and then the question asked is not the move to make.
      final now = folderVerdict(store, carry, target);
      if (now.landing != FolderLanding.asks || now.ask?.title != verdict.ask!.title) return;
      final moved = moveCarried(store, carry, target, asked: true);
      if (moved == null) return;
      fire(HapticKind.success);
      _toast(toasts, moved.said);
      onLanded?.call();
    }());
    return false;
  }
  if (!verdict.takes) {
    fire(HapticKind.warning);
    _toast(toasts, verdict.why ?? 'It can’t go there.');
    return false;
  }
  final moved = moveCarried(store, carry, target);
  if (moved == null) return false;
  fire(HapticKind.success);
  final undo = moved.undo;
  _toast(
    toasts,
    moved.said,
    undo: undo == null
        ? null
        : () {
            undo();
            fire(HapticKind.success);
          },
  );
  return true;
}

/// Asks [ask] in a sheet over the app, a window in the middle on a Mac and a sheet from the foot on a phone, as the
/// app's other questions are asked (lib/notes/trash_sheet.dart): its title, the line that says what happens, Move
/// and Cancel. Move is the default, taken by Return; Cancel, Escape, the back gesture and a tap outside leave
/// everything where it was. Answers true for Move; false where there is no overlay to ask in.
Future<bool> askToMove(BuildContext context, FolderAsk ask) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return Future.value(false);
  final answer = Completer<bool>();
  late final OverlayEntry entry;
  void done(bool move) {
    if (answer.isCompleted) return;
    entry.remove();
    answer.complete(move);
  }

  entry = OverlayEntry(builder: (_) => _MoveAsk(ask: ask, onAnswer: done));
  overlay.insert(entry);
  return answer.future;
}

/// The question's sheet: the focus held while it is up, so Return is Move's.
class _MoveAsk extends StatelessWidget {
  const _MoveAsk({required this.ask, required this.onAnswer});

  final FolderAsk ask;
  final ValueChanged<bool> onAnswer;

  @override
  Widget build(BuildContext context) {
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent && (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
          onAnswer(true);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Sheet(
        key: const ValueKey('move-ask'),
        label: ask.label,
        onClose: () => onAnswer(false),
        children: [
          SheetTitle.text(ask.title),
          SheetNote(ask.note),
          SheetGroup(
            children: [
              SheetRow(key: const ValueKey('move-ask-yes'), label: 'Move', onPress: () => onAnswer(true)),
              SheetRow(key: const ValueKey('move-ask-no'), label: 'Cancel', onPress: () => onAnswer(false)),
            ],
          ),
        ],
      ),
    );
  }
}

/// Where [carry] may be moved, for Move to…: each workspace it would land in, by id with its whole name, the top
/// first as null where it may go there; never where it is now, and never across an organization's edge, which a drag
/// asks about and Move to… leaves to the note's Workspace picker, so a menu of the person's own folders is not
/// every team's too.
List<({String? id, String name})> folderDestinations(WorkspaceStore store, FolderCarry carry) {
  final spaces = store.value;
  return [
    if (folderVerdict(store, carry, null).landing == FolderLanding.moves) (id: null, name: carry.folder ? 'The top level' : 'Out of every folder'),
    for (final w in spaces.list)
      if (folderVerdict(store, carry, w.id).landing == FolderLanding.moves) (id: w.id, name: workspacePathName(spaces.list, w.id)),
  ];
}

/// How a drop zone looks while something is held over it.
enum FolderDropLook {
  /// Nothing carried over it.
  idle,

  /// What is held over it would land.
  takes,

  /// What is held over it would be refused.
  refuses,
}

/// The ring a drop zone wears for [look]: the ink's, on the paper a step darker, for one that takes; a faint red one
/// for one that refuses; none at rest.
BoxDecoration folderDropDecoration(BuildContext context, FolderDropLook look, {required double radius}) {
  final t = context.tokens;
  final line = snapBorder(context, t.len('app-line'));
  return switch (look) {
    FolderDropLook.idle => BoxDecoration(borderRadius: BorderRadius.circular(radius)),
    FolderDropLook.takes => BoxDecoration(
        color: t.color('app-paper-2'),
        border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink) 70%, transparent)'), width: line * 1.5),
        borderRadius: BorderRadius.circular(radius),
      ),
    FolderDropLook.refuses => BoxDecoration(
        border: Border.all(color: t.colorOf('color-mix(in oklch, var(--glacier-red-9) 55%, transparent)'), width: line),
        borderRadius: BorderRadius.circular(radius),
      ),
  };
}

/// A place a carried note or folder can be let go: a workspace by [target], or the top for null. Its [builder] is
/// told how to look; [decorate] wraps it in [folderDropDecoration] itself. A drop that would be refused is still
/// taken, so the toast can say why; [onLanded] is told after one that moved.
class FolderDropZone extends StatelessWidget {
  const FolderDropZone({super.key, required this.store, required this.target, required this.builder, this.decorate = false, this.radius, this.onLanded});

  final WorkspaceStore store;
  final String? target;
  final Widget Function(BuildContext context, FolderDropLook look) builder;

  /// Whether the zone wears the ring itself, at [radius] (the kit's small radius where null).
  final bool decorate;
  final double? radius;
  final VoidCallback? onLanded;

  @override
  Widget build(BuildContext context) {
    return DragTarget<FolderCarry>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (details) {
        // One asked about lands later, on its Move: [onLanded] then, while this zone is still on screen.
        if (dropCarried(context, store, details.data, target, onLanded: () {
          if (context.mounted) onLanded?.call();
        })) {
          onLanded?.call();
        }
      },
      builder: (context, candidates, _) {
        final held = candidates.whereType<FolderCarry>().firstOrNull;
        final verdict = held == null ? null : folderVerdict(store, held, target);
        final look = verdict == null || verdict.landing == FolderLanding.stays ? FolderDropLook.idle : (verdict.takes ? FolderDropLook.takes : FolderDropLook.refuses);
        var child = builder(context, look);
        if (decorate) {
          // Drawn over and under it, never round it: a ring that took room would move what is under the pointer.
          final ring = folderDropDecoration(context, look, radius: radius ?? context.tokens.radius('sm'));
          child = DecoratedBox(
            key: const ValueKey('drop-ring'),
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(border: ring.border, borderRadius: ring.borderRadius),
            child: DecoratedBox(decoration: BoxDecoration(color: ring.color, borderRadius: ring.borderRadius), child: child),
          );
        }
        // Faded only while it refuses: an Opacity at 1 still moved a few pixels of the sidebar's letters (its
        // pictures, test/sidebar), so at rest the zone is its child under the pointer's region and nothing more.
        final refuses = look == FolderDropLook.refuses;
        return MouseRegion(cursor: refuses ? SystemMouseCursors.forbidden : MouseCursor.defer, child: refuses ? Opacity(opacity: 0.6, child: child) : child);
      },
    );
  }
}

/// A note or a folder that can be picked up and carried to a folder: a mouse drags it at once, a finger holds it
/// first ([LongPressDraggable]), so a tap still opens it and a finger's scroll still scrolls. What follows the
/// pointer is a lifted pill with its name ([FolderCarryPill]); the thing itself is dimmed where it was. A screen
/// reader is offered Move to… ([folderDestinations]) as a custom action, a menu at the thing itself.
class FolderCarrySource extends StatefulWidget {
  const FolderCarrySource({super.key, required this.store, required this.carry, required this.child, this.enabled = true, this.moveAction = true});

  final WorkspaceStore store;
  final FolderCarry carry;
  final Widget child;
  final bool enabled;

  /// Whether Move to… is offered here as a screen reader's action ([folderMoveAction]). A row that swipes offers
  /// it among its swipes' actions instead, on the same node ([NoteCarry]): two sets of actions on one node, the
  /// inner wins and the swipes would be lost.
  final bool moveAction;

  @override
  State<FolderCarrySource> createState() => _FolderCarrySourceState();
}

class _FolderCarrySourceState extends State<FolderCarrySource> {
  void _started() {
    folderCarrying.value = widget.carry;
    _announce(context, 'Moving ${widget.carry.label}. Drop it on a folder.');
  }

  void _ended() {
    if (folderCarrying.value == widget.carry) folderCarrying.value = null;
  }

  @override
  void dispose() {
    _ended();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final t = context.tokens;
    final carry = widget.carry;
    final feedback = FolderCarryPill(label: carry.label, folder: carry.folder, tokens: t);
    final dimmed = Opacity(opacity: 0.4, child: widget.child);
    // The pill a little off the pointer: under and to the right of a mouse's arrow, above a finger, so it is seen.
    final Offset grip = mousePointer ? const Offset(-14, -14) : const Offset(24, 64);
    Offset anchor(Draggable<Object> d, BuildContext context, Offset position) => grip;
    final Widget drag = mousePointer
        ? Draggable<FolderCarry>(
            data: carry,
            feedback: feedback,
            childWhenDragging: dimmed,
            dragAnchorStrategy: anchor,
            onDragStarted: _started,
            onDragEnd: (_) => _ended(),
            child: widget.child,
          )
        : LongPressDraggable<FolderCarry>(
            data: carry,
            feedback: feedback,
            childWhenDragging: dimmed,
            dragAnchorStrategy: anchor,
            hapticFeedbackOnStart: true,
            onDragStarted: _started,
            onDragEnd: (_) => _ended(),
            child: widget.child,
          );
    if (!widget.moveAction) return drag;
    return Semantics(customSemanticsActions: {folderMoveAction: () => showFolderMoveMenu(context, widget.store, carry)}, child: drag);
  }
}

/// Move to…, as a screen reader is offered it on whatever can be carried.
const CustomSemanticsAction folderMoveAction = CustomSemanticsAction(label: 'Move to…');

/// Opens Move to… for [carry] at what [context] draws: a menu of where it may go ([folderDestinations]), each moving
/// it as a drop there would, with the same toast. Over the app, until a row is chosen or it is dismissed.
void showFolderMoveMenu(BuildContext context, WorkspaceStore store, FolderCarry carry) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  final box = context.findRenderObject();
  if (overlay == null || box is! RenderBox || !box.hasSize) return;
  final at = box.localToGlobal(Offset.zero) & box.size;
  final places = folderDestinations(store, carry);
  late final OverlayEntry entry;
  var gone = false;
  void close() {
    if (gone) return;
    gone = true;
    entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => PopMenu(
      anchor: GlacierAnchor.rect(at),
      onDismiss: close,
      ariaLabel: 'Move ${carry.label} to',
      children: [
        if (places.isEmpty)
          const GlacierMenuLabel(child: Text('Nowhere else it can go'))
        else ...[
          GlacierMenuLabel(child: Text('Move ${carry.label} to')),
          for (final place in places)
            GlacierMenuItem(
              key: ValueKey('move-to-${place.id ?? 'top'}'),
              onSelect: () {
                if (context.mounted) dropCarried(context, store, carry, place.id);
              },
              child: Text(place.name),
            ),
        ],
      ],
    ),
  );
  overlay.insert(entry);
}

/// What a card, a row or a line is handed to be carried: the workspaces, and itself as carried.
typedef NoteCarry = ({WorkspaceStore store, FolderCarry carry});

/// [child], a note's card, row or line, carried as [carry] says, inside its swipe ([swipes]: Move to… is the swipe's
/// to offer then, [noteCarryActions]); [child] itself without one.
Widget carriedNote(NoteCarry? carry, Widget child, {required bool swipes}) =>
    carry == null ? child : FolderCarrySource(store: carry.store, carry: carry.carry, moveAction: !swipes, child: child);

/// Move to… as an action for a row that swipes to offer beside its swipes' own; none without [carry].
Map<CustomSemanticsAction, VoidCallback> noteCarryActions(BuildContext context, NoteCarry? carry) =>
    carry == null ? const {} : {folderMoveAction: () => showFolderMoveMenu(context, carry.store, carry.carry)};

/// The menu rows of Move to… for [carry], for a menu of the caller's own (a note's, lib/notes/note_menu.dart): one
/// per place it may go, under [PopSub]'s label; none where it can go nowhere else.
List<Widget> folderMoveRows(BuildContext context, WorkspaceStore store, FolderCarry carry) {
  final places = folderDestinations(store, carry);
  if (places.isEmpty) return const [];
  return PopSub.rows(
    context,
    label: 'Move to',
    children: [
      for (final place in places)
        GlacierMenuItem(
          key: ValueKey('move-to-${place.id ?? 'top'}'),
          onSelect: () => dropCarried(context, store, carry, place.id),
          child: Text(place.name),
        ),
    ],
  );
}

/// What follows the pointer while a note or a folder is carried: its kind's glyph and its name on a small lifted
/// card of the paper, with a shadow under it.
class FolderCarryPill extends StatelessWidget {
  const FolderCarryPill({super.key, required this.label, required this.folder, required this.tokens});

  final String label;
  final bool folder;

  /// The page's tokens, handed over: the pill is drawn in the overlay, over the page.
  final Tokens tokens;

  @override
  Widget build(BuildContext context) {
    final t = tokens;
    final size = t.fontSize('sm');
    return IgnorePointer(
      child: Transform.rotate(
        // A touch askew, as a thing picked up is.
        angle: -0.03,
        child: Container(
          key: const ValueKey('carry-pill'),
          constraints: const BoxConstraints(maxWidth: 260),
          padding: EdgeInsets.symmetric(horizontal: t.space(3), vertical: t.space(2)),
          decoration: BoxDecoration(
            color: t.color('app-paper'),
            border: Border.all(color: t.color('glacier-border-strong'), width: t.len('glacier-hairline')),
            borderRadius: BorderRadius.circular(t.radius('md')),
            boxShadow: [
              BoxShadow(color: t.colorOf('color-mix(in oklch, var(--app-ink) 18%, transparent)'), blurRadius: 18, offset: const Offset(0, 8)),
              BoxShadow(color: t.colorOf('color-mix(in oklch, var(--app-ink) 10%, transparent)'), blurRadius: 3, offset: const Offset(0, 1)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            spacing: 0.45 * size,
            children: [
              lucide(folder ? Lucide.folder : Lucide.fileText, size: 15, color: t.color('app-ink-2')),
              Flexible(child: Text(label.trim().isEmpty ? 'Untitled' : label, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: pageText(t, size, weight: 'semibold', color: t.color('app-ink')))),
            ],
          ),
        ),
      ),
    );
  }
}

/// The top of the personal space as a place to drop, drawn over [child] only while a note or folder that may go
/// there is carried, a personal one at once or an organization's folder once asked: "Top level", in the zone's ring. A
/// note dropped there is filed in no folder; a folder, at the top. Used over the sidebar's tools and the strip's
/// heading, so nothing moves as it appears.
class FolderTopDrop extends StatelessWidget {
  const FolderTopDrop({super.key, required this.store, required this.child});

  final WorkspaceStore store;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<FolderCarry?>(
      valueListenable: folderCarrying,
      builder: (context, carried, _) {
        final offered = carried != null && folderVerdict(store, carried, null).takes;
        if (!offered) return child;
        final t = context.tokens;
        final sm = t.fontSize('sm');
        return Stack(
          children: [
            Visibility.maintain(visible: false, child: child),
            Positioned.fill(
              child: FolderDropZone(
                key: const ValueKey('drop-top'),
                store: store,
                target: null,
                decorate: true,
                radius: t.radius('md'),
                builder: (context, look) => Semantics(
                  label: carried.folder ? 'Top level' : 'Out of every folder',
                  child: Container(
                    alignment: Alignment.center,
                    decoration: look == FolderDropLook.idle
                        ? BoxDecoration(
                            border: Border.all(color: t.colorOf('color-mix(in oklch, var(--app-ink-3) 45%, transparent)'), width: 1),
                            borderRadius: BorderRadius.circular(t.radius('md')),
                          )
                        : null,
                    child: ExcludeSemantics(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 0.4 * sm,
                        children: [
                          lucide(Lucide.arrowUpToLine, size: 1.1 * sm, color: t.color('app-ink-2')),
                          Text(carried.folder ? 'Top level' : 'Out of every folder', maxLines: 1, softWrap: false, style: pageText(t, sm, weight: 'medium', color: t.color('app-ink-2'))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
