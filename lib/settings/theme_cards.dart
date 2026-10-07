import 'package:flutter/widgets.dart';
import 'package:glacier/glacier.dart';

import '../core/preferences.dart';
import 'choice_card.dart';
import 'kit/settings_icons.dart';
import 'kit/settings_type.dart';
import 'words.dart';

/// Each theme's colours, for the cards that choose one (`ThemePreviewPalette`, @glacier/tokens): what the page would
/// look like, painted small.
@immutable
class ThemePalette {
  const ThemePalette({required this.background, required this.sidebar, required this.surface, required this.border, required this.text, required this.muted, required this.accent});

  final Color background;
  final Color sidebar;
  final Color surface;
  final Color border;
  final Color text;
  final Color muted;
  final Color accent;
}

/// One card of the theme chooser (`ThemeOption`, themePalettes.ts).
@immutable
class ThemeOption {
  const ThemeOption({required this.value, required this.label, required this.description, required this.palette, this.alternatePalette});

  final String value;
  final String label;
  final String description;
  final ThemePalette palette;

  /// Painted over the right half: the dark side of System.
  final ThemePalette? alternatePalette;
}

/// `INK_LIGHT` (themePalettes.ts): Ghost.md's own ink scale by day, chroma zero, with the accent whatever the app's
/// accent is right now, so the cards follow the swatch below them.
ThemePalette inkLight(Tokens t) => ThemePalette(
  background: t.colorOf('oklch(0.995 0 0)'),
  sidebar: t.colorOf('oklch(0.975 0 0)'),
  surface: t.colorOf('oklch(0.955 0 0)'),
  border: t.colorOf('oklch(0.925 0 0)'),
  text: t.colorOf('oklch(0.16 0 0)'),
  muted: t.colorOf('oklch(0.56 0 0)'),
  accent: t.color('glacier-accent-solid'),
);

/// `INK_DARK`: the same page in reverse by night.
ThemePalette inkDark(Tokens t) => ThemePalette(
  background: t.colorOf('oklch(0.11 0 0)'),
  sidebar: t.colorOf('oklch(0.14 0 0)'),
  surface: t.colorOf('oklch(0.17 0 0)'),
  border: t.colorOf('oklch(0.205 0 0)'),
  text: t.colorOf('oklch(0.965 0 0)'),
  muted: t.colorOf('oklch(0.6 0 0)'),
  accent: t.color('glacier-accent-solid'),
);

/// A named theme's preview as the kit makes it (`previewPalette`, @glacier/tokens theme-presets.ts): steps 1, 2, 6,
/// 12 and 11 of the theme's tinted greys, white for a light theme's surface and step 3 for a dark one's, and step 9
/// of the accent that comes with it. The web takes these from the kit's TypeScript; here they are read from the
/// kit's stylesheet, where the same ramps are written under `data-theme-preset` and `data-accent`.
ThemePalette presetPalette(Tokens t, String id) {
  final info = themePresets[id]!;
  final kit = t.rootTokens.child(attrs: {'theme': info.scheme, 'theme-preset': id, 'accent': info.accent});
  return ThemePalette(
    background: kit.color('glacier-gray-1'),
    sidebar: kit.color('glacier-gray-2'),
    surface: info.scheme == 'light' ? t.colorOf('oklch(0.995 0 0)') : kit.color('glacier-gray-3'),
    border: kit.color('glacier-gray-6'),
    text: kit.color('glacier-gray-12'),
    muted: kit.color('glacier-gray-11'),
    accent: kit.color('glacier-accent-9'),
  );
}

/// `THEME_OPTIONS` (themePalettes.ts): every theme the app has, System first and split into its light and dark
/// halves. A named theme's line says which side of the page it is and the accent it brings: "Light, with red".
List<ThemeOption> themeOptions(Tokens t) {
  final light = inkLight(t), dark = inkDark(t);
  return [
    ThemeOption(value: 'system', label: themeWords['system']!, description: 'Follows the phone', palette: light, alternatePalette: dark),
    ThemeOption(value: 'light', label: themeWords['light']!, description: 'Ink on paper', palette: light),
    ThemeOption(value: 'dark', label: themeWords['dark']!, description: 'Paper on ink', palette: dark),
    for (final id in themePresets.keys)
      ThemeOption(value: id, label: themeWords[id]!, description: '${themePresets[id]!.scheme == 'light' ? 'Light' : 'Dark'}, with ${accentWords[themePresets[id]!.accent]!.toLowerCase()}', palette: presetPalette(t, id)),
  ];
}

/// Port of `ThemeCards` (src/app/settings/ThemeCards.tsx, ThemeCards.module.css, themePalettes.ts): the theme chooser
/// as a grid of radio cards, each a miniature of the app painted in that theme's colours, System split down the
/// middle, light on the left and dark on the right. The miniature is Ghost.md's note page: a top bar with the back
/// word and two tabs, a note (its heading, its lines, a to-do with its box), a pair of segments with the chosen one
/// in the accent, and the Speak pill at the foot. The chosen card is ringed and ticked, never colour alone.
///
/// What differs from the web original: the named themes' colours are read from the kit's stylesheet ([presetPalette]).
class ThemeCards extends StatelessWidget {
  const ThemeCards({super.key, required this.value, required this.onValueChange});

