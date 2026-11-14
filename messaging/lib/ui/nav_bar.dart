import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';

/// One place the navigation pill goes to: one ring.
class NavItem {
  const NavItem({required this.id, required this.icon, required this.label, this.count = 0, this.menu});
  final String id;
  final LucideIcon icon;

  /// The rows of a menu of its own, asked for as it opens: a press with the other button on the ring, or a long
  /// press where there is no other button, hangs the kit's menu over the ring with these in it (the kit's
  /// `GlacierMenuItem`, `GlacierMenuLabel` and `GlacierMenuSeparator`). Matt, 2026-11-14: "add a right click
  /// context menu to archive as well and settings to quick jump to settings sections", and then, of the sheet
  /// across the window it first was: "too large and way too wide", with a picture of a small list hung by the
  /// button it came from, its rows in groups.
  final List<Widget> Function(BuildContext context)? menu;

  /// What the ring is read aloud by, and shown by while the pointer rests on it.
  final String label;

  /// A number worn on the ring's corner (how many are archived); nothing for none.
  final int count;
}

/// The navigation pill that floats at the foot of the list of conversations: a new chat, the messages, the
/// contacts, the archive, Settings. It was made for the Mac's sidebar (Matt, 2026-11-14: "at the bottom of the
/// desktop sidebar, add a navigation bar floating", then "use the same navigation pill that we use in ghost markdown
/// but horizontal instead of vertical") and is the phone's too since the two share a frame (lib/ui/shell.dart;
/// Matt, the same day: "the mobile app should gain the nav from desktop").
///
/// It is Ghost.md's dock (lib/shell/page_dock.dart at the repository's root: `PageDock`, `DockRing`, `DockTip`),
/// laid along where that one stands up, and as wide as the sidebar with its rings evenly along it: a pill of glass, a step of space round its rings and between them, a
/// hairline round it; each ring `--app-ring` across, the page's colour with a line round it and its mark in the
/// page's ink; the one shown now filled with ink, its mark in paper, as the dock's one filled ring is; a number on a
/// ring's corner, in red (the dock wears its own in ink; here Matt asked for red); and a ring's words over it while the pointer rests there, where the dock's
/// come up beside it.
///
/// On a wide phone (a folding phone opened out, a tablet) it stands up instead, as Ghost.md's does: its rings close
/// under one another in a pill no wider than a ring, at the foot of a strip of its own down the window's right
/// ([upright]; Matt, 2026-11-14: "on wider phones like my fold 8 make the navbar render vertically condensed on the
/// right of the screen like we do in ghost markdown"). The frame gives it that strip (lib/ui/shell.dart), so it
/// stands over nothing: not the Send button, not the newest messages.
class NavPill extends StatelessWidget {
  const NavPill({super.key, required this.items, required this.active, required this.onSelect, this.upright = false});
  final List<NavItem> items;

  /// Stood up, its rings a step apart head to foot, rather than laid along the list's foot and spread across it.
  final bool upright;

  /// The id of the item shown now.
  final String active;
  final ValueChanged<String> onSelect;

  /// How far in from the sidebar's foot the pill stands.
  static double inset(Tokens t) => t.space(4);

  /// How much of the list's end the pill stands over, with its room: what the list leaves clear there.
  static double clearance(Tokens t) => t.len('app-ring') + (t.space(2) + t.len('glacier-hairline')) * 2 + inset(t) * 2;

  /// Stood up: how wide the strip it stands in is, the pill and a step of room on either side of it.
  static double railWidth(Tokens t) => t.len('app-ring') + (t.space(2) + t.len('glacier-hairline')) * 2 + _railRoom(t) * 2;

  /// The room on either side of the pill stood up: a small step, since every bit of it is taken from the pane.
  static double _railRoom(Tokens t) => t.space(2);

