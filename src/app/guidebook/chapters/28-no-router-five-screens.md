# No router, five screens

_How the page gets from `index.html` to a screen, and the small machines that hold it there._

Paths in this chapter are under `src/app/` unless they start with `src/` or name another root.

## Before anything mounts

`index.html` paints the background before any token loads, so the first frame is never white. Then an inline script at the end of `<body>` decides which frontend runs. It is written in ES5 with no dependencies, because it has to work with every bundle it might choose.

In a browser, or on the dev server, it does nothing: there is no Tauri, or no built module script, and so no choice to make. Inside the app it:

1. asks Rust `ota_claim_boot` which bundle this launch runs, and runs the embedded frontend if no answer comes within 1.5 seconds;
2. adds the chosen bundle's stylesheets, and only once all of them have loaded, takes the embedded ones away and adds the bundle's module script;
3. gives the bundle 8 seconds to mount, and listens for errors thrown from the bundle's own files;
4. on any failure, calls `ota_boot_failed`, puts the embedded stylesheets back, empties `#root` and mounts the embedded frontend in the same launch.

The embedded module tag is never removed, because a removed module script still runs. So two copies of `src/main.tsx` can load in one launch. Each asks `window.__glyphBoot` whether its own URL is the chosen one, and only that one mounts.

Rendering is not the success signal, since a render only schedules. The first effect of the Shell's housekeeping (`shell/useHousekeeping.ts`) runs `settleBoot` in `core/ota.ts`, which sets `__glyphBoot.mounted` and reports `ota_boot_ok`. The stake and the quarantine behind this are in [[Over the air, and releases]].

## The mount

`src/main.tsx` imports its stylesheets in an order that matters:

| Order | Stylesheet | What it brings |
|---|---|---|
| 1 | `@glacier/tokens/css/fonts.css` | The kit's faces |
| 2 | `@fontsource-variable/inter/opsz.css` | Inter with its optical-size axis, so display sizes draw Inter Display |
| 3 | `@glacier/tokens/css/tokens.css` | The custom properties every component reads |
| 4 | `@glacier/react/styles.css` | The kit's compiled component styles |
| 5 | `src/app/app.css` | The app's own layout |
| 6 | `src/app/ink.css` | The ink palette, which maps the tokens onto paper and ink |
| 7 | `src/app/typefaces.css`, `src/app/editor/codeThemes.css` | The note's faces, and the colours for code |

The kit's styles are read straight from `vendor/@glacier`, not copied into `src/`. A copy goes stale when the kit is rebuilt, and class hashes that no longer match its JavaScript silently unstyle every component.

The module then starts `followShares()`, which sends a changed share again a few seconds after a save, and renders `<App />` inside `StrictMode` into an emptied `#root`.

## Five screens

`App` is a `HapticsProvider`, a `ToastProvider` and the `Shell`. The Shell's one piece of routing state is a `Screen`, from `shell/screen.ts`:

| `name` | What it is | A place? |
|---|---|---|
| `list` | The home page (`home/HomeScreen.tsx`), where the app opens | Yes |
| `notes` | All notes, as a grid of cards (`notes/AllNotesScreen.tsx`) | Yes |
| `note` | One note, perhaps with an `^anchor` to land on, a spoken ask to run, or a review | Yes |
| `capture` | A recording, keyed by `Date.now()` so each one is a fresh mount | No |
| `academy` | Ghost.md Academy, which teaches a mark at a time | No |

The home page is still named `list`, from the days when the home page was the notes list.

A place is somewhere a person goes. Places carry the tab row, they are what the back and forward arrows walk, and on a wide window they take a pane beside the sidebar. A capture and the Academy each take the whole window, and each has its own way out.

Everything else is a sheet or a card over whichever screen is up, held beside `screen` in the Shell: Settings, the guide, the + sheet, the new book sheet, what's new, the notes drawer, the aside, the palette and the launch screen.

There is no router because a router would be a dependency, with its own edge cases, bought to hold one piece of state. Nothing needs an address either. The only ones the page reads are `#fork=` from a shared link and three development switches: `?capture`, `?simulate` (with `say=` beside it for phrases of your own) and `?review`.

## Back is a stack

Android owns the back swipe. `MainActivity.kt` catches it and asks the page, through `window.__glyph.back()`. `core/back.ts` answers by walking a stack of handlers, newest first. A screen or a sheet registers a handler while it is up (`useBack(active, close)`), so the last thing opened is the first thing a swipe closes.

The answer to Android is always yes (`tookBack`), so a back swipe never takes the person out of the app. One thumb stroke can be both the page's own right-swipe and Android's gesture a moment later, so a gesture within 500 ms of the page stepping back counts as the same one. Escape walks the same stack but gives the honest answer, since a key the page did not use belongs to whatever else is listening.

## The machines in shell/

The parts of the Shell that are machines of their own live in `shell/`, one hook each, each with a test beside it. Each header says what has bitten it.

