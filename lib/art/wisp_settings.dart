import 'package:flutter/foundation.dart';

import 'wisp_probe.dart';

/// How a view's smoke is drawn: the filter that bends the words, or the mask that tears them (art/wispMask.ts
/// `WispDraw`). The web app picks the mask in the Mac app, whose engine cannot afford the filter; here the filter is
/// a fragment shader every engine affords, so the mask is only ever asked for by name ([WispSettings.draw], or a
/// view's own `draw`), by a page that compares the two.
enum WispDraw { filter, mask }

/// What smokes under a header: the wisp, or on a desktop a plain blurred strip under the glass (art/wispMask.ts
/// `WispHead`).
enum WispHead { smoke, blur }

/// Which drawing a view's edges get (art/wispEdge.ts `wispModeFor`): the filter, the mask, or on a desktop neither,
/// a blur strip at the top and a short fade at the foot.
enum WispMode { filter, mask, fade }

/// The wisp's switches: what the web app reads from its preferences and from the page it runs in.
///
/// - [wanted] is `preferences().wispEdge` (Settings › Appearance › Motion): off, no edge smokes and a page slips
///   under its header with a clean edge. The app's preferences are not this directory's, so whoever owns them sets
///   this when the person's choice is read and when it changes.
/// - [draw] and [head] are the two overrides the web app keeps in localStorage (`glyph-wisp-draw`,
///   `glyph-wisp-head`), for a page that compares the drawings; null leaves the platform to decide.
///
/// What differs from the page: the web app tells a desktop by its pointer (`(hover: hover) and (pointer: fine)`), a
/// question Flutter cannot ask before a pointer moves, so a desktop here is the platform the app was built for. The
/// Fold is Android, and so a phone however wide it opens, as the page has it.
class WispSettings extends ChangeNotifier {
  WispSettings._();
  static final WispSettings instance = WispSettings._();

  bool _wanted = true;
  WispDraw? _draw;
  WispHead? _head;

  bool get wanted => _wanted;
  set wanted(bool value) {
    if (value == _wanted) return;
    _wanted = value;
    notifyListeners();
  }

  /// The drawing asked for by name, over the platform's own.
  WispDraw? get draw => _draw;
  set draw(WispDraw? value) {
    if (value == _draw) return;
    _draw = value;
    notifyListeners();
  }

  /// The header's edge asked for by name, over the platform's own.
  WispHead? get head => _head;
  set head(WispHead? value) {
    if (value == _head) return;
    _head = value;
    notifyListeners();
  }

  /// Puts every switch back as the app starts with it.
  void reset() {
    _wanted = true;
    _draw = null;
    _head = null;
    notifyListeners();
  }
}

/// Whether the smoke is drawn the quick way: a strip in one pass over the screen with its soft half made small
/// (lib/art/wisp_smoke.dart `paintWispSmoke`), where the first drawing made every primitive of the web filter a
/// picture the size of the strip on every frame of a scroll.
///
/// Not yet what a build draws unless it is told to (`--dart-define=GHOST_WISP_QUICK=true`, or `quick` among a
/// measured build's `GHOST_PERF_SMOKE`): the quick drawing is the same smoke to the eye and not the same pixels, so
/// every reference picture with a strip in it has to be drawn again with it, and those are looked at first.
bool get wispQuick => debugWispQuick ?? (_quick || WispProbe.has('quick'));
const bool _quick = bool.fromEnvironment('GHOST_WISP_QUICK');

/// Says which drawing a test gets, whatever the build was told.
@visibleForTesting
bool? debugWispQuick;

bool get _desktop => switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => false,
      TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
    };

/// Which drawing a view gets when it is not told (art/wispMask.ts `wispDraw`): the filter, unless the mask is asked
/// for by name.
WispDraw wispDraw() => WispSettings.instance.draw ?? WispDraw.filter;

/// What smokes under a header (art/wispMask.ts `wispHead`): the wisp on a phone, a blur strip on a desktop.
WispHead wispHead() => WispSettings.instance.head ?? (_desktop && !WispProbe.has('phone') ? WispHead.blur : WispHead.smoke);

/// art/wispEdge.ts `wispModeFor`: [draw] is what the view asked for; left out, the platform decides.
WispMode wispModeFor([WispDraw? draw]) {
  if (draw == null && wispHead() == WispHead.blur) return WispMode.fade;
  return switch (draw ?? wispDraw()) { WispDraw.filter => WispMode.filter, WispDraw.mask => WispMode.mask };
}

/// art/wispEdge.ts `footSmokes`: whether a page's foot bends the words under it here, for a note's editor to keep its
/// caret [wispEdgeFootClear] clear of the edge. [still] is the phone asking for reduced motion, which takes the
/// filter away and leaves the mask.
bool footSmokes(bool wanted, {WispDraw? draw, required bool still}) {
  if (!wanted) return false;
  final mode = wispModeFor(draw);
  if (mode == WispMode.fade) return false;
  return !(mode == WispMode.filter && still);
}

/// art/dockSmoke.ts `dockBends`: whether the dock's halo bends what scrolls behind it, which it does where the
/// page's own foot is bent. The web app adds "on Android", the one engine there that takes an SVG filter as a
/// backdrop filter; here the halo is drawn from a picture of what is behind it (lib/art/dock_smoke.dart), which
/// every engine can bend.
bool dockBends() => wispDraw() == WispDraw.filter && wispHead() == WispHead.smoke;
