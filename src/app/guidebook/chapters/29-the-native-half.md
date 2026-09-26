# The native half

_The Rust in `src-tauri` and the Kotlin around it: what each owns, the seam the page crosses, and the one number that keeps a bundle and a binary honest with each other._

## What lib.rs lays out

`src-tauri/src/main.rs` is six lines that call `glyph_lib::run()`. `src-tauri/src/lib.rs` declares every module with a line on why it exists, then builds the app:

- four plugins: the opener, haptics and deep links, plus decorum on a desktop;
- three URI schemes, registered on the builder rather than in `setup`, because a scheme has to exist before the webview is made;
- five installs in `setup`: the notes, capture, the models, OTA and links;
- 51 commands.

On exit, a capture still decoding and a model still running are cancelled and joined, before whisper.cpp's static destructors run.

The crate splits in two, and the split is the rule that matters most. The modules below are named as they sit in `src-tauri/src/`.

### The Tauri-free modules

| Module | What it owns |
|---|---|
| `note.rs` | The `Note` that crosses the IPC seam, in the page's `camelCase` |
| `library/` | The notes as Markdown files, and `.glyph/index.sqlite` over them |
| `store.rs` | The database the notes lived in before 1.3.0, read once by the move into the library |
| `whisper/` | Speech to text, with whisper.cpp |
| `llm/` | The language models, with llama.cpp |
| `model_files.rs` | A model file: its spec, whether it is here, and the verified, resumable download |
| `lock.rs` | The one way to take a `Mutex`: poison is recovered, never obeyed |
| `fsx.rs` | Whole-file writes, JSON with a fallback, removals where gone counts as done, and `plain_id` |

None of these holds a Tauri type. `note.rs` gives the reason: a process with no Tauri in it must be able to link them. DESIGN §6.1 planned a separate capture process that never shipped, but the door is used anyway: the update-alert worker reaches `ota::peek` over JNI with the app closed. So the caller supplies every path, and nothing in these modules finds a directory by itself. `model_files.rs` borrows Tauri's async runtime to sleep between tries, but takes no Tauri type.

### The Tauri seams

| Module | What the page reaches it for |
|---|---|
| `commands.rs` | The notes: list, get, create, update, pin, archive, delete, the guarded voice-command writes, a note from sync, and Reveal |
| `capture_commands.rs`, `capture_commands/` | Live dictation: start, push, stop, rewind, the speech models and the better-words pass |
| `ai_commands.rs` | The language models: the catalogue, downloads, runs, cancelling, and reading a spoken command |
| `recordings.rs` | A note's kept tape, `recordings/<id>.wav`, played through the `rec` scheme |
| `images.rs` | Pictures, `images/<uuid>.<ext>`, drawn through the `img` scheme |
| `links.rs` | `ghostmd://` links, kept until the page takes them with `links_take` |
| `link_preview.rs` | A web page's title and summary, for the card under a link |
| `notion.rs` | Notion calls the page cannot make cross-origin, with a token only Rust holds |
| `reset.rs` | Starting over, from the developer settings |
| `update_alerts.rs` | The JNI entry the update worker calls, on Android only |
| `ota.rs`, `ota/` | Over-the-air bundles, served through the `ota` scheme |

A seam resolves a path, takes the lock, calls its Tauri-free half, and turns the error into a `String`, which is what `invoke()` rejects with in JavaScript. Every name that will become a path is checked first (`fsx::plain_id`, `images::valid_name`), because it came from the page. A scheme is `http://<scheme>.localhost/` on Android and Windows and `<scheme>://localhost/` everywhere else, the Apple platforms included. `platform.rs` holds the two window fixes one platform needs: the key window on iOS, and the traffic lights on macOS.

From the page's side, `src/app/core/tauri.ts` is the bridge: `isTauri()` looks for `__TAURI_INTERNALS__`, and `invoke` loads `@tauri-apps/api/core` only when it is there. Tests replace that module with a factory that lists only those two names, which is why `src/app/core/events.ts` and `src/app/core/nativeGeneration.ts` are modules of their own.

## One resolver for directories

`src-tauri/src/paths.rs` is the only place the app's directories are resolved.

- Under `<app_data_dir>`: `Library/`, `recordings/`, `images/`, `models/` (whisper's and the formatter's together) and `ota/`, plus `notion.json` and the old `glyph.sqlite`, which are named where they are used.
- Under `<app_cache_dir>`: `picked/`, where the Android shell leaves a shrunk picture, and `updates/`, where a verified APK waits.

Four of those names are written in Kotlin too, under the Kotlin root given below, which resolves them from its own `Context` and cannot ask Rust:

| Name | Kotlin twin |
|---|---|
| `Library` | `files/LibraryDocuments.kt` |
| `ota` | `updates/UpdateCheckWorker.kt` |
| `picked` | `MainActivity.kt`, the picture picker |
| `updates` | `MainActivity.kt`, `installApk` |

`the_kotlin_twins_name_the_same_directories`, a test in `paths.rs`, reads the Kotlin sources. It fails if either side is renamed alone, or if a Kotlin file stops naming `paths.rs` beside its twin.

## What iOS lacks, one sentence each

`src-tauri/Cargo.toml` builds none of whisper.cpp, llama.cpp, reqwest, sha2 or ring for iOS. The commands still exist there, with the same signatures, so the page needs no platform switch to load.

Each one answers with a sentence from `src-tauri/src/unsupported.rs`, through `on_ios`, as the first statement of its body under `#[cfg(target_os = "ios")]`. There are six sentences: transcription, formatting, updates, the APK, Notion and link previews. A test keeps them word for word, since a person reads them.

The updates sentence says over-the-air updates are "Android-only". In the code only iOS refuses `ota_check`, and the Mac looks for bundles as a phone does.

## Native generations

A bundle that arrives over the air may run on a binary older than itself. The contract between them is one number.

- **`NATIVE_GENERATION`**, in `src-tauri/src/ota.rs`, is what this binary provides: 19 at HEAD. The comment above it is the one complete register of which commands arrived in which generation, from 2 (signed manifests, 0.3.0) to 19 (revision-checked create and update, the guarded voice-command writes and their undo, and `ai_infer_command`).
- **`BUNDLE_REQUIRES`**, beside it, is what the page built from this tree needs, and it is 19 too. `vite.config.ts` reads it out of the file with a regex and stamps it into `ota.json`, so both stay literals. A compile-time test keeps it at or under `NATIVE_GENERATION`.
- **A generation never goes backwards.** Generation 5 added handwriting, 0.5.2 took it out again, and the number stayed. Generation 6 was a bump for a removal, so that older phones would learn a new APK existed.

On the page, each feature asks `hasNativeGeneration` in `src/app/core/nativeGeneration.ts`, with a constant of its own kept beside the command it gates. The question goes to `ota_status` once per page load, and the one answer is shared. It is 0 in a browser and 0 on failure, which hides a feature rather than calling a command that is not there.

| Constant | Generation | File, under `src/app/` |
|---|---|---|
| `RECORDING_GENERATION` | 6 | `capture/engine.ts` |
| `REFINE_GENERATION` | 7 | `capture/refine.ts` |
| `PASTE_GENERATION` | 9 | `core/images.ts` |
| `AI_GENERATION` | 10 | `ai/available.ts` |
| `RESET_GENERATION` | 11 | `core/reset.ts` |
| `REVIEW_GENERATION` | 13 | `ai/review.ts` |
| `SYNC_GENERATION` | 16 | `core/sync/engine.ts` |
| `PREVIEW_GENERATION` | 17 | `core/linkPreview.ts` |
| `FILES_GENERATION` | 18 | `core/libraryFiles.ts` |

A plugin declares its generation in its manifest, and `src/app/plugins/host.ts` asks the same question: Notion's is 12 (`src/app/plugins/notion/manifest.ts`).

While `BUNDLE_REQUIRES` is 19, a bundle from main only ever runs on a generation-19 binary. `src-tauri/src/ota/install.rs` reports `needs-native` for a manifest that needs more, and `src-tauri/src/ota/boot.rs` never claims one. So inside the app, every gate in the table answers yes today. The gates still answer no in a browser, and they are what would let a later page run on an older binary if `BUNDLE_REQUIRES` were held back. The stake and the quarantine are in [[Over the air, and releases]].

## The Android shell

The Kotlin lives in `src-tauri/gen/android/app/src/main/java/com/mattssoftware/glyph/`. Tauri generates most of `src-tauri/gen/android`; the files below are hand-written and tracked. `MainActivity.kt` says so in capitals, because `tauri android init` would replace it with a two-line template.

**`MainActivity.kt`** is the one activity, `singleTask`, and the door the side key comes in through. A capture arrives cold or warm:

- **Cold**, it is recorded before `super.onCreate`, so the window can show over the lock screen, and the page collects it with `GlyphHost.takeLaunch()`.
- **Warm**, it arrives as `onNewIntent` and is pushed in with `window.__glyph.capture()`. The WebView is resumed first, because a paused one queues scripts instead of running them.

Showing over the lock screen is granted per capture and withdrawn by `endCapture`. The activity also hands the back gesture to the page, streams the Fold's hinge angle, shrinks a picked picture into `picked/`, pads the WebView above the keyboard, and passes a verified APK to the installer.

