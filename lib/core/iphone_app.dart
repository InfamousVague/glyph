/// Whether this process is the iPhone app, and what an iPhone leaves out.
///
/// The web app asked `isIOS` of the agent string (`core/platform.ts`) and hung two rules on it that the rest of
/// the page read: its iPhone app has no engines (`src-tauri/src/unsupported.rs`: whisper.cpp and llama.cpp are not
/// built for iOS), so it records nothing and runs no model, and it is the App Store's to update. Here, as for the
/// Mac (lib/core/mac_app.dart), there are two questions:
///
/// - **How the app should look and behave on an iPhone** is `defaultTargetPlatform == TargetPlatform.iOS`, which a
///   test can set (`debugDefaultTargetPlatformOverride`): [recordsVoice] and every pane's "isn't on iPhone yet"
///   read that.
/// - **Whether the iPhone's own halves are there to be called** (the channels in ios/Runner, the core linked into
///   the app itself, the real data directory) is [runsAsIPhoneApp]: true only on an iPhone or in its simulator.
///   A test runs on the Mac, where `Platform.isIOS` is never true, so nothing there is asked of a channel nobody
///   answers.
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

/// True in the iPhone app, on a phone or in the simulator.
final bool runsAsIPhoneApp = !kIsWeb && Platform.isIOS;

/// Whether this build records: all but the iPhone app (`core/platform.ts` `recordsVoice`, which is
/// `!(isTauri() && isIOS)`; there is no browser build here, so it is the platform alone). The real iPhone app's
/// first version is notes only: every way into a recording (Speak, a note's microphone, a tape's Add, the
/// palette's, a meeting) is left out there rather than offered and failing, and the voice model is not looked for.
/// The iPhone's core is built without the engines to match (tool/build-native.sh ios), so nothing is made of
/// voice at all where this is false (lib/main.dart).
bool get recordsVoice => recordsVoiceOn(defaultTargetPlatform);

/// [recordsVoice]'s rule, for a platform said outright.
bool recordsVoiceOn(TargetPlatform platform) => platform != TargetPlatform.iOS;

/// Rust's sentence for something the Tauri app does through a command that is not built for iOS, on an iPhone;
/// null where it may be done, and anywhere else. `src-tauri/src/unsupported.rs`, word for word: the real iPhone
/// app lists the Notion and Slack plugins and lets a person sign in, and each request is answered with this.
/// GitHub is not among them (the page fetches it itself, and it works there).
String? notOnIPhone(String what, {TargetPlatform? platform}) {
  if ((platform ?? defaultTargetPlatform) != TargetPlatform.iOS) return null;
  return switch (what) {
    'notion' => 'Notion is not available on iOS yet.',
    'slack' => 'Slack is not available on iOS yet.',
    _ => null,
  };
}
