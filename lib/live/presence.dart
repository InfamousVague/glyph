/// Who is in each organization right now, and where (docs/SHARED.md, S6). A port of
/// `src/app/core/live/presence.ts`.
///
/// Every member's device holds the organization's own room while the app is open and signed in, and says in it
/// which note or canvas it has open and where its caret or pointer is, so the dashboard reads "editing Roadmap"
/// beside a member and Jump to cursor opens that note at that place. Nothing of it is kept: a device that leaves
/// is gone from the list the moment the relay says so.
///
/// What differs: the page's module (its rooms, what was seen, what was announced, and `usePresence`) is a
/// [Presence] made once with the account, a [ChangeNotifier] the screens listen to; `watchPresence` is
/// [Presence.watch]. `caretColours` and `meIn` are beside the rooms (team.dart).
library;

import 'package:flutter/foundation.dart';

import 'team.dart';

/// A place on a canvas, in the canvas's own pixels: a member's pointer (S9).
class Spot {
  const Spot(this.x, this.y);

  static Spot? of(Object? raw) {
    if (raw is! Map) return null;
    final x = raw['x'], y = raw['y'];
    return x is num && y is num ? Spot(x.toDouble(), y.toDouble()) : null;
  }

  final double x;
  final double y;

  Map<String, Object?> toJson() => {'x': x, 'y': y};
}

/// Where a device is in an organization: the note or canvas it has open, and the place in it (`Whereabouts`).
class Whereabouts {
  const Whereabouts({required this.note, required this.title, this.kind = 'note', this.cursor, this.pointer});

  static Whereabouts? of(Object? raw) {
    if (raw is! Map) return null;
    final note = raw['note'], title = raw['title'], cursor = raw['cursor'];
    if (note is! String) return null;
    return Whereabouts(note: note, title: title is String ? title : '', kind: raw['kind'] == 'canvas' ? 'canvas' : 'note', cursor: cursor is Map ? cursor.cast<String, Object?>() : null, pointer: Spot.of(raw['pointer']));
  }

  final String note;
  final String title;

  /// `note` or `canvas`.
  final String kind;

  /// A caret as Yjs relative positions (`{anchor, head}`): good in every member's copy of the document.
  final Map<String, Object?>? cursor;

  /// On a canvas: the pointer's place in canvas space (S9).
  final Spot? pointer;

  Map<String, Object?> toJson() => {'note': note, 'title': title, 'kind': kind, 'cursor': cursor, 'pointer': pointer?.toJson()};
}

/// One device of a member's, as the room has it (`Seen`).
class Seen {
  const Seen({required this.handle, required this.hue, required this.at, required this.client});
  final String handle;
  final String? hue;
  final Whereabouts? at;
  final int client;
}

/// What the watch reads of the account (`watchPresence`'s imports).
class PresenceWatch {
  const PresenceWatch({required this.signedIn, required this.localOnly, required this.joined, required this.hasKey, required this.changes});

  final bool Function() signedIn;
  final bool Function() localOnly;

  /// The ids of the organizations this account is a member of.
  final List<String> Function() joined;
  final bool Function(String orgId) hasKey;

  /// Whatever says one of those changed: the organizations, their keys, the preferences.
  final List<Listenable> changes;
}

/// The store the screens read, and the switch.
class Presence extends ChangeNotifier {
  Presence(this._rooms);

  final TeamRooms _rooms;
  final Map<String, TeamRoom> _held = {};
  final Map<String, void Function()> _stops = {};
  final Map<String, List<Seen>> _seen = {};

  /// What this device last said of itself per organization, said again when the room comes.
  final Map<String, Whereabouts?> _announced = {};

  void _refresh(String orgId) {
    final room = _held[orgId];
    final list = <Seen>[];
    if (room != null) {
      for (final MapEntry(key: client, value: state) in room.states.entries) {
        if (client == room.clientId) continue;
        final user = Me.of(state['user']);
        if (user == null) continue;
        list.add(Seen(handle: user.name, hue: user.hue, at: Whereabouts.of(state['at']), client: client));
      }
    }
    _seen[orgId] = list;
    notifyListeners();
  }

  /// The other members' devices in an organization, as last heard; none while this device holds no room of it
  /// (`presenceIn`).
  List<Seen> presenceIn(String orgId) => _seen[orgId] ?? const [];

  /// Where this device is in an organization (a note or a canvas open, and the caret or pointer in it), or nowhere
  /// (`announce`).
  void announce(String orgId, Whereabouts? at) {
    _announced[orgId] = at;
    _held[orgId]?.setField('at', at?.toJson());
  }

  /// The organizations whose rooms this device holds, for tests (`heldPresence`).
  List<String> heldPresence() => _held.keys.toList();

  void _drop(String orgId) {
    _stops.remove(orgId)?.call();
    _held.remove(orgId)?.close();
    _seen.remove(orgId);
    notifyListeners();
  }

  /// Holds the organization's own room for every organization this account is a member of and holds the key to,
  /// while signed in and not local-only, and lets each go when that stops being so; the colour worn is said again
  /// when it changes. Answers the way to stop, which lets every room go (`watchPresence`).
  void Function() watch(PresenceWatch of) {
    var stopped = false;
    void settle() {
      if (stopped) return;
      final wanted = of.signedIn() && !of.localOnly() ? [for (final id in of.joined()) if (of.hasKey(id)) id] : const <String>[];
      for (final id in _held.keys.toList()) {
        if (!wanted.contains(id)) _drop(id);
      }
      for (final id in wanted) {
        final held = _held[id];
        if (held != null) {
          final me = _rooms.meIn(id);
          if (held.me != me) held.setMe(me);
          continue;
        }
        final room = _rooms.openPresenceRoom(id);
        if (room == null) continue;
        _held[id] = room;
        _stops[id] = room.onChange(() => _refresh(id));
        if (_announced.containsKey(id)) room.setField('at', _announced[id]?.toJson());
        _refresh(id);
      }
    }

    settle();
    for (final each in of.changes) {
      each.addListener(settle);
    }
    return () {
      stopped = true;
      for (final each in of.changes) {
        each.removeListener(settle);
      }
      for (final id in _held.keys.toList()) {
        _drop(id);
      }
    };
  }
}
