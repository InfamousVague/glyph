/// The Academy's colours and signs (Matt, 2026-10-28: "spice up the academy with more colors and iconography"): each
/// course a hue of its own (courses.dart `Course.look`; until 2026-11-02 each of the web page's seven chapters), worn by
/// its card in the catalog, by the band at the head of its page and its lessons, by the bars that count them, and by
/// the page that sees it off.
///
/// The colours are the walkthrough's and the Market's (`marketHues`, the settings' own): a wash from one deep shade to
/// the next, white marks on it, the same in light and dark, as lib/guide/pages/band.dart has them. Where a course's
/// colour is ink on the page itself (a bar, a count, the words above a lesson's title) it takes the hue's deep shade
/// on a light page and its bright one on a dark page, so it reads on either. The signs are the app's icons, drawn by
/// `AppIcon` in the person's icon pack: something of what each course teaches.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart' show LucideIcon;
import '../art/ghost.dart';
import '../art/lucide.g.dart';
import '../guide/pages/band.dart';
import '../market/market_items.dart' show marketHues;

const Color _white = Color(0xFFFFFFFF);

/// How a course looks: its wash, its sign, and the icons floating round it.
@immutable
class ChapterLook {
  const ChapterLook({required this.hues, required this.icon, required this.tiles});

  /// The wash, by the names `marketHues` keeps; the first is the course's own colour.
  final List<String> hues;

  /// The course's sign: on its card, and in the middle of its bands.
  final LucideIcon icon;

  /// The small tiles round a band's sign.
  final List<LucideIcon> tiles;

  /// The wash's colours: each hue's deep shade, which white reads on in either theme.
  List<Color> get colours => [for (final hue in hues) marketHues[hue]!.$1];

  /// The course's colour as ink on the page: deep on a light page, bright on a dark one.
  Color ink(Tokens t) => t.isDark ? marketHues[hues.first]!.$2 : marketHues[hues.first]!.$1;

  /// A faint wash of [ink] behind something of the course's: a row, an example.
  Color wash(Tokens t, {double light = 0.08, double dark = 0.16}) => ink(t).withValues(alpha: t.isDark ? dark : light);
}

/// The whole Academy's look, on its catalog: the courses' colours in one wash, under a mortarboard.
const ChapterLook academyLook = ChapterLook(hues: ['indigo', 'purple', 'rose', 'orange'], icon: Lucide.graduationCap, tiles: [Lucide.heading, Lucide.table, Lucide.tag, Lucide.squareKanban]);

/// How tall a band is across [width]: a band, not a poster, on a phone and on a wide window alike.
double bandHeight(double width, {double share = 0.34, double least = 120, double most = 190}) => (width * share).clamp(least, most);

/// The band at the head of the catalog: the Academy's wash, its mortarboard, and the first courses' signs.
class AcademyHero extends StatelessWidget {
  const AcademyHero({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => HueBand(
      key: const ValueKey('academy-band'),
      colours: academyLook.colours,
      height: bandHeight(box.maxWidth, least: 140, most: 200),
      tiles: [for (final icon in academyLook.tiles) bandIcon(icon)],
      sign: (height, width) => bandDisc(academyLook.icon, height: height, width: width),
    ),
  );
}

/// The band at the head of a course's page: its wash, its signs, and its own sign in the middle.
class CourseBand extends StatelessWidget {
  const CourseBand({super.key, required this.look});
  final ChapterLook look;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) => HueBand(
      key: const ValueKey('academy-band'),
      colours: look.colours,
      height: bandHeight(box.maxWidth, share: 0.3, least: 120, most: 170),
      tiles: [for (final icon in look.tiles) bandIcon(icon)],
      sign: (height, width) => bandDisc(look.icon, height: height, width: width),
    ),
  );
}

/// The band at the head of a lesson: its course's wash and signs, and the lesson's own mark in the middle, as it is
/// typed (`**`, `- [ ]`).
class LessonBand extends StatelessWidget {
  const LessonBand({super.key, required this.look, required this.symbol});
  final ChapterLook look;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return LayoutBuilder(
      builder: (context, box) => HueBand(
        key: const ValueKey('academy-band'),
        colours: look.colours,
        height: bandHeight(box.maxWidth, share: 0.3, least: 112, most: 160),
        tiles: [for (final icon in look.tiles) bandIcon(icon)],
        sign: (height, width) {
          // The mark on a pill of glass, as wide as it needs: `- [ ]` is longer than `#`.
          final tall = height * 0.46;
          return Container(
            constraints: BoxConstraints(minWidth: tall, maxWidth: math.max(tall, width * 0.5), minHeight: tall, maxHeight: tall),
            padding: EdgeInsets.symmetric(horizontal: tall * 0.28),
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(tall / 2),
              border: Border.all(color: const Color(0x59FFFFFF), width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12))],
            ),
            // As wide as the mark and no wider: Center takes its child's width, and the pill its padding round it.
            child: Center(
              widthFactor: 1,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(symbol, key: const ValueKey('academy-band-mark'), maxLines: 1, softWrap: false, style: t.textAt(tall * 0.42, mono: true, weight: 'semibold', color: _white)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The band that sees a course off: its wash, the ghost with every box ticked once all of it is learned (its
/// sign until then), and a little celebration floating round.
class CourseEndBand extends StatelessWidget {
  const CourseEndBand({super.key, required this.look, required this.learned});
  final ChapterLook look;
  final bool learned;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) => HueBand(
        key: const ValueKey('academy-band'),
        colours: [...look.colours, if (learned) look.colours.first],
        height: bandHeight(box.maxWidth, share: 0.4, least: 150, most: 210),
        tiles: [for (final icon in [Lucide.sparkles, Lucide.graduationCap, Lucide.circleCheck, Lucide.flame]) bandIcon(icon)],
        sign: (height, width) {
          if (!learned) return bandDisc(look.icon, height: height, width: width);
          const ghost = GhostScene.allTicked;
          final across = math.min(height * 0.72 * ghost.ratio, width * 0.5);
          return SizedBox(width: across, child: Ghost(scene: ghost, color: _white, align: GhostAlign.center, heightShare: 1, maxWidth: across));
        },
      ),
    );
  }
}

/// A course's sign: a small tile of its wash with its icon, or a tick once all of it is learned.
class CourseTile extends StatelessWidget {
  const CourseTile({super.key, required this.look, required this.learned, this.size = 40, this.icon});
  final ChapterLook look;
  final bool learned;
  final double size;

  /// Another sign on the wash: Simple's More row wears the Academy's wash with a grid on it.
  final LucideIcon? icon;

  @override
  Widget build(BuildContext context) {
    final colours = look.colours;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.3),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colours.length > 1 ? colours : [colours.first, colours.first]),
        boxShadow: [BoxShadow(color: colours.first.withValues(alpha: 0.28), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: bandIcon(learned ? Lucide.check : icon ?? look.icon)(size),
    );
  }
}
