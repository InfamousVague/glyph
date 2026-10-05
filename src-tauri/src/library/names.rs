//! A note's file name: its title, made safe for every file system a library
//! might be synced to (docs/LIBRARY.md).

/// The title a note's file is named by. Which line it is follows the page's
/// `noteTitle` (core/noteTitle.ts): the first line of words, a picture line
/// skipped, and front matter at the top of the body skipped with it, its
/// `title:` taken as the title where it has one. A book, a canvas and a note an
/// AI signed all open with such a block, and were named "---.md" until
/// 2026-09-27. What is taken off that line is not the page's: both drop a
/// heading's `#`s, but `plain` also drops a list's or a task's marker, a
/// quote's `>`, emphasis and code marks, and a link's address, which the list
/// shows, and keeps the bookmark (`§§`), which the list drops. So
/// "- [ ] **Buy** milk" names a file "Buy milk.md", and the list shows the line
/// as it is written.
///
/// Blanks and fills read as the page reads them (core/blanks.ts `titleWords`,
/// docs/DESIGN.md §145): a filled answer, `??Tokyo??(… from memory, …)`, as its
/// words; a blank that is the whole line as nothing when it asks for a title, or
/// as its question otherwise; and a blank among other words left out. A note
/// titled `# Trip to {?capital of Japan}` was named "Trip to {?capital of
/// Japan}.md" until the rule landed here; core/titles.fixture.json holds the rows
/// both sides are tested on.
pub fn title_of(body: &str) -> String {
    let lines: Vec<&str> = body.lines().collect();
    let (named, words) = without_front_matter(&lines);
    named
        .as_deref()
        .into_iter()
        .chain(words.iter().copied())
        .map(str::trim)
        .find(|line| !line.is_empty() && !is_picture_line(line))
        .map(|line| plain(&title_words(line)))
        .unwrap_or_default()
}

/// The page's `titleWords` (core/blanks.ts): the line with its fills read as
/// their words and its blanks taken out or read, the heading's `#` left on.
fn title_words(line: &str) -> String {
    let text = plain_fills(line);
    if !text.contains("{?") {
        return text;
    }
    let lead_len = heading_lead(&text);
    let (lead, rest) = text.split_at(lead_len);
    let blanks = blanks_in(rest);
    if let [(from, to, question)] = blanks.as_slice() {
        if rest[..*from].trim().is_empty() && rest[*to..].trim().is_empty() {
            let question = question.trim();
            return if asks_for_title(question) {
                lead.trim_end_matches(|c: char| c.is_whitespace()).trim_end_matches('#').trim_end().to_string()
            } else {
                format!("{lead}{question}")
            };
        }
    }
    let mut out = String::with_capacity(text.len());
    let mut at = 0;
    for (from, to, _) in blanks_in(&text) {
        out.push_str(&text[at..from]);
        at = to;
    }
    out.push_str(&text[at..]);
    // Spaces closed up where a blank was - a run of two or more spaces or tabs as one space, as the page's
    // `[ \t]{2,}` - and none left at the end.
    let mut closed = String::with_capacity(out.len());
    let mut run = String::new();
    for c in out.chars() {
        if c == ' ' || c == '\t' {
            run.push(c);
            continue;
        }
        closed.push_str(if run.chars().count() > 1 { " " } else { &run });
        run.clear();
        closed.push(c);
    }
    closed.push_str(if run.chars().count() > 1 { " " } else { &run });
    closed.trim_end().to_string()
}

/// The length of a line's heading mark and the space after it (`# `), or of its leading space: the page's
/// `^\s*(?:#{1,6}\s+)?`.
fn heading_lead(text: &str) -> usize {
    let start = text.len() - text.trim_start().len();
    let after = &text[start..];
    let hashes = after.chars().take_while(|&c| c == '#').count();
    if (1..=6).contains(&hashes) {
        let spaced = after[hashes..].len() - after[hashes..].trim_start().len();
        if spaced > 0 {
            return start + hashes + spaced;
        }
    }
    start
}

