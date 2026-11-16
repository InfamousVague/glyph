import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../kit/settings_type.dart';

/// The box a message is written in, everywhere one is: a conversation of texts (lib/ui/thread.dart) and a chat on
/// Telegram or Bluesky (lib/ui/inbox_ui.dart), so the two read and work the same (Matt, 2026-11-15: "Also use the
/// same composer for telegram").
///
/// Empty, [plus] sits at its start and [ends] at its end, on the words' line; once there are words ([typing]) they
/// take the whole width and the buttons slide into a row under them: [plus] at its start, [below] at its end (Matt,
/// 2026-11-15: "Put the plus symbol inside thr compose input and animate them below when typijg just like this
/// screenshot"). [field] keeps its place in the tree whichever way it is laid out, so the keyboard stays up.
class ComposerBox extends StatelessWidget {
  const ComposerBox({super.key, required this.field, required this.typing, this.plus, this.ends = const [], this.below = const []});
  final Widget field;
  final bool typing;
  final Widget? plus;
  final List<Widget> ends;
  final List<Widget> below;

  static const move = Duration(milliseconds: 200);

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final plus = this.plus;
    Widget slot(bool shown, Widget child) => ClipRect(child: AnimatedSize(duration: move, curve: Curves.easeOutCubic, child: shown ? child : const SizedBox(width: 0)));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: t.space(1)),
      child: Container(
        constraints: BoxConstraints(minHeight: t.lenOf('2.75rem')),
        padding: EdgeInsets.all(t.lenOf('0.25rem')),
        decoration: BoxDecoration(color: t.color('app-paper-2'), borderRadius: BorderRadius.circular(t.lenOf('1.375rem'))),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            slot(!typing && plus != null, plus ?? const SizedBox(width: 0)),
            Expanded(
              child: AnimatedPadding(
                duration: move,
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(left: !typing && plus != null ? t.space(1) : t.space(3), right: typing || ends.isEmpty ? t.space(3) : 0),
                child: field,
              ),
            ),
            slot(!typing, Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: ends)),
          ]),
          ClipRect(
            child: AnimatedSize(
              duration: move,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !typing
                  ? const SizedBox(width: double.infinity)
                  : TweenAnimationBuilder<double>(
                      key: const ValueKey('composer-tools'),
                      tween: Tween(begin: 0, end: 1),
                      duration: move,
                      curve: Curves.easeOutCubic,
                      builder: (context, v, child) => Opacity(opacity: v, child: Transform.translate(offset: Offset(0, (1 - v) * -8), child: child)),
                      child: Padding(
                        padding: EdgeInsets.only(top: t.space(1)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [?plus, const Spacer(), ...below]),
                      ),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// The words' line of a [ComposerBox]: [hint] while it is empty, the words centred on the buttons' middle.
TextStyle composerTextStyle(Tokens t) => pageText(t, t.fontSize('md'), color: t.color('app-ink'), height: 1.3);
StrutStyle composerStrutStyle(Tokens t) => StrutStyle.fromTextStyle(composerTextStyle(t), forceStrutHeight: true, leadingDistribution: TextLeadingDistribution.even);
const composerLeading = TextHeightBehavior(leadingDistribution: TextLeadingDistribution.even);
