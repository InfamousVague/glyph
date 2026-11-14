import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/lucide.g.dart';
import '../effects.dart';
import '../kit/settings_type.dart';
import 'common.dart';

/// What a long press on a message brings up, beside the message itself (Matt, 2026-11-13: "I want the message
/// reactions to pop up under the message like imessage does", and "I'd like to be able to react with full screen
/// effects by pressing and holding on a message as well"): the reactions in a row under the bubble, the screen
/// effects in a row under those, and what else can be done with the message under them. The page dims round the
/// message, which stays lit. With no room under the bubble, it all sits above it.
Future<void> showMessagePopover(
  BuildContext context, {
  required Rect bubble,
  required bool outgoing,
  List<String> reactions = const [],
  Set<String> mine = const {},
  ValueChanged<String>? onReact,
  List<ScreenEffect> effects = const [],
  ValueChanged<ScreenEffect>? onEffect,
  required List<Choice> choices,
}) {
  return Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierDismissible: true,
    barrierColor: const Color(0x00000000),
    transitionDuration: const Duration(milliseconds: 200),
    reverseTransitionDuration: const Duration(milliseconds: 130),
    pageBuilder: (context, animation, _) => _Popover(
      animation: animation,
      bubble: bubble,
      outgoing: outgoing,
      reactions: reactions,
      mine: mine,
      onReact: onReact,
      effects: effects,
      onEffect: onEffect,
      choices: choices,
    ),
  ));
}

class _Popover extends StatelessWidget {
  const _Popover({required this.animation, required this.bubble, required this.outgoing, required this.reactions, required this.mine, required this.onReact, required this.effects, required this.onEffect, required this.choices});
  final Animation<double> animation;
  final Rect bubble;
  final bool outgoing;
  final List<String> reactions;
  final Set<String> mine;
  final ValueChanged<String>? onReact;
  final List<ScreenEffect> effects;
  final ValueChanged<ScreenEffect>? onEffect;
  final List<Choice> choices;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final pad = MediaQuery.paddingOf(context);
    final screen = MediaQuery.sizeOf(context);
    final side = t.lenOf('2.5rem');
    final surface = BoxDecoration(color: t.color('app-paper-2'), border: Border.all(color: t.color('app-rule')), boxShadow: t.shadowOf('0 8px 28px rgba(0,0,0,0.22)'));
    void close() => Navigator.of(context).pop();

