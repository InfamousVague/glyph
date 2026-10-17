/// Who is in each organization right now, and where (docs/SHARED.md, S6). A port of
/// `src/app/core/live/presence.ts`.
///
/// Every member's device holds the organization's own room while the app is open and signed in, and says in it
/// which note or canvas it has open and where its caret or pointer is, so the dashboard reads "editing Roadmap"
/// beside a member and Jump to cursor opens that note at that place. Nothing of it is kept: a device that leaves
/// is gone from the list the moment the relay says so.
///
/// The account has a presence room of its own too (docs/CLAUDE_LIVE.md, "Presence rooms"): every device of the
/// account holds it while signed in and says there which personal note it is on, and the account's connector says
/// there what Claude is doing in personal notes. An AI's entry (`user.ai`) is never a member present: it is kept
/// beside the people, as [Seen.ai], and gathered from every room as [Presence.aisOnline] for the AI's row, the
/// Claude chip in the top bar and Follow (follow.dart).
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
  const Whereabouts({required this.note, required this.title, this.kind = 'note', this.cursor, this.pointer, this.doing});

  static Whereabouts? of(Object? raw) {
    if (raw is! Map) return null;
    final note = raw['note'], title = raw['title'], cursor = raw['cursor'], doing = raw['doing'];
    if (note is! String) return null;
    return Whereabouts(
      note: note,
      title: title is String ? title : '',
      kind: raw['kind'] == 'canvas' ? 'canvas' : 'note',
      cursor: cursor is Map ? cursor.cast<String, Object?>() : null,
      pointer: Spot.of(raw['pointer']),
      doing: doing == 'reading' || doing == 'editing' ? doing as String : null,
    );
  }

  final String note;
  final String title;

  /// `note` or `canvas`.
  final String kind;

  /// A caret as Yjs relative positions (`{anchor, head}`): good in every member's copy of the document.
  final Map<String, Object?>? cursor;

  /// On a canvas: the pointer's place in canvas space (S9).
  final Spot? pointer;

  /// What an AI is doing there, `reading` or `editing` (docs/CLAUDE_LIVE.md); a person's device says nothing, its
  /// having the note open being the editing.
  final String? doing;

  Map<String, Object?> toJson() => {'note': note, 'title': title, 'kind': kind, 'cursor': cursor, 'pointer': pointer?.toJson(), 'doing': ?doing};
}

/// One device of a member's, or an AI, as the room has it (`Seen`).
class Seen {
  const Seen({required this.handle, required this.hue, required this.at, required this.client, this.ai = false, this.via});

  /// A member's handle; an AI's name.
  final String handle;
  final String? hue;
  final Whereabouts? at;
  final int client;

  /// An AI through a member's connector (`user.ai`): never a member present.
  final bool ai;

  /// Whose connector it is, for an AI.
  final String? via;
}

/// An AI online on this account (docs/CLAUDE_LIVE.md, "Claude online"), as one of the rooms last heard it: the one
/// that says where it is, when one does.
@immutable
class AiOnline {
  const AiOnline({required this.name, required this.client, this.hue, this.via, this.at, this.org});

  final String name;

  /// Its awareness client in the room it was heard in.
  final int client;
  final String? hue;
  final String? via;
  final Whereabouts? at;

  /// The organization whose room said [at], or null for the account's own room (a personal note).
  final String? org;

  /// One AI whichever room it is heard in: its name and whose connector it is.
  String get key => aiKey(name, via);

  /// `reading`, `editing`, or null while it is on no note.
  String? get doing => at == null ? null : (at!.doing ?? 'editing');

  /// "editing Roadmap", "reading Roadmap", or "online".
  String get words => aiDoingWords(doing, at?.title);

  @override
  bool operator ==(Object other) =>
      other is AiOnline && other.name == name && other.client == client && other.hue == hue && other.via == via && other.org == org && '${other.at?.toJson()}' == '${at?.toJson()}';

  @override
  int get hashCode => Object.hash(name, client, hue, via, org, '${at?.toJson()}');

  @override
  String toString() => 'AiOnline($name via $via: $words${org == null ? '' : ' in $org'})';
}

/// The one key of an AI (`name` and `via`), the same in every room.
String aiKey(String name, String? via) => '${name.toLowerCase()}|${via?.toLowerCase() ?? ''}';

/// What an AI is doing, in the words its row, the chip and the home page say: "editing Roadmap", "reading
/// Roadmap", or "online" while it is on no note.
String aiDoingWords(String? doing, String? title) {
  if (doing == null) return 'online';
  final what = title == null || title.isEmpty ? 'a note' : title;
  return '$doing $what';
}

/// What the watch reads of the account (`watchPresence`'s imports).
class PresenceWatch {
  const PresenceWatch({required this.signedIn, required this.localOnly, required this.joined, required this.hasKey, required this.changes, this.account = true});

  final bool Function() signedIn;
  final bool Function() localOnly;

  /// The ids of the organizations this account is a member of.
  final List<String> Function() joined;
  final bool Function(String orgId) hasKey;

