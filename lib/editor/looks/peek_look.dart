/// A note drawn small on a card. Ports `src/app/notes/NotePeek.module.css`: the sizes the editor reads, set again
/// at the card's scale ([peekEnv]), and the rules that take the page's grounds and paddings off ([peekLook]).
///
/// What differs: the box itself (`max-block-size`, `overflow: hidden`, the fade's mask, `margin-block-start`) is
/// `MarkdownView`'s, which is the element the stylesheet's `.peek` is. `pointer-events: none`, `user-select: none`
/// and the rules for a table's header (`.cm-glyphTable th`) wait for what they would act on.
library;

import 'package:glacier/glacier.dart';

import 'look.dart';
import 'markdown_look.dart';

/// `.peek` (and `.peek[data-whole]`, `.peek[data-whole][data-look='reading']`): the custom properties the editor's
/// sheets read, at the card's scale.
///
///     --peek-scale: calc(0.62 * var(--app-text-scale));
///     --app-body: calc(var(--glacier-font-size-lg) * var(--peek-scale));
///     --app-h1: calc(var(--glacier-font-size-3xl) * var(--peek-scale));   (4xl when whole; 5xl for a reading page)
///     --app-h2 … --app-h6: 2xl, xl, lg, lg, md                           (3xl, 2xl, xl, lg, md when whole)
///     --app-gutter: 0px;
///     color: var(--app-ink-3);                                            (var(--glacier-text) when whole)
///
/// and `.peek .cm-editor .cm-content { padding: 0 }`.
LookEnv peekEnv(Tokens t, {bool whole = false, String? look, double devicePixelRatio = 2}) {
  final scale = peekScale(t);
  final steps = whole ? <String>[look == 'reading' ? '5xl' : '4xl', '3xl', '2xl', 'xl', 'lg', 'md'] : const <String>['3xl', '2xl', 'xl', 'lg', 'lg', 'md'];
  return LookEnv(
    t: t,
    body: t.fontSize('lg') * scale,
    headings: <double>[for (final step in steps) t.fontSize(step) * scale],
    gutter: 0,
    devicePixelRatio: devicePixelRatio,
    dark: t.isDark,
    ink: whole ? t.color('glacier-text') : t.color('app-ink-3'),
    attrs: look == null ? const <String, String>{} : <String, String>{'data-look': look},
    contentTop: 0,
    contentBottom: 0,
  );
}

/// `--peek-scale`.
double peekScale(Tokens t) => 0.62 * t.len('app-text-scale');

const List<String> _headed12 = <String>[MarkdownClass.lineH1, MarkdownClass.lineH2];
const List<String> _headed34 = <String>[MarkdownClass.lineH3, MarkdownClass.lineH4];

/// The rules of NotePeek.module.css that reach into the editor. `whole` adds `.peek[data-whole]`'s.
LookSheet peekLook({bool whole = false}) => whole ? _whole : _peek;

final List<LookRule> _base = <LookRule>[
  // .peek :global(.cm-editor .cm-scroller .cm-line[class*='lineCode']) { background: transparent; margin-inline: 0; }
  LookRule(
    MarkdownClass.lineCode,
    null,
    classes: 5,
    box: (p, e) {
      p
        ..background = null
        ..marginStart = 0
        ..marginEnd = 0;
    },
  ),
];

final LookSheet _peek = LookSheet('notes/NotePeek.module.css', _base);

final LookSheet _whole = LookSheet('notes/NotePeek.module.css [data-whole]', <LookRule>[
  ..._base,
  // .peek[data-whole] .cm-editor .cm-scroller .cm-line:not(:first-child)[class*='lineH1'] (and lineH2) {
  //   padding-block-start: calc(var(--glacier-space-8) * var(--peek-scale)); }
  for (final name in _headed12) LookRule(name, null, classes: 7, when: (el, c) => !c.first, box: (p, e) => p.paddingTop = e.t.space(8) * peekScale(e.t)),
  // ... [class*='lineH3'] (and lineH4) { padding-block-start: calc(var(--glacier-space-6) * var(--peek-scale)); }
  for (final name in _headed34) LookRule(name, null, classes: 7, when: (el, c) => !c.first, box: (p, e) => p.paddingTop = e.t.space(6) * peekScale(e.t)),
  // .peek[data-whole] .cm-editor .cm-scroller .cm-line:has(> br:only-child) { line-height: 0.8; }
  LookRule('cm-line', (p, e) => p.lineHeight = 0.8, classes: 6, when: (el, c) => c.empty),
]);
