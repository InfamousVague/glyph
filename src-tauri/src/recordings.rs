//! A spoken note's kept recording: `<app_data_dir>/recordings/<id>.wav`, the
//! one rule for which ids may name one, how one that arrived by sync is kept,
//! and the `rec` scheme its tape plays through.
//!
//! The capture seam writes a take here (`capture_stop`) and moves one to the
//! note it turned out to belong to (`capture_reassign_recording`); sync keeps
//! another device's (`sync_put_file`); a deleted note takes its recording with
//! it (`delete_note`). Those used to re-derive the folder and the name rule
//! each for themselves, so renaming either in one place would have left a tape
//! unplayable; they all ask here now.

use std::path::{Path, PathBuf};

use tauri::http::{header, Response, StatusCode};
use tauri::{AppHandle, Runtime};

/// The scheme a kept recording is played through: `http://rec.localhost/<id>.wav`
/// on Android, `rec://localhost/<id>.wav` elsewhere - the same shape as `ota`.
pub const SCHEME: &str = "rec";

/// Where note `id`'s recording lives inside `recordings`, or `None` for an id
/// that is not a plain name. Ids reach this from the page, and one that is not
/// letters, digits, `-` and `_` - a `../`, a slash - must never become a path
/// to write or delete. The rule is `fsx::plain_id`, the same one a note's
/// sidecar and a picture's name obey.
pub fn recording_file(recordings: &Path, id: &str) -> Option<PathBuf> {
    crate::fsx::plain_id(id).then(|| recordings.join(format!("{id}.wav")))
}

/// Keeps a recording that arrived by sync under the note's id: base64 of a
/// WAV file, written whole or not at all into `recordings` (made if it is not
/// there). Refuses an id that may not name a file and bytes that are not a
/// RIFF file, before anything is written.
pub fn place(recordings: &Path, id: &str, base64: &str) -> Result<(), String> {
    use base64::Engine as _;
    let file = recording_file(recordings, id).ok_or_else(|| "That is not a note id.".to_string())?;
    let bytes = base64::engine::general_purpose::STANDARD.decode(base64.trim()).map_err(|_| "That recording could not be read.".to_string())?;
    if !bytes.starts_with(b"RIFF") {
        return Err("That is not a recording Glyph can keep.".to_string());
    }
    std::fs::create_dir_all(recordings).map_err(|e| e.to_string())?;
    crate::fsx::write_atomically(&file, &bytes).map_err(|e| format!("The recording could not be saved: {e}"))
}

/// Serves `<app_data_dir>/recordings/<id>.wav` to the page's `<audio>`, with
/// byte ranges, because a WebView's media element seeks by asking for them and
/// treats a server without `Accept-Ranges` as unseekable. The id is confined
/// by `recording_file`.
pub fn serve<R: Runtime>(app: &AppHandle<R>, request: &tauri::http::Request<Vec<u8>>) -> Response<Vec<u8>> {
    let path = request.uri().path().trim_start_matches('/');
    let bytes = path
        .strip_suffix(".wav")
        .and_then(|id| crate::paths::recordings_dir(app).ok().and_then(|dir| recording_file(&dir, id)))
        .and_then(|file| std::fs::read(file).ok());
    let range = request.headers().get(header::RANGE).and_then(|v| v.to_str().ok());
    answer(bytes, range)
}

/// The response to a request for a recording whose file held `bytes` (or none
/// was found), with the request's `Range` header if it sent one.
fn answer(bytes: Option<Vec<u8>>, range: Option<&str>) -> Response<Vec<u8>> {
    let respond = |status: StatusCode, body: Vec<u8>, extra: Vec<(header::HeaderName, String)>| {
        let mut builder = Response::builder()
            .status(status)
            .header(header::CONTENT_TYPE, "audio/wav")
            .header(header::ACCESS_CONTROL_ALLOW_ORIGIN, "*")
            .header(header::ACCEPT_RANGES, "bytes")
            .header(header::CACHE_CONTROL, "no-store");
        for (name, value) in extra {
            builder = builder.header(name, value);
        }
        builder.body(body).unwrap_or_else(|_| Response::new(Vec::new()))
    };
    let Some(bytes) = bytes else {
        return respond(StatusCode::NOT_FOUND, Vec::new(), Vec::new());
    };
    let total = bytes.len();
    match range.and_then(|range| byte_range(range, total)) {
        Some((start, end)) => respond(
            StatusCode::PARTIAL_CONTENT,
            bytes[start..=end].to_vec(),
            vec![(header::CONTENT_RANGE, format!("bytes {start}-{end}/{total}")), (header::CONTENT_LENGTH, (end - start + 1).to_string())],
        ),
        None => respond(StatusCode::OK, bytes, vec![(header::CONTENT_LENGTH, total.to_string())]),
    }
}

