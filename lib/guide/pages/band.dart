/// Each walkthrough page's colour field (Matt, 2026-10-27: "build an onboarding flow with vivid colors and
/// iconography"): a band in a bold wash of its own, a large sign of what the page is about in the middle of it, and a
/// few of the app's icons floating on glass tiles around it.
///
/// It is the Market's head (lib/market/market_screen.dart `_Band`) made the walkthrough's: the same deep hues the
/// plugins' tiles wear (`marketHues`, the settings' own colours), the same soft light from the top corner
/// (`tileLight`), white marks on colour. The deep shade of each hue is used on both themes, as the Market's band does:
/// white reads on it either way, and the page round it is what turns light or dark.
///
/// The icons are drawn by [AppIcon], so they come in the person's icon pack and style like every other icon in the
/// app. The first and last pages hold the dotwork ghost (lib/art/ghost.dart) in white rather than an icon: it says
/// hello, and it sees you off. The tiles drift slowly, at the app's chosen pace (`motionScale`), and stand still for
/// a person who asked for less motion.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../../art/app_icon.dart';
import '../../art/ghost.dart';
import '../../art/lucide.g.dart';
import '../../claude/claude_mark.dart';
import '../../core/preferences.dart';
import '../../market/market_items.dart' show marketHues, tileLight;
import '../pages.dart';

const Color _white = Color(0xFFFFFFFF);

/// How one page looks: its wash, its sign, and the icons floating round it.
@immutable
class GuideLook {
  const GuideLook({required this.hues, required this.icon, required this.tiles, this.ghost, this.claude = false});

  /// The wash, from the top start corner to the bottom end, by the names `marketHues` keeps.
  final List<String> hues;

  /// The large sign in the middle, where there is no ghost.
  final LucideIcon icon;

  /// The small tiles round it, largest first.
  final List<LucideIcon> tiles;

  /// The ghost in the middle in place of [icon].
  final GhostScene? ghost;

  /// A tile with Claude's mark among them: the AI page, which says Claude can be connected.
  final bool claude;

  /// The wash's colours: each hue's deep shade.
  List<Color> get colours => [for (final hue in hues) marketHues[hue]!.$1];

  /// The page's own colour, for its dot and anything else that says which page this is.
  Color get hue => colours.first;
}

/// Every page's look.
const Map<GuidePage, GuideLook> guideLooks = {
  GuidePage.welcome: GuideLook(hues: ['indigo', 'purple', 'rose'], icon: Lucide.ghost, ghost: GhostScene.welcome, tiles: [Lucide.fileText, Lucide.hash, Lucide.mic, Lucide.refreshCw]),
  GuidePage.speak: GuideLook(hues: ['rose', 'red', 'orange'], icon: Lucide.mic, tiles: [Lucide.audioLines, Lucide.listChecks, Lucide.waves, Lucide.squarePen]),
  GuidePage.meetings: GuideLook(hues: ['cyan', 'blue', 'indigo'], icon: Lucide.users, tiles: [Lucide.calendarDays, Lucide.fileText, Lucide.messageSquareQuote, Lucide.ear]),
  GuidePage.ai: GuideLook(hues: ['purple', 'magenta', 'rose'], icon: Lucide.sparkles, claude: true, tiles: [Lucide.wandSparkles, Lucide.bot, Lucide.textSearch]),
  GuidePage.sync: GuideLook(hues: ['green', 'mint', 'cyan'], icon: Lucide.shieldCheck, tiles: [Lucide.smartphone, Lucide.laptop, Lucide.lock, Lucide.userGroup]),
  GuidePage.market: GuideLook(hues: ['indigo', 'purple', 'rose', 'orange'], icon: Lucide.store, tiles: [Lucide.puzzle, Lucide.palette, Lucide.type, Lucide.swatchBook]),
  GuidePage.mode: GuideLook(hues: ['amber', 'orange', 'coral'], icon: Lucide.slidersHorizontal, tiles: [Lucide.feather, Lucide.layoutGrid, Lucide.listTodo, Lucide.squareKanban]),
  GuidePage.model: GuideLook(hues: ['blue', 'indigo', 'purple'], icon: Lucide.brain, tiles: [Lucide.hardDriveDownload, Lucide.gauge, Lucide.shieldCheck, Lucide.sparkles]),
  GuidePage.start: GuideLook(hues: ['rose', 'orange', 'amber'], icon: Lucide.ghost, ghost: GhostScene.allTicked, tiles: [Lucide.graduationCap, Lucide.sunMoon, Lucide.circleCheck, Lucide.flame]),
};

