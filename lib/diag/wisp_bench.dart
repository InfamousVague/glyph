/// Settings › Developer › Smoke bench: the wisp edge drawn three ways on the same page, with its cost on the screen.
/// A port of `src/app/diag/WispBench.tsx` and `WispBench.module.css`.
///
/// A page that scrolls, wearing the filter, the mask, or nothing, with a frame counter in its header while a hand
/// scrolls it, and a run that drives it the three ways the first rig did (at rest, one repaint a frame, scrolling)
/// and puts the numbers in a table anyone can read off the screen and copy. One surface at a time while measuring: a
/// frame's length is the window's, so three surfaces at once would add up. Side by side is for looking, and says so.
/// Each surface wears [WispEdge] with its own `draw`, exactly what the app's pages wear with that switch; nothing
/// here draws smoke of its own.
///
/// What differs:
/// - **The readings are Flutter's.** A frame here is the scheduler's (lib/diag/frame_clock.dart), the filter is a
///   fragment shader over strips of the view and the mask a picture drawn through them (lib/art/wisp_edge.dart),
///   where the page's were an SVG filter over the whole element and a CSS mask. The numbers answer the same question
///   of this engine; they are not the page's numbers and are not to be read beside them.
/// - "Wearing" is read from the strips the view is drawn through (wisp_bench_run.dart [wearingOf]).
/// - The page mounted itself over Settings with a portal. This is a widget that fills what it is given: [WispBench]
///   in a stack over the screen, or [showWispBench], which puts it on the navigator with no transition.
/// - Closed by the back gesture and by Escape ([OnBack]; the key is also listened for here, for a tree with no
///   `BackScope`).
/// - The header's glass is the blur alone; `saturate(1.1)` is not drawn, as elsewhere in this port.
/// - The table scrolls sideways by itself where it is wider than the page; on the page the whole body did. Its
///   columns are sized the way a browser sizes an automatic table: each as narrow as its longest word.
/// - "The whole app draws…" has no Mac wording: here the filter is the default on every platform
///   (lib/art/wisp_settings.dart). The override is kept under the same key and takes effect when the app next reads
///   it ([useWispDrawAsked]).
/// - The surfaces stand three across from 900 px of WINDOW, as the stylesheet's media query has it.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/back.dart';
import '../core/stored.dart';
import '../settings/kit/settings_kit.dart';
import '../settings/kit/settings_type.dart';
import '../settings/panes/about_pane.dart' show ghostVersion;
import 'frame_clock.dart';
import 'wisp_bench_run.dart';

/// The words the surface is made of (`PARAGRAPHS`).
const List<String> benchParagraphs = [
  'This page exists to be scrolled. Every word on it is here so the surface has the height of a real note and the texture of one: headings, paragraphs of different lengths, the shapes the smoke has to bend or tear.',
  'What is being measured is not the words but the frame. Each time the page repaints, the engine draws it again, and a filter on the page means the whole of it goes through the filter’s graph on every one of those repaints, however small the change that caused it.',
  'A mask is a different bargain. The band’s shape is made once, as a picture, and the engine keeps that picture; scrolling under it moves the words, not the picture, so the frame costs what a frame of plain scrolling costs.',
  'The counter in the header is the last hundred and twenty frames, read as a median, a ninetieth percentile and a worst. Scroll by hand and watch it. A median that is fine and a p90 that is not is what lag feels like.',
  'The run below drives the surface the three ways the first rig did: left alone, a repaint each frame, and a scroll each frame. One drawing at a time, since a frame is the page’s and three surfaces would add up.',
  'Nothing here is a model of the app. The surface wears the hook the app’s pages wear, with the same switch, so what it costs here is what a note costs there.',
];

/// Enough of the same words to scroll a long way (`SECTIONS`).
const int benchSections = 8;

/// Puts the bench over everything, at once, and takes it away when it is closed.
Future<void> showWispBench(BuildContext context) => Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (route, _, _) => WispBench(open: true, onClose: () => Navigator.of(route).maybePop()),
      ),
    );

/// The next frame.
Future<void> _frame() {
  final done = Completer<void>();
  SchedulerBinding.instance.scheduleFrameCallback((_) => done.complete());
  return done.future;
}

