import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'workspaces.dart' show workspaceHues;

// The open notes as tabs, the groups over them, and where a dragged tab is: three pure modules of the web app in one
// file, since each is only the other two's rules for one row.
//
// - `notes/openTabs.ts`: the row of open ids.
// - `notes/tabGroups.ts`: Chrome-style groups over the row.
// - `notes/tabDrag.ts`: the place a dragged tab has reached, from the row as measured.
//
// Every function answers a new list or a new [TabGroups]; nothing here is changed in place.

// ---- notes/openTabs.ts ------------------------------------------------------------------------------------------------

/// How many notes stay open (`MOST_TABS`). Past this the one opened longest ago drops off.
const int mostTabs = 8;

/// [id] opened: at the end of the row, or moved nowhere if it is already there. The oldest drops off past [most].
List<String> addOpen(List<String> open, String id, {int most = mostTabs}) {
  if (open.contains(id)) return [...open];
  final next = [...open, id];
  return next.length > most ? next.sublist(next.length - most) : next;
}

/// [to] opened in [from]'s place: moving within a book stays in the book's one tab. Where [to] already has a tab of
/// its own, [from]'s closes and that one is used; where [from] is not in the row, [to] is added as any note is.
List<String> swapOpen(List<String> open, String from, String to) {
  if (from == to) return [...open];
  if (!open.contains(from)) return addOpen(open, to);
  if (open.contains(to)) return [for (final each in open) if (each != from) each];
  return [for (final each in open) each == from ? to : each];
}

/// [id] closed, or gone from the library.
List<String> closeOpen(List<String> open, String id) => [for (final each in open) if (each != id) each];

/// Where to land when the open note is closed: the tab after it, else the one before it, else nowhere (the home
/// page). The same answer serves a note deleted or archived from under the person.
String? afterClose(List<String> open, String id) {
  final at = open.indexOf(id);
  if (at < 0) return open.isEmpty ? null : open.last;
  if (at + 1 < open.length) return open[at + 1];
  return at > 0 ? open[at - 1] : null;
}

/// [id] dragged to sit at [to], counted among the tabs as they are drawn ([shown]): the notes that still exist, so
/// [to] is an index into that row rather than into the whole of [open], which may carry ids the library no longer has.
List<String> moveOpen(List<String> open, List<String> shown, String id, int to) {
  final from = shown.indexOf(id);
  if (from < 0) return [...open];
  final landing = math.max(0, math.min(shown.length - 1, to));
  if (landing == from) return [...open];
  final order = [...shown]
    ..removeAt(from)
    ..insert(landing, id);
  // The ids that are no longer notes keep their places at the end, so nothing is lost by reordering what is visible.
  return [...order, for (final each in open) if (!shown.contains(each)) each];
}

/// The open ids that are still notes, in order: a note deleted on another device leaves no ghost tab.
List<String> openOnly(List<String> open, Set<String> ids) => [for (final id in open) if (ids.contains(id)) id];

// ---- notes/tabGroups.ts -----------------------------------------------------------------------------------------------

/// A tab group (`TabGroup`, notes/tabGroups.ts): a name and a colour over a run of tabs, which folds shut to its chip.
@immutable
class TabGroup {
  const TabGroup({required this.id, required this.name, required this.hue, this.collapsed = false});

  final String id;
  final String name;

  /// One of the colours workspaces wear ([workspaceHues], core/workspaces.dart; ink.css `[data-hue]`), so the two
  /// read as one palette. A colour this build does not know draws as ink.
  final String hue;

  /// Folded shut to its chip.
  final bool collapsed;

  TabGroup copyWith({String? name, String? hue, bool? collapsed}) =>
      TabGroup(id: id, name: name ?? this.name, hue: hue ?? this.hue, collapsed: collapsed ?? this.collapsed);

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'hue': hue, if (collapsed) 'collapsed': true};

  @override
  bool operator ==(Object other) => other is TabGroup && other.id == id && other.name == name && other.hue == hue && other.collapsed == collapsed;

  @override
  int get hashCode => Object.hash(id, name, hue, collapsed);

  @override
  String toString() => 'TabGroup($id, $name, $hue${collapsed ? ', folded' : ''})';
}

/// The groups over the open tabs (`TabGroups`, notes/tabGroups.ts): the groups in the order made, and which group
/// each note's tab is in, by note id.
///
/// Differs from the web: two of these are equal when they say the same thing ([sameGroups] is `==`), where the web
/// compared them as JSON, which also told apart two maps with their keys in a different order.
@immutable
class TabGroups {
  const TabGroups({this.list = const [], this.of = const {}});

  /// `NO_GROUPS`.
  static const TabGroups none = TabGroups();

