import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../shell/desktop/desktop_scrollbar.dart';
import 'wisp_kit.dart';
import 'wisp_mask.dart';
import 'wisp_probe.dart';
import 'wisp_settings.dart';
import 'wisp_strips.dart';

// ---- the numbers (art/wispEdge.ts) ---------------------------------------------------------------------------------

/// How far under the header's edge the smoke still bends a little: the strip's blur (`WISP_EDGE_SOFT`).
const double wispEdgeSoft = 15;

/// The band's full-strength lip (`WISP_EDGE_BAND`).
const double wispEdgeBand = 7;

/// How far below a header's edge the band's lip sits (`WISP_EDGE_DROP`).
const double wispEdgeDrop = 12;

/// How far the column's lip comes down as its scroll begins (`WISP_EDGE_EASE`): a band's whole depth.
const double wispEdgeEase = wispEdgeDrop + wispEdgeBand + wispEdgeSoft;

/// The strip starts this far above the view (`WISP_EDGE_ABOVE`).
const double wispEdgeAbove = 200;

/// The room round the view the web filter's region keeps for the bend (`WISP_EDGE_SIDE`), and above and below it.
const double wispEdgeSide = 40;
const double wispEdgeCrown = wispEdgeAbove + 40;
const double wispEdgeBelow = 40;

/// The budget a filter's region is held to, in the screen's own pixels (`WISP_EDGE_BUDGET`).
const int wispEdgeBudget = 1 << 24;

/// The foot's lip, its ramp, and how far above the view's edge the lip sits (`WISP_EDGE_FOOT_BAND`, `_SOFT`, `_LIFT`).
const double wispEdgeFootBand = 11;
const double wispEdgeFootSoft = 29;
const double wispEdgeFootLift = 24;

/// How far above a view's bottom edge the foot's smoke reaches words (`WISP_EDGE_FOOT_CLEAR`): a note's editor keeps
/// its caret this far clear of the edge where the foot smokes ([footSmokes]).
const double wispEdgeFootClear = wispEdgeFootLift + wispEdgeFootBand + 2 * wispEdgeFootSoft;

/// How far below the band's lip the bend and blur are worked out at all (`WISP_EDGE_REACH`), and the foot's.
const double wispEdgeReach = wispEdgeBand + wispEdgeSoft * 4 + 48;
const double wispEdgeFootReach = wispEdgeFootBand + wispEdgeFootSoft * 4 + 48;

/// The bend's `scale` under a header and at the foot (art/WispEdgeFilter.tsx), their blur and how near the strokes
/// it is kept.
const double wispEdgeBend = 24;
const double wispEdgeFootBend = 23;
const double wispEdgeBlur = 3.4;
const double wispEdgeNear = 2.5;

/// How far above the foot of what covers a header's smoke ([WispEdge.covered]) the smoke still begins: room for a
/// hairline or a rounded corner at the cover's own edge.
const double wispEdgeCoveredKeep = 8;

/// The fade at a smoking foot, a desktop's plain foot, and the mask drawing's two tears (art/wisp.css).
const double wispFootFadeSmoke = 32;
const double wispFootFadePlain = 28;
const double wispTearTop = 76;
const double wispTearFoot = 104;

/// The desktop's blur strip under a header (art/wisp.css `.app-headerBlur`): its depth, its blur, how long it takes
/// to show, and how much of the page's ground its wash starts from.
const double wispHeaderBlurDepth = 28;
const double wispHeaderBlurSigma = 10;
const Duration wispHeaderBlurTurn = Duration(milliseconds: 160);
const double wispHeaderBlurWash = 0.55;

/// The drift: a step no closer than this to the last (about 35 a second), the noise at rest, how far it slides, and
/// how long after the last scroll the smoke holds still.
const double wispDriftStepMs = 28;
const Offset wispBaseFrequency = Offset(0.018, 0.06);
const double wispSlidePx = 20;
const Duration wispScrollIdle = Duration(milliseconds: 160);

