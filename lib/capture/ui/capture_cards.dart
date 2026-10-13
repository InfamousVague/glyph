/// The recorder's cards, where the chip would be: items arriving in another note's list, which note a name meant,
/// "shall I?" for a command read at Done, and the one line to say in a pause. A port of
/// `src/app/capture/CaptureCards.tsx` (`ListLanding`, `NoteChoiceCard`), of `src/app/ai/ConfirmCard.tsx` with
/// ConfirmCard.module.css, and of the `.tip` paragraph CaptureScreen.tsx writes in place, with the rules of
/// CaptureScreen.module.css they wear (`.landing`, `.landed*`, `.context*`, `.choices`, `.tip`).
///
/// Drawn by the capture screen from what the live reader tells it; they hold no state of their own, and none of them
/// opens a microphone. Each carries its own bottom margin, as its rule says, so the screen sets them one above the
/// buttons with nothing between.
///
/// What differs:
/// - The confirm card lives here and not in `lib/ai`, because the recorder is the one screen that draws it.
/// - The tip is a widget ([PauseTip]) where the web writes a paragraph inline.
/// - A card's `Note` is any note ([LiveCard] and [Offer] are generic here, as take_types.dart says).
/// - [EnterFrom] is the one shape every entrance on these cards has (`@keyframes … { from { … } }` with `both`), so
///   the say card and the chip (say_card.dart, route_chip.dart) use it too.
/// - A pill for a note whose title is too long is cut with an ellipsis by holding its word to the card's width less
///   the pill's own padding, since [AppPill] is a row that will not shrink its word.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app/widgets.dart';
import '../../editor/looks/look.dart' show layoutUnitFloor;
import '../../sheet/css.dart' show snapBorder;
import '../../core/item_syntax.dart' show withoutLead;
import '../instruction_mutation.dart' show listTitle;
import '../list_append.dart' show PlacedInto, linesAbove;
import '../live_route.dart';
import '../offers.dart';
import '../tips.dart' show Tip;

/// An entrance written as one `from` keyframe: `animation: <name> <duration> <curve> <delay> both`. The child starts
/// clear ([opacity] false leaves it solid), [dy] pixels down and at [scale], and arrives where it is laid out; held
/// at `from` through the [delay], as `both` holds it. With reduced motion there is no entrance at all.
class EnterFrom extends StatefulWidget {
  const EnterFrom({super.key, required this.duration, required this.curve, this.delay = Duration.zero, this.dy = 0, this.scale = 1, this.opacity = true, required this.child});

  final Duration duration;
  final Curve curve;
  final Duration delay;
  final double dy;
  final double scale;
  final bool opacity;
  final Widget child;

  @override
  State<EnterFrom> createState() => _EnterFromState();
}

class _EnterFromState extends State<EnterFrom> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(vsync: this, duration: widget.delay + widget.duration);
  bool _begun = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_begun) return;
    _begun = true;
    // `@media (prefers-reduced-motion: reduce) { animation: none }`
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
  Widget build(BuildContext context) {
    final whole = (widget.delay + widget.duration).inMicroseconds;
    final delay = widget.delay.inMicroseconds;
    return AnimatedBuilder(
      animation: _run,
      child: widget.child,
      builder: (context, child) {
        final local = whole == 0 || whole == delay ? 1.0 : ((_run.value * whole - delay) / (whole - delay)).clamp(0.0, 1.0);
        if (local >= 1) return child!;
        // The easing overshoots (the app's pop is a cubic-bezier past 1): the place and the size follow it, the
        // opacity stops at solid.
        final at = widget.curve.transform(local);
        Widget out = Transform.translate(offset: Offset(0, widget.dy * (1 - at)), child: Transform.scale(scale: widget.scale + (1 - widget.scale) * at, child: child));
        if (widget.opacity) out = Opacity(opacity: at.clamp(0.0, 1.0), child: out);
        return out;
      },
    );
  }
}

