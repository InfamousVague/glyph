// The native half of Ghost.md (Glyph in its ids). The webview owns everything
// a person sees; this crate owns what has to outlive it or reach past it: the
// notes on disk, transcription and formatting on the device, over-the-air
// updates, and the few calls a page cannot make for itself.

// Building blocks every other module shares, each written once. See each header.
// The poison-tolerant lock, Tauri-free so whisper/ and llm/ can use it.
mod lock;
// What the page's engine doors and the JNI write-up door must agree on: whether a
// capture runs, the one small.en at a time, the abort background jobs watch. iOS
// has no whisper, no llama and no recorder, so nothing there reaches most of it.
#[cfg_attr(target_os = "ios", allow(dead_code))]
mod guards;
// Whole-file writes, JSON with a fallback, removals where gone is done. Tauri-free too.
mod fsx;
// Where the app keeps things, and the six directory names Kotlin shares.
mod paths;
// What iOS does not have, and the one sentence each such command answers with there.
#[cfg_attr(not(target_os = "ios"), allow(dead_code))]
mod unsupported;
// What the tests share: a directory of a test's own, and a scheme answer's headers.
#[cfg(test)]
mod test_support;

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
// A recording's phrases as the paragraphs of its transcript, and the section they
// live in: the twin of the page's `toParagraphs`, for the write-up that runs with
// the app closed. Tauri-free, and in tools/host-tests.
pub mod transcript;
// The files a meeting's write-up is kept in under `jobs/`: its config, its
// progress, its result. Tauri-free, read by the commands and the JNI door alike.
pub mod jobs;

// The library opened where library-root.json says (the app's own folder, or one
// the person chose), for the launch, a move, the reset and the write-up alike.
// Tauri-free; outside library/ only because an Android folder is reached over JNI.
mod library_root;
// Rust's calls into Kotlin for a folder chosen on Android: the Storage Access
// Framework behind library/tree.rs's vault (native generation 25).
#[cfg(target_os = "android")]
mod saf;

// The webview's door to the notes: one library call per command, and the
// delete that takes a note's pictures and recording with it.
mod commands;
// The Library folder plugin's doors: where the library is, a folder picked and
// looked into, the move into it and back (native generation 25).
mod library_commands;
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
// The computer's own sound in a meeting (the Mac's process tap), mixed into the
// microphone's chunks as capture_push hands them over. See its header.
mod system_audio;

// Formatting on the phone: llama.cpp, a verified model download, and a
// streamed rewrite. Tauri-free like `whisper`; see llm/mod.rs's header.
pub mod llm;

// The webview's door to the formatting model: the catalogue, a download, a
// run, a cancel, and the progress events. See its header.
mod ai_commands;
// Notion from the phone: the signed-in account, and the API calls a page
// cannot make cross-origin. See its header.
mod notion;
// Slack from the phone: the channels' webhooks, kept where no page reads them,
// and the post a page cannot make cross-origin. See its header.
mod slack;
// A web page's title and summary for the card under a link, which the page
// cannot read cross-origin either.
mod link_preview;
// The name of the place a tagged note was written, asked of Nominatim as the
// app, since the page cannot name itself to it. See its header.
mod geocode;
// Links that open the app, ghostmd://, kept until the page takes them.
mod links;

// Pictures in notes: `save_image` adopts one the Android shell picked, the
// `img` scheme draws it, and a deleted note takes its pictures with it. See its
// header for why every name is checked before it touches a path.
mod images;

// Films in notes (native generation 21): `save_video` adopts one the Android
// shell picked, with its poster, the `vid` scheme plays it in ranges
// (`ranged`), and a film no note names goes. See its header for why a film
// never leaves the phone.
mod videos;
mod ranged;

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

// A meeting's write-up with the app closed: the recording finished, transcribed
// span by span, the transcript into the note, the summary from the model.
// Tauri-free, like the engines it drives; not on iOS, which has neither. Only
// the JNI door reaches it, so on the Mac it is built and tested and called by
// nothing, as `unsupported` is on the phone.
#[cfg(not(target_os = "ios"))]
#[cfg_attr(not(target_os = "android"), allow(dead_code))]
mod write_up;
// The webview's door to the write-ups and the tapes: the job config, the
// result, every job's state, a digest, a removal.
mod recording_commands;
// The JNI door the meeting service and its WorkManager job call: finish, run, cancel.
#[cfg(target_os = "android")]
mod recording_jobs;

