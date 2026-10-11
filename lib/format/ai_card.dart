/// The AI card: one face for the model at work, wherever it works. A port of `src/app/format/AiCard.tsx` and
/// `AiCard.module.css`.
///
/// Matt: "highlight the local AI part of this, making sure the app can be run totally without a server; a better,
/// consistent AI card that renders when it's thinking, and it should render things like real phone hardware usage".
/// So one card, opened from the strip under a note's header while a run is on (ai/ai_strip.dart): the model and its
/// size on disk, what it is doing and how fast, the little reader while nothing has arrived yet, and the phone
/// underneath it - the cores it runs on, the memory it holds, the battery it draws on, and, from native generation
/// 14, the engine's own readings every tick: its memory, its share of the cores, the heat. "On this phone" is the
/// point, and the card says so.
///
/// Three sources, by what is there. The engine's readings come with each progress report (`hardware`); the app
/// reads cores, memory class and the battery itself (format/device_facts.dart), so an older binary still shows the
/// phone; and what neither knows is left out rather than guessed.
///
/// What differs: the page's `useDeviceFacts()` is [facts], handed in by whoever draws the card, since a
/// `DeviceFactsController` is made once with the phone's cores and memory and listened to (device_facts.dart). With
/// [inStrip] the card is drawn as the strip's own stylesheet redraws it (AiStrip.module.css `.card > section`): no
/// edge, no ground, the strip's margins.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../ai/backend.dart';
import '../ai/words.dart' show clock, pace;
import '../sheet/css.dart' show snapBorder;
import 'device_facts.dart';
import 'thinking.dart';

/// See the header (`AiCard`, `AiCardProps`).
class AiCard extends StatefulWidget {
  const AiCard({
    super.key,
    required this.model,
    required this.phase,
    required this.doing,
    required this.promptTokens,
    required this.promptTokensDone,
    required this.outputTokens,
    required this.tokensPerSecond,
    required this.elapsedMs,
    this.hardware,
    this.facts = const DeviceFacts(cores: null, memoryGb: null, battery: null),
    this.inStrip = false,
  });

  final String model;
  final Phase phase;

  /// "Formatting", "Summarizing": the verb for what the model is doing.
  final String doing;
  final int promptTokens;
  final int promptTokensDone;
  final int outputTokens;
  final double tokensPerSecond;
  final num elapsedMs;
  final Hardware? hardware;

  /// What the app itself knows of the phone (`useDeviceFacts`).
  final DeviceFacts facts;

  /// Drawn inside the strip, under its line.
  final bool inStrip;

  @override
  State<AiCard> createState() => _AiCardState();
}

