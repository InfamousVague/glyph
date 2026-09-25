//! Over-the-air updates: the web layer swapped without a new APK, and the
//! download half of installing one when the native layer changes.
//!
//! WHY THIS EXISTS. Glyph is sideloaded, so every change used to mean a 43 MB
//! APK, a browser download and an install prompt. Almost every change is to
//! the page, not the binary - so the binary now ships a frontend (the
//! "embedded" one, compiled in by `generate_context!`) and can also run a newer
//! one it downloaded, verified, and keeps under `<app_data_dir>/ota/`.
//!
//! HOW A DOWNLOADED FRONTEND REACHES THE WEBVIEW. Through a custom URI scheme,
//! `ota`, that serves the claimed bundle's files by their real relative paths:
//! `http://ota.localhost/assets/index-abc.js` on Android, `ota://localhost/...`
//! on Apple platforms. AttackFM does this with Tauri's `asset:` protocol
//! instead, and that protocol percent-encodes the whole file path into ONE URL
//! segment - so a relative `./chunk.js` or a CSS `url(./font.woff2)` resolves
//! to the protocol's root and 404s, and every AttackFM OTA build has to inline
//! every chunk, font and image into two fixed-name files. With real paths the
//! OTA bundle is simply `dist/`: the same build the website serves, hashed
//! names and all, and a font that did not change is not downloaded again.
//!
//! The document itself never moves. `index.html` is always the embedded one,
//! at the app's own origin, and its inline loader (see index.html) asks
//! `ota_claim_boot` what to run and adds the chosen bundle's module script and
//! stylesheets. The page's origin - and so its localStorage, its IPC access,
//! and the microphone permission - is the same whichever frontend runs.
//!
//! THE BOOT WAGER, and the part AttackFM learned the hard way (its comments
//! record five OTA versions lost to races around exactly this):
//!
//!  1. `ota_claim_boot` is the ONE call that changes state at launch. It stakes
//!     the bundle it hands out as `pending`, under a process-wide lock.
//!  2. The frontend that actually mounts calls `ota_boot_ok` with the build it
//!     is (or `None` for the embedded one). A matching build clears the stake.
//!     `None` clears it too, WITHOUT counting as a failure: the embedded
//!     frontend mounting means the loader fell back (a slow IPC answer, a
//!     timeout) and the bundle was never actually tried, which is not evidence
//!     against it. AttackFM's version left the stake standing in that case and
//!     quarantined good bundles.
//!  3. A stake still standing at the NEXT claim means a launch ran that bundle
//!     and never mounted. That is a strike; two strikes quarantine the build
//!     for good and fall back to the previous bundle, or to the embedded one.
//!     One strike is not enough because the phone killing the app in its first
//!     second is ordinary.
//!  4. `ota_boot_failed` is the loader's same-launch escape hatch: a bundle
//!     whose script or stylesheet will not load, or that has not mounted within
//!     its deadline, is quarantined at once and the embedded frontend mounts
//!     in the same launch. Nobody waits for a second bad start.
//!
//! NATIVE GENERATIONS. A bundle can only run on a binary that has the commands
//! it calls. `NATIVE_GENERATION` is what this binary provides; `BUNDLE_REQUIRES`
//! is what the page built from this tree needs, and it is the one stamped into
//! `ota.json` (vite.config.ts reads it out of this file). Bump both when the
//! page starts depending on a new command - and never stamp
//! `NATIVE_GENERATION`, which is how AttackFM once locked every older binary
//! out of every future update. A manifest needing more than this binary has is
//! reported as `needs-native`, which is the page's cue to offer the new APK.
//!
//! TRUST IS A KEY, NOT A DOMAIN. `ota.json` and `apk.json` are Ed25519-signed
//! (detached `.sig` files, scheme in scripts/ota-sign.mjs) and accepted only
//! if a key in src-tauri/ota-trusted-keys.txt signed them; every bundle file is
//! then checked against the manifest's SHA-256. So any host may serve updates,
//! an HTTP redirect cannot inject one, and a domain that lapses and changes
//! hands can stop updates but cannot ship code into the app.
//!
//! WHERE UPDATES COME FROM, and how that moves. The APK compiles in
//! src-tauri/ota-sources.txt. A verified manifest may carry `sources` (and
//! `services`, the other endpoints the app reaches); the app remembers the
//! newest such list and tries it first, the compiled list after. Publishing a
//! manifest that names a new domain is therefore how installed apps follow
//! Glyph to one - no new APK - and an older signed manifest can never roll the
//! list back. README "Moving to another domain" is the procedure.
//!
//! WHERE EACH PART LIVES. This file is the seam: the two generation numbers
//! (which two scripts read out of it by path, so they stay here as literals),
//! the compile-time switches and trust roots, the managed state, and the seven
//! commands the page calls, which hold the locks and hand the work to these:
//!
//! - `ota/manifest.rs`: what `ota.json` and `apk.json` say, and the rules every
//!   build id, path and URL in them keeps.
//! - `ota/sources.rs`: where updates come from, and how that moves.
//! - `ota/disk.rs`: `state.json`, `installed.json` and the bundle directories.
//! - `ota/boot.rs`: the boot wager, as decisions over `state.json`.
//! - `ota/scheme.rs`: the `ota` scheme that serves the claimed bundle.
//! - `ota/fetch.rs`, `ota/install.rs`, `ota/apk.rs`: the signed fetch, the
//!   bundle install and the APK download - none of them on iOS, which builds
//!   no reqwest (see `unsupported`).

