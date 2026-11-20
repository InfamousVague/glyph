/// The rail (NavStyle.rail; Matt, 2026-11-19: "a navigation rail version of the app. It should include the circles
/// icons like discord and slack does for the different spaces"): a column down the window's left on every page.
/// Home at its head (the conversations), then each circle as its face, as Discord's servers and Slack's workspaces
/// are, ringed in their own colour for the one open and dotted for one with something unread, and a way to start or join
/// one; the app's own places at its foot, the pill's rings with their counts and their menus. lib/ui/shell.dart puts
/// it at the window's left and answers it.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/lucide_more.dart';
import '../circles/circles.dart';
import '../kit/semantic_colors.dart';
import '../kit/settings_kit.dart' show settingsHue;
import 'circles/circle_face.dart';
import 'nav_bar.dart';

class NavRail extends StatelessWidget {
  const NavRail({
    super.key,
    required this.circles,
    required this.openCircle,
    required this.home,
    required this.items,
    required this.active,
    required this.onSelect,
    required this.onCircle,
    required this.onCircleMenu,
    required this.onAddCircle,
    this.onFeedback,
  });

  /// The circles, in the order the list has them.
  final List<Circle> circles;

  /// The seed of the circle open, or null.
  final String? openCircle;

  /// The ring at its head: Home, the conversations.
  final NavItem home;

  /// The rings at its foot.
  final List<NavItem> items;

  /// The ring shown now ('messages' for Home); none while a circle is open.
  final String active;
  final ValueChanged<String> onSelect;
  final ValueChanged<Circle> onCircle;
  final ValueChanged<Circle> onCircleMenu;
  final VoidCallback onAddCircle;

  /// Share feedback, as a ring just above Settings (Matt, 2026-11-20: "on mobile move the share feedback button just
  /// above the settings cog in the navigation rail"); none where it is somewhere else (the Mac's title strip).
  final VoidCallback? onFeedback;

  /// How wide it is: a ring and room round it.
  static double width(Tokens t) => t.len('app-rail-ring') + t.space(3) * 2;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final gap = t.space(2);
    final rule = Container(width: t.len('app-rail-ring') * 0.6, height: t.len('app-line'), margin: EdgeInsets.symmetric(vertical: gap), color: t.color('app-rule'));
    return Semantics(
      container: true,
      label: 'Navigation',
      explicitChildNodes: true,
      child: ColoredBox(
        color: t.color('glacier-bg'),
        child: Padding(
          padding: EdgeInsets.only(left: pad.left, top: pad.top + t.space(3), bottom: pad.bottom + t.space(3)),
          child: Column(children: [
            NavRing(key: const ValueKey('rail-home'), item: home, shown: active == home.id, onPressed: () => onSelect(home.id)),
            rule,
            Expanded(
              child: ListView(
                key: const PageStorageKey('rail-circles'),
                padding: EdgeInsets.zero,
                children: [
                  for (final c in circles)
                    Padding(
                      // Each a little apart: the halo's room round each face is most of the gap already.
                      padding: EdgeInsets.only(bottom: t.space(1)),
                      child: _CircleRing(key: ValueKey('rail-circle-${c.seed}'), circle: c, open: c.seed == openCircle, onPress: () => onCircle(c), onMenu: () => onCircleMenu(c)),
                    ),
                  Center(
                    child: NavRing(
                      key: const ValueKey('rail-add-circle'),
                      item: const NavItem(id: 'add-circle', icon: LucideMore.circlePlus, label: 'New or join a circle'),
                      shown: false,
                      onPressed: onAddCircle,
                    ),
                  ),
                ],
              ),
            ),
            rule,
            Column(mainAxisSize: MainAxisSize.min, spacing: gap, children: [
              for (final item in items) ...[
                if (item.id == 'settings' && onFeedback != null)
                  NavRing(
                    key: const ValueKey('share-feedback'),
                    item: const NavItem(id: 'feedback', icon: LucideMore.messageSquareWarning, label: 'Share feedback'),
                    shown: false,
                    onPressed: onFeedback!,
                  ),
                NavRing(key: ValueKey('rail-${item.id}'), item: item, shown: item.id == active, onPressed: () => onSelect(item.id)),
              ],
            ]),
          ]),
        ),
      ),
    );
  }
}

