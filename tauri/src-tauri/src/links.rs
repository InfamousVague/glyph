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

/// The links not yet taken. A lock poisoned by a panic elsewhere is recovered
/// (`crate::lock`), so a link that arrives afterwards is still kept and still
/// handed over; this used to skip the lock on poison, which dropped every later
/// link without a word.
#[derive(Default)]
pub struct Waiting(Mutex<Vec<String>>);

impl Waiting {
    fn add(&self, urls: Vec<String>) {
        crate::lock::lock(&self.0).extend(urls);
    }

    fn take(&self) -> Vec<String> {
        std::mem::take(&mut *crate::lock::lock(&self.0))
    }
}

fn keep<R: Runtime>(app: &tauri::AppHandle<R>, urls: Vec<String>) {
    if urls.is_empty() {
        return;
    }
    app.state::<Waiting>().add(urls);
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
    waiting.take()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn links_are_handed_over_once_even_after_a_panic_poisoned_the_lock() {
        let waiting = std::sync::Arc::new(Waiting::default());
        waiting.add(vec!["ghostmd://open#before".to_string()]);
        let holder = std::sync::Arc::clone(&waiting);
        let _ = std::thread::spawn(move || {
            let _guard = holder.0.lock().unwrap();
            panic!("a holder dies with the guard");
        })
        .join();
        assert!(waiting.0.is_poisoned(), "the setup has to poison it, or this proves nothing");
        waiting.add(vec!["ghostmd://open#after".to_string()]);
        assert_eq!(waiting.take(), ["ghostmd://open#before", "ghostmd://open#after"]);
        assert!(waiting.take().is_empty(), "taken once");
    }
}