use std::path::PathBuf;
use std::sync::Mutex;

use serde::Serialize;
use tauri::{AppHandle, Manager, Runtime, State};

// A poisoned lock is recovered (`crate::lock`): every write below is a whole
// file, so a panic mid-command leaves either the old state or the new one,
// never half.
use crate::fsx;
use crate::lock::lock;

#[cfg(target_os = "ios")]
use crate::unsupported::{on_ios, APK, UPDATES};

use manifest::{build_number, ApkInfo, Manifest, Services};

mod boot;
mod disk;
mod manifest;
mod scheme;
mod sources;

#[cfg(not(target_os = "ios"))]
mod apk;
#[cfg(not(target_os = "ios"))]
mod fetch;
#[cfg(not(target_os = "ios"))]
mod install;

#[cfg(test)]
mod test_support;

pub use scheme::{serve, SCHEME};
#[cfg(not(target_os = "ios"))]
pub use sources::services;

/// For the background update check (update_alerts.rs), the one caller with no
/// Tauri in its process.
#[cfg(target_os = "android")]
pub use install::peek;

/// What this binary provides to a bundle. See the module header.
///
/// 2: signed manifests, remembered sources and services (0.3.0). A page may
/// read `sources`/`services` from `ota_status` but must treat them as optional
/// until BUNDLE_REQUIRES says 2. apk.json carries this number, which is how a
/// generation-1 app knows to offer the APK.
///
/// 3: `set_note_starred` / `set_note_archived`, the update-alert bridge (0.3.2).
/// The page feature-detects this through `ota_status` and hides swipe-to-star
/// and archive on older binaries rather than calling commands they lack.
///
/// 4: the on-device model (`ai_*`), `set_note_formatted` / `set_note_project`,
/// and `capture_rewind` (0.4.0). The Formatted view and the cassette's rewind
/// only appear where `ota_status` reports 4; on 3 the tape still pauses.
///
/// 5: handwriting - `GlyphHost.inkPrepare` / `inkRecognize` in the Android
/// shell, ML Kit digital ink (0.5.0). Removed again in 0.5.2 at Matt's call; the
/// number stays, because a generation never goes backwards, and no page reads
/// the ink bridge any more.
///
/// 6: the on-device model is REMOVED - no `ai_*`, no `set_note_formatted` /
/// `set_note_project` - along with projects and suggestions (0.6.0). A bump for
/// a removal, not an addition, so apk.json tells generation-4 and -5 phones
/// that a new APK exists. A page from before it cannot run on this binary
/// anyway: `ota_claim_boot` only keeps a stored bundle newer than the embedded
/// frontend, and this APK's embedded frontend is newer than any 0.5.x bundle.
///
/// 7: `capture_refine`, `capture_refine_model_status` and
/// `capture_fetch_refine_model` - a saved recording transcribed again with
/// small.en after Done (0.6.0).
///
/// 8: `save_image` and the `img` scheme - pictures in notes, adopted from the
/// shell's picker and drawn from `http://img.localhost/<name>` - and
/// `delete_note` removing the pictures a note took with it (0.7.0).
///
/// 9: `save_image_data` - a pasted picture, shrunk by the page and sent as
/// base64, kept only if its bytes are a JPEG, PNG or WebP (0.8.0).
///
/// 10: the on-device formatter is back - `ai_models`, `ai_fetch_model`,
/// `ai_delete_model`, `ai_generate`, `ai_cancel` - and the back gesture handed
/// to the page (0.9.0).
///
/// 11: `ai_device` (memory, cores, chip, free disk), `reset_local_data`, and
/// the hinge angle for the unfold (0.9.1).
///
/// 12: `GlyphHost.setCapturing` - the screen kept on while recording, and
/// `window.__glyph.screenOff` when it goes off anyway, which is the side key
/// pressed to stop - Notion: `notion_save_account`, `notion_account`,
/// `notion_disconnect`, `notion_request` - and `GlyphHost.readClipboard` for
/// the editor's Paste (1.0.0).
///
/// 13: `ai_generate` takes `think`, which leaves a reasoning model's thinking
/// on and streams it ahead of the answer, flagged `thinking` on progress and
/// output - for the review after a recording (1.1.0).
///
/// 14: `hardware` on the model's progress - memory, process CPU, cores, the
/// hottest readable thermal zone - for the AI card (1.2.0).
///
/// 15: notes are a library of Markdown files (library/, docs/LIBRARY.md) in the
/// app's storage, moved in from the old database on first launch; every note
/// carries its `path` (1.3.0).
///
/// 16: `store_apply`, a note written as another device has it, and
/// `sync_put_file`, a synced recording or picture, for sync (docs/SYNC.md).
///
/// 17: `link_preview`, a web page's title for the card under a link.
///
/// 18: the notes' folder shown where the device shows folders: `library_reveal` opens it in Finder, and on Android
/// the activity's `browseFiles` opens it in the Files app, where files/LibraryDocuments.kt lists it (1.7.2).
///
/// 19: revision-checked note create and update (`create_note`, `update_note`), guarded command mutation and its
/// undo (`apply_command_mutation`, `undo_command_mutation`, `latest_command_mutation`), and constrained on-device
/// instruction inference (`ai_infer_command`), for voice commands read from a finished recording.
pub const NATIVE_GENERATION: u32 = 19;

