/// A plugin's mark on its work (Matt, 2026-10-30: "use plugin vendor logo icons for activity updates related to
/// plugins"): a job that belongs to a plugin ([Job.plugin], said where the job begins) wears that plugin's mark in
/// place of its kind's glyph, in the tray's rows, Today's and the Past 7 days' lines, its result chip and the ring's
/// middle while it leads. Lovart's banners and pictures, the AI provider writing a summary (Claude, OpenAI, Gemini,
/// Aster, a custom model), ElevenLabs' read-alouds, Slack's and Discord's posts, Notion's, GitHub's and Google
/// Calendar's reads, the meeting bot in Google Meet or Zoom.
///
/// The marks are the ones the Market and Settings draw (lib/plugins/brands.dart, lib/art/brand_marks.dart), drawn the
/// way the Market's badge draws them: in the brand's colour where that stands out from the paper ([brandInkOn]), else
/// in the ink; Google Meet's, which is drawn only in white on its own colour ([marksInWhite]), on its tile where the
/// row has one, else its mark. A plugin with no mark of its own (Slack, OpenAI, Aster, Zoom's camera, a custom model)
/// wears its glyph, in its kind's colour. The kind's colour stays the job's accent all the same: the row's wash, its
/// bar, the ring's arc, the chip's rim. Calm draws every mark in the ink, as it does every colour of the activity.
///
/// Never in a store's pictures: a build with `GHOST_STORE_NEUTRAL=true` ([brandMarksShown] false) draws the kind's
/// glyph for every job, a plugin's or not.
library;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../art/app_icon.dart';
import '../art/brand_marks.dart';
import '../market/market_items.dart' show pluginTile, tileLight;
import '../plugins/brands.dart';
import '../plugins/built_in.dart' show builtIn;
import '../plugins/types.dart';

/// The plugin [id] names, where its work wears its mark now: none for no plugin, one this build does not ship, or any
/// in a store-shot build.
GlyphPlugin? markedPlugin(String? id) {
  if (id == null || !brandMarksShown) return null;
  for (final plugin in builtIn) {
    if (plugin.manifest.id == id) return plugin;
  }
  return null;
}

/// Whether Calm is on where [t] reads: the activity's colours are the ink then (assets/css/app.css, `data-calm`).
bool activityCalm(Tokens t) => t.color('activity-needs-you') == t.color('app-ink');

/// Whether [id]'s mark is drawn on its own tile in a row that has one: Google Meet's white mark, not in Calm.
bool marksOnTile(String? id, Tokens t) => id != null && marksInWhite.contains(id) && markedPlugin(id) != null && brandOfId(id) != null && !activityCalm(t);

/// A plugin's mark, [size] square, for a job of its ([markedPlugin] must have found it). [colour] is the kind's, for a
/// plugin that wears its glyph; [tile] draws Google Meet's on its own colour, as the Market's tile does; [dim] is a
/// job that waits.
class JobMark extends StatelessWidget {
  const JobMark({super.key, required this.plugin, required this.size, required this.colour, this.tile = false, this.dim = false});

  final String plugin;
  final double size;
  final Color colour;
  final bool tile;
  final bool dim;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final found = markedPlugin(plugin);
    final Widget drawn;
    if (found == null) {
      drawn = const SizedBox.shrink();
    } else {
      final mark = brandOfId(plugin);
      final calm = activityCalm(t);
      final ink = t.color('glacier-text');
      if (mark == null) {
        drawn = AppIcon(pluginLucide(found), size: size, color: calm ? ink : colour, strokeWidth: 2.1);
      } else if (tile && marksOnTile(plugin, t)) {
        final radius = size / 2;
        drawn = DecoratedBox(
          decoration: pluginTile(found, radius: radius),
          child: Stack(
            fit: StackFit.expand,
            children: [
              tileLight(radius: radius),
              Center(child: BrandMarkIcon(mark, size: size * 0.6, color: const Color(0xFFFFFFFF))),
            ],
          ),
        );
      } else {
        drawn = BrandMarkIcon(mark, size: size, color: calm ? ink : brandInkOn(mark, ground: t.color('app-paper'), ink: ink));
      }
    }
    return ExcludeSemantics(
      child: SizedBox.square(
        key: ValueKey('job-mark:$plugin'),
        dimension: size,
        child: dim ? Opacity(opacity: 0.45, child: drawn) : drawn,
      ),
    );
  }
}
