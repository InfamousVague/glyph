import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'blur_letter.dart';
import 'wisp.dart';

/// How long a letter takes to set, in ms (art/WispText.tsx `IN_MS`), the most that is added to it at random, and how
/// much faster than the asked-for pace the letters come.
const double wispInMs = 346;
const double wispInJitterMs = 100;
const double wispSpeed = 16 / 9;

/// Untyping is quicker than typing, and letters leave this far apart.
const double wispOutMs = 345;
const double wispOutGapMs = 26;

/// No more letters than this bend at once; past it the oldest simply sets.
const int wispPoolMax = 48;

/// A letter's bend and blur as it starts to arrive: `feDisplacementMap scale` and `feGaussianBlur stdDeviation` on
/// the page, and here the two numbers its blur is worked out from (lib/art/blur_letter.dart `letterBlur`).
const double wispLetterBend = 34;
const double wispLetterSoft = 5;

/// The noise every letter was bent by (the editor's arriving words still name it in their filters), and how long a
/// change takes to fade in with reduced motion.
const Offset wispLetterFrequency = Offset(0.018, 0.06);
const Duration wispFadeIn = Duration(milliseconds: 220);

/// The seed of the pool's [slot]th filter: each settling letter has a filter of its own, and each filter its own
/// cloud.
int wispSlotSeed(int slot) => slot * 7 + 1;

/// One letter of the text as drawn: waiting unseen, arriving or leaving through its own blur, or set.
class WispLetter {
  WispLetter(this.ch, {this.hidden = false});
  final String ch;
  bool hidden;
  WispRun? run;
}

/// A letter's passage through the blur: [scale] and [blur] are the wisp's bend and blur at this moment, which the
/// letter's softness is worked out from.
class WispRun {
  WispRun({required this.slot, required this.at, required this.dur, required this.arriving, required this.scale, required this.blur});
  final int slot;
  double at;
  final double dur;
  final bool arriving;
  double scale, blur;

  /// How far along the letter is, 0 to 1.
  double progress = 0;
}

class _Phase {
  _Phase({required this.start, required this.steps, required this.length, required this.then, required this.arriving, required this.fire});
  double start;
  final List<WispStep> steps;
  int next = 0;

  /// When the last letter has settled, in ms from [start].
  final double length;
  final VoidCallback then;
  final bool arriving;
  final void Function(WispStep step) fire;
}

/// The letters and their motion, apart from the widget: `WispEngine` of art/WispText.tsx. Given the time by whoever
/// drives it, so a test can.
class WispEngine {
  WispEngine({required double pace, required this.reduced, required this.onSettled, required this.onLayout, required this.onFrame, required this.onWake, required this.now, math.Random? random})
      : _random = random ?? math.Random() {
    setPace(pace);
  }

  final math.Random _random;

  /// The phone asks for reduced motion: the text is shown at rest and a change is a short fade.
  final bool reduced;
  void Function(String text) onSettled;

  /// The letters were laid out again: a new text, or the one before a swap.
  final VoidCallback onLayout;

  /// Something moved: draw again.
  final VoidCallback onFrame;

  /// Frames are wanted until [busy] is false.
  final VoidCallback onWake;

  /// The time in ms, on a clock that only ever goes forward.
  final double Function() now;

  /// Told as each arriving letter starts to appear, with the letter: not for leaving letters, nor with reduced
  /// motion.
  void Function(String letter) onLetter = (_) {};

  late WispWait _wait;
  List<WispToken> tokens = const [];
  List<List<WispLetter>> letters = const [];
  String? _text;
  _Phase? _phase;
  double _lastTick = 0;
  final List<bool> _pool = [];
  final Map<WispLetter, WispRun> _active = {};

  /// Counts the times a change was shown by fading the whole text in (reduced motion).
  int fades = 0;

  String? get text => _text;
  bool get busy => _phase != null || _active.isNotEmpty;
  int get poolSize => _pool.length;
  Iterable<WispLetter> get bending => _active.keys;

  void setPace(double pace) => _wait = cadence(pace * wispSpeed, _random.nextDouble);

