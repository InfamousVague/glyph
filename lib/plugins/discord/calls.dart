/// Ghost in a Discord call, the Discord plugin's half on the device (docs/DISCORD_CALLS.md; Matt, 2026-10-26: "Add a
/// new plugin to post notes to discord chats as well as join discord calls to summarize meetings", and the same day:
/// Discord calls belong to the Discord plugin, its own switch and its linking on the plugin's page). The pure and
/// the talking parts; the page's section is calls_section.dart.
///
/// - **Linking**: the person links their Discord once, with a code. [DiscordCalls.makeCode] sees to the account's
///   encryption key first (a call is sealed to it on arrival, as a Meet's take is), then asks the service for a code
///   (`POST discord/link-code`: eight letters, `K7QM-2XRP`, good once and for ten minutes). They run `/ghost link
///   K7QM-2XRP` in Discord; the page reads the link every few seconds while a code is showing, so the linked name
///   comes up by itself ([DiscordCalls.watchFor]). Unlink is `DELETE discord/link`.
/// - **The switch**: "Join Discord calls", the link's own flag on the service (`PUT discord/calls {on}`), on from the
///   linking. The bot reads it on every `/ghost join` and refuses while it is off. The service holds it, not the
///   synced preferences, because the bot has no key.
/// - **The plugin off**: a pass of the sync on a device where the plugin is off turns the switch off on the service
///   ([discordCallsFollowPlugin]), once, so a plugin taken out in the Market stops Ghost joining calls too; it is
///   turned on again from the page, by hand. Remembered on the device (`glyph-discord-calls-told-off`) so a device
///   with the plugin off asks nothing again.
/// - **The calls**: Discord calls are bookings like any meeting's, `kind` `discord` (server/src/meet.rs `kind_of`),
///   listed by `GET meet` with the rest ([MeetIn.meetings]); the page lists only those ([discordCallsOf]). Their takes
///   are filed by the same meet pass (lib/meet/meet_in.dart), written up and named the same way.
///
/// Against a service with no Discord routes (`no such route`), everything here is quiet and the page says Discord
/// calls are not on this service yet.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../account/api.dart';
import '../../account/crypto_api.dart';
import '../../account/enc_key.dart';
import '../../account/keystore.dart';
import '../../account/session.dart';
import '../../core/stored.dart';
import '../../meet/gmt.dart' show MeetService;
import '../../meet/meet_api.dart' show MeetBooking;
import '../registry.dart' show pluginOn;
import 'manifest.dart';

/// The account's link to a Discord user, as the service says it.
@immutable
class DiscordLink {
  const DiscordLink({required this.name, required this.linkedAt, required this.calls});

  /// The Discord username they linked as.
  final String name;
  final int linkedAt;

  /// "Join Discord calls".
  final bool calls;

  static DiscordLink? fromJson(Object? raw) {
    if (raw is! Map || raw['name'] is! String) return null;
    return DiscordLink(name: raw['name'] as String, linkedAt: raw['linkedAt'] is num ? (raw['linkedAt'] as num).toInt() : 0, calls: raw['calls'] != false);
  }
}

/// A code to link with, and when it runs out (ms).
@immutable
class DiscordCode {
  const DiscordCode({required this.code, required this.expiresAt});
  final String code;
  final int expiresAt;
}

/// The Discord routes, over one [Api] (server/src/discord.rs).
class DiscordCallsApi {
  const DiscordCallsApi(this.api);
  final Api api;

  /// The link, or none, and the Discord application's id the service has (for "Add Ghost to a server"); null from a
  /// service with no Discord routes.
  Future<({DiscordLink? link, String? appId})?> link(String token) async {
    try {
      final said = await api.callMap('GET', 'discord/link', token: token);
      final appId = said['appId'];
      return (link: DiscordLink.fromJson(said['link']), appId: appId is String && RegExp(r'^[0-9]{15,21}$').hasMatch(appId) ? appId : null);
    } catch (failure) {
      if (notYet(failure)) return null;
      rethrow;
    }
  }

  Future<DiscordCode> code(String token) async {
    final said = await api.callMap('POST', 'discord/link-code', token: token);
    final code = said['code'];
    if (code is! String) throw const ApiError(500, 'The service sent no code.');
    return DiscordCode(code: code, expiresAt: said['expiresAt'] is num ? (said['expiresAt'] as num).toInt() : 0);
  }

  Future<DiscordLink?> setCalls(String token, bool on) async => DiscordLink.fromJson((await api.callMap('PUT', 'discord/calls', token: token, body: {'on': on}))['link']);

  Future<void> unlink(String token) => api.call('DELETE', 'discord/link', token: token);
}

/// The account's Discord calls among [meetings]: those the service says are Discord's.
List<MeetBooking> discordCallsOf(List<MeetBooking>? meetings) => [for (final m in meetings ?? const <MeetBooking>[]) if (m.service == MeetService.discord) m];

