//! A file served to a media element a range at a time: the answer the `vid`
//! scheme gives a film (videos.rs), written once for any scheme whose file is
//! too big to read whole.
//!
//! A `<video>` seeks by asking for byte ranges, and treats a server with no
//! `Accept-Ranges` as one it cannot seek on. A film the phone filmed can be a
//! gigabyte, so nothing here ever reads a file whole: a range is a seek and a
//! read of its bytes, never more than `OPEN_RANGE_CAP` of them at once, so an
//! open-ended range (`bytes=a-`, the element's "the rest"), the last bytes
//! (`bytes=-n`) and a closed range as wide as the film are each answered with
//! at most that much as a 206 whose `Content-Range` says where it ends, which
//! a media element reads as "ask again from here". A `HEAD` reads nothing at
//! all (the page asks one to learn whether the film is on this phone before it
//! draws a play button). A request with no range is answered whole only up to
//! `WHOLE_CAP`, and past that with a 416 that names the length, so the element
//! asks again in ranges.
//!
//! The same shape as the `rec` scheme's answer (recordings.rs), made general
//! here rather than there: that one serves a WAV and stays as it is, proven on
//! the phone.
//!
//! WHY THE SLICES ARE SMALL. wry calls a custom scheme's handler on the
//! WebView's own request thread on Android and waits for its answer there
//! (`MAIN_PIPE_TIMEOUT * 3`, 30 s), whether the answer is made at once or on
//! another thread, so a scheme registered asynchronously would change nothing.
//! What matters is that each answer comes well inside that, and a 4 MB read
//! from flash does by orders of magnitude.

use std::io::{Read, Seek, SeekFrom};

use tauri::http::{header, Response, StatusCode};

/// How much of an open-ended range is answered at once: 4 MB, a few seconds of
/// a phone's film. The element asks for the rest as it plays.
pub const OPEN_RANGE_CAP: u64 = 4 * 1024 * 1024;

/// The most a request with no range is answered with whole.
pub const WHOLE_CAP: u64 = 8 * 1024 * 1024;

/// The media type a film's name says it is: mp4 and m4v as MP4, mov as
/// QuickTime, webm as WebM, and nothing else.
pub fn content_type(name: &str) -> Option<&'static str> {
    match name.rsplit_once('.').map(|(_, extension)| extension) {
        Some("mp4" | "m4v") => Some("video/mp4"),
        Some("mov") => Some("video/quicktime"),
        Some("webm") => Some("video/webm"),
        _ => None,
    }
}

/// What a `Range` header asks of a file `total` bytes long.
#[derive(Debug, PartialEq, Eq)]
pub enum Asked {
    /// The inclusive bytes to answer with, as a 206.
    Part(u64, u64),
    /// A range that starts past the end: a 416.
    Beyond,
    /// No range this answers: the whole file, as a 200, where it is small enough.
    Whole,
}

/// The bytes a `Range` header asks for within `total`: `bytes=a-b` (an end
/// past the file is the file's end), `bytes=a-` for the rest, and `bytes=-n`
/// for the last `n`, each capped at `OPEN_RANGE_CAP` from where it starts: a
/// 206 shorter than asked is the server's to give, and a range a gigabyte wide
/// would be a gigabyte in memory twice over on a phone (here, then the
/// WebView's copy). Several ranges at once, or anything else, is answered as
/// though no range were asked.
pub fn asked(range: Option<&str>, total: u64) -> Asked {
    let Some(spec) = range.and_then(|range| range.trim().strip_prefix("bytes=")) else { return Asked::Whole };
    if spec.contains(',') {
        return Asked::Whole;
    }
    let Some((a, b)) = spec.split_once('-') else { return Asked::Whole };
    let (a, b) = (a.trim(), b.trim());
    if a.is_empty() {
        // The last `n` bytes.
        let Ok(n) = b.parse::<u64>() else { return Asked::Whole };
        if n == 0 || total == 0 {
            return Asked::Beyond;
        }
        let start = total.saturating_sub(n);
        let end = start.saturating_add(OPEN_RANGE_CAP).min(total) - 1;
        return Asked::Part(start, end);
    }
    let Ok(start) = a.parse::<u64>() else { return Asked::Whole };
    if start >= total {
        return Asked::Beyond;
    }
    let end = if b.is_empty() {
        start.saturating_add(OPEN_RANGE_CAP).min(total) - 1
    } else {
        let Ok(end) = b.parse::<u64>() else { return Asked::Whole };
        if end < start {
            return Asked::Whole;
        }
        end.min(total - 1).min(start.saturating_add(OPEN_RANGE_CAP) - 1)
    };
    Asked::Part(start, end)
}

