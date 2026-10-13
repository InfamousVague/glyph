/// A build with nothing in it that is drawn through a blur of what is behind it, for measuring what those cost
/// (Matt, 2026-10-12: "a version of the app without the ghostly wisp blur and no blur effects"):
/// `--dart-define=GHOST_PLAIN=true`. No smoke at a page's edges, no halo round the dock, and every pane of glass
/// (the bars, the dock, a menu, a floating card) is its tint alone. False in every other build, by a constant, so
/// the compiler takes every use of it away.
library;

const bool ghostPlain = bool.fromEnvironment('GHOST_PLAIN');
