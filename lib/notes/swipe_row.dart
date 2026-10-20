/// A row you can swipe: right for one action, left for up to two, each armed at a detent you can feel. A port of
/// `src/app/notes/SwipeRow.tsx` and SwipeRow.module.css (docs/DESIGN.md §151); its pure half is `core/swipe.dart`.
///
/// A detent is a distance, as a fraction of the row's width. Crossing one on the way out ticks the motor and fills
/// the gap behind the row with the action's colour, its picture doing a small move; crossing back ticks more softly
/// and empties it. Letting go past a detent does that action; letting go short of the first does nothing and the row
/// springs home. Every detent is shown as well as felt: a ring round the picture fills as the swipe nears it, and
/// the gap turns ink, or red for delete, once it is armed. And a detent can be felt coming: light ticks while the
/// swipe closes on it, speeding up as it nears (`core/detent_feel.dart`).
///
/// What differs:
/// - Which way a touch is going is decided by Flutter's own gesture arena (a sideways drag past the touch slop wins
///   it from the page's scroll), where the page asked for 10px of travel, more across than down by a fifth. Once it
///   is the row's, the row is where the finger is from where it went down, as on the page. The tap that would follow
///   a swipe never comes, since the swipe won the touch.
/// - The page's two ticks are the kit's kinds here: the soft tick of a detent coming is `selection`, as is backing
///   out through one; arriving is `medium`, or `heavy` for delete.
/// - The gap's `@container` queries (a row too short to stack the picture over its word) are worked out from the
///   gap's own size as it is laid out.
/// - The pictures are the home page's icon helper's (`home/home_icons.dart`), until the app's own are ported.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/detent_feel.dart';
import '../core/swipe.dart';
import '../home/home_icons.dart';
import '../home/home_text.dart';

export '../core/swipe.dart' show SwipeAction, SwipeIcon, SwipeTone;

enum _Settling { home, awayLeft, awayRight }

/// A row that swipes to its actions (`src/app/notes/SwipeRow.tsx`). Flutter's gesture arena decides which way a
/// touch is going, where the page asked for 10px of travel more across than down; the rest is as the library doc
/// above says.
class SwipeRow extends StatefulWidget {
  const SwipeRow({super.key, this.start = const [], this.end = const [], required this.onAction, this.radius = 0, this.compact = false, this.also = const {}, required this.child});

  /// Revealed by swiping right, nearest detent first.
  final List<SwipeAction> start;

  /// Revealed by swiping left, nearest detent first.
  final List<SwipeAction> end;
  final ValueChanged<String> onAction;

  /// The frame's own corners: a card's (the web's `className`, NoteCard.module.css `.swipe`).
  final double radius;

  /// A row one line tall: the picture and its word side by side.
  final bool compact;

  /// More of the row's own actions for a screen reader, beside its swipes': Move to… (lib/notes/folder_drag.dart),
  /// which on the same node from inside the row would put the swipes' out.
  final Map<CustomSemanticsAction, VoidCallback> also;
  final Widget child;

