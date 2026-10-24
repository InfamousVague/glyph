/// Marks: the formatting Ghost.md adds to Markdown, all of it in one list. Ports `src/app/plugins/marks/index.tsx`
/// and the part of `src/app/plugins/types.ts` a mark is made of (`InlineFormat`, `FormatLook`).
///
/// Twelve marks, each its delimiter and its look: the spoiler blurs (`lib/editor/marks/wisp_format.dart`),
/// the five effects (heat, frost, wave, shimmer, haunt) are drawn by `lib/editor/marks/text_effects.dart`, each
/// written as its emoji twice either side, and the rest are CSS on the words
/// (`lib/editor/marks/format_looks.dart`), in ink and paper only. [marks] is the one list the parser
/// (`glyphMarkdown(marks)`), the highlighter and the looks all read: a [GlyphFormat] is an `InlineFormatSyntax`.
///
/// What differs:
/// - A style look's CSS is kept as the web writes it, word for word, and read by the small interpreter in
///   `lib/editor/marks/run_paint.dart` (`StyleCss`), which knows the properties these seven looks use and no
///   others. A plugin's own CSS beyond them is not drawn.
/// - The marks are a list the editor's parser can read without the plugin types; the plugin they are, with its one
///   switch in Settings > Plugins, is marks_plugin.dart, and "switched off" is the registry (registry.dart) leaving
///   them out of `formats()`.
/// - `icon` is the kit's icon by its Lucide name, for the Style page when the band is ported.
library;

import '../editor/syntax/language.dart' show InlineFormatSyntax;

/// How the text between a mark's delimiters looks (`plugins/types.ts` `FormatLook`).
sealed class FormatLook {
  const FormatLook();
}

/// The wisp's look: every letter blurred and breathing without rest, plain only while the caret is in the text. It
/// was smoke, every letter bent as well, until 2026-10-24.
class WispLook extends FormatLook {
  const WispLook();
}

/// A moving effect on the words, by name, from the effects the editor draws (`textEffects`).
class EffectLook extends FormatLook {
  const EffectLook(this.effect);
  final String effect;
}

/// A style on the text, as CSS. With [clearAtCaret] the style hides the words (a redaction's bar): it lifts while
/// the caret is in them, and until then nothing under it is drawn.
class StyleLook extends FormatLook {
  const StyleLook(this.css, {this.clearAtCaret = false});
  final String css;
  final bool clearAtCaret;
}

/// An inline formatting a plugin adds to the Markdown of notes (`plugins/types.ts` `InlineFormat`): the text
/// between two runs of [delimiter], drawn with [look].
class GlyphFormat implements InlineFormatSyntax {
  const GlyphFormat({required this.name, required this.delimiter, required this.look, this.cue, this.about, this.icon, this.tint});

  /// The node's name, capitalised, unique across plugins: "Spoiler".
  @override
  final String name;

  /// One to three of the same character, or an emoji twice, which is how an effect is written.
  @override
  final String delimiter;
  final FormatLook look;

  /// The word that says it while recording: "spoiler" for "spoiler … end spoiler".
  final String? cue;

  /// One line on what it is for, for the cheat sheet's table of marks.
  final String? about;

  /// Its own mark on the Style page: a Lucide icon's name.
  final String? icon;

  /// A name in brackets after the mark, turned into extra CSS for those words alone: `==the key==(green)`. Null
  /// for a name the mark does not know.
  final String? Function(String name)? tint;
}

/// The colours a highlight can be named, which are the kit's own ramps and nothing invented here.
const List<String> markColours = <String>['blue', 'red', 'amber', 'green', 'teal', 'purple', 'gray'];

bool isMarkColour(String name) => markColours.contains(name);

/// The wash for a named colour, or empty for a name this build does not know.
String washFor(String name) {
  final clean = name.trim().toLowerCase();
  if (!isMarkColour(clean)) return '';
  // Grey is the kit's own word for it; the token is spelled the American way.
  return 'color-mix(in oklch, var(--glacier-$clean-9) 34%, transparent)';
}

String? _highlightTint(String name) {
  final wash = washFor(name);
  return wash.isEmpty ? null : 'background: $wash; box-shadow: 0 0 0 0.12em $wash;';
}