/// Whether a region [across] by [down] logical pixels fits the budget, counted in the screen's own pixels
/// (art/wispEdge.ts `withinWispBudget`). Every wisp asks before it is worn, and one that does not fit keeps its plain
/// fade.
///
/// The budget was found in WebKit, which paints an element black when its filter's region is over 2^24 device
/// pixels. Nothing here goes black; it is kept as the same guard on the same sizes, since what it guards here is
/// the size of the pictures a strip is drawn through.
bool withinWispBudget(double across, double down, double ratio) {
  final dots = ratio > 0 ? ratio : 1.0;
  return (across * dots).ceil() * (down * dots).ceil() <= wispEdgeBudget;
}

/// Which top band a view wears (art/wispEdge.ts `WispBand`): the page's, which every view under a header shares, or
/// the column's, for a column scrolling beside a page (Settings' sections in the split view). They drift apart: each
/// only while its own views are being scrolled.
enum WispBand { page, column }

/// art/wispEdge.ts `placeRegion`: whether the web filter's region for a view fits the budget. The page's region is
/// the window's size; a column's is its own width out to its [right]-hand edge in the window, and it is held to the
/// budget together with a page's beside it.
bool wispRegionFits({required Size view, required Size window, required WispBand band, required double ratio, double right = 0}) {
  final down = math.max(view.height, window.height) + wispEdgeCrown + wispEdgeBelow;
  if (band == WispBand.column) {
    final across = math.max(view.width, right).ceilToDouble() + wispEdgeSide * 2;
    return withinWispBudget(across + window.width + wispEdgeSide * 2, down, ratio);
  }
  return withinWispBudget(math.max(view.width, window.width) + wispEdgeSide * 2, down, ratio);
}

/// Where a band's noise is at one step of its drift: `baseFrequency`, and the `feOffset` that slides it.
@immutable
class WispDriftAt {
  const WispDriftAt(this.frequency, this.slide);
  final Offset frequency;
  final Offset slide;

  static const rest = WispDriftAt(wispBaseFrequency, Offset.zero);

  /// art/wispEdge.ts `stepBand` at [t] milliseconds on the band's own clock, rounded as the page writes it into its
  /// attributes: four places for the frequency, two for the slide.
  factory WispDriftAt.at(double t) {
    double places(double value, int n) => double.parse(value.toStringAsFixed(n));
    return WispDriftAt(
      Offset(places(wispBaseFrequency.dx + 0.003 * math.sin(t / 2600), 4), places(wispBaseFrequency.dy + 0.01 * math.sin(t / 3400 + 1.3), 4)),
      Offset(places(4 * math.sin(t / 2300 + 0.7), 2), places(wispSlidePx / 2 + (wispSlidePx / 2) * math.sin(t / 3100), 2)),
    );
  }

  @override
  bool operator ==(Object other) => other is WispDriftAt && other.frequency == frequency && other.slide == slide;

  @override
  int get hashCode => Object.hash(frequency, slide);
}

/// art/WispEdgeFilter.tsx `TopBand` as `placeBand` places it under a header [under] px tall (0: at the view's top),
/// its lip [lift] px above its place while a column's eases in.
WispSmoke wispTopSmoke({required double under, double lift = 0, WispDriftAt at = WispDriftAt.rest, WispFade fade = WispFade.none}) {
  final drop = under > 0 ? wispEdgeDrop : 0.0;
  return WispSmoke(
    seed: 3,
    frequency: at.frequency,
    slide: at.slide,
    noiseRect: wispTopWithin(under),
    lipA: under + drop + wispEdgeBand - lift,
    soft: wispEdgeSoft,
    bend: wispEdgeBend,
    blur: wispEdgeBlur,
    near: const Offset(wispEdgeNear, wispEdgeNear),
    fade: fade,
  );
}