/// What the page built from THIS tree needs. vite.config.ts reads this line
/// with a regex and stamps it into `ota.json`, so keep it a literal. Nothing in
/// Rust reads it but the test that keeps it at or under `NATIVE_GENERATION`.
#[allow(dead_code)]
pub const BUNDLE_REQUIRES: u32 = 19;

/// The public keys a manifest must be signed by (any one of them). Compiled in:
/// trust belongs to whoever holds a private key, never to whichever domain
/// happens to answer. See scripts/ota-sign.mjs for the scheme and the keys.
#[cfg(not(target_os = "ios"))]
const TRUSTED_KEYS: &str = include_str!("../ota-trusted-keys.txt");

/// Where this APK looks for updates when it knows no better, most preferred
/// first. A verified manifest's `sources` list is remembered and tried before
/// these - that is how installs follow Glyph to a new domain. The same file
/// deploy-ota.mjs stamps into the manifest; see its header.
const COMPILED_SOURCES: &str = include_str!("../ota-sources.txt");

/// `GLYPH_OTA_BASE` at COMPILE time replaces the compiled sources with one test
/// server - an emulator reaching the host at `http://10.0.2.2:8787`, say - and
/// is the only thing that permits plain http. A compile-time switch on purpose:
/// a runtime one would let anything that can write the app's storage choose
/// where its code comes from. (Signatures would still refuse a foreign bundle,
/// but a test knob has no business in a shipped binary's attack surface.)
const TEST_SOURCE: Option<&str> = option_env!("GLYPH_OTA_BASE");

/// `GLYPH_STAGING` at COMPILE time (the same switch build.gradle.kts reads):
/// a staging build runs beside the real app under its own id and never checks
/// for updates, so the page it was built with is the page that runs.
#[cfg_attr(target_os = "ios", allow(dead_code))]
pub const STAGING: bool = option_env!("GLYPH_STAGING").is_some();

/// `GLYPH_STORE` at COMPILE time: "play" or "appstore" for a build that goes
/// through a store (docs/store/). A store installs and updates the app itself,
/// and Google Play forbids an app updating itself any other way, so a store
/// build never looks for, fetches or offers an APK. The web bundle still
/// updates over the air: that is JavaScript run in the WebView, which both
/// stores allow, and it can't change what the app is for. Compile-time for the
/// same reason as the test source: nothing that can write the app's storage
/// should be able to turn installing apps back on.
pub const STORE: Option<&str> = option_env!("GLYPH_STORE");

// ---- what the page is answered with (src/app/core/ota.ts mirrors these) ----------