  final String value;
  final ValueChanged<String> onValueChange;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final options = themeOptions(t);
    final byValue = {for (final option in options) option.value: option};
    return ChoiceCards<String>(
      label: 'Theme',
      values: [for (final option in options) option.value],
      value: value,
      onValueChange: onValueChange,
      nameOf: (value) => byValue[value]!.label,
      radius: t.radius('lg'),
      // System leads, full width: the one most people should take, with the manual choices paired beneath it.
      layout: (context, cards) => ChoiceGrid(columns: 2, gap: t.space(3), leadSpan: true, children: cards),
      card: (context, value, selected) {
        final option = byValue[value]!;
        return ChoiceCardBody(
          // `.preview`: 6.5rem with its hairline under it.
          picture: Container(
            height: t.lenOf('6.5rem'),
            decoration: BoxDecoration(
              color: option.palette.background,
              border: Border(
                bottom: BorderSide(color: option.palette.border, width: t.len('glacier-hairline')),
              ),
            ),
            child: ClipRect(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Scene(palette: option.palette),
                  // The dark half of System: the same scene, clipped to the right.
                  if (option.alternatePalette != null)
                    ClipRect(
                      clipper: const _RightHalf(),
                      child: _Scene(palette: option.alternatePalette!),
                    ),
                ],
              ),
            ),
          ),
          // `.meta`: the words under it, and the tick.
          words: Padding(
            padding: EdgeInsets.all(t.space(3)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        option.label,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: pageText(t, t.fontSize('sm'), weight: 'semibold', height: t.len('glacier-leading-sm')),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        option.description,
                        style: pageText(t, t.fontSize('xs'), height: t.len('glacier-leading-sm'), color: t.color('glacier-text-muted')),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: t.space(2)),
                ChoiceTick(
                  selected: selected,
                  size: t.lenOf('1.25rem'),
                  border: t.color('glacier-border'),
                  borderWidth: t.len('glacier-hairline'),
                  tick: t.color('glacier-accent-contrast'),
                  child: const SettingsIcon(SettingsGlyph.check, size: 12, strokeWidth: 2.5),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// `clip-path: inset(0 0 0 50%)`.
class _RightHalf extends CustomClipper<Rect> {
  const _RightHalf();

  @override
  Rect getClip(Size size) => Rect.fromLTRB(size.width / 2, 0, size.width, size.height);

  @override
  bool shouldReclip(_RightHalf old) => false;
}

/// Ghost.md, painted small: the note page with its bar, its words and its pill (`Scene`). Every colour is the
/// palette's, so the card shows the theme, not the page.
class _Scene extends StatelessWidget {
  const _Scene({required this.palette});
  final ThemePalette palette;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    double rem(double n) => t.lenOf('${n}rem');
    final p = palette;
    Widget pill(double width, double height, Color color, {double opacity = 1}) => Opacity(
      opacity: opacity,
      child: Container(
        width: width,
        height: height,
        decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      ),
    );
    Widget line(double fraction) => FractionallySizedBox(
      widthFactor: fraction,
      alignment: AlignmentDirectional.centerStart,
      child: Opacity(
        opacity: 0.6,
        child: Container(
          height: rem(0.24),
          decoration: ShapeDecoration(color: p.muted, shape: const StadiumBorder()),
        ),
      ),
    );
    Widget tab({required bool active}) => Container(
      width: rem(1.4),
      height: rem(0.5),
      decoration: ShapeDecoration(
        color: active ? p.text : p.surface,
        shape: StadiumBorder(
          side: BorderSide(color: active ? p.text : p.border, strokeAlign: BorderSide.strokeAlignInside),
        ),
      ),
    );
    return ColoredBox(
      color: p.background,
      // `grid-template-rows: 1.2rem 1fr 1.1rem`
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: rem(1.2),
            padding: EdgeInsets.symmetric(horizontal: rem(0.5)),
            decoration: BoxDecoration(
              color: p.sidebar,
              border: Border(bottom: BorderSide(color: p.border)),
            ),
            child: Row(
              children: [
                pill(rem(0.9), rem(0.26), p.muted, opacity: 0.7),
                SizedBox(width: rem(0.2) + rem(0.3)),
                tab(active: true),
                SizedBox(width: rem(0.3)),
                tab(active: false),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.fromLTRB(rem(0.6), rem(0.55), rem(0.6), rem(0.3)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.46,
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      height: rem(0.36),
                      decoration: ShapeDecoration(color: p.text, shape: const StadiumBorder()),
                    ),
                  ),
                  SizedBox(height: rem(0.34)),
                  line(0.86),
                  SizedBox(height: rem(0.34)),
                  line(0.58),
                  SizedBox(height: rem(0.34)),
                  Row(
                    children: [
                      Container(
                        width: rem(0.42),
                        height: rem(0.42),
                        decoration: BoxDecoration(
                          border: Border.all(color: p.text),
                          borderRadius: BorderRadius.circular(rem(0.1)),
                        ),
                      ),
                      SizedBox(width: rem(0.3)),
                      // 58% of the to-do's own width, as the line beside the box is on the page.
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, box) => Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: SizedBox(width: (box.maxWidth + rem(0.42) + rem(0.3)) * 0.58, child: line(1)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  // `margin-block-start: auto`: the segments stand on the note's foot.
                  const Spacer(),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Container(
                      width: rem(2.6),
                      padding: const EdgeInsets.all(1),
                      decoration: ShapeDecoration(
                        color: p.surface,
                        shape: StadiumBorder(
                          side: BorderSide(color: p.border, strokeAlign: BorderSide.strokeAlignInside),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Two segments, the chosen one in the accent: the one place the accent shows on the page.
                          Expanded(
                            child: Container(
                              height: rem(0.42),
                              decoration: ShapeDecoration(color: p.accent, shape: const StadiumBorder()),
                            ),
                          ),
                          const SizedBox(width: 1),
                          Expanded(child: SizedBox(height: rem(0.42))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // The Speak pill at the foot, in the page's ink.
          SizedBox(
            height: rem(1.1),
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                width: rem(2.2),
                height: rem(0.7),
                decoration: ShapeDecoration(color: p.text, shape: const StadiumBorder()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
