/// Things to say: the card the recorder shows while the microphone waits for the first word (Matt: "when I open the
/// AI page, I should see a list of suggested prompts / commands / etc but don't see that card anymore"). A port of
/// `src/app/capture/SayCard.tsx` and SayCard.module.css.
///
/// Three short groups, one line each way of saying it (capture/tips.dart `starters`): how to shape the note as it is
/// said, where to send it, and what to ask the AI to do with it. The one-line tips that come in a pause teach the
/// same things one at a time once talking has begun; this is the whole of it at once, for the moment before, when a
/// person is deciding what to say. It goes the moment words arrive, and it takes no taps: the recorder is listening,
/// and saying a line is the way to use it. One word at its foot, where a meeting can be recorded
/// (capture/meeting.dart): "Meeting instead", for the day Speak was pressed for a meeting from habit.
///
/// The card is shown by a recorder a person opened; it opens no microphone itself.
///
/// What differs: the short window's rule (`@media (max-height: 560px)`) is read from `MediaQuery`'s height. Nothing
/// else.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../app/widgets.dart';
import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../tips.dart';
import 'capture_cards.dart' show CardEyebrow, EnterFrom;

class SayCard extends StatelessWidget {
  const SayCard({super.key, required this.starters, this.onMeeting});

  final Starters starters;
  final VoidCallback? onMeeting;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // @media (max-height: 560px) {
    //   .card { gap: var(--glacier-space-1); padding-block: var(--glacier-space-2); }
    //   .title, .line:nth-child(n + 2) { display: none; }
    // }
    final short = MediaQuery.sizeOf(context).height <= 560;
    final xs = t.fontSize('xs');
    final sm = t.fontSize('sm');
    final ink3 = t.color('app-ink-3');
    final groups = <({String heading, LucideIcon icon, List<Tip> tips})>[
      (heading: 'To shape it', icon: Lucide.listTree, tips: starters.shape),
      (heading: 'To send it somewhere', icon: Lucide.send, tips: starters.send),
      (heading: 'To ask the AI', icon: Lucide.bot, tips: starters.ask),
    ];

    Widget group(({String heading, LucideIcon icon, List<Tip> tips}) group) {
      final tips = short ? group.tips.take(1).toList() : group.tips;
      // .group { display: grid; gap: var(--glacier-space-1); }
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // .heading {
          //   display: flex;
          //   align-items: center;
          //   gap: 0.4em;
          //   margin: 0;
          //   font-size: var(--glacier-font-size-xs);
          //   font-weight: var(--glacier-font-weight-semibold);
          //   color: var(--app-ink-3);
          // }
          Row(
            children: [
              AppIcon(group.icon, size: 13, strokeWidth: 2.2, color: ink3),
              SizedBox(width: 0.4 * xs),
              Flexible(child: ExactLines.of(Text(group.heading, style: t.textAt(xs, weight: 'semibold', color: ink3)), normal: true, dpr: t.css.lineDpr)),
            ],
          ),
          SizedBox(height: t.space(1)),
          // .lines { list-style: none; margin: 0; padding: 0; display: grid; gap: 2px; }
          for (var i = 0; i < tips.length; i += 1) ...[
            if (i > 0) const SizedBox(height: 2),
            // .line {
            //   font-size: var(--glacier-font-size-sm);
            //   line-height: 1.35;
            //   color: var(--app-ink-3);
            //   overflow-wrap: anywhere;
            // }
            // .say { color: var(--app-ink); font-weight: var(--glacier-font-weight-semibold); }
            // The line as tall as the page's (18.45px at this size, where the engine's is 18): four of them stood the
            // card's foot five device pixels short.
            ExactLines.of(
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '“${tips[i].say}”', style: t.textAt(sm, weight: 'semibold', color: t.color('app-ink'), height: 1.35)),
                    TextSpan(text: ' ${tips[i].does}'),
                  ],
                ),
                style: t.textAt(sm, color: ink3, height: 1.35),
              ),
            ),
          ],
        ],
      );
    }

    final rows = <Widget>[
      // .title { composes: app-eyebrow from global; }
      if (!short) const CardEyebrow('Things to say'),
      for (final each in groups)
        if (each.tips.isNotEmpty) group(each),
      if (onMeeting != null)
        // One word at the foot, for the day Speak was pressed for a meeting: quieter than the lines, since it is a way out.
        // .foot { margin: 0; font-size: var(--glacier-font-size-sm); color: var(--app-ink-3); }
        // .footWord { font-size: inherit; }
        Align(
          alignment: Alignment.centerLeft,
          heightFactor: 1,
          child: AppWord(
            onPressed: onMeeting,
            child: Builder(builder: (context) => Text('Meeting instead', style: Tokens.resized(DefaultTextStyle.of(context).style, sm))),
          ),
        ),
    ];

    final pop = t.transition('app-pop');
    final gap = SizedBox(height: short ? t.space(1) : t.space(3));
    // .card {
    //   flex: none;
    //   display: grid;
    //   gap: var(--glacier-space-3);
    //   margin: 0 0 var(--glacier-space-3);
    //   padding: var(--glacier-space-3) var(--glacier-space-4);
    //   border: var(--glacier-hairline) solid var(--app-rule);
    //   border-radius: var(--glacier-radius-lg);
    //   background: var(--app-paper-2);
    //   animation: say-in var(--app-pop) both;
    // }
    // @keyframes say-in { from { opacity: 0; transform: translateY(6px) scale(0.98); } }
    return Padding(
      padding: EdgeInsets.only(bottom: t.space(3)),
      child: Semantics(
        container: true,
        label: 'Things to say',
        child: EnterFrom(
          duration: pop.duration,
          curve: pop.curve,
          dy: 6,
          scale: 0.98,
          child: Container(
            padding: EdgeInsets.symmetric(vertical: short ? t.space(2) : t.space(3), horizontal: t.space(4)),
            decoration: BoxDecoration(
              color: t.color('app-paper-2'),
              border: Border.all(color: t.color('app-rule'), width: t.len('glacier-hairline')),
              borderRadius: BorderRadius.circular(t.radius('lg')),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rows.length; i += 1) ...[if (i > 0) gap, rows[i]],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