/// The subregion the top band's noise, bend and blur are worked out over.
Rect wispTopWithin(double under) => Rect.fromLTRB(-40, -40, 3960, under + (under > 0 ? wispEdgeDrop : 0) + wispEdgeReach);

/// The foot's filter of art/WispEdgeFilter.tsx as `placeFoot` places it at the bottom edge of a view [height] tall.
WispSmoke wispFootSmoke({required double height, WispDriftAt at = WispDriftAt.rest, WispFade fade = WispFade.none}) {
  return WispSmoke(
    seed: 3,
    frequency: at.frequency,
    slide: at.slide,
    noiseRect: wispFootWithin(height),
    lipB: height - wispEdgeFootLift - wispEdgeFootBand,
    soft: wispEdgeFootSoft,
    bend: wispEdgeFootBend,
    blur: wispEdgeBlur,
    near: const Offset(wispEdgeNear, wispEdgeNear),
    fade: fade,
  );
}

/// The subregion the foot's noise, bend and blur are worked out over.
Rect wispFootWithin(double height) {
  final top = height - wispEdgeFootLift - wispEdgeFootReach;
  return Rect.fromLTRB(-40, top, 3960, top + wispEdgeFootReach + 40 + wispEdgeFootLift);
}

/// art/wisp.css's mask on a smoking view [height] tall: clear at its top edge and whole [topFade] down, whole until
/// [footFade] above where a dock [inset] tall begins, and gone below that.
WispFade wispEdgeFade({required double height, double topFade = 0, double footFade = 0, double inset = 0}) =>
    WispFade(clearUntil: 0, wholeFrom: topFade, wholeUntil: height - inset - footFade, clearFrom: height - inset);

// ---- the drift -----------------------------------------------------------------------------------------------------

/// What else moves with the page's smoke (art/wispEdge.ts `WispFollower`): told each step's slide and the noise's
/// breathing frequency.
typedef WispFollower = void Function(double dx, double dy, Offset frequency);

/// The smoke's drift (art/wispEdge.ts `driftStep`, `drift`, `rest`, `holdWispDrift`, `followWispDrift`): while a view
/// is being scrolled the noise slides up and down and its frequency breathes, at about 35 steps a second, and when
/// the scrolling stops it holds where it is. A clock for each band, advanced only while that band's views scroll.
///
/// One for the app, as the page has one filter for every view of a band: every view wearing a band reads the same
/// place in the drift ([at]), and repaints when it steps ([of]).
class WispDrift {
  WispDrift._();
  static final WispDrift instance = WispDrift._();

  final Map<WispBand, _Lane> _lanes = {for (final band in WispBand.values) band: _Lane()};
  final Set<WispFollower> _followers = {};
  int _held = 0;
  int? _frame;
  double _lastFrameAt = 0;
  double _lastStep = 0;

  /// Where [band]'s smoke is now.
  WispDriftAt at(WispBand band) => _lanes[band]!.at;

  /// Told whenever [band]'s smoke steps or is put back to rest.
  Listenable of(WispBand band) => _lanes[band]!;