/// Every blank in `text` (core/blanks.ts `BLANK`): `{?question}`, not after `{`, `\` or `$`, not `{??`, the
/// question at most 160 characters with no `{`, `}`, `|` or newline, and not closed by `}}`. As (from, to, question).
fn blanks_in(text: &str) -> Vec<(usize, usize, String)> {
    let bytes = text.as_bytes();
    let mut found = Vec::new();
    let mut i = 0;
    while let Some(off) = text[i..].find("{?") {
        let from = i + off;
        i = from + 2;
        if from > 0 && matches!(bytes[from - 1], b'{' | b'\\' | b'$') {
            continue;
        }
        if bytes.get(from + 2) == Some(&b'?') {
            continue;
        }
        let body = &text[from + 2..];
        let Some(end) = body.find(['{', '}', '|', '\n']) else { continue };
        if !body[end..].starts_with('}') || body[..end].chars().count() > 160 {
            continue;
        }
        let to = from + 2 + end + 1;
        if bytes.get(to) == Some(&b'}') {
            continue;
        }
        found.push((from, to, body[..end].to_string()));
        i = to;
    }
    found
}

/// The page's `asksForTitle`: an empty question, or one of the few ways people ask for a title.
fn asks_for_title(question: &str) -> bool {
    let words = question.trim().trim_end_matches(['?', '.', '!']).trim().to_lowercase();
    if words.is_empty() {
        return true;
    }
    let bare = words.strip_prefix("a ").or_else(|| words.strip_prefix("the ")).unwrap_or(&words);
    let noun = ["title", "name", "heading"];
    for n in noun {
        if bare == n {
            return true;
        }
        if let Some(tail) = bare.strip_prefix(n).and_then(|t| t.strip_prefix(' ')) {
            if ["this", "it", "for this", "for it"].contains(&tail) {
                return true;
            }
        }
    }
    matches!(words.as_str(), "title this" | "title it" | "name this" | "name it" | "what to call this" | "what to call it")
}

/// The page's `plainFills`: each filled answer, `??words??(bracket)`, as its words where the bracket reads as a fill
/// (`is_filled`); one that doesn't stays as it is written.
fn plain_fills(text: &str) -> String {
    if !text.contains("??(") {
        return text.to_string();
    }
    let mut out = String::with_capacity(text.len());
    let mut at = 0;
    while let Some(off) = text[at..].find("??") {
        let open = at + off;
        let words_start = open + 2;
        let Some(close_off) = text[words_start..].find("??") else { break };
        let words_end = words_start + close_off;
        let words = &text[words_start..words_end];
        let after = &text[words_end + 2..];
        let ok_words = !words.is_empty() && !words.starts_with(char::is_whitespace) && !words.ends_with(char::is_whitespace) && !words.contains('\n');
        if ok_words && after.starts_with('(') {
            if let Some(end) = after[1..].find([')', '\n']) {
                if after[1 + end..].starts_with(')') && end > 0 {
                    let bracket = &after[1..1 + end];
                    if is_filled(bracket) {
                        out.push_str(&text[at..open]);
                        out.push_str(words);
                        at = words_end + 2 + 1 + end + 1;
                        continue;
                    }
                }
            }
        }
        out.push_str(&text[at..words_start]);
        at = words_start;
    }
    out.push_str(&text[at..]);
    out
}

/// The page's `FILLED`: "<model> from <memory | this note | Source[ and Source]>, <YYYY-MM-DD>", then an optional
/// ". Asked: <question>" and an optional ". <n> of <m>".
fn is_filled(bracket: &str) -> bool {
    let b = bracket.trim();
    let mut search = 0;
    while let Some(off) = b[search..].find(" from ") {
        let at = search + off;
        search = at + 1;
        if at == 0 {
            continue;
        }
        let rest = &b[at + " from ".len()..];
        let Some(comma) = rest.find(", ") else { continue };
        let source = &rest[..comma];
        if !(source == "memory" || source == "this note" || is_source(source)) {
            continue;
        }
        let tail = &rest[comma + 2..];
        if tail.len() < 10 || !is_date(&tail[..10]) {
            continue;
        }
        if fill_tail(&tail[10..]) {
            return true;
        }
    }
    false
}

/// A source's name, or two joined by " and ": a capital, then letters, digits, `_`, `.` or `-`.
fn is_source(source: &str) -> bool {
    let one = |name: &str| {
        let mut chars = name.chars();
        chars.next().is_some_and(|c| c.is_ascii_uppercase()) && chars.all(|c| c.is_alphanumeric() || matches!(c, '_' | '.' | '-'))
    };
    match source.split_once(" and ") {
        Some((a, b)) => one(a) && one(b),
        None => one(source),
    }
}

fn is_date(text: &str) -> bool {
    let b = text.as_bytes();
    b.len() == 10 && b[4] == b'-' && b[7] == b'-' && b.iter().enumerate().all(|(i, c)| i == 4 || i == 7 || c.is_ascii_digit())
}

