/// Links opened into the computer's app (Matt, 2026-11-19: "make a route to allow people to click a link on their phone
/// or desktop to join a circle"): the invite page's Open in Ghost Messaging (site/join) opens
/// `ghostmsg://join/#c.…`, which the Mac hands over through its AppDelegate and Windows through the copy of the app
/// it starts (windows/runner/links.cpp), both on "ghost_desktop/links".
///
/// A circle's link, with the app set up: its invite raised (Join and Not now), as on a phone. Before that (the welcome,
/// pairing): held, and the circle joined and opened once the app is set up (lib/circles/pending_link.dart).
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../circles/pending_link.dart';
import '../ui/circles/circle_invite_card.dart' show openCircleLink;
import '../ui/common.dart' show toast;
import '../ui/shell.dart';

/// Hears the links the system hands the app, and opens the circle each names.
class DeskLinks {
  DeskLinks._();

  static const _channel = MethodChannel('ghost_desktop/links');
  static bool _started = false;

  /// The app's own scheme, as the invite page writes it.
  static const scheme = 'ghostmsg://join/';

  /// The link in [url] as the app knows a circle's: `ghostmsg://join/#c.…` is `https://gogho.st/join/#c.…`.
  static String normalise(String url) {
    final u = url.trim();
    if (u.toLowerCase().startsWith(scheme)) return 'https://gogho.st/join/${u.substring(scheme.length)}';
    if (u.toLowerCase().startsWith('ghostmsg://join')) return 'https://gogho.st/join/${u.substring('ghostmsg://join'.length)}';
    return u;
  }

  /// Listens for links, and takes any the app was started with.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open' && call.arguments is String) await opened(call.arguments as String);
      return null;
    });
    try {
      final waiting = await _channel.invokeListMethod<String>('take');
      for (final url in waiting ?? const <String>[]) {
        await opened(url);
      }
    } catch (_) {
      // A build without the native half: no links come.
    }
  }

  /// [url] was opened into the app.
  static Future<void> opened(String url) async {
    final link = normalise(url);
    final shell = AppShellState.live;
    if (shell == null || !shell.mounted) {
      // Not set up yet: once it is.
      await PendingCircleLink.hold(link);
      return;
    }
    if (!openCircleLink(shell, link) && shell.mounted) toast(shell.context, 'That circle link isn\'t complete. Ask for it again.');
  }
}
