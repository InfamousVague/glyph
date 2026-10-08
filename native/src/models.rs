//! The app's half of a model download, shared by the two seams that have models: `capture` (whisper's live and
//! refine models) and `ai` (the formatting models). What `../glyph/src-tauri/src/model_downloads.rs` is to the
//! Tauri app, without Tauri.
//!
//! `model_files` (included as it is) owns the download itself: the mirrors tried in turn, the resume with a
//! `Range`, the SHA-256 that decides what is accepted. What it cannot know is here: where models live
//! (`<dataDir>/models`), how a download says how far it is (an event), and that two taps on "download" are one
//! download (a gate held for the whole of it).
//!
//! What differs from model_downloads.rs:
//!
//! - **A download is a long job** (work.rs): the command answers `{id}` and the job's `ok` is what the Tauri
//!   command resolved with. The job's thread drives the download on the shim's runtime (`tauri::async_runtime`).
//! - **The mirrors are an argument.** The Tauri app read the ones a signed update manifest had moved it to
//!   (`ota::services`), which this app has none of. A command's `mirrors` (a list of base URLs, each tried as
//!   `<mirror>/<file>`) is the WHOLE list when given, so a test names a server on 127.0.0.1 and no other host is
//!   ever asked; left out, it is the two the web app compiles in (attack.fm, then Hugging Face).
//!
//! The progress event keeps the payload each seam has always sent: `{receivedBytes, totalBytes}` for whisper's
//! models, and the same with the model's `id` first for the formatting models.

use std::path::{Path, PathBuf};
use std::sync::Mutex;

use serde::Serialize;

use crate::dispatch::Core;
use crate::model_files::{self, ModelSpec, ModelStatus};

/// `<dataDir>/models`: whisper's and the formatter's alike.
pub fn dir(core: &Core) -> PathBuf {
    core.data_dir().join(crate::paths::MODELS)
}

/// The progress event's payload, as the page read it.
#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct Progress {
    #[serde(skip_serializing_if = "Option::is_none")]
    id: Option<String>,
    received_bytes: u64,
    total_bytes: u64,
}

/// The mirrors to try: `given` alone when the command named any (trailing slashes trimmed, none twice), else
/// what `compiled` answers for no moved mirrors, which is the web app's own list.
pub fn mirrors(given: Option<Vec<String>>, compiled: impl FnOnce(&[String]) -> Vec<String>) -> Vec<String> {
    match given {
        Some(given) if given.iter().any(|mirror| !mirror.trim().is_empty()) => model_files::mirrors(&given, []),
        _ => compiled(&[]),
    }
}