/// A box whose baseline is its own bottom edge, as an empty box's is in a flex row aligned on baselines.
class _BottomBaseline extends SingleChildRenderObjectWidget {
  const _BottomBaseline({required Widget super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderBottomBaseline();
}

class _RenderBottomBaseline extends RenderProxyBox {
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => size.height;

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline baseline) => getDryLayout(constraints).height;
}

/// `.landedTick`: a tick drawn with two borders, turned.
class _LandedTick extends StatelessWidget {
  const _LandedTick({required this.em, required this.color});

  final double em;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // .landedTick {
    //   flex: none;
    //   inline-size: 0.35em;
    //   block-size: 0.7em;
    //   border-inline-end: 2px solid currentColor;
    //   border-block-end: 2px solid currentColor;
    //   transform: rotate(45deg) translateY(-0.15em);
    // }
    return _BottomBaseline(child: CustomPaint(size: Size(0.35 * em, 0.7 * em), painter: TickPainter(color: color, dx: 0, dy: -0.15 * em)));
  }
}

/// A tick as the page draws one: a box with a 2 px line down its right side and along its foot, turned an eighth of
/// a turn about its middle and then moved by ([dx], [dy]) along its own turned axes (`rotate(45deg) translate(…)`).
class TickPainter extends CustomPainter {
  const TickPainter({required this.color, required this.dx, required this.dy});

  final Color color;
  final double dx;
  final double dy;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final w = size.width / 2;
    final h = size.height / 2;
    canvas.save();
    canvas.translate(w, h);
    canvas.rotate(0.7853981633974483);
    canvas.translate(dx, dy);
    canvas.drawRect(Rect.fromLTRB(w - 2, -h, w, h), paint);
    canvas.drawRect(Rect.fromLTRB(-w, h - 2, w, h), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(TickPainter old) => old.color != color || old.dx != dx || old.dy != dy;
}

/// Items landing in another note's list: the note's name, the list's last lines as they were, and the new lines
/// arriving under them with a tick each. [onUndo], for words the live reader sent there, takes them out again (Not
/// this note).
class ListLanding extends StatelessWidget {
  const ListLanding({super.key, required this.title, required this.body, required this.added, this.onUndo});

  final String title;
  final String body;
  final List<String> added;
  final VoidCallback? onUndo;

  static final RegExp _heading = RegExp(r'^#{1,6}\s+');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final lg = t.fontSize('lg');
    // A line as tall as the page makes it: 1.25 of the size, to a sixty-fourth of a pixel, where the text engine's own
    // is a whole pixel.
    final line = layoutUnitFloor(1.25 * lg);
    final settle = t.transition('app-settle');
    final gap = SizedBox(height: t.space(1));
    final rows = <Widget>[
      // .landingUndo { justify-self: end; }
      if (onUndo != null) Align(alignment: Alignment.centerRight, heightFactor: 1, child: AppWord(onPressed: onUndo, child: const PageWord('Not this note'))),
      // .contextTitle { composes: app-eyebrow from global; }
      CardEyebrow(title),
      for (final above in linesAbove(body, added))
        // .contextLine {
        //   margin: 0;
        //   font-size: var(--glacier-font-size-lg);
        //   line-height: 1.25;
        //   color: var(--app-ink-4);
        //   overflow: hidden;
        //   text-overflow: ellipsis;
        //   white-space: nowrap;
        // }
        SizedBox(
          height: line,
          child: Text(
            withoutLead(above).replaceFirst(_heading, ''),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: t.textAt(lg, color: t.color('app-ink-4'), height: 1.25),
          ),
        ),
      for (var i = 0; i < added.length; i += 1)
        // .landed {
        //   display: flex;
        //   align-items: baseline;
        //   gap: var(--glacier-space-2);
        //   margin: 0;
        //   font-size: var(--glacier-font-size-lg);
        //   font-weight: var(--glacier-font-weight-semibold);
        //   line-height: 1.25;
        //   color: var(--app-ink);
        //   animation: landed-in 460ms cubic-bezier(0.3, 1.4, 0.5, 1) both;
        // }
        // @keyframes landed-in { from { opacity: 0; transform: translateY(14px) scale(0.96); } }
        // style={{ animationDelay: `${120 + i * 140}ms` }}
        EnterFrom(
          duration: const Duration(milliseconds: 460),
          curve: const Cubic(0.3, 1.4, 0.5, 1),
          delay: Duration(milliseconds: 120 + i * 140),
          dy: 14,
          scale: 0.96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _LandedTick(em: lg, color: t.color('app-ink')),
              SizedBox(width: t.space(2)),
              Flexible(child: PageLines(TextSpan(text: withoutLead(added[i])), style: t.textAt(lg, weight: 'semibold', color: t.color('app-ink'), height: 1.25))),
            ],
          ),
        ),
    ];
    // .landing {
    //   flex: none;
    //   display: grid;
    //   gap: var(--glacier-space-1);
    //   margin-block-end: var(--glacier-space-3);
    //   animation: context-in var(--app-settle) both;
    // }
    // @keyframes context-in { from { opacity: 0; transform: translateY(8px); } }
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: Semantics(
        container: true,
        label: 'Added to $title',
        child: EnterFrom(
          duration: settle.duration,
          curve: settle.curve,
          dy: 8,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < rows.length; i += 1) ...[if (i > 0) gap, rows[i]],
            ],
          ),
        ),
      ),
    );
  }
}

