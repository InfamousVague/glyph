/// A message's reactions as stickers slapped on its bubble (Matt, 2026-11-17: "Make reactions pin at randomish places
/// slightly askue so multiple reactions look like stickers plastered on and around the message without overlapping
/// text much"): each kind of reaction its own emoji, tilted a little and set along the bubble's lower edge and its
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
/// down it ([y], 1 its foot), how far it hangs past the side ([out], a share of its own width), and its lean ([turn],
/// radians). Most go along the foot; from the fourth on, every other goes on a lower corner's side.
({double x, double y, double out, double turn}) stickerPlace(String seed, String emoji, int index, int total) {
  final r = math.Random(Object.hash(seed, emoji, index) & 0x7fffffff);
  double jitter(double by) => (r.nextDouble() * 2 - 1) * by;
  final turn = jitter(0.26); // about 15 degrees either way
  if (total > 3 && index >= 3 && index.isOdd) {
    final right = (index ~/ 2).isEven;
    return (x: right ? 1.0 : -1.0, y: 0.55 + jitter(0.25), out: right ? 0.4 : -0.4, turn: turn);
  }
  final along = total > 3 ? (index < 3 ? index : (index - 3) ~/ 2 + 3) : index;
  final slots = total > 3 ? 3 + (total - 3 + 1) ~/ 2 : total;
  final base = slots == 1 ? 0.55 : -0.75 + 1.5 * along / (slots - 1);
  return (x: (base + jitter(0.12)).clamp(-0.95, 0.95), y: 1.0, out: 0.0, turn: turn);
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
    final shown = kinds.take(8).toList();
    return Semantics(
      label: '$total reaction${total == 1 ? '' : 's'}: ${kinds.map((k) => k.emoji).join(' ')}',
      child: Stack(clipBehavior: Clip.none, children: [
        // Room under the bubble for the half of each sticker that hangs below it.
        Padding(padding: EdgeInsets.only(bottom: t.lenOf('0.95rem')), child: bubble),
        Positioned.fill(
          child: Stack(clipBehavior: Clip.none, children: [
            for (final (i, k) in shown.indexed)
              Builder(builder: (context) {
                final p = stickerPlace(seed, k.emoji, i, shown.length);
                return Align(
                  alignment: Alignment(p.x, p.y),
                  child: FractionalTranslation(
                    translation: Offset(p.out, 0),
                    child: GlacierPressable(
                      onPressed: onTap,
                      excludeSemantics: true,
                      builder: (context, state) => AnimatedScale(
                        scale: state.pressed ? 1.15 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: Transform.rotate(
                          angle: p.turn,
                          child: _Sticker(emoji: k.emoji, count: k.count),
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

/// One sticker: the emoji, with a soft shadow under it so it reads as stuck on, and how many where more than one.
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
          child: Text('$count', style: pageText(t, t.lenOf('0.65rem'), weight: 'bold', color: t.color('app-ink'))),
        ),
      ),
    ]);
  }
}