class _AiCardState extends State<AiCard> with TickerProviderStateMixin {
  // animation: card-in 240ms var(--glacier-ease-out) both;
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 240));
  // .line { animation: breathe 1.8s ease-in-out infinite; }
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // @media (prefers-reduced-motion: reduce) { .card, .line { animation: none; } }
    if (context.tokens.reducedMotion) {
      _enter.value = 1;
    } else {
      _enter.forward();
      _breath.repeat();
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final w = widget;
    final facts = w.facts;
    final hardware = w.hardware;
    final spec = modelSpec(w.model);
    final cores = hardware?.cores ?? facts.cores;
    final threads = hardware?.threads;
    final busy = hardware != null && cores != null && cores != 0 ? cpuShare(hardware.cpuPercent, cores) : null;
    final memoryGb = facts.memoryGb;
    final num? memoryTotal = hardware?.totalBytes ?? (memoryGb != null && memoryGb != 0 ? memoryGb * 1e9 : null);
    final memoryUsed = hardware?.rssBytes;

    final String line;
    if (w.phase == Phase.loading) {
      line = 'Loading ${modelName(w.model)}.';
    } else if (w.phase == Phase.prefill) {
      line = w.promptTokens != 0 ? 'Reading the note, ${w.promptTokensDone} of ${w.promptTokens}.' : 'Reading the note.';
    } else if (w.phase == Phase.generating) {
      line = '${w.doing}, ${pace(w.tokensPerSecond)}, ${clock(w.elapsedMs)}.';
    } else {
      line = '${w.doing}.';
    }

    final md = t.fontSize('md'), sm = t.fontSize('sm'), xs = t.fontSize('xs');
    final ink = t.color('app-ink'), ink2 = t.color('app-ink-2'), ink3 = t.color('app-ink-3');
    final battery = facts.battery;
    final tempC = hardware?.tempC;
    final meters = <Widget>[
      if (cores != null && cores != 0)
        _Meter(label: 'Cores', value: threads != null && threads != 0 ? '$threads of $cores' : '$cores', share: threads != null && threads != 0 ? threads / cores : null),
      // Loading is one report with no tick behind it, so its CPU figure would be stale: not shown until the model
      // reads.
      if (busy != null && hardware != null && w.phase != Phase.loading) _Meter(label: 'CPU', value: '${_round(hardware.cpuPercent)}%', share: busy),
      if (memoryTotal != null && memoryTotal != 0)
        _Meter(
          label: 'Memory',
          value: memoryUsed != null && memoryUsed != 0 ? '${gb(memoryUsed)} of ${gb(memoryTotal.round())}' : gb(memoryTotal.round()),
          share: memoryUsed != null && memoryUsed != 0 ? (memoryUsed / memoryTotal).clamp(0, 1).toDouble() : null,
        ),
      if (tempC != null) _Meter(label: 'Heat', value: '${_round(tempC)} °C', share: heatShare(tempC)),
      if (battery != null) _Meter(label: 'Battery', value: '${_round(battery.level * 100)}%${battery.charging ? ', charging' : ''}', share: battery.level),
      if (w.phase == Phase.generating && w.outputTokens != 0) _Meter(label: 'Written', value: '${w.outputTokens} tokens', share: null),
    ];

    final reader = t.lenOf('4.5rem');
    // .title { display: flex; flex-wrap: wrap; align-items: baseline;
    //   gap: var(--glacier-space-1) var(--glacier-space-3); margin: 0; font-size: var(--glacier-font-size-md); }
    final title = Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: t.space(3),
      runSpacing: t.space(1),
      children: [
        // .model { font-weight: var(--glacier-font-weight-semibold); color: var(--app-ink); }
        Text(
          spec?.name ?? modelName(w.model),
          style: t.textAt(md, weight: 'semibold', color: ink),
        ),
        // .size { font-size: var(--glacier-font-size-sm); color: var(--app-ink-3); }
        if (spec != null) Text(gb(spec.bytes), style: t.textAt(sm, color: ink3)),
        // The point of it, said once, in a small pill of ink.
        // .local { font-size: var(--glacier-font-size-xs); font-weight: var(--glacier-font-weight-semibold);
        //   letter-spacing: var(--app-tracking-caps-close); text-transform: uppercase; padding: 0.1em 0.6em;
        //   border-radius: 999px; background: var(--app-ink); color: var(--app-paper); }
        DecoratedBox(
          decoration: ShapeDecoration(color: ink, shape: const StadiumBorder()),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: xs * 0.6, vertical: xs * 0.1),
            child: Text(
              'ON THIS PHONE',
              semanticsLabel: 'On this phone',
              style: t.textAt(
                xs,
                weight: 'semibold',
                color: t.color('app-paper'),
                tracking: t.len('app-tracking-caps-close', em: xs),
              ),
            ),
          ),
        ),
      ],
    );

    // .line { margin: 0; font-size: var(--glacier-font-size-sm); line-height: var(--glacier-leading-sm);
    //   color: var(--app-ink-2); animation: breathe 1.8s ease-in-out infinite; }
    // @keyframes breathe { 50% { opacity: 0.45; } }
    final words = AnimatedBuilder(
      animation: _breath,
      builder: (context, child) => Opacity(opacity: _breath.isAnimating ? breathing(_breath.value, 0.45) : 1, child: child),
      child: Semantics(
        liveRegion: true,
        child: Text(
          line,
          key: const ValueKey<String>('ai-card-line'),
          style: t.text('sm', color: ink2),
        ),
      ),
    );

    // .body { flex: 1; min-inline-size: 0; display: flex; flex-direction: column; gap: var(--glacier-space-2); }
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        title,
        SizedBox(height: t.space(2)),
        words,
        if (meters.isNotEmpty) ...[SizedBox(height: t.space(2)), _Meters(meters)],
        SizedBox(height: t.space(2)),
        // .foot { ... font-size: var(--glacier-font-size-xs); color: var(--app-ink-3); }
        Text('Nothing leaves the phone.', style: t.textAt(xs, color: ink3)),
      ],
    );

    // .card { display: flex; gap: var(--glacier-space-4);
    //   margin: var(--glacier-space-2) var(--app-gutter) var(--glacier-space-3); padding: var(--glacier-space-4);
    //   border-radius: var(--glacier-radius-lg); background: var(--app-paper-2);
    //   border: var(--glacier-hairline) solid var(--app-rule); }
    // The AI card draws its own margins for a page; here it is inside a strip:
    // .card > section { margin: var(--glacier-space-2) var(--glacier-space-2) 0; border: none; background: transparent; }
    final hairline = snapBorder(context, t.len('glacier-hairline'));
    final card = Padding(
      padding: w.inStrip ? EdgeInsets.fromLTRB(t.space(2), t.space(2), t.space(2), 0) : EdgeInsets.fromLTRB(t.len('app-gutter'), t.space(2), t.len('app-gutter'), t.space(3)),
      child: Container(
        key: const ValueKey<String>('ai-card'),
        // A container pads itself by its border too, as a border-box does.
        padding: EdgeInsets.all(t.space(4)),
        decoration: w.inStrip
            ? null
            : BoxDecoration(
                color: t.color('app-paper-2'),
                borderRadius: BorderRadius.circular(t.radius('lg')),
                border: Border.all(color: t.color('app-rule'), width: hairline),
              ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // .reader { flex: none; inline-size: 4.5rem; color: var(--app-ink); }
            // .reader > * { padding: 0; min-block-size: 0; }  .reader svg { inline-size: 4.5rem; block-size: 4.5rem; }
            Thinking(phase: w.phase, size: reader),
            SizedBox(width: t.space(4)),
            Expanded(child: body),
          ],
        ),
      ),
    );

    // @keyframes card-in { from { opacity: 0; transform: translateY(4px); } }
    final ease = t.curve('glacier-ease-out');
    return Semantics(
      container: true,
      label: 'The model at work',
      child: AnimatedBuilder(
        animation: _enter,
        builder: (context, child) {
          final at = ease.transform(_enter.value);
          return at >= 1
              ? child!
              : Opacity(
                  opacity: at,
                  child: Transform.translate(offset: Offset(0, 4 * (1 - at)), child: child),
                );
        },
        child: card,
      ),
    );
  }
}

