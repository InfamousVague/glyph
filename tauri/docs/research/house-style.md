# House style for code in Matt's repos (GlacierUI + AttackFM), for Glyph

Read from the actual files on 2026-09-11. Sources: `/Users/matt/Development/UIUX/GlacierUI/{README.md,NATIVE-PARITY-CHECKLIST.md,eslint.config.js,tsconfig.base.json,vitest.config.ts}`, `packages/react/src/atoms/inputs/Button/{Button.tsx,Button.module.css}`, `packages/react/src/atoms/inputs/Selection/{Switch.tsx,Selection.module.css}`, `packages/react/src/molecules/Field/{Field.tsx,Field.module.css}`, `packages/react/src/internal/{cx.ts,FieldContext.ts,useControlled.ts}`, `packages/react/src/haptics/{haptics.ts,HapticsProvider.tsx}`, `packages/react/test/{setup.ts,components.test.tsx,segmented.test.tsx,haptics.test.tsx}`, `packages/logic/src/composer.ts`; `/Users/matt/Development/Apps/AttackFM/{eslint.config.js,tsconfig.json,vitest.config.ts,vite.config.ts,package.json,.github/workflows/ci.yml}`, `src/app/core/{haptics.ts,platform.ts,tauri.ts,styleGuard.ts}`, `src/app/ux/{ratchet.ts,ratchet.test.ts,format.ts}`, `src/app/settings/{ThemeSelector.tsx,ThemeSelector.module.css,appearance.tsx,behaviourPrefs.ts,cardStyle.ts,developerMode.ts,AppearancePane.tsx,kit/settingsKit.tsx}`, `src/app/player/nowPlayingStore.ts`, `src/app/nav/AppProviders.tsx`, `src/app/library/{library.tsx,library.test.tsx,owned.test.ts}`, `src/app/i18n/{CONVENTIONS.md,index.ts,translate.ts,LocaleShell.tsx,index.test.ts,locales/en.json}`, `src/test/{setup.ts,harness.test.tsx,sourceText.test.ts,libraryFixtures.ts}`, `src/app/styles/{62-settings-shell.css,63-settings-panes.css}`, `src/app/app.css`, `scripts/{i18n-scan.mjs,check-prefs.mjs,check-style-guard.mjs}`.

Note: `src/app/core/ratchet.ts` does not exist; the ratchet lives at `src/app/ux/ratchet.ts` with its test beside it.

## 1. Comment voice

The single most distinctive thing in these repos. Every module opens with a `/** ... */` header, and most exported functions and many constants carry one. They are essays, not labels.

**What a doc comment does**
- States what the module OWNS and what its neighbours own (`composer.ts`: "`chat.ts` owns the transcript that has already happened and `message.ts` owns how one message is drawn. This module owns the other end of the thread").
- Argues WHY it exists HERE rather than elsewhere ("Lives here rather than in either caller because there are two gestures with exactly this shape").
- Says what it deliberately does NOT do ("Nothing here renders, measures, or reads a `window`. Auto-grow in particular is deliberately absent").
- Records what was MEASURED, with numbers: "MEASURED on this tree, 16,558 of 16,897 findings were the same parse error, burying 339 real ones"; "1.9 MB of JSON across eight languages takes app.js from 7.27 MB to 8.59 MB, which is +8% GZIPPED (3.78 -> 4.09 MB)"; "83 `.catch(() => {})`"; "965 places". The phrases "measured, not estimated", "Verified, not assumed", "MEASURED, not estimated" recur.
- Records history when it explains the present: "This file used to claim ... It does not."; "Bumped to -v2 so a value saved before the brand accent existed ... is dropped rather than pinning it forever."
- Warns the next editor off a tempting simplification: "What must NOT happen is somebody 'simplifying' these into eight static imports at the top of the file. That is the same bytes today and forecloses the fix."

