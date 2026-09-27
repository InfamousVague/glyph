//! A recording's phrases as the paragraphs of its transcript, and the
//! `## Transcript` section they live in: the Rust twin of the page's
//! `capture/markdown.ts` (`toParagraphs`, `renderTranscript`, `withTranscript`,
//! `withoutTranscript`) and `ai/summaryText.ts` (`transcriptPieces`).
//!
//! Twins because a meeting on Android is written up with the app closed
//! (`write_up.rs`), and the note must not be wordless on disk until the page
//! next runs: the transcript goes into the body from here. The page renders the
//! same phrases the same way on the Mac and when it lays a refined take out, so
//! the two must agree line for line, or a body the page re-renders would differ
//! from the one Rust wrote and every conflict rule downstream would trip. One
//! fixture, `src/app/capture/paragraphs.fixture.json`, is asserted on both
//! sides; the test here reads it and skips when it is not in the tree.
//!
//! Every target, NOT ONE `tauri::` TYPE, and nothing but `note.rs` beside it,
//! so tools/host-tests compiles it by path with the library.

use crate::note::RecordedSegment;

/// A pause longer than this between two phrases starts a new paragraph. The
/// page's `PARAGRAPH_GAP_MS`, whose docblock says why 1.5 s.
pub const PARAGRAPH_GAP_MS: u64 = 1500;

/// The heading the section is known by.
pub const TRANSCRIPT_HEADING: &str = "## Transcript";

/// `text` with its first character in upper case and the rest as written: the
/// page's `capitalise`.
fn capitalise(text: &str) -> String {
    let mut chars = text.chars();
    match chars.next() {
        Some(first) => first.to_uppercase().chain(chars).collect(),
        None => String::new(),
    }
}

/// A byte that JavaScript's `\w` matches, for the word boundary round a cue.
fn word_byte(byte: u8) -> bool {
    byte.is_ascii_alphanumeric() || byte == b'_'
}

/// `text` cut at every spoken "new paragraph" or "next paragraph" (case
/// ignored, an optional `.,!?` after it consumed): the page's `PARAGRAPH_CUE`
/// split, with its word boundaries.
fn split_cue(text: &str) -> Vec<&str> {
    const CUES: [&str; 2] = ["new paragraph", "next paragraph"];
    let lower = text.to_ascii_lowercase();
    let bytes = lower.as_bytes();
    let mut pieces = Vec::new();
    let mut from = 0;
    let mut at = 0;
    while at < bytes.len() {
        if !text.is_char_boundary(at) {
            at += 1;
            continue;
        }
        let bounded_before = at == 0 || !word_byte(bytes[at - 1]);
        let hit = CUES.iter().copied().find(|cue| {
            let end = at + cue.len();
            bounded_before && lower[at..].starts_with(cue) && (end == bytes.len() || !word_byte(bytes[end]))
        });
        match hit {
            Some(cue) => {
                let mut end = at + cue.len();
                if end < bytes.len() && matches!(bytes[end], b'.' | b',' | b'!' | b'?') {
                    end += 1;
                }
                pieces.push(&text[from..at]);
                from = end;
                at = end;
            }
            None => at += 1,
        }
    }
    pieces.push(&text[from..]);
    pieces
}

/// A piece with the marks a cut leaves at its start dropped: whitespace,
/// `.,;:?`, and a `!` that does not open a picture (`![`). The page's
/// `^(?:[\s.,;:?]|!(?!\[))+`.
fn strip_leading(piece: &str) -> &str {
    let mut rest = piece;
    loop {
        let mut chars = rest.chars();
        let Some(first) = chars.next() else { return rest };
        let drop = first.is_whitespace()
            || matches!(first, '.' | ',' | ';' | ':' | '?')
            || (first == '!' && !chars.as_str().starts_with('['));
        if !drop {
            return rest;
        }
        rest = &rest[first.len_utf8()..];
    }
}