  /// Whatever says one of those changed: the organizations, their keys, the preferences.
  final List<Listenable> changes;

  /// Whether the account's own presence room is held too (docs/CLAUDE_LIVE.md); a test of the organizations' rooms
  /// alone leaves it out.
  final bool account;
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

  /// The account's own room, while held, and who is in it; and what this device last said there.
  TeamRoom? _account;
  void Function()? _accountStop;
  List<Seen> _accountSeen = const [];
  Whereabouts? _accountAnnounced;

  /// The account's room is on its way (its key is read first): asked for once at a time.
  bool _accountOpening = false;

  static List<Seen> _read(TeamRoom? room) => [
        if (room != null)
          for (final MapEntry(key: client, value: state) in room.states.entries)
            if (client != room.clientId)
              if (Me.of(state['user']) case final user?) Seen(handle: user.name, hue: user.hue, at: Whereabouts.of(state['at']), client: client, ai: user.ai, via: user.via),
      ];

  void _refresh(String orgId) {
    _seen[orgId] = _read(_held[orgId]);
    notifyListeners();
  }

  void _refreshAccount() {
    _accountSeen = _read(_account);
    notifyListeners();
  }

  /// The other members' devices in an organization, as last heard, and the AIs there ([Seen.ai]); none while this
  /// device holds no room of it (`presenceIn`).
  List<Seen> presenceIn(String orgId) => _seen[orgId] ?? const [];

  /// The account's other devices and its AIs, in its own room, as last heard; none while it is not held.
  List<Seen> accountPresence() => _accountSeen;

  /// Whether the account's own room is held, for tests.
  bool get holdsAccount => _account != null;

  /// Every AI online on the account, once each whichever rooms it is in: the room that says it is on a note when
  /// one does, an `editing` before a `reading`. In the order of their names.
  List<AiOnline> aisOnline() {
    final best = <String, AiOnline>{};
    int rank(AiOnline ai) => ai.at == null ? 0 : (ai.doing == 'editing' ? 2 : 1);
    void take(Seen seen, String? org) {
      if (!seen.ai) return;
      final ai = AiOnline(name: seen.handle, client: seen.client, hue: seen.hue, via: seen.via, at: seen.at, org: org);
      final held = best[ai.key];
      if (held == null || rank(ai) > rank(held)) best[ai.key] = ai;
    }

    for (final seen in _accountSeen) {
      take(seen, null);
    }
    for (final MapEntry(key: org, value: list) in _seen.entries) {
      for (final seen in list) {
        take(seen, org);
      }
    }
    return best.values.toList()..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  /// Where this device is in an organization (a note or a canvas open, and the caret or pointer in it), or nowhere
  /// (`announce`).
  void announce(String orgId, Whereabouts? at) {
    _announced[orgId] = at;
    _held[orgId]?.setField('at', at?.toJson());
  }

  /// Where this device is among the account's own notes (a personal note open), or nowhere: said in the account's
  /// room, as [announce] says it in an organization's.
  void announceAccount(Whereabouts? at) {
    _accountAnnounced = at;
    _account?.setField('at', at?.toJson());
  }

  /// The organizations whose rooms this device holds, for tests (`heldPresence`).
  List<String> heldPresence() => _held.keys.toList();

  void _drop(String orgId) {
    _stops.remove(orgId)?.call();
    _held.remove(orgId)?.close();
    _seen.remove(orgId);
    notifyListeners();
  }

  void _dropAccount() {
    _accountStop?.call();
    _accountStop = null;
    _account?.close();
    _account = null;
    if (_accountSeen.isEmpty) return;
    _accountSeen = const [];
    notifyListeners();
  }

  /// Holds the organization's own room for every organization this account is a member of and holds the key to,
  /// while signed in and not local-only, and lets each go when that stops being so; the colour worn is said again
  /// when it changes. The account's own room the same, while signed in. Answers the way to stop, which lets every
  /// room go (`watchPresence`).
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
      _settleAccount(of, () => stopped);
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
      _dropAccount();
    };
  }

  /// The account's own room held while signed in and not local-only, and let go when that stops; its key is read
  /// first, so it comes a moment after it is wanted, and a room that came once it was no longer wanted goes again.
  void _settleAccount(PresenceWatch of, bool Function() stopped) {
    bool wanted() => of.account && of.signedIn() && !of.localOnly();
    final held = _account;
    if (!wanted()) {
      if (held != null) _dropAccount();
      return;
    }
    if (held != null) {
      final me = _rooms.meInAccount();
      if (held.me != me) held.setMe(me);
      return;
    }
    if (_accountOpening) return;
    _accountOpening = true;
    _rooms.openAccountPresenceRoom().then((room) {
      _accountOpening = false;
      if (room == null) return;
      if (stopped() || _account != null || !wanted()) {
        room.close();
        return;
      }
      _account = room;
      _accountStop = room.onChange(_refreshAccount);
      final said = _accountAnnounced;
      if (said != null) room.setField('at', said.toJson());
      _refreshAccount();
    }, onError: (Object _) {
      _accountOpening = false;
    });
  }
}
