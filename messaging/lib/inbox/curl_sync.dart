import 'dart:async';
import 'dart:convert';

import '../account/account.dart';
import '../app_state.dart';
import '../me/me.dart';
import 'account_helper.dart';
import 'inbox.dart';

/// The third-party sign-in cookies ("cURL entries") a Chrome extension captures on one device, synced to the rest
/// through the Ghost account so a service signed in once is signed in everywhere (Matt, 2026-11-21: "make a chrome
/// plugin that works with ghost messaging to handle getting all the curl keys ... sync the cURL entries across all
/// devices so we don't need to login to things like instagram on every device if we're already logged into a ghost
/// account").
///
/// The extension (messaging/extension) logs into the account, captures the cookies of a signed-in browser for each
/// cookie-login service (Messenger, Instagram, LinkedIn, and any added later), seals them with a key only the
/// account's devices have (the backup's kept_key, Me.curlKeep), and keeps them on the relay. Every device reads them
/// back as it reaches the relay ([pull]) and, for each service it is not already signed in to, switches that plugin
/// on and signs it in with the cookies — the same path a pasted sign-in takes (AccountHelper.signIn).
///
/// The relay holds only the sealed blob; it cannot read the cookies. One blob per account (keyed by the shared Ghost
/// identity), last writer wins, so the extension reads-modifies-writes it, and so does [share] (a sign-in made in the
/// app, for the account's other devices).
class CurlSync {
  CurlSync._() {
    AccountHelper.onShare = (id, cookies) => unawaited(share(id, cookies));
  }
  static final CurlSync instance = CurlSync._();

  /// The app's choices, set as the app starts: nothing is read or shared before then.
  AppState? _app;
  AppState? get app => _app;
  set app(AppState? a) {
    _app = a;
    // Read again every few minutes while the app runs, not only as the relay says hello or the app comes to the front:
    // a computer's window stays open for days (Matt, 2026-11-21: "Plugins should sync across devices also").
    _every?.cancel();
    if (a != null) _every = Timer.periodic(const Duration(minutes: 2), (_) => unawaited(pull()));
  }

  Timer? _every;

  /// A [pull] is running: another asked for meanwhile is passed over.
  bool _busy = false;

  /// What the account keeps: `{v:1, entries:{<serviceId>:{cookies:{name:value}, at:ms, from:'<label>'}}}`.
  static const _version = 1;

  /// Reads the synced entries and signs in any service this device isn't already on. Safe to call on every reconnect.
  Future<void> pull() async {
    final app = this.app;
    if (app == null || _busy) return;
    _busy = true;
    try {
      final kept = await Me.instance.curlKept();
      if (kept == null || kept['v'] != _version) return;
      final entries = (kept['entries'] as Map? ?? const {}).cast<String, Object?>();
      for (final e in entries.entries) {
        final entry = e.value;
        if (entry is! Map) continue;
        final cookies = (entry['cookies'] as Map?)?.cast<String, Object?>();
        if (cookies == null || cookies.isEmpty) continue;
        final at = (entry['at'] as num?)?.toInt() ?? 0;
        await _apply(app, e.key, {for (final c in cookies.entries) c.key: '${c.value}'}, at);
      }
    } catch (_) {
      // A blob that can't be opened (no account key yet, or a newer format) just means nothing to apply.
    } finally {
      _busy = false;
    }
  }

  /// Keeps [cookies], a sign-in to [serviceId] just made on this device, for the account's other devices: read, joined
  /// and written back whole (the plugin list and the other entries kept as they are). Marked applied here, so this
  /// device doesn't sign in with it again.
  Future<void> share(String serviceId, Map<String, String> cookies) async {
    final app = this.app;
    if (app == null || cookies.isEmpty) return;
    try {
      final kept = await Me.instance.curlKept(strict: true) ?? {'v': _version};
      if (kept['v'] != _version) return;
      final entries = Map<String, Object?>.from((kept['entries'] as Map?)?.cast<String, Object?>() ?? const {});
      final at = DateTime.now().millisecondsSinceEpoch;
      entries[serviceId] = {'cookies': cookies, 'at': at, 'from': Account.instance.profiles.deviceName};
      await Me.instance.curlKeep({...kept, 'entries': entries});
      app.set('curl_applied_$serviceId', '$at');
    } catch (_) {
      // The relay away, or the blob unreadable: not written over; the next sign-in shares it.
    }
  }

  /// The synced cookies of [serviceId] as the extension last kept them, and when; null where there are none. Google
  /// Messages' ('gmessages', GMFB-10) are read here rather than applied: pairing makes Google ask for an emoji on the
  /// phone, so it is started by the person, from Google Messages' setup (lib/gm/google_signin_flow.dart).
  Future<({Map<String, String> cookies, int at})?> entryOf(String serviceId) async {
    try {
      final kept = await Me.instance.curlKept();
      if (kept == null || kept['v'] != _version) return null;
      final entry = (kept['entries'] as Map? ?? const {})[serviceId];
      if (entry is! Map) return null;
      final cookies = (entry['cookies'] as Map?)?.cast<String, Object?>();
      if (cookies == null || cookies.isEmpty) return null;
      return (cookies: {for (final c in cookies.entries) c.key: '${c.value}'}, at: (entry['at'] as num?)?.toInt() ?? 0);
    } catch (_) {
      return null;
    }
  }

  /// Signs this device in to [serviceId] with a synced entry's [cookies], kept at [at] (ms), unless it is signed in
  /// already or this entry was tried before (`curl_applied_<service>` holds the time of the last one applied).
  Future<void> _apply(AppState app, String serviceId, Map<String, String> cookies, int at) async {
    final n = Inbox.instance.named(serviceId);
    if (n is! AccountHelper) return; // only cookie-login helpers can take cURL entries
    // X also needs its passcode, which only the person can give: its sign-in screen offers the synced cookies.
    if (n.service.passcode) return;
    final appliedKey = 'curl_applied_$serviceId';
    final already = int.tryParse(app.choice(appliedKey, '0')) ?? 0;

    // Already signed in on this device: note we've seen this entry and leave the live session alone.
    if (n.state == InboxState.ready || n.state == InboxState.signingIn) {
      if (at > already) app.set(appliedKey, '$at');
      return;
    }
    // Nothing newer than what we last signed in with, and not currently signed in: the cookies likely expired the
    // same way here; try again only when the extension has captured fresher ones.
    if (at <= already && already > 0) return;

    // Not started yet (a plugin switched off, or never started): switch it on so its helper runs, then sign in.
    if (n.state == InboxState.unavailable) await Inbox.instance.enable(n);
    // A helper just started takes a moment to say it is up: wait for it, rather than give up on this entry until the
    // next pull (the reason a synced Discord never signed in on a phone, 2026-11-21).
    for (var i = 0; i < 40 && n.state == InboxState.unavailable; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    if (n.state != InboxState.signedOut) return; // helper not in this build

    final ok = await n.signIn(jsonEncode(cookies), share: false);
    if (ok) app.set(appliedKey, '$at');
  }
}