/// The inclusive byte range a `Range` header asks for within `total` bytes:
/// `bytes=<start>-<end>`, or `bytes=<start>-` for the rest. Anything else - a
/// suffix range, several ranges, an end past the file - is answered with the
/// whole file instead, which a media element accepts as well.
fn byte_range(header: &str, total: usize) -> Option<(usize, usize)> {
    let (a, b) = header.strip_prefix("bytes=")?.split_once('-')?;
    let start: usize = a.parse().ok()?;
    let end: usize = if b.is_empty() { total.saturating_sub(1) } else { b.parse().ok()? };
    (start <= end && end < total).then_some((start, end))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp() -> PathBuf {
        let dir = std::env::temp_dir().join(format!("glyph-recordings-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn header_of(response: &Response<Vec<u8>>, name: header::HeaderName) -> Option<&str> {
        response.headers().get(name).and_then(|value| value.to_str().ok())
    }

    #[test]
    fn a_recording_path_is_only_ever_inside_the_recordings_directory() {
        let dir = Path::new("/data/recordings");
        assert_eq!(recording_file(dir, "0f8e-uuid_1"), Some(dir.join("0f8e-uuid_1.wav")));
        for id in ["", "../notes", "a/b", "a\\b", "..", "n1.wav", "a b"] {
            assert_eq!(recording_file(dir, id), None, "{id:?}");
        }
    }

    #[test]
    fn a_synced_recording_is_kept_whole_under_the_notes_id() {
        use base64::Engine as _;
        let root = temp();
        let dir = root.join("recordings");
        let wav = b"RIFF\x24\0\0\0WAVEfmt ".to_vec();
        place(&dir, "n1", &base64::engine::general_purpose::STANDARD.encode(&wav)).unwrap();
        assert_eq!(std::fs::read(dir.join("n1.wav")).unwrap(), wav, "the folder is made, and the bytes kept exactly");
        let names: Vec<_> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name()).collect();
        assert_eq!(names, ["n1.wav"], "nothing left beside it");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_synced_recording_that_is_not_one_is_refused_before_anything_is_written() {
        use base64::Engine as _;
        let root = temp();
        let dir = root.join("recordings");
        let wav = base64::engine::general_purpose::STANDARD.encode(b"RIFF\x24\0\0\0WAVEfmt ");
        assert_eq!(place(&dir, "../n1", &wav), Err("That is not a note id.".to_string()));
        assert_eq!(place(&dir, "n1", "not base64!"), Err("That recording could not be read.".to_string()));
        let png = base64::engine::general_purpose::STANDARD.encode(b"\x89PNG\r\n\x1a\n");
        assert_eq!(place(&dir, "n1", &png), Err("That is not a recording Glyph can keep.".to_string()));
        assert!(!dir.exists(), "a refusal writes nothing, not even the folder");
        let _ = std::fs::remove_dir_all(&root);
    }

    #[test]
    fn a_range_is_the_bytes_asked_for_or_the_whole_file() {
        assert_eq!(byte_range("bytes=0-99", 1000), Some((0, 99)));
        assert_eq!(byte_range("bytes=900-", 1000), Some((900, 999)), "an open end is the rest of the file");
        assert_eq!(byte_range("bytes=999-999", 1000), Some((999, 999)));
        for header in ["bytes=-500", "bytes=5-2", "bytes=0-1000", "bytes=1000-", "bytes=0-1,5-9", "items=0-1", "bytes=a-b"] {
            assert_eq!(byte_range(header, 1000), None, "{header}");
        }
        assert_eq!(byte_range("bytes=0-", 0), None, "an empty file has no bytes to range over");
    }

    #[test]
    fn a_tape_can_seek_because_every_answer_says_it_takes_ranges() {
        let bytes: Vec<u8> = (0..100).collect();
        let part = answer(Some(bytes.clone()), Some("bytes=10-19"));
        assert_eq!(part.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(part.body(), &bytes[10..20]);
        assert_eq!(header_of(&part, header::CONTENT_RANGE), Some("bytes 10-19/100"));
        assert_eq!(header_of(&part, header::CONTENT_LENGTH), Some("10"));
        let whole = answer(Some(bytes.clone()), None);
        assert_eq!((whole.status(), whole.body().len()), (StatusCode::OK, 100));
        assert_eq!(header_of(&whole, header::CONTENT_LENGTH), Some("100"));
        for response in [&part, &whole] {
            assert_eq!(header_of(response, header::ACCEPT_RANGES), Some("bytes"), "or the media element will not seek");
            assert_eq!(header_of(response, header::CONTENT_TYPE), Some("audio/wav"));
            assert_eq!(header_of(response, header::ACCESS_CONTROL_ALLOW_ORIGIN), Some("*"));
        }
        assert_eq!(answer(None, Some("bytes=0-1")).status(), StatusCode::NOT_FOUND);
    }
}