/// Waits for the surface to settle (`settle`): the edge flips on a scroll, and its drift stops a moment after.
Future<void> _settle(Duration wait) async {
  await Future<void>.delayed(wait);
  await _frame();
  await _frame();
}

/// The width of a `0` in [style]: CSS's `ch`.
double _ch(TextStyle style) => (TextPainter(text: TextSpan(text: '0', style: style), textDirection: TextDirection.ltr)..layout()).width;

double _wide(String text, TextStyle style) => (TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout()).width;

/// Words whose lines are a fraction of a pixel tall on the page (`line-height: 1.5` of 13.39px is 20.09), in a box
/// as tall as the page's. Flutter's text engine sets each such line on a whole pixel (lib/sheet/css.dart says the
/// same of it), so six lines stand half a pixel short and everything under them half a pixel high; the box makes up
/// the difference under the last line.
class FractionLines extends StatelessWidget {
  const FractionLines(this.span, {super.key, required this.style});

  FractionLines.text(String words, {super.key, required this.style}) : span = TextSpan(text: words);

  final InlineSpan span;

  /// The words' style, with the line's height as a multiple ([TextStyle.height]).
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final line = style.fontSize! * style.height!;
    return LayoutBuilder(
      builder: (context, box) {
        final painter = TextPainter(text: TextSpan(style: style, children: [span]), textDirection: Directionality.of(context), textScaler: MediaQuery.textScalerOf(context))
          ..setPlaceholderDimensions([
            for (final _ in _placeholders(span)) const PlaceholderDimensions(size: Size.zero, alignment: PlaceholderAlignment.bottom),
          ])
          ..layout(maxWidth: box.maxWidth);
        final lines = painter.computeLineMetrics().length;
        painter.dispose();
        return SizedBox(height: lines * line, child: Align(alignment: AlignmentDirectional.topStart, child: Text.rich(span, style: style)));
      },
    );
  }

  static Iterable<InlineSpan> _placeholders(InlineSpan span) sync* {
    if (span is PlaceholderSpan) yield span;
    if (span is TextSpan) {
      for (final child in span.children ?? const <InlineSpan>[]) {
        yield* _placeholders(child);
      }
    }
  }
}

class WispBench extends StatefulWidget {
  const WispBench({
    super.key,
    required this.open,
    required this.onClose,
    this.quick = quickLimits,
    this.long = longLimits,
    this.settle = const Duration(milliseconds: 600),
    this.kept,
    this.clock,
    this.version = ghostVersion,
  });

  final bool open;
  final VoidCallback onClose;

  /// The run's limits; the tests shorten them.
  final CellLimits quick, long;

  /// How long to wait for a surface to settle before a cell; the tests don't wait.
  final Duration settle;

  /// Where the app-wide choice is kept; the app's own memory when null.
  final Stored? kept;

  /// The clock a cell is run on; the scheduler's when null.
  final FrameClock? clock;

  /// What the table's first line calls this build.
  final String version;

  @override
  State<WispBench> createState() => _WispBenchState();
}

class _WispBenchState extends State<WispBench> {
  BenchDraw _draw = BenchDraw.filter;
  bool _beside = false;
  String? _running;
  List<BenchRow> _rows = const [];
  String _where = '';
  late WispDraw? _appWide = wispDrawAsked(widget.kept);
  final Copied _copied = Copied('');
  final FocusNode _focus = FocusNode(debugLabel: 'Smoke bench');
  late final TapGestureRecognizer _useTap = TapGestureRecognizer()..onTap = () => _tellApp(_draw.wisp);
  late final TapGestureRecognizer _backTap = TapGestureRecognizer()..onTap = () => _tellApp(null);
  final Map<BenchDraw, ScrollController> _scrollers = {for (final draw in BenchDraw.values) draw: ScrollController()};
  final Map<BenchDraw, GlobalKey> _surfaces = {for (final draw in BenchDraw.values) draw: GlobalKey()};

  /// The repaint cell's mark: where it is in the page, and the frame it was last toggled on; null and there is none.
  final ValueNotifier<({double top, int frame})?> _mark = ValueNotifier(null);

  @override
  void initState() {
    super.initState();
    WispSettings.instance.addListener(_changed);
  }

