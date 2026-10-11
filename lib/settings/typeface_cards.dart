import 'package:flutter/rendering.dart' show OverflowBoxFit;
import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import 'choice_card.dart';
import 'kit/settings_type.dart';
import 'words.dart';

/// The family each face is set in (`FAMILIES`, TypefaceCards.tsx; typefaces.css registers them).
const Map<String, String> typefaceFamilies = {
  'maple': 'Maple Mono',
  'fira': 'Fira Code Variable',
  'inter': 'Inter Variable',
  'noto': 'Noto Sans Variable',
  'plex': 'IBM Plex Sans',
};

/// The families whose files the app ships (pubspec.yaml). A card for any other face is drawn in the page's own sans,
/// the first of the stylesheet's fallbacks (`ui-sans-serif, system-ui, sans-serif`), rather than in whatever the
/// device would put in its place. Add a family here when its file is added.
const Set<String> shippedFamilies = {'Maple Mono', 'Fira Code Variable', 'Inter Variable', 'Noto Sans Variable', 'IBM Plex Sans'};

/// Whether a card previews Markdown, for the note's face, or the app's own words, for the interface's (`kind`).
enum TypefaceKind { note, interface }

/// Port of `TypefaceCards` (src/app/settings/TypefaceCards.tsx, TypefaceCards.module.css): typefaces as small cards,
/// for either of the two faces the app is set in. A note face's card sets the same scrap of a note in it (a heading
/// with its hash, an ampersand, bold between its stars, and the pairs a coding face joins into one sign) with the
/// marks dimmed as the editor dims them. An interface face's card sets a scrap of the app's own words instead: a
/// title and a row of tabs.
///
/// The app ships all five (pubspec.yaml, tool/fonts.py), so each card is its own face.
class TypefaceCards extends StatelessWidget {
  const TypefaceCards({super.key, required this.faces, required this.value, required this.onValueChange, required this.label, required this.kind});

  final List<String> faces;
  final String value;
  final ValueChanged<String> onValueChange;

  /// What the choice is, for a screen reader.
  final String label;
  final TypefaceKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final gap = t.space(2);
    return ChoiceCards<String>(
      label: label,
      values: faces,
      value: value,
      onValueChange: onValueChange,
      nameOf: (face) => faceWords[face]!,
      radius: t.radius('md'),
      // `grid-template-columns: repeat(auto-fill, minmax(10rem, 1fr))`: as many to a row as fit, each wide enough
      // for the heading in a monospace face.
      layout: (context, cards) => LayoutBuilder(
        builder: (context, box) {
          final least = t.lenOf('10rem');
          final columns = ((box.maxWidth + gap) / (least + gap)).floor().clamp(1, cards.length);
          return ChoiceGrid(columns: columns, gap: gap, children: cards);
        },
      ),
      card: (context, face, selected) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: EdgeInsets.all(gap),
            decoration: BoxDecoration(
              color: t.color('app-paper-2'),
              border: Border(bottom: BorderSide(color: t.color('glacier-border-subtle'), width: t.len('glacier-hairline'))),
            ),
            child: _Sample(face: face, kind: kind),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(gap, t.space(1), gap, gap),
            child: ExactLines.of(
              Text(
                faceWords[face]!,
                style: pageText(t, t.fontSize('xs'), weight: 'semibold', height: t.len('glacier-leading-sm'), color: t.color(selected ? 'glacier-text' : 'glacier-text-muted')),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.sample`: the scrap of a note, or of the app, in the card's own face.
class _Sample extends StatelessWidget {
  const _Sample({required this.face, required this.kind});
  final String face;
  final TypefaceKind kind;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final coding = isCodingFace(face) && shippedFamilies.contains(typefaceFamilies[face]);
    final ink = t.color('app-ink');
    final muted = t.color('glacier-text-muted');
    // `font-family: <the face>, ui-sans-serif, system-ui, sans-serif`
    final sans = [for (final f in t.families('glacier-font-sans')) if (shippedFamilies.contains(f)) f, 'Inter Variable'];
    final shipped = shippedFamilies.contains(typefaceFamilies[face]);
    final family = shipped ? typefaceFamilies[face]! : sans.first;
    final rest = [...?t.typography.fallbacks[family], ...sans.where((f) => f != family), ...?t.typography.fallbacks['Inter Variable']];
    double rem(double n) => t.lenOf('${n}rem');

    /// Text of the sample at [size] rem: the card's face, and for a coding face its own features and no spacing, so
    /// `->` joins.
    TextStyle set(double size, {String weight = 'regular', double height = 1.25, Color? color}) {
      final base = pageText(t, rem(size), weight: weight, height: height, color: color ?? ink, mono: coding);
      return base.copyWith(
        fontFamily: family,
        fontFamilyFallback: rest,
        fontFeatures: coding ? const [FontFeature('calt'), FontFeature('liga')] : pageText(t, rem(size)).fontFeatures,
        fontVariations: coding ? [FontVariation('wght', t.len('glacier-font-weight-$weight'))] : base.fontVariations,
      );
    }

    final List<Widget> lines;
    if (kind == TypefaceKind.note) {
      final heading = set(0.95, weight: 'bold');
      final line = set(0.78, height: 1.3);
      lines = [
        Text.rich(
          TextSpan(children: [TextSpan(text: '#', style: set(0.95, color: muted)), const TextSpan(text: ' Quick & Foxy')]),
          style: heading,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: rem(0.2)),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '**', style: set(0.78, height: 1.3, color: muted)),
            TextSpan(text: 'bold', style: set(0.78, weight: 'bold', height: 1.3)),
            TextSpan(text: '**', style: set(0.78, height: 1.3, color: muted)),
            const TextSpan(text: ' -> != <='),
          ]),
          style: line,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
      ];
    } else {
      final tab = set(0.72, height: 1.3, color: muted);
      Widget pill(String word, {bool on = false}) => Container(
            padding: EdgeInsets.symmetric(vertical: rem(0.05), horizontal: rem(0.4)),
            decoration: ShapeDecoration(
              color: on ? t.colorOf('color-mix(in srgb, var(--glacier-text) 10%, transparent)') : const Color(0x00000000),
              shape: const StadiumBorder(),
            ),
            child: Text(word, style: on ? tab.copyWith(color: ink) : tab),
          );
      lines = [
        Text('Notes & Notebooks', style: set(0.95, weight: 'semibold'), maxLines: 1, softWrap: false, overflow: TextOverflow.ellipsis),
        SizedBox(height: rem(0.2)),
        ClipRect(
          child: OverflowBox(
            alignment: AlignmentDirectional.centerStart,
            minWidth: 0,
            maxWidth: double.infinity,
            fit: OverflowBoxFit.deferToChild,
            child: Row(mainAxisSize: MainAxisSize.min, children: [pill('Today', on: true), SizedBox(width: rem(0.35)), pill('Recent'), SizedBox(width: rem(0.35)), pill('Settings')]),
          ),
        ),
      ];
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: lines);
  }
}
