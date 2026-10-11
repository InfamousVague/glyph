//! A spoken note's kept recording: `<app_data_dir>/recordings/<id>.wav`, the
//! one rule for which ids may name one, how one that arrived by sync is kept,
//! and the `rec` scheme its tape plays through.
//!
//! The capture seam writes a take here (`capture_stop`) and moves one to the
//! note it turned out to belong to (`capture_reassign_recording`); the meeting
//! service writes one as it records (`capture/MeetingService.kt`); sync keeps
//! another device's (`sync_put_file`); a deleted note takes its recording with
//! it (`delete_note`). Those used to re-derive the folder and the name rule
//! each for themselves, so renaming either in one place would have left a tape
//! unplayable; they all ask here now.
//!
//! THE SCHEME READS ONLY WHAT IS ASKED FOR. A media element seeks by asking for
//! byte ranges, and an hour's meeting is 115 MB: reading the whole file on the
//! WebView's thread for every request, as this once did, would read it again on
//! every seek. So `serve` stats the file, seeks, and reads the bytes of the
//! range - and an open-ended range (`bytes=a-`, which is how an element asks
//! for "the rest") is answered with the first `OPEN_RANGE_CAP` of it as a 206,
//! whose `Content-Range` tells the element there is more to ask for. A `HEAD`
//! reads nothing at all: the tape asks one to learn why it would not play
//! (tapes/useTape.ts), and that is when a phone short of memory should not be
//! handed an hour's tape to throw away.

use std::io::{Read, Seek, SeekFrom};
use std::path::{Path, PathBuf};

use tauri::http::{header, Response, StatusCode};
use tauri::{AppHandle, Runtime};

/// The scheme a kept recording is played through: `http://rec.localhost/<id>.wav`
/// on Android, `rec://localhost/<id>.wav` elsewhere - the same shape as `ota`.
pub const SCHEME: &str = "rec";

/// How much of an open-ended range is answered at once: 2 MB, about a minute
/// of 16 kHz PCM16. The element asks for the rest as it plays.
pub const OPEN_RANGE_CAP: u64 = 2 * 1024 * 1024;

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
/// by `recording_file`; only the bytes asked for are read.
pub fn serve<R: Runtime>(app: &AppHandle<R>, request: &tauri::http::Request<Vec<u8>>) -> Response<Vec<u8>> {
    let path = request.uri().path().trim_start_matches('/');
    let file = path
        .strip_suffix(".wav")
        .and_then(|id| crate::paths::recordings_dir(app).ok().and_then(|dir| recording_file(&dir, id)))
        .and_then(|file| std::fs::File::open(file).ok())
        .and_then(|file| file.metadata().ok().map(|meta| (file, meta.len())));
    let range = request.headers().get(header::RANGE).and_then(|v| v.to_str().ok());
    answer(file, range, request.method() == tauri::http::Method::HEAD)
}

/// The response to a request for a recording: `file` is the open file and its
/// length, or `None` when none was found; `range` the request's `Range` header
/// if it sent one; `head` for a `HEAD`, which is answered with the headers a
/// `GET` would have and no bytes read. A range is read by seeking to it; no
/// range is the whole file as a 200. A file that cannot be read where it
/// should be is a 500, not a 404: "not on this device" is the page's reading
/// of a 404.
fn answer(file: Option<(impl Read + Seek, u64)>, range: Option<&str>, head: bool) -> Response<Vec<u8>> {
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
    let Some((mut reader, total)) = file else {
        return respond(StatusCode::NOT_FOUND, Vec::new(), Vec::new());
    };
    let (start, end, partial) = match range.and_then(|range| byte_range(range, total)) {
        Some((start, end)) => (start, end, true),
        None => (0, total.saturating_sub(1), false),
    };
    let length = if total == 0 { 0 } else { end - start + 1 };
    let mut body = Vec::new();
    if !head {
        body = vec![0u8; length as usize];
        let read = reader.seek(SeekFrom::Start(start)).and_then(|_| reader.read_exact(&mut body));
        if read.is_err() {
            return respond(StatusCode::INTERNAL_SERVER_ERROR, Vec::new(), Vec::new());
        }
    }
    if partial {
        respond(
            StatusCode::PARTIAL_CONTENT,
            body,
            vec![(header::CONTENT_RANGE, format!("bytes {start}-{end}/{total}")), (header::CONTENT_LENGTH, length.to_string())],
        )
    } else {
        respond(StatusCode::OK, body, vec![(header::CONTENT_LENGTH, total.to_string())])
    }
}