  @override
  void dispose() {
    WispSettings.instance.removeListener(_changed);
    _copied.dispose();
    _useTap.dispose();
    _backTap.dispose();
    _focus.dispose();
    _mark.dispose();
    for (final controller in _scrollers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  /// Tells the whole app which to draw from its next start; nowhere to keep it, and the app keeps its default.
  void _tellApp(WispDraw? which) {
    askWispDraw(which, widget.kept);
    setState(() => _appWide = which);
  }

  /// What the surface wearing [which] is drawn through right now.
  String _wearing(BenchDraw which) {
    final context = _surfaces[which]!.currentContext;
    if (context == null) return 'nothing';
    RenderWispStrips? found;
    void visit(Element element) {
      if (found != null) return;
      final object = element.renderObject;
      if (object is RenderWispStrips) {
        found = object;
        return;
      }
      element.visitChildren(visit);
    }

    (context as Element).visitChildren(visit);
    return found == null ? 'nothing' : wearingOf(found!.strips);
  }

  void _scrollTo(ScrollController controller, double to) {
    if (!controller.hasClients) return;
    final position = controller.position;
    controller.jumpTo(to.clamp(position.minScrollExtent, position.maxScrollExtent));
  }

  /// A cell's driver (`driverFor`): what to do to the surface each frame, and how to leave it.
  ({void Function(int frame) drive, VoidCallback done}) _driverFor(BenchCondition condition, ScrollController controller) {
    switch (condition) {
      case BenchCondition.idle:
        return (drive: (_) {}, done: () {});
      case BenchCondition.repaint:
        // A mark in the page, toggled each frame: the smallest repaint the page can have.
        final top = controller.offset + 120;
        _mark.value = (top: top, frame: 0);
        return (drive: (frame) => _mark.value = (top: top, frame: frame), done: () => _mark.value = null);
      case BenchCondition.scroll:
        // Scrolling: three pixels a frame, back and forth, never back to the top, so the header band stays on.
        const floor = 200.0;
        var direction = 1;
        return (
          drive: (_) {
            if (!controller.hasClients) return;
            final ceiling = controller.position.maxScrollExtent - 3;
            if (controller.offset >= ceiling) {
              direction = -1;
            } else if (controller.offset <= floor) {
              direction = 1;
            }
            _scrollTo(controller, controller.offset + 3 * direction);
          },
          done: () {},
        );
    }
  }

  /// Waits out the edge's own pause after a scroll ([wispScrollIdle]) before a surface is taken off the screen. A
  /// [WispEdge] taken down while its smoke is still moving puts its band to rest as it goes, which tells the next
  /// surface's edge to draw again in the middle of the frame that is removing the first; rested, it has nothing to
  /// tell. The page had no such step, and with the default settle (600 ms) this adds a fifth of a second a surface.
  Future<void> _rest() async {
    await Future<void>.delayed(wispScrollIdle + const Duration(milliseconds: 40));
    await _frame();
  }

  /// Every drawing, every condition, one surface at a time, and the numbers as they come (`run`). The page without
  /// smoke goes first: if it cannot hold its frames the machine is busy, and the run stops there and says so rather
  /// than fill the table with numbers that are not about the smoke ([floorVerdict]).
  Future<void> _run(bool long) async {
    final cell = long ? widget.long : widget.quick;
    final done = <BenchRow>[];
    final media = MediaQuery.of(context);
    setState(() {
      _rows = const [];
      _where = whereItRuns(version: widget.version, platform: defaultTargetPlatform.name, engine: drawnBy(), width: media.size.width, height: media.size.height, ratio: media.devicePixelRatio);
      _beside = false;
      _running = '…';
    });
    await _rest();
    if (!mounted) return;
    for (final which in const [BenchDraw.none, BenchDraw.filter, BenchDraw.mask]) {
      if (which != BenchDraw.none && floorVerdict(done)?.ok == false) break;
      setState(() {
        _running = '${which.value}…';
        _draw = which;
      });
      await _settle(widget.settle);
      if (!mounted) return;
      final controller = _scrollers[which]!;
      if (!controller.hasClients) continue;
      _scrollTo(controller, scrolledTo);
      await _settle(widget.settle);
      if (!mounted) return;
      final wearing = _wearing(which);
      for (final condition in benchConditions) {
        setState(() => _running = '${which.value}: ${condition.label.toLowerCase()}…');
        await _settle(Duration.zero);
        if (!mounted) return;
        final driver = _driverFor(condition, controller);
        final reading = await runCell(driver.drive, cell, widget.clock);
        if (!mounted) return;
        driver.done();
        done.add(BenchRow(draw: which, condition: condition, wearing: wearing, reading: reading));
        setState(() => _rows = [...done]);
        _scrollTo(controller, scrolledTo);
        await _settle(widget.settle);
        if (!mounted) return;
      }
      await _rest();
      if (!mounted) return;
    }
    setState(() => _running = null);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.open) return const SizedBox.shrink();
    final t = context.tokens;
    final running = _running;
    final busy = running != null;
    final smokeOn = WispSettings.instance.wanted;
    final verdict = floorVerdict(_rows);
    final shown = _beside && !busy ? benchDraws : [_draw];
    final across = shown.length > 1 && MediaQuery.sizeOf(context).width >= 900;
    final gap3 = t.space(3), gap4 = t.space(4);
    final muted = t.color('glacier-text-muted');
    final lede = pageText(t, t.fontSize('sm'), color: muted, height: 1.5);
    final draw = _draw;
    final wisp = draw.wisp;
    _copied.text = reportText(_where, _rows);

    Widget ledeBox(Widget child) => Align(alignment: AlignmentDirectional.centerStart, child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 62 * _ch(lede)), child: child));

