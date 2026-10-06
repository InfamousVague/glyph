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

`src/app/ux/ratchet.ts` (AttackFM's path; the pacing here is `src/app/core/detentFeel.ts`, §45) and the 28 ms floor in `fireFelt` are ported from AttackFM unchanged. The
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
`src-tauri/.cargo/config.toml` (now `.cargo/config.toml` at the repository root), bindgen needs the NDK sysroot, and the resulting `.so` will need
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
      markdown.module.css     every token rule from tokens.md §7 (then Editor.module.css)
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
> local rules in `markdown.ts` only, and the page no longer calls `/api/format`. glyph-api
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
| Server | `server/`, `scripts/deploy-server.mjs`, `https://ghostmarkdown.com/api/format` |
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
  `--app-ink-4`, `--app-wash` (a translucent ink tint for highlights), `--app-dots` / `--app-dots-size` (since removed:
  nothing drew them by 2026-09-25).
- **`.app-inverse`** re-declares the whole mapping on the reversed scale, so any element - a chosen row, an armed
  swipe - prints in reverse, kit components inside it included. (An armed Archive is ink with paper words; an armed Delete
  is the red exception above.)
- **`.app-pill`** is the one loud button (Speak, Next, Scan); everything else stays an `.app-word`. **`.app-dots`** was the
  texture, used for empty space only: the guide's cover and the empty list. Nothing used it by 2026-09-25, and it is
  gone from ink.css.

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

- **The page** (`ink/InkScreen.tsx`): dotted paper edge to edge (`.app-dots`, since removed). The note's words sit
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
| The prompt, the run, the view | `src/app/format/{prompt,formatter,FormattedView}.ts(x)` (formatter.ts is now `src/app/format/bodyHash.ts` and `src/app/format/pipeline.ts`; FormattedView.tsx went with §114) |
| Models on the page | `src/app/core/ai.ts` |
| Settings | `src/app/settings/{SettingsSheet,SettingsScreen,FormattingPane,panes,developerMode}.ts(x)`, `kit/` (FormattingPane.tsx is ModelCard.tsx on Recording since §138) |
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
  table of their own (`no tables` stays, meaning new ones). On the emulator with the 2B: a
  three-row bug table typed into a note came back whole and drawn after Format, all cells in
  place - at the end of the note, because the 2B dropped the line and the fallback appended the
  block. The 4B keeps the line where it was.
- **The 2B invents on short notes.** Twice on the emulator, Format on a one-line note ("bug bash
  notes from friday heres what we found") came back as a bug report with a root cause, an impact
  and three actions the note never had; the same 2B on the dentist note enhanced it with reasons
  it never gave. The prompts forbid it and the 4B obeys; the 2B does not, for a note with little
  in it. Worth a rule: skip the 2B's draft pass when the note is short, since the 4B answers a
  short note in seconds anyway, and the draft is where the inventions show.
- **1.0.6, one line.** Choosing Enhance while the Summarize view was open came up empty: the
  view is the same component for every mode and was not remounted on a mode change, so its
  once-per-mount start (the guard that keeps Stop stopped) never fired for the new mode. The
  view is now keyed by mode: a change of mode is a fresh view, with its own editor and its own
  start.

## 29b. The update card, in foil (2026-09-14, 1.0.8)

Matt: "the update banner is kind of ugly with the solid blue, can you update it to be like a white
holographic design". The card (`notes/NotesList.module.css`, now `src/app/notes/Notices.module.css`) is now white in both themes - the
one white card on black paper is the point - with a foil sheen: a pastel spectrum (pink, mint,
lemon, lavender, in oklch at chroma 0.08 so it reads as colour and not a tint) drifting slowly one
way under a band of white light crossing the other, the way a holographic sticker catches a lamp.
Near-black words, a black pill for the action, an inset white hairline and a soft drop shadow so
it sits on light paper too; the progress bar is black on a faint track. Reduced motion stops the
drift. Checked at phone width in both themes; the card only appears when an update is waiting, so
the check was a card injected with the module's classes.

## 29c. Suggestions, inline (2026-09-14)

Matt: "render suggestions inline for stuff like adding a list item as a Notion task and whatnot; I
want the note to feel more alive with the integrations while remaining minimalistic".

- **What it is.** A quiet word at the end of a line for what a plugin could do with it, tapped
  to do it: "Notion" after a to-do that is not a task yet, once the note has a board. A small
  outlined word in the faintest ink, a step smaller than the line, with a hairline of its own
  ink at less than half strength so it shows on black paper and on white without shouting.
  Nothing else on the page changes. While it runs it says its busy word ("Sending") and cannot
  be tapped twice; once the line has become what was offered (a link to the task) the plugin no
  longer offers it and the word is gone. It is never on the line being typed: it would sit
  against the caret and jump with every letter.
- **Where it comes from.** A plugin extension point (`plugins/types.ts` `suggest(noteId, body)`,
  gathered by `plugins.suggestions`), pure and read on every change of the document - the
  answers are a regex per line, and a note of five hundred lines costs nothing. It needs the
  `notes` permission like the other things that change a note; the registry refuses a plugin
  that offers words without it. The Notion plugin offers one per unsent item when a board is
  linked; each runs the same send as the swipe, so the line becomes the task's link and is one
  undo. Other plugins can offer their own (a repo address that could become the note's project,
  say) without the editor knowing what they are.
- **How it is drawn** (`editor/suggestions.ts`). A widget decoration after the line's text
  (`side: 1`), rebuilt on document and selection changes and on a busy effect, so the note's own
  words are never touched and the swipe on the line still works. The widget ignores the editor's
  events and stops its own, so a tap is a tap and not a caret move. Verified in the browser at
  phone width in both themes and by unit tests: the word on every offered line but the caret's,
  following the note as it changes, the busy word while it runs.
- **On the emulator** (1.0.9, a board record written by hand): a note of three to-dos opened
  with the three words in place within a third of a second; tapping one said "Sending" and gave
  the account error on the line, since the emulator has no Notion sign-in, then offered the word
  again. Once, right after a relaunch, a note opened with no words until the caret moved: the
  Notion plugin's readiness is settled by an asynchronous check of the binary at start-up, and
  the editor's first build can precede it. The swipe has the same window. Worth a nudge from the
  registry when readiness changes, later.
- **Later.** A first nudge before anything is linked ("Send to Notion…" on the first to-do,
  opening the board picker) needs a way for a plugin to open its own picker from a note; and
  the Projects plugin could offer "Project" on a line with a GitHub address.

## 29d. Apply, three ways (2026-09-14, 1.0.9)

Matt: "there is no way to accept, append or prepend a summary or enhancement". Apply replaced the
note, which is right for Format and wrong for a summary that belongs above the note or an
enhancement someone wants under it. The Apply word in the robot's line now opens three -
Replace note, Add above, Add below - and Back. Above puts the text, a blank line, then the note;
below puts the note, a blank line, then the text; all three go through the note's editor, so the
history has them, and the notice says which happened ("Added above the note.") with Undo, which
puts the old words back and the kept version back to what it was. The kept text is marked applied
against the hash of the note as it now is, not of the text, so the queue and the passes leave it
alone until the note changes again. Verified in the browser: all three ways, the notice, Undo.

## 29e. The item mark: one form for a linked item (2026-09-14)

Matt: "we also need a common format for linking Notion pages to list items, as the AI will change
how this looks when formatting or enhancing". A sent item's words used to become the link,
`- [ ] [Buy milk](https://…)`, and a rewrite that moved or dropped the link left the item looking
unsent (the 2B moved one into the title): the suggestion offered it again, and Notion would have
had it twice.

- **The form.** The words stay plain and the item ends with a mark, a link whose words are the
  lowercase name of what it is linked to: `- [ ] Buy milk on the way home [notion](https://…)`.
  Generic on purpose: `[github](…)` would mark an issue the same way, and the editor would draw
  it the same way. Written in one place, `core/itemLinks.ts` `linkedLine`, so the swipe, the
  inline suggestion, "Send list to Notion", the voice commands and the recorder's live linking
  (`applyLinks`, which puts the mark at the end of an item, or right after words in a sentence)
  all write it without a change of their own. Recognised alongside the old form, so a note from
  before is never sent twice; `unsentItems` answers an item's words without its mark.
- **Drawn.** `editor/links.ts` draws a mark - the whole `[notion](address)`, when it is the last
  thing on an item's line - as one small solid pill with the name on it: the done twin of the
  outlined suggestion pill, so a note reads at a glance: outlined could be a task, solid is one.
  On the caret's line it is written out in full, like a short link. An ordinary link at the end
  of an item (`[the board](…)`) is not a mark: its words are not one lowercase name.
- **Through the model.** A mark is protected like every link (`format/links.ts`), as
  `[notion](link-1)`, and the three prompts say to keep it at the end of its item. The
  protection remembers the item's words for a mark, and a mark whose token never comes back goes
  onto the item found again by those words - three words in five, letters and digits, three
  characters or more - before the old fallbacks (wrap the words, append at the end). Measured on
  the Mac with the 4B (`llm::tests::keeps_an_item_mark_at_the_end_of_its_item`).

## 29f. A note called Glyph (2026-09-14, 1.1.3)

Matt, from the Fold: he said "add a note to the Glyph note saying testing if this works" and got a
new note titled "Add a note to", the rest gone. Reproduced with `planCommand` against his notes:
he has a note called Glyph, the keyword was not said first, and `findKeyword` took the note's
name mid-phrase for the keyword - the words before it became the note, the words after it were a
command nothing could read, and at the end of the take they were dropped. Said with "Glyph" first,
every phrasing of it already parsed, his included.

- **The fix** (`capture/command.ts`): an occurrence of the word that a preposition leads and
  "note", "page" or "list" follows ("…to the Glyph note") is a name, not the keyword, and the
  search moves on; the keyword still counts first in the phrase or on its own later. So the phrase
  without the keyword is plain words and nothing is lost, and with it the Glyph note can be named.
- **Trying any phrase without a microphone** (`capture/engine.ts`): `?simulate=say&say=a|b` speaks
  the phrases given, one per bar, the way the fixed scripts do. Both cases were run through the
  real recorder in the browser: the card "Add to Glyph: Testing if this works", a spoken yes, and
  the line at the end of the Glyph note; and the keyword-less phrase kept whole as a new note.
- **Still open, for the recorder:** words after a keyword that never resolve into a command are
  dropped at the end of the take. They should go back into the note as words, with a line saying
  the command was not understood.

## 29g. On this phone: the AI card, Local only, and the pinned heading (2026-09-14, 1.1.4)

Matt: "highlight the local AI part of this, making sure the app can be run totally without a
server if desired; a better, consistent AI card that renders when it's thinking, and it should
render things like real phone hardware usage". And, for the list: "better iconography for pinned
notes, make the label more apparent for the group, avoid individually repeatedly marking things
like having a pin on each note".

- **The AI card** (`format/AiCard.tsx`). One face for the model at work, drawn by the robot's views
  while a pass is writing and nothing has arrived yet, and offered to the review screen: the
  model and its size on disk, a pill saying "On this phone", what it is doing and how fast (the
  same lines as before), the little reader in the corner, and the phone underneath as a grid of
  readings with hairline bars - cores, memory, battery from what the page can read itself
  (`format/deviceFacts.ts`: hardwareConcurrency, deviceMemory, getBattery), and from native
  generation 14 the engine's own readings every tick (`Hardware` on Progress: its memory of the
  phone's, its share of the cores, threads of cores, the hottest thermal zone). What nothing
  reports is left out rather than guessed. "Nothing leaves the phone." closes it, with Stop.
- **Local only** (`localOnly` in preferences, a switch in Settings > Formatting under "On the
  phone"; on Account's Privacy card since §138). While it is on: the update check never asks the box (`core/ota.ts`), a model download
  is refused with a sentence (`core/ai.ts`), the voice model is not fetched and the recorder says
  why, the larger voice model is not fetched and the better words wait (`capture/engine.ts`,
  `capture/refine.ts`), and every plugin that declares the network permission is off
  (`plugins/registry.ts`, which now follows preference changes and tells its listeners). Glyph
  runs from what is on the phone; turning it off restores everything.
- **The readings, native generation 14** (`src-tauri/src/llm/hardware.rs`, 1.2.0). The engine's
  reporter samples the phone with every progress report, about every 120 ms: the app's resident
  memory from `/proc/self/statm`, the phone's total and available memory from `/proc/meminfo`
  (the `device` module's parser), the process's CPU time from `/proc/self/stat` turned into a
  percentage of one core over the time since the last sample (640 is six and a half cores busy),
  the engine's threads of the phone's cores, and the hottest thermal zone under
  `/sys/class/thermal` where the phone lets it be read - many do not, and then there is no
  reading rather than a guess. The reading rides on `Progress` as `hardware`, absent where there
  is no `/proc` (the Mac's tests), and the card draws whatever arrives. Reading three small files
  costs microseconds. The parsers take text, so a real phone's files are the unit tests.
- **The pinned heading** (`notes/NotesList.tsx`). The pin left every pinned row and sits once on
  the group's heading, tilted as it was; the heading grew a step and darkened an ink, with a
  hairline under it, so the group reads as a group. Others keeps its label without an icon, so
  the pin stays the pin. Swipes are as they were.

## 29h. The formatter's tidy-up (2026-09-14, 1.2.1)

Matt: "the formatter can do things like double nest links and not clean up Notion task links to
simply say notion, and other basic formatting tasks". Two pure passes in `format/clean.ts`, both
in the pipeline:

- **Before the model, `cleanNote`.** An item linked the old way - its words as the link,
  `- [ ] [Buy milk](notion-url)`, whole or mid-words - becomes the mark form, `Buy milk
  [notion](url)`, so the model sees words as words and the mark as the one thing to keep. Links to
  anywhere else are left as they are. The hash stays the note's own.
- **After the links are back, `cleanRewrite`.** A link nested in a link's words, which a small
  model writes now and then (`[[Buy milk](url)](url)`), unwinds a layer at a time and the inner
  one wins. An item's mark is once and last, wherever the model put it or however many times.
  Then the plain markdown the prompts ask for: `-` bullets for `*` and `+`, task boxes with their
  spaces and a lowercase x, a space after a heading's hashes, no trailing spaces, no run of blank
  lines. Words are never touched; the test that proves it feeds the prompt's own example through
  and gets it back unchanged.
- **Marks are named things.** Restricting the mark grammar came out of this: `[docs](url)` at the
  end of "read the docs" is one lowercase word in a link and was a mark called docs, drawn as a
  pill. Now a mark's name must be a plugin's id (`core/itemLinks.ts` `registerMarkName`, which the
  registry calls with every plugin as it loads; "notion" is built in), everywhere marks are read:
  the editor's pill, the formatter's protection, and both passes here.
- **And one more guard** in `format/links.ts`: a link whose token vanished is never restored
  around words that already sit inside another link, which was a second way to nest.

## 29i. The gist under every title (2026-09-14, 1.2.2)

Matt's board: "live on-device AI summaries on the home list". One quiet line under each note's
title in the list, what the note is about, written on the phone in the background.

- **The line** (`format/gist.ts`, GIST_PROMPT in `prompt.ts`): at most ten words in the writer's
  own voice, no markdown, no closing punctuation; a note with many things in it gets a line about
  what they have in common, not a list of them - the first prompt without that rule gave the
  weekend note fifteen words naming every errand; a second example fixed it, measured with the 4B
  (`llm::tests::gists_a_note_in_one_short_line`). The answer is tidied to one bare line and cut at
  ninety characters on a word (`tidyGist`).
- **The runner.** The list hands `useGists` the notes it shows; a module-level runner works through
  the ones with no gist, or a gist from an older body, one at a time, newest first, only while the
  app is on screen, with the smallest model on the phone (speed over care for a line), forty
  tokens each, links protected as tokens. Each gist is kept in `glyph-ai-results` beside the
  summaries with the hash of the body it came from, so a note that has not changed is never asked
  twice and a note that has shows its old line until the new one lands; a note the runner could
  not gist is left alone for the session. The engine serialises this with the format queue and the
  robot's own passes. Nothing leaves the phone, and Local only changes nothing here.
- **Drawn** in `notes/NotesList.tsx`: one line, the third ink, ellipsised, fading in when it lands;
  nothing at all until then, so a phone without a model looks as it did.

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
- **A project's pack** (`projects/projects.ts`, now `src/app/plugins/github/repos.ts`) goes in with every pass as the
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

**Projects** (`projects/projects.ts`, now `src/app/plugins/github/repos.ts`; the note's cog → Project). Paste a GitHub link (and a token for a
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
`notion/items.ts`, `editor/swipeItems.ts`, the recorder; the first two are now in `src/app/plugins/notion/` and the
items in `src/app/core/itemLinks.ts`, as the plugins entry below records):

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
  - `projects/*` and the project picker → `plugins/projects/` (since `src/app/plugins/github/`), which gains a Settings page (repos read, Forget,
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
  still counts without the keyword, and still asks. The tips in a pause teach the keyword form. (The row went with its
  preference in §136, voice/no-keyword: a command needs no keyword now. §138 streamlined the page it was on.)

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

## 40. The review after a recording (2026-09-14, 1.1.0, native generation 13)

Matt: "Show the AI reasoning dissecting and parsing the note after we hit stop, use slower more detailed models to
check if the fast model got stuff right and work with the user to resolve and commit". He chose a review screen
right after Stop, all four checks (words, structure, commands, names), and the model's raw thinking over a
narrated checklist, knowing that needed an APK.

- **Stop still saves first.** The note is written exactly as before, and only then does the recorder hand over
  (`ReviewHandoff`): the note, the better-words job the queue would have run, every phrase the fast model heard
  (commands included), what each "Glyph" command did or was declined ("Did: add “Fix the seek bar” to
  HelloTrade’s list", "Offered to …; the person said no"), and the other notes commands changed. Leaving at any
  point loses nothing, and whatever would have run anyway (better words, formatting) is queued as before.
- **Listening again** (`capture/refine.ts` `listenAgain`). The larger speech model runs over this take now,
  with progress, instead of later in the queue. The queue and the formatter are held while the review is on
  screen, since they want the same cores.
- **Comparing words** (`review/diff.ts`). A word-level LCS of the fast transcript against the careful one,
  grouped into runs with context. Case and punctuation are ignored, but "hello trade" and "HelloTrade" still
  differ.
- **Thinking it through** (`review/prompt.ts`, `useReview.ts`). The formatting model, or the largest Qwen on the
  phone, since Gemma doesn't reason, with reasoning ON. It gets both transcripts, the disagreements, the
  commands, the note titles, any note a command changed, any plugin context, and the note last. Its thinking
  streams raw into a monospaced pane that follows the newest line.
  - The native layer used to switch thinking off with an empty thought. `ai_generate` now takes `think` and
    `think_budget`, and reports `thinking` on progress and output. Formatting passes send neither and are
    unchanged.
  - The budget matters: on the Mac the 4B reasoned past 2,400 tokens without answering. Past its budget (700
    for the 4B, 600 for the 2B, 500 for the 9B) the engine closes the thought for it in its own voice ("I have
    thought about this enough; …</think>") and the answer is sampled after. Measured: 787 tokens, 115 s on the
    Mac CPU, one correct finding.
  - `llm::tests::prints_a_review_with_its_thinking` runs the real prompt.
- **Findings, earned** (`review/findings.ts`). The answer is a JSON array, read leniently (fences, chatter,
  trailing commas). A finding is kept only if its check is known, its note exists, and its `find` really is in
  that note (exactly, or with whitespace and case forgiven). A model that invents a problem can't invent a fix.
  Changes are "replace" or "add a line" (a list item joins its list). A replace changes the LAST occurrence,
  since the words just said are the newest.
- **Deciding.** Each finding is a card: the check, which note, what and why, the text struck through and the new
  text. "Use this" is the default, a tap makes it "Keep mine", and Edit changes the new text. "Commit N"
  applies the accepted ones to every note they name. "Keep as is", Skip or Back leave the note alone.
  Without a language model the careful model's word changes are offered on their own.
- **Gated.** `reviewAvailable()` needs native generation 13, the Recording setting "Review after recording" (on
  by default), and an unlocked phone. On an older binary Stop behaves exactly as before.
- `?simulate=review&review` in a browser runs the whole flow with scripted models.

## 41. Test results, in Developer mode (2026-09-14)

Matt: "When developer mode is on add a test suite reporting page like we have on attack fm". It follows AttackFM's
page: a report generated where the app is built, compiled into the page, and read in Settings.

- **The report** (`scripts/test-report.mjs`, written to `src/app/diag/testReport.generated.json`). It runs every
  suite to the end, whatever the others did:
  - the page's Vitest (JSON reporter with task locations)
  - the app's Rust: `cargo test --lib` in src-tauri, which leaves the real-model tests ignored
  - glyph-api's Rust
  Parsing is pure (`scripts/testReport/parse.mjs`, tested with the page), and ANSI is stripped and failures are
  clamped. A suite that ran no tests is an error, never a pass. `--only=` and `--skip=` keep the other suites'
  last results, marked "not run".
- **Matched by code, not by commit.** Glyph ships far more often than it commits, so the report records a
  fingerprint of `src/`, both crates' `src/` and `scripts/` (`testReport/source.mjs`, the report itself
  excluded). `vite.config.ts` stamps the same fingerprint into the build as `__GLYPH_SOURCE__`. The page says
  "The same code this build was made from", or warns that the code changed after the tests ran.
- **Every release runs it.** `deploy-ota.mjs` runs the report before the web build and stops on a failing test
  or a suite that didn't run. `--skip-tests` ships anyway, and that build's page then says its report is from
  other code. This adds about 90 seconds per release.
- **The page** (`settings/TestResultsPane.tsx`, Developer mode only, under Developer):
  - A red or green verdict card, recomputed from the suites rather than trusting the report's `ok`, with Passed,
    Failed, Skipped and Not run (an alarm colour when they aren't zero).
  - Warnings: code changed, no fingerprint, suites that didn't run.
  - Where it came from: version, fingerprint pill, commit (+ changes), when it ran, the machine, the tool
    versions.
  - Find: search on every word in a test's name or file, and "Only failures".
  - One card per suite. Tests are grouped by file (a Rust test's module path stands in for its file), with
    failures first and open, and each failure's output under it.
- First run: 436 passed, 0 failed, 7 skipped (the real-model tests), in about 90 s.

## 42. The library: notes as Markdown files (2026-09-14, 1.3.0, native generation 15)

Matt: "a folder and sub folders full of purely markdown files with a small flat file things like sqlite or json
files for indexing so we can keep our whole library in these files … it should all render to valid markdown but
store metadata we can specially format such as linked notion tickets and to-do lists". He chose a folder he
picks, his own folders with titles as file names, Obsidian-compatible metadata, and a hidden `.glyph` folder.
The format is specified in `docs/LIBRARY.md`. This is phase 1: the library in the app's own storage, behind the
same commands.

- **The page didn't change.** `src-tauri/src/library/` implements the old `Store`'s calls (list, get, save,
  delete, pin, archive, recording, formatted, capture), and `NotesStore` now holds a `Library`. The page only
  gains `Note.path`.
- **Files are the truth** (`library/mod.rs`). Every read of the list walks the folder first. A file whose
  modified time and size match its index row is skipped, a changed one is read again, and a row without a file
  is dropped. Opening a note re-reads its file and re-scans if the file is gone or its body changed, so an edit
  in another app shows up. `.glyph/index.sqlite` (`PRAGMA user_version` 1) is a cache that a version change
  simply rebuilds.
- **Front matter** (`library/frontmatter.rs`) is edited by line, never parsed into a map and re-serialised.
  Unknown keys, comments, lists and quoting stay exactly as written, and a key is only touched when its value
  changes. Values Glyph writes are quoted when YAML would misread them.
- **Names** (`library/names.rs`). A title is the first line of words with its Markdown gone: heading and quote
  marks, list and task markers, link addresses (their words stay), pictures, emphasis and bare URLs, and a
  trailing item mark like `[notion](…)`. The first move on the emulator named a file
  "- Buy milk(httpswww…).md"; now it's "Buy milk on the way home….md". Characters a file system refuses are
  dropped, names are cut at 80 characters at a word, and clashes get " 2". Saving under a changed title renames
  the file, and the id in front matter keeps it the same note.
- **A pin is not an edit.** Pin and archive rewrite only front matter, then set the file's modified time back
  (`File::set_modified`), so the list order doesn't jump.
- **Copies.** A file carrying an id that another existing file already has gets its own id, so a copy made in a
  file manager is a second note rather than a fight over one row.
- **Drafts.** The page saves a new note the moment + is tapped, so a backgrounded webview can't lose it. With
  files, every note opened and left became "Untitled N.md". Only words are worth keeping that way, so a blank
  new note is now a draft in native memory, and the first save with words writes its file. A note this run
  started as a draft goes back to being one if all its words are removed and nothing else was set. An earlier try deleted empty notes from the page on the way back, but the editor's last save
  isn't awaited, so it could race a note just typed in. Deciding inside the library, under its lock, can't.
- **Moving in** (`commands.rs` `open_library`). The first launch writes every old note to `Inbox/` with its
  front matter, sidecar and original modified time. Notes with no words and nothing set are skipped, since the
  old app's save-on-open left them behind. `library.json` records the move, and only then are
  `glyph.sqlite{,-wal,-shm}` renamed `.moved`. A move cut short is finished next launch, because a note already
  in the library is never written again.
- **`Vault`** (`library/vault.rs`) is the only thing that touches files: list, read, atomic write (a `.part`
  beside the file, renamed), rename, remove, stat, keep modified time. Paths are relative with forward slashes,
  and `..`, empty segments and absolute paths are refused. Phase 2's folder picker will be a second `Vault` over
  the Storage Access Framework.
- **Checked on the emulator** with a backup of its old database, moved in twice (before and after the skip). 9 notes moved in as 8 files plus
  one skipped empty note, with 6 sidecars. The pinned group, the order and "1 HR AGO" were unchanged. An edit
  renamed its file and kept its id. A new note left empty wrote nothing, a typed one wrote
  `Inbox/Draft check note.md`, and clearing it removed the file.
- Tests: `library::tests` (11), `library::frontmatter` (5), `library::names` (4).

## 43. Workspaces (2026-09-14)

Matt: "add workspaces so we can sort notes by a given workspace."

- **A workspace is a name, and a note is in at most one.** Kept on the page under `glyph-workspaces` (core/workspaces.ts), so it ships over the air: the note store is Rust's SQLite, and a column there is a native change. Nothing is shown while there are none, so a list that never uses them looks as it always did.
- **The list.** Once one exists, a row of outlined names sits under the title (notes/WorkspaceBar.tsx): All, then each workspace, then + for another. The chosen one is solid ink, the list shows only its notes, and the choice is remembered, so the app opens where it was left. Tapping the chosen name again opens its sheet (notes/WorkspaceSheet.tsx): rename, or remove. Removing unfiles its notes and deletes nothing. The archive is never filtered: it is the place to find anything.
- **The note's cog.** A Workspace row under Pin and Archive says where the note is; its page (editor/WorkspacePicker.tsx) lists the workspaces with the note's own ticked, a name for a new one that files the note there as it is made, and a way out of the one it is in. The first workspace is made here as often as on the list.
- **A note made while a workspace is chosen is filed there**, typed or spoken (App.tsx): the list the person is looking at is where the new note should appear. A spoken note that is already filed stays where it is; in memo mode the take goes on the last spoken note, which may live elsewhere.
- Deleting a note forgets its filing (notes/useNoteActions.ts), and so, now, its kept summaries and gist. Reset clears the key.

## 44. A ticked box when Notion says done (2026-09-14)

Matt: "Notion items that are done should automatically update the checked status of the checkbox for the item they're listed in."

- **editor/doneSync.ts** watches the mark details the pills draw (core/markDetails.ts) and, when a to-do line ends with a mark whose task reads as done, changes its `[ ]` to `[x]`. An edit to the note, saved like typing, and not in the undo history: undoing a keystroke should not untick a task that Notion says is finished.
- **Only that way round, once per change of the task.** The tick is answered to the task's last-edited time; a box unticked by hand stays unticked until the task itself changes again, so the note never fights the person holding it. A task in Notion's trash does not tick.
- Nothing new is read: the pills' own reads (editor/links.ts) are what arrive, for the marks in view while the note is open, every minute and on return.


## 45. Working through the Glyph Tasks board (2026-09-14)

Matt: "Take a look at the tasks in the Glyph task management board I've created from within Glyph, work through them and let me know as you do so I can ensure they're tracking in app correctly. When an item is linked to notion it should show a few key details". Each card was moved to In progress when started and Done when verified, with a note saying what changed and whether it needs an APK, so the pills in his notes show the board changing. The first update banner card was closed as already done by the white foil card (§29b), and duplicate cards were closed with their twin.

### 45a. What a Notion task is doing, in the note

- **Details are read back** (`core/markDetails.ts`, `plugins/notion/details.ts`). The editor asks by a mark's name and address, and the plugin that owns the name answers through a provider registered with its extension point (`GlyphPlugin.marks`). A switched-off plugin answers nothing.
  - The Notion provider reads `GET pages/{id}` through `notion_request`, so no new route or login was needed.
  - The status stage comes from the board's own status groups (`GET databases/{id}`, once per board), so "Shipped" is done wherever the board says so. A name guess is the fallback.
  - The pill's facts are a priority-like select and a due-like date ("Overdue" until done).
  - Two reads at a time; fresh for 45 seconds.
  - The last 300 answers are kept (`glyph-notion-tasks`), so an offline note still shows the last status.
  - Signing out forgets them.
- **When it reads.** On opening a note, on coming back to the front, and every minute while a note is open, for the linked lines in view (`editor/links.ts`).
- **First as one pill**, then reworked on Matt's next note: "Not all notion links are being auto formatted to have the full pill showing details … might need multiple pills … maybe consider a card."
- **A row of pills under every linked line** (`editor/linkedRows.ts`).
  - Which lines: an item ending in a mark, an old-style `[words](notion link)` item, or a Notion link in a sentence (`MarkDetailsProvider.reads`).
  - What it shows: the service's name (solid), the stage ring and status, and one pill per fact.
  - It hangs at the item's own indent (`--hang`). The mark at the end of the line draws nothing while the row carries it; on the caret's line it is written out in full as before.
  - Block widgets must come from state, so the rows are a StateField over the document, rebuilt when the document changes, details arrive (`detailsArrived`), or a menu opens.

### 45b. The menu that splits the note open

Matt: "tap on the notion pills to show a few options like opening the ticket in notion or un linking or updating etc. Make these context menus split text in place … splitting the page right where it needs to go and make the options typography and iconography heavy so they fit the theme on all context menus."

- **A tap on a row opens a block widget under it** (`editor/MarkMenu.tsx`, a React root inside the widget via `markMenuMount.tsx`).
  - The lines below move apart and the gap is paper-2 across the width, with its edges shaded like a cut. It grows open (`grid-template-rows` 0fr to 1fr).
  - Contents: the stage and status, the title set large, every property in two columns, and when it changed and was read.
  - Then full-width rows, each a ringed Lucide icon beside a word at xl semibold:
    - Open in Notion.
    - Mark done in Notion / Reopen: the board's first done or to-do status, or its Done checkbox.
    - Use these words as its title, when the item's words differ from the task's title.
    - Refresh.
    - Unlink: the mark or link comes off the line, and the words stay.
  - Menu actions report through the note's own sentence line (`NoteEditing.say`).
- **It closes** on a touch outside, the back gesture, another tap on the row, or an action that changes the line.
- **The press-and-hold menu took the same hand** (`editor/ContextMenu.tsx`): an icon over each word in bold, in a rounded band. It still floats above the selection, since splitting the page would move the text being selected.
- The floating card that briefly did this job (MarkCard) is gone.

### 45c. The note page, the keyboard, and the status bar

- **The tape scrolls with the note** (three cards). In the Write view, the tape row and the editor are one scrolling `.page`, and the header stays put. The editor grows with its words (`Editor` `grow`: height auto, and the scroller doesn't scroll or hold its overscroll, one class more specific than glyphTheme). The Formatted and transcript views keep their own scrolling under a fixed tape.
- **The keyboard covered the page** (two cards). Measured on the emulator: on Android 15+ edge-to-edge, `adjustResize` no longer shrinks the window, so a tapped line near the bottom stayed under the keyboard even while typing.
  - `MainActivity.fitAboveKeyboard` pads the WebView's parent frame by the IME inset, so the page sees an ordinary resize.
  - The listener sits on the frame, never the WebView. Set on the WebView, it replaced Chromium's own listener, `env(safe-area-inset-top)` went to 0, and the header slid under the clock.
  - The editor keeps the caret in view on any window or visual viewport resize.
  - Native generation 15; the page half works without it.
- **The status bar.** A fixed scrim of paper colour under the status bar fades out just below it (`app-statusScrim`, zero height where there is no bar). `GlyphHost.setLightChrome` makes the bar icons follow Glyph's Light/Dark setting rather than the phone's (preferences.ts calls it, and again when System follows a change). Native generation 15.
- **Scroll fades** (two cards: "gradient blur and fade … dont show when on top and bottom of scroll").
  - `art/ScrollFades.tsx` puts two fixed bands over a scroller's edges, each a 3 px backdrop blur masked by a gradient under a veil of paper.
  - Visibility is an attribute set from a passive scroll listener, so scrolling renders nothing.
  - Used on the note page (top and bottom) and the home list (top; the dock already fades the bottom).

### 45d. Colour, voice and touch

- **Seeded cassette colours** (`tapes/tapeColour.ts`). An FNV-1a hash of the note's id picks one of eight shells (tomato, tangerine, mustard, sage, teal, cobalt, violet, rose) and nudges its hue by up to six degrees. All share one oklch lightness and chroma, so every shell reads on black paper and white. Only the shell, print and wound tape take the colour; the label stays paper and ink. The id is for life (front matter), so a note keeps its colour through renames and on every phone.
- **The rings follow the voice** (`capture/voiceLevel.ts`, `SideKeyWaves.tsx`). The recorder publishes the microphone level, and `paceRings` sends rings out of the side key's glow.
  - In silence, one faint ring every 2.7 s.
  - Talking, one every 220 to 580 ms, each wider, brighter, thicker and quicker the louder the voice.
  - Rings are created and animated directly with Web Animations, capped at nine, with no React renders. Reduced motion keeps three still rings.
- **Feeling a detent coming** (`core/detentFeel.ts`). While a swipe closes on a detent (the list row's Pin/Archive/Delete, and a list item's swipe to Notion), light ticks come faster as it nears: none in the first third, then 240 ms apart down to 40 ms. Then comes the firm click of arriving, and nothing while backing off. The item swipe also gained the arrive and back-off clicks it never had.

### 45e. "Glyph", while Glyph is open

Matt: "While Glyph is open I should be able to say the AIs wake word in order to make it start transcribing and updating notes as requested." This reverses the pause of 2026-09-13 for the in-app case only; there is still no background hotword.

- **When it listens** (`capture/useWakeWord.ts`): the list or a note is on screen, no settings or guide is open, the keyword and the new "Listen for “Glyph” while it's open" switch are both on (on by default), and the voice model is already on the phone (it never starts a download).
- **What it costs** (`capture/wakeWord.ts`).
  - In quiet, only the level is watched and the last 1.2 s are held.
  - 400 ms of voice starts a Whisper session on the held audio, and each partial is looked through with `findKeyword`.
  - Speech that ends (1.2 s quiet) or runs past 7 s without the keyword is cancelled, samples and all.
  - Everything stays on the phone. Android shows its microphone dot while Glyph listens.
- **The hand-over.** Hearing the keyword cancels the session and leaves the open microphone and everything since the speech began (`takeWakeHandoff`). The recorder opens (`woke`, aimed at the open note if there is one), rebinds that microphone to its own handlers, and transcribes the held audio first. What came before the keyword in its first phrase is dropped, since that talk wasn't for Glyph. The command and its "shall I?" follow as always.
- **One Whisper session at a time.** A listener stopped while its session was still starting would cancel it on arrival, possibly after the recorder had started its own. The recorder therefore waits for `wakeSettled()` before `capture_start`, and whoever stops or wakes the listener owns cancelling a starting session.
- **The permission loop.** Asking for the microphone puts Android's permission activity over the app for an instant, which hides the page. The first build stopped on that hide and started again on return, round and round, and the emulator ended up with the microphone denied "don't ask again". Now a hide only lets the microphone go after 2.5 s, and a failed start isn't retried until the conditions change.
- **Checked on the emulator**: the listener holds the microphone on the list, an ordinary recording starts beside it, and it picks the microphone back up after Discard. The spoken hand-off needs a voice and was left for the phone. `wakeWord.test.ts` covers the pacing.

## 46. A note wears its links (2026-09-14)

Matt: "There should be some kind of indication if a note is linked to a given notion board or git
project." The only place that said so was the cog sheet.

- **`NoteLink.linked(noteId)`** (`plugins/types.ts`): a link names what the note is linked to
  ("Glyph Tasks", "attackfm/app") or null. The registry's `linksOf(noteId)` collects them from the
  plugins that are on, and `useNoteLinks` keeps a component current: the plugin host now announces
  every write to a plugin's storage (`onPluginStorage`), which is where links live.
- **`plugins/LinkMarks.tsx`**: the plugin's mark in a ring with the name beside it. On the note, a
  row under the tape that opens the cog sheet; on a list row, the marks alone after the time, the
  names in the accessible text. Nothing is drawn for an unlinked note or a plugin switched off.
- **Staging build** (`GLYPH_STAGING=1 npm run android:build …`, `gen/android/app/build.gradle.kts`):
  the same code as "Glyph Staging" under `com.mattssoftware.glyph.staging`, beside the real app with
  its own data and no update checks (`ota.rs` `STAGING`, `UpdateCheckWorker`), so a build can be
  walked through as a new person sees it. `src/channel/<production|staging|dev>/res` carries the one
  resource that differs, the launcher shortcut's target package. `GLYPH_CHANNEL=dev` is the third app,
  "Glyph Dev" (`com.mattssoftware.glyph.dev`), for `tauri android dev`: a debug build whose page comes
  live from the Mac's Vite server and hot-reloads as the code changes, for working on the phone with
  Matt in the room.

## 47. The first page: waves from the side key (2026-09-14)

Matt: "research the rough position of the button on all modern flagship phones, create that list in a database, and on the 'Hold. Talk. Done.' first page have waves emanating from that button spot, but don't do anything to prompt the user to press it yet. Change the text to target telling the user that you hold and talk and the app writes clean markdown using local LLMs that don't kill baby seals or pollute the ocean; we can use quirky fun branding here."

- **Where the key is** (guide/sideKeys.ts): a table of current Android flagships, each with the edge the side key is on, seen from the front, and how far down the phone's height its middle sits. Rough, read off the phones; makers mostly agree on the right edge a little above the middle, below the volume rocker, and differ in one thing: Google puts the power key above the rocker, high on the right, and Sony puts it dead centre with a shutter under it. A phone is known by the model in its user agent (`SM-F971U1`, `Pixel 10 Pro`, `CPH2649`), failing that by its maker (`deviceMaker`, `Build.MANUFACTURER`), failing that the common case. `onScreen` moves a point on the phone to the screen: the display starts a little way down and ends a little short of the foot. The same list lives in Matt's Notion as the database "Side keys on flagship phones", to edit as phones come and go; the app carries its own copy because the guide runs before anything is signed in.
- **The waves** (guide/SideKeyWaves.tsx): four hairline rings of ink, centred on the screen's edge at the key's height so only their inner half shows, widening one after another to a third of a screen and fading before they reach the words. Behind the page (a negative z-index in the guide's stacking context: above its paper, below its content), no touch, nothing pointing, no word "press": the key is there and the page knows it, and that is all it says. Under reduced motion two rings sit still and faint.
- **The words.** "Hold. Talk. Done." stays. Under it: hold the side key and talk, and Glyph writes it up as clean Markdown; the writing is done by small language models on the phone that never phone home, no cloud, no server farm boiling a lake, no baby seals harmed, no oceans polluted. The setup line that was there ("two things to set up") is gone; the pages that follow do the setting up.

## 48. Words from smoke: the Wisp component (2026-09-14)

Matt picked Wisp from the Apparition Type playground (letters bent by SVG turbulence that stills as
each one sets) and asked for it "added to our text component through a helper", "character by
character", able to "swap around entire words", for the guide's first page.

- **`art/wisp.ts`**, pure and tested: a text is words and gaps; a change from one text to another is
  the longest common run of words kept in place, the rest leaving and arriving (a word that moved
  leaves and comes back rather than sliding); letters arrive at a hand's cadence (uneven, a breath
  after a comma, longer after a full stop) and leave from the last letter, quicker.
- **`art/WispText.tsx`**: the component. Its letters are its own DOM under a requestAnimationFrame that
  runs only while something settles; each settling letter has its own filter from a pool capped at
  48 (two letters sharing one flickered), a wide filter region and sRGB interpolation, as the
  playground found. The first `text` types itself in (or is simply there with `still`); each later
  `text` is a word-level swap: out, then in. Reduced motion shows the text at rest and fades changes.
  A screen reader gets the whole text once; the letters are hidden from it.
- **`art/useWisp.ts`** `useWispCycle(texts, holdMs)`: a line that keeps changing, for the headline.
- **The blank list after Skip** (seen once on the emulator): `useNotes` now retries a failed first
  read and re-asks once when the phone's first answer is empty, and the guide's close refreshes the
  list.

## 49. The first page, again: a heads-up that there's AI in here (2026-09-14)

Matt: "redo the first slide, it should be a heads up page that we use AI but say that it all runs on local models on your phone then we're going to do three funny anti AI animations with simple SVG elements like 'no dying baby seals' 'no datacenter water' then make one about it not helping prevent you from being stupid … that ones on you be funny and a bit adult sassy mean … a flashing no symbol then a seal getting bonked on the head with a club then like no symbol again then sludge nasty water turning toxic green with a gradient … heavy iconography and micro animations and color". This replaces §47's words and hero. The side key's rings (§47) stay behind the page.

- **Top of the page: the gags** (`guide/AntiAiStage.tsx`, words and order in `guide/antiAi.ts`). Beats go round:
  1. The no symbol slams in and flashes twice, with the gag's title under it.
  2. Its scene plays, with the punchline.

  Each beat is one React render. Every movement is a CSS animation over `--beat` (the beat's length), with parts turning about points in the drawing (`transform-box: view-box`). A beat only advances while the page is visible.
  - **"No dying baby seals."** A seal on an ice floe. A club on a blue sleeve winds up and lands at 34%: a BONK burst, X eyes, a lump, and stars going round. "Nobody got clubbed so you could write a grocery list."
  - **"No datacenter water."** A datacenter with blinking racks, steaming, pipes a lake dug into the ground. The lake's gradient stops turn from clear blue to sludge green, the fish goes belly up with X eyes, then stink lines and a skull. "No server farm drank a lake and spat it back out glowing."
  - **"No thinking for you, either."** A phone beams answers at a head. Its brain's wrinkles erase one by one, it shrinks to a pea and rattles, and the face goes cross-eyed and slack-jawed. "It won't stop you going soft in the head. That one's on you, sweetie."
  - Under the scene: a coloured badge per gag (blue, green, pink) with its Lucide icon, and a red ban flashing over it during the no beat.
  - With reduced motion, the three are listed still, each badge with its ban.
- **Then the heads-up.**
  - The headline "Heads up: there's AI in here." typed out of smoke (WispText, a size below the display face).
  - One sentence: every model runs on the phone, so nothing said goes to a cloud, a company, or anyone.
  - Four promises as coloured icon pills that pop in one after another, their icons wiggling now and then: Runs on your phone, No cloud, Works offline, Nothing sent anywhere.
- Checked at phone width in the browser by pausing each scene's animations at their moments: the bonk, the toxic lake, the shrunken brain. `antiAi.test.ts` holds the order and the words.

## 50. Wobbly waves, the microphone, and "Not yet, finish reading." (2026-09-14)

Matt, later the same day: "remove showing the glyph logo on the first page, make the pulsing waves wobbly and have them react to the phone's microphone, if the app is relaunched we can assume they hit the button on the side too early so reload with a warning about it being too soon but fit the ghostly theme without being cheesy, just be a bit sassy. Maybe just 'not yet, finish reading.'"

- **The logo** was the first page's hero art; it went with the page's redo into the AI heads-up (§47's Welcome was reworked on its own), so nothing more to remove.
- **The waves** (guide/SideKeyWaves.tsx, guide/waves.ts) are drawn on a canvas now, since they are no longer circles: three slow sines around each outline make it waver like something seen through water rather than shiver. At rest one faint ring every 0.95 s; a voice sends them out closer together, wider and brighter, with a bigger wobble, the level eased frame by frame so a word does not make a ring jump. Frames stop while the page is hidden. Under reduced motion two rings sit still.
- **The microphone** (guide/micLevel.ts) is a small listener of its own, loudness only, closed the moment the page leaves. The guide never asks for it: the first screen of the app should not open with a permission dialog, and the recorder asks when there is a reason to. So the rings listen where the microphone is already allowed and keep their beat everywhere else: a fresh install until its first recording, and the hot-reloading dev build, whose plain-http page has no microphone at all.
- **Too soon** (guide/tooSoon.ts, guide/TooSoon.tsx). The guide notes that it has started and which page it is on; both go when it is finished. A launch with the guide unfinished and left on a reading page (before the side-key page) is someone who held the key on page one: the app comes up on the guide again, one line typed out of smoke at the top of it, "Not yet, finish reading.", and a side-key launch does not record. The key held while the guide is open on a reading page does the same. From the side-key page on, a press is what the page asks for, and it records as before.

## 49. Marks from plugins, a secret in smoke, and the sample note

Matt: "add a default note with every kind of markdown formatting and table and image and everything we support,
add support for additional formatting characters through plugins and add spoiler as one which gives text an
extreme wisp effect when it's between two pipes || ||". Then: "we need a button up top to see all the formatting
symbols, it should split the UI open under the top bar with a wispy fade and then render in a row of formatting
controls we can scroll through horizontally".

- **A plugin can add an inline formatting** (`plugins/types.ts` `InlineFormat`): a node name, a delimiter run of
  one to three of a character Markdown doesn't already use, and a look. The editor's markdown
  (`editor/language.ts` `inlineFormat`) parses each switched-on plugin's formatting the way GFM parses `~~`, with
  the same flanking rules, into a node holding two marks and the words; the marks take the dimmed marker style
  every delimiter has, so nothing is hidden (§3.2). The look is drawn by two small view plugins, not the
  highlighter: `formatLooks.ts` puts a plugin's CSS on the words of a `style` look, and `wispFormat.ts` puts each
  letter of a `wisp` look in smoke. The registry checks the shape at start and refuses a delimiter like `**`.
- **The Spoiler plugin** (`plugins/spoiler/`, since folded into `src/app/plugins/marks/`) is one formatting and nothing else: `||the key is under the
  stone||`. Every letter between the pipes is bent, blurred and half-there, a dozen SVG filters shared round the
  letters and animated together at about thirty steps a second while any smoke is on screen, so the words can't
  be read; put the caret in them and they settle to plain text for editing, leave and they smoke over. Reduced
  motion keeps the smoke still, and still hiding. A read-only note never clears. The letters are plain inline
  marks carrying a filter, as the recorder's arriving words are (§48), so kerning and wrapping don't change.
- **Styles, from the press-and-hold menu** (`editor/ContextMenu.tsx`): a bar of symbols split open under the top
  bar came first and was taken out (Matt: "it doesn't look good as is, maybe it needs to be something we do by
  pressing and holding on text"). Holding on text opens the note's menu, and its Style word turns the menu over to
  the formatting in the menu's own hand, icon over word: the marks that wrap the selection (Bold, Italic, Struck,
  Code, then each switched-on plugin's, so Spoiler sits after them), the forms a line takes (Heading, Quote, List,
  Numbered, To-do), and the inserts (Link, Table, Rule; a picture stays Add image on the first page), in one band
  that scrolls sideways with a little room between the three kinds (three stacked bands "looks a bit strange"; a heavier rule read as "two pixels thick"). A long press on empty paper places the caret and opens the menu there. A style
  pressed wraps or unwraps through `editor/format.ts`, stays on the menu lit in reverse while it applies, so a word
  can take two in one go; an insert closes the menu. The styles come in out of smoke along each band; Back returns.
- **The sample note** (`core/sampleNote.ts`, `core/seed.ts`): one note with one of everything, headings to
  spoiler, a table, a fenced block, a rule, and a picture drawn on the spot (an ink cassette letting off smoke,
  rendered through a canvas into the library's pictures like any pasted one). A fresh library gets it once, a
  few seconds after the first read comes back empty; a library with notes is marked done and left alone, so an
  update drops nothing on anyone. Settings > About > Add the sample note makes another on request. The test
  parses the note and checks every node the editor knows is in it.
- **The marks page** (`guide/Guide.tsx` `Markdown`, `guide/phrases.ts`): the guide's "Talk in markdown" page became
  a rundown (Matt: "a quick rundown of markdown, our special symbols, and how to trigger each with voice"). Three
  lists: every spoken cue with the mark it writes beside the words to say and an example written by the real rules
  (`symbol` on each `PhraseGroup`, pinned by guide.test.ts to appear in its example); the marks that are typed only
  (`TYPED`); and the switched-on plugins' own marks, with the spoken cue where the plugin names one (`InlineFormat.cue`,
  the Spoiler's "spoiler … end spoiler"). The sample note's picture is Jocelyn Morales's smoke from Unsplash
  (docs/THIRD_PARTY.md); the drawn cassette was "quite ugly".
- **Six more marks** (`plugins/marks/index.tsx`), each its own plugin of one formatting so any can be switched off,
  made through one `markPlugin` helper (Matt: "i like all of these, add them each"): `==highlight==` (an ink wash),
  `%%aside%%` (smaller, muted, leaning), `??unsure??` (a dotted line under a doubt), `@@redact@@` (a solid bar,
  lifted while the caret is in it: `FormatLook` grew `clearAtCaret`, and `formatLooks.ts` follows the selection
  when any look lifts), `^^shout^^` (spaced small caps), `++added++` (a line under, the pair of `~~struck~~`). Each
  names its spoken cue and a line for the guide (`InlineFormat.about`); the sample note shows all six.
- **The home page from smoke** (`notes/NotesList.tsx`, `art/WispText.tsx` `delay`): "Notes" types in at a hand's
  pace and the first eight titles follow, quick and each a beat after the last (Matt: "offset them slightly so each
  animation looks special but doesn't take all day"); rows past the eighth are simply there, since the cost is a
  filter per settling letter. `WispText` gained a `delay` for its first text only; the row title's clip box has
  padding inside its margin so a bending letter isn't cut at the line.


## Memo mode sorts: the scratch page (2026-09-15)

Matt: "when I tell it to add a note to a list by a given title I want it to add to that list, but it just gets left on whichever note was last open. Change memo mode to write to a scratch file that's not real until the memo is done, then the AI can figure out how to sort." He chose: show the sorting and commit it; a blank scratch page while talking; without a model, the rules file the commands they know and the rest becomes a new note.

- **The scratch** (`capture/scratch.ts`): with Memo mode on and the recorder not aimed at a note, the take is written to the page's own storage a second at a time, not to a note, and the recorder shows a blank page headed "Memo · sorted when you're done". The recording is kept under the scratch's id. A scratch left by a take that never finished, a memo ended over the lock screen, or one left with Back waits on the list as "A memo is waiting to be sorted".
- **Sorting** (`sort/`): the reasoning model reads the memo beside the person's note titles (`sort/prompt.ts`) and answers with placements, each a note, what to add, and the memo's words it came from. Every placement must name a real note and quote the memo exactly (`sort/plan.ts` `readPlacements`), and the rules (`rulePlacements`, the recorder's own `planCommand`) add any plain "add X to Y" the model missed, so an explicit command is never lost. Without a model, only the rules sort.
- **The screen** (`sort/SortScreen.tsx`, the review's styles): each placement with Use this or Skip, and under them the new note that what's left becomes (`leftover`). Commit files the kept placements through `placeWords` and saves the rest as a new note carrying the recording; "Keep as one note" skips them all. Nothing is written before Commit.

## Memo mode picks a note first (2026-09-18)

Matt: "I want to rework how the local AI works to make things a bit easier to flow. I want memo mode to have the
first step selecting a note - ask for the title of the note and show a few recent options and get a partial match -
take a keyword as 'select note <note>' or 'use note <note>' or other variations. Then after a note is selected we can
use words like 'add task' as a trigger word, then the screen should say 'adding task… what task should we add?' and
we speak the task."

This reverses "Memo mode sorts: the scratch page" above. A memo used to be dictated onto a blank page and sorted
into notes by a model when it ended; now it opens by asking which note, and everything after that has somewhere to
go as it is said. The scratch page and the sort (`capture/scratch.ts`, `sort/`) are no longer written by the
recorder; a scratch left from before still shows on the home page and can be sorted.

- **Which note** (`capture/memoFlow.ts` `parseChoice`, `chooseNote`). The recorder's card asks "Which note?" and
  lists the five most recently edited notes, numbered. A note is named with a word in front of it - "use note
  groceries", "select the work note", "open weekend trip", "go to my groceries list" - or bare, or by its place,
  "the first one", "number two". The name is matched the way every spoken name is (`route.ts` `matchNote`), and
  more leniently after "use note", since the word said it was a name; a bare phrase that only half fits a title is
  taken as a miss, not a choice. As the name is said the note it seems to mean is drawn in ink in the list
  (`guessNote`). A name that fits nothing is said so ("No note called 'camping'. Which note?") and the card keeps
  asking; a name two notes fit about as well shows those two, so "the first one" settles it. "New note" starts a
  fresh one, and "new note called camping" starts one already titled. Over the lock screen the list is not shown
  and the note is not named, as before.
- **Then the note is the page.** Choosing puts the recorder on that note as its own Speak button would: its text
  above, the words said written onto its end, "Adding to 'Weekend trip'" in the top line. Plain talk is dictation,
  every cue works, and "Glyph, …" commands still reach other notes.
- **Trigger words** (`parseTrigger`), at the start of a phrase, ask for one thing: "add task" (or to-do, check box),
  "add item" (bullet, point, entry), "add a line" (note, paragraph, sentence). The card says "Adding a task - What
  task should we add?", the next phrase is the task, and it goes into the note's list (`listAppend.ts`
  `placeWords`, so it joins the list the note has, in its style, or starts a to-do list); a line asked for is its
  own paragraph, however short, where "leave a note for …" would have put a short one in the list. **No "shall I?"**: the
  trigger and the question were the asking, which is what makes it flow; "undo" or "scratch that" takes the last
  thing back. Said in one breath - "add a task: buy milk" - it goes straight in. "Add tasks" takes each phrase as
  one until "done" or a pause. "Never mind" drops the question. "Switch note" (or "switch to work") and "new
  note" leave what was said on the note it was said for and carry on elsewhere (`take.fork`).
- **A phrase that opens like a command is read by the rules first** (`opensLikeCommand`): "add eggs to groceries"
  names a note and asks as the keyword's commands do; "put the kettle on when we arrive" names nothing and stays
  words. The trigger words are Glyph's only where the recorder is in the flow, so a sentence in an ordinary
  recording is never read as one.
- **The take runs it** (`capture/take.ts`, the `flow` step and `FlowView`), so the voice suite tests it from
  scripts like everything else (`voice-tests/suite.json`, the "Memo flow" group, `prefs.memo`). The recorder draws
  it as a card in the place the table's questions and the "shall I?" card take (`FlowCard`), and the top line's
  "New note" becomes "Switch note".
- **Two things came right underneath.** A command that changed the note being recorded onto used to apply its
  change to the stored note, which already held the words a draft had saved, and set that as the base the next
  draft composed the words onto: the words appeared twice. The change now goes into the note as it was before this
  take, and the words follow it (`CaptureScreen.tsx` `updateNote`). And every write to a note - a command's
  change, the draft, the take carrying on elsewhere - now goes through one queue, since two close together read the
  same body and the second lost the first.

## The card is the note, small (2026-09-18)

Matt: "the preview for the formatting should use the same formatter that the actual note uses instead of custom
rolled small stuff like the checkboxes are weird for example." Then: "don't render boards in previews", "the
background and stuff should be transparent on the formatted preview", "the preview is rendering the whole note not
just a small preview".

- **The card holds the note's own editor** (`notes/NotePeek.tsx`): the same `Editor` the note opens in, read-only, in
  the formatted view, at 0.62 of the note's type (`--app-body` and the heading sizes redefined on the card, so the
  ratios hold), given the note after its title (`notes/peek.ts` `peekMarkdown`, fourteen lines at most) and clipped
  to about six lines in its own em, with a mask fade on the last line only when there is more below. The card is a
  button, so the editor takes no pointer events. It replaces the hand-drawn miniature (`notePeek`, since removed),
  whose six-pixel box for a to-do was the "weird checkbox".
- **Peek mode** (`Editor`'s `peek`): the same formatter, but nothing that fetches, polls or acts - no link preview
  cards, no Mermaid, no board drawing, no tap-to-tick, no Notion reads for the marks (`shortLinks({ still })` draws
  them from what is known). A board's fence is left out of the markdown too: its items follow and are drawn as the
  list they are, the blank lines around the cut close to one, and an item's anchor is dropped - it is the name a
  board calls the item by, never part of what it says (BOARDS.md), and on a card it took a line of its own. The
  editor's paper and a code block's or a table header's fill are transparent on the card, and the page gutter is
  zero there, so a list's marker still hangs where the note hangs it (with the gutter simply zeroed on the line, the
  marker hung outside the card and was clipped: the `- [x]` was in the DOM and not on the screen).
- **An editor costs about 25-30 ms** on a Mac in the dev build (a bare CodeMirror view 8, the formatting extensions
  most of the rest), and the sidebar's tree has one card per note, so a card draws its editor only when within
  400px of the screen, one at a time in its own task so the page paints first, and drops it for a blank of its
  height once it has scrolled well away. Measured with a hundred previews in a scroller: five editors exist at any
  moment.

## Claude on the account: the MCP server (2026-09-18)

Matt: "make an MCP plugin for Claude so I can use Claude to remote control my account and add and update notes as
well as read them, be detailed and make sure it all works for every user". docs/MCP.md is the whole of it; the
choices, briefly:

- **It is a device, not a backdoor.** Synced notes are end-to-end encrypted, so anything that reads them holds the
  account key. The MCP server (`mcp/`) runs on the person's own computer, started by Claude, signs in with the
  password once, unwraps the key there with the same code the app runs (`core/sync/crypto.ts`, bundled in), and keeps
  what a signed-in phone keeps - the token, the key, a signing key of its own for renewing the session - in a file
  only they can read. The service sees nothing new. This was the question to settle first, and this is the answer.
- **The wire is the app's wire.** The same sealed payload under `note:<id>`, the same feed and cursor, the same `base`
  on every write, and a 409 handled the app's way: never written over, shown to Claude as the other device's words.
  The e2e test runs the app's own `syncNotes` as the phone against the built server, so the two cannot drift apart
  without a test going red.
- **Append is the app's append.** `append_to_note` uses `capture/listAppend.ts` `placeWords`, so a task Claude adds
  joins the note's list in the list's own style, as a spoken "add task" does.
- **One file to run.** esbuild bundles `mcp/main.ts` with everything under `src/` it reaches and the MCP SDK into
  `mcp/dist/glyph-mcp.mjs` for Node 20+, published beside the app (`deploy-ota.mjs --mcp`). A person needs Node and
  that file; `login`, then one line in Claude's config.
- **The app's modules it could not reuse as-is** are the two that read the page: `core/account/api.ts` reads
  `import.meta.env` at import, which Node has no such thing as, and `core/store.ts` reaches for Tauri; the client
  carries its own small `call()` and copies of `noteTitle` and `imageNames`, each pinned by a test.
- **Then hosted, at Matt's word** ("run the server on our node so that the user doesn't need to"), with the trade
  put to him first and chosen: the box holds a signed-in person's key **in memory only**, for the session, and the
  sign-in page says so. (Since 2026-10-05 the sessions are also kept across a restart, in a file that holds the key
  only sealed under the tokens Claude holds: docs/MCP.md, "What the hosted server keeps".) `mcp/hosted.ts` is the same tools behind OAuth 2.1 with the SDK's own handlers (dynamic
  registration, PKCE, refresh, revocation), sessions as maps in RAM, and MCP over plain HTTP, one request one
  answer. It runs beside glyph-api as `glyph-mcp.service` on the box's own Node 18, and glyph-api hands
  `/api/mcp` on to it (`server/src/mcp_proxy.rs`): the shared Caddyfile, edited by hand with care, stays as it
  is, and the discovery documents live under that path, where the client library looks once the root ones answer
  404 (which attack.fm's do). The whole flow is tested as Claude's own client library runs it.
- **The sign-in page is the app's** (Matt: "redo the plugin page with better iconography and typography usage"):
  Inter carried in the bundle as a data URL so the page needs nothing from anywhere, the ink scale from ink.css with
  dark as the same page printed in reverse, the Welcome shape on the Blank grid moving as it does in the app, and
  icons drawn on the app's 24 grid - a lock, a key, a door - one to each of the three things a person should know
  before typing a password. The one message it can show is ink with a mark beside it, under the password where the
  eye is, not below the buttons where a phone has scrolled past it. A state is a word and a shape, not a colour.
- **The Claude plugin's page, and the instructions drawer** (Matt: "add the instructions for the MCP to an
  instructions drawer we can open from the mcp page in the app"; then "I also don't see the Claude plugin", so it is
  one - `plugins/claude/`, standard, its switch showing or hiding the page and the page saying so): what it is, the
  address with a Copy, what the eight tools do in words, and where the key lives. Its rows open a card over the page
  (`plugins/claude/ClaudeGuide.tsx`): the steps one way at a time, hosted or on your own
  computer, each command in a block with a Copy, so a phone can hand them to a computer without retyping. It rises
  from the bottom on a phone and floats on a wide window, in the notes card's materials with a scrim under it, and
  closes on the X, the scrim, Escape or the back gesture. Drawn into the body: the settings panes move as they
  change, and a fixed card inside a moving thing moves with it. The words live in `claude/steps.ts`, with the
  addresses following the sync service the build talks to, so a staging build points Claude at its own server.
- **Plugins, redone** (Matt: "revamp and redo the plugins page"): a hero with the count and the one rule (a plugin
  off offers nothing anywhere and keeps what it kept), then a card per plugin that leads with the plugin as a thing -
  its icon in the hero's chip, its name, one line, its switch - then the way to its own page when it has one and is
  on, then what it may reach in one line ("Your notes · The internet (api.notion.com) · Voice commands") with the
  reasons a press away. The old page was a row per permission, which was most of it. "Nothing leaves the phone"
  holds the internet plugins off whatever their switch says, and the page says so at the top and on each card held.
- **Appearance in the kit's own clothes** (Matt: "I want the interface size and themes to use the same UI from
  glacier with the physical representation of the screen densities and colors on the app"): the theme is chosen from
  cards, each the page painted small in that theme's colours - AttackFM's ThemeSelector in shape, with the
  miniature redrawn as Glyph's note page: the bar with its two tabs, a heading, lines, a to-do with its box, two
  segments with the chosen one in the accent, the Speak pill (`settings/ThemeCards.tsx`). Light and Dark are the ink
  scale, chroma zero, with the accent left as a variable so the cards follow the swatch under them; the named themes
  take the kit's own preview, which is what the page becomes under one; System is split down the middle. Spacing is
  the kit's DensitySelector with Glyph's words for the steps. Interface size is five cards, each the same row of the
  app - icon, two lines, a switch - drawn at that step, in em from a font size that is the step, so what a step does
  is seen before it is chosen (`settings/ScaleCards.tsx`).

## 50. The tape only where there is audio

Matt: "Don't show the tape on notes that don't have any audio recorded; the notes with audio recordings added should
show the tape so we can add or remove audio there."

- **A note with no recording has no tape** (`tapes/NoteTape.tsx` renders nothing without one, and `editor/NoteScreen.tsx`
  drops the row). Talking into such a note is a ringed mic in the header, beside the robot and the cog, so it stays
  one tap away; the side key still clears the stage for a fresh capture as before.
- **A note with a recording has the tape**: the cassette and Play as before, and under Play two quiet words, Add
  (the recorder aimed at the note; the take is appended to the tape) and Remove.
- **Remove** forgets the recording's length and phrases (`set_note_recording` with null, native generation 6, so no
  new APK), and the tape goes at once with a five-second Undo that puts both back. The audio file itself stays on
  disk until the note is spoken into again or deleted, which is what makes Undo possible; the recorder now appends to
  a note's file only when the note still has a recording (`capture/CaptureScreen.tsx`), so a take after a Remove
  starts a fresh file instead of landing after the removed audio.


## The voice tutorial: every cue, then tips (2026-09-15; removed 2026-09-17)

Removed at Matt's word ("remove the voice tutorial for now its too long"). The cues it taught are in Settings > Help >
How to talk to Glyph (`guide/phrases.ts`), and the voice test suite (`voice-tests/`, `capture/voiceSuite.ts`) now
checks every one of them against recorded speech, which is what the tutorial's lessons had come to be used for. What
follows is how it was.

Matt asked for a tutorial "at any time for the commands you can say in the app" that marks off lesson by lesson, and
then, on what it was missing: "just learning the voice to markdown commands and tips and tricks".

- **Where it is.** Settings, About, Voice tutorial (`tutorial/TutorialScreen.tsx`). The microphone stays open for the
  whole tutorial through the recorder's own engine, and the session is cancelled, so nothing said is saved.
- **The lessons** (`tutorial/lessons.ts`, `lessonsFor`) come in five chapters. The basics: talk, title, sections, a
  spoken new paragraph, and a paragraph from a two-second pause. Lists: bullet points, a list in one breath, numbers,
  steps, to-dos, and a cue said on its own. Making it stand out: important, bold and italic, quotes, dividers, and one
  lesson for the plugins' spoken marks when any are switched on. Talking to Glyph: sending words to a note, answering
  yes or no, switching notes, and building a table, all against a pretend Practice list. Tips and tricks: pausing
  before a cue, words staying yours, the side key, saying "Glyph" in the app, Memo mode, and fixing a note after.
- **How a lesson passes.** A practice lesson checks what the recorder's rules write from what was really said
  (`renderNote`), or what `planCommand` and `reply` make of it, never the example's exact words. A tip is read and
  ticked with Got it. lessons.test.ts passes every lesson on its own example and checks plain talk passes only the
  first.
- **The screen.** A thin bar per lesson with gaps between chapters, the chapter and place above each lesson, and a
  summary at the end grouped by chapter where any lesson can be tapped to take again.

## A workspace chosen glides to the top

Matt: "When I click different workspaces the page should scroll back up smoothly, not just jump to the top."

The jump was the browser's: the new workspace's list is usually shorter, so the page couldn't stay as far down as it
was and snapped up in the same frame. `useGlideToTop` in `notes/NotesList.tsx` remembers where the page was (as it
scrolls, as a finger lands, and at every render), and when the chosen workspace changes it lends the shorter list
enough room at its foot to stay put for a frame, puts the page back, and scrolls to the top smoothly. The room goes
once the page reaches the top, where it is out of sight, or after three seconds whatever happened. The scrollend from
putting the page back is ignored, since taking the room away then would drop the page before it had moved. Reduced
motion goes to the top at once.


## The Notion opener is a drawer (2026-09-15)

Matt: "The notion opener should open in a drawerer instead of rendering in place." A tap on a linked line's row of
pills no longer splits the note open under the line. The same menu (`editor/MarkMenu.tsx`) rises from the bottom
in the note settings' sheet over the dimmed note: the task's stage, status and facts, its title set large, its
properties, then Open in Notion, Mark done or Reopen, Use these words as its title, Refresh and Unlink. A tap on
the dimmed note or the back gesture closes it, and an action that changes the note closes it. The open line is
still kept in the editor's state (`editor/linkedRows.ts`); a view plugin mounts the drawer over the page while it
is open and takes it down when it closes or the line loses its link.

## Two passes on speech: rules for marks, a model for commands (2026-09-15)

Matt: "it feels like the model for doing the agentic tasks should be different than the language parsing model, we
might need two different AI passes, I can't even pass the tutorial". No model read speech before this: Whisper
(base.en) wrote the words and hand-written rules found the cues and commands in them. Twelve synthesised voices
were run through base.en with the tutorial's phrases, and the transcripts through the lesson checks. The words were
mostly right; the rules missed three things.

- **"end bold" comes back "and bold".** It closed only after a pause at the opening cue. It now also closes when it
  ends the sentence (`capture/markdown.ts`); "bold thinking and bold action" is still prose. Plugin marks too.
- **"Glyph" comes back as anything.** "Gliff", "Gliv", "Glit", "Clith", and in half the voices a real word: "Life.",
  "Live,", "Head life,". The spellings are keywords now, and a sound-alike word counts at the very start of a phrase
  when what follows reads as a command (`findSoundAlike`), so "Life is short" stays words. "New notes" and "new
  node" start a note. "Glyph." leads the Whisper cue vocabulary (native: needs an APK); at the end of the line it
  read as its own sentence and broke carrying a sentence across a cut.
- **The command pass** (`capture/understand.ts`). When the rules can't read what was said after the keyword, the
  phone's language model reads it: after a 1.2 s pause, or at once when the rules named a note that isn't there.
  It answers one JSON object (add, switch, new, table or none); the note must be one of the person's, matched by
  title, and the recorder still asks before anything changes. The chip says "working it out" meanwhile. It runs only
  in a pause, with no words coming in, and is cancelled the moment speech resumes, then asked again at the next pause:
  it shares the phone's cores with Whisper, and the recording comes first. For the same reason it is not loaded ahead
  of time, so the first command of a launch waits for the load. Measured on the Mac on 24 commands as
  speech recognition writes them (`llm::tests::understands_spoken_commands`): Qwen3.5 4B 23 right at about 1.3 s,
  2B 20 at 0.5 s, 0.8B 6. Every miss of 4B and 2B was "none", which leaves the words in the note. 4B runs it when
  it is on the phone, else 2B. Marks are never sent to a model: they stay instant and the same every time.
- **The tutorial** uses both: its command lessons take the new spellings, and when the rules can't read the command
  it asks the same model against the practice note.

## Model downloads pick up where they were cut (2026-09-15)

Matt's Fold could not get any language model: "could not download Qwen3.5-4B-Q4_K_M.gguf", with attack.fm answering
404 and Hugging Face "peer closed connection without sending TLS close_notify". Two causes.

- **The attack.fm mirror has never had the language models.** Only the Whisper weights were uploaded to
  `/glyph/models/`, so every language model came from Hugging Face.
- **A cut connection threw the download away.** `whisper::model::download` read one response to the end or failed,
  and a failure deleted the `.part`, so 2.7 GB had to arrive over one unbroken connection. It now picks up where it
  stopped: the next request asks for the rest with a `Range`, the bytes written and hashed so far stay, and the hash
  carries on (Hugging Face's CDN answers a range with a 206 and the right `Content-Range`). A server that sends the
  whole file again is started over from the first byte, so the hash is always over the file in order. Eight tries
  from the last time bytes arrived, a little longer apart each time up to ten seconds; a mirror that never answers
  gets two; an HTTP error such as a 404 is never retried. `resume_tests` cut a local server's first answer a third
  of the way in, with and without range support. Native: it reaches phones with the next APK.

## The Glyph Tasks board, 2026-09-15 evening

Matt's list, worked through with each card moved on the board.

- **Wisp fade-in a third quicker.** Arc, jitter and stagger at 0.75 in `editor/wispArrivals.ts`; `art/WispText.tsx`
  the same, its letters' cadence times 4/3.
- **Backspaced letters fade where they were.** A ghost is a zero-width place at where the text went; it was drawn
  right-aligned to it, a letter left of the letter, and the next backspace carried it back another. It is left-aligned
  now and pinned (`pinGhosts`): its first position against the content is kept, and any later move is undone with a
  `translate`, measured after the DOM update and before paint. The delete fade is 140 ms, 85 ms in a run.
- **Header and More icons at the drawer's size.** The header's mic, robot and More draw at 22 px; the More sheet's
  rows (and plugin rows through `SheetIcon`) are a 22 px drawing in a 2.2 rem ring, as in `MarkMenu`.
- **The last letter of a linked item.** Only a pill opens the Notion drawer; the rest of the row under the item is
  the note's, and a tap there places the caret (`RowWidget.ignoreEvent`).
- **Done, both ways** (`editor/doneSync.ts`). A box ticked or unticked in the note runs the task's Mark done or
  Reopen; a task finished or reopened ticks or unticks the box. Each side answers a change of the other once, and a
  task that can't be written leaves the box as the person set it.
- **Notes reopen where they were left** (`editor/notePlace.ts`). The line at the top of the page and the offset into
  it, per note, the last 200. Restored once the note's words have arrived (they come after the editor), and written
  from the last scroll, since the page is gone by the time the note closes.
- **Pinch to zoom** (`editor/pinchZoom.ts`). Two fingers set `--note-zoom` on the note's page, which redefines the
  body and heading sizes there (a custom property is computed where it is defined, so the root's could not follow),
  from 0.7 to 2, kept for every note. The position under the fingers is held with `coordsAtPos` each frame.

## Voice memos, and the page set as it is spoken (2026-09-15)

Matt: "show actual stuff being written out and formatted as i talk. allow for voice memos to be left as a bullet
point or inline audio segment."

- **The live page is set, not marked up.** The recorder already writes into the note's own editor
  (`capture/LivePage.tsx`); it now shows it in the formatted view, so a heading is a heading and a bullet a bullet as
  it is said, with no marks around them. The note it saves has every mark, as before.
- **A voice memo keeps the sound instead of the words.** "Voice memo" said as its own phrase (`capture/voiceMemo.ts`)
  stops the words being written; what follows stays on the note's tape until "end memo" or a two-second breath, and a
  clip of it is written where the cue was: after "bullet point" it is a bullet, mid-sentence an inline segment. Done
  closes an open memo.
- **A clip is markdown** (`core/clips.ts`): `![voice 0:12](tape:12000-19500@k3f9x2)`, milliseconds into the note's
  recording, so a note is still a plain file. The times are written with the continued tape's length added, since a
  take is appended to the tape it already had.
- **And it says which tape it means.** A note's recording can be removed and another recorded, and the new file
  starts its own timeline, so times alone would point at whatever sound is there now. Every take names its tape - the
  one a continued note holds, or a fresh id - kept beside the note on the device (`tapeId`, `setTapeId`), because the
  audio is on the device too. Remove forgets it and Undo puts it back. A clip plays only while the note's tape still
  carries its id; otherwise it is the quiet mark. A mark with no id, from the first day of clips, plays while the note
  has any recording.
- **The editor plays it where it sits** (`editor/clips.ts`): the mark is replaced by a small player, and comes back
  on the line the caret is on, the bargain the formatted view makes with every mark. With no tape to play - a note
  read in a browser, a recording removed, a clip of a tape the note no longer has - it is a quiet dashed mark saying a
  memo was left here, and nothing to press. One `<audio>` per clip on first
  tap, over the recordings scheme, which serves byte ranges; one plays at a time; the end is watched as it plays.
- **The better words keep them.** A memo's stretch is skipped like a command's, so the larger model never writes its
  words, and `refine.withClips` puts each clip back among the refined phrases in the order they were spoken.

## The board, late on 2026-09-15

- **Backspacing is instant.** A single letter deleted by hand leaves no smoke (`editor/wispArrivals.ts`); it read as
  a stutter under the fingers. A word or selection taken at once still smokes, and so does a letter a rewrite takes
  back while you are talking, which is not typing.
- **The Notion drawer takes the keyboard down with it.** Opening it blurs the note, so the keyboard cannot stand over
  the drawer (`editor/linkedRows.ts`).
- **A bookmark in the header** (`editor/NoteScreen.tsx`, `editor/notePlace.ts`). With none it marks where you are;
  with one it takes you back; pressed again where it already is, it comes off. A note opens at its bookmark ahead of
  wherever it was last left, and the icon is filled while one is set.
- **Sheets have a handle you can pull** (`editor/sheetDrag.ts`). The grip follows the finger down and closes the
  sheet past a hundred pixels or on a flick, judged on how the pull ended rather than its average; a short pull
  springs back; upward it gives a little and returns. The grip alone is the grab, so the rows inside still scroll.
- **Voice memos with nowhere to go** (`sort/plan.ts`, `sort/useSort.ts`). When everything left of a sorted memo is
  clips - bullets and blank lines aside - the note becomes "Unsorted memos" and is filed in a workspace of that name,
  instead of an untitled note of nothing but players.

## Smoke at both ends, and under the clock

Matt: "replace the areas where it's just a black fade and blur to use the wisp fade effect, like the safe area fade
and the bottom page blur."

- **The foot.** `art/wispEdge.ts` gained a foot band: the same strip, blur and bend at a view's bottom edge, with its
  own noise and its own subregions placed by `placeFoot`, so it costs the band and not the page, and parked far below
  while a view has no foot. `useWispEdge(..., { foot: true })` turns it on; the note screen uses it, and the mask fades
  the last 30px (`--wisp-foot-fade`). `art/ScrollFades.tsx`, the blurred paper bands it replaces, is gone.
- **The clock.** On a view with no header the status bar now plays the part of one: the band's lip sits at its edge and
  the top mask reaches it (`--wisp-top-fade` = safe area + 29px), so a page dissolves in smoke as it passes the clock.
  `.app-statusScrim` is solid paper across the bar and stops there; the gradient tail below it is gone.

## Every mark, side by side

Matt: "create a guide page, it should show every formatting mode we have in a table and show you an example of how
it works." The guide has a sixth page (`guide/pages.ts` 'marks', `guide/MarksTable.tsx`): two columns, what you type
on the left with its marks showing, how the note reads it on the right, and under that the words to say while
recording where there are any. The rows are data (`guide/marks.ts`): the app's own marks by group (words, lines,
blocks), then the marks of every switched-on plugin, read from the registry, so a plugin switched off is never
promised and a new one appears by itself, drawn from the CSS the plugin declares. marks.test.ts pins that every
mark the app writes has a row, that each plugin format's row is its delimiter around its words, and that the
spoiler's row is smoke.


## What's new: a changelog of every release (2026-09-15)

Matt: "show a changelog with all updates including OTA." Nothing published a history, so a person on 1.4.1-2 had no
way to see what 1.4.1-3 changed, or what they already had.

- **The site keeps it.** Each deploy writes `/glyph/changelog.json` from the one that is live, newest first, capped
  at sixty: version, build, when, the notes the deploy carried, and the APK version when one went with it
  (`scripts/deploy-ota.mjs`). Carried forward from what is published rather than from any machine, so a deploy from
  another Mac adds to the same list; `scripts/changelog-seed.json` holds the releases that went out before there was
  one, used only when nothing is published yet.
- **Settings shows it** (`core/changelog.ts`, Settings > What's new). Read from wherever the app takes its updates,
  kept for reading with no signal, and the release running is marked. It is words, not code: unsigned, fetched
  plainly, while the bundles it describes stay signed and checked. The web version reads the file beside its own page.

## Boards, written in markdown: out, and back with a generic link (2026-09-16)

Built, shipped in 1.4.1-7 to 1.4.2-1, removed the same night ("for now the board view is too much remove this code"),
and asked for again the next morning: "bring back the board functionality and formatting rules, add it to the
specification / cheat sheet. come up with a generic way to link list items to the board." The standard is
docs/BOARDS.md and it is still two pieces of ordinary markdown, with one of them now doing more.

- **An anchor names an item**, and that is the generic link. `- [ ] Ship the pricing page ^ship-page` still works, but
  so does `- Ask Sam about the copy ^ask-sam` and `1. Unplug it ^unplug`: any list item, not only a to-do, which is
  what makes the link generic rather than a board feature. A card for an item with no box is drawn with a dot instead
  of a tick. The regex takes an anchor only after whitespace and before the end of the line, which is what keeps
  `E = mc^2^` a superscript.
- **Anything can point at an anchor.** `[[#^ask-sam]]` in the middle of a sentence goes to that line, and
  `[[Note#^ask-sam]]` to one in another note (the title half is `editor/wikiLinks.ts`, which skips a `[[#` outright;
  the anchor half is `core/boards.ts`). A **fenced ```board block** is then one more thing that names anchors, rather
  than the only thing that can.
- **A card is its item** (`core/boards.ts` reads and writes the whole syntax; `editor/boards.ts` draws it). The
  card's tick box is the item's box, its words are the item's words, and tapping them puts the caret on that line. A
  column called Done means done: ticking a card moves it there, dragging it there ticks it, and dragging it out
  unticks it.
- **Press and hold to drag** (Matt: "add a way to tap and drag to re organize items in lanes"). The card itself stays
  in the column as the gap it would leave and moves from place to place as the finger goes, while a copy follows
  overhead; `putCardAt` writes it where the gap was, so a card reorders inside a lane as well as moving between them.
  Before the hold is up the finger still scrolls, and a card held at either edge scrolls the board along.
- **Friendlier on a phone**: columns that snap one to a screen, a column name that stays while its cards scroll, an
  empty column that says it will take a card, thumb-sized targets with the chevrons kept for a hand that would rather
  not drag, and a **+** that opens a field for the new card's words and writes the to-do and its card together.
  The first + put the caret into an empty `- [ ] ^item` line, which left every new card named `^item`, `^item-2`,
  and put the caret one place short of the box's space; asking for the words first removes both, and the board is
  redrawn in place (`updateDOM`) so the field and the keyboard survive each card. The `^anchor` at the end of a line is drawn small and faint, so the line reads as its words.
- **The fence stays the truth.** Tapping it puts the caret inside and the drawing steps aside, the way a table does
  (`editor/tables.ts`). A card whose item is gone is drawn with its anchor, so nothing disappears quietly.
- **The example note** (`core/boardNote.ts`, Settings > About > Add the example board) is a working board with two
  fences in one note, and says in its own words how to change it.

## The board again, and the robot moves house (2026-09-16)

- **Text arrives quicker still.** Matt asked twice: after the 33% boost, "speed up the wisp animation on text". The
  arc, its jitter and the stagger are another quarter off in `editor/wispArrivals.ts`, and `art/WispText.tsx` is the
  same with its letters at 16/9 of the asked-for pace.
- **The drawer handle is a bar again.** The grab band I gave it (`NoteSettings.module.css .grip`) put a full radius on
  a 40×30 box, and the clipped background came out an ellipse (Matt: "handle on drawers are ovals instead of
  rectangles with rounded caps"). The band is now plain and the bar is its `::before`, 44×4 with 2 px caps.
- **The robot lives in More.** Matt: "move robot dropdown in topbar into more drawer with an AI group label", and
  "give the dropdown for the robot tools like formatting glass mode". Format, Summarize and Enhance are rows under an
  AI heading in the note's More sheet, the group in glass, the mode showing marked with a dot; the header keeps the
  bookmark, the mic and More. `format/RobotMenu.tsx` and its CSS are deleted, nothing imports them.

## The marks are one plugin

Matt: "move all the additional formatting to one single plugin instead of one of each like shout redact unsure etc."
`plugins/marks/index.tsx` is now a single Marks plugin holding all seven formats, the spoiler among them (its own folder
is gone), with one switch in Settings > Plugins. So the Style page and the guide's table could still show a mark's own
sign rather than the plugin's, `InlineFormat` gained an optional `icon`, which `editor/ContextMenu.tsx` prefers over the
plugin's.

## One GitHub plugin: repos, and issues that tick both ways

Matt: "make a GitHub issues plugin that allows us to sync list items with GitHub project issues, or make it part of an
overall GitHub plugin that's provided by default like Notion." The Projects plugin became that plugin
(`plugins/github/`, id `github`, standard): one link on a note, "GitHub repo", doing both jobs.

- **Issues** (`issues.ts`, `details.ts`). A list item sent becomes an issue on the linked repo and its words become a
  link to it, `- [ ] Ship the page [github](https://github.com/o/r/issues/12)`, the shape Notion's items already use.
  The pill says whether it is open; the card lists the repo, the number, who has it, its labels and milestone. Because
  the provider's stage is plain (open is to do, closed is done) and its actions are called `done` and `reopen`, the
  tick works both ways with no editor change (`editor/doneSync.ts`, `core/markDetails.ts`): ticking the box closes the
  issue, and an issue closed on GitHub ticks the box. Reads are paced two at a time, fresh for 45 seconds, and the last
  300 are kept (`glyph-github-issues`) so a note opened offline still shows what its issues last were.
- **Sending** needs a token; reading needs none. The token has moved into the plugin's own page in Settings, where it
  can be typed rather than only offered while linking a private repo, and every place that would send says so when it
  is missing.
- **Context** is unchanged (`repos.ts`, once `projects.ts`): the repo read on the phone into a briefing the model gets
  with the note. The storage keys are the same, so repos and links carry over; only the plugin's id changed, which
  resets its switch to on.


## The press-and-hold menu, in full (2026-09-16)

Matt: "add a full context menu for text and such." The menu had Cut, Copy, Paste, Find, Select all, Style and Add
image; it now carries the rest of what a person expects of a line, and two of Glyph's own.

- **Duplicate, Delete, Move up, Move down** (`editor/format.ts`). With words selected they work on the selection;
  with none, on the line the caret is on, which is what a finger has usually just tapped.
- **Add to board** (`core/boards.ts` `addToBoard`, docs/BOARDS.md). On a list item in a note that holds a board, this
  gives the line an anchor made from its own words and adds the card, in Done when the item is already ticked.
  Nothing shows on a line that is not a list item, in a note with no board, or on an item already on one.
- **Send** is the plugin's own item action, the one a swipe on the item does (a Notion board, a GitHub issue), so the
  same thing can be done without knowing about the swipe.

## The cheat sheet draws its examples with the editor (2026-09-16)

Matt: "the cheatsheet is disorganized and ugly please redo it with better iconography and layout also make sure were
using the real formatters as some things like spoilers isnt using the right one (wisp)". Both halves of that came
from the same cause.

- **The examples are the app now.** The guide's table and the cheat sheet each used to draw every mark a second time
  in CSS, which is how a spoiler ended up a `blur(3.5px)` on one page and real smoke in a note. `guide/MarkExample.tsx`
  is the note's own editor, read-only, in `formatted` view, with the same extensions and the same switched-on
  plugins: the spoiler is the wisp filter, the code block is the real highlighter, a table is a drawn table and a
  board is a working board. A mark that changes in the app changes on both pages by itself, and the bespoke look CSS
  is gone. An editor per row is a real thing to build, so a row builds one when it comes within a screen of being
  looked at (`IntersectionObserver`).
- **A mark is a card.** Icon, name, the characters in a ring, the line to type, then under a rule the line as it
  reads. Every row carries its own icon in `guide/marks.ts` - a plugin's mark uses the icon the plugin declares - and
  the page is a grid that gives a phone one column and a folded phone two, with a board taking the full width.
- **A field to find a mark** by its name, its characters or the words of its example, above the group chips. Looking
  something up was the whole point of the page and it was a scroll.

## The microphone is only open when something is being recorded (2026-09-16)

Matt: "disable the always on microphone only enable it when actually recording or in memo mode, remove the wake work
functionality completely". The wake word is gone, not switched off: `capture/wakeWord.ts`, `capture/useWakeWord.ts`
and their test are deleted, with the `listenWhileOpen` preference, its Settings row, the handoff the recorder took
from it (`takeWakeHandoff`, `wakeSettled`), the `woke` screen state, and the tutorial tip that taught it. This
reverses the section of 2026-09-16 above ("While Glyph is open I should be able to say the AIs wake word"), which had
itself reversed the pause of 2026-09-13.

- **`prefs.commandWord` stays.** It does a second job: it is what makes a spoken command need "Glyph" in front of it
  *while a recording is running* (`capture/command.ts`), which is not an open microphone and is what keeps "Glyph, add
  buy milk to HelloTrade" apart from a sentence about Glyph. Only the listening is out.
- **One thing opens a microphone.** The recorder (`capture/CaptureScreen.tsx`, memo mode included, since a memo is
  that screen in another mode). The voice tutorial, which opened it for its practice lessons, was removed on
  2026-09-17 (see below).
- **The guide's rings stopped listening too.** `guide/micLevel.ts` opened the microphone on the side-key page so the
  rings could answer a voice; a page that is only read is no place for it, and the rings keep their resting beat.
  The file is gone.
- Nothing in the Kotlin side ever held a microphone: the side key launches the recorder, it does not listen.

## 51. Glyph on a Mac

The desktop app (`npm run desktop:dev`, `desktop:build`) is the same page in WebKit, the engine the Mac and iPhone
apps share, so three things are shaped for it:

- **The title bar.** The window draws under a transparent bar, with its three buttons inset into it
  (`src-tauri/src/lib.rs`). `core/platform.ts` marks the Mac app with `data-titlebar="overlay"`, so app.css gives
  `--app-safe-top` 44px there (every header already pads by it) and lays `.app-dragBar`, a
  `data-tauri-drag-region`, over the strip, which drags the window and zooms it on a double click.
- **What a filter's region costs.** A filter region has a budget of 2^24 device pixels, and a filter asking for more
  is not clipped or scaled down: in WebKit the element paints solid black. That is what took the wisp edge off the
  Mac (Matt: "the whole page is going black when I scroll down", and later "on desktop the wisp effect isn't working
  on the scrolling"), and the guide's headline with it. It was read at the time as WebKit being unable to draw a
  filter measured in its own coordinates (`filterUnits="userSpaceOnUse"`), and both effects were stood down behind
  an `isWebKit` flag. The units were never the problem. Measured in headless WebKit on the app's own filter:
  4096 x 4096 draws and 4200 x 4000 is black, 16000 x 1000 and 3000 x 5000 both draw, so it is area and not a limit
  on a side; at two device pixels to the CSS pixel the boundary moves to 2048 x 2048 exactly, so the budget is
  counted in the screen's pixels and a sharp screen spends four for each one the page asks for. The region we shipped
  was 4000 x 60000 - forty times over - because it was one guess big enough for any view.

  So the region is sized to the view that wears it: `placeRegion` (art/wispEdge.ts) sets it from the window each
  time the hook fits, and `wispFoot` takes the lane's own width instead of a width wide enough for any lane. The
  app's window is 430 x 860 and a laptop's is not much more, so both sit far under; a window so large that even a
  fitted region is over budget wears no filter at all and keeps its mask fade, which is the one case the old
  stand-down still covers. Nothing outside a filter's region is drawn, so the region is set before the element wears
  the filter, never guessed in the markup. `isWebKit` and `data-engine="webkit"` are gone with the stand-downs.

  The lesson worth keeping is the shape of the mistake, not the number: a fix that worked (percentage units) was
  read as an explanation, and the explanation was wrong in a way that cost the Mac an effect for a day. What settled
  it was bisecting the boundary until it had two sides.

  Its sister, found the same night on the workspace pills: **a number quoted in a comment or a message outlives the
  code it described.** The matched pill geometry was passed between sessions as `0.35em`, which had been true for
  about an hour before it was replaced by `0.52em 0.8em`; carried forward, it would have quietly un-matched the very
  pills that had just been matched (notes/NoteTabs.module.css `.space`, notes/NotesList.module.css `.rowSpace`, both
  on `--glacier-font-size-xs`). The quote was honest and stale, which is the dangerous combination. Grep for the
  number rather than remember it, and when two files must hold the same one, derive the second from the first -
  plugins/LinkMarks.module.css sizes its ring off the badge's own tokens for exactly this reason, so a change to the
  padding carries rather than rots.
- **The sidebar.** On a window with the shape for two panes (`useSidebar`, core/useWideScreen.ts) the notes list
  sits in a column beside the open note (Matt: "on widescreen desktop I would like to see a sidebar with all notes
  in them"): each is its phone screen, sized to its pane.

  The rule asks about the window, not the device (Matt: "On a wider display we should just use the desktop layout").
  It used to ask `!isMobile` as well, so a Fold opened out or a tablet kept the phone layout however wide it got -
  the very case the split is for, on the phone Glyph is built on. What it asks now is 660px across (the list's own
  300px column and a note beside it no narrower than a small phone) AND either 600px tall or a fine pointer: a phone
  held in landscape is as wide as a small desktop window and about 390px tall, with nowhere to put a list, while a
  short window on a desktop is one the person chose. Measured across the shapes it has to separate: phone portrait
  and landscape keep the phone layout, a Fold opened out in either orientation splits, as do a tablet, a 1280px
  desktop and a 900x500 one, and a 600px-wide desktop window does not.

  The threshold lives in that one expression. App.tsx stamps `data-split` on the root and the stylesheets ask the
  stamp - the tab bar's ground across a split window (app.css) and Settings becoming a card rather than a screen
  (settings/settings.css, twice). Those were three copies of `900px` written to agree with it, which is three chances
  for the app to change shape at three widths and no way to notice when they drift. A stamp carries no number. The open note's row is marked (`selectedId`), the note
  drops its "← Notes" (`showBack`), the list is read again a moment after each save so titles follow the typing,
  and with nothing open the pane says so and offers Speak and New note (notes/NoNoteOpen.tsx). Recording, review,
  sorting and the tutorial still take the whole window.

## Scrolling past a board, its handle, and smoke in its lanes (2026-09-16)

Three open cards on the Glyph Tasks board, all in `editor/boards.ts`:

- **Scrolling past boards stopped.** Matt: "scrolling past boards is glitchy and stops scroll momentum". There were
  three causes:
  - **The height before drawing.** CodeMirror sizes what it has not drawn by the widget's `estimatedHeight`, and
    the board had none, so it counted as one line (31 px). When a board came into view from above, the editor
    moved the page by the difference (345 px on the test note) to keep its place. On Android that move ends a
    fling. The widget now answers the height it was last drawn at, kept by a hash of what it shows in
    `glyph-board-heights`, or a height worked out from its lanes and the length of its cards' words. Measured
    cold, the guess came within 0.03 px of the drawn board and the page did not move.
  - **Margins.** The board's top margin and the wrapper's bottom margin also stood outside the border box the
    editor measures, so every line under a board was 16 px from where the editor had it. They are padding now.
  - **Lanes that kept the finger.** Lanes stopped at a cap, scrolled, and had `overscroll-behavior: contain`, so a
    fling that landed on a full lane scrolled the lane and stopped the note dead. A lane with no set height now
    shows every card. A lane with a set height scrolls and passes the finger on at its ends. The board has
    `overflow-y: hidden`, since a sideways scroller is a vertical one too. A held card near the screen's top or
    foot rolls the note, because the lane no longer rolls itself.
- **The handle is the plain grip again.** Matt: "the resize handle under the board changed and doesnt match the
  simplistic version anymore". The tab with chevrons, a ring and a shadow is back to Glacier's grip pill, 1.5 rem by
  6 px at 45% ink. It turns white when held.
- **Lane feet smoke.** Matt: "the blur at the bottom of the swimlanes should be the wisp effect we use on text".
  - The page's `#wispEdge` filter is placed for one view at a time, so a lane can't wear it. `art/wispFoot.ts`
    makes the foot half of it at a given height, one filter per lane height, shared and kept.
  - A lane wears it only while it has cards below its foot (`data-more`), over a 1.2 em fade.
  - The smoke is off with Settings' smoke, with reduced motion and where the filter's region would be over budget.
    Those keep the fade. (It was off in WebKit too, which §51 undid, and which is what left the two faults below.)

## The board a list is already on (2026-09-17)

- **Ticks and lanes stopped drifting apart.** An item ticked anywhere is DRAWN in the Done lane, but nothing moved its
  id, so Matt's Task Management note ended with seventeen ids under `To do:` drawing two cards, and he read the fence
  and asked where the others had gone. Most of those ticks came from Notion, not from taps. A box turned in the list
  now moves its card in the same edit and the same undo, and any other card whose item is ticked settles at the same
  time, so a note that has drifted comes right with the next change (`core/boards.ts` `settleBoards`,
  `settleColumns`; `editor/boards.ts` `settleFences` for editor/taskToggle.ts and editor/doneSync.ts). A card the
  person has just moved by hand is left where they put it.
- **Two reader fixes found while looking for that.** An id written into two lanes was read into both, so it was drawn
  twice in the first and the lane he had put it in drew nothing; it now belongs to the first lane that has it. An id
  that was not already an anchor (`Fix Login`) was dropped without a word and gone from the note at the next change;
  it is now read as the anchor it means, but only when the note has an item with that anchor.
- **Add to board** (Matt: "add an 'add to board' option when other items in the list are in a board already"). The row
  was called To board and always used the nearest board above, in its first lane. It now uses the board the item's own
  list is already on, and puts the card beside the neighbour it follows in the list, so the board keeps the list's
  order. Where it went is said aloud, since the board is often off the screen.

## Glyph Academy (2026-09-17)

Matt: "we need a Glyph Academy section that teaches you markdown then teaches you the extra stuff we have. Build the
academy section start with just the markdown basics set it up as a live code type thing where it teaches you then you
type it and see it format below."

- **A lesson is one mark** (`academy/lessons.ts`): a line or two on what it does, an example to look at, something to
  write of your own, a check, a word of praise and a hint. Thirteen of them in the first chapter, Markdown basics, in
  teaching order: title, heading, bold, italic, struck through, code, link, list, in order, to-do, quote, dividing
  line, block of code. Pure, so every lesson's example is a test that its own check passes.
- **The check is on the mark, not the words.** Any title passes the title lesson; extra lines and other marks are
  fine, since somebody learning is usually trying things. A lesson can also be skipped.
- **The live page** (`academy/Playground.tsx`) is the point: a plain field in the typewriter face above - autocorrect
  and autocapitalising off, or a phone turns `# weekend` into `# Weekend` and the underscores into quotes - and under
  it the note's own editor, read-only and formatted, redrawn as the words change. The same trick as the cheat sheet's
  examples (`guide/MarkExample.tsx`): the real marks drawn by the real app, so what is learned is what a note does.
- **The lesson in hand is held in state, not worked out from what has been learned.** Deriving it meant passing a
  lesson moved the page on the instant the mark was typed, and the whole point is to stay and watch it format. It is
  ticked where it stands, Next appears, and nothing is taken away.
- **Progress is kept** (`glyph-academy`), so it opens at the first lesson not passed, and any lesson can be taken
  again from the summary. Nothing typed is saved as a note.
- **The way in** is Settings > About > Help > **Glyph Academy**, where the voice tutorial's row used to be, and a card
  on the notes list for anyone who has not started (`academy/banner.ts`, `notes/NotesList.tsx`; Matt: "I'd like the
  academy page to show up on the home screen kinda like the update banner for new users as a call to action banner").
  It is shown while no lesson has been passed and it has not been put away, so passing one takes it off.
- The summary points at the cheat sheet for Glyph's own marks - boards, spoilers, callouts, anchors - until their
  chapter is written, which is the next piece of this.

## Mermaid diagrams, drawn (2026-09-17)

Matt: "Add support for Mermaid charts".

- **A ```mermaid fence is drawn as its diagram** (`editor/mermaid.ts`), the way a table is drawn as a table and a
  board as a board: the text is what is kept and edited, the drawing steps aside when the caret goes in, and a tap
  puts it there. The fence is read by hand rather than from the syntax tree, as boards are, and the word has to be
  the whole info string, so a note *about* mermaids is not a diagram.
- **Mermaid itself, every diagram type.** The size was put to Matt before it was built: the app is 5.2 MB over the
  air, mermaid 12 minified is 5.4 MB across 102 chunks, and flowchart plus sequence alone would have been about
  1.5 MB. He chose everything, so the payload roughly doubles. It is imported the first time a note actually has a
  diagram, so startup is unchanged, and since the OTA brings every file down to the phone, that import needs no
  network: diagrams draw offline.
- **A diagram that cannot be drawn stays as its own text**, in the typewriter face, with one quiet line saying why -
  the diagram is wrong, or the library never arrived (a browser with no network). No spinner that never ends.
- **Drawings are cached** by what the diagram says and which way the app is painted, and **heights are remembered**
  between launches (`glyph-mermaid-heights`), so the editor knows how tall a diagram is before drawing it and the
  note does not jump as one scrolls into view. That is the same lesson boards taught (docs/BOARDS.md).
- **A drawn diagram carries its colours inside its picture**, so unlike everything else in the editor it cannot
  follow a CSS variable: a small view plugin watches the theme setting and the phone's own scheme, and redraws every
  diagram on the page when either changes. Found by drawing a dark diagram on a light page.
- The cheat sheet has a row for it (`guide/marks.ts`), which draws a real diagram with the real editor.

## A board's cards get a menu, and the note's stays off them (2026-09-17)

Two cards of Matt's, which are two halves of one thing: "Formatting menu shows up on board unexpectedly" and "Add
context menu to board items for moving lanes and adding to notion etc."

- **The note's menu is about a line of text, and a drawn board is not one.** Both ways it opens - the phone's own
  `contextmenu`, and the timed long press for a line with no word under the finger (editor/ContextMenu.tsx) - now
  ignore a press that lands inside a drawn board or a mermaid diagram. The fence's own lines still have it: tapping
  a board puts the caret in the fence and the drawing steps aside, and there the menu is a menu about text again.
- **A card's menu opens from a button, not a press and hold**, because a press and hold is already how a card is
  picked up to drag. A small **more** beside the chevrons.
- **It sits in the lane, under its card**, the way the + field sits at the top of a column: nothing to place, and it
  scrolls with the board. It closes on a choice, on a press anywhere else, and on Escape. (Since §197 it is the kit's
  menu, hung from the more button over the page: in the lane it was cut off by the lane and covered by the header.)
- **What it offers**: every other lane to move to (through the same `land` a drag uses, so crossing into Done ticks
  the item and out of it unticks), the tick, the line in the note, what a plugin offers this item, and **Take off the
  board** (`core/boards.ts` `withoutCard`), which leaves the item exactly where it is in the note.
- **The plugin row asks by line first.** `cardActions` carries the same two seams the note already uses: the per-line
  suggestions (editor/suggestions.ts) and, only where a line has no offer, the action a swipe would run by text
  (editor/swipeItems.ts). A card names an exact line, and sending by text alone would send
  the wrong one of two items that read the same way. Nothing here reaches into a plugin.

## 52. The top bar carries two rows, and a screen's controls (2026-09-18)

Matt: "Move the controls for the note into the topbar and put the tabs on the next line down", then "This row can be
hidden when there are no tabs open".

- **Two lines, one bar.** The controls sit on the top line - the sidebar's button, the two arrows, and whatever the
  screen puts at the far end - and the open notes run underneath. The second line is not rendered at all when nothing
  is open, so a note reached from the list carries no empty strip. `--app-tabs` says which of the two heights the bar
  is (`app.css`, `:root[data-tabs='on'|'rows']`, set by `App.tsx` from `openTabs.length`), and `--app-safe-top` carries
  it as it always did, so every screen's header clears the bar without knowing the bar exists. Measured: 92px with
  tabs, 56px without.
- **A screen's controls reach the bar by portal** (`core/topBarTools.ts`, `notes/NoteTabs.tsx`, `editor/NoteScreen.tsx`).
  The note's tools hold the editor's state - the view being shown, the bookmark's line, the tape - so lifting them into
  `App.tsx` would lift the editor with them. Instead the bar offers a slot, the screen keeps owning its buttons, and
  React puts them in the bar's DOM. A screen renders its controls where they have always been when there is no slot,
  so a route with no bar still works.
- **The ring takes the tap, never the box around it.** The bar passes clicks through to what is under it
  (`.app-tabBar > *` is `pointer-events: none`), so anything meant to be pressed has to say so - and saying it on the
  slot made the slot's whole area a target, swallowing clicks in the few pixels between two rings. This is the same
  bug the tabs row had at 974px, at a tenth of the size, which is the point: it is a class, not an incident. The test
  that settles it is `elementFromPoint` at a spot with no control on it, at a narrow width and a wide one; the answer
  should be the header pane underneath.
- **Exact is not a fit.** At 360px - a fold closed - the seven rings on that line came to exactly its width, 316
  against 316. Tightening the air between them bought the ten pixels, but a row that fits exactly is one larger type
  setting or one more control from cutting the last one off with nothing to show for it, so the line scrolls sideways
  rather than clipping. Reachable beats invisible.

### Three gestures on one row

The tabs take a press, a drag and a wheel, and each had to be asked for before it was there (Matt: "add dragging
around tabs into different positions", then "moving tabs doesn't look like you're actually moving it, doesn't follow
my finger", then "I should be able to scroll left or right on the tabs to see overflowing ones", then "the clicking
and dragging is eating me moving the tabs - the tabs should only move when I press and hold").

- **Hold to pick up, drag to pan.** A press that stays put for 220ms picks the tab up; a press that moves before then
  pans the row by its `scrollLeft`. One rule for a finger and a mouse alike: the mouse had its own, reordering the
  moment it had travelled six pixels, so a click that slid under the hand carried the tab with it.
- **The wheel pans it too.** A mouse has no sideways wheel, so a vertical one over the row is spent on `scrollLeft`;
  a trackpad's own `deltaX` is preferred when it is the larger of the two. Without this the row could not be scrolled
  on a Mac at all, which is how it was for a day.
- **Why the pan is ours and not the browser's.** The row carries `touch-action: pan-y` so a vertical swipe still
  scrolls the page natively. That also tells the browser not to pan the row sideways, so the sideways movement
  arrives as pointer events and is spent by hand. Granting `pan-x` instead would hand the gesture back to the browser
  and take the reorder with it.

Three things about the drag are easy to get wrong, and all three were:

- **Follow the pointer on the window, not on the tab.** Reordering moves the tab's own element, which drops a pointer
  capture held on it: the drag then loses its end, no `pointerup` arrives, and every later tap is swallowed as "the
  click that ends a drag". Window listeners see the whole gesture whatever React does underneath.
- **Measure the places from the tabs that are not moving.** The dragged tab carries an offset so it can follow the
  finger, which moves the box it would otherwise be measured by, so including it makes the row swap and swap back as
  the measurement chases the thing that caused it. The place is counted from the other tabs' middles.
- **Swallow the click that ends a drag**, and clear that flag on the next turn rather than on the click, since a
  gesture that ends off the tab sends no click at all.

### What the DOM says depends on when you ask it

Three things looked broken tonight and were not: a wheel that scrolled one way, an overflow fade that never appeared,
and a blank note pane. All three were reads taken before React had committed, or a screenshot caught mid-load. Each
would have become a bug report to somebody.

A read straight after an action measures the timing, not the app. Attach a listener and inspect what it captured, or
wait a frame and read again, before believing that something is broken - and especially before telling someone else it
is. The suite was green through all three, because none of them were things an assertion can see.

## 53. Make the environment real before calling a bug unreproducible (2026-09-18)

Four bugs got past a green suite in one night, and three of them were found the same way: not by reasoning about the
difference between here and there, but by making here actually be there.

- **The filter region that painted black** (section 51) was found in a headless WebKit, not argued about from Chrome.
- **The glide that would not run** was found in a headless Chromium with reduced motion explicitly turned off, which
  is the state a developer machine is rarely in and a phone often is.
- **The top bar over the workspace pills** (section 52) could not be reproduced in a browser at any width - 26px clear
  every time - because it only exists where the window has a title bar. Stamping `data-titlebar='overlay'` on the root
  turns on the Mac's 44px inset, and the overlap appeared immediately: bar bottom 136, pills at 118.

The shape each time: a report that looks wrong because it cannot be seen locally, and a local setup that differs from
the reported one in exactly one arrangeable way. The inset, the engine, the motion preference - each is one line to
turn on. "I cannot reproduce it" is a statement about the setup, not about the bug.

**Test the worst case, not the fix.** Once the overlap was fixed the fix could be proven the easy way, by measuring it
working. The better test was to delete `--wisp-under` outright at Mac geometry - the state where the observer never
fires at all, which cannot otherwise be arranged - and measure again: 27px clear, against 85px of overlap before. That
says the floor holds when the measurement fails entirely, which measuring the happy path never would.

**And a fallback stands in for something, so it has to be related to it.** `var(--wisp-under, 3.2rem)` was picked
because 3.2rem was roughly the bar at the time; the bar then changed three times in an evening. A fallback that is a
snapshot of another value is wrong from the first change onward, and silently - it is only read when the real value is
missing, which is exactly when nobody is looking. Derive it (`--app-safe-top`) or do not have one.

**Emulating a device's size is not emulating the device.** Two sessions measured the same eight window shapes against
the new split-layout rule and disagreed on one: a phone in landscape, 850x390, which must keep the phone layout. The
rule asks for width AND either height or `(pointer: fine)`, and a headless browser given only a viewport reports a
fine pointer at every size - so the shape passed in one harness and failed in the other, which had `hasTouch` and
`isMobile` set. Neither of us had reasoned it out; one harness happened to include the thing under test. Any rule that
asks about pointer, hover or touch inverts silently under a viewport-only harness, so set the device emulation, not
just the size.

**The tab bar is the worked example.** `--app-tabs` began as one number for a row holding a 40px button, became
`calc(3.5rem + 2.25rem)` when a second row of tabs arrived, and is now the sum of two rows that each measure
themselves - the controls' own expression and the tab's own height, which is the workspace pill's. Three revisions of
one rule, and the first two were each a number standing for something that then moved: the pill changed size four
times, and Appearance > Spacing scales the rings from 27.4px to 56.9px, which is 0.9px past the 56 the bar had set
aside. Each revision was found by a person looking at the screen, never by a test. What the derived form buys beyond
not clipping: at the tightest spacing the bar is now SHORTER than the guess it replaced - 91.8px against 99.2 on a
phone with two tabs - so a setting that asks for less chrome gets it, without anyone choosing a smaller number.

**A limit counts everything inside it unless it says otherwise.** Three of the night's bugs were a number that did not
count what its name suggested: the filter region measured in device pixels rather than CSS ones (section 51), a ring
of `max-inline-size: 7ch` on a border-box pill that spent 17.8px of the seven on its own padding and drew about three
characters of "Engineering", and a tab whose height came from whichever child happened to be tallest. Written as what
they count - `calc(8ch + 1.6em + 2px)`, a height derived from the pill's own parts - they stay true when the parts
change. The pill changed size four times in two days.

## A highlight can be told its colour (2026-09-18)

Matt: "Add a colour option on the highlight supporting the colour names from the glacierUI kit."

- **No new syntax.** `==the cabin key==(green)` uses the brackets a note on a mark already uses
  (editor/markNotes.ts). One shape for "something in brackets after a mark", and **the mark decides what it means**:
  the format answers `tint(name)` (plugins/types.ts), a name it knows is a colour, and anything else is still a note.
  The brackets are hidden either way, so the line reads as its words; only the tap differs, since a colour has
  nothing to say.
- **A name, not a colour**, as with the workspace hues: the note carries `green`, the wash is
  `color-mix(in oklch, var(--glacier-green-9) 34%, transparent)`, and the kit can retune green without touching
  anybody's note. A name this build does not know draws the plain highlight rather than nothing.
- **The colours are the kit's own ramps** and nothing invented here: blue, red, amber, green, teal, purple, gray.
- Measured in the browser rather than read: the plain wash draws at hue 250, green at 150, amber at 75, red at 25,
  and both an unknown name and a real note stay at 250.

## Theme becomes Appearance (2026-09-18)

Matt: "Change theme to be appearance settings and add the density controller, the accent color picker and the
rounding control in there as well as the other existing theme options."

- **One page for how the app is drawn**: the page (light, dark, system), then its accent, its spacing and its
  corners, then the colours of code. Spacing moved here from Type, where it had landed first.
- **The accent is the one way out of grey.** ink.css maps every accent token onto the grey scale, which is what makes
  Glyph grey; that mapping now sits behind `:not([data-accent])`, so choosing a colour lets the kit's own ramp show
  through (tokens.css carries graphite, red, amber, green, teal and purple) while paper, ink and every grey stay put.
  `ink` is the default and stamps nothing. The focus ring came with it: a ring round what has the keyboard is exactly
  what an accent is for, so it is ink with no accent and the accent's own when there is one.
- **Rounding is one multiplier** over the kit's whole radius scale (`--glacier-radius-scale`), stamped as
  `data-rounding`: Square 0, Soft 0.55, Round 1 (the kit's own, stamped nothing), Roundest 1.5. **Pills are untouched
  at every setting**, since `--glacier-radius-full` is a flat 9999px - so Speak stays a pill while every card squares
  off. Measured rather than assumed: a `radius-lg` box draws 16px, 0px, 8.8px and 24px at the four settings.
- **The swatch shows the real thing.** Each dot wears `data-accent` itself, so it is painted by the very ramp that
  choosing it would give the app rather than by hex values kept beside it.
- **A name, not a colour, is stored**, as with the workspace hues, and a name this build does not know - `blue` from
  the old store, where the accent was a colour the app never drew with - reads as the app's own rather than stamping
  something nothing can draw.

## A tick can put an item on the board (2026-09-18)

Matt: items were not moving to Done when he ticked them. Every function was behaving: measuring his note
found three ticked items with no `^anchor`, which are therefore not cards at all, while the other 57 moved correctly.
Two identical-looking to-dos behaved differently and nothing said why - a bug from where a person sits, however
correct the code.

- **Ticking an item that is not a card now adds it**, to the board its own list is already on, in Done, with the
  anchor written at the end of its line (`core/boards.ts` `settleTicks`).
- **Scoped to the list.** docs/BOARDS.md says a board never has to hold every item in the note, so an item in an
  unrelated list further down must not leap onto the board because it was ticked. Its neighbours decide.
- **The anchor is appended, not the line rewritten**, so the edit can never overlap the one character the tick itself
  changes at the start of the line - two changes in one transaction, one undo.
- The alternative - saying why nothing happened - was smaller but leaves the note holding two kinds of to-do that
  look identical. This finishes the thought instead, and is visible and reversible: the card menu takes it back off.

## The workspace pill is a badge again (2026-09-17)

Matt: "Workspace pill doesn't have same left and right padding as top and bottom around the outside."

- **It was 17.8px at the sides against 8px above and below** - the pill's height came from `min-block-size` while its
  sides came from a space token, so the two were never related. An even ring now: `padding: 0.6em`, with the min
  height kept for the tap target.
- **The line box is pinned to the words** (`line-height: 1`), or the font's own slack above and below counts as ring
  and the sides look tight beside it. It has to sit AFTER `font: inherit` in the rule: that shorthand resets
  line-height, which is why the first attempt did nothing.
- **The pills stopped stretching to the tallest item in the row** (`align-items: center`). The **+** is a different
  size, so every pill inherited its height and got a taller ring than the sides they had just been matched to. The +
  is now a round button the height of a pill rather than a pill with one stroke in it.
- The tag a note's row wears got the same ring, and is nudged back onto the time's own line.

## A board holds its height (2026-09-17)

Matt: "Clicking an item to toggle the done state on and off is now super laggy and doesn't actually change the state
off." Two taps in the same place, and the second one missed.

- **The note moved, not the tick.** A board's lanes are as tall as the tallest lane's cards, so the moment a tick
  moved a card between lanes the board's own height changed and everything under it jumped - 48 px in the case
  measured here, in both directions depending on which lane won. The second tap landed on whatever had slid under
  the finger: the next item, or the board itself. Measured precisely, the collapse was reproduced with a
  raw character change, which proved it was the drawing and not the fence write.
- **So a board settles its height when it is drawn and holds it** (`pin`, `--cm-board-pin`): ticking, dragging,
  adding and taking off all leave it where it is, and the lanes scroll inside as a board with a set height does. It
  is let go when the board is built again - the note reopened, its columns changed - when the line under it is
  dragged, which writes a real height, or when the words change size, since the pin is in pixels.
- It is measured in the editor's own measure cycle rather than on an animation frame, so a note opened in a hidden
  tab pins as soon as it is looked at.
- No unit test covers it: jsdom gives every box a height of zero, so a layout pin cannot be seen there. It was
  verified in the browser instead - board height unchanged across a tick, the lines under it not moving, and the
  second tap landing on the item it was aimed at.

## A colour for a workspace (2026-09-17)

Matt: "add the ability to choose from a swatch of colours for the workspace pill colour".

- **Colour as ink, not as a fill.** The app is grey everywhere by design, so a workspace's colour is the one place
  colour carries meaning: which workspace a note is in, seen without reading. Six hues and the app's own ink, and a
  hue is worn by the workspace's pill on the list and by its tag on a note's row.
- **A name, not a colour, is stored** (`core/workspaces.ts` `WORKSPACE_HUES`, `setWorkspaceHue`). What each hue looks
  like belongs to the page (ink.css `[data-hue]`), so the swatch can be retuned without touching anybody's
  workspaces, and a hue from a newer phone reads as ink rather than as a broken colour.
- **One lightness per paper.** `--app-hue-lift` sits with the grey scale and flips with it - 0.55 on white, 0.78 on
  black, and flipped again on an inverse surface - so the same six hues read on every ground the app has. That is
  why the hues are written as `oklch(var(--app-hue-lift) var(--app-hue-chroma) <angle>)` rather than as fixed
  colours.
- **The swatch** (`notes/WorkspaceSwatch.tsx`) is a radio group of dots: arrow keys move between them, and the chosen
  one wears a tick as well as a ring, so it is never colour alone that says which is picked. On a workspace that
  exists the colour is set as it is tapped, since it is a thing to look at: the pill behind the sheet changes under
  your finger. A new one carries its colour into the making.

## A home page, and the notes list gone (2026-09-18)

Matt: "Add a 'home' button to take us to a dashboard like page", with Glyph's own mark as its icon; he chose a new
page on every screen, the phone's start page included, and then "Delete the code" for the list it replaced.

- **The button** comes first in the top bar, before the sidebar's (`notes/NoteTabs.tsx`; Matt: "Move the home
  button to the left of the sidebar button"). It was first drawn as the app icon's dot and dash, and is now a modern
  house (`art/Icons.tsx` `House`; Matt: "change the home logo to be a modern house"): a single-pitch roof with its
  overhang and a door, the icons' wash on its body alone. An active top-bar button is a ring in its own ink rather
  than a solid white fill.
- **The page** (`home/HomeScreen.tsx`) is what a person comes back for: anything waiting on them (update, memo,
  voice model, the Academy), the notes they pinned and the six they were in last as live previews, and every
  unticked to-do from every note (`home/dashboard.ts`), ticked in place by rewriting that one line's box. The
  workspace pills choose what it shows. Every note is a tap away in the sidebar, so the page does not list them all.
- **The notes list is deleted**, with what only it used: its swipe rows (`SwipeRow`, `notes/swipe.ts`), its date
  groups (`notes/groups.ts`) and the empty archive's picture. What it carried that was not the list moved out: the
  notices to `notes/Notices.tsx`, the workspace pills' styles to `notes/WorkspaceBar.module.css`, the glide to the
  top on a workspace change to `core/glideToTop.ts`, and the page's glass bar, scroller and dock to the home page.
- **Left for a decision:** the phone's gist runner (`format/gist.ts`) wrote the line under each row of the list; with
  no list it is never given a note to write for, so it does nothing, but its code is still there.

## 54. A filter on an HTML box, and whose corner it starts from (2026-09-20)

The board lane's foot smoke (`art/wispFoot.ts`) had both of the faults found the same week on the page-level wisps,
and for the same reasons. Measured in Playwright, Chromium and WebKit side by side, on a striped lane 300px tall.

**The placement.** `filter: url(#...)` with `filterUnits="userSpaceOnUse"` does not mean the same thing in the two
engines. Chromium measures user space from the element's own corner. WebKit measures it from the document's corner:
the page's top left, before any page scrolling. A lane places its band at its own foot, so in WebKit the band landed
as far above the foot as the lane sat down the page, and the region - placed in the same frame - stopped covering the
lane at all. Nothing outside a filter's region is drawn, so the cards went with it:

| | band, in rows from the lane's own top | rows of the lane drawn |
| --- | --- | --- |
| Chromium, lane anywhere, any scroll | 272..299 | 136 of 136 |
| WebKit, lane 40px down the page | 232..299 | 134 |
| WebKit, lane 420px down the page | 0..19 | 8 |
| WebKit, lane in a scroller, scrolled | none | 0 |

The page's wisps escape this because `placeRegion` sizes their region to the window from (0, 0), so which corner the
engine starts from makes no difference to them. A lane cannot: its band is somewhere in the middle of the page.

The fix is to stop naming a corner at all. The whole filter is now said in the lane's own box -
`filterUnits="objectBoundingBox"` AND `primitiveUnits="objectBoundingBox"`, every length a fraction of the lane's
width or height - and both engines draw the band at rows 271..299 with every row present, at every scroll position,
in a page and inside a scroller. What that costs is legibility: a length has to be divided by the side it runs
along, a blur needs both of its numbers (one fraction shared between a wide box and a tall one is two different
blurs), and `feDisplacementMap` measures its throw against the box's diagonal over root two.

One attribute must NOT be converted, and converting it shipped a bug. `primitiveUnits="objectBoundingBox"` does not
reach `feTurbulence`'s `baseFrequency`: an engine reads a frequency in the filter's own space whatever the units
attribute says. Converting it with the lengths around it multiplied the frequency by the box, so the noise came out a
couple of hundred times too fine and the smoke read as fine static rather than cloud - Matt, of the tab row's, which
had the same line: "grainy". Measured on bare turbulence at 240x120, neighbouring-pixel difference across and down:
userSpaceOnUse per pixel 1.9 / 5.8, objectBoundingBox per pixel 1.9 / 5.8 - the same cloud, so the units genuinely do
not touch it - and objectBoundingBox times the box 33.6 / 34.7, the static. WebKit gives 1.8 / 5.7, 1.8 / 5.6 and
33.6 / 34.6, so both engines agree and one per-pixel constant serves both.

Worth saying how it got past the first round: the check used to accept the conversion counted mixed pixels per row,
which measures where the band is and how strong it is and is blind to how fine the noise inside it is. The two
filters matched to within 0.2% on that number while looking completely different. The graininess was even visible in
the before-and-after picture taken at the time and was read as the effect working harder. A measurement has to be
able to fail the thing being claimed - the same lesson as the corner probe below, twice in one night.

The subregions stay, converted rather than dropped. Saying it in box units would have been far tidier without them,
and the first draft did exactly that, placing the band with a relative `feOffset` off a region-filling flood so no
absolute coordinate was left anywhere. Measured on two lanes scrolling in headless WebKit, that draft cost 118ms a
frame against 66ms with the subregions kept and 17ms with no filter at all. The subregions are most of what this
effect costs; the shipped filter runs at 67ms.

**The band's geometry**, the same fault the page's foot had at 1.5.0-42. The lip sat in the last 8px of the lane,
inside the 1.2 em mask fade that had already taken the cards to nothing, so the strongest bend happened where there
was nothing left to bend and what showed was a plain dark gradient. The lip now sits `LIFT` = 18px above the foot -
half the page's 36, as this band's lip and ramp are half the page's - so full strength begins 26px up, above where
the fade starts. Measured as smoke surviving above the fade's start: 1921 px of ink before, 6077 after, 3.2x.

The fade is derived from the lip (`WISP_FOOT_FADE` = `BAND + LIFT - 4`, set on the lane as `--cm-lane-fade`) rather
than written beside it. It was `1.2em`, about 20px in a board's type and about 26px at the largest text size - the
width of the whole lip - so the two agreed at one end of the reader's own dial and not at the other, which is the
kind of drift §51's sister lesson is about.

The raised lip raised the floor with it - a lane had to be 106px to carry the band rather than 88, which took the
smoke off boards written `height=6` (about 91px) - and Matt asked for those back: "make them smoke again", with the
ramp shortened to get them. Shortening it for every lane would have paid for the short ones with a tighter, more
abrupt smoke on the tall ones that already look right, so the band is scaled to the lane instead (`fit`): 1 for any
lane with room for the whole band, and below that the lip, the room above it and the ramp shrink together, which
keeps the band's shape and changes only its size. The fade comes down with it, so `WISP_FOOT_FADE` became
`wispFootFade(height)` - a short lane's smaller band needs a shorter fade or the fade swallows it again, on exactly
the lanes this was for.

Measured against the shipped filter at seven heights in both engines: 106px and up come out identical to the
pixel - same band rows, same ink, same fade - and 61, 74 and 91px, which had no smoke at all, now have it. The
floor is 61px rather than the ~74 the change was costed at, and a board cannot be written shorter than `height=5`
anyway. Under it the lane still keeps the plain fade, since a band that small is a hairline standing in for smoke.

**And the corner is worth knowing about on its own.** `art/wispSides.ts` had read the same divergence as WebKit
measuring from the *window's* corner. That is the same corner while the page is at its top, which is where it was
probed, and it is wrong once the page is scrolled. Settled with a filter whose only primitive is a red square at
user space (0, 0) on a box otherwise drawn plain - the output is clipped to the box, so the square only shows where
the origin falls inside it. Chromium drew it at the box's top in every case. WebKit drew it at the box's top for a
box at document y=0 with the page unscrolled, and nowhere at all for that box at document y=300 with the page
scrolled 300, where the window's corner is inside the box and the document's is 300px above. Nothing in wispSides
changed for it at the time - a row at the top of a page that does not scroll sideways has both corners agreeing
across, which is the only direction it placed anything in - but the note was corrected, and the box-units answer here
was the one that filter wanted: it took it the same day, dropped its `left` test and now smokes a row anywhere on the
page (§55).

The budget (`WISP_EDGE_BUDGET`, §51) is untouched and still guards the region. Whether box units change where
WebKit starts painting an over-budget filter black was NOT re-measured - the probe built for it could not reproduce
the black at 2.3x over, so it proved nothing either way - and the guard earns its place on cost regardless.

## 55. The tab row's smoke, in the row's own box (2026-09-20)

`art/wispSides.ts` - the wisp on the tab row's open ends (`notes/NoteTabs.tsx`) - was the last filter still placed in
user space, and it carried two workarounds for the corner divergence §54 settled. Both are gone: the whole filter is
now said in the row's own box, `filterUnits="objectBoundingBox"` AND `primitiveUnits="objectBoundingBox"`, exactly as
the lane's foot is.

**What it used to do instead.** It could not place anything vertically, so it placed everything everywhere: the region,
the bands and the noise all ran `REACH` = 400px above and below the row, wide enough that whichever corner an engine
started from fell inside them. And across it simply refused the job - `wispSides` took the row's `left` and returned
null unless the row began within a pixel of the page's own left edge, the one place the two frames agree across. A row
anywhere else kept a plain fade.

Neither held up. Measured in Playwright on a striped row 600x57 with both ends open, counting columns of the row that
were drawn at all and where the stripes were bent:

| row's place | before, Chromium | before, WebKit | after, both |
| --- | --- | --- | --- |
| page top, unscrolled | bands at 0..48 / 551..599 | same, 0..47 / 552..599 | same |
| in a scroller, 200px down | bands, 600 of 600 columns | bands, 600 columns | same |
| 900px down, page scrolled 700 | bands, 600 columns | **nothing drawn at all** | bands, 600 columns |
| 900px down, page scrolled 900 | bands, 600 columns | **nothing drawn at all** | bands, 600 columns |
| 300px in from the page's left | **no filter** (the `left` test) | **no filter** | bands, 600 columns |

The 400px reach was never a fix, only a reprieve: it bought exactly 400px of page, and a tab row 900px down a scrolled
document is past it, so WebKit's region stopped covering the row and the tabs went with it. In the row's own box there
is no corner to pick and no distance to outrun. WebKit now matches Chromium to within the one column of antialiasing
it always differed by.

**That table is also where this section got something badly wrong, so read the metric before trusting it.** It counts
columns in which the stripes are no longer pure - where the bend touched them - and by that measure Chromium went
from 5579 px of bent ink to 5582, which was written up here as the conversion leaving the appearance untouched. It
was not. A count of bent pixels cannot tell soft smoke from fine static: both bend nearly every pixel in the band,
and both score the same. The `baseFrequency` conversion below had in fact turned the smoke to grain, the shipped
bundle carried it for nine builds, and the person who caught it was Matt, looking at his tabs. A measurement that
cannot fail in the way the thing itself fails is not evidence, however precise the number it prints.

**The reach could then go.** With the frames agreed, the region only has to hold what the bend can throw, so it is
`SIDE` = 24px on all four sides like any other margin, not 400 above and below. That takes the region from 648x857 to
648x105, an eighth of the pixels, and the filter's cost with it. Six rows scrolling at once in headless WebKit: 131.3ms
a frame before, 29.7ms after, against a 16.7ms floor with no filter at all - the effect's own cost falling from 114.6ms
to 13.0ms, which tracks the area almost exactly. Two rows, the ordinary case, went from 42.4ms to sitting on the vsync
floor. The same shrink relaxes `WISP_EDGE_BUDGET`'s guard, which is counted on the region: a row has to be far larger
now before it gives up and keeps the fade.

**The subregions stayed, converted rather than dropped**, on §54's measurement - they are most of what the effect
costs, and taking them off the lane's filter nearly doubled its cost a frame. So the conversion is the fiddly kind: a
length divided by the side of the row it runs along (`box`), both numbers on every `feGaussianBlur` and `feMorphology`
- one fraction shared between a wide row and a short one is two different blurs - and `feDisplacementMap`'s throw
divided by the box's diagonal over root two (`corner`).

**One attribute must NOT be converted, and converting it is the bug above.** `feTurbulence`'s `baseFrequency` is read
in the filter's own user space whatever `primitiveUnits` says, so multiplying it by the box's sides asked for 26
cycles across a 375px row where 0.07 a pixel was meant - noise hundreds of times too fine, and a displacement map fed
fine noise bends every pixel on its own account: grain, not smoke. It stays per pixel, as every other wisp in the app
writes it (`art/wispEdge.ts`, `wispFormat.ts`). Settled by drawing three strips 375x41 side by side from the one seed
- per-pixel in user space, the same numbers in box units, and the multiplied pair - where the first two are the same
soft cloud and the third is static. `art/wispFoot.ts` carried the same line from §54 and was grainy the same way.

**And the tabs gained a layout they never had.** Dropping the `left` test means a row inset from the page's edge
smokes: checked on the real row pushed 243px in, both ends dissolving where before it wore a plain fade. Nothing in
today's layout puts it there - the row still starts at the page's left edge - so nothing changes on screen for now,
but the effect no longer has an opinion about where the row is allowed to sit.

## 56. A canvas edited (2026-09-20)

Matt: "continue progress on canvases, ship what we have so far". The first slice read and drew an Obsidian canvas;
this one changes it (`canvas/CanvasView.tsx`, `canvas/jsonCanvas.ts`).

- **The gestures the app already has.** Only one of them was Matt's choice - a double-tap on the page makes a card
  of words there, keyboard up (docs/CANVAS.md, choice 8). Moving, opening and taking off were never put to him, so
  they follow habits the app already teaches: a press held on a card lifts it, as a board's card and a tab are
  lifted, and a plain drag pans; a double-tap on a card of words opens it, since a single tap already opens a note
  card or a link card and a double-tap is what a single tap cannot mean; a card open to be written in wears a cross
  that takes it off, lines and all. His to change, and the doc says which are his and which are not.
- **The canvas is what is handed back.** Every change is the whole canvas through `onChange`; the note writes it
  into its body as the spec's JSON with the front matter kept (`withCanvas`), through the same debounce and flushes
  typing has. A card mid-drag lives in the view's own copy (`live`) until it is put down, so the lines follow the
  finger without a save per frame. Positions are rounded to the pixel, as the spec keeps them.
- **The editor once, two ways.** A card of words is the note's editor in peek mode until it is opened, and the same
  editor in the note's own mode while it is; the read-only one is only made near the screen (`Near`), the open one
  at once, and the keyboard is asked for a tick after it mounts.
- **Lines, by two taps.** The third slice: the Line tool makes the next two taps a line, from the first card to the
  second; a tap on a line picks it, and a picked line shows its words and a cross. A tool rather than Obsidian's
  drag from an edge dot, since a finger has no hover to find a dot by. The browser caught what the tests could not:
  in Line mode a tap on a link card ran the card's own handler first and the page left for the address, so Line
  mode is handled in the capture phase, before any card sees the tap.
- **Sizes and groups.** The fourth slice: an open card's corner resizes it, no smaller than a word and a cross; a
  held press on a group lifts it with everything wholly inside it, measured as Obsidian measures it, so a card
  half over the edge stays; a double-tap names a group, and its cross takes the group off and leaves the cards. A
  drag is measured from the canvas as it was at pick-up (`carrying.base`), not from the last frame, so a group and
  its cards move by one amount rather than compounding.
- **More ways in, and the way around.** The fifth and sixth slices: the + is a sheet in the home +'s own look (words,
  a note by its title, a web address), a sidebar row dragged onto the canvas is a card of that note, a card's title
  zooms to it, Shift+1 and Shift+2 do what Obsidian's do, and a minimap draws the cards with the screen's box over
  them. The view lives in a ref so a pan is one style write; the minimap needs it as state, so `apply` mirrors it
  once a frame at most.
- **Pictures, charts, tables, and a toolbar of icons.** The seventh slice: a picture card is the spec's file node
  named by the picture store's own name, so it syncs with the notes' pictures and a vault's picture (a folder in its
  name) is told apart; a chart is a card of words that starts as Mermaid, with the editor's diagrams let through on a
  peek by a `diagrams` prop rather than a second mode; the tools moved to a floating pill of icons at the bottom left
  (Matt: "use iconography instead of text") with the map at the bottom right, and what a line needs next is said
  beside them.
- **The map, redone; a table to the edges.** The minimap tells the kinds of card apart, draws the lines between
  the sides they use, names groups when there is room, wears each card's hue and keeps the canvas's shape centred;
  a drag on it pans. `setPointerCapture` is guarded: a browser throws for a pointer it is not tracking, and the press
  must still go where it landed. A card that is only a table (`isOnlyTable`) loses its padding and the table takes
  the card, edge to edge.
- **The example canvas has one of everything.** "Make an example canvas with images, charts, tables, notes and lines
  linking": Settings > About now lays out a group, cards of words, the example board and the sample note as cards,
  a link, a chart, a table and a picture, with words on the lines between them. The picture is the sample note's
  drawing, made and kept by the picture store as the canvas is added, and left out where nothing can draw it, so
  the canvas is whole in a test and on a phone alike.
- **The map grown, and the screen dragged across it.** "Make the minimap a bit bigger when we click on it and allow
  clicking and dragging to navigate around the canvas": a press grows the map half again (`data-big`, sized by CSS
  with a short transition) and it stays grown until a press lands on the canvas. A drag on it moves the screen's box
  by what the finger moved, so the view goes with the finger and nothing jumps under it; a tap on the grown map
  goes to the spot tapped, while the tap that grew it only grew it. The map is drawn in one `viewBox` whatever its
  size on the page, and a finger's place on it is read from the rendered size at that moment, so a press mid-growth,
  or on a phone where the map is scaled down, still lands where it points.
- **Measured in the browser, not assumed:** a held press of 300ms lifted the card and a move of (60, 90) screen
  pixels at scale 1 put it down at (60, 90); a double-tap made a card with a sixteen-hex id, focused, and what was
  typed was in the saved note with its front matter untouched. In the tests, a move before the hold pans and saves
  nothing.

## 57. The wide window's bar is glass (2026-09-20)

Matt, of the Mac app: "the top header is missing the glass effect, it's showing at the very top but the tabs and
such are fully opaque." The very top is the title strip, 44px under the window's own buttons, and it was glass; the
bar under it was not.

- **What painted it.** On a window wide enough for the notes to sit beside a note, App.tsx stamps `data-split` and
  app.css gave the tab bar a ground of solid paper across the whole window - asked for earlier ("the tabbar should go
  across 100% of the screen even on widescreen"), because the transparent bar over two panes read as though it
  stopped at the divider. Solid was the easy way to make it one bar; it also made it the one opaque thing on a page
  of glass. A phone never had the rule, so the phone kept its glass and the desktop lost it.
- **Glass across the window instead.** The bar now wears the header pane's own mix and blur (`.app-headerPane`),
  so it is still one bar from edge to edge and the cards scrolled under it show through it as they do under the
  title strip. Under it, the note pane's own header pane tints only from the bar's foot down (a gradient that starts
  at `--app-safe-top`), so the bar's tint is not laid on the pane's: two tints would have made the note's side of the
  divider darker than the sidebar's. Blur laid on blur looks the same as blur, so the pane keeps its own.
- **Measured at 1280px with the home page scrolled 226px under the bar:** the bar's ground came out
  `color(srgb 0.017 0.017 0.017 / 0.66)` with `blur(18px) saturate(1.1)`, the pane's a gradient from transparent
  at the bar's foot, and the cards read through both.

## 58. The smoke bench (2026-09-20)

Matt, of the Mac app: "the desktop app is incredibly laggy", and once the cost was found, "can we fix the wisp
animation to be more performant?" The cost is the wisp edge's filter in WKWebView (54 above; art/wispEdge.ts), and
the answer being built is the same smoke as a mask (art/wispMask.ts) behind a switch on the hook. What was missing
was a way to see the two against each other with their cost on the same screen, rather than in numbers relayed
from a hand-built rig through three sessions.

- **Settings › Developer › Smoke bench** (settings/WispBench.tsx, now `src/app/diag/WispBench.tsx`): a page over settings with one scrolling surface
  wearing the hook with `draw: 'filter'`, `draw: 'mask'`, or no hook at all - the app's own hook and its own
  switch, so what a surface wears here is exactly what a note would wear. A frame counter sits in the surface's
  header (the last 120 frames: median, p90, worst, written twice a second from the header, which is over the page
  and not in it, so the writing is not a repaint of the thing being measured). Scroll by hand and read it.
- **The run** drives the surface the three ways the rig did - left alone, one repaint a frame (a mark in the
  scroller with its opacity toggled), scrolling (three pixels a frame, back and forth, never back to the top so the
  header band stays on) - for each drawing in turn, and prints n, median, p90 and worst per cell. Two rules from
  the rig are the clock's (diag/frameClock.ts): a cell ends on the wall clock as well as its frame count and says
  how many frames it got (a four-second cap on a three-second frame gave one frame and no median), and the p90
  stands beside the median (3157ms median against 6507 p90 is what "laggy" feels like). Quick: 180 frames or 8s
  a cell; long: 30s.
- **One surface while measuring.** A frame's length is the page's, so three surfaces would add up. Side by side
  draws all three for looking and says so; a run puts the page back to one. What each cell's surface wore is read
  off the element (`data-wisp-edge`, `data-wisp-foot`, `data-wisp-draw`, the computed filter), not assumed from the
  switch, and is in the row. Copy as text gives the table tab-separated under where it ran (version, app or
  browser, engine, window).
- **The whole app, one way.** A line on the page writes the hook's own override (`glyph-wisp-draw` in
  localStorage) so the app can be flipped to the mask or the filter from its next start and felt, not just read;
  and taken back. "No smoke" is not a thing the app can be told to draw.
- **What the pane's numbers are not.** In the desktop app's browser pane the counter read 1000ms flat: that pane's
  requestAnimationFrame is throttled to once a second while it is not the front window, so nothing read there is
  about any engine. jsdom's frames say nothing either, and the tests do not read them as if they did. The number
  that counts is the one on the Mac app's own screen, which is what the page is for.

## 59. The smoke as a mask, for the engine that cannot afford the filter (2026-09-21)

Matt, of the Mac app: "desktop is still very laggy, can we fix the wisp animation to be more performant?" - the
direction being make it cheap, not turn it off. The measurement (58 above, the lane session's, in the real
WKWebView): free at rest, 585-690ms for one repaint with one band's filter, over four seconds a frame scrolling with
both, against 16-18ms with the filter off; the same page in GPU Chromium at 16.7ms whatever the filter does.

- **Why the filter cannot be made cheap there.** WebKit renders the whole element that wears `filter: url()` into
  a buffer and pushes it through the graph on every repaint, however small the primitives' subregions are; a
  scrolling page repaints every frame. Tightening the subregions changes nothing about that. Moving the filter
  onto a thin band at the header's edge would need `backdrop-filter: url()`, which WebKit does not take (its
  backdrop-filter is the CSS functions only), so a band could only bend a copy of the words - a second DOM of the
  note's top edge, kept in step. Not that.
- **The mask instead** (art/wispMask.ts). The band's shape is made once, as an image: the same turbulence the
  filter uses, `stitchTiles` so it tiles along the edge, over the same soft ramp the filter blurs from its strip
  (a grey strip above the lip on white, `feGaussianBlur` down it), the noise added by arithmetic, the red channel
  taken to alpha and pushed through a steep `feComponentTransfer` table so it tears the words into tendrils rather
  than misting them. The foot is the same picture turned over, with its taller ramp. An image used as
  `mask-image` is rasterised one time and cached; a mask composites on the GPU; nothing is re-rendered when the
  page scrolls under it. The scroller's mask gains a layer per band, added to the ramp gradient it already wore
  (`mask-composite: add`), laid from `--wisp-lip` (the hook writes it: the header's height and the drop) with
  `--wisp-mask-above` of smoke over the lip to reach the top of any header. The drift is the same clock writing
  `--wisp-noise-x/y` into `mask-position` - on the views wearing the mask, not on the root, where a custom property
  written thirty-five times a second invalidates style for the whole document whatever the mask costs (the lanes
  session's point, before any measurement). `filter: none` in that mode: the graph never runs.
- **What it loses and keeps.** The bend: the letters dissolve through the smoke instead of being pulled into it.
  Kept: the smoke, its movement with the scroll, both ends, and the engines drawing the one page the same way.
- **A switch, not a replacement.** `useWispEdge(..., { draw: 'filter' | 'mask' })`; left out, the platform decides
  (the mask in the Mac app, `data-titlebar='overlay'`; the filter elsewhere, where the phone's GPU draws the bend
  for nothing), and `glyph-wisp-draw` in localStorage overrides it for anyone comparing. The view says which it
  wears (`data-wisp-draw`), so the bench (58) and the stylesheet can tell. The lane session's caution stands until
  measured: a `mask-position` that changes every frame is a property change on the masked element, and if WebKit
  re-composites for it the fallback is a fixed band with the drift dropped on the Mac, which the switch allows.
- **Found on the way.** The two modules import each other, and two constants read wispEdge's numbers at
  wispMask's top level: whichever module was entered first, the other's top level ran in the first's temporal dead
  zone, and every page importing the editor failed to load. Nothing at the top level now reads across the cycle.
  And a deploy was refused with every test green: a CodeMirror measure on the animation clock, firing after a
  doneSync test, hit jsdom's missing `Range.getClientRects`, and Vitest exits 1 on an unhandled error. Every test
  now gets the stub (src/test/setup.ts) that images.test.ts had for itself. And three first-in-file tests that mount
  an editor - a cold CodeMirror render, about four seconds idle - timed out at Vitest's five while a second suite ran
  on the machine, and refused a deploy the same way. The ceiling is twenty seconds now (vitest.config.ts). Re-proven
  after 1.5.0-68 on the same Mac by the fork session: the same three first-in-file renders took 8.2, 10.0 and 10.1
  seconds under twelve yes-hogs and passed at the 15s ceiling it had then - by a third, which is why it is twenty.
  A hang still fails at twenty.
- **Seen at 1280px in Chromium with the override:** the note's page wore `data-wisp-draw="mask"`, `filter: none`,
  three mask layers `add`ed, the lip at 130px under a 112px bar, and a heading at the lip dissolved through the
  smoke while the lines under it stood whole.

## 60. The workspace, on the note (2026-09-21)

Matt: "please show the workspace on the view that shows the note itself." The home page said which workspace a
note was in and the note did not, so a note opened from a tab, a search or a canvas card gave no sign of where it
lived; the only place that said so was the cog, a tap away.

- **In the link row.** The note already wore a row under its tape for what it is tied to (plugins/LinkMarks.tsx: a
  Notion board, a repo), and a tap on that row opens the cog, which is also where a note is filed. The workspace
  goes first in that row, as the pill the home page draws it with (notes/WorkspaceBar.module.css `.space`) in the
  workspace's own hue, at the row's size so it sits level with the marks. The row now shows for a filed note with
  no links too; a note in no workspace with no links wears nothing, as before. The list's compact row keeps the
  marks alone: it has its own place for a workspace.
- **Read through the store's hook**, so filing the note from the cog, or recolouring the workspace, redraws the
  pill without the note re-rendering for anything else. The tap's label says both: "In the workspace Cabin. Linked
  to Notion Weekend. Change in this note's settings."

## 61. The Mac window opens as a desktop window (2026-09-21)

Matt: "make the desktop version of the app open in a desktop resolution, right now it opens in a portrait layout."
One `tauri.conf.json` served every platform, and its window was a phone's: 430 x 860. The phone never reads that
block (Android and iOS take the screen), so the only thing it ever shaped was the Mac app, which opened as a tall
strip with the phone layout inside it and had to be dragged wide before the sidebar appeared.

- **1280 x 820, centred** (`src-tauri/tauri.conf.json`): wide enough for the split at once - the sidebar wants 660px
  and a mouse (core/useWideScreen.ts) - and inside a 13-inch laptop's screen with room around it. At two device
  pixels to the point that is 4.2M, still far under the filter region's 2^24 budget (54 above).
- **The minimums stay** at 360 x 560: a window dragged narrow gets the phone layout on purpose, which is how the
  phone's shape is checked on a Mac.
- **Not remembered between launches.** Tauri does not restore a window's last size and place on its own; every
  launch opens at 1280 x 820 in the middle of the screen. Remembering would be the window-state plugin, a Rust
  dependency and a capability, not a number - left for when it is asked for.
- **Reaches the Mac only as a new build.** A window's size is the app's, not the web bundle's, so no over-the-air
  update carries it: it ships as a signed universal Mac build (`deploy-ota.mjs --desktop`), downloaded from
  attack.fm/glyph.

## 62. Lines kept apart, labels kept off the cards (2026-09-21)

Matt, with a screenshot of the HelloTrade canvas: "No two arrows should render pointing too close as they look
joined like a diamond. Secondly the text that's on arrow paths sometimes overlaps content and we can't read the boxes
below." Both were the geometry's: every line end sat at the exact middle of its side, and every label at the exact
middle of its curve, whatever else was there.

- **The diamond.** Two lines into the facing sides of neighbouring cards land at the same height, their heads base
  to base in the gap between - one shape with a point at each end. Lines are now drawn together rather than one by one
  (`edgePaths` in canvas/jsonCanvas.ts): ends that share a side of a card are set along it, `END_SPREAD` (28px)
  apart, in the order their far ends come so the lines leave without crossing; and two heads on different cards
  nearer each other than `HEAD_CLEAR` (56px, three heads' lengths) are moved apart along their own sides until they
  are that far apart, each going away from the other along the side's axis, or when level, the one whose line comes
  from further along that axis going that way. An end keeps 16px from its side's corners. Alone, a line lands on the
  middle as before.
- **The label.** It tries the curve's middle and then either way from it, in steps of a twentieth, and takes the
  first point where its box (about 6.8px a letter at the label's 13px, 20px tall) is over open canvas and not over
  a card. A group is open canvas. Where one line fits nowhere it is broken onto two, then three, and the tries run
  again, so words longer than the gap between two cards fit down it (the example canvas's "every mark a note can
  hold", 26 letters between two cards 120px apart, goes on two). Where nothing fits anywhere it sits in the middle
  on one line as before and the halo does what it can.
- **Measured in the tests with the screenshot's shape:** two cards 40px apart, a line into each from above, tips at
  (300, 100) and (340, 100) before, 56px apart after with each still on its own side; two lines into one side
  landing 14px either side of its middle; a label on a straight line over a third card moved to the first clear
  stretch, left on a group, and back at the middle under a card the length of the line.

## 63. The app is Ghost.md (2026-09-21)

Matt: "rename the app from Glyph to 'Ghost.md' since we got that domain name." The rule the rename follows, so the
next person knows what was and was not meant to move:

- **What a person sees is Ghost.md.** Every line of copy in the app (the guide, About, notices, the palette, the
  plugins' pages and their authors, the AI prompts' "inside Ghost.md, a notes app"), the page's title, Tauri's
  `productName` and window title (so the Mac app is Ghost.md.app and the Android launcher says Ghost.md), the
  download pages, the MCP sign-in page and tool words, the sync service's Notion pages, the README. The two example
  canvases and the sample note say it too.
- **What a machine relies on stays.** The bundle and package ids (`com.mattssoftware.glyph`), every localStorage key
  (`glyph-developer`, `glyph-wisp-draw`, ...), the sync salt `glyph/v1/<handle>` (changing it would change every
  account's keys), the `glyph1.` token prefix, the attack.fm/glyph paths and API bases (they move with the domain,
  separately), file and script names, the repo and package name, the design log's history and its quotes.
- **The spoken word is "Ghost".** Nobody will say "dot md" to a phone, so the address a command follows is the short
  name: "Ghost, add a table to this note". The recogniser (capture/command.ts `findKeyword`) accepts "ghost" and what
  speech recognition writes for it beside "glyph" and its own mishearings, so the old word still works and the
  recorded voice suite still passes. Not accepted: "coast" - a mishearing tried and dropped the moment "Packing for
  the coast" lost its last word. Two things worth Matt's eye: "ghost" is a commoner word than "glyph" was, so a
  sentence that starts with it and is not a command will now draw the "no command there, the words stay" notice
  where it did not before; and the Android settings path the guide walks ("Digital assistant app › Ghost.md") says
  the new label before the phone shows it, until the next APK.
- **Reaches the phone and the Mac only as new builds** for the label and the bundle name; the copy goes over the
  air.

## 64. The ghost in the empty places (2026-09-22)

Matt, with the dotwork scenes generated: "process them to be smaller sizes and then wire them all and ship an OTA
update" (docs/GHOSTS.md has the prompts and the table of where each went).

- **One file for both themes.** The pictures are black dots on white. A plain image would have stayed black on the
  dark theme, whose paper is black, and a second dark set would be fourteen more files to keep in step. Instead
  each picture is a mask - the dots are its alpha - and `art/Ghost.tsx` paints a square of `currentColor` through
  it, so the ghost takes the page's ink like the words do: black dots on the light page, white on the dark, in
  `--app-ink-3` by default. Seen in the browser in both themes.
- **Small enough to ship over the air.** 2048px PNGs of 2-4 MB became 600px WebP masks of 28-55 KB (sharp at 200px
  on a 3x screen), 608 KB for all fourteen, imported through Vite so each is hashed and cached like the code.
- **Three sizes**: 12.5rem where the picture leads a page (the empty home page), 7.5rem beside words - the abstract
  shapes' size - and 4.5rem inside a card. Each drifts up and back slowly with long rests, a transform, and holds
  still under reduced motion.
- **Twelve places, and two scenes with none.** Where a page already had words for the moment the ghost sits over
  them; the trash and archive are only shown when they hold something, so their scenes wait for a page, and the app
  has no error screen for "something went wrong". A new note shows its ghost under the first line - over the
  editor, not after it, because the editor grows to fill the page and after it the ghost sat at the foot of the
  screen - and it goes at the first word and comes back if the note is emptied.
- **"Every to-do is done"** needs to know there were to-dos: `tickedTasks` counts the ticked ones (outside code
  fences and the archive), so a page that never had any says nothing.
- **Then twice the size each way** (Matt: "the graphics are too small they should take up at least 4x more space"):
  25rem leading a page, 15rem beside words, 9rem in a card, each capped at its column so a phone's leading ghost
  fills the page's width (331px at 375) rather than overflowing. The masks were remade at 1024px so they stay sharp
  at that size on a 3x screen: 2.0 MB for all fourteen. At 400px the empty home page's stack put "A blank page." at
  the foot of a laptop screen, under the foot's smoke, so where the page is wider than 44rem the ghost and its
  words sit side by side (a container query on the home page's column).

## 65. A quieter guide, and a note that teaches formatting (2026-09-22)

Three asks in a row from Matt.

- **"remove the ghost icon from the welcome page."** The welcome page opens on its headline and its gags again; the
  ghost stays everywhere else it was placed (docs/GHOSTS.md).
- **"on the theme page remove the effect that flicks it on and off and whatnot automatically it's annoying."** The
  page flicked the whole theme light and dark four times by itself, to show there was a choice (GloveSwitch, and the
  code that put the theme back if the person left without choosing). All of it is gone, file and all: the page is
  still until a choice is tapped, and its line says "Pick one to see it. You can change it later in Settings."
- **"remove the step showing markdown and instead just replace the 'everything a note can hold' as a short tutorial
  for formatting everything."** The guide's Markdown step ("The marks, and how to say them") is taken out, so the
  guide is six pages; its cheat sheet page ("Every mark, side by side", which Settings opens directly) stays. The
  sample note is now "How to format a note": for each mark, how to type it, the word to say for it while recording,
  and one example, short, ending with press-and-hold Style. It still holds one of every mark the editor draws - its
  test says so - so it is still the note that shows everything, only now in the order a person learns it.

## 66. The strip behind the clock is the bar (2026-09-22)

Matt, of the Fold's inner screen: "The very top bar where the time and battery and stuff show up still has the
missing semiopaque black background like the rest of the headers have so it looks different." Two sessions had read
the strip as the activity's window background - the page not drawn under the status bar - and the Android 16
emulator, which draws the page under the bar, did not reproduce it. The second screenshot did what the first could
not: the strip had a soft light gradient in it, which is what blurred, untinted cards look like. The page was under
the bar all along; the strip was missing the tint.

- **Why only there.** On a phone the screen's header pane covers the strip, tint and blur, from the top. On the split
  layout (`data-split`, which the Fold's inner screen is: wide and tall) the tab bar is glass of its own across the
  window and began at `--app-inset-top`, under the status bar, while the pane's tint below it starts where the bar
  ends (`--app-safe-top`) so the two would not stack. Between the screen's edge and the bar's top nobody tinted: the
  pane's blur reached it, its tint did not, and the scrolled cards showed through lighter than through the bar - a
  grey gradient over a black bar. The Mac's 44px title strip is the same case.
- **The bar reaches the top.** `:root[data-split] .app-tabBar` now starts at 0 and pads down by the inset, its height
  grown by the same, so the strip is the bar: one glass from the screen's edge to the bar's line. Its bottom edge,
  `--app-safe-top` and the pane's gradient are as they were, so nothing under it moves; the Mac's drag bar (z 41)
  still sits over it (z 5). Measured in the pane at 1024px with a 40px inset forced and the home scrolled under the
  bar: bar top 40 and height 108 before, top 0 and height 148 after, the row's top at 50 (inset plus the bar's own
  inset) either way.
- **What was learned about measuring.** A pixel average of a JPEG told two people "nothing the page paints" when the
  strip was the page's own blur without its tint; the emulator told the truth about where the page was and nothing
  about how it was tinted. The picture that settled it was the one with a gradient in it. A Developer › Window
  section (§ above) now says the inset the page is given, so the first question - is the page under the bar - has a
  number next time.

## 67. The ghost, still, and as big as the room (2026-09-22)

Matt: "I want the ghost pictures not to float and also they can be larger even still, try to fill 100% width or
available height without going too big."

- **Still.** The slow drift up and back is gone, keyframes and all (art/Ghost.module.css).
- **As big as the room, within limits.** A ghost beside words is the column's whole width, up to 40% of the window's
  height and 28rem; one leading a page up to 60% of the height and 36rem; the one in the update card stays 9rem, since
  filling the card would push its words out. Measured at 1280x800: the empty home page's ghost 480px (60% of 800)
  beside its words, the sidebar's 320px in a 337px column, a new note's and an empty canvas's 320px. At 375x812 a new
  note's is 325px of the page's 331, nothing wider than the screen.
- **Two places needed a definite size to be a share of.** The wide home page's side-by-side grid had an auto column
  sized by the ghost, and a width of 100% of that is circular; it is now three parts to the words' two. The empty
  canvas centres its ghost in a grid sized by its content, so its ghost is sized by the screen instead.

## 68. The ghosts cropped to their drawings, and a small one in the update card (2026-09-22)

Matt: "Trim all the white space from around the images we recently added and make the one on the update banner
smaller as right now it makes the update banner huge."

- **Cropped.** Each picture was a square with the drawing in its middle. Now each is cut to its drawing with a 2%
  edge so no dot is lost, remade from the original at 1024px on its long side (2.6 MB for all fourteen). None is
  square any more - from 0.29 wide per unit of height (the trash) to 1.47 (the empty canvas) - so each ghost's box
  takes its picture's shape (`GHOST_RATIOS` in art/ghosts.ts, `--ghost-ratio`), and the limits on height are limits on
  the drawing: a ghost is its column's width, up to 28rem, and up to 40% of the window's height.
- **The update card's ghost is 3rem tall**, about two lines of the card's words: 36 by 48px, and the card 84px tall,
  measured with the real card mounted in the browser. At 9rem wide it had made the card as tall as the ghost.
- **The home page, measured after cropping.** A cropped ghost fills its box, so the old limit put the empty home page's
  ghost behind the dock's buttons on a laptop (its foot at 777px, the dock at 738 in an 800px window), and on a phone
  put the second line of words under the dock. Leading a page it is now up to 45% of the height beside its words and
  38% stacked over them: 360px tall ending at 657 on a laptop, 309px ending at 590 on a phone, the words clear of the
  dock on both.

## 69. Faster: note previews built once, rows that stay put, settings parsed once (2026-09-22)

Matt: "Go through the app and investigate how we can get better performance on desktop and mobile check for render
storms and others", then "Do it". Measured before touching anything, in headless Chromium with 150 notes, with
counters installed before React (commits, what rendered and where each render began, frames, timers, listeners,
observers, long tasks, localStorage reads and JSON parses), on the dev build and the production build, at a laptop's
width and at a phone's with the CPU slowed four times.

- **What was fine.** No render storm across the app. Idle does nothing: no commits, no animation-frame loops, no
  polling but the five-minute sync. Typing in a note's body is four commits for forty-one keys; scrolling a note two.
- **Note previews were editors, built again every time.** Each card on the home page and each of the sidebar's rows
  is the note's own editor, read-only (notes/NotePeek.tsx), mounted as it neared the screen and torn down as it left.
  One scroll down a 150-note sidebar built 276 editors, 5.4 s of CPU in the dev build, with long tasks of 51-71 ms;
  going home built the home cards' again, three long tasks of about 80 ms. Now a card keeps what its editor drew -
  its HTML, for that text in that theme - and lets the editor go: any card of the same text comes back drawn, with no
  editor, and the formatter is the note's own as before, run once per note per session. After: going home builds
  none (one long task of 54 ms, from three), scrolling home has none (from three), the first scroll down the sidebar
  three of at most 55 ms (from nine to thirteen, up to 76); every later scroll builds none. Every card watches the
  screen through one shared observer, not one each (156 before).
- **The sidebar re-rendered every row whenever the app shell did.** Opening a note rendered the shell three times and
  each time all 150 previews, 450 renders; typing in a note's title did it every keystroke. The preview is memoized
  (its props are two strings), so a row whose note has not changed is skipped: opening a note now renders none of
  them.
- **Settings parsed on hot paths.** The Notion and GitHub links were read and parsed on every keystroke through the
  plugins' suggestions, and four plugin keys on every render of a note: about a hundred parses for forty-one keys.
  The home page parsed the whole AI-results sheet once per card, 24 times. Both now keep what they parsed with the
  text it came from (plugins/host.ts, format/results.ts): a read still asks localStorage for the text, which cannot
  be stale however the key was written, and parses only when it has changed. The value is shared, so the four places
  that changed what they read - linking a board, linking or removing a project, keeping an AI result - copy it first.
  After: four parses for forty-one keys.
- **Not done, and why.** The main bundle is 2.54 MB (757 KB gzipped) and loads whole; splitting out the guide,
  settings, canvas and recorder is a larger change, left for its own pass. The Mac app's WebKit was not measured -
  control of the app was not given and it was not used while a watcher sampled it - so what WebKit alone makes costly
  (the smoke, the stacked glass) is still to be read on the Mac, from Settings > Developer > Smoke bench. Headless
  Chromium draws a frame only every few hundred ms, so key-to-paint latency was not measured either.

## 70. Books: notes in an order, with an index (2026-09-22)

Matt: "add a Book feature it should be a collection of organized notes with an index." Built the way boards and
canvases were: a book is a note, its index is its body, and Markdown anywhere reads it (docs/BOOKS.md).

- **The shape.** One line of front matter, `book: true`, makes a note a book; the `title:` names it as a canvas is
  named. The body is a list of `[[links]]` to the chapters in order, a chapter indented under the one before being a
  part's chapter (2.1). The book's own words - a paragraph before the list - stay and show over the index. A chapter
  is any note, found by its title; a title with no note is a chapter still to be written, and opening it makes the
  note the way opening any `[[link]]` does.
- **Drawn as its index** (book/BookView.tsx) where the note's words would be, the Markdown a toggle away in the
  header, exactly as a canvas's JSON is - the same switch, the same rename from a tab's menu, the same write through
  `onChange` on typing's debounce, so the index behind the view and the view are one thing. Rows open chapters; each
  moves a place up or down or comes out of the book, and no edit touches a chapter's own note. Two ways in: a
  chapter named here and opened at once, or a note already written, picked from the library's titles less the
  book's own and those in it.
- **A chapter wears its book** (BookBar under the link marks): the book's title, the place (2 of 5), the neighbours
  either side. Found by title (`bookOf`): the first book in the library whose index names the note; a note in two
  books shows the first.
- **The + makes one** (notes/NewSheet.tsx): "New book", empty, opened on its index.
- **Decided without asking, said here so it can be undone:** the index is a list in a note rather than a folder or
  a kind of its own (a folder cannot hold an order or a preface, and a note syncs, links and opens everywhere a
  note does); one level of parts; rows move a place at a time rather than by drag; no reading-through view yet.
  Not built: reading a book straight through as one page, making one by voice, a book mark in the list.
- **Seen in the pane:** a book from the +, its empty index; "First steps" added by name, the chapter opened wearing
  "New book · 1 of 1"; the book opened from the bar with the row in it. 16 tests of the model and the view; the
  suite 1115 green.

## 71. The scrollbar starts under the header, not behind it (2026-09-22)

Matt: "On the home page the scrollbar goes behind the header."

- The home page's list, like a note's page, runs the whole height of the window so its words can pass under the
  header's glass, and its scrollbar ran with it, from the window's top edge, under the blur.
- The hook that already measures the header for every such view (art/wispEdge.ts, `--wisp-under`) now marks the view
  `data-under-header`, and one rule in app.css starts that view's scrollbar track where the header ends: a slim rounded
  thumb in the page's ink on no track. Measured at 1280x800: the home page's header ends at 73px and so does the top of
  its scrollbar's track.
- Only where there is a pointer (`hover: hover` and `pointer: fine`): styling a scrollbar gives up the platform's own,
  and on a phone the thin one that shows only while scrolling is the right one. Chromium and WebKit both take the
  track's margin; checked in Chromium, and the Mac app's WebKit reads the same rule.

## 72. A book made from the +, with its pages picked; a Library on the home page (2026-09-22)

Matt: "Expand in the UI/UX for creating books allow choosing existing notes as pages etc etc and make a library
section on the home dashboard for books." The first slice (§70) made an empty book and left the pages to its index;
this is the front door.

- **The New book sheet** (book/NewBookSheet.tsx), in the New sheet's own shell: the name, then the library's notes
  under a search, each a row that ticks - a tap puts a note in the book, a second takes it out - with the pages so
  far listed above in the order they were tapped, each movable a place or left out. *Make the book* writes one note
  with that index (`bookNoteBody(title, pages)`) and opens it; closing the sheet writes nothing. Books are not
  offered as pages: a book of books is a thing for another day.
- **The index picks several at once.** *Add a note you have* on a book's index now ticks any number and adds them
  in the order ticked, the same rows as the sheet's.
- **The Library** on the home page (home/HomeScreen.tsx, `bookNotes` in home/dashboard.ts): between Pinned and
  Recent, a card per book - its name, "3 pages", the first four as a small numbered index, when it was last
  touched - a tap opening the index. A book is no longer also a Recent card, so nothing shows twice; the archive
  stays out, as everywhere on the page.
- **Seen in the pane:** the Library with the first slice's book; the +, Book, the sheet; "Field guide" made from
  two notes tapped in order and opened on its two rows. Tests: the sheet (a name required; pages in the order
  tapped, found by name, moved, left out; the index made from exactly them), the dashboard (books newest first,
  the archive out, Recent without them), the index's picker adding two at once; 280 green around the change.

## 73. "Hey Ghost", memo mode gone, and Claude's connections counted (2026-09-22)

Three answers from a multiple-choice round Matt asked for ("ask me outstanding questions with multiple choice
answers I can click on"), built together.

- **"Hey Ghost".** The rename made the spoken word "Ghost" (§63), and "ghost" is a common word: a note that begins
  "Ghost stories…" was a command with no command in it. Matt chose "require hey Ghost for the new word": the
  recogniser (capture/command.ts) takes the new word only after "hey", "hi", "OK" or "so", and "Glyph" with or
  without them, as it always did. The copy that says the word says "Hey Ghost". (§136 made the word optional and
  took away its Settings row, "Commands start with “hey Ghost”".)
- **Memo mode is gone.** The memos screen went on the 20th; Matt chose "remove it" for the capture side. Out: the
  memo flow that asked which note first and answered trigger words, the `memo` preference and its synced entry and
  its row, continuation of the last spoken note, the scratch page and the memo-sorting screen, the waiting-memo card
  and palette entry, the flow's tips, the suite's eleven memo scripts. A recording is a new note, or the note whose
  Speak was pressed. Kept on purpose, being a different feature under the same noun: voice memos, the "voice memo …
  end memo" cue that keeps a clip of the tape inline. The draft, the live page, the better words and the suite kept
  writing with one `appendBody`, which now has a file of its own.
- **Claude's connections.** Several Claude accounts, or Claude on several computers, can be signed in to one Ghost.md
  account, each its own session with its own copy of the key, and nothing said so or could cut one off short of a
  restart. Matt chose "add both": `account_status` says `connections`, and `sign_out_everywhere` ends every session
  for the handle, this one included. The local server is one connection and hands in neither. They reach the box
  with the api.ghost.md move (blocked at the registry as of tonight: the domain is not delegated), or a --mcp
  deploy of their own.
- **A chapter made twice, prevented.** App.tsx `openTitle` made a note by a title from the list in hand, which can
  be a moment old; it asks the store again first.

## 74. Books: a mark on their pages, pages dragged into order, and a book read straight through (2026-09-22)

Three of the four Book slices Matt picked from the multiple-choice round (the fourth, making one by voice, is next).

- **A page says which book** (home/HomeScreen.tsx cards, notes/NoteTree.tsx rows): a title-to-book map built once
  per notes change (book/book.ts `bookIndex`, keyed the way `[[links]]` match), and a note that is a page wears the
  book's mark and name under its title. A book itself, or a note in none, wears nothing; a page in two books is
  marked with the first, as the chapter bar says.
- **Drag to reorder** (book/rowDrag.ts): each row has a grip; a finger holds 220ms before the row lifts, so a finger
  that meant to scroll still scrolls, a mouse lifts at once; the pointer is captured, the lifted row follows, the
  others make room, and on release the page lands where it was let go - in the index a chapter moved to a place,
  taking that row's depth (`withChapterAt`); in the New book sheet the pages reordered before the book is made. The
  shape the canvas and the tab row already drag with. The arrow buttons stay for the keyboard.
- **Read straight through** (book/BookView.tsx): the chapters one after another, each under its numbered title in
  the note's own editor, read-only, in the peek mode NotePeek draws with - the same formatter the note opens with -
  with the front matter and the chapter's own heading taken off (`bodyWithoutTitle`; `withoutFrontMatter` puts the
  front matter's title where the fences were, so that line goes too). A canvas chapter says so and opens on a tap; a
  chapter not written says so. A rail at the top scrolls to each; Index goes back.
- Tests: the map (first book wins; a book and a loose note answer nothing), the move-to-place (depth taken from the
  landing row; the ends), the drag (a mouse at once; a finger after the hold; a move before the hold is a scroll;
  a row let go where it was says nothing), the read-through (order, the canvas and the unwritten said, the rail,
  the way back), the body without its title.

## 75. Sharing a note or a book by a read-only link (2026-09-22)

Matt: "I'd like to be able to share books and notes with people online and allow them to read only the notes and
give them areas to fork the note into their own Ghost.md app." His answers: anyone with the link, encrypted; the
share follows his edits; a small reader page made only of the app's own parts; and keeping a copy either as a
Markdown download or as a copy saved into the reader's app. docs/SHARING.md has the whole of it.

- **The key stays in the link.** A share is sealed on the owner's device with a key of its own, and the key rides
  after the `#`, which browsers never send. The server holds ciphertext by an id, the same promise sync makes.
- **Edits follow.** Three seconds after a save, any share whose note (or, for a book, any chapter) changed is
  sealed and sent again under the same link. Stopping a share deletes it.
- **The reader page** is read.html, a second Vite entry: the editor read-only in its formatted view, the canvas
  read-only, a book's index and its chapter bar. It adds nothing the app doesn't already draw, so the formatted
  view's kept marks (a to-do's box, a wiki link's brackets) show here as they do there.
- **Keeping a copy.** Download gives the `.md`, or a `.zip` of a book's pages. Saving goes through the web app's
  `#fork=` or, in the phone and Mac apps, the + sheet's new "From a shared link". A copy is the reader's own: it
  doesn't follow, clashing titles take "(shared)", and a book's index is rewritten to name the copies.
- **The book bar on a phone.** A side of the bar was sized to its title and ran into the count at 375px wide; it
  now shrinks with an ellipsis, in the app as well as on the reader page.
- **Server:** a `shares` table and four routes beside sync (server/src/shares.rs), limits on size, count per
  account and public reads per IP. It needs a glyph-api deploy before any of this works outside a local run.
- **Seen in the pane, against a local server:** a book with a to-do list, a table and a canvas chapter, shared from
  the cog; read on the reader page at desktop and phone widths; downloaded as a zip; saved back twice, once by the
  web link and once by the + sheet ("(shared)", then "(shared 2)"); an edit read through the same link after the
  three seconds; the link reading nothing after "Stop sharing". Tests: sealing and links, what a note and a book
  share, the fork's renames, the downloads, the zip's CRC; the server's owner rules and limits.

## 76. A right-hand aside (2026-09-22)

Matt: "Add a right side aside menu that can pop out book indexes and list other notes from the workspace when not
in book view, add a sidebar toggle on the right with the icon reversed."

- **The toggle** (notes/NoteTabs.tsx): the sidebar's own icon, mirrored, at the tab row's far end; `aria-expanded`
  says which way it is, and the choice is kept to the device (`glyph-aside-shown`), hidden until opened once.
- **The shell** (App.tsx, app.css): on the split layout a third column, `clamp(240px, 22vw, 320px)`, beside the
  note - the sidebar's mechanism mirrored, `data-aside` on `.app-split` as `data-sidebar` is; on a phone a panel
  over the note from the right under a scrim, closed by the scrim, its X or the back gesture. Opening a note from
  the phone's panel closes it; the column stays.
- **What it holds** (aside/aside.ts, pure): with a book on screen - a page of one, or the book itself - the book's
  index, the open chapter ringed the way the sidebar rings the open note, a tap opening another, the book's title
  opening the book; anywhere else the workspace's other notes in the list's order, the open one and the archive
  left out, named after the workspace or "All notes".
- Tests: the two faces from the notes and the open note; the component's taps and its close.

## 77. A book stays in one tab (2026-09-22)

Matt, seeing the first cut: "the book should open in one tab instead of each page opening in a new tab." Every note
shown became a tab (notes/openTabs.ts `addOpen`), so reading a book left a tab per page behind.

- **The rule** (`swapOpen`): a page opened from inside a book - the index, the chapter bar, the right-hand aside, the
  read-through - takes the current tab's place. A page that already has a tab is used and the book's closes, so the
  row never gains a tab for a page. A `[[link]]` in the words still opens a tab, as any link does.
- **The mechanism** (App.tsx): the tab to give up is noted in a ref by `openTitleWithin` / `openNoteWithin`, and the
  effect that turns a shown note into a tab reads it once; `openNote` and `openTitle` clear it first, so a note opened
  any other way after a book's is not swapped by mistake. The note screen hands `onOpenWithin` to the index, the bar
  and the read-through; the aside opens "within" when it shows a book.
- Tests: the rule's four cases (in place; the page's own tab used and the book's closed; added where the row has no
  tab to take; the same note twice changes nothing).

## 78. Making a book by voice (2026-09-22)

Matt's fourth Book slice: "Make one by voice." Two commands, both read by the rules in capture/command.ts and asked
about before they act, as every command is.

- **"Hey Ghost, make a book called Field guide"** makes the book note, empty with its index ready, beside the
  recording, which carries on where it was; the next command can name the book. Pages can follow the name ("…with
  Trees, Birds and the work note"): each is a note found by its spoken title, the way any named note is, or a chapter
  still to be written when no note answers to it. Said without a name, the recorder keeps listening for one, as it
  does for any command that has not said enough. Only make, create, start, begin and new open a book, because "add a
  book to my reading list" is a book for a list, and that is what it stays.
- **"Hey Ghost, add a chapter to the field guide"** and then the name, or the name in the same breath ("add a chapter
  called Rivers to the field guide", "put Rivers in the field guide"). The rule under it: a note that is a book gets
  chapters, never words. Whatever the rules or the phone's command model would have placed in a book is read again as
  a chapter (`forBook`), so the model's "add" lands right without its prompt knowing what a book is, and the prompt
  stays as it was measured (§ understand.ts). "Add this to the field guide" and "move this to the field guide" make
  the note being recorded a chapter, which is all that moving a recording into an index could mean. A chapter the
  book already has, the book itself, or a note with no name yet is said and not offered.

Nothing new is asked of the person: the card is the one a board's lane uses ("New chapter in Field guide", Add), and
the book's card lists its pages. The take is tested without a recorder (capture/take.test.ts), the way the voice
suite drives it.

## 79. The aside is the drawer's card (2026-09-22)

Matt: "The new right hand sidebar doesn't match the floating left sidebar." It didn't: the aside (§76) was a docked
column on the split layout and a full-height slide-over under a scrim on a phone, while the sidebar is, by default,
a floating card hung from its icon (notes/NotesDrawer.tsx; Matt: "sidebar should open and close in a popover not a
full sidebar even on desktop"), and a column only when Docked is chosen in Settings.

Now the aside's shell follows the sidebar's. With the sidebar a card, the aside is the same card at the right
(`AsideCard` in aside/Aside.tsx, drawn by the drawer's own stylesheet with one rule for the right side): the same
radius, blur, border and shadow, growing out of the mirrored icon that opened it, the page live beside it, closed by
a tap outside, Escape, the phone's back gesture, its X, or opening a page; its own icon is left to close it, as the
drawer's is. On a desktop and a phone alike, since the drawer is the same on both. With the sidebar docked, the
aside is a column beside the note, as it was. The scrim and the slide-over are gone: there is one floating surface
in the app and now two things use it.

## 80. Chapters numbered in their titles; no aside when it has nothing to show (2026-09-22)

Matt: "the top of the glossary for the hello trade book randomly has task management in it twice, the numbers for
the chapters are also all out of order". His book's index had no `book: true`, so the app didn't see a book. The
aside fell back to every other note by last change: his two Task Management notes, then the chapters in the order
they were saved. His answer: "make chapters numbered with some standard identifiers for books maybe at the end of
the title and that should let us lay out the chapters in order when there is no book on the page and there is no
use for the aside don't show it".

- **The standard** (book/chapterNumber.ts, docs/BOOKS.md): "Ch." or "Chapter" and an Arabic or Roman number at the
  end of the title, as in "The risks · Ch. 8". A number in front ("08 · The risks", "Chapter 8: The risks") is
  read too, as his chapters are written. "Top 10", "Batch 5" and "Chapter mix" are not chapter numbers.
- **A run without a book:** the numbered chapters whose pages first point at the same note, else those in the
  same folder, in number order, headed by that note's name. His chapters all start "« [[HelloTrade — The Book]]",
  so they line up 1 to 35 under that name.
- **No aside when it has no use:** the workspace-notes fallback is gone (§76 had it). With no book and no run, the
  aside and its toggle aren't drawn.
- **Not changed:** the app doesn't write numbers into titles, and a book's own index keeps its written order.
- **Seen in the pane:** chapters saved out of order under a book that isn't marked as one, with two Task Management
  notes newer than them. The aside lists 1, 2, 6, 8, 9, 10, 35, the glossary marked. Opening 35 from it replaces
  the tab. Task Management and the home page have no aside and no toggle. The floating card shows the same run.

## 81. The reader page's banner (2026-09-22)

Matt: "The buttons on the read page are too big and should be in a banner at the top that prompts to download the
app too". The header's two full-size pill buttons are now a slim sticky banner across the top. It holds the name, a
line with "Get the app" (the install page beside the reader), and two small buttons: "Save a copy" and ".md" or
".zip". The buttons dropped the app's `app-word` class, whose tap-target height made them 63px tall. They're 32px
now, still a thumb's width. On a phone the line keeps only "Get the app". The save panel ends with "No app yet?
Get Ghost.md". Seen in the pane at 1280 and 375 wide: the banner is 54px and 51px, with no sideways scroll.

## 82. The reader page draws with the app's own code (2026-09-22)

Matt: "For read.html use the exact code we use for formatting the note and stuff so it matches the formatting of
books and such that the real app uses". Two parts of the reader differed from the app.

- **Books.** The reader had its own list of chapters. It now uses book/BookView.tsx with a new `readOnly` prop,
  which hides the grips (and so the drag), the move and take-out tools, and adding. The preface, numbers, canvas
  marks and "Read straight through" stay. A `dark` prop lets the reader's system setting win over the preference,
  which defaults to dark, so a read-through in light mode draws light.
- **Notes.** The reader showed the Formatted view, with the marks hidden. The app opens a note in the preference's
  default, Markdown with the marks dimmed, so the reader now does the same, with the note screen's `grow`.
- **Seen in the pane:** a book with a preface, a formatted chapter, a canvas and one not written. The index,
  chapter and read-through match the app at 1280 and 375 wide, dark and light.

## 83. A canvas in a frame inside a note (2026-09-22)

Matt: "Please make it so we can embed a frame of a canvas within another note so we can browse the canvas from
within a frame inside the note." docs/CANVAS.md had pencilled this in as a ```canvas fence with the JSON inline;
what was asked for is different and better: a note frames a canvas that already exists, so there is one canvas,
changed in one place, seen from every note that frames it.

- **The syntax is Obsidian's embed**, `![[Cabin weekend, laid out]]` on a line of its own (editor/canvasFrames.ts).
  The words are a wiki link with a `!` in front, so the note reads as a link to the canvas in any other app, and
  the link machinery already in the editor - matching a title as a person says it, backlinks, the dashed "not yet
  written" look - comes for free. A title that names a note of words, or nothing, stays the link it is: the frame
  is for canvases, which is what was asked, and a note of words has its own way of being read.
- **The frame is the canvas note's own view** (canvas/CanvasView.tsx) with no `onChange`: browsable, not
  changeable. Pan, zoom, the minimap, every card drawn as it is on the canvas, the whole of it fitted to the frame
  to begin with. Nothing was written twice: the view already knew how to be read-only, since the reader page and a
  book's read-through use it that way. Over it, the canvas's name and an Open, which opens the canvas note itself.
- **A block widget from a state field**, as pictures and diagrams are, because a block's height must be known
  before layout. The caret on the line shows the link as typed, the way a diagram's fence does (editor/mermaid.ts),
  and leaving it draws the frame again; a press on the name in the bar puts the caret there. Every gesture inside
  the frame is the canvas's, so a drag pans the canvas and never the note; the note scrolls from outside the frame.
- **Not on a card.** A canvas draws a note card small with the editor in its peek mode, and the frame is off there:
  a canvas framed in a note framed in a canvas would nest without end.
- **Fresh when the canvas changes.** The frame is keyed by the canvas note's body, and the editor looks at every
  frame again when the notes change under it or the app is repainted; a frame whose canvas is the same is kept, one
  whose canvas changed is drawn again.

The canvas's own JSON parse is cached by body, so a keystroke elsewhere in the note parses nothing. The reader page
(src/read/) does not draw frames yet; a shared note shows the line as the link it is.

## 84. The dead space under a note on a wide screen (2026-09-22)

Matt: "on the bottom of the page on desktop there is a large amount of safe area or white space that can't be used
when scrolling it gets cut off". The editor's theme (editor/glyphTheme.ts) ends the text with `--glacier-space-24`
of room, 126px at this size, so a thumb can tap past the last line and the last paragraph clears the phone's
formatting bar. On the split layout there is no bar and no thumb, and the room is page nobody can reach: scrolled to
the end, the last line sat 126px above the foot. Under `.app-split` it is `--glacier-space-8`, a paragraph's worth,
which keeps the last line off the very edge; the phone keeps the tall room. The reader page, where nothing is typed
at all, takes the smaller one everywhere. Written in Editor.module.css (now editor/markdown.module.css) at three
classes, since the theme's own rule is two. Seen in the pane at 1280 wide: 126px became 42px, the last line ending a
paragraph above the foot.

## 85. The wisp's reach, a third shorter (2026-09-22)

Matt: "The wisp effect travels a bit too far below the header and above the bottom part of the page, reduce how much
room this animation / effect has by 33%". Every measure of how far the smoke reaches came down by a third, and
nothing about how it looks or moves changed: the drift, the noise and the bend are as they were, over a shorter
distance. The header's band 10 to 7 and its ramp 22 to 15, the drop under the header 18 to 12; the foot's band 16 to
11, its ramp 44 to 29 and its lift off the edge 36 to 24; the mask's fades with them, 48px to 32px at the foot and
29px to 19px at the top, and the top fade under a bar from 12px to 8px. The bend's computed reach follows from the
band and the ramp, so it shortened on its own. wispMask.test.ts had the two ramps written out as 22 and 44; it now
reads the constants, and asserts only that the foot's ramp is the taller of the two.

## 86. Pictures that reached a device some other way (2026-09-22)

Matt: "Images in the hello.trade book are not working", and then, from the session that wrote the book: the JPEGs
"went into the Mac's local Glyph image store but they're never uploaded to my account storage." Another Claude
session added eighteen screenshots to ten chapters by writing the notes through the MCP (`update_note`) and putting
the files straight into the Mac's picture folder, since the MCP has no way to send a picture. The Mac drew them; the
phone showed every one broken.

Two gaps in core/sync/notes.ts, both found by the Glyph session and by this one:

- **The Mac marked them sent without sending them.** A pulled note that names a picture this device already holds
  wrote the picture's entry as revision 0 and moved on, and a picture is only sent with a push of the note that names
  it, which skips any picture with an entry. So nothing ever sent it.
- **The phone asked once.** A picture is fetched when the note naming it arrives in the feed; a 404 then (not sent
  yet) was never asked again, because the feed brings a note once.

The fix is a third step in every pass, after pull and push: **settle the pictures.** Every picture a note on this
device names, and that this device has not settled, is either sent (this device holds it) or fetched (it doesn't). A
send asks the account first with a HEAD on the file's route, which the service already answers (axum answers HEAD on
a GET route; attack.fm answered 401 without a token rather than 405), so a device signed in again does not upload
every picture it holds to learn the account has them; where a HEAD cannot be asked at all, the upload goes and a 409
says the account had it. A fetch that finds nothing is not asked again for four minutes, less than the five between
timed passes, so a pass a keystroke sets off asks nothing. An entry at revision 0, as the older app left it, is
settled like no entry at all, which is what repairs the book's eighteen: the Mac that holds them sends them on its
first pass with this update, and the phone fetches them on its next timed pass. No server change.

A picture that lands while its note is open is drawn at once: the native store answers the same address it failed
on, so a picture sync wrote gets a fresh one (`imageArrived` in core/images.ts; the `img` scheme reads only the
path), and the event the browser's pictures already use redraws it.

Tested without a server (core/sync/pictures.test.ts): the Mac sends what the phone asked for too early, the phone
gets it on the next timed pass and not before, an older revision-0 entry is repaired, a picture the account holds is
settled by its head with no upload, and a missing HEAD falls back to the upload. All four fail on the old code.

Not done: the MCP still cannot send a picture, so a note written through it can only name pictures that some device
running the app holds. An upload tool would need the MCP to seal files as the app does, and a deploy of the MCP that
signs its connector out.

## 87. Previous and next under a chapter (2026-09-22)

Matt: "Please add the book navigation for 'next' and 'prev' buttons at the bottom of the page." A chapter already
wore a bar under its header (§ BookBar): the book, its place, and the chapters either side as small arrows with
their titles. At the end of a long page that bar is a screen or more above, so going on meant scrolling back up.

BookFoot is the same place drawn under the last line: two wide buttons, "Previous" and "Next" over the chapters'
titles, Previous on the left and Next on the right whichever is there, none at all for a book of one chapter. It
reads the chapters either side from the same `BookPlace` as the bar (a shared `sides`), so the two can never
disagree, and opens a chapter the way the bar does, in the book's one tab (§77). On the note screen it follows the
editor inside the page, so it scrolls with the words and stands in the note's gutter; it is there for a canvas
chapter too, under the canvas. On the reader page it follows the chapter and steps only between the pages the
share holds, as that page's bar already does. Not on a book's own index, which is the whole list.

## 88. Pictures in a share (2026-09-22)

Matt: "Images for notes are not loading on the attack.fm/glyph/read.html." They could not: a share held its pages'
Markdown and nothing else, and `![…](image/<name>)` names a picture in the sharing device's store. The reader has
no account, and the account's copy of a picture is sealed under the account key, which the link does not carry.

So a share now carries the pictures its pages show, sealed under the share's key with the words. No server change:
the service keeps one ciphertext per share, as before, and its 6 MB limit is on the base64url text it is sent. That
decided the shape. Pictures as base64 inside the share's JSON would be encoded twice (once in the JSON, once more on
the way to the server), so a share with pictures is a small container instead: `GSP1`, the JSON's length, the JSON
with each picture's name and size, then the bytes. A share without pictures is its JSON alone, readable by the page
as it was. About 4.4 MB fits before sealing: the pictures as kept (at most 1600 px, from when they were added) if
they fit; otherwise each redrawn at 1024 px, a reading copy; otherwise as many as fit, in the order the pages show
them. A picture the sharing device does not hold is left out; the reader sees it missing, as the account's other
devices would. Words alone past the limit are refused with a sentence the share row shows.

- **The reader page** lends the share's pictures to the editor as object URLs (core/images.ts `lendImages`) and
  writes nothing: it shares attack.fm's origin with the web app, whose picture store is someone's own.
- **Download** puts the pictures in an `image/` folder beside the pages, where the links point; a note with
  pictures downloads as a zip rather than a bare `.md` that would point at nothing.
- **Save a copy** keeps the pictures first, under their own names (`keepImage`), so the copy draws them and the
  reader's sync sends them on (§86).
- **Shares already sent** go out again with their pictures: the digest that says whether a share changed now starts
  with "p", so every share reads as changed once, and shares are refreshed a few seconds after launch as well as
  after a save.
- **Names are checked** when a share is opened: only a name a note could write for a picture, so a crafted share
  cannot put a file anywhere else through a saved copy.

The sync engine's picture reading and writing moved into core/images.ts (`imageBytes`, `keepImage`) so a share
and sync read and keep pictures the same way. Tested in share/share.test.ts and src/read/Reader.test.tsx; the
reader test fails with the lending taken out.

## 89. A share goes again when a picture it lacked arrives (2026-09-22)

Matt's HelloTrade link showed none of the pictures his phone did. The Glyph session tested §88 end to end against a
local server and found the reader side sound and a gap on the sending side: whether a share changed was a digest of
its pages, and a picture arriving on the sharing device later, by sync, changes no page. A share re-sent (once, for
§88's "p") from a device that had not pulled the pictures yet went without them and was recorded as sent for good.

Now `withPictures` answers which pictures the pages show that this device lacked, the share's record keeps that list
(`lacked`), and a refresh sends a share whose pages did not change only when one of those pictures is here now. Only
those names are looked for, so the three-second follow after a save reads nothing for a share that lacks nothing,
and a picture left out for room is not a lacked one and never sets off a send. The digest's marker became "p2", so
every share sent before this goes once more, with its pictures and the list. Tested in share/refresh.test.ts (the
picture arriving, and not before or after), which fails on the code before this.

## 90. The ghost is the mark (2026-09-22)

Matt put two files on the desktop, ghost.md.png and ghost.md.svg, and asked for the old logo to be replaced with it.
The mark is a note with a folded corner drawn as a ghost, waving, a wisp rising from its head: black lines on paper,
with the paper inside the lines. It replaces §18's bullet, the dot and short bar, everywhere that mark was used.

- **The source.** The SVG came from a vectoriser: six filled shapes (the wisp, the outline, the eyes, and the paper
  of the body and the folded corner), a white square behind them, and grey outline traces of every shape. Only the
  six fills are kept. `design/app-icon.svg` is the mark on paper, two thirds of the square's height, centred on its
  bounds (814 by 1087 of its 1448 canvas). `design/app-icon-foreground.svg` is Android's adaptive layer, the same
  mark at two thirds of that, so its corners stay inside the circle a round launcher keeps. `design/ghost-mark.svg`
  is the mark alone.
- **The app icons** are made from those two by `npx tauri icon design/icon.json`: the Mac's icns, Windows' ico,
  the Linux and Store PNGs, iOS's set, and Android's launcher, round and adaptive foreground in every density.
  Android's are in the git-ignored `src-tauri/gen/android`, so they exist in the checkout the APK is built from and
  are made again from the manifest after a fresh `tauri android init`. They reach phones and Macs with a native
  build: an OTA cannot change an installed app's icon.
- **The web pages** had no icon at all. The app, read.html, install.html and the download page now carry
  `public/favicon.svg`, the mark with its ink and paper swapped where the system is dark so it shows on a dark tab
  bar, and `apple-touch-icon.png` for a home screen.
- **The MCP's sign-in page** opened with the old mark drawn as it moves in the app (a dot lands, a line writes out).
  It now draws the ghost from `art/ghostMark.ts`, the same shapes in the page's ink and paper so it turns over with
  the page, the wisp drifting. It reaches Claude with the next MCP deploy.
- **The old mark's art is gone** from art/Shapes.tsx: its `Welcome` shape was no longer drawn anywhere. At 32 px
  and under, the icon's thin wisp breaks up a little; that is the mark's own line weight.

## 91. The open items, built (2026-09-22)

Matt, of the list of open items: "go after all the ready to build features and ship an OTA update. ship the APK
update as well so everyone gets the new icon."

- **Chapters are the items that open with a link** (book/book.ts `chaptersOf`, docs/BOOKS.md). His HelloTrade
  index counted the "Five things worth knowing" bullets and the canvases list as chapters 36 to 41. Now a prose
  bullet that links a chapter in passing is the book's words. In an index that numbers its chapters, a bullet list
  beside it at the top level is too. Both show in the preface, which now leaves out exactly the index's own lines.
  A chapter added to a numbered index takes the next number.
- **A chapter can start as a canvas:** "Add as a canvas" in the index's new-chapter form. The New book sheet marks
  canvases as the index does.
- **Every shared link in one place, on every device.** The share registry moved from one device's storage into the
  synced settings, end-to-end encrypted, and is brought over once. Settings › Account lists every share with Copy and
  Stop. A share the server holds that no list names, untouched for ten minutes, can be taken down: settings sync as
  one blob, so two devices writing at once can drop one list, while the share stays up. A book's share now also
  follows edits that arrive by sync, not only ones saved on the sharing device.
- **Share links open the apps.** A `ghostmd://` scheme (tauri-plugin-deep-link) and "Open in the Ghost.md app" on
  the reader page. src-tauri/src/links.rs keeps a link until the page asks, since a link that starts the app comes
  before any page listens. The app saves the copy and opens it. It takes a native build, so it comes with this APK
  and Mac app. Older apps still have + › From a shared link.
- **The notes connector names its pictures.** create_note and update_note now list every picture the words show
  (mcp/glyph.ts), as a device would, so the other devices fetch them. Before, update_note kept only names already
  listed, which is why the HelloTrade chapters named none. It ships with a server deploy.

## 92. The home dock floats in the corner on a wide screen (2026-09-23)

Matt: "Move the controls that are at the bottom of the screen to be locked in a floating dock on the bottom right
stacked vertically on a wider display like my fold8". At 600px wide and over (core/useWideScreen.ts's line, taken from
the viewport since a docked sidebar makes the home pane itself narrower), the home page's dock of write, Speak and
Settings is a floating column locked to the bottom right. It's a rounded card of blurred paper holding Settings, then
write, then Speak last, nearest the right thumb. Speak keeps its ink fill as a circle the other two's size, so the
column is one width, and its word is kept for screen readers. A row across the foot of an opened Fold was a reach
from either hand. A phone keeps the row. The sidebar's own Speak and Settings, at its foot, are unchanged. Seen in the
pane at 880 by 790, the Fold's inner screen, and at 390 wide.

## 93. The mascot is the app icon (2026-09-23)

Matt: "update the app icon to use the ghost.md-mascot.png from downloads and push a new version of the app to my
phone and all download endpoints." The picture is the app's own dotwork ghost (docs/GHOSTS.md), waving on lined
paper, cropped close: a full square, no transparency. It replaces the line mark of §90 as the app icon; the
line mark stays where a picture that fine would not read - the tab icon (public/favicon.svg) and the MCP's sign-in
page (art/ghostMark.ts).

- **Desktop and iOS** take the square as it is (`design/app-icon.png`, the picture at 1024), as the icons before it
  did. It holds up small: at 32 px the ghost, its eyes, the wisp and the folded corner are still there.
- **Android's adaptive icon** shows only the middle 72 of the layer's 108 dp and masks that, so a full-bleed
  foreground would lose the wisp and the waving hand. The foreground (`design/app-icon-foreground.png`) is the
  picture at two thirds on a clear layer, exactly the visible part, over a background of the paper's own colour
  (#f3f3f0); a round mask keeps the wisp's tip and the hand. The picture's paper and the flat colour meet only in
  the margin a launcher reveals while it animates.
- **The home-screen icon** for the web pages (`public/apple-touch-icon.png`) is the picture too.
- `design/icon.json` points at the two PNGs; `npx tauri icon design/icon.json` makes every set. The line mark's
  icon SVGs are gone from design/ (the mark itself is `design/ghost-mark.svg`).
- **1.7.1**, a native release: an installed app's icon changes only with a new APK and Mac app.

## 94. A blur under the header on a desktop, a quieter wisp on a phone (2026-09-23)

Matt's card: "on desktop use a simple blur gradient under the headers where the shadow / wisp effect is that we use
on mobile, make it more subtle on mobile but keep the wisp effect".

- **Desktop** means a screen with a fine pointer that hovers (art/wispMask.ts `wispHead`): the Mac app and a browser
  on a computer. The Fold counts as a phone however wide it opens. There, a view scrolled under its header wears no
  smoke at the top. A strip 28px tall is laid just under the header's glass instead (`.app-headerBlur`, then in
  app.css, now in art/wisp.css),
  blurred and fading to nothing, so words going under the header go soft rather than being cut. It's the header's
  sibling, not a child: a child of an element with a backdrop filter blurs only that element's own contents, which
  under the header is nothing. That was the first try, and a line under it stayed crisp. `glyph-wisp-head` in
  localStorage picks either on any screen.
- **Phone:** the wisp stays, a third quieter. The bend's displacement is 36 to 24 under the header and 34 to 23 at
  the foot (art/WispEdgeFilter.tsx).
- **The foot** of a page smokes as it did on every screen. The card named the headers.
- **Seen in the pane:** at 800 by 600 with a mouse, the line in the strip dims and softens and the next is crisp, with
  no smoke. At the phone preset the wisp is worn, no strip is made, and the bend reads 24.

## 95. Authors on notes, and an AI that signs what it co-writes (2026-09-23)

Matt's card: "Add authors to notes, since in the future we'll have shared / collaborative notes and I want the AI to
provide it's logo and name so we can have it listed when they co author books and pages and stuff".

- **Where they're kept:** the front matter's `authors:`, names separated by commas (core/authors.ts). It's part of
  the words, so it goes where the note goes, to every device, a shared link and a download, and needs nothing new in
  sync or the native store. A note with no line is the person's own and shows nothing.
- **The AI signs:** create_note, update_note and append_to_note put the AI after the account's handle (mcp/server.ts,
  docs/MCP.md). It uses the name the AI gives in `author`, else its app's name when it connected. The hosted server
  keeps that name on the sign-in session, since every request there comes to a fresh server that never saw the
  connect. The first build missed this, and the hosted test is what showed it. A rewrite keeps the authors the note
  had.
- **The byline** (authors/Byline.tsx): each author's mark, then "By infamousvague and Claude". It shows on the note
  under a chapter's bar, in a book's index gathered from the book and its chapters, and on the reader page. The logo
  is the app's own sign, a spark, for any AI it knows by name (Claude, ChatGPT, Gemini, Copilot, Cursor), and an
  initial for everyone else. The app ships no company's artwork, and nothing is fetched to draw one.
- **Not yet:** the `authors:` line shows as front matter in the Markdown view, as every front matter key does.
- **Seen in the pane:** a book with one chapter written with Claude and one alone. The index reads "By infamousvague
  and Claude", and so does the chapter, under its bar. Tests: reading, adding and merging authors, the AI's name from
  what it says or its app's name, and the hosted connector writing `authors: matt, Claude` on an append.

## 96. Share links on ghostmarkdown.com (2026-09-23)

Matt: "The ghost markdown.com page isn't opening my read notes do we need to update the share links in the app", then
"Do all three". Links were `attack.fm/glyph/read.html#…`, and ghostmarkdown.com served only the download page. Three
parts, shipped in that order so no link ever pointed at a page that couldn't open it:

- **The page:** the ghostmarkdown.com Caddy block serves `/read.html`, `/assets/*` and `/favicon.svg` from the
  release, beside the downloads. scripts/deploy-landing.mjs now replaces the domain's own block rather than only
  adding one, with the same backup, validate and every-other-site checks.
- **The service:** `https://ghostmarkdown.com` is an allowed origin (server/src/main.rs), so the page can read a share.
- **The app:** `READER_URL` is `https://ghostmarkdown.com/read.html`. On that domain the reader's "Save it in
  Ghost.md on the web" goes to attack.fm/glyph, where the app is, and "Get the app" goes to the download page. Old
  links still open on attack.fm, and so do new ones, since the id and key after the `#` are the whole link.

## 97. A desktop page reaches the bottom of the window (2026-09-23)

Matt, with a screenshot of the Mac app: "the desktop UI on the home page isn't reaching to the bottom of the screen",
then "same when viewing notes". The Mac draws the smoke as a mask (art/wispMask.ts). Its foot showed the page down to
104px above the view's bottom, and a smoke image was to carry the words the rest of the way, but that image showed
nothing there. With the home dock a row across the foot, the dead band was under it. With the dock a floating column
(§92), it was 104px of empty window on the home page and on every note. It reproduced in the pane with
`glyph-wisp-draw` set to mask.

A desktop's edges are plain now, top and foot alike (§94's line, `wispHead`). The top is the blur strip, and the foot
is a 28px fade at the very edge (`[data-wisp-draw='fade']`, then in app.css, now in art/wisp.css), with no smoke at
either end and no filter. A phone keeps the wisp at both.

## 98. Settings is full screen everywhere (2026-09-23)

Matt: "make the settings page full screen". On a wide window Settings had been a card over the page since he asked
for "a modal" on large displays. Now it's the screen on every size, as on a phone. On a wide window the head, the
list and the panes keep one centred column, 46rem, so rows don't stretch across a desktop, and the ground runs edge to
edge (settings.css `--settings-column`). The card's dimmed page behind it and its arrival animation went with it.
Settings leaves by its back arrow as before. The older card asking for a click outside Settings to close it has
nothing outside to click now.

## 99. A book is as wide as a note (2026-09-23)

Matt, with a screenshot of HelloTrade's index on the Mac: "on desktop notes are not taking up 100% width". A note's
words already take the page's whole width; a book's index was held to 44rem, and its read-through to 48rem, so on a
wide window the book was a column down the left. Both limits are gone (book/BookView.module.css), and the index, its
words and reading straight through span the page as a note does. Seen in the pane at 1600 wide: the book is 1588px, the
page's full width.

## 100. Names only in the sidebar, and the notes' folder in Files and Finder (2026-09-23)

Matt: "Start with compact mode, maybe just add a browse local files button somewhere to open the folder on the phones
file browser".

- **Names only** (notes/NoteTree.tsx): a toggle in the sidebar's top row lists each note as one line, its kind's mark
  and its name, instead of its drawing. The marks are a page, a book and a canvas. It's kept to the device, as which
  folders are shut is (notes/tree.ts `glyph-tree-compact`).
- **Browse files:** a folder button beside it shows the library where the device shows folders (docs/LIBRARY.md). On a
  Mac that's Finder. On the phone it's the Files app. The library lives in app-private storage, which no other app can
  open, so Ghost.md shows it there through a DocumentsProvider of its own, "Ghost.md", read-only, with `.glyph/`
  hidden. The button opens the Files app at that place, or the system's file browser starting there on a phone whose
  Files app won't open a place by itself. It needs native generation 18 (1.7.2), so the page offers it only where the
  binary has it.

## 101. Settings in colour, and split on a wide window (2026-09-23)

Matt: "Add colors to the icons throughout the settings page make the icon background semitransparent in the color and
the icon full opacity on the same color", then "Also on full screen and desktop and larger tablets show a split view
for settings with the sidebar on the left and the settings sections on the right".

- **Colour:** each section has a hue (SettingsScreen.tsx `hueOf`). Account is blue, Appearance purple, Recording red,
  Plugins green, About grey, Developer brown and Test results mint, and the sub-pages keep their own: Notion and
  GitHub graphite, Claude coral, the cheat sheet and Examples yellow (§138; until then Type was indigo, Formatting
  orange, Feel teal, Animations pink and Location lime, each a row of its own). Its chip in the list is that colour at
  16% under the glyph in the same colour at full strength, where it was ink with the glyph in paper. Its own page wears
  it too: every row's icon in the same chip, and the hero's glyph and the callouts' icons. Each hue is a shade deeper
  on the light page than on the dark (settings.css), written as flat selectors rather than nested ones, which the
  Mac's WebKit on macOS 13 doesn't read.
- **Split:** where the sidebar would be up (core/useWideScreen.ts `useSidebar`: a desktop, a large tablet, the Fold
  opened), the sections are a 20rem column down the left, the one on show a shade deeper, and its page is on the
  right in a 44rem column. The first section shows until one is chosen. With no list page to return to, back leaves
  Settings. A phone keeps the list, then a page.
- **Seen in the pane:** at 1280 wide, the split with Account showing, then Claude with its icons in coral at a 16%
  tint. At the phone preset, the list with every chip in its colour.

## 102. A launch screen, and a welcome without the AI heads-up (2026-09-23)

Matt: "The loading intro video is too much but I want a loading screen with the logo and checking for updates and stuff
and show statuses for checking for updates etc etc. also I'd like you to revamp the welcome flow remove the AI warning
page".

- **The launch screen** (launch/LaunchScreen.tsx): the icon, the name, and a line per step, each turning to a tick.
  "Opening your notes" becomes a count of them. On the app, "Checking for updates" becomes "Up to date", "An update is
  ready for next time", "Ghost.md 1.x is out" or "Couldn't check for updates". The check is asked for at once rather
  than after the app's usual 4-second settle. "Syncing your devices" becomes "In sync" when signed in. It goes when the
  notes are read and the check has answered, at most three seconds in and at least 0.9 so it can be read. Where no
  check runs (a staging build, local-only mode, the dev server), the update line is left out rather than waited for.
- **The welcome:** the heads-up page, "Heads up: we use AI" and its anti-AI gags, is gone, with HeadsUp, AntiAiStage
  and antiAi.ts. The first page is now "Welcome to Ghost.md" out of smoke, one line on what it is, and three points:
  say it or type it, plain Markdown files, the same on every device. The rest of the flow is as it was: theme, model,
  side key, marks, tips. The page count is a row of dots instead of "1 of 6".
- **The icon in a squircle** (Matt: "put the app logo in a squircle with a black bar that chases around the outside of
  the squircle"): the icon is clipped to a superellipse (n = 5), and a short bar in the page's ink runs round a ring
  of the same shape just outside it, once every 1.15 seconds, over a faint track. The ink is black on the light page
  and white on the dark, where black would be invisible.

## 103. Settings' page fills the split (2026-09-23)

Matt, on the Fold: "The right hand side of the split view settings isn't letting the content inside flow to fill the
available space." The page on the right sat in a narrow strip with wide empty margins. It was meant to be a column a
reader's width (44rem) centred in the pane, by padding each side with `(100% - 44rem) / 2`; but a padding's
percentage is of the containing block's width, which is the whole split - the left column included - not of the pane.
So on the Fold's inner screen each side was padded by half of what the whole screen had over 44rem, and the page came
out far narrower than 44rem and off to one side.

Matt wants the page to fill, so there is no column any more: the pane's page takes its whole width in the app's
gutter, as a note's words do (a book's index did the same, §99). The left column keeps its 20rem.

## 104. The split's left column is its own width (2026-09-23)

The fork session saw it: Settings' split came out half and half (441 of 880, 721 of 1440), where its left column was
meant to be 20rem. The column is also `.settingsScreen__list`, whose `flex: 1` comes later in settings.css at the same
weight, so it grew alongside the page. The column's rule is now two classes (`.settingsScreen__split >
.settingsScreen__side`). Measured in the pane: 320px at 880 wide and at 1440, with the page taking the rest.

## 105. The ghost watches the bar (2026-09-23)

Matt: "I want the ghost's eyes to follow around the loading bar that moves around the icon mask over the ghost's eyes
in the logo and do fake eyes that look around and follow the loader." The launch screen (§102) draws the mascot in a
squircle with a bar chasing round a ring outside it; now the ghost watches the bar go round.

- **The picture's eyes are painted out** (launch/ghost-icon-eyeless.webp): its two dark ovals filled with the body's
  own paper colour, which at the icon's size cannot be told from the body around them.
- **Two eyes are drawn in their place** (launch/eyes.ts): ovals the size of the painted ones, the picture's
  near-black in either theme since they belong to the picture, not the page.
- **They look at the bar.** Each frame both eyes turn toward the bar's middle, as far as they go (a little more up and
  down than across, as the ovals are tall), and ease there over about a tenth of a second rather than jumping, so they
  follow the bar the way eyes follow something moving. Both look at the same point, so they turn slightly toward each
  other as it passes between them.
- **One clock.** The bar was a CSS animation; eyes following it from a separate clock would drift from it. So the
  bar's dash offset is set on the same frame as the eyes, from the time since the screen appeared (`barAt`), with
  the CSS animation left only for a page where that can't run.
- **A blink** soon after the screen appears (the screen stays 0.9 to 3 seconds, so the eyes get about one lap), and
  every 2.6 seconds after.
- **Less motion asked for:** the bar stands still and the eyes look ahead, without a blink.

## 106. Searching Settings (2026-09-23)

Matt: "Add a search bar to the top of the settings sidebar and implement search functionality." A field heads the
list of sections: the left column of the split view, and the top of the list page on a phone. It stays put while the
sections scroll under it.

- **What it finds** (settings/settingsSearch.ts): a section by its name, its state line (Appearance's "Dark"), and a
  few words of its own ("theme", "font"). It also finds a setting inside a section by the name that section's page gives
  it, plus the words someone might look for it by: "vibrate" finds Haptics, "wisp" finds Smoke at the edges. Each section
  lists its settings in SettingsSheet.tsx beside its pane. The cheat sheet lists every mark, so "bold" lands on it, and
  Plugins lists every plugin, on or off.
- **How it matches:** every word typed has to start a word of what it is matched against, in any order. So "sm ed"
  finds Smoke at the edges, and "moke" finds nothing. Curly quotes and apostrophes count as straight ones.
- **What it shows:** the results replace the sections, as one card of rows in the sections' own colours. A section
  shows its name and state. A setting shows its name, with its section's name under it, so "smoke" says which of the
  two pages each smoke is on. A section found by its own name doesn't also list its settings. When nothing matches,
  one quiet line says so.
- **Opening a result** opens its section's page. A setting is then looked up on the page as drawn: a row's label, a
  card's title, or the hero line. It is scrolled to the middle, or by its top if it is a tall card, and lit in the
  section's colour for a moment. A setting that isn't on the page just now (signed out, say) only opens the page.
- **Keys:** Enter opens the first result. The arrows step through the results and back up to the field. Escape
  empties the field before it closes anything. ⌘F or Ctrl+F, while Settings is open, goes to the field.
- **The query stays** until Settings closes. The split view keeps the results in its column while the page changes,
  and a phone comes back from a page to the same results.

Found while checking it: on a desktop, a scrolled Settings page lost its right-hand side. A desktop's views draw plain
edges (§97, `fade`), but a view with no header of its own still took `[data-wisp-edge]`'s SVG filter once scrolled.
That filter's region is sized only by the views that draw with it, so here it had whatever width another view last
gave it: 480px, from a phone-sized load, which left the page drawn only to x = 760. `[data-wisp-draw='fade'][data-wisp-edge]`
now has no filter.

## 107. The ghost winks goodbye (2026-09-23)

Matt: "Remove the blink, when it's done loading have the ghost look at the camera and wink before the loading screen
goes away." The launch screen's ghost (§105) no longer blinks as it watches the bar. Once the app is open:

- **The bar and its track fade** (200ms), since there is nothing left to wait for.
- **The ghost looks out of the screen.** Its eyes stop following the bar and ease back to where the picture had them,
  which is looking straight out at whoever holds the phone. It takes 240ms (`LOOK_OUT_MS`), on the same frame loop
  and easing the bar-watching uses.
- **It winks.** The eye on the viewer's right shuts and opens again over 380ms (`WINK_MS`), held shut for about a third
  of that. The wink squeezes a group round the eye, so the frame loop's move of the eye and the wink's squeeze don't
  fight over one `transform`.
- **Then the screen fades** as before (260ms) and hands over. The screen waits for the wink rather than starting its
  fade when it is ready, so opening now takes about 0.6s longer.
- **Less motion asked for**, or a page with no geometry to move eyes by: no look and no wink, and the screen fades as
  soon as it is ready, as it did.

## 108. A segmented control stands off its card (2026-09-23)

Matt, on the Fold's Appearance page: "Segmented toggles that are on the secondary background that's darker need to
have a different background color as they blend in." The kit's segmented control draws its track in
`--glacier-segment-track`, which the app sets to paper-2 (ink.css) so a control on the page reads as a well. But a
Settings card is paper-2 too, so on a card - Rounding, the code colours, the sidebar style - the track was the card
itself and only the chosen segment showed.

On a Settings card (`.setk__card`, `.settingsScreen__group`) the variable is paper-3: one step further from the
page, lighter than the card on the dark page and darker on the light one. Measured in the preview: 0.24 on a 0.17 card
dark, 0.895 on a 0.955 card light. Controls on the page itself keep paper-2, and the search pill over the list is
untouched. The Claude guide's two-way switch is its own, on a card of another ground, with a border, and is left.

## 109. Two coding faces, chosen from cards (2026-09-23)

Matt: "I'd like a few more typefaces added. I want the one we use to have some cool serifs on things like & and other
symbols but in a monospace capable coding font. Some languages like fira code also support decorators ... where
multiple symbols can combine", and then "add fira code and maple mono fonts, show the fonts as small cards on the app
with markdown symbols like a # Quick & Foxy or something to preview what each font looks like".

- **Chosen by looking.** Nine open-licensed coding faces were set side by side, upright and italic, on the same
  symbols and code: Victor Mono, Fira Code, Cascadia Code, Monaspace Radon and Xenon, Maple Mono, Recursive, Xanh Mono,
  Iosevka. Maple Mono has the most to its symbols without leaving the grid - an ampersand with a looped flourish, a
  cursive at-sign, a cursive italic - and joins every pair a programmer types (\`->\` \`=>\` \`!=\` \`<=\` \`&&\`).
  Fira Code is the one Matt named: its own ampersand, and the ligatures that made the idea known. (Victor Mono's and
  Cascadia's cursive italics and Monaspace Xenon's slab serifs were the runners-up; the Monaspace builds keep their
  ligatures behind stylistic sets.)
- **One face for note and code.** Choosing a coding face sets both the page's face and the code face
  (typefaces.css), so a code block reads as part of the note. The three sans keep JetBrains Mono for code.
- **Ligatures need no spacing.** Measured in Chrome: any letter-spacing but none - even the app's -0.005em - and
  \`->\` stays two characters in all of them. The app tightens Inter's titles and headings; a monospace face is never
  spaced, since its grid is the point, so in a coding face nothing is. Code in any face is unspaced too, which also
  lets JetBrains Mono's own ligatures show in code for the sans faces.
- **The fonts' own features.** app.css turns on Inter's \`cv11\` and \`ss01\` for the whole page; in another font
  those names are other glyphs. Code, and a coding face, get \`calt\` and \`liga\` instead.
- **Cards.** The Type page's segmented control for three faces is now a card per face (settings/TypefaceCards.tsx),
  each setting the same scrap of Markdown in its own face - \`# Quick & Foxy\`, then \`**bold** -> != <=\` - with the
  marks dimmed as the editor dims them, so the ampersand and the joined signs are seen before choosing.
- **Weight.** Maple Mono's four weights the app sets (400 to 700) and two italics, and Fira Code's one variable file,
  bundled and fetched by the browser only when a face is drawn. A face a device doesn't know, synced from a newer one,
  is the default there.

## 110. The dock is a column on every screen (2026-09-23)

Matt: "on my fold 8 I expected the bottom controls to be docked in a right hand side dock going up the right
vertically like on unfolded view, this is how all ... devices should display it." §92 made the home page's dock a
floating column in the bottom-right corner at 600px wide and over, so the opened Fold (880 wide) had it and the
folded Fold's cover screen (about 400 wide) kept the row across the foot. Now the column is the dock everywhere:
Settings, write, then Speak nearest the right thumb, Speak a circle in the page's ink the size of the other two, its
word kept for a screen reader, on a rounded card of blurred paper. The row's own rules - its grid, and the + and cog
pushed to either end - are gone.

The scroller's room at its foot was the row's (96px). The column stands about 156px tall with its offset, so the room
is now the column's own height, from the same measures it is drawn with, and a little more: scrolled to the end at
400 by 880, the last line sits well above it. Seen at 400 by 880, the cover screen, and 880 by 900, the Fold opened.

## 111. A font for the note and one for the interface (2026-09-24)

Matt: "I'd like font pairs. For the note body I want to use the maple mono font and for the interface I want to use
inter by default, make both kinds of fonts pickable in settings not just one global font." §109's one face for
everything is two: the **note font**, any of the five (Maple Mono, Fira Code, Inter, Noto, Plex), Maple Mono by
default; and the **interface font** - tabs, lists, Settings, buttons - one of the three sans, Inter by default. A
monospace face is not offered for the interface: its even grid is for text to be read, and a row of tabs in it runs
wide. Asked first whether Maple Mono is free to make the default: it is, under the SIL Open Font License, which lets
it ship in the app as long as its licence and copyright go with it (docs/THIRD_PARTY.md, which now lists every face).

- **Stamped apart.** The interface's face is the kit's `data-font`, as before; the note's is `data-note-font`,
  always stamped, which typefaces.css turns into `--app-note-font` for the editor's prose (editor/glyphTheme.ts)
  and, for a coding face, the code face too. The editor is every note the app draws, so a note, a home card's
  preview, a canvas card and a book read through all follow the note font, and the chrome round them the interface's.
- **The ligature rules follow the note.** No letter-spacing and the fonts' own features now apply inside a note in a
  coding face (`.cm-editor`), not the whole page, since the interface is in a sans again.
- **The reader.** A shared note's page (read.html) has no settings; with nothing stamped, the note font is the
  default, so a shared note reads in Maple Mono as it does in the app.
- **One face becomes two.** A store, or another device by sync, that says one face for everything is read as a pair
  (core/preferences.ts `facesOf`): a coding face chosen then is the note's, and the interface goes back to Inter; a
  sans chosen then stays the interface's, and the note takes the default. `noteFace` syncs with the rest.
- **Two pickers of cards.** Settings > Type has Note font, whose cards set `# Quick & Foxy` and
  `**bold** -> != <=` in each face, and Interface font, whose cards set a title and a row of tabs. The page's summary
  names both: "Large · Maple Mono · Inter". Each has its own entry in Settings search.

## 112. The Mac's icon has its own shape (2026-09-24)

Matt: "The icon on Mac is a square with no bleed so I see the corners of the image on the app icon container." iOS
and Android cut an app's icon to their own shape, but macOS draws it exactly as it is. The icon was the full-square
mascot on lined paper (design/app-icon.png, since 1.7.1), so in the Dock it was a square among rounded squares, its corners
standing out past everyone else's.

The Mac now has its own icon, laid out on Apple's grid by `python3 scripts/mac-icon.py`:

- **An 824 squircle in the middle of a 1024 canvas.** The picture is scaled to 824 and cut to a superellipse
  (exponent 5, close to Apple's continuous-corner shape), with clear corners round it.
- **A soft shadow under it:** 10px down, 12px blur, 30% black, as the Dock's own icons have.
- **The script writes design/app-icon-macos.png and src-tauri/icons/icon.icns.** tauri.conf.json now lists the icns,
  so the bundler uses it rather than making a square one from the PNGs. `npx tauri icon design/icon.json` writes a
  square icon.icns over it, so run the script again after it. Every other platform keeps the square picture, since it
  shapes the icon itself.

A native change: it reaches a Mac with a new Mac app, not an OTA. Once the new app is in /Applications, the Dock can
keep showing the old icon until the app is opened again, or `killall Dock` is run.

## 113. Ready for the stores: delete account, privacy, a Play build (2026-09-24)

Matt: "I'd like to list this app on the iOS and android app store, in order to do this we need a delete account button
and a few other things. Discover what those other things are and fix them before coming up with two short plan files."

Three read-only audits found what was missing: the Android build against Play's rules, the iOS build against the App
Store's, and every place user data leaves a device. The two plans are docs/store/PLAY_STORE.md and APP_STORE.md. What
was fixed:

**Delete account.** Both stores require it for any app that makes accounts.
- **The server:** `DELETE /api/v1/account` (accounts.rs, store.rs `delete_account`).
  - It asks for the password's login half. A phone left unlocked shouldn't be able to lose its owner's account.
  - A wrong password is a 403, not a 401, since a 401 reads as signed out. It counts against sign-in's rate limits.
  - It deletes the account row, and the tables cascade from it: devices, recovery codes, notes, settings, shares (every
    link stops opening) and recordings' rows. Then it removes the recordings folder.
  - Other devices sign themselves out, because refresh already refuses a token for a missing account.
- **The page side:**
  - `deleteAccount` (account.ts), then `deleteAccountHere` (engine.ts). The latter forgets the sync bookkeeping and the
    share links, as signing out does.
  - Settings › Account › Delete account: a form that says what goes and what stays, then asks for the password. It ends
    on the signed-out page with "Your account is deleted. The notes on this device are still here."
  - The button is in the ink like everything else. The theme maps "danger" to ink, and a red would be the app's only
    tint.
- **Tests:** a server test through the routes (wrong password, no token, then everything checked gone and the handle
  free again), a sync end-to-end run against a real server, a component test, and the flow walked in the browser.
- **Recordings and pictures had no delete route at all.** Until now they outlived their notes on the server; the account
  deletion removes them.

**Privacy.**
- `landing/privacy.html` and `landing/delete-account.html`. Google Play wants a web page that says how to delete an
  account, as well as the button.
- Settings › About › Privacy policy, and a footnote that is the policy's short version. The web version's footnote says
  instead that the browser does the speech recognition (Chrome sends it to Google).
- The policy is written from the data audit.
  - **Where data goes:** the handle, device kind and public keys, timestamps and sizes are readable on the server;
    everything else is sealed.
  - **Access logs:** IPs are held only in memory for rate limits. Caddy's access logs are the one thing not in the repo.
  - **The one exception to end-to-end encryption:** the hosted Claude connection holds the account key in memory while
    it's connected, and the policy says so. (And, since 2026-10-05, on disk sealed under a token Claude holds; the
    policy says that too.)
- **The contact address is infamousvaguerat@gmail.com** (Matt, 2026-09-25), on both pages and in both store plans.

**A Play build: `GLYPH_STORE=play`.** Play forbids an app updating itself outside Play.
- **The switch is compile-time,** in ota.rs `STORE`, like `GLYPH_STAGING`. A store build never fetches `apk.json` in
  the check or in the background peek, and `ota_fetch_apk` refuses. The web bundle still updates over the air, which
  is JavaScript in the WebView, so Play allows it.
- **Gradle** merges `src/store/AndroidManifest.xml` over the release manifest, which removes `REQUEST_INSTALL_PACKAGES`,
  and sets `BuildConfig.STORE` so `GlyphHost.installApk` declines.
- **The page reads the store** from the status (`storeOf` in ota.ts), because the web bundle is shared by every build.
  Where a store updates the app:
  - the release list drops "Installed as Ghost.md 1.7.2";
  - Settings adds that new versions come through the Play Store.

**16 KB pages.** Play takes only native libraries that load on phones with 16 KB memory pages. Both of ours were
4 KB-aligned: `libglyph_lib.so`, and NDK r26's `libc++_shared.so`, which can't be relinked.
- The C++ runtime is now linked statically:
  - llama-cpp-2's `android-static-stdcxx`;
  - the vendored whisper-rs-sys's build.rs, which links `c++_static` and `c++abi`;
  - the CMake toolchain file, with `ANDROID_STL c++_static`.

  So nothing ships `libc++_shared.so`, and build.rs deletes any copy an older build left in `jniLibs/`.
- build.rs links `-z max-page-size=16384`. It's there rather than in `.cargo/config.toml` because Tauri's Android build
  sets its own rustflags, which replace the config's.
- **Checked:**
  - On the built AAB: one `.so`, NEEDED only liblog, libandroid, libdl, libm and libc, and every LOAD segment at 0x4000.
  - On the arm64 Android 16 emulator: the app launches and records. The test binary, pushed to the emulator, passes
    whisper's fixture tests (every key word heard) and llama's generate, prefix-cache and cancel tests with Qwen3.5-0.8B.
  - The LLM tests now take `GLYPH_REPO_DIR` for the page files their prompts come from, as whisper's take
    `GLYPH_MODELS_DIR`.
- The static runtime is in the sideloaded APK too, since it's the same library.
- The manifest also loses Tauri's Android TV entries (leanback, and the TV launcher category). A store reviews an app
  that claims TV as a TV app.

**iOS.** The iOS app isn't ready to submit: it has no voice capture yet (DESIGN §6.3), and APP_STORE.md says what's
left. What was fixed now:
- **The iOS library compiles again:**
  - `libc` is a dependency on every target, since llm/device.rs and hardware.rs are built on iOS too;
  - `ai_generate`'s output type exists there.
- **The icon set has no alpha channel.** Every pixel was already opaque, so nothing looks different, but App Store
  Connect rejects any alpha.
- **The privacy manifest,** `PrivacyInfo.xcprivacy`:
  - No tracking.
  - The data collected with an account is declared rather than argued away: User ID, User Content, Photos, Audio.
  - Required-reason APIs, each from evidence:
    - FileTimestamp C617.1: `stat` of the app's own files, in vault.rs, images.rs and SQLite.
    - DiskSpace E174.1: `statvfs` before a model download.
    - SystemBootTime 35F9.1: `Instant`.
    - UserDefaults CA92.1: defensive, as WebKit and Tauri may use them.
- **Info.ios.plist:**
  - the display name is Ghost.md, where project.yml's product name is still Glyph;
  - the microphone string no longer mentions a cloud option that doesn't exist;
  - `ghostmd` joins `glyph` as a URL scheme, because the deep-link plugin replaces the key;
  - export compliance stays `false`, with the real reason: on iOS all the encryption is Apple's own WebCrypto.
- **Guideline 2.3.10 forbids naming another platform.** Two strings that an iPhone showed are rewritten:
  - the guide's side-key page no longer says "The side key is an Android thing";
  - the home screen's empty state says "tap Speak" everywhere but Android.
- **Updates on an iPhone:**
  - there are no update checks, which only ever failed with "Over-the-air updates are Android-only";
  - Settings says "Ghost.md updates through the App Store";
  - attack.fm's release list is hidden, since an iPhone never runs those builds.

**Not deployed yet.** The Delete account button calls an endpoint only the new glyph-api has, so the order is:
1. glyph-api, which is Matt's call;
2. the landing pages;
3. then the OTA.

**Meetings (1.9.0, §127).** The APK now declares three foreground service types (microphone while a meeting records,
mediaProcessing and specialUse while it is written up), and Play asks what each is for. docs/store/PLAY_STORE.md has
the answers and a data-safety row for a meeting's audio, which is recorded and written up on the phone and synced
only when the person switches that on.

## 114. The AI in the note: runs that land as tracked changes, a strip, a bar, one reader (2026-09-25)

Matt: "rewrite the AI tooling to be more real time, more interactive with UI updates, iconography and general
feedback, while using the AI in the app to write and edit notes." Twenty-five choices, made before a line was written,
decided the shape; the ones that changed the architecture are recorded here, with what they became.

- **Merge PR #1 first, as it stood.** Kevin's instruction-aware voice commands (the final transcript classified once,
  after Done; a confirm card before any write; revision-guarded `create_note` and `update_note`; a guarded command
  mutation with durable undo; `ai_infer_command` with a grammar) came in as a merge onto 1.7.2, resolved against
  everything that had landed since its base: books by voice kept, "add this to the field guide" falling through to the
  book rules, `saveNote`'s last two callers moved to `createNote`. Its native commands are **generation 19**, and the
  page requires 19, so nothing from this tree ships over the air until a binary carrying them reaches each channel
  (attack.fm's APK, the Play build, the Mac app). That is the cost of merging as is, and it was chosen with eyes open.

- **One engine** (`ai/runs.ts`). A run of the model on a note is a state the page draws at every report - which phase,
  which model, how fast, the phone underneath - and, the part everything else rests on, **the lines as they finish**,
  cut at the last newline so `lines` only ever grows by whole lines. One model, one pass: the draft-then-careful
  passes and their background queue went (the chosen model when it is on the phone, else the biggest under it, else
  the smallest there is; `ai/available.ts`). One run at a time, the next waiting as `queued` where the strip can say
  so; a second ask on the same note takes the first's place. The gist waits behind a note's own run. A model asked to
  think keeps its reasoning apart from its answer, and the answer's newlines are kept, since `splitThought`'s trim
  would never let a last line finish.

- **The note is the only surface.** Matt chose a live diff over the note, then auto-apply with Undo, then tracked
  marks that stay until Keep, Revert, Clear marks or typing on the line - and those three together mean: the model's
  lines go into the editor as they finish (`ai/land.ts`), the note is always the text as it now reads (what is saved,
  synced, shared), and the marks are decorations over it (`editor/aiChanges.ts`): added words tinted, the words that
  went struck through where they were (a block above the line for whole lines, inline for words within one), Keep and
  Revert on each run of changes. The robot's own view over the note, its Apply and its kept texts went with it.
  - **The reading rules** (`ai/landing.ts`). Each finished line is looked for among the next eight old lines: found,
    the lines passed over were dropped; nearly the same (half its words shared, and two of them), the old line is
    rewritten word by word, compared with their case and without the punctuation on their end; else it is new. Blank
    lines only ever match the very next line. The decisions are made once, in order, and never revisited, which is what
    lets a line land the moment it arrives and stay where it landed.
  - **Typing while it runs** is fine. The landing bookmark and every mark are mapped through the person's edits; the
    ranges they touched are theirs - never struck, never rewritten - and a line of the model's that would have replaced
    one is dropped and counted, said in a toast when the run ends.
  - **The finished text is read back over the landed lines**, so the tidy-up at the end (a `*` bullet made a `-`, a
    link that came back late) lands as one more small change rather than a rewrite of everything.
  - **A summary lands above the note, Continue under it, everything else over the words it was given.** The front
    matter is never the model's.
  - **The marks are kept with the note** (`ai/marks.ts`), against a hash of the body, and come back when it opens and
    still reads the same. A run's Undo, in the strip or its log, puts the whole note back while it still reads as the
    run left it.
  - **The AI is an author.** A run that changed the note signs it "Ghost" in `authors:` beside the account's handle,
    and the byline draws its spark (`core/authors.ts`, §95). In a live session its lines arrive on the other device as
    any remote typing does; the tint is on the device that ran it.

- **The strip** (`ai/AiStrip.tsx`): one line under the header, floating over the page and never in its smoke, with the
  phase's icon from the kit's set (Matt chose lucide through `@glacier/icons` for every AI state and action), the
  sentence, a hairline bar that fills as the note is read and then as the answer is written, and Stop; afterwards what
  happened and how long, Undo, Keep all while marks remain, and a cross to put it away. Tap it for the AI card with the
  phone's readings, the model's thinking when it thought, and the note's **run log** (`ai/log.ts`): each run, what was
  asked, which model, how long, how it ended, with Undo per run. The log is on the page, per note, a handful at most.

- **The bar** (`ai/PromptBar.tsx`) at the foot of the note: six chips - Format, Summarize, Enhance, Fix spelling,
  Make a list, Continue - and a field for anything else. Where the AI cannot run (a browser, iOS, no model, an older
  binary) it shows greyed with the reason in the field and Get <model> where getting one is the fix. The press-and-hold
  menu offers **Ask the AI** on a selection, which opens the bar with the part as its scope; a chip or an instruction
  then asks, each time, this part or the whole note. A part is widened to whole lines and goes to the model as the
  note, with the rest for context and a word that it is a part (`ai/prompts.ts`), so its answer takes the part's place.

- **One reader** (`ai/instruction.ts`) for an instruction typed or spoken. The chips' runs said in words come first
  ("fix the spelling", "make this a list", "carry on"); a command naming another note is read by the voice commands'
  rules and, for speech, the on-device model once on a name the rules could not match, and offered on the **one
  confirm card** (`ai/ConfirmCard.tsx`, the recorder's, shared); a command that named a note there is no note for
  fails closed with its reason; anything else typed is an ask about the note, and spoken, an ask only after "hey
  Ghost". Typed words never wait on the command model, so "add a heading about the budget" is an ask and not a hunt
  for a note called budget. A confirmed command lands in the open note as a tracked change, or in another note
  through the guarded write with Undo in a toast and a record in that note's log. An instruction spoken into a note
  it continues opens the note with the run on it.

- **The review, in the note** (`ai/useNoteReview.ts`). Stop opens the note. Listening again and comparing are a stage
  of the strip's own, with the percent along its foot; the thinking is a run the strip follows like any other, its
  thought readable in the card as it streams; and each finding lands as a tracked change with Keep and Revert -
  another note's through the guarded write. The review screen, its cards and its Commit are gone; so is the
  formatting queue that ran after it, since the model's words land in the note with the person watching.
  `?simulate=review&review` in a browser still runs the whole flow with the model played by a script
  (`ai/reviewSimulation.ts`, handed to the engine).

- **What could not be done here.** The Tauri crate does not compile on the box this was written on (no GTK), so the
  Android and Mac binaries carrying generation 19 are still to be built and run; the 54 Rust host tests pass, the
  page's 1,300-odd tests pass, and the web build passes. A physical run with a model on the phone is what settles the
  reading rules' feel - how often a rewritten line reads as "nearly the same" - and the pace the lines land at.

## 115. All notes as a grid of cards (2026-09-25)

Matt: "Browsing all notes is super hard there is no good UI it just opens in the sidebar, I'd like a grid view of all
the notes in the 'all notes' section."

The home page's "All notes" opened the sidebar. The sidebar is a tree for jumping to a note you already know by name:
a column of small rows over the page, folded by workspace, with the trash at its foot. For looking through what there
is - which is what "all notes" asks for - it was the wrong shape. So "All notes" is now a page (`notes/AllNotesScreen.tsx`),
and the tab row's house, the arrow in its bar and the phone's back gesture come back home from it.

- **The same card, once** (`notes/NoteCard.tsx`, `NoteCard.module.css`). The home page drew its cards inline - a
  note's, and a book's - and the grid wanted the same ones, so the card is one component now, and its rules left
  `HomeScreen.module.css` for a stylesheet of its own. A book's card and a note's are the one component deciding by
  the body. Drawn `dense`, for the grid, it is a step smaller all through: less padding, the title at the body size,
  the preview four lines rather than six, and the pin and the archive said on the card itself, since there the cards
  are not under headings that say so. The AI's ring and dot in the corner (§114) came with it.
- **The page.** A glass bar with the arrow and the search; under it the workspace pills (the ones the home page has,
  choosing the same workspace), a line of words - Newest or A to Z, how many notes, and the archive's word with its
  count once there is one - and the grid: cards a step narrower than the home page's, so a phone holds two across,
  the Fold opened out four, and a desktop window's reading column five. The order chosen is kept on the device
  (`glyph-all-notes-sort`, cleared by the reset). The gist runner is given the first twenty-four cards, not every note.
- **The search** is over the notes' words, not their names: every word typed must appear somewhere in the note,
  whatever the case, so "trip packing" finds the note with both. Nothing found is the ghost with the search and a
  line, which says to look in the archive when there is one and it is not shown.
- **The rules** are `notes/allNotes.ts` - what matches, the two orders (a nameless note sorts after every name), the
  archive kept out unless asked for - and `allNotes.test.ts` reads them.
- **A place on the trail** (`notes/visited.ts` `ALL_NOTES`). The page carries the tab row, so the arrows reach it the
  way they reach the home page and a note; a recording and the Academy are still things you do rather than places.
  On a wide window it sits in the note pane beside a docked sidebar, as the home page does.
- **The palette** says "Home" for the command that goes home (it said "All notes", which now means the grid) and gains
  "All notes" for the page.

## 116. Effects on words, written as an emoji twice (2026-09-25)

Matt: "I want to add in effects to text in our markdown one of which should be the "heated" effect that gives the
wavey blur like we used on the "AI" text on with the fire on the original onboarding flow. Effects should be shown by
double emoji wrapping them so heat should be two fire emoji's wrapping either side." Then, of the four offered: "Add
each of these effects."

- **The syntax.** An effect is a mark like `==highlight==` whose delimiter is an emoji twice: 🔥🔥heat🔥🔥, ❄️❄️frost❄️❄️,
  🌊🌊wave🌊🌊, ✨✨shimmer✨✨, 👻👻haunt👻👻 (plugins/marks/index.tsx). The emoji is the effect's name, so the note still
  says what it meant in any other Markdown app. The parser took only a run of one character before; it now takes a
  run of one piece, a character or an emoji of several code units (editor/language.ts `delimiterUnit`: 🔥 is two
  UTF-16 units, ❄️ a character and its variation selector). Three flames are three flames, as `|||` is not a spoiler.
  The plugin registry accepts an emoji twice beside its old rule.
- **The look** is a new `FormatLook`, `{ kind: 'effect', effect }`, drawn by editor/textEffects.ts. Two kinds:
  - **A filter over the stretch** for heat and frost, which are one field the words sit in. Heat is the onboarding's
    haze: stretched fractal noise, breathing between two frequencies every 2.4 seconds and re-rolled six times in
    0.9 seconds, bending the letters, then a breath of blur. The onboarding's numbers were for 40-pixel type; five
    variants were compared by eye at 16 px, and the one that read as heat rather than grit (waves about four times a
    letter's height, a bend of a third of it) is scaled with the type it is on. Frost cools the letters towards ice
    with a colour matrix and grows a grainy rime from their edges that creeps and settles; the rime's colour is set per
    page by the editor's theme, pale ice on the dark page and deeper ice on paper, where pale ice was invisible.
  - **A movement passed along the letters** for wave, shimmer and haunt: each letter an inline mark with a CSS
    animation a step behind the one before, moved by relative position rather than a transform, which an inline box
    does not take, so nothing reflows. The delays are negative, so a line drawn fresh is already moving. The shimmer
    is a glow on the dark page and a sheen on paper, where a glow of dark ink read as a smudge.
- **Behaviour.** An effect lifts while the caret is in its words, so they edit as plain text; effects nest; reduced
  motion draws them still. The cheat sheet and the Style page list them like any mark.
- **Said** as adjectives - heated, frosted, wavy, shimmering, haunted - because the nouns are everyday words and the
  spoken form closes on "and" as well as "end": "heat the oven and heat the pan" would have heated "the oven".

## 117. The AI bar is off until asked for (2026-09-25)

Matt: "Hide the AI bar on the note by default, put it behind a toggle button."

- **Off by default,** as the synced preference `aiBar` (core/preferences.ts, core/sync/prefs.ts): the choice is the
  person's, so it travels like the note view does.
- **The toggle is a ✨ where the bar lives.** Hidden, a small ring at the foot of the note on the right; shown, the
  spark at the start of the bar's own field puts it away (ai/PromptBar.tsx `onHide`). It was first a fifth ring with
  the note's tools in the top bar; a review measured that at 412 px, the Fold's cover screen, and the three dots ended
  14 px past the slot's edge, reachable only by a sideways scroll with no scrollbar. At the foot the top bar keeps its
  four.
- **Ask over a selection is asking for the bar,** so it opens it for that note whatever the setting. Putting the bar
  away puts that ask away too (its scope and the focus it was owed), since the bar now unmounts and its focus effect
  would otherwise bring the keyboard up again on words that may have moved.
- The page keeps room under the last line for whichever is there: the bar's height as it tells it, or the ring's.

## 118. A Search in the home dock (2026-09-25)

Matt: "Add a search button to the right hand dock of buttons that opens the command pallette." A ring under Settings
in the home dock (home/HomeScreen.tsx), a magnifier drawn in the app's own line icons (art/Icons.tsx `Magnifier`),
opening the palette that ⌘K opens on a desktop, with the caret in its field. Under Settings rather than above it: it is
reached for more often than Settings and less often than writing. Absent until the palette has handed back its opener,
rather than a button that does nothing.

## 119. Things to say: the recorder's card before the first word (2026-09-25)

Matt: "When I open the AI page, I should see a list of suggested prompts / commands / etc but don't see that card
anymore" - the page that opens from the microphone.

The recorder taught what could be said one line at a time, in a pause (§"Tips in a pause", `capture/tips.ts`):
after 2.5 s of quiet, "Say **Check box** to make a to-do", a different one each pause. Before the first word there
was the listening ghost and the line about how to stop, and nothing about what to say - which is the moment a person
is deciding what to say. So:

- **The card** (`capture/SayCard.tsx`, `capture/tips.ts` `starters`). Above the buttons while the microphone waits,
  "Things to say" in short groups with a mark each: to shape it (the first cues: "Bullet point", "The next item
  is …"); to send it somewhere ("Hey Ghost, add … to Groceries", naming one of their own notes once the notes are
  read, then "move this to Groceries", or "add a chapter to Field guide" when the library has a book; with nothing to
  name, "make a list called …" and "make a book called …"); and, on a note's own Speak, to ask the AI ("Hey Ghost,
  fix the spelling", "summarize this"). It takes no taps; the way to use it is to say a line. It goes the moment
  words arrive, and the one-line tips take over in the pauses as before - a tip is picked only once there are words,
  so none is spent under the card. The ghost above it is a fifth of the height rather than two, so "Start talking."
  keeps its room on an upright phone; a short window (a folded phone on its side) drops the ghost and the card's
  title and keeps one line a group.
- **Only what runs.** A spoken ask is read from the whole take (`ai/instruction.ts` `bareWords` wants the keyword to
  open it) and run only when the recording is a note's own Speak, not over the lock screen (`CaptureScreen.tsx`
  `finish`): the take is let go and the note opens with the run on it, every change marked. So the asks are on the
  card alone, only in that case, and never in the pause rotation, where "say it after the note's words" would end as
  the words in the note. A new recording gets the shaping and sending pairs and no ask, rather than a line that would
  end as a note of the command's words. `ASKS` is held to the reader's own rules by a test, so the card can never
  suggest one it would not run. Over the lock screen the card names no note, as the rest of the page keeps the
  note's words off it.
- **Which note it names** is worked out at render, never once: not the note being written to (the note's own Speak,
  or the one the take just moved to with "move this to …"), which the pause tips already avoided. And a routing line
  the cues' slots leave no room for (a note with a board names its lanes too) comes round after the cues rather than
  never.
- **What it is not.** The card is not the confirm card (§114, `ai/ConfirmCard.tsx`), which still takes its place when
  a command is understood, and it does not show once there are words, on the failed page, or while a command's chip
  is up.

## 119. Heat bends the text above it, and its words go bold (2026-09-25)

Matt, of §116's heat: "The fire effect should be messing with the text above it with the heat waves the text itself
should just have solid in the existing color but bold." Which is what the onboarding's flame did: it bent the words it
stood behind, not itself.

- **The words** are bold, in their own colour (`.cm-effect-heat`, weight 700, which both note faces ship). They
  first had no filter at all. Then Matt asked for "a slight but not as intense heat effect to the text itself being
  heated", so they now carry the same haze at 30% (`own` in `TEXT_EFFECTS.heat`): about a third of a letter's bend
  on the line above becomes a tenth, and the blur almost nothing. Up close they ripple, and at a glance they still
  read as solid bold.
- **The haze** is the same filter as before, over the text on the line above the words, under their width and a
  third of a line either side; and on the line above that at 55%, the heat thinning as it rises. It carries over one
  blank line between paragraphs, since most notes have one, but the weaker line stops at a blank.
- **Where "above" is** depends on the layout (a wrapped line, a heading, a proportional face), so it is measured after
  each draw (editor/textEffects.ts `textAbove`, with the view's character boxes as its probe) and drawn on the next
  frame. The haze changes no layout, so the second measure finds what the first did and the loop ends there.
- The cheat sheet's example has a line above its words, which would otherwise show only bold words.

## 120. A book opens where it was left (2026-09-25)

Matt: "When opening a book re open to the same spot it was last opened." A book is read in three places, and each
book keeps (book/bookSpot.ts, one localStorage key for the hundred most recent books) whichever of them it was last
at:

- **The index.** Written whenever the index is shown.
- **A chapter**, by title, since that is how the book finds its chapters (a chapter moved in the index is still the
  spot). Written when a chapter note is on screen with its book bar. The chapter's own note already keeps its place
  on the page (editor/notePlace.ts), so going back to the chapter goes back to the line too.
- **Reading straight through**: the chapter at the top of the page and how many pixels into it. That is a chapter
  rather than a page offset, so a chapter that grew above the place does not move it. It is written as scrolling
  settles, and when the app is hidden or the book closes. On the way back, the page is scrolled once the chapter is
  drawn, and again 150 ms later once the editors have measured their lines, unless the person scrolls first: the same
  wait as a note's place.

**Only from outside the book.** Opening the book from the home page's Library, the sidebar, the notes list, the
palette's notes by name, or a `[[link]]` goes to the spot (App.tsx `openNoteWhereLeft`, `whereLeft`). A tab, Back and
Forward, and the chapter bar's book button show the book itself, which is its index. Without that exception the book
button would send a chapter back to itself, and there would be no way to the index. For the same reason a book opened
while its spot's chapter is already on screen opens at its index.

Leaving the read-through for the index spends its place: *Read straight through* again starts where the page is, as it
always did. The reader page (src/read/Reader.tsx) keeps nothing.

## 121. One note card to a row on a phone (2026-09-25)

Matt: "Please make the size of the cards for note previews larger on small displays like standard phone portrait view
we may only see one note per row while unfolded may see 3-4".

The All notes page (§115's grid) sized its cards a step under the home page's, 10rem at the least, so a phone
held two across at about 180px each: four lines of a note's preview in type small enough to squint at. The home page's
cards were 15rem, one to a phone row already, but only three across the Fold opened out and on a desktop.

Both grids are now the same rule (`HomeScreen.module.css` and `AllNotesScreen.module.css`, `.cards`):

- **Under 600px wide, one column.** That is the app's phone line (`core/useWideScreen.ts`), the width at which it
  stops splitting, so a phone held upright always gets one card per row, whatever its width.
- **From 600px, as many as fit a card 12rem across.** Measured in the preview: two at 600px, three at 750, four at
  882, and four in a desktop window, where the page's 60rem column is the limit. The Fold opened out lands on three or
  four, depending on the width it reports.

Text size does not change this. The Larger and Largest settings scale the type (`--app-text-scale`), not the root
`rem`, so a card is the same width at every setting; its preview just holds fewer words.

## 122. No AI bar on the note (2026-09-25)

Matt: "Remove the AI button and AI dock code from notes idk why we added that but I don't like it".

§114's bar is gone, and with it §117's ✨ ring that showed and hid it. That removes:

- **The bar** (`ai/PromptBar.tsx`, its styles and tests) with its six chips (`CHIP_KINDS` in `ai/kinds.ts`) and its
  field, the page's room for it at the foot (`--ai-bar-room`), and the **ring** (`.aiSpark`).
- **The `aiBar` preference**, which kept the bar shown or hidden, and its place among the synced settings. A device
  that stored it keeps the unused key; nothing reads it.
- **Ask the AI** in the press-and-hold menu. It opened the bar with a selection as its scope, so it had nowhere to go.
  The menu's slot for such edits is still there, empty.
- **Commands typed into the bar**: the note screen's reading of them, the confirm card over the bar, and the two
  helpers only the bar used (`offerOf` and `listBody` in `ai/instruction.ts`). The confirm card itself stays, since
  the recorder uses it for spoken commands. The reader keeps its typed path, which only its tests now use.

Everything else from §114 stays: the More sheet's AI group and its runs, the strip under the header with its log and
Undo, the tracked changes they land as, an instruction spoken into a note, and the review after a recording.

## 123. A take said into a note never takes the note's tape with it (2026-09-25)

A take said into a note that already has a recording is put on the end of that note's own file (capture_stop
`recordAs` the note's id, `append`), so its words and its sound stay one timeline (capture/timeline.ts). The file is
then the whole of the note's recording, not the take's. Four endings treated it as the take's alone:
- an instruction for the AI ("Hey Ghost, fix the spelling");
- a refused command;
- a command card cancelled;
- a command card confirmed onto another note.
The first three deleted the note's whole recording; the last moved all of it onto the other note (found in the
cleanup's triage, Matt: "Yes fix that bug").

Now those endings let the sound go through one rule (CaptureScreen.tsx `letGo`), the same one a take that said
nothing already followed. A take that went on the end of a continued note's own tape stays there, and the note is told
the tape's new length with its phrases as they were, so the next take's words still line up with their sound. Only a
take recorded under its own id - a new recording - is removed, or moved to the note a confirmed command went to, as
before. The cost is a few seconds of the spoken command left at the end of the note's tape, heard only by playing past
its last words. Recording each take under its own id and joining it on only when the words are saved would avoid that,
but it changes capture_stop's contract and needs a native release.

## 124. The stylesheets as one system (2026-09-25)

The cleanup's third wave went through every stylesheet under src/ with one rule: nothing may draw differently. What
came out of it is a small vocabulary the modules share, and a test that holds the sheets to it.

**The cascade**, in the order both entries import it (src/main.tsx, src/read/main.tsx): the kit's fonts, Inter's
optical sizes, the kit's tokens, the kit's component styles, then Ghost.md's own - app.css (the shell and the shared
values), art/wisp.css (the page's edges under a header and at its foot, beside the art/ code that writes their
variables), ink.css (the palette), typefaces.css (the note's and the code's faces) and editor/codeThemes.css (the code
palettes). Every CSS module comes after all of them, so a module's rule beats a global one of the same weight. The one
global sheet that is not an entry's is settings/settings.css, imported by SettingsScreen.tsx and
settings/kit/settingsKit.tsx: the build puts it among the modules, after some and before others, so nothing may
count on where it falls.

**What app.css names, so no module writes its own copy:**

- `--app-gutter-start` and `--app-gutter-end`: the page's gutter with the notch, which every screen pads by. They are
  worked out at the root, so a surface that sets its own `--app-gutter` (a note drawn small, a book's preface, the
  reader, a mark's example) pads by `--app-gutter` itself.
- `--app-ring`: the one round control, every ring in the bar, the note's tools and the home dock.
- `--app-line`: the 1.5px weight of a line drawn on purpose, beside the kit's 1px hairline, which only separates.
- `--app-glass-mix` and `--app-glass-blur`, the header's glass; `--app-float-blur` and `--app-float-shadow`, a card
  that floats over the page.
- `--app-pop`, `--app-turn` and `--app-settle`: the app's own movements (a card popping in, a glyph turning when its
  button is pressed, a line settling). They are fixed durations and do not follow Settings > Animations > speed. Every
  other duration is still a literal beside the one movement it times, and several lengths recur (160ms, 200ms, 260ms,
  320ms and 900ms in four files each). They were left so on purpose: a shared length is not a shared movement, and a
  name would tie together what is free to change apart. A movement gets a property when a second place has to keep
  time with it, as these three do.
- `--app-tracking-caps` and `--app-tracking-caps-close`: the spacing of small capitals, beside the display and title
  tracking.

**The app's own pieces**, which modules compose rather than copy (`composes: app-unseen from global`): `.app-word`,
the quiet button; `.app-unseen`, words for a screen reader alone; `.app-eyebrow`, the spaced capitals over a group.
`.app-pill` and `.app-inverse` stay in ink.css, being made of ink. Shared module pieces work the same way:
settings/choiceCard.module.css (the theme, size and typeface cards), settings/swatch.module.css (the accent and
workspace dots), guide/MarkExample.module.css `.room` (a read-only editor, also the Academy's), book/rows.module.css,
and the home page's grid and empty page, which All notes composes.

**A composing class never overrides what it composes at the same weight.** postcss-modules writes a copy of the
composed file's rules at the head of every file that composes it, and of identical rules only the last copy counts
(the build's minifier keeps only that one). So the shared rules land just before the last file in the bundle to
compose them, or where the shared file is itself imported if that is later, and every other composer comes before
them: the choice card's rules come after the size and theme cards and before the typeface cards, and the swatch's after
the workspace swatch and before the accent swatch. Importing the shared file first changes nothing, since each
composer still carries its own copy. A composer that needs another value says it with a heavier selector
(`.option.option`, or an attribute), or the shared class leaves that property to its composers. One class broke the
rule from before the pass: the canvas card's words (canvas/CanvasView.module.css `.words`) asked for no height cap, no
margin and the card's ink over notes/NotePeek.module.css `.peek`, and got the peek's cap (about six lines, 120.7px), its
margin and its grey, since the peek's own sheet lands after the canvas's. Since 2026-09-27 they say it as `.words.words`,
and a card's words start at its padding, fill it to its foot and take its ink (0.965 in dark and 0.16 in light, where
they were 0.6 and 0.56): a 170px card on the "How Ghost.md works" canvas shows its words to 136px where they stopped at
121px, and a card that is only a table reaches its top edge. Words longer than their card still stop at its foot with
no fade, as they did, so a line can be cut through there. The test's list of classes that lose is empty.

**Rules the pass wrote down:**

- A `var()` of a property every page declares at its root has no fallback: it could never be used, and 568 of them
  read as values that were not the real ones (160ms beside a 150ms token). The scrollbar's pseudo-elements keep theirs,
  since no computed style or test screenshot can see them.
- The kit's space scale has no 7, 9, 11 or 14, and there is no bare `--glacier-danger`. A read of one draws its
  fallback, or nothing: the Claude drawer's close button, All notes' search pill, its clear and its order words have
  drawn at their content's size since they were written. They now say so, and giving them the size they asked for is a
  change to how they look, left for its own decision.
- The pills keep their 999px. Moved onto `--glacier-radius-full` (9999px) they are the same pills, but a corner is
  drawn a shade differently in a pixel or two, so they were moved back (ink.css says so beside the rounding setting).
- Every dark palette is written twice, for Dark and for System on a dark phone, which leaves `data-theme` off. The two
  must match, and a test holds them to it. The one pair that has always differed is named there rather than changed:
  under System an inverse surface takes the paper's hue lift, under Dark the page's own.

**The test**, src/app/stylesheets.test.ts, reads every stylesheet as text, since the suite runs with CSS off: no
custom property read that nothing declares; no `var()` without a fallback of a property that neither the root, nor the
reading sheet, nor a short named list (set inline by the code, or by the composer of a shared class) declares; no
`composes` of a class that is not there; no composing class setting what it composes at the same weight; and no dark
twin drifted.

**How the pass was proved to change nothing:** main and the branch were built side by side and every element's box
and computed style, pseudo-elements included, compared view by view - home, a note down its length and formatted,
the More sheet and its pages, the press-and-hold menu, the find bar, a board, the palette, All notes, the book and
its read-through, both canvases, the sidebar and aside cards, the guide, the Academy, the recorder, every Settings
pane, and hover and keyboard focus on the cards, swatches and bar buttons - in dark and light on a phone and a
desktop, three runs of each build, with anything that moved between two runs of the same build set aside as noise.
System dark and light, the three named themes, two sets of the Appearance and Type knobs, reduced motion and the
Fold's width were compared on the same views with two runs of each build, WebKit on the glass and card views with
three, and the browser pane on the main views in both themes. What differs is only what should: the build's own time and the test report's source line.

Two files were renamed with it: editor/Editor.module.css is editor/markdown.module.css, the renderer's rule book
named for what it draws, and the wisp's rules left app.css for art/wisp.css.

## 125. Ghost.md: The Guide, in the app (2026-09-25)

Matt: "I would like a "Ghost.md: The Guide"". The app's manual is now a book the app carries: Settings › About ›
*Add Ghost.md: The Guide* puts it in the library as notes and opens its index.

**What it is.** Forty-four chapters in eleven parts. Parts I to VI say what the app does and need no technical
background; Parts VII to XI say how it is made, for someone who reads code. It was written from the source at a2a12e6
and read against the code by a second pass. Where a doc and the code disagree, the chapters follow the code. The
last chapter, *Where the docs and the code disagree*, collects the disagreements that cut across chapters and points to
the chapters that end with their own doc's.

The book view draws no part headings (book/BookView.tsx shows a chapter's title and nothing else of its line, and
`bookWords` drops a heading left before the first chapter), so the index's lede names the two halves by chapter
number, 1 to 26 and 27 to 44. The parts stay in the Markdown, for anyone reading the file.

**How it ships.** Everything is in `src/app/guidebook/`:

- `chapters/NN-slug.md`, one file per chapter, the number its place in the book.
- `index.md`, the book note: `book: true`, the intro, each part a heading over its numbered `[[links]]`, and after the
  last chapter *Five things worth knowing before you start* and *How this was made*, which the index view shows under
  the chapters as the book's own words. The view numbers the chapters straight through the parts' headings
  (docs/BOOKS.md).
- `guidebook.ts`: `GUIDE_TITLE`, `loadGuideBook` and `addGuideBook`.

The chapters are Markdown files rather than strings in code, so the repo holds them as the notes they become,
readable and diffable as they are.

**It costs nothing until it is added.** `loadGuideBook` reads the chapters `?raw` through a lazy `import.meta.glob`,
and the index through a dynamic import, so each is a chunk of its own. Measured in a build of this tree: the entry
holds the glob's map of 44 imports, about 6.4 KB, and no chapter text. The 44 chapter chunks come to 380 KB, 161 KB
gzipped, from 3.7 KB (*Live typing*) to 14.9 KB (*The library on disk*), and the index's to 4.4 KB. An update
downloads them once, as it does every file in `ota.json`; the app reads none of them until the row is pressed.

**Adding it.** App.tsx hands `addGuideBook` the notes as the store has them now, less the trash, rather than the list
in hand, which can be a moment old (as `openTitle` does). Then:

- Signed in, a sync pass runs first (`syncNow`, raced against five seconds), so a book another device has added is
  here before the next step looks for it.
- A book already there by the guide's title is answered as it is, so a second press opens the first book.
- Each chapter is made only where no note has its title, since the index finds its chapters by title: a person's own
  note called *Live typing* stays, and is that chapter. An archived note counts as missing, as it does to a link.
- The chapters are made last one first and the index last, so the list, newest first, reads the index and then the
  book from chapter one, and Recent opens at the start.

The notes are written as typed ones (`source` left out), so they sync, share, change and delete like any other. Like
the other notes About adds, they are not filed in the workspace the list is showing.

A press that fails (the chunks cannot be fetched offline, or a deploy has replaced them under an open tab) says so in
a toast, "Ghost.md: The Guide did not load. Try again.", and leaves the person where they were (App.tsx
`openSample`). Chapters made before the failure stay, and the next press makes only the rest.

**Forty-five newest notes.** Added, the guide's notes are the newest in the library. Recent then shows its first six
chapters until something else is written; the book says so (*The first five minutes*). The command palette offered
only the forty notes changed last by name, so every older note dropped out of it. It now offers those forty with
nothing typed, and once something is typed the forty newest matches from the whole library, matched as the kit
matches a row (`notesByName` in commands/palette.ts, with CommandBar.tsx holding the query).

**Not seeded.** The sample note arrives by itself in an empty library; the guide does not. Forty-five notes would fill
a new library's Recent and its notes list before its person had written anything, so the guide is asked for.

**Held by tests.** `guidebook/guidebook.test.ts` checks that:

- the index parses as a book whose chapters are exactly the files' titles, in order, numbered one to forty-four;
- every chapter opens with its own title as its heading;
- every `[[link]]` outside code lands on a page of the book or a note About adds, and every `[[#^anchor]]` on an item
  in its own page, with the number of links read counted, so a scan that found nothing fails;
- no title is shared with another page or with the notes About adds;
- nothing reads as a secret (an IP address, `password:`, `token=`, SSHPASS, a long hex or base64 key), and the check
  knows one when it is shown one;
- adding twice leaves one book, and a note that already has a chapter's title is kept as that chapter;
- `GUIDE_CHAPTERS`, the count About's row gives, is the number of chapter files.

`settings/AboutPane.test.tsx` checks that the About row is there, counts 44 chapters and calls its handler.
`App.test.tsx` checks that a failed load says so and opens nothing, and that the sync pass runs before the book is
looked for.

`settings/SettingsSheet.test.tsx` finds the row by guide, manual, help and book, and its standing check finds the row
on the About page under the name the search gives it.

**Not done.** A guide added at one version stays as it was: a later release's chapters reach only a library that adds
the guide afresh, and adding it again while the book is there opens the old one. A sync pass that takes longer than
five seconds, or a device offline, can still leave two devices each making a book, since sync keeps notes by id and
never merges two with the same title. Two costs are not measured on the Fold yet: Read straight through mounts one
read-only editor per chapter, 44 at once over 380 KB, and the gist runner owes a line to each chapter the home page
and All notes show, up to thirty whole chapters sent to the smallest model after the guide is added.

**On the home page** (home/dashboard.ts `guidePages`): the Guide's pages stay out of Recent and the to-do list, and
their ticked examples out of the count. Added at once, its forty-four chapters were every Recent card, and the to-dos
four chapters draw as examples ("Book the cabin", "Call the plumber") sat among the person's own. The book is read
from its card in the Library. A chapter of a book of one's own is left as it was: only the Guide's are the manual's.

## 126. Words go into the note you name, as you say them (2026-09-26)

Matt: "whenever I put, hey, like add a note to house to do's, the note is call an electrician to fix the light
sockets. It creates a new note instead of finding a note with a similar title, like house to do's, house list items,
house chores. The AI should first step try to find a note that the person is talking about. And then when it's found
that note, it should look through the note and see what different things I could be talking about adding to. Like if
there's a list already or something like that. And then once we decide, then it should modify that note, open the
note, and start live writing to that note instead of doing the second pass over at the end."

**Why it made a new note.** Since PR #1 a recording was read once, at Done (§114). Matt's exact sentence, with its full
stop, did reach House TODOs through command.ts, but offered "The note is call an electrician…" and split one to-do
into a bullet per word. The new notes came from names under the letters-first matcher's 0.72 bar ("house chores" 0.5,
"house list items" 0.4), from openers the gate did not take ("Hey, like", "Hey goes", "Um, hey Ghost", "I want to"),
and from a name said alone: each ended as an ask, and a fresh recording saved an ask as a note of its words.

**The flow now.** Say "Hey Ghost, add a note to house to do's." at the start of a recording, then "The note is call an
electrician to fix the light sockets." The top line says Adding to "House TODOs", the page shows that note, and the
to-do is drawn into its list as it is said, the page following it there. Tap Done: the note is read fresh, written
once through `apply_command`, and opens with "Added to House TODOs" and Undo. There is no card and no review: the
words went in as they were said, which is the second pass Matt asked to lose.

**Finding the note** (capture/noteFind.ts). A name is read as distinctive words, which must all be in the title, and
kind words (to-do, task, chore, job; list, item, stuff, thing, note, page), which never decide and only back a match
up; to-do has one spelling on both sides. It answers resolved, current (the note being written to, or one of its
headings or lanes), unsure (a card) or missing (with near titles). Against Matt's 76 titles with the Guide added,
every way of saying House TODOs above resolves it; "task list", "hello trade the book" and "signing" are unsure.
The Guide's chapters and canvases are no longer candidates (capture/candidates.ts). Both readers use it.

**Where the words go** (capture/place.ts). The only list; the list under the heading that shares its words, by stems
with verbs left out ("call an electrician" under Electrical, not under Kitchen for "fix"); a to-do list for a to-do,
or when the title says to-dos; else the first open to-do list, or the last list. A note with no list starts one when
its title says what it holds, and otherwise the words go on its end. Each sentence is an item, one that carries the
last on goes under it. The page, Done and the better words all write with `placeTake`, so they agree.

**Reading at each commit** (capture/liveRoute.ts, capture/liveCommand.ts). PR #1's boundary is reopened for reading,
not for storing:

- Only committed phrases are read, and with "Commands start with hey Ghost" on (the default) only a phrase that opens
  with the keyword, or a known mishearing of it before a command for a note named clearly. Partials only draw.
- At the start of a fresh recording the note named is where the take goes (`route`). Mid-take, or on a note's own
  Speak, "add … to X" sends those words to X and the take carries on (`insert`). "Move this to X" moves the take.
  "Remind me to …" is a to-do here. "New note" starts one.
- An unsure name, or a missing one near a title or said with a note noun, raises a card. No card blocks anything: it
  takes Keep here after 8 s, and at once at Done, the side key, the screen going off, back and Discard.
- A book is never switched to; over the lock screen no card is shown and no shared note is written.
- A name that ran to the phrase's end can grow into the next phrase ("house" | "to-dos"), timed on the recording.

**Storing at Done, kept.** Nothing is stored mid-take. So a wrong switch is seen and put right (Not this note, which
sends the take home; Discard; Undo in the note) with nothing to take back from the store, and there are no drafts to
sync, share or double. Done writes each note once: what was said before New note, then the one-shots, then the
take's own note. A note that existed is read fresh and written through `apply_command` (takeWriter.ts `writeInto`),
which checks body and revision; a second conflict makes the words a note of their own. The stop's last words are
compared with every committed phrase, commands and all, and read by the live reader, so a command still being said
at Done is still carried out, and its sound follows it (`reassignRecording`), unless it went on the end of a note's
own tape (§123).

**The note that opens** (editor/useLanding.ts). Undo is an edit in its editor: the pieces written in are taken out as
they were written, saved like typing, and a piece edited since is left alone. Writes to other notes are undone
through `undo_command`. The better words wait while any note is open (refine.ts `holdNote`): the editor must be the
one writer of an open note. A refine job gains `placing` and `live`, so the better words land in the list, and a
better phrase that ran a command and its item together is replaced by the live phrases inside it.

**The reader at Done, fixed too.** It finds names with noteFind.ts, leaves "the note is" out, no longer lets a title's
"to-dos" ask for a list or split one thing word by word, reads "add to house to-dos, call…" up to the comma, takes
filler before the keyword and its mishearings, and saves a keyed ask on a fresh recording without the keyword, with a
chip. A confirmed card opens its note with an Undo; Discard while it waits is its Cancel; its "Or say yes or no" is
gone.

**Changed on purpose.** A note whose title says it is a list, by the word it ends on (House TODOs, Groceries, Task
list; not Task Management), takes what is said on its own Speak as items; any other note's own Speak still goes on its end byte for byte. What was said before New note is
written at Done, not at the tap, so Discard takes it back too. The tips teach only what a recording carries out. The
voice suite plays the live reader; its tests of a spoken no, tables, a plugin, board changes and voice memos are kept
and skipped with their reasons (docs/VOICE_TESTS.md).

**Where this differs from the plan it was built from.** A note's own Speak goes into its lists only when its title says
it is a list, not whenever its last block is a list: dictation into a note that happens to end with a list stays
prose. Front matter is read by the app's one rule (core/frontMatter.ts): a YAML list under a key is not front matter
to that rule, so the placement starts after `frontMatterEnd` and no second rule was made. A list item made from a
command's words is written as its cue ("Check box: …"), which the renderer lays out as the item, so the tape's
transcript shows the cue for that stretch. A table, book or board asked for mid-take is queued as an ask.

**Put right in review.** A second look at the built branch, each fix held to a test that fails without it:

- *The better words.* Every phrase the live reader changed or sent elsewhere is marked for them (a payload read after
  a switch, a one-shot's phrases, the words a card moved), so the larger model's phrase there is replaced by the live
  one, or by nothing: "The note is" no longer comes back into House TODOs, "milk, butter and bread" stays three items,
  and a one-shot's items are not written into the take's own note too. A card's new note keeps its title under them.
- *Mishearings.* "Okay, like", "hey, go", "hey, most" and "hey, post" are no longer the keyword, and a mishearing counts
  only before a command for a note named clearly, by its shape (a note or item said, a name with a kind word, "add
  this to X, …", a heading, "move this to"): "Hey, like, put the parcel in the post" and "Hey, like, I need to call my
  mum" are words. The reader at Done asks the same (`misheardShape`), and after a mishearing makes only a card, never
  a run, an ask or a refusal; the lead-ins a command starts with ("like", "I want to") come off only after the keyword.
- *Cards.* None offers a book, and a book tapped anyway keeps the words here. What a card keeps lands in the order it
  was said. Keep here keeps all of a long name that matched nothing ("moon base pack sunscreen and the tent"). A card
  replaced by another takes Keep here first.
- *One command after another.* A command held for its name gives up when the keyword is said again, and after three
  phrases, which it never did. A note switched to that waits for its words stops waiting when another command comes.
  A keyworded phrase the take opened with, left for the reader at Done, is taken out of the words and queued or left
  out once the live reader does anything, since the reader at Done then never runs.
- *Done.* What was said before a tapped New note is written first, and the reader at Done reads only what came after
  it. "Nothing was said for House TODOs" stays up long enough to read, and names no note over the lock screen. An
  Undo drops the better words only of words it took out of the open note. A note that was there already is not filed
  into the workspace being looked at.
- *One list chooser.* The reader at Done's list choice (listAppend.ts `runFor`) is now place.ts's, so a thing goes into
  the same list whichever reader wrote it.
- *Paragraphs.* "Add a paragraph to Groceries that says we are out of bread" ends the name at "that says" and goes at
  the end, as a paragraph.
- The voice suite's scripts that lost their "Yes." are marked `rerecord`, and its audio pass leaves them until they are
  made again; 101 answers a card.

**Questions for Matt.**

1. The review after recording is off for a take routed into an existing note. Should it go for new notes and a note's
   own Speak too?
2. Voice tables have been unreachable since PR #1. Bring them back in the live reader, or cut them?
3. With the keyword on, "Add a note to House TODOs, …" said without it still gets the card at Done. Should it write
   live too? (Turning the setting off does that now.)
4. Deploys: this is page code only, generation 19, over the air, whenever you choose.
5. A one-shot's note is now among the notes the review is told were changed, so its model reads that note's whole
   body. Keep that, or tell it only the lines added?
6. A command's words go through the dictation cues as any words do, so "leave a note for the weekend trip that says we
   need to book it by Thursday" writes the to-do "Book it by Thursday". Should words after "that says" stay as said?
7. "Hey Ghost, remind me to book the MOT" alone in a new recording makes a note whose first line is the to-do, so the
   list shows it as its title, marks and all; and a card's "New note “Moon base”" is titled with a plain first line,
   not a heading. Should either be titled differently?

**Tests.** noteFind.test.ts (Matt's titles), place.test.ts, liveCommand.test.ts, liveRoute.test.ts (through
liveTake.ts, the recorder's bookkeeping in memory), landing.test.ts, a CaptureScreen describe "adding to a note as it
is said" (Matt's case in two phrases fails at aff54fd), NoteScreen's Undo, useCaptureRoute's landing, refine's holds,
and eight new voice suite scripts (093 to 100) whose audio is still to be made.

**Not done.** A take killed mid-sentence still loses its words (a local journal read back at launch would fix it). The
on-device model does not pick among titles; it has not been timed on the Fold beside Whisper. "Hey Ghost" is not in
Whisper's prompt (an APK change). Voice memos said aloud, plugin commands by voice, and removing take.ts's
phrase-at-a-time reader are follow-ups. Kevin wrote PR #1 and should see this section.

## 127. Tapes on the home page, summaries, and meetings (2026-09-26, revised after review)

Matt: "Id like to expand on the voice notes, display them in a cassette shelf on the home page and add summaries to
them, I'm going to start recording meetings and stuff and letting the audio be transcribed then summarized by AI so I
get summarized recording notes automatically via a background task, when it's done send a notification that a new
recording has been summarized."

Standing rules this is built under: no always-on microphone (a recording in progress is the one open microphone, and
a meeting may need to carry on with the screen off); nothing leaves the phone unless he chooses it (whisper and the
Qwen models on the device; glyph-api is asked for nothing); the tape lives in the note (§26) and the note is the AI's
only surface (§114); every line of copy keeps §21's voice. Read-only map at HEAD 3d804cd. Nothing here has run on the
Fold. Section 9 is where the measured numbers go, and until a line there says a number was measured, every timing in
this section is an estimate from the emulator or the Mac.

**What the review changed.** The first draft was read against the tree and forty-odd holes were found. The shape
that came out of answering them:

- The shelf shows what the recorder made, ordered by when it was recorded. A typed note spoken into keeps its card.
- A summary is written once, on purpose or for a meeting, into a section with a shape the page owns and a close it
  can find again. It is never remade behind the person's back, so an edit to it is never lost and a ticked to-do
  never comes back open.
- Automatic summaries are tied to the kind of recording, not to an invisible length. The one length rule left (long
  voice notes, if he wants them) is written in the setting's own words.
- A meeting on Android is native work only. Nothing ships a screen-on, RAM-only, live-transcribing "meeting" on the
  current binary. The Mac gets meetings in the page recorder first, because its window keeps running and its memory
  is not a phone's.
- The service that records a meeting is the service that writes it up. WorkManager is the retry path, not the main
  one.
- Sync cannot be stopped by one long tape, meeting audio stays on the phone unless he says otherwise, and a
  notification on the lock screen says nothing of what was said.

Four things, in the order they ship: the shelf (page), summaries (page), meetings on the Mac (page), then meetings
and the write-up on Android (a native release, generation 20). Sections 1 and 2 were built as page code in 1.8.0;
sections 3 to 5 as the 1.9.0 APK (native generation 20) and its bundle, and 6 to 9 say what shipped with them.

### 1. Tapes: the shelf on the home page

**What is on it.** `home/dashboard.ts` `tapedNotes(notes, meetings)`: not archived, not a Guide page,
`recordingMs > 0`, and made by the recorder (`source === 'capture'`) or a meeting (`id in prefs.meetings`, section 3).
Ordered by `createdAt`, newest recorded first, which is how a shelf of tapes reads; a summary or the better words
landing later bumps `updatedAt` and must not move a tape along the row. Pure, tested. The list read already carries
`recordingMs`, `source` and `createdAt`, so the shelf costs no fetch. The workspace filter applies as to every group.

A typed note that was later spoken into (a note with a tape whose `source` is `editor`, a note with one voice memo)
is **not** on the shelf and stays in Recent, where he left it. Its card wears the tape's counter in its foot,
"12:40 · Yesterday" (`NoteCard.tsx` reads `recordingMs`, tabular figures, no icon). That is how a spoken-into note is
told from a typed one off the shelf. A note that was recorded is a tape; a note that was written and then talked into
is a note.

**Nothing twice.** `recentNotes` leaves out exactly the notes `tapedNotes` takes (one exported predicate,
`isTape(note, meetings)`, used by both). Pinned keeps its card and the cassette is drawn as well, since pinning is a
deliberate act. `openTasks` is untouched.

**Where it sits.** Pinned, **Tapes**, Library, Recent, To do. Heading `.group` as the others, with a small cassette
mark drawn in `art/Icons.tsx` (`Cassette`, the shell of `TapeArt` in the icon's own line weight), the way the pin sits
on Pinned.

**A cassette.** `<TapeArt bare positionMs={recordingMs} lengthMs={shelfLength} />` inside a `<button>` that opens the
note (`onOpen(id)`, the same `openNoteWhereLeft` a card uses). `bare` draws the label paper with its A mark and no
words: at the shelf's 11rem the label's 13px title would be 7px and its small print 4px, unreadable, and on the cover
screen the whole row is 412px wide. The words go **under** the cassette in real type:

- Line one, the title (`noteTitle(body) || 'Untitled'`), `--glacier-font-size-sm`, one line, clipped by CSS, the
  whole of the column. It was first built with the counter and the date beside it, as the draft said: measured in
  the built page at 412px the pair took 81 to 101 of the column's 176px and the title read as nine characters
  ("Standup n…", "Call with …"), which is not a title to find a tape by, so the counter and the date went under it.
- Line two, in the caps style of `.small`, the counter and the date: "12:40 · 26 Sep" (`tapes/tapeDate.ts`, the
  one formatter NoteTape's label uses as well).
- Line three, the caption (below).

`tapeLabel` stays NoteTape's. Reels still; a tap does not play. The tape is the player and lives in the note (§26).
`aria-label` = "{title}, {counter}, {date}" plus ", summarized" when it has a summary.

- `TapeArt` gets `lengthMs?: number` (default `TAPE_MS`): how much tape fills the cassette.
  `packRadii(positionMs, lengthMs = TAPE_MS)` and `reelTurn(positionMs, ms, lengthMs)` take it. The shelf passes the
  longest tape on the shelf, at least five minutes, so a three-minute note beside an hour's meeting is a thin ring
  beside a full reel. NoteTape passes `Math.max(TAPE_MS, tape.length)`, so a long tape winds across its whole length
  in playback instead of saturating at five minutes. This is what makes tape.ts's header sentence ("nobody has to
  read a number to see how long a note is") true past five minutes.
- The mask id `tape-label-mask` becomes per instance (`useId()`): eight cassettes on one page share it today.
- Arrival beat: each cassette takes `--i` as the cards do (capped at 8). The groups under the shelf count it as
  three beats (`SHELF_BEATS`), the cassettes the cover screen shows, not eight: counted whole, Recent's first card
  came on beat 8, 320ms after Home was pressed, under a heading with nothing yet beneath it.
- To be measured on the Fold's cover screen before the OTA: the title line readable, two and a bit cassettes
  showing. In Chromium at 412x915, not yet the Fold: three cassettes on screen and two whole, the title 176px wide
  and seven of the eight seeded titles whole ("Call with Sam about the l…" the one clipped), the row 196px tall with
  every caption empty, and the "and N more" word level with the reels (both middles at 505px).

**The caption**, under the counter, the first of these that is true:

1. "Recording" with the reels turning, while this note's meeting is being recorded (section 3; the shelf polls
   `GlyphHost.meetingState()` once a second while visible, only on a binary that has it).
2. "Listening again" with the working spinner (`LoaderCircle`, NoteCard's `.working`) while the note's better-words
   job is queued or running (`useRefining().pending.has(id)`).
3. "Writing up" with the spinner while a native write-up is running for it (section 4;
   `useSummaries().native.has(id)`).
4. "Summarizing" with the spinner while its page summary is queued or running (`useSummaries().pending.has(id)`),
   the strip's own word (`kindWords('summarize').doing`).
5. On a phone, while 2 or 4 is true for a tape over ten minutes and the write-up is the page's (not the service's):
   "Keep Ghost.md open" after the word, since the page's queues only run while the app is up (VoiceModelStatus's
   precedent, "Keep Ghost.md open.").
6. "Needs a model" with a `Get a model` word (`app-word`, opens Settings › Formatting) when the job is waiting for a
   language model that is not on the phone.
7. "The summary didn't come" with a `Try again` word after the queue gave up.
8. The summary's first sentence (`summaryLine(body)`), in the gist's style (`.gist`).
9. Else the gist, if the note has one; else nothing.

The caption's words flow as prose and wrap when they must, a word to tap after them and under them when it does not
fit beside. Clipped to one line, as first built, "Listening again. Keep Ghost.md open." (240px at the column's 176)
and "The summary didn't come" beside Try again drew as "Listening again. Keep …" and "The summary …", and rule 5's
sentence never reached the screen. Measured at 412px the two Keep-open states take two lines, Try again goes under
its words, and "Needs a model Get a model" fits on one. An empty caption keeps a line's height
(`min-block-size: calc(size * leading)`: the kit's leading tokens are unitless, and read as a length one is no
length at all, which stylesheets.test.ts now holds), so the page under the shelf does not move when a gist or a
summary lands.

`useGists` is given the shelf's notes as well as the cards' (`carded = [...pinned, ...shelf, ...recent]`,
HomeScreen.tsx), or a 40-second voice note would never get a line. A landed summary changes the body past the gist's
5% rule, so one gist run follows each summary; that is fine and said here.

The order is one pure function, `captionOf` in `home/tapeCaption.ts`, beside the shelf that draws it. The states
that depend on the later sections (1, 3, 4, 6, 7, 8) read their sources through small hooks that answer "none"
today: `ai/summaries.ts` (`useSummaries`, `retrySummary`), `ai/summaryText.ts` (`summaryLine`) and
`home/useMeetingLive.ts`. The caption code and its tests exist now; the later slices fill the hooks. Only
`useRefining().pending` is real in this slice.

**How many.** `SHELF = 8`, beside `RECENT = 6` and `TASKS = 8`. Past eight, a word at the end of the row, "and N
more in All notes" (`.more`, as To do says it), which opens the grid with its new **Tapes** toggle on.
`notes/AllNotesScreen.tsx` gets a Tapes toggle beside the order words, in the archive toggle's shape; `browseNotes`
gains `{ tapes: boolean }` (every note with `recordingMs > 0`, typed ones included, so nothing with a tape is
unreachable). Test in allNotes.test.ts. With a hundred recordings this is the way to the ninety-second. The
controls line on All notes wraps on a phone: with the Tapes word the line no longer fit 412px, so the tally and
Archived go down together as a line of their own under the order words and Tapes (`.counts`), where on a wide line
they sit as they always did.

**Widths.** A row that scrolls sideways at every width, bleeding to the screen's edges under the gutters (negative
inline margins to `--app-gutter-start/end`, padding back in), `scroll-snap-type: x proximity`, each cassette `11rem`
wide with `--glacier-space-3` between, the three text lines under each in the same column. `prefers-reduced-motion`
changes nothing (the reels are still already, except a meeting's, which then stay still too). The mouse wheel is left
alone over the row, unlike over the tab row and the pills (`core/scrollSideways.ts`): those sit in bars with nothing
to scroll above them, while the shelf sits in the page's own scroller, and React's wheel listeners are passive, so a
turn of the wheel over the row moved it a cassette sideways and scrolled the page down at once (synthetic wheel
events in the built page). Shift with the wheel, a trackpad's sideways swipe and a finger all still move the row, and
"and N more" is the mouse's way to the rest.

**Empty.** No group when there are no tapes. No loading state.

**Files.** `home/dashboard.ts` (`isTape`, `tapedNotes`, `recentNotes`), `home/TapeShelf.tsx` +
`TapeShelf.module.css`, `home/HomeScreen.tsx` (the section, `SHELF`, `SHELF_BEATS`, gists for the shelf),
`capture/tape.ts` (`lengthMs`), `tapes/TapeArt.tsx` (`bare`, `lengthMs`, `useId`), `tapes/NoteTape.tsx`
(`lengthMs`), `tapes/tapeDate.ts` (the day and the month, for the label and the shelf), `notes/NoteCard.tsx`
(+ `.tapeLength`), `notes/AllNotesScreen.tsx` + `notes/allNotes.ts` (Tapes toggle; `hasTape`, the one way "has a
recording" is written, which `isTape` and the card read), `art/Icons.tsx` (`Cassette`), `core/preferences.ts`
(`meetings: Record<string, number>`, synced like `trash`, empty until section 3 writes it). Tests: dashboard.test.ts
(order by `createdAt`; archive, Guide and typed-with-tape out; `recentNotes` leaves out only what the shelf takes; a
typed note with a tape stays in Recent), tape.test.ts (`packRadii` with `lengthMs`), tapes.test.tsx (an hour's tape
winds across its whole length, at the strip and at the cassette, and its reels turn over its own radii),
HomeScreen.test.tsx (heading order and the cassette mark; the workspace filter; "and N more" opens the grid with
Tapes on; the shelf's notes are gisted), TapeShelf.test.tsx (each caption state in order and the ten-minute line,
"Keep Ghost.md open." in those words, the reels turn only for a meeting, the five-minute floor, Try again re-queues,
Get a model opens Settings), SettingsSheet.test.tsx (Get a model lands on Formatting), App.test.tsx ("and N more"
reaches the grid with Tapes on; Get a model opens Settings at Formatting), core/sync/prefs.test.ts (`meetings`
travels), stylesheets.test.ts (no leading token read as a length), NoteCard test (the counter in the foot),
allNotes.test.ts (`tapes`). Page code, over the air, generation 19.

### 2. The summary

Built 2026-09-27, as page code, generation 19. Matt: "add summaries to them, I'm going to start recording meetings
and stuff and letting the audio be transcribed then summarized by AI so I get summarized recording notes
automatically". He chose where it runs: on the phone, the on-device model, after the better words, never the
server.

**When.** A summary is made for a **meeting** (section 3) when its transcript is there, automatically; for any note
with a tape, when the tape strip's **Summarize** word is tapped (`tapes/NoteTape.tsx`); and for a **long voice
note**, automatically, only when the setting says so. Meetings do not exist yet: the `'meeting'` kind is typed and
handled by the queue, and nothing makes one. Never for a typed note spoken into (the recorder's own new note alone
is enqueued at Done, `saved.source === 'capture'` and not aimed), and never again on its own: an Add to the tape does
not remake the summary. The strip says "Summary is from before the last take." with the word to remake it, which it
knows from the tape's length: the kept record carries `forMs`, the tape's length when the summary was written, and a
longer tape now is a take it never heard.

- **Setting.** Settings › Recording › After recording › **Summaries**, a three-way choice under Better words:
  "Meetings" (default), "Meetings and long voice notes", "Off". Hint: "The language model on the phone writes a
  summary under the title. What was said, what was decided, and your to-dos. A long voice note is one over three
  minutes. A few minutes of the phone for a long recording." Search words: summary, meeting, write-up, minutes.
  `prefs.summaries: 'meetings' | 'long' | 'off'`, synced with the person's other choices;
  `core/preferences.ts` `LONG_NOTE_MS = 180_000`, one line to change and the sentence in the hint with it. The
  Recording pane is listed on the Mac as well as Android (`isAndroid || (isTauri() && !isMobile)`): the Mac records
  through Speak, runs the better words and the summaries, and its rows had no home there. Without "Where the side
  key is", and its first section titled "While recording" rather than "The side key".

**The review's place.** `CaptureScreen.finish` runs the review only for a take under `LONG_NOTE_MS` (the take's
own span, `recordingMs - fromMs` of its better-words job); a longer take goes back to the list and the recorder's
Done line says why, for `SAID_MS`: "Long recording. The better words come later." with "The summary comes later."
appended when one was queued. The Review setting's hint says "For recordings under three minutes." One or the other,
never both.

**What it reads.** The tape, not the note: `renderNote(note.segments).plain`, the note read fresh by id, commands
already left out of the phrases the note keeps. A meeting's transcript will be the same text, so every path
summarises the same words.

**What it writes.** One section, into the body, so it is words: synced, shared, in the `.md` file, in To do.

```
# Planning call with Sam

## Summary
What the call settled about the March launch.

- Launch moves to the second week of March.
- Sam: the press list by Friday.

- Decided: no paid ads until the beta closes.

- [ ] Book the venue before the 10th.

We started with the launch date. …
```

- **The section has a shape the page owns** (`ai/summaryText.ts` `shapeSummary(modelText)`): the heading
  `## Summary`; one prose line, taken only straight after the heading; then only item lines (`-`, `- [ ]`, `- [x]`),
  blanks collapsed to one between groups and one put after the prose line. What a 4B reaches for is read as what
  was meant: a `*`, `+`, numbered (`1.`, `2)`) or typographic (`•`) bullet is made a dash, a box written tight
  (`-[ ]`) is given its space, a `Decided:` line without its dash is made an item, a label on the prose line
  (`**Summary**`, `**Summary:**`, `Summary:`) or an introduction ending in a colon is not the prose (the next line of
  prose is, and an emptied line never leaves two blanks), and a sentence wrapped over two lines is one sentence
  (joined while the line before did not end its sentence; a second sentence is still dropped). The model's
  `# heading` first line is taken for the title and never written into the section; any other prose line, heading,
  rule, code fence or closing remark is dropped, and a mark still under the pen (a lone `#`, `-`, `1.` or `•`) is
  skipped, so the shape is a prefix of itself as the model streams and a run's landed lines never move (the heading,
  once any prose has come, stays even while a label is stripped to nothing). `summarySection(body, kept?)` finds it
  again: with the kept text (below) it is that text's lines where the body still reads so from `## Summary`, boxes
  ticked or not, with a blank or the end after it - the keep closes it, so the person's own list straight under it
  is never read as the section's, which the shape alone cannot tell (a blank followed by `- [ ]` lines is still the
  shape); by the shape otherwise: through the prose line if it comes before any item, and every following blank or
  item line, ending at the first line that is none of those, or a `#` heading, or a rule, or the end; trailing
  blanks are not its. A dictated note's paragraphs end it at their first line; `## Transcript` ends it too. Never
  inside the front matter. Every reader that has the keep hands it in: both writers, the strip's `edited`, the
  better words' guard.
- **Place** (`summaryPlace(body)`): after the front matter and after the first line of words, whatever its marks:
  after a `# title` line; after a plain first paragraph, through its last line; after a to-do first line and the
  list it opens; a picture first line is stepped over as `noteTitle` steps over it. Never above the first line of
  words. A note with no words at all (`hasWords`: the tape kept and the text cleared, a picture alone) would be
  titled "Summary" by the section's own heading, so both writers put the model's heading above it as a `# title`
  line; a title named in the front matter counts as words and is left.
- **Again, only on purpose.** `ai/summaryKeep.ts` (`glyph-summaries`, a `noteSheet`) keeps per note the exact
  section text the app wrote, the model, when, and `forMs`. On a remake: a section that still equals the kept text
  is replaced whole; one that differs was edited, and the strip asks "You edited the summary. Replace it?" with
  **Replace** and **Keep mine**, nothing written until one is tapped (Replace queues the job with `replace: true`;
  a job of the queue's own finds an edited section and is dropped, never remade behind the person's back); with no
  section a fresh one is written at its place. `carryTicked(old, next)`: every `- [x]` line of the old section is
  carried verbatim into the new one after the new to-dos, or as a group of its own when the new one has none; a
  ticked line the model kept - whatever the case of its box or its closing full stop - is not doubled; un-ticked
  old to-dos are not carried.
- **Title**: `dateTitled(body)` is a first line reading "Meeting, 26 Sep 14:05" (either order of day and month);
  `retitled(body, title)` takes the model's heading only then, and never a title named in the front matter. Both
  writers apply it.
- **Guard**: `updateNote(id, next, note.revision)`; a conflict is read again and applied once more, then given up
  for this pass with the model's answer kept on the job (`text`), so the next kick writes without asking the model
  again; any other failure of the write counts as a try, so a note the bridge cannot write fails after three rather
  than being tried every twenty seconds for as long as the app is open. The job waits for `syncSettled()` and calls
  `syncNow()` before its read and after its write. The merge rule (section 6: theirs taken with the local section
  re-applied, no conflict copy) is to come; until it lands, a summary landing while another device edits the same
  note makes a conflict copy as any crossing edit does.
- **An open note lands through its editor.** The note screen registers a starter with the queue
  (`ai/summaries.ts` `openForSummaries`, from `editor/useNoteAi.ts`); when the job's turn comes the queue hands it
  the words and the summary is a run (`ai/start.ts` `startNoteRun` with `{ recording }`: the recording prompt, the
  tape's words, a `scope` at the section's place or over the old section - its newline included, so the lander
  does not take the section's last line for the note's and put one more blank under it at every remake - and a
  `placement` of `'replace'` on the run, which `landingAt` takes over the kind's own rule and `ai/useLanding.ts`
  reads again for a note reopened mid-run). The strip follows it and the lines land as tracked changes with Keep
  and Revert. The model's answer is shaped as it streams (`restore`), with a blank line landed first where the line
  above is words; a title that ran straight into its paragraph gets a blank line put under it before the run, so
  the section stands on its own rather than making the paragraph the last item's. The ticked to-dos are carried as
  the run finishes, and the title taken once it is done. What the queue keeps is the section as it landed
  (`summarySection` of the run's text), never the run's text with its opening blank, so the strip's next Summarize
  finds the section unchanged. The strip's word itself only enqueues: the pieces of a long transcript run in the
  queue, and the final pass lands as the run. A note that is closed is written plain by `withSummary`, since a
  background write can make no marks - but never under an open editor: the plain write checks for the note's
  starter before every `updateNote`, and a note opened while the model wrote is handed the finished answer
  (`SummaryAsk.text`) for its editor to land at once, with no run, as the same tracked changes (`landReady`: the
  lander, the AI's signature, the log's record for Undo); a kept answer from a pass that could not write is handed
  over the same way at the next kick. The editor's next save would otherwise conflict and every save of that visit
  after it be dropped (`editor/useNoteSaving.ts`), which is the hole the hand-off exists to close. Both writers
  place the section with `summaryPlace` and shape it with `shapeSummary`: one rule, one set of tests.
- `summaryLine(body)`: the prose line under `## Summary`, for the shelf, the toast and the notification.
- More's Summarize (SUMMARIZE_PROMPT over the body, landing above the note) stays as it is; the strip's word is the
  recording's. Its hint: "The recording, summarized under the title."

**The prompt** (`format/prompt.ts` `RECORDING_SUMMARY_PROMPT`, a plain `String.raw` literal so `llm/tests.rs` can
read it by name, with SUMMARIZE_PROMPT's keeps). It asks for: a first line `# name` in the recording's own words;
one sentence saying what the recording is (who was there only if said); three to eight points as `-` items, **other
people's actions among them with the name first** ("- Sam: the press list by Friday."), never boxed - the rule sits
with the points because the example puts "- Sam: the press list." there, and a 4B copies the example over a rule;
decisions as `-` items beginning "Decided:", only where something was decided; **a `- [ ]` only for what the person
recording has to do** (said as I, we, my, or their own name), under ten words, with the when where said; at most a
fifth of the recording's words and never more than about two hundred; plain markdown, no `*` bullets, no numbered
lists, no other labels, no closing remark. `TEMPERATURE` (0.3), no thinking. Model:
`modelFor(present, prefs.formatModel)`. Budget `recordingSummaryBudget(chars) = min(1024, max(200, tokens / 6 + 96))`.
The Rust side runs it since 1.9.0: `llm/tests.rs` reads both prompts by name
(`recording_summary_boxes_only_the_recorders_own_actions`, `recording_notes_are_items_only`) over a two-speaker
meeting and checks which lines carry a box; both need the model and skip without it.

**Long recordings.** `transcriptPieces(plain, PIECE_CHARS = 12_000)`: 20,000 chars or fewer goes in one pass;
longer is cut at paragraph breaks into pieces of about 3,000 tokens, a paragraph longer than a piece cut at sentence
ends, nothing dropped. Each piece goes through `RECORDING_NOTES_PROMPT` with the line "Part n of m of one recording."
before it (budget `recordingNotesBudget(chars) = min(512, max(128, tokens / 4 + 64))`), then the joined notes through
the summary prompt under `NOTES_CONTEXT(words)`: "These are notes on the parts of one recording, in order. The
recording itself was about 9,400 words: the summary's length is measured against that, not against these notes."
- without the second sentence an hour's meeting came out at a fifth of the notes, about a hundred words. Each
finished piece is checkpointed in the job (`pieces`), so a kill after four of five starts at the fifth.

**The queue** (`ai/summaries.ts`, on `capture/refine.ts`'s pattern). `glyph-summary-queue` in localStorage, one job
per note `{ id, kind, tries, started?, pieces?, text?, native?, failed?, replace? }`. `enqueueSummary(id, kind,
{ native, replace })`, `startSummaries(changed, summarized)` wired in `shell/useHousekeeping.ts` after
`startRefining`, kicked 4 s after launch and 2 s after every return to the foreground, one at a time, only in Tauri,
only while the page is visible to start.

- **Holds**: `refineHeld()` (the recorder or a review is up); `refinePending(id)` (the note's better words are still
  to come, checked before the run and again before the write; a job held only by that looks again in 20 s);
  `anyRunning()` with a 3 s wait; `isTrashed(id)` (the job waits, and a delete for good drops it); `syncSettled()`.
  The hold is read again after every wait and before every generation - after the sync wait, between two pieces,
  before the editor's starter - so one that arrives mid-job starts nothing more; the gist runner checks the same
  before its generation.
- **The recorder wins the cores.** `refine.ts` tells who follows its hold (`onRefineHold`), and the summary queue
  and the gist runner (`format/gist.ts` `pauseGists`) follow it: a run in flight is cancelled (`ai_cancel` through
  the run's own cancel) and its job left queued, uncounted; a gist cancelled this way is not counted against its
  note. That cut is the queue's own (`cut`, set as it cancels) and is told from a stop by the person: the strip's
  Stop, the scene's, or a run of their own started on the note, which end the summary's run the same way, drop
  the job instead - Stop sticks, and the model is not asked again twenty seconds later. An editor run the recorder
  cut leaves the lines that landed (a half section, the app's own); the job is patched `replace: true`, so the
  re-run lands over that half by shape rather than reading it as an edit and dropping the job. A subscription
  rather than calls into the two modules, because the queue reads `refineHeld` and `refinePending` from refine.ts
  and a module that imported it back would be a cycle. refine.ts's guard reads the note against what Done saved
  with the app's own section (the kept one, unchanged) written in at its place (`withSummary(savedBody, kept)`,
  trailing newline aside), and carries the section into the better words where they lack it, so a summary that
  landed between Done and the better words stops neither; a `## Summary` the person typed is theirs, in the better
  words already from the words before the take and never moved, and the app's section edited since Done is an edit
  like any other, which wins.
- **A poison job cannot kill the app at every launch.** A job is marked `started` before it runs and cleared
  however it ends; a job found `started` at launch counts that as one try. `refine.ts` has the same field. Three
  tries and it is `failed`, for the caption's Try again (`retrySummary`), which resets `tries`.
- **No model**: the job waits, looks again in 60 s, and the caption says "Needs a model" with the way to Settings;
  the strip says "Needs a model." too, for a job queued from elsewhere, while its own Summarize word is there only
  where the AI can run or is still being looked for (`useNoteAi` `canSummarize`, from `ai/available.ts`: not in a
  browser, not on iOS, not without a model). A job queued behind the note's better words is not "Summarizing" yet:
  the strip's word is plain and disabled and the line under it says "The summary comes after the better words."
  "busy" or "cancelled": 20 s, uncounted. A failure: `tries + 1`.
- A note deleted for good drops its job and its kept record (`dropSummary`, `forgetSummary` beside
  `forgetResults` in `notes/useNoteActions.ts`); trashed, it waits.
- **Success**: `changed()` refreshes the list; a toast "Summarized “{title}”" with **Open** (`useToast`, 10 s,
  opening the note where it was left) when the page is visible, and not for a native job. A native job (section 4)
  waits in the queue for a result nothing delivers yet.
- Runs through `generate()` for a closed note, and through the note screen's starter for an open one.
  `useSummaries()` is the external store the shelf and the strip read: `pending`, `native`, `failed`, `needsModel`.
- `ai_unload` after a long tape is generation 20; until then the five-minute idle bounds the engine's context.

**The scene** (§128) is for one run, and a summary run may follow the review's on the same note: while the queue
holds a job for the note, `scene/AtWork.tsx` waits `GRACE_MS` after an end rather than `HOLD_MS` alone, then
follows the summary run as "Reading the recording" and "Writing the summary".

**Web.** No summariser: the strip has no Summarize word there (`summary` is null where the AI cannot run), the
setting is not listed, and the page shows what synced, the shelf's caption included.

**Files.** `ai/summaries.ts`, `ai/summaryText.ts` (`shapeSummary`, `summarySection`, `summaryPlace`, `withSummary`,
`withoutSummary`, `carryTicked`, `summaryLine`, `dateTitled`, `retitled`, `transcriptPieces`; pure),
`ai/summaryKeep.ts` (`glyph-summaries`), `ai/start.ts` (`recording` option, `landingAt` from a placement),
`ai/runs.ts` (`placement`), `ai/useLanding.ts`, `format/prompt.ts` (two prompts, two budgets), `capture/refine.ts`
(`refineHeld`, `refinePending`, `onRefineHold`, `started`, the stripped compare), `format/gist.ts` (`pauseGists`),
`capture/CaptureScreen.tsx` (the review's line, the Done line, the long-note enqueue), `tapes/NoteTape.tsx`
(Summarize, the ask, the lines), `editor/useNoteAi.ts` + `editor/NoteScreen.tsx` (the starter, the strip's ask),
`settings/RecordingPane.tsx` + `SettingsSheet.tsx`, `core/preferences.ts` (`summaries`, `LONG_NOTE_MS`),
`core/sync/prefs.ts`, `shell/useHousekeeping.ts` + `App.tsx` (wire, toast, Open), `notes/useNoteActions.ts` (drop
on delete), `scene/AtWork.tsx` (the grace). Tests: summaryText.test.ts (shape, the stream, found by shape and
closed by a paragraph, a heading, a rule, `## Transcript`; place after a title, a plain line, a to-do, a picture,
front matter; the no-words title; replace whole; the keep closing the section over the person's list; ticked
carried and matched loosely; `dateTitled`; pieces; `summaryLine`; every paragraph kept on a remake; the labels,
bullets, boxes and wrapped sentences the shape reads; the stream with them), summaries.test.ts (writes and keeps;
waits behind refine, before the run and before the write; behind a run; the recorder cancels and leaves the job,
during the sync wait and between pieces too; `started` counts a try; no model says so, in the store; three tries
then failed and Try again; a write failure counts; trashed waits and deleted drops; native waits; visible only;
edited left alone and replaced on purpose; the conflict; the date title; pieces and the checkpoint; the open note's
hand-off through the real editor run, the section kept as landed, the note opened mid-generation handed the answer,
the recorder's cut versus the person's Stop), prompt.test.ts (both prompts readable by name, the other-people rule
with the points, the budgets), start.test.ts (the run's scope over the section's newline, placement, the streamed
shape, the blank line, over the old section and in place, edited refused, the keep closing over a list, the no-words
title, the date title taken, the ready answer landed with no run), refine.test.ts (the guard with the section
written in, a typed section left, an edited one stopping the pass, `started`, the hold told), gistRunner.test.tsx
(paused, and paused during the catalogue read), tapes.test.tsx (the word, the ask, the lines, the wait for the
better words), NoteScreen.test.tsx (the word only where the AI can run), CaptureScreen.test.tsx (review under three
minutes, none over, the Done line, the enqueue only when the setting says), RecordingPane.test.tsx and
SettingsSheet.test.tsx (the choice, the Mac), useHousekeeping.test.tsx (the toast's Open), useNoteActions.test.tsx
(the drop), AtWork.test.tsx (the grace). In Rust, to come: `llm/tests.rs` over the two-speaker fixture. Page code,
over the air, generation 19. Nothing here has run on the Fold.

### 3. Meetings

Built 2026-09-27: on the Mac as page code, and on Android as native generation 20 (1.9.0). Matt chose where the words
are made and how long the microphone stays open: summaries on the phone, never the server, and a meeting recording
that keeps going with the screen off.

**A meeting is known by a preference.** `prefs.meetings: Record<noteId, startedAtMs>` (slice 1's shape, written from
here). The note is `source: 'capture'`, titled by `capture/meeting.ts` `meetingTitle`: "Meeting, 26 Sep 14:05", the
day and the month in the locale's own order from `Intl.DateTimeFormat`'s parts with its literals dropped (de-DE's
"." after the day), then the time on a 24-hour clock. `meeting.test.ts` holds it to `dateTitled` under en-GB, en-US
and de-DE at 00:05 and 14:05, so the model's heading still replaces it when the summary lands.

**Record only, during.** No live reader, no reader at Done, no keyword, no quiet stop, no review, no title from the
first sentence. The transcript is paragraphs cut at 1.5 s pauses under `## Transcript`, no cues
(`capture/markdown.ts` `renderTranscript`, with `transcriptOf`, `withTranscript` and `withoutTranscript` beside it).

**Where it can run.** `capture/meeting.ts` `MEETING_GENERATION = 20` and `canRecordMeeting()`: the Mac always,
Android from generation 20 (`hasNativeGeneration`), never iOS (no whisper, no model) and never a browser (its engine
keeps no audio). The + sheet's **Meeting** row (the cassette, "Record a meeting. The screen can go off. It is written
up afterwards.") and the recorder card's "Meeting instead" are drawn only where it answers true.

#### 3a. On the Mac, in the page recorder

`captureScreen(fromAssistant, noteId?, { meeting: true })` puts `CaptureScreen` in meeting mode: the quiet stop off,
the live reader replaced by the take listening raw, no card, no instruction, no review, no keyword, the where-line
"Meeting", and the live page drawing `renderTranscript(segments, partial)` under the date title. "Meeting instead" on
the card flips the recorder into this mode. Done writes `# <title>` over the transcript as a `'capture'` note, files
it, records its tape, writes `prefs.meetings[id]`, queues the better words with `meeting: true` (`capture/refine.ts`
renders such a job through `renderTranscript` and keeps the app's summary section, compared with `withoutSummary`)
and the summary unless Summaries is Off, and says "Keep Ghost.md open while it is written up." The hour's audio is in
RAM until Done, as every page recording is; on a Mac that is 115 MB and fine. Not measured (section 9).

#### 3b. On Android, generation 20

1. **The page first.** `shell/useCaptureRoute.ts` `meeting`: the note (date title, `'capture'`), filed where the list
   is looking, its tape id, `prefs.meetings[id]`, a native summary job unless Summaries is Off, and only then
   `GlyphHost.startMeeting(noteId, title)`, which answers from what the bridge thread can check:
   - `"started"`: the meeting screen. `meeting { event: "started" }` confirms it; `failed` undoes it.
   - `"permission"`: RECORD_AUDIO is not granted (a phone that never dictated). The activity asks with request code
     4104 (`REQUEST_MICROPHONE`; 4101 is update alerts', 4102 the picture picker's) and delivers the answer as
     `meeting { event: "permission", noteId, granted }` from `onResume`, never from `onRequestPermissionsResult`,
     so the page's retry starts the service with the activity resumed, which a `microphone` service needs. A refusal
     Android answers without a dialog (refused for good) goes at once, since no resume follows it.
   - `"recording"`: that meeting's screen, and the new note taken back.
   - anything else: taken back and said.

   **The undo has one owner**, the same hook: the note deleted, the preference and the job dropped, the meeting
   screen left, and the line ("Ghost.md needs the microphone to record a meeting.", "The meeting could not start.",
   or the service's own sentence). From the recorder's card, `CaptureScreen` first cancels its session, stops the
   WebView's microphone, discards the take and ends the capture, because the WebView's microphone must be shut
   before `AudioRecord` can open. While a meeting is being recorded every way into a capture (Speak, the side key,
   the boot) opens the meeting screen instead, since the microphone is taken.

2. **`capture/MeetingService.kt`**, declared `microphone|mediaProcessing|specialUse` and started as `microphone`
   (typed from Android 11, the two-argument form below) inside one `try`: the notification first and shown at once
   (`FOREGROUND_SERVICE_IMMEDIATE`, where Android 12+ would hold it back ten seconds), a partial wake lock
   `glyph:meeting` with its own limit past the cap, then `AudioRecord` from `MIC`, 16 kHz mono PCM16, no effects, a
   two-second buffer. Anything thrown, or a recorder that did not initialise, deletes the file, clears the state and
   pushes `failed`. A reader thread writes 4 KB at a time straight into `recordings/<id>.wav` through
   `capture/WavSpool.kt`, whose 44-byte header is `wav::header`'s byte for byte, both lengths patched every ten
   seconds and at close, so a kill leaves a header at most ten seconds short. The state behind `meetingState()` is
   in the service's companion and mirrored in SharedPreferences `glyph_meeting` for the meeting a kill leaves.
   - The notification (channel `glyph_recordings`, id 4201): "Recording · 12:40", its counter refreshed every ten
     seconds, silent and alerting once, ongoing, public on the lock screen (a running microphone should be
     stoppable by whoever holds the phone, and it shows only a counter), with **Stop** and **Discard** as
     foreground-service intents. Its tap is a plain launch with an extra: at a cold start `takeLaunch()` answers
     `"meeting"` and the boot opens the meeting screen from `meetingState()`; with the app up it is
     `meeting { event: "open" }`.
   - **Muted by another app.** An `AudioRecordingCallback` on the recorder: while `isClientSilenced` the notification
     says "Muted by another app · 12:40" and the meeting screen "Muted by another app."; the file keeps growing with
     silence, so the timeline stays honest. A read error stops the meeting as Done does, with the reason `error`.
   - **The cap.** At two hours "Still recording? · 2:00:00" is a notification of its own (id 4203, not silent, since a
     question nobody can hear is not a question) with **Keep going** and **Stop**. Unanswered for five minutes, the
     meeting stops as Done with the reason `cap`; at four hours it stops whatever was answered.
   - No `FLAG_KEEP_SCREEN_ON` and no screen-off receiver: those are the dictation's. The screen can go off, the app
     can be left, the phone can be folded.
   - **Swiping the app away ends the meeting, and it is written up anyway.** The draft said a started service
     outlives its task. On this shell it does not: the Tauri shell exits its process when its last activity is
     destroyed (`lib.rs`'s run callback lets `ExitRequested` through), and the service goes with the process. On
     the emulator a Recents swipe ended it with "exited cleanly (0)", the service still in front, and the meeting
     then waited for the next launch to be written up. So `onTaskRemoved` stops the meeting as Done does and waits
     for the chain request to be written down, and what was recorded is written up with the app closed (section 9
     has it seen). Keeping the recording going past a swipe means keeping the process when a meeting holds it and
     giving a new activity in that process a webview, and Tauri's plugin manager keeps its first activity for good
     (its own comment: "on destroy, we should change to a different activity"). That is shell work of its own, and
     whether it is worth doing is Matt's question.
3. **`capture/MeetingScreen.tsx`** (`shell/screen.ts` `{ name: 'meeting', noteId, fromAssistant, key }`): the cassette
   turning (`TapeArt playing`, the elapsed time as its position and `max(TAPE_MS, elapsed)` as its length), the
   counter, "Recording. The screen can go off and you can leave. Stop here or from the notification.", **Discard**
   and **Done**. Nothing of the note, since the side key can open it over the lock screen. It calls none of the
   recorder's mount effects: no `setCapturing`, no `setRecorderLive`, no screen-off answer. **Back leaves; it does not
   stop**: the list, and a locked phone handed back to its lock screen when the side key opened it. Done calls
   `stopMeeting()`; Discard calls `discardMeeting()` and deletes the note, its preference and its job itself.
   Under the cassette, until asked once on this device (`glyph-meeting-alerts-asked`): "Let Ghost.md tell you when it
   is written up." with **Allow**; refused, "Notifications are off for Ghost.md, so stop it here." The state comes
   from the one store, `capture/meetingLive.ts`: `meetingState()` read once a second while visible and something
   listens, at once on a return to the front and on the activity's refresh (heard as the notes-changed event, since
   the notes store owns `refresh`), and on every `meeting` push, which it fans out to the screens that own undo
   state (`onMeetingEvent`). `home/useMeetingLive.ts` is that store's note id, so the shelf's "Recording" caption is
   real, and `tapedNotes(notes, meetings, live)` puts the live meeting first before it has a length.
4. **Stop** (Done, the notification, the cap, a read error): the microphone let go (the wake lock kept for the
   write-up), then `RecordingJob.finish(dataDir, noteId, title)` on the service's own thread. `finish` writes
   `jobs/<id>.progress` as `queued` with the title before anything that can fail, then patches the header from the
   file's length and records the tape's length on the note. It never deletes anything: an error is written into the
   file and the chain takes the job, whose `run` repeats `finish`'s steps where they are not done, so an hour of audio
   is never unlinked because a library open lost a race. The page is told `stopped` with its reason, the service
   says it has the job in hand, makes the chain request, and carries on as the write-up (section 4). **Discard**
   deletes the WAV, marks the job cancelled and clears `glyph_meeting`; from the notification, with the app closed,
   the id is also kept in `discarded` until the page has deleted the note and called `forgetDiscarded`.

   **No meeting starts while a Stop is being put away** (`MeetingService.isEnding`, from the Stop until the type has
   changed for the write-up; about one to four seconds): `startMeeting` answers "The last meeting is still stopping.
   Try again in a moment.", which the page says and takes back. The review found why: a meeting started in that
   window had its state and `glyph_meeting` cleared by the last one's bookkeeping, so its Done returned early and the
   microphone stayed open until the process died; the type change for the write-up ran under its open `AudioRecord`,
   so it went on recording silence with the screen off; and its Done waited behind the last one's whole write-up on
   the one control thread. Now the bookkeeping clears only what still names its own meeting, the write-up runs on a
   thread of its own so a later Done and Discard never queue behind it, a write-up does not start (or go on) while a
   meeting records, and a new meeting asks any write-up in hand to let go as `meeting`, the service's or the worker's,
   asking again for five seconds because a run that has not reached Rust's `RUNNING_JOB` cannot hear the first ask.
   "Still recording?" is taken down whenever the service stops or a killed meeting is recovered, and a write-up's
   last progress line is not posted after Android's budget (`onTimeout`) has stopped the service. The spooled WAV is
   synced to the disk at every ten-second patch, so a power cut loses at most that, and a header a power cut left
   claiming more than landed is brought down to the file by `patch_header` rather than failing the job three times.
5. **A meeting a kill left.** `MeetingService.recover`, off the main thread at every `MainActivity.onCreate`: a
   `glyph_meeting` with no service recording is cleared and handed to the chain with its title, unless Rust already
   has a progress file for it or a request for it waits (a second fresh request after the page took the first one's
   result would write the meeting up again), and the page is told `stopped { reason: "died" }` once it has a
   handler (offered every two seconds for half a minute a resume). It does not call `finish` itself, so it cannot
   race Tauri's own index open in the same second. Then the sweep: every
   `jobs/*.progress` that is not `done`, `needsModel`, `failed` or `cancelled` goes back into the chain unless a
   request for it is already there. `library/index.rs` opens under a process-wide lock around its version check and
   rebuild, and `index_file` replaces a row in one immediate transaction: two handles in one process scanning the same
   file raced the path's unique constraint in one run of two before, and never in thirty since, under load too.

**Every take spooled to disk is not in this release.** Nothing yet recovers a spooled take without a note, so it ships
with that recovery in a later native release, and the recorder's header sentence stays as slice 1 corrected it: a
kill loses the take's audio.

**`wav.rs`** has one rule for where the samples end, `data_end`: a `data` chunk that is the file's last runs to the
end of the file in whole samples, and any other is its declared length clamped to the file. `parse`, `read_span` (one
stretch read by seeking, never the hour), `duration_ms` (the header and the length only) and `spans::find` all use it,
so a header ten seconds short reads the same everywhere; `patch_header` puts it right. Tests both ways round.

**`recordings.rs` serves a tape by seek.** `serve` stats the file, seeks and reads only the bytes a range asks for;
an open range (`bytes=a-`) is answered with at most `OPEN_RANGE_CAP` (2 MB) as a 206 with its `Content-Range`, and the
element asks for the rest as it plays. No range is the whole file as a 200, as before. Opening an hour's note no
longer reads 115 MB on the WebView's thread, and a seek does not read it again. A `HEAD` (the tape asking why it
would not play, the Tapes row asking which audio is here) reads nothing and says the length. Tested on a file through
a reader that counts what it reads.

**Files.** Kotlin: `capture/MeetingService.kt`, `capture/WavSpool.kt`, `recordings/RecordingJob.kt`,
`recordings/RecordingWorker.kt`, `recordings/WriteUp.kt`, `recordings/RecordingAlerts.kt`, `MainActivity.kt` (the
bridge, 4103 and 4104, the resumed-activity reference the service speaks through, the launch extra, the link), the
manifest (`FOREGROUND_SERVICE` and its `MICROPHONE`, `MEDIA_PROCESSING` and `SPECIAL_USE` kinds, `WAKE_LOCK`, the
service with its special-use subtype, the write-up's types merged onto WorkManager's own foreground service). Rust:
`guards.rs`, `jobs.rs`, `transcript.rs`, `write_up.rs`, `recording_jobs.rs`, `recording_commands.rs`,
`whisper/spans.rs`, `whisper/wav.rs`, `recordings.rs`, `library/index.rs`, `ota.rs` (`NATIVE_GENERATION` 20,
`BUNDLE_REQUIRES` still 19). Page: `capture/meeting.ts`, `capture/meetingLive.ts`, `capture/MeetingScreen.tsx`,
`core/host.ts`, `core/recordings.ts`, `shell/useCaptureRoute.ts`, `shell/screen.ts`, `notes/NewSheet.tsx`,
`capture/SayCard.tsx`, `capture/CaptureScreen.tsx`. Tests: meeting.test.ts, meetingLive.test.tsx,
MeetingScreen.test.tsx, useCaptureRoute.test.tsx (the start in order, the microphone's answer with and without a note
named, every undo, the meeting already recording, a tap that names no note), CaptureScreen.test.tsx (the Mac's
meeting and Meeting instead), NewSheet.test.tsx; in Rust wav.rs's and spans.rs's (tone-and-silence files, one with a
short header), recordings.rs's (ranges on a file), library's two handles on an older index from two threads; in
Kotlin `WavSpoolTest`.

### 4. The write-up with the app closed (Android, generation 20)

**Who runs it.** The service itself, after Stop: `startForeground` again under `mediaProcessing` on Android 15 and
later, `specialUse` on 14, the untyped form below, with the notification (still id 4201) saying "Listening to the
recording, 40%", then "Summarizing". The chain request is made before the write-up starts, so a kill mid-way is
WorkManager's to pick up rather than the next launch's; if the type change is refused (the emulator accepted it; the
Fold is section 9's), the chain takes the job.

**The retry path**, `recordings/RecordingWorker.kt`, a plain `Worker`:
- One chain, `glyph-write-ups`, under `APPEND_OR_REPLACE` (under `APPEND` a failed or cancelled request would cancel
  everything queued after it), linear backoff from two minutes, each request tagged `glyph-write-up:<id>`.
- A second unique work, `glyph-write-ups-charging` (`KEEP`, requires charging), sweeps every unfinished job into the
  chain when the charger connects. That is how a job the battery rule held comes back, with no polling.
- `doWork`: waits (`Result.retry()`) while a meeting is being recorded or the service has this job in hand; succeeds
  at once for a job already done or with no file left and nothing fresh asked; asks to be foreground (id 4202) inside
  a `try`, and runs without when Android refuses it from the background, which costs at most the span in hand.
  `Result.retry()` only for a partial; every terminal outcome is a success, so a job that failed for good does not
  back off forever. `onStopped` (Reset, or the ten-minute limit on work with no foreground) lets the run go as a
  timeout, resumable.
- One member of the chain is never cancelled through WorkManager, since that cancels everything appended after it.

**One door to start a write-up and one to stop it, both Kotlin's**, the one side that knows WorkManager and the JNI
cancel. `GlyphHost.writeUp(noteId, now)` (Write up now, Try again, a note restored from the trash, a model that
arrived) queues one fresh request. `cancelWriteUp(noteId)` (the trash) is `RecordingJob.cancel(…, "cancel")` alone,
and the worker that later reaches the id finds it cancelled and moves on. **A fresh request carries when it was made**
(`requestedAt`), and Rust reopens a `cancelled` file for it only when the cancel is older: WorkManager retries a
request with the same input after every hold, and a meeting put in the trash while a Write up now waited was being
written up by the retry, notification and all. The two doors run one after the other on one Kotlin thread, so the
toast's Undo straight after a trash always makes the newer request. `cancelWriteUps()` (Reset) cancels both
unique works whole and then any run in hand, waiting for it on the bridge thread, so Rust's reset removes `jobs/`
after the run's last write rather than before one that would leave a file behind.

**When.** Settings › Recording › Meetings › **Write up**: "When charging or above half" (the default) or "Straight
away", with the hint "A meeting is written up when the phone is charging or above half. Straight away uses more of
the battery." The rule is Rust's, decided from Kotlin's readings (`charging`, `batteryPercent`) and the setting in
`jobs/config.json`: a job held by it is `waiting` for `battery`, Kotlin makes the charging sweep, and the shelf's
caption says "Waiting to charge" with **Write up now**, which queues it with `now` from the foreground. Heat:
`severe` or worse at the start holds the job; during a run Kotlin reads the thermal status every thirty seconds and
cancels with `thermal` at `THERMAL_STATUS_SEVERE`, Rust lets go within one graph computation, and the service waits a
minute at a time, up to thirty, before running again (the worker retries instead). Android 15's `onTimeout` cancels
with `timeout` and stops within seconds.

**Cores.** One rule, `guards::background_threads(x) = max(2, x / 2)`, applied to whisper's `min(4, cores)` and the
model's `clamp(2, 6)` alike, and only while the app is in front (`appInFront`, from `ProcessLifecycleOwner`): with it
closed nobody is typing, and the write-up takes what the foreground would. Chosen once a run. llama-cpp-2 0.1.156 has
no run-time thread setter, so the kept context remembers its count and is remade when a job asks for another.

**The Rust job** (`write_up.rs`, no Tauri types; `recording_jobs.rs` is the door, three
`Java_com_mattssoftware_glyph_recordings_RecordingJob_{finish,run,cancel}` symbols under `catch_unwind` answering
JSON, and `recordings/RecordingJob.kt` loads `glyph_lib` itself, as `UpdateCheck` does, because WorkManager can start
the process with no activity). `run(dataDir, noteId, options)`:

0. No WAV: `gone`, and the file with it. The file's phase is settled first, before any hold, so a done job looked at
   during a dictation is still done: `done` answers `alreadyDone`; `cancelled` answers `cancelled` unless the run is
   fresh; a fresh run resets the tries and queues a `cancelled`, `failed` or `needsModel` file with its checkpoints
   kept; `failed` at three tries answers the error `again`; `needsModel` looks for the model once more and answers
   `again` while it is still not there. Kotlin posts nothing for an answer said before. Then the holds, each a
   `waiting` file and a retry that is not counted: a dictation running (`capturing`), the one small.en in use
   (`busy`: `guards::WRITE_UP`, which the dictation's better words try too; a lock poisoned by a panic is recovered,
   never busy for good), the battery, the heat. A `queued` file repeats `finish`'s steps, each only where not done.
1. **Listening.** `whisper/spans.rs` `find` runs the energy VAD over the file thirty seconds at a time by the live
   streamer's rules (two voiced frames to start, 600 ms of quiet to close once 1.5 s of speech has come, 300 ms kept
   either side, split at the longest pause once a span would pass `WINDOW_CAP`, 28 s), never holding the hour. Each
   span not yet done is read with `read_span` and transcribed by small.en (base.en when only that is on the phone;
   neither is `needsModel`) on the job's abort, with the previous span's tail as its prompt through
   `text::prompt_plain`, never `text::prompt`: the cue vocabulary would prime an hour of cross-talk with "Title.
   Heading. Scratch that." Every span is checkpointed, so the job resumes by span, and a watcher rewrites the percent
   every two seconds. The engine and the audio go before the model loads.
2. **The note.** The phrases beside it (`set_recording`), and the transcript into its body from Rust:
   `transcript::paragraphs`, the twin of `toParagraphs`, held to the page by one fixture both sides read
   (`src/app/capture/paragraphs.fixture.json`), through `with_transcript` and `update_note` at the note's revision; a
   conflict is read again once, then held as `conflict`. A meeting note is never wordless on disk, in its `.md` file,
   in sync or to the MCP, even when the summary never comes.
3. **Summarizing**, unless Summaries is Off, and not at all when nothing was heard: a model asked to summarise an
   empty transcript writes one anyway, and the prompt's first rule is that nothing is invented. `llm::shared()`, the
   one worker both doors use (moved out of Tauri's managed state), with `background: true`. 20,000 characters or
   fewer in one pass; longer, `transcript::pieces` at 12,000 through `RECORDING_NOTES_PROMPT` with "Part n of m of one
   recording." before each piece, each piece's notes checkpointed, then the notes through the summary prompt with
   `NOTES_CONTEXT` as its context: exactly where `ai/summaries.ts` puts them. The model, the prompts, the piece rule,
   the temperature and the two settings come from `jobs/config.json`, which the page writes at launch and on every
   change (`ai_keep_job_config`); a fresh install that never ran the page falls back to `write_up::prompts`, which a
   test without a model holds equal to the page's `String.raw` literals, `PIECE_CONTEXT` and `NOTES_CONTEXT` among
   them (moved to `format/prompt.ts` as `{n}`, `{m}` and `{words}` templates with a `fill` on each side). No model on
   the phone is `needsModel`, never retried on its own, and nothing ever downloads.
4. **Done.** `jobs/<id>.json` `{ summary, model, transcriptChars, finishedAt }`, the file `done`, the model unloaded.

Any other error is counted; the third is `failed`. `cancel(dataDir, noteId, reason)` raises the abort when that note's
run is in hand; for `cancel` it waits up to five seconds for the run to let go and marks the file `cancelled`, never
taking `WRITE_UP`, so the trash is never stuck behind a dictation's better words. A `done` file is left as it is: its
result waits for the page, and a meeting brought back from the trash lands it rather than being written up twice. It
removes nothing: removal is `recording_result_take`'s, `recording_delete`'s, `delete_note`'s and reset's.

**Asked again, it keeps the words the note has.** A fresh run with nothing listened to yet, for a note that already has
words under `## Transcript` (the page took the last result), takes those words as the transcript: listening again
would take an hour's decoding and replace everything from the heading down, the person's corrections with it.

**The model is the page's rule on both sides.** The config names the model the page would run, and is sent again when
a model is downloaded or removed as well as when the model chosen, Write up or Summaries changes (`ai/jobConfig.ts`;
the model list is not read for any other preference); a model's arrival sends it before asking a waiting job again.
Rust picks by the same rule from what is on the phone (`llm::model::model_for`, the twin of `modelFor`), so a config
that still names an absent model does not end the job "Needs a model" a second time.

**Two handles, one writer at a time.** The app's library and the write-up's (opened over JNI) write the same notes in
one process, and `update_note`'s check of the revision and its write are separate steps: interleaved, both passed at
the same revision and the later file write won with no conflict seen. Every write in `library/` now holds one
process-wide lock, re-entrantly, so the editor's rebase on a conflict is what meets the transcript.

**The foreground comes first.** A page generation asked for while a background piece runs raises the abort with
`busy` before it is sent: the piece ends, the job is retried two minutes later uncounted, and a voice command after
Done, a page summary or a format never waits behind a 3,000-token prefill. A background job counts as running from
its model's load, so a request that arrives during the load preempts it too. The worker drains its inbox into a
queue and takes a shutdown first, then foreground work, then background. Exit raises `shutdown` and waits up to two
seconds for the run in hand to let go (it runs on the service's or the worker's thread, which nobody joins) before
the worker is joined; a dictation starting raises `capturing` before its engine loads and counts as running from
then (`guards::capture_starting`), so a write-up that begins in that second is held rather than lowering the flag the
dictation raised; whether a capture is running is derived from the capture slot under its own lock after every
change of it (`guards::change_capture`), never stored by hand.

**The files** (`jobs.rs`, every target, no Tauri types): `jobs/config.json`, `jobs/<id>.progress` and `jobs/<id>.json`.
Every write to a `.progress` in the process goes through `Progress::save` under one lock, which reads the file's phase
first and never writes over `cancelled` unless it is a fresh `queued`, so a cancel from the trash is not undone by the
watcher's next tick. Kotlin only reads the phase, the percent and the title.

**On the page while the app is up.** `ai/summaries.ts` `landNativeResult(id)`, in this order: an answer the job
already holds is written without asking the phone (the take happened, the page died before the write); else
`recording_result_take`, and a result makes the job if there is none and lands through the same `write` as every page
summary, or through the note's editor when it is open; no summary (Summaries Off, or nothing heard) ends the job.
It runs on `recordingDone`, on every kick, at once on a return to the front and on the refresh, and every fifteen
seconds while a native job waits and the page is visible. `publish()` reads `recording_job_state` into the shelf's
store: `needsModel`, `failed`, `waiting` for the battery (the new `waiting` caption), `cancelled` (the job dropped),
else `native`. Try again and Write up now call `writeUp(id, true)`; a model arriving asks each waiting job again with
`writeUp(id, false)`. The better words hold while a write-up is listening or summarizing (both want small.en; Rust's
`WRITE_UP` is the hard guard). **The open editor** takes the transcript Rust wrote: a conflict whose only difference
is the transcript section (`withoutTranscript` alike) is rebased onto it and saved again, and any other conflict stops
as before; `NoteScreen` reloads a note with no unsaved edits when its write-up leaves listening or ends, so the
transcript is seen arriving; a save flushed and not yet answered counts as unsaved, so the note is not adopted over
it. The trash: putting a meeting there cancels its write-up (`cancelWriteUp`, for every meeting, since Summaries Off
makes no page job to ask by) and drops the page job; taking it out again, by Restore or by the toast's Undo alike,
asks the phone again only where the phone still holds a job for it or the note has no transcript. An update's
install is refused while a meeting records ("Stop the meeting first."), as a reset is. Reset refuses while a meeting is being recorded ("Stop the
meeting first."), then cancels the write-ups before `reset_local_data`, which now removes `jobs/` with the recordings.
After a page summary of a transcript over the one-pass length, the page lets the engine's context go (`ai_unload`).

**Memory, said plainly.** One span's audio and whisper, dropped; then the model and one piece's context. Not the old
draft's 115 MB, 230 MB, 190 MB and an 8k-token cache at once.

**Files.** Rust: `write_up.rs`, `recording_jobs.rs`, `jobs.rs`, `guards.rs`, `lock.rs` (`try_lock`),
`transcript.rs` (and in tools/host-tests), `whisper/spans.rs`, `whisper/engine.rs` (`load_with_threads`,
`TimedText::offset` moved from the refine), `whisper/text.rs` (`prompt_plain`), `llm/engine.rs` (the shared worker,
the queue order, the preemption), `llm/generate.rs` (the context's thread count), `llm/job.rs` (`background`),
`ai_commands.rs` (`ai_unload`, `shutdown`), `capture_commands.rs` and `capture_commands/refine.rs` (the flag, the
lock), `recording_commands.rs`, `reset.rs`, `commands.rs` (`delete_note` takes the job's files). Kotlin:
`recordings/`. Page: `ai/summaries.ts`, `ai/jobConfig.ts`, `core/ai.ts` (`keepJobConfig`, `unloadModel`), `core/recordings.ts`,
`format/prompt.ts`, `shell/useHousekeeping.ts`, `editor/useNoteSaving.ts`, `editor/NoteScreen.tsx`,
`home/tapeCaption.ts`, `home/TapeShelf.tsx`, `home/dashboard.ts`, `capture/refine.ts`, `notes/useNoteActions.ts`,
`core/reset.ts`. Tests: every terminal phase with and without `fresh`; a cancel during a run marks the file and the
watcher's tick cannot unmark it; a poisoned `WRITE_UP` recovered; a cancel within its wait while a refine holds the
lock; `finish` on a library that cannot open keeps the WAV and a `queued` file that says so; a silent meeting written
up to the end without a model, and not summarised with summaries on; the holds; the counted error; the Kotlin door
and the Rust symbols naming each other; the Kotlin twins for `recordings` and `jobs`; the queue order and the
preemption on a fake inbox. Since the review, each rule the review could break with every suite green has a test
that fails without it: the real listening with base.en over two spoken sentences (two spans, each phrase at its place
on the tape, a resume that decodes only the second), skipped without the model or `say`; the summary one pass and
piece by piece through a stand-in for the model (the piece line in the prompt, the parts line in the context, a
resume at the piece it stopped on, a dictation between pieces holding the rest); every condition of the battery rule
and its boundary; Summaries Off with words; a meeting a kill left before `finish`; the fence; a cancel that leaves a
done file; the words kept on a fresh run; the model picked from what is here; the Kotlin options' keys against the
Rust fields, the answers' keys, the thermal words and the terminal phases read out of `WriteUp.kt`, the door's full
signatures; one `recordingsDir` in `MeetingService.kt`; the capture slot raced by a stop and a start; a foreground
request preempting a background one on the real model; the context remade for other cores; the window cap and the
short phrase in the span finder; two handles writing one revision at once. On the page: `landNativeResult`'s order,
`tapedNotes` with a live id, the editor's rebase, its stop on another writer's words, and no adopting over a save in
flight, the caption's `waiting`, the trash's cancel, Undo and Restore, the reset's and the install's refusal, the
meeting screen never keeping the screen on, the page's gates against `NATIVE_GENERATION` (scripts/lib/otaRs.test.mjs),
the job config and when it is sent, the digest on iOS and on a failed call. `llm/tests.rs` reads both recording
prompts by name over a two-speaker meeting (only the recorder's own actions boxed, the notes items only); both need
the 4B and skip without it.

### 5. The notification

**Android.** Channel `glyph_recordings` ("Recordings", `IMPORTANCE_DEFAULT`, "While a meeting is being recorded, and
when one has been written up"), made by `recordings/RecordingAlerts.kt` the way `UpdateAlerts` makes `glyph_updates`.
When a write-up ends for the first time, the service or the worker posts it under the tag `GlyphRecordings` with the
note id's hash: "Written up: Meeting, 26 Sep 14:05" (the progress file's title; the model's heading is the page's to
apply) over the summary's first sentence (BigText), found by `write_up::summary_line` as the page's `summaryLine`
finds it. Without a sentence it says where the words are: "The summary is in the note.", "The transcript is in the
note." with Summaries Off, "Nothing was heard in the recording." for a tape with no speech. No model: "Needs the
language model to write up the meeting." Failed: "The meeting could not be written up." `VISIBILITY_PRIVATE` with a
public version that says only "A recording was written up": a locked phone shows nothing of a note, and a meeting's
first sentence says who decided what. Auto-cancelled. Never posted for an answer said before, a job already done, a
cancel or a tape that is gone. The write-up's own progress notification is private too, with a public version titled
"Writing up": a write-up asked again takes its title from the note's heading, which is the note's words. `window.__glyph.recordingDone({ id, outcome })` goes to a resumed page beside it, and
the page toasts a native job only when Ghost.md cannot notify, so a meeting written up while the app is open is said
once, and one written up with notifications refused is still said.

**Permission.** `GlyphHost.requestNotifications()` asks with its own request code, 4103, and its answer arrives as
`window.__glyph.notified()`, never through `alerts`: `answerHost` keeps one answer a name, `alerts` is update alerts',
and turning those on starts a six-hourly network job. It answers `"allowed"`, `"asked"`, or `"blocked"` (asked
before and refused for good, or granted with the app's notifications turned off). `canNotify()` is the permission,
the app's switch and the channel not set to nothing. Asked from the meeting screen once per device, and from Settings
› Recording › Meetings › "Tell me when a meeting is written up" (**Allow**). Refused, the write-up still runs, the
shelf still says, and the meeting screen says "Notifications are off for Ghost.md, so stop it here."

**The tap opens the note with its words.** The content intent is `ACTION_VIEW ghostmd://note/<id>` at MainActivity,
and the link reaches the page two ways, because the deep-link plugin's channel is per activity and set once by Rust:
an activity recreated in a live process has none, and `links.rs` would never see the URL. So MainActivity keeps
`intent.data` itself in `onCreate` and `onNewIntent`, and `GlyphHost.takeLink()` hands it over once, beside the
plugin's `links_take`; `share/appLinks.ts` `followAppLinks` takes both and drops a URL it has already seen in the same
take, `readNoteLink` reads `ghostmd://note/<id>`, and `shell/useAppLinks.ts` (was `useForkLinks`) sends share links to
the fork and note links to `openNote`, which lands a waiting result first (`landNativeResult`) and then opens the note
where it was left. The transcript is in the body already, so a tap that beats the summary still opens a note with its
words.

**The page path** (dictations, the strip's word, Mac meetings): the toast, "Summarized “{title}”" with **Open**, as
section 2 built it. No system notification from the page.

**Mac** system notifications need `tauri-plugin-notification` and a signed bundle: not in this release.

### 6. Sync, storage, sharing, privacy

- **The summary and the transcript are words in the body**: the `.md` file, sync, a share link, a download, To do.
  The phrases stay in the sidecar. `docs/LIBRARY.md` says so, and names `jobs/` beside `recordings/`.
- **One tape cannot stop sync.** `push` catches per note: a note whose send fails is counted and the pass goes on,
  `once()` reports "N notes not synced" with the first reason, and a 401 still ends the pass. The settings row's
  summary says the count.
- **A recording over the service's limit is never sent.** `RECORDING_SYNC_LIMIT = 64 * 1024 * 1024`, the server's
  `RECORDING_LIMIT`; a tape is over it when `recordingMs * 32 + 44` is, decided before a byte is read. The note goes
  with its length and phrases and no recording, so the words show everywhere and the tape says "This recording is not
  on this device." where `rec://` has nothing.
- **Meeting audio stays on the phone unless he says otherwise.** Settings › Account › Sync › **Sync meeting
  recordings**, off by default: "A meeting is other people's voices. Off, the words sync and the audio stays on the
  device it was made on." A recording kept back on purpose is marked (`SyncState.files[id].stayed`), so switching the
  setting on sends it without the note having to change. The Sync section's footer counts what stayed: "3 recordings
  stayed on this phone" (`stayedHere`). Whether a meeting's audio should ever leave the phone stays his question.
- **The WAV is not re-read on every push.** `SyncState.files[id].forMs`: the file is read or hashed only when the
  tape's length has changed. On generation 20 the hash is `recording_digest(id)` (SHA-256 on the blocking pool; the
  page compares the first 32 hex characters, as it always hashed), the bytes read only for an upload, and a tape with
  no file is remembered as looked at, so a removed tape is not asked about on every push. iOS hashes nothing there,
  so it and a call that failed read the bytes as before rather than being taken for "no tape". Which notes are
  meetings is read when each recording is decided, not when the pass began, and the Mac lists a meeting before its
  tape is kept, so a pass under way never sends a meeting's audio.
- **A conflict does not lose the summary or copy the note.** When both sides changed a note and they differ only by
  the app's own section (`withoutSummary` alike), theirs is taken with the local section put back, no conflict copy.
- **Storage.** Settings › Recording › **Tapes** (Android and the Mac): "Your tapes take about 2.3 GB on this device."
  (`recordingMs * 32` summed over the tapes whose audio is here: not one this row removed, nor a synced one whose
  audio the `rec` scheme answers 404 for) and **Remove audio older than a month**, which asks twice, as emptying the trash does,
  and calls `recording_delete` for tapes older than thirty days (generation 20). The words and phrases stay; the
  device remembers which audio it removed (`glyph-audio-removed`), and such a tape says "The audio was removed."
- **Nothing leaves the phone.** Whisper and the model are on the device; the service and the worker open no network
  and never download; the notification's words are written on the phone. The recording notification and Android's
  microphone mark are the visible sign a meeting is being recorded; telling the room stays the person's.
- **The stores.** Play reviews every foreground service type an app declares: `docs/store/PLAY_STORE.md` lists the
  three this release declares and what to say about each (§113).
- Deleting a note deletes its file, sidecar and WAV as before, and its job files; Reset removes `jobs/` and cancels
  the chain.

### 7. Every line, in the app's voice (§21)

As shipped. No dashes, no semicolons, no ellipses; Summarize, Summarizing, Summarized.

- + sheet: "Meeting", "Record a meeting. The screen can go off. It is written up afterwards." Recorder card:
  "Meeting instead".
- Meeting screen: "Recording. The screen can go off and you can leave. Stop here or from the notification.", "Let
  Ghost.md tell you when it is written up." with Allow, "Muted by another app.", "Notifications are off for Ghost.md,
  so stop it here." Refused microphone: "Ghost.md needs the microphone to record a meeting." Could not start: "The
  meeting could not start." A binary without the service: "Meetings need the newest Ghost.md." Started while the
  last one's Stop is put away: "The last meeting is still stopping. Try again in a moment."
- Recording notification: "Recording · 12:40", Stop, Discard; "Muted by another app · 12:40". The question: "Still
  recording? · 2:00:00", Keep going, Stop. The write-up: "Listening to the recording, 40%", "Summarizing". Written up:
  "Written up: Meeting, 26 Sep 14:05" with the first sentence, or "The summary is in the note.", "The transcript is in
  the note.", "Nothing was heard in the recording."; public: "A recording was written up". No model: "Needs the
  language model to write up the meeting." Failed: "The meeting could not be written up."
- Captions: "Recording", "Listening again", "Writing up", "Summarizing", "Keep Ghost.md open", "Waiting to charge"
  with Write up now, "Needs a model" with Get a model, "The summary didn’t come" with Try again.
- Settings: Write up, "When charging or above half", "Straight away", "A meeting is written up when the phone is
  charging or above half. Straight away uses more of the battery."; "Tell me when a meeting is written up"; "Your
  tapes take about 2.3 GB on this device.", "Remove audio older than a month"; "Sync meeting recordings", "A meeting is
  other people's voices. Off, the words sync and the audio stays on the device it was made on.", "3 recordings stayed
  on this phone", "N notes not synced". Developer › Reset while recording, and an update's install: "Stop the meeting
  first."
- Mac meeting at Done: "Keep Ghost.md open while it is written up." Tape: "The audio was removed.", "This recording
  is not on this device."

"The summary is in the note." and "Nothing was heard in the recording." were written at the integration, for two ends
the notification had no line for, and "The last meeting is still stopping. Try again in a moment." at the review, for
a start the service now refuses. They are Matt's to change.

### 8. Slices, each shippable alone

1. **The shelf** and 2. **Summaries**: page code, over the air, generation 19, live from 1.8.0 (sections 1 and 2).
3. **Meetings on the Mac**: page code in the 1.9.0 bundle, gated by platform, not generation.
4. and 5. **Meeting recording on Android, and the write-up with the app closed**: one APK, 1.9.0, native generation
   20, `BUNDLE_REQUIRES` still 19. Every new call on the page is gated on `hasNativeGeneration(MEETING_GENERATION)`, so
   the same bundle over the air on a generation-19 APK shows no Meeting on Android and calls none of it. The native
   things that had waited for a release came with it: the recogniser's words (§133), both recording prompts read by
   name in `llm/tests.rs`, `ai_unload`, range serving by seek.
6. **Mac notifications**: not built.

### 9. Measured

Nothing below was measured on a device in this release: the Fold was not reachable while it was built. Every line
stays blank until one is.

- Slice 1: the shelf on the cover screen, the title line readable at 11rem: not measured on a device in this release.
- Slice 2: a ten-minute recording on the Fold, refine time and summary time on the 4B: not measured on a device in
  this release.
- Slice 3: a one-hour meeting on the Mac, refine and summary: not measured in this release.
- Slice 4: a one-hour meeting on the Fold, battery over the hour, whether `MIC` without gain control is enough across a
  table: not measured on a device in this release.
- Slice 5: the Fold's Android version; whether a `microphone` service may change to `mediaProcessing` after Stop
  (it may on the emulator, below), and how long it may run; whether WorkManager's `setForeground` is refused from the
  background; `isClientSilenced` firing when a call takes the microphone; the deep-link plugin's channel in an
  activity recreated in a live process (moot while the shell exits with its activity, section 3); what a Recents
  swipe does to a meeting on the Fold; an hour's battery; the write-up's minutes at half the cores with the app in
  front and at all of them with it closed; the heat; a meeting started within seconds of the last one's Stop (refused
  until the Stop is put away) and a write-up in hand letting go for a new meeting, both of which the review's fixes
  changed after the emulator runs below: not measured on a device in this release, nor on the emulator.

**Seen on the emulator, which is not the Fold** (attackfm: Android 16, API 36, arm64, four cores, 1.5 GB). Numbers
here say what happened there and nothing about a phone.

- The Kotlin build, 2026-09-27, on a staging debug build with no Rust door: `startMeeting` asked for the microphone
  and the retry ran from `onResume`; the service in front as `microphone` (types `0x80`), 4201 ongoing, silent,
  public, two actions; the WAV growing at 32 kB/s with the screen asleep under the wake lock, its header within ten
  seconds while recording and exact at close; `requestNotifications` asked and `notified` came; Discard listed the
  note in `discarded` until `forgetDiscarded`; a `kill -9` mid-meeting left a header ten seconds short, and the next
  launch handed it to the chain. WorkManager's foreground service took the merged types from a process in front.
- The 1.9.0 release APK, the same night, installed over 1.7.2 (the note data kept):
  - The + sheet had Meeting (generation 20), and `jobs/config.json` was written at launch with `qwen3.5-2b`, the
    model that emulator has.
  - A meeting started as `microphone`; Back left it recording; with the screen off it grew at 32,153 B/s and the
    header was 9.3 s behind. The notification's Stop ran `finish` and the service's own write-up with no refusal
    logged, and posted "Written up: Meeting, Sep 27 22:32" over "Nothing was heard in the recording." (the
    emulator's microphone gives silence, peak 8 of 32,767), private with its public version. Its tap opened the note
    with its `## Transcript` and its 2:20 tape. This is what found three seams: the shelf that did not show the
    meeting until the list was read again, the meeting screen's header with no gutters, and the Recents swipe.
  - A meeting ended by a Recents swipe, with 25 s of synthesised speech put into its file, was handed to the chain at
    the next launch: one span, base.en, the transcript word for word, the summary by the 2B, landed by the page with
    the model's title ("Launch date set to second week of March") and its to-do in To do, 14 s after the worker
    started, with the app in front.
  - The task removed while recording (`am stack remove`, the way out a Recents swipe takes, since the headless
    gesture did not register a second time): `onTaskRemoved` stopped the meeting, the service wrote it up and posted
    its notification, and the process exited ten seconds later, native threads printing "FORTIFY:
    pthread_mutex_lock called on a destroyed mutex" as it went, still "exited cleanly (0)".
  - The task removed during a write-up of 148 s of speech: the process exited, WorkManager ran the job again in a new
    process two minutes later, and the low-memory killer took that process twice while the 2B summarised (1.5 GB
    resident on a 1.5 GB emulator); listening was not repeated after its checkpoint. The third process finished it
    with no activity in it, fifteen minutes after the removal (two kills, WorkManager's backoff between them, and a
    model test on the same Mac at the end), and posted "Written up: Meeting, Sep 27 22:51" over the summary's
    sentence.
  - A meeting stopped from its notification with 148 s of speech written over the start of its file: the service
    went from `microphone` (`0x80`) to `mediaProcessing` (`0x2000`) at Stop and kept it until the write-up ended,
    and then stopped. With the app not in front the result waited in `jobs/` for the page, as it should.
  - The written-up notification tapped with the app swiped away (Android had restarted the process for the voice
    interaction service, with no activity): the app opened on the note, its summary and its transcript.
  - Everything above ran on the release APK before the whisper words moved (§133). The final APK was installed over
    it and launched; on the freshly booted emulator the WebView's first construction ran past Android's five-second
    input limit once (the trace is in Chromium's init), and the page's own language-model work then held all four
    cores with the 2B, so no meeting was driven on that build.

## 128. The phone at work: the review, full screen (2026-09-26)

Matt: "make the analyzing steps of the AI full screen high contrast SVG iconography with cool effects like a
piping hot phone CPU scrolling through the thoughts and transcriptions of the AI etc. review the layout and
images and steps on the real fold device".

After Done on a recording the note opens and the review runs in it (§114, ai/useNoteReview.ts), and until now
that was the strip under the header. Now a scene covers the screen while it runs (scene/AtWork.tsx): a phone
drawn in the two inks, its case in the faint third ink and the CPU die at its centre in full ink, the working
step's mark drawn large on its screen, the die's hatch warming and a column of stipple thinning up off the phone
while a model works, five rings of dots blooming out of the die and its pins lighting from the phone's real busy
figure and temperature (the engine's sample with every report, llm/hardware.rs), and behind the phone the
transcript's phrases, then the note's lines, then the model's thought and each thing it finds as it writes it,
scrolling through the phone with a slight heat shimmer (the second §119's filter at the words' own share, so
they read; stepped with each report rather than animated by SMIL, so the model keeps its cores). Six step lines
in the order things really happen (listening again, loading the model, reading the note, thinking it through,
writing what it found, done), a title in the strip's own words, four counters (Heat, CPU, Pace, Since Done), a
hidden live line for a screen reader, and two words: Stop, the strip's own control, and "Back to the note",
which drops to the strip. Back does the same, armed one commit after the note's own handler so the first swipe
takes the scene and not the note. The scene is a child of the note screen and never navigates: leaving the note
mid-review drops the findings, so nothing here does.

Decisions. Warmth is state and glow is measured: the hatch, the column and the shimmer say a model is working
(the speech model pegs four cores before any sample exists, and the Mac never gets one); the rings, the pins and
the readings come only from the phone, and a phone that hides its thermal zones (§29g) reads "No reading" and
lights by busy alone, over the engine's threads so full load reaches the outer ring. The list is drawn whole so
the steps can be seen coming; comparing is one frame, so it is the listen step's tick and detail; a listen with
nothing to compare against is skipped, not ticked. The careful model's words never stream, so the phrases
advance with its percent, a placement; reading walks the transcript again and then the note's lines. The
review's answer is JSON, so while it writes the pane shows each finding's "what" as the model's words, the open
one typing in, and never the JSON; what lands is what readFindings can place. Since Done is wall time from the
moment the scene opened, beside the run's own "in 1:12". The scene begins to leave the moment the run ends, so
the marks and the toast are seen arriving. Reduced motion keeps the state and drops the shimmer and the rises.
The shimmer wears only with Settings › Animations' smoke at the edges on, the switch that already means "SVG
turbulence costs frames here". No preference: every review shows it, one tap sends it behind. Typed runs from
the More sheet keep the strip. Not for a take said into an existing note (§123). On the Mac and on a binary
before generation 14 there are no readings: the die warms, the rings stay dark, Heat and CPU say "No reading".

For later. The scene is for one run. The summaries of §127 section 2 run long recordings in pieces; that branch
adds its opener, a grace after done before the scene leaves, and "part n of m". The `stage` prop is the shape the
better-words queue would hand it once refine.ts hears `capture://refine-progress`. The 'working' ghost
(docs/GHOSTS.md 9) stays unplaced: one picture a screen, and this screen's is the phone.

The bench. Settings › Developer › The phone at work plays it from a script (scene/scripted.ts) with a heat
reading, without one, and without any readings; the script is installed round startRun alone and cleared on
close, and the rows are off while the model is on a note. `?scene=heat|cold|none` in a browser does the same at
launch, and answers nothing under Tauri.

Tests: steps.test.ts, feed.test.ts, AtWork.test.tsx (first frame, opens, follows, a stage wins, leaves, stops,
back order, no timers left, still, the smoke switch, hidden), HotPhone.test.tsx, scripted.test.ts,
SceneBench.test.tsx, runs.test.ts (useAnyRunning), NoteScreen.test.tsx. Page code, over the air, generation 19.

Revised after the review of the built page (the same day), which measured the picture rather than reading it.
The current line is kept 72% down the pane, under the die's pins, not 60%: 60% was the die itself, and the head
line, the pen line and each finding as it was written were cut through by it on the cover screen; the lines
already read pass up behind the die and the mark, which hide them, and the one being read or written never is.
The thought is split at sentence ends only and left to wrap, with a sentence past thirty words cut at a clause
end: cutting every fourteen words, which the transcript keeps as a placement, left centred stubs ("and the",
"sentence.") that read as broken text, and Qwen's real thoughts run longer than the script's. The note's lines
scroll through as words, their Markdown marks off the front. The rings are drawn in the third ink like the case,
so over the words they read as heat off the die and not as speckle on the text; the die, its pins and the mark
keep the contrast. The streaming modes snap the pane rather than gliding it (a glide never caught the next line:
the pen line rode at 76 to 93% of the pane, in the mask's fade). The mask's solid band starts at 18%, under the
column of stipple. A step's mark sits on the first line of its words when the detail wraps. The settle dims the
words to the third ink with the die, and holds 900 ms rather than 400, so the six ticks and the cooled die can be
seen before the fade. On the inner screen the pane stays centred under the phone (only the side reads from the
left), and the title has two lines' room with its words at the foot, so the steps and the counters no longer
move half a line between "is thinking it through." and "is writing what it found."; a wide window that is short
(the cover screen turned landscape) scrolls the scene rather than clipping Stop and Back to the note off its
foot. While the document is hidden the scene does not leave: an end off screen is settled and left on return,
so the findings are still seen landing. The one leave that fires on nothing having happened (the eight-second
open grace) asks again as it fires, after one play in the browser pane left mid-run at eight seconds and was
never reproduced: the cleanup should have cleared it and no path to a survivor was found. The bench's body says
"Played. Play again to watch it once more." once the scene has left it. The feed is keyed on the run's words and
the prompt's progress, not the whole run, so a report that moves only the clock never splits the transcript
again. Shared rather than copied: `megabytes`, `heatShare` and `cpuShare` in core/ai.ts (the AI card's meters
use them too), `HEAT_NOISE` in editor/textEffects.ts (a retune of the editor's heat reaches the haze), and
`paceNumber` in ai/words.ts.

Known and left. The scene covers the tab bar (it is full screen): the ways out are Back to the note, the back
gesture and Escape, and the tab row is under it until then. A take that also wrote into an existing note through
a command, confirmed after Done, opens that note with both a landing and a review: the scene covers the landing
preview of the lines arriving for the review's length, and Back to the note reveals them landed. Nothing here
is wrong by the design, and neither is built round until Matt has seen the scene on the Fold.

Not done. Nothing measured on the Fold yet: the Pace tile with the scene up against sent behind, smoke on and
off, is the number that decides; if it fails, the shimmer stays behind the smoke switch as it is, then HAZE_HZ
comes down, then the rings' transitions. Whether the Fold shows a thermal zone is still unconfirmed. Play again
on the Fold after backgrounding the app during a play is the case that would reproduce the eight-second leave,
if anything does. Discard and Done are the recorder's and are gone before the scene starts.

## 129. Only what a recording can reach stays (2026-09-26)

Matt, told that voice tables had been unreachable since PR #1 (§126, question 2): "Cut it, let's refine things to
just keep what's active now".

So every voice and recorder feature the running app could no longer reach has gone, with every line that taught one.
Each was checked first: nothing on the page called it outside its own tests, and a recording, through the live reader
(§126) or the reader at Done, never got to it. A command said for one of them is read as it was before the cut: at
Done a table, a book, a chapter, a board or a move is still turned down and becomes an ask or the note's words.

**What went.**

- The table dialogue by voice: "Hey Ghost, add a table to X", the labels, the rows, "done", the preview and the yes.
  capture/table.ts, the table card and its preview, the take's tables and their clock, voice tests 063 to 065 and the
  simulated table scripts. `cellsOf` moves into command.ts, which still reads a table's shape so it can refuse it.
- The take's phrase-at-a-time reader: `phrase` and `tick`, the spoken yes and no, the twenty seconds a question was
  given, and `TAKE_TIMING`, whose two timings the live reader used are its own now (`LIVE_TIMING`). With it the
  phone's command model asked mid-take (`understandInstructionCommand`, `commandModel`) and the card's "say yes or no".
  Voice test 057, a spoken "no".
- What only that reader reached: a book or a chapter made by voice (`makeBook`), a board made or a card moved by voice
  (the `lane` and `card` plans, which need a board no caller passes), moving the take or starting a named note from a
  card (`routeTo`, `carryOn`), and the ghost of the words sliding away (Tail). Voice tests 070 and 071.
- The spoken voice memo, "voice memo … end memo" (capture/voiceMemo.ts), and the pause tip that offered it. Voice
  tests 072 and 073.
- Plugin voice commands and item targets: "send that to Notion", "new task for X in Notion", "add a note for the
  Notion task for …". plugins/notion/voice.ts and `findTasks`, the `voice` and `itemTargets` extension points and
  `CaptureContext`, the recorder's last-said and sent links (`applyLinks`), the plugin chip, a placement's plugin
  target, Notion's pause tip and its voice permission, and "say it" in its description. Voice test 068.

The confirm card after Done has two offers now, words into a note and a new list by name, and the take's offers are
typed as the plans the reader at Done carries out (`FinalPlan`). No review follows that card, so the take no longer
logs what it did for one (`describeOffer` and the take host's `log` went). A book the model names at Done is turned
down as the rules' is (`forBook`), so no path offers words for a book's index. The chip keeps the views the live
reader shows. The voice suite is 93 scripts, all run.

**What stayed.** The live reader, all of it, and "Hey Ghost, add call Sam to Doing" said on a board's own Speak, which
puts a card in Doing as it is said (liveRoute.ts into place.ts's lane placing, voice test 069). The reader at Done,
its card, and its refusals. Every dictation cue and the plugins' format cues; the tips, the Things to say card and its
asks. Typed and drawn tables, and Style › Table. Boards and books. Notion and GitHub: the swipe, the quiet word, Send
list, links and pills. Voice memos already in notes, drawn and played, with the tape id kept at Done.

**Taught true.** The Guide's chapters on memos, the marks, commands, boards, books, the better words, Notion, the one
page, formats, the plugin seam, the microphone, the command guards and the tests; the index's five things; and the
disagreements chapter, whose voice entries are all resolved. docs/BOARDS.md, BOOKS.md, MARKDOWN.md, PLUGINS.md,
VOICE_TESTS.md, instruction-voice-commands.md and docs/README.md. Settings › Plugins shows Notion's reach without
"Voice commands", and the Guide's Notion chapter says the same. The new list by name, which the reader at Done carries
out, is taught in the commands chapter and the lists chapter. The Things to say card teaches it with "with": items
said as a sentence of their own after the name are read as part of the name.
The historical sections of this file are left as they were.

**Kept for Matt to decide.** Not cut, because each is a choice rather than a dead branch:

1. command.ts still reads a table, a book, a chapter, a board, a move and a new note (`TABLE`, `MAKE_BOOK`,
   `MAKE_BOARD`, `forBook`, `chapterFor`), only so the reader at Done can turn them down; without them "add a table
   to Work" would offer to add "a table" to Work. Fold them into one refusal, as liveCommand.ts's `NOT_WORDS` is?
2. `matchLane` and `moveToLane` (core/boards/lanes.ts), the keyword's sound-alikes (`findSoundAlike`), the mid-take
   drafts in takeWriter.ts (`flushDraft`, `keepDraft`, `updateNote`, and with them `savedDraft`, always false now,
   `undoDraft`, which the recorder still calls and which does nothing, and the writer host's `markdown` and
   `hasWords`), `clipMarkdown`, and a refine job's `clips`, which a job queued by an older build may still carry: each
   is now unused or test-only. Keep or cut?
3. The plugin `tips` point and the `voice` permission kind stay, with no plugin using either.
4. `interpretWakeCommand` stays for the evaluation corpus, whose create cases the reader at Done would refuse. Move the
   corpus onto `classifyFinalTranscript` and accept that?
5. Adding to a lane by voice works but nothing teaches it. A tip on a board's own Speak?
6. "Hey Ghost, send that to Notion" is read as words for a note called Notion: with none the chip says so, and with a
   note titled like "Notion setup" the words go there. Guard the word?
7. Mid-take, "make a book called …" or "add a table to …" is queued as an ask for the AI. Leave it out instead?
8. After a routed command, "No." is written as an item. It was the old reader's answer.
9. The update changes the Guide in the app, not the copy anyone already added to their notes: `addGuideBook` answers
   a Guide that is there as it is. A copy added at 1.8.0-12 to -14 still says the Notion card lists voice commands
   and a pause offers "Voice memo … end memo". Accept that, or rewrite the chapters still exactly as a release shipped
   them?

**Native follow-ups.** Page code only, generation 19, over the air. Two things in Rust describe what went, for the
next native release: `CUE_VOCABULARY`'s `MORE_CUES` in src-tauri/src/whisper/text.rs still primes Whisper with
"Voice memo, end memo", and llm/tests.rs `understands_spoken_commands` measures `COMMAND_PROMPT`, table cases and
all, where it could measure `COMMAND_SYSTEM`, which `ai_infer_command` sends. `REVIEW_PROMPT` still says spoken cues
make tables, and that voice commands start with "Ghost.md", where the keyword is "Hey Ghost" or "Glyph". It is page
code, but changing it changes the review, and llm/tests.rs reads it by name, so both go with the next measurement.

**Tests.** The cut features' tests went with them. New: no tip offers a voice memo, `cellsOf` is held in
command.test.ts, and no plugin word comes off a note's name in route.test.ts. After the review of the cut: the reader
at Done turns a book down by the rules and by the model, and a board without asking the model; Create on the card
makes the list with its items and opens it; Add keeps "Parkersburg, West Virginia" one item; Done keeps a continued
tape's id and gives a removed one a new id; a phrase of words and then the keyword reaches the better words' job; a
plugin's formatting is laid out when said; the Things to say card's new list is read, with its items, by the reader
at Done; and voice test 102 says "New item for groceries" as the tip teaches it. Still with no test: the quiet stop
held open while a command waits for its note's name.

## 130. Scratch that: taking back what was just said (2026-09-27)

Matt: "Id like sentences to be able to redact." Asked what that means: redacting is what happens "when the user says
something like 'actually …' or 'scratch that, add it to the <note> instead'".

**The flow.** Say "The meeting is at three." then "Scratch that." and the sentence goes back into smoke; the chip says
Took back “The meeting is at three” with Undo for four seconds. Say "Actually, the meeting is at four." instead and
the first is replaced by the second; say "No wait, four." and only the word changes. Say "Scratch that, add it to
Groceries instead.", or "Scratch that." and then "Add it to Groceries.", and the sentence leaves this note and lands
in Groceries at Done, as a one-shot does; once the Undo goes, Groceries' lines show with Not this note. Undo makes it
as if the phrase had been plain words: the sentence comes back and the opener is written after it.

**What counts** (capture/takeBack.ts). Safe openers are an order, and need a pause after them: scratch that, strike
that, take that back, forget that, delete that, never mind, cancel that, ignore that, and no wait alone; "Take that
back to the shop" is words. Risky ones are how people talk: "actually", "I mean", "sorry,", "no," and "no wait" before
words count only before a correction, which is the sentence said again with a change (`corrects`: the words they
share, from both sides: two of them, or all of the previous, or one word changed in place, or the same words but for
one of a kind), a change of one word of a kind (`swapWord`: a number, a day, a month, a name), or a send of "it" or
"that"; after "Hey Ghost" a whole sentence counts, unless a command follows, which is then the command ("Hey Ghost,
actually, add a note to House TODOs"). So "Actually, I think we should go", "No wait, that's fine" and "Call Sam" |
"Actually, Sam is away" stay sentences. An opener stands at the start of a phrase, after a stop in any case, or after
a comma when only a drop, a send or a change follows: Whisper's "the meeting is at three, scratch that" reads. A send
says "it" or "that", never "this", which is the take's own word: "move this to X" still moves the recording.

**What is taken back.** The last thing the live reader placed in this take, by the phrase it came from: the last
sentence on the page, three items said in one breath, or the last phrase given to a note named. A second "scratch
that" takes the one before. A command with nothing said for it yet is what a safe take-back cancels; a risky one there
is the command's words. Words sealed by "New note" are out of reach. A phrase with words before the opener is read as
two, the head first, a phrase of its own, so "We need eggs. Scratch that." takes back the eggs and "Hey Ghost, add
call Sam to Work. Actually, call Sarah." corrects the item in Work.

**Where it leaves.** The page, through the wisp. The take, so Done never writes it. The tape's transcript, whose
phrases are the take's (the sound stays: the tape is never touched). The better words: the stretch is marked at
settle and the job always carries the live phrases once a take-back ran (`changedWords`), so a drop is replaced by
nothing and a replacement by itself (refineText.ts unchanged). The reader at Done reads the take's phrases filtered
by the same rule, never the raw transcript. Never `committed` or `heard`: the stop's last words and the review
compare like with like, and the log says what went. A take-back never engages the reader, so a command left for the
reader at Done is not reclaimed by it.

**Nothing lost silently.** Every take-back shows what went, with Undo, and quiet stop waits for it. The spans are
pushed only when it settles (five seconds on the reader's clock, a second after the chip goes; the next take-back;
New note; a switch; Done), since `commandSpans` cannot be undone. A send that finds no note keeps the words and says
so; one that is not sure asks on the card with the words on the page, and Keep here puts them back where they were,
a one-shot's into it. The take-back's own words never land anywhere. One settled at Done is named in the note's
toast and the review.

**Where this differs from the plan it was built from.** A send's card leaves the words on the page while it asks,
rather than taking them off: a note chosen takes them, as every card takes what was said since it, and Keep here
puts a one-shot's back into it. A send said in a breath of its own after "Scratch that." asks on that card when its
name is not sure, puts the words back and says so when it was said with the keyword and finds nothing, and is words
when said without it and finding nothing: "Put it in the oven" after a scratch is not a send that failed. `corrects`
also takes the same words but for one of a kind ("it's on Tuesday" | "it's on Thursday"), which the shared-words
rule alone refused. A replacement's chip says Replaced “…” with “…”, since the new sentence is on the page and Took
back would read as a refusal.

**Revised after the review of the built branch (the same day).** A safe opener's one-word rest that changes a word
("Scratch that, Sarah") is written once, not also as a phrase of its own. The keyword is the opener's only when it
stands right before it: before a command in the head ("Hey Ghost, add call Sam to Work. Actually, we should go for
a walk.") it was the command's, and the new sentence is words, as on main. "Hey Ghost, actually, add a note to House
TODOs" is that command, said as people say it: `command` takes a risky opener off a command's words when a command
follows (`commandAfterOpener`), and nothing is taken back; with nothing said before, a keyed "actually, …" is words
as heard, keyword kept, so the page and the better words agree. Whisper cutting a send's opener from its name
("Scratch that, add it to" | "Groceries instead.") is read as the one send: the opener waits for the name, never
written, and a phrase that is no name leaves the drop a plain drop. Anything placed after a bare drop ends its wait
for a send, so "add it to X" after another sentence never sends the dropped one; the keyword alone between them does
not. "Put that in the list" keeps its "the", so it means this note on a fresh take too, and lands the sentence as an
item. A one-word rest after a stop has its first letter put down, so "Scratch that. Tomorrow." swaps no name. A
tapped New note leaves the take past its start, as the spoken cue does (both gave a one-shot for a route said next
on main). Several plain phrases on one stretch, a head and a rest that stayed words, are each their own, so the next
scratch takes the last alone. A take-back in an open one-shot puts its count back, so an enumeration said next is
its items. Undo writes a keyworded phrase without its keyword and marks the stretch `keyword`, as `read` marks one,
so the better words leave "hey Ghost" out; a correction goes back beside the item it corrected, in its one-shot. The
chip quotes a phrase left for the reader at Done without its keyword. The partial: an opener after words in the
phrase goes to the chip and the words stay on the page, and so does a send while a drop waits for one. Shared
rather than copied: the resolved and current sends (`sendTaken`), a send's refusals (`sendRefused`), its card
(`askSend`), the hold dropped before a take-back (`dropHold`); `withoutWords` and the record agree on what one
phrase is (`same`); the number words are spoken/numbers.ts's. Left as the plan had it, and pinned: "The meeting is
at three" | "Actually, the meeting is important" is a correction (the frame is said again); "Bullet point: eggs" |
"Actually, eggs are in the fridge" too.

**Tests.** takeBack.test.ts (the grammar), liveRoute.test.ts "taking back what was just said" (the record's order
and its choke points, the spans at settle and at once, each outcome, Undo), CaptureScreen.test.tsx (the page, the
chip, Undo, the partial split at the opener, New note tapped, a one-shot emptied, the tape and the job at Done, the
reader at Done, a take-back only the stop heard), refineText.test.ts (a take-back's spans with live phrases, the
larger model's merged phrase, the Undo of a keyed one), chip and RouteChip tests, landing.test.ts, tips.test.ts,
liveCommand.test.ts ("instead"), voice tests 103 to 111, `?simulate=takeback`.

## 131. The redaction, back as the twelfth mark (2026-09-26)

Matt: "Id like sentences to be able to redact". Asked what that meant, he gave two things: the spoken take-back
while recording, which is §130, and "also add redact formatting", which is this.

**What it is.** `@@the gate code@@` is the Marks plugin's twelfth mark, Redact, between Unsure and Shout where it
sat before it was cut (ce0193d built it with the plugin; bc10ca2 took it out at 1.4.2-4, "remove redacted its the
same as spoiler"). A solid bar of the page's ink over the words, lifted while the caret is in them so they can be
read and edited (`clearAtCaret`, the FormatLook flag kept for it since the cut), and a look only: the words stay in
the note between their at signs, so the file a share or an export gives, and any other app, has them. The bar stays
wherever there is no caret to lift it: in the Formatted view, where the at signs go too, on the reader page, whose
editor is read-only, and on a note's card, as the spoiler's smoke does in both. (The copy first said a share shows the
words; the review read the reader page, where formatLooks lifts only while `editable && hasFocus`, and the four
places that said it say this now.) Said "redact … end redact", and heard as "redacted" too, since
Whisper writes the past tense as often as not. Style › Redact, the cheat sheet row and the Academy's lesson come from
the same entry; the Academy's lesson and the sample note's line are the two places with words of their own.

**The bar, measured.** A note with a redaction in a sentence, in a heading, in a quote, and around a link, code and
bold, on a light page and a dark one, in the marks view and the Formatted view, with the caret out and in. Three
things the old CSS did not do:

1. In a heading the old bar was the body's height, with the heading's letters showing above it. The look's span was
   outside the highlighter's: formatLooks comes before syntaxHighlighting in Editor.tsx, and the tree highlighter
   is `Prec.high`, so the `.h2` span sat inside a box sized by the line's font. formatLooks is `Prec.highest` now.
   CodeMirror nests the decorations of higher precedence inside, so every style look's span sits inside the
   highlighter's and takes the size of the words it is on: a redaction in a heading is a bar as tall as the
   heading, and a highlight in one is a wash as tall as the heading, which it was not before either.
2. Inside the highlighter's spans the bar is drawn in pieces, one per run the highlighter makes (a link's brackets,
   its words, the backticks, the stars), and rounded pieces left a notch of paper at every join. The bar is
   square-ended now, and the shadow's spread (0.08em) closes the hairline between pieces; measured, the pieces on
   one line share their top and their height (24px on an 18px line).
3. `-webkit-text-fill-color` as well as `color`. A link's or code's own colour is set on the span its words sit in,
   and the fill colour is what the glyphs take, so a link's words inside the bar are ink on ink. The editor theme's
   selection rule already sets the fill for the same reason.

**What the review of it found, and what changed.** Three ways the words showed, each closed:

1. A redaction inside another look was not drawn at all. `styledRanges` stopped its walk at every styled node, so
   `==a highlight with @@a bar@@ inside==` showed the words in the wash, in both views and both themes. The walk goes
   on now, and a look inside a look is drawn inside it, the inner span nested in the outer's (same range set, in
   document order, which is the order a `RangeSetBuilder` wants). One exception: nothing inside a bar is drawn, or a
   highlight in a bar would wash the ink and show the words through it (`@@a ==wash== in a bar@@` is a bar). Lifted,
   the bar shows what is under it as it is, a highlight's wash included.
2. An emoji painted through the bar: a colour emoji takes neither `color` nor the fill colour, so the Heat effect's
   own flames and any 🎉 sat on the ink in full colour. The span is printed flat in the ink by a filter,
   `--app-ink-flat: brightness(0) invert(var(--app-ink-level))` (ink.css): brightness takes every pixel to black,
   invert lifts black to a grey, and the level is the ink's own grey in sRGB, written beside each scale, 0.052 on
   paper and 0.954 on a dark page, the inverse surfaces' beside theirs, and the kit's under a named theme (0.182 for
   dawn, 0.915 for boreal and ember), the nearest grey to a tinted ink. The scale is grey throughout, so on it the
   flat bar is the ink to the rounding. stylesheets.test.ts works each level out from its scale's `--app-gray-12`,
   so a retuned ink fails a test rather than leaving the bar a shade off.
3. A link's short address showed between two pieces of bar: links.ts draws it as a widget, and a widget sits beside
   the mark's span, not in it, so `@@see [the plan](https://example.com)@@` was a bar, "example.com", a bar. The
   looks that hide their words are named in a facet now (formatLooks.ts `coveringLooks`, the `clearAtCaret` ones),
   and links.ts leaves an address under one whole, as text under the bar; the widget comes back when the bar goes,
   since the caret's line shows its links whole anyway.

A selection that touches the words lifts the bar as the caret does, so selecting redacted words shows them: the
mark's words being edited, not a leak. The home page's live previews draw the bar too, since they draw with the
note's own looks, and with no caret it stays.

**Taught.** The sample note's marks line and its EVERYTHING; the Guide's marks chapter (seven of its own, the row,
the at-work line, and "a look, not a lock"); the cues chapter's row; chapters 30 and 32's counts; docs/MARKDOWN.md and
docs/PLUGINS.md; the plugin's header, twelve. Every one of them says what the review found true: the file has the
words, the bar stays where there is no caret, and nothing under it shows, an emoji included.

**Tests.** marks.test.ts: back between `@@`, said "redact", after Unsure and before the effects; the bar is one token
for background, colour and fill, and lifts at the caret; drawn over the words alone with the at signs outside it;
kept in the Formatted view with the at signs hidden; gone while the caret is in the words and back when it leaves.
The lifting test that made up a lifting highlight uses the real mark again. The sample note holds a Redact; the
Academy's lesson passes a bar and refuses one at sign and an unclosed bar; "redacted Sam Ortiz end redact" writes
`@@Sam Ortiz@@` and "the file was redacted before it went out" stays words; the voice suite's line shape reads `@@`
(voiceSuite.test.ts: `@@` around the words is a different shape from none). The cheat sheet's table, its
said-to-the-recorder test and the Academy's one-lesson-per-row test cover the new row from the registry without a
line added, and guidebook.test.ts reads the registry too now: every mark of its own in chapter 04's table and its
at-work line and the count in its heading, every effect in chapter 05's table with its cue, every cue in chapter 10's
table, and the plugin's count in chapters 30 and 32; a mark added or cut is a chapter to change. From the review:
formatLooks.test.ts, a look inside a look and none under a bar until it lifts, and the facet's names; marks.test.ts,
a bar inside a highlight nested in the wash's span, a highlight inside a bar not drawn, the filter on the look, and a
link's address under a bar left whole beside one outside it shortened; links.test.ts the same under a made-up
covering look; stylesheets.test.ts, each scale's ink level as the sRGB grey of its own gray-12, and the kit's for the
three named themes. docs/MARKDOWN.md and docs/PLUGINS.md are pinned by nothing, as no file under docs/ is: no test
reads them, and this section says so rather than saying they are covered.

**Not done.** No voice suite script says it: the suite's audio is recorded off the phone (docs/VOICE_TESTS.md), so a
script would arrive unrecorded. Whisper is not primed with "redact": the cue vocabulary is Rust
(src-tauri/src/whisper/text.rs), a native release, and no plugin cue is in it today. An effect inside a bar is still
drawn: editor/textEffects.ts walks the tree on its own and reads no `coveringLooks`, so its motion goes on under the
ink; what of it shows through a flat-printed span is unmeasured.

## 132. Room to breathe: the home page as headed groups, a digest, and one family of marks (2026-09-27)

Matt: "The library and tapes headers on the home page are different sizes, id like you to redo the home dashboard
UI/UX to make it easier to digest everything with cards and quick actions and summaries and better labeling. Right
now it's just very data dense with no solid organization and use of white space"

Built on branch home/redesign against HEAD 3c30964 (1.8.0-18), in four slices and a browser pass, each committed
alone: the headings and their marks; the To do card; the tape card and the offer; the digest; the measurements. Then
a review's findings put right, below ("Put right after the review").

**The mismatch, at its cause.** Pin and Cassette on the headings were art/Icons.tsx `icon()` strokes, a 1em box
drawn at `font-size: 1.15em` of a 13.4px heading, so ~15.4px with a 1.5px stroke, and the cassette's reels (r 2.75
of 24) closed to dots at that size, which is why it read filled. Book was @glacier/icons' lucide proxy given only a
className: lucide writes width=24 height=24 stroke-width=2 attributes and ignores the em, so it drew 24px and thin
beside them. Recent and To do had no mark at all. Now every heading mark is Icons.tsx's line at 1em of the heading's
own size (19.4px at 412, 22.5 on the opened Fold, a ~2px stroke, the dock's weight): Pin (tilted, as §29g left it),
TickBox, Cassette with its reels redrawn at r 3 so they stay open, Book drawn in the app's line, Clock, and Grid on
the foot's All notes. The kit's Book and LayoutGrid left HomeScreen.tsx. The test that keeps it: every h2 svg on the
page is sized 1em and carries no width attribute (HomeScreen.test.tsx).

**The page, top to bottom.** The date as the page's one title (xl), a digest line under it, the pills and the
notices as they were; then Pinned, To do, Tapes, Library, Recent, and All notes at the foot. Pinned stays first
(Matt, §29g: "put pinned notes in a category above the rest of the notes in lists"); To do comes up from the foot to
second, since it is what is waiting and its tick is the page's one in-place action; Tapes keep §127's place above
the Library; Recent runs last into All notes, which is its own See all. Nothing is shown twice and dashboard.ts's
grouping rules are untouched. Constants: `RECENT = 4` (was 6), `TASKS = 5` (was 8), `TASKS_OPEN = 40`, `SHELF = 8`.

**One scale.** Head xl, headings lg semibold in sentence case with title tracking (the spaced capitals went from
this page: `.group`, `.app-eyebrow` and the shelf's `.meta` were three competing caps styles), card titles md on
every card (the grid's dense size, so home and All notes share one; NoteCard.module.css `.title`), lines sm and xs
in the third ink. A count after a heading is md regular tabular in the third ink: "To do · 14", the dot midway with
the heading's gap on either side of it (a margin of the count's own had it 12px from the word and a space from the
number, reading as the number's); Tapes counts only when there are more than the shelf holds. The mark sits in the
second ink so the word leads. The row's word ("See all", "Show all 14") ends before the dock's column wherever the
dock crosses the page: the page runs under the dock by design (§84, §97), and a card's corner may pass behind it, but
a word to tap must not, and at 412 "See all" sat wholly under the dock on the first screen. The dock reaches past the
gutter by its ring, two paddings and its inset less the gutter (55px at 412), and crosses the 60rem column until the
pane is wider than the column by twice that (~1115px), so the row keeps that reach at its end under a container
query on the pane (`.screen` is `home-pane`), at 70rem, not on the column: a 1440px window with the sidebar docked
is a 1060px pane, where the column is at its 60rem and the dock still crosses it by 22px.

**The digest.** One line under the date, only the phrases that are true, separated by middle dots: "5 to-dos open
· Working on 2 tapes · 3 notes touched today". A phrase that goes somewhere is a word, in the first ink at the quiet
button's weight so it reads apart from one that is only said (it inherited the line's ink at first, and nothing said
the digest was a row of quick actions), with a line under it for the mouse: "5 to-dos open" and "Working on 2 tapes"
glide to their groups, "1 tape needs a model" opens Settings › Formatting. "Nothing waiting on you" is said when none
of the waiting phrases are true, and so is "N notes touched today": it counts every kind of note the person touched,
pinned, tape and book alike (the Guide's pages and its book out: the day the manual is added it is the newest note of
all), and those notes are all over the page, so a glide to Recent, which holds four of one kind, landed on a group
that did not match its number. Pure and tested in dashboard.ts (`digest`, `touchedToday`, `startOfToday`,
`tapesWaiting`); no fetch, the queues' sets and the to-dos were already on the page. No full stops: a row of
fragments, like "All notes · 41". The dot is drawn after each phrase but the last (`li:not(:last-child)::after`),
not before each but the first: at 412px three phrases wrap, and a dot at the head of the second line read as a
bullet. The glide is `scrollIntoView` on the group's section, with `scroll-margin-block-start` of the safe top so
the heading lands under the glass bar, and `auto` behaviour under reduced motion. Its target is fixed when it starts,
so what is above the group has to hold its height while the page moves: a pinned card's peek lets its editor go as
the card leaves the scroller, and the blank that stands in is now held as a minimum height as well as a size
(notes/NotePeek.tsx), since the card's `flex: 1` on the peek, with its basis of 0%, let a set block-size fold to
nothing; before that the heading landed 69px behind the bar, one pinned card's peek short.

**Air, on the kit's scale.** space-8 between groups (space-10 in the 60rem column), space-3 from a heading row to
its cards, space-4 between cards on the home page (All notes keeps space-3 through its compose; the home page's
`.section .cards` rule is heavier and not composed), the To do rows without hairlines, the tape row's gap space-4,
the foot space-8 above. The date leaves space-2 for the digest, and the digest space-5, as the pills and notices do.
Rhythm around cards, never a band at the foot (§84, §97): the page still runs under the dock to the screen's
bottom, and the scroller's foot padding is still counted from the dock's four buttons.

**The To do card.** Five rows in one card (were eight hairlined rows), each the box, the words, and "{note} ·
{when touched}" under them; "Show all 14" in the heading row opens it in place to forty, then "and N more in your
notes"; "Show fewer" folds it, and so does choosing another workspace. Two columns from 44rem. All ticked, the card
holds the all-ticked ghost at its small size. The card takes one arrive beat after the pinned cards; the Library
and Recent count it in theirs.

**The tape card.** The shelf's cassette became a 13rem card on the note card's ground: the drawn cassette at the
card's inner width, a two-line title at md, the caption with three lines' room for the summary's prose line (§127's
caption order unchanged; the clamp is on the prose line alone, since a legacy `-webkit-box` makes block items of a
state's spinner and its word), the offer word, and the note card's foot "12:40 · 26 Sep" last, so a row of tapes
and a row of notes read as one kind of thing. The cards stretch to one height so their feet line up. "See all"
moved from the row's end to the heading, where a mouse can reach it, with "· N" beside the word, both only past
the shelf's eight. The offer, "Summarize" (the strip's own verb, kindWords('summarize').label), shows only on Tauri
for a tape of LONG_NOTE_MS or more with no summary and nothing queued (tapeCaption.ts `canOfferSummary`), and asks
the queue for the tape's real kind (dashboard.ts `summaryKindOf`: a meeting's for a note in the meetings map).

**Quick actions.** Tick in place; Show all; See all; the digest's phrases; Summarize, Get a model and Try again on
a tape; the dock, unchanged. Nothing on a card at rest (§29g). A per-card menu on hold or right-click was designed
and not built: nothing at rest would say it exists, and a long press inside a scroller is a gesture Android fights.
If Matt wants pin, archive and delete on the page, the discoverable form is an always-drawn "More for {title}"
word at the title's right opening a sheet with the palette's "This note" words; the palette has them today.

**Put right after the review** (the same day; a review of the slices, three lenses, nineteen findings). The
heading row's word out from under the dock (above); the glide's overshoot, at its cause in NotePeek's blank (above);
the count's dot centred; the digest's words told from its said phrases, and the day's count said rather than sent
to Recent; the Guide's book out of the day's count with its pages; the header comment in the page's order; the five
comments that still sent "and N more" to the grid; the two To do sections folded into one, so ticking the last to-do
swaps the card's body for the ghost without a second arrive; the shots script scrolling the page's scroller rather
than the docked sidebar's, so the wide pages' lower halves were looked at. Tests for what no test could fail:
Summarize asks the queue for 'meeting' for a note in the meetings map and 'recording' for a plain capture, and is not
offered off Tauri (`enqueueSummary` a `vi.fn()`, `isTauri` a switch); the To do card folds and the digest counts
afresh when a workspace is chosen; five to-dos have no Show all and six do; "and N more in your notes" only once
opened; "Working on 1 tape" glides to Tapes; the foot's mark is the 1em line with no width and no inline font-size,
and every heading's mark wears `groupMark`.

**Measured** (Chromium 2×, Playwright from the npx cache against `vite preview` of the branch's build, the §132
seed of twelve notes with three tapes; light and dark identical to the pixel; the Fold itself not yet):
- 412 × 915: date at y 93, 33px tall at 23.4px; the digest one line (two with three phrases); Pinned heading at
  y 178; pinned card 197px; To do card (five two-line rows) 283px at y 501–784, so the fold lands after the fifth
  row and the whole card is on the first screen; tape card 208 × 270px, the row 284px (was 196); one card whole
  and 164px of the next showing; first screen holds: the date, the digest, Pinned and its card, To do with all
  five rows, and the Tapes heading (y 819) with the row's top edge.
- 375 × 812: the same column 331 wide; pinned card 196px, To do card 282px (y 498–780); 127px of the second tape
  card showing; the Tapes heading lands at y 815, three pixels under the fold, so the first screen holds the head,
  Pinned and To do.
- 768 × 1024 (sidebar docked; the list column is 300px, not the 380 the design guessed, so the pane is 468 and the
  column 420): 2 card columns of 200px; To do rows in one column (card 293px); tape cards 276px, two whole, none
  peeking with three tapes.
- 1280 × 900 (sidebar docked, pane 900, column 847): 4 card columns of 196px; To do rows in two columns (card
  196px); tape cards 283px, three whole; the first screen holds the head, Pinned and To do (y 601–855).
- 1812 × 1000 (sidebar docked, pane 1432, the 60rem column at 960 with 236px each side): 4 card columns of 224px;
  To do in two columns (card 201px); tape cards 287px, the seed's three whole (a fourth would be whole too, a
  fifth would peek); first screen holds: the head, Pinned (card 294px), To do, and the Tapes heading (y 939) with
  the row's top. Without the sidebar the same column sits at x 426.
- The five marks at 412: each 19.4px square (the pin's tilted box 23.1); the stroke 1.9px; the cassette's holes
  2.9px across, and 0.65px between the two reels' strokes at the middle, which reads as two rings and not one.
- The other passes at 412: a "Work" workspace chosen shows the pills under the digest and filters it ("2 to-dos
  open · 1 note touched today", To do · 2 with no Show all); `design` pending in the queue reads "7 to-dos open ·
  Working on 1 tape · 5 notes touched today" and the card's caption "Summarizing. Keep Ghost.md open." with its
  spinner; the Academy card sits between the digest and Pinned.
- After the review, in the browser pane (thirteen tapes and fifteen to-dos, so both words are on the page): at 412
  the row keeps 66px at its end and "See all" spans x 267-323 against a dock at x 335-394 (it spanned 334-390, under
  it); at 1280 with the sidebar docked (pane 900) the row keeps 78px and "Show all 15" ends at x 1176 against a dock
  at 1189; at 1812 docked (pane 1432, past 70rem) the row keeps nothing and both words end on the column's edge at
  x 1576, the dock at 1718. The count's dot at 412: 9px from "do" and 9px from "7" (was 12 and 4). A tap on "7 to-dos
  open" at 412: the To do section lands at y 70 under the 53px bar, its scroll margin 71, the heading at y 75; the
  pinned card that scrolled past is still 196.5px with its peek held at 69px (it landed at y 1 with the card at 128px).
  In the dark the word is the paper ink, the said phrase 0.8 and the dot 0.6, as the tokens say. Recent at rest,
  below the fold, measures 646px at 412 with its four cards' blanks held (490 with them folded to 0px), so the cards
  fill in without the page under them moving.

**Tests.** HomeScreen.test.tsx: the order Pinned, To do, Tapes, Library, Recent; every heading's mark 1em with no
width attribute; four Recent cards from six; five to-dos, Show all 8 → eight and Show fewer → five, Show all 45 →
forty and "and 5 more in your notes", no Show all under five; "Shop · Just now" on a row; eight tapes with "· 11"
and See all → `onAllNotes({ tapes: true })`, and neither at eight; the digest's phrases and the quiet one, nothing
while loading or on an empty page; a phrase glides to its section and the model phrase opens Settings.
TapeShelf.test.tsx: the foot outside the button; Summarize for a 200 s idle tape on `canSummarize`, not for 40 s,
not off Tauri, not once summarised nor in any queue state; `canOfferSummary` in each state. dashboard.test.ts:
`summaryKindOf`, `startOfToday`, `touchedToday` (midnight counts, a millisecond before does not, the archive and the
Guide's pages never), `tapesWaiting` (once per note, working before needing a model before failed), `digest`
(order, singular and plural, the quiet phrase). App.test.tsx: the path to the grid via See all. stylesheets.test.ts
runs as is: every read a declared token, leading tokens only as line-height or in a calc, no composer overriding.

**Left undone.** The Fold's own measurements; §127 section 9 still "To come"; a per-card menu (above); sublines
under headings ("1 hr 41 min in all."), kind labels on cards and a to-do count in a card's foot, all considered and
left out as the density Matt asked to remove; a Pinned cap (All notes has no Pinned toggle to land on); Recent at
eight on a wide screen (eight editors for two rows); a fifth tape card peeking on the opened Fold was not seen,
since the seed has three tapes. The review's two that stay: the tape cards at a fixed 13rem do not sit on the
grid's columns on a wide screen (at 1812 the second tape's edge is ~20px left of the second grid column, the Recent
cards 224 wide against the tapes' 208), since the grid's auto-fill column count is not a number a sideways row can
read from CSS without a formula that repeats the grid's rule, and a formula in two places is where they part; and
the card ground written out three times (the note card's `.card`, the tape's `.tape`, the To do card's `.todo`, with
`@keyframes arrive` in three sheets), which a global `.app-card` beside `.app-word` would fold into one, a change to
NoteCard's sheet beyond this page. The `.todo` comment says why it alone has no hover wash: nothing on it opens as a
whole.

Cites: §21, §26, §29g, §29i, §31, "The card is the note, small" and "A home page, and the notes list gone"
(2026-09-18), §64/§67, §71, §72, §84/§97, §92/§110, §94, §115, §118, §121, §124, §125, §127.

## 133. What waited for a native release: the words said to the app, heard (2026-09-27)

The native half of what earlier sections left for "the next APK", shipped with meetings in 1.9.0 (generation 20,
§127). Nothing in it has run on the Fold.

**The recogniser is told the words said to the app** (`src-tauri/src/whisper/text.rs`). A prompt primes whisper with
the spelling of what it is likely to hear; what a person says to Ghost.md itself was missing from it.
- `MORE_CUES` gains "Redact, end redact." (§131's mark, whose "Not done" said whisper was not primed with it).
- `SPOKEN_CUES`, new: "Hey Ghost.", the keyword since §73, "Ghost." on its own, and the take-backs
  `capture/takeBack.ts` reads (§130): "Scratch that. Strike that. Take that back. Forget that. Delete that. Never
  mind. Cancel that. Ignore that. No wait." It follows `MORE_CUES`, only after a finished sentence, as `MORE_CUES`
  does. `without_prompt_echo` does not count these: "Hey Ghost. Scratch that. Never mind." is three in a row said on
  purpose, where three cues from the other lists in a row is whisper reciting its prompt. Tested: three spoken cues
  in a row are kept, and no prompt has a double space.
- **"Hey Ghost." is not in `CUE_VOCABULARY`,** which the build first put it in, after "Glyph.", with the count its
  test holds moved to 14. The whisper tests that need the models, which no builder's tree had, were run at the
  integration with `models/` in place, and `a_prompt_tail_carries_a_sentence_across_the_cut` failed: base.en heard
  "Fresh bread on the way home." where a phrase carried across a cut must go on as "fresh", the capital
  `CUE_VOCABULARY`'s own comment says any word past the short line brings. Out of the line it passes, the count is
  13 again, and the keyword is primed where it is said, after a sentence. Whether the new words make the keyword
  and the take-backs heard more often is not measured: the ignored twelve-voice comparison (`tests::cue_vocabulary`)
  was not run.
- The same run found `a_timed_pass_over_part_of_a_recording_keeps_its_phrases_in_order_and_in_range` reading 298 for
  whisper's last progress report. whisper.cpp reports `100 * (seek - start) / (end - start)` before each window, and
  a window whose last token is not a timestamp moves `seek` on by the whole 30 s, so a slice shorter than a window
  can read up to 300; any word added to the prompt can decide that last token, and "Redact, end redact." alone did,
  on this fixture. The phrases and their times were right. The test now holds the report to 100 to 300, and the
  better words' progress event, which the page shows, is clamped to 100.
- The riskier openers the page also takes ("actually", "I mean", "sorry", "or rather", "no") are ordinary words and
  are not made more likely.
- `prompt_plain(committed, tail)`, new: the tail alone, with no vocabulary. A meeting's write-up prompts each span
  this way, because an hour of cross-talk primed with "Title. Heading. Scratch that." would hear cues nobody said.

**`llm/tests.rs` reads the recording prompts by name**, as it reads the others: `RECORDING_SUMMARY_PROMPT` over a
meeting with two other speakers (only the recorder's own actions boxed, Priya's and Tom's never), and
`RECORDING_NOTES_PROMPT` (items only). Both need the 4B and skip without it; at the integration they ran with it on
the Mac and passed, in four minutes. Beside them, with no model, the write-up's compiled-in prompts are held equal to
the page's literals, `PIECE_CONTEXT` and `NOTES_CONTEXT` included.

**`ai_unload`** and **range serving by seek** are §127's (sections 4 and 3).

**Still open from §129's native follow-ups:** `MORE_CUES` still primes "Voice memo, end memo", and
`understands_spoken_commands` still measures `COMMAND_PROMPT` where `ai_infer_command` sends `COMMAND_SYSTEM`. Both
change what a measurement means, so they go with the next measurement on the Fold rather than with this release.

Cites: §73, §127, §129, §130, §131.

## 134. Where a note was written: the tag and the map card (2026-09-27)

Matt: "Add the ability to geotag notes and show a map card embedded on the note". Then, while it was being built:
"Add a setting to geotag notes by default and turn it on".

Built on branch notes/geotag against HEAD 891f3cd (1.8.0-20), in slices committed alone: the tag in the front matter
and the device half; the card, the note and its sheet; the folded front matter; Settings › Location; new notes tagged;
the share, the reader, the MCP, the gist and the card's foot; a second look and a browser pass, each put right in its
own commit; the native half; the docs; and what the branch's review found, put right in one more. §133 is left for
the meetings branch, which may take it.

**The tag is words.** A note that knows where it was written says so in its own front matter, `location:
51.5074,-0.1278` and, once known, `place: "Trafalgar Square, London"`: two flat keys beside `title:`, `book:` and
`authors:`, read and written by core/frontMatter.ts as they are, so the tag syncs like typing, is in the note's file,
and shows in Obsidian's Properties. Four decimals at most (about 11 m); a rough fix (accuracy past 1000 m, Android's
Approximate) is written with two, and read back as rough: a district's zoom (11), a ring rather than a pin, "Roughly" before the
numbers. Reading is tolerant (spaces, quotes, brackets) and never rewrites; anything that is not two numbers in range
is no tag, left as typed. The peek, the title, the gist (hashed and judged on the words after the front matter, so a
tag never becomes a card's line nor regenerates one), the review's prompt and the AI's runs never see it as words.
core/geotag.ts is the pure half, which the MCP server bundles to carry a tag across `update_note` as it carries the
authors; core/location.ts is the device half; core/placeLink.ts is where a tapped map goes, apart from both so a shared
page loads neither.

**Tagged by default, as Matt asked, and only what the person makes.** "Tag new notes with my location" is on by
default (Settings › Location) and kept on the device, as Local only is: it makes the device ask where it is, a network
lookup, and a switch turned on elsewhere must not make a browser tab here raise a location prompt at its next new note.
Map and Place names, which describe the person as Link previews do, sync. It covers a typed new
note (App.tsx `newNote`, the + sheet's Note and New note) and a recording's own new note (shell/useCaptureRoute.ts
`finished`), and nothing the app makes: not the Guide's chapters, the samples, the example board and canvas, a canvas
or a book from the + sheet, a note made for a title, a shared link's copy, a note that arrives by sync, and not the
notes a recording's spoken commands made (`landing.made`: a list by name, "New note" and its card), since Matt listed
"notes created by a spoken command" among the app's. Existing notes are never tagged. The position is asked once. On a
device that has never answered the prompt, the first new note says what it is for in the app's words, a toast "New
notes can keep where they were written." with "Allow location", and the system's dialog comes from that press, never
over a blank note unannounced; let pass, it is not offered again until the next launch. Refused (or blocked on
Android), the switch stays on, the refusal is
kept (`glyph-geotag-refused`), no new note asks again, and the More sheet of every note made since says why ("Ghost.md
wasn't allowed to know where you are, so this note wasn't tagged. Tap to ask again." on Android, which asks again after
a first refusal; in a browser, which does not, "Allow location for this site in the browser's settings, then tap to
try again."), never on a note from before.
Allowing location in the phone's settings forgets the refusal (Android's bridge reads granted, or the browser's
permissions API does), as does a fix from the sheet or Settings. A quiet ask over a locked phone that would have
needed the prompt is not a refusal.

**The rule the recorder taught.** Better words land only if the note still reads as Done saved it (capture/refine.ts
`apply`), on the queue path and, one step later, on the review path, which hands its job back when it ends
(`REVIEW_HANDED_BACK`, ai/useNoteReview.ts). So a tag for a new recording waits (`setPendingTag`): written at once
where no pass and no review is coming; once the pass has landed or the review has handed back, written by the note's
screen when it is open, and otherwise by core/location.ts `settleWaitingTags`, which runs when a pass finishes
(shell/useHousekeeping.ts), two seconds after a note's screen is left, and at launch, so the tag reaches the note, its
card, sync and the other devices without the note being opened again (Matt's Fold, with Better words on, holds every
open note's pass until it is left, so this is the usual path). It is drawn on the card from the waiting record
meanwhile. A waiting tag lives a day, and its day starts again each time it is found still waiting for a queued pass.
A typed note's tag waits for its first words, so a note opened and left still leaves nothing behind: its card is the
quiet one (no tiles), its name is not asked, and a draft left without a word takes its waiting tag with it. A fix
that comes after its note was left is kept for it and written the same way. The waiting tag goes with the note to the trash,
with a delete for good and with the recording's Undo, which also takes a tag out of a note it leaves with nothing
else. The recorder's tag is asked from an effect on the screen once it has changed from the capture screen: the
note's screen has mounted and watches its tag by then (a parent's effects run after its children's), so the tag goes
through its editor rather than under it, where a write would leave the editor's saving a revision behind. Never at
`start`: the generated chrome client has one permission listener for the microphone and the location. Nothing in
capture/ changed. When the meetings branch has merged, refine's compare can learn to look past the page's front
matter, and the wait can go.

**Nothing leaves the phone unless chosen, and Local only turns all of it off.** A fix is a network lookup on Android
and the web (the fused provider sends nearby Wi-Fi and cell identifiers to Google; browsers to theirs), so Local only
turns off the fix itself, not only the tiles and the name. The tiles and the name are each a switch. The name is asked
of Nominatim once, at three decimals (two for a rough tag), only for a tag this device made and only once the tag is in
the note (never for a note that arrived by sync, a forked share or one the MCP wrote, nor for a draft that may never be
kept), one request a second across the app and one per place at a time, the switches read again after its wait (Local
only turned on meanwhile sends nothing, and counts nothing as failed), from Rust in the app
(src-tauri/src/geocode.rs, generation 20) since its policy asks for a User-Agent naming the application and a page
cannot set one; on the web the page's own origin names it. A share leaves `location:` and `place:` out of every page
unless that note's "Share where it was written" is ticked on its sheet (`shares[id].place`), since a share follows
every save and a location added to a note shared last week would otherwise reach everyone holding its link.
Removing a tag, for a share as for Remove location, takes out every `location:` and `place:` line, a second one typed
by hand or two devices adding one at once included. The rule is the sealing page's, and every signed-in device
follows every share, so a device on a page from before it (the Mac until relaunched, a browser tab opened before the
deploy, a binary too old for the update) would re-seal a tagged share whole: the stripping pages go out, and every
device is reloaded, before a shared note is tagged (docs/SHARING.md; a format gate on the share service is the lasting
answer, not built). The
reader page shows a tagged page's map only on a tap ("Show the map"), never asks for a name, and loads the card itself
only for a tagged page.

**The card.** At the top of the note with the byline, over the first line, the width of the column up to 32rem (a
link card's width, so on the Mac it is a card in the note and not a banner over it, the place's chip and the pin one
glance apart), 6rem tall on a phone and 8rem from 600px (the opened Fold, the Mac), never shrunk by the scrolling page's
flex column on a note longer than the screen: OpenStreetMap's standard tiles through Leaflet, greyscale under a
45% wash of the page's paper-2 so the map sits back and the pin is the only full-ink mark, inverted on a dark page from
the app's own theme rather than the OS's, and following the phone's own dark mode while the note is open on System
(`useDarkNow`). The pin is the card's own drawing over the wash, one drawing on both layers in one place: on the quiet
card in the second ink, over the map in the first, so the map arriving only deepens it. Its tip sits 10px below the
middle of the box, the map's box running 20px past the card's foot so Leaflet centres the tag there, which clears the
pin's head of the place's chip above it at phone width and its tip of the chips at the foot (Leaflet's marker pane
sits inside its map pane, under the wash, which drew the pin as grey as the streets). A rough tag's ring sits in the
middle and is as wide as the cell its two decimals round to (the half diagonal), since a fixed ring read as a precise
spot; drawn at zoom 11 rather than the 12 the name is asked at, since at 12 the true ring (28px in London) crowded both
chips, and at 11 it is 14px in London, 10 at the equator, held between 10 and 18. The place or the coordinates in a chip at the top left, "©
OpenStreetMap contributors" at the bottom right only where OSM's tiles or name are shown, why the card is quiet at the
bottom left. Loading, offline and every tile refused are one state, the quiet card under the map: paper, a dot grid,
the pin (a ring for a rough tag); the map fades in once a tile has come. It follows the Fold opening (a
ResizeObserver), takes none of Leaflet's colours, arrives on the kit's beat when added to an open note and leaves on it
when removed, so the words move once and smoothly either way, is isolated so
Leaflet's z-indexes never cross the header it scrolls under, and is not drawn over the transcript, a canvas or a
book's index, where the page does not scroll with the words. A tap opens the phone's maps chooser (`geo:`, the
opener's scope widened), Apple Maps on the Mac, openstreetmap.org elsewhere, with the place or the coordinates and
never the title. Leaflet arrives only when a map is drawn, as its own chunk, and a test reads the sources for the one
way in (MapCard.test.tsx, "Leaflet's weight"). The tiles carry the page's origin as their Referer, which the tile
policy asks of a web page; the shared page's no-referrer rule would otherwise strip it. On the shared page "Show the
map" is drawn as the kit's small button is, with a map's mark, since it is the one thing there to press.

**The front matter folds, which is Matt's to keep or take back.** Goal 2 says nothing is ever hidden, replaced or
folded, and it breaks ties second; §95 left the visible `authors:` line as a "Not yet". A tagged note doubles the lines
above its words, and with tagging on by default every new note is tagged, so the block is drawn as one quiet line
naming its keys ("location · place") while the caret is out of it or the editor is not focused. The caret entering it,
or a tap on the line, opens it to the lines exactly as they are. The review of this branch named the conflict, and it
is left to Matt: the fold is kept here because the spec asked for it and four lines of front matter over every new
note cost more than a line, and taking it back is `frontFold` out of editor/extended.ts, with its rule in
markdown.module.css and its tests. It folds only where the words can be edited: the shared page's read-only editor
shows the lines as they are, as it did before, so a stranger is not shown key names with nothing to open them. The
line's band keeps to the gutter as the card does, and it belongs with the card above it: the card has no bottom
margin, and the heading under the line keeps 16px above it rather than none.

**Platforms, as found.** Android: the generated chrome client already raises the prompt on the page's first
`getCurrentPosition` and grants silently once the app holds the permission; what was missing was the manifest, since
Android denies an undeclared permission with no dialog. location/LocationAccess.kt says "blocked" (denied twice, or
off for the app), which the page turns into "Open settings", and asks ahead of any fix through the activity's own
request code 4105 (4101 update alerts, 4102 a picked picture, 4103 and 4104 the meetings' notifications and
microphone), never through the chrome client's one shared launcher. That client lets a position through silently
only when both FINE and COARSE are held, and otherwise launches its shared launcher: after an "Approximate" answer it
would raise Android's "change to precise?" dialog on every launch, over a locked phone too. So once either permission
is held, the helper tells the WebView the page's origin may have a position (`GeolocationPermissions.allow` for
`http://tauri.localhost`, where the OTA page runs too), and takes it back when neither is; the client's prompt is
never reached. "Blocked" is decided from the prompt's answer (a denial after which Android will not ask again), not
from "asked before", so a dialog dismissed without an answer, or a lapsed "Only this time", stays "ask". Open settings
starts its activity on the main thread with the bridge thread waiting, as openAssistantSettings does. The Mac's WebView never answers a position
request (wry has no geolocation delegate, macOS no default provider), so the Mac is told `mac` before anything is
asked, draws what the phone tagged, and its Info.plist carries the location strings for the day CoreLocation is
wired. The web asks the browser. NATIVE_GENERATION is 20 (the meetings branch makes it 20 too; the entries merge);
BUNDLE_REQUIRES stays 19, each native call gated (the bridge's `locationAccess` on Android, generation 20 for the name).

**Copy.** The sheet's row, last in Where it sits, with the locate mark: "Add my location" / "Where you are now, kept in
the note. Its name is asked of OpenStreetMap once." (the second sentence only with place names on); "Remove location" /
the place or the coordinates; and, where it cannot: "Local only is on. A location fix would ask the phone's location
service.", "This Mac can't say where it is yet. Tag it on the phone and it syncs here.", "Update Ghost.md to tag notes
with where they were written.", "This browser can't say where you are." Toasts on a failed fix: "Ghost.md wasn't
allowed to know where you are.", "Location is off for Ghost.md." with Open settings, "Couldn't find where you are. Try
again with location on, or outside." No toast for a tag added or removed: the card arriving or going is the feedback;
"Finding where you are." only after 600 ms. Settings › Location: "Map on a tagged note", "Place names", "Tag new notes
with my location" ("Every note you make here starts with where you were, typed or spoken. Off, you add a location by
hand from More on a note. This switch stays on this device."), a footnote after a refusal ending "Allow location for
Ghost.md in the phone's settings and they will be." on Android and "Allow location for this site in the browser's
settings and they will be." in a browser, and under Local only "A tagged note shows where it was written and a pin
while Local only is on, and no new location is taken." (a named tag keeps its name). The first ask's toast: "New notes
can keep where they were written.", with "Allow location". The card: "Local only is on.", "Map off in Settings.",
"Show the map". The share row: "Share where it was written". A card's foot: "3 min ago · Trafalgar Square", the name
only, never coordinates, and only from the note's own words.

**Measured** (the web build, Chromium, 412 × 915 at 2.6 dpr unless said, the note's tab strip showing). The H1's top,
as the builder first measured it: 134px on an untagged note, 280 on a tagged one (the card 120 to 216, the folded line
252 to 280), so a tag cost 146px at 412; at 840 the card is 128 tall and the H1 at 326; at 1280, 340. After the review
(the H1's text, not its line, so the room kept above it counts): 129 untagged, 289 tagged at 412 (the card 120 to 216,
the folded line 239 to 267, 23px under the card and 22 over the heading's words, which keeps it the card's), 336 at
840, 350 at 1280; the card 96 tall on a note of 35 lines where it had been 2; 512px wide at 840 and 1280 where it had
run 1227; the pin's head 1px under the place's chip at 412 where they had crossed by 4, even for "Place du Carrousel
et Jardin des Tuileries, Paris"; the quiet pin and the map's at the same 28 × 28 box; under System, the tiles' filter
turning from the light one to the dark one with the phone, the note left open. The reader fetched no tile before "Show
the map", and its tiles then carried the page's origin as Referer. Tiles: 6 in a 6rem card at 412, 8 in an 8rem
card at 840, 12 at 1280. Filters chosen side by side against the page: light `grayscale(1) contrast(0.92)
brightness(1.04)`, dark `grayscale(1) invert(1) brightness(1.1)` (0.8 sank the streets into the paper, 1.4 made the
blocks compete with the chip's words), the wash paper-2 at 0.45 in both. Standard tiles, not retina: at 2.6 dpr the z+1
tiles at half size were sharper but twice as busy. Leaflet's own seam fix (`mix-blend-mode: plus-lighter`) opened a
device pixel of paper at every tile edge inside the filtered pane; tiles drawn normally and 256.5px wide close it,
seen at 2 and 2.6 dpr in both themes. Local only: the tagged note opened with no request to openstreetmap.org. One
Nominatim request for a new note, `lat=51.508&lon=-0.128&zoom=15`, answered "Trafalgar Square, City of Westminster".
Bundle, against main at 891f3cd: `index-<hash>.js` 2062.56 → 2074.27 kB (gzip 531.26 → 536.07), the chunk the app
shares with the reader (BookView) 1115.01 → 1119.17 kB, `read-*.js` 5.75 → 6.34 kB; new, the card's chunk 6.86 kB
(+3.16 kB CSS) and Leaflet's 149.91 kB (gzip 43.42) with 15.61 kB of CSS, loaded only for a drawn map.

**Tests.** After the review: a caret at the top kept with the words when a tag is written above them; a fix that
comes after the note was left, kept and written; Add held while a pass is queued or a review is live (the review held
open until it hands back); a draft's tag quiet and unnamed until its words, and gone with it when left blank; a name
from while the note was closed written on open, and only onto its own tag; the quiet card under Local only and no card
over the transcript; a closed note's waiting tag written once its pass has gone, kept past a day while queued, dropped
for a note that is gone, and written two seconds after its screen is left; one Nominatim ask for two notes at one
place, none if Local only comes on during the wait; a closed note named only while its tag is the one asked about and
no pass is queued; the minute's cap on a fix; Android's prompt answered with neither permission read as refused; the
first ask introduced once a run (location, the capture route and App); a share sealed and sent without the tag, with
it once ticked, without it again once unticked, and a tag added after the share went left out (share/refresh.test.ts,
through `shareNote`, `refreshShares` and `shareWithPlace`); every `location:` line out; delete for good dropping the
waiting tag; tagging new notes kept on the device; the reader's read-only editor not folding; the capture route asking
only once the note's own screen is up (a probe screen that watches only once mounted, which fails if the ask moves
into `finished`); and Leaflet imported by value nowhere and lazily only by the card, the reader reaching the card only
lazily (sources read, since the build is the only other witness). The NoteScreen tests of where a note was written run
each an hour apart on a faked clock, so an earlier test's Nominatim wait can never hold a later one's name. Before:
core/geotag.test.ts (the round trip, the precision, the tolerant read, `shortPlace`), core/location.test.ts
(the fix and its failures, the gates, the name asked once a second apart at three decimals, the waiting tag, refusals
kept, forgotten, and never a quiet ask), editor/MapCard.test.tsx, editor/NoteScreen.test.tsx (the card where it is and
is not drawn; Add and Remove as one undo step; the waiting tag on the queue and review paths; a new note's tag drawn
at once, named while it waits, landed with the first words, never over a tag the note has; the sheet's refusal line),
editor/NoteSettings.test.tsx, editor/extended.test.ts (the fold), editor/useLanding.test.tsx,
settings/LocationPane.test.tsx, shell/useCaptureRoute.test.tsx (the take's own note only, handed to the note's screen,
a review keeps it waiting, never at start), notes/NoteCard.test.tsx, notes/useNoteActions.test.tsx,
share/share.test.ts, share/ShareRows.test.tsx, src/read/Reader.test.tsx, mcp/server.test.ts, ai/start.test.ts,
ai/useNoteReview.test.tsx, format/gist.test.tsx, core/preferences.test.ts, core/sync/prefs.test.ts; Rust: geocode.rs's
URL and refusals, unsupported.rs's sentence. The Kotlin compiled (`:app:compileUniversalDebugKotlin`) and the manifest
merged in a copy of the generated project.

**Left undone.** Before a store build ships with the map on by default: OSM's tile policy asks an app for "a
distinct, stable `User-Agent`" naming it, and the Android and Mac WebViews send their stock one (the Referer is met;
docs/THIRD_PARTY.md). A suffix on Android's WebView User-Agent, set as the activity makes it, or the tiles fetched as
the app the way the names are, would meet it; both are native and left for Matt, since the one touches every request
the page makes and the other is a tile proxy. The share rollout above. A generation-20 binary from the meetings branch
alone would have `canAskPlace` answer yes without `geocode_place` (the name then fails quietly for the session): if the
two do not ship in one binary, this branch's generation goes to 21. London's answers name the borough ("City of
Westminster") where the spec imagined "London"; left as Nominatim gives it rather than guess at boroughs. The fold,
for Matt (above). The worktree's node_modules is its own copy, not the main checkout's through a symlink, so the main
checkout has no leaflet until `npm install` there at the merge. On the Fold, by the builder and not CI: the prompt on the first new note, Approximate drawn rough,
blocked and Open settings, the `geo:` chooser, a spoken tagged note with its tape row measured, a tagged note synced
to the Mac. The reader's card was tested, not seen: a share needs the share service. CoreLocation on the Mac; "Update
location" as a third row state; a "Set a place" by name for notes written elsewhere; asking for a name again after a
failed ask, other than remove and add; refine's compare looking past the front matter once meetings/page has merged.
Main has since gained docs/store/play/forms.md (the Play pack), which says the location permission and its Data safety
rows are to be answered if this is in the bundle: its "The app never reads location" and the Location row there need
reading again against this section when it merges.

Cites: §21, §29g, §95, §126, §127, §132, docs/LIBRARY.md "Front matter", docs/SHARING.md, docs/MCP.md

## 136. A command needs no keyword: "hey Ghost" is optional, and the setting is gone (2026-09-27)

Matt: "Remove the function which expects hey ghost before commands and the associated setting also see if you can
clean up / streamline settings a bit".

Built on branch voice/no-keyword against HEAD 891f3cd (1.8.0-20), from a design that a review replayed sentence by
sentence through both readers before anything was built; each finding it made is a rule below and a test on the
reviewer's own sentence. Numbered 136 because 133 to 135 are being taken by branches in flight (meetings/page,
notes/geotag and one more); it is the next free number at merge, and nothing was renumbered.

**What went.** `Preferences.commandWord` (§38; kept in §50 for its second job; the live reader's gate in §126), its
sync entry (an older blob's key is dropped by `known()`), the Recording row "Commands start with “hey Ghost”", its
hint and its search entry, `commandWordOn()` and its reads in the recorder, `LiveContext.keywordOn`,
`LiveTakeOptions.keywordOn`, the suite's `prefs.commandWord`, the `keyword` flag on `tips`, `tipInPause` and
`starters`, and the dead `!keyed` branches of `act` and `command` (every caller passed `true`; `readNameFirst` is
read unconditionally there, since only a keyed phrase reaches `command`). Nothing in Rust: Whisper's cue vocabulary
keeps "hey Ghost", since the word still works.

**The flow now.** "Add call the plumber to House TODOs", said at any point in a recording, puts it there as "Hey
Ghost, add call the plumber to House TODOs" did: at the start of a fresh recording the take goes to the note,
mid-take the words do and the take carries on, "move this to X" moves it, "new note" alone starts one, and
"Actually, add …" is the command as people say it (`bare` reads `commandAfterOpener`, and `takeBack` lets such a
phrase through when its words pass the gate). One gate decides, liveCommand.ts `bareCommand`, the one a mishearing
of the keyword already had to pass (§126, "Mishearings"), now one function for the live reader's bare and misheard
phrases (`clear`, `bareReading`, `readsAsRoute`) and the reader at Done's mishearing card, so a mishearing means the
same to each, which `misheardShape`'s doc promised and the first draft broke. It asks four things:

- *The shape* (`bareShape`). "Add a note to X, …" or "new item for X, …" with the name run to a comma, a colon, a
  stop or the phrase's end, never to a split the grammar chose (`!split`: "Another item on the agenda is the budget"
  read as name "agenda" and wrote "- Is the budget" into Agenda). "Put this in X, …" stopped at a separator. "Add X
  to Y" and "add X under H in Y". "Move this to X" or "switch this to X" (`Reading.plainMove`: the verb is move or
  switch and "this" was said), to a note rather than a day (`WHEN`: "move this to Tuesday" moves a meeting, even
  beside a note called Tuesday); "go to work", "continue in the garage" and "move it to X" each moved a whole
  recording, sticky, and "it" is a send's word (§130), and in the review of the build so did "move everything to the
  garage" and "move these to the kitchen", which is how people talk about boxes. "New note" alone, never "another
  note" (how people introduce their next point). Never a to-do for here, a name said first, a name that starts with
  a verb, or `current` (a heading, a lane, "the list", "here": the least distinctive names there are), and never a
  card, a hold or a chip.
- *The note*: resolved at `FIND.clear`, which rose from 0.85 to 0.9, the whole of a title's distinctive words. 0.85
  is the floor `covered()` gives any name that is the start of a title, so one common word cleared it ("bank" is
  Bank statements, "weekend" Weekend trip, "car" Car insurance, all 0.85); "house" is House TODOs at 0.9 and "the
  work list" Work at 0.9. And one the recorder may write to (`refusal`: no book, no shared note over the lock
  screen). `LIVE_TIMING.bareScore` stays as its alias.
- *The evidence* (`bareEvidence`): for "put this in", "add X to Y" and a heading, the name says what kind of list it
  is (`saysList`: a kind word, "house to-dos", "the work list", "packing list", or a shopping word, "groceries"). A
  title that says so is not enough on its own: the first build took `titleKind(title)` too, and "house" is House
  TODOs and "garden" Garden jobs at 0.9, so "Put the washing in the house." wrote the whole recording into House
  TODOs as to-dos and "Put the bags in the house and lock the car." made two of them. For "add a note to X" and "new
  item for X" the noun is the evidence only when it is filed (`Reading.filed`: added, put, stuck, popped, appended,
  saved or filed; a note, an item, an entry, a bullet, a to-do, a task, a reminder, a bug or an issue): "Leave a note
  for Mum, dinner is in the oven." sent a whole recording into Mum, and "send a note to Sam", "drop a line to the
  team", "jot down a note for the kids", "another point for the agenda" and "another thing for the kitchen" are
  messages and meeting talk, which need the name to say it is a list, as the other shapes do. The heading is one the
  note has (`headingIn`, at `FIND.resolved`). "Move this" is its own evidence. A list in the body is no evidence any
  more: nearly every note has one bullet, and "Send this to Sam, the deposit is due" wrote into a note called Sam.
- *The words*: in the same phrase, unless the take is at the start of a fresh recording (not a note's own Speak),
  where a route may wait for them in the open (the page switches, the chip says waiting, Not this note is there), or
  the command moves the take. A bare command with nothing said for it opened a one-shot that took the next three
  phrases of dictation. A mishearing mid-take is held to this too.

Anything short of that is words, untouched: no card, no hold, no chip. "Okay." | "Add a note to House TODOs, call
Sam." starts the take there, and "Um." | "New note." makes no note of "Um": the filler is marked with the command
rather than written (`readHeld`, decided after the read, since `record` places by time, by whether the phrase's
first step is a command's mark; "Okay." before words is still words). `choose` prefers the heading reading when one
name is read two ways and the note has that heading ("add fix the tap under Kitchen in home jobs"), and otherwise the
reading that keeps "under …" in the thing: the first build preferred the heading always, so "Hey Ghost, add clean
under the sofa in house to-dos." wrote "- [ ] Clean", where main had kept it whole by accident (its comparator
answered -1 both ways for one name).

**What the keyword still does**, all of it already in code: a phrase that is no route after it is an ask or a run;
an unsure or missing name gets a card; an opener is held for its name (chip "Hey Ghost, listening for a command");
the name-first shapes ("For Groceries, …"); a heading or lane of the note being written to ("add call Sam to
Doing"); a name and its words with no comma between them; "go to X", "carry on in X", "move it to X", "another
note", "a new note"; a command whose words are still to come, mid-take; a to-do for here ("make a note to …", "add
a to-do: …"); it interrupts a held command, an open one-shot or a note waiting for its words; it is stripped along
with more of the lead-ins (`LEAD_INS` after it, `PLAIN_LEAD` without); its partial goes to the chip. The take-backs
(§130) never read the setting and are unchanged: after "Hey Ghost" a whole new sentence counts as a correction, a
keyed send that finds nothing is refused with a chip, a bare one is words; the one rule added mirrors the keyed one,
a risky opener before words that pass the gate is the command, not a correction. A phrase with words before its
opener ("Buy milk. Actually, add call the plumber to House TODOs.") is read as two first and its rest meets the rule
alone (`!read.head`): the first build kept all of it as words, where the keyed form acted.

**Asks at Done.** The named runs were already read without the keyword at the start of a note's own Speak (`runOf`
before `keyed`), and the rules are prefix-anchored, so "Fix the spelling of Kowalski on the sign before Friday",
"Tidy up the garage before the weekend", "Summarise the call with Jo" and "Continue the discussion with Sam
tomorrow" were each a run that let the recording go and rewrote the note. Without the keyword a run is now the whole
phrase and nothing more but its object (`runOf(words, { whole: true })`, `RUN_REST`: "it", "this", "that", "the
note", "this note", "everything", "up", "please", "for me", "now"); with more words after it, it is the note's
words, and the keyword forces the run. Each of the five asks on the say-card passes. A free ask without the keyword
stays words, even alone in a fresh take into an open note: the reader cannot tell the first sentence of dictation
from an instruction, and the wrong call rewrites the note ("A free ask only counts when the keyword opens the take",
chapter 18, stands). A bare command at the start of a fresh recording whose name resolves nothing is words live,
and the reader at Done, which reads the whole transcript through `finalCommandWords` as it always did, now saves it
as the note with the reason as its notice ("No note called “shopping”, so the words are saved as a note.", the name
as said up to its comma, `savedAsWords`, where the rules' reason carried "shopping, oat milk"), `{ kind: 'words',
notice }`, no longer refused with nothing saved: a person who did not say the keyword did not say it was a command. A
keyed one is refused as before (at Done), or kept by the live reader with its own chip ("No note called “shopping”,
so the words stay here."), as before.

The reader at Done reads a fresh recording's, or a note's own Speak's, whole transcript when the live reader did
nothing, and `planCommand` is loose, "since the keyword already says it is one" (command.ts): a plain note, a prefix
at 0.85, a heading that is not there. So on main, and on the first build of this branch, what the live gate kept as
words came back at Done as a card: "Add the flour to the bowl." | "Then stir it for a minute." offered Add to Bowl
with both sentences, "Put this in the car, then drive." Car insurance, "Add call the plumber to work." Work, and into
Garage's own Speak "Add the flour to the bowl." offered to move it out. The card writes nothing until Add, but its
Cancel lets the recording go, so the dictation was lost on a tap that meant "not that note". Now a place offer for a
transcript with no keyword is words when the live gate turned it down (ai/instruction.ts `turnedDown`: the words
have a bare shape for that note, and no such reading passes `bareCommand`), whether the rules or the model made the
offer. What the live gate had no reading of for that note is offered as ever: a title that starts with a verb ("add
to the note labeled Go pack sunscreen", the stop-transcript test), a name only the model matches, a new list by
name, and, into a note's own Speak, a command whose words came in the next breath ("Add a note to weekend trip." |
"Book the ferry."), since the transcript at Done has no phrase breaks to tell it from one breath. Those cards keep
the Cancel that lets the recording go (question 11).

**Teaching.** Every example says the command bare, in a form the gate takes: "Add … to Groceries" for a note whose
title says it is a list (said whole, its last word is the kind or shopping word the gate wants), "Add a note to Work,
…" for one that does not (tips.ts `addTo` chooses by `titleKind`), "New item for X, …" with the item in the same
breath (the first build said "and then the item", a second breath, which mid-take is words: "- For Groceries" was
written into the note being recorded), "Move this to X" and "New note"; one line says "Hey Ghost" first is optional
(the Guide's habits page, chapter 11). The note a tip names is one the gate can name bare: never a book (the pause's
tip skipped none before) and never a title that starts with a verb (Call log, Book club, Set list), which is read as
what to do, keyed or not for a move; the tip names the next note, and the say-card offers the new list instead. The
say-card's ask reads "Summarise this", as chapters 11 and 18 do. The habits page's three phrases are "Add bread to
Groceries", "Add a note to Work, call Sam" (guide/phrases.ts `NOTE_COMMAND`, where the first build only matched its
string) and "Fix the spelling"; guide.test.ts runs each through the readers bare and keyed. A heading or lane of the note you are in keeps the
keyword in every example, and chapter 11, chapter 13 and BOARDS.md say why. The chapter "Commands after Hey Ghost"
is "Spoken commands" (11-spoken-commands.md), its links and libraryTitles.ts with it; it gains "What is read without
it" and "Saying “Hey Ghost” first". Chapter 18's table says the runs bare; chapter 24 loses the row and its hint;
chapter 34 describes `bareCommand` and gains a row for an unsure or missing name without the keyword. The model's
command prompt (understand.ts, which src-tauri's `understands_spoken_commands` reads by name) says the person "may
have said" the keyword; the review's prompt and its simulations say "each spoken command".

**Voice suite.** The 22 recorded scripts stand (the keyword is stripped as before). 066 kept its lines and its
recording and now expects the Glyph note written to ("the Glyph note" is a name, said bare). 059's wording changed,
not its expectation. 112 to 118 are text-only until their audio is made: "add oat milk to groceries" at the start;
"add call the plumber to House TODOs" as a one-shot mid-take; "move this to weekend trip"; Matt's sentence in two
phrases without "Hey Ghost" (093 bare); "put the parcel in the post" and a note there is none of, words; "go to
work", words; "fix the spelling of Kowalski on the sign" into a note's own Speak, words. The suite plays the live
reader only, so 116 and 118 now say they check what is written as it is said; the reader at Done's side of them is
instruction.test.ts's and CaptureScreen.test.tsx's.

**Settings, streamlined.** Recording's reading was "A note a take", memo mode's, which went on 2026-09-22; it now
reads what is on: "Review · better words · meeting summaries" by default, "Stops when quiet · …" with quiet stop,
"Nothing after recording" with none. Feel, a page of one switch listed only where there is a motor, absorbs
Animations, which the sheet's own comment said sat with the "how it works" pages though it was listed after the
plugins: one page in Feel's place, icon Waves, sections Speed, Movement and, only where `hapticsAvailable()`, Touch;
its reading is the Animations one plus "haptics" where there is a motor, first word capitalised as Recording's is,
or "All still". AnimationsPane.tsx went into FeelPane.tsx; chapter 24 has one Feel section; every "Settings ›
Animations" in the guidebook, the docs, the code's comments and the smoke bench's one line says Feel. Recording's
sections are not regrouped (meetings/page is adding rows there), so "Review after recording" still sits under "The
side key" on Android; Type and Appearance are not merged (question 1). Settings search finds "How to talk to
Ghost.md" (About) by "hey ghost" and "keyword", so someone looking for the switch that went is led to the Guide.

**In the browser**, a build previewed with a library of House TODOs (a to-do list), Groceries, Sam (one bullet),
Launch board (Doing a lane), Work, Weekend trip, Porch light, Car insurance, Garage and Agenda, driven through
`?simulate=say`, the bodies read back from localStorage: "Add call the plumber to House TODOs." alone switched to
House TODOs and wrote "- [ ] Call the plumber", no note made; "Kevin owns the release." | "Add a note to house
to-dos, call Sam." | "The cabin has two bedrooms." wrote "- [ ] Call Sam" there and the note kept both sentences;
"Buy milk." | "Go to work." | "Ring the plumber." was one note and Work untouched; the agenda, Sam, porch and car
sentences in one take were one note and no note changed; "Move this to the garage." took "Kevin owns the release."
and "Ring the plumber." into Garage; "Actually, add call the plumber to House TODOs." then "Add oat milk to
groceries." after a sentence wrote into both and the note kept its sentence; "Okay." | "Add a note to weekend trip,
book the ferry." | "Pack the tent." started the take in Weekend trip with no "Okay."; "Make a new list called Comic
books with Batman and Superman." showed Create at Done and made the list; "Scratch that, add it to groceries
instead" sent "Oat milk" as before; into Garage's own Speak, "Fix the spelling of Kowalski on the sign." was
appended as words. The say-card read "“Add … to House TODOs”", "“Move this to House TODOs”", "“Fix the spelling”"
and "“Summarize this”", and the pause tip "Say “Add … to House TODOs” …", nothing keyed. Settings in the browser:
Feel with Speed and Movement, reading "Ghostly typing · smoke · ripples"; with an Android user agent, Recording
reading "Review · better words · meeting summaries", its rows Stop when I go quiet, Review after recording, Height,
Better words, Summaries, and no "hey Ghost" on the page.

**In the browser again**, after the review of the build, the same way with Bowl, Mum, Tuesday, Garden jobs and Call
log added: "Put the washing in the house." | "The rest of the note.", "We talked." | "Move everything to the
garage." | "More.", "Leave a note for Mum, dinner is in the oven." | "The rest." and "Add the flour to the bowl." |
"Then stir it for a minute." were each one note, no note changed and no card at Done; "Hey Ghost, add clean under the
sofa in house to-dos." wrote "- [ ] Clean under the sofa"; "Buy milk. Actually, add call the plumber to House TODOs."
in one phrase wrote "- [ ] Call the plumber" and made "# Buy milk"; "Add call the plumber to House TODOs." alone
still switched there; "New item for groceries, oat milk." mid-take wrote "- Oat milk"; "Add to shopping, oat milk."
made its note, and the notice was not seen (question 8); into Garage's own Speak "Add call the plumber to work." was
appended, with no card. With Call log the most recent note the say-card offered "Make a list called … with …" and the
pause tip "Say “Add … to House TODOs” …"; the ask read "“Summarise this”". Settings search for "hey ghost" found How
to talk to Ghost.md under About.

**Changed on purpose.** A bare command routes at any point, not only at the start with the setting off. "Add a note
to Weekend trip, …" routes when Weekend trip has no list: "a note" was said. "OK like move this to the Galaxy Fold"
moves the take. "New note." alone works bare. A mishearing mid-take with no words in the phrase is words, where it
opened a one-shot. `FIND.clear` is 0.9, so a mishearing before a name that is only the start of a title is words. A
bare run with more words after it is words into the note. A bare command refused at Done is saved as words with the
reason. 066's expectation. Tests: liveRoute.test.ts "the keyword" became "without the keyword" and "the guards" was
rewritten, the mishearing list lost its move line; tips.test.ts strings and its `keywordOn` loop; guide.test.ts and
Tips.test.tsx on the bare phrases plus a keyed variant; SettingsSheet.test.tsx labels, rows and readings;
settingsSearch.test.ts's fixture row; CaptureScreen.test.tsx's refusal test, now a bare command saved as words with
the reason beside a keyed one kept with the live reader's chip, "stays on a continued note's tape" now said with the
keyword (a bare "add to the camping list …" is the note's words), and the New note test's command at Done now a new
list by name (a bare "add oat milk to groceries" is carried out live). After the review of the build: "move
everything", "move these" and a move to a day are words bare; a note or item left, sent or raised for someone, and
"put … in the house" beside House TODOs, are words bare; "Hey Ghost, add clean under the sofa in house to-dos" keeps
"under the sofa"; "Buy milk. Actually, add …" in one phrase carries the command out; "Um." | "New note." makes no
note of "Um"; a place offer at Done that the live gate turned down is words, not a card; the bare notice names the
note as said ("No note called “shopping”"); the tips' "New item for X, …", their skipping of books and of titles
that start with a verb, and "Summarise this"; Settings search finds "How to talk to Ghost.md" by "hey ghost" and
"keyword". Tests: liveCommand.test.ts's `switch everything to work` row is now false, and its evidence rows say the
name, not the title; instruction.test.ts's notice strings; CaptureScreen.test.tsx's notice string; tips.test.ts's
new-item tip, with the `', oat milk'` special case gone.

**Questions for Matt.** 1. Type and Appearance overlap (Text size beside Size, two font rows): merge Type into
Appearance as a section? 2. A bare opener alone ("Add a note to." then a pause) is words; hold it for its name as
after the keyword? 3. A bare command's partial draws on the page until it commits; the keyword's goes to the chip.
Worth a partial-time guess against the note titles? 4. While a note waits for its words, "Add call Sam to Work." is
the words (only the keyword interrupts). Keep? 5. Mid-take a bare command needs its words in the same breath; "Add a
note to house to-dos." | "Call Sam." is two sentences of dictation. Keep, or let a bare route wait one phrase with
the chip showing? 6. "Add call the plumber to Work" is words beside a note called Work, since neither the name nor
the title says it is a list; "the work list", "a note" or "a task" routes. Widen shape 4 to any note whose body
holds a list, or (the review's suggestion, since a body with a list is what caught Sam) only to a name that is the
whole title? 7. Answered in the review of the build, for Matt to overturn: "Send a note to Sam, the deposit is due"
beside a note called Sam is words, as are "leave a note for Mum", "drop a line to the team" and "another point for
the agenda"; "send a note to the house list, …" routes. Keep? 8. The reason a bare command was saved as words is set on the recorder's line as it saves, and a new
recording's recorder closes at once, so in the app it is not seen; the same is true of "… isn't something a
recording can do, so the words are saved as a note", which is older. Hold the recorder for `SAID_MS` when a notice
is set, as `finish` already does for "Nothing was said for …"? (CaptureScreen.tsx's `finish` was left alone here, for
the branches merging before this one.) 9. A take-back's send needs no gate: "Leave the bike by the door." | "No, put
it in the garage." sends the sentence to Garage, and "Actually, it goes in the garage." does too, on main as here.
Now that commands are taught bare, should a send after a risky opener with no keyword need the bare gate's evidence
(a name that says it is a list)? 10. "Make a list called Comic books" is made bare only when it opens a recording;
in the middle of one it is words, where after the keyword it is queued for the reader at Done. Queue it bare too?
11. A card at Done for a transcript with no keyword (a verb-named note, a name only the model matched, a two-breath
command into a note's own Speak) keeps the Cancel that lets the recording go. Should its Cancel keep the words as a
note instead, since nobody said it was a command? (A change to CaptureScreen.tsx's `finish`, for after meetings/page
merges.) 12. The Play listing on main (docs/store/play, since d69aa6f, after this branch's base) leads with "HEY
GHOST" and 'Say "Hey Ghost, add a note to House TODOs"', and What's new says the same. Both still work; keep "Hey
Ghost" as the listing's hook, or say the command bare and the keyword optional? The copy is not on this branch, so
it is unchanged here.

**Tests.** liveCommand.test.ts (`bareShape`, `bareEvidence`, `plainMove`, `filed`, `split`, the heading reading),
noteFind.test.ts (the prefix scores, `FIND.clear`, `headingIn`), liveRoute.test.ts ("without the keyword", "the
guards", "stays words without the keyword" at the start and mid-take, now with the review of the build's sentences
and no chip; filler before a bare command or "New note"; "Buy milk. Actually, add …"; the name-first shapes after
the keyword only; a book and a shared note over the lock screen; a note's own Speak waiting for no words; "under
the sofa"), instruction.test.ts (runs as whole phrases, a bare refusal saved with the name as said, the shared
mishearing gate, "the reader at Done, without the keyword": the turned-down sentences as words and keyed as cards),
tips.test.ts (bare tips carried out, "Add a note to Work, …", "New item for Groceries, …" and its two breaths as
words, a book or a verb title never named, the asks as whole runs), guide.test.ts (all three habits), Tips.test.tsx,
CaptureScreen.test.tsx (a bare command at the start, live; a bare refusal at Done and its keyed variant; a run
sentence and a turned-down command into a note's own Speak; a fresh recording that opens with a turned-down
sentence, no card), FeelPane.test.tsx (Touch only where there is a motor), SettingsSheet.test.tsx (and the search
for the switch that went), settingsSearch.test.ts, the suite's 066 and 112 to 118.

**Not done.** The seven scripts' audio; a partial-time guess for bare commands; Type and Appearance; a bare route
that waits one phrase; the notice held on screen (question 8); Cancel keeping the words (question 11); the Play copy
(question 12). A Guide already added to a library keeps its chapters as they were ("a book already there by the
guide's title is answered as it is", guidebook.ts), so Matt's phone still has "Commands after Hey Ghost" and chapter
24's row for the switch until the Guide is removed and added again (Settings › About). The keyed
"Hey Ghost, move this to Call log." is queued as an ask mid-take, since a name that starts with a verb is never a
move's (SHAPE_5 wants `nameable` 'name'): older than this branch, and left for its own change.

Cites: §38, §50, §126, §127 (Recording on the Mac), §130.

## 137. The home page laid out wide: two across, then a main and a rail (2026-09-27)

Matt: "Extend the dashboard to support wide phone / tablet layouts too", and later: "It's okay if they're two across
or the layout changes slightly on wide the four column was a suggestion not a rule"

Built on branch home/wide against 891f3cd (1.8.0-20, §132), in two commits and a browser pass: the tiers and the
page's code; the stylesheets; then the numbers, and this. Then a review's findings put right, in a third commit and
a second browser pass ("Put right after the review", below). The text says what the page does after it.

**The idea, by the page's own width.** The phone's column is the unit. Past 44rem of column the page is two of them
across; past 66rem it is a main two cards wide beside a rail that holds To do. Under 44rem nothing changes, and a
phone draws exactly what 1.8.0-20 drew. The page decides by its own width, never the window's: container queries on
`home-page` (the `.page` column, already a container), and home/tiers.ts's `tierOf` for the counts, read by
home/useColumnTier.ts off the same box. The window would be the wrong question: the pane is the window less a docked
sidebar (`clamp(300px, 30vw, 380px)`, app.css `.app-split`), and a 1280 window with the sidebar docked is a 900px
pane, which a window query would lay out as a desk. The one thing on the screen that reads the window is the dock
(§92), and it still does. The lines are in rem, so Settings' interface size (`uiScale`, the root's size) moves them,
and the hook reads the root's rem as the queries do.

**The lines, and what each costs.** Both are where To do's heading row fits: "To do · 11", the gap, "Show all 11"
and the dock's clearance at the row's end need 294px at 44rem and 305 at 1024 wide (heading 128.7, gap 15.1, word
86.3, clearance 74.5). 44rem (704px of column; a pane of 752, or 764 with the Mac's 12px scrollbar) is where the old
wide rules already began, and where a unit is 328, room for that row beside a pinned card; under it every phone, a
docked Fold and a docked tablet keep the stack. A lower line was measured and left (below). 66rem (1056px; a pane of
1108, 1120 with the scrollbar, a window of 1492-1504 with the sidebar docked) is the desk's: its rail is a third of
the column less its share of the gap, 335px at the line, and holds the row with 30px to spare. At 60rem, the old
cap, the rail was 304, and "To do" broke over two lines at the desk's foot. The cap rises to 80rem, past the desk's
line, or no desk could exist. 50rem is the tapes' own line (below).

**Two across (44rem to under 66rem).** Two equal units, space-10 between them, no dense packing: every group is
placed in the order it is written, and the order seen is the order written. Every group spans both units but for the
pair:

- one pinned card and To do not opened out: Pinned in unit 1 and To do in unit 2, side by side;
- two or more pinned cards: Pinned is a row of two, To do spans under it with its rows in two columns;
- no Pinned: To do spans, its rows in two columns;
- no To do: the one pinned card keeps unit 1, and the Tapes come under it;
- To do opened out (Show all, more than five open): it spans under Pinned, with its heading held where it was on the
  screen (below); a tick down to five puts it back beside Pinned, held the same way;
- no notes: the ghost in unit 1, its words in unit 2.

Library and Recent always span, two across, and one book or an odd last card leaves half a row of air: the board's
grid showing. The page says whether there is a pair (HomeScreen.tsx `paired`: one pinned card, To do on the page,
and not opened out) as `data-paired` on the grid, and the sheet places the two by `.grid[data-paired]`, each with
one unit's worth (`--home-units: 1`: one card across, one column of rows). To do's rows are a column for each unit
the card is across: one in a unit or in the rail, two when it spans, so across the page the first column of rows
ends where unit 1 does. `data-group` is written only as `.grid > [data-group=…]`, since NoteTabs, the cheat sheet
and StyleItems use an attribute of that name for other things. Past 44rem a group's heading never breaks: it keeps
to one line, and a word that no longer fits beside it goes under it. At the kit's own size that never happens
(measured, below); it is there for a large interface size.

**The hinge.** On the Fold opened out, flat and undocked, the crease is the pane's middle, which is the column's
middle, and it runs down the units' gap: "the hinge in the gap", as scene/AtWork.module.css has it. Recent's, the
Library's and a two-card Pinned's gap, the tapes' middle gap and a spanning To do's row gap are all space-10 too, so
the clearance is 24.5-24.9px either side at every width measured, and nothing on the page crosses it at rest. The
date, the digest and the notices are held to unit 1 (`max-inline-size: calc((100% - space-10) / 2)`), so no line of
the head crosses it either. What does cross: the rows that scroll sideways (the pills, and the tapes under 50rem)
pass over it as they scroll, and a spanning To do card's ground runs across it, its rows either side. A horizontal
hinge (the Fold turned) is scrolled past like any line. **Docked, the hinge is not in the gap.** With the sidebar
docked and shown (Matt's own setting on the Fold, as §132's seed has it) the pane is 570-660, the column 521-610,
the stack, and §121's viewport rule gives two cards of 251-295; the crease at viewport x 435-480 runs 111-155px into
the first card column of every row (870 to 960 wide). The fix is not this page's: give `.app-split` the crease on a
finger-driven window in the Fold's band (`@media (pointer: coarse) and (min-width: 800px) and (max-width: 1000px) {
.app-split[data-sidebar='shown'] { grid-template-columns: minmax(300px, 50%) minmax(0, 1fr) } }`), so the sidebar
ends at the crease and the pane (400-480) holds the phone's layout clear of it; it moves the note and All notes
panes too, so it is its own branch. The exact hook is the Viewport Segments media feature
(`horizontal-viewport-segments: 2`), which Chromium ships, but by Android's FoldingFeature it reports two segments
only for a separating fold (half opened), so a Fold lying flat would read as one: measure it with
diag/windowFacts.ts before relying on it.

**The tapes on the units (50rem to under 66rem).** Half a unit each, two to a unit, four across, a spacer track
between the pairs making the middle gap the page's space-10: a tape's outer edge is a unit's edge, and the crease
runs between the second and the third. From TapeShelf.module.css, by `@container home-page`: the first container
query in the tree asked from another module's sheet, which works because CSS modules localise classes and keyframes,
never a container's name (Vite 7.3.6's postcss-modules-local-by-default 4.2.0 and scope 3.2.1, read). The placements
live in the ranged block alone, so the desk's grid never inherits a fourth column. The row's block padding goes on
the grid (it was room for the arrive beat in a row that clips; a grid does not). 50rem because every width the Fold
may report opened out with its hinge down the page (870-933, §92 saw 880) is 51-55rem of column, while tablets
upright (720-785 of column) keep the phone's 13rem row, a tape 208 with a 167px cassette. The cost is the cassette:
measured, 142 at 870, 144 at 880, 150 at 906, 157 at 933, 163 at 960, 144 in Matt's 1280 window with the sidebar
docked (141 with the Mac's scrollbar), 179 on a 1024 tablet turned, 197 at the tier's top (1100), against the
phone's 170, and about 139 at the grid's foot. **The line is provisional** until the Fold's own width is read (Left
undone): if Matt finds the cassettes small in the 880 shot, 57.5rem gives every Fold the 208 tapes back, the row
crossing the crease as it scrolls; if the Fold reads about 800 wide with its hinge down the page, about 46rem puts
it on the grid too, with cassettes of ~127 and two-line titles, where 50rem leaves it the row, whose second tape
sits over the crease at rest. This closes §132's leftover (tapes not on the grid's columns) on the units; on a desk
it stays open (below).

**The desk (66rem and up).** A main (2fr: cards two across, tapes three) and a rail (1fr, one card wide) holding To
do, on named areas: `'head head' 'pinned tasks' 'tapes tasks' 'library tasks' 'recent tasks' '. tasks' 'foot foot'`.

- **Two across in the main**, not four: a card is 329 at the desk's foot and 359-397 above it, against 386-499 on
  the units, so 66rem is a step, not a cliff (at the line, 1100 to 1120 wide, cards go 499 to 329, tapes 239 to 213,
  To do from a unit of 499 to the rail's 339). A 1024 tablet turned (units 462) and a 1440 MacBook with the sidebar
  docked (476) are two across, Pinned beside To do. The sidebar's toggle at 1280 changes little: docked (a 900 pane,
  two across) cards 397, tapes 188, To do in unit 2 at 397 with five rows; undocked (a desk) cards 381, tapes 247,
  the rail 392 with eight rows and six Recent cards, which arrive.
- **The flexible sixth row.** An item spanning a flexible track is left out of the auto rows' sizing, so a rail
  taller than the main (Show all's forty, 2297px) grows that row alone and the air falls under Recent; the main's
  groups do not move, and the foot comes space-10 under the rail. An absent group is an empty row with no height.
  The rhythm is the groups' own margins, never a row gap, or an absent group would leave a double one.
- **Why To do alone rides the rail**: it is the one list of rows, and the one group that grows tall. Two groups in
  one rail cell would need a wrapper, and as rows of their own they would share heights with the main's.
- **No To do at all** (a workspace that never had one; ticking every to-do keeps the card with its ghost, so the
  rail stays): one column, cards three across (343-412) and tapes four (252-304), so every row at the counts is
  whole.
- **Reading order.** What is written is what is seen, read by each group's top and then from the left. The one
  exception: with no Pinned, To do's top is level with the Tapes', and the page reads To do before the Tapes beside
  it, the rail read at its top as a side column is.
- The head's lines and the notices are held to the main's width (two thirds less the gap's share); the empty page
  puts the ghost where the main is and its words where the rail is.
- The tapes, three across the main, do not share the cards' two columns, so §132's leftover stays open here.

**The counts** (home/tiers.ts `CAPS`). Recent 4 and To do 5 before Show all in the stack and on the units (Recent
two rows of two); a desk 6 (three rows of two, or two of three with no rail) and 8 (the rail is tall). The shelf
stays 8 everywhere, so the same library shows the same tapes on every screen, the biggest never shows fewer than the
cover screen, and the desk's rows at it are whole (three, three and two; two of four with no rail). `TASKS_OPEN`
stays 40. The gist runner is asked about the two extra Recent cards on a desk, which is what is on screen. The hook
answers in a layout effect first, so a desk never paints the phone's counts for a frame, then a size observer, whose
answer is committed at once (`flushSync`): an update from outside React waits for a later task, and crossing the
desk's line painted one frame of the desk's layout with the phone's counts. It starts as the stack, which is a
phone's answer.

**Show all on the units, and its held heading.** Opening To do out of the pair spreads it across the page under the
pinned card, which moved its heading down by the card's height, away from the thumb that pressed it; and the tick
that brings the count down to what the card holds puts it back beside the pinned card, which moved it up by as much,
out from under the finger ticking the list off (Show fewer goes with it, since there is no more to fold). So Show
all, Show fewer and a tick each record the heading row's top, and a layout effect after the commit scrolls the page
by as much as the row moved. Where the row does not move (a phone, the rail, a card already spanning, most ticks) it
moves by 0. It is a scroll set, not a glide, so reduced motion needs nothing. Chromium's scroll anchoring did not
fight it: measured below.

**The head's air.** In a grid, an item keeps its last piece's margin inside it, so the head ends with its space-5
and gives the first row's space-10 back (`.grid > .head:has(+ :is(.section, .empty))`, a negative margin): the first
group sits space-5 under the head, as on the phone, and rows are space-10 apart. The `:has()` keeps the loading
page, the head and the foot alone, from pulling the foot up against the date. If Matt finds the title block close on
the wide screens, the one number to change is the margin, to `-space-5`, for space-10 under the head.

**The dock** is the floating column at the pane's bottom right at every width (Matt, §110: "this is how all ...
devices should display it"). A heading row keeps clear of it under `@container home-pane (max-width: 92rem)`, where
it was 70rem: with the column capped at 80rem the dock crosses it until the pane is 80rem plus twice the dock's
whole width and inset, ~1469px (91.8rem).

**The foot, and All notes as it was.** Every group, the empty page and the foot have space-10 above them on the
wider screens. All notes keeps its 60rem column and §121's grid exactly as 1.8.0-20 had them. The first pass took
its column to 80rem with the home page's, so the foot's "All notes · 13" opened a column of the same width; the
review found its grid then six across of 200 at 1600 (four of 228 at 60rem) while the home page's cards are twice
that, and Matt asked about the dashboard. So on a desk the foot now opens a column narrower than the home page's (by
160 each side at 1600, 102 at 1600 docked), and whether All notes should follow is Left undone. The home page's wide
rules are its sections' alone (`.section .cards` inside `@container home-page`), which cannot match there.

**The empty page.** On the units the ghost is in unit 1 and its words in unit 2, the crease between; on a desk the
ghost is where the main is and the words where the rail is. The ghost sits at its column's end, against the gap: it
stops at 45% of the height, and from its column's start it left its words 515px off on a desk (main's 3fr/2fr left
233-268). All notes keeps its own 3fr/2fr copy.

**Motion.** Nothing new moves. A fold or an unfold re-lays the grid at once, and only the cards a bigger count adds
arrive, on their beats. **Light and dark**: no colour was added, and the layout is the same to the tenth of a pixel
in both at every size measured.

**Measured** (Chromium 2×, Playwright 1.59.1 from the npx cache, chromium-1217 and webkit-2272, against `vite
preview` of the branch's build and of 891f3cd's from a `git archive`; the task's seed: three tapes, Lisbon pinned,
the Portugal book, six typed notes, eleven open to-dos, one archived; the page's clock installed at Sunday 27
September 2026, 15:00; the Fold with touch and a 40px inset forced, §53, §66). Widths with a mouse are given as
Chromium draws them with its scrollbars hidden, and then "with the scrollbar" as a Chromium that draws them measures
them: the Mac draws the app's 12px one (app.css, pointer: fine), and Playwright's WebKit drew it in some contexts
and an overlay in others, and matched Chromium to the tenth either way. Touch sizes are the same in both engines.

- **The phones against main, to the pixel**, on the final build: 412 × 915 and 375 × 812, light and dark, with
  motion and reduced, Home and All notes at rest, scrolled 0.85 of the height and at the foot. With reduced motion,
  all 24 pairs identical. With motion the smoke under the bar drifts on requestAnimationFrame's clock while a page
  scrolls (art/wispEdge.ts), so its phase is the machine's timing; the clock is paused before the first scroll and
  each scroll run for a set stretch of it, and main is shot twice so the method can be seen to fail. Home was
  identical in 11 of 12 pairs, and the twelfth (375 light, the foot) differed by 6272 pixels above y 96, the smoke's
  band, exactly as main against itself did. All notes, scrolled and at its foot, differed in five pairs, four of
  them only above y 150, the smoke's band (main against itself differed there too, by 3717-8714, in three pairs);
  the fifth (375 light, the foot) also lower, 2728 pixels down to y 768, and run twice more it gave 5272 above y 146
  and then 0, Home identical both times. The built CSS keeps the range preludes as written, `(44rem <= width <
  66rem)` and `(50rem <= width < 66rem)`.
- **The Fold opened out, undocked** (hinge vertical): 870 × 657, column 821, units 24.5-410.5 and 459.5-845.5, cards
  2 × 386, tapes 183 (cassette 142), hinge at 435 with 24.5 clear; 880 × 664, column 831, cards 2 × 391, tapes 186
  (144), 24.5 clear; 906 × 684, cards 2 × 404, tapes 192 (150); 933 × 704, cards 2 × 417, tapes 199 (157), 24.8
  clear; 960 × 725 and 960 × 800, cards 2 × 430, tapes 205 (163), 24.9 clear. At every one: Pinned's and To do's
  headings on one line (247.9 and 247.9 at 880) and their cards too (296.7); the head's last piece to the first
  heading 24.5-24.9 (space-5), row to row 49.0-49.8 (space-10); the date, the digest and the notices end on unit 1's
  edge; "Show all 11" ends 12-13px before the dock (782.9 against 795.6 at 880); nothing crosses the hinge; the
  first screen holds the head, Pinned beside To do, and the Tapes' heading.
- **The Fold docked and shown** (870-960): panes 570-660, the stack, cards 2 × 251-295, the tapes' row at 208; the
  hinge crosses the first card column (above). **Turned** (657 × 870, 704 × 933): the stack, cards 2 × 296 and 3 ×
  206 by §121; docked at 704 the pane is 404 and one card across; at 657 the sidebar does not split (under 660).
  **Reading B** (800 × 960): two across, column 752, cards 2 × 352, the tapes' row at 208, whose second tape sits
  over the crease at rest; docked, pane 500, the stack.
- **Tablets.** 768 × 1024: two across, cards 2 × 336, the tapes' row at 208 (167), the first screen down to the
  Library's heading; docked, the stack at 468 as §132 had it (2 × 200). 820 × 1180: two across, 2 × 362. 1024 × 768:
  two across, column 974, units 462, Pinned beside To do (headings 213.2 and 213.2, cards 263.3), tapes 221 (179),
  "Show all 11" ending at 924.3 against the dock's 937.4; docked, the stack at 717, 3 × 209. WebKit at 1024 × 768
  the same to the tenth.
- **Either side of the desk's line**, with a mouse. 1000 × 800 and 1010 × 800: two across, cards 2 × 450 and 455,
  tapes 215 and 217. 1100 × 800: two across at its top, column 1049 (1037 with the scrollbar), cards 2 × 499 (493),
  tapes 239 (197). 1120 × 800: a desk at its foot, column 1069 (1057), main 678 and rail 339 (335), cards 2 × 329
  (325), tapes 3 × 213 (170), "To do · 11" and "Show all 11" on one row, the headings level (216.5) and the cards
  (267.3).
- **The desktop.** 1280 × 900 docked (pane 900): two across, cards 2 × 397 (391 with the scrollbar), tapes 188 (144;
  185 and 141), To do in unit 2 at 397 (391); undocked: a desk, main 783 and rail 392 (388), cards 2 × 381 (377),
  tapes 3 × 247 (203; 244 and 200), eight rows, six Recent cards; 1280 × 820 docked as 1280 × 900. 1440 × 900 docked
  (pane 1060, the review's MacBook): two across, column 1006 (994), units 476 (470), tapes 227 (182), headings level
  at 227.9, "Show all 11" ending at 1332.8 (1320.8) against the dock's 1347.1. 1600 × 1000 docked (pane 1220):
  column 1165 (1153), cards 2 × 359 (355), tapes 3 × 232 (186), the rail 370 (366), "Show all 11" at 1491 (1479)
  against the dock's 1506; undocked: the 80rem cap, column at x 160 (154), cards 2 × 397, tapes 3 × 258 (212), rail
  408. 1812 × 1000 docked (pane 1432): the cap at x 456 (450), "Show all 11" ends at 1655, the dock at 1718;
  undocked, the column at x 266 (260). Headings level at every one (222.2 at 1280, 231.2 at 1600 and 1812); the head
  to the first group 26.3-27.5, rows 52.7-55.
- **Every width, for the heading row.** From 700 to 1920 in 4px steps, with a mouse undocked and docked and with
  touch, at rest and after Show all, in Chromium drawing its scrollbars and in WebKit: no group heading on two
  lines, no word under its heading, and wherever Pinned and To do sit side by side their headings and cards level to
  the pixel. The narrowest rail 334-335. Two across from a pane of 752 (764 with the scrollbar; a window of
  1080-1096 docked), a desk from 1108 (1120; 1492-1504 docked). Against the first pass's build the same sweep found
  "To do" on two lines at 1012 wide with touch and 1024 with a mouse, at rest, and on past them after Show all, the
  rail at 304.
- **The states**, one seed each, at 880 × 664 (the Fold) and 1280 × 900 undocked: two pinned, a row of two with To
  do across under it, 831 wide and 188 tall with five rows in two columns, the card's ground over the crease and no
  row within 24.5 of it; no Pinned, To do across first at 880, and at 1280 level with the Tapes (read first, above);
  every to-do ticked, the ghost's card in unit 2 (391 × 337), still paired, and in the rail (392 × 436); no to-do
  ever, the one pinned card in unit 1 at 880 and at 1024, and a desk of one column at 1120 (cards 3 × 343, tapes
  252), 1280 (3 × 395, tapes 291), 1600 docked (3 × 374, tapes 275) and 1812 (3 × 412, tapes 304); nine tapes, two
  rows of four on the units, the eighth's edge on unit 2's (855.5), and three, three and two at 1280, with "· 9" and
  See all; the Academy card held to unit 1 (415.5) and to the main (809.4); a workspace chosen, the pills across; no
  notes, the ghost's right edge 49 from its words at 880 (the crease 25 from each), 50 at 1024, 53 at 1280 and 55 at
  1812 (515 at 1280 and 1812 before).
- **Show all's heading**, at 880: 247.9 before and 247.5 after, the page scrolled 353 as the card spread under the
  pinned card; Show fewer puts both back exactly; the same at 1024 (213.2, the page to 360) and at 1440 docked
  (227.9, to 383). With forty-five to-dos, forty rows in two columns and "and 5 more in your notes". At 1280 and at
  412 the heading does not move and neither does the page.
- **Ticking the list off**, Show all pressed and the first box ticked six times: at 880 the heading stays at 247.5
  through five ticks and is at 247.9 after the sixth, which puts the card back beside Pinned, the page from 353 to 0
  (the first pass: the heading to -105 under the bar, the page left at 353); at 1024, 213.5 to 213.2 (360 to 0);
  1280 docked, 222.3 to 222.2 (374 to 0); 1440 docked, 227.5 to 227.9 (383 to 0); WebKit at 880 and 1440 docked
  within 0.6. At 412 the page does not move and the heading comes up 4.3 as its row loses "Show fewer", as main's
  does.
- **One frame of the counts.** A second size observer on the column, made after the page's, read the counts in the
  same delivery: from 1100 to 1140 wide and back it saw 1049 with four Recent cards and five rows and 1089 with six
  and eight, every time, in both engines; the sidebar's toggle at 1440 the same (1006 and 1280). Against the first
  pass's build, across its own line (1000 to 1040), it saw 990 with four and five before six and eight.
- **All notes**: at 412 as main's, to the pixel (above); at 1600 and 1812 docked its 60rem column (x 510 and 616),
  four across of 228, as 1.8.0-20.
- **Light and dark**: every measurement the same in both, at all 37 sizes.

**Put right after the review.** Three reviewers' findings, verified in the browser before any change:

- **Ticking in place broke on two columns** (found three times): the tick from six to five ended the spread, the
  pair rule matched again and To do went back beside Pinned with nothing holding it, the heading 353px up under the
  bar and the next tap on the Tapes. Now the pair is the page's own state, `paired`, and every press on the card
  holds its heading (above).
- **"To do" on two lines at the desk's foot** (found twice), and **the desk too early** (a 1024 tablet turned
  landing on the desk at its thinnest, a 298 card, 318 of nothing and a 308 rail): the desk's line to 66rem, where
  the rail is 335; and a heading never breaks past 44rem.
- **One frame of the phone's counts** when the column crossed the desk's line: the observer's answer committed at
  once.
- **The empty page's words 515px from the ghost** on a desk: the ghost at its column's end.
- **All notes at 80rem** made its cards smaller and more of them on a big window, a change to a page Matt did not
  ask about: back to 60rem.
- **The desktop numbers** were measured with Chromium's scrollbars hidden, 4-12px off the Mac's: the rows above give
  both.
- **Tests that could not fail**: the review broke the sheets sixty ways and fifty-one stayed green, and five breaks
  to the page's code did too. The tests below now pin what can be pinned without a layout.
- **Lower the wide line to about 40rem**, so docked tablets and the docked Fold leave the stack: measured, and left.
  A docked 1024 tablet's column is 666, units of 308, and To do's row there needs 304.6: three pixels to spare in
  the headless engines, and none where WebKit set the heading 4px wider for the reviewer. The docked Fold's columns
  (521-610) would need 653 for units that hold the row, so no line that keeps it on one line reaches them; the
  docked Fold needs the `.app-split` follow-up either way. Left undone, with the question of whether Matt runs the
  Fold docked.
- **The tapes' line not settled**: the Fold was not attached (`adb devices` listed none), so its width is still
  unread. The line stays at 50rem, called provisional here and in TapeShelf.module.css, with both one-number
  fallbacks.
- **The desk's dead space** (a lone pinned card half a row wide; the rail's third empty once To do scrolls past; the
  main beside a tall rail): a sticky To do and a lone pinned card placed otherwise are both layout choices for Matt,
  not defects; left undone, with the shots.

**Tests.** home/tiers.test.ts: `tierOf` either side of 44 and 66rem at a rem of 16 and of 20; `CAPS`; both sheets'
`@container home-page` preludes hold only `LINES`' numbers, and each of them; the exact questions (from each line,
and between two, never at one), and the shelf a grid only from its own line; nothing for the phone: no rule for the
grid, the head or the notices, or naming a group's place, outside a question of the page; the column the page's
container, its cap past the desk's line and the dock's line past the cap; the groups placed by the names
HomeScreen.tsx writes, `[data-paired]` only on `.grid` and the page writing it there, the desk's areas in the page's
order (and one column in it with no To do), every group in the area of its own name; the tapes' placements only in
the 50-66rem block; `--home-units` and `--shelf-across` declared in the home page's sheet and read with fallbacks of
1 and 3. HomeScreen.test.tsx: the sections named in the page's order with their ids; the head, the groups and the
foot as the grid's children, the date, the digest and the notices in the head; the pair only while To do is not
opened out, again after a tick down to five, with the ghost's card, and not with two pins, no To do or no pin; the
held heading, with the layout told (300 beside Pinned, 520 under it), for Show all and Show fewer, for the tick that
puts the card back in the pair, and not where nothing moves; the column read on mount at 1100 wide, before any
report: six Recent cards, eight rows with "Show all 11" and the shelf's eight of nine with "· 9" and See all (that
the read comes before the first paint is the hook's and the browser pass's to show: jsdom paints nothing); seven
to-dos on a desk, all shown and no Show all; the column told 800, 1100 and 800 again, and the counts following; at
an interface size of 125% the lines at a rem of 20 (1100 and 1300 two across, 1400 a desk); the observer let go with
the page. Twenty of the review's breaks, re-made (the hold keyed on Show all or left off a tick, the pair blind to
the spread, a fixed rem, Show all at five, the head's or the notices' class dropped, a phone rule for the head, the
container renamed, the cap at 60rem, the dock's line at 70rem, the desk's areas reordered, To do's area dropped, a
group's name misspelt in either of two places, either fallback changed, `<=` in a range, the tapes' grid from 44rem,
the pair's attribute renamed), each fail a test. The tracks, the gaps, the head's caps and the hinge's clearance can
only be seen laid out, and are proved by the browser pass above, not by the suite. The existing tests unchanged:
jsdom's rect is 0, the stack. stylesheets.test.ts as it is. tsc, eslint on the touched files, vitest in full (3259
passed, 123 skipped).

**Left undone.**

- The Fold's real CSS size: two readings disagree (2448 × 1848 at DPR 2.625-2.8125 is 870-933 wide with the hinge
  down the page; the task's 1812 × 2176 is about 800 wide), and the tree declares no density. Settings › Developer ›
  Window, or `adb shell wm size` and `wm density`, decides it, and with it the tapes' line: 50rem as it is (the 880
  shot), 57.5rem for the phone's full-size tapes on every Fold, or about 46rem if the Fold reads 800 wide (the 800 ×
  960 shot).
- Whether Matt runs the Fold docked (§132's seed says so). Docked, this branch changes nothing on his Fold: the pane
  is the stack, and the hinge runs through the first card column until the `.app-split` follow-up (above). A docked
  tablet turned (column 666) stays the stack too, for the heading row's sake.
- The desk's air: a lone pinned card is half a row in a main two cards wide (1280: 381 of card, then 402 of nothing
  before the rail), and once To do scrolls past, the rail's third of the page is empty to the foot. A To do that
  stays in view in the rail while it is not opened out (`position: sticky` under the bar) and a lone pinned card
  across the main are both Matt's to choose, from the 1280 × 900 and the 1600 × 1000 docked shots.
- All notes' column: 60rem while the home page's goes on to 80rem, so the foot opens a narrower column on a desk; at
  80rem §121's grid would be six across of 200.
- To do's tick boxes at the crease: in unit 2 they sit at x ~485 of 880, just right of it. Mirrored to the row's end
  they would be at ~815-835, inside the dock's band (x 796-860) as the page scrolls, and away from the editor's
  box-first line, so it is left to Matt on the device.
- The pills row, not held to a unit: past about five pills it runs over the crease like the tapes' row.
- The tapes in a desk's main, three across, not on the cards' two columns.
- All notes' own empty-state tracks (3fr/2fr), and the tape's ground still written out three times (§132).

Cites: §21, §29g, §53, §66, §84/§97, §92/§110, §121, §127, §132.

## 138. Settings, streamlined: five rows on one screen (2026-09-28)

Matt, with the "hey Ghost" removal: "also see if you can clean up / streamline settings a bit". Designed read-only
against 891f3cd (1.8.0-20) from an inventory of every row (36 shots at 412 × 915), two proposals and a judged pick,
then built on branch settings/tidy against 60716fa (1.9.0-1), after meetings/page (§127), notes/geotag (§134) and
voice/no-keyword (§136) had put their rows on these pages. Where the design and the tree differed, the tree won
(below). Numbered 138, the next free number at the end: §133 is taken, and §135 is a gap left as it is.

**What was wrong.** Twelve rows on a phone, two screens tall, fourteen in developer mode, three of them plugins with
their own pages. Type and Appearance each held a size dial, one described only by how it differed from the other.
Location was a page of three switches (lime), Feel a page that had just taken in Animations (§136). Local only, the
whole network switch, was filed under Formatting, and two pages sent people there "in Formatting". Each downloaded
model was listed twice, in two cards with one title. Two rows opened the same walkthrough, one named for voice cues it
did not show. The Summaries segment's middle label did not fit at 412. About's Help card was eight rows, five of them
"Add …". Sidebar, a choice App.tsx reads only on a wide window, was drawn on a phone too. Every search list was kept by
hand in SettingsSheet.tsx, away from the rows it named.

**The shape.** Five rows on a phone: Account · Appearance · Recording · Plugins · About, in cards [Account] ·
[Appearance, Recording, Plugins] · [About], with Developer and Test results on a card of their own in developer mode.
Recording is listed where it was (Android, and the Mac app), so the web and iOS see four. Every row keeps its live
line. The pages that went are cards: Type (with the "Aa" sample in its head, in the note's own face), Motion and
Touch on Appearance, which is the one page a person enters to fiddle with looks; the model on Recording, beside the
summaries and the review it writes; Privacy (Local only, Link previews, the policy and its two lines) and Location on
Account, beside sync and shared links, the other things that send. Notion, GitHub and Claude are sub-pages behind
their Plugins cards, the cheat sheet and a new Examples page (the four Adds) behind About's Help. A sub-page is off
the list, still searched, wears its parent's name in the head ("← Plugins", "← About"), and back steps there first;
in the split view its parent's row stays current, the head names the parent there too, and back steps to the parent
before it leaves. Hues: Account blue,
Appearance purple, Recording red, Plugins green, About grey, Developer brown, Test results mint; the sub-pages keep
graphite, coral and yellow. Indigo, orange, teal, pink and lime went with their pages.

**Reconciled with the tree.** *Location* is one card on Account after Privacy, the page's three switches, its
refusal footnote and its platform words as they were. "Tag new notes with my location" stays on the device and out of
the sync list (the geotag review's call, §134: one device's choice must not make another ask for its position), where
the design had it as a synced row in Privacy. It follows Privacy, and both follow the account's own cards, signed in
or out (below, "After the review"). *Feel* was already
one page (§136): Appearance's Motion and Touch are FeelPane as merged. *Meetings*: "Tell me when a meeting is written
up" is the row as built (Allow, then On: the permission is the host's, not a preference), and Write up is the switch
"Write up straight away" over the same two stored values, off "charging" (the default) and on "now", synced as
before, so nothing migrates. *Tapes*: the room the tapes take is the card's footer, a readout under its group, and the
row is "Remove audio older than a month" with Remove, then Tap again; on a binary before generation 20 it is held
with "Update Ghost.md to remove audio here.", once the binary has said which generation it is. *The hey-Ghost row* had already gone (§136). *Link previews* moved from
the Type page to Privacy.

**What went.** Developer's Set-up card: "Choose your model" was the walkthrough's model page alone, the Model card's
choice, and "Welcome guide" exactly About's welcome walkthrough (`GUIDE_MODEL_PAGE` went with them). Formatting's
second "On the phone" card, and Remove on the model in use: the one in use has no Remove, so nothing switches the model
behind a person's back (`fallback()` went), unless it is the only one here, where there is nothing to pick first. Formatting's web and iOS invitation to another store. Sidebar on a phone.
Size's paragraph about Text size. Local only's second hint. The three Play the scene rows, now a Readings choice and
one row. The "Swipe left to go back into …" line: the swipe stays, the sentence goes. About's Privacy card and footnote
(a move). The hand-kept search lists (a move, below).

**Renamed.** Recording's "The side key" over quiet and the review → "While recording"; "Where the side key is" →
"The side key", last on the page. "How to talk to Ghost.md" → "The welcome walkthrough", with a hint that names what
guide/pages.ts shows (the palette's command too). "Formatting cheat sheet" (About) → "Cheat sheet"; "Add Ghost.md:
The Guide" → "Ghost.md: The Guide". Appearance's "Size" → "Scale", beside "Text size". The Summaries segment → three
picks with a hint each. "Write up" → "Write up straight away". "Your tapes" → the card "Tapes". Developer's line
"Set-up, reset" → "Benches, reset". Plugins' hero loses its dashes ("not its rows, its commands or its page").

**The readings.** Account: the sync line, and " · Local only" while it is on. Appearance: the page and the note's
face, then only what has moved off its default (text size, interface face, accent, spacing, corners): "Dark · Maple
Mono". Recording: the model that writes a take up, then what a take becomes: "Qwen3.5 4B · better words", or "Qwen3.5 4B,
2.7 GB to get · words as heard" where it is not here, which is Formatting's line until now. It was §136's "Review ·
better words · meeting summaries". It was built as "Better words · Qwen3.5 4B on the phone" and lost its end in the
split view's 20rem column at 1280 and 880, so the model comes first and "on the phone" went. The cheat sheet's line is "Every mark you can type": it promised
every cue, and the sheet shows none.

**The mechanism.** `SettingsSection` gained `listed` and `parent`, and where a step goes is settings/sectionSteps.ts,
pure and tested alone. `goTo` gained `setting`, looked for on the page as a search hit is, scrolled to and lit: the
home page's "Get a model" and the digest's phrase open Recording at the Model card (App.tsx `toFormatting` is
`toModel`), and "Local only" in the Plugins callout, a held plugin's row and the signed-in Account callout is a word
(settingsKit `GoWord`) that opens Account at the Privacy card. Each page's search list is a `findable` in a `.ts`
beside it (`AccountPane.findable.ts` and the rest: the lint's `react-refresh/only-export-components` keeps a list
out of a component file), a plugin's on its `settings.settings`, so Notion's, GitHub's and Claude's pages are
searched for the first time. settingsSearch.ts did not change. No preference key, default or sync entry changed.

**Every search word kept.** SettingsSheet.test.tsx renders every page, hidden ones and plugin pages too, in a browser
signed out, on Android in developer mode signed out, on Android signed in, and on the Mac on a wide window signed in,
and fails on a name its page does not draw unless ELSEWHERE says why (a shared link, the form's own mode, update
alerts, the meeting service, Notion in the app or signed in). It searches every word main's 58 entries had (their
names and words, on Android in developer mode, signed in and out, narrow and wide) and fails on one that finds
nothing, and lands 26 old names on their new places ("formatting" and "choose your model" on Recording › Model,
"location" on Account › Location, "animations" on Appearance › Motion, "hey ghost" and "welcome guide" on The welcome
walkthrough, "boards" on Notion's page, and so on). That is the claim on Android, where every setting is. Each other
device is searched on its own too, and finds nothing only for a setting it does not have, each named in the test:
Recording's words where there is no recorder (a browser on a computer, an iPhone), the side key's off Android, the
meetings' outside the Android app, the tapes' and the model's where there are none, the haptics' where there is no
motor, and What's new's on an iPhone, where the App Store says it. A few of those found a page before that had nothing
of theirs on it, and find nothing now: Formatting's "ai", "download" and "llm" and Developer's "Choose your model" in a
browser and on an iPhone, Feel's "vibration" in a browser and on the Mac, and in a browser on an Android phone the
meetings' and the tapes' rows, listed there and never drawn. The contract runs in a browser on an Android phone and
on an iPhone as well, and the meetings' and Notion's pages, which the sheet's test cannot draw whole, are checked
against their lists in their own tests.

**Measured** (the built page in headless Chromium, 412 × 915 at 2.625, the Android app and the Mac app stubbed
through `__TAURI_INTERNALS__` with native generation 20, no network; scratchpad/settings/after, shot again after the
review, and after/fixes for what the review changed). The list ends at 627 px on Android in developer mode and 479
without (seven and five rows), 562 and 414 on the web (six and four), 671 and 523 in a narrow Mac window under its
title bar: one screen with air under it, where it was two. Account signed out is 1991 px: the ghost at 123, Sign in's
title at 467 and the form at 579, all on the first screen; Privacy at 1017, Location at 1479. On the Fold opened out
(880 × 790, the split view) Sign in is at 471 and the form at 567. It was built with Privacy first, 2011 px with Sign
in at 948, below the fold. Signed in, 1857 px, Privacy at 776. Local only's hint is four lines at 412, five before.
Appearance is 3473 px on Android, eight cards. Recording on Android is 2163 px (While recording 123, After recording
384, Summaries 535, Model 860, Meetings 1380, Tapes 1621, The side key 1781), 1511 on the Mac, which says "this Mac"
five times and "the phone" none. The Model card's Remove is 16 px, as Get is, and 13 px clear of the radio (it was
13.4 px text, 4 px away), "Tap again" after the first tap. Recording's line in the split view's column, "Qwen3.5 4B ·
better words", is whole at 1280 and at 880. In the split view GitHub's page draws on the right with Plugins current on
the left, "← Plugins" in the head, and the head steps to Plugins, then says "← Settings". A card a link lands on, read
every 40 ms for 2.6 s: lit until about 1.6 s, and its opacity never under 1 once it has risen, where it fell to 0 at
1.64 s before. Searched at 412: "haptics" finds Appearance › Haptics, "location" Account's Location card and its tag
row, "model" Recording's Model card (and Reset everything, by its word "models"), "cheat" the sheet alone, "tapes"
Recording's Tapes card, "examples" one row, "privacy" the Privacy card first; each hit opens the page with the card or
row lit. With Local only on, its word on Plugins lands on Account with the Privacy card lit, signed in or out. About ›
Examples, back three times to close, and Settings opens again on the list.

**After the review.** A look pass and a code pass, each on its own build, found three things to put right before it
shipped and a list of smaller ones. Signed out, Privacy first put Sign in on the second screen at 412 × 915 and off
the Fold's opened screen, with the ghost between the two privacy cards: Account is now the ghost and the way in first,
then Privacy and Location, signed in or out, and the Local only callout is back signed out (main had one), its word
lighting the card below. The Model card's Remove sat 4 px from the radio that picks the same model and deleted a
gigabyte file in one tap: it asks twice now, Remove and then Tap again, as the Tapes card's does, at the row's size
rather than the value's small text, and held off the radio. Every card a link or a search landed on blinked 1.6 s
later: `[data-found]` had swapped the card's arrival animation for the light, so the arrival ran again when the light
went. A lit card keeps its arrival in its list now (settings.css, read by SettingsScreen.test.tsx since the tests run
with CSS off). And a fresh open landed on the last page a link had opened, a bug main had for the cheat sheet and the
plugin pages that this change had widened to every sub-page and every "Local only": the screen answers each request
once, by its nonce. Smaller, each with a test where one could say it. The model in use has Remove when it is the only
one here, or its gigabytes could only be freed by getting a second model or resetting everything, and In use is the
model that runs (`modelFor`), not only the chosen one. The split view's head over a sub-page says its parent and steps
there, as back already did. Recording says "this Mac" on the Mac, as its Model card does. The model hints lost their
semicolons. The search shows a sub-page once, by its own name, not About's row for it as well; "privacy" opens the
Privacy card first ("Sync meeting recordings" lost the word); What's new and the meetings' rows are listed only where
they are drawn; "where the side key is" finds the side key again. Local only's hint no longer lists the Location card's
three, which say it under their own rows. The Tapes row says nothing until the binary has answered. The callout's
"Local only" is a plain word while a password or delete form has the card off the page. The walkthrough's model page
offers nothing to get on an iPhone, which runs no model and has no Recording page to point at. The stale page names
left in chapters 03, 04, 05, 09, 16, 22, 37, 41 and 44, the smoke bench's callout and the More sheet's cheat sheet hint
are put right. A browser can switch Local only now, where Formatting drew only its empty state: a new switch for the
web, and its hint says what a browser holds off. Not taken: the cheat sheet opened from a note still says "← About"
and steps there, and "Local only" from Plugins lands on Account, whose back is the list, since back goes to a page's
parent and the head says so (§2 of the design); Link previews stays live under Local only, since its switch also says
whether a link's card is drawn at all (editor/linkCards.ts) and only the title's fetch is held; and the Examples rows
keep their "Add the" labels, the longest wrapping to two lines at 412.

**Left for Matt.** Privacy as a card on Account after the ways in (the look pass's call), before them (the design's),
or a sixth listed row (the design's fallback), decided on the Fold with the after/ shots. "Write up straight away"
inverts the meetings spec's wording. The More sheet's
"Formatting cheat sheet" (editor/NoteSettings.tsx, core/sampleNote.ts line 203, chapter 01) could say "Cheat sheet" as
the palette, the Academy and About do: not done without a yes. "Summarize" stays as the strip spells it. Older than
this and seen in the pass: the chosen Scale card's "Default" is drawn in the card's own ground, invisible in both
themes (ScaleCards.module.css); "Settings > Updates" in Notion's and the reset's messages names a page that became
About's card long ago. landing/privacy.html now says Settings › Account for link previews and location, and needs a
landing deploy to go live; the manifest's comment (src-tauri) still says Settings › Location and was left, since only
the page's code changed.

**Tests.** sectionSteps.test.ts; SettingsScreen.test.tsx (a sub-page off the list, found by the search, opened from
its parent, back and the swipes by depth, the split view's current row and back, a target lit and lit again, the
freed hues); SettingsSheet.test.tsx (the lists, the sub-pages, the targets, the readings, the contract in four states,
every old word, the landings); AppearancePane.test.tsx (was FeelPane's), ModelCard.test.tsx (was FormattingPane's),
PrivacyCard.test.tsx, LocationCard.test.tsx (was LocationPane's), RecordingPane.test.tsx (the cards in order, the
picks, the switch over `writeUp`, the Tapes footer and the held row), AccountPane.test.tsx, AboutPane.test.tsx,
DeveloperPane.test.tsx, PluginsPane.test.tsx, settingsSearch.test.ts's fixture, App.test.tsx, Model.test.tsx. The
guidebook's chapter 24 is rewritten, and chapters 01, 03, 04, 05, 06, 09, 13, 15, 16, 18, 19, 22, 23, 25, 26, 30, 32,
37, 41 and 44 say where each setting is now. After the review: a fresh open lands on the list, the split view's head
over a sub-page, a target lit once per request and in the split view, the lit card's arrival read from settings.css
(SettingsScreen.test.tsx); an Android browser and an iPhone, the contract in both, each device's search losses by
name, "privacy" first, a sub-page found once, the Account callout's word, Examples in yellow with its four handlers
(SettingsSheet.test.tsx); the order signed out and in, the callout signed out, the word held while a form is open
(AccountPane.test.tsx); two taps, the only model, the model that runs (ModelCard.test.tsx); the Mac's words, the
unknown generation, the meetings drawn against their list (RecordingPane.test.tsx); Notion's page against its list
(NotionPane.test.tsx); the device-only line and no refusal under Local only (LocationCard.test.tsx); the iPhone's
model page (Model.test.tsx).

Cites: §21, §29g, §101, §103, §106, §127, §132, §134, §136.

## 139. The page spans the window: two more desks past the cap (2026-09-28)

Matt: "On desktop there is a limit to the width of the body content but it should allow content to span 100% of the
app window".

A note already did: its editor ran the pane's width. The home page did not: `.page` was a column capped at 80rem
(1280px) in the middle of the window, and All notes' at 60rem. Both caps are gone (`HomeScreen.module.css` and
`AllNotesScreen.module.css`, `.page`), so each page spans the pane less its gutters.

The cap was there so a card would not become a banner, and §137's desk depended on it: uncapped, the desk's main two
cards across would be about 570px each in an 1800 window. So the home page gains two tiers past the desk
(`home/tiers.ts`, the container queries in `HomeScreen.module.css`):

| Tier | From | Main | Rail | No To do | Recent / to-dos |
|---|---|---|---|---|---|
| desk (§137) | 66rem | 2 cards, 3 tapes | 1fr of 3 | 3 cards, 4 tapes | 6 / 8 |
| broad | 88rem | 3 cards, 4 tapes | 1fr of 4 | 6 cards, 8 tapes | 6 / 8 |
| vast | 120rem | 4 cards, 8 tapes | 1fr of 4 | 8 cards, 8 tapes | 8 / 10 |

Every count keeps §137's rule that a row is whole: six Recent cards are two rows of three or one of six, eight are two
rows of four or one of eight, and the shelf's eight tapes are two rows of four or one of eight. The broad line is 88rem
because that is where its rail, a quarter of the page, reaches 342px, room for To do's heading, count and word (§137's
294-305).

Measured in the preview, sidebar hidden:

| Window | Page | Tier | Recent cards |
|---|---|---|---|
| 412 | 367 | stack | 1 across, 367 (unchanged) |
| 1280 | 1215 | desk | 2 across, 377 |
| 1440 | 1374 | desk | 2 across, 429 |
| 1600 | 1533 | broad | 3 across, 355; no To do, 6 across, 237 |
| 1800 | 1745 | broad | 3 across, 408 |
| 2560 | 2493 | vast | 4 across, 441; no To do, 8 across, 294 |

All notes keeps §121's grid, so it simply fits more: eight across at 204px in an 1800 window.

The heading rows' clearance from the dock (§137) was asked of the pane's width, at 92rem, because past that the dock
stood clear of the capped column. With the page spanning the pane the dock crosses it at every width, so the
clearance is a plain rule now, and the `home-pane` container it asked is gone. The phone is untouched: under 44rem no
tier applies, the cap never reached a phone's column, and the clearance already applied there.

## 140. Typed text appears at once; deleted text still smokes away (2026-09-28)

Matt: "Don't ghostly fade the text in I want text input to be instantaious we can show the ghostly fade away when
deleting though still".

With Ghostly typing on, every letter typed used to arrive out of smoke (`editor/wispMotion.ts`), and a paste
animated its first forty letters. So for a moment a letter that had been typed was not yet there to read. Now the
typing path sets no arrivals: what is typed or pasted is drawn as it lands. The `PASTE_MAX` cap went with it.

What still moves:

- **What is taken out by hand.** A word or a selection deleted at once smokes away where it stood, quickly, and quicker
  in a run of backspaces. So does the text a typed letter replaces. A single backspaced letter still just goes,
  as before.
- **A tapped box's mark** (`input.toggle`, `input.choice`) dissolves in and out where it stands. A tap is not typing.
- **Words that were not typed:** the recorder's heard and rewritten words, the AI's lines as they land, and the
  review's findings, all with the `wisp` annotation. Also the quick reveal of a note's text as it opens.

The setting keeps its name. Its hint now says what it does: "Words you say arrive as smoke, and words you delete leave
as smoke. What you type appears at once." The Guide's chapters 24 and 30 say the same.

## 141. A + beside the line, and a short list of things to add (2026-09-28)

Matt: "Add a + button next to the line we're typing in, in the empty gutter padding and add a menu to add things like
geotag cards images videos and more."

Then, of the four questions the design left him: a place is "a map card at the line, many per note"; the list is
"Fuller but hide extras behind nested menu"; the + shows on "EMPTY LINES ONLY, on every platform, Mac hover included";
and the journal's entries, which are §142's, are titled by the minute.

**One +, beside the caret's empty line** (`editor/insertPlus.ts`, the rule in `editor/plusLine.ts`). It sits in the room
every line already leaves before its first letter, the gutter (`--app-gutter`, 22.4px on the phone, 24.5 on the opened
Fold, 26.3 on the Mac): two strokes in the third ink, 12px, no ring, since the app's ring is wider than the phone's
gutter. Its target is that line's gutter and no more, so a tap in another line's gutter, or on this line's first letter,
still lands where it did. An empty line is one with no words (`core/itemSyntax.ts` `lineWords`): blank, or only a
list's, a to-do's or a quote's lead. The + comes once the caret has rested there for 150ms, so Enter, Enter in a run
never flickers it, and the first letter typed makes the line one with words and takes it away at once. It arrives on
typing's arc, 350ms and a 2px lift, and leaves on a deleted letter's beat, 140ms; one that had not finished arriving
goes with no fade. It is never drawn in the front matter, in fenced code, on a selection, in a view that cannot be
edited or has lost the focus, on a notebook's index or a canvas, over the transcript, or while an AI run writes into the
note. Only the note screen asks for it. Nothing about it waits for the keyboard to finish composing a word: showing and
hiding it touches no line. A change that leaves the caret on the same empty line, a space or Enter ending an empty item,
leaves it where it is rather than blinking it out and back. It sits level with the row's words, inside the border a
quote's last line carries below them, and it is placed before it is seen, not in the next frame, which a busy thread
paints late. Beside a lead it is drawn smaller and at the gutter's outer edge, 10px from 2px in, or it and a list's dash
read as one, "+-". Its line carries `cm-plusLine` while it shows, which fades the bookmark's gold edge in the same
gutter, and the class is changed only while nothing is being composed.

**The press keeps the keyboard, and the focus.** The + is a button in the scroller, outside the lines, so none of
CodeMirror's handlers see it, and its press is the suggestion pill's rule: a pointer or mouse press has its default
taken away, a touch is only kept from the editor (a prevented touchstart never becomes a click on Android), and a long
press never reaches press and hold. A tap or a click turns it into a × and opens the list against its row. The editor
keeps its focus, and the list is driven from the editor's keys at the highest precedence, as CodeMirror's completion
list is: Up and Down move the lit row, Enter chooses, Escape closes, Left goes back from More, Right goes into it, and
the lit row is named to a screen reader by `aria-activedescendant`. The lit row wears the kit's ring only once a key has
moved it: lit by the pointer, or first as the list opens, it has the pressed paper alone, or the ring would follow the
mouse. Any other key closes the list and does what it always does; so does any change or caret move. Tab reaches the +
from the editor even while it waits, taking the focus shows it at once, and Enter on it opens the list with the focus on
its first row.

**The list** (`editor/AddList.tsx`, the rows in `editor/addRows.ts`). A short card in paper-2 with press and hold's
hairline and shadow, rows 2.75rem tall with an icon in the third ink and the words in ink, and no hints but a dimmed
row's reason. It opens below the +'s row, above it when the keyboard leaves no room below, and on the larger side,
scrolling with a fade at the cut edge, when neither holds it all; never over the row, and clear of the top bar and the
tabs. More, at the first page's foot, and Back, at the top of More and of a step, are held outside the rows that scroll:
on the phone with the keyboard up there is room for six or seven rows, and More was the one under the fade. Its left
edge is the text's. On a coarse pointer 600px and wider it keeps to one side of the window's middle, the Fold's crease:
at the text when it fits before the crease (or when at least 12rem does), else 16px past it, and across it only when
neither side has 12rem. It does not close on a scroll: the keyboard rising shortens the page and the editor scrolls the
caret into view, so the list follows the + in one frame, and closes only once the + has left the screen. It closes on a
row chosen, a press elsewhere, a wheel or a drag outside it, Escape, the back gesture and the ×; on More or a step, the
back gesture goes back a page first, as Back and Left do. It is not a sheet, which takes the page and the keyboard, and
not press and hold's sideways band, which reads as a toolbox. (Since §197, when it opens above it goes over the top bar
and the tabs, as far as the status bar.)

**Seven things, then More.** A picture, A video, A place, the time as it will be written (Matt's example was "28 Sep
2026, 14:05"; the month is the locale's own short form, as a meeting's title's is, so a British phone writes "28 Sept
2026, 14:05" and an American one "Sep 28 2026, 14:05"; `core/stamp.ts`, the day and the short month in the locale's
order, the year, a 24-hour clock, the one copy §142's journal shares), A table, A note (a step inside the list: "Which
note?", part of its title, at most twelve), A to-do, and More. More turns the list over to a second page in the same
card, Back at its top: a heading, a bulleted list, a numbered list, a quote, a callout, a choice, a block of code, a
divider, a board (as Make a board writes one: To do, Doing and Done, and a first card named by an anchor nothing else
has), a chart (the canvas's own Mermaid seed), a canvas drawn in a frame (a step, "Which canvas?"), a footnote (the next
number closing the words just above the empty line, as the Guide writes one, its line at the end of the note; alone on a
line it was a footnote to nothing), a tag, a counter ("Count [0/8]", the name selected), a sum, and each effect that is
switched on, named as it is said ("Heated words") with a word between its marks to write over, since its marks alone
drew four emoji and no effect. Each comes with a seed to write over. The marks that wrap words (bold and the rest) stay
Style's: on an empty line there are no words to wrap. A voice memo is not offered, since the recorder no longer makes
them, nor a web link, which is pasted.

**A row is there, dimmed or not there, by one rule.** A row this device or this build can never do is not drawn: an
over-the-air page on an older binary shows nothing it cannot do. A row a choice the person made stands in the way of
is drawn dimmed with the choice named, which today is Local only, for a place; a press on it adds nothing. A refusal
found only by trying keeps the row and is said when it happens. So the Mac has no place (its WebView never answers a
fix) and no picture until its picker has been run on a Mac (`MAC_PICKER_TRIED`), the iPhone app has no place (it
declares no location permission, and `canLocate` now answers `ios` before anything is asked), and only an Android
binary of native generation 21, whose bridge has `pickVideo`, has a video row: the note screen asks once as it opens
(`core/videos.ts` `canAddVideos`).

**Where each goes** (`editor/inserts.ts`, docs/MARKDOWN.md). Drawn things (a picture, a place, a film, a canvas's frame)
get a line of their own: they take the caret's line when it has no words, lead included, and otherwise go after it, and
a blank line keeps them out of a list, a quote or a table above. A place, a film and a frame are links, and keep a blank
line from a paragraph above as well, or another reader runs them into its sentence, "Lunch at the harbour Cais do Sodré,
Lisbon"; a picture under a paragraph stays on the next line, which every reader draws as a picture of its own. Blocks
get a blank line on either side where words are. Words go at the caret, spaced as a sentence needs. A to-do, a list, a
heading or a sum is a line's lead, written on the empty line, turning an empty item's lead into its own, never a second
box. Each insert is one transaction with its history isolated, so one Undo takes back exactly it, and what the + writes
is there at once, drawn lines whole, as typing is since §140: its user events (`input.plus`, `input.plus.drawn`) set
nothing in motion, and the empty lead a picture takes the place of just goes.

**Found on the way, and mended by the same rules.** A picture from Add image, from a paste or from the + under an empty
to-do was the to-do's words; under a list item, a quote or on the empty line under a table it joined them. A table from
Style took the next line of words as a row. A rule from Style under a paragraph read as a heading in Obsidian and on
GitHub, though never in the app, whose parser has no setext headings. All now leave a blank line where it is needed. And
Add image on the Mac asked for the phone's picker, which it has not got, and only ever said this build cannot add
pictures: the Mac takes the page's file input now, which WebKit answers with its open panel. The panel holds to no
filter, so a file that is not a picture is refused in words, a HEIC an older Mac cannot open says to save it as a JPEG
first, and the shrink asks again without its turning option when an older WebKit refuses the option. A chart, one tap
away in More now, drew in Mermaid's lavender on a light page: it draws in Mermaid's grey (`neutral`) there, the app's
two inks, as it already did on a dark one.

**A place is a line.** `[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)`, a plain link to a `geo:` address, alone on its
line (`core/placeRefs.ts`): four decimals, or two for a rough fix. It draws as the map card under it
(`editor/placeCards.ts`), without the place chip, since the line says the name, and folds to its name off the caret.
The note screen draws it live, a shared page quiet until the reader asks, and every other editor (a note drawn small, a
notebook read straight through) draws no card, since nothing there may fetch. The note's own tag stays in its front
matter with its card at the top, and a note can hold many places. The fix is found as Add my location finds it, "Finding
where you are." after a moment. The name is asked while the fix is found, from what is known first
(`core/location.ts` `placeName`), and waited for three seconds, so place and name land as one write and one Undo. This
changes the letter of the location module's second rule, which asked only for a tag already in its note: a place
pressed with the + is asked for while its note is open and its spot is kept, since the person chose these coordinates
and this note seconds before. A note left, or a place let go, before the fix sends nothing. A name later than the wait
is written only while the place is still the newest change the note's history holds and nothing waits to be redone, so
an Undo never takes back a name in place of what the person just did. The note's own tag is not the person's doing. In
a new note under Tag new notes, or an entry whose journal keeps where it was written, the tag waiting for the first
words lands just after a first insert from the +, as it does after typing's first letter (§134), a step of its own and
its name another: there the first Undo takes back the tag's name, not the insert, and a late name is still written,
since the steps the tag took are counted apart (`tagSteps`). Add my location and Remove location from the sheet are
the person's, and keep the coordinates. A write that lands after the person has gone to another field (the Find bar, a
sheet) takes no selection, no scroll and no focus. Local only takes the fix, the name and the tiles.

**Shares: a switch of their own.** A share leaves out every `geo:` address in its pages' words, in whatever form it is
written, unless "Share the places in it" is ticked (`Kept.places`, docs/SHARING.md). The tag's "Share where it was
written" keeps its row and its words exactly, so no tick anyone gave grows to cover places added later. The Copy the
link hint names in one sentence what the link carries of each.

**AI runs keep places whole.** A place's line, and a video's, goes to the model as a picture-shaped token,
`![place-1](place)`, as a table does, and comes back verbatim (`format/embeds.ts`); every prompt that names the table's
token is told of these in one sentence, and a summary may leave one out. A model can no longer move a place's
coordinates or describe it.

**A video stays on its phone** (the second slice, native generation 21; `BUNDLE_REQUIRES` stays 19). The line is its
poster linked to it, `[![video 0:12](image/<poster>.jpg)](video/<uuid>.mp4)` (`core/videoRefs.ts`), the alt its
length as a voice memo's is. The poster is an ordinary picture, so sync, a share and the reader's download carry it
with no word about films, and the owner's other devices and a reader see a still.

- **The pick** (`media/VideoPick.kt`). The Photo Picker (`MediaStore.ACTION_PICK_IMAGES` for videos, on Android 13 and
  later and on 11 and 12 with its module), or the chooser for videos where there is none, with no permission asked: the
  manifest still names no READ_MEDIA. The film is copied as filmed, off the UI thread, in 1MB blocks, into the cache's
  `picked/`, with 500MB of the phone kept free, checked before a byte is copied and every 64MB after. Its length, size
  and turn are read off the copy, and its poster is a frame a second in (half way through a shorter one), turned upright
  only where the frame still lies as the film is stored, shrunk to 1600px and written as a JPEG beside it. It is made
  there, not in the page, since a frame drawn from the app's own scheme would taint the page's canvas. Nothing else is
  read from the file: no place, no date, no device. The answer is its own event, `video`, never the picture's, whose one
  pending pick it must not answer. It says `copying` first, once a film is chosen, so "Adding the video." comes a moment
  into the copy and not while the picker is still up. Whatever goes wrong on the copying thread is answered, never
  thrown, since a throw there would end the app and leave the page waiting; the poster's frame is made at the poster's
  size where the phone can (Android 8.1 on), not an 8K frame made whole first; a chooser's answer that names its film
  only in a clip is read; and a kind that is not kept (3GP, MKV) says so, "This kind of video can’t be added. MP4, MOV
  and WebM can.", rather than that the film cannot be read. One film is picked at a time, since the answer does not say
  which pick it is for: a second while the first copies is refused in words. A film whose note was left, or whose place
  went, while it copied is thrown away rather than kept.
- **Keeping it** (`videos.rs`). `save_video` adopts the poster among the pictures and the film into `video/` under fresh
  names, both or neither, each only from directly inside `picked/` and the film only when its first bytes say what its
  extension does (`ftyp` for MP4 and QuickTime, or the older QuickTime atoms `wide`, `free`, `skip`, `mdat`, `moov` and
  `pnot`, EBML's magic for WebM). An answer the page was not waiting for (a reload behind the picker) is thrown away
  with `discard_picked`, and whatever waits in `picked/` for more than an hour goes, pictures included, which nothing
  swept before: at launch, and each time a film is kept or thrown away, since a phone can keep the app's process for
  days. A deleted note takes the films only it named, as its pictures; a film no note names is noted by a sweep at most
  once a day and goes after a week unnamed, time for an Undo, a note in the trash and sync. A reset takes `video/` and
  `picked/`.
- **Out of the cloud.** The manifest gains `dataExtractionRules` (Android 12 and later) and `fullBackupContent`
  (earlier), both leaving `video/` out of Google's cloud backup, so a film never goes to the person's Drive. Nothing is
  named for a move to a new phone by cable, so it is meant to carry everything, films included; whether Smart Switch
  honours the rules has not been tried. `paths.rs` and the Kotlin tests read both files. Leaving films out does not
  bring the notes' backup back: past Auto Backup's 25MB quota nothing of the app is backed up, and a speech model under
  `models/` (60MB, or 190) is past it on its own, and a few long recordings can be. Whether notes should go to that
  backup at all is Matt's question, and nothing wider is decided here.
- **Playing it** (`editor/videos.ts`, `ranged.rs`). The `vid` scheme serves a film a range at a time by seek: every
  range, open, closed or the last bytes, is answered at most 4MB at a time, a HEAD reads nothing, and a request with no
  range is answered whole only up to 8MB and otherwise told the length. The folder it plays from is found once and kept,
  since on Android the platform's answer is a trip to the main thread and a 4K film asks several times a second. It is
  registered as `rec` and `img` are, since wry answers every custom scheme on Android on the WebView's own thread and
  waits there regardless. On the note screen the card asks one HEAD before it draws the paper disc; "This video isn’t on
  this phone." takes the disc's place where the film is not there. A tap plays the film over its poster, the same size,
  with sound; another pauses it; a line of ink along the foot is its progress. No native controls, no autoplay, no loop,
  one film at a time. Full screen is a layer of the page, black in both themes with a white close, because the generated
  WebView client refuses the platform's own; the back gesture closes it and hands the time back, and the focus to the
  card's Full screen. A film that will not play is asked about again: gone, the card says so; still here, "This video
  can’t be played on this phone.", since a kind the WebView cannot decode is not a missing film. A film just added keeps
  the caret under its card in sight once as its poster arrives, and never again, or a card drawn afresh as the note
  scrolls pulled the page back under the finger. Off the caret the line folds to "video 0:12", but in fenced code, and
  the picture widget steps aside so the poster is drawn once. A shared canvas's cards draw a film as a shared page does.
- **Who is told what.** An older Android binary: "Update Ghost.md to play this video." Another device, the owner's
  Mac or a browser: "A video of 0:12. It stays on the phone it was added on." A shared page: "A video of 0:12. Only a
  still from it is shared." The iPhone app refuses both commands (`unsupported.rs`), and has no row.
- **AI runs** keep a video line whole as `![video-1](video)`, as for places, above.

**To try on the Fold.** Whether the gutter-wide, row-tall target is easy to hit on the cover screen at the default
density and at compact; how One UI's back gesture treats a tap that starts at the left edge; whether 150ms feels right;
how often a place's name comes inside three seconds; the list's room above Samsung Keyboard on the cover screen; and the
note step's field keeping the keyboard up. For the film: a portrait clip's poster the right way up, whether a `.mov`
plays when served as QuickTime, a gigabyte's copy time and the room check, seeking, full screen and back, and, on the
staging build, `bmgr backupnow` leaving `video/` out of the backup's listing, and a move by Smart Switch keeping it.

## 142. Notebooks, and journals of dated entries (2026-09-28)

Matt: "id like books to be renamed notebooks and I'd like a journal function where we can just do entries into a
book marked as a journal where we pick the template for pages (time and date prefixed, with geo location, etc etc)".

**The word.** A book is a notebook now, and its parts are pages wherever a person reads them: the index, the bar, the
foot, the aside and the add form said chapters while the cards and the New sheet said pages. The home page's Library
is Notebooks, under a notebook's own mark (art/Icons.tsx `Notebook`: the book with three rings across its spine, 4
wide and 4 apart, so at the heading's 19.4px they stay three rings and not a bar). As with Glyph becoming Ghost.md
(§63), only words changed. `book: true`, `title:`, the share's `kind: 'book'` (a new kind would change the digest
and reseal every share), `glyph-book-spots`, the element ids (`book-chapter-N`, `data-book-foot`,
`data-group="library"`), the file names, `src/app/book/`, docs/BOOKS.md, the MCP's tool names and the entries above
this one keep theirs, so an older app draws a notebook made now as the book it was, and the other way round. "book"
stays a search word: the palette's New notebook and About's Guide row are found by it. Bookmarks, and "book" the
verb, are untouched.

**Where it reads.** The + and the New notebook sheet. The index, the bar and the foot a page wears. The aside and its
toggle, "Notebook index", which it also says over a run of numbered chapters, as "Book index" did. The card's
"Untitled notebook". The name field on a notebook's More sheet, "What this notebook is called" (it said canvas for
both). The share row, which adds "Every page goes with it." on a notebook. The share limit's refusal, "Share a page,
or fewer of them." The shared links' footer. The reader's banner, "A shared notebook." The recorder's chip, "“Field
guide” is a notebook, so the words stay here." The typeface card, About's Guide row ("The whole app in 44 short
chapters"), and the MCP's co-author words. The command palette gains New notebook, beside New note. The aside's list
of numbered chapters with no notebook keeps "Chapters", since that is what they are.

**The Guide and the docs.** Chapter 14 is "Notebooks, and reading one through" and chapter 21 "Sharing a note or a
notebook", with every link to them, and the files keep their names. An installed Guide keeps its old titles, which
still agree with each other, so no link breaks: only a fresh add gets the new ones. Where the Guide called itself a
book it says this Guide, and its own parts stay chapters. docs/BOOKS.md keeps its name under the title Notebooks. The
Play listing, forms and features, the screenshot notes and the privacy page say notebook. Two things wait: the
screenshots `04-a-book.png` (its caption, "A book, read straight through.", is drawn into the picture) and
`09-the-tapes-shelf.png` (it shows Library) are made again in the next screenshot pass, and privacy.html and the MCP's
words reach the world only with their own deploys, on Matt's word.

**Voice.** The recorder learns no new word. "Make a book called …" is still what it knows to turn down, and "new
notebook for school, pens and paper" stays a note's words, since a command needs no keyword now (§136) and a
notebook is an everyday thing to say. One thing was put right on the way: the kind of thing said before a note's words
("a note", "a bug") ended where its letters did, not where its word did, so "add a notebook to Work" put the word
"book" in Work, and "a bugfix for login" lost "a bug". Now the kind ends at a word's end (capture/command.ts
`OBJECT_NOUN`). The tips never teach a notebook or a journal, as they never taught a book.

**A journal** is a notebook with `journal: true`, a `template:` and, if it keeps places, `entry-place: true`, all flat
keys in the page's own front matter beside `book: true` (book/journal.ts). The template is one double-quoted string
with JSON's escapes, which YAML reads as the text it is. An older app draws a journal as a notebook and keeps the keys.
It is made from the New notebook sheet's Journal choice, or a notebook is kept as one from its More sheet, every page
where it was, and made a notebook again from there. Not the Guide: a manual is not a diary.

**An entry** is a note named `2026-09-28 14.05`: ASCII digits in every language, so its key never loses the month,
and nothing a file name drops, so its file is `2026-09-28 14.05.md` and the index's link resolves in any Markdown app.
Matt chose any number of entries a day, each named by the minute, and a second in the same minute is ` (2)`. Its
`date:` is the wall clock with no offset, so a shared entry does not say which time zone it was written in, and an
entry written at 23:30 in New York stays on the 28th when it is read in London.

**New entry** is one tap in the journal and two from home, through the +'s "Entry in Diary" row for the journal
written in last, and the palette has "New entry in" for three. It keeps a record on the device first (book/entryDrafts.ts),
puts the entry's line last in the index, through the journal's own screen when it is open so its next save cannot
write the old index back, makes the note from the template and opens it with the caret at the end. The journal is
drawn as its entries by month, newest first by when each was written, whatever order the lines are in, three months
open and each older one a row. An entry nobody has written in is taken back when it is left: home, its tab closed,
or the journal opened in its tab. Not when it is spoken into, and not when another tab is shown. A launch after the
phone let the app go does the same, and no place lands on it first. Opening a journal from outside opens the journal,
where New entry is, never the entry it was last read at.

**The template** is one of five (the date and the time, just the time, a morning page, a day's to-dos, my own), with
Obsidian's double-brace placeholders looked up by their own names only (format/prompt.ts's `in` would print a
function's source for `{{constructor}}`). Words inside a format go in square brackets, as in Moment, and the sheet says
so under the placeholders. Times are on the 24-hour clock, as meeting titles are. A change is for entries from then
on. The day and the time come from core/stamp.ts, the module the + writes its date with. The sheet shows the page an
entry would start as now, drawn by the note's own editor.

**The place is the entry's own tag, never words.** The journal's switch is the choice, and travels with it. Local
only, the Mac, a refusal and an introduction before any first prompt ("Diary keeps where each entry was written.")
stay each device's. Its default is the device's Tag new notes, whatever the device can do, so a journal made on the
Mac keeps the places of entries made on the phone, and turning it on asks from that press where the prompt has never
been answered. The tag waits for the entry's first own words, and the map fetches no tiles until then.

**Speak an entry** is the journal's mic, where it used to write into the index. The words continue the template's
last line (capture/place.ts `lead`), so a spoken entry still starts with its time, and a day's to-dos said aloud
become to-dos. The place is asked once the recorder has gone, never at the tap, since the microphone's prompt and a
location prompt share one listener in the Android WebView. With a meeting recording it opens the meeting and makes
nothing. On the way: a take aimed at an existing note is no longer filed and tagged as the take's own new note, which
§134's "existing notes are never tagged" always said.

**A journal is shared an entry at a time.** A shared notebook is sent whole after every save of a page, which a year
of photographs cannot carry. A journal not shared says so where the share row would be.

**Two devices** adding pages to one notebook between syncs merge the index lines instead of making "Diary 2"
(core/sync/notes.ts `mergedIndex`).

**Faster notebooks.** App finds a note by its title through one map, not a search per row, and the index reads its
pages' authors again only when a page changed.

**Claude** writes an entry with `add_journal_entry`, from the app's own journal modules, which import nothing that
draws or stores so the MCP server bundles them. `append_to_note` refuses a journal's index, and `update_note` keeps a
notebook's keys. An entry is named and filed by its time, so the hosted server asks for `at`, the person's own clock,
where the local one (`npm run mcp`) takes the computer's: the box's clock would put an entry written at half past
midnight on the day before. The hosted connector is not deployed: that is Matt's word. Until it is, the one on the box
is older than `keepKeys`, and an `update_note` through it that leaves out an entry's front matter takes its `title:`,
and with it the entry's row in its journal (the note stays, under its heading).

**After review.** Words typed into a new entry and left at once for home, inside the save's 400 ms, were taken back
with the entry: App looked at the store before the screen's last save reached it. An entry is the person's on its
first own keystroke now, and its record goes then. A double tap on New entry made two entries of one name and one
line, and taking back the one left took the other's line: a second press while one is made does nothing, a name is
unique against the journal's lines too, and a line stays while another note is named by it. Back from an untouched
entry gives its journal the tab back, and so takes the entry back. A row's words skip only what the template wrote for
that entry, filled for its minute: a template line that was only `{{date}}` had stood for every line. The bar's sides
say a time or a day, not the first letters of a date. A journal's card counts only entries written, across
workspaces, and lists them by day and time with no numbers. The template's preview is drawn in the view and the face
a new note opens in, its heading a step above its words, and a heading counts no empty to-do. A shared entry is
read without its `title:` and `date:`, and a notebook kept as a journal after it was shared is read as the notebook
it was sent as. Claude's `add_journal_entry` writes the line first and turns down a time that is not one, and a
rewrite keeps `title:` only where it is a notebook's or an entry's name.

Found on the way, and older than journals: a note opened again from a list read before its last save opened without
its last words, and the next keystroke's save, from the old revision, was refused and stopped the saving. A notebook's
page opened again from its bar did it, and so did every entry opened from its journal's row after it was written in. A
note's screen now reads the note once the last screen on it has finished saving, and takes that copy while nothing is
typed there yet, and a screen that saved anything says so as it goes, so the list and the journal's rows catch up
(editor/useNoteSaving.ts).

**Where the two meet.** A row's words, in the journal and in the aside, skip what the + beside the line draws as
something other than words (`firstWords`): a place, a film, a picture, a canvas's frame, a table, a rule, and fenced
code, a chart or a board, whole. A callout's kind, the lead of an empty heading, list or sum, and a footnote's marker
come off, and a link is its words. An entry whose first thing was a place had read
`[Cais do Sodré, Lisbon](geo:38.7057,-9.1446)` in its row, coordinates and all, and said them to a screen reader; now
its row is its day and its time until words come.

**Left undone.** One entry a day, where a second tap opens today's. A daily reminder and a launcher shortcut (native,
generation 21). The side key starting an entry. A folder per journal on disk. Reading a month straight through.
Sharing a whole journal, or part of one. A notebook's pages nested under it in the sidebar. The page's keys in
Obsidian's Properties, which reads only the file's first block.

## 143. Settings' column smokes under its search field (2026-09-28)

(Numbered 143 because the + and the notebooks, in flight at the same time, have 141 and 142.)

Matt: "on the settings page when scrolling on the left sidebar we should see the wisp fade effect under the search bar
covering the overflowing content like we see with the header on the main page".

In the split view (§138) the left column scrolls on its own, and its rows slid under the search field's edge and were
cut there. Now the field is the column's header, as the top bar is the home page's: laid over the rows in the
header's glass (`--app-glass-mix` over `--app-glass-blur`, which is what `.app-headerPane` is: the task's "solid" came
from a stale line in art/wispEdge.ts, since corrected), the rows starting under it (`--wisp-under`), and the column
wearing the wisp edge under it. On a phone's screen (the Fold opened out) that is the smoke; on a desktop's, the blur
strip under the glass (§94). At rest nothing moves: the first row stands where it stood, measured the same to the
pixel on main and the branch in Chromium and WebKit at 1280 x 900 and 880 x 790. The phone's list is unchanged.

**A band of its own.** The column smokes while the section's page beside it may be smoking too, under a header of
another height: the page's band sits at its own top, the column's under a field 58-60px tall. Every attribute of the
one filter is global, so a second view wearing it moves the first one's band to its own header, and the drift moves
both while only one scrolls. So the header's band is drawn twice (`art/WispEdgeFilter.tsx` `TopBand`), the page's and
the column's, alike but for their ids, and the hook takes `band: 'column'`. Each band has its own drift: its own count
of views scrolling and its own clock, so the column's smoke holds while only the page scrolls (Matt: "only animate
when we're actively scrolling"). On the Fold's build, scrolling the page for a second moved the page's noise and left
the column's where it stood; scrolling the column then moved the column's. The view's attribute says which filter it
wears (`data-wisp-edge="column"`), at the weight of the page's rule so the reduced-motion rule still takes it off. The
column's band is a top only: the hook does not hear `foot` with it, since the stylesheet chains a view's two ends as
the page's top and the foot.

**Its first row.** The home page's first line stands 46px under its header, and the band's lip, 19px under the header's
edge, reaches it over the first 27px of a scroll. The column's first row starts at the field's edge, its words 15px
under it and already inside the lip, so the band switching on at the fifth px took them from crisp to full smoke at
once, and the card's top edge frayed. The column's lip now eases in (`WISP_EDGE_EASE`, a band's depth: the drop, the
lip and one ramp of the blur, 34px): it starts that far above its place, its ramp under the field's glass, and comes
down a px for each px scrolled. On the Fold's build the first row stays crisp through the first 12px and goes to smoke
as it reaches the field's edge, by 20px; from 34px on the column's smoke is the home page's exactly. The desktop's blur
strip already faded in over 160ms, so it needed nothing. Renders: `first-rows-fold-chromium-dark-home-before-fix`.

**The keyboard.** With the field laid over the list, a row under its glass counted as already in view, so a row
focused from the keyboard was left behind the field: arrowing up through 13 results for "note" left the focused row
83% hidden at the worst step, on the Mac and the Fold in both engines, and Shift+Tab did the same. The column's scroll
padding is now its top padding and a px (the hook measures the field rounded; the Mac's is 59.47): at every step, in
Chromium and WebKit, the focused row lands clear of the field, as it did on main.

**The budget.** Each filter's region is held to 2^24 device pixels. The page's is the window's size: at two device
pixels to the CSS pixel, 1280 x 900 gives 2720 x 2360 device pixels, 0.38 of the budget, and 1800 x 1100 gives 3760 x
2760, 0.62. The column's was the window's too, on the view that each filter has a budget of its own, and that turned
out not to be so in WebKit: with the filter forced and both bands on at 1800 x 1100, each drawn alone, WebKit gave back
an empty frame every time, with the break between 1.00 and 1.08 of the budget together. So the column's region is its
own width, out to its right-hand edge in the window (WebKit counts user space from the document's corner, and keeps the
window's height for the same reason): 399 px across, 0.13 of the budget at 1800 x 1100, 0.75 for the pair, and WebKit
draws both. And the column is held to the budget together with a window-wide page's region beside it, so a window
whose pair would not fit keeps the column's plain edge while the page smokes. The page's top and its foot are still
held each on its own; whether a view wearing both in WebKit fits at all is not settled (the review found a forced home
page at 1280 x 900 coming back empty too), and nothing that ships draws either there.

**The scrollbar.** A view under a header has the app's own scrollbar, starting at the header's edge (app.css
`[data-under-header]`) and never above `--app-safe-top`, for a header at the window's top. The field is below Settings'
head: on the Mac `--app-safe-top` is 117px against the field's 59, so the track began 58px under the field. The
column's starts at the field. The app's scrollbar is a classic one, 12px across, so on a desktop a column long enough to
scroll (a search with many results) lays its rows 12px narrower, as the home page's cards are, and a long title wraps
or truncates sooner ("Tag new notes with my location" breaks after "with" at 1280 x 900). Matt's call if he would rather
the platform's overlay scrollbar here.

**The desktop's drift.** On a desktop the edges are plain (the blur strip, the short fade), with no filter worn, yet
scrolling ran the drift and wrote seventy-odd attributes a second to the filter's noise. It now starts no loop on a
desktop, for the page's band as well as the column's.

**Not done: WebKit's corner.** The column's band is placed in user space, as the page's is, and WebKit starts user
space from the document's corner (§54). With the filter in WebKit the band lands as far above its place as the column
is below the window's top, 69px on the Fold's size: at the column's own top, where the rows under the field's glass are
bent and smoke is thrown up over the bottom of Settings' head and into the field's padding above the pill, while the
rows at the field's edge stay crisp. The Mac draws the blur strip and Android is Chromium, so nothing that ships shows
it; an iPad build would (the Apple target includes the iPad, and a touch screen takes the filter), as it would leave
Settings' page beside it without smoke. Placing the bands in their views' own boxes, as the lanes' foot is, would
settle both.

**Not done: the cost of a second band.** A column scrolled and left still keeps its filter while the page beside it
scrolls, and the compositor applies it again every frame: in headless Chromium's software compositor that was about 23%
more per frame. What it costs on the Fold's GPU is for the Smoke bench there to say.

## 144. Names for a new note, and templates to start one (2026-09-28)

(Numbered 144 because the Settings column's smoke has 143, and the AI fills and the voice assistant's switch, in flight
at the same time, have 145 and 146.)

Matt: "Add suggestions for note names like the days date and other standard note formats. When making a new note also
offer a few templates to chose from with cards showing how they look (map header, typography focus, etc)". Then, asked
where and how: "cards on the blank page", the big map header, the reading page, and "the day in words first". Every
other question took its default: every new note opens focused, six templates, the cards formatted, a taken name gets "
(2)", ⌘N bound in the Mac app, and your own templates later, as notes in a Templates notebook.

**Ready to type.** + › Note, the palette's New note and ⌘N open a new note with the caret in its first line and the
editor focused, the keyboard up where the phone allows it. No new note took focus before. The screen's `caretAtEnd`, a
journal's entry's, became `caret`, a place or `end`. Whether Android raises the keyboard for a focus that follows the
note's write is the Fold's to say. If it does not, the caret waits in line 1 and the first tap raises it, as before.

**The map's box holds its place.** With the caret in line 1 from the first frame, a map card arriving with the fix, or
leaving when the fix failed, moved the line under a typing thumb (about 105px at 412). So where a fix is expected
(`willLocate`: Tag new notes on, not Local only, a device that can locate, no refusal standing, and location allowed,
each read as it stands) the box is held from the first frame, drawn as `MapPicture`: the card's own box and dot grid, no
map, no button, `inert`, nothing fetched. The tag arrives in it with no beat, so nothing moves. A fix that does not come
leaves it saying `No place yet.` until the note is left, and a note reopened with no tag draws none. Where the prompt
was never answered nothing is held until the introduction's Allow, which holds the box under the person's own press.
What still moves: the folded front matter line arrives with the tag at the first own words, as it did.

**Names on the blank page.** Under a new note's empty first line, four quiet chips in a fixed order: the day in words
with its year, `Monday, 28 September 2026`, then `2026-09-28`, `2026-09-28 14.05` and `2026-W40` (core/noteNames.ts).
The ISO names are ASCII digits in every language, so a file name and a title's key keep them whole, and none has a
colon. A tap writes the name as the note's heading, as one undo step, the caret on the line under it. The heading is the
name, as it is for every note, and names the file, `Inbox/2026-09-28.md`. A name another note has, archived or in the
Trash too, is left out and the rest keep their places, so no chip opens another note or makes a second of a name. Where
a language's title key loses the month (Russian keys "понедельник, 28 сентября 2026 г." as `28 2026`, like every 28th
that year), the words are still offered, but today's taken check asks the ISO name. The minute's chip turns with the
clock while shown. The + beside the line writes the minute's name, not the stamp, on the line that names the note, since
`28 Sept 2026, 14:05` there files as `28 Sept 2026, 1405.md`.

They show only while the page is being written in: the editor has the focus, and the page is ready for words, which is
no keyboard on the screen (the Mac, a desktop), the keyboard up (core/keyboard.ts: the viewport 150px under the tallest
it has been at its width, kept by width so the Fold opening is not a keyboard), or the person's own tap ended on the
words or their key reached them. A tap is taken at its click, its last event, so chips that appear under a finger are
never that tap's target. It fails safe: a keyboard already up at launch, a floating one and a hardware one each read as
down, and the chips wait for a tap. They are a block after line 1 inside the editor (editor/nameChips.ts), so they
follow the line wherever the held box puts it, and a press on one keeps the caret, the focus and the keyboard, as a
suggestion pill's does.

**Only a note made now.** Names and templates are offered only on a note `newNote` made in this run that has had no
words of the person's (`markFresh`, kept in memory only). An emptied old note is a real file with a history, and a
name's take-back is a delete with no Trash, so an old note never shows them and nothing offered can take one away.

**Templates on the blank page.** Under the names, while they are shown, a card for each of six templates
(notes/noteTemplates.ts): A day, A meeting, A checklist, Notes on a book, A map at the top and A page to read. Each card
is the top of the note it makes, drawn by the note's own editor, formatted, in the note's ink and heading proportions
(NotePeek's `whole`), one to a row on a phone and as many as fit 15rem from 600px, three at 880 and on the Mac. Every
card's picture is the same height, so a row's names line up, and only A map at the top draws a map. A card is a button
named by its template and described by its sentence, and what it draws is one `inert` picture with no button in it. A
press keeps the focus in line 1 and turns the blank note into that template as one change: its record first, then its
name settled (a second A day is `2026-09-28 (2)`, and its card says `Today has a note by this name. This makes a
second.` before the press), then the caret in its first open line, the page at its top. One undo brings the blank page,
the names and the cards back. The cards go at the first letter with the names, or at a tap elsewhere on the page that
began while they were shown, never at the tap that brought them. A map at the top is not drawn where the device can
never locate (the Mac, an older Android binary, a browser with no geolocation), and is dimmed, not a button, with its
reason under Local only or a refusal that still stands. The + sheet's Note row is as it was, and no row or palette
command offers templates: the blank page does. The ghost goes under the cards, in their block.

**Your own templates.** The blank page's last card, Your templates, opens the notebook the templates are kept in
(notes/ownTemplates.ts) in the blank note's tab. It is found by `templates: true` beside `book: true` and never by its
name. The first press makes it with the six built-ins as its pages, the pages first and the notebook last, as the Guide
is added, against the store read then and out of the Trash, so a press cut short makes only what is missing the next
time. From then on the blank page's cards are its pages in its index's order, two notebooks made on two devices read
oldest first and a page named twice offered once. A page is marked, `templates: page`, and only a marked note is one:
the seed makes all six whatever the person's notes are called, a line in the notebook opens its marked page, and a
`[[link]]` anywhere else still means the person's note of that name. A page is named by its `title:`, its words after
the front matter are the template, and only `look:` passes to a note made from it, so a page written where it was tagged
never hands its place on. A page still word for word a built-in keeps that one's sentence and rules, and any other says
`One of your own.` Add a page in the notebook makes a page with its heading left open. The pages stay out of Recent, To
do, the ticked count, the notes touched today, what a spoken command can name, the palette's list before anything is
typed and a notebook's page pickers. Settings were the other way, and were not taken: they sync as one sealed blob, last
writer wins, and Claude reads notes only. The costs: seven notes appear and sync, and a device on 1.9.0 shows the pages
in Recent the day they are made, their `{{date}}` as it is, until the update reaches it. Claude's rewrite keeps
`templates:`.

**One engine and one record.** The journal's `fillTemplate` fills them, moved to core/template.ts and given the ISO week
(`GGGG`, `WW` and `W`, while Moment's locale week, `gggg` and `ww`, stays as typed) and `firstOpenAt`, where the caret
goes. The journal's record of an entry nobody has written in is core/untouched.ts now, its journal optional and its
storage key the one 1.10.0 wrote, so a templated or named note left without a word of the person's is taken back as an
untouched entry is, with no toast and no line to take out, and no place lands on it before then. Only an entry is spoken
from its last line: a templated note's mic speaks into it as into any note. The screen saves a name or a template at
once rather than on typing's beat, and a take-back that finds a new note with no words in the store yet, its save still
on the way, leaves the record to the next look.

**Two looks.** One flat key, `look:`. `look: map` draws the note's map as a header across its column, 10rem on a phone
and 16rem from 600px, up to 48rem, its box drawn from the first frame with or without a place, saying `No place yet.` or
`Local only is on.` where there is none, and the place asked for once from the card's own press whatever Tag new notes
says. `look: reading` sets the words in the interface's face (the note face swapped on the editor, and both of
typefaces.css's coding-face rules kept off it, so Inter keeps its features, optical sizes and the title's -0.035em), a
5xl title from the column's own scale, a lead line a step larger in the second ink that says `A line that says what it
is about.` while it is empty, and a 36rem column from 600px, the map card and the byline starting where it does. On a
phone a map note's header runs the page's whole width, square, a masthead rather than a taller card. No serif ships,
only Maple Mono has true italics, and the text size is the person's, so that is all a look can be. The key is kept out
of the folded front matter line, and a block holding only the look folds to nothing, so a reading note opens on its
title. The More sheet's Reading it gains Look, Plain, Reading, and Map for a note with a place, as one undo, and the
person's own, so it forgets an untouched record. The shared reader draws both looks and not the key, and Claude's
rewrite keeps `look:`.

**The tab says the name.** A new note's tab said Untitled however its first line was typed, since tabs are drawn from
App's list, read again when the store says so and not on the editor's saves. The note screen now says its title to a
small store outside React (core/liveTitles.ts) as line 1 changes, and only the tab row subscribes, preferring it while
it is newer than the note App has, so a rename by sync afterwards wins.

**⌘N.** The palette always showed ⌘N beside New note and nothing bound it. In the Mac app it makes a blank note ready to
type, from a place only, and not while a sheet, the palette or the Guide is open. Not in a browser, whose ⌘N it is.

**Found on the way.** CodeMirror tells its extensions of a focus change once, and drops the telling when another change
lands first. A new note is focused and given its caret, its + and its names in one moment, so on the Fold's build the
names never heard it had the focus. The names' field reads the focus again 20ms after each focus and blur. The folded
front matter line has the same blind spot, and is left as it was. The heading counter had already stopped counting an
empty to-do on main. §134's line that a tag shows in Obsidian's Properties is not so: the page's keys are a second front
matter block, which Obsidian and any CommonMark reader draw as a rule and then a heading holding the keys (the `---`
under them makes one), as they draw `look:`.

**Tests.** The ISO week at the year's turns, the caret for each template, a taken name's " (2)" measured after, each of
the six made exactly, your own templates (the notebook by its key, their order, two notebooks, a look passed on and
nothing else, a built-in's rules kept, the pages kept apart, a seed cut short), the names in their order in eight
languages and dropped where taken, the day's key kept or lost in fourteen, the keyboard by width, the record with and
without a journal and one 1.10.0 kept, the fresh set, the chips' gates (focus, a tap's click, a key, the keyboard) and
their press, a focus CodeMirror dropped, the lead line and the hint, the look's fold, the held box found, missed and
left, the cards (buttons, pictures, the dimmed and absent map card, A day taken), a card's press and its undo, a map
note's header and its one ask, the Look row, the reader, the take-back of a templated note left, ⌘N, and an old note
emptied by hand showing nothing and still there after. After review, each of these with a test that fails without it:
a touch's events before its click drawing nothing, a keyboard up before the editor, a phone waiting for the click, the
cards staying for the click that brought them, a card or a name pressed from the keyboard giving the focus back, the
page at its top after either, a stale press on a name or a second card doing nothing, a card kept at once, a name
followed once typed after, a note opened to be read taking no focus, A day's taken name wired through the screen and
said on no other card, only A map at the top drawing a map, the cards gone during an AI run, a note of the person's by
a page's name never taken for the page (the seed, the lists, a link, the notebook's line, its book bar), a second
device's pages kept apart, Your templates pressed twice at once, the pickers, the open note's own name, archived and
binned names taken, a templated note's mic, ⌘N's modifiers, its default and a recording under it, a closed tab's
editor title forgotten, a fix not expected where location is blocked or denied, the turned phone not a keyboard,
`templates: false`, and Claude's rewrite keeping a page's mark.

**Measured** (a production build of this branch, Playwright's Chromium as the Android app at generation 21 and as the
Mac app, the clock at 14:05 on Monday 28 September in London, shots in `scratchpad/newnote/shots/`). At 412 with the
keyboard's height taken (412 by 585): the held box 120 to 216, line 1 at 239 from the first frame, the chips in two rows
from 279 to 350, the first card from about 370. At 880 the chips take one row and the cards three across. On the Mac the
chips and cards are there at once, five cards with no A map at the top. A map note's header is 367 by 160 at 412 and 768
by 256 at 1280. A reading note's title is Inter at 44.4px with -1.55px tracking at 412, where a Maple title is 36.9px,
and its words hold a 36rem column at 1280.

**After review** (three reviews of the branch: its look, its behaviour, and its tests by mutation). The first tap on a
blank page picked a name or a card: on Android a touch's mouse events and its click come after the finger has left, at
the place it left, so the names drawn at the tap's pointerup were under its click. It is taken at the click now. A
person's note named like a page, `# Notes on a book` holding a to-do, was made a page by the seed and left home, To do
and Recent. Pages are marked now. A card pressed lower down left the caret's heading under the tabs, since the page kept
its scroll. A templated note's mic spoke every sentence as a to-do under To do, the journal's rule for an entry. The
open note's own name was taken from it when the list was read again, so an undo to the blank page offered the rest and A
day promised a second. A box was held for a fix that could not come where location was blocked with no refusal kept
here. Every card drew a small pinned map wherever the note held a box: four on the Fold's first screen, and one under
`No place yet.`. The cards were 204 to 336px tall, their names at three heights across a row. A reading note's map sat
127px outside its column at 880, a map note's header on a phone read as a taller card, the chips' tabular figures spread
`2026 - 09 - 28`, and the Look row's radios were said to be off.

**Measured after** (the same build and stub, the clock at 14:05 on Monday 28 September in London, shots in
`scratchpad/fixstage/look/`). At 412 by 915 with no keyboard, a first tap at 300, 420 and 600: every event of it on the
words with no names drawn, the names after it, the note still blank, and a second tap on a name names it. Notes on a book
pressed with the page scrolled at 412 by 585: the page at 0, its heading at 239 to 280 under the tabs' 98. The cards 199
tall at 412 (219 for A meeting's two lines), the page 2103 against 2482. At 880, 226 tall, three across, their names on
one line, the page 1296 against 1634, and Your templates across the row under them. A reading note's map card at 880
starts at 152, where its words do, 512 wide. A map note's header at 412 is 412 by 160.

**Left undone.** A daily note, where today's name opens today's note, asked together with a journal's one a day. On the
Fold: the keyboard rising for the focus after the write, `keyboardUp` against the real keyboard on both screens and the
floating one, the held box on the first painted frame and the fix's time, the header's tile count against §134's, the
cards' first draw at 4x throttle and in WebKit. The front matter line's arrival at the first words. The recorder's
meeting title in the ISO shape, which is the summary's placeholder. Moment's locale week. The looks on a canvas's card,
a notebook read through and a home card. An empty to-do drawn as a box: a bare `- [ ] ` is not a task to the parser, so
the note and its card draw `- [ ]` as the journal's to-do preset does, and every to-do in the editor is its brackets.
The ghost under the cards is still below the first screen at 412 and 880: the cards are Matt's ask, and the ghost over
them would push them off it. A name with an ISO date breaks after the date's first hyphen where a heading is narrow (A
meeting's card at 880, its note at 412), the browser's rule for every hyphenated word, and a run kept whole is the one
thing that could then run off a phone at a large Text size or a pinch. A note of the person's named like a page still
wears the Templates notebook's mark in the lists, which find a notebook by a page's title. Where the app's keys go in a
file, so Obsidian reads them, is §142's question. A `template` argument for Claude's `create_note`,
whose hosted server deploys only on Matt's word.

## 145. Blanks the AI fills (2026-09-28)

(Numbered 145: note names and templates have 144, the voice-assistant switch and the onboarding 146.)

Matt: "Add an option as well for the users to be able to put special syntax in a note that allows the AI to fill
context make a few different scenarios like "flights are cheapest to Tokyo on [[what day / time?]]" Then the AI fills
in the squares with the factual response using the phones local AI model think of other scenarios as well".

Built from the revised design (scratchpad/aifill/fills.md) and Matt's answers to its questions, which win where they
differ. The syntax is `{?question}`. Totals, day counts, dates and conversions are worked out live by the app. Fills run
only when pressed. A live blank is paused until online, then looked up by the phone itself. The voice-only runs get
typed doors, and an Ask field. Every other question took the design's default.

**The syntax is `{?question}`.** `[[…]]` is already a note link (editor/wikiLinks.ts), and a tap on one makes a note.
`{{…}}` is the journal's and the templates'. So a blank is a curly bracket and a question mark
(core/blanks.ts `BLANK`): not `{{?`, not after a backslash or a `$` (`${?HOME}`), not `{??`, no `|` in the question, at
most 160 characters. It makes no node in the parser and means nothing in Obsidian, GitHub or Pandoc. `{?}` asks the
model to read its sentence, or the question just before it: the asking words (`askingWords`) read "How many days
until Christmas? {?}" as that question and `Q: …?` then `A: {?}` as the Q.

**Code decides where an answer comes from, never the model.** Every blank goes through three pure readings first
(ai/fills/lane.ts): worked out by the app (core/fillFacts.ts: a total or an average of the note's own amounts, a count
of to-dos or of the list above, days until or since a date, a weekday, a date some weeks on, a unit conversion, the time
in about eighty cities and the day their clocks change), recognised and not finished (Can't work out: two currencies, a
line with two amounts, Easter, a slashed date, no date to count to, a city it does not know), live (core/fillLive.ts:
weather today, prices now, rates, markets, opening hours, transport, the newest of anything, results, and an event after
a fixed year per model, `learntUntil`, 2024 for all four until read from their cards, never the clock), or the model's.
A worked-out answer is drawn after the square like a sum, with its working a tap away, and never written unless Write
it in is pressed. Every refusal offers Ask the model anyway, since a word list can be wrong.

**The square.** editor/blanks.ts draws a blank as a dashed hairline of the words' own ink round the question, the
braces dim in the Markdown view and hidden in Formatted but on the lines being written, and an icon at its end that says
what will happen before anything is pressed: a calculator, a calendar or a globe for the app's working, a speech bubble
with a question mark for the model, a signal for a lookup, a crossed-out signal for what can't be known. On the line
being typed the icon, the words after the square and the pill wait until the hands have stopped for 700 ms. A drawn
table draws its cells' squares and dotted answers, with its pill after its last row. A card's peek draws the square
with no icon.

**Only a press fills.** The Fill pill at the end of the line ("Fill", "Fill 2", "Filling", "Waiting"), Fill the blanks
in the More sheet with its count, the palette's Fill the blanks, and the panel's Ask again and Ask the model anyway.
Never on typing, opening, leaving or syncing. The fills' queue (ai/fills/queue.ts) is the page's, beside the summaries',
so a press finishes when its note is closed: the answers are written to the store with the revision they were read at,
read again once on a conflict, and kept for the next open when that fails, with "Filled 2 blanks in Tokyo trip." and
Open. A generation's answers land in one change with the AI's signature on the first, a press is one line in the log
with one Undo however many generations it took (`batch` on the run), a fill waits while Format runs on its note, and a
Format asked while it fills stops it: "Format stopped the fill. 2 blanks are still questions." The + stays while a fill
runs, since a fill holds no landing an insert could cross.

**What the model reads, and how it answers.** One prompt with a worked example per shape (ai/fills/prompts.ts), read
by the Rust tests by name, and a message of the note's title and the part a blank needs: its section, a cell's
headings, header row and own row, a list and the line above it, a title's first 2,000 characters. The cell is named in
words ("Blank 2 is the Year of The Remains of the Day."), other blanks are `___`, worked-out ones their answers, earlier
fills their words, and the room is counted in tokens by script. The date line is fixed English on every phone.
Answers come back as `[1] …`. The shape of a blank is read by code from where it sits (ai/fills/shape.ts): a title, a
language, items, a cell, a summary, a number, a line or a phrase, and the answer is checked against its shape before
it is written (an echo taken off, a title or summary naming what the note lacks refused, a translation into Japanese
with no Japanese script refused, a cap on each). A refused answer writes nothing and says Not known, No answer came or
Didn't fit after the square for the session.

**Measured first, per model.** src-tauri/src/llm/tests.rs reads the prompts from the page and the cases as the page
builds them (src/app/ai/fills.fixture.json, kept equal to the builder by a vitest) and runs them on the Mac's models at
temperature 0, the bar binding on the 4B in the deploy's test run:

- The adopted form first failed on items on every model: asked for three under one number, the 4B gave "Sunglasses"
  and the 9B "Cash, power bank, and rain jacket" on one line. An items blank is now asked as numbered slots, one new
  item a blank (`3. {?1 more}`, `4. {?2 }`, `5. {?3 }`), which the models already answer as several blanks.
- The engine refused a 969-token prompt with 35 to write ("the window is 1024"): it makes a window of the prompt, the
  budget and 16, rounded up to 512, and wants 64 of it left. A fill's budget has a floor of 48, which always leaves it.
- Matt's own Tokyo blank came back UNKNOWN on the 4B and the 9B: the prompt's line on live prices read "cheapest" as a
  fare. One line more says general advice about prices stays true from month to month, and the 4B says "Tuesday".
  The 9B still says UNKNOWN, which the square says as Not known, and Ask again is a tap.
- Three language cells of a table came back without Japanese script ("arigatō gozaimasu"), which the check refused.
  The hint now names the script ("Blank 1 is Thank you in Japanese, in Japanese script."), and the 4B writes ありがとう
  (arigatō), 駅はどこですか (eki wa doko desu ka) and すみません (sumimasen).
- With those, the 4B and the 9B meet every case at rung 1, one generation a press, every line an `[N]` line: Canberra,
  Kazuo Ishiguro and 1989 in one message, Cabin booking, UNKNOWN for the newest Pixel and the 2026 World Cup, Sam, the
  station in Japanese, three new items in a bulleted and a numbered list, 8848, and Argentina when asked again with
  "It is not: France.". `FILL_RUNGS` is 1 for both.
- The 2B meets the bar at no rung (Mark Twain for The Remains of the Day, France for 2026, a Samsung for the newest
  Pixel). It fills at rung 1, where it missed least, and the bar prints its misses rather than failing.
- Gemma 4 E4B cannot run at all on this build: every request answers "cannot apply the chat template: ffi error -1",
  the existing gist test too. A native fault, left to its own task. It takes the rung of a model never measured, 2.
- `FILL_PROMPT` reads as 968 tokens on the Qwen models, and `FILL_PROMPT_TOKENS` is 975.

The eye run of the design's scenarios on the 4B (rung 1, the Mac, timings under other builds' load and not a measure):
Tuesday for the cheapest day to Tokyo, a one-line standup that keeps Priya, Tom, Tuesday and the 24th, Call the plumber
for the tap's next step, the three phrases in Japanese script, the smell of rain on dry earth, 120 grams of flour,
Argentina for 2022 with France in the note, Frank Herbert, Tokyo in the title, 13 to 17 years for a cat, and a
press of five blanks in one generation of 6.6 s. And calm misses, dotted from memory: "milk and water" for buttermilk,
"Duas cafés" for two coffees, one word of Korean, three minutes for a soft egg. The 2B said France for 2022 with the
Qatar line in the note, and "Monday morning" for Tokyo.

**The answer says what it is, in the file.** An Unsure mark whose note the app hides: `??midweek??(Qwen3.5 4B from
memory, 2026-09-28. Asked: what day / time?)`, read back by `FILLED`: whose answer, from memory, from this note, or from
a named web source, the date, the question, and an item's place. "From this note" only when the answer's words stand in
one sentence of the note beside what was asked (ai/fills/source.ts). A trailing `?` goes after the bracket, or the
parser would not close the mark. A title line never holds a mark: a title fills as plain words, a question as the whole
first line stays the title with its answer under it, and every reader of titles, to-dos, the item text sent to Notion
and GitHub, a board's card and search reads a filled answer as its words (`plainFills`), so no list shows a bracket. A
tap on an answer opens its panel (editor/fillPanel.ts): whose, from where, when and what was asked, `MODEL_LIMITS` word
for word, and Keep as mine, Ask again (told "It is not: France.", since greedy decoding repeats itself), Put the
question back (an items fill's items together, by their places).

**Live blanks, looked up by the phone** (Matt: "Pause till online", then "Phone looks it up, all local"). A live blank
pressed with Fill asks one keyless public source that answers a page's CORS check with `*` (ai/fills/web.ts, checked
2026-09-28): Open-Meteo's geocoder and forecast for the weather, Frankfurter's European Central Bank rates for money,
with the sum the app's own, and Wikipedia's search with the first sentences of its pages, then Wikidata's facts for
the page the question names best, for results, the newest and events after the training. Only the question goes, or
the place and then its coordinates, or two currency codes, never the note or the amount. The model on the phone writes
the answer from what came back with a prompt that answers only from it, or says UNKNOWN, and the answer is marked
`from Open-Meteo`. Offline, the square says "Waiting for a connection" and the lookup goes on by itself when the phone
is online, never started but by the press. Prices, fares, markets, opening hours and transport have no source that
allows it and say "No public source the phone can ask answers this." No general web search allows a page to call it
keylessly: DuckDuckGo's result pages refuse a script, and its instant-answer API answers only from Wikipedia's topics,
so Wikipedia's own search is the search source. Measured from recorded answers, the 4B and the 9B wrote "Rain showers,
19 to 25 °C", "Spain" (the 9B, reading Wikidata's facts a line each, "Spain men's national football team"), and
UNKNOWN from a page that did not say, 3 of 3. Settings › Account › Privacy gains "Look up blanks online", on by
default, off and held under Local only, which keeps such blanks paused and says so, and kept on the device.
landing/privacy.html gains a paragraph, committed and not deployed.

**Typed doors** (Matt: "Those, plus an Ask field"). Fix spelling, Make a list and Continue were reachable only by voice.
They are rows of the More sheet's AI group now, after Format, Summarize and Enhance, and in the palette, and an Ask
field under them runs any typed instruction as the spoken Ask always ran, its changes marked with Keep and the log's
Undo.

**Carried through rewrites.** A blank and a filled answer go to every other run as link tokens (format/links.ts),
put back whole whatever words the model gave them, and a summary may leave one out. The gist reads the note with its
blanks taken out. Maths drawn from `$` now follows Pandoc's rule (core/maths.ts), so two prices on a line are prices.

**The + writes one.** More gains A blank for the AI, `{?}` with the caret inside, on its own line after a blank line
under a table, a list or a quote, or as an empty item's words. The empty line straight under a table with an empty cell
gains Blanks in the empty cells. The cheat sheet has A blank, and the Academy a lesson.

**Claude.** `search_notes` reads fills as words, and create_note and update_note say what a blank is and how to answer
one. The MCP's copy of the title rule comes with the bundle. None of it reaches Claude until the next Claude server
deploy Matt approves.

**Page only, over the air.** No Rust but the tests, no Kotlin, no native generation. Left out, each needing native
code or Matt: the Rust namer's title rule (src-tauri/src/library/names.rs keeps `??`, brackets and braces in a file's
name until it reads core/titles.fixture.json in a binary of its own), Gemma's template, automatic fills on leaving a
note and the `[[?` alias (both Matt's to choose), and a measure on the Fold, which was not reachable. The Model card
names the fills, and its about lines are §146's to reword ("Careful with facts" for the 4B, which the probes showed
confidently wrong). With no Settings › AI page yet (§146's), Get a model opens Recording at the Model card. (2026-10-05, finishing what was left: the namer reads the same rows now - `title_of` reads a note's first line
through a port of `titleWords`, and a Rust test runs every row of core/titles.fixture.json - so a note titled
`# Trip to {?capital of Japan}` is "Trip to.md", in the next binary. The 4B's line says "check a fact it answers from
memory" in place of "Careful with facts". §146 was never merged: its branch, voice/assistant-flag, waits on Matt.)

**What the shots found.** The built page, driven in Chromium as the Fold and as the Mac with the 4B's own answers
handed back, showed faults the unit tests had passed over. Each is fixed with a test that fails on the old code. Every
square's icon was an empty `<svg>`: editor/iconDom.ts forced React's draw with flushSync while React was committing
the editor, where it does nothing, and the test counted the empty ones. The icon is now React's own draw, copied into
the copies waiting for it. A fill's landing, signed in the same change, crashed the wisp for the note ("No tile at
position 70"): the plugin read the note's new positions in the DOM of the note before the change, and now maps them
back. "Cheapest flight to Lisbon today" went to the model, since cheapest was not a price. A press of live blanks
offline said nothing, and now says they wait for a connection. A short square that wrapped drew two boxes, and one of
28 characters or fewer now stays on one line. A summary naming what the same press had just written beside it (Lisbon,
in Trip prep) was refused as naming what the note lacks. A title or a summary is now checked last, against the note
with the press's other answers in it. And the whole-note read of blanks read the tree its state was made with, not the
one it asked for, which the readers' test showed under the 9B's load: a fence past a long note's first 3000 characters
read as words.

**Tests.** core/blanks.test.ts (the sixteen cases, the parser reading every written mark as Unsure, the title
fixture), core/blanks.readers.test.ts (both readers over one corpus, their two named differences), core/maths.test.ts,
core/fillFacts.test.ts, core/fillLive.test.ts, ai/fills/{shape, source, read, message, prompts, web, edits, queue,
voice}.test.ts (the queue with a simulated model: one change a generation, a closed note written with its revision, a
Format stopping a fill, a press behind another, a live blank waiting offline then asking Open-Meteo), the
editor/blanks, fillPanel, iconDom and wispArrivals tests, the readers' tests (home's To do, Notion's item text,
search, the gist, the MCP's search), the + rows, the More sheet, the palette, Privacy, and the Rust bar.

Cites: §21, §122, §127, §138, §141, §142.

## 147. The home page: the notebooks and the notes, searched, five ways (2026-09-30)

Matt: "redesign the home page / dashboard to be easier to navigate, remove things like the todo list and other things
focus more on displaying the books and notes in a easy way to search and look through give me 5 different dashboard
layout styles we can chose from in the settings also redesign the top bar so that the mic, reading vs code mode move
into the more button in the header".

**What went.** The date and its digest, To do, the shelf of tapes, the Academy card, the refining notice, and the
tiers that laid those groups out across a desk (§137, §139). home/tiers.ts, home/useColumnTier.ts, home/TapeShelf.tsx,
home/tapeCaption.ts and home/useMeetingLive.ts went with them, as nothing else drew them. The to-dos are still in their
notes, and a tape is still a card with its cassette in All notes, whose Tapes toggle finds every one.

**What the page is.** From the top: a search field over the notebooks and the notes (notes/allNotes.ts `matches`, the
same search as All notes), a filter of four words with their counts (All, Notebooks, Notes, Pinned), the workspaces'
pills, and the two notices that are about the app itself (an update, the voice model). Then the notebooks and the
notes, each newest first with the pinned ones first, never the archive, in the layout chosen. A search that finds
nothing says so with the words searched for. The foot is the way to All notes, which counts what the Cards and Shelf
layouts left out ("2 more in All notes") past their 48 cards. The dock is as it was. home/homeLayout.ts holds the rules
and is pure; HomeScreen.tsx draws them, its stylesheet HomeLayouts.module.css.

**The five layouts**, chosen in Settings › Appearance › Home page (a `homeLayout` preference, synced):

- **Cards**, the default: the notebooks as cards, then the notes, each drawn small, as the page had them.
- **List**: one line each, the kind's mark, the name, how it starts (its first line under its title, marks taken off)
  or a notebook's count of pages or a journal's of entries, the notebook it is in, and when. The most on a screen.
- **Shelf**: the notebooks as covers along a row that scrolls sideways, a spine down each, and the notes as dense cards
  under it.
- **Library**: each notebook's name as a heading that opens it, its pages as rows under it in its order, then the notes
  in no notebook. Two notebooks across once the column passes 44rem.
- **Timeline**: everything by when it was last touched: Today, Yesterday, Earlier this week, This month, Earlier.

The search and the filter stay on top whichever is chosen, so a person looks the same way in all five.

**The top bar.** A note's tools are the bookmark and More. The mic ("Talk into this note", or "Speak an entry" on a
journal) is More's first row, and the view switch is its Show row, which names both views in the note's own words
(Markdown or Formatted, JSON or Canvas, Markdown or Index). Show was already in More on a phone (§138's clean-up); the
wide screens' copy in the bar went. A note playing its tape has neither, as before: the tape has its own Add, and the
page is the transcript's until it stops.

**Tests.** home/homeLayout.test.ts (the order, the filters, the counts, the first line, the spans, the library),
home/HomeScreen.test.tsx (the search, the filter, each layout, the workspace, the empty page, the foot, the dock),
settings/AppearancePane.test.tsx (the five picks), editor/NoteScreen.test.tsx (the two tools, More's mic and Show).

Cites: §132, §137, §138, §139, §142.

## 148. The home page's mixes, and its filters beside the search (2026-09-30)

Matt, after §147: "i like the card view and the timeline view add a few more variations that are mixes and matches of
different views, move the all, notebooks, notes, pinned, and the workspaces into filters next to the search bar".

**Four mixes.** Settings › Appearance › Home page lists Cards and Timeline first, the two Matt liked, then four layouts
that cross them with each other and with the rest, then List, Shelf and Library as they were:

- **Card timeline** (Cards × Timeline): the Timeline's spans, Today to Earlier, each with a card for every note in it.
- **Spotlight** (Cards × Timeline): the four touched last as cards under Recent, then everything else as the
  Timeline's rows. By when alone, not pinned first: the cards are where the person was, and a pinned note still has
  its pin on its row, and the Pinned filter.
- **Shelf and timeline** (Shelf × Timeline): the notebooks as covers along the shelf, then only the notes, by when.
- **Notebook cards** (Library × Cards): each notebook's name, which opens it, over up to six of its pages as cards and
  "N more in Trip" past them, then the notes in no notebook as cards.

A page's card or row under its own notebook does not name the notebook again. The layouts are one pure function now,
home/homeLayout.ts `homePlan`: a layout and the lists in, sections out, each a heading (a word, a span, or a notebook
of its own) and the notes it draws as cards, rows or covers. The page draws whatever sections it is handed, so a new
mix is a case in that function and a test. Every layout that draws cards stops at 48 of them, since each is the note
drawn small in an editor of its own, and the foot counts the rest on its way to All notes; Notebook cards spends those
48 notebook by notebook. Rows are cheap and never stop.

**The filters beside the search.** The two rows of pills under the search went: All, Notebooks, Notes and Pinned,
then the workspaces. The search has one button at its end (home/HomeFilters.tsx), a circle its height, and the kit's
Popover opens from it with two groups of radios: Show, with how many of each, and Workspace (every workspace, then each
in its colour), then New workspace and the chosen one's Edit, which open the workspace sheet as the pills did. Both
groups stay open to be picked in one visit; a tap outside, Escape or the phone's back closes the panel. The arrow keys
move a group's choice, round the ends. What is chosen is never hidden: the button is inked while anything is on, its
name says what ("Filters: Notebooks, Kitchen"), and a chip under the search names each choice, in the workspace's colour
for a workspace, with a cross that takes it off. With everything shown, nothing stands between the search and the
notes. The search and its button stay on a workspace with nothing in it, so there is a way out of it, and go only on a
page with no notes and no workspaces at all.

**What the review found.** A four-lens review of the change, each finding put to a skeptic before it counted, confirmed
these, and each is fixed with a test that fails without it:

- A page was drawn only under its notebook, so in Library and Notebook cards a search or a filter that found a page
  and not its notebook (a word only the page has; Pinned on a pinned page; Notes) drew nothing, and said nothing, since
  the empty message asked whether anything was found rather than whether anything was drawn. A note is loose now unless
  it is a page of a notebook drawn on the page; those left over go under "Other notes" when some belong to a notebook
  left out, and the message asks whether the layout drew anything. (Library had it before; Notebook cards copied it.)
- Notebook cards showed a journal's six oldest entries, as its index is in the order they were added. A journal's
  pages are newest first now, by when each was written, as its own screen and its card order them.
- A page its notebook names twice was drawn twice, with one React key for both. Each is drawn once.
- A span in Card timeline cut short by the 48 said how many it drew, not how many it holds.
- The plan was kept from the moment it was made, so after midnight "Today" still held yesterday's notes until
  something else changed. It is made again when the day turns.
- The panel had no height of its own and the kit never clamps one, so with a few workspaces New workspace fell below
  the screen: it scrolls within the room under the button now. The keyboard is never dropped: the panel opens on the
  chosen Show, leaving it by Tab closes it, a chip's cross hands focus to the next chip or the button, and the
  workspace sheet hands it back to the button. The rows', covers', headings' and the clear button's focus rings, lost
  in the rewrite, are back.
- The tests' notes were a minute old at load, so a run in the two minutes after midnight put them in Yesterday. The
  page's clock is held in the tests now.

**Tests.** home/homeLayout.test.ts (every layout's sections, the card budget, Spotlight's lead, a page found without
its notebook, a page named twice, a journal newest first), home/HomeScreen.test.tsx (the panel, its counts, the arrow
keys in both groups, back and the keyboard leaving, the chips and their crosses, a workspace chosen, made and edited,
an empty workspace left, each mix drawn), settings/AppearancePane.test.tsx (the nine picks).

Cites: §137, §147.

## 149. Spotlight is the home page's default (2026-09-30)

Matt: "make the spotlight mode the default". A device where no layout was picked opens the home page on Spotlight
(§148): the four notes touched last as cards, then everything else by when. It leads Settings › Appearance › Home
page's list, as the default does.

Preferences are kept whole, so every device that had drawn the home page since §147 had stored Cards, the default
then, without anyone choosing it; a new default alone would have reached no one who had updated. So the pick is
remembered as a pick, as the code colours' is (`codeChosen`): `homeLayoutChosen`, set by a tap in Settings and synced
with the layout. Until it is set, the stored layout is read as the default. A layout picked on purpose stays.

Tests: core/preferences.test.ts (Cards stored and not picked opens on Spotlight; picked, it stays),
home/HomeScreen.test.tsx (a fresh device draws Spotlight), settings/AppearancePane.test.tsx (Spotlight first and
chosen; a tap writes the layout and that it was picked).

Cites: §147, §148.

## 150. Spotlight's pinned list, and recordings that read as recordings (2026-09-30)

Matt: "add a section above all the others that shows above recent that's a simple list of pinned notes", then "also
make it so voice recordings also show up in the timeline".

**Pinned.** Spotlight (§148, the default since §149) opens with the pinned notes, above Recent: a line each, the
simplest list the page has (home/homeLayout.ts `SectionDraw` 'lines') - the kind's mark, the name, the notebook it is
in, and when, newest first. No pin on a line, since the list is the pinned ones, and no line of how it starts: it is
for finding a note by its name. A pinned note is not drawn again under Recent or the spans below, as a phone's notes
keep theirs at the top alone. Nothing pinned, no Pinned; the Pinned filter on, only Pinned.

**Recordings.** A voice recording was on the page all along, in every layout's lists - it is a note, with its tape
kept (notes/allNotes.ts `hasTape`) - but the rows drew it as a page of words, so since the tape shelf went (§147) a
person looking down the timeline for one saw none. A recording is a kind of its own now (`kindOf` 'tape'): its row
and its line wear the shelf's cassette (art/Icons.tsx) and say its length before its words, "0:40", and the meeting
being recorded, whose note has no tape until it stops, says "Recording now" beside a dot that beats
(capture/meetingLive.ts). In every list and filter it is a note like any other; a card already said its length.

**Tests.** home/homeLayout.test.ts (Pinned first, newest first, and nowhere else; a recording's kind; a recording in
every filter a note is in), home/HomeScreen.test.tsx (the pinned lines, their notebook, no pin, not repeated; a
recording's cassette and length in the Timeline; the one being recorded).

Cites: §147, §148, §149.

## 151. The home page's notes swipe: pin, archive, and further to delete (2026-09-30)

Matt: "also add swiping left or right on notes (with haptics and a detent for pulling further to delete instead of
archive". The notes list had exactly this (§28, §31) until it went in 1.5.0, and its row came back whole
(notes/SwipeRow.tsx, notes/swipe.ts) for every note the home page draws: the rows, Spotlight's pinned lines, and the
cards, in every layout. Not the shelf's covers, which scroll sideways.

- **Right**, past one detent at 22% of the width: Pin, or Unpin on a pinned note.
- **Left**, past the first detent: Archive. Pulled on past a second at 55%: Delete instead, in the one red the app has.

Each detent is felt as well as shown. Light ticks come faster as a drag closes on it (core/detentFeel.ts), a firm click
says it has arrived - heavier for Delete - and the lightest tick says it was backed out of, so a thumb finds Archive
and then Delete without looking, and backs off either. Behind the note, a ring round the action's picture fills as the
detent nears, and the gap takes the action's colour once it is armed, since a fling can cross two detents inside one
pulse of the motor. Let go short of the first and the note springs home; the click a swipe ends on never opens it.
Archive and Delete slide the note away first, then act through App's own note actions (notes/useNoteActions.ts), with
the Undo the editor's Delete and Archive give, and the note's tab closed with it. A drag that starts mostly vertical is
the page's scroll, and one that starts in the phone's back-gesture edge is the system's.

A card's frame is cut to its corners; a line one row tall shows the picture and its word side by side, since one
above the other is taller than the line.

**A short row's gap** (2026-10-01; Matt, of the timeline: "the padding isnt enough around the archive icon it's right
against the edges"). The action was drawn the one way, the picture over its word with the further-along line under
that, about 76 pixels, and a row of a title and a line of words is about 74: it filled the gap to the edge. The gap now
keeps a margin all round, and measures itself (a size container, notes/SwipeRow.module.css): under 5.25rem tall the
picture is a size down with its word beside it. It keeps to the row's edge as the row slides, as Mail's actions do,
and the words fade in only once the gap holds them whole, the word first and the further-along line after, rather
than a pair wider than the gap cut off at both ends. A card's gap is tall enough, and stays as it was.

**Tests.** notes/swipe.test.ts (a note's swipes, pinned and not; the detents), home/HomeScreen.test.tsx (a row pinned,
archived, and deleted pulled further, with the motor's clicks at each detent, heavier for Delete, and its ticks on the
way; springing back and never opening; the cards and the pinned lines; no swipe without the page's actions).

Cites: §28, §31, §147, §150.

## 152. Pull to refresh: the home page, All notes, and a note (2026-09-30)

Matt: "add a pull to refresh feature on notes and the home page". A page pulled down from its top refreshes
(notes/PullToRefresh.tsx, core/pull.ts): the home page and All notes sync and read the notes again; a note saves what
is typed, syncs, and takes the note as the store then has it into the editor (useNoteSaving.ts `adopt`) - unless
something typed since is still to be saved, which is never taken away, and the next save's rebase looks after it. The
sync is waited for five seconds at most (core/sync/engine.ts `syncWithin`) and goes on after; signed out it answers
at once, and the pull is a re-read.

It is felt the way the swipes are (§151). The page comes down at half the finger's travel to the detent, 64px, then as
a rubber band to 110px at most. Light ticks quicken as it nears the detent, a firm click says it is there, the lightest
tick says it was backed out of, and a tap says the refresh is done. It is shown too: in the gap the page leaves under
the top bar, a ring fills round an arrow, the arrow turns over once a let-go would refresh, the ring spins while it runs
(half a second at least, so it never flickers), and a tick says it is done, all said to a screen reader as it happens.

Only a touch that is plainly a pull is one: down, more than across, from a page at its top, and within 300 ms - a finger
that rests first is choosing words in a note, and a long press then a drag of the selection's handles stays the
editor's. It stops the browser's own overscroll while it pulls, which only a touchmove listened to directly can do. On a
note only where the page itself scrolls: the Formatted view and the transcript scroll their own, and a canvas is drawn.

**Tests.** core/pull.test.ts (the rubber band, the detent, which touches are a pull), notes/PullToRefresh.test.tsx (a
pull past the detent refreshes, with its clicks, its ring and its tap; short of it and backed out of, nothing; scrolled
down, a rested finger, or off, nothing), editor/NoteScreen.test.tsx (a note takes another device's words, and never
loses what is typed).

Cites: §151.

## 153. ghostmarkdown.com, the whole app on one page (2026-09-30)

Matt: "you have total creative liberty to use glacierUI and redesign the GhostMarkdown.com website to be a full feature
of the app with CTA for downloading on the app stores or from the website directly".

The download page was the icon, the name, one line and three buttons. The site is now the app, section by section, in
the app's own look: ink on paper, the note's face with the Markdown's marks left dimmed, the app's ghosts as masks in
the page's ink, and Glacier's tokens for type, spacing, radii, motion and shadows (docs/LANDING.md has the files).

- **The opening** says what it is in six words, "Say it. It lands as Markdown.", and shows it: the recorder drawn at
  work, each thing said arriving in the note in smoke, as the app writes spoken words, then settling to ink. It runs
  only while it is on screen and the tab is in front, and holds still, the note whole, under reduced motion.
- **The ways to get it** lead: the device in hand's first and filled (the APK on Android, the Mac app on a Mac, the web
  app on an iPhone or iPad), the other two beside it, and the stores' buttons, which say Coming soon until a listing is
  live (`STORES` in home.js). The versions and sizes are read from the manifests the apps update from.
- **Every flagship feature has a section**, each with something to see or try: the cues as said and as written; Hey
  Ghost as a recording that moves notes; the review, whose Keep and Revert work; a tape and its summary; the seven marks
  and five effects drawn as the app draws them (the spoiler opens on a tap, the redaction lifts on focus); the home page
  in two of its screens; journals, boards and canvases in theirs; privacy in six plain facts; the devices, with the Mac
  in a laptop; and the six pages, System, Light, Dark, Dawn, Boreal and Ember, which retheme the site itself and are
  kept for the privacy and delete pages too.
- **The screens are the app's**, taken from the web build at a phone's size and a desk's (scripts/landing-shots.mjs),
  so they are never a mock-up of something the app does not draw.

Taking the desk's screen showed a canvas's row on the home page reading "{", the first line of its JSON. A canvas's
row says how many cards it has now, "4 cards" (home/HomeScreen.tsx; a test in home/HomeScreen.test.tsx).

Cites: §132, §147, §148, §151, §152.

## 154. The site reframed: organise your life, and work on it with AI (2026-09-30)

Matt: "reframe the website don't focus on the talking part focus on how it can organize your life and how it works with
AI tools to document and work in tandem, remove some of the verbosity to make the page half as long and use only real
components from the app for things like the tape cassette".

- **The story is order and AI, not voice.** The opening says "Organise everything. Work on it with AI." over the app on
  a wide screen. Then four bands, a sentence or two each: Organise (the home page, journals, boards and canvases, in
  the app's screens; finding, workspaces, and swipes and pull to refresh in a line each); Work with AI (the phone's
  own models, every change marked to keep or revert, Claude's connector - which signs what it wrote, never deletes, and
  never writes over another device's edit - with its address to copy, and Notion and GitHub); Document (meetings
  written up, voice's one place); and Private. The recorder, Hey Ghost, the review mock-up, the marks, the devices'
  band, the themes' band and the questions went. The page is half as long: 228 lines of HTML from 526, and on a desk
  5,200px from 12,000.
- **Only the app shows the app.** The screens are the web build's (§153), now with a note the AI has just worked on -
  its changes marked, Keep all in the strip, "By Matt and Ghost" - and a note Claude wrote, "By Matt and Claude", seeded
  as the app keeps them. The cassette is the app's own `TapeArt`, built for the site from src/landing/parts.tsx
  (`npm run build:landing`): it plays on a tap, its reels winding the tape across, and turns with the site's theme.
  The hand-drawn cassette, recorder, review and mark specimens are gone.
- **What the review of §153 found, where it still applies:** the privacy line now says that Claude's hosted connector
  holds your key while connected, and that the connector on your own computer keeps it there (Guide chapter 23); the
  Mac's first-open steps are the Guide's for macOS 15 and later; the third ink is a step darker, since it was under
  4.5:1 on Dawn and the light tints; the device's download is moved first in the page, not only drawn first; the
  browser's bar takes the page's paper; and reduced motion stills the buttons' movement too.

Cites: §147, §151, §153.

## 155. A mark on every filter (2026-09-30)

Matt: "all, notebooks, notes and 'Every workspace' should have left icons". Only Pinned had one in the filters' panel
(§148). Each Show choice now wears the mark its things wear on the page: All the grid of the foot's All notes,
Notebooks a notebook, Notes a page, Pinned the pin. Every workspace wears the workspace's folder (art/Icons.tsx), where
each workspace wears its colour. The marks are the second ink, a step up from the third, since they are the row's
picture now and not an empty space held for one (home/HomeFilters.tsx `ShowMark`; a test in home/HomeScreen.test.tsx).

Cites: §148.

## 156. Fields, tickets and queries: the grammar they share (2026-09-30)

Matt: "What other notion and jira like features can we code with custom markdown to add to our app like tickets and
such". Of the eight ideas that came back he picked three, "Do 1, 2 and 3 in parallel": fields on a to-do, tickets as
notes, and a query fence that lays them out as a table, a list, a board, a calendar or a gantt. Each has a section of
its own after this one. This one is the grammar all three read, written first and alone, so that none of them writes a
second copy of it: one grammar per syntax, in one pure module, tested line by line (core/itemSyntax.ts says why).

**Fields on a to-do** (core/taskFields.ts). Obsidian Tasks' own signs, so the line is a task in Obsidian too: 📅 due,
🛫 start, ⏳ scheduled, ✅ done, ➕ created and ❌ cancelled, each followed by an ISO day; 🔺 ⏫ 🔼 🔽 ⏬ for the five
priorities; 🔁 and a rule in words for a recurrence, kept and not yet acted on; Tasks' 🆔, ⛔ and 🏁 read and kept. A
person is ours, `@sam`: an at sign after the start, a space or an opening bracket, then a letter, so an address, a
redaction's `@@` and `@2pm` are not people. Any other field is Dataview's `[key:: value]`, which a query can ask for by
name, and Dataview's own `[due:: …]` stands for the date where there is no 📅. Fields are read anywhere in the words,
as Dataview reads them, but not in code, an address, a note link's title, maths, HTML or a redaction (core/blanks.ts
`quietRanges`). They are written where Tasks reads them: at the end of the words, in Tasks' order, a person or a
named field before that run, since Tasks stops at the first thing that is not one of its fields. The proposal's own
example, `📅 2026-10-03 ⏫ @sam #bug`, reads here, but Tasks sees only words in it, so the app writes
`@sam #bug ⏫ 📅 2026-10-03`. All of it goes before the item's tail (the bookmark, the mark, a counter, the anchor), so
the tail is still the tail: a board still finds its card and a Notion mark is still the mark. `withoutFields` gives
the words alone, for a card and for a title sent to Notion or GitHub.

**A ticket's properties** (core/properties.ts). Front matter read as named values, in order, through
`frontMatterEnd` and nothing else. That rule takes no YAML list written down the page, so a list is written across,
`["[[GHO-9]]", "[[GHO-10]]"]`, and read that way or with commas, as `authors:` is. A value YAML would misread - a
colon and a space, a ` #`, a leading `[`, `@` or quote - is quoted when written, and every value comes back as it went
in. A ticket is `type: ticket`; its keys and what each holds (a status, a person, a priority, a day, a number, links,
a list) are listed once for a panel and a query to share. The workflow is Backlog, To do, In progress, In review, Done
unless the notebook gives its own `statuses:`, and every status stands somewhere, as Jira groups them: not started,
under way, or done (Done, Closed, Won't do and Cancelled all finished with). A notebook's `key: GHO` numbers its
tickets: the next is one more than the highest number anything still names, so a number is never given twice.

**Days** (core/days.ts). A day is kept as its ten characters, so two compare as text, and it is the person's own day
by the device's clock: `toISOString` says it is tomorrow in New York at half past eleven at night. Days on and days
between are counted on the calendar, where no clock change moves them.

**What moved for it.** The tag's grammar left the editor for core/tags.ts, since a query's `from: #bug` reads notes
the editor never opened (editor/tags.ts draws from it). A front matter value's quotes come off as YAML's do, escapes
and all (core/frontMatter.ts `unquoted`), for every reader. The fills' queue writes its date with core/days.ts.

**Tests.** core/taskFields.test.ts (every sign, every place a person is and is not, the quiet words, Tasks' order
however the fields are added, the tail kept, and a line Obsidian Tasks still reads its due date from after the app has
written a person, a named field, a priority and a recurrence into it), core/properties.test.ts (front matter edges,
lists both ways, quoting that comes back as it went, statuses, keys and the next id), core/days.test.ts (New York's
evening and London's clock change), core/frontMatter.test.ts (YAML's escapes), core/tags.test.ts (moved).

Cites: §145.

## 157. Tickets as notes (2026-09-30)

Matt: "What other notion and jira like features can we code with custom markdown to add to our app like tickets and
such", and of the eight ideas, "Do 1, 2 and 3 in parallel". This is the second: a ticket is a note whose front matter
says `type: ticket`, numbered by its notebook like a Jira issue, drawn with its properties as Notion draws a page's,
and linked by its key. The grammar is §156's (core/properties.ts); this is what is built on it. The whole of it is
docs/TICKETS.md.

**The notebook's key.** A notebook takes `key: GHO` from its More sheet, as Ticket key, under its name: typed in any
case, written in capitals the moment it is a key, and what is wrong said while it is not (book/tickets.ts
`keyProblem`, `withNotebookKey`; editor/NoteSettings.tsx). Not a journal's. With a key, its index offers New ticket
beside Add a page (book/BookView.tsx): a title and what it starts with. The line goes into the index first, as a page's
does, and App makes the ticket (App.tsx `openTicketWithin`): `type: ticket`, the next id, and the workflow's first
open status, To do in the default since Backlog is where a ticket waits rather than starts (`firstOpenStatus`). The
next id is one past the highest number any note names, read from the store, the Trash included, at the press, so a
number is never given twice and nothing keeps a counter that two devices would have to agree on.

**The templates.** A Bug report and a Feature join the six built-ins (notes/noteTemplates.ts): a blank page's cards, a
Templates notebook's pages, and New ticket's choices. Their words open with the ticket's own front matter, and the
filler gained `{{next-id}}` (core/template.ts): the notebook's next key where the note is made, and, where there is
none, its `id:` line left out rather than written empty. Front matter is not words, so the card, the untouched record
and the caret all measure the words after it, as a look's key always was. A template's page carries the ticket's keys
in its one block, and passes them to the note it makes (notes/ownTemplates.ts), so your own Bug report is still one; a
page is drawn as the ticket it makes, with no key of its own. A ticket made with no key is offered its notebook's next
on its panel.

**The panel.** For a ticket, the folded front matter (§134) gives way to a panel (editor/tickets.ts; extended.ts
`frontMatterDrawn`): the key, then Status, Assignee, Priority and Due always, and Start, Estimate, Blocked by, Parent
and Labels where set or behind More (editor/TicketPanel.tsx, editor/ticketRows.ts). Statuses from the notebook's
workflow, in their category's colour; people the library already names, assignees and `@people` both, the most named
first, or one typed; the five priorities and None; the phone's own date picker under a day said as Today or Sat 3 Oct,
red once due has passed; an estimate and labels typed in place; other tickets found by key or title and linked by key.
Each pick is the smallest change to the front matter through `withProperty`, so one Undo takes it back and the key
keeps its case. A ticket waiting on one not done leads with a lock and the ticket. The caret in the block, the panel's
`{}` or its quiet line of other keys shows the lines, as every drawn block steps aside (drawnBlock.ts); a press on a
value keeps the caret out, as a board's card does. A view that cannot be edited draws it with nothing to pick. Only
where the screen gave the library's tickets (`WikiOptions.tickets`, App's shell/useTickets.ts): a card's small note
and a shared page draw the front matter as before.

**Keys as links.** `[[GHO-12]]` opens the ticket with that key, in any case: App's titles gained the tickets' keys,
after the titles, so a note called "GHO-12" still wins and a key nobody has is a link waiting to be written. The link
is drawn with the ticket's title after it, its status's dot, struck once done, but not inside front matter, where it is
a line of keys. Claude's `read_note` finds a ticket by its key the same way (mcp/server.ts).

**Where it is listed.** A ticket's key and status, small and in the status's colour, on home's cards, rows and lines
and a notebook's index rows (notes/TicketMark.tsx), its status placed in its notebook's workflow.

**Kept.** A rewrite through the MCP server that dropped the front matter whole gets a ticket's keys back; one that wrote
its own keeps it, and gets back only `type:` and `id:` (`keepKeys`). A notebook keeps `key:` and `statuses:`. The
library on disk keeps a ticket's block whole after its own, its `id:` never taken for the note's (a Rust test). The
cost: a ticket written in another app with its keys in the file's only block has that `id:` read as the note's
identity by the library; it is left for when the library merges a page's block into its own (docs/LIBRARY.md).

**Tests.** book/tickets.test.ts (the key and its problems, the next id past the Trash, the first open status, a new
ticket's body with and without a template, a ticket's notebook by index and by key, finding by key or title, waits,
people), core/template.test.ts (`{{next-id}}` filled bare or its line left out), notes/noteTemplates.test.ts and
ownTemplates.test.ts (the two tickets, made and kept as pages), editor/ticketRows.test.ts, editor/tickets.test.ts (the
panel in place of the fold, stepping aside, the smallest change, a key's title and its redraw), editor/TicketPanel.test.tsx
(every picker's write), book/BookView.test.tsx (New ticket, a row's mark), editor/NoteScreen.test.tsx (the key on the
More sheet, a pick written into the note), home/HomeScreen.test.tsx, App.test.tsx (New ticket's id past the Trash and
its status in a custom workflow; a key opening its ticket), mcp/server.test.ts, and src-tauri/src/library/tests.rs.

Cites: §134, §142, §144, §156.

## 158. Fields on a to-do: chips, a tap to change one, and saying them (2026-09-30)

Matt: "What other notion and jira like features can we code with custom markdown to add to our app like tickets and
such", and of the eight ideas, "Do 1, 2 and 3 in parallel". This is the first: a to-do's due date, priority and
person, proposed as `- [ ] Fix the login loop 📅 2026-10-03 ⏫ @sam #bug ^login-loop`, "due, priority and person as
chips: overdue red, @sam as a person", and "due Friday" or "for Sam" said to write the field. The grammar is §156's
(core/taskFields.ts), which writes the proposal's line as `@sam #bug ⏫ 📅 2026-10-03` so Obsidian Tasks still reads
its date; this section is what the app draws from it, what a tap and a press do, and what the recorder hears.

**Chips** (editor/taskFields.ts, editor/fieldChips.ts). Off the caret's line each field is a small chip in a tag's size
and weight; on it, the characters are there to edit, as a shortcode's emoji and a place's name are. The due day is
named from today: Today, Tomorrow, Yesterday, else "Sat 3 Oct", the year only when it is not this one, in the device's
own language as every other date in the app is, so an American phone says "Sat, Oct 3". It is in the red ramp once it
has passed and the box is not ticked, in amber on the day, and in the third ink once the box is ticked or a ✅ day is
on the line, since a finished thing is not late. Start, scheduled, done, created and cancelled days are quieter,
unfilled, each with its word ("Starts tomorrow"). A priority is Jira's chevrons, two up for highest to two down for
lowest, in red, amber, blue and the third ink, its name for a screen reader. A person is their initial in a purple
ring and the name as written, `@sam-ortiz` shown as "sam ortiz". A repeat is a small repeat mark and its words; a
named field is its value with its key quieter before it; Dataview's own `[due:: …]` is drawn as the due day it stands
for. Tasks' 🆔, ⛔ and 🏁 are left as written: ids for Obsidian to follow, which nothing here acts on. Nothing is drawn
in code, an address, HTML, a comment, maths, a blank's question or the front matter. A chip is an inline block, so it
is given `text-indent: 0`: a list item's line hangs off its marker with a negative indent, which a chip inherited and
pulled its own words out of its box by, the first thing the phone-sized shots showed.

**A tap changes it, through the menu the note already has.** Not a new kind of menu: a tap on a due, start or
scheduled day, a priority or a person opens press and hold's band (editor/ContextMenu.tsx) at the chip, on that
field's page (editor/FieldItems.tsx), in the band's own hand. A day offers Today, Tomorrow, Next week, Pick a date and,
when it has one, Remove, the day it has lit. Priority offers the five, the most urgent first in the chips' own marks,
and None. A person offers Remove. The chip is drawn by CodeMirror and the band by React, so the tap reaches the band as
an event on the editor's element (editor/fieldMenu.ts `FIELD_TAP`), as a press and hold reaches it as the browser's
`contextmenu`. The press is kept from the editor as the suggestion pill's is, so the caret stays and the keyboard does
not rise; and the editor is given its focus back after a choice only where it had it. A chip with no menu - a repeat,
a named field, a done day - is the editor's: a tap puts the caret on its line, where it is the characters again.
Pick a date is the phone's own picker, a native date input opened with `showPicker` from the press itself. The input
is the page's, not the band's: the band closes on a press as every row's does, and the keyboard going down can scroll
the page, which closes it too, so an input inside it would be gone before the picker answered.

**Adding one.** Of the places a line's actions are offered, the + beside the line is for an empty line only, and a
linked line's drawer is a Notion task's; a list item's are press and hold's. So on a list item the band now offers
**Due date**, **Priority** and **Assign** after Move down, each turning the band to its page with Back to the actions.
Assign offers the people the note already names, each lit where they are on the line and pressed on and off, the band
staying open for a second, and Someone new, which writes the at sign where a person goes and leaves the caret after it.
Next week is the Monday of next week, a week that starts on a Monday, as a British calendar's does: the day a thing put
off to next week is looked at again (core/dayWords.ts `nextWeek`, which the voice's "next week" is too).

**Saying them** (capture/spoken/fields.ts, core/dayWords.ts). While a list item is spoken - a to-do, a done one, a
bullet, a step, or an item added to another note's list - a due day, a priority and a person said at its end are
taken off its words and written as its fields: "remember to call the plumber due Friday, high priority, for Sam" is
`- [ ] Call the plumber @Sam ⏫ 📅` and Friday. High precision, as every spoken rule is (capture/markdown.ts), since a
false field takes words out of what was said: a cue is read only at the end of an item, in any order, each kind once.
"Due" needs a day it can read after it (today, tomorrow, a weekday, "next Friday", next week, the weekend, "in two
weeks", "the third of October", "October 3rd", "the third"), so "the rent is due soon" is words. A priority is
"high priority", "top priority" (highest), "low priority" and the rest, "priority high", or "urgent" (high). A person
is "for" or "assigned to" and one or two capitalised words, since Whisper writes a name with a capital, so "for now"
and "for dinner" are words; not a weekday, a month or a holiday ("for Friday" is when, not who); and not after a thing
given or booked, "a present for Sam", "flights for Lisbon", which is who it is for or where. "Due next week." or "High
priority." said on its own a breath after an item belongs to that item; "For Sam." on its own does not, since it may
be the start of something else. A weekday is the next one, today included; "next Friday" is the Friday of next week; a
date with no year is the next one. An item that is nothing but a cue, "Urgent.", stays the words it was. The day is
counted from the person's own day when the take is rendered (core/days.ts).

**An item's words leave its fields out** wherever they are its title or its card: a task sent to Notion or an issue to
GitHub (core/itemLinks.ts, which reads the words for finding the item again the same way, so a send still marks its
line), a board's card (core/boards/items.ts `cardText`), an anchor made for an item ("Call @sam 📅 2026-10-03" is
`call`), the home page's open to-dos, and progress under a heading, which counts no box with only fields after it.
Tags stay words. A board card shows the due day, the priority and the people as chips of its own, at the start of its
footer under the words (editor/boards/fields.ts), and a tap on one opens the band for the item's line. The preview a
note card draws is the note's own editor, so it draws the chips too, with no taps. Search finds a priority by its name,
"high priority", since nobody types the sign; a person and a day are found as written.

**Not done.** The Notion plugin sends a task's title and nothing else, so the due day is not sent as the task's date:
that would need the board's date property read when the board is chosen, and the swipe's send to carry its line. A
repeat is kept and drawn, and ticking one does not make the next. A board card's own menu has no rows for fields:
its chips open the band instead.

**Tests.** editor/fieldChips.test.ts (each field's look, days named in British, the tones), editor/taskFields.test.ts
(chips over a real editor: the caret's line as written, nothing in code, front matter or a blank, a tap told to the
menu and the caret kept), editor/fieldMenu.test.ts (the days offered, the people named, each edit one undo, the date
picker), editor/FieldItems.test.tsx (the band's pages through ContextMenu, from a chip and from the line's actions),
editor/boards/fields.test.ts (a card's words and chips), core/dayWords.test.ts, capture/spoken/fields.test.ts, cases in
capture/markdown.test.ts and capture/listAppend.test.ts, voice tests 119 to 124 (voice-tests/suite.json), and the
words left out in core/itemLinks.test.ts, core/boards/items.test.ts, editor/headingProgress.test.ts,
home/dashboard.test.ts and notes/allNotes.test.ts. The cheat sheet has four rows (a due date, a priority, a person, a
field by name), taught by one Academy lesson, Fields on a to-do; the Guide's Lists and to-dos has a section, Saying
the marks its cues, and Boards made of list items the card's chips. docs/MARKDOWN.md and docs/BOARDS.md say the same.

Cites: §127, §145, §156.

## 159. A query: the database view, written as a fence (2026-10-01)

Matt: "What other notion and jira like features can we code with custom markdown to add to our app like tickets and
such", and of the eight ideas, "Do 1, 2 and 3 in parallel". This is the third, proposed as a fence of a few lines,
`from: #bug`, `where: status != Done`, `sort: priority, due`, `show: table`, drawn as a table, a list, a board, a
calendar or a gantt, with totals that reuse a sum's arithmetic, and "a code block, like the board fence" in any other
app. It reads the other two: a ticket is §157's front matter, a to-do's fields are §158's, both through §156's grammar
and never a second parser. docs/QUERIES.md is the grammar written down for a person; this is why it is this one.

**Built in two halves.** The three were built at once by three agents on the shared grammar. The query's agent was
stopped by a rate limit with the pure half written and untested (read, records, values, run, gantt, and the sums'
arithmetic moved to core so a total and a sum agree); the tests, the drawing and this were finished by hand. Its tests
found two things worth keeping: a gantt bar whose start was written after its due day ran one day instead of between
the two, and, once the fields' half had merged, a query read every to-do's fields as empty, since core/itemLinks.ts
`itemWords` had learned to leave fields out of what an item says. A to-do's fields are now read from its line's own
words (`lineWords`), and what it says from `itemWords`.

**The grammar** (core/query/read.ts). One clause to a line, each left out for its default, the names Dataview's and
Tasks' where they have one (`from`, `where`, `sort`, `group`, `limit`, and `sort by:`, `group by:`), so a person who
has written those reads this. `from:` is a kind first (`notes`, `tickets`, `tasks`), then `#tag`, `[[note]]`,
`@person` and `"words"`, side by side for all, with `or`, `not`, a dash and brackets. `where:` is tests joined by `and`
before `or`, `not` and brackets; a field alone is a test that it says something. Words need no quotes, so `status =
In progress` reads as written, and a status with `and` in it is quoted. A field's name is Dataview's form
(core/taskFields.ts `fieldKey`), and the names Dataview and a person also use are read as the app's (`completed` is
`checked`, `people` is `assignee`). A query that cannot be read is never half run: its first problem is answered at
its line and column in a sentence a person can act on, and a line it does not know offers the one within two letters.

**The values** (core/query/values.ts) are why the words mean what a person meant. A priority compares by rank, the
most urgent the greatest, and none sits between medium and low as Tasks sorts it. A status compares by its place in
the workflow, the notebook's own `statuses:` or the default, so `status < Done` is the open ones in order. A number is
read as a sum reads one. A person is one person however written. A list is equal to anything it holds, a tag holding
the tags inside it. Anything compared with a field that says nothing is false but `!=`, as Dataview has it, so
`due < today` never lists the undated, and a field no record has is empty rather than an error, since a query may name
any front matter key there is.

**The defaults** (core/query/run.ts) make one line useful. A tasks query lists the open ones unless it asks about being
done. Notes come the last changed first; tickets the most urgent, then the soonest due, then by key; to-dos the
soonest due, then the most urgent; nothing in a field last, whichever way. A ticket board has every status of its
workflow as a lane, empty ones and all, as a Jira board does. A table is the default for tickets, a list for the rest.

**The library** (core/query/records.ts, shell/useQueries.ts). Every note a screen shows, less the archive and the
templates' pages, the open note as its editor has it, so a to-do typed under a query of to-dos is in it at once. A
note's reading is kept by its id while its words stay the same, one cache per editor, so a keystroke reads one note
again and not the library.

**Drawn** (editor/queries.ts, editor/QueryView.tsx). In place of the fence while the caret is elsewhere, as a board, a
table and a diagram are (editor/drawnBlock.ts); the pencil at its head puts the caret in its lines. A card in the
page's tinted surface, as a ticket's panel is, in the app's face, with a quiet head of what it lists and how many. A
cell is drawn as its value: a due day by when it is and red once late, a priority as the fields' chevrons, a person in
their ring, a status with its category's dot, a ticket's key in mono, a tag as a tag - the looks a field has on its
line and a ticket has in a list, so a thing reads the same wherever it is. A month is a grid of days with a dot for
each record and the picked day's records under it; a gantt is Mermaid's, through the diagrams' own cached, queued,
themed path. It is drawn again when the note changes, when App hands new notes, and at midnight, when `today` moves.

Three things the phone-sized shots showed. A block widget's width decides the editor's, and a table's columns made
every line of the note as wide as the table: the query takes the board's measure of the note's width
(`--cm-board-room`) and scrolls inside it. A table squeezed to the card wrapped a chip onto two lines, so it is as wide
as its columns and scrolls. And Mermaid's dark theme draws the words on and beside a finished, an under-way or a late
bar in a near-black ink marked important, so beside its bar they vanished: a dark page now gives Mermaid a gantt
palette of dark bars that carry light words, edged by what they are, which mends a gantt written in a note too.

**A tap.** A name opens its note or ticket; a to-do opens its note at its line, a landing by number (`line:N`,
editor/useLandAt.ts) since most to-dos have no anchor, or, in this note, puts the caret there. A to-do's box ticks it
where it is written: in this note with the tap on a box's own edit (editor/taskToggle.ts `toggleBox`), its boards
settled in the same undo; in another through App, the store's copy changed by core/query/tick.ts, which finds the line
where the query read it or by its words if the note has moved, settles that note's boards the same way, and leaves a
line that is gone alone rather than tick the wrong one. Nothing else a query draws writes anything.

**Not done.** A board is read only: a card is moved by changing its ticket or its box, not by dragging it across, which
would mean a status written into a note the query is not in. A calendar's day does not make a to-do. A query does not
query the Trash or the archive.

**Tests.** core/query/read.test.ts (every clause, the defaults, the words, each problem at its place),
core/query/run.test.ts over a library fixture (the records, from:, where: by kind, the order, the limit, the cells,
boards, groups and totals, the gantt's text), core/query/gantt.test.ts, calendar.test.ts, fence.test.ts,
tick.test.ts, core/sums.test.ts, editor/queries.test.ts (drawn over a real editor: each way to show it, live as it is
typed and as the library changes, the problem's sentence, the lines with the caret in them, no pencil and no tick
where it cannot be edited, and what each tap does here and in another note), editor/useLandAt.test.tsx (a line by its
number), and the + menu's A query (editor/addRows.test.ts). The cheat sheet has a row, A query, taught by an Academy
lesson; the Guide's Boards made of list items has a section.

Cites: §156, §157, §158.

## 160. Ready-made databases, a dated to-do and a ticket, on the + (2026-10-01)

Matt: "Give me an example database to copy and make templates for databases on the + menu as well as the other new
stuff". The three features of §156 to §159 were each reachable only by knowing their syntax, bar a query's one seed:
a person who has never written `where: due <= today+7` would not write it. So the + offers them as things to pick.

**A database** (More › A database, editor/addRows.ts, editor/AddList.tsx) is now a page of its own, as More is the
first page's, with Back at its top going back to More rather than the first page, by the back gesture and the Left key
too. On it, ten ready-made queries (core/query/templates.ts): to-dos due this week, overdue to-dos, to-dos by person,
to-dos on a calendar, a ticket board, open tickets with their estimates and a total, a ticket timeline, notes changed
this week, how many to-dos are open, and Write your own. They name no notebook, tag or person, so each finds something
in any library the moment it is put in, or says plainly that nothing matches yet; and they are written the way
docs/QUERIES.md teaches, so the lines behind the pencil are an example of the grammar as much as a database. Each is
written as a block with the caret on the line after it, so it is drawn at once rather than showing its lines; Write
your own is the one left open, its kind selected to be written over. Each row wears what it shows: a list, an alarm
clock for the late ones, people, a calendar, a board, a table, a gantt, the history, a sum, a pencil.

**A to-do with a due date** (More, after A choice): a to-do where A to-do would put one, its words "To-do" selected
to be written over and `📅` tomorrow after them, as one change and one undo (`datedPlan`). Tomorrow, because a thing
written down now is most often for tomorrow, and the chip is there to tap for any other day (§158).

**Make this a ticket** (More, after A database, in a note that is not a ticket, a notebook or a canvas): `type:
ticket`, and `status: To do` where the note has no status, written into its front matter as one change, the caret and
the words where they were (`ticketPlan`). The panel then draws, and offers the notebook's next key where it has one
(§157's Give it GHO-14).

**Tests.** core/query/templates.test.ts (each reads, runs, and is shown as its row says, over the queries' library
fixture), editor/addRows.test.ts (the page's rows, a template drawn at once and Write your own open, the dated to-do
and its one undo, the ticket's front matter with and without a status, and the row only where it can be one), and
editor/AddList.test.tsx (More to A database and back to More, by Back and the back gesture). The Guide's Lists and
to-dos and Boards made of list items say where they are; docs/QUERIES.md and docs/TICKETS.md too.

Cites: §156, §157, §158, §159.

## 161. The Academy in chapters, with standard Markdown to skip (2026-10-01)

Matt: "Rework the ghost.md academy so that there is the option to skip default markdown if the user doesn't want to
learn that, additionally make sure it's up to date with the latest features like boards and query's. Make chapters in
the lesson as well".

- **It opens on its contents** (`academy/AcademyScreen.tsx` `Contents`), not at a lesson: seven chapters, each with a
  line on what it covers (`CHAPTER_ABOUT`) and how much of it is learned, a tap to start one at its first lesson not
  learned, and Start or Continue for the first lesson not learned anywhere. Learned everything, it is the summary.
- **"I know Markdown already"** is a Glacier switch on the contents, kept (`glyph-academy-skip-standard`). It leaves
  out every lesson marked `standard`, which is what any Markdown app reads the same way: all of Markdown basics, and
  a table, a picture and a footnote from More Markdown. Ghost.md's own marks (a video, a callout, a diagram, maths,
  everything after) are always taught. Markdown basics then reads Skipped and cannot be opened; the count is of what
  is left.
- **A chapter ends on a page of its own** (`ChapterEnd`): its lessons with their ticks, each to take again, and Next:
  the following chapter that has lessons on offer, or Done at the last. A lesson's head says which chapter it is:
  "Chapter 5 · Boards and to-dos · 2 of 5". Back from a lesson or a chapter's end is the contents; from the contents,
  out.
- **The chapters**: Markdown basics, More Markdown, Lines that do more, Links and places, Boards and to-dos (fields
  on a to-do, a name for an item, that item from the words, a board, a board's height), Tickets and queries (a
  ticket, a ticket notebook's key, a query, where:, show:, group: and total:), Marks and effects. The old Pointing
  somewhere is split between the middle three.
- **A lesson can go further with a mark another owns** (`rows: []`): a board's height, a notebook's key, a query's
  where:, show: and group:. The cheat sheet still has one row per mark, taught by exactly one lesson.

## 162. Maths drawn by KaTeX, and marks drawn in a view nobody is typing in (2026-10-01)

Matt, of the Academy's maths lesson: "should the maths be formatted any special way or do something?", then "yes" to
drawing it; and of the emoji lesson: "it should appear when :smile: is done".

- **A formula is drawn** (`editor/mathsDrawn.ts`): `$…$` in its line, `$$…$$` alone on a line or between two lines of
  `$$` set in the middle of the page, by KaTeX. KaTeX was already in the app through Mermaid; it is imported, with its
  stylesheet, the first time a note has a formula, so startup is unchanged and it draws offline. With the caret on its
  line (or in its block) a formula is what was typed, set as code. One KaTeX cannot read stays as typed, dotted under,
  what is wrong said in its title. Found by core/maths.ts, so prices stay prices, and never in code or front matter.
- **The caret's line only counts in a view being typed in** (`editor/extended.ts` `decorate`): a read-only view or one
  without the focus has its caret at the top, unseen, and an emoji, a definition's colon and the like on the first line
  stayed as typed there - the Academy's preview, a note just opened. Now they are drawn until somebody is typing.

## 163. The tickets' first pass: a model that would not run, and a place at the top as the header (2026-10-01)

Matt: "Use the glyph connector … and work through the open issues assign yourself on them as well". The Glyph
notebook (§157) held eighty tickets, GLY-1 to GLY-80, moved from the old board; seventy-five were Done and five To do.
Each was set to In progress with Claude as its assignee through the connector before it was worked, and Done, with a
line saying what changed and where, when it was.

**GLY-1, pull to refresh on a note,** had shipped already (§152): closed with a pointer to it.

**GLY-2, "Summarizing doesn't work, it fails every time with 'summary didn't come'", and GLY-5, "FFI error when
trying to fill details like {?weather in Tokyo Japan}", were one fault.** §145 had found it and left it: Gemma 4
E4B could not run at all, every request answering "cannot apply the chat template: ffi error -1". llama.cpp renders a
conversation from templates it recognises by a few characters each (`<|im_start|>` for Qwen's ChatML,
`<start_of_turn>` for Gemma 2 and 3) and answers -1 for any other; llama-cpp-2 reports that as "ffi error -1", and
Gemma 4's template is none of them. With Gemma 4 chosen, every summary failed three times and was given up ("The
summary didn't come"), and every fill said the error. Two fixes, one for the binary and one for the page, since a
binary is a new install and the page can go over the air today:

- **The engine renders the template itself** (src-tauri/src/llm/prompt.rs `render_template`, generate.rs). Where
  llama.cpp does not know a template, the model's own Jinja, `tokenizer.chat_template` in its file, is rendered with
  minijinja and Python's string methods (`minijinja-contrib`'s pycompat), with the variables Hugging Face's renderer
  gives it: the messages, the generation prompt, the BOS and EOS tokens as their text (the tokenizer, which parses
  special tokens, reads them back as tokens), and `enable_thinking`; `raise_exception` and `strftime_now` are there.
  A template that refuses a system turn (Gemma 2's raises) is rendered again with the system prompt at the head of
  the user's turn. The rendering is cut at the sentinel as before (`frame`), so the prefix is still snapshotted.
  Tested in tools/host-tests against ChatML as Jinja (matching llama.cpp's own rendering), Gemma 3's and Gemma 2's
  templates, and a template in marks llama.cpp has no name for, written with `namespace`, `break`, `.strip()`,
  `tojson` and a thinking switch. The engine's files compile against the pinned llama-cpp-2 with no warnings. Not
  run on a phone with Gemma 4 here: the container cannot reach Hugging Face for the file.
- **The page passes over a model this binary cannot run** (core/runnable.ts). A run that fails on its chat template
  remembers the model against the binary's version, and `modelFor` chooses from the other models on the phone while
  there is one, so the next summary, fill and phone write-up (its config is sent again) go to a Qwen. A write-up the
  phone failed that way marks it too (ai/summaries.ts `refreshJobStates`). The failure is said as "Gemma 4 E4B can't
  run in this version of Ghost.md. Choose another model in Settings › AI, or install the newest Ghost.md.", and
  Settings › AI says "Can't run in this version of Ghost.md." under it. A newer binary is asked again. With only the
  failing model on the phone, it is still the one tried, so the failure is still said.

**GLY-3, "Map location when placed at the very top of a note should produce a full screen header of the map instead
of the slim card".** A map note's look (§144) draws where the note was written as its header; a place line put at the
top was still the slim card. Now a place on the note's first line with words, or on the one straight after it (a
note's first line is its title), is drawn as the header: the same MapCard at its `header` size, across the column up
to 48rem, 10rem tall on a phone and 16rem from 600px (core/placeRefs.ts `topPlaceLine`, editor/placeCards.ts). Words
put above it make it the card again, as a place further down is.

**Tests.** core/runnable.test.ts, core/ai.test.tsx (the worded failure, the model remembered), core/placeRefs.test.ts
and editor/placeCards.test.ts (the top place and the card below it), and the Rust templates in
src-tauri/src/llm/prompt.rs, run by tools/host-tests.

Cites: §144, §145, §152, §157.

## 164. A specification under About, held to the code (2026-10-01)

**GLY-4, "Add specification page under the settings page, it should strictly define all our custom AI fills, and
custom markdown format extensions as well as a link to the official base markdown spec".** The cheat sheet (§138)
teaches what to type; nothing said exactly what the app reads. Settings › About › Help has a sixth row,
**Specification**, a sub-page as the cheat sheet is (settings/SpecPane.tsx).

- **The base, linked.** CommonMark and GitHub Flavored Markdown, opened in the browser, then the two places the
  editor differs from a renderer's defaults: setext headings are off and HTML is shown as text.
- **Every extension, defined.** In parts: what other apps share (links between notes, tags, item anchors, callouts,
  footnotes, definition lists, raised and lowered, maths, emoji, diagrams, fields on a to-do), the Marks plugin's own
  marks, the app's own lines and blocks (counter, sum, choice, progress, bookmark, place, video, board, ticket,
  query), the AI fills (a blank, what answers it and in what order, a filled answer's note), the front matter keys
  the app reads, and template placeholders. Each says how it is written, the rule, and how any other app shows the
  same characters.
- **Held to the code three ways** (settings/specification.ts). Where one pattern is the rule (a tag, an anchor, a
  counter, a choice, the bookmark, maths, a place, a blank, a filled answer's note), the page shows the pattern the
  app runs, imported from the module that runs it, so it cannot drift; `TAG` is exported from core/tags.ts for it.
  Every mark the cheat sheet teaches is covered by a definition, and a test fails when a new one arrives without one.
  And each shown pattern is tested against the entry's own example.
- **Found by Settings' search** by each definition's name and its part's title, not by the characters (the cheat sheet
  is found by those, and an example's words, a board's `height=`, would answer searches meant for other pages). A name
  a page draws its own way is marked `data-findable`, which `findSetting` now reads beside the kit's rows. So "ai"
  finds the AI fills on every device, where it found nothing on one with no model.

**Tests.** settings/specification.test.ts; AboutPane.test.tsx and SettingsSheet.test.tsx for the row, the sub-page
and the search.

Cites: §138, §156, §157, §158, §159, §163.

## 165. Priorities drawn with the kit's icons, never the emoji (2026-10-01)

Matt: "for priorities use icons from glacierui not emoji". A to-do's chip, the field menu and a query's cell already
drew Jira's chevrons from @glacier/icons; the ticket panel still put the emoji before a priority's name and on each row
of its sheet. It now draws the same chevrons in the same colours (red for highest and high, amber for medium, blue for
low, quiet for lowest), from one map (editor/fieldChips.ts `PRIORITY_ICON`), which the field menu now shares rather than
keeping its own. The emoji stay what a to-do is written with, Obsidian Tasks' characters, so a note reads the same in
Obsidian; they are never what the app draws. Tested in editor/TicketPanel.test.tsx.

Cites: §157, §158, §159.

## 166. Checkboxes and radios drawn over their own characters (2026-10-01)

Matt: "for checkboxes and radios render a large UI component where the [ ] or (x) would be but make them take up the
same physical space in the note". A to-do's box was its three characters in the accent and the monospace face, and a
choice's the same; now each is drawn as a control (editor/boxControls.ts): a rounded checkbox, filled with the accent
and a check when ticked, and a ring with a dot when a choice is picked. Each is 1.3em, larger than the letters it
stands on and narrower than their three-character width.

**The same space.** The box is one widget drawn in place of the three characters, holding those characters inside it,
transparent, so it is exactly as wide as they are with nothing to measure, and the control is centred in their width.
The characters are still in the document, so a copy and the Markdown view take them, a wrapped item hangs under its
first word (glyphLines.ts measures them), and a tap ticks or picks where it did (taskToggle.ts, choices.ts). It gives
way to the characters while the caret or a selection touches them — the edges included, since a replaced widget has
no inside for the caret to land in — so a box can still be written by hand.

**One widget, not a mark (2026-10-01).** It was first a `mark` over the characters with the box drawn as a `::before`.
A toggle's edit splits the characters into two text runs, and the mark could be drawn over both, so for the length of
the fill's transition the box appeared twice (Matt: "the checkboxes duplicate when clicking during the animation").
A single widget cannot split; updating it in place when it is ticked (`updateDOM`) rather than building it again keeps
the fill's animation and never draws the box twice.

**Writing one by hand.** While the caret or a selection is inside the three characters, they show as typed, as a
mark's characters do. A caret before the box or at the words keeps the control. Nothing is drawn in code, where
`- [ ]` is characters.

**Tests.** editor/boxControls.test.ts: every box and choice found with its state, the characters kept, revealed only
with the caret inside, and none in code.

Cites: §156, §158.

## 167. Everything, as one zip on a USB drive (2026-10-01)

Matt: "Please add a feature that allows me to plug in a USB drive and export the entire app onto a folder or zip file
with ghostmarkdown_<datetime>.7z or something". Settings › Account has an Export card after Location, with one row,
**Export everything**, signed in or out.

**A zip, not a 7z.** A Mac, Windows, Android's Files app and every Linux desktop open a zip with nothing installed; a
7z needs an app on all of them. It is named `ghostmarkdown_2026-10-01_21-42-05.zip` on the device's own clock (no
colon, which a FAT drive will not hold), and holds one folder of that name, so opening it makes a folder, not a
scatter of files. "A folder" is what opening it gives.

**What is in it** (src-tauri/src/export.rs). `Library/` as docs/LIBRARY.md has it, every note a Markdown file in its
folders, with `.glyph/library.json` and each recording's phrases; `images/`, `video/` and `recordings/`; the page's
`README.txt`, which says what each folder is, and `settings.json`, the preferences, plugins and workspaces; and a
`manifest.json` with the date, the binary's and the page's versions and the counts. Left out: the index (a cache,
rebuilt from the files, with its journal files), a save or a download under way (fsx.rs's `.<hex>.tmp`, `.part`),
the models (gigabytes, downloaded again), a meeting's write-up under way, the over-the-air builds, and anything that
signs in: the account's session, the sync key, the Notion and GitHub tokens. A drive is easily lost.

**Written as a stream.** Words are deflated and media stored as they are (they are compressed already, and a WAV
barely shrinks); Zip64 takes over past 4 GB. Checked here with a 4.4 GB film: `unzip -t` and Python's zipfile read it
whole, UTF-8 names included. A stream needs no seek, so one writer serves both apps:

- **The Mac** (`export_save`): the system's save panel (tauri-plugin-dialog, called from Rust, so no page permission
  names it), a USB drive among its places, and the archive written to the file chosen.
- **Android** (`export_fd`): the activity opens the system's picker to make the file (files/ExportTarget.kt,
  ACTION_CREATE_DOCUMENT, no permission asked), opens it, and hands the page its descriptor
  (`window.__glyph.exportTarget`), which the page passes to Rust. Nothing is built in the phone's storage first, so a
  library with gigabytes of films needs no room for a second copy. The descriptor is taken only when it is a new,
  empty, plain file outside the app's own storage (export.rs `adopt_descriptor`); a number passed by mistake is
  refused and never closed, so it cannot write over the index or a recording or end a pipe of the WebView's.
- **A browser** zips the notes and pictures it keeps on the page (share/zip.ts), and saves it through the browser's
  save picker where there is one, else as a download.

**Its words.** While it runs, a callout says how far it has got ("Exporting, 1.2 GB of 3.4 GB. Keep Ghost.md open,
and the drive plugged in.") with a bar and Stop; after, what it wrote. A failure is said as what happened to the
drive: full; formatted as FAT32, which stops at 4 GB; taken out; read-only. A failed or stopped export takes its
half-written file away, so the drive holds only an archive that opens. One export runs at a time. An iPhone says it
cannot yet; a binary before native generation 22 says to update.

**Native generation 22**, gated on the page (`EXPORT_GENERATION` in core/exportAll.ts), so `BUNDLE_REQUIRES` stays
at 19: the export needs the new binary on the Mac and on Android, and nothing else does.

**Tests.** export.rs, run by tools/host-tests: what is listed and left out, the archive read back with its folder,
compression and manifest, a stop, the drive's failures in words, the name, the zip's clock, and the descriptor
taken or refused (and left open). core/exportAll.test.ts: the name, the settings without a secret, the README, each
platform's way, Android's picker handshake with the file kept or taken away, the Mac's panel and its progress, and a
browser's zip. The whole Tauri crate type-checks and passes clippy on Linux (desktop); the Android branch and the
Kotlin are not compiled here, with no Android SDK in this container.

Cites: §141, §157, §163.

## 168. Back to the characters: `[ ]` and `( )` as typed, still tapped (2026-10-02)

Matt, after living with §166: "Go back to making the checkboxes and radios actual symbols and stuff the checkboxes look
good but they're hard to interact with and I think the plain text but interact able is better". The drawn checkbox and
radio are gone (editor/boxControls.ts and its test are deleted, and the editor no longer loads them). A to-do's box is
its characters again, `[ ]` and `[x]` in the accent and the monospace face (markdown.module.css `.taskMarker`), and a
choice's `( )` and `(x)` the same (choices.ts), as they were before §166.

Nothing about the tap changed, because it never belonged to the drawing: a tap on the three characters, or within a
thumb's slop of them, still ticks a box or picks a choice (taskToggle.ts, choices.ts, boxTaps.ts), and the caret goes
into the brackets like any other characters, which is what the drawn control made hard: it had to give way to the
characters before they could be touched, and as one widget (§166's second form) it had no inside for the caret at
all.

§166 stays as the record of what was tried, and why it went.

Cites: §166.

## 169. Values you can press: pickers for a query's and an index's fields (2026-10-02)

Matt: "make parts of query boards and stuff intractable, I'd like to be able to click things like done labels in order
to change the status and just have more interactivity with data in the tables queries and index's use modals with
iconography and color".

A query (§159) drew its records' values and wrote nothing but a ticked box and, since the board's drag, a card's lane.
Now every value a person sets is a button where the note can be edited: a status, a priority, a person and a due, start
or scheduled day, in a table's cell, a list's line and a board's card (`editor/QueryView.tsx` `Picked`). A press opens
a sheet of its choices (`editor/FieldPicker.tsx`), the app's one bottom sheet (`editor/Sheet.tsx`) with the kit's rows,
and the choice is written where the record is. Which sheet a field opens, and with what it holds now, is
`editor/fieldPicks.ts` `pickOf`, pure and tested; a title, a tag, a note's name, an estimate and a day the app keeps
(`created`, `updated`) open nothing.

**Marks and colours.** Each choice wears a mark in its colour, and the cells wear the same ones, so the sheet reads as
the row it was opened from:

- **A status** by where it stands in its workflow (`statusLook`): a dashed ring for a backlog (Backlog, Later, Someday,
  Icebox), a ring not started, a dot under way in blue, an eye in review in purple, a tick done in green. In a cell it
  is a pill tinted in its colour, where it was a dot and words. A status the workflow does not name is offered too, so
  the one a record has is never missing from its sheet; No status takes it off.
- **A priority** in Jira's chevrons, the colours its chip has on a line (`editor/fieldChips.ts`); None.
- **A person** as their initial on a round of their own hue, one of six from the kit's scales, the same for a name
  however it is written (`hueOf`): the people the library names, the most named first (`book/tickets.ts` `peopleIn`,
  now read from any `{ body }`), a name typed, and No one. Read only when the sheet opens, since it reads every note.
- **A day**: Today under the sun, Tomorrow under a sunrise, Next week under the calendar, Pick a date (the phone's own
  calendar, `editor/fieldMenu.ts` `pickDay`), and Remove in red where there is one.
- **A to-do's status** is its box: To do or Done, which ticks or clears it (`onTick`) only where that is a change.

**One writer.** The board's drag (`onMove`) and a picked value (`onSet`) go through one function in
`editor/queries.ts`, `setField`: into the editor for a record in this note, one change and one undo; through the screen
for one in another (`QueryOptions.move`, App's `moveFromQuery`, `core/query/move.ts`), which reads the notes again. A
to-do's person is not a named field but its `@people`, so `withTaskField` takes off whoever is there and puts the one
picked on; anything else on a line goes through `withField` as before. A row carries its workflow now (`Row.workflow`),
so a status's sheet offers its own notebook's statuses rather than the default.

**Not a drag.** A press on a value stops at the value: it never starts a board's card being carried (`startDrag`),
whose own press on the card is unchanged.

**The index.** A notebook's index (`book/BookView.tsx`) had each ticket's key and status in quiet words inside the row's
button. Where the index can be changed, the key stays there and the status becomes a pill of its own among the row's
tools, which opens the same sheet on the notebook's workflow (`notes/TicketMark.tsx` `TicketStatusButton`), written
through the queries' writer by the page's title (`NoteScreen.tsx` `setStatus`). On a phone the pill is its mark alone
in its colour: beside the tools, its words left "Pricing pa…" of a title at 412 wide. Read only, the index draws the
status in words as before.

Measured in the preview at 1280, 820 and 412 wide: a table's In progress picked as Done wrote `status: Done` into
GHO-1 and its board followed; an index's To do picked as In progress wrote `status: In progress` into GHO-2.

## 170. Notifications (2026-10-02)

Matt, in the brief that is §171's: "implement a full notification system and put the invites in there with an inline
accept and deny also wire up existing features to notifications where it makes sense so that we see things like
claude creating a new note or making edits etc, there should be a notifications section in settings in order to
customize the notifications we receive".

Until now the app told a person things only as they happened and only where they stood: a toast for a voice command's
note with Undo, "Summarized …" with Open, a fill landed (shell/useHousekeeping.ts); and two rows that reach the phone
itself, About's "Update alerts" and Recording's "Tell me when a meeting is written up". Nothing was kept, nothing
reached another device, and no account could tell another anything. The feed is the thing that can: what the
service knows about a team, and what the account knows about itself, in one list the bell counts. The whole of it,
the wire and the limits, is docs/TEAMS.md; this is why it is shaped as it is.

**One table, two shapes.** A notification is a row in `notifications`, keyed by account and id and fed on the
account's one write counter. A row the service writes - an invitation, who joined or left, a rename - carries its
kind, who caused it, the organization and a small plaintext body, because the service is the one that knows and
another account caused it; that is the only shape an invitation can take without new key material (§171). A row the
account writes about itself - Claude's writes through the connector, a meeting written up, a note kept twice - carries
a blob sealed under the account key as `{ kind, ...details }` with `notification:<id>` as its associated data, as a
note is sealed under `note:<id>`. The review asked whether `kind` belonged in the seal, since a column alone could be
relabelled by anyone who can write the file and a `note-edited` drawn as `summary-written` would defeat a mute; so
the kind rides inside, the client trusts it over the column, and the column stays for the service's pruning and the
device's unread count, which never opens a seal.

**On the account's counter, read state included.** The feed takes `accounts.rev` through `Store::next_rev` inside
every write's transaction, as notes, settings and recordings do, and pages by the notes feed's cursor rule, so a
device resumes it exactly as it resumes notes. Read and hidden live on the server rather than in a device flag, so
that a row read on the phone is read on the Mac: every change to a row - read, hidden, an invitation answered - takes
a new revision and the row is fed again, hidden rows included, as deletions ride the notes feed; a device applies a
fed row only when its revision is above its copy's. Pruning orders by `created_at`, never by revision, which a read
mark moves. The cost, which the review named and the privacy lists now say: the server learns when each
notification was read or hidden, where before it saw when things change and never when they are looked at. It is
polled as the first step of the sync pass, before the notes, so a note a row names has arrived by the time the row is
drawn; fetched again at once after an inline answer and when the page opens; no nudge over the live relay in this
slice, since the relay keeps only a socket count per account and the client holds no socket unless a note is live,
and an unknown frame is dropped by every client already, so a nudge can come later without a wire change.

**What the person does here is theirs at once.** A read, a hide, Mark all read and an invitation's answer apply
locally and queue a mark, replayed at the start of the next pass and dropped when the service confirms it; while a
mark is pending the local state wins over any fed row that still lacks it, since a page fetched before the mark landed
would otherwise undo a tap. Mark all read carries this device's cursor (`before`), so it marks only what was shown.
An answer refused as "You were not invited." was given on another device: the mark is dropped and the feed fetched
again. The answer is keyed by the organization, not the row (`answerInvite(orgId, accept)`), so the Organizations
page can answer an invited row it has no notification id for.

**Opened lazily.** The design first opened sealed rows as they arrived and kept them in memory; the review found that
after a reload nothing arrives, so every row of Claude's would draw without its title until a pass happened to come,
and that one bad blob opened inside the pass would stop the cursor at its page for ever. So a sealed row is opened at
draw time, memoised by id, never in the pass: until then, and for one that will not open, it is drawn by its kind
alone, "Claude edited a note", and the bell counts from the plaintext fields.

**Which events.** The kinds table (docs/TEAMS.md) is the judgement Matt asked for in "where it makes sense". The
service writes nine kinds about a team. Claude's five come from the connector's side, since the service cannot tell:
the note is ciphertext and a token carries no device, and a write Claude makes is indistinguishable on the wire from
a phone's. The other way, each device noticing a known AI's name arriving in a note's authors, was turned down: it
fires once per device, only for a signed write, and never for a client that signs nothing. `note-edited` carries a
line diff, `{ added, removed, first, at }`, because the review found "Claude edited Trip to Lisbon" had nothing to
open onto - the app kept no note history then (§182 adds one, for the notes that ask for it), and `update_note` holds both bodies at the moment of the write and threw
the difference away; now the row reads "· 2 lines changed", the first changed line sits under it, and the note opens
at that line's anchor. `add_journal_entry` makes two writes and one row; the Claude rules note is announced only when
it is made, not on every connect. The app's own two: `summary-written` where a recording's summary lands
(ai/summaries.ts `said`, before the toast's gates, so a row lands whether or not the toast is shown) and
`sync-conflict` where a pass keeps a copy, by a hook on the sync context (`onConflict`) rather than a field on the
pass's outcome, which ten test literals compare whole. Voice commands and fills are the person's own act and already
toasted, so they are not recorded.

**Four switches, synced; no phone row.** Settings › Notifications has team, claude, summaries and conflicts, and a
row to mute each organization, kept in the synced settings as every chosen setting is (last writer wins, and a mute is
a tap to choose again); every row is still written and the page filters. An invitation has no switch: off, the inviter
would wait for an answer that could not come. The design had a row for the phone's own notifications; the review
showed it promised what nothing could do - the host has only permission calls, no `notify()`, and no sync runs while
the app is closed - so the row is gone and the pane's footer says what is true: "Ghost.md looks when it opens; the
bell shows what arrived." The native piece (a `notify` host call and a worker that polls the plaintext kinds) is a
follow-up. The summaries row's hint, "Here, in the list; the phone's own notification is under Recording", keeps the
two rows that read as one thing apart; "Update alerts" and the meeting row stay where they were.

**Listed beside Account, in coral.** The pane is a listed section in group 0, after Account, since both are about
what reaches you; coral was one of the two hues `settings.css` defined and nothing used. The row's summary is "n of 4
on", Plugins' shape, rather than an unread count, which would couple the sheet to the feed. The label arrays
SettingsSheet.test.tsx pins each grow by one.

**The bell and the page.** A bell ring in the tab row after the two arrows and before the slot, whose unread state is
`data-on` with a 6px ink dot and no number - the bar's rings are monochrome and nothing in it carries a figure; the
count lives on the page's head and the Settings row. The Notifications page is a `Screen` like All notes (a place,
with the tab row): a row per notification with the kind's icon from the kit, its sentence (`sentenceOf`, the one
place the words live) and when; an invitation's row has Accept and Decline, one `InviteActions` component shared
with the Organizations page and the home page's card for the newest pending invitation whose organization is in the
list; a note kind opens the note, `note-edited` at its first changed line; an organization kind opens the
organization; Mark all read, pull to refresh, the ghost when empty. Muted categories and muted organizations are not
drawn. Signed out, or under Local only, the page explains with the Account `GoWord` idiom.

**Limits.** Three hundred rows kept per account, pruned inside the write transaction by age, the read-or-hidden first
and never a pending invitation, so a flood of self rows (an MCP session editing note after note, sixty posts a minute
allowed) cannot push an unanswered invitation out; read-or-hidden rows go after sixty days. A post is 8 KB of blob in
a 16 KB body, and idempotent: an id the account already has answers its stored revision and writes nothing, so a
retry after a lost answer makes no second row. A kind the service makes cannot be posted.

**Not yet.** The service ships before the page (§171), so a 404 whose body is the service's `no such route`, or no
service body, is "not yet" and the step is quiet; every other 404 is an answer in the service's words. One helper,
`notYet`, for the pass, the pages and the connector.

**Measured.** On the branch at d2da88dc, a `vite build` served by `vite preview` on 127.0.0.1:5280 (alice) and
localhost:5280 (bob) against the branch's glyph-api on 127.0.0.1:18799, in the desktop app's browser pane
(Chromium), two accounts made through Settings › Account. At 412×915 the bell is a 39px ring at x 189 with its
6px dot 6px in from the top and the right; the page's head reads "Notifications" at 19.4px with the count pill,
"Mark all read" 104×54 at the right; an invitation's row is 367 wide at x 22 and 99 tall with the sentence over
two lines, "Accepted" under it and the date at the end. At 1280×900 the bell is 46px at x 243, the list 768 wide
at x 26, and a row 75 tall ("bob accepted your invitation to Ghost team · 6 min ago"). The flow, live: alice
invited bob by handle, bob's bell lit on the page's open, Accept settled the row and lit alice's bell on her
next launch, and bob's "Ghost team" workspace appeared in his filters with the org mark. Two defects found on
that run and fixed before merging: the service answered its moments in seconds (a member "since January 21"),
and an answered invitation stayed unread. No shots folder was kept; the measurements were read live.

**Tests.** Server: notifications_tests.rs (a post read back and a repeat landing once; the kinds and the limits; read
marks and hiding fed again with a new revision; the cursor rule; one account never seeing another's; three hundred
kept with the read ones first and never a pending invitation; sixty a minute) and store/notifications.rs's own.
Client: core/notifications/feed.test.ts (two devices converging on read and hidden; a mark kept over a row fed before
it landed; an invitation answered inline and answered elsewhere; the two 404s; a sealed row opened lazily, never
stalling, trusted for its kind), kinds.test.ts (the sentences), record.test.ts (sealed, unsent on failure and sent by
the next pass, idempotent, nothing without a key, kept here under Local only), core/sync/engine.test.tsx (the order
of the pass), core/account/api.test.ts (`notYet`), core/ids.test.ts, core/preferences.test.ts and sync/prefs.test.ts
(the switches, settled and travelling), reset.test.ts (the feed's key goes). Screens: NotificationsScreen.test.tsx,
NotificationsPane.test.tsx, SettingsSheet.test.tsx (the label arrays, the findables, the summary), App.test.tsx.
Connector: mcp/server.test.ts (a notification after each write, none after a refused write, the tool still answering
when the post fails) and mcp/hosted.test.ts (the hosted author's name rides in the payload).

Cites: §113, §127, §138, §143, §164, §171, §173.

## 171. Organizations (2026-10-02)

Matt: "build the ability to create teams in the app. We should be able to create an organization in order to add
users as team members by handle, adding a team member should show them an invite, while doing this also implement a
full notification system and put the invites in there with an inline accept and deny also wire up existing features
to notifications where it makes sense so that we see things like claude creating a new note or making edits etc,
there should be a notifications section in settings in order to customize the notifications we receive. There should
be a way to view an organization. Organizations should also get their own workspace automatically, when on the
organization view make a new settings screen copying the same layout and stuff from the normal settings page but make
it tailored towards organization features." The spelling is organization, his word and the app's (Summarize); the
code says `org`. The notifications half is §170; the model, the wire, every refusal sentence and the limits are
docs/TEAMS.md.

**Plaintext, and said so.** Nothing could be shared across accounts before this: the only keys are the account key,
which never leaves a device except wrapped, and Ed25519 signing keys. An invitation by handle with an inline accept
needs the service to know the organization and who is in it, so an organization's name, hue, members' handles, roles
and invitation states are plaintext on the service, as handles already are, and the notes stay per account and sealed.
The other two shapes were weighed and left: an organization key wrapped per member under a new per-account
encryption key is true end-to-end for a team's notes and names but a new crypto design, a membership-aware relay and
an org-owned feed; a secret carried out of band, as a share link carries its key after the `#`, needs a second channel
to deliver it, which contradicts "add by handle". The four places the app states its promise - docs/SYNC.md, the
privacy policy, the Play data-safety answers and the Guide's chapters 19 and 26 - now say what an organization puts in
the clear, and that the server learns when a notification was read.

**Not shared yet, and the screen says so.** "Organizations should also get their own workspace automatically": each
member's devices get a workspace named after the organization, in its hue, the moment they join. It is not a shared
note store - the filing map is per-person settings, and a note filed in it is sealed under its owner's key - and the
review found that a member who files a note there expects teammates to see it and sees nothing. So the Workspace
section's footer and the Members hero say it in Matt's register: "Notes filed here stay yours for now; sharing them
with the team comes next." The organization key above is the follow-up.

**Inviting by handle resolves the handle.** `POST orgs/{id}/members { handle }` answers 404 "No one has that handle."
when nobody has it. Every way in was written so that asking reveals nothing about which handles exist, and signup's
"That handle is taken." was the one leak; this is the second, and the first a signed-in account gets. Matt was told
the two shapes - confirm the handle, or answer "invited" either way and withdraw an unanswered invitation later - and
did not object to the first, which is the one that makes the form usable. The price is paid in the limiter: thirty
invitations an hour per inviting account and per address, per hour rather than per minute, spent before the lookup so
a refused attempt still costs; and docs/TEAMS.md names the oracle in one sentence. "They are already a member." is a
second, smaller tell, counted the same way.

**One owner, who has joined, at all times.** The roles are owner, admin and member. The review found the first draft
could leave an organization with no owner (an admin removing the owner, or the owner demoting themself), or with an
owner who had not joined (a hand-over to an invitee): nobody could then rename, hand over or delete it, and the rule on
deleting an account no longer held anyone, so the organization was immortal. The invariant is kept in store/orgs.rs
and nowhere else: nobody removes the owner (403 "Hand the organization over first."), an admin may remove only members
and invitees (403 "Only the owner can remove an admin."), the owner's own role changes only by a hand-over (the same
403), a hand-over to someone who has not joined is 409 "They have not joined yet.", and `role: 'owner'` set on a
member is one transaction that makes the old owner an admin. Deleting an account is refused inside `delete_account`'s
own transaction - not a check before a separate delete, which an acceptance could slip between - while the account
owns an organization anyone else is in, joined or invited: 403 "Hand over or delete your organizations first."; an
organization whose only row is its owner's goes with the account, and in the same transaction every organization the
account had joined is told it left. Only `account_id` and `owner_id` cascade: `invited_by` and `from_id` are SET
NULL, so an inviter leaving the service takes nobody with them and a row in someone else's feed keeps everything but
its sender, which reads as "Someone".

**An invitation's life.** The review found a write into a stranger's feed with no cap and no memory: any account could
push a fresh card onto someone's home page twenty times a minute and, in a quarter of an hour, evict every real row.
So inviting someone already invited refreshes `since` and writes no new row; declining keeps the row as `declined`
for a day and the same organization cannot ask again ("They declined; ask again tomorrow."), after which the same
`invite` row flips back to pending - one per person per organization, ever; an invitee may have twenty waiting across
every organization; an organization holds fifty rows, joined and invited; pruning never takes a pending invitation.
An organization that dies settles every pending invitation as declined and hidden in the same transaction, since a
pending row with a dead Accept was the other thing the review found, and the home card draws only invitations whose
organization is in the current list. A withdrawn invitation is settled the same way and nobody else is told.

**The workspace's id is `org-<orgId>`.** The design had each device mint an id and mark the workspace with an `org`
field; the review traced what last-writer-wins settings do to that: two devices make two workspaces for one
organization, the loser's filings are dropped when the other blob wins, and a build from before this rewrites the
settings without the field (`asWorkspace` rebuilds `{ id, name, hue }`), so the reconcile finds no mark and makes a
second "Ghost" beside the first. The id is the truth now: every device of every member makes the same one, a filing
keyed by it survives whichever blob wins, the mark is read from the prefix on every read and never trusted from
storage, and the reconcile is idempotent. It runs after a 200 list only, over rows with state `member`: a list that
did not arrive - offline, the deploy gap's 404, a 500 - leaves the workspaces and the cached list as they were, since
reading a failure as "no organizations" would unfile every member's notes and push that to their other devices; and
it runs outside `applyingRemote`, so its change is pushed by `syncSoon` rather than waiting for the next pass. On disk
the folder is `orgs/<name>` (`folderFor` takes the workspace, not its name, so the type system found every caller),
`addWorkspace` dedupes names among personal workspaces only, the hue follows the organization and its swatch is not
offered, Rename and Remove refuse it, and the pill, chip and folder row carry `data-org` with a small mark before the
name, so two "Ghost" pills can be told apart.

**Not told what you did.** The service writes a rename, a removal or a deletion to the other members only, as the app
toasts a voice command rather than recording it; who accepted hears nothing of their own acceptance; the asker hears
`invite-accepted` (or the owner, if the asker has since left) and everyone else `member-joined`. Every server body
carries the organization's `name` at the time, and the live name is joined at read time only while the reader is
still a member, so someone removed does not go on reading every later rename through their old rows.

**The view is a settings screen, landed on Members.** "There should be a way to view an organization", and then "when
on the organization view make a new settings screen copying the same layout": the organization is a `Screen`,
`{ name: 'organization'; orgId; from? }`, drawn by `OrganizationSheet` as a second `SettingsScreen` with `title` (the
organization's name) and `search: false`, since five sections need no search pill. The review's point was that on a
phone a SettingsScreen opens on its list, so "view an organization" would have shown five rows and not one member; so
it opens landed on Members through `goTo`, and Members begins with a hero - name, hue chip, member count, your role -
then the list with role chips and state, invite by handle, remove, and the owner's role change and hand-over. The
sections are General (name and hue, editable for the owner and an admin), Members, Workspace (the workspace, its
"stay yours for now" sentence, and a way to the notes filed in it), Notifications (mute this organization) and Leave
or Delete last, in the danger tone. Back from Members steps to the section list; from there back closes. `title`
threads to every hard-coded "Settings" word in SettingsScreen.tsx and to `backWord`'s root, so the head and the
dialogs name the organization. Opened from Settings › Account › Organizations, `from: 'settings'` makes its close
reopen Settings on the Organizations page and its head read "← Organizations", since the personal sheet is a boolean
that had closed under it and a person opening three organizations would otherwise walk the list three times. It is
also opened from an organization workspace's pill (second tap), "Edit {current}" on the home filters, a folder's "…"
in the tree, and any organization notification.

**Where organizations are made.** Settings › Account › Organizations is a sub-page of Account (`listed: false`,
`parent: 'account'`, the first under it), a row between Sync and Shared links: the organizations you are in with
role and member count, an invited one with Accept and Decline, and New organization (a name, then the organization
opens). The review found four taps under a page about signing in a long way to a first team, so "New organization"
also sits beside "New workspace" in the home page's filters when signed in.

**Deploy order.** glyph-api first, on Matt's word, then after the login gap the web OTA with `--mcp` and the hosted
connector; the page tolerates the gap in one direction through `notYet` (§170), and the deploy's probe fails when
`GET /api/v1/orgs` without a token is not a 401, since an old binary answers 404.

**Measured.** The same run as §170. At 412×915 the organization's section list sits under "← Organizations":
General 56, Members 65, Workspace 64, Notifications 65 and Leave 56 tall, each 367 wide at x 22, in three cards
as Settings' are; Members opens on the hero (the hue round, "Ghost team", "2 members · You are member") over the
D1 sentence and the rows "alice Owner — owner since 6 min ago" and "bob Member — You, joined 4 min ago". At
1280×900 the split view keeps the list beside the pane; the owner's Members pane adds the invite field and, once
bob is invited, his row "Invited by alice" with Withdraw and the status line "bob is invited. They see it in
their notifications." Under Account › Organizations at 412: "Ghost team — Member · 2 members" and the New
organization card. In the home filters at 1280 the org's pill wears the mark beside "Every workspace", with "New
organization" under "New workspace". The org screen refetches its members only when it opens, so alice's open
Members pane still read "bob Invited" after bob accepted until it was opened again.

**Tests.** Server: orgs_tests.rs (made, listed, read, renamed and deleted by its owner; a name, a hue, a role and an
id checked before anything is looked up; a stranger's one 404 from every route; an invitation telling the invitee and
an acceptance telling the asker and the rest; declining settling, telling the asker and making the organization wait
a day; every invitation refusal in its words; the owner invariant through the routes; a rename reaching every member
once with a former member keeping the old name; deleting an organization settling its invitations; an asker deleting
their account leaving the invitee a member, and an owner with others refused; the limits on owning, inviting and
changing), store/orgs.rs's own, and every new route in sync_tests.rs's
`every_signed_in_route_refuses_in_the_same_words`. Client: core/orgs/orgs.test.ts (the calls in the service's words;
the reconcile on a list that arrived and only then, over members only, one workspace per organization across devices
with no filing lost; the list kept per account and forgotten on signing out), core/workspaces.test.ts,
core/noteFolders.test.ts (`orgs/<name>`), reset.test.ts (the list's key goes). Screens: OrganizationSheet.test.tsx,
AccountPane.test.tsx (the row and the sub-page), SettingsScreen.test.tsx (`title`, `search`), sectionSteps.test.ts
(`backWord`'s root), HomeScreen.test.tsx (the invitation card), App.test.tsx.

Cites: §42, §100, §138, §143, §170.

## 172. A new library's examples, and a note's menu on a right-click (2026-10-02)

Matt: "Please pre populate new accounts with an example board, example tickets (3) example journal and an example with
all the formatting, add context menus so i can right click on desktop to delete a note".

**The starter notes.** A fresh library got one note, the sample with every mark the app draws (core/sampleNote.ts). It
now gets eight, once, the same way and under the same mark (core/seed.ts `seedSampleNote`, the `glyph-sample-note`
flag), so a library that already has notes is never given any:

- the example board, Launch week (core/boardNote.ts);
- a notebook, Example project, with the ticket key EX, and its three tickets (core/starterNotes.ts): EX-1 Plan the
  first release, Done; EX-2 Fix the sign-in loop, In progress, Sam's, highest, due in two days; EX-3 Write the welcome
  page, To do, due in a week, blocked by EX-2, so its lock shows. One in each kind of status, so the index's pills
  (§169) show all three colours, and each with a short paragraph and its to-dos;
- a journal, Journal, with its first entry named by the minute it was made, filled from the journal's default
  template, as New entry fills one (App.tsx);
- the sample note, made last so it is the newest and leads Recent.

Each is written by the functions the app uses when a person makes one (`bookNoteBody`, `withNotebookKey`,
`newTicketBody`, `journalNoteBody`, `withEntry`, `entryBody`, `fillTemplate`), so they open, change and sync as
anything made by hand, and deleting one takes nothing else with it. The mark is now set before anything is made, so a
second pass while the first is still writing makes nothing twice.

**A note's menu.** A mouse's right-click on a note's card (notes/NoteCard.tsx, the home page's grids and All notes), a
home page row, line or notebook cover (home/HomeScreen.tsx) and a sidebar row (notes/NoteTree.tsx) opens a menu at the
pointer (notes/NoteMenu.tsx): Open, Pin or Unpin, Archive or Unarchive, and Delete in the danger tone. Each does what
the card's swipe does (§151) through the same actions: Delete closes the note's tab and puts it in the Trash with an
Undo (notes/useNoteActions.ts), so a right-click is never a way to lose a note. The tab row's own menu (notes/
TabMenus.tsx) gains Delete note, the same delete.

One menu for the app, mounted once by App.tsx, and opened through a small store (notes/noteMenu.ts): a list only says
which note and where the pointer was. Drawn with the kit's Menu, as the tab menus are, hung from a point of no size
where the pointer was, in a layer on the body. Not the kit's ContextMenu, which also opens on a touch's long press: on a
phone that press is a card's swipe and a tab's drag, so only a mouse opens this menu (`byMouse`: the event's
`pointerType`, or, where a WebView does not say, a screen whose pointer is fine and can hover). (Since §197 it is hung
through editor/PopMenu.tsx, which also closes it on a press anywhere and the back gesture.)

## 173. The walkthrough hands over; the rings move behind the mic (2026-10-02)

Matt, in one message and a follow-up: "Remove the 'start a voice note with speak' step from the signup process, move
the ripple waves effect to show behind the mic icon in app when recording, remove the settings section for the side
button ripple position too" and "remove the 'every mark, side by side' section, and for the 'a few habits' instead show
the option to learn about markdown and other stuff, take the ghost.md academy or 'start'".

**Four pages.** The walkthrough is Welcome, the theme, the model, and a last page that hands over (`guide/pages.ts`,
`guide/pages/Start.tsx`): "Learn it, or just start." The marks, the words you can say, boards, canvases and the rest
are the Academy's, and the page offers it as a pill under its words; Start, in the dock where Try it was, closes the
guide and lands on the home page, which offers the Academy again to anyone who started writing first (the card on the home page,
`academy/banner.ts`). The side-key page (§47, §18), the marks page and the habits page are deleted, with the shapes, the waves and
the tables that were only theirs: `guide/pages/SideKey.tsx`, `Marks.tsx`, `Tips.tsx`, `guide/SideKeyWaves.tsx`,
`guide/waves.ts`, `guide/sideKeys.ts`, `guide/assistant.ts`, and `art/Shapes.tsx`'s phone. The table of side keys
lives on in Matt's Notion ("Side keys on flagship phones") as a record; nothing in the app reads it. The voice cues are
taught beside each mark on the cheat sheet alone now (`guide/MarksTable.tsx`'s "say" line), and `guide/phrases.ts`'s
examples still hold the recorder to them in `guide/guide.test.ts`.

**Too soon** (`guide/tooSoon.ts`) is measured from the last page instead of the side-key page: every page before it
is reading, and a launch by the key while the guide was left on one still brings the guide back with its line. The
side key is behind the developer flag either way (since 2026-09-28), so this is the rare case kept honest, not a path.

**The rings.** The recorder's rings rose from the screen's edge where the phone's side key was guessed to be, only
for a recording the key had started (`capture/sideKey.ts`, `capture/SideKeyWaves.tsx`, §43), and Recording in
Settings carried a card, "The side key", to slide the guess into place. All of that goes. The top line of the recorder
now begins with a microphone (`CaptureScreen.tsx`, `.mic`), a mark that the mic is live, and the rings rise from
behind it for every recording, Speak's and the key's alike (`capture/VoiceWaves.tsx`): the layer measures the mic's
box and centres its rings there, so there is nothing to guess and nothing to set. The voice still sends them out
(`capture/voiceLevel.ts` `paceRings`, §43), in the faintest ink, under the top line so the mic sits in front of them.
Recording's search words lose "The side key" (`RecordingPane.findable.ts`); Appearance's "Ripples while recording",
the wisp through the words, is a different thing and stays.

Cites: §18, §43, §47.

## 174. Notifications in a drawer under the bell (2026-10-02)

Matt: "revamp the notifications make it all in a drawer instead of full screen, also the items in the list are clipped
right now. and don't render 100% width".

§170's notifications were a page in the pane, drawn where All notes is, with the tab row over it. They are now the
floating card the notes drawer and the aside already are (notes/FloatingCard.tsx), hung at the right under the bell
(notes/NotificationsDrawer.tsx, which was NotificationsScreen.tsx): the page that was up stays where it was and live
beside the card, and a tap outside it, Escape, the phone's back gesture, its cross or the bell again closes it. The
bell is its toggle (`data-notifications-toggle`, `aria-expanded`), lit while it is open. Opening a note or an
organization from a row closes the drawer behind it. The `notifications` Screen is gone (shell/screen.ts); the
palette, a `ghostmd://notifications` place link and an organization's screen open the drawer through App's
`showNotifications` as before.

**Its width.** `wide` on the floating card: 26rem on a desktop, and on a phone the window less a margin each side
(385px at 412), never the window's width. The page version took the pane's whole width.

**Its rows.** A row is a grid of the kind's mark, the words and when. The words column takes what is left and wraps,
so a long organization's name or note title breaks onto the next line rather than running off the card; the line
Claude changed is held to two lines (`line-clamp`), where it was one cut with an ellipsis; when keeps a column of its
own; Accept and Decline sit under the words and may wrap. The head is the name with the unread count, Mark all read
and a close, over a hairline, with the rows scrolling under it inside the card. The ghost for "Nothing yet" is the
small one. The page's own top bar, its wisp at the head and its pull to refresh went with it: the drawer takes the
feed again each time it opens, as the page did.

Measured in the preview with a fake session and five rows: at 1280 the card is 416px at the right under the bell; at
412 it is 385px, and no row is wider than its card.

## 175. An organization's dashboard, with its settings behind a cog (2026-10-02)

Matt: "Design and deploy a dashboard for organizations when clicking an organization in the header don't take me to
the settings, instead, take me to this dashboard page and have a organization settings icon on that".

§171 made the organization's view its settings: a second SettingsScreen landed on Members. An organization now has a
page of its own, `notes/OrganizationScreen.tsx`, and the `organization` Screen is that page (`{ name: 'organization';
orgId }`, the `from` gone); the settings became an overlay over whatever is up, held beside `screen` in the Shell as
the personal Settings are (`orgSettings` in App.tsx).

**What opens which.** Looking at a team opens the dashboard: the tab row's organizations icon, a notification about
it, a `ghostmd://org/<id>` link, an invitation accepted on the home page, one just made from the home filters, and a
second tap on its workspace's pill. Editing opens the settings: the dashboard's cog, the edit words on
its workspace (Edit on the home filters, a folder's "…", the workspace's sheet) and Settings › Account › Organizations.
From the cog they open on their list of sections, since the page under them already shows the team, and their head
names the organization as the place it goes back to (`from: 'dashboard'`, `closeWord`), not "Back to your notes";
from Settings they open on Members and close back to Settings, as before. Left or deleted from its settings, the
dashboard has nothing to show, so closing goes home.

**The page.** Built as All notes is: the glass bar with the arrow home, the organization's name with its colour, and
the cog at the bar's end (`aria-label` "Organization settings"); under it the scroller with its smoke and a pull to
refresh. With more than one organization, a row of pills moves between them. The hero is the colour's round, the
name, "2 members · You are owner" and the sentence that notes filed there stay yours for now (D1), with New note,
which makes a note already filed in its workspace and opens it ready to type, and, for an owner or an admin, Invite,
which brings the invite field into view and focuses it. Then three sections: **Notes**, the six newest filed in its
workspace as the home page's cards, with All N to the home page on that workspace; **Members**, each with an initial,
the handle, the role's chip and "You, owner since …" or "Invited by …", and the invite field for an owner or an admin,
whose refusals are the service's own sentences; and **Activity**, the organization's own news from the feed (joined,
left, removed, renamed, a role changed, an invitation answered), eight at most, with a way to the notifications. On a
window 44rem wide the members stand in a column beside the notes and the activity (`grid-template-areas`, rows `auto
1fr` so a long members column never pushes the activity down). Invited and not yet in, the page is the invitation
with Accept and Decline; gone from the list, it says so; signed out or under Local only, it says why, with a word to
Account. The members are read when the page opens, when the organization's news arrives and on a pull, so someone
who accepts while the page is open is a member a moment later.

**Two things found on the way.** Accepting an only invitation from the home page did nothing visible: the pass that
delivers the answer takes the list of organizations again, the card is drawn only while the invitation is open, so
it went mid-pass, and InviteActions told its page only while it was still drawn. It now tells the page of a
delivered answer either way; only its own words wait on being drawn. The home page's test held its fake pass so the
page is drawn again before it ends, as the network holds a real one, and fails without the fix. And on a phone the
home page was 19px wider than the window: the dock's halo (GLY-81's ghost blur, `inset: -2.4rem`) spilled past the
edge, and a focus slid the whole app sideways. `.screen` clips its sideways overflow (`overflow-x: clip`, not
`hidden`, so it is no scroller); the halo is cut only where it was past the window.

Measured in the preview against a local glyph-api with two accounts: alice made Ghost team and invited bob from the
dashboard (the member list said "bob Invited"); bob's accept on his home card opened Design crit's dashboard at 412px,
2 members, the document 412 wide; alice's dashboard showed bob as a member and "bob accepted your invitation to Ghost
team" under Activity. Tests: OrganizationScreen.test.tsx (the hero and members, the cog, New note, filed notes, the
invite's refusal and success, a member without invite, the activity's filter, the invitation, the pills, gone,
signed out), App.test.tsx (the cog over the dashboard and back, a pill to another, Settings' route), the
OrganizationSheet case for the cog, and HomeScreen.test.tsx's only invitation.

Cites: §170, §171, §174.

## 176. Claude can delete notes, as far as the Trash (2026-10-02)

Matt: "clean up the extra claude rules delete them, add the ability for claude to delete notes".

The connector had no delete on purpose ("Claude on the account: the MCP server", 2026-09-18): archiving was what it
could do, because the app could undo it. It now has `delete_notes` and `restore_notes` (mcp/server.ts), and they go
exactly as far as the app's own Delete: the Trash (core/trash.ts), a synced setting of note ids and when each went in.
A deleted note leaves the lists, search and links on every device at their next sync and waits, whole, in the sidebar's
Trash folder; the app or `restore_notes` brings it back to where it was, its workspace, pin and archive untouched.
Emptying the Trash, the only delete for good, stays the person's, in the app. So Claude's delete is as undoable as an
archive, and means what the person means by delete.

The other tools now know the trash. `list_notes` leaves it out, and lists it alone with `in_trash`, the most recently
deleted first, for `restore_notes`; `search_notes` leaves it out; a title finds only notes out of it, as a link in the
app does, while an id still reads a trashed note, which then says `inTrash`; `account_status` counts it apart; and a
"Claude rules" note in the Trash is never the rules (the same day's fix made the rules the oldest live note of that
title, f1f13732).

The settings are written as `file_notes` writes them (`changePrefs`): read with their revision, only `trash` changed,
written back, and read again and redone once if another device wrote in between. A note deleted twice keeps its first
time, and the answer says which notes were already in the Trash, or not in it to restore. No notification is posted
for a delete: the feed's kinds are the service's to know, and a new one is a glyph-api change.

Tests: mcp/server.test.ts "deleting notes, to the Trash" (moved with every other setting kept and the note whole; the
lists, search, a title and the status leaving it out; read by its id, saying so; restored; twice, and never deleted,
said apart; a rules note in the Trash not the rules) and the tool list.

Cites: "Claude on the account: the MCP server".

## 177. Clearing notifications, and Mark all read that reaches every row (2026-10-02)

Matt: "I cant clear out old notifications from 17 mins ago and older".

Two things stood in the way. The drawer (§174) had no way to clear a row at all: only Mark all read, which keeps the
rows. And Mark all read marked the rows at or below the device's cursor (core/notifications/feed.ts), which is right for
the service but not for what the drawer shows: a row held above the cursor, fed by a page whose cursor never landed,
stayed unread through every press.

- **Mark all read** now marks everything the device holds: `before` is the greater of the cursor and the highest
  revision among its rows. The service reads it as "everything this device had seen", as before.
- **A row's cross** clears it (`hide`): hidden here at once and on every device once the service has the mark. With a
  mouse the cross shows as the pointer comes over the row or the keyboard reaches it; on a touch screen it is always
  there, faint.
- **Clear all**, in the drawer's head beside Mark all read, clears every row shown (`hideAll`, one change; the service
  hides a row at a time, so each is its own mark, replayed by the next pass). It leaves an invitation still waiting for
  its answer, and such a row has no cross: it is the one place to answer it. The word goes when nothing is left to
  clear.

Measured in the preview with a fake session, four rows held above the cursor: Mark all read left none unread, and Clear
all left the waiting invitation alone.

## 178. The top bar six ways, and the home page's four layouts as cards (2026-10-03)

Matt: "redesign the top header with 5 different styles for me to chose from make them all actually unique and
different keep the tabs but feel free to re arrange things and make some UI/UX decisions to make things cleaner",
then, with the five on a canvas: "I'd like to be able to pick the different header styles from within the app
settings, also cut the home page layout selection down to 4 items and show them in cards representing the actual
layout".

**The five, and Classic.** The bar as it was is Classic, and stays the default so nothing moves until it is chosen.
The five are the same pieces in a different order and shape (notes/NoteTabs.tsx `style`; core/preferences.ts
`TopBar`, synced, stamped on the root as `data-topbar`), so a tab is dragged, grouped, renamed and closed the same
whichever way it is drawn:

- **Ledger**: the tabs first, as a browser has them, with Home pinned in the row as a house tab; the open tab opens
  down into the tool row, which is paper with a line under it and belongs to that tab. The row is always drawn, so
  Home always is, and the bar is always two lines.
- **Strip**: one line. Home pinned as the first capsule, the tabs scrolling as capsules between the controls, the
  cross on the open one alone. The bar never grows a line.
- **Masthead**: the controls as the app's own words - Home, Notes, Back, and Forward only when there is somewhere
  forward to go, Teams for the organizations - and the tabs as an index line under a rule, the open one underlined.
  The screen's own rings stay rings.
- **Islands**: no bar. Three capsules of glass float over the page, the floating cards' glass and shadow (app.css):
  the way around (home, sidebar, the arrows), the tabs, and the screen's own (its tools, Organizations, the bell,
  More, the aside). The page scrolls under them: the screen's header pane and the split layout's bar paint no glass.
  On a phone the tabs' capsule wraps to a line of its own; in two panes the three share one line, so the bar is one
  line tall there whatever is open.
- **Thumb**: the bar names the open note, its workspace's pill and its name centred between the rings; the tabs
  stand in a strip of glass at the foot of the screen, in a thumb's reach, only while a note is open. `data-foot` on
  the root adds the strip's height to `--app-safe-bottom`, so the home page's dock, a scroller's last line and a
  sheet clear it without knowing it is there, as the headers clear the bar.

In every way but Classic the cross is the open tab's alone (the mockups' decision, which Matt chose from): the others
close from their menu, or once opened. The organizations icon stays in the bar in every way, as Matt had placed it
the day before - except on a phone in the Strip and in Thumb, whose one line cannot hold seven rings and still show a
tab: measured at 412px with a note open, the Strip's tabs had 60px, the open one's pill and none of its name, and
Thumb's middle the same. There, under 600px, an arrow with nowhere to go and the Organizations ring stand down
(Organizations is also the home filters' and Settings'), which leaves the tabs about 170px, and Thumb's bar drops its
own Home ring while the foot is up, since the house is pinned there. What the shell needs of a style is two questions, shell/topBar.ts `barRows` and `barFoot`: the bar's
heights are named once in app.css (`--app-tabs-one`, `--app-tabs-two`, `--app-bar-extra` for the Islands' capsules)
and chosen by `data-tabs`.

**The home page's layouts, cut to four.** Nine (§147, §148) were too many to choose between. Spotlight, Cards,
Timeline and List stay, the four that differ; the mixes (Card timeline, Shelf and timeline, Notebook cards), the
Shelf and the Library went with the code that drew them - the covers, the dense cards, the notebook sections and the
pages-of-a-notebook plan. A layout chosen that is gone falls back to Spotlight.

**Cards that are the thing.** Both choices are radio cards now, as the themes and the interface size are
(settings/LayoutCards.tsx, settings/TopBarCards.tsx; choiceCard.module.css): each card a small picture of the page,
or the bar, drawn that way in the page's own ink - rings, tabs, capsules, the index line, the foot strip; the search,
pinned line, cards and rows - with its name and a sentence under it, the chosen one ringed and ticked.

The five were drawn first as a design canvas, a phone and a Mac artboard each over the Weekend trip note, for Matt to
choose from; the app's versions follow those, drawn with the app's own tokens. Tests: shell/topBar.test.ts,
NoteTabs.test.tsx "the bar's styles", App.test.tsx (the stamps by style), AppearancePane.test.tsx (the cards),
homeLayout.test.ts and HomeScreen.test.tsx (the four).

Cites: §147, §148, §170, §174.

## 179. Invite by link (2026-10-03)

Matt: "add the ability to invite people to a team by link".

Inviting by handle needs the other person's handle, and they need an account first. A link needs neither: it can go
in a chat to people who have not signed up yet.

**Making one.** Owners and admins see Invite by link on the organization's Members page and under the dashboard's
invite field (settings/InviteLinks.tsx). New link asks two things, each a segmented row: how long it lasts (a day, a
week, 30 days, no end) and who can use it (one person, five, twenty-five, no limit). A week and no limit are chosen
to start. The link is copied as it is made, since sending it is why it was made. Each working link is a row named by
the end of its code, "Link ending nQwJa", with how long it has and how many used it under it, and Copy, Send where the
device can share, and Turn off. Its whole address would be cut off in the dashboard's column, so the row does not
show it. A device that will not copy shows the link written out, wrapping anywhere so it never widens the column.

**Following one.** The link is the reader page with the code in its hash, as a share link is (src/read/JoinPage.tsx).
The page says only that it is an invitation to a team, because the service shows the organization only to someone
signed in. It offers the app's own scheme and the web app. Either way the app asks "Join Tea club?" first
(notes/JoinSheet.tsx): who shared the link, how many are in it, and that its workspace is made on each device. Join
lands on the organization's dashboard. Not now lets the link go. A link that stopped says so in the service's words.
Followed signed out, the sheet says to sign in, the code waits on the device for up to a week, and the sheet comes
back once an account is signed in. A link or a bare code pasted into + › From a shared link goes the same way.

**What the service does.** Joining by a link is an invitation and its acceptance in one step: the person is a member,
the link's maker is told as an inviter is, and every other member hears of the joining (docs/TEAMS.md, "Invite by
link"). A member who does not manage the organization sees no links at all.

Measured in the preview with a fake session and a stub service: a link made for one person read "0 of 1 used", Turn
off took its row away, and a `#join=` address asked "Join Tea club?", left the address bar, and Join opened the new
organization's dashboard. At 375px the panel sits inside the settings card with the card's padding.

Tests: server/src/orgs_tests.rs and store/org_links.rs; core/orgs/joinLinks.test.ts, notes/JoinSheet.test.tsx,
settings/InviteLinks.test.tsx, the invite-link cases in settings/OrganizationSheet.test.tsx and
shell/useAppLinks.test.tsx, and src/read/JoinPage.test.tsx.

Cites: §170, §171, §175.

## 180. The top bar four ways (2026-10-03)

Matt: "cut the options in settings down to Classic, Ledger, Masthead and Islands".

The Strip and Thumb (§178) are gone, with the code that drew them: their branches in notes/NoteTabs.tsx, Thumb's
heading of the open note and its foot of tabs, the rules that gave up rings on a phone to fit them, their pictures in
settings/TopBarCards.tsx, and the root's `data-foot` stamp with the bottom inset it added. Settings › Appearance › Top
bar now shows four cards, two by two. A Strip or a Thumb chosen before the cut is not one of the four, so it reads as
Classic, on this device and on any other the preference syncs to, as a home layout that went did in §178.

Tests: shell/topBar.test.ts, core/preferences.test.ts (the two that went read as Classic), NoteTabs.test.tsx,
App.test.tsx and AppearancePane.test.tsx.

Cites: §178.

## 181. The bell's rows as phone notifications (2026-10-03)

Matt: "also send notifications as actual phone notifications too", after "I don't see notifications for these changes
on my phone".

An Android phone now shows team news, invitations and Claude's changes as its own notifications, from native
generation 23 (docs/TEAMS.md, "On the phone"). Two roads lead there and the phone posts each row once. The page posts
the rows a sync brings while the app runs in the background, in the bell's own words. A WorkManager job reads the feed
about every fifteen minutes while the app is closed, with a session the page hands it, and words Claude's sealed rows
by their kind. Nothing is posted while the app is in front.

Settings › Notifications gains On this phone: one switch, per phone, on by default. When Android is keeping the app's
notifications from showing, the row says so and offers Allow notifications. A meeting written up keeps its own
notification under Recording, so it does not come twice.

Not covered: the Mac, which has no notification of its own here yet, and a phone with the APK from before generation
23. A note edited in the app or outside it was never a notification, so editing the rules notes on disk posts nothing,
then or now; only the connector's writes and the service's team news are rows in the feed.

Tests: notices/NoticeWorkerTest.kt (the sentences, what is posted, where a tap goes, when the session is refreshed),
core/notifications/phone.test.ts, and the phone row in settings/NotificationsPane.test.tsx.

Cites: §170, §174, §177.

## 182. Version history, and the versions file (2026-10-04)

Matt: "Please add edit history timelines to notes that are in organizations by default and allow versioning on
personal notes by enabling it under the more menu. We should be able to revert back to previous versions like git
kinda but create a special file like a versions files that efficiently tracks changes in a way that can be shared via
a file it doesn't need to be super human readable but it should be at least a bit (like a yarn lock)", and then
"include a way to view changes on a timeline in app along with the author of the changes". His three answers: the file
sits beside the note, it syncs encrypted like the note, and a version is kept after a pause and by hand.

**Which notes.** A note in an organization's workspace keeps a history unless it is switched off; a note of one's own
keeps one once More › Keep version history is pressed. Both are the `versions` preference (a yes for one's own, a no
for an organization's), so the choice syncs (core/versions/record.ts). Notes are still not shared inside an
organization (docs/TEAMS.md), so for now an organization's timeline is the person's own edits on their devices; the
file already carries an author per version for when teammates write into one note.

**When.** After two minutes with no typing, when the note is left (closed, the app put away, the page gone), when the
history is switched on or a note that keeps one is opened, and by hand with an optional name. Never a version of no
change: the same words again are not a version, though a name can be put on the last one
(editor/useVersionKeeping.ts).

**The file.** `<Title>.versions` beside `<Title>.md`, renamed, moved and deleted with it, never indexed as a note
(src-tauri/src/library/versions.rs; native generation 24, `versions_read` and `versions_write`). It reads like a
lock file (core/versions/file.ts):

    # Ghost.md versions 1
    # note gho-7f3a
    # A version is the change from the one before it: "=N" keeps N lines, "-" takes a line out, "+" puts one in.

    v1 2026-10-04T15:20:01.000Z matt 3f9a21c0 full
      +# Launch plan
      +- book the venue
    v2 2026-10-04T16:02:44.000Z matt 8c0d4e11 "Before the review"
      =1
      -- book the venue
      +- book the venue (done)

Each version is its head line - number, time, author, an FNV-1a hash of the whole text, and a name - and its change
from the version before as Myers' shortest edit script, the one git uses (core/versions/diff.ts). One in every 50 is
written whole (`full`), and the file keeps at most 1,000 versions, the oldest going first. Reading rebuilds every
version and checks it against its hash: a version that does not come out right is left out and counted, never shown
as something it was not, and only the versions up to the next whole one go with it. In a browser, and on a binary
older than generation 24, the page keeps the file under `glyph-versions-<id>`, and moves it beside the note the first
time it is read on a binary that can (core/versions/store.ts).

**Sync.** The file is a third kind of sealed file beside recordings and pictures, `v-<note id>`, and the note carries
its hash (core/sync/notes.ts). Two devices that both kept versions are not a choice: their files are merged version
by version, keyed by time, author and hash, on whichever side meets the other's - a 409 on the send, or a newer hash
on a pull - so every version of both survives, in the order they were kept. A version kept with no change to the
words sends the note again with the file, so the other devices hear of it by the note's revision.

**The timeline.** More › Version history: a field to name a version and Save a version now; the versions newest first
under the day each was kept, on a line down the page, each with its author's initial in a ring, who, when, its name,
"+3 −1", and the first line it changed. A version opened shows what it changed against the one before, then what
restoring it would change against the note now, line by line as a diff reads, and Restore. Restoring keeps the note
as it is as a version first, puts the old words in through the editor as one change to undo, and keeps them as a new
version named "Back to version 3" - the history only grows, as `git revert` does. Share the versions file sends it
through the phone's share sheet where it takes a file, downloads it in a browser, and opens the library's folder on
the Mac, where it sits beside the note. Stop keeping history leaves the file; switched on again, it carries on.

Not covered: importing a versions file someone sent, which is merged the same way but has no button yet; a note's
history on the server after the note is deleted (its sealed file stays); and canvases, which are JSON and have no
line diff worth reading.

Tests: core/versions/diff.test.ts, file.test.ts, record.test.ts; the versions cases in core/sync/notes.test.ts; the
timeline in editor/NoteSettings.test.tsx; src-tauri library/versions.rs.

Cites: §170, §179.

## 183. An organization's audit log (2026-10-04)

Matt: "I'd like an "audit log" for organizations to be able to browse history of changes across all files".

**Where.** A page under the dashboard (§175): the clock beside the cog in its bar, and the Audit log word on its
Activity heading, open it; its arrow and the phone's back gesture are the dashboard again. It is the `organization`
Screen with `page: 'log'` (shell/screen.ts), so it is drawn where the dashboard is - with the tab row, in the pane
beside the sidebar on a wide window - and a note opened from it opens as one from the dashboard does.
notes/OrganizationLog.tsx.

**What.** Every version kept of every note filed in the organization's workspace (§182: an organization's notes keep
history by default), the archived among them, read from each note's versions file a few at a time (core/versions/log.ts
`useChangesAcross`: a line per version - who, when, how much, the first line it changed - and not every version's
text) and read again, one note at a time, as a version is kept or sync brings a file. Between them, the team's own news
from the feed (§175's set: who joined, left or was removed, a rename, a new role, an invitation answered), so the log
reads as what happened here, in order. Newest first under the day's name, on the version history's timeline (§182):
the author's initial in a ring, "matt edited Roadmap", the clock, the version's name, "+3 −1" and the first line it
changed, with v12 at the end; a piece of news is its kind's mark in the ring and its sentence as the drawer words it.
The timeline's words moved to editor/versionWords.ts, and the first-line peek to core/versions/diff.ts, so both pages
read the same; the news kinds and their marks to notes/orgNews.tsx, so both pages draw the same.

**The tools.** Over the timeline a field narrows the log to a note, a person or a version's name as it is typed, and
three pills show everything, the notes alone or the team alone; wide, they share a row. Under them the figures: "128
changes across 14 notes · 2 people", "Reading the history… 3 of 14 notes" while the files come in, and "· 12 lines
shown" while narrowed; then a quiet line for what is missing - "History is off for Groceries and Old plan." for notes
switched off from their More (§182), and how many versions could not be read.

**A change opened** is the note's name with the version's, who made it and when, and what that version changed against
the one before - the same diff the history draws, read from the note's file then - with Open the note and Only this
note, which narrows the log to that note under a dashed pill with an x. Nothing yet is the ghost with "Nothing has
changed here yet."; nothing that matches is the search ghost with "Nothing matches."

**Not yet.** Notes in an organization are still the person's own (docs/TEAMS.md, D1), so the log is their own changes
on their devices, with what the team did around them; shared notes will bring the others' changes in through the same
files. A deleted note's history goes with it; an export of the log; a version restored from here (the note's own
history has Restore).

Tests: core/versions/log.test.tsx; notes/OrganizationLog.test.tsx; the audit log cases in
notes/OrganizationScreen.test.tsx, App.test.tsx and shell/screen.test.ts.

Cites: §175, §182.

## 184. A phone's bar while a note is read, and the Islands' blur (2026-10-04)

Two small ones on the top bar.

**The bell and the people icon step out on a phone with a note open.** Matt: "don't show notifications on mobile
while on the viewing of a note also don't show the organization on the page when viewing notes either". A phone's
bar holds a note's own tools while one is read, so with a note on screen the people icon and the bell are not drawn
(App.tsx `quietBar`: `isMobile` and the `note` Screen; notes/NoteTabs.tsx draws neither without its callback). They
are back on the home page, the grid and an organization's pages, and a phone's own notifications carry the bell's
rows meanwhile (§181). `isMobile` is the device (core/platform.ts), not the window's width: a narrow Mac window keeps
them, a Fold opened wide does without.

**The Islands' blur strip hangs from the capsules' foot.** Matt: "on desktop there is a small gap below the header
before the blur shows". In the Islands (§180) on a window in two panes, the capsules' one line is centred in the bar
over its bottom padding, and the blur strip under a screen's empty header pane (§178's desktop edge, art/wisp.css
`.app-headerBlur`) hung from the pane's foot, which is the bar's edge: a crisp band the air tall showed between the
capsules and the blur. Measured at 1200px: the capsules end at 59.9, the bar at 72.4, the strip began at 72. The air
is named once (app.css `--app-bar-air`: the bar's bottom padding and half the breath the line is centred in, nothing
in the other styles, whose tab line is the bar's foot), and the two screens whose pane is only the bar's glass - a
note (editor/NoteScreen.module.css `.header:empty`) and the home page (home/HomeScreen.module.css) - pull the strip,
their header's next sibling, up by it. The pane itself keeps its height, so `--wisp-under` and the page's first line
stay where they were.

Tests: the quiet bar in App.test.tsx; the strip's place is CSS over a sibling the hook lays (art/wispEdge.ts), checked
in the browser at 1200px: the strip now starts at 59.9.

Cites: §178, §180, §181.

## 185. Slack (2026-10-04)

Matt: "include #6 as a plugin as well as #5", where #5 was "Slack: post a meeting's summary, or a note, to a channel
when you choose to. It pairs well with organizations: a team's news could go to its channel too. Sending is always
your choice, so the encryption holds." He chose incoming webhooks: no sign-in, no server work, the post goes straight
from the device.

**A sixth built-in plugin, off until switched on** (src/app/plugins/slack/, `standard: false`). Its page in Settings ›
Plugins › Slack lists the person's channels: a name they give ("#launch") and the webhook Slack gave them, checked by its
shape as it is pasted (`https://hooks.slack.com/services/…` or `/workflows/…`), with Test, Rename and Forget on each. In a
browser the page says Slack works in the app; on a binary before native generation 25 it says to update.

**On a note's More sheet**, once a channel is added: "Post to Slack" posts the whole note, its title as a bold first line
and the rest in Slack's mrkdwn (plugins/slack/mrkdwn.ts: bold, italics, strikes, headings as bold lines, ☐ and ☑ for
to-dos, • for bullets, `<url|words>` links, code as written, the three escapes; front matter dropped, links into the app
as their words, a picture on the phone left out, and a redaction as a bar rather than in the clear). "Post the summary to
Slack" shows only on a note with a meeting's summary (`summarySection(body, keptText(noteId))`) and posts that section
under the note's title. With several channels the row opens them as a page of the sheet; with one it posts at once. The
note then says "Posted to #launch.", or "Not posted to #launch." and Slack's reason in a sentence. To make the choice a
page, `NoteAction` gained `choices(noteId)` and `run(editing, choice)`, and `visible` is now handed the body too, so the
summary row can ask whether there is one.

**An organization's news to its channel.** For each organization the person is a member of, the page offers a channel
for its news. After each pass of the feed, the new news rows (notes/orgNews.tsx `NEWS`) for an organization with a
channel go there as the bell's sentence (`sentenceOf`), by the phone notifications' rule: rows above the cursor the pass
began at, oldest first, nothing on a device's first look. Each row goes once per device (the posted ids are kept,
`glyph-slack-posted`, before the post goes), nothing older than the moment the channel was chosen goes, and a post that
fails is not tried again. Core does not name the plugin: core/sync/engine.ts tells core/notifications/arrived.ts, the
registry listens there and hands the rows to switched-on plugins' new `newRows` extension point.

**Where the webhooks live.** A webhook is a secret: whoever holds it can post to the channel. So, as with Notion's
sign-in, it is kept natively: `slack.json` in the app's data directory, written with `fsx::write_private` (0600), id to
URL (src-tauri/src/slack.rs: `slack_channels`, `slack_save_channel`, `slack_forget_channel`, `slack_post`). The page keeps
only names and ids (`glyph-slack-channels`) and posts by naming the id, so no page can read a webhook back once it is
handed over. Rust holds every URL to `https://hooks.slack.com/services/` or `/workflows/` and plain token characters,
when it is kept and again when it is posted to, follows no redirect, and times out at 20 seconds; a reset removes the
file with the Notion account. The post is native for a second reason too: hooks.slack.com does not answer a web page's
cross-origin request.

**This device's only.** Neither channels nor the news choice sync, and the page says "Kept on this device". A second
phone has no channels until they are added there, and every device with a channel set for an organization posts its
news, so the page says to set it on one.

Not covered: Slack sign-in, choosing a channel from Slack's own list, threads, replies or editing a post, posting a
picture or a recording, retrying a failed news post, posting news from a closed app (it rides on the page's sync passes),
and iOS, where `slack_post` refuses as Notion's request does. Native generation 25 is the parent change's bump.

Tests: plugins/slack/mrkdwn.test.ts, channels.test.ts, news.test.ts, actions.test.ts and SlackPane.test.tsx; the choices
page and `visible`'s body in editor/NoteSettings.test.tsx; the registry's list; `slack::tests` in Rust (the allow-list,
the private file, a hand-edited file, Slack's answers as sentences) and the reset's.

Cites: §138, §181, §183.

## 186. Meetings with the computer's sound (2026-10-04)

Matt: "can you make it so that the app can listen to the microphone and system audio so that we can record meetings
with raw audio?" A meeting (§127 section 3) can now have the device's own sound in it beside the microphone: on the
Mac everything the Mac plays, through a Core Audio process tap; on Android the sound of other apps, through
AudioPlaybackCapture. He chose both knowing the limits, and the app says them where the switch is.

**One stream, mixed before it is kept.** Every tape is 16 kHz mono PCM16 (whisper/wav.rs `header`, the write-up's
`read_span`, Kotlin's WavSpool), so the two sources are summed into that one stream before a byte is written, rather
than kept as a second track that rewinds, appends and moves (`capture_reassign_recording`) would have to keep in step.
The sum is plain up to 0.8 of full scale and bent smoothly towards it above (a tanh knee), so a loud call over a loud
room is softened, not clipped. The two sides run on two clocks, so the device's sound waits in a ring and each
microphone chunk takes as much of it as has arrived, up to its own length: a chunk that finds the ring short is
microphone-only at its end and the ring is fuller for the next, so it settles at the jitter between them; past a
second the oldest is dropped, so the far side is never more than a second late.

**The Mac** (src-tauri/src/system_audio.rs and system_audio/mac.rs). The microphone is the page's (capture/audio.ts)
and every chunk already passes through `capture_push`, so that is where the sum is made, and the live transcription
hears both sides because it is fed from the same push. The tap is global, mono, unmuted and private, excludes this
app's own process, and is read through a private aggregate device clocked by the default output device (as Apple's
sample and AudioCap set it up); its IOProc downmixes, brings the frames to 16 kHz with the page's box-average resampler
ported to Rust, and fills the ring. Commands: `system_audio_available`, `system_audio_start`, `system_audio_status`
(`heard`: anything but silence since it opened), `system_audio_stop`; `capture_stop`, `capture_cancel`, a new
`capture_start` and the app's exit close it too. The app still runs on macOS 13.1, and a binary that links a symbol
its OS lacks does not launch, so `AudioHardwareCreateProcessTap` and its destroy are found with `dlsym` and a Mac
older than 14.2 says "Recording the computer's sound needs macOS 14.2 or later" and records the microphone. The
consent ("System Audio Recording Only", NSAudioCaptureUsageDescription in Info.macos.plist) is not an error when
refused, only zeros, so the recorder says where the switch is when nothing has come through for eight seconds. In the
meeting recorder the top line carries the word (capture/ComputerSound.tsx): "With this Mac's sound", or "This Mac's
sound: off", a tap to change it then and there.

**Android** (capture/OtherApps.kt, SoundMix.kt). AudioPlaybackCapture, Android 10 and later, for USAGE_MEDIA, GAME and
UNKNOWN, with this app's own uid left out. It never hears a call: a call app's voices are USAGE_VOICE_COMMUNICATION,
which no app may capture, so the far side of a phone call, a Meet or a Zoom on the phone is not in the tape; a video,
a podcast or a game is. The page says so plainly ("Android lets Ghost.md hear media and games, never calls."). It runs
on a MediaProjection: with the switch on, the activity asks the microphone first, then the screen-share consent
(`createScreenCaptureIntent`, the whole display on Android 14 so the dialog offers no single app), and starts the
service once it is answered, declined or not (`GlyphHost.startMeetingWith`). The service comes to the front as
`microphone|mediaProjection` (Android 14 refuses a projection to any other type; FOREGROUND_SERVICE_MEDIA_PROJECTION in
the manifest), opens the playback capture at 16 kHz mono (48 kHz stereo brought down where a phone will not), and its
reader thread fills the ring; the microphone's reader mixes it into each read before WavSpool writes it. Declined,
failed, or stopped from the status bar's chip, the meeting carries on with the microphone, and `meetingState` says
which (`otherApps`, `otherAppsHeard`, `otherAppsNote`), which the meeting screen shows.

**The switch.** `meetingSound` (core/preferences.ts), off by default and kept on the device, not synced: what it hears
and what it asks for are the device's own. It is on the + sheet under Meeting, in Settings › Recording (Android's
Meetings card; a Meetings card of the Mac's own), and in the Mac's meeting recorder. All of it is native generation 25
(capture/systemSound.ts `MEETING_SOUND_GENERATION`): a page that came over the air to an older binary shows the row
with the update it needs and records the microphone.

Unmeasured, to check by hand: the tap's consent and a real call on a Mac on 14.2 or later (and that the aggregate's
last input buffer is the tap's when the output device has inputs of its own, as a USB headset can); a 13.x Mac
launching at all; the projection consent, a YouTube video and a call on the Fold; whether the playback capture opens at
16 kHz there.

Tests: the mixer, resampler and soft clip in system_audio.rs (9, and one ignored by-hand test in system_audio/mac.rs that opens a
real tap: `cargo test --lib system_audio -- --ignored --nocapture`) and SoundMixTest.kt (7); the page's gate and words
(capture/systemSound.test.ts), the recorder's word (capture/ComputerSound.test.tsx), the switch in RecordingPane.test.tsx
and NewSheet.test.tsx, the meeting screen's lines, the host bridge, and the preference's normalisation.

Cites: §127.

## 187. The library in a folder of your own (2026-10-04)

Matt: "include #6 as a plugin", #6 being "An Obsidian vault, iCloud Drive or Dropbox. Notes are already plain Markdown
files. Letting you choose where the library folder lives would make Obsidian, backups and other editors work for
free." On the Mac and on Android, both now. docs/LIBRARY.md "Choosing the folder" is the whole of it; this is why.

**A plugin, off until switched on.** Settings › Plugins › Library folder (plugins/folder/). Most people never move
their notes, so the page is not in their way; switching it off hides the page and leaves the notes wherever they are.
Its id is `library-folder`, with a hyphen, because every plugin id is also a name an item mark may carry and
`[folder](…)` is a link a person could write. Native generation 25: `library_root`, `library_choose_folder`,
`library_inspect`, `library_move`, `library_use_app_folder`, and the activity's `GlyphHost.chooseLibraryFolder`
answered as `window.__glyph.libraryFolder`.

**Safety came first, before a folder could be chosen.**

- *A reset never deletes a person's folder.* It used to remove every `.md` the library listed, which in an Obsidian
  vault is the vault. Now it forgets the choice, the folder's index and an Android folder's bookkeeping, goes back to
  the app's own folder and empties that, as before. And `Library::clear` on a chosen folder forgets its index and
  deletes nothing, as a second guard (reset.rs, library/mod.rs).
- *The index is never in the folder.* WAL SQLite is three files a sync service copies one at a time; two Macs on one
  Dropbox folder would each write the other's. A chosen folder's index is `<app_data_dir>/index/<key>.sqlite` (FNV-1a
  of the place, not std's hasher, whose output may change with the compiler). The sidecars and `library.json` stay in
  the folder's `.glyph/`: small JSON written whole, which sync carries like the notes, so a recording's phrases go with
  its note to the other Mac. The app's own folder keeps its index where it always was, so nobody who never chooses a
  folder has anything moved.
- *An iCloud placeholder is not a deleted note.* The walk skipped dot names, so `.Plan.md.icloud` made a note vanish and
  the next scan dropped its row. The placeholder now answers for the note: the row stays, its name is taken, a read
  asks iCloud (`brctl download`) and waits three seconds, and what has not come down opens from the index and refuses a
  save rather than write a second file over it (library/vault.rs `NotDownloaded`).
- *Front matter already coexisted with Obsidian* (frontmatter.rs keeps every key and line it does not manage); the move
  test edits a vault's daily note and checks its `tags:` are kept.

**Move, adopt, and never the other way.** A folder with Markdown in it is adopted as it is: its files become notes,
the app's go in beside them at their own paths, " 2" on a clash. An empty one simply receives the notes. The order is
copy, switch, then remove, so a note is never in neither place, and a copy that stops part way takes back exactly what
it wrote. Only the app's own folder is ever emptied by a move: leaving a folder of the person's (for another, or for
the app's own with "Bring a copy back") copies. Going back with nothing ("Start empty") was kept because a person who
used a folder as a one-off export target may want the app clean. Revisions and the voice commands' undo memory are
carried into the new index, so the open editor's next save is not a conflict.

**An adopted file keeps its name.** In the app's own folder a file follows its title, as always. In a chosen folder
only a file Ghost.md named does: Obsidian's `2026-10-01.md` keeps its name when edited here, or its daily note and
every `[[link]]` to it would break.

**Android: the second vault, and Rust calling Kotlin.** A folder from ACTION_OPEN_DOCUMENT_TREE has document ids, not
paths, so library/tree.rs's `TreeVault` stands on a small `Documents` trait that saf.rs answers over JNI from
files/LibraryTree.kt - the first calls this way. A Rust thread cannot `FindClass` an app class, so Kotlin hands Rust
the JVM and the class itself (`LibraryTree.install` → `attach`), from the activity before Tauri starts and from the
write-up's two doors; each call runs in its own local frame and answers one JSON string. Listing is one
DocumentsContract query per folder with five columns, never a DocumentFile per file, and the ids found are kept.
`.glyph/` is in the app's storage there (`trees/<key>/`), since SQLite and the sidecars need paths. SAF cannot set a
file's time, so "a pin is not an edit" is kept by recording the time a note shows against the time and size its file
really has (`kept-times.json`): the moment another app changes the file, its own time shows. A write is in place, not
atomic, which is the one thing an app's own folder does better. The activity lets go of grants for folders that are no
longer the library on each launch. The Files app's "Ghost.md" place is hidden while the notes are in the person's own
folder, where Files already shows them, and Browse files opens that folder.

**The page** says where the notes are; Choose a folder… opens the system's panel or picker and then says, before
anything moves, what is in the folder and what will happen to the notes; Use Ghost.md's own folder offers the copy or
the clean start and says the folder keeps every file. A folder that cannot be reached opens the app's own for that run,
with a callout, and the choice is tried again next launch. Good to know is by device: on Android a folder on the phone
(Syncthing) is the reliable case and Dropbox and Drive may be online-only through their apps, iCloud has no Android
app; on the Mac, iCloud's placeholders; everywhere, that adopted files sync as notes and that pictures, films,
recordings and the index stay in the app. A browser, an iPhone and an older binary each get a sentence instead.

Not yet: watching the folder (another app's change is seen at the next list or open, as before); an iPhone; pictures in
the folder (phase 3).

Tests: library/root.rs, relocate.rs, tree.rs, vault.rs (the iCloud placeholder), library_root.rs, library_commands.rs,
reset.rs (`a_reset_never_deletes_a_folder_of_the_persons_and_goes_back_to_the_apps_own`), paths.rs (the Kotlin twins
and the bridge's methods); plugins/folder/FolderPane.test.tsx; the cards in PluginsPane.test.tsx and registry.test.ts.

Cites: §167, §182.

## 188. Version history in the desktop's side panel (2026-10-04)

Matt: "Please make a sidebar that can be expanded on desktop to see the version history". The right-hand aside, which
the tab row's mirrored sidebar icon opens (aside/Aside.tsx), was only ever a notebook's index or a run of chapters, and
had no icon at all for an ordinary note. On a desktop - a window wide enough for two panes, and not a phone, which
keeps its history in the More sheet - it now holds the open note's version history too (aside/AsideHistory.tsx): the
More sheet's timeline (§182), beside the note rather than over it. A notebook's page has both, as two tabs, Index (or
Entries, or Chapters) and History, the last one chosen kept to the device (`glyph-aside-tab`). A note that keeps no
history says so, with Keep version history. A canvas has none: its words are JSON.

The panel is outside the note, but what it compares a version with is the words in the editor now, and a restore goes
through the editor as one change to undo, as the More sheet's does. So the note on screen says how to do both while it
is open (core/versions/live.ts, `liveNoteOpened` in editor/NoteScreen.tsx). Docked or floating, it follows the
sidebar's style, as the index always has; its toggle and its card are labelled Side panel now.

Tests: aside/Aside.test.tsx (the two tabs, the history alone, starting one, a restore through the editor).

## 189. Windows on a desktop, and a bar that fits what it has room for (2026-10-04)

Matt: "on desktop open windows in modals instead of the drawers, add the version history as an item in the header when
the space is available, I'd like the top toolbar to automatically adapt to show more or less icons if there is real
estate on the screen for it (not all items under more, the following should be able to expand out in order of
priority): Share, History, Bookmark, Pin/Unpin, Archive, Speak".

**Windows, not drawers.** Every bottom sheet is the one shell (editor/Sheet.tsx), so on a desktop (`data-platform`
`desktop`: the Mac app, and a browser on a computer) it is a window in the middle of the screen instead: all corners
rounded, at most 34rem wide and 82% of the height, the same dimmed page behind it, closed the same ways - a click
outside, Escape, its own close. The pull-down grip goes, since there is no thumb to pull it (NoteSettings.module.css).
Phones keep the drawer from the foot.

**A bar that fits.** The note's tools in the top bar (editor/NoteTools.tsx) bring six of More's actions out beside the
view switch and More, in that order, as many as the row has room for: Share (the share link in a window of its own),
History (the desktop's side panel at its History tab, §188, or More's history page where there is none), Bookmark,
Pin or Unpin, Archive, Speak. Each is there only where More would offer it, and stays in More too. The room is the
control row's width less everything else on it (editor/toolRoom.ts): its other controls at their width, the Islands
bar's capsule less the tools in it, and the open tabs, where they share the row, at the width of their tabs. So the
answer does not depend on what is drawn, and settles at once. It is measured again when the row changes size or what
is in it. With nothing to measure (a test, no layout) none come out, as on the narrowest phone.

Not covered: the order is fixed, not the person's to choose; and on a phone the drawer stays.

Tests: editor/NoteTools.test.tsx (as many as fit, first first; all on a wide row, none on a narrow one; the row's
other controls taken).


## 190. The canvas's controls, reworked, and a minimap that is the canvas (2026-10-05)

Matt: "I'd like you to spend some time reworking the controls and creation aspects of canvases, navigating it and
resizing things are not easy especially on mobile resizing containers is near to impossible. the canvas minimap could
also be far more detailed with modern displays and the frame is too bright white and has no radii".

The whole of it is docs/CANVAS.md's eighth slice. What changed on the screen:

**A picked card.** A tap picks a card of any kind; the next opens it. The picked card wears a ring in the page's ink,
a round handle at each corner (and, for a pointer, a short bar at the middle of each side), and a pill of glass over
it with what can be done: write or open, a line from here, colour, copy, take off. All three are drawn at the same
size on the screen whatever the zoom, a handle 44px to the finger round a 13px dot, 16px on a touch screen. The old
22px wedge and the crosses are gone. A group is resized the same way, which it could not be at all.

**Moving without the wait.** A mouse drags a card at once, with a hand for a cursor over what moves. A finger drags
the picked card at once and pans from anything else. A group is taken by its name or border, so its ground stays the
page's to pan and to double-tap a card onto.

**Making.** The + offers a group, made about the picked card when there is one. A new card steps aside from one
already at its spot.

**The tools.** Zoom out and Zoom in sit beside Fit behind a hairline rule, on a window wide enough: at a phone's
width they would run the toolbar into the map, and two fingers zoom there.

**The minimap.** It is the canvas drawn small, in vectors: words as the bars they make from far off, a note's title,
a picture as itself, the lines as their real curves with their heads. It is a little larger, 204 by 136, with the
floating cards' round and shadow. The screen's box is a line of the ink at under half strength with a five-unit
round, and what is outside it is shaded toward the page, so where you are is the lit part.

Checked in the browser pane on a canvas of a group, three cards of words, a note, an address and three lines: a card
resized from its corner (260 by 180 to 306 by 230 at two thirds scale), a card dragged by the mouse, the group resized
and coloured, and the change read back out of the note's JSON. At 400px the tools end at 151 and the map starts at
240. A finger's own paths - dragging the picked card, panning from another, a group by its name - are held by the
tests, since the pane's clicks arrive as a mouse's.

Tests: canvas/CanvasView.controls.test.tsx (picking, moving, the keys, the bar, the +, the zoom buttons), the sizes
in CanvasView.test.tsx, the map in CanvasView.navigation.test.tsx, edits.test.ts and mapDetail.test.ts.

Cites: §62, §124.

## 191. Keys and colours: the first slice of notes shared in an organization (2026-10-05)

Matt's brief and his four answers are docs/SHARED.md, which is the plan; this is its first slice (S2, S3, S7), with
nothing yet that uses the keys.

**The account's encryption key pair.** ECDH P-256, made on the first signed-in device that syncs on this build and
registered with the service, the private half sealed under the account key (core/account/encKey.ts); every other
device of the account reads and unseals it on its next pass and keeps it non-extractable beside the account key
(core/account/keystore.ts `encryptionKey`). The service keeps the first registration and answers a second 409 with
it, which the second device adopts, so two devices racing end with one pair. Signing out takes it off the device
with the other keys.

**The organization key.** 32 random bytes, made by the first member device to ask and find none, wrapped for every
member who has a public key - ECIES, an ephemeral P-256 pair per wrap, HKDF-SHA-256, AES-256-GCM bound to
`org-key:<org id>:<generation>` (core/orgs/wrap.ts) - and posted as the first generation with `make`. A device that
posts `make` against a generation already in force is answered 409 with it and reads its own wrap instead; a device
holding the key wraps it for whoever the service lists as missing (core/orgs/orgKeys.ts). The list's rows carry
`keys: { generation, mine, missing }`, so a device whose key is in hand with nobody missing asks nothing more. The
step runs after the organizations in every full pass, best effort: a failure is the next pass's, never the sync's
status (core/sync/engine.ts). On the service: four tables, `account_keys`, `org_key_state`, `org_keys` and the hues'
(server/src/store/keys.rs), and the routes `account/key`, `orgs/{id}/keys` (server/src/orgs.rs).

**Colours.** One of the seven hues, or none. Settings › Account › Your colour sets the account's (settings/ColourCard.tsx,
`PUT account/colour`); an organization's dashboard and its settings' Members page carry "Your colour here", the
account's unless one is picked there, with "Use your account's colour" to go back (`PUT orgs/{id}/colour`). The
member rows wear each person's colour on their initial (notes/OrganizationScreen.tsx `.avatar[data-hue]`), and
every member row from the service carries `colour` and `pub`. The list carries the account's `colour`, kept with it
(core/orgs/orgs.ts `OrgState.colour`), and a row from an older build reads as no colour and no keys.

**What the server can see** grows by the public keys, the wraps (ciphertext) and the colours (SHARED.md, S10).

Tests: core/orgs/wrap.test.ts, core/account/encKey.test.ts, core/orgs/orgKeys.test.ts, the colour cases in
settings/AccountPane.test.tsx, settings/OrganizationSheet.test.tsx and notes/OrganizationScreen.test.tsx; on the
service, store/keys.rs's own and the two cases at the end of orgs_tests.rs.

Cites: §175, §182, §183, §189, §190.

## 192. The wash back on every icon, on its body alone (2026-10-05)

Matt: "a bunch of the icons across the app is missing the semiopaque fill that the icons should all have".

The wash had been cut back to seven icons (app.css), because set on a whole icon it filled every shape in it and the
inside doubled up: the mic's cup over its capsule, a page's fold over the page. Everything else was left hollow. The
house showed the way out, and now every icon does it: the wash is on the icon's body, one shape of it, and the
detail is strokes over that.

- **The kit's icons.** art/iconWash.ts picks each icon's body: its largest closed shape, and any other closed shape
  of some size that sits clear of it. What is inside the body stays a stroke, so a cog keeps its hole and a ticked
  circle its tick; an open path is never washed. Thirteen icons whose body is a path left open along an edge another
  stroke draws - the bin, the flag, the lightbulb, the book - are named by hand, each looked at washed first.
  iconWash.css is made from that, for the icons the app actually imports (`npm run icons:wash`), and the test that
  makes it fails when an icon comes into the app without its rule.
- **The app's own icons** (art/Icons.tsx): the cog, the magnifier, the pin, the cassette, the tick box, the book and
  notebook, the clock, the grid, the archive box, the bin, the folder, the board and the locate ring each draw their
  body under their line. A body with a hole in it is filled even-odd, so the cog's middle and the cassette's reels
  stay clear.
- **Left as outlines:** icons that are lines and nothing else - arrows, ticks, the plus, the cross, brackets, a
  list's lines. There is nothing in them to fill.

Measured in the browser pane by asking every icon on the screen whether any shape of it computes to a fill: on a
note's bar and in Settings, the only hollow ones were arrows, the plus, the cross, the code brackets, a chevron and
the sliders.

Tests: art/iconWash.test.ts (a body, a path that comes back to its start, and the stylesheet against the icons in use).

Cites: §132.

## 193. Team notes: the second slice of notes shared in an organization (2026-10-05)

docs/SHARED.md, S1, S4 and S5: a note filed in an organization's workspace is the team's. Matt: "Organizations should
have real time sync on documents so everyones stuff stays up to date" - this is the durable half; the live half,
over the relay, is the next slice.

**Filed is shared.** Filing is the sharing: a note in the organization's workspace is on every member's devices, read
and edited by every member. The dashboard's hero, the organization's Workspace section, the join sheet and the
workspace sheet now say "Notes filed here are the team's: everyone in it reads and edits them, and edits made apart
merge." Taking a note out of the workspace, or moving it to another, takes it from everyone, so the picker
(editor/WorkspacePicker.tsx) asks twice, armed for four seconds in between, as leaving an organization is.

**The organization channel.** A second sync, after the account's own in every full pass and once for each
organization joined whose key this device holds (core/team/sync.ts; core/sync/engine.ts): the organization's feed of
rows, each note's update log, and the organization's files. On the service: `org_notes`, `org_note_updates`,
`org_files` and `org_revs` (the organization's own write counter, so a cursor is per organization), and the routes
under `orgs/{id}/notes`, `…/updates` and `orgs/{id}/files` (server/src/org_notes.rs, store/org_notes.rs), every body
ciphertext under the organization key, checked for size and shape. The account's sync leaves team notes alone
(`teamNote` in core/sync/notes.ts): one that was the account's is deleted from its feed, so the account's other
devices take it from the team, and a stale row of it in the feed is passed over.

**The document of record is the CRDT.** Each team note is a Yjs document held on the device (core/team/doc.ts,
kept in IndexedDB by core/team/docs.ts: the state, the seq of the log applied, the seq its last snapshot covered,
and the updates made here not yet posted). The editor binds to it while the note is filed in an organization's
workspace (editor/useTeamNote.ts, the live binding's `bindLive` over the document's text, undo the document's);
words that reach the note without the editor - a capture, a journal entry, Claude - are reconciled into it as one
change (`reconcile`: the common head and foot kept, what lies between replaced), so a change made anywhere merges
with the team's rather than writing over it. The organization's row for a note carries a snapshot - the state, the
note's words and particulars - and the log carries every update since; a pass pulls the rows (adopting each into the
document held, merged and never doubled; this device's own words from before the team had the note reconciled in as
a change), reads the organization's log heads in one request and applies only the logs that moved (Matt: "It takes
quite a long time for organization notes to load"), reconciles the note's words, posts the updates made here, and puts the row again for a
changed pin, archive or folder, or after two hundred updates, cutting the log to the snapshot. Two members who
edited apart merge by the CRDT: the channel keeps no conflict copies. The note's versions file travels by the
organization's files, merged version by version as before, so every member's edits are in its history by handle,
which the audit log (§183) reads; its pictures travel the same way.

Opening an organization's dashboard, or pulling down on it, runs a whole pass rather than the notifications' own, so
the team's notes are there before they are read.

**Not yet.** The live half (S6): the relay's organization rooms, presence, cursors in colour and "editing Roadmap"
with Jump to cursor. Recordings do not travel with a team note. Claude's connector writes the account's feed and
cannot reach a team note yet. The live-typing trial switch leaves team notes to their own binding.

Tests: core/team/doc.test.ts, core/team/sync.test.ts (two devices on one organization through the service in
memory), the team cases in core/sync/notes.test.ts, editor/WorkspacePicker.test.tsx; on the service,
store/org_notes.rs's own and org_notes_tests.rs.

Cites: §175, §182, §183, §191.

## 194. A canvas's cards snap to its dots (2026-10-05)

Matt: "Add the option for snapping to the grid dots on by default on canvases", then "Give haptics when it snaps".

The dots were decoration, drawn in the middle of each 24px square. They are the grid now: moved half a square, one
sits at the canvas's own corner and at every 24px from it, and a card's corner lands on one (docs/CANVAS.md,
"Snapping to the dots"). The switch is a magnet in the tools, after the Line tool, washed while it is on - a quieter
mark than the Line tool's ink, which says the next tap is the tool's. On a phone's width To card left the row to make
room for it. Each landing on a new dot is a `selection` tick.

Measured in the browser pane: a card at 7,13 dragged 43 by 36 on the screen at 1.3 scale landed at 48,48, level with
a card already on the grid, and the dots' origin sat on the world's (the background 15.6px back of the world's
133.05, half of a 31.2px square).

Tests: canvas/CanvasView.snap.test.tsx and the grid's cases in edits.test.ts.

Cites: §190.

## 195. Live for the team: the third slice of notes shared in an organization (2026-10-05)

docs/SHARED.md, S6. Matt: "the color will be used to tag the persons cursor when they are live editing a document or
have a section of the document highlighted. I would like to be able to see the activity for users in organizations
like "editing <doc_name>" and be able to click the user's profile and "jump to cursor" to open the doc they're editing
to the exact point" - and, seeing none of it in the app after the second slice: "Did we ever ship the "follow cursor"
and the live updates of who's viewing what file etc etc?"

**The organization's rooms.** The relay (server/src/live.rs) takes `org` on a join, a leave and a message: the room
is the note id as ever, scoped to the organization rather than the account, so its members' devices reach each other
across their accounts and nobody else does. Membership is checked at the join and again on a message once a minute
(`RECHECK_SECS`), so a member removed is out of the organization's rooms within that long, told "No such
organization." as a stranger is. The `peers` notice now says which connection left, for the presence below. The
transport and the hub (core/live/transport.ts, hub.ts) carry `org` on every frame and event and key their rooms by
it, so an organization's room and the account's own of the same name are told apart; `holdRoom` and `releaseRoom`
let anything hold a room on the device's one connection.

**A team note's room** (core/live/team.ts, held by editor/useTeamNote.ts while the note is open) never makes a
document, which is where an account's own rooms needed their seeding rule (§LIVE.md): the document is the team's CRDT
of record (§193), one lineage on every member's devices. In the room a device says who it is and asks with its state
vector; each of the others answers with what it lacks, and asks back once if the asker's vector shows it holds
something they lack; from then on every change goes out as it is made and is applied as the channel applies a log,
which still posts it for the members not in the room. Messages are sealed under the organization key with
`live:org:<org>:<room>` bound in, and opened in order.

**Carets in colour.** The room's awareness (y-protocols) carries each device's handle, hue and the hue as CSS, and in
a note's room the selection as relative positions, so `yCollab` with it (editor/liveBinding.ts) draws every other
member's caret in their colour with their handle riding on it - always shown, since a phone has no hover - and their
selection as a wash of it. The caret's colour is the hue at the lightness the paper needs, read where it is drawn
(`--app-hue-lift`, `--app-hue-chroma`; ink for a member without a colour). When the relay says a connection left,
the room drops the states that connection spoke for at once, rather than at the protocol's thirty-second timeout.

**"Editing Roadmap", and Jump to cursor.** Every member's device holds the organization's own room, `presence`
(core/live/presence.ts, watched from App.tsx), while signed in with the organization key in hand and not local-only,
and says in it where it is: the note open, its title, and the caret as it moves, at most every 400 ms. The dashboard
reads it (notes/OrganizationScreen.tsx): a dot on the member's initial in the colour they wear, "here now" or "editing
Roadmap" on their row in that colour, and the row opens their profile - since when, the colour they wear here, where
they are - with **Jump to cursor**, which opens that note with the caret on the screen (shell/screen.ts `cursor`); the
team-note hook puts the selection there once the document is bound and scrolls it to the middle. A caret whose words
are gone, or that was never of this document, is left alone. None of it is behind the live-typing trial switch: a
team's notes are live by being the team's.

**Not yet.** Comments (S8, the fourth slice, being built beside this), canvases live with pointers (S9, the fifth),
rotation of the key (S11). A member's profile card counts no comments until the fourth slice. Between an account's
own devices carets are still not shared.

Tests: core/live/team.test.ts (a relay in memory with an organization's rooms: typing both ways, a device with offline
changes caught up both ways on joining, a caret seen, moved along and dropped with its connection, a message for
another room or under another key ignored, the organization's own room saying where each device is),
core/live/presence.test.ts, the organization cases in core/live/hub.test.ts and transport.test.ts, the team seal in
wire.test.ts, a member's caret drawn in editor/liveBinding.test.ts, "editing Roadmap" and the jump in
notes/OrganizationScreen.test.tsx; on the service, an organization's room reaching its members across accounts and
nobody else, and a removed member put out, in server/src/live_tests.rs.

Cites: §183, §191, §193; docs/LIVE.md "The team's rooms".

## 196. Comments on notes: the fourth slice of notes shared in an organization (2026-10-05)

docs/SHARED.md, S8, on notes. Matt: "please make sure comments were added to the app like we discussed previously and
add them to the context menu for a note and the popover toolbar so we can quickly click to add comments".

**The format** is the note's own text (core/comments/format.ts): an anchor after the words, `[^c1]`, or round a
selection, `==the words==[^c1]`, and one ```comments fence at the end holding every thread - a head line of id,
handle and ISO time in UTC to the second, the words under it, replies indented two in the same shape, and
`resolved <handle> <time>` closing a thread. Decided beyond S8: a comment's words may run to several lines, each a line
of the fence, and an empty line typed in them is not kept; a words line that would read as a head, or that starts with
a backslash or three backticks, is written behind a backslash, which reading takes off; a handle never starts with
one, which is how the two are told apart. Ids are `c` and four letters or digits, none the note has used for a thread,
an anchor or a footnote. The fence is the last ```comments block the note has that is not inside another block (the
Guide shows one inside a ```` block). A selection over several lines is anchored after its last line's words without
a wash, and one inside a highlight takes that highlight as its wash.

Reading never rewrites: each part keeps its lines and offsets, and every change is a few edits at them, so an
unchanged note writes back as itself, a hand-edited fence keeps the lines it does not understand (a head with a time
it cannot read is words of the thread above, or a line of nobody's), and deleting the last thread takes the fence and
the blank line before it, leaving the words as they were. The edits go into the editor as one dispatch
(editor/useNoteComments.ts, as `chooseLook` does): one undo, saved as typing is, and in a team note a few characters
for the CRDT to merge.

**In the editor** (editor/comments.ts): the anchor is a small round in its author's colour, a ring once resolved, and
the caret on it shows it as written; a tap opens the thread's card. The words round a selection are a highlight, and
an open thread sets the highlight's own colour (`--app-mark`) to its author's on a mark around it, so the wash is
theirs, and a resolved one sets it clear. The fence is drawn as the threads, open ones first, as a query's fence is
drawn as its answer; a tap on one opens its card and brings its anchor into view, and the pencil shows the lines.
Nowhere else is any of it installed - a card's small note, a shared page - so the anchor and the fence read as text.

**The card** (editor/CommentCard.tsx, in the app's sheet, editor/CommentSheet.tsx): each comment's author in their
colour, how long ago, the words; a reply field that sends on Enter; Resolve or Reopen; Delete thread, which asks a
second press. Its pieces take a parsed thread and say what was pressed, so a canvas's threads (S9) can draw the same
card, and `countsBy` (core/comments/format.ts) counts each person's comments and replies from parsed threads for the
profile card.

**Colours** (core/comments/colours.ts): in an organization's workspace, your own from the kept list at once and each
member's from the organization's rows, read once a session; elsewhere, and for anyone the rows do not name, ink.

**Ways in.** Comment on the press-and-hold band, second after Cut and Copy (the selection, or the caret's line); in
the bar right after Version history while there is room; in More, with "2 comments, 1 open" when there are threads,
which opens their list; and "Add a comment" on a note's right-click menu in a list, which opens the note with a
comment started on its first line (core/comments/ask.ts, heard by the screen once its editor is there). A note's
title leaves its anchor out (core/noteTitle.ts), so a title commented on keeps its name. Comments are by the
account's handle, or `me` without one (core/comments/author.ts).

**Not yet.** The audit log's "sam commented on Roadmap" and the profile card's counts (S8's last sentence) read what is
here but are not drawn; a canvas's comments are slice 5. A comment made in a team note reaches the others live, as
any edit does (§195).

Tests: core/comments/format.test.ts and colours.test.tsx, editor/comments.test.ts, editor/CommentCard.test.tsx, and
the comment cases in editor/NoteScreen.test.tsx, ContextMenu.test.tsx, NoteSettings.test.tsx, notes/NoteMenu.test.tsx
and academy/lessons.test.ts.

Cites: §159, §172, §191, §193, §195.

## 197. Menus that hang from what opened them (2026-10-05)

Matt, on 2026-09-28: "Allow the header to be overlapped by the popup menus use the glacierUI context menus", and
earlier, of the linked line's options, "make the options typography and iconography heavy so they fit the theme on all
context menus". A branch built this that day (`ui/glacier-menus`, its own §147, a number main has since used for the
home page) and was never merged; main moved some 255 commits on. This is that work brought onto today's code, written
again against it rather than merged.

**What came over as it was.**

- **PopMenu** (`editor/PopMenu.tsx`): the kit's Menu hung from something already on the page. The kit draws its panel
  at the body, z 200, so it covers the header and the tabs wherever it hangs; PopMenu adds what the app's own menus
  had. The back gesture and Escape close it (`core/back.ts`). A press anywhere closes it, heard on the window's way
  down, since a board card and the lanes' line keep their press to themselves and the kit listens only on the way up;
  a press on its anchor or in any of its panels, flyouts too (the kit's `data-menu-stack`), is its own. It goes when its
  anchor leaves the page or is scrolled off the screen. Under a finger its rows are the + list's height and weight. It
  is held to its room: under the bar for a menu from the bar (`reach="down"`), half the screen for one from the page
  (`reach="either"`), so the side the kit turns it to always holds it whole. On the opened Fold it keeps to its
  anchor's side of the crease. `PopSub` lists a menu inside a menu in place under its name, each row carrying its whole
  name, unless a mouse has a window wide enough for a flyout either side of the menu; the kit's flyout ran off a
  phone's edge. The owner hears one `onDismiss`, a microtask after the kit's close, so the kit's focus on the anchor
  lands first.
- **The room** (`editor/menuRoom.ts`): from 8px under the status bar to 8px over the keyboard's top. The + list opening
  above now goes over the header and the tabs as far as the status bar; press and hold's band goes under the caret
  where above would reach the status bar, and never past the keyboard.
- **A board card's menu is the kit's**, through PopMenu, hung from the card's more button and drawn at the body: in the
  lane, the lane cut its last rows and the header covered it near the top. Its rows are data (`cardRows`); a row closes
  the menu and then does what it says; any change to the note, a redraw that takes the more button away, and the view
  going close it (`editor/boards.ts`). The lane menu's look and hooks are gone.
- **The tab and group menus** go through PopMenu, so a back swipe closes them rather than the screen under them.
- **The canvas's + sheet is drawn at the body** (`canvas/AddSheet.tsx`), so its scrim dims from the top rather than
  starting under the header. Done inside AddSheet rather than in CanvasView, which other sessions are changing today.
- **One tick a press.** The + list's and press and hold's rows say their own tick, and the app's tap tick added a
  second: their roots carry `data-haptics="own"` and the tap tick lets a button or a row there off (a field still
  ticks). Back on the Style page, and now on a field's page too, says its own. The + ticks on opening only for a mouse,
  a key or a /, since a finger's press has the tap tick. A tab's or a group's menu opened by holding ticks once
  (`tickHeld`).

**What changed on the way.**

- **The note's right-click menu** (§172) came after the branch. It is PopMenu's too, from a point: PopMenu takes `at`
  as well as an anchor, and puts a mark of no size there at the body. It closes on a press anywhere and the back
  gesture; a right-click elsewhere opens the next where the last one closes, since the close only clears the store if
  it still holds the menu that closed. Its rows are untouched.
- **The organizations' picker** (§171) also came after. It was the kit's Menu with its own trigger, which nothing could
  close by the back gesture; it is PopMenu's now, open while the people icon says so, and a second press on the icon
  closes it. Its rows are untouched.
- **The Mac's inset.** The branch kept menus under the Mac's 44px title strip. Main has since put the three buttons in
  the bar's own row and set the inset to nothing (app.css `data-titlebar`), so on the Mac the room starts at the
  window's top; followed main.
- **Press and hold's band** gained a field's page (§158) since; it is placed by the same rule.

**What main already had, kept.** The sheets: on a desktop every sheet is now a window in the middle (§189), and they
stay sheets, as the branch said. The floating cards (`notes/FloatingCard.tsx`: the notes drawer, the aside, the
notifications) are dialogs, not menus, and keep their own close on a press outside. The top bar's tools
(`editor/NoteTools.tsx`, `editor/toolRoom.ts`) have no menu of their own; More opens the sheet. The + list and press
and hold stay the app's own, not the kit's: the kit's menu takes the focus as it opens, which would put the phone's
keyboard away while typing. Whether they should wear the kit's glass is still Matt's to say.

**Dropped.** Nothing of the branch's behaviour. Its measurements (Playwright on a phone, the Fold and the Mac, both
engines) were of its own build and are not repeated here.

Measured, built and served, in the browser pane at 1024 x 768 with a mouse: a note's menu at the pointer, drawn at the
body with its mark, turned upward whole from a right-click 13px off the window's foot, and Escape took it and its
mark away; a card's menu hung under its more button at the body, 0 of 15 points covered, a press on the header
closed it, Escape gave the focus back to the more button and left the note open; a tab's menu hung down over the
header's foot. Not seen in a browser: the + list over the header with a keyboard up, the Fold's crease and a
finger's rows, which are the tests'.

Tests: editor/PopMenu.test.tsx (the placing from the anchor and from a point, the names on the anchor, the back
gesture, Escape and its focus, a press kept from the page, the anchor leaving, the crease, the rows under a name),
editor/menuRoom.test.ts, core/haptics.test.ts (the let-off and the holds), editor/AddList.test.tsx and
editor/ContextMenu.test.tsx (where they sit, the mark, the two Backs' ticks), editor/boards.test.ts (the card's menu at
the body), notes/NoteTabs.test.tsx (rows in place, the flyout for a mouse, the back gesture, the hold's tick, the
organizations' picker), notes/NoteMenu.test.tsx (the mark, the back gesture, a press anywhere and the next
right-click), editor/NoteScreen.test.tsx (the list and the band beside the page), canvas/CanvasView.test.tsx (the +
sheet at the body).

Cites: §141, §158, §171, §172, §189.

## 198. Canvases for the team: the fifth slice of notes shared in an organization (2026-10-05)

docs/SHARED.md, S9. Matt, with the shared-notes brief: "while you're building this also build in cursor tracking on
canvases and comments" - and "Please do the rest of the slices".

**The canvas is its types.** A canvas filed in an organization's workspace was already the team's (§193), but as
words: its JSON in the note's `Y.Text`, where two members' edits at once merged letter by letter into a splice that
was no JSON at all. Now the team's document holds the canvas as types beside the words (core/team/canvas.ts): the
nodes a map by id of each node's fields, a card's words a `Y.Text` so typing in one card by two members merges, the
lines a map by id, the z-order an array of ids, the threads a map by id. The document's own named roots, so two
devices seeding at once from the same JSON write the same keys into the same maps and neither loses the other's;
seeded the first time a member draws the canvas, after the note's room has had its say (`TeamRoom.caughtUp`: alone
in the room, an answer applied, or two and a half seconds), so a structure about to arrive is not seeded over. Two
members moving different cards, or the same card at once, keep what each did or take one of them whole - never a
splice of two numbers.

**The words follow the types.** Once seeded, the note's words are read from the types (core/team/doc.ts `words`:
the front matter as the text has it, the JSON as the types say it) and never written into the shared text, which
is what garbled; `reconcile` reads words that reached the note without the view - the JSON typed by hand, Claude -
into the types, and only a changed front matter into the text. The view edits as before, handing back the whole
canvas, and the structure writes only what changed (canvas/useTeamCanvas.ts); a canvas note's editor, which shows
its JSON behind the view switch, is not bound to the shared text. The camera is not refitted for another member's
move. An attempt that wrote the JSON into the text in the same transaction as the types was tried first, and its
test showed two replies made at once leaving `"replies": [,` behind: the words were taken out of the merge.

**Pointers, and the card being written in.** The note's room carries `pointer` (the canvas's own pixels, said at
most every 80 ms) and `card` beside `user` in its awareness; the others are drawn as small arrows in their colours
with their handles (canvas/Pointers.tsx), at their pointers' places and one size on the screen at any zoom, and the
card one is writing in wears a ring in their colour with their handle on its corner. The organization's page says
"editing <title>" for a canvas as for a note, and Jump to cursor opens it centred on the member's pointer
(`goTo`; shell/screen.ts `cursor` is a caret or a spot).

**Comments on cards.** A thread is a `comments` entry in the canvas's JSON, after the edges - `{ id, node, by, at,
text, replies, resolved? }`, Ghost.md's own field, which Obsidian reads past and which a card taken off takes with
it - with the shape a note's threads have (§196), so the note's thread card and sheet draw it (canvas/comments.ts,
canvas/useCanvasComments.tsx, editor/CommentCard.tsx, editor/CommentSheet.tsx) in the members' colours
(core/comments/colours.ts). A round on the card's top-left corner, in the colour of who started the first open
thread, says how many are open, hollow once all are resolved, and opens the thread or the card's threads as a list;
Comment on the picked card's bar starts one. In the team's structure the replies are an array both members' replies
land in.

**Not yet.** A member's profile card does not count their canvas comments. A canvas's threads are not in the
organization's audit log sentence. The sixth slice (S11, the key's rotation and the log's pruning) is next.

Tests: core/team/canvas.test.ts (seeded once, two devices seeding at once, a card each moved and the same card typed
in both kept, the same card moved by both landing whole, cards and lines added and taken off in order, words
reconciled into the types and a rename into the front matter alone, two replies at once both kept),
canvas/comments.test.ts, canvas/jsonCanvas.comments.test.ts, canvas/CanvasView.team.test.tsx (a member's move
drawn, pointers and the ring, the wait for the room, the jump), canvas/CanvasView.comments.test.tsx (the round, the
thread's card, Comment on the bar), the room's catch-up in core/live/team.test.ts.

Cites: §193, §195, §196; docs/CANVAS.md "In an organization".

## 199. The key's turn: the sixth slice of notes shared in an organization (2026-10-05)

docs/SHARED.md, S11. Matt: "Please do the rest of the slices". The organization key (§191) was made once and never
replaced: a member who left, or was removed, kept a copy of it on their devices, and everything the team wrote
afterwards was sealed under a key they held.

**A turn owed.** When a member leaves or is removed, the service records a turn (`org_key_turns`, a row per going;
server/src/store/orgs.rs `remove_member`) and says the key is stale - on `GET orgs/{id}/keys` and on every row of
the list (`keys.stale`) - until the next generation is made, which clears the rows. An invitee withdrawn owes
nothing, having had no wrap.

**The next device turns it.** On a pass, an organization whose list says stale and whose generation in force this
device holds (core/orgs/orgKeys.ts `turnDue`) is first synced as ever under the old key, so the team's notes are
whole here; then the device makes the generation after it, wrapped for every member who remains and has a public
key (`turnOrgKey`: `POST keys { make }`, and 409 means another device turned it first, whose wrap is read next
pass), and puts every team note again under the new key (core/team/sync.ts `resealTeamNotes`: the row with the
document's whole state, its log cut to it, its versions file and its pictures sent again sealed afresh). The
generation before stays in hand for the session.

**Nothing new under the old key.** Every write names the generation its body is sealed under (`generation` on the
row, the updates and a file; server/src/org_notes.rs), and the service refuses one that is not in force, 409 with
the one that is, so a device that slept through the turn stops that organization's pass (`KeyTurned`) and seals
under the new key on its next, rather than leaving updates nobody can open. A row or an update still under an
older generation - written before the turn and not re-sealed yet - is read with this account's wrap at that
generation (`GET keys?generation=`, `orgKeyAt`) and put again under the one in force by whoever read it.

**The log held.** The service keeps a note's log to 500 updates (store/org_notes.rs `UPDATES_KEPT`): a post past
that is answered 409 `snapshot` with the head, and the device puts the row with `upTo`, which cuts the log and
carries the pending updates, then posts on.

**Not yet.** A member's own devices still hold the old key until the app restarts; the turn protects what is
written from then on, not what they already had, which is the nature of a copy. Rotation on a schedule, or by hand
from the organization's settings, is not offered.

Tests: core/orgs/orgKeys.test.ts (the turn: stale, the next generation wrapped for those who remain, the older
generation kept and read back, a turn made elsewhere first), core/team/sync.test.ts (every note re-sealed with its
log cut, its picture and its versions readable under the new key alone; a write under a stale generation refused
and the pass stopped with the turn; a row under an older generation read and put again; the log's cap met with a
snapshot); on the service, orgs_tests.rs (a turn owed and answered, an older wrap read) and org_notes_tests.rs (the
generation refused, the log's cap).

Cites: §191, §193, §195, §198.

## 200. Organizations on the home page, and a pass that survives one organization (2026-10-05)

Matt: "add organizations to the home page". Under the notices, over the notes, a section **Organizations** with a
card for each organization joined (home/HomeOrganizations.tsx): its colour, its name, how many are in it, how many
notes are filed in its workspace, and who is in the app now - "sam is editing Roadmap, 1 more here", from the
organization's own room (§195). A tap opens its dashboard. One card a row on a phone, as many as fit on a wide
window. Not drawn while searching or inside one workspace, nor for an account in no organization; an invitation
still waiting stays the notice above it.

And from the same afternoon (Matt: "It doesn't seem like notes are syncing in the organization or updating in real
time", "It also says we're both not in the app right now"): the dashboard now counts the device reading it as in
the app - your own row wears the dot, and your profile says "In the app now, on this device" - since the room only
ever listed the others; and in the pass, one organization's channel failing, or one team row that will not open, is
counted as unsent with the organization's name in the reason rather than failing the whole sync (core/sync/engine.ts,
core/team/sync.ts `pull`), beside the per-step catches the pass was given the same hour.

Tests: home/HomeOrganizations.test.tsx, the self-presence lines in notes/OrganizationScreen.test.tsx, the unread
row in core/team/sync.test.ts.

Cites: §195, §199.

## 201. New tickets from a query's board (2026-10-05)

Matt: "add the ability to add new tickets to query boards from the board like we can on the standard board". A
ticket board drawn by a ```query (`from: tickets`, `show: board`) has a **+** at the end of each lane's head, as a
```board's column has (editor/boards/composer.ts). It opens a field at the top of the lane drawn as the card it is
about to be - the same corners, ring, empty box and Add as the ```board's - and Enter or Add makes the ticket; the
field stays open and empty for the next, and Escape, or leaving it empty, puts it away. A press on the + of a lane
already open takes the focus back to its field.

What the ticket says is what lands it in that lane (core/query/draft.ts `ticketDraft`): the board's grouped field set
to the lane's value (a status, or a field of words; the "No …" lane and lanes of days, people or priorities have no
+, since a lane's name cannot write those back, as they cannot take a dragged card), the notebook `from: [[…]]`
names, the labels its `#tag`s ask for, the assignee its `@person` does, and every `field = value` in `where:`. Only
what every record listed must have is taken: a source or a test under `or` or `not` is one of several ways in and is
left to the person, and a field the ticket's maker sets (`id`, `type`, `title`…) is never copied.

App makes it (`addFromQuery`), as New ticket in a notebook does (`openTicketWithin`, §157): the notebook `from:`
names, else the one the board's own note is in; its next key read across every note, the Trash's too; its
workflow's first open status, then the lane's. Its page goes in the notebook's index, and it is filed in the
notebook's workspace, else the board's note's. It is not opened: the board is where the next one is typed. A title
some note already has is refused with a toast, since `[[links]]` find notes by title. Where the board is drawn in
the notebook itself, the index line is written by the board's editor (editor/queries.ts), never under it. A board of
to-dos, or of notes, has no + : a to-do has no one note it belongs in, and a note no workflow.

Tests: core/query/draft.test.ts; the four in editor/queries.test.ts under "a new ticket typed at a lane of a board".

Cites: §157, §159, §169.

## 202. An organization's notes at once: the word to fetch, and the key wrapped at the invitation (2026-10-05)

Matt: "when users first go to an organization it takes a while for the notes to sync locally to them like upwards of
10-15 minutes sometimes, make this instantaneous syncing should be real-time" and "maybe we need to store the notes
on the server ready to go so we can rapidly sync to new users". The notes were on the service already, sealed; what
a new member waited for was the key and the clock. A pass ran every five minutes: one for an existing member's
device to notice them and wrap the organization key, one for their own device to read the wrap, and the notes in the
pass after that, with every note's versions file and pictures fetched before the next note was shown.

**The key waits with the invitation.** A member's device now wraps the key for someone invited as well as someone
joined (server/src/store/keys.rs: `missing` lists both, and a wrap is kept for both), and does so right after sending
an invitation; the wrap is read only by a member, so an invitee learns nothing until they accept, and then has the
key with nobody else online. Someone who joins by a link, or had no key pair when invited, is wrapped for by the
word below.

**The word to fetch** (core/live/nudge.ts). Every member's device holds the organization's `sync` room on the relay
while the app is open, key or no key, and says three unsealed words in it, none a secret: `need` (this device has
no key - said after registering its own key pair, on joining the room and whenever someone comes in), `keys` (a
device holding the key has just wrapped for whoever lacked one), and `changed` (this device just wrote a row, an
update or a file to the organization). A device that hears `need` and holds the key wraps at once; one that hears
`keys` reads its wrap; one that hears `changed`, or has just got the key, runs a **team pass** - the feed, the list,
the keys and the organizations' channels, without sweeping the account's own notes (core/sync/engine.ts `team`). So
an edit made anywhere reaches the other members' devices in the seconds its own pass takes to send it, and the
five-minute pass is the fallback it always was.

**Notes before their files.** A pull applies every row first, tells the list (`pulled`), and only then fetches the
versions files and pictures (core/team/sync.ts `later`), so sixty notes are readable in the time sixty rows take.

The keys step also runs whenever an organization's key is not in hand, not only when a wrap is known to be waiting,
since the first thing a new member's device must do is register its key pair for someone to wrap to.

What the relay learns grows by this: that a member's device is in the app, and when it wrote to the organization.

Tests: core/live/nudge.test.ts, the invitee cases in server/src/orgs_tests.rs and store/keys.rs, `keyWork` in
core/orgs/orgKeys.test.ts, the outcome's `sent` in core/team/sync.test.ts.

Cites: §191, §193, §195, §199.

## 203. The tabs scroll cleanly on a desktop (2026-10-05)

Matt: "scrolling on the tabs is glitchy on desktop".

Two causes, both in the row of tabs.

- **The smoke at its ends was a filter on the row that scrolls.** With more tabs than fit, the row wore the wisp
  (art/wispSides.ts), so every frame of a scroll pushed the whole row through the filter again. In the Mac app's engine
  that stalls: art/wispMask.ts has the measurement, over half a second a repaint, and it is why the page's headers
  left the filter on a desktop (§54). The row had not. Now the Mac app and any desktop, a fine pointer that hovers,
  keep the plain fade at each open end, 32px where it was 12px under the smoke. A phone keeps the smoke.
- **A sideways swipe was counted twice.** The row scrolls by a trackpad's swipe by itself, and the wheel handler
  (core/scrollSideways.ts) added the same swipe again, so the tabs moved twice as far as the fingers. The handler now
  takes only a vertical turn of the wheel, which a sideways row cannot use any other way. Measured in Chromium at
  1024px with eight tabs open: a swipe of 300 moved the row 300, and 600 with the old line put back.

A scroll also asks less each frame: which ends are open, and nothing else. It used to measure the open tab and place
its outline again, which a scroll never moves.

Tests: art/wispSides.test.ts (not worn on a desktop or in the Mac app), core/scrollSideways.test.ts.

Cites: §54, §178.

## 204. Backup: every note onto a removable drive, as files (2026-10-05, native generation 26)

Matt: "add a section to the settings called "Backup" it should prompt the user to plugin a removable drive to backup
all the notes in the app to workspace folders and such under a Ghost.md folder on the root of the drive".

**Settings › Backup**, under Workspaces, where a drive can be written: the app on the Mac and on Android, not a
browser or an iPhone (settings/BackupPane.tsx). With no drive in, the page asks for one - "Plug in a drive" - and
looks again every two seconds while it is open, so a drive plugged in shows up by itself (core/backup.ts
`listDrives`). Each drive is a row: its name, its room and the last backup it holds ("Last backed up today, 18:52 ·
312 notes"), and **Back up**. While a backup runs, how far it has got and Stop; after, what it did ("Backed up 312
notes to KINGSTON: 14 files written, 326 already there."), and on the Mac **Eject** (`diskutil eject`).

**Not the export (§167).** The export makes one zip to carry away; a backup is a folder anyone can open, kept up to
date: `<the drive>/Ghost.md/` with `Inbox/`, `Workspaces/<name>/` and `Organizations/<name>/` - the library's own
folders (docs/LIBRARY.md) by the names Settings gives them - each note's `.versions` file beside it, the pictures,
films and recordings under `Attachments/`, a README, and `.ghostmd-backup.json`, which says what each file was when it
was written (a note by an FNV-1a hash of its words, a picture by its size and time). The next backup to the same drive
writes only what changed, or what the drive lost or holds at another size, and takes off a note gone from the app -
but only a file the backup wrote: nothing else in `Ghost.md/`, and nothing outside it, is ever touched. The README and
the manifest are written last, so a backup stopped part way leaves the last manifest true of what it names. One that
would not fit is refused before it writes anything (the drive's room from statvfs on the Mac).

**The Mac** (backup_commands.rs): a drive is a mount of its own under `/Volumes` - not the boot volume's link to `/`,
nor a folder left there - that `diskutil info -plist` (read through the Mac's own plutil, no plist crate for five
keys) calls neither internal nor a disk image, and writable: a USB stick, an SD card in a reader or the Mac's own
slot, an external disk; never a mounted .dmg, the Recovery volume or a network share. Asked once per drive while it
stays mounted. Every file lands whole, through a temporary file beside it and a rename.

**Android** (files/BackupDrives.kt): a drive is a `StorageVolume` the phone calls removable and has mounted for
writing. Ghost.md asks for **no storage permission** (none would be granted for a drive, and Google Play asks for a
declaration of them): the first backup to a drive opens the system's own picker on the drive's root
(`createOpenDocumentTreeIntent`, Android 10 and up), the person allows it once, and the grant is kept by the drive's
id, so the next backup asks nothing; LibraryTree's tidy at launch keeps these grants. A folder chosen inside the drive
is refused with a sentence that says to choose the drive itself, so `Ghost.md/` lands on its top level. The writing
is Rust's, through the folder bridge a library folder uses (saf.rs `TreeTarget`, §187), and one new call,
LibraryTree.kt `copyIn`, which streams a picture, film or recording from the app's own storage onto the drive and
refuses any file outside it.

Tests: backup.rs (the plan, only what changed, nothing of the person's taken off, no room, a stop, the folder
target's whole writes), backup_commands.rs (which `diskutil` answers are a drive), core/backup.test.ts,
settings/BackupPane.test.tsx, and paths.rs's check that LibraryTree.kt has `copyIn`.

Cites: §167, §187.

## 205. Library folder and Export are settings (2026-10-05)

Matt: "library folder should be a setting not a plugin and export should be a setting secion".

**Settings › Library folder** (settings/LibraryFolderPane.tsx, core/libraryFolder.ts) is §187's page as it was, with
its cards and its search words, but no longer behind a plugin's switch: where the notes live is the app's own
business, not an extension's. It calls the app's commands directly (`invoke`, with `FOLDER_GENERATION` 25 for the
binary), where it went through a plugin host that checked its manifest; the library-folder plugin is gone from
`BUILT_IN`, and a `library-folder` switch left in `glyph-plugins` is read by nothing. Listed where the app keeps its
notes in files it can move: the Mac and Android, not a browser or an iPhone.

**Settings › Export** (settings/ExportCard.tsx) is §167's card as a section of its own, out of Account, where it sat
after Location: carrying everything off as one zip is not something an account does, and it works signed out. Listed
everywhere, since a browser exports its own zip and an iPhone says it cannot yet.

The three that carry the notes - Library folder, Backup (§204) and Export - share a card of their own under Account's.

Tests: settings/LibraryFolderPane.test.tsx (moved from plugins/folder/, its manifest's test now the generation's),
SettingsSheet.test.tsx's lists and cards, AccountPane.test.tsx without Export, PluginsPane.test.tsx and
registry.test.ts without the plugin.

Cites: §167, §187, §204.

## 206. Report, in an organization's settings (2026-10-05)

Google Play's rules for an app where people share what they write ask for a way to block and a way to report, in the
app. Blocking was already there in the organization's own terms: decline an invitation, leave, and for an owner or an
admin, remove a member. Reporting was not. **Report** is a sixth section of an organization's settings
(settings/OrganizationSheet.tsx), amber, in the last group above Leave or Delete, with one row: "Report a member or a
note" opens an email to the address on the privacy page, its subject naming the organization and its id, its body who
is reporting.

It is an email and not a form to the service because team notes are sealed under the organization's key (docs/SHARED.md):
the service could carry a report's id but never what it is about, so the person has to bring the words, and the page
says so. The opener's default scope already lets `mailto:` through (src-tauri/capabilities/default.json), so nothing
native changed.

Tests: settings/OrganizationSheet.test.tsx (six sections; the email's address, subject and body).

Cites: §171.

## 207. The dock's shadow is the wisp (2026-10-06)

Matt: "Change the shadow behind the floating dock to be the wisp blur effect we use on the bottom under the header".

The home page's dock had a dark drop shadow (`0 8px 28px`), and behind it the halo of GLY-81: a blur and a paper wash
feathered evenly over 3rem. The drop shadow is gone, and the halo's edge is the header's smoke (art/dockSmoke.ts):
the recipe art/wispMask.ts makes the header's band from - turbulence over a soft ramp, taken to alpha through a curve
- with the ramp wrapped round the dock's pill, so what scrolls toward the dock dissolves in wisps that thin out as
they leave it. The ramp is blurred from a pill standing half the reach out, not the dock's own edge: a blurred edge is
half gone where the edge was, and a ramp from the dock's edge left smoke a few pixels deep (seen by tinting the halo
red in the pane, which is how this was tuned; a count of pixels would not have said). The curve is gentler than the
header's and the noise the same both ways, since a halo leaves on every side where a header has one lip.

A mask on every engine, as the Mac's header wears: the filter that bends the page under a phone's header is worn by
the page itself, and nothing can bend only what lies round a floating thing (`backdrop-filter: url()` is not in
WebKit). The image is made for the halo's measured size (`useDockSmoke`), and again when the dock changes size; until
then, and where nothing lays out, the halo keeps its two feathering gradients. Still, as the halo was: nothing drifts.

Tests: art/dockSmoke.test.tsx.

Cites: §94 (the wisp and the blur under a header), GLY-81.

## 207. Settings is the header's cog (2026-10-06)

Matt: "Move the settings cog from the floating dock to the header to the right of the notification bell". The cog
is a ring in the tab bar (notes/NoteTabs.tsx `onSettings`), after the bell and before the screen's More, in all four
bar styles; the home dock (home/HomeScreen.tsx) is the palette, write and Speak. A phone's note screen, whose bar is
quiet, has neither the bell nor the cog, as before for the bell.

Tests: notes/NoteTabs.test.tsx (the cog after the bell), home/HomeScreen.test.tsx (no Settings in the dock).

Cites: §206.

## 209. Ghost.md for Windows (2026-10-06)

Matt: "Build and compile a windows build and host it on the website ideally signed and notorized if possible".

**Built on a Windows runner** (.github/workflows/windows.yml), by hand or on a push to the `windows` branch: a Mac
cannot build it, since the speech and language engines are C++ built with MSVC, and the repository is public, so the
runner costs nothing. It makes the NSIS installer (x64, about 15 MB; WebView2, the page's engine, is fetched by the
installer where a PC has none), then runs it silently, starts the app, and twenty seconds later checks it is still up
with a window, keeping what the screen shows as an artifact beside the installer. About thirteen minutes cold; the
engines' build is cached, failed runs included.

**What the code needed** was little, since the desktop app was the Mac's and the page already asks which it is
(`isMacApp` for the title bar): `sysconf` and a descriptor adopted from Android's picker are Unix's (llm/hardware.rs,
export.rs), and the bundle's icons had no `.ico`. Backup (§204) lists Windows' removable drive letters through
kernel32 itself (backup_commands.rs `win`), a stick or a card with a volume in it; a USB hard disk is "fixed" to
Windows and is not listed yet, and there is no Eject of the app's own. A meeting's own sound (§186) and the Mac's
traffic lights are not there.

**Published by scripts/deploy-windows.mjs**, which fetches the run's artifact with `gh`, reads the installer's PE
header for whether it is signed (scripts/lib/pe.mjs; macOS has no signtool), hashes it, and places
`/glyph/glyph-setup.exe` and then `/glyph/windows.json` by rename, as the APK and the Mac app are placed.
deploy-ota.mjs protects both from its `rsync --delete`. The download page offers it (landing/: a Windows way, the hero
button for a Windows visitor, the version and size from windows.json), and ghostmarkdown.com's Caddy block serves the
two paths from the release directory (deploy-landing.mjs, which now rides an open connection rather than logging in
again: a chain thought to be one login had been two).

**Not signed.** Windows has no notary; what it has is Authenticode, which needs a certificate bought in Matt's name
(Azure Trusted Signing, or a certificate from a CA), and none is held. So the installer is unsigned, SmartScreen says
"Windows protected your PC" until More info › Run anyway, and the page says so under the downloads for as long as
windows.json says `signed: false`. The workflow's header names the two secrets a certificate would go in.

It does not update itself as a binary: the page inside it takes over-the-air builds as every app does (§14), and a
new installer is a new run and a new deploy-windows.

Tests: scripts/lib/pe.test.mjs; the Windows way in core/backup.test.ts; the runner's own first launch.

Cites: §14, §167, §186, §204.