**Mechanics**
- Wrapped at ~80 columns (median 75, p95 79 for ` * ` lines in AttackFM). Code lines run longer (0.9% over 100, 0.2% over 120); no Prettier config in either repo.
- The dash is a spaced hyphen ` - `, never an em dash, in code comments (AttackFM: 5,360 ` - ` vs 57 `—` in ts/tsx; Glacier: 673 vs 4). Em dashes appear in user copy (`en.json`) and READMEs only.
- CAPITALS for the load-bearing word: "the DENOMINATOR IS THE WHOLE CLIENT", "NOT `behavior: 'smooth'`", "Read at EMIT time", "it IS the RTL implementation", "LOAD-BEARING".
- British spelling in prose: colour (92), behaviour (54), catalogue (351), favourite, centred, initialiser, artefact, grey, normalise. Identifiers bound to an API stay as the API spells them (`fetchRemoteFavorites`, `FAVORITES_KEY`).
- In-file section rules: `// --- the tap tick ---------------------------------------------------------` (haptics.ts, settingsKit.tsx), `// ---- counting ----` (composer.ts), `// ── Where you are, sent to your account ───` (behaviourPrefs.ts), `/* --- the row ---- */` in CSS.
- Zero `TODO`, `FIXME`, `HACK` in AttackFM `src/` (Glacier has one). Parked work gets a header explaining what is parked and why, not a tag.
- Every empty `catch {}` carries a comment saying why silence is the right outcome: `// A bridge that will not buzz is silence, not an error worth surfacing.`, `// Storage refused: the choice holds for this run and not beyond it.`, `// Silence, as ever.`. `no-empty` stays on bare because of this.
- `eslint-disable-next-line <rule> -- <reason>`: the reason after `--` is mandatory and specific (82 sites, e.g. `-- tick is the redraw signal: the cached index is module state written outside React, so it is not a dependency React can see`).
- JSX comments inside provider trees explain ORDER: `AppProviders.tsx` says "The nesting ORDER is load-bearing - each layer's comment says why it sits where it does".
- No trivial comments. Nothing like `// increment counter`. A one-line `/** */` on an export is fine when the name needs one qualifier: `/** How far a finger may travel and still have been a tap rather than a drag. */`.

**Favoured words and constructions** (counts in AttackFM ts/tsx): "rather than" 1,440; "which is" 804; "deliberately" 193; "honest/honestly" 127; "measured" 96; "on purpose" 91; "the one place" 20; "load-bearing" 19; "the whole point"; "worse than no X"; "that is not tidiness"; "X is a Y, not a Z"; "the honest answer/number/default". Aphorisms close arguments: "A gate whose output you have to sieve is not a gate."; "A fix that cannot work is worse than no fix: it closes the question."; "a threshold nobody can reach is a gate everyone disables". Domain metaphors are consistent: a directory is a "room", a nav entry is a "door" (`*Door.ts`), a list is a "shelf", a boundary is a "seam", a threshold that only moves one way is a "ratchet", UI conventions are a "vocabulary"/"language"/"dialect".

**Avoided**: "utilize", "leverage" (0), "robust", "seamless" (2 total), "Note that" (1), "basically", emoji, "simple"/"easy" framing, `TODO`. "simply" and "just" are used, but only as "simply no-op"/"just a track", never as "it's simple".

**Commit subjects** are sentences: `A zero byte in a source file makes it invisible to grep`, `The lint gate reads this checkout, and a watching desktop gets its player back`. Glacier prefixes but still sentences: `fix(seekbar): the thumb stands taller than the swell can reach`.

### Five verbatim doc comments

1. `src/app/ux/ratchet.ts` (header):
```
/**
 * The run-up to a detent, felt.
 *
 * A single tick when a gesture crosses its line is a fact, not a feeling: it
 * reports where the line WAS, after the finger went past it. A dial tells you
 * a stop is coming - its notches tighten as it nears one - and that is what a
 * drag with a threshold in it wants too, because the hand is already moving
 * and the decision is made before the eye catches up.
 *
 * So the approach is ticked: softly and far apart at first, closer and firmer
 * as it arrives, and the threshold itself lands properly.
 *
 * Lives here rather than in either caller because there are two gestures with
 * exactly this shape - the pull from the top of a page, and pushing the Now
 * Playing sheet back down - and a tick pattern that drifts between them is a
 * phone that feels like two different apps depending on which way you drag.
 */
```