  /// Stood up with [count] rings: how tall it is with its room above and below. A window shorter than this (a
  /// small phone on its side) has no room for it stood up.
  static double railHeight(Tokens t, int count) => t.len('app-ring') * count + t.space(2) * (count - 1) + (t.space(2) + t.len('glacier-hairline')) * 2 + inset(t) * 2;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    final radius = BorderRadius.circular(t.radius('full'));
    // The pill runs the sidebar's width and its rings stand evenly along it, the first and the last at its ends
    // (Matt, 2026-11-14: "Evenly space the icons across the bottom of the sidebar instead of condensing them to the
    // center").
    final rings = [
      for (final item in items)
        _Ring(key: ValueKey('nav-${item.id}'), item: item, shown: item.id == active, upright: upright, onPressed: () => onSelect(item.id)),
    ];
    return Padding(
      padding: upright ? EdgeInsets.symmetric(horizontal: _railRoom(t), vertical: inset(t)) : EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), inset(t)),
      child: SizedBox(
        width: upright ? null : double.infinity,
        child: Semantics(
          container: true,
          label: 'Navigation',
          explicitChildNodes: true,
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: Container(
                padding: EdgeInsets.all(gap + t.len('glacier-hairline')),
                foregroundDecoration: BoxDecoration(border: Border.all(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline')), borderRadius: radius),
                decoration: BoxDecoration(color: t.colorOf('color-mix(in srgb, var(--glacier-bg) 82%, transparent)'), borderRadius: radius),
                child: upright
                    // Ghost.md's dock as it is there: head to foot, a step between its rings.
                    ? Column(mainAxisSize: MainAxisSize.min, spacing: gap, children: rings)
                    : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: rings),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One ring of the pill (the dock's `DockRing`): quiet, or filled with ink when it is the one shown. One with a
/// menu of its own ([NavItem.menu]) hangs it over itself.
class _Ring extends StatefulWidget {
  const _Ring({super.key, required this.item, required this.shown, required this.onPressed, this.upright = false});
  final NavItem item;
  final bool shown;

  /// In a pill stood up at the window's right: its words keep their right edge on the ring's, inside the window.
  final bool upright;
  final VoidCallback onPressed;

  @override
  State<_Ring> createState() => _RingState();
}

class _RingState extends State<_Ring> {
  /// Its menu is open, and the rows it opened with: kept while it closes, so it does not empty as it goes.
  bool _open = false;
  List<Widget> _rows = const [];

  /// A press with the other button, or a long press where there is no other button.
  void _showMenu() {
    final rows = widget.item.menu?.call(context) ?? const <Widget>[];
    if (rows.isEmpty) return;
    setState(() {
      _rows = rows;
      _open = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final round = _round(context);
    if (widget.item.menu == null) return round;
    // A small list by the ring it came from, its right edge on the ring's, no wider than its longest row needs and
    // no taller than the window has room for: more rows than that scroll inside it.
    return GlacierMenu(
      open: _open,
      onOpenChange: (open) {
        if (!open && _open) setState(() => _open = false);
      },
      // Over the ring where the pill is laid along; beside it, towards the pane, where the pill is stood up and
      // over the ring is another ring.
      placement: widget.upright ? Placement.leftEnd : Placement.topEnd,
      ariaLabel: widget.item.label,
      style: GlacierMenuStyle(
        minWidth: t.lenOf('12.5rem'),
        maxWidth: t.lenOf('15rem'),
        maxHeight: math.max(t.lenOf('10rem'), math.min(t.lenOf('26rem'), MediaQuery.sizeOf(context).height - t.len('app-ring') - t.lenOf('7rem'))),
      ),
      trigger: (context, trigger) => round,
      children: _rows,
    );
  }

  Widget _round(BuildContext context) {
    final t = context.tokens;
    final item = widget.item;
    final shown = widget.shown;
    final onPressed = widget.onPressed;
    final onMenu = item.menu == null ? null : _showMenu;
    final ring = t.len('app-ring');
    final size = shown ? 18.0 : t.lenOf('1.15rem');
    final stroke = shown ? 2.2 : 2.0;
    final ink = shown ? t.color('app-paper') : t.color('glacier-text');
    return HoverTip(
      message: item.label,
      end: widget.upright,
      child: GestureDetector(
       behavior: HitTestBehavior.translucent,
       onSecondaryTapUp: onMenu == null ? null : (_) => onMenu(),
       onLongPress: onMenu,
       child: GlacierPressable(
        onPressed: onPressed,
        semanticLabel: item.label,
        builder: (context, state) {
          final mark = AppIcon(item.icon, size: size, strokeWidth: stroke, color: ink, wash: false);
          final Widget round = shown
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
                      child: mark,
                    ),
                  ),
                )
              : GlacierFocusRing(
                  visible: state.focused,
                  child: Container(
                    width: ring,
                    height: ring,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: t.color(state.hovered || state.pressed ? 'app-paper-2' : 'glacier-bg'),
                      shape: BoxShape.circle,
                      border: Border.all(color: t.color('glacier-border-strong'), width: t.len('app-line')),
                    ),
                    child: mark,
                  ),
                );
          if (item.count <= 0) return round;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              round,
              PositionedDirectional(
                end: -5,
                top: -5,
                child: ExcludeSemantics(
                  child: Container(
                    // Large enough to read at a glance, and red: a count is the one thing on the pill that is not
                    // the page's own ink (Matt, 2026-11-14: "the badge is too small and it doesn't look like it's
                    // the right color make it red"). It was fourteen across in the page's ink, which on the ring
                    // that is shown (itself ink) read as a hole in it. A line of the page's ground round it keeps
                    // it off the ring in either case.
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: t.colorOf('#dd3a30'), borderRadius: BorderRadius.circular(10), border: Border.all(color: t.color('glacier-bg'), width: 2)),
                    child: Text(item.count > 99 ? '99+' : '${item.count}', style: t.textAt(11, weight: 'bold', height: 1.15, color: const Color(0xFFFFFFFF))),
                  ),
                ),
              ),
            ],
          );
        },
       ),
      ),
    );
  }
}

/// A ring's words while the pointer rests on it (the dock's `DockTip`): over the ring here, since the pill lies
/// along the sidebar's foot and beside a ring is another ring.
///
/// Any button that is a picture alone can wear one ([below]: under it, for one near the top of its column; [end]:
/// its right edge on the button's, for one at its column's right).
class HoverTip extends StatefulWidget {
  const HoverTip({super.key, required this.message, required this.child, this.below = false, this.end = false});
  final String message;
  final Widget child;
  final bool below;
  final bool end;

  @override
  State<HoverTip> createState() => _HoverTipState();
}

class _HoverTipState extends State<HoverTip> {
  final OverlayPortalController _portal = OverlayPortalController(debugLabel: 'navigation tip');
  final LayerLink _link = LayerLink();
  Timer? _waiting;

  @override
  void dispose() {
    _waiting?.cancel();
    super.dispose();
  }

  void _enter() {
    _waiting?.cancel();
    _waiting = Timer(const Duration(milliseconds: 450), () {
      if (mounted && Overlay.maybeOf(context) != null) _portal.show();
    });
  }

  void _exit() {
    _waiting?.cancel();
    if (_portal.isShowing) _portal.hide();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
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
              targetAnchor: widget.below ? (widget.end ? Alignment.bottomRight : Alignment.bottomCenter) : (widget.end ? Alignment.topRight : Alignment.topCenter),
              followerAnchor: widget.below ? (widget.end ? Alignment.topRight : Alignment.topCenter) : (widget.end ? Alignment.bottomRight : Alignment.bottomCenter),
              offset: Offset(0, widget.below ? t.space(2) : -t.space(3)),
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: Container(
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
