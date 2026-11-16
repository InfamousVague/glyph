import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../app_state.dart';
import '../backgrounds.dart';
import '../looks.dart';

/// A look (lib/looks.dart) drawn small, in its own colours whatever the page around it is: its page, a bubble from
/// someone else and one of yours, as a conversation in that look would show them. The look's rules are laid over a
/// theme of its own, so the preview is the look itself and not a guess at it.
class LookPreview extends StatelessWidget {
  const LookPreview({super.key, required this.look, this.theme, this.bubble = 'theme', this.width});
  final Look look;

  /// 'light' or 'dark' for a look with both halves; the page's own where null. A look with one is always drawn in it.
  final String? theme;

  /// Your bubble's colour (lib/backgrounds.dart's ids): the look's own unless said.
  final String bubble;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final outer = context.tokens;
    final attrs = look.attrs(platform: outer.attrs['platform'] ?? 'mobile', theme: theme ?? (outer.isDark ? 'dark' : 'light'));
    return GlacierTheme(
      sheet: outer.sheet,
      attrs: attrs,
      typography: outer.typography,
      child: Builder(builder: (context) {
        final t = context.tokens;
        final (mine, onMine) = bubbleOf(t, bubble);
        final theirs = theirBubble(t, onBackground: false);
        final page = t.color('glacier-bg');
        final words = t.textAt(t.fontSize('xs'), color: t.color('app-ink'));
        // One line box for every face, so a look in a taller one (Phosphor's mono) is no taller than the rest and the
        // names under the tiles share a baseline.
        final strut = StrutStyle(fontSize: t.fontSize('xs'), height: 1.25, forceStrutHeight: true);
        Widget line(String text, {required bool out}) => Align(
              alignment: out ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                // Tight sides, so the words fit the smallest tile even in Phosphor's mono.
                padding: EdgeInsets.symmetric(horizontal: t.space(1) + 2, vertical: t.space(1)),
                decoration: BoxDecoration(
                  color: out ? mine : theirs,
                  borderRadius: BorderRadius.circular(t.radius('md')),
                  border: out ? (bubbleNeedsRim(mine, page) ? Border.all(color: t.color('app-rule')) : null) : (theirRim(t) ?? (bubbleNeedsRim(theirs, page) ? Border.all(color: t.color('app-rule')) : null)),
                ),
                child: Text(text, maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis, strutStyle: strut, style: out ? words.copyWith(color: onMine) : words),
              ),
            );
        return Container(
          width: width,
          padding: EdgeInsets.all(t.space(1) + 2),
          color: page,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Words short enough for the smallest tile in the widest face (Phosphor's mono cut "Free at 7?" to "Free at").
            line('Free?', out: false),
            SizedBox(height: t.space(1)),
            line('Yes!', out: true),
          ]),
        );
      }),
    );
  }
}

/// Every look offered, each as a small preview with its name under it; the one chosen ringed. Settings › Appearance.
class LookPicker extends StatelessWidget {
  const LookPicker({super.key, required this.app});
  final AppState app;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final chosen = app.look;
    final corner = t.radius('lg');
    final gap = t.space(2);
    final looks = [
      for (final look in Look.values)
        if (look.ready || look == chosen) look,
    ];
    Widget card(Look look, double side) {
      final on = look == chosen;
      // Ghost's preview wears the bubbles Ghost would: yours where Ghost is the look, else white, which choosing Ghost
      // goes back to.
      final bubble = look != Look.ghost ? 'theme' : (chosen == Look.ghost ? app.bubble : 'white');
      return GlacierPressable(
        onPressed: () => app.setLook(look),
        semanticLabel: '${look.label}${on ? ', chosen' : ''}',
        builder: (context, state) => AnimatedScale(
          scale: state.pressed ? 0.95 : 1,
          duration: const Duration(milliseconds: 120),
          child: SizedBox(
            width: side,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(corner),
                  border: Border.all(color: on ? t.color('app-ink') : t.color('app-rule'), width: on ? 2.5 : 1),
                ),
                padding: EdgeInsets.all(on ? 1.5 : 3),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular((corner - 3).clamp(0, corner)),
                  child: LookPreview(look: look, bubble: bubble, width: side),
                ),
              ),
              SizedBox(height: t.space(1)),
              Text(look.label, maxLines: 1, overflow: TextOverflow.ellipsis, strutStyle: StrutStyle(fontSize: t.fontSize('xs'), height: 1.3, forceStrutHeight: true), style: t.textAt(t.fontSize('xs'), weight: on ? 'semibold' : 'regular', color: t.color(on ? 'app-ink' : 'app-ink-2'))),
            ]),
          ),
        ),
      );
    }

    // As many across as fit at 5rem, stretched to fill the row up to 6.25rem each, where fixed 6.25rem tiles left a
    // third of a tile empty at the row's end on a phone.
    return LayoutBuilder(builder: (context, box) {
      final least = t.lenOf('5rem'), most = t.lenOf('6.25rem');
      final across = box.maxWidth.isFinite ? ((box.maxWidth + gap) / (least + gap)).floor().clamp(1, looks.length) : looks.length;
      final side = box.maxWidth.isFinite ? ((box.maxWidth - gap * (across - 1)) / across).floorToDouble().clamp(least, most) : most;
      return Wrap(spacing: gap, runSpacing: t.space(3), children: [for (final look in looks) card(look, side)]);
    });
  }
}
