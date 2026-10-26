/// The Market's themes and fonts (Matt, 2026-10-26: "include some more themes, fonts"): a card each, a theme's a
/// note painted small in that theme's own colours and a face's a specimen set in it, each applied by a press with the
/// one in use marked.
///
/// A theme is applied as Appearance applies it (`themeChoice`, lib/core/preferences.dart), so a named theme brings
/// its accent; a face as a note's (`noteFace`) or the interface's (`typeface`). The lists are the app's own
/// (`themeOptions`, `typefaces`, `interfaceFaces`), so a theme or a face added there has its card here.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/art.dart';
import '../core/preferences.dart';
import '../settings/kit/settings_type.dart';
import '../settings/theme_cards.dart';
import '../settings/typeface_cards.dart' show shippedFamilies, typefaceFamilies;
import '../settings/words.dart';
import 'market_cards.dart';
import 'market_items.dart';

/// The tick on the card in use: a filled round in the ink with a check, never colour alone.
class _InUse extends StatelessWidget {
  const _InUse({required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final size = t.lenOf('1.25rem');
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        color: on ? t.color('app-ink') : const Color(0x00000000),
        shape: CircleBorder(side: on ? BorderSide.none : BorderSide(color: t.color('app-rule'), width: t.len('glacier-hairline'))),
      ),
      alignment: Alignment.center,
      child: on ? AppIcon(Lucide.check, size: 12, strokeWidth: 3, color: t.color('app-paper'), wash: false) : null,
    );
  }
}

/// One theme: Ghost.md's note painted small in its colours (its paper, its sidebar, its ink and its accent: a title,
/// lines, a tag and a ticked to-do), System split light and dark down the middle, and its name and line under it.
class MarketThemeCard extends StatelessWidget {
  const MarketThemeCard({super.key, required this.option, required this.selected, required this.onPress});

