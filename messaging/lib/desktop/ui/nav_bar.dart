import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../kit/settings_type.dart';

/// One place the Mac's navigation bar goes to.
class DeskNavItem {
  const DeskNavItem({required this.id, required this.icon, required this.label, this.count = 0});
  final String id;
  final LucideIcon icon;
  final String label;

  /// A number worn on the icon's corner (how many are archived); nothing for none.
  final int count;
}

/// The navigation bar that floats at the foot of the Mac's sidebar (Matt, 2026-11-14: "at the bottom of the desktop
/// sidebar, add a navigation bar floating from glacier UI include the new chat button, messages, settings button and
/// archive").
///
/// It is Glacier UI's NavBar, drawn here since this app's copy of the kit has no NavBar of its own to use
/// (GlacierUI, packages/react/src/structures/NavBar, and AppShell's floating bottom bar): a row of items a control's
/// height tall, a step of space between them and two round them; each an icon over its label, quiet until it is the
/// one shown; the one shown marked by a soft pill that slides to it; the bar itself a rounded card off the sidebar's
/// edges by three steps of space, with a hairline round it and a shadow under it.
class DeskNavBar extends StatelessWidget {
  const DeskNavBar({super.key, required this.items, required this.active, required this.onSelect});
  final List<DeskNavItem> items;

  /// The id of the item shown now.
  final String active;
  final ValueChanged<String> onSelect;

  /// How much of the list the bar covers, with its room below: what the list leaves clear at its end.
  static double clearance(Tokens t) => t.lenOf('3rem') + t.space(2) * 2 + t.space(3) * 2;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final at = items.indexWhere((i) => i.id == active);
    final radius = t.lenOf('1.25rem');
    final itemRadius = BorderRadius.circular(t.lenOf('0.75rem'));
    final ink = t.color('app-ink');
    return Padding(
      padding: EdgeInsets.fromLTRB(t.space(3), 0, t.space(3), t.space(3)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.color('app-paper-2'),
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: t.color('app-rule')),
          boxShadow: const [BoxShadow(color: Color(0x47000000), blurRadius: 20, offset: Offset(0, 8)), BoxShadow(color: Color(0x1F000000), blurRadius: 3, offset: Offset(0, 1))],
        ),
        child: Padding(
          padding: EdgeInsets.all(t.space(2)),
          child: SizedBox(
            height: t.lenOf('3rem'),
            child: Stack(children: [
              // The pill under the item shown: one shape that slides from where it was.
              if (at >= 0)
                AnimatedAlign(
                  alignment: Alignment(items.length <= 1 ? 0 : -1 + 2 * at / (items.length - 1), 0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  child: FractionallySizedBox(
                    widthFactor: 1 / items.length,
                    heightFactor: 1,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: t.space(1) / 2),
                      child: DecoratedBox(decoration: BoxDecoration(color: ink.withValues(alpha: 0.12), borderRadius: itemRadius)),
                    ),
                  ),
                ),
              Row(children: [
                for (final item in items)
                  Expanded(
                    child: GlacierPressable(
                      onPressed: () => onSelect(item.id),
                      semanticLabel: item.label,
                      builder: (context, state) {
                        final shown = item.id == active;
                        final colour = shown ? ink : t.color(state.pressed || state.hovered ? 'app-ink' : 'app-ink-3');
                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: t.space(1) / 2),
                          child: DecoratedBox(
                            // The one shown has the pill, not the hover's wash.
                            decoration: BoxDecoration(color: !shown && (state.pressed || state.hovered) ? ink.withValues(alpha: 0.06) : const Color(0x00000000), borderRadius: itemRadius),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Stack(clipBehavior: Clip.none, children: [
                                AppIcon(item.icon, size: 18, color: colour, wash: shown),
                                if (item.count > 0)
                                  Positioned(
                                    left: 12,
                                    top: -6,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      constraints: const BoxConstraints(minWidth: 15),
                                      decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(8)),
                                      child: Text(item.count > 99 ? '99+' : '${item.count}', textAlign: TextAlign.center, style: pageText(t, 9.5, weight: 'bold', color: t.color('app-paper'), height: 1.2)),
                                    ),
                                  ),
                              ]),
                              const SizedBox(height: 3),
                              Text(item.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), weight: shown ? 'semibold' : 'medium', color: colour, height: 1.2)),
                            ]),
                          ),
                        );
                      },
                    ),
                  ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
