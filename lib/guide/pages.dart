/// The walkthrough's pages, in order, named once. A port of `src/app/guide/pages.ts` (`GUIDE_PAGES`, `GuidePage`).
/// Each page's words are a widget of its own in lib/guide/pages/, and guide.dart draws them by these names.
///
/// The order is load-bearing past the dots: every page before the last is a reading page, where a launch by the side
/// key is someone who has not finished (too_soon.dart). The last page hands over to the Academy.
///
/// What differs: the page's tuple of names is an enum, and `GUIDE_PAGES` is [GuidePage.values]. It is not called
/// `guidePages`, which lib/core/book.dart already has for the pages of the Guide, the book.
library;

/// One page of the walkthrough (`GuidePage`).
enum GuidePage { welcome, theme, model, start }

/// The pages in order (`GUIDE_PAGES`).
const List<GuidePage> walkthroughPages = GuidePage.values;
