/// The editor's own styling: what `src/app/editor/glyphTheme.ts` sets on the selectors CodeMirror generates, as
/// values the view and its lines read.
///
/// glyphTheme.ts is an `EditorView.theme`: a stylesheet over `.cm-editor`, `.cm-scroller`, `.cm-content` and
/// `::selection`. Here there are no such elements, so each declaration lands where its element's job went:
/// - `&  { background-color: var(--glacier-bg); color: var(--glacier-text) }`: [GlyphTheme.paper] for whoever
///   paints behind the editor, and the root of the look's cascade (`Props.root`);
/// - `.cm-scroller { font-family: var(--app-note-font, ...); font-size: var(--app-body); line-height: 1.6 }`: the
///   root of the cascade too (`LookEnv.noteFamilies`, `LookEnv.body`);
/// - `.cm-content { padding: var(--glacier-space-5) 0 var(--glacier-space-24); caret-color:
///   var(--glacier-accent-solid) }`: `LookEnv.contentTop`/`contentBottom` and [GlyphTheme.caret];
/// - `.cm-line ::selection` and the `[data-me-hue]` rules of `ownSelection`: [GlyphTheme.selectionInk] and
///   [GlyphTheme.selectionPaper];
/// - `.cm-placeholder { color: var(--glacier-text-subtle) }`: [GlyphTheme.placeholder].
///
/// What differs: `overflow-y`, `overscroll-behavior`, `height: 100%` and the focus outline are the scroll view's
/// and the note screen's. The selection is painted by the line (the web keeps the browser's own selection so its
/// handles and magnifier are real; here the input layer draws those), in the same literal colours: the page's ink
/// and paper as ink.css sets them, since a highlight could not read the tokens there. The theme is not a
/// compartment to reconfigure: it is read from the tokens each time the look is made, so the page's side changing
/// retunes the editor by itself.
library;

import 'package:flutter/painting.dart' show Color;
import '../looks/look.dart';

/// glyphTheme.ts `HUE_ANGLES`: the hues a person may wear, and their angles.
const Map<String, double> hueAngles = <String, double>{'ember': 32, 'amber': 75, 'moss': 150, 'sea': 230, 'violet': 295, 'rose': 355};

/// The values of glyphTheme.ts for one side of the page.
class GlyphTheme {
  GlyphTheme._(this.paper, this.ink, this.caret, this.placeholder, this.selectionInk, this.selectionPaper);

  /// The theme for the look's tokens and its side. `LookEnv.meHue` is `data-me-hue` round the editor.
  factory GlyphTheme.of(LookEnv env) {
    final t = env.t;
    // SELECTION_INK = ['oklch(0.16 0 0)', 'oklch(0.965 0 0)'], SELECTION_PAPER = ['oklch(0.995 0 0)', 'oklch(0.11 0 0)']
    final paper = t.colorOf(env.dark ? 'oklch(0.11 0 0)' : 'oklch(0.995 0 0)');
    var ink = t.colorOf(env.dark ? 'oklch(0.965 0 0)' : 'oklch(0.16 0 0)');
    final angle = hueAngles[env.meHue];
    // ownSelection: `oklch(0.78 0.13 <angle>)` on the dark page, `oklch(0.55 0.14 <angle>)` on the light.
    if (angle != null) ink = t.colorOf(env.dark ? 'oklch(0.78 0.13 $angle)' : 'oklch(0.55 0.14 $angle)');
    return GlyphTheme._(t.color('glacier-bg'), t.color('glacier-text'), t.color('glacier-accent-solid'), t.color('glacier-text-subtle'), ink, paper);
  }

  /// `&  { background-color: var(--glacier-bg) }`.
  final Color paper;

  /// `& { color: var(--glacier-text) }`.
  final Color ink;

  /// `.cm-content { caret-color: var(--glacier-accent-solid) }`.
  final Color caret;

  /// `.cm-placeholder { color: var(--glacier-text-subtle) }`.
  final Color placeholder;

  /// The ground of selected text.
  final Color selectionInk;

  /// Selected words.
  final Color selectionPaper;
}
