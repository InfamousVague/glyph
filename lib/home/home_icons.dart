/// The home page's icons, behind one helper: the one place the page chooses a drawing, so its call sites read by job.
///
/// On the web they come from two places, and so here: the kit's (`@glacier/icons`, which is Lucide: [AppIcon] with
/// [Lucide]'s paths) and the app's own strokes (`src/app/art/Icons.tsx`, [DrawnIconView] with [AppIcons]: the pin,
/// the clock, the grid, the notebook, the cassette, the magnifier, the plus, the folder, the archive box and the bin,
/// each a 24-unit path stroked 2.4 wide). Both wear the page's wash, a third of their ink inside the icon's body.
///
/// A kit icon's stroke is the caller's to say, as it is the JSX's on the page (`<Search size={15} strokeWidth={2.2} />`
/// is `HomeIcon(HomeGlyph.search, size: 15, strokeWidth: 2.2)`); unsaid it is Lucide's own 2, as it is there. The
/// app's own strokes are always 2.4 and take no stroke.
library;

import 'package:flutter/widgets.dart';
import '../art/app_icon.dart';
import '../art/icons.dart';
import '../art/lucide.g.dart';

/// What an icon is of, by its job on the page; which drawing does the job is [HomeIcon]'s to say.
enum HomeGlyph {
  /// The search field's mark (kit `Search`).
  search,

  /// The dock's magnifier (art `Magnifier`).
  magnifier,

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

/// The kit's drawing for a glyph, where it is the kit's.
const Map<HomeGlyph, LucideIcon> _kit = {
  HomeGlyph.search: Lucide.search,
  HomeGlyph.filters: Lucide.slidersHorizontal,
  HomeGlyph.cross: Lucide.x,
  HomeGlyph.check: Lucide.check,
  HomeGlyph.note: Lucide.fileText,
  HomeGlyph.bookOpen: Lucide.bookOpen,
  HomeGlyph.book: Lucide.book,
  HomeGlyph.canvas: Lucide.workflow,
  HomeGlyph.mic: Lucide.mic,
  HomeGlyph.organization: Lucide.userGroup,
  HomeGlyph.people: Lucide.users,
  HomeGlyph.activity: Lucide.activity,
  HomeGlyph.loader: Lucide.loaderCircle,
  HomeGlyph.arrowDown: Lucide.arrowDown,
};

/// The app's own drawing for a glyph, where it is the app's.
const Map<HomeGlyph, DrawnIcon> _own = {
  HomeGlyph.magnifier: AppIcons.magnifier,
  HomeGlyph.notebook: AppIcons.notebook,
  HomeGlyph.tape: AppIcons.cassette,
  HomeGlyph.pin: AppIcons.pin,
  HomeGlyph.clock: AppIcons.clock,
  HomeGlyph.grid: AppIcons.grid,
  HomeGlyph.plus: AppIcons.plus,
  HomeGlyph.workspace: AppIcons.workspace,
  HomeGlyph.archive: AppIcons.archiveBox,
  HomeGlyph.bin: AppIcons.bin,
};

/// One icon of the home page, [size] logical pixels square, in [color] or the text colour around it. Said to nobody:
/// what it stands beside names it, as `aria-hidden` did on the page.
class HomeIcon extends StatelessWidget {
  const HomeIcon(this.glyph, {super.key, required this.size, this.color, this.strokeWidth = 2});

  final HomeGlyph glyph;
  final double size;
  final Color? color;

  /// `strokeWidth={…}` of the kit's icon on the page, in the icon's own 24 units; Lucide's 2 where the JSX says
  /// none. One of the app's own strokes is 2.4 whatever this says.
  final double strokeWidth;

  /// Whether [glyph] is one of the app's own strokes (art/Icons.tsx), not the kit's.
  static bool isOwn(HomeGlyph glyph) => _own.containsKey(glyph);

  @override
  Widget build(BuildContext context) {
    final ink = color ?? DefaultTextStyle.of(context).style.color;
    final own = _own[glyph];
    // Both keep themselves from the semantics tree.
    return own != null ? DrawnIconView(own, size: size, color: ink) : AppIcon(_kit[glyph]!, size: size, strokeWidth: strokeWidth, color: ink);
  }
}
