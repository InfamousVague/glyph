/// What the web build knows of itself, for the screens that say so (Settings › About; docs/WEB.md). Plain values,
/// so the phone's app reads them too and finds them false.
library;

import 'package:flutter/foundation.dart' show kIsWeb;

/// This is the app in a browser.
const bool onWeb = kIsWeb;

/// The page opened on a shelf in memory (a private window, storage turned off), and keeps nothing past this tab.
bool webKeepsNothing = false;

/// How many of the old web app's notes were carried into this page's library when it opened (web_core.dart
/// `carryOldPage`): said once, on the About pane, so a person who used the old page knows where their notes went.
int webCarried = 0;
