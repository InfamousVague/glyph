import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// `.app-pill` (ink.css): the app's one filled button, ink on paper turned round.
class AppPill extends StatelessWidget {
  const AppPill({super.key, required this.onPressed, required this.child, this.icon, this.haptic = HapticKind.light});

  final VoidCallback? onPressed;
  final Widget child;
  final Widget? icon;
  final HapticKind? haptic;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      haptic: haptic,
      builder: (context, state) {
        final ink = state.disabled ? t.color('app-ink-3') : t.color('app-paper');
        final size = t.fontSize('md');
        return GlacierFocusRing(
          visible: state.focused,
          offset: 3,
          color: t.color('app-ink'),
          child: AnimatedScale(
            // `.app-pill:active { transform: scale(0.98) }`, over the fast duration.
            scale: state.pressed ? 0.98 : 1,
            duration: t.duration('glacier-duration-fast'),
            curve: t.curve('glacier-ease-out'),
            child: Container(
              constraints: BoxConstraints(minHeight: t.space(12)),
              padding: EdgeInsets.symmetric(horizontal: t.space(6)),
              decoration: BoxDecoration(color: state.disabled ? t.color('app-paper-3') : t.color('app-ink'), borderRadius: BorderRadius.circular(t.radius('full'))),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[IconTheme(data: IconThemeData(color: ink, size: size * 1.1), child: icon!), SizedBox(width: t.space(2))],
                  DefaultTextStyle.merge(
                    style: t.text('md', weight: 'semibold', color: ink).copyWith(letterSpacing: -0.005 * size, height: 1.2),
                    child: child,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `.app-word` (app.css): a button that is only its word, muted until pressed.
class AppWord extends StatelessWidget {
  const AppWord({super.key, required this.onPressed, required this.child});

  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return GlacierPressable(
      onPressed: onPressed,
      builder: (context, state) {
        final color = state.disabled
            ? t.color('glacier-text-subtle')
            : state.pressed
                ? t.color('glacier-text')
                : t.color('glacier-text-muted');
        return GlacierFocusRing(
          visible: state.focused,
          radius: t.radius('sm'),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: t.space(12)),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: t.space(2)),
              // As wide as its word, and the word in the middle of its height.
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 1,
                heightFactor: 1,
                child: DefaultTextStyle.merge(style: t.text('md', weight: 'medium', color: color), child: child),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// `.app-eyebrow` (app.css): a small heading in capitals over a section.
class AppEyebrow extends StatelessWidget {
  const AppEyebrow(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.fontSize('xs');
    return Text(
      text.toUpperCase(),
      style: t.text('xs', weight: 'bold', color: t.color('app-ink-3')).copyWith(letterSpacing: t.len('app-tracking-caps', em: size)),
    );
  }
}