/// What the loader needs to run a bundle, or `bundle: None` for the embedded frontend.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BootState {
    pub bundle: Option<BootBundle>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct BootBundle {
    pub build: String,
    pub version: String,
    /// Absolute URL prefix the entry and styles are relative to.
    pub base: String,
    pub entry: String,
    pub styles: Vec<String>,
}

/// Everything Settings shows about versions.
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Status {
    pub native_version: String,
    pub native_generation: u32,
    pub embedded_build: Option<String>,
    pub embedded_version: Option<String>,
    pub active_build: Option<String>,
    pub active_version: Option<String>,
    /// The build this process is serving right now, which lags `active` until a reload.
    pub running_build: Option<String>,
    pub quarantined: Vec<String>,
    /// Where updates are looked for, in the order they are tried.
    pub sources: Vec<String>,
    pub services: Services,
    /// The store this build came from ("play", "appstore"), or none for a download from attack.fm (`STORE`).
    pub store: Option<&'static str>,
}

/// The answer to "is there anything new?"
#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CheckResult {
    /// `current`, `installed` (reload to run it), `needs-native`, `quarantined`, or `offline`.
    pub web: &'static str,
    pub web_build: Option<String>,
    pub web_version: Option<String>,
    pub apk: Option<ApkInfo>,
    /// Why the web half could not be checked, when `web` is `offline`.
    pub error: Option<String>,
    /// The source that answered with a verified manifest.
    pub source: Option<String>,
}

// ---- managed state ----------------------------------------------------------------

/// What the OTA system holds for the life of the process.
pub struct OtaState {
    /// Around every read-modify-write of `state.json`.
    lock: Mutex<()>,
    /// The bundle directory the `ota` scheme serves. Set by each claim and by
    /// nothing else, so a bundle installed mid-run is not served until the page
    /// reloads and claims it - half an old frontend and half a new one is the
    /// failure this prevents.
    serving: Mutex<Option<(String, PathBuf)>>,
    /// One install at a time; a check that finds one running waits for it.
    #[cfg(not(target_os = "ios"))]
    installing: tauri::async_runtime::Mutex<()>,
    /// The embedded manifest, read once.
    embedded: Mutex<Option<Option<Manifest>>>,
}

impl OtaState {
    fn new() -> OtaState {
        OtaState {
            lock: Mutex::new(()),
            serving: Mutex::new(None),
            #[cfg(not(target_os = "ios"))]
            installing: tauri::async_runtime::Mutex::new(()),
            embedded: Mutex::new(None),
        }
    }
}

/// Hands the OTA state to Tauri. Called from `setup`, before the page loads:
/// the loader's first IPC call is the claim.
pub fn install<R: Runtime>(app: &tauri::App<R>) {
    app.manage(OtaState::new());
}

/// `<app_data_dir>/ota`, made if it is not there yet.
fn root<R: Runtime>(app: &AppHandle<R>) -> Result<PathBuf, String> {
    let dir = crate::paths::ota_dir(app)?;
    fsx::make_dir(&dir)?;
    Ok(dir)
}

// ---- commands -----------------------------------------------------------------

/// Decide what this launch runs, and stake it (`boot::claim`). Called once per
/// page load, by the loader in index.html and by nothing else.
#[tauri::command]
pub fn ota_claim_boot<R: Runtime>(app: AppHandle<R>, state: State<'_, OtaState>) -> BootState {
    let embedded = boot::embedded_manifest(&app, &state);
    let Ok(root) = root(&app) else {
        *lock(&state.serving) = None;
        return BootState { bundle: None };
    };
    let _guard = lock(&state.lock);
    let mut stored = disk::read_stored(&root);
    let before = serde_json::to_string(&stored).unwrap_or_default();

    let boot = match boot::claim(&root, &mut stored, embedded.as_ref()) {
        Some((manifest, dir)) => {
            *lock(&state.serving) = Some((manifest.build.clone(), dir));
            BootState {
                bundle: Some(BootBundle {
                    base: scheme::scheme_base(),
                    build: manifest.build,
                    version: manifest.version,
                    entry: manifest.entry,
                    styles: manifest.styles,
                }),
            }
        }
        None => {
            *lock(&state.serving) = None;
            BootState { bundle: None }
        }
    };

    if serde_json::to_string(&stored).unwrap_or_default() != before {
        // A state that cannot be written is a stake that will not be there
        // next launch: the bundle runs unwagered, which is the lesser failure.
        let _ = disk::write_stored(&root, &stored);
    }
    boot
}