/// The confirm card's shell (ConfirmCard.module.css `.confirm`): a ring of ink on paper-2, popping in.
class _ConfirmShell extends StatelessWidget {
  const _ConfirmShell({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pop = t.transition('app-pop');
    // .confirm {
    //   flex: none;
    //   display: grid;
    //   gap: var(--glacier-space-1);
    //   margin: 0 0 var(--glacier-space-3);
    //   padding: var(--glacier-space-4);
    //   border: var(--app-line) solid var(--app-ink);
    //   border-radius: var(--glacier-radius-lg);
    //   background: var(--app-paper-2);
    //   animation: card-pop var(--app-pop) both;
    // }
    // @keyframes card-pop { from { opacity: 0; transform: translateY(6px) scale(0.98); } }
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: Semantics(
        container: true,
        liveRegion: true,
        label: label,
        child: EnterFrom(
          duration: pop.duration,
          curve: pop.curve,
          dy: 6,
          scale: 0.98,
          child: Container(
            padding: EdgeInsets.all(t.space(4)),
            decoration: BoxDecoration(
              color: t.color('app-paper-2'),
              border: Border.all(color: t.color('app-ink'), width: snapBorder(context, t.len('app-line'))),
              borderRadius: BorderRadius.circular(t.radius('lg')),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i += 1) ...[if (i > 0) SizedBox(height: t.space(1)), children[i]],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// .line {
//   margin: 0;
//   font-size: var(--glacier-font-size-lg);
//   font-weight: var(--glacier-font-weight-semibold);
//   line-height: 1.25;
//   color: var(--app-ink);
//   overflow-wrap: anywhere;
// }
Widget _cardLine(Tokens t, String text) => PageLines(TextSpan(text: text), style: t.textAt(t.fontSize('lg'), weight: 'semibold', color: t.color('app-ink'), height: 1.25));

/// "Add to which note?": the live reader was not sure which note a name meant, or found none but came near one
/// (capture/live_route.dart). The card shows the words as they would land and a button for each note it could be, a
/// new note by the name as heard, and Keep here. It blocks nothing: the recording carries on, what is said meanwhile
/// goes to the page, and after 8 s, or at Done, the words stay here. A title, "the first one" or "keep it here" said
/// answers it as a tap does.
class NoteChoiceCard<N extends Object> extends StatelessWidget {
  const NoteChoiceCard({super.key, required this.card, required this.onChoose});

  final LiveCard<N> card;
  final void Function(CardChoice choice) onChoose;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return _ConfirmShell(
      label: card.heading,
      children: [
        // .heading { composes: app-eyebrow from global; }
        CardEyebrow(card.heading),
        if (card.payload.isNotEmpty) _cardLine(t, withoutLead(card.payload)),
        // .choices {
        //   display: flex;
        //   flex-wrap: wrap;
        //   gap: var(--glacier-space-2);
        //   margin-top: var(--glacier-space-2);
        // }
        // .choices > button { max-width: 100%; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
        Padding(
          padding: EdgeInsets.only(top: t.space(2)),
          child: LayoutBuilder(
            builder: (context, box) => Wrap(
              spacing: t.space(2),
              runSpacing: t.space(2),
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final candidate in card.candidates)
                  AppPill(
                    onPressed: () => onChoose(CardChoiceNote(id: candidate.id)),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: (box.maxWidth - 2 * t.space(6)).clamp(0.0, double.infinity)),
                      child: Text(candidate.title, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                if (card.newTitle.isNotEmpty)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: box.maxWidth),
                    child: AppWord(onPressed: () => onChoose(const CardChoiceNew()), child: PageWord('New note “${card.newTitle}”')),
                  ),
              ],
            ),
          ),
        ),
        // .actions {
        //   display: flex;
        //   align-items: center;
        //   justify-content: space-between;
        //   margin-block-start: var(--glacier-space-2);
        // }
        Padding(
          padding: EdgeInsets.only(top: t.space(2)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppWord(onPressed: () => onChoose(const CardChoiceKeep()), child: PageWord(card.form == LiveCardForm.declined ? 'Leave it' : 'Keep here')),
            ],
          ),
        ),
      ],
    );
  }
}

/// The confirm card: exactly what a command is about to do, before it does it, for a command read at Done from a
/// recording: words for a note by name, or a new list by name. Matt (PR #1): "Shows the exact proposed change before
/// applying it."
class ConfirmCard<N extends Object> extends StatelessWidget {
  const ConfirmCard({super.key, required this.offer, required this.onConfirm, required this.onCancel});