  /// Shows [text]: typed in the first time (unless [still]), swapped word by word after.
  void set(String text, bool still) {
    if (text == _text && _phase == null) return;
    final from = _interrupt();
    if (reduced) {
      _layout(tokenize(text), const {});
      // A change with reduced motion: the new text fades in, whole.
      if (from != null) fades += 1;
      _text = text;
      onSettled(text);
      return;
    }
    if (from == null && still) {
      _layout(tokenize(text), const {});
      _text = text;
      onSettled(text);
      return;
    }
    final plan = planSwap(from ?? '', text, _wait, wispOutGapMs);
    void arrive() {
      _layout(plan.to, plan.diff.arriving.toSet());
      _text = text;
      _begin(true, plan.arrive, runLength(plan.arrive, wispInMs + wispInJitterMs), _show, () {
        _phase = null;
        onSettled(text);
      });
    }

    if (plan.out.isNotEmpty) {
      _begin(false, plan.out, runLength(plan.out, wispOutMs), _hide, arrive);
    } else {
      arrive();
    }
  }

  /// Lands the rest at once: the letters still in motion set where they are, the ones yet to come simply appear (or
  /// go), and the settled callback fires as it would have at the end. For a text whose tail is out of sight.
  void finish() {
    // A leaving phase hands on to an arriving one through `then`; both are landed.
    for (var guard = 0; _phase != null && guard < 3; guard++) {
      final phase = _phase!;
      _phase = null;
      for (final entry in _active.entries.toList()) {
        _settle(entry.key, entry.value);
      }
      for (var i = phase.next; i < phase.steps.length; i++) {
        final letter = _letter(phase.steps[i]);
        if (letter == null) continue;
        letter.hidden = !phase.arriving;
      }
      phase.then();
    }
    onFrame();
  }

  /// Lets go of everything it holds: the letters in motion.
  void dispose() {
    _phase = null;
    for (final letter in _active.keys) {
      letter.run = null;
    }
    _active.clear();
  }

  /// Stops whatever is moving and lands on the text its letters belong to; answers that text (null before the first).
  String? _interrupt() {
    if (_phase == null) return _text;
    _phase = null;
    for (final entry in _active.entries.toList()) {
      _settle(entry.key, entry.value);
    }
    if (_text != null) _layout(tokenize(_text!), const {});
    return _text;
  }

  /// Words of letters, gaps as text: every letter of a [hidden] word waits, unseen, holding its place.
  void _layout(List<WispToken> next, Set<int> hidden) {
    tokens = next;
    letters = [
      for (var index = 0; index < next.length; index++)
        next[index].kind == WispTokenKind.gap ? <WispLetter>[] : [for (final ch in lettersOf(next[index].text)) WispLetter(ch, hidden: hidden.contains(index))],
    ];
    onLayout();
  }

  void _begin(bool arriving, List<WispStep> steps, double length, void Function(WispStep) fire, VoidCallback then) {
    _phase = _Phase(start: now(), steps: steps, length: length, then: then, arriving: arriving, fire: fire);
    _lastTick = 0;
    tick();
  }

  /// One frame: fire the letters whose moment has come, move every settling letter on, and stop when nothing is
  /// left.
  void tick() {
    final at = now();
    // Frames stop while the app is hidden or the phone is busy. Coming back, the clock is moved on by the gap, so
    // the letters carry on from where they were instead of every overdue one arriving in the same frame.
    final gap = _lastTick != 0 ? at - _lastTick : 0.0;
    if (gap > 200) {
      _phase?.start += gap;
      for (final run in _active.values) {
        run.at += gap;
      }
    }
    _lastTick = at;
    final phase = _phase;
    if (phase != null) {
      final elapsed = at - phase.start;
      while (phase.next < phase.steps.length && phase.steps[phase.next].at <= elapsed) {
        phase.fire(phase.steps[phase.next]);
        phase.next += 1;
      }
    }
    for (final entry in _active.entries.toList()) {
      final run = entry.value;
      final t = math.min(1.0, (at - run.at) / run.dur);
      run.progress = t;
      // Arriving: the bend is over by three quarters of the way and the blur a little later, so the last frames
      // near zero, where a half pixel of displacement shimmers on thin strokes, are not drawn. Leaving: the same
      // curve backwards, the letter thinning as it bends.
      final p = run.arriving ? t : 1 - t;
      final bend = math.max(0.0, 1 - p / 0.72);
      final soft = math.max(0.0, 1 - p / 0.9);
      run.scale = wispLetterBend * bend * bend;
      run.blur = wispLetterSoft * soft * soft;
      if (t >= 1) _settle(entry.key, run);
    }
    onFrame();
    if (phase != null && identical(phase, _phase) && phase.next >= phase.steps.length && at - phase.start >= phase.length && _active.isEmpty) {
      _phase = null;
      phase.then();
      return;
    }
    if (busy) onWake();
  }

