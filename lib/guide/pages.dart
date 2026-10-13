/// The walkthrough's pages, in order, named once. A port of `src/app/guide/pages.ts` (`GUIDE_PAGES`, `GuidePage`).
/// Each page's words are a widget of its own in lib/guide/pages/, and guide.dart draws them by these names.
///
/// The order is load-bearing past the dots: every page before the last is a reading page, where a launch by the side
/// key is someone who has not finished (too_soon.dart). The last page hands over to the Academy.
///
/// What differs: the page's tuple of names is an enum, and `GUIDE_PAGES` is [GuidePage.values]. It is not called
/// `guidePages`, which lib/core/book.dart already has for the pages of the Guide, the book.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;

/// One page of the walkthrough (`GuidePage`).
enum GuidePage { welcome, theme, model, start }

/// The pages in order (`GUIDE_PAGES`).
const List<GuidePage> walkthroughPages = GuidePage.values;

/// The pages this device walks through: all four, but on an iPhone, which runs no model (Matt, 2026-10-13), the
/// page that asks a new person to choose one is left out, since none can ever be fetched there.
List<GuidePage> get walkthroughPagesNow =>
    defaultTargetPlatform == TargetPlatform.iOS ? const [GuidePage.welcome, GuidePage.theme, GuidePage.start] : walkthroughPages;