2. `src/app/core/haptics.ts` (`fireFelt`):
```
/**
 * The same floor `ratchet.ts` keeps, for the paths that are not ratchets.
 *
 * `fireNativeHaptic` has no rate limit of its own, which is right for a
 * one-shot: a tap should answer immediately, every time. It is wrong for
 * anything a finger can repeat faster than the engine can speak - a mashed
 * skip button, a scrub crossing chapter marks pixels apart on a long book, a
 * thumb resting inside a detent band. The Taptic Engine queues a flood and
 * then plays it back as mush, so those callers come through here instead.
 */
```

3. `packages/logic/src/composer.ts` (`composerSubmitModeFor`):
```
/**
 * The submit mode a pointer type would choose, for a caller who wants to opt in.
 *
 * Deliberately not the default. Reading the environment makes the most
 * destructive behaviour in the component non-deterministic: it mis-resolves on
 * a touchscreen laptop, flips mid-session when an iPad meets a keyboard, and
 * leaves a docs example, a test, and the user's own screen disagreeing about
 * what Enter does. A caller who knows their platform can pass the result of
 * this; the component itself starts at `enter` and stays there.
 */
```

4. `src/app/settings/developerMode.ts` (header, middle paragraph):
```
 * A LIVE store rather than a behaviourPrefs pair, and the difference matters:
 * this flag is flipped from INSIDE a child pane (About) and has to change the
 * PARENT's sections array on the spot. behaviourPrefs' on()/set() have no
 * change channel and `storage` events never fire in the tab that wrote them,
 * so SettingsModal would not learn about the flip until its next mount. This
 * is the same shape as core/haptics.ts: a module listener set and a
 * useSyncExternalStore hook.
```

5. `vitest.config.ts` (AttackFM, the thresholds):
```
        /**
         * THE RATCHET.
         *
         * These are the numbers this tree actually produced on the run that
         * installed them, floored to two decimals - not a target, not a round
         * number someone liked. The rule is only that they never go down. A
         * threshold nobody can reach is a gate everyone disables; a threshold
         * set at today's truth is a gate that catches the commit which quietly
         * deletes a test.
```

## 2. Imports

- Every relative import carries its extension: `.ts`, `.tsx`, `.css`, `.json`. AttackFM: 2,448 of 2,450 relative imports; Glacier: 756 of 756. Enabled by `"allowImportingTsExtensions": true`, `"moduleResolution": "bundler"`, `"noEmit": true` (both tsconfigs).
- No path aliases. Zero `@/` imports; no `paths` in either tsconfig. Packages come in by name: `@glacier/react`, `@glacier/tokens`, `@glacier/icons` (AttackFM `package.json`: `"@glacier/react": "file:./vendor/@glacier/react"` etc.), `@glacier/spec`, `@glacier/motion`, `@glacier/logic` inside the kit.
- Glacier README rule 7: "No aliased imports. Write `motion`, not `motion as m`; `styles`, not `s`."
- Observed order (not lint-enforced): third-party packages first (`motion/react`, `@glacier/*`, `react`), then relative modules, then `import styles from './X.module.css'` last. Inline type specifiers: `import { useId, type ComponentProps, type ReactNode } from 'react'` (230 sites); `import type { X } from` for type-only modules (362). Long lists are one-per-line, alphabetical, `type` entries last.
- No `import React`, no `React.FC`, no `export default` in AttackFM `src/` (0 of each); named exports only. Config files use `export default`.
- Platform plugins are lazy: `let pluginPromise = null; function plugin() { pluginPromise ??= import('@tauri-apps/plugin-haptics'); return pluginPromise; }` and callers `void plugin().then(...).catch(() => {})`.
- Tests: `vi.mock(...)` first, then `const { makeRatchet } = await import('./ratchet.ts');` (top-level await after the mocks).
- Atomic direction (Glacier rule 6): atoms never import molecules/organisms; shared contracts live in `internal/` (`FieldContext.ts`, `cx.ts`, `useControlled.ts`).

## 3. Naming

