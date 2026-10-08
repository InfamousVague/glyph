/// The instructions drawer (Matt: "add the instructions for the MCP to an instructions drawer we can open from the
/// mcp page in the app"): a card over the Claude plugin's page with the steps to connect, one way at a time -
/// hosted, or a file on your own computer - each command in a block with a Copy beside it, so a phone can hand them
/// to a computer without retyping. On a phone it rises from the bottom; on a wide window it floats in the middle.
/// A port of `src/app/plugins/claude/ClaudeGuide.tsx` with `claude.module.css`, rule for rule.
///
/// It closes on the X, a tap on the scrim, Escape, or the phone's back gesture, and every open lands on the way it
/// was opened for. Drawn over the app rather than in the pane, because the settings panes move as they change and
/// a fixed card inside a moving thing moves with it.
///
/// What differs:
/// - The page's portal into `document.body` is an [OverlayPortal] into the app's overlay; Escape and the back
///   gesture are one handler on the app's back stack (lib/core/back.dart), which hears both.
/// - `text-wrap: pretty` has no counterpart: a paragraph breaks where it fills.
/// - The hover grounds of the X and the Copy are drawn while a pointer is over them, as the page's `:hover`.
/// - A Copy's own `Copied` lasts as the kit's does (lib/settings/kit `Copied`, a second and a half).
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/art.dart';
import '../../core/back.dart';
import '../../settings/kit/settings_kit.dart' show Copied;
import '../../sheet/css.dart';
import 'steps.dart';

class ClaudeGuide extends StatefulWidget {
  const ClaudeGuide({super.key, required this.way, required this.handle, required this.onClose});

  /// Which way's steps to open on, or null for closed.
  final Way? way;

  /// The handle this device is signed in with, for the sign-in command; null when it is not.
  final String? handle;
  final VoidCallback onClose;

  static const Key cardKey = ValueKey<String>('claude-guide-card');
  static const Key scrimKey = ValueKey<String>('claude-guide-scrim');

  @override
  State<ClaudeGuide> createState() => _ClaudeGuideState();
}

class _ClaudeGuideState extends State<ClaudeGuide> with SingleTickerProviderStateMixin {
  // Told to show before it is attached, so the card is up from the frame the portal is built in; closed, there is
  // no portal at all.
  OverlayPortalController _portal = OverlayPortalController()..show();

  /// `scrimIn 180ms ease-out` and the card's `riseIn 220ms` (or `floatIn 180ms`), off one clock of 220.
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  late Way _shown = widget.way ?? Way.hosted;
  bool _started = false;