/// Where each tile floats: its centre across and down the band (0 to 1), its size as a share of the band's height,
/// and its turn. Kept off the middle, where the sign is.
const List<(double, double, double, double)> _spots = [
  (0.16, 0.24, 0.24, -0.12),
  (0.85, 0.30, 0.20, 0.10),
  (0.82, 0.78, 0.22, -0.06),
  (0.14, 0.76, 0.18, 0.14),
];

class GuideBand extends StatefulWidget {
  const GuideBand({super.key, required this.page, required this.height});
  final GuidePage page;
  final double height;

  @override
  State<GuideBand> createState() => _GuideBandState();
}

class _GuideBandState extends State<GuideBand> with SingleTickerProviderStateMixin {
  /// One slow turn that every tile's drift is read from; still for a person who asked for less motion.
  late final AnimationController _drift = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = context.tokens.reducedMotion;
    // Six seconds a turn at the normal pace, longer at Relaxed and shorter at Brisk (Settings › Appearance).
    _drift.duration = Duration(milliseconds: (6000 * preferences.value.motionScale).round());
    if (still) {
      _drift
        ..stop()
        ..value = 0;
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final look = guideLooks[widget.page]!;
    final height = widget.height;
    final radius = t.radius('lg') * 1.6;
    final colours = look.colours;
    final tiles = <Widget Function(double)>[
      if (look.claude) (size) => ClaudeMark(size: size * 0.5, color: _white),
      for (final icon in look.tiles) (size) => AppIcon(icon, size: size * 0.5, strokeWidth: 2.2, color: _white),
    ].take(_spots.length).toList();
    return ExcludeSemantics(
      child: ClipRRect(
        key: ValueKey('guide-band-${widget.page.name}'),
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: colours,
                stops: [for (var i = 0; i < colours.length; i++) i / (colours.length - 1)],
              ),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final width = box.maxWidth;
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(child: tileLight(radius: radius)),
                    for (var i = 0; i < tiles.length; i++) _tile(i, tiles[i], width: width, height: height),
                    Center(child: _sign(t, look, height: height, width: width)),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Tile [i], drifting a few pixels up and down out of step with the others.
  Widget _tile(int i, Widget Function(double) mark, {required double width, required double height}) {
    final (x, y, share, turn) = _spots[i];
    final size = math.min(height * share, width * 0.2);
    final glass = Transform.rotate(
      angle: turn,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0x2EFFFFFF),
          borderRadius: BorderRadius.circular(size * 0.28),
          border: Border.all(color: const Color(0x40FFFFFF)),
          boxShadow: const [BoxShadow(color: Color(0x26000000), blurRadius: 14, offset: Offset(0, 6))],
        ),
        child: mark(size),
      ),
    );
    return Positioned(
      left: x * width - size / 2,
      top: y * height - size / 2,
      child: AnimatedBuilder(
        animation: _drift,
        child: glass,
        builder: (context, child) => Transform.translate(offset: Offset(0, 5 * math.sin(2 * math.pi * (_drift.value + i * 0.23))), child: child),
      ),
    );
  }

  /// The page's sign: the ghost in white, or a large icon on a disc of glass, breathing slowly.
  Widget _sign(Tokens t, GuideLook look, {required double height, required double width}) {
    final ghost = look.ghost;
    final Widget sign;
    if (ghost != null) {
      // As tall as most of the band, and never wider than half of it: the picture's own height follows its width.
      final across = math.min(height * 0.72 * ghost.ratio, width * 0.5);
      sign = SizedBox(width: across, child: Ghost(scene: ghost, color: _white, align: GhostAlign.center, heightShare: 1, maxWidth: across));
    } else {
      final side = math.min(height * 0.46, width * 0.36);
      sign = Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x33FFFFFF),
          border: Border.all(color: const Color(0x59FFFFFF), width: 1.5),
          boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 30, offset: Offset(0, 12))],
        ),
        child: AppIcon(look.icon, size: side * 0.5, strokeWidth: 2, color: _white),
      );
    }
    return AnimatedBuilder(
      animation: _drift,
      child: sign,
      builder: (context, child) => Transform.scale(scale: 1 + 0.025 * math.sin(2 * math.pi * _drift.value), child: child),
    );
  }
}