- Files: components `PascalCase.tsx` (`ThemeSelector.tsx`, `AppearancePane.tsx`); modules `camelCase.ts` (`behaviourPrefs.ts`, `styleGuard.ts`); hooks `useX.ts` (`useNavStack.ts`, `useSwipeBack.ts`, `useFilePlan.ts`) - 67 hooks live in plain `.ts`; stores `xStore.ts` (`nowPlayingStore.ts`, `transcriptStore.ts`, `cacheStore.ts`); nav entries `xDoor.ts`; CSS module `X.module.css` beside its component; tests `x.test.ts(x)` beside the module.
- Directories are lowercase feature rooms: `core/`, `ux/`, `nav/`, `settings/`, `library/`, `player/`, `i18n/`, `notify/`, `test/`. Glacier: `atoms/{inputs,display,feedback}/Name/`, `molecules/Name/`, `organisms/`, `structures/`, `internal/`, `haptics/`, `i18n/`; tests in `packages/react/test/kebab-name.test.tsx`.
- Constants `SCREAMING_SNAKE` with a doc line: `TICK_FLOOR_MS = 28`, `FLOOR_MS = 28`, `TAP_SLOP_PX = 10`, `TAP_MAX_MS = 700`, `REPLY_PREVIEW_LIMIT = 120`, `DRAFT_NEAR_LIMIT = 0.9`.
- Storage keys `attackfm-<thing>` kebab-case; `-v2` when the stored shape changed (`attackfm-appearance-v2`). Glyph: `glyph-<thing>`.
- Read/set/use triples: `hapticsPref()` / `setHapticsPref()` / `useHapticsPref()`; `cardStyle()` / `setCardStyle()` / `useCardStyle()`; `developerModeEnabled()` / `setDeveloperMode()` / `useDeveloperMode()`.
- Verbs name effects: `fireNativeHaptic`, `fireFelt`, `fireMicroTick`, `heartbeatHaptic`, `installTapHaptics` (returns its cleanup), `makeRatchet` (factory returning `{ feel, arrive, reset }`).
- Props: `onValueChange`, `onCheckedChange` (never bare `onChange` on kit controls); `'aria-label': ariaLabel` destructured; booleans default `false` (`skeleton`, `glass`, `fullWidth`, `loading`); `size?: ControlSize` = `'sm' | 'md' | 'lg'`; `variant?: ButtonVariant` = `'solid' | 'soft' | 'outline' | 'ghost' | 'danger' | 'glass' | 'gradient'`.
- Types: `interface XProps extends Omit<ComponentProps<'input'>, 'size'>`; unions derived from const arrays: `export const composerSubmitModes = ['enter', 'modifier'] as const; export type ComposerSubmitMode = (typeof composerSubmitModes)[number];`.
- Providers: `XProvider` + `useX()` in one file; `useX` throws `'useX must be used within an XProvider'`; optional variant `useXOptional`. Both are named in eslint `allowExportNames`.

## 4. State management

No zustand, no redux (zero matches). Three shapes, chosen by whether a change channel is needed:

1. **Module store + `useSyncExternalStore`** (33 files). `let current`, `const listeners = new Set<() => void>()`, `subscribe(fn)` returning the delete, `snapshot()`, an exported setter that early-returns on no change and then `for (const fn of listeners) fn()`, and `useX()` calling `useSyncExternalStore(subscribe, snapshot, snapshot)` (server snapshot `() => false` for booleans). Canonical: `nowPlayingStore.ts`, `developerMode.ts`, `cardStyle.ts`, `haptics.ts` (pref).
2. **Context provider** for tree-wide state persisted to localStorage: `AppearanceProvider` / `useAppearance()` in `appearance.tsx` (`useState(readStored)`, one effect writes `data-theme` / `data-theme-preset` / `data-accent` / `data-density` / root `font-size` and `localStorage.setItem`, `useMemo` value with `update: (next: Partial<Appearance>) => void`).
3. **Plain module functions, no React**, for prefs read at the moment of acting: `behaviourPrefs.ts` `on(key, fallbackOn)` / `set(key, value, fallbackOn)`, storing only the side that differs from the default so a later default change reaches untouched devices.

Rules that go with them: `localStorage` always inside `try { } catch { /* why */ }`; document attributes that affect first paint are written from the module body before React mounts (`cardStyle.ts` `apply(current)`, `platform.ts` `dataset.platform`) or from a lazy `useState` initialiser (`LocaleShell`), never from an effect; `void promise` for fire-and-forget (324 sites); effects read state through refs and list only discontinuities in deps, with an annotated disable when the linter disagrees.