/// The inclusive byte range a `Range` header asks for within `total` bytes:
/// `bytes=<start>-<end>`, or `bytes=<start>-` for the rest, capped at
/// `OPEN_RANGE_CAP` from the start. Anything else - a suffix range, several
/// ranges, an end past the file - is answered with the whole file instead,
/// which a media element accepts as well.
fn byte_range(header: &str, total: u64) -> Option<(u64, u64)> {
    let (a, b) = header.strip_prefix("bytes=")?.split_once('-')?;
    let start: u64 = a.parse().ok()?;
    let end: u64 = if b.is_empty() { start.saturating_add(OPEN_RANGE_CAP).min(total).saturating_sub(1) } else { b.parse().ok()? };
    (start <= end && end < total).then_some((start, end))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{header_of, TempDir};

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
        let root = TempDir::new("recordings");
        let dir = root.join("recordings");
        let wav = b"RIFF\x24\0\0\0WAVEfmt ".to_vec();
        place(&dir, "n1", &base64::engine::general_purpose::STANDARD.encode(&wav)).unwrap();
        assert_eq!(std::fs::read(dir.join("n1.wav")).unwrap(), wav, "the folder is made, and the bytes kept exactly");
        let names: Vec<_> = std::fs::read_dir(&dir).unwrap().map(|e| e.unwrap().file_name()).collect();
        assert_eq!(names, ["n1.wav"], "nothing left beside it");
    }

    #[test]
    fn a_synced_recording_that_is_not_one_is_refused_before_anything_is_written() {
        use base64::Engine as _;
        let root = TempDir::new("recordings");
        let dir = root.join("recordings");
        let wav = base64::engine::general_purpose::STANDARD.encode(b"RIFF\x24\0\0\0WAVEfmt ");
        assert_eq!(place(&dir, "../n1", &wav), Err("That is not a note id.".to_string()));
        assert_eq!(place(&dir, "n1", "not base64!"), Err("That recording could not be read.".to_string()));
        let png = base64::engine::general_purpose::STANDARD.encode(b"\x89PNG\r\n\x1a\n");
        assert_eq!(place(&dir, "n1", &png), Err("That is not a recording Glyph can keep.".to_string()));
        assert!(!dir.exists(), "a refusal writes nothing, not even the folder");
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
        // An hour's tape: the rest is answered in slices the element asks for one by one.
        let hour = 115 * 1024 * 1024;
        assert_eq!(byte_range("bytes=0-", hour), Some((0, OPEN_RANGE_CAP - 1)));
        assert_eq!(byte_range("bytes=1000-", hour), Some((1000, 1000 + OPEN_RANGE_CAP - 1)));
        assert_eq!(byte_range("bytes=1000-", 1000 + 10), Some((1000, 1009)), "a short rest is the rest");
    }

    /// A file on disk, opened the way `serve` opens it.
    fn opened(dir: &TempDir, bytes: &[u8]) -> Option<(std::fs::File, u64)> {
        let path = dir.join("n1.wav");
        std::fs::write(&path, bytes).unwrap();
        let file = std::fs::File::open(&path).unwrap();
        let total = file.metadata().unwrap().len();
        Some((file, total))
    }

    #[test]
    fn a_tape_can_seek_because_every_answer_says_it_takes_ranges() {
        let dir = TempDir::new("rec-scheme");
        let bytes: Vec<u8> = (0..100).collect();
        let part = answer(opened(&dir, &bytes), Some("bytes=10-19"), false);
        assert_eq!(part.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(part.body(), &bytes[10..20]);
        assert_eq!(header_of(&part, header::CONTENT_RANGE), Some("bytes 10-19/100"));
        assert_eq!(header_of(&part, header::CONTENT_LENGTH), Some("10"));
        let whole = answer(opened(&dir, &bytes), None, false);
        assert_eq!((whole.status(), whole.body().len()), (StatusCode::OK, 100));
        assert_eq!(header_of(&whole, header::CONTENT_LENGTH), Some("100"));
        assert_eq!(whole.body(), &bytes);
        for response in [&part, &whole] {
            assert_eq!(header_of(response, header::ACCEPT_RANGES), Some("bytes"), "or the media element will not seek");
            assert_eq!(header_of(response, header::CONTENT_TYPE), Some("audio/wav"));
            assert_eq!(header_of(response, header::ACCESS_CONTROL_ALLOW_ORIGIN), Some("*"));
        }
        assert_eq!(answer(None::<(std::fs::File, u64)>, Some("bytes=0-1"), false).status(), StatusCode::NOT_FOUND);
        let empty = answer(opened(&dir, &[]), None, false);
        assert_eq!((empty.status(), empty.body().len()), (StatusCode::OK, 0));
    }

    /// The rest of a long tape comes a slice at a time, and only that slice is read.
    #[test]
    fn an_open_ended_range_is_the_first_slice_and_says_how_much_is_left() {
        let dir = TempDir::new("rec-open");
        let long: Vec<u8> = (0..(OPEN_RANGE_CAP as usize + 5000)).map(|i| (i % 251) as u8).collect();
        let first = answer(opened(&dir, &long), Some("bytes=0-"), false);
        assert_eq!(first.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(first.body().len() as u64, OPEN_RANGE_CAP);
        assert_eq!(first.body(), &long[..OPEN_RANGE_CAP as usize]);
        assert_eq!(header_of(&first, header::CONTENT_RANGE), Some(format!("bytes 0-{}/{}", OPEN_RANGE_CAP - 1, long.len()).as_str()));
        let rest = answer(opened(&dir, &long), Some(&format!("bytes={OPEN_RANGE_CAP}-")), false);
        assert_eq!(rest.body(), &long[OPEN_RANGE_CAP as usize..]);
        assert_eq!(header_of(&rest, header::CONTENT_RANGE), Some(format!("bytes {}-{}/{}", OPEN_RANGE_CAP, long.len() - 1, long.len()).as_str()));
    }

    /// A reader that counts what is read through it: the proof that a range
    /// reads its bytes and no more, where the body alone could be a slice of a
    /// whole file read into memory.
    struct Counting<R> {
        inner: R,
        read: std::rc::Rc<std::cell::Cell<u64>>,
    }

    impl<R: Read> Read for Counting<R> {
        fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
            let n = self.inner.read(buffer)?;
            self.read.set(self.read.get() + n as u64);
            Ok(n)
        }
    }

    impl<R: Seek> Seek for Counting<R> {
        fn seek(&mut self, to: SeekFrom) -> std::io::Result<u64> {
            self.inner.seek(to)
        }
    }

    /// How many bytes a `Counting` reader has read, shared with the test that asks.
    type ReadSoFar = std::rc::Rc<std::cell::Cell<u64>>;

    fn counted(dir: &TempDir, bytes: &[u8]) -> (Option<(Counting<std::fs::File>, u64)>, ReadSoFar) {
        let read = std::rc::Rc::new(std::cell::Cell::new(0));
        let (file, total) = opened(dir, bytes).unwrap();
        (Some((Counting { inner: file, read: std::rc::Rc::clone(&read) }, total)), read)
    }

    #[test]
    fn a_range_reads_only_its_bytes_and_a_head_reads_none() {
        let dir = TempDir::new("rec-counted");
        let long: Vec<u8> = (0..(OPEN_RANGE_CAP as usize * 3)).map(|i| (i % 251) as u8).collect();
        let (file, read) = counted(&dir, &long);
        let part = answer(file, Some("bytes=1000-1999"), false);
        assert_eq!(part.body(), &long[1000..2000]);
        assert_eq!(read.get(), 1000, "the thousand bytes asked for, not the file");
        let (file, read) = counted(&dir, &long);
        let open = answer(file, Some("bytes=5-"), false);
        assert_eq!(open.body().len() as u64, OPEN_RANGE_CAP);
        assert_eq!(read.get(), OPEN_RANGE_CAP, "an open end reads its slice");
        let (file, read) = counted(&dir, &long);
        let head = answer(file, None, true);
        assert_eq!((head.status(), head.body().len(), read.get()), (StatusCode::OK, 0, 0), "a HEAD reads nothing");
        assert_eq!(header_of(&head, header::CONTENT_LENGTH), Some(long.len().to_string().as_str()), "and says how long it is");
        let (file, read) = counted(&dir, &long);
        let head = answer(file, Some("bytes=0-99"), true);
        assert_eq!((head.status(), read.get()), (StatusCode::PARTIAL_CONTENT, 0));
        assert_eq!(header_of(&head, header::CONTENT_RANGE), Some(format!("bytes 0-99/{}", long.len()).as_str()));
        assert_eq!(answer(None::<(std::fs::File, u64)>, None, true).status(), StatusCode::NOT_FOUND, "a missing tape is still a 404");
    }
}