  @override
  State<SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<SwipeRow> {
  double _dx = 0;
  _Settling? _settling;
  SwipeAction? _armed;

  // One touch's swipe: where it went down, how wide the row was, and how near a detent it has been felt.
  double _downX = 0;
  double _width = 1;
  String? _armedId;
  Approaching _approaching = Approaching();
  bool _mine = false;
  bool _cancelled = false;
  Timer? _acting;

  @override
  void dispose() {
    _acting?.cancel();
    super.dispose();
  }

  void _onStart(DragStartDetails details) {
    // Android's back gesture owns a band at each edge of the screen: a touch that begins there is the system's.
    final touch = details.kind == null || details.kind == PointerDeviceKind.touch;
    final screen = MediaQuery.sizeOf(context).width;
    _mine = !(touch && startsInGestureEdge(details.globalPosition.dx, screen));
    if (!_mine) return;
    _cancelled = false;
    _downX = details.globalPosition.dx;
    _width = math.max(1, context.size?.width ?? 1);
    _armedId = null;
    _approaching = Approaching();
    setState(() => _settling = null);
  }

  void _onUpdate(DragUpdateDetails details) {
    if (!_mine) return;
    final moveX = details.globalPosition.dx - _downX;
    final actions = moveX > 0 ? widget.start : widget.end;
    final shown = actions.isEmpty ? 0.0 : followFinger(moveX, actions.last.detent, _width);
    final distance = shown.abs() / _width;
    final fire = HapticsProvider.of(context);
    final at = (details.sourceTimeStamp ?? Duration.zero).inMicroseconds / 1000;
    if (tickNow(_approaching, [for (final a in actions) a.detent], distance, at)) fire(HapticKind.selection);

    final next = armedAt(actions, distance);
    if (next?.id != _armedId) {
      final deeper = next != null && (_armedId == null || actions.indexWhere((a) => a.id == next.id) > actions.indexWhere((a) => a.id == _armedId));
      // Out through a detent: a firm click, heavier for a destructive one. Back through it: the lightest tick.
      fire(deeper ? (next.tone == SwipeTone.danger ? HapticKind.heavy : HapticKind.medium) : HapticKind.selection);
      _armedId = next?.id;
    }
    setState(() {
      _dx = shown;
      _armed = next;
    });
  }

  void _finish({required bool cancelled}) {
    if (!_mine) return;
    _mine = false;
    // A touch the system took back (a call coming in, the back gesture winning) does nothing: Flutter ends a drag
    // the same way for a let-go and for a cancel, so the cancel is heard from the pointer itself, just before.
    cancelled = cancelled || _cancelled;
    final actions = _dx > 0 ? widget.start : widget.end;
    final action = cancelled ? null : armedAt(actions, _dx.abs() / _width);
    if (action == null) {
      setState(() {
        _armed = null;
        _settling = _Settling.home;
        _dx = 0;
      });
      return;
    }
    if (action.removes) {
      setState(() {
        _armed = null;
        _settling = _dx > 0 ? _Settling.awayRight : _Settling.awayLeft;
        _dx = _dx.sign * _width * 1.1;
      });
      _acting = Timer(const Duration(milliseconds: 180), () => widget.onAction(action.id));
    } else {
      setState(() {
        _armed = null;
        _settling = _Settling.home;
        _dx = 0;
      });
      widget.onAction(action.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final side = _dx > 0 ? widget.start : (_dx < 0 ? widget.end : const <SwipeAction>[]);
    // What shows behind the row: the action the swipe has armed, or the first one it is heading for.
    final current = _armed ?? side.firstOrNull;
    final at = current == null ? -1 : side.indexWhere((a) => a.id == current.id);
    final next = at >= 0 && at + 1 < side.length ? side[at + 1] : null;
    final distance = _dx.abs() / _width;
    final progress = current == null ? 0.0 : math.min(1.0, distance / current.detent);
    final settle = t.reducedMotion ? const Duration(milliseconds: 1) : t.duration('glacier-duration-normal');

    final row = TweenAnimationBuilder<double>(
      // No transition while the finger drives it: the row has to be under the thumb, not chasing it.
      tween: Tween<double>(end: _dx),
      duration: _settling == null ? Duration.zero : settle,
      curve: t.curve('glacier-ease-out'),
      builder: (context, dx, child) => Transform.translate(offset: Offset(dx, 0), child: child),
      // `.row { background: var(--glacier-bg) }`: the row covers the gap it has not yet left.
      child: ColoredBox(color: t.color('glacier-bg'), child: widget.child),
    );

    Widget frame = Stack(
      children: [
        if (_dx != 0)
          PositionedDirectional(
            top: 0,
            bottom: 0,
            start: _dx > 0 ? 0 : null,
            end: _dx > 0 ? null : 0,
            width: _dx.abs(),
            child: ExcludeSemantics(
              child: _Behind(action: current, next: next, armed: _armed != null, tone: _armed?.tone, progress: progress, start: _dx > 0, compact: widget.compact),
            ),
          ),
        row,
      ],
    );
    frame = widget.radius > 0 ? ClipRRect(borderRadius: BorderRadius.circular(widget.radius), child: frame) : ClipRect(child: frame);
    if (widget.start.isEmpty && widget.end.isEmpty) return frame;
    return Listener(
      onPointerCancel: (_) => _cancelled = true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // From where the finger went down, so the row is under it and does not lag by the slop.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: _onStart,
        onHorizontalDragUpdate: _onUpdate,
        onHorizontalDragEnd: (_) => _finish(cancelled: false),
        onHorizontalDragCancel: () => _finish(cancelled: true),
        excludeFromSemantics: true,
        child: Semantics(
          customSemanticsActions: {
            for (final action in [...widget.start, ...widget.end]) CustomSemanticsAction(label: action.label): () => widget.onAction(action.id),
            ...widget.also,
          },
          child: frame,
        ),
      ),
    );
  }
}

/// The gap the row leaves as it slides is the action: its picture in a ring that fills as the swipe nears the
/// detent, and its word. Armed, the ring closes, the picture does its small move, and the gap fills: ink for pin and
/// archive, red for delete.
class _Behind extends StatelessWidget {
  const _Behind({required this.action, required this.next, required this.armed, required this.tone, required this.progress, required this.start, required this.compact});

  final SwipeAction? action;
  final SwipeAction? next;
  final bool armed;
  final SwipeTone? tone;
  final double progress;

  /// The gap is at the row's start (it was swiped right).
  final bool start;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final (ground, ink) = switch (tone) {
      SwipeTone.accent || SwipeTone.neutral => (t.color('app-ink'), t.color('app-paper')),
      SwipeTone.danger => (t.color('glacier-red-9'), t.colorOf('oklch(0.99 0 0)')),
      null => (t.color('app-wash'), t.color('glacier-text-muted')),
    };
    final current = action;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: ground),
      duration: const Duration(milliseconds: 160),
      curve: t.curve('glacier-ease-out'),
      builder: (context, color, child) => ColoredBox(color: color ?? ground, child: child),
      child: ClipRect(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(2), horizontal: t.space(3)),
          child: current == null
              ? const SizedBox.expand()
              : LayoutBuilder(
                  builder: (context, box) {
                    // `@container swipe-gap (height < 5.25rem)`: a container's query measures its content box, the
                    // gap inside its padding, so a pinned line's Unpin has no word until the gap is 7rem and the
                    // padding wide.
                    final height = box.maxHeight, width = box.maxWidth;
                    final short = height < t.lenOf('5.25rem');
                    return _Action(
                      key: ValueKey(current.id),
                      action: current,
                      next: armed ? next : null,
                      armed: armed,
                      ink: ink,
                      progress: progress,
                      start: start,
                      compact: compact,
                      short: short,
                      showLabel: !short || width >= t.lenOf('7rem'),
                      showMore: !short || width >= t.lenOf('9.5rem'),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

class _Action extends StatefulWidget {
  const _Action({
    super.key,
    required this.action,
    required this.next,
    required this.armed,
    required this.ink,
    required this.progress,
    required this.start,
    required this.compact,
    required this.short,
    required this.showLabel,
    required this.showMore,
  });

  final SwipeAction action;
  final SwipeAction? next;
  final bool armed;
  final Color ink;
  final double progress;
  final bool start;
  final bool compact;
  final bool short;
  final bool showLabel;
  final bool showMore;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> with TickerProviderStateMixin {
  /// `@keyframes action-in`: 140ms from `{ opacity: 0; transform: scale(0.85) }`.
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 140));

  /// The armed picture's small move, and the badge's pop with it: the longest of them is 380ms.
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (context.tokens.reducedMotion) {
      _in.value = 1;
      _move.value = 1;
    } else {
      _in.forward();
      if (widget.armed) _move.forward();
    }
  }

  @override
  void didUpdateWidget(_Action oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.armed && !oldWidget.armed && !context.tokens.reducedMotion) _move.forward(from: 0);
  }

  @override
  void dispose() {
    _in.dispose();
    _move.dispose();
    super.dispose();
  }

  /// A keyframed value at [t] of a move [ms] long, eased by [curve].
  double _at(int ms, Curve curve) => curve.transform((_move.value * 380 / ms).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final action = widget.action;
    final rem = t.lenOf('1rem');
    final badge = (widget.compact ? 2.0 : (widget.short ? 2.25 : 2.75)) * rem;
    final glyph = (widget.compact ? 1.05 : (widget.short ? 1.15 : 1.35)) * rem;
    final xs = t.fontSize('xs');
    final label = Text(action.label.toUpperCase(), softWrap: false, style: pageText(t, xs, weight: 'bold', color: widget.ink, tracking: 0.06 * xs));
    final further = widget.next == null || widget.compact
        ? null
        : Opacity(
            opacity: 0.7,
            child: Text('Further to ${widget.next!.label.toLowerCase()}', softWrap: false, style: pageText(t, 0.625 * rem, color: widget.ink, tracking: 0.02 * 0.625 * rem)),
          );

    final picture = AnimatedBuilder(
      animation: _move,
      builder: (context, _) {
        const springy = Cubic(0.3, 1.5, 0.5, 1);
        var scale = 0.78 + widget.progress * 0.22;
        var turn = action.icon == SwipeIcon.pin || action.icon == SwipeIcon.unpin ? -12.0 : 0.0, dy = 0.0, opacity = 1.0;
        if (widget.armed && !t.reducedMotion) {
          // `@keyframes badge-pop`: 0.9, to 1.14 at 55%, to 1, over 320ms.
          final pop = _at(320, const Cubic(0.3, 1.6, 0.5, 1));
          scale = pop < 0.55 ? 0.9 + (1.14 - 0.9) * (pop / 0.55) : 1.14 + (1 - 1.14) * ((pop - 0.55) / 0.45);
          switch (action.icon) {
            case SwipeIcon.pin:
              // `pin-in`: from `translateY(-5px) rotate(-30deg)` to `rotate(-12deg)`.
              final p = _at(360, springy);
              dy = -5 * (1 - p);
              turn = -30 + 18 * p;
            case SwipeIcon.unpin:
              // `pin-out`: to `translateY(-3px) rotate(20deg)`, a little faded.
              final p = _at(360, Curves.easeOut);
              dy = -3 * p;
              turn = -12 + 32 * p;
              opacity = 1 - 0.2 * p;
            case SwipeIcon.archive:
              // `box-drop`: from `translateY(-4px)`.
              dy = -4 * (1 - _at(320, springy));
            case SwipeIcon.delete:
              // `bin-shake`: -10deg at 20%, 8deg at 45%, -4deg at 70%, and still.
              final p = _at(380, Curves.easeInOut);
              const keys = [(0.0, 0.0), (0.2, -10.0), (0.45, 8.0), (0.7, -4.0), (1.0, 0.0)];
              for (var i = 1; i < keys.length; i += 1) {
                if (p <= keys[i].$1) {
                  final span = keys[i].$1 - keys[i - 1].$1;
                  turn = keys[i - 1].$2 + (keys[i].$2 - keys[i - 1].$2) * ((p - keys[i - 1].$1) / span);
                  break;
                }
              }
          }
        } else if (widget.armed) {
          scale = 1;
        }
        return Transform.scale(
          scale: scale,
          child: SizedBox.square(
            dimension: badge,
            child: CustomPaint(
              painter: _RingPainter(progress: widget.armed ? 1 : widget.progress, color: widget.ink.withValues(alpha: widget.armed ? 1 : 0.55)),
              child: Center(
                child: Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: Transform.rotate(
                      angle: turn * math.pi / 180,
                      child: HomeIcon(
                        switch (action.icon) { SwipeIcon.pin || SwipeIcon.unpin => HomeGlyph.pin, SwipeIcon.archive => HomeGlyph.archive, SwipeIcon.delete => HomeGlyph.bin },
                        size: glyph,
                        color: widget.ink,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    Widget fade(bool shown, Widget child) => AnimatedOpacity(opacity: shown ? 1 : 0, duration: const Duration(milliseconds: 120), curve: t.curve('glacier-ease-out'), child: child);

    final Widget laid;
    if (widget.short) {
      // The picture keeps to the row's edge, following it, and the words come in once the gap can hold them whole.
      final words = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: widget.start ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [fade(widget.showLabel, label), if (further != null) fade(widget.showMore, further)],
      );
      // The pair is its own width at the row's edge of the gap: without a least of its own the row filled the gap
      // and stood at its far edge.
      laid = OverflowBox(
        alignment: widget.start ? AlignmentDirectional.centerEnd : AlignmentDirectional.centerStart,
        minWidth: 0,
        maxWidth: double.infinity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: widget.start ? [words, SizedBox(width: t.space(2)), picture] : [picture, SizedBox(width: t.space(2)), words],
        ),
      );
    } else {
      // `.behind { place-items: center }`: the pair is its own height in the middle of the gap. An OverflowBox hands
      // its child the gap's height as its least where none is said, and the column filled the gap from its top.
      laid = OverflowBox(
        minHeight: 0,
        maxWidth: double.infinity,
        maxHeight: double.infinity,
        child: ConstrainedBox(
          constraints: BoxConstraints(minWidth: 4.5 * rem),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [picture, SizedBox(height: t.space(1)), label, if (further != null) ...[SizedBox(height: t.space(1)), further]],
          ),
        ),
      );
    }
    return AnimatedBuilder(
      animation: _in,
      child: laid,
      builder: (context, child) {
        final p = Curves.easeOut.transform(_in.value);
        return Opacity(opacity: p, child: Transform.scale(scale: 0.85 + 0.15 * p, child: child));
      },
    );
  }
}

/// `.ring circle`: a circle of radius 20 in a box of 44, stroked 2.5, drawn from twelve o'clock for as much of the
/// way round as the swipe has come to its detent.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final unit = size.width / 44;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: 20 * unit);
    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress.clamp(0.0, 1.0),
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5 * unit
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.progress != progress || old.color != color;
}
