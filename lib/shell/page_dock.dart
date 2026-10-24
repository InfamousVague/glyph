/// The dock, the same on every page (docs/DOCK.md). Matt, 2026-10-17: "I want the right side dock standardized across
/// all pages but include icons relevant to what you can do on that page like settings and ask claude."
///
/// It is the home page's dock made once: a floating column of rings in a pill of glass, at the bottom end corner of
/// the page it is on, in from the edges by the page's safe areas and a step, with the smoke's halo round it where the
/// app hands one in. Claude is always at its head (lib/claude/claude_dock.dart), with Talk to Claude under it where
/// the build can hear (the orange mic, lib/claude/claude_voice.dart), what the page is for in the middle,
/// and a settings-type ring always at its foot: the app's Settings on a page of notes, the note's ⋯ on a note, the
/// organization's cog on its page.
///
///     DockAction      one ring: its mark, the words it is read aloud and shown by on a desktop, its press
///     PageDock        the pill: Claude, the page's rings, the foot
///     PageDockSeam    what the app hands a page for its dock: Claude, the halo, and a page of notes' own rings
///     PageDockFrame   a page with its dock over it, placed, kept clear of the keyboard and of the chat
///     DockOffer       a view inside a page (a canvas, a notebook, a journal) offering the page's dock its rings
///     PageDockRoom    how much of the page's end and foot the dock stands in, for what draws beside it
///     DockShrink      the dock two thirds of itself while the page under it is scrolled
///
/// While the keyboard is up in an editor the dock steps aside, so it never stands over the caret: it fades out (at
/// once under reduced motion), takes no presses and says nothing, and comes back as the keyboard goes. Every ring is
/// a button with its words said, and on a desktop (a mouse) the words come up beside it while the pointer rests on it.
///
/// While the page is scrolled the dock grows smaller, to two thirds of itself, and its own size again once the page
/// is still. Matt, 2026-10-17: "when we scroll make the dock bar animate to be 33% smaller". See [DockShrink].
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app/plain.dart';
import '../art/art.dart' show AppIcon, LucideIcon;
import '../home/home_icons.dart';
import 'wide_screen.dart' show mousePointer;

/// How a ring moves when it is pressed, as the home page's own do: Search's magnifier leans in, the + gives a
/// quarter turn, the rest dip.
enum DockMotion { lean, turn, dip }

/// One ring of the dock.
@immutable
class DockAction {
  const DockAction({
    required this.id,
    required this.label,
    required this.onPressed,
    this.icon,
    this.glyph,
    this.tip,
    this.motion = DockMotion.dip,
    this.ink = false,
    this.busy = false,
    this.badge,
  }) : assert(icon != null || glyph != null, 'a ring has a mark');

  /// Its name among the page's: its key is `dock-<id>`.
  final String id;

  /// The words a screen reader says for it, and the tip on a desktop unless [tip] says others.
  final String label;
  final String? tip;
  final VoidCallback? onPressed;

  /// Its mark: one of Lucide's, or one of the home page's own drawings ([HomeGlyph]).
  final LucideIcon? icon;
  final HomeGlyph? glyph;
  final DockMotion motion;

  /// The page's one ink-filled ring: Speak, the thing Ghost.md is for.
  final bool ink;

  /// Working: the ring is quieter and says so.
  final bool busy;

  /// A word or a count on the ring's shoulder.
  final String? badge;

  /// What it draws, for a dock deciding whether it changed: its press is not compared.
  Object get look => (id, label, tip, icon?.name, glyph, motion, ink, busy, badge, onPressed != null);
}

/// The pill: Claude at the head, the page's rings, and [foot] last. A port of the home page's `.dock`, which it was
/// written from and still draws (lib/home/home_screen.dart).
class PageDock extends StatelessWidget {
  const PageDock({super.key, this.claude, this.talk, this.actions = const <DockAction>[], this.foot, this.label = 'Page actions', this.claudeTip = 'Ask Claude'});