/// Committed phrases, grouped into paragraphs by pause length and spoken cue:
/// the twin of the page's `toParagraphs`. A gap over [`PARAGRAPH_GAP_MS`]
/// breaks, a "new paragraph" cue breaks, every paragraph starts with a
/// capital, a phrase after a finished sentence does too, and an empty phrase
/// is skipped.
pub fn paragraphs(segments: &[RecordedSegment]) -> Vec<String> {
    let mut out = Vec::new();
    let mut current = String::new();
    let mut last_end: Option<u64> = None;
    fn flush(current: &mut String, out: &mut Vec<String>) {
        let text = current.trim();
        if !text.is_empty() {
            out.push(capitalise(text));
        }
        current.clear();
    }
    for segment in segments {
        let text = segment.text.trim();
        if text.is_empty() {
            continue;
        }
        if last_end.is_some_and(|end| segment.start_ms.saturating_sub(end) > PARAGRAPH_GAP_MS) {
            flush(&mut current, &mut out);
        }
        last_end = Some(segment.end_ms);
        for (index, piece) in split_cue(text).into_iter().enumerate() {
            if index > 0 {
                flush(&mut current, &mut out);
            }
            let part = strip_leading(piece).trim();
            if part.is_empty() {
                continue;
            }
            // A phrase after a finished sentence starts one, whatever case whisper gave it.
            let said = if !current.is_empty() && current.ends_with(['.', '!', '?']) { capitalise(part) } else { part.to_string() };
            if current.is_empty() {
                current = said;
            } else {
                current.push(' ');
                current.push_str(&said);
            }
        }
    }
    flush(&mut current, &mut out);
    out
}

/// The byte offset of the `## Transcript` line in `body`, if it has one.
fn transcript_at(body: &str) -> Option<usize> {
    let mut at = 0;
    for line in body.split_inclusive('\n') {
        if line.trim_end() == TRANSCRIPT_HEADING {
            return Some(at);
        }
        at += line.len();
    }
    None
}

/// `body` with its transcript section replaced, or one appended: whatever is
/// above the `## Transcript` heading stays (a title, a summary), and from the
/// heading to the end is the paragraphs, joined by blank lines.
pub fn with_transcript(body: &str, paragraphs: &[String]) -> String {
    let before = transcript_at(body).map_or(body, |at| &body[..at]).trim_end();
    let mut out = String::with_capacity(before.len() + paragraphs.iter().map(|p| p.len() + 2).sum::<usize>() + 32);
    if !before.is_empty() {
        out.push_str(before);
        out.push_str("\n\n");
    }
    out.push_str(TRANSCRIPT_HEADING);
    if !paragraphs.is_empty() {
        out.push_str("\n\n");
        out.push_str(&paragraphs.join("\n\n"));
    }
    out.push('\n');
    out
}

/// `body` without its transcript section, trailing whitespace trimmed: what the
/// page compares two bodies by to tell a transcript's arrival from an edit.
pub fn without_transcript(body: &str) -> String {
    transcript_at(body).map_or(body, |at| &body[..at]).trim_end().to_string()
}

/// A paragraph's sentences, each with its closing mark: split where `.`, `!`
/// or `?` (an optional closing quote or bracket after it) meets whitespace,
/// which the page's `SENTENCE_END` also takes.
fn sentences(paragraph: &str) -> Vec<&str> {
    let mut out = Vec::new();
    let mut from = 0;
    let mut chars = paragraph.char_indices().peekable();
    while let Some((at, c)) = chars.next() {
        if !c.is_whitespace() {
            continue;
        }
        let before = &paragraph[..at];
        let ends = before.ends_with(['.', '!', '?']) || {
            let mut trimmed = before.chars();
            matches!(trimmed.next_back(), Some('"' | '”' | '’' | ')')) && trimmed.as_str().ends_with(['.', '!', '?'])
        };
        if !ends {
            continue;
        }
        out.push(&paragraph[from..at]);
        let mut end = at + c.len_utf8();
        while let Some((next_at, next)) = chars.peek().copied() {
            if !next.is_whitespace() {
                break;
            }
            end = next_at + next.len_utf8();
            chars.next();
        }
        from = end;
    }
    out.push(&paragraph[from..]);
    out
}