## 5. CSS

- Kit: CSS Modules, `import styles from './Button.module.css'`, classes joined with `cx()` from `internal/cx.ts` (`(...parts: Array<string | false | null | undefined>) => string`). Class names camelCase (`styles.fullWidth`, `styles.nativeInput`, `styles.previewScene`). AttackFM has one module (`ThemeSelector.module.css`) and otherwise global chapters `src/app/styles/NN-name.css` imported in order by `src/app/app.css` ("ORDER IS THE CASCADE") with BEM classes (`.setk-row__label`). Glyph should use the kit's way: modules.
- Tokens only (Glacier README rule 1: "If a value isn't a token, it doesn't ship"). Glacier module CSS: 3,336 `var(--glacier-` vs 261 `px` (the px are `outline: 2px`, `1px` hairlines). Names seen: `--glacier-space-{1..6}`, `--glacier-radius-{sm,lg,full}`, `--glacier-control-radius`, `--glacier-control-height-{sm,md,lg}`, `--glacier-hairline`, `--glacier-border`, `--glacier-border-subtle`, `--glacier-border-strong`, `--glacier-bg`, `--glacier-surface`, `--glacier-surface-raised`, `--glacier-hover`, `--glacier-active`, `--glacier-text`, `--glacier-text-muted`, `--glacier-accent-solid`, `--glacier-accent-solid-hover`, `--glacier-accent-soft`, `--glacier-accent-text`, `--glacier-accent-contrast`, `--glacier-danger-solid`, `--glacier-danger-text`, `--glacier-focus-ring`, `--glacier-duration-fast`, `--glacier-duration-normal`, `--glacier-ease-out`, `--glacier-ease-spring`, `--glacier-font-sans`, `--glacier-font-size-{xs,sm,md,lg}`, `--glacier-font-weight-{medium,semibold}`, `--glacier-leading-{xs,sm}`, `--glacier-glass-regular`, `--glacier-glass-thick`, `--glacier-glass-border`, `--glacier-glass-highlight`, `--glacier-glass-saturate`, `--glacier-blur-sm`, `--glacier-shadow-{1,2}`. Token trap from `settingsKit.tsx`: "`var(--glacier-accent)` does not exist - use `-solid`/`-text`."
- Logical properties: 0 `margin/padding-left|right` in either repo; `padding-inline`, `margin-block-start`, `border-inline-end`, `border-block-end`, `inline-size`, `block-size`, `min-inline-size`, `inset-inline-start` (AttackFM 357 logical vs 0 physical; `LocaleShell` says "230 logical against 13 physical").
- State via data attributes, never modifier classes: `data-selected={selected || undefined}`, `data-checked`, `data-loading`, `data-invalid`, `data-active`, `data-disabled`, `data-tone`, `data-lead`, `data-split`; selectors `.option[data-selected]`, `.track[data-checked]`. `|| undefined` removes the attribute when false. Glacier's top attrs: `data-shape` 54, `data-elevation` 33, `data-disabled` 25, `data-active` 25, `data-tone` 24. Document-level: `data-theme`, `data-density`, `data-accent`, `data-theme-preset`, `data-platform`, `data-card-style`, plus `lang` and `dir`.
- Motion: `transition: border-color var(--glacier-duration-fast) var(--glacier-ease-out)`; `@media (prefers-reduced-motion: reduce) { transition: none; }`; in JS `useReducedMotion()` from `motion/react`, `springTransition(Spring.Snappy)`, `pressTap('control', reduce || inert)`, `motionProps(Motion.FadeIn, Speed.Fast)`. Glacier rule 4: "Motion is enum-only."
- Controls: `-webkit-tap-highlight-color: transparent; user-select: none;`; visually-hidden native input `.nativeInput { position: absolute; width: 1px; height: 1px; margin: -1px; clip-path: inset(50%); overflow: hidden; white-space: nowrap; }`; focus `.nativeInput:focus-visible + .track { outline: 2px solid var(--glacier-focus-ring); outline-offset: 2px; }`. Safe areas `env(safe-area-inset-top, 0px)`.
- CSS comments argue too: Button.module.css on `line-height: normal` explains the half-pixel strut bug.

