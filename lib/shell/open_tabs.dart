import 'package:flutter/foundation.dart';

import '../core/note.dart';
import '../core/tabs.dart';

/// Where to go after tabs close ([OpenTabsController.close]): [leaves] false and nothing needs to move, the tab
/// being read was not among them; true and [to] is the tab to open, or null for the home page.
typedef TabLanding = ({bool leaves, String? to});

/// The notes a person has open, as tabs, and the groups over them: the web app's shell/useOpenTabs.ts, held once for
/// the whole app.
///
/// Every way into a note ends in the shell showing it, so the row is kept here rather than at each of them: a note
/// shown is a note open. Only the row is kept, never which tab was in front - the app opens on the home page as it
/// always has, so tabs whose notes have not loaded yet simply are not drawn. A group's tabs are drawn together, so
/// [tabs] hands them on in that order.
///
/// Two things here have bitten, and each says so where it is done: which tab a note opened from inside a book takes
/// ([replaceNext]), and what a closed tab's group is measured against (the prune, against [open] as kept and not the
/// tabs whose notes have loaded).
///
/// Differs from the web:
/// - The hook was handed the note on screen, the library and the live ids on every render; here the shell says them
///   as they change ([update]).
/// - The row and the groups were a synced preference the hook read and wrote itself. The preferences are another
///   module's here: the row and the groups as kept come in by the constructor, a change made on another device by
///   [groupsFromElsewhere], and every change goes out through [onOpenChanged] and [onGroupsChanged].
/// - `close` answers a [TabLanding] where the web answered a string, null or undefined.
class OpenTabsController extends ChangeNotifier {
  OpenTabsController({List<String> open = const [], TabGroups groups = TabGroups.none, this.onOpenChanged, this.onGroupsChanged})
      : _open = List.unmodifiable(open),
        _groups = groups {
    // A closed tab leaves its group, and a group left with nothing in it goes: measured against the row as kept.
    _prune(tell: false);
  }

  /// The row changed: for whoever keeps it (the synced preference `openNotes`).
  final ValueChanged<List<String>>? onOpenChanged;

  /// The groups changed (the synced preference `tabGroups`).
  final ValueChanged<TabGroups>? onGroupsChanged;

  List<String> _open;
  TabGroups _groups;
  String? _shown;
  List<Note> _notes = const [];
  Set<String> _live = const {};

  /// The tab the next note shown takes rather than one of its own; read once.
  String? _swap;

  List<String>? _drawnIds;
  List<Note>? _tabs;

  /// The row as kept, in the order opened: ids whose notes have not loaded, or have gone, included.
  List<String> get open => _open;

  TabGroups get groups => _groups;

  /// The note on screen, as last said.
  String? get shown => _shown;

  /// [tabs]' ids: the order a drag or a key moves a tab within.
  List<String> get drawnIds => _drawnIds ??= List.unmodifiable(displayOrder(openOnly(_open, _live), _groups));

  /// The open notes that exist, in the order drawn: each group's tabs together.
  List<Note> get tabs {
    final made = _tabs;
    if (made != null) return made;
    final byId = {for (final note in _notes) note.id: note};
    return _tabs = List.unmodifiable([for (final id in drawnIds) if (byId[id] != null) byId[id]!]);
  }

  void _changed({bool open = false, bool groups = false}) {
    _drawnIds = null;
    _tabs = null;
    if (open) onOpenChanged?.call(_open);
    if (groups) onGroupsChanged?.call(_groups);
    notifyListeners();
  }

  bool _setOpen(List<String> next) {
    if (listEquals(next, _open)) return false;
    _open = List.unmodifiable(next);
    return true;
  }

  /// The prune, after the row changes. Answers whether the groups changed.
  bool _prune({bool tell = true}) {
    final next = pruneGroups(_groups, _open);
    if (sameGroups(next, _groups)) return false;
    _groups = next;
    if (tell) onGroupsChanged?.call(_groups);
    return true;
  }