  /// Holds the drift still until the answer is called (`holdWispDrift`): the capture engine holds it while the phone
  /// listens.
  VoidCallback hold() {
    _held += 1;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _held -= 1;
    };
  }

  /// Follows the page band's drift until the answer is called (`followWispDrift`).
  VoidCallback follow(WispFollower follower) {
    _followers.add(follower);
    return () => _followers.remove(follower);
  }

  /// Counts [band]'s views scrolling (`drift`); the one loop runs while any is. A view that stops says so with [on]
  /// false, and with [reset] puts its band back to rest if it was the last.
  void moving(WispBand band, bool on, {bool reset = true}) {
    final lane = _lanes[band]!;
    lane.moving = math.max(0, lane.moving + (on ? 1 : -1));
    final drifting = _lanes.values.fold<int>(0, (sum, one) => sum + one.moving);
    if (on && drifting == 1) {
      _lastFrameAt = 0;
      _frame ??= SchedulerBinding.instance.scheduleFrameCallback(_step);
    }
    if (drifting == 0 && _frame != null) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
      _frame = null;
    }
    if (!on && lane.moving == 0 && reset) rest(band);
  }

  /// A band at rest: its noise at the base frequency and not slid.
  void rest(WispBand band) => _lanes[band]!.set(WispDriftAt.rest);

  /// [rest], unless a view of the band has begun to scroll since it was asked for.
  void restIfStill(WispBand band) {
    if (_lanes[band]!.moving == 0) rest(band);
  }

  void _step(Duration timeStamp) {
    _frame = SchedulerBinding.instance.scheduleFrameCallback(_step);
    final now = timeStamp.inMicroseconds / 1000;
    // The smoke's own clock only runs while it moves, so a scroll picks it up where the last one left it.
    final gap = _lastFrameAt != 0 ? math.min(now - _lastFrameAt, 50.0) : 0.0;
    _lastFrameAt = now;
    final state = SchedulerBinding.instance.lifecycleState;
    if (_held > 0 || (state != null && state != AppLifecycleState.resumed)) return;
    for (final lane in _lanes.values) {
      if (lane.moving > 0) lane.clock += gap;
    }
    if ((now - _lastStep).abs() < wispDriftStepMs) return;
    _lastStep = now;
    for (final entry in _lanes.entries) {
      final lane = entry.value;
      if (lane.moving <= 0) continue;
      lane.set(WispDriftAt.at(lane.clock));
      if (entry.key != WispBand.page) continue;
      for (final follower in _followers.toList()) {
        follower(lane.at.slide.dx, lane.at.slide.dy, lane.at.frequency);
      }
    }
  }

  /// Everything as the app starts with it: for a test.
  @visibleForTesting
  void debugReset() {
    if (_frame != null) SchedulerBinding.instance.cancelFrameCallbackWithId(_frame!);
    _frame = null;
    _held = 0;
    _followers.clear();
    _lastFrameAt = 0;
    _lastStep = 0;
    for (final lane in _lanes.values) {
      lane
        ..moving = 0
        ..clock = 0
        ..set(WispDriftAt.rest);
    }
  }
}

class _Lane extends ChangeNotifier {
  int moving = 0;
  double clock = 0;
  WispDriftAt at = WispDriftAt.rest;

  void set(WispDriftAt value) {
    if (value == at) return;
    at = value;
    notifyListeners();
  }
}

// ---- the view ------------------------------------------------------------------------------------------------------

/// The wisp edge: the app's standard soft top for anything that scrolls under a header, and its foot
/// (art/wispEdge.ts `useWispEdge`, art/WispEdgeFilter.tsx, art/wisp.css). Content slipping up behind the header goes
/// to smoke, bent by fractal noise and softened, the bend growing the higher the content goes; words scrolling off
/// the foot dissolve the same way. While the view is scrolled the smoke drifts, and when the scrolling stops it
/// holds ([WispDrift]).
///
/// Wrap the thing that scrolls: `WispEdge(under: headerHeight, foot: true, child: ListView(...))`. The scroller is
/// found by the notifications it sends, so [child] must hold one vertical scroller, the outermost. The arguments are
/// the hook's:
///
/// - [under] is the height of a header the scroller runs beneath (the hook's `under` ref, measured); the band's lip
///   sits a drop below it. With none, the lip is at the view's top edge and the view fades over the status bar's
///   height and 8px more ([safeTop], `--app-safe-top` by default).
/// - [foot] smokes the foot while there is more below; [footOver] is the height of what stands over the foot (a
///   dock), so the smoke happens at its top edge and the view is gone below it.
/// - [draw] asks for a drawing by name ([WispDraw]); left out, the platform decides ([wispModeFor]): the filter on a
///   phone, and on a desktop no smoke, a blur strip under the header and a short fade at the foot.
/// - [band] is the column's for a column scrolling beside a page; it has no foot, and its lip eases down over the
///   first [wispEdgeEase] px of a scroll.
/// - [onChanged] is the hook's answer: whether the top is smoking.
///
/// As on the page: nothing is worn until the view is scrolled off its top and can scroll; nothing at all with the
/// smoke switched off ([WispSettings.wanted]); with reduced motion the bend goes and the fade stays; and a window
/// past the budget keeps its plain edge ([wispRegionFits]).
///
/// What differs from the page: the header is a number here, not an element the hook measures, and the view does not
/// set its own top padding from it (`--wisp-under`); whoever lays out the header knows its height and pads the
/// scroller. Its scrollbar under a header (`data-under-header`) is lib/shell/desktop/desktop_scrollbar.dart's. The
/// strips of the view that smoke are drawn through pictures of themselves and the rest of the view is left as it
/// paints (wisp_strips.dart), where the page filters the whole
/// element.
class WispEdge extends StatefulWidget {
  const WispEdge({
    super.key,
    required this.child,
    this.under = 0,
    this.covered = 0,
    this.foot = false,
    this.footOver = 0,
    this.draw,
    this.band = WispBand.page,
    this.safeTop,
    this.onChanged,
    this.scrollbar = true,
  });