  /// Claude's ring (lib/claude/claude_dock.dart), drawn by itself: it hears what it shows.
  final Widget? claude;

  /// Talk to Claude, under Claude's ring (lib/claude/claude_dock.dart `ClaudeTalkButton`).
  final Widget? talk;
  final List<DockAction> actions;

  /// The settings-type ring at the foot.
  final DockAction? foot;

  /// What the dock as a whole is called to a screen reader.
  final String label;

  /// Claude's tip on a desktop.
  final String claudeTip;

  /// How many rings it draws.
  int get count => (claude != null ? 1 : 0) + (talk != null ? 1 : 0) + actions.length + (foot != null ? 1 : 0);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    final radius = BorderRadius.circular(t.radius('full'));
    final rings = <Widget>[
      if (claude != null) DockTip(message: claudeTip, child: claude!),
      if (talk != null) DockTip(message: 'Talk to Claude', child: talk!),
      for (final action in actions) DockRing(key: ValueKey('dock-${action.id}'), action: action),
      if (foot != null) DockRing(key: ValueKey('dock-${foot!.id}'), action: foot!),
    ];
    return Semantics(
      container: true,
      label: label,
      // Each button its own, however few there are: one alone would otherwise be read as the dock itself.
      explicitChildNodes: true,
      child: ClipRRect(
        borderRadius: radius,
        // One of the bars' group where there is one (lib/notes/tabs/bar_parts.dart `BarGlass`).
        child: BackdropFilter.grouped(
          enabled: !ghostPlain,
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: EdgeInsets.all(gap + t.len('glacier-hairline')),
            foregroundDecoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')), borderRadius: radius),
            decoration: BoxDecoration(color: t.colorOf(ghostPlain ? 'color-mix(in srgb, var(--glacier-bg) 94%, transparent)' : 'color-mix(in srgb, var(--glacier-bg) 82%, transparent)'), borderRadius: radius),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < rings.length; i += 1) ...[if (i > 0) SizedBox(height: gap), rings[i]],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The room a dock of [rings] takes at a page's foot, from the bottom of the window: the step it stands in by, the
/// pill, and the air the home page leaves over it (`foot` in lib/home/home_screen.dart). The safe area is not in it.
double pageDockRoom(Tokens t, int rings) {
  if (rings <= 0) return 0;
  return t.space(4) + t.len('app-ring') * rings + t.space(2) * (rings + 1) + t.space(6);
}

/// One ring. `.round`: an icon in a ring the height of the Speak pill, there but a step quieter than the one filled
/// thing on the screen; `ink`, that filled thing. Each gives a small move when pressed.
class DockRing extends StatelessWidget {
  const DockRing({super.key, required this.action});

  final DockAction action;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    final turn = t.transition('app-turn');
    // The glyphs are `1.15rem`, the size `.round` sets; Speak's mic is 18 with a heavier stroke.
    final size = action.ink ? 18.0 : t.lenOf('1.15rem');
    final stroke = action.ink ? 2.2 : 2.0;
    final ink = action.ink ? t.color('app-paper') : t.color('glacier-text');
    final busy = action.busy;
    Widget mark(bool pressed) {
      final Widget drawn = action.glyph != null ? HomeIcon(action.glyph!, size: size, strokeWidth: stroke, color: ink) : AppIcon(action.icon!, size: size, strokeWidth: stroke, color: ink);
      final Widget quiet = busy ? Opacity(opacity: 0.45, child: drawn) : drawn;
      return switch (action.motion) {
        DockMotion.lean => AnimatedScale(scale: pressed ? 0.9 : 1, duration: turn.duration, curve: turn.curve, child: quiet),
        DockMotion.turn => AnimatedRotation(turns: pressed ? 0.25 : 0, duration: turn.duration, curve: turn.curve, child: quiet),
        DockMotion.dip => quiet,
      };
    }

    final badge = action.badge;
    return DockTip(
      message: action.tip ?? action.label,
      child: GlacierPressable(
        onPressed: action.onPressed,
        semanticLabel: busy ? '${action.label}, working' : action.label,
        builder: (context, state) {
          final Widget round = action.ink
              ? GlacierFocusRing(
                  visible: state.focused,
                  offset: 3,
                  color: t.color('app-ink'),
                  child: AnimatedScale(
                    scale: state.pressed ? 0.98 : 1,
                    duration: t.duration('glacier-duration-fast'),
                    curve: t.curve('glacier-ease-out'),
                    child: Container(
                      width: ring,
                      height: ring,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: t.color('app-ink'), shape: BoxShape.circle),
                      child: mark(state.pressed),
                    ),
                  ),
                )
              : GlacierFocusRing(
                  visible: state.focused,
                  child: Container(
                    width: ring,
                    height: ring,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: t.color('glacier-bg'), shape: BoxShape.circle, border: Border.all(color: t.color('glacier-border-strong'), width: t.len('app-line'))),
                    child: mark(state.pressed),
                  ),
                );
          if (badge == null) return round;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              round,
              PositionedDirectional(
                end: -2,
                top: -2,
                child: ExcludeSemantics(
                  child: Container(
                    key: ValueKey('dock-${action.id}-badge'),
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(7), border: Border.all(color: t.color('glacier-bg'), width: 1.5)),
                    child: Text(badge, style: t.textAt(9, weight: 'semibold', height: 1.2, color: t.color('app-paper'))),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The words of a ring beside it, on a desktop, while the pointer rests on it: at the ring's start side, since the
/// dock stands at the page's end. Nothing on a phone, nor where the app has no overlay to draw them in.
class DockTip extends StatefulWidget {
  const DockTip({super.key, required this.message, required this.child, this.wait = const Duration(milliseconds: 450)});

  final String message;
  final Widget child;
  final Duration wait;

  @override
  State<DockTip> createState() => _DockTipState();
}

class _DockTipState extends State<DockTip> {
  final OverlayPortalController _portal = OverlayPortalController(debugLabel: 'dock tip');
  final LayerLink _link = LayerLink();
  Timer? _waiting;

  @override
  void dispose() {
    _waiting?.cancel();
    super.dispose();
  }

  void _enter() {
    _waiting?.cancel();
    _waiting = Timer(widget.wait, () {
      if (mounted && Overlay.maybeOf(context) != null) _portal.show();
    });
  }

  void _exit() {
    _waiting?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    if (!mousePointer) return widget.child;
    final t = context.tokens;
    final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
    return MouseRegion(
      onEnter: (_) => _enter(),
      onExit: (_) => _exit(),
      child: Listener(
        onPointerDown: (_) => _exit(),
        child: OverlayPortal(
          controller: _portal,
          overlayChildBuilder: (context) => Positioned(
            left: 0,
            top: 0,
            child: CompositedTransformFollower(
              link: _link,
              showWhenUnlinked: false,
              targetAnchor: rtl ? Alignment.centerRight : Alignment.centerLeft,
              followerAnchor: rtl ? Alignment.centerLeft : Alignment.centerRight,
              offset: Offset(rtl ? t.space(3) : -t.space(3), 0),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Container(
                    key: const ValueKey('dock-tip'),
                    padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: t.space(1)),
                    decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('sm'))),
                    child: Text(widget.message, maxLines: 1, softWrap: false, style: t.textAt(t.fontSize('xs'), weight: 'medium', height: 1.3, color: t.color('app-paper'))),
                  ),
                ),
              ),
            ),
          ),
          child: CompositedTransformTarget(link: _link, child: widget.child),
        ),
      ),
    );
  }
}

/// Where the dock stands over what is behind it, for whoever draws its halo (art/dock_blur.dart `DockBlur`): the
/// halo blurs what is behind the dock, so it is handed both. [shown] is false while the dock has stepped
/// aside, when there is no halo either.
@immutable
class DockPlace {
  const DockPlace({required this.behind, required this.dock, required this.alignment, required this.padding, this.shown = true, this.scale});

  final Widget behind;
  final Widget dock;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;
  final bool shown;

  /// How large the dock is drawn now, of the box it was laid out in, held to its corner at [alignment]: smaller
  /// while the page scrolls ([DockShrink]). The halo is drawn round the dock as it is drawn, and its reach goes with
  /// it. Null where the dock is always its own size.
  final ValueListenable<double>? scale;
}

/// The halo round the dock: answers [DockPlace.behind] and [DockPlace.dock] laid together with the halo between,
/// the dock at its alignment inside its padding of the box it is given.
typedef DockHaloBuilder = Widget Function(BuildContext context, DockPlace place);

/// Claude's ring for a page, given what the page is about: the words the chat opens with (a note's `[[Title]]`), read
/// when it is pressed, or null for none.
typedef DockClaudeBuilder = Widget Function(String Function()? subject);

/// What the app hands a page for its dock. Every part is optional: a page handed none draws no dock.
@immutable
class PageDockSeam {
  const PageDockSeam({this.claude, this.talk, this.halo, this.actions = const <DockAction>[], this.foot});

  final DockClaudeBuilder? claude;

  /// Talk to Claude for a page, given what the page is about, as [claude] is; none where the Claude plugin is off or
  /// the build cannot hear.
  final DockClaudeBuilder? talk;
  final DockHaloBuilder? halo;

  /// The app's own rings for a page of notes (Search, New note, Speak), and its Settings at the foot. A page with
  /// rings of its own (a note, an organization) draws those in their place.
  final List<DockAction> actions;
  final DockAction? foot;

  /// How many rings a page of notes draws from it: Claude, the app's own, the foot.
  int get rings => (claude != null ? 1 : 0) + (talk != null ? 1 : 0) + actions.length + (foot != null ? 1 : 0);
}

/// What covers the window's end edge now, in pixels: the chat with Claude as a panel down the right of a wide window
/// (lib/claude/claude_chat.dart). A dock under it moves out to its start.
final ValueNotifier<double> windowEndCover = ValueNotifier<double>(0);

/// How much of a page's end and foot its dock stands in, for what is drawn in that corner too (a canvas's map).
class PageDockRoom extends InheritedWidget {
  const PageDockRoom({super.key, required this.end, required this.bottom, required super.child});

  /// From the page's end edge to the dock's far side.
  final double end;

  /// From the page's foot to the dock's top.
  final double bottom;

  static PageDockRoom? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<PageDockRoom>();

  @override
  bool updateShouldNotify(PageDockRoom old) => old.end != end || old.bottom != bottom;
}

/// A page with its dock over it, where the home page's stands: the bottom end corner, in by the safe areas and
/// `--glacier-space-4`, riding over the keyboard; or, with [stepAside], gone while the keyboard is up. Under the chat
/// panel of a wide window it moves out to the panel's start, so it stays on the page and in reach.
///
/// [child] is the page: what scrolls behind the dock, which the halo is drawn over. The tree is the same shape
/// whether the dock shows or not, so nothing of the page is made again as it comes and goes.
class PageDockFrame extends StatefulWidget {
  const PageDockFrame({super.key, required this.seam, this.subject, this.actions, this.foot, this.stepAside = false, this.label = 'Page actions', required this.child});

  final PageDockSeam seam;

  /// What Claude is asked about from this page (see [DockClaudeBuilder]).
  final String Function()? subject;

  /// The page's own rings, in place of the seam's; and its own foot.
  final List<DockAction>? actions;
  final DockAction? foot;

  /// Whether the dock steps aside while the keyboard is up: a page being written in.
  final bool stepAside;
  final String label;
  final Widget child;

  @override
  State<PageDockFrame> createState() => _PageDockFrameState();
}

class _PageDockFrameState extends State<PageDockFrame> {
  /// How far the window's end is past this page's end, measured after a layout: a docked side panel's width.
  double _past = 0;

  @override
  void initState() {
    super.initState();
    windowEndCover.addListener(_covered);
  }

  @override
  void dispose() {
    windowEndCover.removeListener(_covered);
    super.dispose();
  }

  void _covered() {
    if (mounted) setState(() {});
  }

  void _measure() {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize || !box.attached) return;
      final window = MediaQuery.sizeOf(context).width;
      final rtl = Directionality.maybeOf(context) == TextDirection.rtl;
      final at = box.localToGlobal(Offset.zero);
      final past = rtl ? math.max(0.0, at.dx) : math.max(0.0, window - (at.dx + box.size.width));
      if ((past - _past).abs() > 0.5) setState(() => _past = past);
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final seam = widget.seam;
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final hidden = widget.stepAside && keyboard > 0;
    final cover = windowEndCover.value;
    if (cover > 0) _measure();
    // The chat panel over this page's end, past whatever stands between the page and the window's edge.
    final under = math.max(0.0, cover - _past);
    final end = t.len('app-safe-right') + t.space(4) + under;
    // The phone's own bar is under the keyboard while it is up: the dock rides over the keys then. Whichever is
    // higher, so as the keys slide away the dock follows them down and stops on the bar: taken from the keyboard
    // alone while any of it showed, the last frames dropped the dock below the bar and it leapt back up at the end.
    final safe = t.len('app-safe-bottom');
    final bottom = math.max(keyboard, safe) + t.space(4);
    final dock = PageDock(
      claude: seam.claude?.call(widget.subject),
      talk: seam.talk?.call(widget.subject),
      actions: widget.actions ?? seam.actions,
      foot: widget.foot ?? seam.foot,
      label: widget.label,
    );
    final still = t.reducedMotion;
    final padding = EdgeInsetsDirectional.only(end: end, bottom: bottom);
    const alignment = AlignmentDirectional.bottomEnd;
    final halo = seam.halo;
    final ring = t.len('app-ring');
    // Smaller while the page scrolls: inside the fade, so the fade's box (what the halo measures) is the dock's own
    // size, and the room the page keeps at its foot is the room it keeps at rest.
    return DockShrink(
      builder: (context, shrink) {
        final shown = AnimatedOpacity(
          key: const ValueKey('page-dock'),
          opacity: hidden ? 0 : 1,
          duration: still ? Duration.zero : t.duration('glacier-duration-fast'),
          curve: t.curve('glacier-ease-out'),
          child: shrink.dock(IgnorePointer(ignoring: hidden, child: ExcludeSemantics(excluding: hidden, child: dock))),
        );
        final behind = shrink.page(widget.child);
        return PageDockRoom(
          end: end + ring + 2 * (t.space(2) + t.len('glacier-hairline')),
          // The bar's part of the room shrinks as the keyboard covers it, rather than all at once.
          bottom: math.max(0.0, safe - keyboard) + pageDockRoom(t, dock.count),
          child: halo != null
              ? halo(context, DockPlace(behind: behind, dock: shown, alignment: alignment, padding: padding, shown: !hidden, scale: shrink.scale))
              : Stack(fit: StackFit.expand, children: [behind, Padding(padding: padding, child: Align(alignment: alignment, child: shown))]),
        );
      },
    );
  }
}

/// How large the dock is while the page under it is scrolled, of its own size. Matt, 2026-10-17: "when we scroll make
/// the dock bar animate to be 33% smaller", then "the navbar should only get 20% smaller 33% is too small". Rings, the
/// gaps between them, the pill round them and the halo round that, all of it, held to the dock's bottom end corner,
/// so it stays where the thumb is.
const double dockScrolledScale = 0.8;

/// How near the page's top counts as at it, in logical pixels: the dock is whole again there.
const double dockTopSlack = 4;

/// Whether [n] is the page's own scroll, the one the dock grows smaller for: up and down, of the page itself
/// (`depth` 0, nearest the listener). A carousel across the page, a code block's or a table's own scroller, the
/// field of a search: each of those is a scroller inside the page, and the dock is left as it is.
bool dockHearsScroll(ScrollNotification n) => n.depth == 0 && n.metrics.axis == Axis.vertical;

/// The dock four fifths of itself ([dockScrolledScale]) once the page under it is scrolled down, and its own size
/// again when the page is back at its top (Matt, 2026-10-17: "it should stay small until scrolling back to the top of
/// the page"). Every page's dock ([PageDockFrame]) and the home page's (lib/home/home_screen.dart `_screen`).
///
/// It hears the page's scrolls, not the page: [DockShrinking.page] puts a listener round what scrolls, and
/// [DockShrinking.dock] a scale round the dock, and an animation of this widget's own drives the scale. Nothing of the
/// page, nor of the dock, is built again as it shrinks; the scale is a transform, so a ring is pressed where it is
/// drawn, small or not, and its own motions (Claude's turning, a ring's lean and turn) go on inside it.
///
/// **The person's scrolls.** It grows smaller as the person scrolls the page away from its top: a drag (a thumb, a
/// trackpad) or a wheel, which say so as they begin (`UserScrollNotification`, a drag's details). The page moved by
/// the app away from its top (a jump to where it was left, a heading brought into view) leaves the dock as it is:
/// nobody's thumb is on the page then. Once small, it stays so however long the page is still, and grows back only
/// when the page is at its top again ([dockTopSlack]), whoever took it there: the thumb, or the app gliding it back
/// for another filter.
///
/// Shrinks in `--glacier-duration-fast`, grows back in `--glacier-duration-normal`, both `--glacier-ease-out`; under
/// reduced motion it is one size or the other at once.
class DockShrink extends StatefulWidget {
  const DockShrink({super.key, required this.builder});