  int _slot() {
    final free = _pool.indexOf(false);
    if (free >= 0) return free;
    if (_pool.length >= wispPoolMax) {
      // Faster than anyone types: the oldest letter simply sets now, cleanly.
      MapEntry<WispLetter, WispRun>? oldest;
      for (final entry in _active.entries) {
        if (oldest == null || entry.value.at < oldest.value.at) oldest = entry;
      }
      if (oldest != null) {
        _settle(oldest.key, oldest.value);
        return oldest.value.slot;
      }
    }
    _pool.add(false);
    return _pool.length - 1;
  }

  WispLetter? _letter(WispStep step) {
    if (step.token < 0 || step.token >= letters.length) return null;
    final word = letters[step.token];
    return step.char >= 0 && step.char < word.length ? word[step.char] : null;
  }

  /// A letter arrives: seen, fading in, soft until it sets.
  void _show(WispStep step) {
    final letter = _letter(step);
    if (letter == null) return;
    letter.hidden = false;
    final dur = wispInMs + _random.nextDouble() * wispInJitterMs;
    _bend(letter, arriving: true, dur: dur, scale: wispLetterBend, blur: wispLetterSoft);
    onLetter(letter.ch);
  }

  /// A letter leaves: thinning as it goes soft, and gone at the end.
  void _hide(WispStep step) {
    final letter = _letter(step);
    if (letter == null) return;
    _bend(letter, arriving: false, dur: wispOutMs, scale: 0, blur: 0);
  }

  void _bend(WispLetter letter, {required bool arriving, required double dur, required double scale, required double blur}) {
    final old = letter.run;
    if (old != null) _settle(letter, old);
    final slot = _slot();
    _pool[slot] = true;
    final run = WispRun(slot: slot, at: now(), dur: dur, arriving: arriving, scale: scale, blur: blur);
    letter.run = run;
    _active[letter] = run;
    if (_phase == null) onWake();
  }

  /// Crisp before the blur comes off, so taking it away changes nothing on screen.
  void _settle(WispLetter letter, WispRun run) {
    letter.run = null;
    if (!run.arriving) letter.hidden = true;
    _pool[run.slot] = false;
    _active.remove(letter);
  }
}

/// Words that arrive out of a blur, a letter at a time, and swap whole words when the text changes
/// (art/WispText.tsx, with art/WispText.module.css for the fade and the lift).
///
/// Give it a [text]; the first text types itself in at a hand's pace (or is simply there, with [still]), and every
/// later text is worked out word by word (wisp.dart): the words that stay put stay, the words that go are untyped
/// from their last letter, quicker and going soft as they thin out, and then the new words type in. Each settling
/// letter comes in soft and faint and sharpens as it sets (lib/art/blur_letter.dart), where it came out of smoke,
/// bent by its own cloud of noise (Matt, 2026-10-24: "replace the smoke effect with a gradient blur on all places
/// that use the wisp smoke", on every platform). With reduced motion the text is shown at rest and a change is a
/// short fade.
///
/// The arguments are the component's: [pace] in letters a second, [still] for a first text shown at rest,
/// [onSettled] called once the text on screen has fully settled. Its `as` and `className` are [style] here (take it
/// from `tokens.textAt(...)`), with [textAlign] and [maxLines] for what the page's stylesheet would have said.
/// A text that runs past [maxLines] lands its unseen tail at once, as a clamped title does on the page.
///
/// What differs from the page: words are laid out by this widget, letter by letter, as the page's are (every letter
/// there is a box of its own, so neither kerns across letters); a word too long for its line is not broken. Where
/// the page bends a letter through an SVG filter, here it is blurred in a layer of its own.
///
/// Cost: a layer and a blur for each settling letter, and nothing for a letter once it has set.
class WispText extends StatefulWidget {
  const WispText(this.text, {super.key, this.pace = 14, this.still = false, this.style, this.textAlign = TextAlign.start, this.maxLines, this.onSettled, this.random});

  final String text;

  /// Letters a second when typing in.
  final double pace;

  /// The first text is shown at rest instead of typed in.
  final bool still;
  final TextStyle? style;
  final TextAlign textAlign;
  final int? maxLines;

  /// Called once the text on screen has fully settled, with that text.
  final ValueChanged<String>? onSettled;