/// The marks, in the order the Style page and the guide show them.
const List<GlyphFormat> marks = <GlyphFormat>[
  GlyphFormat(name: 'Spoiler', delimiter: '||', look: WispLook(), cue: 'spoiler', about: 'The words blur until you put the caret in them.', icon: 'eye-off'),
  GlyphFormat(
    name: 'Highlight',
    delimiter: '==',
    look: StyleLook('background: var(--app-mark, var(--app-wash)); border-radius: 0.2em; box-shadow: 0 0 0 0.12em var(--app-mark, var(--app-wash));'),
    cue: 'highlight',
    about: 'A wash of blue behind the words, for the line you will want again. Name a colour after it - ==this==(green) - for another.',
    icon: 'highlighter',
    tint: _highlightTint,
  ),
  GlyphFormat(
    name: 'Aside',
    delimiter: '%%',
    look: StyleLook('font-size: 0.88em; font-style: italic; color: var(--glacier-text-muted);'),
    cue: 'aside',
    about: 'A note to yourself inside the note: smaller, quieter, leaning.',
    icon: 'message-square-dashed',
  ),
  GlyphFormat(
    name: 'Unsure',
    delimiter: '??',
    look: StyleLook('text-decoration: underline dotted; text-decoration-color: var(--glacier-text-subtle); text-underline-offset: 0.22em; text-decoration-thickness: 0.09em;'),
    cue: 'unsure',
    about: 'A dotted line under a fact to check later. Add “(why)” after it and tapping the words shows that note.',
    icon: 'circle-question-mark',
  ),
  // The bar and the words are the same ink, so nothing shows through it on either side of the page. Square ended:
  // the bar is drawn in pieces where other marks sit inside it. Lifted while the caret is in the words.
  GlyphFormat(
    name: 'Redact',
    delimiter: '@@',
    look: StyleLook(
      'background: var(--glacier-text); color: var(--glacier-text); -webkit-text-fill-color: var(--glacier-text); box-shadow: 0 0 0 0.08em var(--glacier-text); filter: var(--app-ink-flat);',
      clearAtCaret: true,
    ),
    cue: 'redact',
    about: 'A solid bar of ink over the words, lifted while the caret is in them. A look only: a share still has the words.',
    icon: 'eraser',
  ),
  GlyphFormat(
    name: 'Shout',
    delimiter: '^^',
    look: StyleLook('font-variant-caps: all-small-caps; letter-spacing: 0.09em; font-weight: var(--glacier-font-weight-semibold);'),
    cue: 'shout',
    about: 'Spaced small capitals: emphasis that is not bold.',
    icon: 'megaphone',
  ),
  GlyphFormat(
    name: 'Added',
    delimiter: '++',
    look: StyleLook('text-decoration: underline; text-underline-offset: 0.18em; text-decoration-thickness: 0.11em;'),
    cue: 'added',
    about: 'A line under what was added, the pair of struck-through for what went.',
    icon: 'plus',
  ),
  // The first of the effects: an emoji twice either side, as every effect is written.
  GlyphFormat(
    name: 'Heat',
    delimiter: '🔥🔥',
    look: EffectLook('heat'),
    cue: 'heated',
    about: 'The words go bold, and the line above them wavers in the heat coming off them. Two flames either side: 🔥🔥too hot🔥🔥.',
    icon: 'flame',
  ),
  GlyphFormat(
    name: 'Frost',
    delimiter: '❄️❄️',
    look: EffectLook('frost'),
    cue: 'frosted',
    about: 'The words go cold, a rime creeping over their edges and settling. Two snowflakes either side: ❄️❄️frozen❄️❄️.',
    icon: 'snowflake',
  ),
  GlyphFormat(
    name: 'Wave',
    delimiter: '🌊🌊',
    look: EffectLook('wave'),
    cue: 'wavy',
    about: 'The words bob along the line, a ripple passing through them. Two waves either side: 🌊🌊out to sea🌊🌊.',
    icon: 'waves',
  ),
  GlyphFormat(
    name: 'Shimmer',
    delimiter: '✨✨',
    look: EffectLook('shimmer'),
    cue: 'shimmering',
    about: 'A glint slides across the words every few seconds. Two sparkles either side: ✨✨silver✨✨.',
    icon: 'sparkles',
  ),
  GlyphFormat(
    name: 'Haunt',
    delimiter: '👻👻',
    look: EffectLook('haunt'),
    cue: 'haunted',
    about: 'The words fade almost away and back, slowly, like something passing. Two ghosts either side: 👻👻nobody there👻👻.',
    icon: 'ghost',
  ),
];
