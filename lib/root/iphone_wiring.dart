/// What the root and a note's desk are given on an iPhone, where the real iPhone app's page answers differently
/// from every other platform's and the answer is not one a platform check already gives (lib/core/iphone_app.dart
/// has the rest: no recorder, no voice at all).
///
/// Each is one of the page's own rules, named where it is kept:
///
/// - **Settings › About says the App Store updates the app** (`core/ota.ts` `storeOf`: "an iPhone is always the
///   App Store's, and has no over-the-air updates at all"). There is no update client on an iPhone
///   (`Updates.forBuild` makes one for Android alone), so About is told so outright: [appStoreUpdates].
/// - **The + beside a line offers no picture** (`editor/addRows.ts` `canPickPicture`: false in the iPhone app),
///   though the note's own menu and a canvas add one through the phone's chooser, as the page's do through its
///   file input: [plusOffersPicture].
/// - **The More sheet keeps its AI rows, and a press says why not** (`editor/useNoteAi.ts` `runAi`: the rows are
///   always drawn and the availability's own sentence is the toast): [iPhoneAiRows]. Nothing of the AI is made on
///   an iPhone, whose core has no engine, so the rows have no `NoteAi` to ask; the sentence is asked of the same
///   rule the page asks (`ai/available.ts` `availability`).
/// - **A plugin that asks the Tauri app's Rust is refused in Rust's words** (`src-tauri/src/unsupported.rs`:
///   Notion and Slack reach their services through commands that are not built for iOS, and link previews and
///   place names the same way), while GitHub, which the page fetches itself, works: `notOnIPhone`
///   (lib/core/iphone_app.dart, where a plugin can read it) and [iPhoneLinkPreviews].
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

import '../ai/available.dart';
import '../core/blanks_syntax.dart' show hasBlank;
import '../core/updates.dart' show describeBuild, ghostBuild;
import '../editor/view/editor_view.dart';
import '../settings/panes/about_pane.dart' show ghostVersion;
import '../settings/panes/settings_host.dart' show SettingsUpdates;

bool _iPhone(TargetPlatform? platform) => (platform ?? defaultTargetPlatform) == TargetPlatform.iOS;

/// What Settings › About is told on an iPhone: the version, and that the App Store is where its updates come from.
/// Null anywhere else, where the update client says (lib/root/update_wiring.dart `settingsUpdatesOf`).
SettingsUpdates? appStoreUpdates({TargetPlatform? platform}) =>
    _iPhone(platform) ? SettingsUpdates(version: ghostVersion, built: ghostBuild.isEmpty ? null : describeBuild(ghostBuild), store: 'appstore') : null;

/// Whether the + beside a line offers A picture here (`canPickPicture`).
bool plusOffersPicture({TargetPlatform? platform}) => !_iPhone(platform);

/// The AI's sentence on an iPhone, from the page's own rule: "The AI is not on iOS yet."
String get aiNotOnIPhone => switch (availability(const [], '', const Where(tauri: true, ios: true, localOnly: false, generation: null))) {
      Unavailable(:final reason) => reason,
      _ => '',
    };

/// The More sheet's AI rows on an iPhone: each says why not, in the words the page's toast has. Fill the blanks
/// says there are none first, as the page's does (`fillAll` answers before the model is asked for). Null anywhere
/// else, where a desk with no AI draws no rows.
void Function(EditorView view, String kind, [String? instruction])? iPhoneAiRows(void Function(String message) say, {TargetPlatform? platform}) {
  if (!_iPhone(platform)) return null;
  return (view, kind, [instruction]) => say(kind == 'fill' && !hasBlank(view.state.doc.toString()) ? 'No blanks for the model in this note.' : aiNotOnIPhone);
}

/// Whether a link's preview is ever fetched here: not on an iPhone (`unsupported.rs` `LINK_PREVIEWS`; the page
/// keeps the refusal as a failed look and draws no card).
bool iPhoneLinkPreviews({TargetPlatform? platform}) => !_iPhone(platform);