    // `.link`: a button that is a word in the sentence, underlined, and never broken across lines (a button is one
    // piece on the page; here its spaces are the kind a line does not break at).
    InlineSpan link(String words, TapGestureRecognizer tap) {
      final ink = t.color('glacier-accent-solid');
      return TextSpan(text: words.replaceAll(' ', '\u00A0'), recognizer: tap, semanticsLabel: words, style: TextStyle(color: ink, decoration: TextDecoration.underline, decorationColor: ink));
    }

    final action = pageText(t, t.lenOf('1rem'), weight: 'semibold');
    final words = [_beside ? 'One at a time' : 'Side by side', busy ? 'Running' : 'Run the bench', 'Run long'];
    final buttonsWide = [for (final word in words) _wide(word, action) + t.space(1) * 2].fold<double>(0, (a, b) => a + b) + t.space(2) * (words.length - 1);
    final buttons = Wrap(
      spacing: t.space(2),
      runSpacing: t.space(2),
      children: [
        RowAction(onPress: () => setState(() => _beside = !_beside), disabled: busy, child: Text(words[0])),
        RowAction(onPress: () => unawaited(_run(false)), disabled: busy, child: Text(words[1])),
        RowAction(onPress: () => unawaited(_run(true)), disabled: busy, child: Text(words[2])),
      ],
    );
    final choice = GlacierSegmentedControl(
      ariaLabel: 'Drawing',
      fullWidth: true,
      size: GlacierSegmentedSize.sm,
      options: [for (final option in benchDraws) GlacierSegmentedOption(value: option.value, label: Text(option.label))],
      value: draw.value,
      disabled: busy,
      onValueChange: (value) => setState(() => _draw = benchDraws.firstWhere((option) => option.value == value, orElse: () => BenchDraw.filter)),
    );