  /// Where the hand's unevenness comes from: a test gives its own.
  final math.Random? random;

  @override
  State<WispText> createState() => WispTextState();
}

class WispTextState extends State<WispText> with TickerProviderStateMixin {
  WispEngine? _engine;
  late final Ticker _ticker = createTicker(_onTick);
  late final AnimationController _fade = AnimationController(vsync: this, duration: wispFadeIn, value: 1);
  final ValueNotifier<int> _frame = ValueNotifier(0);
  double _base = 0;
  double _elapsed = 0;
  int _layouts = 0;
  int _fades = 0;
  bool _overflowed = false;
  double? _finishAt;
  final GlobalKey _box = GlobalKey();

  /// The engine, for a test to read what each letter is doing.
  @visibleForTesting
  WispEngine get engine => _engine!;

  /// Whether the text is still arriving or leaving: the page's `data-wisp-typing`.
  bool get typing => _engine?.busy ?? false;

  double get _now => _base + _elapsed;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_engine != null) return;
    // Asked once, as the page asks when the component mounts.
    _engine = WispEngine(
      pace: widget.pace,
      reduced: MediaQuery.of(context).disableAnimations,
      onSettled: (text) => widget.onSettled?.call(text),
      onLayout: () {
        _layouts += 1;
        if (mounted && SchedulerBinding.instance.schedulerPhase != SchedulerPhase.persistentCallbacks) setState(() {});
      },
      onFrame: () => _frame.value += 1,
      onWake: _wake,
      now: () => _now,
      random: widget.random,
    )..onLetter = _onLetter;
    _engine!.set(widget.text, widget.still);
    _fades = _engine!.fades;
  }

  @override
  void didUpdateWidget(WispText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pace != widget.pace) _engine!.setPace(widget.pace);
    if (oldWidget.text != widget.text || oldWidget.still != widget.still) {
      _overflowed = false;
      _finishAt = null;
      _engine!.set(widget.text, widget.still);
      if (_engine!.fades != _fades) {
        _fades = _engine!.fades;
        _fade.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _fade.dispose();
    _engine?.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _wake() {
    if (!_ticker.isActive && mounted) {
      _base = _now;
      _elapsed = 0;
      _ticker.start();
    }
  }

  void _onTick(Duration elapsed) {
    _elapsed = elapsed.inMicroseconds / 1000;
    final engine = _engine!;
    if (_finishAt != null && _now >= _finishAt!) {
      _finishAt = null;
      engine.finish();
    }
    if (engine.busy) engine.tick();
    if (!engine.busy && _finishAt == null) {
      _base = _now;
      _elapsed = 0;
      _ticker.stop();
    }
  }

  /// Typing past the bottom of a box that clips (a title clamped to two lines): once the last letter that shows has
  /// set, the unseen tail lands at once rather than typing on for nobody.
  void _onLetter(String letter) {
    if (_overflowed || _finishAt != null) return;
    final box = _box.currentContext?.findRenderObject();
    if (box is RenderWispText && box.hasSize && box.clipped) {
      _overflowed = true;
      _finishAt = _now + wispInMs + wispInJitterMs;
    }
  }

  @override
  Widget build(BuildContext context) {
    final engine = _engine!;
    final style = DefaultTextStyle.of(context).style.merge(widget.style);
    return FadeTransition(
      opacity: CurvedAnimation(parent: _fade, curve: Curves.easeOut),
      child: _WispTextBox(
        key: _box,
        engine: engine,
        layouts: _layouts,
        text: widget.text,
        style: style,
        textAlign: widget.textAlign,
        textDirection: Directionality.maybeOf(context) ?? TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: widget.maxLines,
        repaint: _frame,
      ),
    );
  }
}

class _WispTextBox extends LeafRenderObjectWidget {
  const _WispTextBox({
    super.key,
    required this.engine,
    required this.layouts,
    required this.text,
    required this.style,
    required this.textAlign,
    required this.textDirection,
    required this.textScaler,
    required this.maxLines,
    required this.repaint,
  });

  final WispEngine engine;
  final int layouts;
  final String text;
  final TextStyle style;
  final TextAlign textAlign;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final int? maxLines;
  final Listenable repaint;

  @override
  RenderWispText createRenderObject(BuildContext context) =>
      RenderWispText(engine: engine, layouts: layouts, label: text, style: style, textAlign: textAlign, textDirection: textDirection, textScaler: textScaler, maxLines: maxLines, repaint: repaint);

  @override
  void updateRenderObject(BuildContext context, RenderWispText renderObject) {
    renderObject
      ..layouts = layouts
      ..label = text
      ..style = style
      ..textAlign = textAlign
      ..textDirection = textDirection
      ..textScaler = textScaler
      ..maxLines = maxLines;
  }
}

class _Placed {
  _Placed(this.letter, this.painter, this.offset);
  final WispLetter letter;
  final TextPainter painter;
  Offset offset;
}

/// The letters laid out as the page lays them: each word a box that never breaks inside, each letter a box inside
/// it, the gaps plain spaces that a line may break at, and a line break where the text has one.
class RenderWispText extends RenderBox {
  RenderWispText({
    required this.engine,
    required int layouts,
    required String label,
    required TextStyle style,
    required TextAlign textAlign,
    required TextDirection textDirection,
    required TextScaler textScaler,
    required int? maxLines,
    required this.repaint,
  })  : _layouts = layouts,
        _label = label,
        _style = style,
        _textAlign = textAlign,
        _textDirection = textDirection,
        _textScaler = textScaler,
        _maxLines = maxLines;

  final WispEngine engine;
  final Listenable repaint;

  int _layouts;
  set layouts(int value) {
    if (value == _layouts) return;
    _layouts = value;
    markNeedsLayout();
  }

  String _label;
  set label(String value) {
    if (value == _label) return;
    _label = value;
    markNeedsSemanticsUpdate();
  }

  TextStyle _style;
  set style(TextStyle value) {
    if (value == _style) return;
    _style = value;
    _forget();
  }

  TextAlign _textAlign;
  set textAlign(TextAlign value) {
    if (value == _textAlign) return;
    _textAlign = value;
    markNeedsLayout();
  }

  TextDirection _textDirection;
  set textDirection(TextDirection value) {
    if (value == _textDirection) return;
    _textDirection = value;
    _forget();
  }

  TextScaler _textScaler;
  set textScaler(TextScaler value) {
    if (value == _textScaler) return;
    _textScaler = value;
    _forget();
  }

  int? _maxLines;
  set maxLines(int? value) {
    if (value == _maxLines) return;
    _maxLines = value;
    markNeedsLayout();
  }

  final Map<String, TextPainter> _painters = {};
  List<_Placed> _placed = const [];
  double _lineHeight = 0;
  int _lines = 0;

  /// Whether the text runs past what the box shows: more lines than [maxLines], or taller than its room.
  bool get clipped => _clipped;
  bool _clipped = false;

  /// Where each letter was put, in reading order: for a test.
  @visibleForTesting
  List<Rect> get debugLetterRects => [for (final placed in _placed) placed.offset & placed.painter.size];

  void _forget() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
    markNeedsLayout();
  }

  TextPainter _painter(String text) {
    return _painters.putIfAbsent(text, () => TextPainter(text: TextSpan(text: text, style: _style), textDirection: _textDirection, textScaler: _textScaler)..layout());
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    repaint.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    repaint.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    for (final painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
    super.dispose();
  }

  /// Lays the words out in lines no wider than [maxWidth]; answers the text's own width and its lines.
  ({double width, int lines, List<_Placed> placed}) _flow(double maxWidth) {
    final placed = <_Placed>[];
    final lineOf = <int>[];
    final widths = <double>[0];
    var x = 0.0;
    var line = 0;
    void newLine() {
      line += 1;
      x = 0;
      widths.add(0);
    }

    for (var index = 0; index < engine.tokens.length; index++) {
      final token = engine.tokens[index];
      if (token.kind == WispTokenKind.gap) {
        // `white-space: pre-wrap`: spaces are kept and hang at a line's end, and a line feed breaks the line.
        for (final rune in token.text.runes) {
          final ch = String.fromCharCode(rune);
          if (ch == '\n') {
            newLine();
          } else {
            x += _painter(ch == '\t' ? ' ' : ch).width;
          }
        }
        continue;
      }
      final word = engine.letters[index];
      final painters = [for (final letter in word) _painter(letter.ch)];
      final wide = painters.fold<double>(0, (sum, painter) => sum + painter.width);
      if (x > 0 && x + wide > maxWidth + 0.01) newLine();
      for (var i = 0; i < word.length; i++) {
        placed.add(_Placed(word[i], painters[i], Offset(x, 0)));
        lineOf.add(line);
        x += painters[i].width;
      }
      widths[line] = x;
    }
    final width = widths.fold<double>(0, math.max);
    final box = math.min(width, maxWidth);
    final lineHeight = _painter(' ').preferredLineHeight;
    for (var i = 0; i < placed.length; i++) {
      final free = box - widths[lineOf[i]];
      final shift = switch (_textAlign) {
        TextAlign.center => free / 2,
        TextAlign.right => free,
        TextAlign.end => _textDirection == TextDirection.ltr ? free : 0.0,
        TextAlign.start => _textDirection == TextDirection.ltr ? 0.0 : free,
        TextAlign.left || TextAlign.justify => 0.0,
      };
      placed[i].offset = Offset(placed[i].offset.dx + shift, lineOf[i] * lineHeight);
    }
    return (width: box, lines: engine.tokens.isEmpty ? 1 : line + 1, placed: placed);
  }

  @override
  double computeMinIntrinsicWidth(double height) {
    var widest = 0.0;
    for (final word in engine.letters) {
      widest = math.max(widest, word.fold<double>(0, (sum, letter) => sum + _painter(letter.ch).width));
    }
    return widest;
  }

  @override
  double computeMaxIntrinsicWidth(double height) => _flow(double.infinity).width;

  @override
  double computeMinIntrinsicHeight(double width) => computeMaxIntrinsicHeight(width);

  @override
  double computeMaxIntrinsicHeight(double width) {
    final flow = _flow(width);
    final lines = _maxLines == null ? flow.lines : math.min(flow.lines, _maxLines!);
    return lines * _painter(' ').preferredLineHeight;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final flow = _flow(constraints.maxWidth);
    final lines = _maxLines == null ? flow.lines : math.min(flow.lines, _maxLines!);
    return constraints.constrain(Size(flow.width, lines * _painter(' ').preferredLineHeight));
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => _painter(' ').computeDistanceToActualBaseline(baseline);

  @override
  void performLayout() {
    final flow = _flow(constraints.maxWidth);
    _placed = flow.placed;
    _lineHeight = _painter(' ').preferredLineHeight;
    _lines = _maxLines == null ? flow.lines : math.min(flow.lines, _maxLines!);
    size = constraints.constrain(Size(flow.width, _lines * _lineHeight));
    _clipped = flow.lines > _lines || flow.lines * _lineHeight > size.height + 1;
  }

  @override
  bool hitTestSelf(Offset position) => true;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    // The whole text is read in one piece; the drawn letters are nothing a screen reader should spell out.
    config
      ..isSemanticBoundary = true
      ..label = _label
      ..textDirection = _textDirection;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final shows = _clipped ? size.height + 0.5 : double.infinity;
    for (final placed in _placed) {
      final letter = placed.letter;
      if (letter.hidden || placed.offset.dy + _lineHeight > shows) continue;
      final at = offset + placed.offset;
      final run = letter.run;
      if (run == null) {
        placed.painter.paint(canvas, at);
        continue;
      }
      _paintRun(canvas, at, placed, run);
    }
  }

  /// A letter on its way: the fade and the lift of art/WispText.module.css's keyframes, and its blur while there is
  /// any bend or blur left on its clock.
  void _paintRun(Canvas canvas, Offset at, _Placed placed, WispRun run) {
    final t = run.progress.clamp(0.0, 1.0);
    final double opacity, lift;
    if (run.arriving) {
      // `wispIn`, eased out between each pair of its frames.
      opacity = t < 0.3 ? 0.8 * Curves.easeOut.transform(t / 0.3) : 0.8 + 0.2 * Curves.easeOut.transform((t - 0.3) / 0.7);
      lift = 4 * (1 - Curves.easeOut.transform(t));
    } else {
      // `wispOut`, eased in.
      opacity = t < 0.55 ? 1 - 0.6 * Curves.easeIn.transform(t / 0.55) : 0.4 * (1 - Curves.easeIn.transform((t - 0.55) / 0.45));
      lift = -5 * Curves.easeIn.transform(t);
    }
    if (opacity <= 0) return;
    canvas.save();
    canvas.translate(at.dx, at.dy + lift);
    paintBlurLetter(canvas, box: placed.painter.size, sigma: letterBlur(run.scale, run.blur), opacity: opacity, draw: (canvas) => placed.painter.paint(canvas, Offset.zero));
    canvas.restore();
  }
}
