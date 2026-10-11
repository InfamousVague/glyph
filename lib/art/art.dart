/// The art layer of Ghost.md (the web app's `src/app/art/`): the wisp and its smoke as fragment shaders, words from
/// smoke, the ghost, the icons and the cogs.
///
/// | The web app | Here |
/// | --- | --- |
/// | `useWispEdge(scroller, key, under, { foot, footOver, draw, band })`, `<WispEdgeFilter />`, art/wisp.css | [WispEdge] |
/// | `holdWispDrift()`, `followWispDrift()` | [WispDrift.hold], [WispDrift.follow] |
/// | `footSmokes()`, `WISP_EDGE_FOOT_CLEAR`, `withinWispBudget()` | [footSmokes], [wispEdgeFootClear], [withinWispBudget] |
/// | `wispFoot(height, width)`, `wispFootFade(height)` | [WispFoot], [wispFoot], [wispFootFade] |
/// | `wispSides(width, height, start, end)` | [WispSides], [wispSides] |
/// | `wispDraw()`, `wispHead()`, the `wispEdge` preference | [WispSettings], [wispDraw], [wispHead] |
/// | `<WispText text pace still onSettled />`, art/wisp.ts | [WispText], wisp.dart |
/// | `useDockSmoke(halo)`, `.dockHalo` | [DockSmoke], [DockHalo] |
/// | `<Ghost scene size align />` | [Ghost] |
/// | `GHOST_MARK` | [GhostMark] |
/// | art/Icons.tsx | [AppIcons] with [DrawnIconView], [HouseIcon], [placePath] |
/// | a lucide icon from `@glacier/icons`, iconWash.css | [AppIcon] with [Lucide] |
/// | `<Tips />` | [TipsShape] |
/// | `<WorkingGears label />`, art/gears.ts | [WorkingGears], gears.dart |
library;

export 'app_icon.dart';
export 'art_gallery.dart';
export 'dock_smoke.dart';
export 'gears.dart';
export 'ghost.dart';
export 'ghost_mark.dart';
export 'icon_wash.dart';
export 'icons.dart';
export 'lucide.g.dart';
export 'shapes.dart';
export 'svg_path.dart';
export 'turbulence.dart';
export 'wisp.dart';
export 'wisp_box.dart';
export 'wisp_edge.dart';
export 'wisp_foot.dart';
export 'wisp_kit.dart';
export 'wisp_mask.dart';
export 'wisp_settings.dart';
export 'wisp_sides.dart';
export 'wisp_smoke.dart';
export 'wisp_strips.dart';
export 'wisp_text.dart';
export 'working_gears.dart';
