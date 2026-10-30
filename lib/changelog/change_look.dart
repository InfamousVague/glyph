/// How a release's lines are drawn, on the What's new card and the Changelog page alike: each item's glyph in a soft
/// round of its kind's colour, its words, and its kind as a small tag in that colour.
///
/// The colours are the activity's (assets/css/app.css `--activity-*`, docs/ACTIVITY.md), so the app has one palette
/// for its live and its news: New in the downloads' green, Better in the sync's blue, Fixed in the pictures' amber.
/// Each has its light and its dark shade, and Calm turns all three to the ink, as it does every colour of the activity;
/// the tag's word still says which.
///
/// An item's `icon` is a glyph by Lucide's name, drawn in the icon pack and style chosen in Settings › Appearance
/// ([AppIcon]), or a built-in plugin's id: that plugin's mark, in its brand's colour where it stands out from the paper
/// and else the ink, as the activity tray draws a plugin's work (lib/activity/job_mark.dart); Google Meet's white on its
/// own colour ([marksInWhite]); the plugin's glyph in the kind's colour where it wears no mark, and for every plugin in a
/// build for a store's pictures (`GHOST_STORE_NEUTRAL`, [brandMarksShown]). A name that is neither is the sparkle.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../activity/job_mark.dart' show activityCalm;
import '../art/app_icon.dart';
import '../art/brand_marks.dart';
import '../art/lucide.g.dart';
import '../market/market_items.dart' show pluginTile, tileLight;
import '../plugins/brands.dart';
import '../plugins/built_in.dart' show builtIn;
import '../plugins/types.dart';
import '../sheet/css.dart' show pageText;
import 'changelog.dart';

/// The token a kind wears.
String changeToken(ChangeKind kind) => switch (kind) {
      ChangeKind.added => 'activity-downloads',
      ChangeKind.better => 'activity-sync',
      ChangeKind.fixed => 'activity-images-2',
    };

/// A kind's colour on this page: light or dark, vivid or Calm's ink.
Color changeColour(Tokens t, ChangeKind kind) => t.color(changeToken(kind));

/// What an item's `icon` names: a Lucide glyph, or a built-in plugin (with its mark where it wears one now).
@immutable
class ChangeGlyph {
  const ChangeGlyph({required this.glyph, this.plugin, this.mark, required this.known});

  /// The glyph drawn where there is no mark: the name's own, the plugin's, or the sparkle for a name that is neither.
  final LucideIcon glyph;
  final GlyphPlugin? plugin;

  /// The plugin's mark, drawn in place of [glyph]; none for a plugin without one and in a store-shot build.
  final BrandMarkData? mark;

  /// Whether the name was a glyph or a plugin at all (test/changelog holds every item's to it).
  final bool known;
}

/// The built-in plugin [id] names, if any.
GlyphPlugin? builtInPlugin(String id) {
  for (final plugin in builtIn) {
    if (plugin.manifest.id == id) return plugin;
  }
  return null;
}

/// What [icon] draws.
ChangeGlyph changeGlyphOf(String icon) {
  final lucide = Lucide.all[icon];
  if (lucide != null) return ChangeGlyph(glyph: lucide, known: true);
  final plugin = builtInPlugin(icon);
  if (plugin != null) return ChangeGlyph(glyph: pluginLucide(plugin), plugin: plugin, mark: brandOfId(icon), known: true);
  return const ChangeGlyph(glyph: Lucide.sparkles, known: false);
}

/// An item's glyph in a soft round of its kind's colour, [size] across.
class ChangeIcon extends StatelessWidget {
  const ChangeIcon({super.key, required this.icon, required this.kind, this.size = 34});