/// The answer to a request for a file: `file` is the open file and its length,
/// or `None` when there is none (a 404, which the page reads as "not on this
/// phone"); `range` the request's `Range` header; `head` for a `HEAD`, answered
/// with the headers a `GET` would have and no bytes read. A file that cannot be
/// read where it should be is a 500, not a 404.
pub fn answer(file: Option<(impl Read + Seek, u64)>, range: Option<&str>, head: bool, content_type: &str) -> Response<Vec<u8>> {
    let respond = |status: StatusCode, body: Vec<u8>, extra: Vec<(header::HeaderName, String)>| {
        let mut builder = Response::builder()
            .status(status)
            .header(header::CONTENT_TYPE, content_type)
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
    let beyond = || respond(StatusCode::RANGE_NOT_SATISFIABLE, Vec::new(), vec![(header::CONTENT_RANGE, format!("bytes */{total}"))]);
    let (start, end) = match asked(range, total) {
        Asked::Part(start, end) => (start, end),
        Asked::Beyond => return beyond(),
        Asked::Whole if head || total <= WHOLE_CAP => {
            let mut body = Vec::new();
            if !head && total > 0 {
                body = vec![0u8; total as usize];
                if reader.seek(SeekFrom::Start(0)).and_then(|_| reader.read_exact(&mut body)).is_err() {
                    return respond(StatusCode::INTERNAL_SERVER_ERROR, Vec::new(), Vec::new());
                }
            }
            return respond(StatusCode::OK, body, vec![(header::CONTENT_LENGTH, total.to_string())]);
        }
        // Too big to answer whole: the element is told the length, and asks in ranges.
        Asked::Whole => return beyond(),
    };
    let length = end - start + 1;
    let mut body = Vec::new();
    if !head {
        body = vec![0u8; length as usize];
        if reader.seek(SeekFrom::Start(start)).and_then(|_| reader.read_exact(&mut body)).is_err() {
            return respond(StatusCode::INTERNAL_SERVER_ERROR, Vec::new(), Vec::new());
        }
    }
    respond(
        StatusCode::PARTIAL_CONTENT,
        body,
        vec![(header::CONTENT_RANGE, format!("bytes {start}-{end}/{total}")), (header::CONTENT_LENGTH, length.to_string())],
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{header_of, TempDir};

    #[test]
    fn a_film_is_typed_by_its_name() {
        assert_eq!(content_type("a.mp4"), Some("video/mp4"));
        assert_eq!(content_type("a.m4v"), Some("video/mp4"));
        assert_eq!(content_type("a.mov"), Some("video/quicktime"));
        assert_eq!(content_type("a.webm"), Some("video/webm"));
        for name in ["a.mkv", "a.MP4", "a", "a.jpg"] {
            assert_eq!(content_type(name), None, "{name}");
        }
    }

    #[test]
    fn a_range_is_the_bytes_asked_for_and_an_open_one_a_slice() {
        assert_eq!(asked(Some("bytes=0-99"), 1000), Asked::Part(0, 99));
        assert_eq!(asked(Some("bytes=900-"), 1000), Asked::Part(900, 999), "the rest of a short file");
        assert_eq!(asked(Some("bytes=999-999"), 1000), Asked::Part(999, 999));
        assert_eq!(asked(Some("bytes=10-5000"), 1000), Asked::Part(10, 999), "an end past the file is its end");
        assert_eq!(asked(Some("bytes=-100"), 1000), Asked::Part(900, 999), "the last hundred");
        assert_eq!(asked(Some("bytes=-5000"), 1000), Asked::Part(0, 999));
        for past in ["bytes=1000-", "bytes=1000-1001", "bytes=-0"] {
            assert_eq!(asked(Some(past), 1000), Asked::Beyond, "{past}");
        }
        for other in [None, Some("bytes=5-2"), Some("bytes=0-1,5-9"), Some("items=0-1"), Some("bytes=a-b"), Some("bytes")] {
            assert_eq!(asked(other, 1000), Asked::Whole, "{other:?}");
        }
        assert_eq!(asked(Some("bytes=0-"), 0), Asked::Beyond, "an empty file has no bytes to range over");
        let gigabyte = 1024 * 1024 * 1024;
        assert_eq!(asked(Some("bytes=0-"), gigabyte), Asked::Part(0, OPEN_RANGE_CAP - 1));
        assert_eq!(asked(Some("bytes=5000-"), gigabyte), Asked::Part(5000, 5000 + OPEN_RANGE_CAP - 1));
        // The last bytes of a long film, and a closed range as wide as it, are capped the same way.
        assert_eq!(asked(Some("bytes=-500000000"), gigabyte), Asked::Part(gigabyte - 500_000_000, gigabyte - 500_000_000 + OPEN_RANGE_CAP - 1));
        assert_eq!(asked(Some("bytes=0-1073741823"), 2 * gigabyte), Asked::Part(0, OPEN_RANGE_CAP - 1));
        assert_eq!(asked(Some("bytes=100-199"), gigabyte), Asked::Part(100, 199), "a narrow range is answered as asked");
    }

    /// A file on disk, opened the way the scheme opens it.
    fn opened(dir: &TempDir, bytes: &[u8]) -> Option<(std::fs::File, u64)> {
        let path = dir.join("film.mp4");
        std::fs::write(&path, bytes).unwrap();
        let file = std::fs::File::open(&path).unwrap();
        let total = file.metadata().unwrap().len();
        Some((file, total))
    }

    #[test]
    fn every_answer_says_it_takes_ranges_and_what_it_is() {
        let dir = TempDir::new("ranged");
        let bytes: Vec<u8> = (0..100).collect();
        let part = answer(opened(&dir, &bytes), Some("bytes=10-19"), false, "video/mp4");
        assert_eq!(part.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(part.body(), &bytes[10..20]);
        assert_eq!(header_of(&part, header::CONTENT_RANGE), Some("bytes 10-19/100"));
        assert_eq!(header_of(&part, header::CONTENT_LENGTH), Some("10"));
        let whole = answer(opened(&dir, &bytes), None, false, "video/mp4");
        assert_eq!((whole.status(), whole.body().as_slice()), (StatusCode::OK, bytes.as_slice()));
        assert_eq!(header_of(&whole, header::CONTENT_LENGTH), Some("100"));
        for response in [&part, &whole] {
            assert_eq!(header_of(response, header::ACCEPT_RANGES), Some("bytes"), "or the element will not seek");
            assert_eq!(header_of(response, header::CONTENT_TYPE), Some("video/mp4"));
            assert_eq!(header_of(response, header::CACHE_CONTROL), Some("no-store"));
            assert_eq!(header_of(response, header::ACCESS_CONTROL_ALLOW_ORIGIN), Some("*"));
        }
        let missing = answer(None::<(std::fs::File, u64)>, Some("bytes=0-1"), false, "video/mp4");
        assert_eq!(missing.status(), StatusCode::NOT_FOUND, "not on this phone");
        let beyond = answer(opened(&dir, &bytes), Some("bytes=100-"), false, "video/mp4");
        assert_eq!((beyond.status(), header_of(&beyond, header::CONTENT_RANGE)), (StatusCode::RANGE_NOT_SATISFIABLE, Some("bytes */100")));
    }

    /// A reader that counts what is read through it: the proof that an answer
    /// reads its bytes and no more.
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

    type ReadSoFar = std::rc::Rc<std::cell::Cell<u64>>;

    fn counted(dir: &TempDir, bytes: &[u8]) -> (Option<(Counting<std::fs::File>, u64)>, ReadSoFar) {
        let read = std::rc::Rc::new(std::cell::Cell::new(0));
        let (file, total) = opened(dir, bytes).unwrap();
        (Some((Counting { inner: file, read: std::rc::Rc::clone(&read) }, total)), read)
    }

    #[test]
    fn a_long_film_is_read_a_slice_at_a_time_and_never_whole() {
        let dir = TempDir::new("ranged-long");
        let long: Vec<u8> = (0..(WHOLE_CAP as usize + 5000)).map(|i| (i % 251) as u8).collect();

        let (file, read) = counted(&dir, &long);
        let first = answer(file, Some("bytes=0-"), false, "video/mp4");
        assert_eq!(first.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(first.body().as_slice(), &long[..OPEN_RANGE_CAP as usize]);
        assert_eq!(read.get(), OPEN_RANGE_CAP, "the open range reads its slice");
        assert_eq!(header_of(&first, header::CONTENT_RANGE), Some(format!("bytes 0-{}/{}", OPEN_RANGE_CAP - 1, long.len()).as_str()));

        let (file, read) = counted(&dir, &long);
        let part = answer(file, Some("bytes=1000-1999"), false, "video/mp4");
        assert_eq!((part.body().as_slice(), read.get()), (&long[1000..2000], 1000));

        let (file, read) = counted(&dir, &long);
        let head = answer(file, None, true, "video/mp4");
        assert_eq!((head.status(), head.body().len(), read.get()), (StatusCode::OK, 0, 0), "a HEAD reads nothing");
        assert_eq!(header_of(&head, header::CONTENT_LENGTH), Some(long.len().to_string().as_str()), "and says how long it is");

        let (file, read) = counted(&dir, &long);
        let head = answer(file, Some("bytes=0-99"), true, "video/mp4");
        assert_eq!((head.status(), read.get()), (StatusCode::PARTIAL_CONTENT, 0));

        // Past 8 MB, a request with no range is not read at all: it is told the length and asks in ranges.
        let (file, read) = counted(&dir, &long);
        let whole = answer(file, None, false, "video/mp4");
        assert_eq!((whole.status(), read.get()), (StatusCode::RANGE_NOT_SATISFIABLE, 0));
        assert_eq!(header_of(&whole, header::CONTENT_RANGE), Some(format!("bytes */{}", long.len()).as_str()));

        // At 8 MB exactly, it is answered whole.
        let (file, read) = counted(&dir, &long[..WHOLE_CAP as usize]);
        let whole = answer(file, None, false, "video/mp4");
        assert_eq!((whole.status(), read.get()), (StatusCode::OK, WHOLE_CAP));
    }
}
