/// The walkthrough: what Ghost.md is, how it looks, which model it runs, and where the rest is taught. A port of
/// `src/app/guide/Guide.tsx` with `Guide.module.css` (the frame's rules: `.guide`, `.top`, `.progress`,
/// `.progressDot`, `.skip`, `.page`, `.tooSoon`, `.dock`, `.nav`, `.primary`, `.nextSlot`, `.next`, `.nudge`).
///
/// Shown once on first launch and any time from Settings › About or the palette. Since 2026-10-27 (Matt: "build an
/// onboarding flow with vivid colors and iconography as well as a friendly elevenlabs v4 voice explaining each
/// section") it is a tour of the app, a section a page: each page a band in a colour of its own with large icons
/// floating in it (pages/band.dart), its headline, and its words, which a friendly voice reads aloud as the page
/// shows (narrator.dart, the words in narration.dart) and which stay on the page as its captions. The speaker in the
/// bar turns the voice off and on, remembered on the device. On a phone the band is above the words; on a wide
/// window (an unfolded Fold, the Mac) it stands beside them and stays while they scroll.
///
/// This is the frame the pages share: the dots saying where the reader is, the speaker, Skip, the dock with Back and
/// Next where the thumb is, the back gesture and the swipes. Each page's words are a widget of its own in
/// lib/guide/pages/, in the order pages.dart names them. The last page hands over to the Academy.
///
/// It covers the whole screen, the app's tab bar included: put it over everything else, and take it away while a
/// recording is on screen (the page it is on is the caller's to hold, so a person who went off and came back is
/// where they were).
///
/// What differs:
/// - The model page is given the phone's models ([Guide.models], guide_models.dart), and the theme and model pages
///   the preferences ([Guide.preferences]); the page's pages reach for modules.
/// - [Guide.recordsVoice] is the caller's to say, where the page reads the platform.
/// - The page under the bar is padded by the bar's height as it is worked out here; the page measures its header
///   (`--wisp-under`, a whole pixel) and falls back to 3.5rem.
/// - A swipe is watched by swipe_nav.dart, a port of `useSwipeNav` kept in this folder.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/widgets.dart';
import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../art/blur_edge.dart';
import '../art/wisp_text.dart';
import '../core/back.dart';
import '../core/preferences.dart';
import '../notes/tabs/bar_parts.dart' show BarGlass;
import 'bottom_nudge.dart';
import 'guide_models.dart';
import '../shell/desktop/mac_lights.dart';
import 'narrator.dart';
import 'pages.dart';
import 'pages/about.dart';
import 'pages/band.dart';
import 'pages/mode.dart';
import 'pages/model.dart';
import 'pages/parts.dart';
import 'pages/start.dart';
import 'pages/welcome.dart';
import 'swipe_nav.dart';

class Guide extends StatefulWidget {
  const Guide({
    super.key,
    required this.index,
    required this.onIndex,
    required this.onClose,
    required this.onAcademy,
    this.tooSoon = false,
    this.models,
    this.preferences,
    this.recordsVoice = true,
    this.random,
    this.narrator,
  });

  /// The page showing, held by the caller: the guide is taken away while a capture is on screen, and a person who
  /// went off to record from page 2 should come back to page 2.
  final int index;
  final ValueChanged<int> onIndex;
  final VoidCallback onClose;

  /// The last page's other way out: the Academy, for the rest.
  final VoidCallback onAcademy;

  /// The reader held the side key before the guide got to it (too_soon.dart): one line says so, at the top of the
  /// page.
  final bool tooSoon;

  /// The phone's models, for the model page; a phone with none to fetch when null.
  final GuideModels? models;

  /// The preferences the theme and model pages set; the app's own when null.
  final ValueNotifier<Preferences>? preferences;

  /// Whether this phone records, for what the first page promises.
  final bool recordsVoice;

  /// Where the nudge's words are picked from: a test gives its own.
  final math.Random? random;

  /// What reads each page aloud; one of the guide's own when null, let go with it. A test gives its own, with a
  /// player that counts.
  final Narrator? narrator;

  @override
  State<Guide> createState() => _GuideState();
}

class _GuideState extends State<Guide> with WidgetsBindingObserver {
  late final BottomNudge _nudge = BottomNudge(random: widget.random);
  late final Narrator _narrator = widget.narrator ?? Narrator();
  final NoGuideModels _noModels = NoGuideModels();
  ScrollController _scroll = ScrollController();

  ValueNotifier<Preferences> get _prefs => widget.preferences ?? preferences;
  List<GuidePage> get _pages => walkthroughPagesFor(ios: kIsWeb || defaultTargetPlatform == TargetPlatform.iOS, prefs: _prefs.value);
  GuidePage get _page => _pages[widget.index.clamp(0, _pages.length - 1)];
  bool get _last => widget.index == _pages.length - 1;

