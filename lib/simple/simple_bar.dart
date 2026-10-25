/// Simple mode's two bottom controls (GHST-105): the bar with its two destinations, Notes and To-dos, and the pair
/// that floats over it, a filled round + and a plain round microphone. Matt, 2026-10-18: "The simple mode in the
/// app is not quite right, it still is a bit complex with the tabs and such, spend a significant amount of time
/// looking into simple apps like todoist and others to build out a clean simple UI". What the simple apps share
/// (Apple Notes, Simplenote, Keep, Todoist, Things, Reminders) is one list, one search, one big + where the thumb
/// is, and two or three destinations along the bottom; nothing of the app's own frame above the list.
///
/// Built apart from the pill of rings every other page has (lib/shell/page_dock.dart): the dock is the advanced
/// app's, a column of everything a page can do; here there are two things to press, and each is drawn as itself.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';

/// Where the simple home page is: the notes, or the to-dos. Kept to the device by the root, never synced: which
/// list a phone was left on is that phone's.
enum SimpleTab { notes, todos }

/// The bar along the foot of the page: Notes and To-dos, an icon and its word each, the current one in the page's
/// ink and the other quiet. It keeps clear of the phone's home bar (`--app-safe-bottom`).
class SimpleBar extends StatelessWidget {
  const SimpleBar({super.key, required this.tab, required this.onTab});

  final SimpleTab tab;
  final ValueChanged<SimpleTab> onTab;

  /// How tall the bar is over the safe area: the room a page under it keeps.
  static double heightOf(Tokens t) => t.space(12) + t.len('glacier-hairline');

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Notes or to-dos',
      child: Container(
        padding: EdgeInsets.only(bottom: t.len('app-safe-bottom')),
        decoration: BoxDecoration(
          color: t.color('glacier-bg'),
          border: Border(top: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline'))),
        ),
        child: SizedBox(
          height: t.space(12),
          child: Row(
            children: [
              Expanded(child: _Destination(tab: SimpleTab.notes, label: 'Notes', icon: Lucide.fileText, current: tab == SimpleTab.notes, onTab: onTab)),
              Expanded(child: _Destination(tab: SimpleTab.todos, label: 'To-dos', icon: Lucide.listChecks, current: tab == SimpleTab.todos, onTab: onTab)),
            ],
          ),
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination({required this.tab, required this.label, required this.icon, required this.current, required this.onTab});

  final SimpleTab tab;
  final String label;
  final LucideIcon icon;
  final bool current;
  final ValueChanged<SimpleTab> onTab;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    return GlacierPressable(
      key: ValueKey('simple-tab-${tab.name}'),
      semanticLabel: label,
      selected: current,
      onPressed: () => onTab(tab),
      builder: (context, state) {
        // The current one in the page's ink; the other quiet, and a shade darker while the pointer rests on it.
        final ink = current ? t.color('app-ink') : (state.hovered || state.pressed ? t.color('app-ink-2') : t.color('app-ink-3'));
        return GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('sm'),
          child: ExcludeSemantics(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AppIcon(icon, size: 22, strokeWidth: current ? 2.2 : 1.9, color: ink),
                SizedBox(height: t.space(1) / 2),
                Text(label, style: t.textAt(xs, weight: current ? 'semibold' : 'medium', color: ink)),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The two round buttons over the bar's end: a plain microphone where the build can hear ([onSpeak]; none, and
/// there is no microphone), and the filled + (Todoist's, Keep's, Apple Notes' compose: the one thing the page is
/// for, where the thumb is). A press on the + makes a note straight away; held, it opens the sheet of everything
/// else the + can make ([onNewLong]).
class SimpleActions extends StatelessWidget {
  const SimpleActions({super.key, required this.onNew, this.onNewLong, this.onSpeak});

  final VoidCallback onNew;
  final VoidCallback? onNewLong;
  final VoidCallback? onSpeak;

  /// How tall the pair stands: the +'s own height. The + is the app's one round control (`--app-ring`), the size of
  /// the dock's and the gear's, and the microphone a step under it (Matt, 2026-10-25: "on simple mode the + and
  /// microphone buttons are far too large"; they were `--glacier-space-12` and `-10`, the ring is `-10` × 0.88).
  static double heightOf(Tokens t) => _plusOf(t);
  static double _plusOf(Tokens t) => t.len('app-ring');
  static double _micOf(Tokens t) => t.len('app-ring') * 0.85;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      spacing: t.space(3),
      children: [
        if (onSpeak != null) _Round(key: const ValueKey('simple-speak'), label: 'Speak a note', icon: Lucide.mic, size: _micOf(t), filled: false, onPressed: onSpeak!),
        _Round(key: const ValueKey('simple-new'), label: 'New note', icon: Lucide.plus, size: _plusOf(t), filled: true, onPressed: onNew, onLongPress: onNewLong),
      ],
    );
  }
}

/// One round button: ink on paper for the +, paper with a hairline for the microphone, each lifted by a shadow so it
/// reads as floating over the list, and dipping a little while pressed (at once under reduced motion).
class _Round extends StatelessWidget {
  const _Round({super.key, required this.label, required this.icon, required this.size, required this.filled, required this.onPressed, this.onLongPress});

  final String label;
  final LucideIcon icon;
  final double size;
  final bool filled;
  final VoidCallback onPressed;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      semanticLabel: label,
      onPressed: onPressed,
      onLongPress: onLongPress,
      builder: (context, state) {
        final ink = filled ? t.color('app-paper') : t.color('app-ink');
        final ground = filled ? t.color('app-ink') : t.color('glacier-surface-raised');
        return GlacierFocusRing(
          visible: state.focused,
          offset: 3,
          color: t.color('app-ink'),
          child: AnimatedScale(
            scale: state.pressed ? 0.94 : 1,
            duration: t.reducedMotion ? Duration.zero : t.duration('glacier-duration-fast'),
            curve: t.curve('glacier-ease-out'),
            child: Container(
              width: size,
              height: size,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ground,
                shape: BoxShape.circle,
                border: filled ? null : Border.all(color: t.color('glacier-border'), width: t.len('glacier-hairline')),
                boxShadow: t.shadow('glacier-shadow-3'),
              ),
              child: AppIcon(icon, size: size * 0.46, strokeWidth: filled ? 2.4 : 2.1, color: ink),
            ),
          ),
        );
      },
    );
  }
}