/// The first `size` characters of `text` and the rest, on a character.
fn cut_chars(text: &str, size: usize) -> (&str, &str) {
    match text.char_indices().nth(size) {
        Some((at, _)) => text.split_at(at),
        None => (text, ""),
    }
}

/// A long paragraph as runs of sentences each under `size`, a sentence longer
/// than that cut where it must be: the page's `sentencesUnder`.
fn sentences_under(paragraph: &str, size: usize) -> Vec<String> {
    let mut out = Vec::new();
    let mut run = String::new();
    for sentence in sentences(paragraph) {
        let mut rest = sentence;
        while !rest.is_empty() {
            let (part, after) = cut_chars(rest, size);
            rest = after;
            if !run.is_empty() && run.chars().count() + 1 + part.chars().count() > size {
                out.push(std::mem::take(&mut run));
            }
            if run.is_empty() {
                run = part.to_string();
            } else {
                run.push(' ');
                run.push_str(part);
            }
        }
    }
    if !run.is_empty() {
        out.push(run);
    }
    out
}

/// `plain` cut at paragraph breaks into pieces of about `size` characters, a
/// paragraph over that cut at its sentences: the twin of the page's
/// `transcriptPieces`. Whether a transcript needs cutting at all
/// (`onePassChars`) is the caller's rule, as it is the page's.
pub fn pieces(plain: &str, size: usize) -> Vec<String> {
    let text = plain.trim();
    if text.is_empty() {
        return Vec::new();
    }
    let mut units: Vec<String> = Vec::new();
    let mut paragraph = String::new();
    let close = |paragraph: &mut String, units: &mut Vec<String>| {
        let trimmed = paragraph.trim();
        if !trimmed.is_empty() {
            if trimmed.chars().count() <= size {
                units.push(trimmed.to_string());
            } else {
                units.extend(sentences_under(trimmed, size));
            }
        }
        paragraph.clear();
    };
    for line in text.split('\n') {
        if line.trim().is_empty() {
            close(&mut paragraph, &mut units);
        } else {
            if !paragraph.is_empty() {
                paragraph.push('\n');
            }
            paragraph.push_str(line);
        }
    }
    close(&mut paragraph, &mut units);

    let mut out = Vec::new();
    let mut piece = String::new();
    for unit in units {
        if !piece.is_empty() && piece.chars().count() + 2 + unit.chars().count() > size {
            out.push(std::mem::take(&mut piece));
        }
        if piece.is_empty() {
            piece = unit;
        } else {
            piece.push_str("\n\n");
            piece.push_str(&unit);
        }
    }
    if !piece.is_empty() {
        out.push(piece);
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::{Path, PathBuf};

    fn segment(text: &str, start_ms: u64, end_ms: u64) -> RecordedSegment {
        RecordedSegment { text: text.into(), start_ms, end_ms }
    }

    /// The repository: `GLYPH_REPO_DIR`, or the nearest directory above this
    /// crate that holds a `package.json` (src-tauri's parent, or
    /// tools/host-tests' grandparent).
    fn repo_dir() -> Option<PathBuf> {
        if let Some(dir) = std::env::var_os("GLYPH_REPO_DIR") {
            return Some(PathBuf::from(dir));
        }
        let mut dir = Path::new(env!("CARGO_MANIFEST_DIR")).to_path_buf();
        loop {
            if dir.join("package.json").is_file() {
                return Some(dir);
            }
            if !dir.pop() {
                return None;
            }
        }
    }

    /// The fixture both twins are asserted on, when it is in the tree.
    #[test]
    fn the_paragraphs_agree_with_the_pages_fixture() {
        let path = repo_dir().map(|dir| dir.join("src/app/capture/paragraphs.fixture.json"));
        let Some(source) = path.as_ref().and_then(|path| std::fs::read_to_string(path).ok()) else {
            eprintln!("SKIPPED: src/app/capture/paragraphs.fixture.json is not in this tree yet");
            return;
        };
        #[derive(serde::Deserialize)]
        struct Case {
            name: String,
            segments: Vec<RecordedSegment>,
            paragraphs: Vec<String>,
        }
        let cases: Vec<Case> = serde_json::from_str(&source).expect("the fixture is a list of cases");
        assert!(!cases.is_empty());
        for case in cases {
            assert_eq!(paragraphs(&case.segments), case.paragraphs, "{}", case.name);
        }
    }

    #[test]
    fn a_pause_a_cue_and_a_finished_sentence_shape_the_paragraphs() {
        let got = paragraphs(&[
            segment("ok so the launch moves.", 0, 2000),
            segment("to march", 2100, 3000),
            segment("", 3000, 3000),
            segment("sam owns the press list", 5000, 7000),
            segment("and the copy. new paragraph, we decided no ads", 7100, 9000),
            segment("Next Paragraph. until the beta closes!", 9100, 11_000),
        ]);
        assert_eq!(
            got,
            [
                "Ok so the launch moves. To march",
                "Sam owns the press list and the copy.",
                "We decided no ads",
                "Until the beta closes!",
            ]
        );
        assert!(paragraphs(&[segment("  ", 0, 1), segment("...", 1, 2)]).is_empty(), "nothing said is no paragraph");
        // A cue inside a word is a word; a picture's `!` is kept.
        assert_eq!(paragraphs(&[segment("renew paragraphs. ![](image/a.jpg)", 0, 1)]), ["Renew paragraphs. ![](image/a.jpg)"]);
    }

    #[test]
    fn the_transcript_section_is_replaced_whole_or_appended_under_what_is_there() {
        let paragraphs = vec!["First.".to_string(), "Second.".to_string()];
        assert_eq!(with_transcript("# Meeting, 26 Sep 14:05\n", &paragraphs), "# Meeting, 26 Sep 14:05\n\n## Transcript\n\nFirst.\n\nSecond.\n");
        let summarised = "# Meeting\n## Summary\nWhat was settled.\n\n- [ ] Book it.\n\n## Transcript\n\nOld words.\n";
        assert_eq!(with_transcript(summarised, &paragraphs), "# Meeting\n## Summary\nWhat was settled.\n\n- [ ] Book it.\n\n## Transcript\n\nFirst.\n\nSecond.\n");
        assert_eq!(with_transcript("", &[]), "## Transcript\n", "no words yet is still the section");
        assert_eq!(without_transcript(summarised), "# Meeting\n## Summary\nWhat was settled.\n\n- [ ] Book it.");
        assert_eq!(without_transcript("# Meeting\n\n"), "# Meeting");
        assert_eq!(without_transcript(&with_transcript("# Meeting\n", &paragraphs)), without_transcript("# Meeting\n"), "the page's rule: a transcript's arrival is not an edit");
    }

    #[test]
    fn pieces_are_cut_at_paragraph_breaks_and_a_long_paragraph_at_its_sentences() {
        let plain = "One two three.\n\nFour five six.\n  \nSeven eight.";
        assert_eq!(pieces(plain, 40), ["One two three.\n\nFour five six.", "Seven eight."]);
        assert_eq!(pieces(plain, 1000), [plain.replace("\n  \n", "\n\n")]);
        assert!(pieces("  \n\n ", 10).is_empty());
        let long = "A first sentence here. A second one? \"A third.\" Then a fourth sentence that runs on for a while";
        let got = pieces(long, 40);
        // A sentence longer than the size is cut where it must be, as the page's `slice` cuts it.
        assert_eq!(got, ["A first sentence here. A second one?", "\"A third.\"", "Then a fourth sentence that runs on for ", "a while"]);
        assert!(got.iter().all(|p| p.chars().count() <= 40), "{got:?}");
        assert_eq!(sentences("Costs 3.50 today. Really?  Yes!"), ["Costs 3.50 today.", "Really?", "Yes!"]);
    }
}