/// The page's side: the link as last read, a code while one is showing, and what a press does.
class DiscordCalls extends ChangeNotifier {
  DiscordCalls({required this.account, required this.keys, required this.api, required this.crypto});

  final AccountSource account;
  final KeyStore keys;
  final Api api;
  final AccountCrypto crypto;

  DiscordLink? _link;
  String? _appId;
  bool _read = false;
  bool _available = true;
  DiscordCode? _code;
  String? _problem;
  bool _busy = false;
  Timer? _watch;

  /// The link; null until read, or with none.
  DiscordLink? get link => _link;

  /// The Discord application's id, from the service (or this build's `GHOST_DISCORD_APP_ID`); null where neither has
  /// one.
  String? get appId => _appId;

  /// Whether the link has been read at least once.
  bool get read => _read;

  /// Whether the service has the Discord routes at all.
  bool get available => _available;

  /// The code showing, until it is used or runs out.
  DiscordCode? get code => _code;

  /// Why the last thing pressed did not work; null once something has.
  String? get problem => _problem;

  bool get busy => _busy;

  /// How often the link is read while a code is showing.
  static const Duration watchEvery = Duration(seconds: 4);

  /// The time now, ms; a test moves it on.
  @visibleForTesting
  int Function() clock = () => DateTime.now().millisecondsSinceEpoch;

  String _token() {
    final session = account.session;
    if (session == null) throw const ApiError(401, 'Sign in under Settings › Account first.');
    return session.token;
  }

  /// The link read now.
  Future<void> refresh() async {
    if (account.session == null) return;
    try {
      final said = await DiscordCallsApi(api).link(_token());
      _available = said != null;
      final was = _link;
      _link = said?.link;
      _appId = said?.appId ?? _appId;
      _read = true;
      // Linked with the code that was showing: it is used.
      if (_link != null && (was == null || was.linkedAt != _link!.linkedAt)) _code = null;
      if (_code != null && clock() >= _code!.expiresAt) _code = null;
      if (_code == null) _stopWatching();
    } catch (failure) {
      _problem = 'Your Discord link could not be read just now.';
    }
    notifyListeners();
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    _busy = true;
    _problem = null;
    notifyListeners();
    try {
      await work();
    } on ApiError catch (failure) {
      _problem = failure.message;
    } catch (_) {
      _problem = 'That did not work just now. Try again.';
    }
    _busy = false;
    notifyListeners();
  }

  /// "Link Discord": the account's encryption key seen to, then a code, read for the link until it is used.
  Future<void> makeCode() => _run(() async {
        final token = _token();
        final accountKey = await account.accountKey();
        if (accountKey == null) throw const ApiError(409, 'Sign in again on this device first: its key is not here.');
        await ensureEncryptionKey(EncryptionKeyContext(token: token, accountKey: accountKey, keys: keys, api: api, crypto: crypto));
        _code = await DiscordCallsApi(api).code(token);
        watchFor();
      });

  /// The link read every [watchEvery] while a code shows, so the name comes up once `/ghost link` is run.
  @visibleForTesting
  void watchFor() {
    _watch?.cancel();
    _watch = Timer.periodic(watchEvery, (_) => unawaited(refresh()));
  }

  void _stopWatching() {
    _watch?.cancel();
    _watch = null;
  }

  /// "Join Discord calls" switched.
  Future<void> setCalls(bool on) => _run(() async {
        _link = await DiscordCallsApi(api).setCalls(_token(), on) ?? _link;
      });

  /// "Unlink": the link let go on the service; Ghost answers this Discord user's `/ghost join` with how to link.
  Future<void> unlink() => _run(() async {
        await DiscordCallsApi(api).unlink(_token());
        _link = null;
        _code = null;
        _stopWatching();
      });

  @override
  void dispose() {
    _stopWatching();
    super.dispose();
  }
}

/// What this device remembers it told the service, so a device with the plugin off asks once.
const String discordCallsToldOffKey = 'glyph-discord-calls-told-off';

/// A sync pass's word on the switch (see the header): with the plugin off on this device and not yet told, "Join
/// Discord calls" off on the service; with it on, the memory cleared, so it is told again if it goes off. Quiet: a
/// service without the routes, an account with no link (404) and a failure are all let be, the first two remembered.
Future<void> discordCallsFollowPlugin({required Api api, required String token, required Stored kept, bool Function()? on}) async {
  final pluginIsOn = (on ?? () => pluginOn(manifest))();
  final told = kept.read<bool>(discordCallsToldOffKey, false, (raw) => raw == true);
  if (pluginIsOn) {
    if (told) kept.write(discordCallsToldOffKey, false);
    return;
  }
  if (told) return;
  try {
    await DiscordCallsApi(api).setCalls(token, false);
    kept.write(discordCallsToldOffKey, true);
  } on ApiError catch (failure) {
    // No such route, or nothing linked: there is nothing to turn off, now or later.
    if (failure.status == 404) kept.write(discordCallsToldOffKey, true);
  } catch (_) {
    // Offline: the next pass tries again.
  }
}
