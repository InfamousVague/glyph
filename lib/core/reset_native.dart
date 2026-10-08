/// The phone's own half of starting over: what lib/core/reset.dart's `ResetNative` asks, done by the Rust core's
/// `reset_local_data` (native/src/kept/reset.rs, the web app's src-tauri/src/reset.rs line for line) and by the
/// activity on the channel reset.dart names (android/…/ghost_md/ResetChannel.kt). On the page these were
/// `invoke('reset_local_data')`, `GlyphHost.cancelWriteUps` and `meetingStateNow()`.
///
/// **The seam, for whoever makes the root's `ResetGround`** (this file imports nothing of reset.dart, so it is
/// wired by its methods, each of which has the shape `ResetNativeOf` takes):
///
/// ```dart
/// final phone = PhoneReset(invoke: core.invoke, recordingNow: () => meetingStateNow()?.recording ?? false);
/// ResetGround(
///   native: ResetNativeOf(
///     hasGeneration: phone.hasGeneration,
///     recording: phone.recording,
///     cancelWriteUps: phone.cancelWriteUps,
///     resetLocalData: phone.resetLocalData,
///   ),
///   …
/// );
/// ```
///
/// What differs:
/// - **There is no generation to wait for.** The page could be newer than the binary it ran in (an update over the
///   air), so it asked for native generation 11; here the Dart and the core are one build, and [hasGeneration]
///   answers true.
/// - **[recording] cannot ask the phone**, being synchronous: it answers what [recordingNow] says (the meeting's
///   state the root already follows). So [resetLocalData] asks the service itself first (`recording` on the
///   channel) and refuses with the same words, whatever the app last heard.
/// - **[cancelWriteUps] is asked and not waited for** by its caller, as on the page; [resetLocalData] waits for it
///   before a file is removed, so a write-up never finds its files gone under it.
/// - **The secure store is emptied here** (`forgetSecrets`), after the files: the web kept the session and the
///   plugins' sign-ins where the page's own clearing and Rust's two files reached them. A store that could not be
///   emptied fails the reset with its own sentence, the files already gone, as reset.dart says a failure partway
///   does.
/// - **Off Android there is no phone half** (a Mac run, a test without one): the channel's three are skipped, and
///   the core's `reset_local_data` is the whole of it.
library;

import 'dart:async';

import 'package:flutter/services.dart';

import 'native/core.dart';

/// The channel ResetChannel.kt answers on (`resetChannelName`, lib/core/reset.dart).
const MethodChannel resetChannel = MethodChannel('ghost.md/reset');

/// Said when a reset is asked for while a meeting is being recorded (`stopTheMeeting`, lib/capture/meeting.dart).
const String _stopTheMeeting = 'Stop the meeting first.';

class PhoneReset {
  PhoneReset({required CoreInvoke invoke, this.recordingNow, MethodChannel channel = resetChannel})
      : _invoke = invoke,
        _channel = channel;

  final CoreInvoke _invoke;
  final MethodChannel _channel;

  /// Whether a meeting is being recorded, as the app last heard (`meetingStateNow()?.recording`).
  final bool Function()? recordingNow;

  /// The cancel asked for and not yet answered.
  Future<void>? _cancelling;

  /// `hasNativeGeneration`: always, since the core is this build's own (see the header).
  Future<bool> hasGeneration(int wanted) async => true;

  /// Whether a meeting is being recorded, as far as the app knows.
  bool recording() => recordingNow?.call() ?? false;

  /// One call to the phone; null where there is no phone half.
  Future<T?> _phone<T>(String method) async {
    try {
      return await _channel.invokeMethod<T>(method);
    } on MissingPluginException {
      return null;
    }
  }

  /// Cancels the write-ups queued on the phone's work queue, and the one under way. Not waited for here.
  void cancelWriteUps() {
    final asked = _phone<void>('cancelWriteUps').then<void>((_) {}, onError: (Object _) {});
    _cancelling = asked;
    unawaited(asked.whenComplete(() {
      if (identical(_cancelling, asked)) _cancelling = null;
    }));
  }

  /// Everything a person made on this phone, gone; the models too with [models]. Throws the core's or the phone's
  /// own sentence for a failure partway; whatever was removed stays removed.
  Future<void> resetLocalData({required bool models}) async {
    if (await _phone<bool>('recording') == true) throw StateError(_stopTheMeeting);
    await _cancelling;
    await _invoke('reset_local_data', {'models': models});
    try {
      await _phone<void>('forgetSecrets');
    } on PlatformException catch (failure) {
      throw StateError(failure.message ?? 'A kept sign-in could not be forgotten.');
    }
  }
}
