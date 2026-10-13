/// A build with nothing in it that is drawn through a blur of what is behind it, for measuring what those cost
/// (Matt, 2026-10-12: "a version of the app without the ghostly wisp blur and no blur effects"):
/// `--dart-define=GHOST_PLAIN=true`. No smoke at a page's edges, no halo round the dock, and every pane of glass
/// (the bars, the dock, a menu, a floating card) is its tint alone. False in every other build, by a constant, so
/// the compiler takes every use of it away.
library;

const bool ghostPlain = bool.fromEnvironment('GHOST_PLAIN');

/// With [ghostPlain], whether the header alone keeps a slight blur of what scrolls under it
/// (`--dart-define=GHOST_BAR_BLUR=true`; Matt, 2026-10-12: "a slight blur behind the header like we do on the
/// Matt's Tools app", if it costs no frames): one small backdrop filter, where a build that is not plain has one
/// under every bar, the dock and each floating card, and the smoke besides.
const bool ghostBarBlur = bool.fromEnvironment('GHOST_BAR_BLUR');

/// The header's slight blur in a plain build, and the share of the page's ground over it.
const double plainBarBlurSigma = 8;
const String plainBarBlurGlass = 'color-mix(in srgb, var(--glacier-bg) 84%, transparent)';
