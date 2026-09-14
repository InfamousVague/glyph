# Glyph scaffold plan: a hand-built create-glacier-app for a phone

Reference notes for the design panel. Everything below was read from the files named; nothing is
guessed. Absolute paths throughout.

## 1. What `create-glacier-app` actually does (so we can do it by hand)

Source: `/Users/matt/Development/UIUX/GlacierUI/packages/create-glacier-app/build.mjs` and `index.mjs`.

`build.mjs` (run on `prepack`) assembles `template/` from the live starter app
`/Users/matt/Development/UIUX/GlacierUI/apps/starter`:

1. Ensures `packages/react/dist/{index.js,index.d.ts,styles.css}` exist (builds with
   `npm run build -w @glacier/react` if not; that script is `vite build && NODE_OPTIONS=--max-old-space-size=20480 rollup -c rollup.dts.config.mjs`).
2. Copies `apps/starter/src` and `apps/starter/index.html` into the template, then **overwrites
   `src/styles.css` with `packages/react/dist/styles.css`** (the monorepo starter's `src/styles.css`
   is an empty placeholder because the monorepo aliases `@glacier/react` to raw TS source).
3. Writes a standalone `package.json` (name `__APP_SLUG__`, scripts `dev`/`build`/`preview`/`typecheck`,
   deps `@glacier/react|tokens|icons` as `file:./vendor/@glacier/*`, `react ^19.1.0`, `react-dom ^19.1.0`,
   `motion ^12.23.0`, `lucide-react ^1.23.0`; devDeps `@types/react ^19.2.0`, `@types/react-dom ^19.2.0`,
   `@vitejs/plugin-react ^5.0.0`, `typescript ^5.9.0`, `vite ^7.0.0`).
4. Writes `vite.config.ts` (`base: './'`, `plugins: [react()]`, `server: { port: 5240, strictPort: true }`,
   `clearScreen: false`) and `tsconfig.json` (`target ES2022`, `lib [ES2022, DOM, DOM.Iterable]`,
   `module ESNext`, `moduleResolution bundler`, `jsx react-jsx`, `strict`, `noUncheckedIndexedAccess`,
   `skipLibCheck`, `isolatedModules`, `allowImportingTsExtensions`, `noEmit`, `resolveJsonModule`;
   `include: ['src', 'vite.config.ts']`).
5. Vendors the kit:
   - `vendor/@glacier/react/dist/{index.js,index.d.ts,styles.css}` + a `package.json` with
     `exports: { '.': { types: './dist/index.d.ts', import: './dist/index.js' }, './styles.css': './dist/styles.css' }`,
     `dependencies: { motion: '^12.23.0' }`, `peerDependencies: react/react-dom ^19.0.0`.
   - `vendor/@glacier/tokens/{src (minus generate.ts), css, json}` + `package.json` with
     `exports: { '.': './src/index.ts', './css/tokens.css', './css/fonts.css', './json/tokens.json' }` and the
     fontsource deps copied from `packages/tokens/package.json`.
   - `vendor/@glacier/icons/src` + `package.json` (`exports: { '.': './src/index.ts' }`, dep `lucide-react ^1.23.0`).
6. Copies `apps/starter/src-tauri` (minus `target`), replacing `com.glacier.starter` with `__APP_IDENTIFIER__`.
7. Writes `_gitignore` (`node_modules`, `dist`, `.DS_Store`, `src-tauri/target`) and a README.

`index.mjs` then: copies the template, renames `_gitignore` -> `.gitignore`, runs a text replace over
`.(json|ts|tsx|html|css|md|rs|toml)` for `__APP_SLUG__`, `__APP_IDENTIFIER__` (`com.example.<slug>`),
`__APP_NAME__`, and the literal `Glacier Starter`; and for the Tauri option adds scripts
`tauri`/`tauri:dev`/`tauri:build`, devDep `@tauri-apps/cli ^2`, deps `@tauri-apps/api ^2` and
`@tauri-apps/plugin-opener ^2`.

## 2. Where the freshest built kit lives (confirmed with `ls -la` and md5)

- **Only `/Users/matt/Development/Apps/AttackFM/vendor/@glacier/react/dist/` has a built kit**:
  `index.js` 1,309,978 B, `index.d.ts` 293,466 B, `styles.css` 251,466 B, all dated **Sep 6 21:01**.
- `floe/vendor/@glacier/react/` and `PrettyCardboard/vendor/@glacier/react/` contain **only `package.json`**
  (their directories were touched Sep 6 21:00 but there is no `dist/`). The monorepo
  `packages/react/dist` does not exist either. So AttackFM's copy is the one to vendor.
- `AttackFM/vendor/@glacier/tokens/css/tokens.css` md5 `1adfc2b3…` == monorepo `packages/tokens/css/tokens.css`
  (Aug 1). floe's tokens.css differs (older). Copy tokens and icons from AttackFM too.