  /// What the shell knows now: [shown] the note on screen, or null; [notes] the library as loaded, and [live] the ids
  /// among them the person can still see (not deleted, not in the trash), which are the only tabs drawn.
  ///
  /// A note shown takes a tab: its own at the end of the row, or the tab [replaceNext] named. A request that nothing
  /// read goes as soon as no note is on screen: a page asked for from its own aside is already the note shown, so no
  /// tab changed and the request stayed, and the next note opened from the home page took that page's tab.
  void update({required String? shown, required List<Note> notes, required Set<String> live}) {
    var openChanged = false;
    final shownChanged = shown != _shown;
    _shown = shown;
    if (shown == null) {
      _swap = null;
    } else if (shownChanged) {
      final from = _swap;
      _swap = null;
      openChanged = _setOpen(from != null ? swapOpen(_open, from, shown) : addOpen(_open, shown));
    }
    final libraryChanged = !identical(notes, _notes) || !setEquals(live, _live);
    _notes = notes;
    _live = live;
    final groupsChanged = openChanged && _prune(tell: false);
    if (!openChanged && !libraryChanged && !shownChanged) return;
    _changed(open: openChanged, groups: groupsChanged);
  }

  /// The groups as the person changed them: a chip folded, a tab put into one, a colour chosen.
  void setGroups(TabGroups next) {
    if (sameGroups(next, _groups)) return;
    _groups = next;
    _changed(groups: true);
  }

  /// The groups as another device left them, read again from the preferences: taken only where they say something
  /// else, and not written back.
  void groupsFromElsewhere(TabGroups theirs) {
    if (sameGroups(_groups, theirs)) return;
    _groups = theirs;
    final pruned = _prune(tell: false);
    _changed(groups: pruned);
  }

  /// The row as another device left it.
  void openFromElsewhere(List<String> theirs) {
    if (!_setOpen(theirs)) return;
    final pruned = _prune(tell: false);
    _changed(groups: pruned);
  }

  /// Closes the tabs of [ids]: one, or a whole group's. Answers where to go when the tab being read was among them -
  /// the first tab after it that stays open, else the one before, or null for the home page - and `leaves: false`
  /// when it was not. A group used to be closed a tab at a time, each asking where to go as though it were the only
  /// one closing, so closing the group the note was read in landed on the next tab of the same group, and opened it
  /// again.
  TabLanding close(Iterable<String> ids) {
    final closing = ids.toSet();
    final shown = _shown;
    final TabLanding landing = shown != null && closing.contains(shown)
        ? (leaves: true, to: afterClose([for (final id in openOnly(_open, _live)) if (id == shown || !closing.contains(id)) id], shown))
        : (leaves: false, to: null);
    if (_setOpen([for (final id in _open) if (!closing.contains(id)) id])) {
      final pruned = _prune(tell: false);
      _changed(open: true, groups: pruned);
    }
    return landing;
  }

  /// Takes [id] out of the row without asking where to go: its note is being deleted or archived, and the shell goes
  /// home.
  void drop(String id) {
    if (!_setOpen(closeOpen(_open, id))) return;
    final pruned = _prune(tell: false);
    _changed(open: true, groups: pruned);
  }

  /// [id] moved to sit at [to] among the tabs as drawn. A drag has already said which group it is in ([grouped]); a
  /// move by the keys asks where it landed - into a group, or out of one.
  void move(String id, int to, {bool grouped = false}) {
    final drawn = drawnIds;
    final next = moveOpen(_open, drawn, id, to);
    final openChanged = _setOpen(next);
    var groupsChanged = false;
    if (!grouped) {
      final after = afterMove(_groups, [for (final each in next) if (drawn.contains(each)) each], id);
      if (!sameGroups(after, _groups)) {
        _groups = after;
        groupsChanged = true;
      }
    }
    if (openChanged && _prune(tell: false)) groupsChanged = true;
    if (openChanged || groupsChanged) _changed(open: openChanged, groups: groupsChanged);
  }

  /// The next note shown takes [id]'s tab rather than one of its own; null, it takes one of its own. Read once, by
  /// the note being shown, and every other way of opening a note says null first. A note opened from inside a book
  /// - the index, the chapter bar, the aside - takes the current tab's place (Matt: "the book should open in one tab
  /// instead of each page opening in a new tab").
  // ignore: use_setters_to_change_properties
  void replaceNext(String? id) => _swap = id;
}
