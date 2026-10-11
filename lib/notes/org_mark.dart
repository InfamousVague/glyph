import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../sheet/css.dart';

/// The small mark an organization's workspace wears before its name (docs/TEAMS.md, D5): on its pill, its chip and
/// its row in the home filters, and its folder in the sidebar (note_tree.dart). A port of `src/app/notes/OrgMark.tsx`
/// and `OrgMark.module.css`.
///
/// An organization's name can be a personal workspace's too, so two pills called Ghost are told apart by this. The
/// kit's group of three, a touch under the text's size, in the words' own colour.
///
/// What differs: [em] and [color] are the text's size and colour where it stands, which the page's `em` and
/// `currentColor` read for themselves; left out, they are the [DefaultTextStyle]'s here. One widget for the sidebar
/// and the home page (lib/home/marks.dart hands it on), which each drew their own until 2026-10-09.
class OrgMark extends StatelessWidget {
  const OrgMark({super.key, this.em, this.color, this.size});

  /// The font size of the words it stands before.
  final double? em;
  final Color? color;

  /// Its box, where a rule sets one over the mark's own 0.9em (the home filters' `.choiceMark`, 1em).
  final double? size;

  /// The mark in a line of text, as the page's inline `svg` is: `vertical-align: -0.1em`, then its
  /// `margin-inline-end: 0.35em` before the words.
  static InlineSpan span({required double em, required Color color}) => WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: Transform.translate(offset: Offset(0, 0.1 * em), child: OrgMark(em: em, color: color)),
      );

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    final text = em ?? style.fontSize ?? context.tokens.fontSize('md');
    final ink = color ?? style.color ?? context.tokens.color('glacier-text');
    return Padding(
      // `margin-inline-end: 0.35em`
      padding: EdgeInsetsDirectional.only(end: 0.35 * text),
      child: Semantics(
        // `aria-label="Organization" role="img"`
        label: 'Organization',
        image: true,
        // `inline-size: 0.9em; block-size: 0.9em; color: currentColor; opacity: 0.85`
        child: ExcludeSemantics(child: lucide(Lucide.userGroup, size: size ?? 0.9 * text, strokeWidth: 2.2, color: ink.withValues(alpha: ink.a * 0.85))),
      ),
    );
  }
}