| File | What it holds | What its header warns of |
|---|---|---|
| `useOpenTabs.ts` | The open tabs, at most eight (`MOST_TABS`), and their Chrome-style groups (`notes/openTabs.ts`, `notes/tabGroups.ts`) | A page opened from inside a book takes the current tab's place (`swapOpen`); a request nothing read once lingered and stole the next note's tab. Groups pruned against tabs not loaded yet were emptied on every start. |
| `useTrail.ts` | Where the person has been, for the arrows (`notes/visited.ts`) | A "this move was me" flag, left set by a step that landed where the page already was, killed Back on the next note |
| `useCaptureRoute.ts` | How a capture begins, and where the app lands after it | Every start waits for deferred deletes first (`capture/launch.ts`), or the recorder reads a note that is about to go. The side key during a capture is Stop, because Android never says when the key is let go. |
| `useGuide.ts` | The walkthrough, and its too-soon guard | In 1.6 a side key held on the guide's first page opened the home page with neither the guide nor its "Not yet, finish reading." line |
| `useForkLinks.ts` | A shared link arriving, as `#fork=<link>` or `ghostmd://` (`share/appLinks.ts`) | Both wait for the notes to be read, and the hash leaves the address bar so a reload does not save the copy twice |
| `useHousekeeping.ts` | The work that draws nothing | `settleBoot` runs first, before anything that might reload. A voice command's undo, offered again after a restart, once vanished under StrictMode's second run of the effect. |
| `useRootStamp.ts` | `data-tabs` and `data-split` on `<html>` | Widths and heights kept in several stylesheets, each copy a chance to disagree |
| `useVisibleNotes.ts` | The notes a screen may show: none held back by a pending delete, none in the trash | The old list filtered and the other screens did not, so a note had to be deleted twice before it left them |

`useHousekeeping.ts` is also where the rest of the background work starts: the back stack and the tap haptics, the better-words queue (`capture/refine.ts`), sync, the sidebar's refresh 300 ms after a save on a window wide enough for two panes, the one-time sweep that puts any memos left from older builds in the trash (`core/sweepMemos.ts`), and the sample note for a library that is still empty four seconds after its first read.

## The chrome

- **The tab row** is `notes/NoteTabs.tsx` in `.app-tabBar`, drawn once by the Shell on every place, the same on each. The screens know nothing about it: `--app-safe-top` carries its height, and `useRootStamp('tabs', …)` says `on`, or `rows` when a second row of tabs is showing. Its first row holds home, the sidebar's icon, back and forward, a slot for the screen's own buttons and, when there is something to show, the aside's icon. The second row holds the open tabs with the + after the last one, and is not drawn at all when nothing is open.
- **The dock** is the home page's floating column of buttons (`home/HomeScreen.tsx`): write, Speak, Settings, and Search once the palette has handed back its opener.
- **The sidebar** is one tree, `notes/NoteTree.tsx`, shown two ways. By default it is a popover card, `notes/NotesDrawer.tsx`. Docked is a column beside the note: it is chosen in Settings, and only possible when `useSidebar()` in `core/useWideScreen.ts` says the window fits two panes. That means at least 660px wide, and at least 600px tall unless there is a mouse. While a field has the focus the height keeps its last answer, so the keyboard rising on an opened Fold cannot move the note into another pane and so close the keyboard again.
- **The aside** shows a book's index while the book or one of its pages is open, or a run of numbered chapters that have no book (`aside/aside.ts`). Anywhere else it holds nothing, and neither it nor its toggle is drawn.
- **The palette** is the kit's `CommandPalette`, in `commands/CommandBar.tsx`, over the list in `commands/palette.ts`. The kit binds ⌘K. A phone reaches it from the notes drawer's first row, or from the dock's Search. `palette.ts` is pure: handed the state of the app and a set of doings, it answers a list, and every doing is something the app already does by hand.

## One sheet that travels

`core/preferences.ts` holds one object in `localStorage` under `glyph-preferences`. `settle` makes it whole on every read, so a store written by an older or a newer build still reads as something the app can draw. `applyPreferences` stamps it onto `<html>` as `data-*` attributes, a root font size and the kit's durations. Density, accent, rounding, text size and the interface's face take their attribute off at the default, because the token CSS keeps the defaults on `:root`. The theme, the note's face and the two code themes are always stamped; the theme comes off only when it follows the system.

The sheet carries more than settings. It holds the open tabs (`openNotes`), the tab groups, the workspaces and which note is filed in each, the trash, and the notes shared by link with their keys. They live here because the notes are Rust's, and a new field there is a native change and a new APK, while a preference ships over the air.

`core/sync/prefs.ts` lists the keys that travel, sealed as one blob; when two devices both changed their settings, the one sending now wins. The interface size, the sidebar style, the accent, the corner rounding, the formatting model and Local only stay on the device, and so does which workspace the list is showing.

## Haptics off, and on

`App` mounts the kit's `HapticsProvider` with `enabled={false}` and `impl={hapticsImpl}`. That looks like a contradiction and is not.

The flag switches off only the kit's own delegated tick, which fires on pointerdown and so buzzed all the way down a flicked list. It also keeps the kit's web engine silent in a browser. The `impl`, `fireNativeHaptic` in `core/haptics.ts`, is what `useHaptics()` hands to components, and the kit passes it on ungated. It is `undefined` where there is no motor, and it checks the device's own switch (`glyph-haptics`) itself.

`installTapHaptics` puts the tap tick back on pointerup, where a tap can be told from a drag: at most 10px of travel and at most 700 ms held, on something tappable, and never with a mouse. The editor's haptics go through a 28 ms floor (`fireFelt`), so typing never floods the motor.

## Read next

- [[The native half]]
- [[Over the air, and releases]]
- [[The editor and its language]]