## 6. i18n

AttackFM (app scale): i18next + react-i18next. `const t = useT();` from `src/app/i18n/LocaleShell.tsx` inside components; `translate(key, options)` from `src/app/i18n/translate.ts` in plain functions (NOT reactive, for strings handed to the OS); `Trans` for sentences with a hole; `useSongCount()` for the common plural. Keys `namespace.camelCaseName` named by MEANING (`library.empty`, not `library.noMusicInYourLibrary`); namespaces are app areas plus `common` (only for words with one meaning everywhere). Plurals via `_one` / `_other` and `{ count }`; never a ternary. Numbers, dates, bytes, "3 days ago" go through `src/app/ux/format.ts` (`formatNumber`, `formatBytes`, `formatTotal`, `formatDate`, `formatAgo`, `formatClock`), never the catalogue. Module-scope tables carry `labelKey` / `nameKey`, resolved at render. Strings that are matched on get `i18n-ignore` in a comment with the reason. Catalogues `src/app/i18n/locales/{en,es,fr,de,ja,pt,zh,ar}.json`; English bundled, others `import()`ed in `CATALOGS`. Gate: `npm run i18n:gate` = `i18n-scan.mjs --max 0 && --keys && --catalogues && i18n-verify.mjs --quiet`. Locale flows into the kit's `LocaleProvider`; `html.lang`, `html.dir` and `setFormatLocale` stamped in the same breath, before first paint.

Kit scale: `@glacier/react` exports `LocaleProvider`, `useT`, `defineMessages`, `Message`, `locales`, `rtlLocales`, `DEFAULT_LOCALE`. Glacier's eslint enforces `react/jsx-no-literals` (`noStrings: true, ignoreProps: true`, `allowedStrings` = punctuation) on `packages/react/src/**/*.tsx`. `index.ts` argues the kit's `Record<Locale, string>` model is right for ~50 strings and wrong for thousands (plurals, translator workflow).

## 7. Tests

- Vitest with `globals: false`: every file starts `import { describe, expect, it, vi } from 'vitest'` (alphabetical). Environment `jsdom`. `@testing-library/react` (`render`, `screen`, `fireEvent`, `renderHook`, `waitFor`), matchers via `import '@testing-library/jest-dom/vitest'` in setup. Glacier adds `axe-core`: every component suite ends with `it('has no axe violations', async () => { const results = await axe.run(container, { rules: { region: { enabled: false }, 'page-has-heading-one': { enabled: false } } }); expect(results.violations).toEqual([]); })`.
- AttackFM layout: co-located `src/**/*.test.{ts,tsx}`; shared fixtures in `src/test/` (`libraryFixtures.ts` `track(over: Partial<Track>)`, typed as `Track` never `any`; malformed input is `as unknown as Track`); `src/test/setup.ts` does `cleanup()`, `localStorage.clear()`, `sessionStorage.clear()`, and stubs `matchMedia` to answer no. `restoreMocks: true`. `vitest.config.ts` is a separate file that `mergeConfig`s `vite.config.ts` so `define` constants exist. Coverage: v8, `reporter: ['text', 'lcovonly']`, denominator is all of `src/`, thresholds are a ratchet (12.5/12.5/11/9.5) that "never go down".
- Glacier layout: `packages/react/test/*.test.tsx` importing from `../src/index.ts`; `test/setup.ts` polyfills `matchMedia`, `PointerEvent` (as a `MouseEvent` subclass so clientX survives), `ResizeObserver`; projects `tokens`, `spec`, `logic` (node) and `react` (jsdom); thresholds 92/76/77/92, "Raise these as coverage grows; never lower them."
- What gets tested: pure logic pulled into `.ts` siblings (`react-refresh/only-export-components` at `error` forces this); behaviour by role and accessible name (`getByRole('switch', { name: 'Wi-Fi' })`); controlled vs uncontrolled; kit defaults such as `data-haptic="selection"` on native inputs; rate floors and once-latches by spying the motor (`vi.mock('../core/haptics.ts', () => ({ fireMicroTick, fireNativeHaptic }))`); "A TEST THAT PASSES PROVES NOTHING UNTIL YOU HAVE WATCHED IT FAIL" (`harness.test.tsx`) - each case says which production line would break it.
- Test names are sentences with the same voice: `it('holds a floor between ticks, however fast the finger moves')`, `it('arrives exactly once per gesture')`, `it('KEEPS a bare year in brackets - "Alive (2007)" is a record, not a note')`. Suite headers quote the module's own doc comment back. Tests are exempt from the i18n scanner; `no-explicit-any` stays `error` in tests.