  final List<TabGroup> list;
  final Map<String, String> of;

  /// The group [noteId]'s tab is in, or null.
  TabGroup? groupOf(String noteId) {
    final id = of[noteId];
    if (id == null) return null;
    for (final group in list) {
      if (group.id == id) return group;
    }
    return null;
  }

  Map<String, Object?> toJson() => {'list': [for (final group in list) group.toJson()], 'of': {...of}};

  /// Tab groups as stored, kept to their shape (`readTabGroups`, core/preferences.ts): a group with a name and a
  /// colour, and tabs that point at one.
  factory TabGroups.fromJson(Object? raw) {
    if (raw is! Map) return TabGroups.none;
    final list = raw['list'], of = raw['of'];
    if (list is! List || of is! Map) return TabGroups.none;
    final groups = <TabGroup>[
      for (final g in list)
        if (g is Map && g['id'] is String && g['name'] is String && g['hue'] is String)
          TabGroup(id: g['id'] as String, name: g['name'] as String, hue: g['hue'] as String, collapsed: g['collapsed'] == true),
    ];
    final known = {for (final g in groups) g.id};
    return TabGroups(
      list: groups,
      of: {
        for (final entry in of.entries)
          if (entry.key is String && entry.value is String && known.contains(entry.value)) entry.key as String: entry.value as String,
      },
    );
  }

  @override
  bool operator ==(Object other) => other is TabGroups && listEquals(other.list, list) && mapEquals(other.of, of);

  @override
  int get hashCode => Object.hash(Object.hashAll(list), Object.hashAllUnordered(of.entries.map((e) => Object.hash(e.key, e.value))));

  @override
  String toString() => 'TabGroups($list, $of)';
}

/// The tabs in the order they are drawn: each group's together, where the first of them is in the open order.
List<String> displayOrder(List<String> open, TabGroups groups) {
  final out = <String>[];
  final drawn = <String>{};
  for (final id in open) {
    final group = groups.of[id];
    if (group == null) {
      out.add(id);
      continue;
    }
    if (!drawn.add(group)) continue;
    for (final member in open) {
      if (groups.of[member] == group) out.add(member);
    }
  }
  return out;
}

/// The open tabs in a group, in the order they are drawn.
List<String> membersOf(TabGroups groups, String group, List<String> open) => [for (final id in open) if (groups.of[id] == group) id];

/// The colour a new group takes: the first no other group is wearing, so groups start out told apart.
String _nextHue(TabGroups groups) {
  final worn = {for (final g in groups.list) g.hue};
  for (final hue in workspaceHues) {
    if (hue != 'ink' && !worn.contains(hue)) return hue;
  }
  return 'ink';
}

/// A new group holding this tab, named "Group" to be renamed, in a colour no other group has.
({TabGroups groups, String id}) newGroup(TabGroups groups, String noteId, {String? id}) {
  final made = id ?? 'g-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
  final group = TabGroup(id: made, name: 'Group', hue: _nextHue(groups));
  return (groups: _tidy(TabGroups(list: [...groups.list, group], of: {...groups.of, noteId: made})), id: made);
}

TabGroups joinGroup(TabGroups groups, String noteId, String group) {
  if (!groups.list.any((g) => g.id == group)) return groups;
  return _tidy(TabGroups(list: groups.list, of: {...groups.of, noteId: group}));
}

TabGroups leaveGroup(TabGroups groups, String noteId) {
  if (!groups.of.containsKey(noteId)) return groups;
  return _tidy(TabGroups(list: groups.list, of: {...groups.of}..remove(noteId)));
}

TabGroups renameGroup(TabGroups groups, String group, String name) {
  var words = name.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (words.length > 40) words = words.substring(0, 40);
  if (words.isEmpty) return groups;
  return TabGroups(list: [for (final g in groups.list) g.id == group ? g.copyWith(name: words) : g], of: groups.of);
}

TabGroups recolourGroup(TabGroups groups, String group, String hue) =>
    TabGroups(list: [for (final g in groups.list) g.id == group ? g.copyWith(hue: hue) : g], of: groups.of);

TabGroups toggleGroup(TabGroups groups, String group) =>
    TabGroups(list: [for (final g in groups.list) g.id == group ? g.copyWith(collapsed: !g.collapsed) : g], of: groups.of);

/// The group goes; its tabs stay open, ungrouped.
TabGroups ungroup(TabGroups groups, String group) => TabGroups(
      list: [for (final g in groups.list) if (g.id != group) g],
      of: {for (final entry in groups.of.entries) if (entry.value != group) entry.key: entry.value},
    );