  final Offer<N> offer;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final String heading;
    final String action;
    final List<String> lines;
    String? detail;
    switch (offer) {
      case OfferPlace<N>(:final title, :final added, :final into):
        heading = 'Add to $title';
        action = 'Add';
        lines = added.map(withoutLead).toList();
        detail = into == PlacedInto.list ? 'In its list' : 'As a new paragraph';
      case OfferNew<N>(:final title, lines: final items):
        heading = 'Create ${listTitle(title)}';
        action = 'Create';
        lines = [...?items];
        if (items != null && items.isNotEmpty) detail = 'As a new list';
      case OfferPlan<N>(heading: final said, action: final word, lines: final shown, detail: final note):
        heading = said;
        action = word;
        lines = shown;
        detail = note;
    }
    return _ConfirmShell(
      label: heading,
      children: [
        CardEyebrow(heading),
        for (final line in lines) _cardLine(t, line),
        // .detail {
        //   margin: 0;
        //   font-size: var(--glacier-font-size-sm);
        //   color: var(--app-ink-3);
        // }
        if (detail != null) Text(detail, style: t.textAt(t.fontSize('sm'), color: t.color('app-ink-3'))),
        // .actions { display: flex; align-items: center; justify-content: space-between; margin-block-start: var(--glacier-space-2); }
        Padding(
          padding: EdgeInsets.only(top: t.space(2)),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AppWord(onPressed: onCancel, child: const PageWord('Cancel')),
              AppPill(onPressed: onConfirm, child: Text(action)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A tip in a pause: something to say, quiet, just above the buttons. Say “Check box” to make a to-do.
class PauseTip extends StatelessWidget {
  const PauseTip({super.key, required this.tip});

  final Tip tip;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final md = t.fontSize('md');
    // .tip {
    //   flex: none;
    //   margin: 0 0 var(--glacier-space-3);
    //   text-align: center;
    //   font-size: var(--glacier-font-size-md);
    //   color: var(--app-ink-3);
    //   animation: tip-in 600ms ease-out both;
    // }
    // .tip strong { color: var(--app-ink-2); font-weight: var(--glacier-font-weight-semibold); }
    // @keyframes tip-in { from { opacity: 0; transform: translateY(4px); } }
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: EnterFrom(
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        dy: 4,
        child: SizedBox(
          width: double.infinity,
          child: Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: 'Say '),
                TextSpan(text: '“${tip.say}”', style: t.textAt(md, weight: 'semibold', color: t.color('app-ink-2'))),
                TextSpan(text: ' ${tip.does}.'),
              ],
            ),
            textAlign: TextAlign.center,
            style: t.textAt(md, color: t.color('app-ink-3')),
          ),
        ),
      ),
    );
  }
}

