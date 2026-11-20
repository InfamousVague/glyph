/// The rail (NavStyle.rail; Matt, 2026-11-19: "a navigation rail version of the app. It should include the circles
/// icons like discord and slack does for the different spaces"): a column down the window's left on every page.
/// Home at its head (the conversations), then each circle as its face, as Discord's servers and Slack's workspaces
/// are, with a bar at its edge for the one open and a dot for one with something unread, and a way to start or join
/// one; the app's own places at its foot, the pill's rings with their counts and their menus. lib/ui/shell.dart puts
/// it at the window's left and answers it.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/lucide_more.dart';
import '../circles/circles.dart';
import '../kit/semantic_colors.dart';
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
  static double width(Tokens t) => t.len('app-ring') + t.space(3) * 2;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final gap = t.space(2);
    final rule = Container(width: t.len('app-ring') * 0.6, height: t.len('app-line'), margin: EdgeInsets.symmetric(vertical: gap), color: t.color('app-rule'));
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
                      padding: EdgeInsets.only(bottom: gap),
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

/// A circle in the rail: its face, a bar at the rail's edge (tall for the one open, a dot for one with something
/// unread), and a red count where someone mentioned you, as Discord marks its servers.
class _CircleRing extends StatelessWidget {
  const _CircleRing({super.key, required this.circle, required this.open, required this.onPress, required this.onMenu});
  final Circle circle;
  final bool open;
  final VoidCallback onPress;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ring = t.len('app-ring');
    final circles = Circles.instance;
    final unread = circles.unread(circle);
    final mentions = circles.mentions(circle);
    return HoverTip(
      message: circle.name,
      beside: true,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: (_) => onMenu(),
        onLongPress: onMenu,
        child: GlacierPressable(
          onPressed: onPress,
          semanticLabel: '${circle.name}${unread > 0 ? ', $unread unread' : ''}',
          builder: (context, state) => SizedBox(
            width: NavRail.width(t),
            height: ring,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              // The bar at the rail's edge: tall for the circle open, short under the pointer, a dot for unread.
              Positioned(
                left: 0,
                child: AnimatedContainer(
                  duration: t.duration('glacier-duration-fast'),
                  curve: t.curve('glacier-ease-out'),
                  width: 4,
                  height: open ? ring * 0.7 : (state.hovered ? ring * 0.4 : (unread > 0 ? 8 : 0)),
                  decoration: BoxDecoration(color: t.color('app-ink'), borderRadius: const BorderRadius.horizontal(right: Radius.circular(4))),
                ),
              ),
              GlacierFocusRing(
                visible: state.focused,
                offset: 3,
                color: t.color('app-ink'),
                child: AnimatedScale(
                  scale: state.pressed ? 0.95 : 1,
                  duration: t.duration('glacier-duration-fast'),
                  child: CircleFace.of(circle, size: ring, selected: open),
                ),
              ),
              if (mentions > 0)
                Positioned(
                  right: t.space(3) - 6,
                  bottom: -4,
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
          ),
        ),
      ),
    );
  }
}