/// JavaScript's `Math.round`: a half goes up.
int _round(num value) => (value + 0.5).floor();

/// `ease-in-out`, the keyword.
const Cubic _easeInOut = Cubic(0.42, 0, 0.58, 1);

/// The opacity of something that breathes down to [low] at the middle of its round and back: a keyframe at 50%, each
/// half eased. [at] is the round's own share, 0 to 1.
double breathing(double at, double low) {
  final half = at < 0.5 ? at * 2 : (1 - at) * 2;
  return 1 + (low - 1) * _easeInOut.transform(half);
}

/// The readings: two columns of label, value and a hairline bar.
class _Meters extends StatelessWidget {
  const _Meters(this.meters);

  final List<Widget> meters;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // .meters { display: grid; grid-template-columns: repeat(auto-fill, minmax(8.5rem, 1fr));
    //   gap: var(--glacier-space-2) var(--glacier-space-4); margin: 0; }
    final least = t.lenOf('8.5rem');
    final across = t.space(4), down = t.space(2);
    return LayoutBuilder(
      builder: (context, constraints) {
        final room = constraints.maxWidth;
        final columns = ((room + across) / (least + across)).floor().clamp(1, meters.length);
        final wide = (room - across * (columns - 1)) / columns;
        return Wrap(
          key: const ValueKey<String>('ai-card-meters'),
          spacing: across,
          runSpacing: down,
          children: [for (final meter in meters) SizedBox(width: wide, child: meter)],
        );
      },
    );
  }
}

/// One reading: a label, a value, and a thin bar when the value is a share of something (`Meter`).
class _Meter extends StatelessWidget {
  const _Meter({required this.label, required this.value, required this.share});

  final String label;
  final String value;
  final double? share;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final xs = t.fontSize('xs');
    final leading = t.len('glacier-leading-sm');
    final ink = t.color('app-ink');
    final share = this.share;
    // .meter { display: grid; grid-template-columns: auto 1fr; column-gap: var(--glacier-space-2);
    //   align-items: baseline; font-size: var(--glacier-font-size-xs); line-height: var(--glacier-leading-sm); }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            // .meterLabel { color: var(--app-ink-3); letter-spacing: 0.04em; text-transform: uppercase; }
            Text(
              label.toUpperCase(),
              semanticsLabel: label,
              style: t.textAt(xs, color: t.color('app-ink-3'), height: leading, tracking: xs * 0.04),
            ),
            SizedBox(width: t.space(2)),
            // .meterValue { margin: 0; color: var(--app-ink); font-variant-numeric: tabular-nums; text-align: end; }
            Expanded(
              child: Text(
                value,
                key: ValueKey<String>('ai-card-meter-$label'),
                textAlign: TextAlign.end,
                style: t.textAt(xs, color: ink, height: leading).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
          ],
        ),
        if (share != null)
          // .bar { grid-column: 1 / -1; margin: 2px 0 0; block-size: 2px; border-radius: 1px;
          //   background: color-mix(in oklch, var(--app-ink) 14%, transparent); overflow: hidden; }
          // .bar > span { display: block; block-size: 100%; background: var(--app-ink);
          //   transition: inline-size 300ms ease-out; }
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(1),
              child: SizedBox(
                height: 2,
                child: ColoredBox(
                  color: t.colorOf('color-mix(in oklch, var(--app-ink) 14%, transparent)'),
                  child: TweenAnimationBuilder<double>(
                    // style={{ inlineSize: `${Math.round(share * 100)}%` }}
                    tween: Tween<double>(end: _round(share * 100) / 100),
                    duration: t.reducedMotion ? Duration.zero : const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    builder: (context, at, _) => FractionallySizedBox(
                      alignment: AlignmentDirectional.centerStart,
                      widthFactor: at.clamp(0, 1).toDouble(),
                      child: ColoredBox(key: ValueKey<String>('ai-card-bar-$label'), color: ink),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