  /// The page and its dock, wrapped by [DockShrinking.page] and [DockShrinking.dock].
  final Widget Function(BuildContext context, DockShrinking shrink) builder;

  @override
  State<DockShrink> createState() => _DockShrinkState();
}

/// What [DockShrink] hands its builder: the page's listener, the dock's scale, and the scale itself, for a halo.
@immutable
class DockShrinking {
  const DockShrinking._(this.scale, this._heard);

  /// How large the dock is now, of its own size: 1 at the page's top, [dockScrolledScale] once scrolled down it.
  final Animation<double> scale;
  final NotificationListenerCallback<ScrollNotification> _heard;

  /// [child], what scrolls behind the dock, heard as it scrolls. The scrolls go on up past it.
  Widget page(Widget child) => NotificationListener<ScrollNotification>(onNotification: _heard, child: child);

  /// [child], the dock, drawn at [scale], held to its corner at [alignment].
  Widget dock(Widget child, {AlignmentGeometry alignment = AlignmentDirectional.bottomEnd}) => _DockScaled(scale: scale, alignment: alignment, child: child);
}

class _DockScaled extends StatelessWidget {
  const _DockScaled({required this.scale, required this.alignment, required this.child});

  final Animation<double> scale;
  final AlignmentGeometry alignment;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(key: const ValueKey('page-dock-scale'), scale: scale, alignment: alignment.resolve(Directionality.maybeOf(context) ?? TextDirection.ltr), child: child);
}

class _DockShrinkState extends State<DockShrink> with SingleTickerProviderStateMixin {
  /// 0 at rest, 1 small.
  late final AnimationController _small = AnimationController(vsync: this);
  late final DockShrinking _shrinking = DockShrinking._(_small.drive(Tween<double>(begin: 1, end: dockScrolledScale)), _heard);

