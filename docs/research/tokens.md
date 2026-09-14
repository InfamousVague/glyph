# Glacier token vocabulary for the Glyph editor stylesheet

Reference notes for the design panel. Every name below was read from the token source or the generated CSS; nothing is inferred. Paths are absolute.

## 1. Where the tokens live and the rules that bind them

- Source of truth: `/Users/matt/Development/UIUX/GlacierUI/packages/tokens/src/*.ts` (`color.ts`, `semantic.ts`, `type.ts`, `space.ts`, `radius.ts`, `motion.ts`, `elevation.ts`, `density.ts`, `size.ts`, `shape.ts`, `gradient.ts`, `effects.ts`, `layout.ts`, `theme-presets.ts`, `contrast.ts`). `generate.ts` orders them into `/Users/matt/Development/UIUX/GlacierUI/packages/tokens/css/tokens.css` (285 unique custom properties, prefix `--glacier-`) and `json/tokens.json`. Regenerate with `npm run gen -w @glacier/tokens`; never edit `tokens.css` by hand (README rule 5).
- Glyph consumes the vendored copy: `/Users/matt/Development/Apps/glyph/vendor/@glacier/tokens/css/tokens.css`, byte-identical to the kit source (`@glacier/tokens` 0.1.0). `src/main.tsx` imports, in order, `@glacier/tokens/css/fonts.css`, `@glacier/tokens/css/tokens.css`, `@glacier/react/styles.css`, then `./app/app.css`. `app.css` already sets `html, body { font-family: var(--glacier-font-sans); color: var(--glacier-text); background: var(--glacier-bg); }`.
- House rules from `/Users/matt/Development/UIUX/GlacierUI/README.md`: (1) no raw values, every color/size/radius/duration is a `--glacier-*` token; (2) components consume the semantic layer, never ramp steps (`--glacier-text`, not `--glacier-gray-12`); (3) spatial values come off the space scale; (4) motion is enum-only via `Motion`/`Speed`/`Ease`/`Spring` from `@glacier/motion`.
- The kit ships no ThemeProvider or `useTheme`. Apps write attributes on `<html>` themselves; AttackFM's `src/app/settings/appearance.tsx` (`AppearanceProvider`) is the house pattern, mirrored by the docs app at `apps/docs/src/App.tsx` lines 449-489.

## 2. Color

### Ramps (never consumed directly by components)

Eight 12-step OKLCH ramps: `gray` (hue 260), `accent` (228), `red` (25), `amber` (75), `green` (150), `blue` (228), `purple` (305), `teal` (190), emitted as `--glacier-<ramp>-<1..12>`. Step roles are fixed in both themes (`color.ts` header): 1-2 app backgrounds, 3-5 component backgrounds (rest/hover/active), 6-8 borders (subtle/default/strong+focus), 9-10 solid fills, 11-12 text (low/high contrast). Light runs bright to dark; dark runs dark to bright.

### Semantic aliases (`semantic.ts`, what a stylesheet should use)

| Group | Tokens | Light value | Dark value |
|---|---|---|---|
| Surfaces | `--glacier-bg` | gray-1 `oklch(0.993 0.0007 260)` | gray-1 `oklch(0.14 0.0017 260)` |
| | `--glacier-surface` | gray-2 | gray-2 |
| | `--glacier-surface-raised` | `oklch(0.995 0 0)` | gray-3 |
| | `--glacier-surface-sunken` | gray-3 | `oklch(0.115 0.008 260)` |
| | `--glacier-overlay` | `oklch(0.2 0.01 260 / 0.45)` | `oklch(0.07 0.01 260 / 0.65)` |
| Washes | `--glacier-hover` (gray-3), `--glacier-active` (gray-4), `--glacier-selection` (accent-5) | selection `oklch(0.906 0.0825 228)` | selection `oklch(0.285 0.087 228)` |
| Borders | `--glacier-border-subtle` (gray-4), `--glacier-border` (gray-6), `--glacier-border-strong` (gray-8) | | |
| Text | `--glacier-text` (gray-12) | `oklch(0.303 0.0066 260)` | `oklch(0.935 0.005 260)` |
| | `--glacier-text-muted` (gray-11) | `oklch(0.498 0.0102 260)` | `oklch(0.805 0.0102 260)` |
| | `--glacier-text-subtle` | literal `oklch(0.535 0.012 260)` (light override so it clears WCAG AA 4.5:1, worst case 4.6:1 on sunken) | gray-9 `oklch(0.64 0.013 260)` |
| | `--glacier-text-disabled` (gray-8) | fails AA by design; disabled only | |
| Accent | `--glacier-accent-solid` (9), `--glacier-accent-solid-hover` (10), `--glacier-accent-soft` (3), `--glacier-accent-soft-hover` (4), `--glacier-accent-border` (7), `--glacier-accent-text` (11), `--glacier-accent-contrast`, `--glacier-focus-ring` (8) | | |
| Status | `--glacier-{danger,success,warning,info}-{solid,solid-hover,soft,soft-hover,border,text,contrast}` from red/green/amber/blue | `warning-contrast` is dark ink `oklch(0.22 0.015 260)` | |
| Controls | `--glacier-segment-track`, `--glacier-segment-thumb`, `--glacier-slider-thumb` | | |

