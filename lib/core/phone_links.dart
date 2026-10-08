/// Links that opened the app, from the phone: the [LinkSource] (lib/share/app_links.dart) over the activity's
/// `ghost_md/links` (android/…/ghost_md/AppLinks.kt). What `links_take`, the `glyph://link` event and
/// `GlyphHost.takeLink` (src/app/core/host.ts `takeHostLink`) were to the page's `followAppLinks`.
///
/// **The seam: nothing calls this yet.** It is wired in one step, where the root has its notes and its door (the
/// four things the app does with a link: lib/share/app_links.dart `AppLinkDoor`). Once the notes are read, as the
/// page waited for `loading` to end (src/app/shell/useAppLinks.ts):
///
/// ```dart
/// // in the root's state, after the library's first read:
/// _stopLinks = followAppLinks((link) => openAppLink(link, door, onError: warn), PhoneLinks());
/// // and in dispose:
/// _stopLinks?.call();
/// ```
///
/// One [PhoneLinks] for the life of the app: making one takes the channel's handler, so a second would leave the
/// first deaf to `arrived`. [dispose] lets the handler go.
///
/// What differs:
/// - **One road, not two.** The Tauri app heard of a link from the deep-link plugin (kept in Rust) and, for an
///   activity made again inside a live process, from the activity itself. Here the activity is the only one, and it
///   keeps its links in the process, so [take] has every link and [takeActivityLink] answers null.
/// - **`arrived` is the activity calling Dart** on the same channel, where the page listened for a Tauri event.
/// - **Where there is no phone half** (a Mac run, a test without one) [take] answers nothing, where the page's
///   `invoke` rejected and `followAppLinks` read that as none.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import '../share/app_links.dart';

/// The channel AppLinks.kt answers on: `take` gives the links kept since the last ask; `arrived` is said to Dart.
const MethodChannel phoneLinksChannel = MethodChannel('ghost_md/links');

class PhoneLinks implements LinkSource {
  PhoneLinks({MethodChannel channel = phoneLinksChannel}) : _channel = channel {
    _channel.setMethodCallHandler(_said);
  }

  final MethodChannel _channel;
  final StreamController<void> _arrived = StreamController<void>.broadcast();

  Future<Object?> _said(MethodCall call) async {
    if (call.method == 'arrived' && !_arrived.isClosed) _arrived.add(null);
    return null;
  }

  /// Every link the activity kept since the last ask, oldest first, and kept no longer. Only the app's own scheme
  /// comes through: the activity keeps no other, and this drops anything else a channel could be made to say.
  @override
  Future<List<String>> take() async {
    final List<Object?>? kept;
    try {
      kept = await _channel.invokeListMethod<Object?>('take');
    } on MissingPluginException {
      return const [];
    }
    return [
      for (final link in kept ?? const <Object?>[])
        if (link is String && link.startsWith('ghostmd://')) link,
    ];
  }

  /// Null: the activity's link is among [take]'s (see the header).
  @override
  String? takeActivityLink() => null;

  /// Told each time another link is kept while the app runs.
  @override
  Stream<void> get arrived => _arrived.stream;

  /// Stops hearing the activity. For the app's end, or a test's.
  void dispose() {
    _channel.setMethodCallHandler(null);
    unawaited(_arrived.close());
  }
}
