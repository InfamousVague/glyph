import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

/// Every icon Settings draws, by the name the web app imports it under from `@glacier/icons` (a proxy over
/// lucide-react), plus the app's own back arrow (art/Icons.tsx `ArrowLeft`).
enum SettingsGlyph {
  arrowLeft,
  bell,
  bookOpen,
  check,
  chevronRight,
  circleUser,
  fileCode,
  flaskConical,
  folder,
  folderOpen,
  hardDriveDownload,
  hardDriveUpload,
  info,
  mic,
  puzzle,
  search,
  shapes,
  sparkles,
  sunMoon,
  terminal,
  userGroup,
  x,
}

/// The one way Settings draws an icon: a [SettingsGlyph] at a size, in the colour the surrounding [IconTheme] or
/// [color] gives it, as an `<svg>` on the page takes `currentColor`.
///
/// Stands in for the app's own icon widget, which is being built elsewhere with the wash the web gives its icons (a
/// third of the icon's ink inside its outline, app.css "Icons are outlines, with a wash inside"). Until it lands
/// these are Lucide's outlines from `lucide_icons_flutter`, chosen in [_lucide] and nowhere else, so the swap is this
/// file.
///
/// What differs from the web original: no wash; `userGroup` is Lucide's `users-round`, the nearest this package's
/// version has; the back arrow is Lucide's `arrow-left` where the web draws its own; and [strokeWidth] is honoured
/// only for the two that ask for one, each by the nearest cut the icon font has (2.5 on its 24 grid): the tick on a
/// choice card, which asks for 2.5, and the back arrow, which the web strokes at 2.4.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.glyph, {super.key, this.size = 16, this.color, this.strokeWidth});

  final SettingsGlyph glyph;

  /// The side of the icon's square in logical pixels: the `size` the web passes its icon.
  final double size;
  final Color? color;

  /// The stroke the web asks for on its 24-unit grid; Lucide's own 2 when null.
  final double? strokeWidth;

  @override
  Widget build(BuildContext context) => Icon(_lucide(glyph, heavy: (strokeWidth ?? 2) > 2.2), size: size, color: color);
}

IconData _lucide(SettingsGlyph glyph, {bool heavy = false}) => switch (glyph) {
      SettingsGlyph.arrowLeft => heavy ? LucideIcons.arrowLeft500 : LucideIcons.arrowLeft,
      SettingsGlyph.bell => LucideIcons.bell,
      SettingsGlyph.bookOpen => LucideIcons.bookOpen,
      SettingsGlyph.check => heavy ? LucideIcons.check500 : LucideIcons.check,
      SettingsGlyph.chevronRight => LucideIcons.chevronRight,
      SettingsGlyph.circleUser => LucideIcons.circleUser,
      SettingsGlyph.fileCode => LucideIcons.fileCode,
      SettingsGlyph.flaskConical => LucideIcons.flaskConical,
      SettingsGlyph.folder => LucideIcons.folder,
      SettingsGlyph.folderOpen => LucideIcons.folderOpen,
      SettingsGlyph.hardDriveDownload => LucideIcons.hardDriveDownload,
      SettingsGlyph.hardDriveUpload => LucideIcons.hardDriveUpload,
      SettingsGlyph.info => LucideIcons.info,
      SettingsGlyph.mic => LucideIcons.mic,
      SettingsGlyph.puzzle => LucideIcons.puzzle,
      SettingsGlyph.search => LucideIcons.search,
      SettingsGlyph.shapes => LucideIcons.shapes,
      SettingsGlyph.sparkles => LucideIcons.sparkles,
      SettingsGlyph.sunMoon => LucideIcons.sunMoon,
      SettingsGlyph.terminal => LucideIcons.terminal,
      SettingsGlyph.userGroup => LucideIcons.usersRound,
      SettingsGlyph.x => LucideIcons.x,
    };
