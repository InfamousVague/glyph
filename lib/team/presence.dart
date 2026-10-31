/// Who is on a team's page right now, by page (docs/TEAMSPACES.md, "Presence"; Matt, 2026-10-31: "Build first: all
/// four: the sidebar and page tree, the doc page UI, the teamspace home and members, presence"): the avatars in the
/// open note's header and the dot beside the page's row in the sidebar read this, and nothing of it is stored.
///
/// It says nothing on the wire of its own. Everything it reads is already said in each organization's own room
/// (lib/live/presence.dart, lib/live/team.dart), which every member's device holds while the app is open and signed
/// in: each device's awareness state carries who it is (`user`, its handle and the colour it wears in that
/// organization, the account's or the organization's override) and the note or canvas it has open (`at`, said by
/// lib/live/open.dart as a team note opens and unsaid as it closes). That room is end to end: every message sealed
/// under the organization's key (`sealTeamEnvelope`, bound to the room), so the relay sees neither the note's id nor
/// its title. A personal note is said only in the account's own room, which only the account's own devices hold, and
/// so it is never on anyone's page here.
///
/// **How long someone stays.** The room's awareness (y-protocols, the Rust core's) says each device again every
/// fifteen seconds and forgets one unheard for thirty, on the room's three-second tick; a device that closes the
/// note says nowhere at once; one that goes behind another app lets its socket go (`LiveServices.paused`), and the
/// relay tells the room that connection left, which drops its state the same moment. So there is no expiry of its
/// own here: someone is here for exactly as long as the room has them, and [PagePresence] is told every change.
///
/// What it adds is the view by page rather than by organization: every member on each note, once each however
/// many of their devices have it open, with since when this device has seen them there; this account's own other
/// devices left out (it is you), and an AI left out (never a member present; it has the Claude chip and Follow).
library;

import 'package:flutter/foundation.dart';

import '../live/presence.dart';

/// One member on a page, as its header and its sidebar row draw them.
@immutable
class PresentMember {
  const PresentMember({required this.id, required this.name, required this.since, this.hue, required this.org});

  /// The member: their handle, lower-cased, the one key of a member however their devices spell it.
  final String id;

  /// Their handle as their device says it.
  final String name;

  /// The colour they wear in the organization (one of the app's hues, ember to rose), or null for ink.
  final String? hue;

  /// Since when this device has seen them on the page: the first of their devices to arrive there.
  final DateTime since;

  /// The organization whose room said so.
  final String org;

  /// What their round shows: the handle's first letter, capitalised.
  String get initial => name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();

  @override
  bool operator ==(Object other) => other is PresentMember && other.id == id && other.name == name && other.hue == hue && other.since == since && other.org == org;

  @override
  int get hashCode => Object.hash(id, name, hue, since, org);

  @override
  String toString() => 'PresentMember($name on $org${hue == null ? '' : ', $hue'})';
}

/// Who is on each team page now, by note id, this account left out ([PresentMember]s in the order they came). A
/// [ValueListenable]: told only when who is on some page is different, not on every caret that moves.
class PagePresence extends ChangeNotifier implements ValueListenable<Map<String, List<PresentMember>>> {
  /// [read] answers the other devices in each organization's room as last heard ([Presence.presenceIn] for each one
  /// held), asked again whenever [changes] says so; [self] is the handle signed in, whose own devices are not shown.
  PagePresence({required Map<String, List<Seen>> Function() read, required Listenable changes, required String? Function() self, DateTime Function()? clock})
      : _readRooms = read,
        _changes = changes,
        _self = self,
        _clock = clock ?? DateTime.now {
    _changes.addListener(_refresh);
    _refresh();
  }

  /// The live service's presence read by page: every organization whose room this device holds.
  factory PagePresence.of(Presence live, {required String? Function() handle, DateTime Function()? clock}) => PagePresence(
        read: () => {for (final org in live.heldPresence()) org: live.presenceIn(org)},
        changes: live,
        self: handle,
        clock: clock,
      );

  final Map<String, List<Seen>> Function() _readRooms;
  final Listenable _changes;
  final String? Function() _self;
  final DateTime Function() _clock;

  /// Since when each member has been on each page, by `note|member`: kept while they stay, forgotten as they go, so
  /// one who comes back is new again.
  final Map<String, DateTime> _since = {};
  Map<String, List<PresentMember>> _value = const {};
  bool _disposed = false;

  @override
  Map<String, List<PresentMember>> get value => _value;

  /// Who is on [noteId] now; none for a page nobody else has open, and for every personal note.
  List<PresentMember> presenceOn(String noteId) => _value[noteId] ?? const [];

  void _refresh() {
    if (_disposed) return;
    final me = _self()?.toLowerCase();
    final now = _clock();
    // Each member once per page: their first device's handle and colour, from the organization that says so.
    final found = <String, Map<String, ({String name, String? hue, String org})>>{};
    for (final MapEntry(key: org, value: seen) in _readRooms().entries) {
      for (final device in seen) {
        final at = device.at;
        if (device.ai || at == null || at.note.isEmpty) continue;
        final id = device.handle.toLowerCase();
        if (id.isEmpty || id == me) continue;
        found.putIfAbsent(at.note, () => {}).putIfAbsent(id, () => (name: device.handle, hue: device.hue, org: org));
      }
    }
    final kept = <String>{};
    final next = <String, List<PresentMember>>{};
    for (final MapEntry(key: note, value: members) in found.entries) {
      final list = [
        for (final MapEntry(key: id, value: one) in members.entries)
          PresentMember(id: id, name: one.name, hue: one.hue, org: one.org, since: _since.putIfAbsent('$note|$id', () => now)),
      ];
      for (final member in list) {
        kept.add('$note|${member.id}');
      }
      list.sort((a, b) {
        final when = a.since.compareTo(b.since);
        return when != 0 ? when : a.id.compareTo(b.id);
      });
      next[note] = List.unmodifiable(list);
    }
    _since.removeWhere((key, _) => !kept.contains(key));
    if (_same(next, _value)) return;
    _value = Map.unmodifiable(next);
    notifyListeners();
  }

  static bool _same(Map<String, List<PresentMember>> a, Map<String, List<PresentMember>> b) {
    if (a.length != b.length) return false;
    for (final MapEntry(key: note, value: list) in a.entries) {
      final other = b[note];
      if (other == null || !listEquals(list, other)) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _changes.removeListener(_refresh);
    super.dispose();
  }
}
