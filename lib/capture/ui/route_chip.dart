/// The chip just above the recorder's buttons: where the words are going while a command is heard, and what came of
/// it. A port of `src/app/capture/RouteChip.tsx` and the `.route*` rules of CaptureScreen.module.css.
///
/// Outlined with dots while a note is being named or a command worked out, filled with a tick once something has
/// landed, dashed when a name matched no note, filled with an Undo when the last thing said was taken back. What it
/// says is the live reader's and the recorder's (capture/take_host.dart `RouteView`); which look it takes, and how
/// long a settled one stays, are chip.dart. It says and shows only: it opens no microphone.
///
/// What differs:
/// - The chip centres itself and carries its own bottom margin, where the page's column did the centring
///   (`align-self: center`): give it the column's width.
/// - The look (`data-phase`) is a key on the chip's box, `ValueKey('route-chip-<phase>')`, for a test to find.
/// - With reduced motion neither entrance plays. On the page the filled chip's pop still did, its rule being more
///   specific than the one that stills the chip, which was never meant.
/// - Words too long for the chip are cut at the edge of its padding rather than at its border, and the dashed
///   outline's dashes are Chromium's for a line this thin (three widths on, two off), drawn here by hand.
/// - Undo keeps the chip's paper colour while it is pressed.
library;

import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app/widgets.dart';
import '../../sheet/css.dart' show snapBorder;
import '../chip.dart';
import '../take_host.dart';
import 'capture_cards.dart' show EnterFrom, TickPainter;

/// The chip for [route], with [itemWords] - what of a command is being heard - where the chip shows it, and [onUndo]
/// for a take-back that can still be put back: the recorder withholds it once Done is writing.
class RouteChip extends StatelessWidget {
  const RouteChip({super.key, required this.route, required this.itemWords, this.onUndo});

  final RouteView route;
  final String itemWords;
  final VoidCallback? onUndo;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final phase = chipPhase(route);
    final md = t.fontSize('md');
    // .route[data-phase='moved'], .route[data-phase='tookBack'] {
    //   border-color: var(--app-ink);
    //   background: var(--app-ink);
    //   color: var(--app-paper);
    //   animation: chip-pop var(--app-pop) both;
    // }
    final filled = phase == 'moved' || phase == 'tookBack';
    final ink = filled ? t.color('app-paper') : t.color('app-ink-2');
    final words = t.textAt(md, color: ink);
    // .route strong { color: var(--app-ink); font-weight: var(--glacier-font-weight-bold); }
    // .route[data-phase='moved'] strong, .route[data-phase='tookBack'] strong { color: inherit; }
    final strong = t.textAt(md, weight: 'bold', color: filled ? ink : t.color('app-ink'));

    Widget text(List<InlineSpan> spans, {bool cut = false}) => Flexible(
          child: Text.rich(TextSpan(children: spans), style: words, maxLines: 1, softWrap: false, overflow: cut ? TextOverflow.ellipsis : TextOverflow.clip),
        );
    Widget plain(String said) => text([TextSpan(text: said)]);
    Widget bold(String said) => text([TextSpan(text: said, style: strong)]);
    final dots = _Dots(em: md, color: ink);
    // .routeTick {
    //   inline-size: 0.35em;
    //   block-size: 0.7em;
    //   margin-inline: 0.15em 0.1em;
    //   border-inline-end: 2px solid currentColor;
    //   border-block-end: 2px solid currentColor;
    //   transform: rotate(45deg) translate(-0.1em, -0.1em);
    // }
    final tick = Padding(
      padding: EdgeInsets.only(left: 0.15 * md, right: 0.1 * md),
      child: CustomPaint(size: Size(0.35 * md, 0.7 * md), painter: TickPainter(color: ink, dx: -0.1 * md, dy: -0.1 * md)),
    );