    final body = <Widget>[
      ledeBox(FractionLines.text(
        'The same page wearing the smoke as a filter, as a mask, or not at all. Scroll it by hand and read the frames in its '
        'header, or run the bench: at rest, a repaint a frame, and scrolling, one drawing at a time. The numbers are the '
        'page\'s, so measuring is done on one surface; side by side is for looking.',
        key: const ValueKey('bench-lede'),
        style: lede,
      )),
      if (!smokeOn) const SettingsCallout(child: Text('The smoke is switched off under Appearance › Motion, so every surface here wears nothing. Turn it on to compare.')),
      // `.controls`: the choices and the buttons, in one row that wraps on a phone. The choice takes what is left of
      // the row (`flex: 1 1 16rem`) and is never narrower than 16rem.
      LayoutBuilder(
        key: const ValueKey('bench-controls'),
        builder: (context, box) {
          final least = t.lenOf('16rem');
          if (box.maxWidth >= least + gap3 + buttonsWide + 0.5) {
            return Row(children: [Expanded(child: choice), SizedBox(width: gap3), buttons]);
          }
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [SizedBox(width: double.infinity, child: choice), SizedBox(height: gap3), buttons]);
        },
      ),
      // The whole app drawn one way from its next start: the edge's own override, so a page can be felt, not just read.
      ledeBox(FractionLines(
        key: const ValueKey('bench-app-wide'),
        style: lede,
        TextSpan(
          children: [
            TextSpan(text: _appWide != null ? 'The whole app draws the ${_appWide!.name} from its next start.' : 'The whole app draws the filter unless told otherwise.'),
            const TextSpan(text: ' '),
            if (wisp != null && _appWide != wisp) link('Use the ${draw.value} app-wide', _useTap),
            // `.link + .link { margin-inline-start: var(--glacier-space-3) }`
            if (wisp != null && _appWide != wisp && _appWide != null) WidgetSpan(child: SizedBox(width: gap3)),
            if (_appWide != null) link('Back to the default', _backTap),
          ],
        ),
      )),
      // `.surfaces`: one, or three across on a window wide enough for three real pages.
      if (across)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (index, which) in shown.indexed) ...[
              if (index > 0) SizedBox(width: gap3),
              Expanded(child: _Surface(key: _surfaces[which], draw: which, scroller: _scrollers[which]!, counting: !busy, mark: _mark)),
            ],
          ],
        )
      else
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (index, which) in shown.indexed) ...[
              if (index > 0) SizedBox(height: gap3),
              _Surface(key: _surfaces[which], draw: which, scroller: _scrollers[which]!, counting: !busy, mark: _mark),
            ],
          ],
        ),
      if (busy) Semantics(liveRegion: true, child: Text(running, key: const ValueKey('bench-status'), style: pageText(t, t.fontSize('sm'), color: muted))),
      if (_rows.isNotEmpty)
        Column(
          key: const ValueKey('bench-results'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_where, key: const ValueKey('bench-where'), style: pageText(t, t.lenOf('0.75rem'), color: muted, mono: true)),
            SizedBox(height: t.space(2)),
            if (verdict != null) ...[
              verdict.ok ? ledeBox(FractionLines.text(verdict.words, key: const ValueKey('bench-verdict'), style: lede)) : SettingsCallout(child: Text(verdict.words, key: const ValueKey('bench-verdict'))),
              SizedBox(height: t.space(2)),
            ],
            _BenchTable(rows: _rows),
            if (!busy) ...[
              SizedBox(height: t.space(2)),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _copied,
                  builder: (context, copied, _) => RowAction(
                    onPress: _copied.copy,
                    child: Text.rich(TextSpan(children: [
                      WidgetSpan(alignment: PlaceholderAlignment.middle, child: AppIcon(copied ? Lucide.check : Lucide.copy, size: 14)),
                      TextSpan(text: copied ? ' Copied' : ' Copy as text'),
                    ])),
                  ),
                ),
              ),
            ],
          ],
        ),
    ];

    final ground = t.color('glacier-bg');
    return OnBack(
      onBack: widget.onClose,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
          widget.onClose();
          return KeyEventResult.handled;
        },
        child: Semantics(
          scopesRoute: true,
          namesRoute: true,
          label: 'Smoke bench',
          explicitChildNodes: true,
          child: ColoredBox(
            key: const ValueKey('bench-over'),
            color: ground,
            child: DefaultTextStyle(
              style: pageText(t, t.lenOf('1rem'), color: t.color('glacier-text')),
              child: Padding(
                // `padding-block-start: var(--app-safe-top); padding-block-end: var(--app-safe-bottom)`
                padding: EdgeInsets.only(top: t.len('app-safe-top'), bottom: t.len('app-safe-bottom')),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BenchBar(
                      key: const ValueKey('bench-bar'),
                      title: 'Smoke bench',
                      onClose: widget.onClose,
                      padding: EdgeInsets.symmetric(vertical: gap3, horizontal: gap4),
                      rule: BorderSide(color: t.color('glacier-border-subtle')),
                      closeColor: muted,
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        key: const ValueKey('bench-body'),
                        padding: EdgeInsets.all(gap4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final (index, child) in body.indexed) ...[if (index > 0) SizedBox(height: gap4), child],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The bar both benches have (`.bar`, `.title`, `.close`): a name, whatever stands between, and a round X.
class BenchBar extends StatelessWidget {
  const BenchBar({super.key, required this.title, required this.onClose, required this.padding, required this.rule, required this.closeColor, this.pressedColor, this.between});

  final String title;
  final VoidCallback onClose;
  final EdgeInsetsGeometry padding;

  /// `border-block-end`.
  final BorderSide rule;

  /// The X at rest, and while pressed (the title's ink when not given).
  final Color closeColor;
  final Color? pressedColor;

  /// What stands between the title and the X (the scene bench's Play again).
  final Widget? between;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = DefaultTextStyle.of(context).style.color ?? t.color('glacier-text');
    final size = t.fontSize('md');
    final side = t.lenOf('2.25rem');
    return Container(
      padding: padding,
      decoration: BoxDecoration(border: Border(bottom: rule)),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              // `font-size: md; font-weight: semibold; letter-spacing: -0.01em`
              child: Text(title, key: const ValueKey('bench-title'), style: pageText(t, size, weight: 'semibold', color: ink, tracking: -0.01 * size)),
            ),
          ),
          SizedBox(width: t.space(3)),
          if (between != null) ...[between!, SizedBox(width: t.space(3))],
          GlacierPressable(
            key: const ValueKey('bench-close'),
            onPressed: onClose,
            semanticLabel: 'Close',
            builder: (context, state) {
              final pressed = state.pressed || state.hovered;
              return Container(
                width: side,
                height: side,
                alignment: Alignment.center,
                decoration: BoxDecoration(shape: BoxShape.circle, color: pressed ? ink.withValues(alpha: 0.08) : null),
                child: AppIcon(Lucide.x, size: 18, color: pressed ? (pressedColor ?? ink) : closeColor),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// A surface that wears one drawing of the smoke, and a counter of its frames in its header (`Surface`).
class _Surface extends StatefulWidget {
  const _Surface({super.key, required this.draw, required this.scroller, required this.counting, required this.mark});

  final BenchDraw draw;
  final ScrollController scroller;
  final bool counting;
  final ValueListenable<({double top, int frame})?> mark;

  @override
  State<_Surface> createState() => _SurfaceState();
}

class _SurfaceState extends State<_Surface> {
  final ValueNotifier<String> _counter = ValueNotifier('…');
  final FrameRing _ring = FrameRing(120);
  int? _frame;
  double _wrote = 0;

  @override
  void initState() {
    super.initState();
    if (widget.counting) _start();
  }

  @override
  void didUpdateWidget(_Surface old) {
    super.didUpdateWidget(old);
    if (old.counting != widget.counting || old.draw != widget.draw) {
      _stop();
      if (widget.counting) _start();
    }
  }

  @override
  void dispose() {
    _stop();
    _counter.dispose();
    super.dispose();
  }

  // The live counter: every frame marked, the header's words written twice a second (a write in the header, over
  // the page, is not a repaint of the page). Not while a run is on, whose own clock is the one that counts then.
  void _start() {
    _ring.reset();
    _wrote = 0;
    _frame = SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  void _stop() {
    final frame = _frame;
    if (frame != null) SchedulerBinding.instance.cancelFrameCallbackWithId(frame);
    _frame = null;
  }

  void _tick(Duration _) {
    final now = realClock.now();
    _ring.mark(now);
    if (now - _wrote > 500) {
      _wrote = now;
      final read = _ring.read();
      _counter.value = read.n > 0 ? '${ms(read.median)} · p90 ${ms(read.p90)} · worst ${ms(read.worst)}' : '…';
    }
    _frame = SchedulerBinding.instance.scheduleFrameCallback(_tick);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final draw = widget.draw;
    final ink = t.color('glacier-text');
    final head = t.lenOf('3rem');
    final side = t.space(5);
    final para = pageText(t, t.lenOf('0.9375rem'), color: ink, height: 1.6);
    final titleSize = t.lenOf('1.05rem');
    final title = pageText(t, titleSize, weight: 'semibold', color: ink, height: 1.6, tracking: -0.01 * titleSize);
    final blur = glassBlurOf(t);

    // `.prose`: sections of a heading and six paragraphs. Every heading is the first child of its section, so each
    // has the 0.5em top margin of `h3:first-child` and never the 1.6em: the first stands 0.5em from the top, and a
    // later one 1em under the paragraph before it, whose margin its own collapses into.
    final prose = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var section = 0; section < benchSections; section++) ...[
          SizedBox(height: section == 0 ? 0.5 * titleSize : para.fontSize!),
          FractionLines.text(section == 0 ? 'A page to scroll' : 'Section ${section + 1}', style: title),
          SizedBox(height: 0.5 * titleSize),
          for (final (index, words) in benchParagraphs.indexed) ...[
            if (index > 0) SizedBox(height: para.fontSize!),
            FractionLines.text(words, style: para),
          ],
        ],
        // The last paragraph's margin, which nothing follows to collapse it.
        SizedBox(height: para.fontSize!),
      ],
    );

    Widget page = SingleChildScrollView(
      controller: widget.scroller,
      child: Stack(
        children: [
          Padding(
            // `padding: 3rem var(--glacier-space-5) var(--glacier-space-5)`
            padding: EdgeInsets.fromLTRB(side, head, side, side),
            child: Center(child: ConstrainedBox(constraints: BoxConstraints(maxWidth: 60 * _ch(para)), child: prose)),
          ),
          // `.mark`: the mark the repaint cell toggles: small, in view, and part of the page (so its paint is the page's).
          ValueListenableBuilder(
            valueListenable: widget.mark,
            builder: (context, mark, _) {
              if (mark == null) return const SizedBox.shrink();
              final dot = t.lenOf('0.5rem');
              return Positioned(
                left: t.space(3),
                top: mark.top,
                child: Container(key: const ValueKey('bench-mark'), width: dot, height: dot, decoration: BoxDecoration(shape: BoxShape.circle, color: ink.withValues(alpha: mark.frame.isOdd ? 1 : 0.5))),
              );
            },
          ),
        ],
      ),
    );
    final wisp = draw.wisp;
    if (wisp != null) page = WispEdge(under: head, foot: true, draw: wisp, child: page);

    return Container(
      height: t.lenOf('24rem'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: t.color('glacier-bg'), borderRadius: BorderRadius.circular(t.radius('lg')), border: Border.all(color: t.color('glacier-border-subtle'))),
      child: Stack(
        children: [
          Positioned.fill(child: Semantics(label: '${draw.label} page', child: KeyedSubtree(key: const ValueKey('bench-page'), child: page))),
          // `.head`: the header the surface's page runs under, the app's own glass by its recipe.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: head,
            child: ClipRect(
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: Container(
                  key: const ValueKey('bench-head'),
                  color: t.colorOf('color-mix(in srgb, var(--glacier-bg) var(--app-glass-mix), transparent)'),
                  padding: EdgeInsets.symmetric(horizontal: t.space(4)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(draw.label, key: const ValueKey('bench-head-label'), style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: ink)),
                      // `.counter`: over the surface and not in it, so writing it does not repaint the page.
                      RepaintBoundary(
                        child: ValueListenableBuilder<String>(
                          valueListenable: _counter,
                          builder: (context, words, _) => Semantics(
                            label: '${draw.label} frame times',
                            child: Text(words, key: const ValueKey('bench-counter'), style: pageText(t, t.lenOf('0.75rem'), weight: 'medium', color: t.color('glacier-text-muted'), mono: true).copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()])),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `blur(18px)` of `--app-glass-blur`, as a sigma: a CSS blur's length is the standard deviation.
double glassBlurOf(Tokens t) {
  final value = t.raw('app-glass-blur') ?? '';
  final px = RegExp(r'blur\(\s*([\d.]+)px').firstMatch(value)?.group(1);
  return double.tryParse(px ?? '') ?? 18;
}

/// The run's table (`.table`): a column each for the drawing, the condition, what the surface wore and the four
/// numbers, sized as a browser sizes an automatic table and scrolled sideways where that is wider than the page.
class _BenchTable extends StatelessWidget {
  const _BenchTable({required this.rows});
  final List<BenchRow> rows;

  static const List<String> _heads = ['Drawing', 'Condition', 'Wearing', 'n', 'Median', 'p90', 'Worst'];

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('glacier-text'), muted = t.color('glacier-text-muted');
    final pad = t.space(2);
    final small = t.lenOf('0.75rem');
    final rule = BorderSide(color: t.color('glacier-border-subtle'));
    final cell = pageText(t, t.fontSize('sm'), color: ink).copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]);
    final number = pageText(t, t.fontSize('sm'), color: ink, mono: true).copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]);
    final wearing = pageText(t, small, color: muted, mono: true);
    // `A frame past 100ms is the one to look at`: a raw red, as the stylesheet has it.
    final slow = pageText(t, t.fontSize('sm'), weight: 'semibold', color: const Color(0xFFC0392B), mono: true).copyWith(fontFeatures: const [ui.FontFeature.tabularFigures()]);
    TextStyle head(bool num) => pageText(t, small, weight: 'semibold', color: muted, tracking: 0.04 * small, mono: num);
    TextStyle time(double value) => value > 100 ? slow : number;

    final table = <List<({String text, TextStyle style, bool breaks})>>[
      [for (final (index, name) in _heads.indexed) (text: name.toUpperCase(), style: head(index > 2), breaks: false)],
      for (final row in rows)
        [
          (text: row.draw.label, style: cell, breaks: false),
          (text: row.condition.label, style: cell, breaks: false),
          // `overflow-wrap: anywhere`: the column is never widened for it.
          (text: row.wearing, style: wearing, breaks: true),
          (text: '${row.reading.n}', style: number, breaks: false),
          (text: ms(row.reading.median), style: time(row.reading.median), breaks: false),
          (text: ms(row.reading.p90), style: time(row.reading.p90), breaks: false),
          (text: ms(row.reading.worst), style: time(row.reading.worst), breaks: false),
        ],
    ];
    // Each column's least width (its longest word) and most (its longest cell on one line), padding in.
    final least = List<double>.filled(_heads.length, 0), most = List<double>.filled(_heads.length, 0);
    for (final line in table) {
      for (final (column, it) in line.indexed) {
        // A hair over, so a word as wide as its column is not broken by the last bit of a float.
        most[column] = math.max(most[column], _wide(it.text, it.style) + pad * 2 + 0.02);
        if (it.breaks) continue;
        for (final word in it.text.split(' ')) {
          least[column] = math.max(least[column], _wide(word, it.style) + pad * 2 + 0.02);
        }
      }
    }

    return LayoutBuilder(
      builder: (context, box) {
        final room = box.maxWidth;
        final leastSum = least.fold<double>(0, (a, b) => a + b), mostSum = most.fold<double>(0, (a, b) => a + b);
        final List<double> widths;
        if (!room.isFinite || leastSum >= room) {
          widths = least;
        } else if (mostSum <= room) {
          // Room to spare (`inline-size: 100%`): shared out by what each column would take.
          widths = [for (final width in most) width * room / mostSum];
        } else {
          final spare = room - leastSum, wanted = mostSum - leastSum;
          widths = [for (var i = 0; i < least.length; i++) least[i] + spare * (most[i] - least[i]) / wanted];
        }
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Semantics(
            label: 'Bench results',
            child: Table(
              key: const ValueKey('bench-table'),
              defaultVerticalAlignment: TableCellVerticalAlignment.top,
              columnWidths: {for (final (index, width) in widths.indexed) index: FixedColumnWidth(width)},
              children: [
                for (final (index, line) in table.indexed)
                  TableRow(
                    key: ValueKey('bench-row-$index'),
                    decoration: BoxDecoration(border: Border(bottom: rule)),
                    children: [
                      for (final (column, it) in line.indexed)
                        Padding(
                          // `border-collapse: collapse`: a rule is shared by the rows it lies between, half each, so
                          // the headings carry half of the one under them and every other row half of two.
                          padding: EdgeInsets.fromLTRB(pad, pad + (index == 0 ? 0 : rule.width / 2), pad, pad + rule.width / 2),
                          child: Text(it.text, key: ValueKey('bench-cell-$index-$column'), style: it.style, textAlign: column > 2 ? TextAlign.end : TextAlign.start, softWrap: true),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