### Glass and effects (`effects.ts`)

`--glacier-glass-thin` / `-regular` / `-thick` / `-border` / `-highlight` (per theme), `--glacier-hairline: 1px`, `--glacier-blur-sm|md|lg` (10/20/32px, each multiplied by `--glacier-glass-blur-scale`), `--glacier-glass-saturate: 1.8`. Kit recipe (CodeBlock `.glass`): `background: var(--glacier-glass-regular); border-color: var(--glacier-glass-border); backdrop-filter: blur(var(--glacier-blur-sm)) saturate(var(--glacier-glass-saturate)); box-shadow: inset 0 var(--glacier-hairline) 0 var(--glacier-glass-highlight);`.

### Elevation, size, layout, gradients

`--glacier-shadow-0..5`; `--glacier-elevation-overlay-0..5` (transparent in light, `oklch(1 0 0 / 0.04..0.15)` in dark). `--glacier-size-2xs..4xl` (0.5rem to 4rem, not fluid: avatars, dots, spinners). `--glacier-container-xs|sm|md|lg|xl|prose(68ch)|full`, `--glacier-breakpoint-sm|md|lg|xl` (informational). `--glacier-gradient-accent`, `-wash-{neutral,accent,danger,success,warning,info}`, `-sheen`, `-scrim-1..3`, `-sweep`. Shape tokens `--glacier-shape-*` exist for the gamified plates; `--glacier-shape-accent-edge: 3px` is the only stripe-width token in the kit.

## 3. Type (`type.ts`)

- Families: `--glacier-font-sans: 'Inter Variable', ui-sans-serif, system-ui, -apple-system, 'Segoe UI', sans-serif`; `--glacier-font-mono: 'JetBrains Mono Variable', ui-monospace, 'SF Mono', SFMono-Regular, Menlo, monospace`. `[data-font='noto'|'plex']` swaps sans, `[data-mono='plex']` swaps mono; the defaults (`inter`, `jetbrains`) are the absence of the attribute. `fonts.css` registers the Fontsource faces (`@fontsource-variable/inter`, `@fontsource-variable/jetbrains-mono`, `@fontsource-variable/noto-sans`, `@fontsource/ibm-plex-sans`, `@fontsource/ibm-plex-mono`).
- Weights: `--glacier-font-weight-regular: 400`, `-medium: 500`, `-semibold: 600`, `-bold: 700`. No light/black.
- Nine fluid steps, each with `--glacier-font-size-<step>`, `--glacier-leading-<step>`, `--glacier-tracking-<step>`. Resolved at a 390px phone (fluid range is 320px to 1536px, so a phone sits at the clamp minimum):

| Step | size | px @390 | leading | tracking |
|---|---|---|---|---|
| xs | `clamp(0.6944rem, ..., 0.72rem)` | 11.5 | 1.5 | 0em |
| sm | `clamp(0.8333rem, ..., 0.9rem)` | 14.4 | 1.5 | 0em |
| md | `clamp(1rem, ..., 1.125rem)` | 18.0 | 1.5 | 0em |
| lg | `clamp(1.2rem, ..., 1.4063rem)` | 22.5 | 1.4 | 0em |
| xl | `clamp(1.44rem, ..., 1.7578rem)` | 28.1 | 1.4 | -0.01em |
| 2xl | `clamp(1.728rem, ..., 2.1973rem)` | 35.2 | 1.2 | -0.01em |
| 3xl | `clamp(2.0736rem, ..., 2.7466rem)` | 44.0 | 1.2 | -0.02em |
| 4xl | `clamp(2.4883rem, ..., 3.4332rem)` | 54.9 | 1.1 | -0.02em |
| 5xl | `clamp(2.986rem, ..., 4.2915rem)` | 68.7 | 1.1 | -0.02em |