    // Each run of words and each element is its own item on the chip's line, a gap apart, as in a flex box.
    final List<Widget> items;
    switch (route) {
      case RouteViewTookBack(:final said, :final outcome):
        items = [
          // .routeText { min-inline-size: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
          text(
            switch (outcome) {
              TookBackGone() => [TextSpan(text: 'Took back “$said”')],
              TookBackSent(:final sent) => [TextSpan(text: 'Sent “$said” to '), TextSpan(text: sent, style: strong)],
              TookBackPlaced(:final placed) => [TextSpan(text: 'Put “$said” $placed')],
              TookBackReplaced(:final replaced) => [TextSpan(text: 'Replaced “$said” with “$replaced”')],
              TookBackChanged(:final changed) => [TextSpan(text: 'Changed “$said” to “$changed”')],
            },
            cut: true,
          ),
          if (onUndo != null)
            // .routeUndo { flex: none; margin-inline-start: var(--glacier-space-2); color: var(--app-paper); }
            Padding(
              padding: EdgeInsets.only(left: t.space(2)),
              child: AppWord(
                onPressed: onUndo,
                // `.app-word { font: inherit; font-weight: medium }`: the chip's own size, in the chip's paper.
                child: Text('Undo', style: t.textAt(md, weight: 'medium', color: t.color('app-paper'))),
              ),
            ),
        ];
      case RouteViewHearing(:final name):
        items = [dots, plain('Looking for “$name”')];
      case RouteViewWaiting(:final title):
        items = itemWords.isNotEmpty ? [bold('$title:'), plain(itemWords)] : [dots, plain('Say the note for'), bold(title)];
      case RouteViewCommand(words: final heard):
        final said = [heard, partialCommand(itemWords)].where((part) => part.isNotEmpty).join(' ');
        items = [
          dots,
          text([TextSpan(text: 'Hey Ghost', style: strong), TextSpan(text: said.isNotEmpty ? ': $said' : ', listening for a command')]),
        ];
      case RouteViewSaid(text: final said):
        items = [plain(said)];
      case RouteViewDone(text: final said):
        items = [tick, plain(said)];
      case RouteViewAdded(:final title, :final added):
        items = [tick, plain(added.length == 1 ? 'Added to' : '${added.length} added to'), bold(title)];
      case RouteViewMoved(:final title, :final spot):
        items = [
          tick,
          if (title == 'New note')
            plain('New note')
          else
            // Its own box, so a long title ends in an ellipsis inside the chip rather than at its edge.
            text([const TextSpan(text: 'Now on '), TextSpan(text: title, style: strong), if (spot != null && spot.isNotEmpty) TextSpan(text: ' · $spot')], cut: true),
        ];
      case RouteViewMissed(:final title):
        items = [plain('No note called “$title”, so it stays here')];
    }

    // .route {
    //   flex: none;
    //   align-self: center;
    //   display: inline-flex;
    //   align-items: center;
    //   gap: var(--glacier-space-2);
    //   max-inline-size: 100%;
    //   margin: 0 0 var(--glacier-space-3);
    //   padding: var(--glacier-space-2) var(--glacier-space-4);
    //   border: var(--app-line) solid var(--app-ink-3);
    //   border-radius: var(--glacier-radius-full);
    //   font-size: var(--glacier-font-size-md);
    //   color: var(--app-ink-2);
    //   white-space: nowrap;
    //   overflow: hidden;
    //   text-overflow: ellipsis;
    //   animation: chip-in 240ms cubic-bezier(0.3, 1.3, 0.5, 1) both;
    // }
    // .route[data-phase='missed'] { border-style: dashed; }
    final line = snapBorder(context, t.len('app-line'));
    final edge = filled ? t.color('app-ink') : t.color('app-ink-3');
    final dashed = phase == 'missed';
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < items.length; i += 1) ...[if (i > 0) SizedBox(width: t.space(2)), items[i]],
      ],
    );
    final Widget box = dashed
        ? CustomPaint(
            key: ValueKey('route-chip-$phase'),
            foregroundPainter: DashedPillPainter(color: edge, width: line),
            child: Padding(padding: EdgeInsets.symmetric(vertical: t.space(2) + line, horizontal: t.space(4) + line), child: row),
          )
        : Container(
            key: ValueKey('route-chip-$phase'),
            padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(4)),
            decoration: BoxDecoration(
              color: filled ? t.color('app-ink') : null,
              border: Border.all(color: edge, width: line),
              borderRadius: BorderRadius.circular(t.radius('full')),
            ),
            child: row,
          );

    final pop = t.transition('app-pop');
    final Widget entered = filled
        ? _ChipPop(key: const ValueKey('chip-pop'), duration: pop.duration, curve: pop.curve, child: box)
        // @keyframes chip-in { from { opacity: 0; transform: translateY(6px) scale(0.96); } }
        : EnterFrom(key: const ValueKey('chip-in'), duration: const Duration(milliseconds: 240), curve: const Cubic(0.3, 1.3, 0.5, 1), dy: 6, scale: 0.96, child: box);

    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: Center(heightFactor: 1, child: Semantics(container: true, liveRegion: true, child: entered)),
    );
  }
}

