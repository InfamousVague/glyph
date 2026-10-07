/// The pure half of pulling a page down to refresh it: how far the page follows a finger, where the detent is, and
/// which touches are a pull at all. A port of `src/app/core/pull.ts` (docs/DESIGN.md §152). The page follows the
/// finger at half its travel, so it feels weighted, to the detent; past it only a sixth as fast, and never more than
/// [pullMostPx]. Nothing differs.
library;

/// How far the page must come down for a let-go to refresh it, in px (`PULL_DETENT_PX`).
const double pullDetentPx = 64;

/// The furthest the page comes down however far the finger goes (`PULL_MOST_PX`).
const double pullMostPx = 110;

/// Where the page rests while the refresh runs (`PULL_REST_PX`).
const double pullRestPx = 52;

/// A refresh shown for less than this reads as a flicker (`PULL_LEAST_MS`).
const int pullLeastMs = 500;

/// How far to take the first touch's travel as saying what it is (`INTENT_PX`).
const double pullIntentPx = 10;

/// A pull decides itself quickly: a finger that rests first is choosing words (`INTENT_MS`).
const int pullIntentMs = 300;

/// The page's offset for a finger [dy] px below where it started: weighted to the detent, then a rubber band.
double pullOffset(double dy) {
  if (dy <= 0) return 0;
  final weighted = dy / 2;
  if (weighted <= pullDetentPx) return weighted;
  final past = pullDetentPx + (weighted - pullDetentPx) / 3;
  return past < pullMostPx ? past : pullMostPx;
}

/// Whether the page, down by [offset], would refresh on a let-go.
bool pullArmed(double offset) => offset >= pullDetentPx;

/// What the start of a touch is (`pullIntent`'s answers).
enum PullIntent { pull, other, undecided }

/// What the start of a touch is: a pull (down, more than across, from a page at its top, and soon), a scroll or a
/// drag of something else, or not yet known.
PullIntent pullIntent(double dx, double dy, bool atTop, int elapsedMs) {
  if (dx.abs() < pullIntentPx && dy.abs() < pullIntentPx) return elapsedMs > pullIntentMs ? PullIntent.other : PullIntent.undecided;
  return atTop && dy > 0 && dy > dx.abs() * 1.2 && elapsedMs <= pullIntentMs ? PullIntent.pull : PullIntent.other;
}