  @override
  void initState() {
    super.initState();
    _nudge.addListener(_changed);
    // The mode page takes the model page out of the count as Simple is tapped: the dots and Next follow at once.
    _prefs.addListener(_changed);
    _narrator.addListener(_changed);
    WidgetsBinding.instance.addObserver(this);
    _opened();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// The page being read aloud, said again only when the page showing is another.
  GuidePage? _said;

  void _say() {
    final page = _page;
    if (page == _said) return;
    _said = page;
    _narrator.show(page);
  }

  /// The app has left the screen: the voice stops with it, and is not started again on the way back, where the words
  /// are on the page to read.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) unawaited(_narrator.hush());
  }

  /// A page has opened: the nudge waits afresh, and the page is measured once it has been laid out.
  void _opened() {
    _nudge.opened();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measure();
      if (mounted) _say();
    });
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    _nudge.measured(max: position.maxScrollExtent, pixels: position.pixels);
  }

  @override
  void didUpdateWidget(Guide old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) {
      // Each page is a scroller of its own, from its top (`key={page}`).
      final was = _scroll;
      _scroll = ScrollController();
      WidgetsBinding.instance.addPostFrameCallback((_) => was.dispose());
      _opened();
    }
  }

  @override
  void dispose() {
    _nudge
      ..removeListener(_changed)
      ..dispose();
    _prefs.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _narrator.removeListener(_changed);
    // The guide has gone: so does its voice.
    if (widget.narrator == null) {
      _narrator.dispose();
    } else {
      unawaited(_narrator.hush());
    }
    _noModels.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The phone's back gesture (and Escape) steps back through the guide before it closes it; a swipe right does the
  /// same, and a swipe left is Next.
  void _stepBack() {
    if (widget.index > 0) {
      widget.onIndex(widget.index - 1);
    } else {
      widget.onClose();
    }
  }

  void _toBottom() {
    if (!_scroll.hasClients) return;
    final t = context.tokens;
    final to = _scroll.position.maxScrollExtent;
    if (t.reducedMotion) {
      _scroll.jumpTo(to);
    } else {
      _scroll.animateTo(to, duration: t.duration('glacier-duration-slow'), curve: Curves.easeInOut);
    }
  }

  Widget _view() => switch (_page) {
    GuidePage.welcome => GuideWelcome(recordsVoice: widget.recordsVoice),
    GuidePage.speak || GuidePage.meetings || GuidePage.ai || GuidePage.sync || GuidePage.market => GuideAbout(page: _page),
    GuidePage.mode => GuideMode(store: widget.preferences),
    GuidePage.model => GuideModel(phone: widget.models ?? _noModels, store: widget.preferences),
    GuidePage.start => GuideStart(onAcademy: widget.onAcademy, store: widget.preferences),
  };

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final start = t.len('app-gutter-start');
    final end = t.len('app-gutter-end');
    final bleed = t.space(2);
    final atBottom = _nudge.atBottom;
    final nudging = !atBottom && _nudge.due;

    // The top bar: the guide clears the notch alone (`--app-inset-top`, not `--app-safe-top`, which carries the
    // app's tab bar as well).
    final barTop = t.len('app-inset-top') + t.space(1);
    final barHeight = barTop + t.space(12) + t.space(2);
    // `--wisp-under`: the header's height as the page reads it, a whole pixel.
    final under = barHeight.roundToDouble();
    final barPx = t.len('app-action') * 0.88;

    // On the Mac the window's three buttons are where the bar's dots begin: the bar starts after their room and
    // says where its centre is, so they sit on it (the tab bar's rule; the page has none for the guide).
    final lights = trafficLightsRoom(t);
    final header = Padding(
      padding: EdgeInsets.fromLTRB(start + lights, barTop, end - bleed, t.space(2)),
      child: _onLights(lights > 0, Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _Progress(at: widget.index, count: _pages.length, hue: guideLooks[_page]!.hue),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Voice(off: _narrator.muted, onPressed: () => _narrator.setMuted(!_narrator.muted)),
              // Nearly the size of Back and Next below: the page's corners read as one set of controls.
              GuideWord(_last ? 'Close' : 'Skip', onPressed: widget.onClose, style: t.textAt(barPx, weight: 'semibold')),
            ],
          ),
        ],
      )),
    );

    // A wide window (an unfolded Fold, a tablet, the Mac) has the band beside the words, the height of the page and
    // still while the words scroll; a phone has it above them, about a third of the screen.
    final screen = MediaQuery.sizeOf(context);
    final wide = screen.width >= guideWideFrom;
    final footRoom = t.len('app-safe-bottom') + t.space(24);
    final bandWidth = wide ? math.min((screen.width - start - end) * 0.46, 620.0) : 0.0;
    final bandGap = t.space(10);
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.tooSoon) const _TooSoon(),
        if (!wide) ...[
          GuideBand(page: _page, height: (screen.height * 0.3).clamp(170.0, 300.0)),
          SizedBox(height: t.space(6)),
        ],
        _view(),
      ],
    );
    final page = SingleChildScrollView(
      key: ValueKey(_page),
      controller: _scroll,
      // `overscroll-behavior: contain`.
      // Starts under the bar, so content only meets its blur once scrolled.
      padding: EdgeInsets.fromLTRB(wide ? start + bandWidth + bandGap : start, under + t.space(4), end, t.space(24)),
      child: _Enter(child: wide ? ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: words) : words),
    );
    final band = !wide
        ? null
        : Positioned(
            left: start,
            top: under + t.space(4),
            bottom: footRoom,
            width: bandWidth,
            child: _Enter(key: ValueKey(_page), child: LayoutBuilder(builder: (context, box) => GuideBand(page: _page, height: box.maxHeight))),
          );

    final actionPx = t.len('app-action');
    final dock = Padding(
      padding: EdgeInsets.fromLTRB(start - bleed, t.space(8), end, t.len('app-safe-bottom') + t.space(3)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // `.nav[data-hidden] { visibility: hidden }`: its place is kept on the first page.
          Visibility(
            visible: widget.index > 0,
            maintainSize: true,
            maintainAnimation: true,
            maintainState: true,
            child: GuideWord(
              'Back',
              onPressed: widget.index > 0 ? () => widget.onIndex(widget.index - 1) : null,
              style: t.textAt(actionPx, weight: 'semibold', tracking: t.len('app-tracking-title', em: actionPx)),
            ),
          ),
          // Next and the nudge share one place in the dock: Next waits for the bottom of the page, the nudge fades in
          // meanwhile.
          Stack(
            alignment: Alignment.centerRight,
            children: [
              _Shown(
                shown: nudging,
                child: _Primary(
                  onPressed: _toBottom,
                  icon: _Bob(on: nudging, child: AppIcon(Lucide.arrowDown, size: 18, strokeWidth: 2.6, color: t.color('app-paper'))),
                  label: _nudge.words,
                ),
              ),
              _Shown(
                shown: atBottom,
                child: _last ? _Primary(onPressed: widget.onClose, label: 'Start') : _Primary(onPressed: () => widget.onIndex(widget.index + 1), label: 'Next'),
              ),
            ],
          ),
        ],
      ),
    );

    return OnBack(
      onBack: _stepBack,
      child: SwipeNav(
        onBack: _stepBack,
        onForward: () {
          if (!_last && _nudge.atBottom) widget.onIndex(widget.index + 1);
        },
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          namesRoute: true,
          label: 'How to use Ghost.md',
          child: ColoredBox(
            color: t.color('glacier-bg'),
            child: DefaultTextStyle(
              style: t.textAt(16),
              child: Stack(
                children: [
                  // Content slipping behind the top bar goes soft, and into the fade over the buttons at the foot.
                  Positioned.fill(
                    child: NotificationListener<ScrollMetricsNotification>(
                      // Told once the frame that changed them is over: the page grew, or the window did.
                      onNotification: (_) {
                        _measure();
                        return false;
                      },
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (_) {
                          _measure();
                          return false;
                        },
                        child: BlurEdge(under: under, foot: true, safeTop: t.len('app-inset-top'), child: page),
                      ),
                    ),
                  ),
                  ?band,
                  // The top bar sits over the page rather than above it: a blurred pane the smoke leads into.
                  Positioned(top: 0, left: 0, right: 0, child: BarGlass(child: header)),
                  Positioned(left: 0, right: 0, bottom: 0, child: dock),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the reader is, as a row of dots, the one on show filled (`.progress`, `.progressDot`): a ring still to
/// come, a small filled dot passed, and a longer filled bar for the one on show.
class _Progress extends StatelessWidget {
  const _Progress({required this.at, required this.count, required this.hue});
  final int at;
  final int count;

  /// The page's own colour (band.dart), which the lit dot wears.
  final Color hue;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final subtle = t.color('glacier-text-subtle');
    final turn = t.reducedMotion ? Duration.zero : const Duration(milliseconds: 240);
    return Semantics(
      image: true,
      label: 'Page ${at + 1} of $count',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            AnimatedContainer(
              duration: turn,
              curve: t.curve('glacier-ease-out'),
              width: i == at ? 18 : 7,
              height: 7,
              decoration: BoxDecoration(
                color: i == at ? hue : (i < at ? subtle : subtle.withValues(alpha: 0)),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: i == at ? hue : subtle, width: t.len('app-line')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// From this width the band stands beside the words rather than above them: an unfolded Fold, a tablet, a window
/// on the Mac.
const double guideWideFrom = 720;

/// The speaker in the bar: the voice on, or crossed out and off. Remembered on the device (narrator.dart).
class _Voice extends StatelessWidget {
  const _Voice({required this.off, required this.onPressed});
  final bool off;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      button: true,
      toggled: !off,
      label: 'Read aloud',
      excludeSemantics: true,
      onTap: onPressed,
      child: GlacierPressable(
        key: const ValueKey('guide-voice'),
        onPressed: onPressed,
        builder: (context, state) {
          final ink = state.pressed ? t.color('glacier-text') : t.color('glacier-text-muted');
          return GlacierFocusRing(
            visible: state.focused,
            radius: t.radius('sm'),
            child: SizedBox.square(
              dimension: t.space(12),
              child: Center(
                child: SizedBox.square(
                  dimension: 24,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      AppIcon(Lucide.volume2, size: 24, strokeWidth: 2.2, color: ink),
                      // Off is the speaker struck through, edged in the page's ground so the stroke reads over it.
                      if (off)
                        Transform.rotate(
                          angle: math.pi / 4,
                          child: Container(
                            width: 3,
                            height: 30,
                            decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(2), border: Border.symmetric(vertical: BorderSide(color: t.color('glacier-bg'), width: 0.8))),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// `.page`'s `enter`: a page arrives from eight pixels down, out of nothing, over the normal duration.
class _Enter extends StatelessWidget {
  const _Enter({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    if (t.reducedMotion) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: t.duration('glacier-duration-normal'),
      curve: t.curve('glacier-ease-out'),
      child: child,
      builder: (context, at, child) => at >= 1 ? child! : Opacity(opacity: at, child: Transform.translate(offset: Offset(0, 8 * (1 - at)), child: child)),
    );
  }
}

/// "Not yet, finish reading.": a line at the top of the page for a reader who held the side key too early, out of
/// smoke like the rest (`.tooSoon`).
class _TooSoon extends StatelessWidget {
  const _TooSoon();

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final px = t.fontSize('lg');
    final style = t
        .textAt(px, weight: 'medium', height: 1.3, tracking: -0.01 * px, color: t.color('app-ink-2'))
        .copyWith(shadows: [Shadow(blurRadius: 18, color: t.colorOf('color-mix(in oklch, var(--app-ink) 30%, transparent)'))]);
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(5)),
      child: Semantics(liveRegion: true, container: true, child: guideLines(style, WispText('Not yet, finish reading.', pace: 18, style: style))),
    );
  }
}

/// `.app-pill.primary`: the dock's filled button, at least 8.5rem wide.
class _Primary extends StatelessWidget {
  const _Primary({required this.onPressed, required this.label, this.icon});
  final VoidCallback onPressed;
  final String label;
  final Widget? icon;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(minWidth: context.tokens.lenOf('8.5rem')),
    child: AppPill(onPressed: onPressed, icon: icon, child: Text(label, maxLines: 1, softWrap: false)),
  );
}

/// `.next, .nudge` and their `[data-shown]`: there and pressable, or gone eight pixels down and out of reach, said
/// to no one (`aria-hidden`, `tabindex="-1"`).
class _Shown extends StatelessWidget {
  const _Shown({required this.shown, required this.child});
  final bool shown;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final still = context.tokens.reducedMotion;
    return IgnorePointer(
      ignoring: !shown,
      child: ExcludeFocus(
        excluding: !shown,
        child: ExcludeSemantics(
          excluding: !shown,
          child: AnimatedOpacity(
            opacity: shown ? 1 : 0,
            duration: Duration(milliseconds: still ? 200 : 320),
            curve: still ? Curves.linear : Curves.easeOut,
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: shown || still ? 0 : 8),
              duration: still ? Duration.zero : const Duration(milliseconds: 420),
              curve: const Cubic(0.2, 1.4, 0.4, 1),
              child: child,
              builder: (context, down, child) => Transform.translate(offset: Offset(0, down), child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// The nudge's arrow bobs, pointing the way (`nudgeBob`: three pixels down and back, 900 ms each way).
class _Bob extends StatefulWidget {
  const _Bob({required this.on, required this.child});
  final bool on;
  final Widget child;

  @override
  State<_Bob> createState() => _BobState();
}

class _BobState extends State<_Bob> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  void _sync() {
    final moving = widget.on && !context.tokens.reducedMotion;
    if (moving && !_bob.isAnimating) {
      _bob.repeat(reverse: true);
    } else if (!moving && _bob.isAnimating) {
      _bob
        ..stop()
        ..value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Bob old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _bob,
    child: widget.child,
    builder: (context, child) => Transform.translate(offset: Offset(0, 3 * Curves.easeInOut.transform(_bob.value)), child: child),
  );
}

/// The guide's bar as the row the Mac's window buttons are set on, where there are any.
Widget _onLights(bool mac, Widget row) => mac ? MacLightsRow(child: row) : row;