/// The frontend that mounted reports in (`boot::settle`). `None` is the embedded frontend.
#[tauri::command]
pub fn ota_boot_ok<R: Runtime>(app: AppHandle<R>, state: State<'_, OtaState>, build: Option<String>) -> Result<(), String> {
    let root = root(&app)?;
    let _guard = lock(&state.lock);
    let mut stored = disk::read_stored(&root);
    if !boot::settle(&mut stored, build.as_deref()) {
        return Ok(());
    }
    disk::write_stored(&root, &stored)
}

/// The loader's same-launch verdict: this bundle would not load or mount.
#[tauri::command]
pub fn ota_boot_failed<R: Runtime>(app: AppHandle<R>, state: State<'_, OtaState>, build: String, reason: String) -> Result<(), String> {
    build_number(&build).ok_or("bad build id")?;
    // The page logs the reason to the console, which is what reaches logcat.
    let _ = reason;
    let root = root(&app)?;
    let _guard = lock(&state.lock);
    let mut stored = disk::read_stored(&root);
    boot::quarantine(&root, &mut stored, &build);
    *lock(&state.serving) = None;
    disk::write_stored(&root, &stored)
}

/// Everything Settings shows about versions (`Status`).
#[tauri::command]
pub fn ota_status<R: Runtime>(app: AppHandle<R>, state: State<'_, OtaState>) -> Status {
    let embedded = boot::embedded_manifest(&app, &state);
    let stored = root(&app).map(|r| disk::read_stored(&r)).unwrap_or_default();
    let known = root(&app).map(|r| sources::read_known(&r)).unwrap_or_default();
    let active_version = root(&app)
        .ok()
        .zip(stored.active.as_ref())
        .and_then(|(r, a)| disk::bundle_manifest(&r.join(a)))
        .map(|m| m.version);
    Status {
        native_version: app.package_info().version.to_string(),
        native_generation: NATIVE_GENERATION,
        embedded_build: embedded.as_ref().map(|m| m.build.clone()),
        embedded_version: embedded.map(|m| m.version),
        active_build: stored.active,
        active_version,
        running_build: lock(&state.serving).as_ref().map(|(build, _)| build.clone()),
        quarantined: stored.quarantined,
        sources: sources::effective_sources(&known),
        services: known.services,
        store: STORE,
    }
}

/// Look for a newer web bundle and install it; report the published APK alongside.
///
/// Installing does not run the bundle. It lands in `active`, and the next page
/// load claims it - the page offers a reload when the person is somewhere a
/// reload costs nothing, and a cold start picks it up regardless.
#[tauri::command]
pub async fn ota_check<R: Runtime>(app: AppHandle<R>, state: State<'_, OtaState>) -> Result<CheckResult, String> {
    #[cfg(target_os = "ios")]
    return on_ios(UPDATES, (app, state));
    #[cfg(not(target_os = "ios"))]
    {
        install::check(&app, &state).await
    }
}

/// Forget every downloaded bundle; the next load runs the embedded frontend.
/// No page calls it: it is the hand-run way back from a devtools console.
#[tauri::command]
pub fn ota_revert<R: Runtime>(app: AppHandle<R>, state: State<'_, OtaState>) -> Result<(), String> {
    let root = root(&app)?;
    let _guard = lock(&state.lock);
    let mut stored = disk::read_stored(&root);
    boot::revert(&root, &mut stored);
    disk::write_stored(&root, &stored)
}

/// Download the published APK into the cache directory the FileProvider
/// exposes, verified, and answer with its path for `GlyphHost.installApk`.
///
/// Rust does the download rather than the page because the page cannot: a
/// `fetch` from the app's origin to attack.fm needs CORS headers Caddy's file
/// server does not send, and 43 MB through IPC as base64 would be absurd
/// anyway. Progress arrives as `ota://apk-progress`.
#[tauri::command]
pub async fn ota_fetch_apk<R: Runtime>(app: AppHandle<R>, state: State<'_, OtaState>) -> Result<String, String> {
    #[cfg(target_os = "ios")]
    return on_ios(APK, (app, state));
    #[cfg(not(target_os = "ios"))]
    {
        apk::fetch(&app, &state).await
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A tree whose page needs more than its own binary provides would publish
    /// bundles that no install of that binary could ever run. Checked at compile
    /// time: the constants are constants, so the build itself fails.
    #[test]
    fn the_page_never_needs_more_than_this_binary_provides() {
        const { assert!(BUNDLE_REQUIRES <= NATIVE_GENERATION) };
    }
}