  final Widget child;
  final double under;

  /// How much of [under] is behind something that hides the smoke: a header of glass, whose blur is wider than
  /// anything the smoke does (the bars' is 18px; the smoke throws a pixel 12 at most and softens by 3.4). The view
  /// is left to paint itself there, and the smoke begins [wispEdgeCoveredKeep] above the cover's foot: what shows
  /// under the header's edge is the same smoke, and what is behind the glass is the view through the same blur,
  /// bent or not. Nothing (the default) where the header is clear, or islands with the page between them. On a
  /// page whose header is most of the top strip this is most of the strip not drawn: under a header 107px tall,
  /// 72 rows of smoke where there were 171.
  final double covered;
  final bool foot;
  final double footOver;
  final WispDraw? draw;
  final WispBand band;

  /// The phone's status bar and whatever bar stands under it, where the view has no header: `--app-safe-top` when
  /// left out.
  final double? safeTop;
  final ValueChanged<bool>? onChanged;

  /// Whether the view wears a desktop's scrollbar under its header (lib/shell/desktop/desktop_scrollbar.dart). A
  /// note's page does not: measured in the page's own engine, its scroller keeps a scrollbar of no width whatever
  /// it holds, where the home page's is 12 px.
  final bool scrollbar;

  @override
  State<WispEdge> createState() => _WispEdgeState();
}

class _WispEdgeState extends State<WispEdge> with SingleTickerProviderStateMixin {
  double _pixels = 0, _max = 0;
  bool _worn = false, _footWorn = false, _moving = false;
  Timer? _idle;
  bool _still = false;
  double _ratio = 1;
  Size _window = Size.zero;
  double _safeTop = 0;
  Color _ground = const Color(0x00000000);
  Color? _ink;
  late final AnimationController _blur = AnimationController(vsync: this, duration: wispHeaderBlurTurn);
  final ValueNotifier<int> _ready = ValueNotifier(0);
  late WispBand _band = widget.band;

  bool get _wanted => WispSettings.instance.wanted;
  WispMode get _mode => wispModeFor(widget.draw);
  bool get _foot => widget.foot && widget.band == WispBand.page;

  /// On a desktop the top is a blurred strip hung under the header's glass, not smoke: only with a header.
  bool get _blurHead => widget.under > 0 && _mode == WispMode.fade;

  @override
  void initState() {
    super.initState();
    WispSettings.instance.addListener(_settingsChanged);
    _prepare();
  }