/// A circle in the rail: its face, ringed in its own colour (Matt, 2026-11-20: "the hover and click indicator on the
/// rail is too similar to discords, tweak it a bit to make it our own"). Not Discord's bar at the rail's edge: a halo
/// round the face itself, a little apart from it, in the circle's colour. Under the pointer the face lifts and a faint
/// halo comes; the circle open has it whole, an orbit round its face; one with something unread wears a dot at its
/// shoulder; and a red count where someone mentioned you.
class _CircleRing extends StatelessWidget {
  const _CircleRing({super.key, required this.circle, required this.open, required this.onPress, required this.onMenu});
  final Circle circle;
  final bool open;
  final VoidCallback onPress;
  final VoidCallback onMenu;

  /// The gap between the face and its halo, and the halo's width.
  static const gap = 3.0, halo = 2.0;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-rail-ring');
    final circles = Circles.instance;
    final unread = circles.unread(circle);
    final mentions = circles.mentions(circle);
    final fast = t.duration('glacier-duration-fast');
    final ease = t.curve('glacier-ease-out');
    return HoverTip(
      message: circle.name,
      beside: true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (_) => onMenu(),
        onLongPress: onMenu,
        child: GlacierPressable(
          onPressed: onPress,
          semanticLabel: '${circle.name}${unread > 0 ? ', $unread unread' : ''}${open ? ', open' : ''}',
          builder: (context, state) {
            final lit = open || state.hovered;
            return SizedBox(
              width: NavRail.width(t),
              height: ring + (gap + halo) * 2,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
                // The halo, in the circle's own colour: whole round the one open, faint under the pointer.
                GlacierScope(
                  attrs: {'hue': circle.hue},
                  child: Builder(builder: (context) {
                    final hue = settingsHue(context.tokens);
                    return AnimatedContainer(
                      key: ValueKey('rail-halo-${circle.seed}'),
                      duration: fast,
                      curve: ease,
                      width: ring + (gap + halo) * 2,
                      height: ring + (gap + halo) * 2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: hue.withValues(alpha: open ? 1 : (state.hovered ? 0.35 : 0)), width: halo),
                      ),
                    );
                  }),
                ),
                GlacierFocusRing(
                  visible: state.focused,
                  offset: gap + halo + 2,
                  color: t.color('app-ink'),
                  child: AnimatedScale(
                    scale: state.pressed ? 0.94 : (lit && !open ? 1.05 : 1),
                    duration: fast,
                    curve: ease,
                    child: CircleFace.of(circle, size: ring, selected: open, ringed: false),
                  ),
                ),
                // Something unread there: a dot at the face's shoulder, while no mention says more.
                if (unread > 0 && mentions == 0 && !open)
                  Positioned(
                    top: gap,
                    right: (NavRail.width(t) - ring) / 2 - 1,
                    child: ExcludeSemantics(
                      child: Container(
                        key: ValueKey('rail-unread-${circle.seed}'),
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(color: t.color('app-ink'), shape: BoxShape.circle, border: Border.all(color: t.color('glacier-bg'), width: 2)),
                      ),
                    ),
                  ),
                if (mentions > 0)
                  Positioned(
                    right: t.space(3) - 6,
                    bottom: 0,
                    child: ExcludeSemantics(
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: t.danger, borderRadius: BorderRadius.circular(11), border: Border.all(color: t.color('glacier-bg'), width: 2)),
                        child: Text(mentions > 99 ? '99+' : '$mentions', style: t.textAt(12, weight: 'bold', height: 1.15, color: const Color(0xFFFFFFFF))),
                      ),
                    ),
                  ),
              ]),
            );
          },
        ),
      ),
    );
  }
}