/// Memberships of tabs that have closed, and groups with nothing left in them, go.
TabGroups pruneGroups(TabGroups groups, List<String> open) {
  final openIds = open.toSet();
  return _tidy(TabGroups(list: groups.list, of: {for (final entry in groups.of.entries) if (openIds.contains(entry.key)) entry.key: entry.value}));
}

/// Where a dragged tab belongs, once it has been dropped at [order] (the new drawn order). Dropped between two tabs
/// of one group, it joins that group. Kept in its own group while either neighbour is still in it, so moving a tab
/// about inside its group, or to its edge, leaves it there. Dropped among tabs of no group, or of another group but
/// not inside it, it leaves.
TabGroups afterMove(TabGroups groups, List<String> order, String noteId) {
  final at = order.indexOf(noteId);
  if (at < 0) return groups;
  final before = at > 0 ? groups.of[order[at - 1]] : null;
  final after = at + 1 < order.length ? groups.of[order[at + 1]] : null;
  final own = groups.of[noteId];
  if (before != null && before == after) return before == own ? groups : joinGroup(groups, noteId, before);
  if (own != null && (before == own || after == own)) return groups;
  return own != null ? leaveGroup(groups, noteId) : groups;
}

/// Whether two sets of groups say the same thing: groups read back from another device, or a prune that found
/// nothing to take out, are not a change worth a render or a write.
bool sameGroups(TabGroups a, TabGroups b) => a == b;

/// No empty group, and no tab pointing at a group that has gone.
TabGroups _tidy(TabGroups groups) {
  final known = {for (final g in groups.list) g.id};
  final of = {for (final entry in groups.of.entries) if (known.contains(entry.value)) entry.key: entry.value};
  final used = of.values.toSet();
  return TabGroups(list: [for (final g in groups.list) if (used.contains(g.id)) g], of: of);
}

// ---- notes/tabDrag.ts -------------------------------------------------------------------------------------------------

/// A tab in the row, or a folded group's chip, as measured on screen (`RowStop`).
@immutable
class RowStop {
  const RowStop({required this.left, required this.width, required this.tabs});
  final double left;
  final double width;

  /// How many tabs it stands for in the order: one for a tab, a folded group's count for its chip.
  final int tabs;
}

/// Which place in the row [x] is over: how many of the tabs' middles it has passed, counted in tabs. The tab being
/// dragged is not among [stops], on purpose: it follows the finger, and measuring it made the row swap and swap back.
int placeAt(List<RowStop> stops, double x) {
  var place = 0;
  for (final stop in stops) {
    if (x > stop.left + stop.width / 2) place += stop.tabs;
  }
  return place;
}

/// Something a dragged tab can be over (`DropSpot`): a tab (in [group], or none), a group's chip, or the + at the
/// row's end.
@immutable
class DropSpot {
  const DropSpot({required this.left, required this.right, this.group});
  final double left;
  final double right;

  /// The group a tab dropped here is in: the tab's own group, the chip's group, or null for a tab of none and the +.
  final String? group;
}

/// Which group a dragged tab belongs in, by what it is over, the way Chrome decides it: over a tab of a group, or the
/// group's chip, it is in that group; over a tab of none, over the + or past either end of the row, it is in none.
/// Between two things, and in a row with nothing in it but the tab being dragged, it stays as it was: `settled` is
/// false, where the web answered `undefined`.
({bool settled, String? group}) groupAt(List<DropSpot> spots, double x) {
  if (spots.isEmpty) return (settled: false, group: null);
  if (x < spots.first.left || x > spots.last.right) return (settled: true, group: null);
  for (final spot in spots) {
    if (x >= spot.left && x <= spot.right) return (settled: true, group: spot.group);
  }
  return (settled: false, group: null);
}

/// A frame at sixty a second, which the coast's slowing is measured in.
const double _frameMs = 16.67;

/// How much of its speed a coasting row loses each frame: a fifteenth.
const double _friction = 1 / 15;

/// Slower than this - a pixel every few frames - and the row has stopped.
const double _still = 0.02;

/// One frame of a flick carrying on: the row [ms] further along from [left] at [pace] pixels a millisecond, slowed,
/// and whether it has now stopped - too slow to see, or at either end of a row that scrolls to [end]. A long gap
/// between frames counts as four at most, so a stalled frame cannot fling the row.
({double left, double pace, bool done}) coasted(double left, double pace, double ms, double end) {
  final frames = math.min(4.0, ms / _frameMs);
  final next = left + pace * _frameMs * frames;
  final slowed = pace * math.pow(1 - _friction, frames);
  return (left: next, pace: slowed, done: slowed.abs() < _still || next <= 0 || next >= end);
}
