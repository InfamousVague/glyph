/// The walkthrough's first page: what Ghost.md is, in one line and three points. A port of
/// `src/app/guide/pages/Welcome.tsx`, with `.promises`, `.promise` and `.promiseIcon` of `Guide.module.css`.
///
/// The name comes out of smoke like the app's other headlines, and the points pop in after it, one after another,
/// their icons giving a wiggle now and then. There is no picture: the launch screen showed the icon a moment ago.
///
/// What differs: `recordsVoice` is the caller's to say (core/platform.ts reads the phone; the iPhone app records
/// nothing yet and promises lists rather than a voice). The pop-in and the wiggle are worked from one clock here,
/// where the stylesheet has a keyframe animation for each.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/lucide.g.dart';
import '../../art/wisp_text.dart';
import 'parts.dart';

/// `POINTS`, for a phone that records and one that does not.
List<({LucideIcon icon, String label})> welcomePoints({required bool recordsVoice}) => [
  recordsVoice ? (icon: Lucide.mic, label: 'Say it or type it') : (icon: Lucide.listChecks, label: 'Lists, to-dos and boards'),
  (icon: Lucide.fileText, label: 'Plain Markdown files'),
  (icon: Lucide.refreshCw, label: 'The same on every device'),
];

class GuideWelcome extends StatefulWidget {
  const GuideWelcome({super.key, this.recordsVoice = true});
  final bool recordsVoice;

  @override
  State<GuideWelcome> createState() => _GuideWelcomeState();
}

class _GuideWelcomeState extends State<GuideWelcome> with SingleTickerProviderStateMixin {
  /// Milliseconds since the page opened: what every promise's pop-in and wiggle is worked from.
  final ValueNotifier<double> _ms = ValueNotifier(0);
  late final Ticker _ticker = createTicker((elapsed) => _ms.value = elapsed.inMicroseconds / 1000);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = context.tokens.reducedMotion;
    if (_still) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _ticker.start();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ms.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final title = guideTitleStyle(t);
    final points = welcomePoints(recordsVoice: widget.recordsVoice);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          header: true,
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: chWidth(title, 14)), child: guideLines(title, WispText('Welcome to Ghost.md', pace: 16, style: title))),
        ),
        GuideLead('${widget.recordsVoice ? 'Notes you type or say.' : 'Notes you type.'} Plain Markdown, kept on your own devices, the same on every one.'),
        Padding(
          padding: EdgeInsets.only(top: t.space(5)),
          child: Semantics(
            container: true,
            label: 'What Ghost.md does',
            child: Wrap(
              spacing: t.space(2),
              runSpacing: t.space(2),
              children: [
                for (final (index, point) in points.indexed) _Promise(icon: point.icon, label: point.label, index: index, ms: _ms, still: _still),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// `promiseIn`'s easing: past its mark and back.
const Cubic _pop = Cubic(0.2, 1.4, 0.4, 1);

/// How far through `promiseIn` promise [index] is at [ms]: `420ms … both`, delayed `420 + index * 120` ms.
double promiseInAt(double ms, int index) => ((ms - (420 + index * 120)) / 420).clamp(0.0, 1.0);

/// The icon's turn at [ms], in degrees (`wiggle`: 3.2 s, ease-in-out between its stops, from 1.2 s and 0.4 s later
/// for each promise after the first).
double wiggleAt(double ms, int index) {
  final since = ms - (1200 + index * 400);
  if (since < 0) return 0;
  final at = (since % 3200) / 3200;
  const stops = <(double, double)>[(0, 0), (0.86, 0), (0.89, -14), (0.92, 12), (0.95, -6), (1, 0)];
  for (var i = 0; i + 1 < stops.length; i++) {
    final (from, a) = stops[i];
    final (to, b) = stops[i + 1];
    if (at <= to) return a + (b - a) * Curves.easeInOut.transform(((at - from) / (to - from)).clamp(0.0, 1.0));
  }
  return 0;
}

class _Promise extends StatelessWidget {
  const _Promise({required this.icon, required this.label, required this.index, required this.ms, required this.still});
  final LucideIcon icon;
  final String label;
  final int index;
  final ValueListenable<double> ms;
  final bool still;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = t.lenOf('0.3rem');
    final side = t.lenOf('1.9rem');
    final circle = Container(
      width: side,
      height: side,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: t.color('app-ink'), shape: BoxShape.circle),
      child: AppIcon(icon, size: 18, strokeWidth: 2.4, color: t.color('app-paper')),
    );
    final pill = Container(
      padding: EdgeInsets.fromLTRB(pad, pad, t.lenOf('0.9rem'), pad),
      decoration: BoxDecoration(color: t.colorOf('color-mix(in srgb, var(--app-ink) 9%, transparent)'), borderRadius: BorderRadius.circular(999)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          still ? circle : ValueListenableBuilder<double>(valueListenable: ms, child: circle, builder: (context, at, child) => Transform.rotate(angle: wiggleAt(at, index) * math.pi / 180, child: child)),
          SizedBox(width: t.space(2)),
          Flexible(child: Text(label, style: t.textAt(t.fontSize('md'), weight: 'semibold'))),
        ],
      ),
    );
    if (still) return pill;
    return ValueListenableBuilder<double>(
      valueListenable: ms,
      child: pill,
      builder: (context, at, child) {
        final linear = promiseInAt(at, index);
        if (linear >= 1) return child!;
        final eased = _pop.transform(linear);
        return Opacity(
          opacity: eased.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 10 * (1 - eased)), child: Transform.scale(scale: 0.8 + 0.2 * eased, child: child)),
        );
      },
    );
  }
}