  /// Where [_small] is going: 0 or 1, so a scroll's every frame does not start the way there again.
  double _goal = 0;

  // The kit's motion, as it was at the last build.
  bool _still = false;
  Duration _fast = Duration.zero, _normal = Duration.zero;
  Curve _ease = Curves.linear;

  @override
  void dispose() {
    _small.dispose();
    super.dispose();
  }

  bool _heard(ScrollNotification n) {
    if (!dockHearsScroll(n)) return false;
    final metrics = n.metrics;
    // At the top (or pulled past it, as a refresh is): whole, whoever brought the page there.
    if (!metrics.hasPixels || metrics.pixels <= metrics.minScrollExtent + dockTopSlack) {
      _go(0);
      return false;
    }
    final theirs = switch (n) {
      UserScrollNotification(:final direction) => direction != ScrollDirection.idle,
      ScrollStartNotification(:final dragDetails) => dragDetails != null,
      ScrollUpdateNotification(:final dragDetails) => dragDetails != null,
      _ => false,
    };
    if (theirs) _go(1);
    return false;
  }

  void _go(double goal) {
    if (_goal == goal) return;
    _goal = goal;
    if (_still) {
      _small.value = goal;
      return;
    }
    _small.animateTo(goal, duration: goal == 1 ? _fast : _normal, curve: _ease);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    _still = t.reducedMotion;
    _fast = t.duration('glacier-duration-fast');
    _normal = t.duration('glacier-duration-normal');
    _ease = t.curve('glacier-ease-out');
    return widget.builder(context, _shrinking);
  }
}

/// The dock's rings that a view inside a page offers it: a canvas's Add a card and Fit, a notebook's Add a page and
/// Read straight through, a journal's New entry. The page that holds the dock makes one ([DockOffers]) and puts it
/// over the view ([DockOfferScope]); the view says its rings with a [DockOffer].
class DockOffers extends ChangeNotifier {
  List<DockAction> _actions = const <DockAction>[];
  Object? _from;
  bool _gone = false;

