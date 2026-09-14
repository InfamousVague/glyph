# Glacier kit surface for Glyph

Reference notes for the design panel. Everything below was read from
`/Users/matt/Development/UIUX/GlacierUI/packages/react/src`, `packages/tokens`,
`packages/spec`, `packages/logic`, `apps/docs/src`, and the AttackFM app at
`/Users/matt/Development/Apps/AttackFM`. Prop names, exported names, CSS custom
property names and attribute values are quoted verbatim.

## 1. Entry points and what is actually vendored

- `@glacier/react` is one flat entry: `packages/react/src/index.ts` (370 lines).
  The vendored copy in Glyph is `vendor/@glacier/react/dist/{index.js,index.d.ts,styles.css}`;
  it bundles `@glacier/spec`, `@glacier/logic` and `@glacier/motion` internally and
  depends only on `react`, `react-dom`, `motion` (^12.23.0).
- Styles: `import '@glacier/tokens/css/fonts.css'`, `import '@glacier/tokens/css/tokens.css'`,
  `import '@glacier/react/styles.css'` (Glyph's `src/main.tsx` already does this, in that order).
- Icons: `@glacier/icons` is a proxy over `lucide-react` (`export * from 'lucide-react'`,
  `IconProps = LucideProps`). Usage: `import { Search } from '@glacier/icons'`, `<Search size={16} />`,
  colour inherits `currentColor`.
- Enums re-exported from the react entry: `Size` (`xs|sm|md|lg|xl`), `Tone`
  (`neutral|accent|success|warning|danger|info|note|auto|subtle|inherit`), `TextTone`
  (`default|muted|subtle|accent|danger|success|warning`), `Variant`
  (`solid|soft|outline|ghost|glass|danger|gradient|wash`), `SkeletonVariant` (`text|rect|circle`),
  `ScrollbarAppearance` (`subtle|default|accent`). Each member equals its string, so
  `size="lg"` and `size={Size.Large}` are both accepted.
- NOT exported from `@glacier/react`: the `Spring` enum (`snappy|smooth|bouncy`, lives in
  `@glacier/motion`), and the markdown helpers `tokenizeMarkdown`, `toggleMark`, `toggleBlock`,
  `activeMarks`, `activeBlock`, `markForShortcut`, `insertLink` (live in `@glacier/logic`,
  `packages/logic/src/rich-text.ts`). Only the types `MarkdownMark`, `MarkdownBlock` are
  re-exported. `@glacier/logic` and `@glacier/motion` are not vendored in Glyph.

## 2. Exact `<html>` attributes the token layer reads

From `packages/tokens/src/generate.ts` and the emitted `css/tokens.css` (1056 lines):

| attribute | values | absent means |
|---|---|---|
| `data-theme` | `'light'` / `'dark'` | follow `prefers-color-scheme` (`:root:not([data-theme='light'])` under the dark media query) |
| `data-theme-preset` | `'light'` / `'dark'` / `'dawn'` / `'boreal'` / `'ember'` (`themePresetIds`) | base neutral/glass tokens |
| `data-accent` | `'green'` / `'purple'` / `'teal'` / `'amber'` / `'red'` / `'graphite'` | blue (the `:root` accent ramp) |
| `data-font` | `'noto'` / `'plex'` | Inter (`sansFonts.inter`) |
| `data-mono` | `'plex'` | JetBrains Mono |
| `data-density` | `'extra-compact'` / `'compact'` / `'spacious'` / `'more-space'` | `'comfortable'` |
| `data-layout` | `'floating'` / `'full'` | flush; `Drawer` reads `document.documentElement.getAttribute('data-layout') === 'floating'` at open time |
| `dir` | `'rtl'` | ltr |

The docs app (`apps/docs/src/App.tsx` lines 445-476) and AttackFM
(`src/app/settings/appearance.tsx` lines 143-178) both remove the attribute at its
default and set it otherwise; `data-theme-preset` and `data-layout` are always stamped.
Glyph's `index.html` currently hard-codes `data-theme="dark"` plus a pre-token
`html { background: #0f0f10 }` first-paint rule.

Density (`packages/tokens/src/density.ts`): `controlHeights` per mode for `sm|md|lg`
(comfortable = `2.25rem / 2.75rem / 3.25rem`, compact = `1.875 / 2.25 / 2.75rem`,
extra-compact = `1.625 / 2 / 2.5rem`), and `densityScale` multiplier
(`0.65 / 0.8 / 1.1 / 1.2 / 1.35`) emitted as `--glacier-density-scale`, which every
`--glacier-space-*` token rides. `Density` type and `densityModes` const
(`['extra-compact','compact','comfortable','spacious','more-space']`) are exported.

Token families available (all `--glacier-*`): `bg`, `surface`, `surface-raised`,
`surface-sunken`, `text`, `text-muted`, `text-subtle`, `text-disabled`, `accent-1..12`,
`accent-solid`, `accent-solid-hover`, `accent-soft`, `accent-soft-hover`, `accent-text`,
`accent-border`, `accent-contrast`, same `-solid/-soft/-text/-border/-contrast` sets for
`success|warning|danger|info`, `border`, `border-subtle`, `border-strong`, `hairline`,
`overlay`, `focus-ring`, `selection`, `hover`, `active`, `glass-thin|regular|thick`,
`glass-border`, `glass-highlight`, `glass-saturate`, `blur-sm|md|lg`, `shadow-0..5`,
`elevation-overlay-0..5`, `space-0|1|2|3|4|5|6|8|10|12|16|20|24|px`, `radius-none|xs|sm|md|lg|xl|2xl|full`,
`control-radius`, `control-height-sm|md|lg`, `font-sans`, `font-mono`,
`font-size-xs|sm|md|lg|xl|2xl|3xl|4xl|5xl`, `leading-*`, `tracking-*`,
`font-weight-regular|medium|semibold|bold`, `duration-instant|fast|normal|slow|slower`,
`ease-out|in-out|exit|spring`, `breakpoint-sm|md|lg|xl`, `container-xs..xl|prose|full`.
There is no safe-area token anywhere in the kit; AttackFM pads with
`env(safe-area-inset-*)` in app CSS and Glyph's `index.html` already sets `viewport-fit=cover`.

## 3. Providers and app frame

**`AppShell`** (`organisms/AppShell/AppShell.tsx`), props `AppShellProps extends ComponentProps<'div'>`:
`sidebar: ReactNode` (required), `header?`, `bottomNav?`, `sidebarWidth?: string` (default `'17rem'`),
`sidebarLabel?` (default `'Navigation'`), `floating?`, `isMobile?: boolean` (else follows
`'(max-width: 1023px)'`), `resizable?`, `onSidebarWidthChange?(width: string)`,
`minSidebarWidth?` (200), `maxSidebarWidth?` (460). On mobile the sidebar becomes a fixed
off-canvas drawer (`max-width: 85vw`, `z-index: 40`, backdrop `z-index: 30`) with a built-in
hamburger `IconButton` in the sticky glass header and a close button; any `a, button` tap
inside the sidebar closes it; Escape closes it. `bottomNav` becomes `position: sticky; bottom: 0`
glass bar and content gets `padding-bottom: calc(var(--glacier-control-height-md) + var(--glacier-space-6))`.
Root attributes: `data-mobile`, `data-desktop`, `data-floating`, `data-bottom-nav`,
`data-sidebar-collapsed`; width lives in `--shell-sidebar`. Docs composition on a phone
(`apps/docs/src/pages/organisms/AppShellPage.tsx`): `<AppShell isMobile sidebar={<Sidebar>…</Sidebar>}
header={<Toolbar end={…}>Title</Toolbar>} bottomNav={<NavBar aria-label="Primary">…</NavBar>}>`.
Guidance: for Glyph, pass `isMobile` explicitly from the Tauri platform check, render the
notes list as the main content (not the sidebar), and keep `header` empty on the editor
screen (`.header[data-empty]` on mobile drops the glass and hairline). No safe-area padding
is applied; add it in `app.css`.

**`HapticsProvider`** (`haptics/HapticsProvider.tsx`): `{ enabled?: boolean (false), impl?: HapticFn, children }`.
With `enabled` it installs one capture-phase `pointerdown` listener, touch-only, that calls
`motor(kind)` for the nearest match of `PRESSABLE` =
`'button, [role="button"], a[href], summary, [role="switch"], [role="checkbox"], [role="radio"], [role="tab"], [role="menuitem"], [role="option"], [data-haptic]'`;
kind comes from `data-haptic` (default `'light'`, `'none'` opts out). Text inputs are excluded.
`useHaptics(): HapticFn` returns `(kind?) => { motor(kind); emitFeedback({kind}) }`.
`haptic(kind)` (module function) does the same with the web engine; `setHapticsEnabled`,
`hapticsEnabled` gate it. `HapticKind = 'selection'|'light'|'medium'|'heavy'|'success'|'warning'|'error'`.
Web fallbacks: `navigator.vibrate` patterns (`selection: 8, light: 10, medium: 18, heavy: 26,
success: [12,40,14], warning: [16,60,16], error: [22,40,22,40,22]` ms) or a hidden iOS
`<input switch>` toggle. Neither reaches WKWebView, which is why AttackFM mounts
`<HapticsProvider enabled={false} impl={hapticsImpl}>` and routes everything through
`fireNativeHaptic(kind)` in `src/app/core/haptics.ts` (maps to `@tauri-apps/plugin-haptics`
`selectionFeedback()`, `impactFeedback('light'|'medium'|'heavy'|'soft')`,
`notificationFeedback('success'|'warning'|'error')`), plus `fireFelt` (28 ms floor),
`fireMicroTick` (`impactFeedback('soft')`), `installTapHaptics()` (tap tick on `pointerup`,
10 px slop, 700 ms max, so scrolls stay silent), and `src/app/ux/ratchet.ts`
`makeRatchet(): { feel(travel, from, to, nowMs), arrive('medium'|'heavy'), reset() }` with
`NOTCH_FAR = 24`, `NOTCH_NEAR = 9`, `TICK_FLOOR_MS = 28`. Kit controls that stamp
`data-haptic="selection"` on their native input: `Switch`, `SegmentedControl` radios,
`Tabs` buttons, `DensitySelector` options.

**`VisualFeedbackProvider`** (`haptics/VisualFeedbackProvider.tsx`): `{ enabled?, variant?: 'shockwave'|'pulse'|'glow'|'nudge', intensity?: 'subtle'|'normal'|'strong', children }`.
Subscribes to the bus (`subscribeFeedback`), dedupes within `PRESS_SUPPRESS_MS = 150` of a press,
throttles bus events to `BUS_THROTTLE_MS = 55`, caps `MAX_CONCURRENT = 6`. `useVisualFeedback(): (kind?, origin?) => void`.
`emitFeedback({ kind, x?, y? })` and `subscribeFeedback(listener)` are exported from `haptics/feedback.ts`.

**`ToastProvider` / `useToast`** (`molecules/Toast/Toast.tsx`): `useToast()` returns
`{ toast(options: ToastOptions), dismiss() }`; throws outside the provider. `ToastOptions =
{ tone?: 'neutral'|'info'|'success'|'warning'|'danger', message: ReactNode, icon?, action?: { label: string; onPress(): void }, duration?: number (0 = sticky), dismissible?, glass? }`.
Latest wins, no queue. Per-tone auto-dismiss: `neutral/info/warning 4500`, `success 3500`,
`danger 7000` ms. Portalled to `document.body`, bottom-centre at
`inset-block-end: var(--glacier-space-6)`, `z-index: 200`, no safe-area offset and no
className hook on the viewport. Danger toasts are `role="alert"`.

**`LocaleProvider` / `useT` / `kitMessages`** (`i18n/`): `LocaleProvider({ locale, children })`;
`useT()` returns `Translate = (message: Message, params?) => string`; `useLocale()`.
`locales = ['en','es','fr','de','ja','pt','zh','ar']`, `DEFAULT_LOCALE = 'en'`,
`rtlLocales = {'ar'}`, `direction(locale)`. `Message = Record<Locale, string>` so
`defineMessages({ save: { en, es, fr, de, ja, pt, zh, ar } })` fails to compile if any of
the eight is missing. `kitMessages` keys include `dismiss`, `close`, `cancel`, `previous`,
`next`, `editorToolbar`, `editorBold`, `editorItalic`, `editorCode`, `editorStrike`,
`editorHeading`, `editorQuote`, `editorBullet`, `editorNumber`, `densityExtraCompact`,
`densityCompact`, `densityDefault`, `densityComfortable`, `densityMoreSpace`, `clearSearch`,
`openNavigation`, `closeNavigation`, `resizeSidebar`. Glyph should `defineMessages` its own
catalog and set `document.documentElement.lang/dir` like the docs app does.

## 4. Overlays

- **`Modal`** `{ open, onClose, title?, description?, size?: 'sm'|'md'|'lg'|'xl', footer?, children }`.
  Max widths `22 / 28 / 36 / 48rem`, `max-height: calc(100vh - space-6*2)`, always has a close
  button, springs open, closes instantly. Uses `useDialogLayer` (scroll lock, Tab trap,
  Escape, focus restore, layer stack so nested dialogs work).
- **`Drawer`** `{ open, onClose, title?, description?, side?: 'left'|'right'|'bottom' ('right'), size?: 'sm'|'md'|'lg' ('md'), floating?, footer?, dismissible? (true), children }`.
  Side widths `min(22|28|36rem, 100vw - space-8)`, under `40rem` viewport `calc(100vw - space-4)`;
  `bottom` is full width, `max-height: calc(100vh - space-12)`, top corners `radius-2xl`.
  Glass-thick material, `z-index: 100`. Phone guidance: `side="bottom"` for note actions
  and settings sheets; `dismissible={false}` while recording.
- **`AlertDialog`** `{ open, onClose, title (required), description?, actionLabel (required), onAction, cancelLabel?, tone?: 'neutral'|'danger', actionDisabled?, actionLoading?, dismissible? (false), children }`.
  Focuses Cancel first. Use `tone="danger"` for delete-note.
- **`Popover`** `{ trigger: ReactElement, placement?: Placement, open?, defaultOpen?, onOpenChange?, openOn?: 'press'|'hover', 'aria-label'?, className?, children }`.
  `Placement` = `top|bottom|left|right|inline-start|inline-end` each with `-start|-center|-end`.
  Panel `max-width: min(24rem, calc(100vw - 2rem))`.
- **`Menu`** `{ trigger, placement?, open?, defaultOpen?, onOpenChange?, 'aria-label'?, className?, children }`;
  rows: `MenuItem { icon?, shortcut?, danger?, onSelect?, disabled? }`, `MenuSeparator`, `MenuLabel`,
  `MenuSub { label, icon?, disabled?, menuClassName? }`. `ContextMenu { content, onOpenChange?, 'aria-label'?, menuClassName? }`
  opens on right-click or touch long-press. Panel `max-width: min(22rem, calc(100vw - 2rem))`.
- **`FloatingPanel`** `{ open, title, onClose, defaultPosition?: {x,y}, className?, children }`:
  draggable, non-modal, viewport-clamped. Desktop-shaped; not for phone.
- **`CommandPalette`** `{ open, onOpenChange, commands: CommandDescriptor[], onRun(id), query?, defaultQuery?, onQueryChange?, placeholder?, emptyLabel?, footer? (null drops the key-hint strip), size?: 'sm'|'md'|'lg', shortcut? (binds ⌘K/Ctrl+K) }`.
  `CommandDescriptor = { id, label, group?, keywords?, shortcut?, disabled? }`. Max widths `24/32/40rem`.
  Could serve as note search on phone with `footer={null}` and `shortcut={false}`.

## 5. Atoms and inputs

- **`Button`** `extends ComponentProps<typeof motion.button>`: `variant?: 'solid'|'soft'|'outline'|'ghost'|'glass'|'danger'|'gradient'` ('solid'), `size?: 'sm'|'md'|'lg'`, `shape?`, `edgeAccent?`, `sweep?`, `loading?`, `skeleton?`, `fullWidth?`. Press scale via `pressTap('control')`.
- **`IconButton`**: `'aria-label': string` (required), `variant?` ('ghost'), `size?`, `skeleton?`. Square `--glacier-control-height-{size}`.
- **`Input`** `Omit<ComponentProps<'input'>,'size'>`: `size?`, `skeleton?`, `glass?`, `leadingIcon?`, `trailingIcon?`. Reads `useField()` for `id`/`aria-describedby`/`aria-invalid`.
- **`Textarea`**: `size?`, `skeleton?`, `glass?`. **`SearchField`**: `value?`, `defaultValue?`, `onValueChange?(value)`, `placeholder?` ('Search'), `size?`, `shortcut?` (trailing `Kbd` slot; becomes a clear button once there is text), `glass?`.
- **`Switch`**: `label?`, `checked?`, `defaultChecked?`, `onCheckedChange?(checked)`, `size?: 'sm'|'md'`, `skeleton?`, `glass?`; renders `<input type="checkbox" role="switch" data-haptic="selection">`.
- **`Select`**: `options: { value, label, disabled? }[]`, `value?`, `defaultValue?`, `onValueChange?`, `placeholder?` ('Select…'), `size?`, `fullWidth?`, `disabled?`, `skeleton?`, `glass?`, `name?`, `id?`, `'aria-label'?`. Listbox portals to body, `z-index: 200`, flips up when under 240 px below.
- **`Field`**: `label?`, `hint?`, `error?` (replaces hint, shakes in, `role="alert"`), `required?`, `skeleton?`, `children`. Provides `FieldContext { id, describedBy, invalid }` that Input/Textarea/Select/SearchField consume; `useField()` is exported.
- **`Text`** `Omit<ComponentProps<'p'>,'children'>`: `as?: 'p'|'span'|'div'|'strong'|'em'|'small'`, `size?: 'xs'|'sm'|'md'|'lg'` ('md'), `tone?` (`TextTone` strings, 'default'), `weight?: 'regular'|'medium'|'semibold'|'bold'`, `mono?`, `align?: 'start'|'center'|'end'|'justify'`, `skeleton?`.
- **`Heading`**: `level?: 1|2|3|4|5|6` (2), `visualLevel?`, `align?`, `noMargin?`, `skeleton?`. h1 = `--glacier-font-size-3xl` bold, h2 = `2xl`, h3 = `xl`, h4 = `lg`, h5 = `md`, h6 = `sm` subtle.
- **`Label`** `ComponentProps<'label'>`: `required?`, `skeleton?`. **`Kbd`**: `glass?`, `skeleton?`. **`Link`**: `skeleton?`.
- **`Surface`** `ComponentProps<'div'>`: `level?: 0|1|2|'sunken'` (1) → `--glacier-bg / surface / surface-raised / surface-sunken`; `glass?`, `skeleton?`.
- **`Card`** `motion.div`: `elevation?: 0..5` (1), `interactive?` (hover lift + tap), `variant?: 'solid'|'glass'|'wash'`, `shape?`, `skeleton?`. Padding `--glacier-space-5`, radius `xl`.
- **`Pill`** `ComponentProps<'span'>`: `tone?: 'neutral'|'accent'|'success'|'warning'|'danger'|'info'`, `variant?: 'soft'|'solid'|'outline'`, `size?: 'sm'|'md'`, `shape?`, `icon?`, `onRemove?`, `skeleton?`, `glass?`.
- **`Divider`**: `orientation?: 'horizontal'|'vertical'`, `label?`, `skeleton?`. **`Skeleton`** `ComponentProps<'span'>`: `variant?: 'text'|'rect'|'circle'`, `width?`, `height?`, `radius?`; `aria-hidden`, `data-skeleton="true"`.
- **`EmptyState`**: `icon?`, `title` (required), `description?`, `action?`, `skeleton?`.

## 6. Lists and scrolling

- **`ScrollArea`** `Omit<ComponentProps<'div'>,'children'>`: `maxHeight?: number|string`, `orientation?: 'vertical'|'horizontal'`, `scrollbarAppearance?: 'subtle'|'default'|'accent'`, `showScrollbarTrack?` (true), `hideScrollbar?`. Viewport is `tabIndex=0 role="group"`; fades set via `data-fade-start`/`data-fade-end`; a `ResizeObserver` watches every child. On phone prefer `hideScrollbar` and let the native scroller work.
- **`List` / `ListItem`**: `List { size?: 'sm'|'md', divided? }` (a `<ul>` with `data-size`). `ListItem { title (required), description?, leading?, trailing?, selected?, disabled?, href?, onClick? }` renders `<a>` when `href`, `<button aria-pressed>` when `onClick`, else `<div>`; stamps `data-glacier-list-item`, `data-selected`, `data-disabled`.
- **`VirtualList`** `Omit<ComponentProps<'div'>,'children'|'ref'>`: `count`, `itemSize: number` (fixed px, deliberately), `renderItem(index)`, `height?`, `overscan?` (3), `onVisibleChange?(start,end)`, `getKey?(index)`, `emptyLabel?`, `skeleton?`, `ref?: Ref<VirtualListHandle>` where `VirtualListHandle = { scrollToIndex(index, align?: 'auto'|'start'|'center'|'end') }`. Viewport `role="listbox"` `tabIndex=0`, rows `role="option"` with whole-list `aria-setsize/posinset`. Fixed height means a notes list needs one row height (title + one preview line).

## 7. Navigation and structure

- **`SegmentedControl`** `ComponentProps<'div'>`: `options: { value, label, disabled? }[]`, `value?`, `defaultValue?`, `onValueChange?`, `size?`, `fullWidth?`, `skeleton?`, `spring?` (default snappy; enum not importable from `@glacier/react`, leave unset), `disabled?`, `'aria-label'?`. Radio-based, thumb is a shared `layoutId`.
- **`Tabs`**: `tabs: { value, label, content, disabled? }[]`, `value?`, `defaultValue?`, `onValueChange?`, `spring?`, `fullWidth?`, `skeleton?`, `'aria-label'?`. WAI-ARIA automatic activation.
- **`NavBar`** `ComponentProps<'nav'>`: `orientation?: 'horizontal'|'vertical'`, `'aria-label': string` (required), `end?`, `showLabels?` (false), `spring?`, `shape?`, `edgeAccent?`, `sweep?`, `skeleton?`. **`NavBarItem`**: `icon` (required), `label: string` (required), `active?`, `badge?: number`, `as?`, `href?`. Icon-only items wrap in a `Tooltip`, so on phone set `showLabels` for the bottom bar.
- **`Toolbar`** `ComponentProps<'div'>`: `start?`, `end?`, `sticky?`, `border?`, `surface?` (glass). **`TitleBar`**: `title?`, `start?`, `end?`, `trafficLightInset?`, `surface?` (true), `border?` (true), `skeleton?`; carries `data-tauri-drag-region` and is desktop-window oriented.
- **`Sidebar`** `{ header?, footer?, spring? }`, **`SidebarSection`** `{ title? }`, **`SidebarItem`** `{ as?, href?, icon?, active?, trailing? }`.
- **`DensitySelector`**: `value: DensityMode`, `onValueChange(value)`, `labels?`, `disabled?`, `'aria-label': string` (required). Horizontal `ScrollArea` of radio cards; already the docs' and AttackFM's density picker.
- Layout primitives `Box`, `Stack` (gap default 4), `Row` (`wrap?`), `Grid`, `Center`, `Spacer`, `Container` (`size?: 'xs'|'sm'|'md'|'lg'|'xl'|'prose'|'full'`, `as?`): all take `BoxStyleProps` (`padding`, `paddingX/Y/Top/Right/Bottom/Left` as `SpaceStep`, `background: 'transparent'|'bg'|'surface'|'surfaceRaised'|'surfaceSunken'|'accent'|'accentSoft'|'glass'`, `radius`, `border: boolean|'subtle'|'strong'|'accent'`, `elevation 0..5`, `width 'auto'|'full'|'fit'`, `maxWidth`, `height 'auto'|'full'|'screen'`, `grow`, `shrink`, `alignSelf`) and `FlowProps` (`gap`, `align`, `justify`), `Responsive<T>` by `base|sm|md|lg|xl`. No raw lengths anywhere.

## 8. The kit's own markdown editor (context for the editor decision)

`RichTextEditor` (`organisms/RichTextEditor/RichTextEditor.tsx`, 278 lines): props
`value?`, `defaultValue?`, `onValueChange?`, `placeholder?`, `marks?: MarkdownMark[]`
(`'bold'|'italic'|'code'|'strike'`), `blocks?: MarkdownBlock[]` (`'heading'|'quote'|'bullet'|'number'`),
`rows?` (8), `maxLength?`, `disabled?`, `skeleton?`. It is a `<textarea>` with
`color: transparent; caret-color: var(--glacier-text)` stacked over an `aria-hidden` highlight
`<div>` that renders `tokenizeMarkdown(value)` as `<span class="run" data-kind data-marks data-block>`;
marker runs are dimmed (`.run[data-kind='marker'] { color: var(--glacier-text-subtle) }`),
bold/italic/strike/code/heading/quote/link styled, and both layers share `.editorText`
(`font-family: var(--glacier-font-mono)`, `font-size: var(--glacier-font-size-sm)`,
`line-height: 1.5`, `white-space: pre-wrap`). Edits go through `document.execCommand('insertText')`
so native undo survives. This is exactly the "tokens stay visible, dimmed" behaviour Glyph
wants, but it is monospace, re-tokenizes and re-renders the whole document on every
keystroke, and `tokenizeMarkdown` is not exported from the vendored react entry.
`MarkdownTokenKind = 'text'|'marker'|MarkdownMark|MarkdownBlock|'link-text'|'link-url'|'code-lang'|'code-block'|'code-keyword'|'code-string'|'code-number'|'code-comment'`.

## 9. Open questions for the panel

1. Vendor `@glacier/logic` (for `tokenizeMarkdown`, `toggleMark`, `toggleBlock`) or write Glyph's own incremental, line-scoped tokenizer for CodeMirror decorations.
2. `ToastProvider` viewport and `AppShell` bottomNav/header have no `env(safe-area-inset-*)` padding and no className hooks; Glyph must add safe-area padding via `app.css` wrappers.
3. `Spring` is not reachable from `@glacier/react`; `spring` props must be left at their defaults unless `@glacier/motion` is vendored.
4. AttackFM disabled the kit's pointerdown haptic listener because it buzzed during scroll flicks; Glyph should mount `HapticsProvider enabled={false} impl={…}` the same way and own its tap tick on pointerup.
5. `VirtualList` is fixed-row-height only; the notes list row must be one fixed height.
