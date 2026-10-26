/// The phone's half of its own notifications for the bell's rows: the three calls the web app made on
/// `window.GlyphHost` (`watchNotices`, `postNotice`, `noticesState`; `src/app/core/host.ts`), and the one
/// Settings › Notifications asks Android's prompt with (`requestNotifications`), over the channel
/// `ghost_md/notices` (android/…/ghost_md/Notices.kt, with the Tauri app's `notices/NoticeAlerts.kt` and
/// `NoticeWorker.kt` behind it). What is watched and posted, and when, is lib/sync/phone.dart.
///
/// What differs:
/// - The page's host answered at once; a channel answers a moment later, so each call is a [Future]. "The binary
///   cannot" is still null: a desktop, an iPhone, a test, or an Android build from before the phone's half.
/// - [NoticesHost] is the seam, so what decides (lib/sync/phone.dart) is tried against a stand-in.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/services.dart';

/// What the phone does with the bell's rows: not watched, shown, or watched but kept from showing by Android
/// (`NoticesState`).
enum NoticesState { off, on, blocked }

NoticesState? _stateOf(Object? answer) => switch (answer) {
      'off' => NoticesState.off,
      'on' => NoticesState.on,
      'blocked' => NoticesState.blocked,
      _ => null,
    };

/// One row as the phone posts it (`postNoticeOnHost`'s argument).
typedef PhoneNotice = ({String id, String title, String? text, String link});

/// The JSON a row is handed to the phone as. A row with no line under its title is sent without `text`, never
/// `"text": null`: Android's `optString` reads a JSON null as the word "null", and every such notification said it
/// (Matt: "All the ghost notifications say "null" for the description").
String noticeJson(PhoneNotice notice) => jsonEncode({
      'id': notice.id,
      'title': notice.title,
      if (notice.text != null && notice.text!.trim().isNotEmpty) 'text': notice.text,
      'link': notice.link,
    });

/// The phone, asked about its notices.
abstract interface class NoticesHost {
  /// The phone told what to watch for the closed app (JSON), or '' to stop; null where the binary cannot
  /// (`watchNoticesOnHost`).
  Future<NoticesState?> watch(String json);

  /// One row as a phone notification: true when it was posted now or before, false where it could not be
  /// (`postNoticeOnHost`).
  Future<bool> post(PhoneNotice notice);

  /// The phone's notices as Android has them now: whether anything is watched, and whether the permission, the
  /// app's switch and the channel would let one show. Null where the binary has none (`noticesStateOnHost`).
  Future<NoticesState?> state();

  /// Asks Android to let Ghost.md notify (`requestNotifications`): true where it already may or its prompt is now
  /// up, false where no prompt can change it (refused twice, or turned off in the phone's settings) and where the
  /// binary cannot ask. The prompt's own answer is not told: [state] is read again.
  Future<bool> allow();
}

/// The channel the phone's notices answer on.
const MethodChannel noticesChannel = MethodChannel('ghost_md/notices');

/// The phone's own half, on Android; nothing anywhere else.
class PhoneNoticesHost implements NoticesHost {
  const PhoneNoticesHost({MethodChannel channel = noticesChannel, bool? android}) : _channel = channel, _android = android;

  final MethodChannel _channel;
  final bool? _android;

  bool get _here => _android ?? (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  Future<Object?> _ask(String method, [Map<String, Object?>? arguments]) async {
    if (!_here) return null;
    try {
      return await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  @override
  Future<NoticesState?> watch(String json) async => _stateOf(await _ask('watch', {'json': json}));

  @override
  Future<bool> post(PhoneNotice notice) async {
    final answer = await _ask('post', {'json': noticeJson(notice)});
    return answer == 'posted' || answer == 'seen';
  }

  @override
  Future<NoticesState?> state() async => _stateOf(await _ask('state'));

  @override
  Future<bool> allow() async {
    final answer = await _ask('allow');
    return answer == 'allowed' || answer == 'asked';
  }
}