Note: these px assume the browser base is 16px at 390px viewport; the clamp minimum applies at 320px, so real values at 390px are 5-8% above the min column shown in `tokens.css`.

Kit heading map (`Typography.module.css` `.heading`, spec `heading.ts`): base `font-weight-semibold`, color `text`; h1 = `font-size-3xl` + `leading-3xl` + `tracking-3xl` + `font-weight-bold`; h2 = 2xl; h3 = xl; h4 = lg; h5 = md; h6 = sm, `text-transform: uppercase; letter-spacing: 0.05em; color: var(--glacier-text-subtle)`.

## 4. Space, radius, motion, density

- Space (`space.ts`): `--glacier-space-0|1|2|3|4|5|6|8|10|12|16|20|24` plus `--glacier-space-px: 1px`. Each is `calc(clamp(n*0.25rem, ..., n*0.3125rem) * var(--glacier-density-scale))`. At 390px with the default density (1.1): space-1 = 5.5px, space-2 = 11, space-3 = 16.5, space-4 = 22, space-5 = 27.5, space-6 = 33, space-8 = 44.
- Radius (`radius.ts`): `--glacier-radius-none: 0px`, `-xs: 0.1875rem`, `-sm: 0.375rem`, `-md: 0.625rem`, `-lg: 1rem`, `-xl: 1.375rem`, `-2xl: 1.75rem`, `-full: 9999px`; xs through 2xl multiply `--glacier-radius-scale` (default 1). `--glacier-control-radius: var(--glacier-radius-full)` (capsule controls).
- Motion (`motion.ts`): `--glacier-duration-instant: 75ms`, `-fast: 150ms`, `-normal: 250ms`, `-slow: 400ms`, `-slower: 600ms`; `--glacier-ease-out: cubic-bezier(0.16, 1, 0.3, 1)`, `-in-out: cubic-bezier(0.65, 0, 0.35, 1)`, `-spring: cubic-bezier(0.34, 1.56, 0.64, 1)`, `-exit: cubic-bezier(0.4, 0, 1, 1)`; `--glacier-stagger-step: 60ms`. Under `prefers-reduced-motion: reduce` every duration and the stagger step collapse to `0.01ms`. JS enums in `@glacier/motion`: `Speed.{Instant,Fast,Normal,Slow,Slower}`, `Ease.{Out,InOut,Spring,Exit}`, `Spring.{Snappy,Smooth,Bouncy}`.
- Density (`density.ts`): `data-density` on `<html>` with values `extra-compact` (scale 0.65), `compact` (0.8), `comfortable` (1.1, the `:root` default, so no attribute), `spacious` (1.2), `more-space` (1.35). Each block also rewrites `--glacier-control-height-sm|md|lg` (comfortable: 2.25rem / 2.75rem / 3.25rem). Only the space scale and control heights move; type does not.

## 5. How light/dark, presets, and accents flip

All on the root element (`<html>`), all in `tokens.css`:

- Dark: `[data-theme='dark'] { color-scheme: dark; ... }` and `@media (prefers-color-scheme: dark) { :root:not([data-theme='light']) { ... } }`. "System" is the absence of `data-theme`. `color-scheme` is set in both directions, so UA carets, native selection, scrollbars, and form controls follow.
- Named presets: `:root[data-theme-preset='dawn'|'boreal'|'ember']` replace the gray ramp (warm/cool neutrals), the glass tokens, and a few semantics; `light` and `dark` are also valid `themePresetIds` but emit no block. `themePresets` in `theme-presets.ts` carries `{ id, scheme, accent, preview }`.
- Accent: `[data-accent='green'|'purple'|'teal'|'amber'|'red'|'graphite']` (light) plus `[data-theme='dark'][data-accent=...]` and the media-query twin rewrite `--glacier-accent-1..12` and `--glacier-accent-contrast` (amber and teal flip contrast to dark ink). `blue` is the default and has no block; select it by removing the attribute. Everything downstream (`selection`, `focus-ring`, `accent-text`, gradients, `shape-glow`) follows automatically.
- Glyph's `index.html` hard-codes `data-theme="dark"` and a pre-token paint; an appearance provider must overwrite it (AttackFM removes the attribute for system).

