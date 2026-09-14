# Glyph

A mobile-first markdown notes app built on Glacier UI. Three things make it Glyph rather than
another notes app: the markdown renders as you type **without the syntax ever disappearing**, the
phone answers under your thumb as each style lands, and a long-press of the side key captures a
spoken note that is transcribed on the device, with the app closed.

This document is the implementation contract. It was written from the research notes in
`docs/research/` (read those for the evidence behind every claim here; they cite AOSP source,
package sources, and measurements taken on this Mac on 2026-09-11).

---

## 1. Goals and non-goals

**Goals, in the order they break ties**

1. **Typing feels native.** Input latency on a phone is the product. A note of 50,000 words must
   type as smoothly as an empty one.
2. **Tokens stay on screen.** `**bold**` renders bold *with the asterisks still there*, dimmed. A
   heading is bigger *and* still shows its `#`. Nothing is ever hidden, replaced, or folded, so the
   document you edit is exactly the document you see. This is the iA Writer / Bear 1 school, not
   the Obsidian live-preview school, and it is deliberately the simpler of the two.
3. **The phone answers.** A tick when an inline mark closes, a weightier tap when a heading is
   born, a success note on save. Rate-limited so a fast typist never gets mush.
4. **Voice capture from a hardware button**, working with the app closed and with no network.
5. **A simple UI.** A list, an editor, a settings sheet. Glacier components and tokens only.

**Non-goals for v1**

Sync, sharing, attachments, tags, folders, backlinks, search across notes, a preview mode, tables
UI, collaborative editing, a desktop-first layout. The desktop build exists only so the app can be
developed and tested in a window; it is not a product yet.

---

## 2. Stack

Already standing in this repo and verified to build (`npm run build`, `cargo check`, an iOS
simulator bundle, and an arm64 Android APK all pass as of 2026-09-11):

| Layer | Choice |
| --- | --- |
| UI kit | Glacier, vendored at `vendor/@glacier/{react,tokens,icons}` via `file:` deps |
| Frontend | Vite 7, React 19, TypeScript 5.9, CSS Modules over `--glacier-*` tokens |
| Shell | Tauri v2, `com.mattssoftware.glyph`, iOS 15+ and Android (minSdk 24, target 36) |
| Editor engine | CodeMirror 6 |
| Store | Rust: SQLite via `rusqlite` (bundled), WAL |
| Haptics | `@tauri-apps/plugin-haptics` behind Glacier's `HapticsProvider` |
| Transcription | `whisper-rs` (whisper.cpp) on device; cloud opt-in |

Two inherited fixes are already carried from AttackFM and must not be dropped: the vendored
`tao` 0.35.3 with the `autorelease_ptr` backport (without it release iOS builds segfault at launch
on iOS 26/27), and `ensure_key_window` in `src-tauri/src/lib.rs` (without it the iOS keyboard never
rises, which for a notes app is the whole app not working).

---

## 3. The editor core

### 3.1 Why CodeMirror 6

The requirement "the tokens stay visible" decides this on its own. CodeMirror's document **is** the
markdown string; decorations style ranges of that string without changing it. Every rich-text
engine works the other way round: Lexical's `registerMarkdownShortcuts` explicitly clears the
opening and closing tags, and Tiptap's input rules turn `**x**` into a bold mark with the asterisks
consumed. Keeping tokens on those engines means fighting the model in every keystroke.