The bridge is two objects, both typed in `src/app/core/host.ts`:

- **Inbound**, the activity calls `window.__glyph`: `refresh`, `capture`, `alerts`, `image`, `back`, `hinge` and `screenOff`.
- **Outbound**, the page calls `window.GlyphHost`, the `JavascriptInterface` the activity registers, with fourteen methods, from `takeLaunch` to `browseFiles` in the order the type lists them.

`window.__glyph` is one object shared by every module that answers the host. `answerHost` merges a registration and removes only its own key: when the store assigned the whole object for its refresh hook, a second handler would have wiped the first, and the side key would have done nothing while the app was open. Every `GlyphHost` method added after the first APK is optional in the type, because an over-the-air page can be running on an APK from before it.

**The three assistant services** in `capture/` make Ghost.md eligible to be the phone's digital assistant, which is what the side key's press-and-hold opens:

| Service | Why it exists |
|---|---|
| `GlyphInteractionService` | The `VoiceInteractionService` that qualifies for the role, and the only way to be started over the lock screen |
| `GlyphSessionService` | Hands the system a `GlyphSession`, which starts the activity with the capture action and hides at once |
| `GlyphRecognitionService` | Recognises nothing and answers busy; Android refuses an assistant that names no recognition service |

The session calls `startActivity`, not `startAssistantActivity`. The second would open a separate task, and with it a second Tauri runtime. Transcription happens in the page and in Rust, never in these services.

**`files/LibraryDocuments.kt`** is a read-only `DocumentsProvider`. It lists the library in the Files app as "Ghost.md", with the library's own folders (`Inbox` and the workspaces) as folders and each note as its `.md`, and hides `.glyph/`. It is read-only because a note changed behind the library's back would reach neither its index nor sync. `GlyphHost.browseFiles` opens it, from generation 18.

**The update check** is in `updates/`. When alerts are switched on, `UpdateAlerts.kt` schedules `UpdateCheckWorker` every six hours. `UpdateCheck.kt` loads `glyph_lib` itself, since WorkManager can start the process with no activity, and calls `run` in `src-tauri/src/update_alerts.rs`. That answers from `ota::peek`, with the same signature checks and remembered sources as `ota_check` and no `AppHandle`. A panic is caught before it can unwind into the JVM, and one release alerts once.

**`src-tauri/gen/android/app/build.gradle.kts`** makes three channels from one tree:

| Channel | Switch | Id | Name |
|---|---|---|---|
| production | none | `com.mattssoftware.glyph` | Ghost.md |
| staging | `GLYPH_STAGING=1` | `com.mattssoftware.glyph.staging` | Glyph Staging |
| dev | `GLYPH_CHANNEL=dev` | `com.mattssoftware.glyph.dev` | Glyph Dev |

Staging installs beside the real app with its own data and never checks for updates. Dev runs the page live from the Mac's dev server. What differs by channel, such as the launcher shortcut's target, lives in `src-tauri/gen/android/app/src/channel/<channel>/res`.

`GLYPH_STORE=play` makes the Google Play build: the same app and id, with `src-tauri/gen/android/app/src/store/AndroidManifest.xml` merged in to remove the permission to install packages. `BuildConfig.STORE` makes `installApk` answer `store`, and `STORE` in `ota.rs` stops the app looking for an APK at all. The web bundle still updates over the air. A release build is never debuggable, and runs no R8, which could rename the Kotlin that is reached by name: `GlyphHost`, the services and the JNI entry points.

## The Apple side

`src-tauri/gen/apple` is the Xcode project Tauri generates: `project.yml`, `glyph_iOS/Info.plist`, a privacy manifest, and `Sources/glyph/main.mm`, whose `main` only calls `ffi::start_app()`. The iPhone runs the same page against the same commands, but with the engines left out, so voice, formatting, Notion, link previews and updates answer with their sentences. `docs/store/APP_STORE.md` says the iPhone app is not ready to submit: voice capture is the blocker, unless a first version ships with voice hidden. `platform.rs` makes its window key so the keyboard can rise, and `src-tauri/vendor/tao` carries a one-line backport without which a release build crashes at launch on iOS 26 and 27. The Mac is a desktop target of the same crate: whisper.cpp and llama.cpp are built for it, decorum sets the traffic lights into an overlay title bar, `library_reveal` opens the notes' folder in Finder, and `npm run desktop:build` makes the `.app` and a `.dmg`.

## Read next

- [[Over the air, and releases]]
- [[From microphone to Markdown]]
- [[The library on disk]]
