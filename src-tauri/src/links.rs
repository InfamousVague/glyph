//! Links that open the app: `ghostmd://…`, the reader page's "Open in the Ghost.md app" (src/read/Reader.tsx), which
//! carries a share's `id.key` after its `#`. tauri-plugin-deep-link hands them over - at launch for a link that
//! started the app, or as an event while it runs - and they wait here until the page asks for them, since a link
//! that starts the app arrives before any page is listening. The page takes them with `links_take` when it has
//! read its notes, and again whenever `glyph://link` says another arrived (App.tsx). What a link means is the page's
//! to decide: here it is only kept, as text.

use std::sync::Mutex;
use tauri::{Emitter, Manager, Runtime, State};
use tauri_plugin_deep_link::DeepLinkExt;

/// The event that says a link is waiting.
const ARRIVED: &str = "glyph://link";

#[derive(Default)]
pub struct Waiting(Mutex<Vec<String>>);

fn keep<R: Runtime>(app: &tauri::AppHandle<R>, urls: Vec<String>) {
    if urls.is_empty() {
        return;
    }
    if let Ok(mut waiting) = app.state::<Waiting>().0.lock() {
        waiting.extend(urls);
    }
    let _ = app.emit(ARRIVED, ());
}

/// Keeps the link that started the app, and every one that arrives while it runs.
pub fn install<R: Runtime>(app: &tauri::App<R>) {
    app.manage(Waiting::default());
    let handle = app.handle().clone();
    if let Ok(Some(urls)) = app.deep_link().get_current() {
        keep(&handle, urls.into_iter().map(|url| url.to_string()).collect());
    }
    let later = handle.clone();
    app.deep_link().on_open_url(move |event| keep(&later, event.urls().into_iter().map(|url| url.to_string()).collect()));
}

/// The links waiting, handed over once: a link opens the app's copy of it once, however often the page asks.
#[tauri::command]
pub fn links_take(waiting: State<'_, Waiting>) -> Vec<String> {
    waiting.0.lock().map(|mut kept| std::mem::take(&mut *kept)).unwrap_or_default()
}