/// `@keyframes chip-pop { 0% { transform: scale(0.9); } 60% { transform: scale(1.04); } }`, eased between each pair
/// of keyframes as CSS eases a keyframed animation. Still with reduced motion.
class _ChipPop extends StatefulWidget {
  const _ChipPop({super.key, required this.duration, required this.curve, required this.child});

  final Duration duration;
  final Curve curve;
  final Widget child;

  @override
  State<_ChipPop> createState() => _ChipPopState();
}

class _ChipPopState extends State<_ChipPop> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(vsync: this, duration: widget.duration);
  bool _begun = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_begun) return;
    _begun = true;
    if (context.tokens.reducedMotion) {
      _run.value = 1;
    } else {
      _run.forward();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _run,
        child: widget.child,
        builder: (context, child) {
          final at = _run.value;
          if (at >= 1) return child!;
          final scale = at < 0.6 ? 0.9 + 0.14 * widget.curve.transform(at / 0.6) : 1.04 - 0.04 * widget.curve.transform((at - 0.6) / 0.4);
          return Transform.scale(scale: scale, child: child);
        },
      );
}

/// Three dots breathing while the name is still being said (`.routeDots`): one, two, three, round and round.
class _Dots extends StatefulWidget {
  const _Dots({required this.em, required this.color});

  final double em;
  final Color color;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> with SingleTickerProviderStateMixin {
  // animation: dots 900ms steps(3, jump-none) infinite;
  late final AnimationController _run = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  bool _begun = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_begun) return;
    _begun = true;
    // @media (prefers-reduced-motion: reduce) { .routeDots { animation: none; } }
    if (!context.tokens.reducedMotion) _run.repeat();
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // .routeDots {
    //   inline-size: 1.4em;
    //   block-size: 0.35em;
    //   background: radial-gradient(circle, currentColor 45%, transparent 50%) 0 50% / 0.45em 0.35em repeat-x;
    //   animation: dots 900ms steps(3, jump-none) infinite;
    //   opacity: 0.8;
    // }
    // @keyframes dots { from { clip-path: inset(0 66% 0 0); } to { clip-path: inset(0 0 0 0); } }
    return ExcludeSemantics(
      child: Opacity(
        opacity: 0.8,
        child: CustomPaint(size: Size(1.4 * widget.em, 0.35 * widget.em), painter: _DotsPainter(em: widget.em, color: widget.color, run: _run, still: !_run.isAnimating)),
      ),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.em, required this.color, required this.run, required this.still}) : super(repaint: run);

  final double em;
  final Color color;
  final Animation<double> run;
  final bool still;

  @override
  void paint(Canvas canvas, Size size) {
    // Three steps with none jumped: the clip stands at 66%, 33% and nothing, a third of the time each.
    final shown = still ? 3 : (run.value * 3).floor().clamp(0, 2) + 1;
    final right = switch (shown) { 1 => 0.66, 2 => 0.33, _ => 0.0 };
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(0, 0, size.width * (1 - right), size.height));
    final tile = Size(0.45 * em, 0.35 * em);
    // `circle` with no size is farthest-corner: the tile's half diagonal.
    final radius = Offset(tile.width / 2, tile.height / 2).distance;
    for (var i = 0; i * tile.width < size.width; i += 1) {
      final rect = Rect.fromLTWH(i * tile.width, 0, tile.width, tile.height);
      final gradient = RadialGradient(colors: [color, color, color.withValues(alpha: 0)], stops: const [0, 0.45, 0.5]);
      canvas.drawRect(rect.intersect(Offset.zero & size), Paint()..shader = gradient.createShader(Rect.fromCircle(center: rect.center, radius: radius)));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.em != em || old.color != color || old.still != still;
}

/// A dashed outline round a pill: `border: 1.5px dashed` on a box with `border-radius: full`.
class DashedPillPainter extends CustomPainter {
  const DashedPillPainter({required this.color, required this.width});

  final Color color;
  final double width;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(width / 2);
    final outline = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(rect.shortestSide / 2)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..color = color;
    for (final PathMetric metric in outline.computeMetrics()) {
      // Whole dashes round the outline: the gap gives, as a browser's does.
      final on = width * 3;
      final count = (metric.length / (on + width * 2)).round().clamp(1, 100000);
      final step = metric.length / count;
      for (var i = 0; i < count; i += 1) {
        canvas.drawPath(metric.extractPath(i * step, i * step + on), paint);
      }
    }
  }

  @override
  bool shouldRepaint(DashedPillPainter old) => old.color != color || old.width != width;
}
