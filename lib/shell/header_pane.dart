import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../notes/tabs/bar_parts.dart';

/// A header pane over a screen that scrolls under it: `.app-headerPane` of the web app's app.css. Dark glass in the
/// dark and light glass on paper, the page's own colour at two thirds over a blur of whatever runs under it, from
/// the top of the phone: its [child] is padded down by `--app-safe-top`, the notch and the tab bar, so the pane is
/// the glass behind the bar too.
///
/// Under a split window's bar, which is glass of its own across the whole window, the pane's tint starts where the
/// bar ends, so the two are not laid on each other; in the Islands it paints nothing, the capsules carrying their
/// own glass and the page scrolling under them.
///
/// Put it in a [Stack] over the scroller. The wisp at its foot (art/wisp.css) is not drawn here.
class HeaderPane extends StatelessWidget {
  const HeaderPane({super.key, this.child});

  /// The screen's own header under the bar, if it has one.
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final safeTop = t.len('app-safe-top');
    final content = Padding(padding: EdgeInsets.only(top: safeTop), child: child ?? const SizedBox(width: double.infinity));
    final Widget pane;
    if (t.attrs['topbar'] == 'islands') {
      pane = content;
    } else if (t.attrs.containsKey('split')) {
      pane = BarGlass(
        head: true,
        tint: const Color(0x00000000),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned(left: 0, right: 0, top: safeTop, bottom: 0, child: ColoredBox(color: glassTint(t))),
            content,
          ],
        ),
      );
    } else {
      pane = BarGlass(head: true, child: content);
    }
    return Positioned(top: 0, left: 0, right: 0, child: pane);
  }
}

/// The status bar's ground on a screen with no header pane: `.app-statusScrim`, solid paper across the bar and no
/// further, so what scrolls up does not run under the phone's clock. Nothing can be touched through it, and it is
/// nothing where there is no status bar.
class StatusScrim extends StatelessWidget {
  const StatusScrim({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final paper = t.color('glacier-bg');
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: t.len('app-inset-top'),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [paper, paper, paper.withValues(alpha: 0)], stops: const [0, 0.78, 1]),
          ),
        ),
      ),
    );
  }
}
