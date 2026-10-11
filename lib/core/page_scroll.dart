/// How the app's pages scroll, decided once for every screen: what a browser decides for the page.
///
/// The web app writes no physics. A scroller there is `overflow: auto` with `overscroll-behavior: contain`, and the
/// engine under the page does the rest: Android's WebView stops a list dead at its ends, WebKit on an iPhone
/// carries it on with the phone's own momentum and lets it stretch past each end and spring back (`contain` only
/// keeps the stretch from being handed to the page behind), and a Mac's does the same under a trackpad. So the
/// port's screens say nothing either. They are scrolled by whatever [GhostScrollBehavior] answers, which is put
/// over the whole app (lib/app/ghost_app.dart), and a screen that needs a behaviour of its own (no scrollbar, no
/// glow) extends it rather than `ScrollBehavior`, so the one rule still reaches its scroller.
///
/// What is left to a screen is a rule that is the screen's own and no platform's: a board's lanes snap, a page
/// under a pull to refresh does not move, a table drawn by a finger does not scroll.
library;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/widgets.dart';

/// The app's scroll behaviour. Everything but the physics is Flutter's own for the platform.
class GhostScrollBehavior extends ScrollBehavior {
  const GhostScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => pagePhysicsFor(getPlatform(context));
}

/// A page's physics on [platform]: an iPhone's rubber band and momentum, a Mac's (the same band, stopping sooner,
/// as a trackpad's does), and everywhere else a list that stops at its ends, as Android's does.
ScrollPhysics pagePhysicsFor(TargetPlatform platform) => switch (platform) {
      TargetPlatform.iOS => const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics()),
      TargetPlatform.macOS => const BouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast, parent: RangeMaintainingScrollPhysics()),
      _ => const ClampingScrollPhysics(parent: RangeMaintainingScrollPhysics()),
    };

/// The physics of a page that can be pulled down to refresh, while nothing is pulling it
/// (lib/notes/pull_to_refresh.dart). The pull is the page's own at its top: the web's stops the browser's
/// overscroll there (`preventDefault` on its touchmove, PullToRefresh.tsx), so on an iPhone and a Mac the top
/// holds still for the pull and only the foot stretches. Anywhere else it is the page's own physics.
ScrollPhysics pullRestPhysics({TargetPlatform? platform}) => switch (platform ?? defaultTargetPlatform) {
      TargetPlatform.iOS => const FootBouncingScrollPhysics(parent: RangeMaintainingScrollPhysics()),
      TargetPlatform.macOS => const FootBouncingScrollPhysics(decelerationRate: ScrollDecelerationRate.fast, parent: RangeMaintainingScrollPhysics()),
      final other => pagePhysicsFor(other),
    };

/// A rubber band at the foot and none at the top: the top is held, as a list that stops at its ends holds it.
class FootBouncingScrollPhysics extends BouncingScrollPhysics {
  const FootBouncingScrollPhysics({super.decelerationRate, super.parent});

  @override
  FootBouncingScrollPhysics applyTo(ScrollPhysics? ancestor) => FootBouncingScrollPhysics(decelerationRate: decelerationRate, parent: buildParent(ancestor));

  @override
  double applyBoundaryConditions(ScrollMetrics position, double value) {
    // Above the top: what a clamped list refuses, refused. Below the foot nothing is, and the band takes it.
    if (value < position.pixels && position.pixels <= position.minScrollExtent) return value - position.pixels;
    if (value < position.minScrollExtent && position.minScrollExtent < position.pixels) return value - position.minScrollExtent;
    return 0;
  }
}
