/// The art layer of Ghost.md (the web app's `src/app/art/`): the gradient blur at a page's edges and round the
/// dock, words that arrive out of a blur, the ghost, the icons and the cogs.
///
/// Where the web app wears the wisp, a smoke of fractal noise, this app has worn a gradient blur since Matt,
/// 2026-10-24: "replace the smoke effect with a gradient blur on all places that use the wisp smoke", and then
/// "remove the smoke on mac too so all versions get blur". The rows below say which of the page's names each stands
/// for.
///
/// | The web app | Here |
/// | --- | --- |
/// | `useWispEdge(scroller, key, under, { foot, footOver })`, art/wisp.css | [BlurEdge] |
/// | `footSmokes()`, `WISP_EDGE_FOOT_CLEAR`, `withinWispBudget()` | [footBlurs], [blurEdgeFootClear], [withinPictureBudget] |
/// | `wispFoot(height, width)` | [BlurFoot] |
/// | `wispSides(width, height, start, end)` | [BlurSides] |
/// | the `wispEdge` preference | [BlurEdgeSettings] |
/// | `<WispText text pace still onSettled />`, art/wisp.ts | [WispText], wisp.dart, blur_letter.dart |
/// | `useDockSmoke(halo)`, `.dockHalo` | [DockBlur], [DockBlurHalo] |
/// | `<Ghost scene size align />` | [Ghost] |
/// | `GHOST_MARK` | [GhostMark] |
/// | art/Icons.tsx | [AppIcons] with [DrawnIconView], [HouseIcon], [placePath] |
/// | a lucide icon from `@glacier/icons`, iconWash.css | [AppIcon] with [Lucide] |
/// | `<Tips />` | [TipsShape] |
/// | `<WorkingGears label />`, art/gears.ts | [WorkingGears], gears.dart |
library;

export 'app_icon.dart';
export 'art_gallery.dart';
export 'blur_box.dart';
export 'blur_edge.dart';
export 'blur_letter.dart';
export 'dock_blur.dart';
export 'edge_backdrop.dart';
export 'edge_strips.dart';
export 'gears.dart';
export 'ghost.dart';
export 'ghost_mark.dart';
export 'icon_packs.dart';
export 'icon_wash.dart';
export 'icons.dart';
export 'lucide.g.dart';
export 'shapes.dart';
export 'svg_path.dart';
export 'turbulence.dart';
export 'wisp.dart';
export 'wisp_kit.dart';
export 'wisp_text.dart';
export 'working_gears.dart';
