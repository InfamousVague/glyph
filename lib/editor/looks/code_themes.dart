/// Colours for code in a note. Ports `src/app/editor/codeThemes.ts` (the names) and `codeThemes.css` (the palettes):
/// the custom properties a fenced block and its tokens are drawn with, chosen for each side of the page's theme
/// by `data-code-light` and `data-code-dark` on the root.
///
/// What differs: the page reads `--code-*` from the stylesheet; codeThemes.css is not one of the sheets the token
/// engine loads (tool/sync-design.sh), so the palettes are written out here and resolved through the tokens they
/// name. The stylesheet writes every dark palette twice, for an explicit Dark and for System on a dark phone; here
/// the theme's side is asked once (`Tokens.isDark`). The tokens are found by lib/editor/code.
library;

import 'package:flutter/painting.dart' show Color;
import 'package:glacier/glacier.dart';

/// codeThemes.ts `CODE_THEMES_LIGHT`: value and label.
const List<(String value, String label)> codeThemesLight = <(String, String)>[('pastel', 'Pastel'), ('ink', 'Ink'), ('github', 'GitHub'), ('solarized', 'Solarized')];

/// codeThemes.ts `CODE_THEMES_DARK`. (`isCodeThemeLight` and `isCodeThemeDark` are lib/core/preferences.dart's.)
const List<(String value, String label)> codeThemesDark = <(String, String)>[
  ('pastel', 'Pastel'),
  ('ink', 'Ink'),
  ('one-dark', 'One Dark'),
  ('dracula', 'Dracula'),
  ('nord', 'Nord'),
];

// `:root { ... }`: ink, the base every palette is written over.
const Map<String, String> _ink = <String, String>{
  'bg': 'color-mix(in oklch, var(--glacier-text) 7%, var(--glacier-bg))',
  'fg': 'var(--glacier-text)',
  'keyword': 'var(--glacier-text)',
  'string': 'var(--glacier-text-muted)',
  'comment': 'var(--glacier-text-subtle)',
  'type': 'var(--glacier-text)',
  'property': 'var(--glacier-text-muted)',
  'name': 'var(--glacier-text)',
  'literal': 'var(--glacier-text)',
  'punctuation': 'var(--glacier-text-muted)',
  'macro': 'var(--glacier-text)',
  'meta': 'var(--glacier-text-muted)',
};

// `:root[data-code-light='...']`
const Map<String, Map<String, String>> _light = <String, Map<String, String>>{
  'pastel': <String, String>{
    'fg': 'var(--glacier-text)',
    'keyword': 'oklch(0.52 0.13 330)',
    'string': 'oklch(0.52 0.11 155)',
    'comment': 'oklch(0.6 0.02 260)',
    'type': 'oklch(0.55 0.12 70)',
    'property': 'oklch(0.52 0.12 25)',
    'name': 'oklch(0.5 0.12 250)',
    'literal': 'oklch(0.55 0.13 45)',
    'punctuation': 'var(--glacier-text-muted)',
    'macro': 'oklch(0.52 0.1 200)',
    'meta': 'oklch(0.5 0.1 295)',
  },
  'ink': <String, String>{},
  'github': <String, String>{
    'fg': '#1f2328',
    'keyword': '#cf222e',
    'string': '#0a3069',
    'comment': '#6e7781',
    'type': '#953800',
    'property': '#0550ae',
    'name': '#8250df',
    'literal': '#0550ae',
    'punctuation': '#1f2328',
    'macro': '#8250df',
    'meta': '#116329',
  },
  'solarized': <String, String>{
    'fg': '#586e75',
    'keyword': '#859900',
    'string': '#2aa198',
    'comment': '#93a1a1',
    'type': '#b58900',
    'property': '#268bd2',
    'name': '#268bd2',
    'literal': '#d33682',
    'punctuation': '#657b83',
    'macro': '#cb4b16',
    'meta': '#6c71c4',
  },
};

// `:root[data-theme='dark'][data-code-dark='...']`
const Map<String, Map<String, String>> _dark = <String, Map<String, String>>{
  'pastel': <String, String>{
    'fg': 'var(--glacier-text)',
    'keyword': 'oklch(0.82 0.1 330)',
    'string': 'oklch(0.86 0.09 155)',
    'comment': 'oklch(0.62 0.02 260)',
    'type': 'oklch(0.88 0.08 85)',
    'property': 'oklch(0.84 0.07 30)',
    'name': 'oklch(0.84 0.07 245)',
    'literal': 'oklch(0.85 0.08 55)',
    'punctuation': 'var(--glacier-text-muted)',
    'macro': 'oklch(0.85 0.07 200)',
    'meta': 'oklch(0.8 0.08 295)',
  },
  'ink': <String, String>{},
  'one-dark': <String, String>{
    'fg': '#abb2bf',
    'keyword': '#c678dd',
    'string': '#98c379',
    'comment': '#7f848e',
    'type': '#e5c07b',
    'property': '#e06c75',
    'name': '#61afef',
    'literal': '#d19a66',
    'punctuation': '#abb2bf',
    'macro': '#56b6c2',
    'meta': '#d19a66',
  },
  'dracula': <String, String>{
    'fg': '#f8f8f2',
    'keyword': '#ff79c6',
    'string': '#f1fa8c',
    'comment': '#6272a4',
    'type': '#8be9fd',
    'property': '#50fa7b',
    'name': '#50fa7b',
    'literal': '#bd93f9',
    'punctuation': '#f8f8f2',
    'macro': '#ffb86c',
    'meta': '#ffb86c',
  },
  'nord': <String, String>{
    'fg': '#d8dee9',
    'keyword': '#81a1c1',
    'string': '#a3be8c',
    'comment': '#616e88',
    'type': '#8fbcbb',
    'property': '#88c0d0',
    'name': '#88c0d0',
    'literal': '#b48ead',
    'punctuation': '#eceff4',
    'macro': '#d08770',
    'meta': '#d08770',
  },
};

/// The code theme in force: `--code-<name>` for the page's side, as a colour.
class CodeTheme {
  CodeTheme._(this._t, this._values, this.name);

  /// The theme the root's `data-code-light` / `data-code-dark` name for the side `t` is on. A name the stylesheet
  /// has no palette for leaves ink, as a missing attribute does there.
  factory CodeTheme.of(Tokens t) {
    final name = t.attrs[t.isDark ? 'code-dark' : 'code-light'];
    final palette = (t.isDark ? _dark : _light)[name] ?? const <String, String>{};
    return CodeTheme._(t, <String, String>{..._ink, ...palette}, name ?? 'ink');
  }

  final Tokens _t;
  final Map<String, String> _values;
  final String name;
  final Map<String, Color> _colors = <String, Color>{};

  /// `--code-<name>`: bg, fg, keyword, string, comment, type, property, name, literal, punctuation, macro, meta.
  Color color(String name) => _colors.putIfAbsent(name, () => _t.colorOf(_values[name]!));

  /// `--code-keyword-weight`: bold in ink, which shows the shape of code in weight; `inherit` (null) in a coloured
  /// theme.
  double? get keywordWeight => _inkWeights ? _t.len('glacier-font-weight-bold') : null;

  /// `--code-name-weight`.
  double? get nameWeight => _inkWeights ? _t.len('glacier-font-weight-medium') : null;

  bool get _inkWeights => !_values.containsKey('keyword') || _values['keyword'] == _ink['keyword'];
}