  @override
  void dispose() {
    _gone = true;
    super.dispose();
  }

  /// What is offered now.
  List<DockAction> get actions => _actions;

  /// [from]'s rings: the dock is drawn again when what they look like changes, and only then; a press is always
  /// the latest one offered.
  void offer(Object from, List<DockAction> actions) {
    if (_gone) return;
    final same = identical(from, _from) && listEquals([for (final a in _actions) a.look], [for (final a in actions) a.look]);
    _from = from;
    _actions = actions;
    if (!same) notifyListeners();
  }

  /// [from] has gone: its rings go with it.
  void withdraw(Object from) {
    if (_gone || !identical(from, _from)) return;
    _from = null;
    if (_actions.isEmpty) return;
    _actions = const <DockAction>[];
    notifyListeners();
  }
}

class DockOfferScope extends InheritedWidget {
  const DockOfferScope({super.key, required this.offers, required super.child});

  final DockOffers offers;

  static DockOffers? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<DockOfferScope>()?.offers;

  @override
  bool updateShouldNotify(DockOfferScope old) => !identical(old.offers, offers);
}

/// Offers [actions] to the dock of the page this is on, after each build, and takes them back when it goes. Nothing
/// where the page has no dock. Draws [child] as it is (a box or a sliver).
class DockOffer extends StatefulWidget {
  const DockOffer({super.key, required this.actions, required this.child});

  final List<DockAction> actions;
  final Widget child;

  @override
  State<DockOffer> createState() => _DockOfferState();
}

class _DockOfferState extends State<DockOffer> {
  DockOffers? _offers;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final now = DockOfferScope.maybeOf(context);
    if (!identical(now, _offers)) {
      _offers?.withdraw(this);
      _offers = now;
    }
  }

  @override
  void dispose() {
    final offers = _offers;
    // After the frame: the dock is being built in it, perhaps, as this goes.
    if (offers != null) SchedulerBinding.instance.addPostFrameCallback((_) => offers.withdraw(this));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offers = _offers;
    if (offers != null) {
      final actions = widget.actions;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) offers.offer(this, actions);
      });
    }
    return widget.child;
  }
}