/// `.app-eyebrow` as a card's heading wears it: the small spaced capitals in the third ink, on a line of the page's
/// own leading (`line-height: normal`, 14 px at the phone's size), where the kit's step (`AppEyebrow`) is taller.
class CardEyebrow extends StatelessWidget {
  const CardEyebrow(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    // The line is the page's to the device pixel (13.33px on a phone 476 wide, where the engine's whole pixel is 13).
    return ExactLines.of(
      Text(text.toUpperCase(), style: t.textAt(size, weight: 'bold', color: t.color('app-ink-3'), tracking: t.len('app-tracking-caps', em: size))),
      normal: true,
      dpr: t.css.lineDpr,
    );
  }
}

/// Words on lines as tall as the page makes them: a unitless `line-height` times the size, to a sixty-fourth of a
/// pixel (Blink's layout unit), where the text engine here rounds a line to a whole pixel. Over a card's few lines
/// that is most of a pixel of drift, which this takes back: the words are set as they are, in a box as tall as the
/// page's would be. [style] must carry a size and a height.
class PageLines extends StatelessWidget {
  const PageLines(this.text, {super.key, required this.style, this.maxLines});

  final InlineSpan text;
  final TextStyle style;
  final int? maxLines;

  @override
  Widget build(BuildContext context) {
    final line = layoutUnitFloor(style.height! * style.fontSize!);
    return _Lines(
      line: line,
      child: Text.rich(text, style: style, maxLines: maxLines, overflow: maxLines == null ? null : TextOverflow.ellipsis),
    );
  }
}

/// A paragraph given the height of its lines at [line] each, counted from its own height at whole-pixel lines.
class _Lines extends SingleChildRenderObjectWidget {
  const _Lines({required this.line, required Widget super.child});

  final double line;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderLines(line);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) => (renderObject as _RenderLines).line = line;
}

class _RenderLines extends RenderProxyBox {
  _RenderLines(this._line);

  double _line;
  set line(double value) {
    if (value == _line) return;
    _line = value;
    markNeedsLayout();
  }

  Size _sized(Size child) {
    final rounded = _line.roundToDouble();
    final count = rounded <= 0 ? 1 : (child.height / rounded).round().clamp(1, 1 << 20);
    return constraints.constrain(Size(child.width, count * _line));
  }

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final size = child.getDryLayout(constraints.loosen());
    final rounded = _line.roundToDouble();
    final count = rounded <= 0 ? 1 : (size.height / rounded).round().clamp(1, 1 << 20);
    return constraints.constrain(Size(size.width, count * _line));
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints.loosen(), parentUsesSize: true);
    size = _sized(child.size);
  }
}

/// The word of an `.app-word` button as these screens' own rules leave it: `font: inherit`, which under the
/// recorder's footer and cards is the page's own sixteen pixels, medium, in the button's ink for its state. The
/// shared `AppWord` sets its word at the kit's `md` step, which is the same size on a phone to a tenth of a pixel
/// and grows with a wide window where the page's word does not.
class PageWord extends StatelessWidget {
  const PageWord(this.word, {super.key});

  final String word;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Text(word, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, style: t.textAt(t.lenOf('1rem'), weight: 'medium', color: DefaultTextStyle.of(context).style.color));
  }
}
