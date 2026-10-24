/// The service's word that something came for this account, and what the device does about it (Matt, 2026-10-24:
/// "meetings don't load on the phone app right away I have to wait several minutes for them to sync").
///
/// The sync is passes (lib/sync/engine.dart): at launch, on resume, a couple of seconds after a change made here, and
/// otherwise five minutes apart. So a meeting Ghost was in, ended while the app was open, waited up to five minutes
/// before the phone even asked for its recording; a mail to the account's address the same; and the Meetings page's
/// list read itself once a minute at the most. Now the service pokes every signed-in socket of the account the moment
/// one comes (server/src/live.rs, POKES), and the device fetches at once:
///
/// - **take**: a meeting's recording was kept for the account. The sync now (its Meetings step files it as a note to
///   write up), and the meetings' list read again (the meeting is done).
/// - **meet**: the meetings' list changed (an invite booked, moved or called off, a skip, the bot joining or leaving,
///   a series booking its next). The list read again ([PokeHooks.meetings]); nothing to sync.
/// - **mail**: a mail was filed. The sync now (its Mail step).
/// - Anything else, from a newer service: the sync now, which fetches whatever it is.
///
/// A poke says nothing else - no id, no title - and what is fetched is fetched by the routes it always was, with this
/// device's own token. Several in a breath are one fetch, [settle] after the first (400 ms, as nudge.dart's), and a
/// sync asked for while one runs is the one after it (the engine's queue). When the socket comes back after dropping
/// with the app in front, the pokes missed meanwhile are made up for with one of each.
///
/// The socket: held while the app is in front and signed in, with settings that let the account sync, even with no
/// note open and no organization ([LiveHub.keepOpen]); let go behind, as every room is ([LiveHub.rest]), the resume's
/// own sync fetching what came meanwhile. An older service sends no pokes, and the device fetches at its passes as it
/// always did.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'hub.dart';

/// Several pokes in a breath are one fetch.
const Duration _settle = Duration(milliseconds: 400);

/// The words, as the service says them.
const String pokeTake = 'take';
const String pokeMeet = 'meet';
const String pokeMail = 'mail';

/// What a poke asks of the account.
class PokeHooks {
  const PokeHooks({required this.sync, this.meetings});

  /// The sync now (the engine's `syncNow`): its Mail and Meetings steps fetch what came.
  final Future<void> Function() sync;

  /// The meetings' list read now ([MeetIn.readNow]); none where the service's meetings are not offered.
  final void Function()? meetings;
}

/// What the watch reads of the account.
class PokeWatch {
  const PokeWatch({required this.signedIn, required this.localOnly, required this.changes});
  final bool Function() signedIn;
  final bool Function() localOnly;
  final List<Listenable> changes;
}

/// The connection held for the pokes, and each poke turned into a fetch.
class Pokes {
  Pokes({required this.hub, Duration settle = _settle}) : _rest = settle;

  final LiveHub hub;
  final Duration _rest;

  PokeHooks? _hooks;
  Timer? _settling;
  bool _sync = false;
  bool _meetings = false;

  void _heard(String what) {
    switch (what) {
      case pokeMeet:
        _meetings = true;
      case pokeTake:
        _sync = true;
        _meetings = true;
      default:
        // `mail`, and any word a newer service says: the sync fetches whatever it is.
        _sync = true;
    }
    _settling ??= Timer(_rest, _fetch);
  }

  void _fetch() {
    _settling = null;
    final hooks = _hooks;
    final sync = _sync, meetings = _meetings;
    _sync = _meetings = false;
    if (hooks == null) return;
    if (sync) unawaited(hooks.sync().catchError((Object _) {}));
    if (meetings) hooks.meetings?.call();
  }

  /// Holds the connection while signed in and not local-only, lets it go when that stops being so, and fetches on
  /// each poke. Answers the way to stop.
  void Function() watch(PokeHooks hooks, PokeWatch of) {
    _hooks = hooks;
    final stopListening = hub.listenPokes(
      poked: _heard,
      back: () {
        _heard(pokeTake);
        _heard(pokeMail);
      },
    );
    void settle() => hub.keepOpen(of.signedIn() && !of.localOnly());
    settle();
    for (final each in of.changes) {
      each.addListener(settle);
    }
    return () {
      for (final each in of.changes) {
        each.removeListener(settle);
      }
      stopListening();
      hub.keepOpen(false);
      _hooks = null;
      _settling?.cancel();
      _settling = null;
      _sync = _meetings = false;
    };
  }
}
