// The native half of Ghost.md (Glyph in its ids). The webview owns everything
// a person sees; this crate owns what has to outlive it or reach past it: the
// notes on disk, transcription and formatting on the device, over-the-air
// updates, and the few calls a page cannot make for itself.

// Building blocks every other module shares, each written once. See each header.
// The poison-tolerant lock, Tauri-free so whisper/ and llm/ can use it.
mod lock;
// Whole-file writes, JSON with a fallback, removals where gone is done. Tauri-free too.
mod fsx;
// Where the app keeps things, and the four directory names Kotlin shares.
mod paths;
// What iOS does not have, and the one sentence each such command answers with there.
#[cfg_attr(not(target_os = "ios"), allow(dead_code))]
mod unsupported;

// A note as the crate and the page share it. `pub`, and free of Tauri types,
// so a caller with no Tauri in its process could reach it over JNI - DESIGN
// 6.1's capture service, which did not ship in that form (capture runs in the
// page; DESIGN 13). The first such caller that DID ship is the update-alert
// worker, for `ota`, below. See note.rs's header.
pub mod note;
/// The notes as a folder of Markdown files, and the index over them (docs/LIBRARY.md).
pub mod library;
// The database the notes lived in before 1.3.0, read once to move them into the library.
pub mod store;

// The webview's door to the notes: one library call per command, and the
// delete that takes a note's pictures and recording with it.
mod commands;
// A spoken note's kept recording, and the `rec` scheme its tape plays through.
mod recordings;

// On-device transcription. `pub` and Tauri-free for the same reason as `note`,
// though today only the capture commands drive it. See whisper/mod.rs's header.
pub mod whisper;

// A model file, whichever engine reads it: its spec, whether it is here, and
// the verified, resumable download. Tauri-free, like the engines it serves.
pub mod model_files;

// The Tauri half of a model download, which both doors below share: where
// models live on this device, the progress event, one download at a time.
mod model_downloads;

// The webview's door to live dictation: the model download, a capture's
// start/push/stop, and the events that carry text back. See its header for the
// two ordering rules the page has to keep.
mod capture_commands;

// Formatting on the phone: llama.cpp, a verified model download, and a
// streamed rewrite. Tauri-free like `whisper`; see llm/mod.rs's header.
pub mod llm;

// The webview's door to the formatting model: the catalogue, a download, a
// run, a cancel, and the progress events. See its header.
mod ai_commands;
// Notion from the phone: the signed-in account, and the API calls a page
// cannot make cross-origin. See its header.
mod notion;
// A web page's title and summary for the card under a link, which the page
// cannot read cross-origin either.
mod link_preview;
// Links that open the app, ghostmd://, kept until the page takes them.
mod links;

// Pictures in notes: `save_image` adopts one the Android shell picked, the
// `img` scheme draws it, and a deleted note takes its pictures with it. See its
// header for why every name is checked before it touches a path.
mod images;

// Starting over, from developer settings: notes, recordings, pictures, and on
// request the models. See its header.
mod reset;

// Over-the-air updates: the `ota` scheme that serves a downloaded frontend, the
// boot wager that rolls a bad one back, and the APK download for native
// changes. See its header, and index.html for the loader that drives it.
mod ota;

// Update alerts: the JNI door a WorkManager job walks through with the app
// closed - the first code in Glyph that runs with no Tauri in the process.
#[cfg(target_os = "android")]
mod update_alerts;

// The window fixes one platform needs: iOS's key window, macOS's traffic lights.
mod platform;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let builder = tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        // The Taptic Engine: the web layer's HapticsProvider fires through
        // this on the phone instead of the (WKWebView-less) web fallbacks.
        .plugin(tauri_plugin_haptics::init())
        // ghostmd:// links (a shared note's "Open in the Ghost.md app"): links.rs keeps them for the page.
        .plugin(tauri_plugin_deep_link::init())
        // Registered on the builder, not in setup: a scheme has to exist before
        // the webview is created, and the webview is created before setup runs.
        .register_uri_scheme_protocol(ota::SCHEME, |ctx, request| ota::serve(ctx.app_handle(), &request))
        // A spoken note's kept recording, for its tape to play.
        .register_uri_scheme_protocol(recordings::SCHEME, |ctx, request| recordings::serve(ctx.app_handle(), &request))
        // A picture in a note, `![](image/<name>)`, for the editor to draw.
        .register_uri_scheme_protocol(images::SCHEME, |ctx, request| images::serve(ctx.app_handle(), &request));

    // decorum positions the native macOS traffic lights. There are none to
    // position on a phone, and the plugin is not built for those targets.
    #[cfg(desktop)]
    let builder = builder.plugin(tauri_plugin_decorum::init());

    builder
        .setup(|app| {
            // Before anything else a person can touch: the list screen asks
            // for notes on its first paint, and a command answering "no
            // managed state" reads to the page as an empty library.
            commands::install(app)?;
            // No I/O and cannot fail: the model is looked for when the Record
            // screen asks, not at launch.
            capture_commands::install(app);
            // Nothing loaded until a note asks to be formatted.
            ai_commands::install(app);
            // Before the page loads: the loader's first IPC call is the claim.
            ota::install(app);
            // After the plugin's own setup, which is what reads the link a launch came with.
            links::install(app);

            #[cfg(target_os = "ios")]
            platform::ensure_key_window(app.handle());
            #[cfg(target_os = "macos")]
            platform::place_traffic_lights(app);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_notes,
            commands::get_note,
            commands::create_note,
            commands::update_note,
            commands::apply_command_mutation,
            commands::undo_command_mutation,
            commands::latest_command_mutation,
            commands::delete_note,
            commands::set_note_starred,
            commands::set_note_archived,
            commands::set_note_recording,
            commands::set_note_formatted,
            commands::store_apply,
            commands::sync_put_file,
            commands::library_reveal,
            link_preview::link_preview,
            links::links_take,
            images::save_image,
            images::save_image_data,
            capture_commands::models::capture_model_status,
            capture_commands::models::capture_fetch_model,
            capture_commands::models::capture_refine_model_status,
            capture_commands::models::capture_fetch_refine_model,
            capture_commands::refine::capture_refine,
            capture_commands::capture_start,
            capture_commands::capture_push,
            capture_commands::capture_stop,
            capture_commands::capture_reassign_recording,
            capture_commands::capture_discard_recording,
            capture_commands::capture_cancel,
            capture_commands::capture_rewind,
            capture_commands::transcribe_wav,
            ai_commands::ai_device,
            notion::notion_save_account,
            notion::notion_account,
            notion::notion_disconnect,
            notion::notion_request,
            ai_commands::ai_models,
            ai_commands::ai_fetch_model,
            ai_commands::ai_delete_model,
            ai_commands::ai_generate,
            ai_commands::ai_infer_command,
            ai_commands::ai_cancel,
            reset::reset_local_data,
            ota::ota_claim_boot,
            ota::ota_boot_ok,
            ota::ota_boot_failed,
            ota::ota_status,
            ota::ota_check,
            ota::ota_revert,
            ota::ota_fetch_apk,
        ])
        .build(tauri::generate_context!())
        .expect("error while building tauri application")
        // `build` + `run` rather than `run` alone for one event: a capture
        // still decoding when the app quits is cancelled and joined before
        // whisper.cpp's static destructors run. See capture_commands::shutdown.
        .run(|app, event| {
            if let tauri::RunEvent::Exit = event {
                capture_commands::shutdown(app);
                ai_commands::shutdown(app);
            }
        });
}