  /// What the drawing needs that cannot be had at once: the programs and the table, and for the mask its bands.
  void _prepare() {
    if (WispKit.maybe?.tableNow(3) == null) {
      WispKit.load().then((_) {
        if (mounted) _ready.value += 1;
      });
    }
    if (_mode == WispMode.mask && wispMaskBandsNow() == null) {
      wispMaskBands().then((_) {
        if (mounted) _ready.value += 1;
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final media = MediaQuery.of(context);
    _still = media.disableAnimations;
    _ratio = media.devicePixelRatio;
    _window = media.size;
    final tokens = GlacierTheme.maybeOf(context);
    _safeTop = widget.safeTop ?? (tokens?.raw('app-safe-top') != null ? tokens!.len('app-safe-top') : media.viewPadding.top);
    if (tokens != null) _ground = tokens.color('glacier-bg');
    if (tokens != null) _ink = tokens.color('glacier-text');
    if (_still) _holdStill(false);
  }

  @override
  void didUpdateWidget(WispEdge old) {
    super.didUpdateWidget(old);
    if (old.band != widget.band) {
      _holdStill(true);
      _band = widget.band;
    }
    if (old.safeTop != widget.safeTop && widget.safeTop != null) _safeTop = widget.safeTop!;
    if (old.draw != widget.draw) _prepare();
    if (old.foot != widget.foot || old.draw != widget.draw || old.under != widget.under || old.band != widget.band) _check();
  }

  @override
  void dispose() {
    WispSettings.instance.removeListener(_settingsChanged);
    _idle?.cancel();
    if (_moving) {
      // A view taken down within the idle of its last scroll (a page left as it was flicked): the band comes to
      // rest once the frame is done, since the tree is locked now and the band's listeners would be told to rebuild.
      _moving = false;
      final band = _band;
      WispDrift.instance.moving(band, false, reset: false);
      SchedulerBinding.instance.addPostFrameCallback((_) => WispDrift.instance.restIfStill(band));
    }
    _blur.dispose();
    _ready.dispose();
    super.dispose();
  }

  void _settingsChanged() {
    if (!mounted) return;
    if (!_wanted) _holdStill(true);
    _prepare();
    _check();
    _rebuild();
  }

  /// Builds again for a change that came in a notification, which may arrive while the frame is being built.
  void _rebuild() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// The view's size as its last layout gave it ([build]'s `LayoutBuilder`), kept so that asking does not read a
  /// box in the middle of a layout: a scroller that ends a drag while it is laid out (a pull to refresh takes its
  /// physics away, and the framework cancels the drag from `applyNewDimensions`) says so to this view there and
  /// then, and a debug build refuses `RenderBox.size` to anyone but the box's parent at that moment. The refusal
  /// came up through the scroller's own cancel, which left it in its drag for good: the home page took no touch
  /// after a pull until the app was started again.
  Size? _laid;

  Size? get _size => _laid;

  /// How far above its place the top band's lip is at this scroll: the page's never; the column's while it eases in.
  double get _lift => widget.band == WispBand.column ? math.max(0, wispEdgeEase - _pixels.roundToDouble()) : 0;

  /// Whether the web filter's region could cover this view at all: a window past the budget goes without.
  bool get _roomy {
    if (_mode != WispMode.filter) return true;
    final size = _size;
    if (size == null) return true;
    final box = context.findRenderObject()! as RenderBox;
    final right = box.attached ? box.localToGlobal(Offset(size.width, 0)).dx : size.width;
    return wispRegionFits(view: size, window: _window, band: widget.band, ratio: _ratio, right: right);
  }

  void _holdStill(bool reset) {
    _idle?.cancel();
    if (!_moving) return;
    _moving = false;
    WispDrift.instance.moving(_band, false, reset: reset);
  }

  /// art/wispEdge.ts `check`: which ends this view wears at this scroll.
  void _check() {
    if (!mounted) return;
    if (!_wanted) {
      if (_worn || _footWorn) {
        _worn = false;
        _footWorn = false;
        _blur.value = 0;
        widget.onChanged?.call(false);
        _rebuild();
      }
      return;
    }
    // Scrolled off its top AND able to scroll: a view that stops scrolling keeps its place, and must not go on smoking.
    final more = _max > 4;
    final roomy = _roomy;
    final scrolled = _pixels > 4 && more && roomy;
    // The foot smokes while there is still something below the view's bottom edge to scroll to.
    final ending = _foot && more && roomy && _pixels < _max - 4;
    if (ending != _footWorn) {
      _footWorn = ending;
      _rebuild();
    }
    if (scrolled == _worn) return;
    _worn = scrolled;
    _rebuild();
    widget.onChanged?.call(scrolled);
    if (_blurHead) {
      scrolled ? _blur.forward() : _blur.reverse();
      return;
    }
    // The top band goes with it, and a view back at its top puts its band back to rest.
    if (!scrolled) _holdStill(true);
  }

  bool _metrics(ScrollMetrics metrics, {required bool scrolled}) {
    if (metrics.axis != Axis.vertical) return false;
    final lift = _lift;
    _pixels = metrics.pixels - metrics.minScrollExtent;
    _max = metrics.maxScrollExtent - metrics.minScrollExtent;
    _check();
    // Smoking already: the column's lip may still be on its way down.
    if (_lift != lift) _rebuild();
    if (scrolled) _onScroll();
    return false;
  }

  /// Scrolling moves the smoke; a pause in it holds the smoke where it is. A desktop's plain edges have no smoke to
  /// move, so their scrolling starts no loop.
  void _onScroll() {
    if ((!_worn && !_footWorn) || _still || _mode == WispMode.fade || !_wanted) return;
    if (!_moving) {
      _moving = true;
      _band = widget.band;
      WispDrift.instance.moving(_band, true);
    }
    _idle?.cancel();
    _idle = Timer(wispScrollIdle, () => _holdStill(false));
  }

  List<WispStrip> _strips(Size size) {
    if (!_wanted || (!_worn && !_footWorn && !_blurHead) || WispProbe.has('noedge')) return const [];
    final mode = _mode;
    final width = size.width, height = size.height;
    // With no header the page means the status bar to play the part (`beneath = height || safeTop()`), but its
    // `safeTop()` is `parseFloat` of `--app-safe-top`, which the app writes as a `calc()`: not a number, so 0. On a
    // phone the lip therefore sits at the view's own top edge with no drop, hidden in the first of the fade, and what
    // is seen is the fade alone, `--app-safe-top + 8px` long (measured in Settings on Android: the strip ends 7px
    // down, the mask is whole at 150px). The port stands where the page stands, not where its comment says.
    final beneath = widget.under > 0 ? widget.under : 0.0;
    final drop = beneath > 0 ? wispEdgeDrop : 0.0;
    // Under a header the header hides the top; with none the view dissolves into the status bar's own ground.
    final topFade = !_worn || widget.under > 0 ? 0.0 : _safeTop + 8;
    final inset = _foot ? widget.footOver : 0.0;
    final strips = <WispStrip>[];

    if (mode == WispMode.mask) {
      final bands = wispMaskBandsNow();
      final slide = _still ? Offset.zero : WispDrift.instance.at(widget.band).slide;
      const bandSize = Size(wispMaskTile, wispMaskHeight);
      if (_worn) {
        final lip = beneath + drop - _lift;
        strips.add(WispMaskStrip(
          rect: Rect.fromLTRB(0, 0, width, math.min(height, lip + wispTearTop)),
          whole: Rect.zero,
          band: bands?.top,
          bandSize: bandSize,
          bandAt: Offset(slide.dx, lip - wispMaskAbove + slide.dy),
        ));
      }
      if (_footWorn) {
        final edge = height - inset;
        strips.add(WispMaskStrip(
          rect: Rect.fromLTRB(0, math.max(0, edge - wispTearFoot), width, height),
          whole: Rect.zero,
          band: bands?.foot,
          bandSize: bandSize,
          // `mask-position: calc(100% - ...)`: the percentage is of the room left over, the view less the band.
          bandAt: Offset(slide.dx, (height - wispMaskHeight) - inset - wispMaskHeight + wispMaskAbove - slide.dy),
        ));
      }
      return strips;
    }

    final smokes = mode == WispMode.filter && !_still;
    final footFade = !_footWorn ? 0.0 : (mode == WispMode.fade ? wispFootFadePlain : wispFootFadeSmoke);
    final fade = wispEdgeFade(height: height, topFade: topFade, footFade: footFade, inset: inset);

    if (_blurHead) {
      if (_blur.value > 0) {
        final shown = Curves.easeOut.transform(_blur.value);
        strips.add(WispBlurStrip(
          rect: Rect.fromLTWH(0, widget.under, width, math.min(wispHeaderBlurDepth, math.max(0, height - widget.under))),
          wash: _ground.withValues(alpha: wispHeaderBlurWash),
          opacity: shown,
          sigma: wispHeaderBlurSigma,
        ));
      }
    } else if (_worn) {
      if (smokes) {
        final at = WispDrift.instance.at(widget.band);
        // Behind a header that hides it, no smoke is drawn (`covered`; a measured build can say every header is one).
        final hidden = WispProbe.has('covered') ? beneath : math.min(widget.covered, beneath);
        strips.addAll(wispSmokeStrips(
          // Down to the end of the fade where that is longer than the band: the strip is what the mask is drawn in.
          rect: Rect.fromLTRB(0, math.max(0, hidden - wispEdgeCoveredKeep), width, math.min(height, math.max(beneath + drop + wispEdgeReach, topFade))),
          smoke: wispTopSmoke(under: beneath, lift: _lift, at: at, fade: fade),
          within: wispTopWithin(beneath),
          paper: _ground,
          ink: _ink,
        ));
      } else if (topFade > 0) {
        strips.add(WispFadeStrip(rect: Rect.fromLTRB(0, 0, width, math.min(height, topFade)), fade: fade));
      }
    }

    if (_footWorn) {
      final edge = height - inset;
      if (smokes) {
        // The foot's own noise drifts with the page's top, so both ends of a view move as one smoke.
        final at = WispDrift.instance.at(WispBand.page);
        final within = wispFootWithin(edge);
        strips.addAll(wispSmokeStrips(rect: Rect.fromLTRB(0, math.max(0, within.top), width, height), smoke: wispFootSmoke(height: edge, at: at, fade: fade), within: within, paper: _ground, ink: _ink));
      } else {
        strips.add(WispFadeStrip(rect: Rect.fromLTRB(0, math.max(0, edge - footFade), width, height), fade: fade));
      }
    } else if (_worn && inset > 0 && !_blurHead) {
      // The mask still ends where the dock begins.
      strips.add(WispFadeStrip(rect: Rect.fromLTRB(0, math.max(0, height - inset), width, height), fade: fade));
    }
    return strips;
  }

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (notification) => notification.depth == 0 && _metrics(notification.metrics, scrolled: false),
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) => notification.depth == 0 && _metrics(notification.metrics, scrolled: notification is ScrollUpdateNotification),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
              _laid = null;
              return widget.child;
            }
            final size = constraints.biggest;
            _laid = size;
            return ListenableBuilder(
              listenable: Listenable.merge([WispDrift.instance.of(widget.band), WispDrift.instance.of(WispBand.page), _blur, _ready]),
              builder: (context, child) => WispStrips(strips: _strips(size), repaint: _ready, child: child),
              // Where there is a mouse, a view under a header wears the page's own scrollbar, from the header's
              // foot down (app.css `[data-under-header]`); nothing on a phone.
              child: widget.scrollbar ? DesktopScrollbar(under: widget.under, child: widget.child) : widget.child,
            );
          },
        ),
      ),
    );
  }
}
