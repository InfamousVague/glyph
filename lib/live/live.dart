/// Live sync for this device, made once with the account: the one connection (hub.dart), the notes live with
/// another device (shared.dart), the switch for the account's own notes (enabled.dart), the organizations' rooms
/// (team.dart), who is in each and where (presence.dart, the account's own room too), the editors bound now and
/// Follow (editor_binding.dart, follow.dart), the word that there is something to fetch (nudge.dart), and the
/// service's word that something came for the account (poke.dart). What `App.tsx` gets by importing `core/live` and
/// calling `watchPresence()` and `watchNudges()`.
///
/// Nothing is connected by making it: the hub opens its socket once [LiveServices.start] is watching and the account
/// is signed in, held for the pokes with no room at all (poke.dart), and its rooms come as an organization's own or a
/// note's are held. Signed out, or with settings that keep everything on the device, no room is held and there is no
/// socket.
library;

import 'package:flutter/foundation.dart';

import '../account/account.dart';
import '../account/crypto_api.dart';
import '../core/preferences.dart';
import '../core/stored.dart';
import '../orgs/org_keys.dart';
import '../orgs/orgs.dart';
import '../team/crdt.dart';
import 'editor_binding.dart';
import 'enabled.dart';
import 'follow.dart';
import 'hub.dart';
import 'nudge.dart';
import 'poke.dart';
import 'presence.dart';
import 'shared.dart';
import 'team.dart';
import 'transport.dart';

/// The bundle.
class LiveServices {
  /// [base] is the service's (`http://…/api`); the relay is beside it. [socket] is a test's.
  LiveServices({
    required String base,
    required this.account,
    required AccountCrypto crypto,
    required Crdt crdt,
    required this.orgs,
    required this.orgKeys,
    required this.prefs,
    required Stored kept,
    LiveSocket Function(String url)? socket,
    Duration? tick = const Duration(seconds: 3),
  })  : shared = SharedLive(),
        enabled = LiveEnabled(kept) {
    final url = liveUrl(base);
    String? token() => account.session?.token;
    hub = LiveHub(LiveHubDeps(
      url: url,
      token: token,
      crypto: crypto,
      crdt: crdt,
      accountKey: account.accountKey,
      enabled: () => enabled.value,
      shared: shared,
      connect: socket == null ? null : (events) => WebSocketTransport(url: url, token: token, events: events, socket: socket),
    ));
    rooms = TeamRooms(
      hub: hub,
      crypto: crypto,
      crdt: crdt,
      orgKeyOf: orgKeys.orgKeyOf,
      handle: () => account.session?.handle,
      colourIn: (orgId) => orgs.orgRow(orgId)?.colour,
      accountKey: account.accountKey,
      accountColour: () => orgs.orgsState().colour,
      tick: tick,
    );
    presence = Presence(rooms);
    follow = FollowAi(online: presence.aisOnline, changes: presence, bound: bound);
    nudges = Nudges(hub: hub, hasKey: (orgId) => orgKeys.orgKeyOf(orgId) != null);
    pokes = Pokes(hub: hub);
  }

  final Account account;
  final Orgs orgs;
  final OrgKeys orgKeys;
  final PreferencesStore prefs;
  final SharedLive shared;
  final LiveEnabled enabled;
  late final LiveHub hub;
  late final TeamRooms rooms;
  late final Presence presence;
  late final Nudges nudges;
  late final Pokes pokes;

  /// The notes whose editors are bound on this device now (open.dart puts each).
  final BoundEditors bound = BoundEditors();

  /// The AIs online on the account, and Follow; the root says how a note is opened for it.
  late final FollowAi follow;

  final List<void Function()> _stops = [];

  List<String> _joined() => [
        for (final row in orgs.orgsState().list)
          if (row.state == 'member') row.id,
      ];

  /// The organizations' rooms held for as long as the account is in them (`watchPresence`, `watchNudges`), the
  /// nudges asking [hooks] of the engine; and the connection held while signed in, the service's pokes asking
  /// [pokes] of the account (poke.dart). Once.
  void start(NudgeHooks hooks, [PokeHooks? pokes]) {
    if (_stops.isNotEmpty) return;
    bool signedIn() => account.session != null;
    bool localOnly() => prefs.value.localOnly;
    // The account too: its key is read for the account's own room, which comes once it is unlocked.
    final changes = <Listenable>[orgs, orgKeys, prefs, account];
    _stops
      ..add(presence.watch(PresenceWatch(signedIn: signedIn, localOnly: localOnly, joined: _joined, hasKey: (orgId) => orgKeys.orgKeyOf(orgId) != null, changes: changes)))
      ..add(nudges.watch(hooks, NudgeWatch(signedIn: signedIn, localOnly: localOnly, joined: _joined, changes: changes)));
    if (pokes != null) _stops.add(this.pokes.watch(pokes, PokeWatch(signedIn: signedIn, localOnly: localOnly, changes: changes)));
    follow.start();
  }

  /// The app came back to the front: the connection is tried now.
  void resumed() => hub.wake();

  /// The app left the front: no socket is held until it is back.
  void paused() => hub.rest();

  void dispose() {
    for (final stop in _stops) {
      stop();
    }
    _stops.clear();
    follow.dispose();
    hub.dispose();
  }
}