  bool get _open => widget.way != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_open) _arrive();
  }

  @override
  void didUpdateWidget(ClaudeGuide old) {
    super.didUpdateWidget(old);
    final way = widget.way;
    // Every open lands on the way it was asked for, however the last one was left.
    if (way != null && way != old.way) _shown = way;
    if (_open && old.way == null) _arrive();
    if (!_open) _started = false;
  }

  /// Starts the entrance. Nothing listens to the clock yet: the overlay is built after this.
  void _arrive() {
    if (_started) return;
    _started = true;
    // A portal of its own for each opening: a controller keeps its place in the overlay only while it is attached.
    _portal = OverlayPortalController()..show();
    // `@media (prefers-reduced-motion: reduce) { .scrim, .card { animation: none } }`
    if (context.tokens.reducedMotion) {
      _enter.value = 1;
    } else {
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OnBack(
        active: _open,
        onBack: widget.onClose,
        child: _open ? OverlayPortal(controller: _portal, overlayChildBuilder: _overlay, child: const SizedBox.shrink()) : const SizedBox.shrink(),
      );

  Widget _overlay(BuildContext overlayContext) {
    final t = context.tokens;
    final media = MediaQuery.of(overlayContext);
    // `@media (min-width: 720px)`: a wide window, where the card floats.
    final wide = media.size.width >= 720;
    final dvh = media.size.height - media.viewInsets.bottom;
    final line = snapBorder(overlayContext, 1);
    final radius = Radius.circular(t.radius('lg'));
    final edge = t.color('glacier-border-subtle');
    final all = guides(widget.handle);
    final guide = all.firstWhere((g) => g.way == _shown, orElse: () => all.first);

    // `max-block-size: calc(100dvh - var(--app-safe-top) - var(--glacier-space-8))`, or on a wide window
    // `min(46rem, calc(100dvh - var(--glacier-space-12)))`.
    final tallest = wide ? (dvh - t.space(12)).clamp(0.0, t.lenOf('46rem')) : (dvh - t.len('app-safe-top') - t.space(8)).clamp(0.0, double.infinity);
    final shape = wide ? BorderRadius.all(radius) : BorderRadius.vertical(top: radius);

    final Widget inside = DefaultTextStyle(
      style: pageText(t, 16, color: t.color('glacier-text')),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _head(t),
          _ways(t, all),
          Flexible(
            // `.scroll { min-block-size: 0; overflow-y: auto; padding: 0 var(--glacier-space-5) var(--glacier-space-6) }`
            child: SingleChildScrollView(
              key: ValueKey(_shown),
              padding: EdgeInsets.fromLTRB(t.space(5), 0, t.space(5), t.space(6)),
              child: _steps(t, guide, narrow: media.size.width <= 420),
            ),
          ),
        ],
      ),
    );

    final rise = CurvedAnimation(parent: _enter, curve: t.curve('glacier-ease-out'));
    final Widget card = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'Connecting Claude',
      child: ConstrainedBox(
        key: ClaudeGuide.cardKey,
        // `inline-size: 100%; max-inline-size: 34rem`
        constraints: BoxConstraints(maxWidth: t.lenOf('34rem'), maxHeight: tallest),
        child: CustomPaint(
          // `border: 1px solid var(--glacier-border-subtle); border-block-end: 0` over the card's ground, and the
          // shadow outside it: the card is see-through, and a shadow under it would be blurred into the glass.
          painter: _CardPainter(
            radius: radius.x,
            wide: wide,
            line: line,
            edge: edge,
            shadows: wide ? t.cssShadows('app-float-shadow').where((s) => !s.inset).map((s) => s.toBoxShadow()).toList() : const [BoxShadow(color: Color(0x47000000), offset: Offset(0, -12), blurRadius: 40)],
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: BackdropFilter(
              // `backdrop-filter: var(--app-float-blur)`
              filter: ui.ImageFilter.blur(sigmaX: blurSigma(t, 'app-float-blur'), sigmaY: blurSigma(t, 'app-float-blur')),
              child: ColoredBox(
                // `background: color-mix(in srgb, var(--glacier-bg) 92%, var(--glacier-text) 3%)`
                color: t.colorOf('color-mix(in srgb, var(--glacier-bg) 92%, var(--glacier-text) 3%)'),
                child: Padding(
                  // The border's own room, and on a phone `padding-block-end: var(--app-safe-bottom)`.
                  padding: EdgeInsets.fromLTRB(line, line, line, wide ? line : t.len('app-safe-bottom')),
                  child: inside,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // `.scrim { background: var(--app-scrim); animation: scrimIn 180ms ease-out }`, closed by a press, not a tap.
        Listener(
          key: ClaudeGuide.scrimKey,
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) => widget.onClose(),
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _enter, curve: const Interval(0, 180 / 220, curve: Curves.easeOut)),
            child: ColoredBox(color: t.color('app-scrim')),
          ),
        ),
        // `.over { display: flex; align-items: flex-end; justify-content: center }`; wide, in the middle with
        // `padding: var(--glacier-space-6)`.
        Padding(
          padding: wide ? EdgeInsets.all(t.space(6)) : EdgeInsets.zero,
          child: Align(
            alignment: wide ? Alignment.center : Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: rise,
              builder: (context, child) {
                final at = rise.value;
                // `riseIn { from { transform: translateY(24px); opacity: 0 } }`, or
                // `floatIn { from { opacity: 0; transform: translateY(-6px) scale(0.97) } }`.
                final moved = wide
                    ? Transform.translate(offset: Offset(0, -6 * (1 - at)), child: Transform.scale(scale: 0.97 + 0.03 * at, child: child))
                    : Transform.translate(offset: Offset(0, 24 * (1 - at)), child: child);
                return at >= 1 ? child! : Opacity(opacity: at, child: moved);
              },
              child: card,
            ),
          ),
        ),
      ],
    );
  }

  /// `.head`: the title and the X.
  Widget _head(Tokens t) {
    final lg = t.fontSize('lg');
    return Padding(
      // `padding: var(--glacier-space-4) var(--glacier-space-4) var(--glacier-space-2) var(--glacier-space-5)`
      padding: EdgeInsets.fromLTRB(t.space(5), t.space(4), t.space(4), t.space(2)),
      child: Row(
        spacing: t.space(3),
        children: [
          Expanded(
            child: Semantics(
              header: true,
              // `.title { font-size: lg; font-weight: bold; letter-spacing: var(--app-tracking-title) }`
              child: Text('Connecting Claude', style: pageText(t, lg, weight: 'bold', color: t.color('glacier-text'), tracking: t.len('app-tracking-title', em: lg))),
            ),
          ),
          GlacierPressable(
            onPressed: widget.onClose,
            semanticLabel: 'Close',
            builder: (context, state) {
              // `.close:hover, .close:focus-visible { background: var(--app-paper-2); color: var(--glacier-text) }`
              final lit = state.hovered || state.focused;
              return DecoratedBox(
                decoration: BoxDecoration(color: lit ? t.color('app-paper-2') : null, shape: BoxShape.circle),
                child: AppIcon(Lucide.x, size: 18, color: t.color(lit ? 'glacier-text' : 'glacier-text-muted')),
              );
            },
          ),
        ],
      ),
    );
  }

  /// `.ways`: the two-way switch, a word in the track, ink on paper when chosen, as the app's segments are.
  Widget _ways(Tokens t, List<Guide> all) {
    final sm = t.fontSize('sm');
    return Padding(
      // `margin: 0 var(--glacier-space-5) var(--glacier-space-3)`
      padding: EdgeInsets.fromLTRB(t.space(5), 0, t.space(5), t.space(3)),
      child: Semantics(
        container: true,
        label: 'Which way',
        child: Container(
          // `padding: 2px; border: 1px solid var(--glacier-border-subtle); border-radius: 999px; background: var(--app-paper-2)`
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(999), border: Border.all(color: t.color('glacier-border-subtle'))),
          // `display: grid; grid-template-columns: 1fr 1fr; gap: 2px`
          child: Row(
            spacing: 2,
            children: [
              for (final g in all)
                Expanded(
                  child: GlacierPressable(
                    onPressed: () => setState(() => _shown = g.way),
                    button: false,
                    selected: g.way == _shown,
                    semanticLabel: g.label,
                    builder: (context, state) {
                      final chosen = g.way == _shown;
                      return Container(
                        // `padding: 0.45rem 0.75rem; border-radius: 999px`
                        padding: EdgeInsets.symmetric(vertical: t.lenOf('0.45rem'), horizontal: t.lenOf('0.75rem')),
                        decoration: BoxDecoration(
                          color: chosen ? t.color('app-ink') : null,
                          borderRadius: BorderRadius.circular(999),
                          // `.way:focus-visible { outline: 2px solid var(--app-ink); outline-offset: 2px }`, inside the cell here.
                          border: state.focused ? Border.all(color: t.color('app-ink'), width: 2, strokeAlign: BorderSide.strokeAlignOutside) : null,
                        ),
                        alignment: Alignment.center,
                        child: ExcludeSemantics(
                          child: Text(
                            g.label,
                            maxLines: 1,
                            overflow: TextOverflow.clip,
                            softWrap: false,
                            style: pageText(t, sm, weight: 'semibold', color: chosen ? t.color('app-paper') : t.color('glacier-text-muted')),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _steps(Tokens t, Guide guide, {required bool narrow}) {
    final md = t.fontSize('md');
    final sm = t.fontSize('sm');
    final muted = t.color('glacier-text-muted');
    final dot = t.lenOf('1.5rem');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // `.lead { margin: 0 0 var(--glacier-space-4); font-size: md; line-height: 1.5; color: muted }`
        Padding(
          padding: EdgeInsets.only(bottom: t.space(4)),
          child: _lines(Text(guide.lead, style: pageText(t, md, color: muted, height: 1.5))),
        ),
        // `.steps { display: grid; gap: var(--glacier-space-5) }`
        for (final (i, step) in guide.steps.indexed)
          Padding(
            key: ValueKey('claude-step-${step.title}'),
            padding: EdgeInsets.only(top: i == 0 ? 0 : t.space(5)),
            // `.step { display: grid; grid-template-columns: auto minmax(0, 1fr); gap: var(--glacier-space-3) }`
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: t.space(3),
              children: [
                // `.number`: an ink dot with the figure in paper, 1.5rem across, `margin-block-start: 0.05rem`.
                ExcludeSemantics(
                  child: Container(
                    key: ValueKey('claude-step-number-${i + 1}'),
                    width: dot,
                    height: dot,
                    margin: EdgeInsets.only(top: t.lenOf('0.05rem')),
                    decoration: BoxDecoration(color: t.color('app-ink'), shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: Text('${i + 1}', style: pageText(t, sm, weight: 'semibold', color: t.color('app-paper')).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                  ),
                ),
                Expanded(
                  // `.stepBody { display: grid; gap: var(--glacier-space-2); min-inline-size: 0 }`
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    spacing: t.space(2),
                    children: [
                      Semantics(
                        header: true,
                        // `.stepTitle { font-size: md; font-weight: semibold; line-height: 1.5rem }`
                        child: Text(step.title, style: pageText(t, md, weight: 'semibold', color: t.color('glacier-text'), height: t.lenOf('1.5rem') / md)),
                      ),
                      // `.words { font-size: sm; line-height: 1.5; color: muted }`
                      _lines(Text(step.body, style: pageText(t, sm, color: muted, height: 1.5))),
                      for (final text in step.snippets) _Snippet(key: ValueKey(text), text: text, narrow: narrow),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// [text] in lines as tall as the page's ([cssLine]), where the text engine's own are whole pixels.
Widget _lines(Text text) => CssLines(line: cssLine(text.style!), child: text);

/// The card's hairline and its shadow: the border on three sides on a phone, where the card stands on the bottom
/// edge, and all round on a wide window.
class _CardPainter extends CustomPainter {
  const _CardPainter({required this.radius, required this.wide, required this.line, required this.edge, required this.shadows});
  final double radius;
  final bool wide;
  final double line;
  final Color edge;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(radius);
    final box = Offset.zero & size;
    final outer = wide ? RRect.fromRectAndRadius(box, r) : RRect.fromRectAndCorners(box, topLeft: r, topRight: r);
    // Outside the box only.
    canvas.save();
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(box.inflate(200))
      ..addRRect(outer));
    for (final shadow in shadows) {
      canvas.drawRRect(outer.shift(shadow.offset).inflate(shadow.spreadRadius), shadow.toPaint());
    }
    canvas.restore();
    // The hairline, inside the box's edge; on a phone its foot is below the card, where nothing is drawn.
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = line
      ..color = edge;
    final half = line / 2;
    canvas.save();
    canvas.clipRect(box);
    final lined = wide ? outer.deflate(half) : RRect.fromRectAndCorners(Rect.fromLTRB(half, half, size.width - half, size.height + radius), topLeft: Radius.circular(radius - half), topRight: Radius.circular(radius - half));
    canvas.drawRRect(lined, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CardPainter old) => old.radius != radius || old.wide != wide || old.line != line || old.edge != edge || old.shadows != shadows;
}

/// The height of one line of [style] on the page, for a rule that sets `line-height` to a multiple: the size times
/// the multiple, as the page's engine lays it out. Chromium counts in 64ths of a pixel: the line's height is cut
/// down to one, the face's ascent and descent are each rounded to one, and what is left over is put half above and
/// half below, each half cut down again. So a line is the multiple's height or a 64th under it, and a paragraph of
/// eight lines is an eighth of a pixel shorter than the sum says, which a list of steps adds up.
double cssLine(TextStyle style) {
  final size = style.fontSize ?? 16;
  final multiple = style.height ?? 1;
  // The face's own ascent and descent at this size, read off a line set solid with its leading shared evenly.
  final painter = TextPainter(text: TextSpan(text: 'x', style: style.copyWith(height: 1, leadingDistribution: TextLeadingDistribution.even)), textDirection: TextDirection.ltr)..layout();
  final metrics = painter.computeLineMetrics();
  painter.dispose();
  if (metrics.isEmpty) return size * multiple;
  final ascent = metrics.first.unscaledAscent;
  final descent = size - ascent - 2 * (metrics.first.ascent - ascent);
  final a = (ascent * 64).round(), d = (descent * 64).round();
  final leading = (size * multiple * 64 + 1e-6).floor() - a - d;
  return (a + d + 2 * (leading / 2).floor()) / 64;
}

/// How many letters of the mono face stand across [width]: every one is as wide as the next.
int _columns(TextStyle style, double width) {
  final painter = TextPainter(text: TextSpan(text: '0' * 20, style: style), textDirection: TextDirection.ltr)..layout();
  final advance = painter.width / 20;
  painter.dispose();
  return advance <= 0 || !width.isFinite ? 1 << 20 : ((width + 0.01) / advance).floor().clamp(1, 1 << 20);
}

final RegExp _letter = RegExp(r'[A-Za-z]');
final RegExp _wordLetter = RegExp(r'[A-Za-z0-9]');

/// [text] in lines of at most [columns] letters, broken where the page breaks a `.code` (`white-space: pre-wrap;
/// overflow-wrap: anywhere`, as Chromium does it): after a space, after a hyphen inside a word, and, for a word
/// that is longer than a whole line, wherever the line is full. Spaces are kept, and those at a line's end hang
/// past it. An address is not broken at its slashes, which is where Flutter's own breaker would break it and so
/// why this is done by hand: the commands are for copying by eye as well as by the button.
List<String> wrapCode(String text, int columns) {
  final out = <String>[];
  for (final hard in text.split('\n')) {
    // The pieces a line may end after: a run of letters up to and with a hyphen inside a word, or to the end of
    // the spaces after it.
    final pieces = <String>[];
    var from = 0;
    for (var i = 0; i < hard.length; i++) {
      final here = hard[i];
      final next = i + 1 < hard.length ? hard[i + 1] : '';
      final afterSpace = here == ' ' && next != ' ' && next.isNotEmpty;
      final afterHyphen = here == '-' && i > 0 && _wordLetter.hasMatch(hard[i - 1]) && _letter.hasMatch(next);
      if (afterSpace || afterHyphen) {
        pieces.add(hard.substring(from, i + 1));
        from = i + 1;
      }
    }
    pieces.add(hard.substring(from));

    var line = '';
    for (var piece in pieces) {
      // What must fit: the piece without the spaces at its end, which hang.
      var needs = piece.trimRight().length;
      if (line.isNotEmpty && line.length + needs > columns) {
        out.add(line);
        line = '';
      }
      // Longer than a line by itself: broken wherever the line is full.
      while (line.isEmpty && needs > columns) {
        out.add(piece.substring(0, columns));
        piece = piece.substring(columns);
        needs = piece.trimRight().length;
      }
      line += piece;
    }
    out.add(line);
  }
  return out;
}

/// One thing to copy: the words, and a Copy that says Copied for a moment (`.snippet`, `.code`, `.copy`).
class _Snippet extends StatefulWidget {
  const _Snippet({super.key, required this.text, required this.narrow});
  final String text;

  /// `@media (max-width: 420px)`: the Copy is its icon alone (the label still says it).
  final bool narrow;

  @override
  State<_Snippet> createState() => _SnippetState();
}

class _SnippetState extends State<_Snippet> {
  late final Copied _copied = Copied(widget.text)..addListener(_redraw);

  void _redraw() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(_Snippet old) {
    super.didUpdateWidget(old);
    _copied.text = widget.text;
  }

  @override
  void dispose() {
    _copied
      ..removeListener(_redraw)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final sm = t.fontSize('sm');
    final copied = _copied.value;
    return Container(
      // `padding: space-2 space-2 space-2 space-3; border: 1px solid border-subtle; border-radius: md; background: paper-2`
      padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(2), t.space(2)),
      decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.radius('md')), border: Border.all(color: t.color('glacier-border-subtle'))),
      // `display: flex; align-items: flex-start; gap: var(--glacier-space-2)`
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: t.space(2),
        children: [
          Expanded(
            child: Padding(
              // `.code { padding-block: 0.3rem; font-family: mono; font-size: sm; line-height: 1.45; white-space: pre-wrap; overflow-wrap: anywhere }`
              padding: EdgeInsets.symmetric(vertical: t.lenOf('0.3rem')),
              child: LayoutBuilder(
                builder: (context, box) {
                  final style = pageText(t, sm, mono: true, color: t.color('glacier-text'), height: 1.45);
                  // Broken here, where a page would break it (see [wrapCode]), and set as its lines stand; said
                  // as it is written, with no breaks.
                  final lines = wrapCode(widget.text, _columns(style, box.maxWidth));
                  return CssLines(
                    line: cssLine(style),
                    child: Align(alignment: AlignmentDirectional.centerStart, child: Text(lines.join('\n'), softWrap: false, semanticsLabel: widget.text, style: style)),
                  );
                },
              ),
            ),
          ),
          GlacierPressable(
            onPressed: _copied.copy,
            semanticLabel: copied ? 'Copied' : 'Copy',
            builder: (context, state) {
              // `.copy[data-copied] { color: muted }`; `.copy:hover, .copy:focus-visible { background: var(--app-paper-3) }`
              final color = t.color(copied ? 'glacier-text-muted' : 'glacier-text');
              final icon = AppIcon(copied ? Lucide.check : Lucide.copy, size: 16, color: color);
              return Container(
                padding: widget.narrow ? EdgeInsets.all(t.lenOf('0.4rem')) : EdgeInsets.symmetric(vertical: t.lenOf('0.35rem'), horizontal: t.lenOf('0.6rem')),
                decoration: BoxDecoration(color: state.hovered || state.focused ? t.color('app-paper-3') : null, borderRadius: BorderRadius.circular(999)),
                child: widget.narrow
                    ? icon
                    : Row(
                        mainAxisSize: MainAxisSize.min,
                        // `gap: 0.35em`
                        spacing: 0.35 * sm,
                        children: [icon, ExcludeSemantics(child: Text(copied ? 'Copied' : 'Copy', style: pageText(t, sm, weight: 'semibold', color: color)))],
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