- Vendor `package.json`s in AttackFM match the template's shapes above. `@glacier/tokens` deps:
  `@fontsource-variable/inter ^5.2.8`, `@fontsource-variable/jetbrains-mono ^5.2.8`,
  `@fontsource-variable/noto-sans ^5.2.10`, `@fontsource/ibm-plex-mono ^5.2.7`, `@fontsource/ibm-plex-sans ^5.2.8`
  (resolve to 5.3.0). `fonts.css` is five `@import`s of those packages.
- `@glacier/icons/src/index.ts` is `export * from 'lucide-react'` plus `export type { LucideProps as IconProps }`
  and `ICON_NAMES`.

Refresh command (when the kit changes): `cd /Users/matt/Development/UIUX/GlacierUI && npm run build -w @glacier/react`,
then copy `packages/react/dist/*` into `glyph/vendor/@glacier/react/dist/` and re-run `npm install`
(the `file:` dep is a symlink-free copy in npm 11, so re-install is what refreshes `node_modules`).

## 3. Files to create under `/Users/matt/Development/Apps/glyph` (currently empty)

Notation: **COPY** = byte-copy from the path shown; **ADAPT** = start from the path shown and change what is listed; **NEW** = write from the spec below.

### Root
| File | Action |
| --- | --- |
| `package.json` | NEW, see §4 |
| `tsconfig.json` | COPY `/Users/matt/Development/Apps/AttackFM/tsconfig.json` (the template's plus `"types": ["vite/client"]`) |
| `vite.config.ts` | NEW, see §5 |
| `index.html` | NEW, see §6 |
| `.gitignore` | ADAPT AttackFM's: `node_modules`, `/dist`, `.DS_Store`, `src-tauri/target`, `/coverage`, plus the `src-tauri/gen/**` negation chain in §9 |
| `README.md` | ADAPT template README (`__APP_NAME__` -> Glyph) |
| `eslint.config.js` | ADAPT `/Users/matt/Development/Apps/AttackFM/eslint.config.js`: keep `IGNORED` (`node_modules/**`, `vendor/**`, `dist/**`, `src-tauri/gen/**`, `src-tauri/target/**`, `coverage/**`, `docs/**`), the `house` rules and `reactRules`, the `src/**/*.{ts,tsx}` scope, the scripts scope and the test scope; drop the site/plugins/e2e/booth scopes and the `allowExportNames` list (start it at `['useAppearance','useT']`) |
| `vitest.config.ts` | ADAPT AttackFM's: `mergeConfig(appConfig, defineConfig({ test: { environment: 'jsdom', globals: false, setupFiles: ['./src/test/setup.ts'], include: ['src/**/*.test.{ts,tsx}'], restoreMocks: true } }))`; no coverage thresholds yet |
| `src/test/setup.ts` | COPY `/Users/matt/Development/Apps/AttackFM/src/test/setup.ts` |
| `scripts/ios-clean.mjs` | COPY `/Users/matt/Development/Apps/AttackFM/scripts/ios-clean.mjs` (it hardcodes `app_iOS.xcarchive` and `libapp.a`, so keep the crate named `app`, see §9) |

### Vendored kit (all COPY from `/Users/matt/Development/Apps/AttackFM/vendor/@glacier/`)
`react/package.json`, `react/dist/index.js`, `react/dist/index.d.ts`, `react/dist/styles.css`;
`tokens/package.json`, `tokens/css/{fonts.css,tokens.css}`, `tokens/json/tokens.json`, `tokens/src/*.ts`
(color, contrast, density, effects, elevation, gradient, index, layout, motion, radius, semantic, shape, size, space, theme-presets, type);
`icons/package.json`, `icons/src/{index.ts,index.native.ts,names.ts}`.

### `src/`
| File | Action |
| --- | --- |
| `src/main.tsx` | NEW, see §7 |
| `src/app/App.tsx` | ADAPT starter `src/app/App.tsx`, see §8 |
| `src/app/app.css` | NEW, see §10 |
| `src/app/preferences.ts` | ADAPT starter, see §11 |
| `src/app/SettingsSheet.tsx` | ADAPT starter `SettingsModal.tsx`, see §11 |
| `src/app/i18n.ts` | ADAPT starter: keep `APP_LOCALES`, `LANGUAGES`, `messages`, `MessageKey`, `useT()`, `toKitLocale()`; replace the keys with Glyph's strings |
| `src/app/router.ts` | REPLACE the hash router with a two-screen stack (§8) |
| `src/app/tauri.ts` | ADAPT starter: keep `isTauri()` (`'__TAURI_INTERNALS__' in window`); drop `minimizeWindow`/`toggleMaximizeWindow`/`closeWindow`/`greet`; use AttackFM's literal `await import('@tauri-apps/api/core')` style, not the starter's `/* @vite-ignore */` computed specifier |
| `src/app/platform.ts` | COPY `/Users/matt/Development/Apps/AttackFM/src/app/core/platform.ts` minus `hasLocalLibrary`/`canRunSubprocesses` (keeps `isMobile`, `isIOS`, `isAndroid`, `isDesktopApp`, and the `document.documentElement.dataset.platform` stamp) |
| `src/app/haptics.ts` | ADAPT `/Users/matt/Development/Apps/AttackFM/src/app/core/haptics.ts` (rename `PREF_KEY` to `'glyph-haptics'`; drop `heartbeatHaptic`) |
| `src/app/ratchet.ts` | COPY `/Users/matt/Development/Apps/AttackFM/src/app/ux/ratchet.ts` (+ `ratchet.test.ts`) |
| `src/app/systemBack.ts` | ADAPT `/Users/matt/Development/Apps/AttackFM/src/app/nav/systemBack.ts` (rename `__AFM_BACK__` -> `__GLYPH_BACK__`, and in MainActivity.kt) |
| `src/app/useMediaQuery.ts` | COPY `/Users/matt/Development/Apps/AttackFM/src/app/ux/useMediaQuery.ts` |
| `src/app/notes/NotesList.tsx`, `src/app/notes/EditorScreen.tsx` | NEW placeholders for the editor/store readers |

Not created: `src/styles.css` (the template's snapshot of the kit CSS; AttackFM imports `@glacier/react/styles.css` instead, see §7), `RouteSidebar.tsx`, `pages/DashboardPage.tsx`, `pages/LibraryPage.tsx`, `pages/AboutPage.tsx`.

### `src-tauri/`
| File | Action |
| --- | --- |
| `Cargo.toml` | NEW, see §9 |
| `build.rs` | COPY starter (`fn main() { tauri_build::build() }`) |
| `.gitignore` | COPY starter (`/target`, `/gen/schemas`) |
| `src/main.rs` | COPY starter (`app_lib::run()`) |
| `src/lib.rs` | NEW, see §9 |
| `capabilities/default.json` | NEW, see §9 |
| `tauri.conf.json`, `tauri.ios.conf.json`, `tauri.android.conf.json` | NEW, see §9 |
| `Info.ios.plist` | ADAPT `/Users/matt/Development/Apps/AttackFM/src-tauri/Info.ios.plist`, see §9 |
| `app-icon.png` | NEW 1024px source; run `npx tauri icon src-tauri/app-icon.png` (AttackFM has 21 entries in `icons/`) |
| `vendor/tao/` | COPY `/Users/matt/Development/Apps/AttackFM/src-tauri/vendor/tao` (1.5 MB, tao 0.35.3 + the autorelease backport), see §9 |
| `Cargo.lock` | do NOT copy; let cargo regenerate |
| `gen/` | produced by `npx tauri ios init` / `npx tauri android init`; hand-written parts in §9 |

## 4. `package.json` (versions from AttackFM/floe; resolved versions in AttackFM's lock in brackets)

```json
{
  "name": "glyph",
  "private": true,
  "version": "0.1.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc --noEmit && vite build",
    "preview": "vite preview",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest",
    "lint": "eslint . --max-warnings 0",
    "check": "npm run lint && npm run typecheck && npm run test",
    "tauri": "tauri",
    "tauri:dev": "tauri dev",
    "tauri:build": "tauri build",
    "ios:dev": "node scripts/ios-clean.mjs && tauri ios dev",
    "ios:build": "node scripts/ios-clean.mjs && tauri ios build",
    "ios:build:sim": "node scripts/ios-clean.mjs && tauri ios build --debug --target aarch64-sim",
    "android:dev": "JAVA_HOME=\"/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home\" ANDROID_HOME=\"$HOME/Library/Android/sdk\" NDK_HOME=\"$HOME/Library/Android/sdk/ndk/26.3.11579264\" tauri android dev",
    "android:build": "JAVA_HOME=\"/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home\" ANDROID_HOME=\"$HOME/Library/Android/sdk\" NDK_HOME=\"$HOME/Library/Android/sdk/ndk/26.3.11579264\" tauri android build",
    "android:emulator": "\"$HOME/Library/Android/sdk/emulator/emulator\" -avd glyph -netdelay none -netspeed full"
  },
  "dependencies": {
    "@glacier/icons": "file:./vendor/@glacier/icons",
    "@glacier/react": "file:./vendor/@glacier/react",
    "@glacier/tokens": "file:./vendor/@glacier/tokens",
    "@tauri-apps/api": "^2",
    "@tauri-apps/plugin-deep-link": "^2.4.9",
    "@tauri-apps/plugin-haptics": "^2.3.2",
    "@tauri-apps/plugin-opener": "^2",
    "lucide-react": "^1.23.0",
    "motion": "^12.23.0",
    "react": "^19.1.0",
    "react-dom": "^19.1.0"
  },
  "devDependencies": {
    "@eslint/js": "^10.0.1",
    "@tauri-apps/cli": "^2",
    "@testing-library/dom": "^10.4.1",
    "@testing-library/jest-dom": "^7.0.1",
    "@testing-library/react": "^16.3.3",
    "@types/node": "26.2.0",
    "@types/react": "^19.2.0",
    "@types/react-dom": "^19.2.0",
    "@vitejs/plugin-react": "^5.0.0",
    "eslint": "^10.10.0",
    "eslint-plugin-react-hooks": "^7.1.1",
    "eslint-plugin-react-refresh": "^0.5.6",
    "globals": "^17.12.0",
    "jsdom": "^30.0.1",
    "typescript": "^5.9.0",
    "typescript-eslint": "^8.70.0",
    "vite": "^7.0.0",
    "vitest": "^5.0.0"
  }
}
```

Resolved in AttackFM's `package-lock.json`: react 19.2.8, vite 7.3.6, typescript 5.9.3, @vitejs/plugin-react 5.2.0,
@tauri-apps/api 2.11.1, @tauri-apps/cli 2.11.4, plugin-haptics 2.3.2, plugin-opener 2.5.4, plugin-deep-link 2.4.9,
motion 12.43.0, lucide-react 1.28.0, @types/react 19.2.18, vitest 5.0.0, eslint 10.10.0, typescript-eslint 8.70.0.
Local toolchain: node v25.9.0, npm 11.12.1, tauri-cli 2.11.4, rustc 1.94.1, Xcode 26.6, xcodegen at `/opt/homebrew/bin/xcodegen`.
Installed rust targets include `aarch64-apple-ios`, `aarch64-apple-ios-sim`, `x86_64-apple-ios`, `aarch64-linux-android`,
`armv7-linux-androideabi`, `i686-linux-android`, `x86_64-linux-android`.
Editor-engine deps (CodeMirror etc.) are the editor reader's call and go in `dependencies` later.

## 5. `vite.config.ts`

```ts
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// A relative base so the built app works when Tauri serves it from a custom
// protocol rather than the server root. @glacier/react resolves from the
// vendored copy in node_modules (installed via the file: dependency).
export default defineConfig({
  base: './',
  plugins: [react()],
  server: {
    // 5240 is AttackFM, 5241 is floe; must match tauri.conf.json build.devUrl.
    port: Number(process.env.PORT) || 5242,
    strictPort: true,
  },
  clearScreen: false,
});
```
AttackFM's `define`/OTA/rollup `onwarn` machinery is not needed (no over-the-air bundles); its
`onwarn` that throws on unlisted rollup warnings is worth keeping if the panel wants the same gate.

## 6. `index.html` (phone)

```html
<!doctype html>
<html lang="en" data-theme="dark">
  <head>
    <meta charset="UTF-8" />
    <!-- maximum-scale=1 / user-scalable=no: an app shell, not a document -
         without them iOS zooms the page when a focused input's font is under
         16px. viewport-fit=cover is what makes env(safe-area-inset-*) report
         real values, so the notch/home-indicator padding in app.css engages. -->
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover"
    />
    <title>Glyph</title>
    <style>
      /* Pre-tokens paint so the first frame is never a white flash. */
      html { background: #0f0f10; }
      html[data-theme='light'] { background: #ffffff; }
    </style>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
```
The viewport line and its comment are AttackFM's verbatim. `#0f0f10` is also the Android
`android:windowBackground` in `res/values/themes.xml`, so the boot colour matches on both sides.
AttackFM additionally reads its stored locale in an inline `<script>` before paint (key `attackfm-locale`)
so RTL does not flip after first render; Glyph can do the same for `data-theme` if it defaults to `system`.

## 7. `src/main.tsx` import order

```tsx
import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
// The token layer: fonts first, then the CSS custom properties every component reads.
import '@glacier/tokens/css/fonts.css';
import '@glacier/tokens/css/tokens.css';
// The compiled component styles, read straight from the vendored package rather
// than a copy in src/: a snapshot goes stale the moment the kit is rebuilt, and a
// stylesheet whose class hashes no longer match the JS silently unstyles everything.
import '@glacier/react/styles.css';
import './app/app.css';
import { App } from './app/App.tsx';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
```
This is AttackFM's order (`/Users/matt/Development/Apps/AttackFM/src/main.tsx`), which differs from the
template's `./styles.css` snapshot import on purpose (the comment is theirs). AttackFM also stamps
`document.documentElement.dataset.platform` before render; `platform.ts` does that at import time.

## 8. What to drop from the starter's desktop shell, and what replaces it

Starter `App.tsx` (`/Users/matt/Development/UIUX/GlacierUI/apps/starter/src/app/App.tsx`) composes
`TitleBar` (with `data-tauri-drag-region`, `trafficLightInset`, `SidebarToggle`, `SearchField` + `Kbd ⌘K`, `Bell`, `Avatar`),
an `AppRail` (`NavBar orientation="vertical"` with `NavBarItem`s and an `end` slot for Settings),
`RouteSidebar` (`Sidebar`/`SidebarSection`/`SidebarItem`, brand lockup), a `main.appContent`, and `SettingsModal`;
`preferences.layout` (`'floating' | 'full'`) and `sidebarCollapsed` drive `.appWindow[data-layout]`/`[data-sidebar]` in `app.css`.

Drop for Glyph: `TitleBar` and everything in it, `SidebarToggle`, `AppRail`, `RouteSidebar.tsx`, the three pages,
`DESKTOP = isTauri()` (wrong on a phone; AttackFM's `isDesktopApp = isTauri() && !isMobile` is the right question),
the hash `router.ts` (`ROUTES = ['dashboard','library','about']`, `useRoute()`), `VisualFeedbackProvider`
(desktop pointer effect), and the preferences `layout`, `sidebarCollapsed`, `font`, `mono`, `radiusScale`,
`frostedness`, `visualFeedback*`. Also drop the root `data-layout` stamp: the kit's `styles.css` only uses
`[data-layout=bar|bubble|inline|popover|row|square|stacked]` on its own components; `floating`/`full` were the
starter's own app.css hooks.

Keep: the `App()` shape (`useState(loadPreferences)`, one effect calling `applyPreferences` + `savePreferences`,
one effect setting `document.documentElement.lang`/`dir` via `direction(locale)`), `LocaleProvider locale=`,
`ToastProvider` + `useToast().toast({ tone, message })`, `HapticsProvider`, `i18n.ts`'s `useT()`.

Replace with: a two-screen stack in `router.ts`, e.g.
`type Screen = { kind: 'list' } | { kind: 'editor'; id: string }`, `useScreens()` returning `[screen, push, pop]`,
with `useSystemBack(screen.kind !== 'list', pop)` so Android's back swipe pops (AttackFM's `systemBack.ts`
contract: handlers return `true` when consumed; `MainActivity` calls `window.__GLYPH_BACK__()` and
`moveTaskToBack(true)` on anything but `"true"`). Settings opens as an overlay, not a route, exactly as the starter
says ("Settings is not here: it opens in a modal, not a route").

Provider tree for Glyph (AttackFM's `nav/AppProviders.tsx` pattern):
```tsx
<LocaleProvider locale={preferences.locale}>
  <HapticsProvider enabled={false} impl={hapticsImpl}>
    <ToastProvider>
      <Shell />
    </ToastProvider>
  </HapticsProvider>
</LocaleProvider>
```
`enabled={false}` silences only the kit's delegated pointerdown tick (it buzzed on every scroll start);
`impl={hapticsImpl}` keeps `useHaptics()` inside kit components routed to the Taptic Engine. The app-wide tap
tick is `installTapHaptics()` from `haptics.ts` (fires `'selection'` on pointerup within 10 px / 700 ms on a
`TAPPABLE` element), installed once in an effect in `App`. `HapticsProviderProps` is exactly
`{ enabled?: boolean; impl?: HapticFn; children }` with `HapticKind = 'selection'|'light'|'medium'|'heavy'|'success'|'warning'|'error'`.

## 9. The Tauri crate (mirrors AttackFM's phone build)

`Cargo.toml`:
```toml
[package]
name = "app"            # keep "app": gen/apple is named app_iOS/libapp.a and scripts/ios-clean.mjs hardcodes both
version = "0.1.0"
description = "Glyph, a phone-first markdown notes app"
authors = ["Matt"]
edition = "2021"

[lib]
name = "app_lib"
crate-type = ["staticlib", "cdylib", "rlib"]

[build-dependencies]
tauri-build = { version = "2", features = [] }

[dependencies]
tauri = { version = "2", features = [] }
tauri-plugin-opener = "2"
tauri-plugin-deep-link = "2.4.9"
tauri-plugin-haptics = "2.3.2"
serde = { version = "1", features = ["derive"] }
serde_json = "1"

[features]
custom-protocol = ["tauri/custom-protocol"]

# tao 0.35.3 (newest any released tauri accepts; Cargo.lock: tauri 2.11.5, tauri-runtime-wry 2.11.4,
# wry 0.55.1) frees its UISceneConfiguration before UIKit reads it; release builds segfault at
# launch on iOS 26/27. vendor/tao = pristine 0.35.3 + the one-line 0.36.0 autorelease_ptr backport.
[patch.crates-io]
tao = { path = "vendor/tao" }
```
No `tauri-plugin-decorum` (desktop traffic lights; does not build for iOS/Android; AttackFM scopes it under
`[target.'cfg(not(any(target_os = "ios", target_os = "android")))'.dependencies]` only because it still draws a
desktop title bar). Glyph has no title bar, so omit it and its `core:window:allow-*` permissions.
The whisper/store crates (`whisper-rs`, `rusqlite` 0.32.1 is in the local cargo cache) are the other readers' call.

`src/lib.rs` skeleton:
```rust
#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_deep_link::init())
        .plugin(tauri_plugin_haptics::init())
        .invoke_handler(tauri::generate_handler![])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

`capabilities/default.json`:
```json
{
  "$schema": "../gen/schemas/desktop-schema.json",
  "identifier": "default",
  "description": "Permissions the main window needs: the Taptic Engine, the glyph:// link, the opener.",
  "windows": ["main"],
  "permissions": [
    "core:default",
    "opener:default",
    "deep-link:default",
    "haptics:allow-impact-feedback",
    "haptics:allow-notification-feedback",
    "haptics:allow-selection-feedback"
  ]
}
```

`tauri.conf.json` (AttackFM's, trimmed):
```json
{
  "$schema": "https://schema.tauri.app/config/2",
  "productName": "Glyph",
  "version": "0.1.0",
  "identifier": "com.mattssoftware.glyph",
  "build": {
    "frontendDist": "../dist",
    "devUrl": "http://localhost:5242",
    "beforeDevCommand": "npm run dev",
    "beforeBuildCommand": "npm run build"
  },
  "app": {
    "windows": [
      { "title": "Glyph", "width": 420, "height": 860, "minWidth": 360, "minHeight": 560, "resizable": true }
    ],
    "security": { "csp": null }
  },
  "plugins": {
    "deep-link": { "desktop": { "schemes": ["glyph"] }, "mobile": [ { "scheme": ["glyph"] } ] }
  },
  "bundle": {
    "active": true,
    "targets": "all",
    "iOS": { "minimumSystemVersion": "15.0", "developmentTeam": "F6ZAL7ANAD" },
    "icon": ["icons/32x32.png", "icons/128x128.png", "icons/128x128@2x.png", "icons/icon.icns", "icons/icon.ico"]
  }
}
```
Identifier: AttackFM is `com.mattssoftware.attackfm`, floe is `com.infamousvague.floe`; the App Store team
(`F6ZAL7ANAD`, "same team PrettyCardboard signs with") is used with the `mattssoftware` prefix. 420x860 is floe's
phone-shaped desktop window. AttackFM's `withGlobalTauri: true` exists only for its OTA boot loader; not needed.

`tauri.ios.conf.json` / `tauri.android.conf.json` (AttackFM's shape):
```json
{ "$schema": "./gen/schemas/mobile-schema.json",
  "app": { "windows": [ { "title": "Glyph", "label": "main" } ] },
  "bundle": { "externalBin": [] } }
```

`Info.ios.plist` (merged by the CLI into the generated Info.plist; survives re-init, unlike `gen/apple/app_iOS/Info.plist`).
Keep from AttackFM: `CFBundleURLTypes` (`CFBundleURLName` = identifier, `CFBundleURLSchemes` = `glyph`),
`UIApplicationSceneManifest` with `UIApplicationSupportsMultipleScenes=true` and
`UISceneDelegateClassName` = `TaoSceneDelegate` (iOS 26 warns / iOS 27 traps apps without scene adoption),
`UISupportedInterfaceOrientations` = Portrait, `ITSAppUsesNonExemptEncryption=false`, and a
`NSMicrophoneUsageDescription` for capture. Drop `UIBackgroundModes audio`, `NSLocalNetworkUsageDescription`,
`NSBonjourServices`, `NSAppTransportSecurity`, camera/location strings, the CarPlay scene.

`gen/apple/project.yml` (written by `npx tauri ios init`, then hand-edited; a delete-and-reinit resets it, and
`xcodegen generate` must be re-run in `gen/apple` after editing): `deploymentTarget: iOS: 15.0` (template hardcodes
14.0, Xcode 26 refuses it), `DEVELOPMENT_TEAM`/`CODE_SIGN_STYLE: Automatic`. AttackFM also hand-vendored the Swift
halves of `tauri-plugin-haptics` (`gen/apple/tauri-plugin-haptics/Package.swift` depending on
`../.tauri/tauri-api`) and lists it under `packages:` because "this project predates any plugin with real iOS code";
a fresh `ios init` with CLI 2.11.4 should stage them itself; verify `gen/apple/.tauri/tauri-api` exists after init,
otherwise the Taptic Engine silently no-ops.
`gen/apple/.gitignore` is `xcuserdata/ build/ Externals/`; root `.gitignore` also ignores
`src-tauri/gen/apple/{build,Externals,app.xcodeproj,Pods,Podfile.lock}` while tracking `project.yml`.

`gen/android` (from `npx tauri android init`; `compileSdk 36`, `minSdk 24`, `targetSdk 36`): hand-written and
tracked via the `.gitignore` negation chain (`src-tauri/gen/android/**` then `!…/app/src/main/AndroidManifest.xml`,
`!…/java/com/mattssoftware/glyph/**` minus `generated/`, `!…/res/values/**`, `!…/res/xml/**`, `!…/app/build.gradle.kts`):
- `MainActivity.kt` (`class MainActivity : TauriActivity()`): `enableEdgeToEdge()` before `super.onCreate`,
  and in `override fun onWebViewCreate(webView: WebView)` register
  `onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) { … webView.evaluateJavascript("window.__GLYPH_BACK__ ? window.__GLYPH_BACK__() : false") { result -> if (result != "true") moveTaskToBack(true) } })`.
  This is also where the assistant-role / capture overlay work will land.
- `AndroidManifest.xml`: add `<uses-permission android:name="android.permission.RECORD_AUDIO" />`; leave the
  `<!-- DEEP LINK PLUGIN. AUTO-GENERATED. DO NOT REMOVE. -->` block alone (the `glyph` scheme is generated from
  `tauri.conf.json`; a hand-written duplicate was how AttackFM's links went dead).
- `res/values/themes.xml`: `Theme.MaterialComponents.DayNight.NoActionBar` with transparent status/navigation bars,
  `android:enforceNavigationBarContrast=false`, `android:windowBackground=#0f0f10`.

## 10. `src/app/app.css` phone base (from AttackFM's `styles/00-mobile-header-and-dj-traits.css`)

The kit's `styles.css` contains **zero** `safe-area-inset` references, so the app owns insets. Rules to carry over,
all token-valued: `*, *::before, *::after { box-sizing: border-box }`; `html, body { margin: 0; font-family: var(--glacier-font-sans); color: var(--glacier-text); background: var(--glacier-bg); overscroll-behavior: none }`;
`#root { height: 100vh; height: 100dvh }`; `@supports (-webkit-touch-callout: none) { html, body { overscroll-behavior: none; -webkit-text-size-adjust: 100% } }`;
`html { -webkit-touch-callout: none; -webkit-user-select: none; user-select: none; -webkit-tap-highlight-color: transparent }`;
`:focus:not(:focus-visible) { outline: none }`; `input, textarea, select, [contenteditable], [contenteditable] * { -webkit-touch-callout: default; -webkit-user-select: text; user-select: text }` (the editor lives here);
`.appWindow { position: relative; display: flex; flex-direction: column; height: 100dvh; overflow: hidden; background: var(--glacier-bg); color: var(--glacier-text); --app-safe-top: env(safe-area-inset-top, 0px); --app-safe-bottom: env(safe-area-inset-bottom, 0px); --app-safe-left: …; --app-safe-right: … }`.
AttackFM keys Android-only chrome on `html[data-platform='android']` (set by `platform.ts`).
Token names in play: `--glacier-space-1…10`, `--glacier-radius-{sm,md,lg,xl,full}`, `--glacier-hairline`,
`--glacier-glass-border`, `--glacier-surface`, `--glacier-bg`, `--glacier-text`, `--glacier-border`,
`--glacier-focus-ring`, `--glacier-accent-solid`, `--glacier-accent-contrast`, `--glacier-accent-soft`,
`--glacier-accent-text`, `--glacier-font-sans`, `--glacier-font-mono`, `--glacier-font-size-{xs,sm,md,lg,xl,2xl…5xl}`,
`--glacier-duration-fast`, `--glacier-ease-out`, `--glacier-shadow-3/4`, `--glacier-radius-scale`,
`--glacier-glass-blur-scale`. (`var(--glacier-accent)` does not exist; use `-solid`/`-text`.)

## 11. `preferences.ts` and the settings sheet

Starter pattern (`/Users/matt/Development/UIUX/GlacierUI/apps/starter/src/app/preferences.ts`): a `Preferences`
interface, `DEFAULT_PREFERENCES`, `STORAGE_KEY = 'glacier-starter:preferences'`, `loadPreferences()`
(`{ ...DEFAULT_PREFERENCES, ...JSON.parse(raw) }` in try/catch), `savePreferences()`, and `applyPreferences()` which
stamps `document.documentElement`: `data-theme` (removed for `'system'`), `data-density` (removed for `'comfortable'`),
`data-accent` (removed when equal to `accentOptions[0]!.name`, i.e. `'blue'`), `data-font`/`data-mono`, and the inline
custom properties `--glacier-radius-scale`/`--glacier-glass-blur-scale`. Types come from `@glacier/tokens`:
`Density = 'extra-compact' | 'compact' | 'comfortable' | 'spacious' | 'more-space'`, `accentOptions` (names
`blue, green, purple, teal, amber, red, graphite`), `accentSteps(option, theme)[8]` for swatches. tokens.css has
`[data-theme='light'|'dark']`, `[data-density=…]`, `[data-accent=…]`, `[data-font='noto'|'plex']`, `[data-mono='plex']`.

Glyph's trimmed shape:
```ts
export interface Preferences {
  theme: 'system' | 'light' | 'dark';
  density: Density;
  accent: string;
  locale: AppLocale;
}
const STORAGE_KEY = 'glyph:preferences';
```
Haptics live beside it, AttackFM-style, because non-React code (`fireNativeHaptic`, the ratchet) must read the
switch synchronously: `haptics.ts` keeps `PREF_KEY = 'glyph-haptics'` storing `'on'|'off'`, `hapticsPref()` defaulting
to `isMobile`, `setHapticsPref(on)`, `useHapticsPref()` (`useSyncExternalStore`), `hapticsAvailable()`
(`isTauri() && isMobile`), `fireNativeHaptic(kind)`, `fireFelt(kind)` (28 ms floor), `fireMicroTick()`
(`impactFeedback('soft')`), and `hapticsImpl`. The plugin is imported lazily
(`import('@tauri-apps/plugin-haptics')`) and maps kinds to `selectionFeedback()`, `impactFeedback('light'|'medium'|'heavy')`,
`notificationFeedback('success'|'warning'|'error')`.

Settings surface: the starter's `SettingsModal` (`Modal size="lg"`, `FormSection`/`Fieldset`/`Label`,
`SegmentedControl` for theme with `fullWidth`, `DensitySelector value onValueChange aria-label`, accent
`role="radiogroup"` swatches, `Switch label checked onCheckedChange`, footer `Button variant="outline"` Reset +
`Button` Done, `toast({ tone: 'neutral', message: 'Settings reset to defaults' })`). On a phone AttackFM swaps the
modal for a full-screen portalled sheet (`MobileSettings`, `MOBILE_QUERY = '(pointer: coarse) and (max-width: 699px), (max-width: 540px)'`,
rows built from `PaneSection`/`SettingRow`). For Glyph the kit `Drawer` (`open, onClose, title, side, size, floating, footer, dismissible`)
or `Modal` (`size: 'sm'|'md'|'lg'|'xl'`) both portal; the panel should pick one. The haptics row renders only when
`hapticsAvailable()` and fires `fireNativeHaptic('light')` 50 ms after switching on (AttackFM `AppearancePane.tsx`).

## 12. Kit facts the panel must not get wrong

- Exports include `RichTextEditor` (`value, defaultValue, onValueChange, placeholder, marks: MarkdownMark[], blocks: MarkdownBlock[], rows, maxLength`)
  with `MarkdownMark = 'bold'|'italic'|'code'|'strike'` and `MarkdownBlock = 'heading'|'quote'|'bullet'|'number'`;
  also `Textarea`, `VirtualList` (`count, itemSize, renderItem, height, overscan, getKey, emptyLabel`, `VirtualListHandle.scrollToIndex`),
  `NavBar` (`orientation, 'aria-label', end, showLabels`), `NavBarItem` (`icon, label, active, badge`), `PageHeader`
  (`title, description, actions, secondaryActions, headingLevel, density`), `TitleBar`, `Toolbar`, `EmptyState`,
  `AlertDialog` (`open, onClose, title, actionLabel, onAction, tone`), `SearchField`, `List`/`ListItem`, `Skeleton`.
- `direction(locale)`, `LocaleProvider`, `useLocale`, `locales`, `rtlLocales`, `DEFAULT_LOCALE`, `densityModes`,
  `DensityMode` (= `Density`), `useHaptics`, `haptic`, `setHapticsEnabled`, `VisualFeedbackProvider`.

## 13. Open questions

1. Crate name `app`/`app_lib` (AttackFM, template) vs `glyph`/`glyph_lib` (floe's style): keeping `app` lets
   `scripts/ios-clean.mjs` copy verbatim.
2. Bundle identifier: `com.mattssoftware.glyph` (AttackFM) or `com.infamousvague.glyph` (floe)?
3. Whether tauri-cli 2.11.4's `ios init` stages the haptics Swift package or whether it must be copied from
   `AttackFM/src-tauri/gen/apple/{.tauri,tauri-plugin-haptics}`.
4. Default theme `'dark'` (starter, AttackFM) vs `'system'`; affects the `index.html` pre-paint.
5. Whether to keep the kit's delegated tap haptics (`HapticsProvider enabled`) or AttackFM's pointerup tick.