The others fail on other grounds too. Monaco's own FAQ answers "Is the editor supported in mobile
browsers or mobile web app frameworks?" with "No", and it weighs 1,153 kB gzipped before workers.
A transparent-textarea overlay (what Glacier's own `RichTextEditor` does) only stays aligned
because it is monospace at one size: proportional prose with bold runs and larger headings
desynchronises the caret from the glyphs, so requirement 2 kills it outright. That is not a
criticism of the kit's editor, which is a chat composer and right for that job.

Measured cost of CodeMirror, gzipped: 65 kB for state+view, 174.5 kB for the whole markdown stack.
About 55–60 kB of that is the `lang-html` chain that `@codemirror/lang-markdown` hard-depends on.
**Decision: accept it for v1.** AttackFM's shipped bundle is ~8.8 MB; 175 kB is not the constraint,
parse and layout are, and the chain buys correct highlighting for HTML inside a note. Revisit only
if a cold-start measurement on the Fold says otherwise.

Performance, measured on a 380 kB / 55,817-word note: full parse 27–32 ms, reparse after an
edit 1.1 ms. The view renders only the viewport; the parser works in idle slices and yields when
`navigator.scheduling.isInputPending()` says a keystroke is waiting.

### 3.2 How tokens stay visible

Two layers, and between them they are the entire renderer. There is no widget machinery, no
replacement decorations, no reveal-on-cursor logic — all of which exist in Obsidian-style
implementations *because* they hide the markers. Glyph never hides them, so it needs none of it.

**Inline — one `HighlightStyle`, no plugin code.** Lezer's markdown grammar already tags every
marker (`#`, `**`, `>`, `` ` ``, `-`, `[`, `]`) as `processingInstruction`, and emits one span per
run carrying the union of its tags. So `**` gets `strong` *and* `processingInstruction` while the
word between gets only `strong`. One rule styles the content, one rule dims every marker:

```ts
export const glyphHighlight = HighlightStyle.define([
  { tag: tags.heading1, class: styles.h1 },
  // ...heading2..6, strong, emphasis, strikethrough, monospace, link, url, quote, list...
  { tag: tags.processingInstruction, class: styles.mark }, // MUST be last: same specificity wins by order
]);
```

`.mark` sets `color: var(--glacier-text-subtle)` and `font-weight: var(--glacier-font-weight-regular)`
and nothing else. It must never change size, because a marker that changes the line's metrics as it
is typed makes the text jump under the thumb. Never `opacity` (it dims the background through the
glass) and never `--glacier-text-disabled` (it fails AA contrast).

**Block — one small `ViewPlugin` with `Decoration.line`.** Padding above a heading, the quote bar,
the list hanging indent, and the fenced-code background need the line element, which an inline span
cannot reach. The plugin walks `syntaxTree` over `view.visibleRanges` only, maps a node name to a
line class, and builds a `RangeSetBuilder` of zero-length line decorations. See
`docs/research/codemirror.md` §6b for the exact code, including the two rules that bite: line
decoration ranges must be zero-length and sit at `line.from`, and `RangeSetBuilder.add` must be
called in sorted order.

Under an active IME composition the plugin maps its existing decoration set through the changes
instead of rebuilding (`this.decorations.map(u.changes)`). Decoration churn mid-composition is the
classic mobile bug class — four separate CodeMirror issues, all Android or iOS.

### 3.3 Type scale

Body is `--glacier-font-size-md` in `--glacier-font-sans`. Headings step **one below the kit's
heading map**, because the kit's H1 is `3xl`, which is 44 px on a phone and turns a note into a
poster:

| | H1 | H2 | H3 | H4 | H5 | H6 |
| --- | --- | --- | --- | --- | --- | --- |
| size | `2xl` | `xl` | `lg` | `md` | `md` | `sm` |
| weight | bold | semibold | semibold | semibold | semibold | semibold |

Each takes its matching `--glacier-leading-*` and `--glacier-tracking-*` step. H6 also takes
`--glacier-text-subtle`; it does **not** take the kit's `text-transform: uppercase`, because typed
characters have to read as typed. Variable line heights are supported — the view keeps a height
map, estimated first and measured when drawn.

Full token assignments for every element (inline code, fenced code, quote bar, list markers, links,
selection, caret, placeholder) are tabulated in `docs/research/tokens.md` §7, and the list of
plausible-sounding tokens that **do not exist** is in §8. Do not invent one; there is no
`--glacier-caret`, no `--glacier-link`, no `--glacier-code-bg`.

### 3.4 Theming

`EditorView.theme(spec, {dark})` scopes its rules under a generated class, and style-mod writes
values verbatim — so `var(--glacier-surface)` passes straight through and Glacier's `data-theme`
flip on `<html>` retunes the editor with no rebuild. The `dark` flag still goes through a
`Compartment` and is reconfigured on theme change, so CodeMirror's own `&dark` base rules agree
with the rest of the app.

### 3.5 Mobile input

CodeMirror defaults `.cm-content` to `spellcheck: false`, `autocorrect: off`,
`autocapitalize: off`, `writingsuggestions: false` — correct for code, wrong for prose. Glyph
overrides all four through `EditorView.contentAttributes`:

```ts
{ autocorrect: 'on', autocapitalize: 'sentences', spellcheck: 'true', inputmode: 'text', enterkeyhint: 'enter' }
```

with a Settings switch to turn them off, because autocorrect and markdown syntax do occasionally
argue.

**Do not install `drawSelection()`.** It hides the native caret, which on Mobile Safari also hides
the native grab handles, the magnifier, and the callout — and it costs an extra DOM layout cycle
per update. Keeping the native selection gives all of that back for free; the colour comes from
`caret-color` and `::selection` in the theme. (CodeMirror ships
`drawSelection({iosSelectionHandles: true})` to redraw what it broke; the better move is not to
break it.)

`markdown()` is configured `{ base: markdownLanguage, addKeymap: true, completeHTMLTags: false,
pasteURLAsLink: true }`. `base: markdownLanguage` is GFM (the default `commonmarkLanguage` has no
`~~` and no task lists). `addKeymap` gives Enter → `insertNewlineContinueMarkup`, which continues a
list for you and is the single most useful phone behaviour in the package.
`completeHTMLTags: false` stops a `<` from raising an autocomplete popup over a phone keyboard.

**Budgets.** Keystroke to paint under 16 ms on the Fold at 5,000 words; note open to first paint
under 150 ms; no frame over 50 ms while scrolling a 50,000-word note. Measured with
`performance.now()` around the update listener and a Chrome DevTools trace over the Android
WebView, not by feel.

---

## 4. Haptics

The kit's web haptics never reach WKWebView; the motor is the Tauri plugin. Glyph mounts
`<HapticsProvider enabled={false} impl={hapticsImpl}>` exactly as AttackFM does — `enabled={false}`
switches off the kit's delegated `pointerdown` tick, which fires at the start of a scroll flick and
buzzes all the way down a list — and installs its own tap tick on `pointerup` with a 10 px slop and
a 700 ms ceiling.

`src/app/ux/ratchet.ts` and the 28 ms floor in `fireFelt` are ported from AttackFM unchanged. The
Taptic Engine queues a flood and plays it back as mush; a floor is what keeps a fast typist from
feeling porridge.

| Event | Kind | How it is detected | Limit |
| --- | --- | --- | --- |
| Inline mark closed (`**`, `_`, `` ` ``, `~~`, `]`) | `selection` | Transaction inserted a closing character; the enclosing `StrongEmphasis`/`Emphasis`/`InlineCode`/`Strikethrough`/`Link` node exists in the new tree at the caret and did not in the old one | 28 ms floor |
| Heading created | `medium` | A new `ATXHeading1-6` line node where the old tree had none | 28 ms floor |
| Quote, list, rule, fence created | `light` | Same test against `Blockquote`, `ListItem`, `HorizontalRule`, `FencedCode` | 28 ms floor |
| List continued on Enter | micro tick (`impactFeedback('soft')`) | `insertNewlineContinueMarkup` inserted a marker | 28 ms floor |
| Task box toggled | `selection` | Tap handler on `TaskMarker` | per tap |
| Formatting bar press | `selection` | The bar's own transaction, annotated `input.format` | per tap |
| Note saved | `success` | Store write resolved | once per save |
| Capture started / stopped | `medium` / `success` | Capture state machine | once each |
| Ordinary characters | nothing | — | — |

The detection is a tree diff, not a regex, because a regex fires inside fenced code where no mark
was created. Transactions carrying `input.type.compose` are skipped entirely: mid-composition an
IME rewrites the same characters repeatedly, and every rewrite would buzz. The exact code is in
`docs/research/codemirror.md` §11.

---

## 5. The notes store

**The store is Rust-owned, and that is forced by the capture feature.** On Android the capture
overlay runs in a separate process with no webview alive; it must be able to write a note. So the
store cannot live in the page.

SQLite through `rusqlite` (bundled, so no system library), at `<app_data_dir>/glyph.sqlite` in WAL
mode with `busy_timeout` set, because two processes write it.

```sql
notes(id TEXT PRIMARY KEY, body TEXT NOT NULL, created_at INTEGER, updated_at INTEGER, source TEXT)
captures(id TEXT PRIMARY KEY, note_id TEXT, audio_path TEXT, model TEXT, duration_ms INTEGER, state TEXT)
```

The Rust module (`src-tauri/src/store.rs`) takes no `tauri::` types. That is the load-bearing
constraint: the same functions are called by the Tauri commands *and* by a JNI entry point from the
Android capture service, and the capture process never runs `tauri::Builder`. Commands exposed to
the page: `list_notes`, `get_note`, `save_note`, `delete_note`, `pending_captures`.

The page reaches it through one module, `src/app/core/store.ts`, which falls back to a
`localStorage` implementation of the same interface when `isTauri()` is false — so `npm run dev` in
a browser is a real working app, which is where most of the editor work will actually happen.

Saving is debounced 400 ms after the last keystroke and flushed on blur, on route change, and on
`visibilitychange`. A phone kills backgrounded webviews without warning; an unflushed draft is lost
work and lost trust.

---

## 6. Voice capture

### 6.1 Android: yes, and here is exactly how

The answer to "can I press and hold a hardware button to dictate a note": **yes**, by Glyph
becoming the device's digital assistant. That single role covers every trigger worth having — Pixel
long-press power, Samsung side key press-and-hold, corner-swipe, and home-button long-press all
route to the assistant role holder. Verified against AOSP `main`: `PhoneWindowManager.powerLongPress()`
case `LONG_PRESS_POWER_ASSISTANT` performs its own haptic and calls `launchAssistAction(...)`.

Two things to know before building it:

- **The role cannot be requested from code.** `roles.xml` marks `ASSISTANT` as
  `requestable="false"`, so `createRequestRoleIntent` shows nothing. Onboarding must open
  `Settings.ACTION_VOICE_INPUT_SETTINGS` and ask the user to pick Glyph, and read the result back
  with `RoleManager.isRoleHeld`.
- **It is exclusive.** Holding it means giving up Gemini or Bixby on that phone. That is a real
  cost and the onboarding must say so plainly, and must offer the Quick Settings tile and the
  `glyph://capture` shortcut to anyone who says no.

Volume-key long-press in the background is **not** feasible without an `AccessibilityService`,
which Play restricts. Dropped.

The shape, in `src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/capture/`, hand
written and tracked in git the way AttackFM tracks its Kotlin (a plugin crate buys nothing here and
costs a build):

1. `GlyphInteractionService` — the `VoiceInteractionService`. The system keeps it bound and alive.
2. `GlyphSession` / `GlyphSessionService` — the overlay. Its window is `TYPE_VOICE_INTERACTION`,
   window layer 21, which AOSP comments as "above the lock screen", so capture works on a locked
   phone. `onShow` starts `AudioRecord` at 16 kHz mono PCM16 and reads `invocation_type` from the
   args so the note can record that it came from the side key.
3. `GlyphRecognitionService` — a stub that returns `ERROR_RECOGNIZER_BUSY`. It exists only because
   the role check refuses a service whose metadata lacks `recognitionService`.

Stop (or a 90 s cap) writes a WAV to `<filesDir>/captures/`, starts a `shortService` foreground
service whose notification doubles as the progress indicator, and calls into Rust over JNI. The
generated `Rust.kt` already does `System.loadLibrary("app_lib")`, and `crate-type` already includes
`cdylib`, so a `#[no_mangle] extern "system"` function is reachable from the capture process with
no Tauri involvement. When the app is next resumed, `MainActivity.onResume` evaluates
`window.__glyph?.refresh()` and the page re-queries the store — no cross-process events needed.

### 6.2 Transcription

`whisper-rs` 0.16, model `ggml-base.en-q5_1.bin` (60 MB), downloaded on first run with a SHA-256
check, with `tiny.en-q5_1` (32 MB) bundled as the offline floor and the automatic choice on a
low-RAM device. Planning figures: base.en-q5_1 transcribes a 60 s note in roughly 10–20 s on a
2023+ flagship, tiny.en in 4–8 s. Large models OOM on phones; do not offer them.

**The build risk is the cross-compile, not the code.** `tauri android build` sets no
`CMAKE_TOOLCHAIN_FILE`, so ggml must be pointed at the NDK toolchain by hand through
`src-tauri/.cargo/config.toml`, bindgen needs the NDK sysroot, and the resulting `.so` will need
`libc++_shared.so` copied into `jniLibs`. This is milestone 1 for a reason: it is the only part of
the plan that might not work, and everything else is useful whether or not it does. Fallbacks, in
order: the `sherpa-onnx` crate, Android's on-device `SpeechRecognizer`, the OpenAI API as an opt-in
setting (~$0.006/min).

### 6.3 iOS

**iOS cannot record from the background at all** — Apple's own forum answer is that an app cannot
initiate an `AVAudioSession` recording from the background via an intent. So the iOS story is
foreground-first and honest about it: an App Shortcut (`CaptureNoteIntent`, reachable from the
Action button on iPhone 15 Pro and every 16/17, from Back Tap on anything since the 8, and from
Siri and Spotlight) foregrounds Glyph and starts recording on arrival. The target is under a second
from press to recording, which means starting `AVAudioEngine` in Swift before the webview paints.

On iOS the transcription default should probably be Apple's own `SpeechTranscriber` (iOS 26) rather
than whisper: it is free, on-device, and better. whisper-rs with the `metal` feature is the pre-26
path. That keeps whisper's build risk on one platform instead of two.

---

## 7. UI v1

Three screens, hand-composed rather than using the kit's `AppShell`, because `AppShell`, `Drawer`
and the toast viewport have no `env(safe-area-inset-*)` handling and no className hook to add it —
on a notched phone their content sits under the notch. Everything *inside* the layout is Glacier.

**Notes list.** A header (title, a settings `IconButton`, a new-note `IconButton`), then a scrolling
list of two-line rows: first line of the note as the title in `Text weight="medium"`, second line a
`--glacier-text-muted` preview, with a relative timestamp. A row is a `Card variant="wash"
interactive`. Swipe-to-delete is v1.1; long-press opens a `Menu` with Delete, which routes through
an `AlertDialog tone="danger"`. The floating capture button sits bottom-right above the safe area.

**Editor.** Full-bleed CodeMirror under a slim header carrying back, a title that is just the first
line, and an overflow `Menu`. A formatting bar docks above the keyboard — bold, italic, code,
heading, quote, bullet, link — implemented as CodeMirror transactions annotated
`input.format`, using the same delimiters the kit uses (`**`, `_`, `` ` ``, `~~`) so what the bar
writes is what the highlighter reads. Keyboard avoidance rides `visualViewport`, which is the only
thing that reports the real keyboard inset in a WebView.

**Settings.** A bottom `Drawer` with theme, accent, density, font, haptics on/off, autocorrect
on/off, transcription model, and the capture-role onboarding card. Preferences persist to
`localStorage` and stamp `data-*` attributes on `<html>` exactly as AttackFM's `appearance.tsx`
does: an attribute is *removed* when its value is the default, so the token `:root` defaults win.

---

## 8. File layout

```
src/
  main.tsx                    fonts.css -> tokens.css -> @glacier/react/styles.css -> app.css
  app/
    App.tsx                   route switch (list | editor | settings), no router library
    app.css                   phone shell, --app-safe-*, keyboard inset
    core/
      platform.ts             isTauri, isIOS, isAndroid, isMobile
      haptics.ts              fireNativeHaptic, fireFelt, fireMicroTick, hapticsImpl, pref
      store.ts                notes API; Tauri commands, localStorage fallback
      preferences.ts          theme/accent/density/font/haptics/autocorrect + applyPreferences
    ux/
      ratchet.ts              ported from AttackFM, with its test
    editor/
      Editor.tsx              the CodeMirror host component
      Editor.module.css       every token rule from tokens.md §7
      glyphHighlight.ts       the inline HighlightStyle
      glyphLines.ts           the block ViewPlugin
      glyphTheme.ts           EditorView.theme over --glacier-* + the dark Compartment
      feel.ts                 transaction -> haptic
      format.ts               the formatting bar's commands
    notes/
      NotesList.tsx, NoteRow.tsx
    settings/
      SettingsSheet.tsx
src-tauri/src/
  lib.rs                      builder, ensure_key_window, command registration
  store.rs                    SQLite; NO tauri types
  capture.rs                  JNI entry points; whisper
```

---

## 9. Dependencies to add

npm: `@codemirror/state` 6.7.4, `@codemirror/view` 6.43.11, `@codemirror/language` 6.12.4,
`@codemirror/commands` 6.11.0, `@codemirror/lang-markdown` 6.5.2 (pulls `@lezer/*`).

cargo: `rusqlite` (feature `bundled`), `serde`/`serde_json` (already there), later `whisper-rs`
0.16 and `jni`.

---

## 10. Build plan

Each milestone ends with a build pushed to the Fold (`npm run push:fold`) and a specific thing to
check by hand on the phone.

| # | Milestone | Acceptance check on the Fold |
| --- | --- | --- |
| 1 | **whisper-rs Android spike.** Get `whisper-rs` cross-compiling for `aarch64-linux-android` and transcribe one bundled WAV through a temporary Tauri command. Nothing else depends on it, and everything else is wasted if it is impossible. | A test button returns transcribed text, with a timing log |
| 2 | **Store + shell.** SQLite store, Tauri commands, the localStorage fallback, the notes list, create/open/delete. Plain `<textarea>` editor. | Notes survive force-quit; list is correct |
| 3 | **Editor core.** CodeMirror with `glyphHighlight`, `glyphLines`, `glyphTheme`, prose content attributes, native selection. | `**bold**` shows bold with visible dimmed asterisks; headings grow; selection handles and the magnifier work; typing is smooth in a long note |
| 4 | **Haptics.** The bridge, the ratchet, `feel.ts`, the Settings switch. | A tick as `**` closes, a heavier tap on a new heading, nothing while scrolling, no mush when typing fast |
| 5 | **Formatting bar + settings sheet.** Keyboard-docked bar, full appearance settings. | Bar tracks the keyboard exactly; theme and density flip the editor live |
| 6 | **Android capture.** The three Kotlin services, the role onboarding, the overlay, the JNI write, `refresh()` on resume. | Long-press the side key with Glyph closed, speak, and find the note in the list |
| 7 | **iOS capture.** `CaptureNoteIntent`, Action button / Back Tap, `SpeechTranscriber` with whisper fallback. | Back Tap starts recording in under a second |

---

## 11. Risks

1. **whisper-rs will not cross-compile for Android** (cmake toolchain, bindgen sysroot,
   `libc++_shared.so`, periodic ggml aarch64 breakage). *Mitigation:* milestone 1; then
   `sherpa-onnx`, then `SpeechRecognizer`, then cloud.
2. **Users must give up Gemini to give Glyph the side key**, and the role cannot be requested in
   code. *Mitigation:* honest onboarding; tile and shortcut paths for those who decline.
3. **CJK IME on iOS** is the live CodeMirror bug area (issue 1748, Korean input, 2026-09).
   *Mitigation:* skip decoration rebuilds while `view.composing`; add a Korean/Japanese keyboard
   pass to device testing.
4. **Two processes writing SQLite.** *Mitigation:* WAL, `busy_timeout`, short transactions,
   `refresh()` on resume.
5. **Play review of `FOREGROUND_SERVICE_MICROPHONE`** needs a declaration and a demo video.
   *Mitigation:* record only while the overlay is up unless the user backgrounds mid-capture;
   prominent disclosure before the `RECORD_AUDIO` prompt.
6. **Lock-screen behaviour differs by OEM.** *Mitigation:* test Pixel and Galaxy;
   `supportsLaunchVoiceAssistFromKeyguard="true"`; never rely on an `ACTION_ASSIST` activity for
   locked capture.
7. **The manifest is regenerated.** The deep-link plugin rewrites its own region on every build.
   *Mitigation:* keep the capture entries outside it, tracked in git, and commented.

---

## 12. Open questions for Matt

None of these block milestones 1–4; each has a default already chosen so work does not stop.

1. **Editor face.** Sans at `md` (chosen — the iA/Bear feel) or the kit's mono at `sm`?
2. **Heading sizes.** One step below the kit map (chosen) or the kit map, with a 44 px H1?
3. **Caret colour.** Accent (chosen — matches the platform tint) or `--glacier-text` (kit precedent)?
4. **Backspace after `- `.** `addKeymap: true` gives `deleteMarkupBackward`, which removes the
   whole list marker in one press. Useful, but invisible to a phone user until it happens. Keep it
   (chosen) or bind plain Backspace?
5. **Is giving up Gemini acceptable to you personally** on the Fold, or should the tile and
   shortcut be the primary path with the assistant role as an opt-in?

---

## 13. Capture, as built (2026-09-12)

Matt chose **press-and-hold of the side key**, replacing Gemini as the digital assistant.
Three decisions changed from sections 6 and 7 above once the device and the server were
inspected, and they are recorded here rather than silently edited in.

**The side key opens the app, not an overlay.** Section 6.1 planned a native overlay drawn
by the voice interaction session. The note has to render as live markdown while it is
spoken, and the only markdown renderer in the app is the CodeMirror editor in the webview,
so a native overlay would have meant a second renderer that drifts from the first. Instead
`GlyphSession.onShow` launches `MainActivity` with `ACTION_CAPTURE` and hides itself. The
activity grants itself `showWhenLocked` for that one capture and withdraws it when the
capture ends; a capture finished on a locked phone steps back behind the lock screen
instead of opening the note. `startActivity`, not `startAssistantActivity`: the latter uses
the assistant activity type, which would put a second `singleTask` Tauri activity, and a
second Rust runtime, in a separate task.

**Audio is captured in the page.** `getUserMedia` into an `AudioWorklet` at 16 kHz, streamed
to Rust as raw `f32` bytes over Tauri IPC. This is the path AttackFM's Booth already proves
on the same phone, and the generated `RustWebChromeClient` already turns the page's request
into Android's microphone prompt. Samples captured before the model has loaded are held and
replayed, so the first words are never lost to warm-up.

> **Removed in 0.6.0.** The server pass below is gone: capture formats with the spoken cues and the
> local rules in `markdown.ts` only, and the page no longer calls `/glyph/api/format`. glyph-api
> still runs on the box, unused. Kept as the record of what was built.

**Formatting is annotation, on attack.fm, by Ollama.** The box runs Ollama with local models
and no GPU, so a model rewriting a whole note would take tens of seconds. The model instead
returns a title, phrases to bold, to-dos, enumerations and section breaks, each an exact
substring of the transcript; the server drops anything that is not verbatim, the phone
checks again, and `src/app/capture/markdown.ts` applies them. The model therefore cannot
change a word Matt said. Local rules format the note while he speaks, and annotations take
over for the text they covered, by offset, so speech after the last request is never left
unformatted while it waits.

| Piece | Where |
| --- | --- |
| Assistant hook | `src-tauri/gen/android/.../capture/*.kt`, `MainActivity.kt`, `AndroidManifest.xml`, `res/xml/glyph_*.xml` |
| Streaming Whisper | `src-tauri/src/whisper/`, `src-tauri/src/capture_commands.rs` |
| Microphone | `src/app/capture/audio.ts` |
| Engine interface | `src/app/capture/engine.ts` (Whisper, browser, simulated) |
| Speech to markdown | `src/app/capture/markdown.ts` |
| Annotation client | `src/app/capture/annotate.ts` |
| Screen | `src/app/capture/CaptureScreen.tsx` |
| Server | `server/`, `scripts/deploy-server.mjs`, `https://attack.fm/glyph/api/format` |
| Model files | `https://attack.fm/glyph/models/` |

Develop the capture screen without a phone at `http://localhost:5250/?capture&simulate`.

The one setting Glyph cannot change for itself: Settings > Apps > Default apps > Digital
assistant app > Glyph. Android marks the assistant role as not requestable by apps.

---

## 14. Typography first, and updates over the air (2026-09-12)

Matt asked for a UI driven by large type with minimal chrome, and for the phone to update
without a cable. Both reverse earlier decisions, recorded here rather than silently edited.

**Type is the interface.** Section 3.3 held headings one step *below* the kit map so a note
would not read as a poster; the poster is now the point. The scale lives in `app.css` as
`--app-*` properties, each a kit step multiplied rather than a new number: the list title is
`5xl × 1.3`, a note's title in the list is `2xl`, editor body is `lg`, and H1–H6 run `4xl`
down to `md`, with leading and tracking tightening as size grows. A Text size setting
(Large / Larger / Largest) scales all of it, and a Typeface setting exposes the kit's three
sans families; Inter's optical-size axis is loaded so display sizes get the display cut.
Section 7's chrome goes: no cards, no header bars, no icon buttons. Actions are words
(Settings, Write, Speak, Notes, Delete, Discard, Save) and the formatting bar's keys are the
markdown characters themselves. The hairline between list rows is the only rule on screen and
the Speak dot the only colour.

**Updates over the air.** An installed Glyph runs either the frontend compiled into the APK or
a newer `dist/` it downloaded from `attack.fm/glyph/ota.json`, served through a custom `ota`
URI scheme. The scheme is the departure from AttackFM, which uses Tauri's `asset:` protocol and
so must inline every chunk and font into two fixed-name files: an `ota` URL keeps real paths,
so the OTA bundle is the ordinary Vite build and unchanged files (the fonts, mostly) are
reused rather than downloaded. The loader in `index.html` never removes a script tag; each copy
of `main.tsx` asks `__glyphBoot` whether it was chosen. A bundle that fails to load, throws
while starting, or does not mount in 8 s is quarantined and the embedded frontend mounts in the
same launch; one staked at launch and never reported mounted twice running is quarantined at
the next. Native changes ship as an APK the app downloads, verifies and hands to Android's
installer. The full contract is the header of `src-tauri/src/ota.rs`.

| Piece | Where |
| --- | --- |
| Type scale, word buttons | `src/app/app.css` |
| Text size, typeface | `src/app/core/preferences.ts`, `src/app/settings/SettingsSheet.tsx` |
| Scheme, boot wager, install, APK download | `src-tauri/src/ota.rs` |
| Loader | `index.html` |
| Mount handshake | `src/main.tsx` |
| Checks, reload, APK install | `src/app/core/ota.ts` |
| APK installer hand-off | `MainActivity.kt` (`GlyphHost.installApk`), `REQUEST_INSTALL_PACKAGES` |
| Manifest | `vite.config.ts` writes `dist/ota.json` |
| Publishing, install page | `scripts/deploy-ota.mjs`, `public/install.html` |
| Signing, keys, sources | `scripts/ota-sign.mjs`, `scripts/ota-keygen.mjs`, `src-tauri/ota-trusted-keys.txt`, `src-tauri/ota-sources.txt` |

**Signed, and not tied to a domain (0.3.0).** Before a public APK, the update path could not depend
on attack.fm staying Matt's: a lapsed domain would have let its next owner ship code into every
install. Manifests are now Ed25519-signed (native generation 2), verified with `ring` before a
parser sees a byte, and carry `sources` and `services` that the app remembers - so installs can
be moved to a new domain by a signed publish, and service endpoints (formatting, model mirrors)
move with them. Verified on the emulator: a tampered manifest is refused and nothing is
remembered; a signed one installs and records its sources; with the first server gone, the app
updates from a second server it learned of only through a signed manifest; and a signed apk.json
from that server offers the APK. README "Moving to another domain" is the procedure.

**0.3.2: swipes, alerts, and a theme to start with.** List rows swipe (`notes/SwipeRow.tsx`): right
to star, left to archive, further left to delete, each threshold a haptic detent that is also
shown (one word behind the row, red for delete) because a fast fling can cross two inside one motor
pulse. Stars and archiving are columns in SQLite (`starred`, `archived_at`, added by an idempotent
migration) and are not edits - they do not move `updated_at`. Delete is deferred behind an Undo
toast rather than done and re-saved, and is made final the moment the app is backgrounded, a
capture starts, or a second delete arrives. Update alerts are opt-in background notifications
(README "Update alerts"); the first-run guide now opens by asking light or dark, applied live.

---

## 15. On-device formatting and project context (2026-09-12) - removed in 0.6.0

> Removed at Matt's call: "summaries and suggestions" are out. Glyph is voice, live transcription,
> and markdown from the spoken cues. Gone with it: the on-device model and its download, the
> Raw | Formatted view, marked suggestions, projects, the project scanner on attack.fm, and the
> server annotation pass (section 13). Native generation 6 marks the removal; on first launch the app
> deletes the 1.28 GB model file if it was ever downloaded. Kept here for what was measured, because
> it is the answer to "why not just add an LLM" the next time it comes up.

What was built and shipped in 0.4.0 to 0.5.x: llama.cpp in the app, running Qwen3.5-2B Q4_K_M
(1.28 GB) on the phone's CPU, with a prefix snapshot so a repeated system prompt was not decoded
twice; a Raw | Formatted switch carrying CriticMarkup `{++ suggestions ++}`; and projects - public
git repositories read on attack.fm into ~1,500-token context packs kept on the phone.

What the measurements said, and still say:

- **Small models rewrite.** Asked to "keep every word, mark additions", all four 1-2B models tried
  (Qwen3.5 2B and 0.8B, LFM2.5 1.2B, Gemma-3 1B) reworded the note - dropped "I need to", invented
  labels, added chatty closers. Asked to quote sentences, they "tidied" the quotes. What worked was
  showing the note as numbered sentences and asking for indices under a GBNF grammar, then
  formatting with code, so the words could not change by construction.
- **Two ggml copies crash.** whisper-rs and llama-cpp-2 each bundle ggml under the same static
  library names; they link without complaint and fail at run time (SIGBUS on Qwen3.5's first
  decode). It took a vendored whisper-rs-sys built against llama's ggml. With llama gone, whisper is
  back on its own bundled ggml, exactly as through 0.3.2.
- **Grammar sampling is slow over a big vocabulary.** Checking the model's first choice against the
  grammar before filtering the whole vocabulary took Qwen3.5-2B from 29 to 44 tokens a second on four
  Apple-silicon cores.

## 16. Ink (2026-09-13)

Matt's direction: minimal, monochrome, and trivially inverted between light and dark. The references were black-and-white
phone screens: pure ink on paper, one black pill per screen, big grotesk type, grey surfaces, a selected row printed in
reverse, and a dot grid as the only texture.

Built at the token layer, in `src/app/ink.css`, imported after everything else:

- **One neutral scale**, `--app-gray-1` (paper) to `--app-gray-12` (ink), chroma zero, defined for paper and reversed for
  dark. Every Glacier semantic token and ramp is mapped onto it, accent and status colours included: danger is ink, and a
  state is said with a word or a shape. Kit components restyle without being touched. The one exception, at Matt's call:
  a swipe's Delete is red (`--glacier-red-9`, the kit ramp `ink.css` leaves unmapped), word and armed band alike.
- **Named tokens for app CSS**: `--app-paper`, `--app-paper-2`, `--app-paper-3`, `--app-rule`, `--app-ink` to
  `--app-ink-4`, `--app-wash` (a translucent ink tint for highlights), `--app-dots` / `--app-dots-size`.
- **`.app-inverse`** re-declares the whole mapping on the reversed scale, so any element - a chosen row, an armed
  swipe - prints in reverse, kit components inside it included. (An armed Archive is ink with paper words; an armed Delete
  is the red exception above.)
- **`.app-pill`** is the one loud button (Speak, Next, Scan); everything else stays an `.app-word`. **`.app-dots`** is the
  texture, used for empty space only: the guide's cover and the empty list.

The accent picker is gone: there is nothing left for it to choose. `preferences.accent` still loads from old storage and
is never applied. Two kit parts no token reaches are handled by structure rather than hashed class names: the segmented
control's selected label turns paper on its ink thumb, and the switch's literal `#fdfdfd` thumb takes the page's paper.

## 17. The tape (2026-09-13)

Matt asked for the press-and-hold capture screen to show a skeuomorphic tape spinning, the way
AttackFM shows its disc: hold it to pause, let go to carry on, and rewind to talk over what was
said, with the words being recorded over highlighted as it winds back.

**A tape in miniature** (`capture/Cassette.tsx`, physics in `capture/tape.ts`). Recording moves
tape from the left reel to the right one at a constant speed, so the right pack grows with the note
(area-conserving radii over a five-minute tape) and each reel turns at tape speed over its own
radius. Only the reels and pack radii are touched per frame, through refs; shell, label and glass are
static layers, as on the disc. The shell and label are printed in the ink tokens, so the tape reverses
with the theme; the wound tape, well and hubs keep literal values.

**The transport is the tape.**

- *Hold* pauses: the page stops handing samples to the engine, so the recording's timeline stands
  still (no silence is sent, so no false paragraph break), and the header counter - time recorded,
  not time passed - stops with it.
- *Turn the reels back* (clockwise, against the recording spin) to wind back: one slow turn of a
  half-full reel is ~2.5 s, spinning fast multiplies it up to ten times. A soft tick every second, a
  firmer one at every phrase start. The note washes out (`--app-wash`) from the first word that will
  not stand - found by rendering the note as it would stand and comparing, so titles and lists need
  no mapping - and scrolls to it. Winding forward gives the words back.
- *Let go* after winding: the phrases after the point are dropped at once and recording continues
  from there, over the top.

**Rewind in the engine** (`whisper/stream.rs`, `worker.rs`, `capture_rewind`, native generation 4).
The streamer now keeps the whole recording (16-bit, ~1.9 MB a minute) and each committed segment's
end sample. `rewind(to_ms)` drops whole segments that end after the point (whisper's word times are
not good enough to cut inside one), truncates the recording, rebuilds the window state at the last
kept segment's end with the VAD re-primed from the ~3 s before it, and re-feeds the audio up to the
point as uncommitted - so the start of the phrase is transcribed again with what is said next, and
new segments tile onto the kept ones. It emits an empty partial and `capture://rewound { toMs,
segments }` carrying every segment that still stands; the page replaces its list rather than counting,
so a segment lost to an aborted tick cannot leave the two sides disagreeing. An inference in flight is
cut short with the abort flag, which the worker clears when it takes the request, under the mailbox
lock; the request carries the audio pushed before it, so audio pushed after lands after the point.

On a generation-3 binary the tape still pauses; turning the reels does nothing. The browser engine
pauses too; the `?simulate` engine rewinds, which is how the screen is exercised without a phone.

## 18. The side key, continued (2026-09-13)

Matt: a held side key should record onto the same note if the last recording was a few minutes ago,
close everything else, and use an even barer recorder; and ideally stop when the key is released, or
at least when it is held again.

- **Continuing.** A side-key capture that starts within five minutes of the last capture ending adds
  to that note (`capture/continuation.ts`; the last capture is remembered in localStorage, since it is
  a fact about this device's last few minutes). The new words go below the note's text with a blank
  line; they take no `# title` of their own (`renderNote(…, { titled: false })`: a spoken "Title: …"
  there becomes a `## heading`). The note's text before the capture is read from the store once, when
  the first draft is written - after an editor that was open has flushed - and Discard puts it back
  exactly. "New note" is one tap away. Over the lock screen the continued note is not named.
- **Clearing the stage.** The side key closes the settings sheet, the walkthrough, an open note and
  the keyboard before the recorder mounts; the capture ends on the note (or the list, when locked).
- **The bare recorder** (`quick`, for captures from outside the app): no header, status or editor.
  A single small line says where the words are going (or what is wrong), the last words said fill the
  screen in display type (`capture/Tail.tsx`, bottom-aligned, fading out at the top, the guessed
  phrase lighter, rewound words washed), then the tape, Discard and Done. Tapping the top line shows
  the pipeline diagnostics, which also appear by themselves when Whisper has heard eight seconds and
  produced nothing.
- **Memo mode (0.5.10, fixed in 0.7.1).** With the setting on, every recording - the Speak button
  as much as the side key - goes onto the last spoken note until New note is tapped. Until 0.7.1 the
  lookup ran only for side-key captures, so a recording from the list made a new note.
- **Stopping.** Holding the side key again during a capture saves it. Letting go cannot: Android
  hands the assistant app the hold (`onLaunchVoiceAssistFromKeyguard` / `ACTION_ASSIST`) and never the
  release - the side key is the power key, and its events are not delivered to apps.
- **Icon.** First the tape zoomed in until the window and reels filled the square; from 0.6.2, at
  Matt's ask, its top-left corner instead (`design/app-icon.svg`): the rounded shell corner with its
  screw, the label's corner with the A mark and the start of the title, and the left reel, on paper.
  The adaptive foreground (`design/app-icon-foreground.svg`) shifts the corner in a little so a round
  launcher mask keeps it. From 0.8.0 the bullet instead, Matt's pick from the four simpler prompts: a
  solid dot and a short rounded bar on paper, a markdown bullet that is also a reel with tape running
  off it. Redrawn as exact shapes (circle r 124, bar 296 by 96, 30 apart, centred on 1024); the
  foreground is the same mark at two thirds.

## 19. Writing by hand (2026-09-13) - removed in 0.5.2

> Removed the same day at Matt's call ("too much"): the page, the Write entry and the Android
> recognizer (with its 11 MB of native code) are gone. Kept here as the record of what was tried and
> measured. Native generation 5 stays taken.

Matt: write with a finger or a pen on a full-screen page, in the bottom part of the screen, and have
the ink fade away - on the dot pattern.

- **The page** (`ink/InkScreen.tsx`): dotted paper edge to edge (`.app-dots`). The note's words sit
  at the top in display type, bottom-aligned, fading out at the top, with a caret. The bottom of the
  screen - 42% by default, dragged anywhere from 25% to 72% by the grip on its top rule, remembered -
  is the writing band. Opened from a note's header ("Write by hand"); Done reads any ink still on
  the band before closing, and the editor opens on the result.
- **The rhythm.** Write a word or a few; 650 ms after the pen lifts, the ink is read, the words land in
  the note (spaced, washed for a moment), and the ink is lifted into its own canvas that fades out
  over 700 ms, so the band is clean paper again while the next word is already being written. Up to
  three other readings sit above the band as chips; one tap swaps them in. Two keys: new line, and
  take back the last word. Once a pen has touched the band, finger touches there are ignored (a
  resting palm is not writing).
- **Recognition on the phone** (`ink/recognizer.ts`, `ink/InkRecognition.kt`, native generation 5):
  ML Kit digital ink (pinned to 18.1.0 - 19.x carries Kotlin 2.1 metadata this project's Kotlin 1.9
  cannot read). Each piece of ink is sent with the band's size and the last 20 characters of the line
  as pre-context. A language's model (~20 MB) is downloaded from Google's model servers the first
  time the pen is used, then it works offline. Adds ~11 MB of arm64 native code to the APK; no
  libc++ of its own, so no clash with whisper and llama's. The page feature-detects the bridge
  methods, so the pen appears only on binaries that have them; the dev server has a mock.
- **The ink is not the note.** Nothing drawn is stored; handwriting is a way of typing.

## 20. Three ways in, and the tape as an intro (2026-09-13)

Matt: Glyph is used by talking and by typing (handwriting too, briefly - see §19), and the tape,
however good it looks, takes space the words should have.

- **The home dock**: Type as a quiet word on the left, Speak as the screen's one ink pill on the right.
  (A Write entry for handwriting sat between them in 0.5.1 and went with handwriting in 0.5.2.)
- **The tape is an intro.** Both recorders open with it - proof the microphone is live before a word
  has been understood - and once four words are on screen it folds away (its drawer's row animates
  to nothing while the tape shrinks toward the bottom), leaving the words the whole screen. What is
  left is a chip of two small turning reels and the counter, between Discard and Done. A tap on the
  chip brings the tape back to pause or wind back; it folds away again four seconds after it was
  last touched, and never while it is held or winding.

## 21. The reset (2026-09-13)

Matt paused mid-deploy and reset the scope: keep voice → live transcription → markdown by the spoken
cues the guide teaches; remove "summaries and suggestions" (the on-device model, the Formatted
view, projects, the scanner, the server annotate pass) and handwriting; go barebones and hone the
core; a zen, monochrome, developer-feel UI with abstract black-and-white shapes for pictures. He
answered fifteen questions to pin it down, and asked for one over-the-air update per stage.

**Decisions, in his words where they were his:** local cues only, all of the current set; the tape
"is a great UI element, it just gets in the way of the actual recordings" - so it leaves the recorder
and becomes the way to browse spoken notes (a shelf), with the audio kept and playable; one minimal
recorder for the Speak button and the side key; live words as "markdown taking shape"; Done goes
back to the list; list rows are title and time; the format bar goes; star/archive/delete swipes
stay; Settings keeps Type, Theme, Feel, Updates and About, reworked into one calm page; bold
grotesk; pictures are abstract shapes ("no ink inspiration, they're both black and white markdown
notes"), on empty states, guide pages, and the recorder's opening and save.

**Stages shipped:**
- 0.5.2 (OTA): the strip-out; the recorder (`capture/CaptureScreen.tsx`, `Tail.tsx` with
  `tail.ts` marking `#`, `-`, `- [ ]`, `**` dimmed as they land, `Opening.tsx` for the arcs and the
  saved bar); Editor without pending/rewind/suggestion decorations; format bar gone; list rows
  title + time; dock Write · Speak; Settings page (glyph-2a).
- 0.5.3 (APK, native generation 6): the model and its engine gone from the binary (whisper back on
  its bundled ggml; the 1.28 GB model file deleted once at startup if present); recordings kept:
  `capture_stop({ recordAs, append })` writes 16 kHz PCM WAV to `<app_data>/recordings/<id>.wav`
  (appending for a continued note), `set_note_recording` stores `recordingMs` and the segments,
  `delete_note` removes the file, `rec://` serves it with byte ranges; the Tapes shelf
  (`tapes/TapesScreen.tsx`, `TapeArt.tsx`), a "Tapes" word beside Settings.
- 0.5.4 (OTA): the tape player (`tapes/TapePlayer.tsx`): a tape tapped on the shelf comes forward
  with Play under it, the phrases as spoken with the one being heard in ink, a tap on a phrase
  seeking there, the reels turning; the audio comes from `rec://<id>.wav`. A browser has a clock in
  place of the audio.
- 0.5.5 (OTA): the pictures (`art/Shapes.tsx`): nine abstract shapes on currentColor, square, sized
  and dimmed by the page - Blank on the empty list, EmptyArchive, EmptyShelf, and one per guide page.
  The recorder's Opening and Saved live with it in `capture/Opening.tsx` because they animate.
  Matt was given twelve image-generation prompts for the same set, should he want drawn versions.
- 0.5.6 (OTA): the live note lays itself out as it is said (`capture/tail.ts` reads each line's
  kind off its mark; `Tail.tsx` sets headings larger, hangs to-dos and bullets off a dimmed gutter,
  keeps `**` dimmed inline); and the copy pass in Matt's voice across the app - no dashes, no
  semicolons, no ellipses, short direct sentences, full stops (glyph-2a did guide/, notes/,
  settings/; stale tips about the tape and "Fix it after" were rewritten).
- 0.5.7 (OTA): Delete is red, the one hue in the app (the kit's `--glacier-red-9`, themed).
- 0.5.8 (OTA): a left swipe reads Archive, then a red cross for delete: every action of a side is
  shown in the order the swipe reaches it (`SwipeRow.tsx`), the armed one full, the ones passed
  dimmed; the armed delete band is red with the cross in white.
- 0.5.9 (OTA): an armed Archive is a band of ink with the word in paper, so the left swipe reads as
  two squares, white then red on a dark page.

The native rewind (`capture_rewind`, `Streamer::rewind`) stays in the binary, tested and unused by
the page, in case re-recording over a phrase comes back in another form.

## 22. Better words after the recording (2026-09-13)

Matt: "The voice to text model isn't very good. Find a better version we can use if possible, maybe a
bit slower and more phone usage."

glyph-2a measured six models on 73 read-speech clips (clean, and with pink noise plus a 300 Hz
high-pass as a phone-mic stand-in), through the exact commit call, on the Mac and on the arm64
emulator path (no BLAS, the closest thing to the Fold). The live model, base.en-q5_1, makes 10-11%
word errors and streams at 0.85x real time on the phone path; small.en-q5_1 makes 5-7% but streams at
0.21x, so it cannot keep up live, and using it only for commits would queue every phrase behind
speech. large-v3-turbo makes 3-4% at 0.04x: a minute of CPU per minute of speech and a 574 MB
download, the quality ceiling for later. distil-small.en was worse than base here.

So the better model runs AFTERWARDS. base.en stays live, untouched. When a recording is saved
(0.5.3 keeps every one), a job goes on a queue (`capture/refine.ts`, localStorage, one at a time,
never while the recorder is on screen, resumed on launch), and the phone runs small.en-q5_1 over that
take's range of the WAV in the background (`capture_refine`, native generation 7): about 12 s of
four-core CPU per minute of speech on the Fold, the 190 MB model downloaded on first use and loaded
only for the pass. The note's words are replaced with the better transcript - rendered by the same
cue rules, the first take titled, a later one not - only if the note still reads exactly as Done
saved it; the recording's phrases are replaced either way, for the player. The row says "Improving"
while it waits; a switch under Recording turns it off.

Shipped as 0.6.0 (APK, native generation 7) on 2026-09-13. The first real pass runs on Matt's phone:
the emulator's microphone is silent, so no recording could be made there to refine.

## 23. No setext headings (2026-09-13)

Matt: "The formatting is off, it is making the next line a heading and there is no way to stop
typing in headings." His screenshot had a lone `-` under an address line, and in CommonMark a line
of dashes under a paragraph makes the paragraph a setext heading. So typing `-` to start a list
promoted the line above, and the big type looked like a mode nobody could leave. The editor's parser
(`editor/language.ts`) now removes `SetextHeading`: `#` is the only way to a heading, a lone `-` is
an empty list item, `---` is a rule. Tested on the syntax tree. Shipped as 0.6.1.

## 24. Pictures in notes (2026-09-13)

Matt: "add support for inline images".

A note refers to a picture as `![caption](image/<name>)`, a relative path, so a folder of notes and
an `image/` folder beside it would still read anywhere markdown is read. **Photo**, beside Delete in
a note's header, opens the phone's picture picker (`GlyphHost.pickImage`, MainActivity.kt); the
activity decodes the pick at a sane sample size, turns it the right way up from EXIF, caps the long
side at 1600 px and writes a JPEG at 85 into cacheDir/picked/; Rust files it under
`<app_data_dir>/images/<uuid>.jpg` (`save_image`, which accepts only that cache folder) and the `img`
scheme serves it; `delete_note` removes the pictures a note refers to. Native generation 8.

In the editor (`editor/images.ts`) the line keeps its markdown, dimmed and editable, and the picture
is a block widget under it: nothing is hidden, the caret behaves as on any line, deleting the line
removes the picture. A note that opens with a picture is titled by the first line of words under it.
In a browser the picture lives in IndexedDB and reaches the editor as a blob URL, so the screen can be
built and judged without a phone. Shipped as 0.7.0 (APK).

## 25. Animated pictures (2026-09-13, 0.8.1)

Matt: no generated art after all. "For the rest we're just going to use animated SVG icons", with a
new picture for the empty notes list still to come from him.

- **What moves.** Each picture in `art/Shapes.tsx` does the thing it stands for: the archive's last
  line dissolves into dots and comes back, the shelf's two reels turn (the small one faster), the
  welcome bullet lands and its line writes out (the same mark as the app icon), the theme square
  turns over so ink and paper change places, the side key goes in and sound leaves it, the markdown
  lines write themselves in and the box ticks, the tips lid lifts and settles. The recorder's two
  already moved.
- **How.** CSS keyframes in `Shapes.module.css`, on transforms, opacity and dash offsets only, so
  nothing lays out again. Loops of four to six seconds with long rests, so a page is calm most of
  the time. Reduced motion stops them in the pose the markup draws, which is the finished one.
- **Holes are holes.** A reel's hub and the paper dot in the theme's ink half are cut with even-odd
  paths rather than painted in the page colour, so they stay see-through on any background.
- **Still.** Blank, the empty notes list, until Matt's picture arrives.

## 26. A simpler home, and the tape inside the note (2026-09-13, 0.8.2)

Matt: the top bar ("2 notes", Tapes, Settings) had to go. He first asked for a sidebar on a swipe
left, then, since a swipe left on a note already archives it, chose instead: "add a settings cog
button next to the speak button and tapes should be removed, show the tape at the top of each note
and allow playing back the tape within the recording and on the raw mode show transcriptions on the
notes in real time".

- **Home.** Nothing above the Notes title; it keeps the top line's space so it doesn't crowd the
  status bar. The dock is Write on the left, then a cog in a ring the height of the Speak pill, then
  Speak. Next, at Matt's ask, Write became a + in the same ring on the left. With the cog pushed to the
  far right after Speak the row read as illogical (Speak crowded against Settings), so the dock is
  now three places, each with one job: + on the left, Speak centred as the one ink pill, the cog on
  the right (a `1fr auto 1fr` grid). Either thumb reaches Speak, and the two rings balance. The +
  gives a quarter turn when pressed. Ships with 0.9.0. The cog turns a tooth when pressed (`art/Icons.tsx` `Cog`, drawn from its radii). The
  Archive keeps its link at the foot of the list and its own back word.
- **No shelf.** `TapesScreen` and the shelf's picture are gone, and so is the old `TapePlayer`.
- **The tape in the note** (`tapes/NoteTape.tsx`, `tapes/useTape.ts`). A note with a recording has
  a small cassette at the top, with the time, a Play pill, and two words: Note and Transcript. Tapping the
  cassette plays or pauses too, and its reels turn and the tape winds across, so the picture is the
  progress bar. Leaving the note stops the tape.
- **Transcript.** The recording's own phrases, as spoken, in the note's place: the one being heard in ink,
  the ones heard in grey, the ones to come lighter, kept in view while it plays. Tapping a phrase
  takes the tape there. The editor stays mounted underneath, hidden, so nothing typed is lost, and
  measures itself again when Note comes back.
- **Next to it.** The on-device formatter is coming back with a Raw | Formatted toggle;
  that folds into this one control rather than adding a second. Matt's "raw mode" is that
  unformatted note, so the recording's view is called Transcript, not Raw.

## 27. The formatter, on the phone (2026-09-13, 0.9.0, native generation 10)

Matt: "bring back in the contextual AI note summarizer and formatter / meeting summarizer we're
going to make this our last flagship feature and really focus on getting it right ... a segmented
toggle at the top again to switch between raw and formatted notes ... it's okay if it's quite slow i
want it to be super accurate and I want to be able to see the note transforming in real time". Asked
whether to run it through a cloud model on attack.fm: "I'd like it to be an on device model, the idea is
that everything on here will be on device". And: several models to choose from in Settings, Settings
rebuilt on AttackFM's settings components in monochrome, and the back gesture going back in the app.

**What it does.** A note has three views under its header, one segmented control: Raw (the note as
written or spoken, the only one that edits), Formatted (the model's rewrite), and Transcript on a
spoken note (section 26). Formatted, opened for the first time, starts writing by itself and the
words arrive as they are made; a line above says what is happening (loading, reading the note n of
m, writing at so many tokens a second) with Stop, and afterwards which model wrote it and how long it
took, with Redo. The result is kept with the note (`formatted`, `formatted_for`, `formatted_model`)
under a hash of the exact body it came from, so an edit to Raw makes Formatted say "the note has
changed since this was written" with Update. The note itself is never touched.

**The model.** llama.cpp in the app again (`llama-cpp-2` pinned to 0.1.156), with the ggml fix from
0.4.x restored: `vendor/whisper-rs-sys` builds whisper.cpp against llama's ggml (`shared_ggml` in its
build.rs, `extern crate llama_cpp_sys_2` in its lib.rs), and `.cargo/config.toml` names the NDK, API
24 and `armv8.2-a+dotprod+fp16` for llama-cpp-sys-2, which reads none of the toolchain file. Four
models, all Apache-2.0, GGUF Q4_K_M, pinned to a Hugging Face revision with the LFS id as the
SHA-256 (`llm/model.rs`, and the same table in `scripts/fetch-model.mjs llm:<id>`): Qwen3.5 2B
(1.3 GB), **Qwen3.5 4B (2.7 GB, the default)**, Qwen3.5 9B (5.7 GB, for the Fold's 12 GB), Gemma 4
E4B (5.0 GB). Downloaded on demand with whisper's verified downloader, from attack.fm/glyph/models
first, Hugging Face after.

**The engine** (`llm/engine.rs`): one worker thread holding the model; a context sized to the job
(prompt plus the most it may write, in steps of 512, up to 8,192) and remade only when one needs
more, because the KV cache for 8,192 tokens on a 9B is over a gigabyte; the fixed instructions
prefilled once and restored from a snapshot on every later run (measured with the real prompt: 621
of 634 prefix tokens restored, prefill 6,397 ms to 156 ms on the Mac; the saving is larger on a phone); a sampler close to greedy (temperature 0.3, top-k 40, top-p
0.9, min-p 0.05, repeat penalty 1.05 over 256 tokens, seed 42); progress every 120 ms carrying the
whole text so far; cancellation between 128-token prefill chunks and between tokens. Thinking is
switched off through the template (`prompt.rs`, an empty thought), so the first token is the note's.
`ai_commands.rs` is the seam: `ai_models`, `ai_fetch_model`, `ai_delete_model`, `ai_generate`,
`ai_cancel`; `ai://model-progress` and `ai://progress`.

**The prompt lives on the page** (`format/prompt.ts`), so it is tuned over the air; the Rust test
reads it out of the file. A bug worth recording: the test first found the words "`String.raw`" in the
file's own doc comment and ran every measurement with a garbage system prompt; the output was still a
decent note, which is how it went unnoticed for an hour. The extraction now looks for the
declaration and a test checks the prompt starts as it should. With the real prompt, the 4B on four
Apple-silicon cores at 25 tokens a second: keeps every fact of a spoken note, its reasons and who
does what, as task items and bullets, a level 1 title in the note's words, no emoji, no label rows;
it makes a small inference now and then ("at 2" to "2pm"). The 2B on the arm64 emulator (2.5 GB of
RAM) formatted a note in 22 s, load included, and on a note of two words and a picture it invented a
sentence and described the picture; the prompt now says a picture line is copied and never described
and a note of a few words stays a few words. Phone numbers come when Matt runs it on the Fold.

**Settings** is AttackFM's settings kit in ink (`settings/kit/settingsKit.tsx`, `settings.css`): a
list of sections in clustered cards (Type, Theme; Recording, Formatting, Feel; Updates, About), each
opening a pane under `← Settings`, with a live one-line reading per row. Formatting holds the model
picker: Get for a model not here (with the bytes arriving), a radio for one that is, and an "On the
phone" card with Remove and the storage total. About's version, tapped seven times, unlocks a
Developer page (the way Android's own is) holding the developer switch and Projects, parked: the
plan is a git project's code as context for a note's formatting, and the switch holds the place.

**Back** (`core/back.ts`, MainActivity's `OnBackPressedCallback`): a stack of handlers, the newest
first: note → list, settings pane → settings → close, archive → notes, guide page → previous page →
close, the recorder → Done. At the root the app goes behind the home screen and is never finished.
Escape does the same on a desktop.

| Piece | Where |
| --- | --- |
| Engine, catalogue, prompt framing, tests | `src-tauri/src/llm/` |
| Commands and events | `src-tauri/src/ai_commands.rs` |
| Formatted columns | `store.rs` (`set_formatted`), `commands.rs` (`set_note_formatted`) |
| The prompt, the run, the view | `src/app/format/{prompt,formatter,FormattedView}.ts(x)` |
| Models on the page | `src/app/core/ai.ts` |
| Settings | `src/app/settings/{SettingsSheet,SettingsScreen,FormattingPane,panes,developerMode}.ts(x)`, `kit/` |
| Back | `src/app/core/back.ts`, `MainActivity.kt` |
| ggml, once | `src-tauri/vendor/whisper-rs-sys`, `Cargo.toml` patch, `.cargo/config.toml` |

**Added the same evening (native generation 11):** a **Choose your model** page in the welcome
guide after Light or dark (`guide/Guide.tsx` `Model`, the pages named in `guide/pages.ts`), a row per
model with its size, the chosen one in reverse, and "get it now" under the list on a phone; the
**Developer** page grew Set-up rows (that page on its own, the guide from the start) and a **Reset**
card: Reset local data (notes, recordings, pictures, settings, the guide's seen flag; the models and
developer mode stay) and Reset everything (the models directory too, whisper's included, fetched
again when asked for). Two taps, the first arms it for five seconds. Rust `reset.rs`
(`reset_local_data({ models })`) empties the store and removes the directories; the page clears its
own keys and reloads onto the guide. And **the little reader** (`format/Thinking.tsx`): Matt asked for
"a robot doing things or a fun abstract animation" for the wait before the first word, so a robot
made of the app's shapes - a rounded square with two dots and an antenna over three bars - blinks its
antenna with its eyes shut while the model loads, then opens them and sweeps each bar in turn while
the note is read, and leaves the moment text arrives.

Not done yet: the 9B and Gemma 4 have not been run on a phone (the catalogue trusts llama.cpp's
architecture list, which has both); a "meeting" mode with its own prompt; Projects. The other Glyph
session is researching newer local models and building one `ModelPicker` for Settings and the guide.

## 28. Swipes, motion, skeletons, and the tick (2026-09-13, 0.9.2)

Matt, in one evening: animations on Settings loading in and the other pages; skeleton loading
states for everything async; haptic feedback as the model's words arrive; the transcript as the
default whenever a tape plays rather than a tab; no Done word on Settings, swipe to go back; and
"going forward with swiping the other direction too". All page-only, shipped over the air.

- **Swipes** (`core/swipe.ts`, `useSwipeNav`): a quick, mostly horizontal drag across a surface -
  64 px or more sideways, twice as far sideways as up or down, inside a second and a half. Right is
  back, left is forward. On Settings (`SettingsScreen`): right steps out of a pane, then closes the
  page; left goes back into the pane just left, and a line under the list says so. On the guide:
  right is the previous page (the first closes it), left is Next. Drags that begin on something that
  moves sideways itself are ignored: the kit's segmented control (a radiogroup of radio inputs; the
  guide's own choice rows are buttons and swipe fine), sliders, text being edited. The list's rows and
  the editor keep their own gestures, so the swipe is not installed there. The phone's edge gesture
  still goes through `core/back.ts`. Found in the browser: a surface that renders null while closed
  has no element until it opens, so the hook takes an `active` flag; and hot reload keeps an old
  effect's closure, so a change to the swipe's constants needs a full reload to be seen.
- **Motion**: Settings rows and a pane's cards arrive one after another (`--i` set inline, 40 ms
  apart), a pane pushes in from the right and the list pops back from the left, the note's header,
  view control and body rise in a beat apart (on the parts, not on `.screen`, whose transform the
  unfold drives), the list's first nine rows arrive staggered. All off under reduced motion.
- **Skeletons**: paper-3 blocks the shape of what is coming, breathing. The list while notes are
  read; the Formatted view until the kept text is known (which also fixed a race: the view could
  start a run before `getNote` answered, and format a note that already had a version); the
  transcript's phrases while a recording's words load; and `setk-skeleton*` / `setk-row--skeleton`
  in settings.css for the model picker.
- **The tick** (`FormattedView`): the phone's lightest haptic, `selection`, once per progress report
  that brought new text, never more than every 100 ms.
- **Transcript on play**: the segmented control is Raw | Formatted only; on a spoken note the
  transcript takes the screen while `tape.playing` and steps aside when it stops.
- **The side key's phone** (`art/Shapes.tsx` `SideKey`): a wide slab with corners barely rounded,
  zoomed in on the edge, and the key large on its right; Matt: "not a weird super tall phone".

## 29. The note's own menu (2026-09-13, 0.9.3)

Matt: "remove the photo button at the top, just expect images to be pasted in, and add a press and
hold context menu that overrides the system one; add the usual copy paste but also add image etc".

- **Measured first.** A long press in the editor fires `contextmenu`; preventing it keeps the word
  the press selected, handles and all, and Android's own Cut / Copy / Read aloud bar never appears
  (emulator, side by side with a control run where it did). So the menu is the page's alone: no
  change to MainActivity, no subclassing of wry's WebView. The page can WRITE the clipboard on a tap
  (`navigator.clipboard.writeText`) but not read it (`readText` and `read` both "Read permission
  denied" in the WebView), so Paste needs one native method, `GlyphHost.readClipboard()`, asked of
  the generation-12 native batch; until it exists Paste is not shown and the keyboard's own
  paste, pictures included, still works.
- **The menu** (`editor/ContextMenu.tsx`): a band of paper-2 above the selection with Glyph's words
  along it - Cut and Copy when something is selected, Paste when the activity can read the clipboard,
  Select all, Add image (the picker that used to be the Photo word) - and a second, quieter band for
  the formatter's selection edits (Shorten, Expand, Make a list, Fix grammar), planned
  as `format/edits.ts`; the menu takes them as props and renders them greyed with a reason
  while the model is not on the phone. It leaves on a touch elsewhere, a scroll, or the back gesture,
  and a press on it never takes the editor's focus.
- **Paste, on 1.0.0.** `GlyphHost.readClipboard()` landed in the 1.0.0 activity (JSON `{ text }`,
  `{ path }` for a picture shrunk into the cache, `{ error }` or `{}`); the menu inserts the text,
  adopts the picture, and does nothing for the other two. Checked on the emulator with the release
  build: Select all, Cut (109 characters to none), Paste (back to the same 109).
- **Five words on a phone held upright (1.0.1).** The band was running off the right edge with "Add image"
  cut mid-word (emulator, 412 dp: 443 dp of words in 395). Now the words sit snug enough to share
  412 dp, and on a narrower screen the band scrolls sideways and fades at whichever end has more
  (`data-more` on the row, a mask in the CSS): a word fading out reads as "and more", a word cut
  off reads as broken. The menu also measures itself with layout sizes, not the drawn box, because
  the entrance animation starts a touch smaller and had been putting it 8 dp off.
- **The Formatted view is a note (1.0.2).** Matt, from the Fold on 1.0.1: "I can't scroll or
  interact with the formatted one". Two causes. The pane's `flex: 1` did nothing inside the note's
  `.body`, which is a plain block, so the pane was the height of its words and a long rewrite ran
  off the bottom with nothing to scroll (measured on the emulator: pane 356 of a 639 body, and a
  40-item rewrite 2821 tall in a 631 scroller once fixed with `block-size: 100%`). And the editor
  was read-only, with Android's own selection bar on a long press. Now it scrolls, it has the same
  press-and-hold menu as the note (Cut, Copy, Paste, Select all; no Add image, a picture makes no
  sense in the model's text), and it can be edited: an edit is kept as the formatted text after a
  400 ms pause and on leaving, with the hash it stands for, and marked `edited` in place of a model
  (`format/pipeline.ts` EDITED, which sorts above every model) so no pass revises it and the line
  reads "Edited by you." The note changing, or Redo, asks the model again. While a pass is writing
  the text is read-only, so the two never type over each other; the pipeline's own appends are told
  apart from the person's by a flag around the dispatch, or a landed draft would have been kept as
  an edit.
- **Links survive the model (1.0.3).** Matt: "AI formatting drops links" - a Notion send leaves
  `[the words](https://www.notion.so/…)` in a list item, and the rewrite lost it. Kept by
  construction, not by asking (`format/links.ts`): before the note goes in, every `[words](url)`,
  `<url>` and bare address is swapped for a token the model can copy, `[words](link-1)` or
  `<link-2>`, the way a picture line is kept whole; after, the tokens are swapped back, taking
  `link-1`, `link 1`, `<link-1>` or `(link-1)` however the model wrote them and keeping the model's
  words around a markdown link. A token that never comes back is not a lost link: its words are
  made the link again if they survived, otherwise the link is added at the end of the note on its
  own line. The prompt asks too. Measured on the Mac with the 4B (`llm::tests::
  keeps_a_link_token_where_it_was`): both tokens kept in a list item, no address invented. On the
  emulator with the 2B (1.0.3): a Notion link in a task item and a bare address both came back
  whole in 7 s, though the 2B moved the Notion link into the title; the 4B keeps it on the item.
- **An empty note is not formatted.** Found on the way: opened on a note with nothing in it, the
  Formatted view started a pass and the 2B wrote a meeting agenda from nothing. The view and
  `formatter.start` now refuse an empty body, as the queue already did.
- **Apply (1.0.3).** Matt: no way to keep the formatting. The Formatted view's line carries
  Apply, beside Redo, whenever a finished text is on screen and the note has not moved on (an edit
  still being typed is flushed first). The screen replaces the note's document through the Raw
  editor, so the editor's history covers it, switches to Raw, and says "Applied to the note." with
  Undo for eight seconds. The formatted version is kept against the new body's hash and marked
  `applied` (sorts above every model, like `edited`), so neither the queue nor a revision formats
  the text it just applied; Undo puts the old words back and re-keeps the formatted version as it
  was. Not shown while a pass writes, for a stale text (Update first), or for one already applied.

## 29a. The robot: Format, Summarize, Enhance (2026-09-14, 1.0.5)

Matt: "add more features around the AI in addition to format, I want a summarize and an enhance;
make all of these buttons instead of the segmented toggle, make a robot drop-down button for these
options".

- **One button.** The Raw | Formatted segmented control is gone. In the header, beside the cog,
  a ring with a robot's head and a caret (`format/RobotMenu.tsx`, the glyph in `art/Icons.tsx`)
  drops a card: Format, Summarize, Enhance, each with a line on what it does, the one showing
  marked with a dot, and, while one shows, "Back to note". Choosing opens that mode's view over
  the note (`format/FormattedView.tsx`, now the robot's view for every mode); Close in its line,
  "Back to note", or the phone's back gesture returns to the note. The ring fills with ink while
  a mode shows, so the header says which state the note is in. The card hangs from the header,
  which now sits above the tape and the note (`z-index` on `.header`): its entrance animation's
  transform makes it a stacking context, and without the z-index the card drew behind the tape.
- **Three modes, one machine** (`format/modes.ts`). Each mode is a prompt (`prompt.ts`:
  SYSTEM_PROMPT is Format's, SUMMARIZE_PROMPT and ENHANCE_PROMPT beside it), a budget
  (`budgetFor`: a summary gets half the note's tokens, an enhancement three times), and a kept
  text per note. The pipeline, the passes (smallest model first), the link tokens, the streaming
  view, editing, Apply and Undo are shared: `runPipeline` takes the mode, its events carry it, and
  `useFormatter(noteId, mode)` looks up the kept text itself and listens only to its mode.
- **Where the texts live** (`format/results.ts`). Format's stays in the note's store (SQLite on
  the phone): it is what the background queue writes after a recording. Summarize and Enhance
  are asked for by hand and kept on the page under `glyph-ai-results`, per note and mode, with the
  same hash and model as the store's columns, so all three modes read alike. Moving them into the
  store is a native change (a column each, a generation bump) for a later APK; this is what ships
  over the air. The key is on the reset list.
- **The prompts, measured with the 4B on the Mac** (`llm::tests`, which now read any of the
  page's prompts by name). Enhance: at least as long as the note, every one of fifteen facts kept,
  no room run out. Summarize took three tries: the first prompt gave a "summary" 1.5 times the
  note (a sentence restating every task, then the tasks again, then facts again); firmer words
  did not help; an example did - the Format prompt's plumber note and its four-line summary - with
  "one short sentence saying what the note is for, never a run through its contents" and "nothing
  else: no bullets repeating the tasks". The 4B then wrote a heading, one line and four task items
  under ten words each. A summary may drop a second-order detail (the report's due date behind
  "block Friday afternoon for it"); the test asks for the tasks' own whens.
- **Wording elsewhere.** The Formatting pane and the model guide said "open Formatted on a
  note"; they now say to tap the robot.
- **On the emulator with the 2B** (1.0.5, then 1.0.6): the dentist note summarized in 26 s to a
  heading, one line and three tasks; enhanced in 58 s to a paragraph and three tasks - with
  reasons the note never gave ("need a dental check-up before my morning routine"), which is the
  2B inventing where the 4B, in the Mac test, did not. Enhance is the mode that leans hardest on
  the model; the Fold's 4B pass has the last word. Each mode's kept text came back on switching:
  Summary, Enhanced, and Format's "Edited by you" from the earlier edit.
- **Tables survive the model too (1.0.7).** With tables in notes (§37's tables by voice, drawn by
  `editor/tables.ts`), a rewrite would mangle them. `format/tables.ts` swaps each GFM block - a
  header row with pipes, a delimiter row, every following row with pipes - for one line before
  the model and back after, verbatim; tables go first, then links, so a link in a cell is inside
  the block, and back in reverse. The line is shaped like a picture, `![table-1](table)`: measured
  with the 4B on the Mac, a bare `[table-1]` was dropped as noise even with a prompt line asking
  for it, while a picture-shaped line is copied every time, since the prompts have always asked
  that of pictures. Format and Enhance keep it where it was and append a block whose line never
  came back; a summary may leave a table out. The prompts say to copy the line and never draw a
  table of their own (`no tables` stays, meaning new ones).
- **1.0.6, one line.** Choosing Enhance while the Summarize view was open came up empty: the
  view is the same component for every mode and was not remounted on a mode change, so its
  once-per-mount start (the guard that keeps Stop stopped) never fired for the new mode. The
  view is now keyed by mode: a change of mode is a fresh view, with its own editor and its own
  start.

## 30. Talking to the recorder (2026-09-13, 0.9.2 to 0.9.4)

Matt, three asks in one evening: stop recording when the side key is let go ("surely the phone
reports what button states we're in"), send words to a note by naming it ("listen for keywords like
add to <note title> … show indications in real time … move the text over and write it out on the
correct note"), and teach the spoken markdown while he pauses. Then, from the Fold: "It missed the
mark quite a bit on the real time markdown formatting of the message creating a simple list of
items".

**The side key cannot be seen let go.** Android keeps the power key from every app so none can
stop a phone turning off: no key event, no accessibility event, and `getKeyCodeState` exists only
inside system_server (it is in `InputManagerService` but not in `IInputManager.aidl`). Samsung
Knox can send press and release intents, but only on a phone enrolled in enterprise management. So:

- **A press stops it** (native generation 12, 0.9.5). While a recording runs the screen is kept on
  (`FLAG_KEEP_SCREEN_ON`, `GlyphHost.setCapturing`), so the screen going off means the key was
  pressed: MainActivity's `ACTION_SCREEN_OFF` receiver, registered only during a recording, calls
  `window.__glyph.screenOff()`, and the recorder saves as Done does. A held press does not turn the
  screen off, so letting go of the hold that started it does not stop it. On an older APK the page
  finds no `setCapturing` and keeps saying "Hold the side key again to stop".
- **Stop when I go quiet** (Settings > Recording, off by default; `capture/quiet.ts`): four seconds
  of quiet after words, judged against a noise floor that follows the room, with the recogniser's
  words (which lag speech) only ever making the wait longer. Nothing stops before the first word.
- **Rings from the key** (`capture/SideKeyWaves.tsx`, `sideKey.ts`): on side-key recordings, three
  rings rise from the screen's edge beside the key, swelling a little with the microphone's level.
  Android does not say where buttons are: the Fold line (`SM-F9`) is 47% down the right edge, other
  phones a guess, and Settings > Recording has a slider with a preview to move it. The spot follows
  the key round the screen as the phone turns.

**Naming a note** (`capture/route.ts`, 0.9.3). "Add to", "add this to", "put that in", "send it
to", "switch to", at the start or the end of a phrase; "new note" on its own. The spoken name is
matched against the notes' titles by words, by letter pairs (so "week end trip" is "Weekend trip")
and by prefix, and only a clear winner counts: a command that moves words to the wrong note is
worse than a missed one. While the name is still being said a chip guesses "Add to **Shopping
list**"; when the phrase commits the chip fills with a tick, the words slide off, the note's last
lines appear above them (the context strip, which now always shows which note is being written on)
and the take writes itself out below. A name that fits nothing says so and the words stay. The
whole take moves, so "oat milk, add to shopping" and "add to shopping, oat milk" land the same;
splitting one take across two notes is not done.

**Tips in a pause** (`capture/tips.ts`): after 2.5 s without new words, one line above the buttons,
"Say **Check box** to make a to-do", a different one each pause, gone when talking resumes. The
routing tip names one of his own notes. `?simulate=route` speaks a note that routes itself, for
watching all of it without a microphone.

**Lists said the way people say them** (0.9.4, `capture/markdown.ts`). His first real list, as
Whisper wrote it: "List item is weed. List item is Culver's onion ring. The next list item is
Culver's cement mixer ice cream. And lastly, the final item that we need on our list is a gallon of
black coffee." The cue rules only knew "bullet point", so it came out half prose. Now:

- An item phrase names an item and gives it ("list item is", "the next item is", "another one is",
  "item number three is", "the last thing we need on the list is") and becomes a list line of just
  the item. A bare "item" or "thing" needs an ordinal or the word "list" beside it, so "the thing is,
  I'm tired" and "the item is broken" stay sentences.
- A sentence that announces a list ("add a list below", "here's my shopping list", "make a numbered
  list") keeps its words and opens a list; short plain sentences after it (five words or fewer, not
  "I'm…" or "it's…") are its items until a longer sentence ends it. After a cue list ("bullet point,
  eggs") a short "Thanks." stays a reply.
- A list keeps its kind: begun with "number one" it stays numbered through "the next item is", and a
  pause between items no longer breaks it. Item phrases inside cues are stripped too ("number one,
  list item is weed" is "1. Weed").

## 31. Pins, and swipes that show what they do (2026-09-13, 0.9.5)

Matt: "redo the archive delete start ui, rename star to pin and show a pins icon on the top right".

- **Pin, not star.** The swipe right is Pin (Unpin on a pinned note) and a pinned note carries a
  small tilted pin in its row's top right corner, in the meta line's grey, dropping in when it is
  pinned. Pinned notes still sit first. The store keeps its `starred` field; only the word changed.
- **Pinned is a category** (1.0.0, `notes/groups.ts`). Matt: "put pinned notes in a category above
  the rest of the notes in lists". Pinned notes gather under a small PINNED label and the rest under
  OTHERS, both in the rows' meta voice so they read as dividers, not headings. With nothing pinned
  there are no labels and the list is one run as before; the archive is never split.
- **The gap is the action** (`notes/SwipeRow.tsx`). A swipe no longer uncovers a line of large words.
  The gap the row leaves holds the action's picture in a ring and its word under it: the ring fills
  as the swipe nears the detent, the picture grows into place, and at the detent the ring closes,
  the motor ticks and the whole gap fills, ink for Pin, Archive and Restore, red for Delete, with
  the picture doing its small move (the pin pressed in, the box dropped, the bin shaken). Armed on
  Archive, a line under it says "Further to delete"; past that detent the picture becomes the bin.
  The pictures are the app's own strokes (`art/Icons.tsx`: `Pin`, `ArchiveBox`, `Unarchive`, `Bin`).

## 32. Items into a note's list, and short links (2026-09-13, 0.9.6)

Matt reset the focus to a few core features ("I just want a few core features to work"): items spoken
into a note's list, projects as context for the local AI, Notion tasks, and short links. The models page
and the wake word wait. This section is the first two; Notion and projects follow.

**"New item for AttackFM"** (`capture/route.ts` `kind: 'item'`, `capture/listAppend.ts`). Said in the
recorder, it names a note (the same forgiving match as "add to", so "attack FM" is AttackFM) and the
item goes into that note's list, not onto the take:

- The item can come in the same breath ("new item for AttackFM, fix the login bug") or as the next
  phrase, the chip saying "Say the item for **AttackFM**" and then showing the words as they are said.
  "New items" or "new tasks" takes every phrase until a pause longer than a paragraph's, and a phrase
  that lists ("update the readme, ship the APK and tell Sam") becomes one item each.
- The list is the note's last run of list lines; items go on its end in its style (`- [ ]`, the next
  number with the same delimiter, the same bullet, the same indent), after any lines that continue the
  last item. A note with no list gets one at its end, to-dos when "task" or "to-do" was said.
- The note is written at once, while the take carries on where it was; when the take is itself writing
  onto that note, its drafts build on the grown body. The landing preview shows the list's last lines
  and the new ones arriving with a tick, and the chip says "3 added to **AttackFM**".

**Short links** (`core/shortUrl.ts`, `editor/links.ts`). "Don't show the full link path just show the
first 3 chars after the tld then a ... and the last 3 chars": a link's address shows as its host, three
characters, an ellipsis and three characters, `notion.so/att…c0d`, with the whole address as its title.
In the editor it is a replace decoration over the `URL` node, the first thing the editor draws in place
of what is written, so it steps aside on any line the selection touches (the address is written out in
full there, to edit) and while an IME composes. The recorder's words and the list's titles shorten
addresses the same way. The stored text never changes.

## 33. Talking into a note, and the note's settings (2026-09-13, 0.9.7)

Matt: "i want to be able to start talking on a note and also I don't see the speak icon show up on
the note or a settings button on the note to be able to manage it as a project or something and I
don't see the cassette at the top of the note".

- **A cassette on every note** (`tapes/NoteTape.tsx`). A spoken note's tape plays as before, with
  Speak as a word beside Play. A note never spoken into shows the same cassette, quieter, labelled
  with its title and BLANK, "Nothing recorded yet" and a Speak pill; tapping the cassette is Speak.
- **Speak on a note** opens the recorder aimed at that note (`noteId` on the capture screen): the words
  go on its end whatever memo mode says, the recording joins the note's tape, and Done comes back to
  the note, read fresh from the store so its body and a Formatted comparison are current. The note's
  typing is flushed before it goes.
- **The note's settings** (`editor/NoteSettings.tsx`): the header is `← Notes` and a cog; Delete moved
  into the cog's sheet, from the bottom over the dimmed note, with Pin (or Unpin) and Archive, then
  "Linked to": Project (a GitHub repo the AI reads) and Notion board, shown before they work, and
  Delete in red at the bottom. Back closes the sheet before it leaves the note.

## 30. Formatting in passes (2026-09-13, 0.9.8)

Matt, with a rough spoken note on the Fold: "the quick format wasn't really fast, maybe the quick
format needs to reformat a few times with slower models to make revisions". The same shape whisper
already has (base.en live, small.en after), applied to the formatter.

- **Passes** (`format/pipeline.ts`): the models on the phone from the smallest up to the one chosen
  in Settings, smallest first, so a draft comes quickly and the chosen model has the last word. Each
  pass writes from the note itself rather than from the draft (a careful model anchored to a careless
  draft keeps its mistakes; from the note it kept every fact in the samples) and is saved as it lands
  (`formatted`, `formatted_for`, `formatted_model`), so a killed app keeps the best it had. One run per
  note, shared by whoever asked, watched through `subscribe`: the draft streams into the view; a
  revision keeps the draft on screen and shows only its pace, then swaps the text in when it lands.
  A note whose kept text is a draft by a smaller model gets only the passes above it.
- **The queue** (`format/queue.ts`): a spoken note is formatted without being asked, after the whisper
  post-pass has finished with it (read off the `glyph-refine-queue` key, so the draft is not written
  from words about to be replaced), one note at a time, never while the recorder is on screen or the
  app is hidden, persisted in localStorage like the refine queue. Hooked by the recorder's Done
  (`enqueueFormat`) and started from App (`startFormatting`), two lines.
- **The view**: "Draft by Qwen3.5 2B. Revising with Qwen3.5 4B, 0:42." with Stop, which keeps the
  draft; then "Qwen3.5 4B, 1:20." with Redo, or "changed since" with Update.
- **A project's pack** (`projects/projects.ts`) goes in with every pass as the
  system message's context, so it is part of the snapshotted prefix, and its version is folded into
  `formatted_for` (`noteHash`), so a re-read pack reads as an edit.
- **Measured on the arm64 emulator** (2B only, so one pass): a two-line note drafted in 28 s into a
  title and two task items; the background queue, given a stale note, drafted it again within 30 s
  of launch with the app untouched. The draft-then-revise path needs two models on one phone and is
  covered by the unit tests until the Fold has both.

## 34. "The next item is", said in two breaths (2026-09-13, 0.9.8)

From the Fold, after 0.9.4: "1. The Grand Canyon / 2. Spain / 3. The next item is / Paris. / The next
item is. Greece." Whisper commits a phrase at a breath, so the item phrase and its item arrive as two
phrases; and when it hears a list being dictated it sometimes writes its own "1. … 2. … 3." inline.

- **An item phrase with no item** ("The next item is.", or inside a cue, "Number three, the next item
  is") is held, and the next sentence is taken as the item, whatever its length, in the list's kind: a
  held numbered cue keeps the count. If a second item phrase comes instead, or nothing follows, the
  held words are kept as words.
- **Whisper's inline numbering** (`inlineNumbering`): two or more markers counting up by one within a
  paragraph are split into "number N," cues before sentences are read, so the numbered rule lays them
  out, and a piece that is only an item phrase waits for the next phrase. A year ("1990.") or a lone
  "2." is not a run.
- **Formatting after a recording** (staged passes, `format/queue.ts`): Done queues the note
  after its refine job, and the queue is paused while the recorder is on screen.

## 35. Projects and Notion (2026-09-13, 0.9.9 page, 1.0.0 native)

Matt: "we should bring back linking projects and have the local AI go through and examine them where
possible for context so we can also link notion boards to convert list items into notion tasks or say
'add a note for the notion task for <notion task title fuzzy match>' and reference the notion task in a
formatted link". His choices: projects are GitHub repos; Notion is "Sign in with Notion"; list items
become tasks by voice, by swipe and by sending a whole list.

**Projects** (`projects/projects.ts`, the note's cog → Project). Paste a GitHub link (and a token for a
private repo, kept on the phone). The page reads GitHub's API directly: the repo's description and
default branch, its tree, and up to eight files that say what it is, ranked README,
AGENTS.md, docs with "design" in the name, the manifest, other top-level docs, skipping vendored and
built folders. Up to 16,000 characters of that go to the formatter's model (or the smallest one on the
phone) with a prompt for a plain briefing under 250 words: what it is, its parts, the names and terms
that will come up, current work. With no model, or in a browser, the README's words (HTML, images,
badges and link targets stripped) stand in. The pack is kept under `glyph-github-projects` (not the
0.4.x `glyph-projects`, which holds entries of another shape) and linked per note in
`glyph-project-links`. `projectContextFor(noteId)` hands the pack to the formatting pipeline
as the request's `context`, so it sits in the snapshotted prefix; `projectContextVersion` counts in its
"changed since" hash.

**Notion, the server half** (`server/src/notion.rs`, glyph-api). A public integration's code has to be
swapped for a token with the client secret, which cannot ship in the app. `start` (state + PKCE-style
challenge) redirects to Notion's consent page; `callback` swaps the code and holds the tokens for ten
minutes, answering the browser with a one-line page in ink; `claim` hands them over once, only to a
verifier whose SHA-256 is the challenge, so the token never travels in a URL; `refresh` swaps a refresh
token. No bearer token on these routes: the public web build carries none, and the verifier and the
refresh token are the secrets. NOTION_CLIENT_ID and NOTION_CLIENT_SECRET come from `.env` and travel
to the box's root-owned environment file over the deploy's stdin (`scripts/deploy-server.mjs`); without
them the routes say sign-in is not set up.

**Notion, the phone half** (`src-tauri/src/notion.rs`, native generation 12). api.notion.com does not
answer a web page, so Rust keeps the account in `notion.json` under the app's data (written beside and
renamed over, 0600, removed by a reset) and makes the calls the page asks for, limited to the routes
Glyph uses (search, databases, data_sources, pages, blocks, users/me), refreshing once on a 401.

**Notion, on the page** (`core/notion.ts`, `settings/NotionPane.tsx`, `editor/NoteSettings.tsx`,
`notion/items.ts`, `editor/swipeItems.ts`, the recorder):

- Settings > Notion: signed in or not and to which workspace, Sign in / Sign out, and the boards shared.
  Signing in opens the browser; coming back to Glyph collects it by itself.
- A note's cog → Notion board picks where its tasks go (`glyph-notion-links`), and Send list to Notion
  makes every unsent item a task. An item is sent once: its words become `[words](task url)`, which the
  editor shows short, and ticked to-dos and items that are already links are skipped.
- Swiping a list item left in a linked note sends that one: the line follows the finger, a tile behind it
  fills toward the send point and turns ink when it counts.
- By voice while recording: "send that to Notion" (the last phrase, or the items just added to another
  note), "new task for AttackFM in Notion, …" (the item goes into AttackFM's list and to its board), and
  "add a note for the Notion task for …" (the task found by name across linked boards, fuzzy, and linked
  in the take). A sent phrase of the take keeps the shape its cues gave it and only gains the link
  (`applyLinks`).

## 36. "Leave a note for …" (2026-09-14)

Matt: "leave a note on the page for <title> that says <desc> and make it smart enough that if a list
item is present it will add to the list intelligently".

- **The command** (`capture/route.ts`, kind `leave`). Said at the start of a phrase: leave, add, put,
  write, drop, jot or stick; a note, line, comment, reminder or memo; on, in, to or for; optionally "the
  page for" or "the note called"; then the note's name; then what introduces the note ("that says",
  "saying", "that", a comma or a colon). "Leave a note for AttackFM." on its own waits, and the next
  phrase is the note, as "new item for" does. "Add a note for the Notion task for …" keeps its own
  reading. The name is matched to a note the same fuzzy way as every other route.
- **Where it goes** (`capture/listAppend.ts`, `leaveNote`). A note with a list takes it as an item of that
  list, in the list's style (a to-do list gets a to-do, a numbered list the next number). A note with
  several lists takes it in the one it fits: the list whose heading (or "Label:" line) and items share
  the most words with it, the heading counting double, the last list on a tie. A long thought (more than
  30 words or two sentences), or a note with no list, takes it as its own paragraph at the end. "That" and
  "to" before the words are dropped: "that says to fix the login" is the item "Fix the login".
- **Seen as it happens.** The chip reads "Note for AttackFM" while the name is being said, "Say the note
  for AttackFM" while it waits, and the landing preview shows the list's last lines with the new one
  arriving under them. A tip in a pause teaches it with one of your own titles. `?simulate=leave` in the
  browser says it both ways.

## 37. Plugins (2026-09-14)

Matt: "build plugin support and extract the notion stuff into a plugin that ships standard". Built in and
switchable (not installable from outside yet), with GitHub Projects the second standard plugin. The guide to
writing one is `docs/PLUGINS.md`.

- **Nothing in the app names a plugin.** The note's cog asks `plugins.noteLinks()` and `noteActions()`, the
  list swipe asks `itemAction(noteId)`, the recorder asks `voiceCommands()`, `itemTargets()` and `tips()`, the
  formatter asks `pluginContextFor(noteId)`, and Settings asks `usePlugins()`. A plugin switched off offers
  nothing, at once. Its data stays for when it's back on.
- **The manifest is enforced.** A plugin reaches the phone only through its host, which refuses native commands,
  storage keys and permissions the manifest didn't declare. The registry refuses a plugin whose voice commands
  lack `voice`, or whose note actions lack `notes`. Settings › Plugins lists each permission with its reason and
  the hosts it talks to.
- **What moved.**
  - `core/notion.ts` → `plugins/notion/client.ts`, now through the host.
  - `settings/NotionPane.tsx` → `plugins/notion/`.
  - The board picker and Send list (from NoteSettings and NoteScreen) → `plugins/notion/`.
  - The Notion voice commands (from route.ts and CaptureScreen) → `plugins/notion/voice.ts`.
  - `projects/*` and the project picker → `plugins/projects/`, which gains a Settings page (repos read, Forget,
    the token).
  - `notion/items.ts` → `core/itemLinks.ts`, since linking list items is generic.
  - The item command's `notion` flag is a generic `target` word that a plugin offers.
  - The swipe tile's word comes from the action.
  - `reset.ts` takes plugin keys from the manifests.
  - The parked Developer › Projects switch is gone.
- **Settings.** Each switched-on plugin with a page gets a row (Notion, Projects) in its own group, then
  Plugins, reading "2 of 2 on".
- **Kept stable.** Notion still needs native generation 12 and the same four commands. The storage keys are
  unchanged, so boards, projects and sign-ins survive the update. With one context-giving plugin its version
  passes through untouched, so no note is formatted again because of the move.

## 38. "Glyph", then the command, then yes (2026-09-14)

Matt said "add a note to hello trade" while recording, and got a new note titled "To the hello trade". His
request: "have it listen for keywords and not do anything until it hears the keyword and confirms the action like
adding a list item to the hello trade note". Two faults caused it. Commands only matched a handful of exact
phrasings ("add buy milk to …" and "add a list item to …" matched none). And a pause mid-command split it into
two phrases that were each plain words.

- **Nothing is a command until "Glyph"** (`capture/command.ts` `findKeyword`). This covers the spellings the small
  model writes for it (glif, gliff, glyf), with "hey" or "OK" in front, and never matches "hieroglyphs" or
  "cliff". Words before the keyword stay in the note. Words after it, across as many phrases as it takes, are the
  command, shown in the chip ("Glyph: add a list item to…") and never written into the note.
- **Read loosely, since the keyword already marks a command** (`planCommand`). Everything route.ts knew, plus
  "add/put/stick X to/in/on Y". Every split point is tried, and the one whose name best matches a note wins.
  "A list item", "a task" or "a note that says" in front says what kind of thing it is. A command that names a
  note but not what goes in it waits for the next phrases (the chip reads "Say the item for HelloTrade").
- **Then it asks.** A card where the chip was: "ADD TO HELLOTRADE", the lines exactly as they will land (the
  preview and the result are both `placeWords`), "In its list" or "As a new paragraph", then Cancel and Add. It
  also takes "yes" or "no" said aloud (`reply`; short phrases only, so "No problem with the invoice" is a
  sentence). Talking on leaves the card up and the words go into the note. Twenty seconds unanswered means not
  done. Plugins' commands ask too: `VoiceCommand.describe` gives the card its words, e.g. "Send “Book the cabin”
  to Notion".
- **The keyword said as a word** ("Glyph is going to need a plugin store"). With no command within 4.5 s, what
  was said goes back into the note as it was. A note about Glyph shouldn't lose its words to a false start.
- **The recording stays open.** Stop-when-quiet waits while a command is being said or asked about.
- **The better words leave commands out.** The refine pass re-transcribes the whole take, so it was putting routed
  command words back into notes. A job now carries `skip` (the command stretches) and `keywordAt` (phrases cut at
  "Glyph"), and `withoutCommands` drops and cuts the better phrases by overlap.
- **Settings › Recording › Commands start with “Glyph”**, on by default. Off, a phrase that reads as a command
  still counts without the keyword, and still asks. The tips in a pause teach the keyword form.

## 39. Tables, said a piece at a time (2026-09-14)

Matt: "add a feature for creating markdown tables ... if we say something like 'add a table to the attackfm bugbash
note' it should ask 'and what will the column labels be?' ... to guide the user more".

- **Asking for one** (`capture/command.ts`, plan kind `table`). After "Glyph": add, make, create or start a table.
  Name a note ("to the AttackFM bugbash note") or none, meaning the note being recorded. "…with columns bug, owner
  and status" skips the first question. "A table of contents" isn't a request.
- **The conversation** (CaptureScreen `TableCard`). A card where the chip is asks one thing at a time: "What will
  the column labels be?", then "What goes in the first row?", then "Next row? Or say “done”". The table grows
  in the card as it's answered, and the words being heard show under the question. Everything said while it
  asks is the table's, never the note's (and the better-words pass leaves it out). "Cancel" or "never mind"
  drops it, so does 45 s of nothing, and "That's all" on the card finishes it like "done".
- **Cells** (`capture/table.ts`). A row is said the way a list is: commas, with "and" before the last one
  ("bug, owner and status"), or "and" alone. "Column one, …" prefixes are dropped. A short row is padded, and a
  long one keeps its extra words in the last cell rather than growing a column. A pipe in a cell is escaped.
- **Then it asks, like every command.** The finished table is previewed ("ADD THIS TABLE TO ATTACKFM", "2 rows,
  at the end of the note") and a yes or a tap adds it as its own block at the end of that note. A table for
  the note being recorded follows the take's words.
- **Drawn as a table** (`editor/tables.ts`). A GFM table the caret isn't in is drawn as a real one: header,
  hairline grid, words never broken mid-word, scrolling sideways when wider than the screen. Tapping it puts
  the caret at its start and shows the pipes to edit; moving out draws it again. It's a state field, because
  block decorations can't come from a view plugin, and focus is tracked in a field of its own. The Formatted
  view uses the same editor, so tables are drawn there too (read-only, always drawn). The formatter keeps table
  blocks verbatim (`format/tables.ts`).
- `?simulate=table` answers the questions and says yes; `?simulate=tableask` stops at the yes.