    Widget pill(List<Widget> children, {Widget? lead}) => DecoratedBox(
          decoration: surface.copyWith(borderRadius: BorderRadius.circular(side)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(side),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.all(t.space(1)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [?lead, ...children]),
            ),
          ),
        );

    Widget round(String emoji, String label, bool chosen, VoidCallback onPress) => GlacierPressable(
          onPressed: () {
            close();
            onPress();
          },
          semanticLabel: label,
          builder: (context, state) => AnimatedScale(
            scale: state.pressed ? 1.25 : 1,
            duration: const Duration(milliseconds: 120),
            child: Container(
              width: side,
              height: side,
              margin: EdgeInsets.symmetric(horizontal: t.lenOf('0.1rem')),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chosen ? t.colorOf('color-mix(in srgb, #4f5bd5 22%, transparent)') : const Color(0x00000000),
                border: chosen ? Border.all(color: t.colorOf('#4f5bd5'), width: 2) : null,
              ),
              alignment: Alignment.center,
              child: Text(emoji, style: pageText(t, t.lenOf('1.4rem'), height: 1.15)),
            ),
          ),
        );

    final panel = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: outgoing ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (reactions.isNotEmpty && onReact != null) pill([for (final e in reactions) round(e, mine.contains(e) ? 'Remove $e' : 'React $e', mine.contains(e), () => onReact!(e))]),
        if (effects.isNotEmpty && onEffect != null) ...[
          SizedBox(height: t.space(2)),
          pill(
            [
              for (final e in effects)
                round(effectReactionEmoji[e]!, mine.contains(effectReactionEmoji[e]) ? 'Take back ${effectLabel(e)}' : 'React with ${effectLabel(e)}, over the whole screen', mine.contains(effectReactionEmoji[e]), () => onEffect!(e)),
            ],
            lead: Padding(
              padding: EdgeInsets.only(left: t.space(3), right: t.space(1)),
              child: Semantics(label: 'Screen effects', child: AppIcon(Lucide.sparkles, size: 18, color: t.color('app-ink-3'))),
            ),
          ),
        ],
        if (choices.isNotEmpty) ...[
          SizedBox(height: t.space(2)),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: DecoratedBox(
              decoration: surface.copyWith(borderRadius: BorderRadius.circular(t.radius('lg'))),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(t.radius('lg')),
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final c in choices)
                    GlacierPressable(
                      onPressed: () {
                        close();
                        c.onPress();
                      },
                      builder: (context, state) {
                        final ink = c.danger ? t.colorOf('#dd3a30') : t.color('app-ink');
                        return ColoredBox(
                          color: state.pressed ? t.color('app-paper-3') : const Color(0x00000000),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: t.space(4), vertical: t.lenOf('0.7rem')),
                            child: Row(children: [
                              Expanded(child: Text(c.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('md'), weight: 'medium', color: ink))),
                              SizedBox(width: t.space(3)),
                              AppIcon(c.icon, size: 18, color: ink),
                            ]),
                          ),
                        );
                      },
                    ),
                ]),
              ),
            ),
          ),
        ],
      ],
    );

    final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
    return Stack(children: [
      // The page dims, the message stays lit; a tap anywhere outside puts it all away.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: close,
          child: FadeTransition(opacity: animation, child: CustomPaint(painter: _Scrim(bubble, t.radius('lg')))),
        ),
      ),
      Positioned.fill(
        child: CustomSingleChildLayout(
          delegate: _Beside(bubble: bubble, outgoing: outgoing, safe: EdgeInsets.fromLTRB(8, pad.top + 8, 8, pad.bottom + 8), gap: t.space(2)),
          child: FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.8, end: 1.0).animate(curved),
              alignment: outgoing ? Alignment.topRight : Alignment.topLeft,
              child: ConstrainedBox(constraints: BoxConstraints(maxWidth: math.min(360, screen.width - 16)), child: panel),
            ),
          ),
        ),
      ),
    ]);
  }
}

/// Where the popover sits: under the bubble on the bubble's own side, above it when there is no room under, and
/// inside the screen whatever the bubble's size.
class _Beside extends SingleChildLayoutDelegate {
  _Beside({required this.bubble, required this.outgoing, required this.safe, required this.gap});
  final Rect bubble;
  final bool outgoing;
  final EdgeInsets safe;
  final double gap;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => BoxConstraints.loose(Size(constraints.maxWidth - safe.horizontal, constraints.maxHeight - safe.vertical));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final x = (outgoing ? bubble.right - child.width : bubble.left).clamp(safe.left, math.max(safe.left, size.width - safe.right - child.width));
    final under = bubble.bottom + gap;
    final over = bubble.top - gap - child.height;
    final lowest = size.height - safe.bottom - child.height;
    final y = under <= lowest ? under : (over >= safe.top ? over : lowest.clamp(safe.top, math.max(safe.top, lowest)));
    return Offset(x.toDouble(), y.toDouble());
  }

  @override
  bool shouldRelayout(_Beside old) => old.bubble != bubble || old.outgoing != outgoing || old.safe != safe;
}

/// The dimmed page, with the message's own place left clear.
class _Scrim extends CustomPainter {
  _Scrim(this.bubble, this.radius);
  final Rect bubble;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final hole = RRect.fromRectAndRadius(bubble.inflate(4), Radius.circular(radius + 4));
    canvas.drawPath(
      Path.combine(PathOperation.difference, Path()..addRect(Offset.zero & size), Path()..addRRect(hole)),
      Paint()..color = const Color(0x73000000),
    );
  }

  @override
  bool shouldRepaint(_Scrim old) => old.bubble != bubble;
}
