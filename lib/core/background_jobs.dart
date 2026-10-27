/// A job the app runs on its own, told to the device it runs on, so the device keeps it going (Matt, 2026-10-26:
/// "Make the header generation async and a background task that runs while the app is generating the images"). The
/// first is Lovart's header images for the recent notes (lib/plugins/lovart/banner_run.dart); the channel is named
/// for any job, `ghost_md/jobs`.
///
/// - **Android** (android/…/ghost_md/BackgroundJobs.kt): `running` starts a foreground service, or tells the one
///   started what to say, as the meeting's recording and write-up hold the app up (capture/MeetingService.kt). Its
///   ongoing notification says the job's title and how far it is, with Stop, which comes back here as `stop`; a
///   partial wake lock is held with it, so the job goes on with the screen off or the app behind another. `ended`
///   lets the service go and posts a notification that says how it ended, as a meeting's "Written up" does.
/// - **The Mac app** (macos/Runner/MainFlutterWindow.swift): `running` keeps the app out of App Nap, which slows the
///   timers and fetches of an app whose window is behind others; `ended` lets it nap again. No notification: the
///   app's own toast says it.
/// - Anywhere else (a test, an iPhone, the web): nothing, and the job runs while the app does.
///
/// Nothing is waited on: a channel that does not answer is a device without the half, never a job that cannot run.
library;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb, debugPrint;
import 'package:flutter/services.dart';

import 'mac_app.dart' show runsAsMacApp;

/// The device, told of the app's jobs.
abstract interface class BackgroundJobs {
  /// The job [id] is running: [title] ("Making header images") and [text] ("12 of 100") on its notification, with
  /// how far it is where it says.
  Future<void> running(String id, {required String title, required String text, int? done, int? total});

  /// It ended: the device lets it go, and says [title] (with [text] under it) where it notifies; [quiet], it says
  /// nothing (a picture or two made, which the app shows itself). Others still running keep the device holding on.
  Future<void> ended(String id, {required String title, String? text, bool quiet = false});

  /// Who is told when the person stops the job from the device's own notification.
  void onStop(void Function(String id)? stop);
}

/// Nothing told: a test, and a build with no half for it.
class NoBackgroundJobs implements BackgroundJobs {
  const NoBackgroundJobs();

  @override
  Future<void> running(String id, {required String title, required String text, int? done, int? total}) async {}

  @override
  Future<void> ended(String id, {required String title, String? text, bool quiet = false}) async {}

  @override
  void onStop(void Function(String id)? stop) {}
}

/// The channel the jobs are told on.
const MethodChannel jobsChannel = MethodChannel('ghost_md/jobs');

/// The phone's and the Mac's half, over [jobsChannel].
class ChannelBackgroundJobs implements BackgroundJobs {
  ChannelBackgroundJobs({MethodChannel channel = jobsChannel, bool? here}) : _channel = channel, _here = here ?? (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || runsAsMacApp));

  final MethodChannel _channel;
  final bool _here;

  Future<void> _ask(String method, Map<String, Object?> arguments) async {
    if (!_here) return;
    try {
      await _channel.invokeMethod<Object?>(method, arguments);
    } on MissingPluginException {
      // A build from before the half.
    } on PlatformException catch (failure) {
      debugPrint('[ghost] the device was not told of the job: ${failure.message}');
    }
  }

  @override
  Future<void> running(String id, {required String title, required String text, int? done, int? total}) =>
      _ask('running', {'id': id, 'title': title, 'text': text, 'done': ?done, 'total': ?total});

  @override
  Future<void> ended(String id, {required String title, String? text, bool quiet = false}) => _ask('ended', {'id': id, 'title': title, 'text': ?text, if (quiet) 'quiet': true});

  @override
  void onStop(void Function(String id)? stop) {
    if (!_here) return;
    _channel.setMethodCallHandler(stop == null
        ? null
        : (call) async {
            if (call.method == 'stop' && call.arguments is Map && (call.arguments as Map)['id'] is String) stop((call.arguments as Map)['id'] as String);
            return null;
          });
  }
}