## 6. The kit's own precedent: `RichTextEditor.module.css`

`/Users/matt/Development/UIUX/GlacierUI/packages/react/src/organisms/RichTextEditor/RichTextEditor.module.css` is a markdown editor that keeps markers visible (a textarea over a highlight layer). Its choices: text layer `font-family: var(--glacier-font-mono); font-size: var(--glacier-font-size-sm); line-height: 1.5`; `caret-color: var(--glacier-text)`; `.run[data-kind='marker'] { color: var(--glacier-text-subtle) }`; bold = `font-weight-bold`; italic = `font-style: italic`; strike = `line-through`; inline code = `color: var(--glacier-accent-text)`; heading runs = `font-weight-bold` (no size change); quote = `text-muted` + italic; `link-text` = `accent-text` underlined; `link-url` = `text-muted`; fenced `code-block` = `text-muted`, `code-lang`/`code-keyword` = `accent-text`, `code-string` = `success-text`, `code-number` = `warning-text`, `code-comment` = `text-subtle` italic; placeholder = `text-subtle`; focused frame = `accent-border`. Token kinds come from `tokenizeMarkdown` in `packages/logic/src/rich-text.ts` (`MarkdownTokenKind`).

Bug to avoid: this file (and SortableList, CalendarView, native CalendarView) uses `var(--glacier-surface-hover)`, which is not defined anywhere in `tokens.css`; the real wash is `--glacier-hover`.

## 7. Recommended tokens for the Glyph editor

Rule of thumb for any live-preview engine: color, weight, and style changes are always safe; padding, borders, and backgrounds on inline runs are safe only when the editor paints the styled DOM itself (CodeMirror 6 mark decorations, ProseMirror), never in a transparent-textarea overlay, where they would shift glyphs off the caret.

| Element | Tokens |
|---|---|
| Editor page / body text | `background: var(--glacier-bg)`; `color: var(--glacier-text)`; `font-family: var(--glacier-font-sans)` (kit RichTextEditor uses `font-mono` + `sm`; decide); `font-size: var(--glacier-font-size-md)`; `line-height: var(--glacier-leading-md)`; `letter-spacing: var(--glacier-tracking-md)`; padding `var(--glacier-space-4)` inline; `caret-color` below |
| H1 | `font-size: var(--glacier-font-size-3xl); line-height: var(--glacier-leading-3xl); letter-spacing: var(--glacier-tracking-3xl); font-weight: var(--glacier-font-weight-bold)` (44px on a phone; the one-step-down map `2xl/xl/lg/md/md/sm` is the alternative to decide) |
| H2 | `font-size-2xl`, `leading-2xl`, `tracking-2xl`, `font-weight-semibold` |
| H3 | `font-size-xl`, `leading-xl`, `tracking-xl`, `font-weight-semibold` |
| H4 | `font-size-lg`, `leading-lg`, `font-weight-semibold` |
| H5 | `font-size-md`, `leading-md`, `font-weight-semibold` |
| H6 | `font-size-sm`, `leading-sm`, `font-weight-semibold`, `color: var(--glacier-text-subtle)`; drop the kit's `text-transform: uppercase` because typed characters must read as typed |
| Bold | `font-weight: var(--glacier-font-weight-bold)` |
| Italic | `font-style: italic` (no token exists; the kit writes the literal) |
| Strikethrough | `text-decoration: line-through` |
| Inline code | `font-family: var(--glacier-font-mono)`; color-only variant `color: var(--glacier-accent-text)` (kit); boxed variant `background: var(--glacier-surface-sunken); border-radius: var(--glacier-radius-xs); padding-inline: var(--glacier-space-1); color: var(--glacier-text)` (Kbd precedent, DOM-painting engines only) |
| Fenced code | `font-family: var(--glacier-font-mono); font-size: var(--glacier-font-size-sm); line-height: var(--glacier-leading-md); tab-size: 2; background: var(--glacier-surface-sunken); border: var(--glacier-hairline) solid var(--glacier-border-subtle); border-radius: var(--glacier-radius-lg); padding: var(--glacier-space-3) var(--glacier-space-4)`; fence line and language `color: var(--glacier-accent-text)`; syntax as in section 6 |
| Blockquote bar | `border-inline-start: var(--glacier-shape-accent-edge) solid var(--glacier-border-strong)` (3px; `--glacier-space-1` is the only other width token), `padding-inline-start: var(--glacier-space-3)`; quoted text `color: var(--glacier-text-muted)`, optional `font-style: italic` (kit) |
| List markers (`-`, `1.`) | `color: var(--glacier-text-subtle)` (they are syntax); hanging indent via `text-indent`/`padding-inline-start: var(--glacier-space-4)` |
| Links | `[text]` `color: var(--glacier-accent-text); font-weight: var(--glacier-font-weight-medium); text-decoration: underline; text-underline-offset: 0.2em`; brackets and `(url)` `color: var(--glacier-text-subtle)` (kit uses `text-muted` for the URL) |
| Dimmed syntax (`**`, `#`, `>`, backticks) | `color: var(--glacier-text-subtle)`; inherit size and weight from the run so metrics never change; never `opacity` and never `--glacier-text-disabled` (fails AA) |
| Selection highlight | `::selection { background: var(--glacier-selection); }`; CodeMirror `.cm-selectionBackground { background: var(--glacier-selection) }`; no foreground override (no selection-text token) |
| Caret | `caret-color: var(--glacier-text)` (kit precedent); the tinted alternative is `var(--glacier-accent-solid)`; CodeMirror `.cm-cursor { border-left-color: ... }`; never `--glacier-accent-9` |
| Placeholder | `color: var(--glacier-text-subtle)` |
| Focus | full-bleed editor shows no ring; a framed editor uses `border-color: var(--glacier-accent-border)` on `:focus-within` |
| Formatting bar | glass recipe from section 2 on `--glacier-glass-regular`; pressed control `background: var(--glacier-accent-soft); color: var(--glacier-accent-text)`; hover `var(--glacier-hover)`; radius `--glacier-radius-md`; transitions `var(--glacier-duration-fast) var(--glacier-ease-out)` |

