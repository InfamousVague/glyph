/// The walkthrough's pages, in order, named once. A port of `src/app/guide/pages.ts` (`GUIDE_PAGES`, `GuidePage`).
/// Each page's words are a widget of its own in lib/guide/pages/, and guide.dart draws them by these names.
///
/// The order is load-bearing past the dots: every page before the last is a reading page, where a launch by the side
/// key is someone who has not finished (too_soon.dart). The last page hands over to the Academy.
///
/// What differs: the page's tuple of names is an enum, and `GUIDE_PAGES` is [GuidePage.values]. It is not called
/// `guidePages`, which lib/core/book.dart already has for the pages of the Guide, the book.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;

import '../core/preferences.dart';

/// One page of the walkthrough (`GuidePage`). Since 2026-10-27 (Matt: "build an onboarding flow with vivid colors
/// and iconography as well as a friendly elevenlabs v4 voice explaining each section") it walks through what the app
/// is, a section a page, each in a colour of its own and read aloud (narration.dart): what Ghost.md is, speaking a
/// note, meetings, the AI, sync and privacy, and the Market. Then it asks: `mode` is simple or advanced (GHST-103),
/// before the model, which Simple does without. The light-or-dark question the walkthrough opened with is on the
/// last page now, where it is the last thing chosen before writing.
enum GuidePage { welcome, speak, meetings, ai, sync, market, mode, model, start }

/// The pages in order (`GUIDE_PAGES`).
const List<GuidePage> walkthroughPages = GuidePage.values;

/// The pages this device walks through: all of them, but on an iPhone, which runs no model (Matt, 2026-10-13), the
/// page that asks a new person to choose one is left out, since none can ever be fetched there; and so is it for
/// someone who chose Simple on the page before it (GHST-103), who asked for less and is not asked to pick a language
/// model. An iPhone records nothing and runs no AI of its own either (lib/core/iphone_app.dart), so the pages about
/// speaking a note and the AI on the device are not promised there.
List<GuidePage> get walkthroughPagesNow => walkthroughPagesFor(ios: kIsWeb || defaultTargetPlatform == TargetPlatform.iOS, prefs: preferences.value);

/// [walkthroughPagesNow] for a given device and store, which the guide asks with its own (a test's).
List<GuidePage> walkthroughPagesFor({required bool ios, required Preferences prefs}) =>
    [
      for (final page in walkthroughPages)
        if (!(ios && (page == GuidePage.speak || page == GuidePage.ai)) && !(page == GuidePage.model && (ios || (prefs.experienceChosen && prefs.simple)))) page,
    ];
