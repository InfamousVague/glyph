import 'dart:async';
import 'dart:convert';

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
/// identity), last writer wins, so the extension reads-modifies-writes it. This class only reads.
class CurlSync {
  CurlSync._();
  static final CurlSync instance = CurlSync._();

  AppState? app;
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

  Future<void> _apply(AppState app, String serviceId, Map<String, String> cookies, int at) async {
    final n = Inbox.instance.named(serviceId);
    if (n is! AccountHelper) return; // only cookie-login helpers can take cURL entries
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
    if (n.state != InboxState.signedOut) return; // helper not in this build, or still coming up

    final ok = await n.signIn(jsonEncode(cookies));
    if (ok) app.set(appliedKey, '$at');
  }
}