## 8. Tokens that do NOT exist (do not invent)

`--glacier-surface-hover`, `--glacier-surface-active` (use `--glacier-hover` / `--glacier-active`); `--glacier-caret`, `--glacier-cursor`; `--glacier-selection-text`, `--glacier-selection-fg`; `--glacier-link`, `--glacier-link-hover`, `--glacier-link-visited`; `--glacier-code-bg`, `--glacier-code-text`, `--glacier-inline-code-*`, `--glacier-syntax-*`, `--glacier-marker`; `--glacier-quote-bar`, `--glacier-quote-*`; `--glacier-text-dim`, `--glacier-text-faint`, `--glacier-text-primary/secondary/tertiary`; `--glacier-accent` bare; `--glacier-border-hover` (kit uses `border-strong`); `--glacier-font-serif`, `--glacier-font-duo`, `--glacier-font-size-base/body/6xl`, `--glacier-font-weight-light/extrabold/black`; `--glacier-leading-tight/normal/loose` (leading is per size step); `--glacier-tracking-tight/wide`; `--glacier-space-7/9/11/14/32`; `--glacier-radius-3xl`, `--glacier-radius-pill`; `--glacier-ease-in`, `--glacier-ease-linear`, `--glacier-ease-bounce`; `--glacier-duration-*` beyond the five roles; `--glacier-focus-ring-width/offset` (kit writes literal `2px`); `--glacier-heading-*`, `--glacier-h1-*`; `--glacier-z-*`; `--glacier-safe-area-*` (glyph's `app.css` defines `--app-safe-top/bottom/left/right`); `data-theme='system'` (system is no attribute); `[data-accent='blue']` block (blue is the default).

## 9. Open questions

1. Editor face: kit precedent is `font-mono` + `font-size-sm`; iA/Bear feel argues for `font-sans` + `font-size-md`. Should Settings expose `data-mono` and a mono/sans toggle?
2. H1 at `font-size-3xl` is 44px on a phone. Adopt the kit map or the one-step-down map?
3. Caret: `--glacier-text` (kit) or `--glacier-accent-solid` (platform tint)?
4. Should Glyph offer `data-theme-preset` (dawn/boreal/ember) or only light/dark/system plus `data-accent`?
5. Is `tokenizeMarkdown` from `@glacier/logic` reachable from glyph? Only `icons`, `react`, `tokens` are vendored; `@glacier/react`'s vendored `package.json` lists only `motion` as a dependency, so logic/spec/motion may be bundled into `dist`.
6. Should the editor honour `data-density` at all? Line spacing is typographic; only paddings should ride the space scale.
7. Fix `--glacier-surface-hover` upstream (alias it or migrate the four components to `--glacier-hover`)?