/// What may follow a fill's date, as the page's `(?:\. Asked: (.+?))?(?:\. (\d) of (\d))?$` takes it: nothing, a
/// place (". 2 of 3"), or ". Asked: " and a question of any words, a place after it or not.
fn fill_tail(tail: &str) -> bool {
    let b = tail.as_bytes();
    let place = tail.len() == 8 && tail.starts_with(". ") && b[2].is_ascii_digit() && &tail[3..7] == " of " && b[7].is_ascii_digit();
    tail.is_empty() || place || tail.strip_prefix(". Asked: ").is_some_and(|question| !question.is_empty())
}

/// The most lines front matter may take, both fences included: the page's
/// `FRONT_MATTER_LINES`. A `---` further down is a rule in a long note.
const FRONT_MATTER_LINES: usize = 40;

/// The page's `withoutFrontMatter`: the `title:` of the body's front matter,
/// its quotes taken off, where it has a title with words in it, and the lines
/// after the block (every line where there is no block).
fn without_front_matter<'a>(lines: &'a [&'a str]) -> (Option<String>, &'a [&'a str]) {
    let end = front_matter_end(lines);
    if end == 0 {
        return (None, lines);
    }
    let named = lines[1..end - 1].iter().find_map(|line| title_value(line)).filter(|title| !title.is_empty());
    (named, &lines[end..])
}

/// The page's `frontMatterEnd` (core/frontMatter.ts): the index of the line
/// after the closing fence, or 0 where there is no front matter. That is a
/// fence (`---` or `+++`) on the first line, then only `key:` lines and blank
/// ones, then a fence within the first 40 lines. A note that opens with a
/// rule and some words opens with a rule. The file's own front matter is read
/// by another rule (frontmatter.rs `split`), which the page never sees.
fn front_matter_end(lines: &[&str]) -> usize {
    if !lines.first().is_some_and(|line| is_fence(line)) {
        return 0;
    }
    for (n, line) in lines.iter().enumerate().take(FRONT_MATTER_LINES).skip(1) {
        if is_fence(line) {
            return n + 1;
        }
        if !is_key_line(line) && !line.trim().is_empty() {
            return 0;
        }
    }
    0
}

/// A front matter fence on a line of its own: the page's `FENCE`.
fn is_fence(line: &str) -> bool {
    matches!(line.trim_end(), "---" | "+++")
}

/// A `key:` line: the page's `KEY_LINE`, a key of ASCII letters, digits, `_`,
/// `.` and `-`, with space allowed before it and before its colon.
fn is_key_line(line: &str) -> bool {
    let rest = line.trim_start();
    let key = rest.len() - rest.trim_start_matches(|c: char| c.is_ascii_alphanumeric() || matches!(c, '_' | '.' | '-')).len();
    key > 0 && rest[key..].trim_start().starts_with(':')
}

/// A `title:` line's value, as `withoutFrontMatter` reads it: the key in any
/// case, a quote off each end, then trimmed. None for any other key.
fn title_value(line: &str) -> Option<String> {
    let rest = line.trim_start();
    let key = rest.get(..5).filter(|key| key.eq_ignore_ascii_case("title"))?;
    let value = rest[key.len()..].trim_start().strip_prefix(':')?.trim_start();
    let value = value.strip_prefix(['"', '\'']).unwrap_or(value);
    let value = value.strip_suffix(['"', '\'']).unwrap_or(value);
    Some(value.trim().to_string())
}

/// A line's words without its Markdown: a heading's `#`s, a quote's `>`, a
/// list's or task's marker, a link's address (its words stay), a picture,
/// emphasis and code marks, and bare addresses. "- [ ] [Buy milk](https://…)
/// on the way home" is "Buy milk on the way home".
fn plain(line: &str) -> String {
    let mut text = line.trim_start_matches('#').trim_start().to_string();
    loop {
        let trimmed = text.trim_start();
        let next = trimmed
            .strip_prefix("> ")
            .or_else(|| trimmed.strip_prefix("- [ ] "))
            .or_else(|| trimmed.strip_prefix("- [x] "))
            .or_else(|| trimmed.strip_prefix("- [X] "))
            .or_else(|| trimmed.strip_prefix("- "))
            .or_else(|| trimmed.strip_prefix("* "))
            .or_else(|| trimmed.strip_prefix("+ "))
            .map(str::to_string)
            .or_else(|| {
                let digits = trimmed.chars().take_while(char::is_ascii_digit).count();
                (digits > 0 && digits < 4).then(|| trimmed[digits..].strip_prefix(". ").or_else(|| trimmed[digits..].strip_prefix(") ")).map(str::to_string)).flatten()
            });
        match next {
            Some(rest) => text = rest,
            None => break,
        }
    }
    let mut out = String::with_capacity(text.len());
    let chars: Vec<char> = text.chars().collect();
    let mut i = 0;
    while i < chars.len() {
        let c = chars[i];
        // `![alt](src)` goes; `[words](href)` keeps its words.
        if c == '[' || (c == '!' && chars.get(i + 1) == Some(&'[')) {
            let open = if c == '!' { i + 1 } else { i };
            if let Some(close) = (open + 1..chars.len()).find(|&j| chars[j] == ']') {
                if chars.get(close + 1) == Some(&'(') {
                    if let Some(end) = (close + 2..chars.len()).find(|&j| chars[j] == ')') {
                        let words: String = chars[open + 1..close].iter().collect();
                        // An item's mark (`[notion](…)` at its end, docs/LIBRARY.md) names a plugin, not the note.
                        let mark = chars[end + 1..].iter().all(|ch| ch.is_whitespace()) && !words.is_empty() && words.chars().all(|ch| ch.is_ascii_lowercase() || ch.is_ascii_digit() || ch == '-');
                        if c != '!' && !mark {
                            out.push_str(&words);
                        }
                        i = end + 1;
                        continue;
                    }
                }
            }
        }
        if matches!(c, '*' | '_' | '`' | '~') {
            i += 1;
            continue;
        }
        out.push(c);
        i += 1;
    }
    out.split_whitespace()
        .filter(|word| !is_link(word))
        .collect::<Vec<_>>()
        .join(" ")
}

/// A bare address or an autolink (`<…>`), which says nothing a file name wants.
fn is_link(word: &str) -> bool {
    word.starts_with("http://") || word.starts_with("https://") || (word.starts_with('<') && word.ends_with('>'))
}

fn is_picture_line(line: &str) -> bool {
    line.starts_with("![") && line.ends_with(')') && line.contains("](")
}

/// Most characters a file name keeps: long titles are cut at a word.
const MAX_STEM: usize = 80;

/// A title as a file name without its extension. Characters Windows, Android
/// or a sync service refuse are dropped, markdown emphasis goes, runs of space
/// shrink to one, and a trailing dot or space is trimmed (Windows can't hold
/// one). An empty result is "Untitled".
pub fn file_stem(title: &str) -> String {
    let cleaned: String = title
        .chars()
        .filter(|c| !matches!(c, '/' | '\\' | ':' | '*' | '?' | '"' | '<' | '>' | '|' | '#' | '^' | '[' | ']') && !c.is_control())
        .collect::<String>()
        .replace("**", "")
        .replace("__", "");
    let mut stem = cleaned.split_whitespace().collect::<Vec<_>>().join(" ");
    if stem.chars().count() > MAX_STEM {
        let cut: String = stem.chars().take(MAX_STEM).collect();
        stem = match cut.rfind(' ') {
            Some(at) if at > MAX_STEM / 2 => cut[..at].to_string(),
            _ => cut,
        };
    }
    let stem = stem.trim_end_matches(['.', ' ']).trim_start_matches('.').trim().to_string();
    if stem.is_empty() { "Untitled".to_string() } else { stem }
}

/// The first of `Stem.md`, `Stem 2.md`, `Stem 3.md` … that `taken` says is free.
pub fn unique_name(stem: &str, mut taken: impl FnMut(&str) -> bool) -> String {
    let first = format!("{stem}.md");
    if !taken(&first) {
        return first;
    }
    (2..)
        .map(|n| format!("{stem} {n}.md"))
        .find(|name| !taken(name))
        .expect("an unbounded range finds a free name")
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The page's rows (core/titles.fixture.json): a note that is only that line is titled the same here as in the list.
    #[test]
    fn blanks_and_fills_title_a_note_as_the_page_titles_it() {
        let fixture: serde_json::Value = serde_json::from_str(include_str!("../../../src/app/core/titles.fixture.json")).unwrap();
        for row in fixture["rows"].as_array().unwrap() {
            let line = row["line"].as_str().unwrap();
            assert_eq!(title_of(line), row["title"].as_str().unwrap(), "{line}");
        }
    }

    #[test]
    fn a_blank_not_closed_as_one_or_a_bracket_that_is_no_fill_stays_as_written() {
        assert_eq!(title_of("# Plan {?{nested}}"), "Plan {?{nested}}");
        assert_eq!(title_of("# Price ??ten??(maybe less)"), "Price ??ten??(maybe less)");
        assert_eq!(title_of("# Visit ??Kyoto??(Qwen3.5 4B from Wikipedia and OSM, 2026-10-01. Asked: old capital. 2 of 3)"), "Visit Kyoto");
        assert_eq!(title_of("{?name this}"), "");
        assert_eq!(title_of("# {?title}\nSecond line"), "");
    }

    #[test]
    fn the_title_is_the_first_line_of_words() {
        assert_eq!(title_of("\n![](image/a.jpg)\n# AttackFM bug bash\n\nFriday."), "AttackFM bug bash");
        assert_eq!(title_of("Call Sam about the cabin\nmore"), "Call Sam about the cabin");
        assert_eq!(title_of("   \n"), "");
    }

    #[test]
    fn the_title_drops_markdown_so_the_file_name_is_words() {
        assert_eq!(title_of("- [ ] [Buy milk](https://www.notion.so/attackfm/Buy-milk-1a2b) on the way home"), "Buy milk on the way home");
        assert_eq!(title_of("> **Bold** idea with `code` and ~~old~~"), "Bold idea with code and old");
        assert_eq!(title_of("1. First step <https://x.y> see https://example.com"), "First step see");
        assert_eq!(file_stem(&title_of("- [ ] buy milk [notion](https://www.notion.so/x)")), "buy milk", "a trailing item mark is not part of the name");
    }

    #[test]
    fn front_matter_in_the_body_is_skipped_and_its_title_taken() {
        // A book (book/book.ts `bookNoteBody`), named by its `title:` out of its quotes.
        assert_eq!(title_of("---\ntitle: \"My book\"\nbook: true\n---\n# My book\n\n- [[Chapter one]]\n"), "My book");
        assert_eq!(file_stem(&title_of("---\nbook: true\ntitle: My book\n---\n\nIntro")), "My book", "the book that was filed as ---.md");
        // A canvas (canvas/jsonCanvas.ts `canvasNoteBody`), whose words open with `{`.
        let canvas = "---\ntitle: \"Cabin plan: the weekend\"\n---\n{\n  \"nodes\": [],\n  \"edges\": []\n}\n";
        assert_eq!(file_stem(&title_of(canvas)), "Cabin plan the weekend");
        // A note an AI signed (core/authors.ts `withAuthor`): no `title:`, so its first line of words.
        assert_eq!(title_of("---\nauthors: Matt, Claude\n---\n# Weekend trip\n\nBook the cabin."), "Weekend trip");
        assert_eq!(title_of("---\ntitle: \"\"\nbook: true\n---\n# Reading list"), "Reading list", "an empty title is no title");
        // A note tagged where it was written (core/geotag.ts `withGeoTag`), which every new note is by default.
        assert_eq!(title_of("---\nlocation: 51.5074,-0.1278\nplace: \"Trafalgar Square, London\"\n---\n# Groceries\n\n- [ ] Oat milk\n"), "Groceries");
    }

    #[test]
    fn a_rule_and_some_words_are_not_front_matter() {
        // Words between the fences make the first `---` a rule, even after a line that looks like a key. The note is
        // titled by its first line, as the page's list titles it, not by what follows the second rule.
        assert_eq!(title_of("---\nNote: the cabin is booked\nand the car is not\n---\nPack on Thursday."), "---");
        // A close within the first 40 lines ends the keys; one further down is a rule in a long note.
        let keys = |n: usize| format!("---\n{}---\nWords", "key: value\n".repeat(n));
        assert_eq!(title_of(&keys(38)), "Words");
        assert_eq!(title_of(&keys(39)), "---");
    }

    #[test]
    fn a_title_becomes_a_safe_file_name() {
        assert_eq!(file_stem("Bugs: the **big** list / v2?"), "Bugs the big list v2");
        assert_eq!(file_stem("..."), "Untitled");
        assert_eq!(file_stem("Ends with a dot."), "Ends with a dot");
        let long = "word ".repeat(40);
        let stem = file_stem(&long);
        assert!(stem.chars().count() <= MAX_STEM && !stem.ends_with(' '));
    }

    #[test]
    fn a_clash_gets_a_number() {
        let taken = ["Weekend trip.md", "Weekend trip 2.md"];
        assert_eq!(unique_name("Weekend trip", |n| taken.contains(&n)), "Weekend trip 3.md");
        assert_eq!(unique_name("New", |_| false), "New.md");
    }
}
