/// Who is on, wherever someone's face is drawn (lib/ui/common.dart Avatar; Matt, 2026-11-17: "activity presence
/// sensing for friends and conacts on telegram and signal to be able to tell if a friend is online on a given plaform
/// anywhere the users avatar is shown", and "especially required for our own API reporting presence sensing within the
/// app for users who have signed up for a username and are part of our own system").
///
/// Ghost Messaging's own first: someone this phone shares keys with (by their number) or a friend by username
/// (`@name`), as the relay server's hub says they come and go and put the app away (lib/net/hub_carrier.dart). Then
/// the other networks that say so (Telegram; lib/inbox/inbox.dart). Online anywhere wins.
library;

import 'package:flutter/foundation.dart';

import 'friends/buddies.dart';
import 'inbox/inbox.dart';
import 'net/net.dart';

class Presence {
  Presence._();

  /// Told whenever anyone's presence changes, on our own system or another network.
  static Listenable get changes => Listenable.merge([Net.instance.presence, Inbox.instance.presenceChanges]);

  /// The install name on our own system of whoever [address] names: a friend by username (`@name`), or someone this
  /// phone shares keys with, by their number. Null for anyone else.
  static String? ghostIdOf(String address) {
    if (address.startsWith('@')) {
      final name = address.substring(1).toLowerCase();
      for (final b in Buddies.instance.all) {
        if (b.username.toLowerCase() == name) return b.id;
      }
      return null;
    }
    if (address.contains(':')) return null;
    return Net.instance.byAddress(address)?.id;
  }

  /// Whether whoever [address] names is on now, and where; or when they were last seen. Null where nothing is known.
  static InboxPresence? of(String address) {
    final id = ghostIdOf(address);
    final g = id == null ? null : Net.instance.presenceOfId(id);
    final ghost = g == null ? null : InboxPresence(network: 'Ghost Messaging', online: g.online, lastSeen: g.lastSeen, away: g.away, busy: g.busy);
    // Busy or away on Ghost is how they chose to be shown: it wins over being online elsewhere.
    if (ghost != null && (ghost.online || ghost.busy || ghost.away)) return ghost;
    final other = Inbox.instance.presenceOfAddress(address);
    if (other != null && other.online) return other;
    if (ghost == null) return other;
    if (other == null) return ghost;
    // Neither on: whichever saw them last.
    final a = ghost.lastSeen, b = other.lastSeen;
    if (a == null) return other;
    if (b == null) return ghost;
    return a.isAfter(b) ? ghost : other;
  }
}