## 8. Lint and compiler rules that bite

TypeScript (both repos): `strict`, `noUncheckedIndexedAccess` (so `arr[0]!` or a guard; hence `no-non-null-assertion` is off), `isolatedModules`, `allowImportingTsExtensions`, `moduleResolution: "bundler"`, `target: ES2022`, `jsx: react-jsx`; AttackFM adds `types: ["vite/client"]`, `include: ["src", "vite.config.ts"]`.

AttackFM eslint (`npm run lint` = `eslint . --max-warnings 0`): `no-empty: 'error'` bare (comment every empty block); `@typescript-eslint/no-empty-function` with `allow: ['arrowFunctions']`; `@typescript-eslint/no-explicit-any: 'error'` (9 `as any` remain, 49 `as unknown as`); `eqeqeq: ['error', 'always', { null: 'ignore' }]`; `no-useless-assignment: 'error'`; `no-unused-vars` with `^_` ignore for args/vars/caught; `react-hooks/rules-of-hooks: 'error'`; `react-hooks/exhaustive-deps: 'error'`; `react-refresh/only-export-components: ['error', { allowConstantExport: true, allowExportNames: [...context hooks and tables] }]` - a `.tsx` may export components plus listed hooks; helpers go in `.ts` siblings. `no-restricted-syntax` bans raw `<button|input|textarea|select>` and hand-rolled `role="progressbar"` on the AI surfaces ("AI surfaces use GlacierUI primitives: Button, TextField, Textarea, Select - not a raw control") - for Glyph apply this to every surface. React rules glob is `**/*.{ts,tsx}` not `.tsx`. Type-aware rules off by measurement; `void` by convention. Test scope lifts only `no-empty-function`, `only-export-components`, `rules-of-hooks`. `vendor/**` is never linted.

Glacier eslint: `react/jsx-no-literals` as above; hooks rules; scope `packages/react/src/**/*.tsx`.

Build: Vite `rollupOptions.onwarn` throws on any warning except two named cycles; `chunkSizeWarningLimit` raised to a number that is "still an alarm". CI (`.github/workflows/ci.yml`) runs `npm ci`, `lint`, `typecheck`, `test`, `i18n:gate`, `prefs:check`, `build`; `npm run check` locally.

## 9. Haptics vocabulary (for Glyph's brief)

Kit: `HapticKind = 'selection' | 'light' | 'medium' | 'heavy' | 'success' | 'warning' | 'error'`; `HapticsProvider({ enabled = false, impl?: HapticFn })` with one delegated `pointerdown` listener (touch only); `useHaptics()`, `haptic(kind)`, `setHapticsEnabled`, `data-haptic="selection"` on native inputs, `data-haptic="none"` opt-out. App: `AppProviders` mounts `<HapticsProvider enabled={false} impl={hapticsImpl}>` and installs its own `installTapHaptics()` that fires on pointerUP within `TAP_SLOP_PX` 10 / `TAP_MAX_MS` 700 on a `TAPPABLE` selector. `fireNativeHaptic(kind)` maps to `@tauri-apps/plugin-haptics` `impactFeedback` / `selectionFeedback` / `notificationFeedback`; `fireMicroTick()` = `impactFeedback('soft')`; `fireFelt(kind, at)` with `FLOOR_MS` 28; `makeRatchet()` with `TICK_FLOOR_MS` 28, `NOTCH_FAR` 24 / `NOTCH_NEAR` 9 and pure `nextNotch`, `notchWeight`, `notchSpacing` for tests; `hapticsAvailable()` gates the Settings row; pref `attackfm-haptics` on/off, default `isMobile`.
