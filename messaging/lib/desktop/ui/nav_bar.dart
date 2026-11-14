import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';

/// One place the Mac's navigation pill goes to: one ring.
class DeskNavItem {
  const DeskNavItem({required this.id, required this.icon, required this.label, this.count = 0});
  final String id;
  final LucideIcon icon;

  /// What the ring is read aloud by, and shown by while the pointer rests on it.
  final String label;

  /// A number worn on the ring's corner (how many are archived); nothing for none.
  final int count;
}

/// The navigation pill that floats at the foot of the Mac's sidebar: a new chat, the messages, the archive, Settings
/// (Matt, 2026-11-14: "at the bottom of the desktop sidebar, add a navigation bar floating", then "use the same
/// navigation pill that we use in ghost markdown but horizontal instead of vertical").
///
/// It is Ghost.md's dock (lib/shell/page_dock.dart at the repository's root: `PageDock`, `DockRing`, `DockTip`),
/// laid along where that one stands up: a pill of glass, a step of space round its rings and between them, a
/// hairline round it; each ring `--app-ring` across, the page's colour with a line round it and its mark in the
/// page's ink; the one shown now filled with ink, its mark in paper, as the dock's one filled ring is; a number on a
/// ring's corner as the dock wears one; and a ring's words over it while the pointer rests there, where the dock's
/// come up beside it.
class DeskNavBar extends StatelessWidget {
  const DeskNavBar({super.key, required this.items, required this.active, required this.onSelect});
  final List<DeskNavItem> items;

  /// The id of the item shown now.
  final String active;
  final ValueChanged<String> onSelect;

  /// How far in from the sidebar's foot the pill stands.
  static double inset(Tokens t) => t.space(4);

  /// How much of the list's end the pill stands over, with its room: what the list leaves clear there.
  static double clearance(Tokens t) => t.len('app-ring') + (t.space(2) + t.len('glacier-hairline')) * 2 + inset(t) * 2;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    final radius = BorderRadius.circular(t.radius('full'));
    return Padding(
      padding: EdgeInsets.only(bottom: inset(t)),
      child: Center(
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < items.length; i += 1) ...[
                      if (i > 0) SizedBox(width: gap),
                      _Ring(item: items[i], shown: items[i].id == active, onPressed: () => onSelect(items[i].id)),
                    ],
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

/// One ring of the pill (the dock's `DockRing`): quiet, or filled with ink when it is the one shown.
class _Ring extends StatelessWidget {
  const _Ring({required this.item, required this.shown, required this.onPressed});
  final DeskNavItem item;
  final bool shown;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    final size = shown ? 18.0 : t.lenOf('1.15rem');
    final stroke = shown ? 2.2 : 2.0;
    final ink = shown ? t.color('app-paper') : t.color('glacier-text');
    return _Tip(
      message: item.label,
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
                end: -2,
                top: -2,
                child: ExcludeSemantics(
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: BorderRadius.circular(7), border: Border.all(color: t.color('glacier-bg'), width: 1.5)),
                    child: Text(item.count > 99 ? '99+' : '${item.count}', style: t.textAt(9, weight: 'semibold', height: 1.2, color: t.color('app-paper'))),
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

/// A ring's words while the pointer rests on it (the dock's `DockTip`): over the ring here, since the pill lies
/// along the sidebar's foot and beside a ring is another ring.
class _Tip extends StatefulWidget {
  const _Tip({required this.message, required this.child});
  final String message;
  final Widget child;

  @override
  State<_Tip> createState() => _TipState();
}

class _TipState extends State<_Tip> {
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
              targetAnchor: Alignment.topCenter,
              followerAnchor: Alignment.bottomCenter,
              offset: Offset(0, -t.space(3)),
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