  final String icon;
  final ChangeKind kind;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colour = changeColour(t, kind);
    final calm = activityCalm(t);
    final found = changeGlyphOf(icon);
    final glyphSize = size * 0.52;
    final mark = found.mark;
    final plugin = found.plugin;
    final Widget drawn;
    if (mark != null && plugin != null && marksInWhite.contains(plugin.manifest.id) && !calm) {
      // Google Meet's mark is drawn only in white on its own colour: its tile, round, in place of the wash.
      final radius = size / 2;
      return ExcludeSemantics(
        child: SizedBox.square(
          key: ValueKey('change-icon:$icon'),
          dimension: size,
          child: DecoratedBox(
            decoration: pluginTile(plugin, radius: radius),
            child: Stack(fit: StackFit.expand, children: [tileLight(radius: radius), Center(child: BrandMarkIcon(mark, size: glyphSize, color: const Color(0xFFFFFFFF)))]),
          ),
        ),
      );
    } else if (mark != null) {
      final ink = t.color('glacier-text');
      drawn = BrandMarkIcon(mark, size: glyphSize, color: calm ? ink : brandInkOn(mark, ground: t.color('app-paper-2'), ink: ink));
    } else {
      drawn = AppIcon(found.glyph, size: glyphSize, color: colour, strokeWidth: 2.1);
    }
    return ExcludeSemantics(
      child: Container(
        key: ValueKey('change-icon:$icon'),
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: colour.withValues(alpha: t.isDark ? 0.2 : 0.13)),
        child: drawn,
      ),
    );
  }
}

/// A kind's word as a small tag in its colour: "New", "Better", "Fixed".
class ChangeTag extends StatelessWidget {
  const ChangeTag(this.kind, {super.key});

  final ChangeKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colour = changeColour(t, kind);
    final size = t.fontSize('xs');
    return Container(
      key: ValueKey('change-tag:${kind.id}'),
      padding: EdgeInsets.symmetric(horizontal: t.space(2), vertical: 1),
      decoration: ShapeDecoration(color: colour.withValues(alpha: t.isDark ? 0.2 : 0.12), shape: const StadiumBorder()),
      child: Text(kind.label, maxLines: 1, style: pageText(t, size, weight: 'semibold', color: colour, height: 1.4)),
    );
  }
}

/// One item: its icon, its words and its tag, the tag on the words' first line.
class ChangeLine extends StatelessWidget {
  const ChangeLine({super.key, required this.item});

  final ChangeItem item;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Semantics(
      container: true,
      label: '${item.kind.label}: ${item.words}',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: t.space(2)),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ChangeIcon(icon: item.icon, kind: item.kind),
              SizedBox(width: t.space(3)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(item.words, style: pageText(t, t.fontSize('sm'), color: t.color('glacier-text'), height: 1.45)),
                ),
              ),
              SizedBox(width: t.space(2)),
              Padding(padding: const EdgeInsets.only(top: 6), child: ChangeTag(item.kind)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A release's heading: its version, its title where it has one, and its day ("30 Oct 2026").
class ReleaseHeading extends StatelessWidget {
  const ReleaseHeading({super.key, required this.release, this.running = false});

  final Release release;

  /// The version this device runs: said beside it.
  final bool running;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final quiet = t.color('app-ink-3');
    final title = release.title;
    return Semantics(
      header: true,
      child: Padding(
        padding: EdgeInsets.only(top: t.space(3), bottom: t.space(1)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(release.version, style: pageText(t, t.fontSize('md'), weight: 'bold', color: t.color('glacier-text'))),
            SizedBox(width: t.space(2)),
            Expanded(
              child: title == null ? const SizedBox.shrink() : Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: pageText(t, t.fontSize('sm'), weight: 'medium', color: t.color('glacier-text-muted'))),
            ),
            SizedBox(width: t.space(2)),
            Text(running ? "${releaseDay(release.date)} · you're on this one" : releaseDay(release.date), style: pageText(t, t.fontSize('xs'), color: quiet)),
          ],
        ),
      ),
    );
  }
}

const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// "30 Oct 2026" for "2026-10-30"; the file's own words for anything else.
String releaseDay(String date) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(date);
  if (match == null) return date;
  final month = int.parse(match.group(2)!);
  if (month < 1 || month > 12) return date;
  return '${int.parse(match.group(3)!)} ${_months[month - 1]} ${match.group(1)}';
}
