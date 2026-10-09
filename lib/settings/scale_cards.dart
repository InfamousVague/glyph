import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import 'choice_card.dart';
import 'kit/settings_type.dart';
import 'words.dart';

/// Port of `ScaleCards` (src/app/settings/ScaleCards.tsx, ScaleCards.module.css): interface size as cards, one per
/// step, and inside each the same small piece of the app (a row with its icon, its two lines and its switch) drawn
/// at that size, so what a step does is seen before it is chosen. The piece is sized in em from a font size that is
/// the step, so it grows and shrinks exactly as the app would.
///
/// What differs from the web original: the chosen card's word is drawn. On the page it is painted in the page's
/// paper on the card's paper and cannot be read: ink.css's rule for the kit's segmented control
/// (`[role='radiogroup'] > label[data-selected] > span:last-child`) matches this card's structure too, and outranks
/// the card's own `.option[data-selected] .label`. The rule the card wrote for itself is the one kept here.
class ScaleCards extends StatelessWidget {
  const ScaleCards({super.key, required this.value, required this.onValueChange});

  final double value;
  final ValueChanged<double> onValueChange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final hairline = t.len('glacier-hairline');
    return ChoiceCards<double>(
      label: 'Interface size',
      values: uiScales,
      value: value,
      onValueChange: (scale) {
        if (isUiScale(scale)) onValueChange(scale);
      },
      nameOf: (scale) => scaleWords[scale]!,
      radius: t.radius('md'),
      layout: (context, cards) => ChoiceGrid(columns: uiScales.length, gap: t.space(2), children: cards),
      card: (context, scale, selected) => Padding(
        padding: EdgeInsets.only(bottom: t.space(2)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The piece of the app, in a fixed-height window so the five cards line up whatever their step.
            Container(
              height: t.lenOf('3.25rem'),
              decoration: BoxDecoration(
                color: t.color('app-paper-2'),
                border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: hairline)),
              ),
              child: ClipRect(child: _Piece(em: t.lenOf('${scale}rem'))),
            ),
            SizedBox(height: t.space(1)),
            ExactLines.of(
              Text(
                scaleWords[scale]!,
                textAlign: TextAlign.center,
                style: pageText(t, t.fontSize('xs'), weight: 'semibold', height: t.len('glacier-leading-sm'), color: t.color(selected ? 'glacier-text' : 'glacier-text-muted')),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// `.piece`: a row of the app at one step. `inline-size: 3.4em; max-inline-size: calc(100% - 0.6rem)`, centred in a
/// grid whose one column is as wide as the window or as the piece wants, whichever is more: so past the step where
/// the piece outgrows its card it keeps 0.3rem from the window's start and runs out under its end, as on the page.
class _Piece extends StatelessWidget {
  const _Piece({required this.em});
  final double em;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final ink = t.color('app-ink');
    final inset = t.lenOf('0.3rem');
    return LayoutBuilder(
      builder: (context, box) {
        final track = math.max(box.maxWidth, 3.4 * em);
        final width = math.min(3.4 * em, track - 2 * inset);
        return OverflowBox(
          alignment: AlignmentDirectional.centerStart,
          minWidth: 0,
          maxWidth: double.infinity,
          child: Padding(
            padding: EdgeInsetsDirectional.only(start: (track - width) / 2),
            child: SizedBox(
              width: width,
              child: Row(
                children: [
                  Container(width: 0.7 * em, height: 0.7 * em, decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(0.18 * em))),
                  SizedBox(width: 0.3 * em),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(height: 0.22 * em, decoration: ShapeDecoration(color: ink, shape: const StadiumBorder())),
                        SizedBox(height: 0.18 * em),
                        FractionallySizedBox(
                          widthFactor: 0.6,
                          child: Opacity(opacity: 0.45, child: Container(height: 0.22 * em, decoration: ShapeDecoration(color: ink, shape: const StadiumBorder()))),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 0.3 * em),
                  Container(
                    width: 0.95 * em,
                    height: 0.55 * em,
                    padding: EdgeInsets.all(0.07 * em),
                    alignment: AlignmentDirectional.centerEnd,
                    decoration: ShapeDecoration(color: t.color('glacier-accent-solid'), shape: const StadiumBorder()),
                    child: Container(width: 0.41 * em, height: 0.41 * em, decoration: BoxDecoration(color: t.color('app-paper'), shape: BoxShape.circle)),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