  final ThemeOption option;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return MarketCard(
      key: ValueKey('market-theme-${option.value}'),
      onPress: onPress,
      label: 'Theme ${option.label}',
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: t.lenOf('7rem'),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ThemeMiniature(palette: option.palette),
                if (option.alternatePalette != null) ClipRect(clipper: const _EndHalf(), child: ThemeMiniature(palette: option.alternatePalette!)),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(3)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(option.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
                      Text(option.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
                    ],
                  ),
                ),
                SizedBox(width: t.space(2)),
                _InUse(on: selected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// `clip-path: inset(0 0 0 50%)`: System's dark half.
class _EndHalf extends CustomClipper<Rect> {
  const _EndHalf();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(size.width / 2, 0, size.width, size.height);

  @override
  bool shouldReclip(_EndHalf old) => false;
}

/// The accent a miniature draws in [p]: Ink's accent is no colour, so on the dark page it is the page's ink, not the
/// light page's black (the app's accent is read as it is now, whichever page that is). The website's miniatures draw
/// the same (lib/market/market_listing.dart).
Color miniatureAccent(ThemePalette p) => (p.accent.computeLuminance() - p.background.computeLuminance()).abs() < 0.2 ? p.text : p.accent;

/// A note in a theme's colours, small: the sidebar's strip with its dots, the title, three lines, a tag in the
/// accent and a to-do ticked in it. Every colour is the palette's.
class ThemeMiniature extends StatelessWidget {
  const ThemeMiniature({super.key, required this.palette});

  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final accent = miniatureAccent(p);
    Widget bar(double width, double height, Color color, {double opacity = 1}) => Opacity(
          opacity: opacity,
          child: Container(width: width, height: height, decoration: ShapeDecoration(color: color, shape: const StadiumBorder())),
        );
    // A line of words, a share of the note's width.
    Widget line(double share) => FractionallySizedBox(widthFactor: share, alignment: AlignmentDirectional.centerStart, child: bar(double.infinity, 4.5, p.muted, opacity: 0.7));
    return ClipRect(
      child: ColoredBox(
        color: p.background,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The sidebar: a strip in its own paper with the notes as dots.
            Container(
              width: 22,
              decoration: BoxDecoration(color: p.sidebar, border: Border(right: BorderSide(color: p.border))),
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                children: [
                  for (var i = 0; i < 4; i++) ...[
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: i == 0 ? accent : p.muted.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(2.5))),
                    const SizedBox(height: 6),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(widthFactor: 0.5, alignment: AlignmentDirectional.centerStart, child: bar(double.infinity, 8, p.text)),
                    const SizedBox(height: 9),
                    line(0.9),
                    const SizedBox(height: 5),
                    line(0.7),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(2.5)),
                          alignment: Alignment.center,
                          child: CustomPaint(size: const Size(6, 6), painter: _Tick(p.background)),
                        ),
                        const SizedBox(width: 6),
                        Expanded(child: line(0.55)),
                      ],
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: ShapeDecoration(color: accent.withValues(alpha: 0.18), shape: const StadiumBorder()),
                          child: bar(22, 4, accent),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                          decoration: ShapeDecoration(color: p.surface, shape: StadiumBorder(side: BorderSide(color: p.border))),
                          child: bar(16, 4, p.muted),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A tick, for the miniature's to-do.
class _Tick extends CustomPainter {
  const _Tick(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(Path()
      ..moveTo(0, size.height * 0.55)
      ..lineTo(size.width * 0.38, size.height * 0.9)
      ..lineTo(size.width, size.height * 0.1), paint);
  }

  @override
  bool shouldRepaint(_Tick old) => old.color != color;
}

/// Text set in [face] at [px]: the face's own family where the app ships its file, the page's sans where not, and a
/// coding face with its ligatures, so `->` joins (TypefaceCards' sample, lib/settings/typeface_cards.dart).
TextStyle faceText(Tokens t, String face, double px, {String weight = 'regular', Color? color, double height = 1.25}) {
  final shipped = shippedFamilies.contains(typefaceFamilies[face]);
  final coding = isCodingFace(face) && shipped;
  final sans = [
    for (final f in t.families('glacier-font-sans'))
      if (shippedFamilies.contains(f)) f,
    'Inter Variable',
  ];
  final family = shipped ? typefaceFamilies[face]! : sans.first;
  final rest = [...?t.typography.fallbacks[family], ...sans.where((f) => f != family), ...?t.typography.fallbacks['Inter Variable']];
  final base = pageText(t, px, weight: weight, height: height, color: color ?? t.color('app-ink'), mono: coding);
  return base.copyWith(
    fontFamily: family,
    fontFamilyFallback: rest,
    fontFeatures: coding ? const [FontFeature('calt'), FontFeature('liga')] : base.fontFeatures,
    fontVariations: coding ? [FontVariation('wght', t.len('glacier-font-weight-$weight'))] : base.fontVariations,
  );
}

/// Which of the two faces a font card sets: a note's, or the interface's.
enum FaceRole { note, interface }

/// The line a face's card sets in it: a scrap of a note for a note's face, the app's own words for the interface's.
/// The website's market page sets the same two (lib/market/market_listing.dart).
const Map<FaceRole, String> faceSamples = {FaceRole.note: 'The quick brown ghost -> drifts past **bold** notes.', FaceRole.interface: 'Notes, Notebooks & Settings'};

/// One face: "Aa" large in it and a line of a note in it, its name, what it can be set as, and whether it is the one
/// in use for [role]; pressed, it is.
class MarketFontCard extends StatelessWidget {
  const MarketFontCard({super.key, required this.face, required this.role, required this.selected, required this.onPress});

  final String face;
  final FaceRole role;
  final bool selected;
  final VoidCallback onPress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final name = faceWords[face] ?? face;
    final sample = faceSamples[role]!;
    final roles = faceRoles(face);
    return MarketCard(
      key: ValueKey('market-face-${role.name}-$face'),
      onPress: onPress,
      label: '$name for ${role == FaceRole.note ? 'notes' : 'the interface'}',
      selected: selected,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: t.lenOf('6.2rem'),
            color: t.color('app-paper-3'),
            padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(2)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Aa', style: faceText(t, face, t.lenOf('2.6rem'), weight: 'semibold', height: 1)),
                SizedBox(width: t.space(3)),
                Expanded(child: Text(sample, maxLines: 3, overflow: TextOverflow.ellipsis, style: faceText(t, face, t.fontSize('sm'), height: 1.3, color: t.color('app-ink-2')))),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(t.space(3), t.space(2), t.space(3), t.space(3)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'semibold', color: t.color('app-ink'))),
                      Text(roles.join(' · '), maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('xs'), color: t.color('app-ink-3'))),
                    ],
                  ),
                ),
                SizedBox(width: t.space(2)),
                _InUse(on: selected),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
