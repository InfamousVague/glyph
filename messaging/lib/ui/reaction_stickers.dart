/// A message's reactions as stickers slapped on its bubble (Matt, 2026-11-17: "Make reactions pin at randomish places
/// slightly askue so multiple reactions look like stickers plastered on and around the message without overlapping
/// text much"): each reaction its own emoji, tilted a little and set along the bubble's lower edge and its
/// lower corners, half on the bubble and half off, so the words above stay clear. Where each goes and how far it leans
/// comes from the message and the emoji, so a sticker stays where it landed however often the list is drawn.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../kit/settings_type.dart' show pageText;

/// One kind of reaction: its emoji and how many gave it.
typedef StickerKind = ({String emoji, int count});

/// Where sticker [index] of [total] on the message [seed] goes: across the bubble ([x], -1 its left edge to 1 its right),
/// down it ([y], 1 its foot), how far it hangs past the side ([out], a share of its own width), how much lower than the
/// foot ([down], a share of its own height), its lean ([turn], radians) and its size ([scale], about 0.85 to 1.2: no two
/// stickers quite the same, Matt, 2026-11-17: "make them slightly vary in side and rotation as well").
///
/// They go along the foot, spread evenly; from five on, the fourth and fifth sit on the lower corners, outside the
/// bubble and under its words; past five along the foot, every other one sits a little lower, so they stagger rather
/// than pile up.
({double x, double y, double out, double down, double turn, double scale}) stickerPlace(String seed, String emoji, int index, int total) {
  final r = math.Random(Object.hash(seed, emoji, index) & 0x7fffffff);
  double jitter(double by) => (r.nextDouble() * 2 - 1) * by;
  final turn = jitter(0.3); // about 17 degrees either way
  final scale = 1.02 + jitter(0.17);
  final sides = total >= 5 ? 2 : 0;
  if (sides > 0 && (index == 3 || index == 4)) {
    final right = index == 4;
    return (x: right ? 1.0 : -1.0, y: 1.0, out: right ? 0.5 : -0.5, down: -0.15 + jitter(0.1), turn: turn, scale: scale);
  }
  final feet = total - sides;
  final k = sides > 0 && index > 4 ? index - 2 : index;
  final base = feet == 1 ? 0.55 : -0.8 + 1.6 * k / (feet - 1);
  final down = feet > 5 && k.isOdd ? 0.45 : 0.0;
  return (x: (base + jitter(0.06)).clamp(-0.9, 0.9), y: 1.0, out: 0.0, down: down + jitter(0.06), turn: turn, scale: scale);
}

/// [bubble] with [kinds] stuck on it. [seed] names the message (its key), so each sticker keeps its place; [onTap] is a
/// press on any of them.
class ReactionStickers extends StatelessWidget {
  const ReactionStickers({super.key, required this.bubble, required this.kinds, required this.seed, this.onTap});
  final Widget bubble;
  final List<StickerKind> kinds;
  final String seed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (kinds.isEmpty) return bubble;
    final t = context.tokens;
    final total = kinds.fold<int>(0, (n, k) => n + k.count);
    // One sticker for each reaction, not one a kind with a number (Matt, 2026-11-17: "show multiple reactions as
    // multiple emoji's pinned on and around the message"): two hearts from two people are two hearts. Eight at most;
    // the last of those says how many more there are.
    const most = 8;
    final each = [for (final k in kinds) for (var c = 0; c < k.count; c++) k.emoji];
    // Taken a kind at a time so every kind shows before any is shown twice.
    final order = <String>[];
    for (var round = 0; order.length < each.length && order.length < most; round++) {
      for (final k in kinds) {
        if (round < k.count && order.length < most) order.add(k.emoji);
      }
    }
    final more = total - order.length;
    final shown = [for (final (i, e) in order.indexed) (emoji: e, count: i == order.length - 1 && more > 0 ? more + 1 : 1)];
    return Semantics(
      label: '$total reaction${total == 1 ? '' : 's'}: ${kinds.map((k) => k.emoji).join(' ')}',
      child: Stack(clipBehavior: Clip.none, children: [
        // Room under the bubble for the half of each sticker that hangs below it, and more where they stagger.
        Padding(padding: EdgeInsets.only(bottom: t.lenOf(shown.length > 7 ? '1.5rem' : '0.95rem')), child: bubble),
        Positioned.fill(
          child: Stack(clipBehavior: Clip.none, children: [
            for (final (i, k) in shown.indexed)
              Builder(builder: (context) {
                final p = stickerPlace(seed, '${k.emoji}#$i', i, shown.length);
                return Align(
                  alignment: Alignment(p.x, p.y),
                  child: FractionalTranslation(
                    translation: Offset(p.out, p.down),
                    child: GlacierPressable(
                      onPressed: onTap,
                      excludeSemantics: true,
                      builder: (context, state) => AnimatedScale(
                        scale: state.pressed ? 1.15 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: Transform.rotate(
                          angle: p.turn,
                          child: Transform.scale(scale: p.scale, child: _Sticker(emoji: k.emoji, count: k.count)),
                        ),
                      ),
                    ),
                  ),
                );
              }),
          ]),
        ),
      ]),
    );
  }
}

/// One sticker: the emoji, with a soft shadow under it so it reads as stuck on; on the last, how many more there are
/// past the eight shown ([count] is that one and those).
class _Sticker extends StatelessWidget {
  const _Sticker({required this.emoji, required this.count});
  final String emoji;
  final int count;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final style = pageText(t, t.lenOf('1.5rem'), height: 1.1).copyWith(shadows: const [Shadow(color: Color(0x40000000), blurRadius: 3, offset: Offset(0, 1))]);
    if (count <= 1) return Text(emoji, style: style);
    return Stack(clipBehavior: Clip.none, children: [
      Text(emoji, style: style),
      Positioned(
        right: -t.lenOf('0.35rem'),
        bottom: -t.lenOf('0.1rem'),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: t.lenOf('0.25rem')),
          decoration: BoxDecoration(color: t.color('app-paper-3'), borderRadius: BorderRadius.circular(t.lenOf('0.5rem'))),
          child: Text('+${count - 1}', style: pageText(t, t.lenOf('0.65rem'), weight: 'bold', color: t.color('app-ink'))),
        ),
      ),
    ]);
  }
}
