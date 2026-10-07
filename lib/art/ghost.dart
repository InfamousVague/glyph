import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

/// The ghost's scenes (art/ghosts.ts): each a picture of its own, named for the moment it is drawn in, with the
/// picture's width over its height. The pictures are cropped to their drawings, so none of them is square, and the
/// box each is drawn in takes its shape from this. The file names keep the scene's number in docs/GHOSTS.md.
enum GhostScene {
  noNotes('02-no-notes-yet', 811 / 1024),
  emptyWorkspace('03-nothing-in-this-workspace', 1024 / 980),
  newNote('04-a-new-note', 1024 / 949),
  searchNothing('05-search-found-nothing', 594 / 1024),
  trashEmpty('06-the-trash-empty', 295 / 1024),
  archiveEmpty('07-the-archive-empty', 863 / 1024),
  listening('08-listening', 1005 / 1024),
  working('09-the-model-working', 728 / 1024),
  emptyCanvas('10-an-empty-canvas', 1024 / 697),
  allTicked('11-every-to-do-ticked', 649 / 1024),
  signedOut('12-signed-out-not-syncing', 1024 / 908),
  wentWrong('13-something-went-wrong', 874 / 1024),
  welcome('14-welcome-first-run', 709 / 1024),
  update('15-an-update-is-ready', 776 / 1024);

  const GhostScene(this.file, this.ratio);
  final String file;

  /// The picture's width over its height (`GHOST_RATIOS`).
  final double ratio;

  /// The scene's picture in the bundle (`GHOSTS`): the web app's own mask, copied from src/app/art/ghosts.
  String get asset => 'assets/art/ghosts/$file.webp';
}

/// `lead`, where the picture leads a page (the empty home page): the column's width, up to 45% of the window's
/// height and 36rem. `small`, under or beside words: the column's width, up to 40% of the height and 28rem. `tiny`,
/// inside a card: 3rem tall.
enum GhostSize { lead, small, tiny }

enum GhostAlign { start, center }

/// The ghost, Ghost.md's mascot, for the app's empty pages and quiet moments (art/Ghost.tsx, art/Ghost.module.css).
///
/// A sheet of paper with a dog-eared corner, a curl of smoke from its head, and a pose for each moment, in stipple
/// dotwork. Each scene is one picture whose dots are its alpha, painted in the page's ink: so one file serves both
/// themes, and a page sets the ghost's weight the way it sets any ink ([color]: `--app-ink-3` unless given, the
/// quiet ink under words). It sits still. Decoration only: hidden from a screen reader, since the words beside it
/// say what the moment is.
///
/// [heightShare] and [maxWidth] are for the screens whose own stylesheets set the limits over again (the home
/// page's empty state holds it to 38% of the height on a phone, the recorder's to 20%); left out they are the
/// size's own.
///
/// What differs from the page: nothing in what is drawn. The picture's width is worked out here from the room it is
/// given, where the page's stylesheet says `min(100%, 28rem, 40dvh × ratio)` and lets the engine do it.
class Ghost extends StatelessWidget {
  const Ghost({super.key, required this.scene, this.size = GhostSize.small, this.align = GhostAlign.start, this.color, this.heightShare, this.maxWidth});

  final GhostScene scene;
  final GhostSize size;

  /// `center` sits it in the middle of a column, for a page that centres its words.
  final GhostAlign align;
  final Color? color;

  /// How much of the window's height the drawing may take, 0 to 1.
  final double? heightShare;

  /// The ceiling on its width, in logical pixels, so a large monitor does not get a poster.
  final double? maxWidth;

  /// How wide the ghost is drawn in a column [available] wide in a window [windowHeight] tall, with the root font
  /// [rem] px: the stylesheet's `inline-size`.
  static double widthFor(GhostScene scene, GhostSize size, {required double available, required double windowHeight, required double rem, double? heightShare, double? maxWidth}) {
    if (size == GhostSize.tiny) return 3 * rem * scene.ratio;
    final share = heightShare ?? (size == GhostSize.lead ? 0.45 : 0.40);
    final ceiling = maxWidth ?? (size == GhostSize.lead ? 36 : 28) * rem;
    return math.min(available, math.min(ceiling, share * windowHeight * scene.ratio));
  }

  @override
  Widget build(BuildContext context) {
    final tokens = GlacierTheme.maybeOf(context);
    final ink = color ?? tokens?.color('app-ink-3') ?? const Color(0xFF808080);
    final rem = tokens?.lenOf('1rem') ?? 16;
    final windowHeight = MediaQuery.sizeOf(context).height;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = widthFor(scene, size, available: constraints.maxWidth, windowHeight: windowHeight, rem: rem, heightShare: heightShare, maxWidth: maxWidth);
          final picture = SizedBox(
            width: width,
            height: width / scene.ratio,
            // The dots are the picture's alpha, and the ink is laid in through them: a mask, as the page has it.
            child: Image.asset(scene.asset, color: ink, colorBlendMode: BlendMode.srcIn, fit: BoxFit.contain, filterQuality: FilterQuality.medium, excludeFromSemantics: true),
          );
          if (align == GhostAlign.center && constraints.hasBoundedWidth) return Align(alignment: Alignment.topCenter, heightFactor: 1, child: picture);
          return Align(alignment: AlignmentDirectional.topStart, widthFactor: 1, heightFactor: 1, child: picture);
        },
      ),
    );
  }
}