/// Downloads `spec` into `dir` unless it is already there, emitting `event` as the bytes arrive, and answers its
/// status. Blocks the calling thread (a job's) for the whole download, holding `one_at_a_time`, so a second ask
/// waits for the first rather than writing the same `.part` beside it; having waited, it finds the file there.
pub fn fetch_reporting(dir: &Path, one_at_a_time: &Mutex<()>, spec: &ModelSpec, mirrors: &[String], event: &'static str, id: Option<&str>) -> Result<ModelStatus, String> {
    let _one_download = crate::lock::lock(one_at_a_time);
    let id = id.map(str::to_string);
    tauri::async_runtime::block_on(model_files::fetch(dir, spec, mirrors, move |received, total| {
        crate::events::emit(event, &Progress { id: id.clone(), received_bytes: received, total_bytes: total });
    }))
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use std::io::{Read, Seek, SeekFrom, Write};
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::Arc;

    #[test]
    fn the_progress_payload_is_the_one_each_seam_always_sent() {
        let whisper = Progress { id: None, received_bytes: 10, total_bytes: 60 };
        assert_eq!(serde_json::to_string(&whisper).unwrap(), r#"{"receivedBytes":10,"totalBytes":60}"#);
        let formatting = Progress { id: Some("qwen3.5-4b".into()), received_bytes: 10, total_bytes: 60 };
        assert_eq!(serde_json::to_string(&formatting).unwrap(), r#"{"id":"qwen3.5-4b","receivedBytes":10,"totalBytes":60}"#);
    }

    #[test]
    fn mirrors_given_are_the_whole_list_and_none_given_is_the_web_apps_two() {
        let local = mirrors(Some(vec!["http://127.0.0.1:9/models/".into(), "http://127.0.0.1:9/models".into()]), crate::whisper::model::mirrors_with);
        assert_eq!(local, ["http://127.0.0.1:9/models"], "no real mirror is appended to a list that was given");
        for none in [None, Some(Vec::new()), Some(vec![" ".to_string()])] {
            assert_eq!(mirrors(none, crate::whisper::model::mirrors_with), crate::whisper::model::MIRRORS.map(String::from).to_vec());
        }
    }

    /// A server on 127.0.0.1 for one file, which cuts the first connection after `cut` bytes of the body and
    /// honours `Range: bytes=n-` on those that follow. Answers its base URL and the requests it saw.
    pub(crate) fn serve_cutting(file: PathBuf, cut: usize) -> (String, Arc<Mutex<Vec<String>>>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = Arc::new(Mutex::new(Vec::new()));
        let log = Arc::clone(&seen);
        let served = Arc::new(AtomicUsize::new(0));
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut stream) = stream else { continue };
                let mut request = Vec::new();
                let mut byte = [0u8; 1];
                while !request.ends_with(b"\r\n\r\n") && stream.read(&mut byte).is_ok_and(|n| n == 1) {
                    request.push(byte[0]);
                }
                let request = String::from_utf8_lossy(&request).into_owned();
                let from: u64 = request.lines().find_map(|line| line.to_ascii_lowercase().strip_prefix("range: bytes=").and_then(|range| range.trim_end_matches('-').parse().ok())).unwrap_or(0);
                log.lock().unwrap().push(format!("{} from {from}", request.lines().next().unwrap_or("")));
                let Ok(mut source) = std::fs::File::open(&file) else {
                    let _ = stream.write_all(b"HTTP/1.1 404 Not Found\r\ncontent-length: 0\r\nconnection: close\r\n\r\n");
                    continue;
                };
                let total = source.metadata().unwrap().len();
                let head = if from > 0 {
                    format!("HTTP/1.1 206 Partial Content\r\ncontent-range: bytes {from}-{}/{total}\r\ncontent-length: {}\r\nconnection: close\r\n\r\n", total - 1, total - from)
                } else {
                    format!("HTTP/1.1 200 OK\r\ncontent-length: {total}\r\nconnection: close\r\n\r\n")
                };
                let first = served.fetch_add(1, Ordering::SeqCst) == 0;
                let mut left = if first { cut as u64 } else { total - from };
                source.seek(SeekFrom::Start(from)).unwrap();
                if stream.write_all(head.as_bytes()).is_err() {
                    continue;
                }
                let mut buffer = vec![0u8; 64 * 1024];
                while left > 0 {
                    let want = buffer.len().min(left as usize);
                    let Ok(read) = source.read(&mut buffer[..want]) else { break };
                    if read == 0 || stream.write_all(&buffer[..read]).is_err() {
                        break;
                    }
                    left -= read as u64;
                }
                // Dropping the stream closes it: for the first connection, in the middle of the body.
            }
        });
        (base, seen)
    }

    /// The real base.en from a local server that drops the first connection a third of the way in: the rest is
    /// asked for with a `Range`, the whole hashes right, and nothing but 127.0.0.1 is spoken to.
    #[test]
    fn a_download_cut_partway_is_picked_up_where_it_stopped_and_verifies() {
        let Some(models) = std::env::var_os("GLYPH_MODELS_DIR").map(PathBuf::from).filter(|dir| dir.is_dir()) else { return eprintln!("SKIPPED: GLYPH_MODELS_DIR is not a folder") };
        let spec = crate::whisper::model::ACTIVE;
        let source = models.join(spec.file);
        if !source.is_file() {
            return eprintln!("SKIPPED: no {}", source.display());
        }
        let cut = 20 * 1024 * 1024;
        let (base, seen) = serve_cutting(source.clone(), cut);
        let dir = crate::test_support::TempDir::new("models-resume");
        let gate = Mutex::new(());
        let began = std::time::Instant::now();
        let status = fetch_reporting(&dir, &gate, &spec, &mirrors(Some(vec![base]), crate::whisper::model::mirrors_with), "test://model-progress", Some("resume-test")).unwrap();
        eprintln!("base.en from 127.0.0.1 with one cut at {cut} bytes: {} ms, requests {:?}", began.elapsed().as_millis(), seen.lock().unwrap());
        assert!(status.present);
        assert_eq!(std::fs::metadata(&status.path).unwrap().len(), spec.bytes);
        assert!(!model_files::part_path(&dir, &spec).exists(), "the .part became the file");
        let seen = seen.lock().unwrap().clone();
        assert_eq!(seen.len(), 2, "{seen:?}");
        assert!(seen[0].ends_with("from 0"));
        let resumed: u64 = seen[1].rsplit(' ').next().unwrap().parse().unwrap();
        assert!(resumed > 0 && resumed <= cut as u64, "the second request asks for the rest, from where the first stopped: {seen:?}");
        let reports = crate::events::tests::heard(|event, payload| event == "test://model-progress" && payload["id"] == "resume-test");
        assert!(reports.len() > 10, "{} reports", reports.len());
        assert!(reports.windows(2).all(|pair| pair[0].1["receivedBytes"].as_u64() <= pair[1].1["receivedBytes"].as_u64()), "it never starts over");
        assert_eq!(reports.last().unwrap().1, serde_json::json!({ "id": "resume-test", "receivedBytes": spec.bytes, "totalBytes": spec.bytes }));
        // Asked again, it is there: no request at all.
        let again = fetch_reporting(&dir, &gate, &spec, &["http://127.0.0.1:9".to_string()], "test://model-progress", None).unwrap();
        assert!(again.present);
    }

    #[test]
    fn a_mirror_without_the_file_is_an_error_that_names_it_and_leaves_nothing() {
        let (base, _) = serve_cutting(PathBuf::from("/nowhere/at/all.bin"), 0);
        let dir = crate::test_support::TempDir::new("models-missing");
        let error = fetch_reporting(&dir, &Mutex::new(()), &crate::whisper::model::ACTIVE, &[base.clone()], "test://model-progress", None).unwrap_err();
        assert!(error.contains(&base) && error.contains("404"), "{error}");
        assert_eq!(std::fs::read_dir(&*dir).unwrap().count(), 0, "a refused download left a file behind");
    }
}