// Everything the app keeps as one zip, on a USB drive or wherever a person chooses (native generation 22):
// export.rs writes it, export_commands.rs is the Mac's save panel and Android's picker.
mod export;
mod export_commands;
// A backup onto a removable drive, as plain files under Ghost.md/ (docs/DESIGN.md §204): backup.rs writes it,
// backup_commands.rs finds the Mac's drives and runs it; Android's drives are files/BackupDrives.kt's.
mod backup;
mod backup_commands;

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
        .register_uri_scheme_protocol(images::SCHEME, |ctx, request| images::serve(ctx.app_handle(), &request))
        // A film in a note, `[![video 0:12](image/<poster>)](video/<name>)`, for its card to play, a range at a time.
        .register_uri_scheme_protocol(videos::SCHEME, |ctx, request| videos::serve(ctx.app_handle(), &request));

    // decorum positions the native macOS traffic lights. There are none to
    // position on a phone, and the plugin is not built for those targets.
    #[cfg(desktop)]
    let builder = builder.plugin(tauri_plugin_decorum::init());
    // The Mac's save panel, for the export (export_commands.rs), and its folder panel, for the library's folder
    // (library_commands.rs). Asked from Rust only, so no page permission names it.
    #[cfg(desktop)]
    let builder = builder.plugin(tauri_plugin_dialog::init());

    builder
        .setup(|app| {
            // Before anything else a person can touch: the list screen asks
            // for notes on its first paint, and a command answering "no
            // managed state" reads to the page as an empty library.
            commands::install(app)?;
            // The folder picked for the library, held between the look and the move.
            library_commands::install(app);
            // No I/O and cannot fail: the model is looked for when the Record
            // screen asks, not at launch.
            capture_commands::install(app);
            // Nothing opened until a meeting asks for the computer's sound.
            system_audio::install(app);
            // Nothing loaded until a note asks to be formatted.
            ai_commands::install(app);
            // Before the page loads: the loader's first IPC call is the claim.
            ota::install(app);
            // After the plugin's own setup, which is what reads the link a launch came with.
            links::install(app);
            // Off the main thread, after the library: what waits in picked/ and the films no note names.
            videos::install(app);
            export_commands::install(app);
            backup_commands::install(app);

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
            commands::versions_read,
            commands::versions_write,
            commands::store_apply,
            commands::sync_put_file,
            commands::library_reveal,
            library_commands::library_root,
            library_commands::library_choose_folder,
            library_commands::library_inspect,
            library_commands::library_move,
            library_commands::library_use_app_folder,
            link_preview::link_preview,
            geocode::geocode_place,
            links::links_take,
            images::save_image,
            images::save_image_data,
            videos::save_video,
            videos::discard_picked,
            export_commands::export_save,
            export_commands::export_fd,
            export_commands::export_cancel,
            backup_commands::backup_drives,
            backup_commands::backup_last,
            backup_commands::backup_run,
            backup_commands::backup_cancel,
            backup_commands::backup_eject,
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
            system_audio::system_audio_available,
            system_audio::system_audio_start,
            system_audio::system_audio_status,
            system_audio::system_audio_stop,
            ai_commands::ai_device,
            notion::notion_save_account,
            notion::notion_account,
            notion::notion_disconnect,
            notion::notion_request,
            slack::slack_channels,
            slack::slack_save_channel,
            slack::slack_forget_channel,
            slack::slack_post,
            ai_commands::ai_models,
            ai_commands::ai_fetch_model,
            ai_commands::ai_delete_model,
            ai_commands::ai_generate,
            ai_commands::ai_infer_command,
            ai_commands::ai_cancel,
            ai_commands::ai_unload,
            recording_commands::ai_keep_job_config,
            recording_commands::recording_result_take,
            recording_commands::recording_job_state,
            recording_commands::recording_digest,
            recording_commands::recording_delete,
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
