/// The home page's icons, behind one helper so they can be swapped for the app's own icon widget when it is ported.
///
/// On the web they come from two places: the kit's (`@glacier/icons`, which is Lucide) and the app's own strokes
/// (`src/app/art/Icons.tsx`: the pin, the clock, the grid, the notebook, the cassette, the magnifier, the plus, the
/// folder, the archive box and the bin, each a 24-unit path stroked 2.4 wide with a third of its ink washed inside).
///
/// What differs: every one of them is Lucide's drawing here, for now. Where the web draws the app's own stroke, this
/// draws Lucide's nearest: the same subject, a slightly thinner line (2 of 24, not 2.4), no wash inside, and Lucide's
/// proportions (its pin is a tack with a round head; the app's is a flared body under a cap).
library;

import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// What an icon is of, by its job on the page; which drawing does the job is [HomeIcon]'s to say.
enum HomeGlyph {
  /// The search field's mark (kit `Search`), and the dock's magnifier (art `Magnifier`).
  search,

  /// The filters button (kit `SlidersHorizontal`).
  filters,

  /// A cross: the search's clear, a chip's take-off (kit `X`).
  cross,

  /// The tick on the chosen radio (kit `Check`).
  check,

  /// A page of words (kit `FileText`).
  note,

  /// A notebook in a heading and in the filters (art `Notebook`).
  notebook,

  /// A notebook as a row's kind (kit `BookOpen`).
  bookOpen,

  /// A page's notebook, on its card (kit `Book`).
  book,

  /// A canvas (kit `Workflow`).
  canvas,

  /// A recording (art `Cassette`).
  tape,

  /// Pinned (art `Pin`).
  pin,

  /// Recent (art `Clock`).
  clock,

  /// Every note (art `Grid`).
  grid,

  /// A new note, a new workspace (art `Plus`).
  plus,

  /// Speak (kit `Mic`).
  mic,

  /// Every workspace (art `Workspace`, a folder).
  workspace,

  /// An organization's mark before its workspace's name (kit `UserGroup`).
  organization,

  /// The Organizations heading (kit `Users`).
  people,

  /// Recent in an organization (kit `Activity`).
  activity,

  /// A swipe's archive (art `ArchiveBox`).
  archive,

  /// A swipe's delete (art `Bin`).
  bin,

  /// A refresh running (kit `LoaderCircle`).
  loader,

  /// A pull not yet let go (kit `ArrowDown`).
  arrowDown,
}

const Map<HomeGlyph, IconData> _drawings = {
  HomeGlyph.search: LucideIcons.search,
  HomeGlyph.filters: LucideIcons.slidersHorizontal,
  HomeGlyph.cross: LucideIcons.x,
  HomeGlyph.check: LucideIcons.check,
  HomeGlyph.note: LucideIcons.fileText,
  HomeGlyph.notebook: LucideIcons.notebook,
  HomeGlyph.bookOpen: LucideIcons.bookOpen,
  HomeGlyph.book: LucideIcons.book,
  HomeGlyph.canvas: LucideIcons.workflow,
  HomeGlyph.tape: LucideIcons.cassetteTape,
  HomeGlyph.pin: LucideIcons.pin,
  HomeGlyph.clock: LucideIcons.clock,
  HomeGlyph.grid: LucideIcons.layoutGrid,
  HomeGlyph.plus: LucideIcons.plus,
  HomeGlyph.mic: LucideIcons.mic,
  HomeGlyph.workspace: LucideIcons.folder,
  HomeGlyph.organization: LucideIcons.usersRound,
  HomeGlyph.people: LucideIcons.users,
  HomeGlyph.activity: LucideIcons.activity,
  HomeGlyph.archive: LucideIcons.archive,
  HomeGlyph.bin: LucideIcons.trash2,
  HomeGlyph.loader: LucideIcons.loaderCircle,
  HomeGlyph.arrowDown: LucideIcons.arrowDown,
};

/// One icon of the home page, [size] logical pixels square, in [color] or the text colour around it. Said to nobody:
/// what it stands beside names it, as `aria-hidden` did on the page.
class HomeIcon extends StatelessWidget {
  const HomeIcon(this.glyph, {super.key, required this.size, this.color});

  final HomeGlyph glyph;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Icon(_drawings[glyph], size: size, color: color ?? DefaultTextStyle.of(context).style.color),
      ),
    );
  }
}
