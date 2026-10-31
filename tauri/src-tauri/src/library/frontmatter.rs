//! A note's front matter: the YAML block at the top of the file, as Obsidian's
//! Properties write it (docs/LIBRARY.md).
//!
//! Not a YAML library, on purpose. A library would parse the block into values
//! and write it back out in its own style: reordered keys, requoted strings,
//! comments gone. That rewrites a person's file every time Glyph pins a note.
//! This keeps the block as its lines. Reading picks out the few top-level keys
//! Glyph knows (plain, quoted, `true`/`false`, `[flow, lists]` and `- block`
//! lists). Writing replaces only the lines of a key whose value changes, and
//! appends a key that wasn't there. Everything else (unknown keys, nested maps,
//! comments, blank lines, the person's quoting) comes back byte for byte.
//!
//! Two shapes of file (docs/MARKDOWN_FIRST.md §11, Matt, 2026-10-31: "one block,
//! phased"). Until now a note with page properties was written as TWO blocks:
//! the library's (`LIBRARY_KEYS`), then the page's (`type: ticket`, `status:`,
//! `due:` ...), which the Dart side writes at the top of the body. Other apps
//! write ONE block with every key in it, and that is where Ghost.md is going.
//! `read` takes a file in either shape to the same two things, the library's
//! block and the page's body (a body that opens with the page's own block, as
//! the Dart side has always seen it), and `write` puts them back in the shape
//! the file had: a one-block file stays one block, a two-block file stays two
//! until `ONE_BLOCK` is on. Off, nothing writes a one-block file that wasn't
//! one already; it goes on a release after every device reads both shapes.

/// The keys the library manages, which are never the page's: a one-block file
/// has them beside the page's keys, and `read` takes them out of the body.
/// mod.rs `MANAGED_KEYS` (the seven written today, `recording-ms` the newest:
/// a recording's length, mod.rs `set_recording`) and `trashed`, the trash's; the
/// Dart side's `libraryKeys` (lib/core/front_matter.dart) is this list.
pub const LIBRARY_KEYS: &[&str] = &["id", "created", "updated", "source", "pinned", "archived", "trashed", "recording-ms"];

/// Whether writers merge the library's keys into the page's block (one `---`
/// block in the file) rather than writing a block of their own above it. OFF:
/// it goes on a release after every device reads both shapes
/// (docs/MARKDOWN_FIRST.md §9 slice 7). Tests set it either way with
/// `one_block_for_test`.
pub const ONE_BLOCK: bool = false;

#[cfg(test)]
thread_local! {
    static ONE_BLOCK_OVERRIDE: std::cell::Cell<Option<bool>> = const { std::cell::Cell::new(None) };
}

/// `ONE_BLOCK`, or what a test on this thread set it to.
pub fn one_block() -> bool {
    #[cfg(test)]
    if let Some(set) = ONE_BLOCK_OVERRIDE.with(|cell| cell.get()) {
        return set;
    }
    ONE_BLOCK
}

/// Sets `one_block` for the rest of this test thread.
#[cfg(test)]
pub fn one_block_for_test(on: bool) {
    ONE_BLOCK_OVERRIDE.with(|cell| cell.set(Some(on)));
}

/// Whether `text` is a ticket's key, `GHO-12`: a letter, one to nine more
/// letters or digits, a dash and a number of up to six figures, in any case
/// (lib/core/properties.dart `issueKey`). A one-block ticket written by hand
/// may say `id: GHO-12`, and that `id` is the page's, not the library's.
pub fn is_issue_key(text: &str) -> bool {
    let text = text.trim();
    let Some((prefix, number)) = text.split_once('-') else { return false };
    let mut prefix = prefix.chars();
    let starts = prefix.next().is_some_and(|c| c.is_ascii_alphabetic());
    let rest: Vec<char> = prefix.collect();
    starts
        && (1..=9).contains(&rest.len())
        && rest.iter().all(|c| c.is_ascii_alphanumeric())
        && (1..=6).contains(&number.len())
        && number.starts_with(|c: char| ('1'..='9').contains(&c))
        && number.chars().all(|c| c.is_ascii_digit())
}

/// A value Glyph reads or writes.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Value {
    Text(String),
    Bool(bool),
    List(Vec<String>),
}

/// The block's lines, without the `---` fences.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct FrontMatter {
    lines: Vec<String>,
}

/// A file split into its front matter (if it has one) and its body.
///
/// A block is only front matter when the file STARTS with `---` on its own line
/// and a closing `---` (or `...`) follows. A `---` further down is a
/// thematic break in the body, not metadata.
pub fn split(text: &str) -> (Option<FrontMatter>, &str) {
    let rest = text.strip_prefix('\u{feff}').unwrap_or(text);
    let Some(after) = rest.strip_prefix("---\n").or_else(|| rest.strip_prefix("---\r\n")) else {
        return (None, text);
    };
    let mut offset = 0;
    for line in after.split_inclusive('\n') {
        let bare = line.trim_end_matches(['\n', '\r']);
        if bare == "---" || bare == "..." {
            let block = &after[..offset];
            let body = &after[offset + line.len()..];
            let lines = block.split('\n').map(|l| l.trim_end_matches('\r').to_string()).collect::<Vec<_>>();
            // `split` leaves an empty last piece after the final newline; it isn't a line.
            let lines = match lines.last() {
                Some(last) if last.is_empty() && block.ends_with('\n') => lines[..lines.len() - 1].to_vec(),
                _ => lines,
            };
            return (Some(FrontMatter { lines }), body);
        }
        offset += line.len();
    }
    (None, text)
}

/// The front matter and body joined back into a file. No front matter, or an empty one, is no block.
pub fn join(front: Option<&FrontMatter>, body: &str) -> String {
    match front {
        Some(front) if !front.is_empty() => format!("---\n{}\n---\n{}", front.lines.join("\n"), body),
        _ => body.to_string(),
    }
}

/// A top-level key on this line, if it starts one: `key:` at column 0, not a comment or list item.
fn key_of(line: &str) -> Option<&str> {
    if line.starts_with([' ', '\t', '#', '-']) || line.is_empty() {
        return None;
    }
    let colon = line.find(':')?;
    let key = line[..colon].trim();
    let after = &line[colon + 1..];
    (!key.is_empty() && (after.is_empty() || after.starts_with([' ', '\t']))).then_some(key)
}

fn unquote(raw: &str) -> String {
    let raw = raw.trim();
    if raw.len() >= 2 && ((raw.starts_with('"') && raw.ends_with('"')) || (raw.starts_with('\'') && raw.ends_with('\''))) {
        let inner = &raw[1..raw.len() - 1];
        return if raw.starts_with('"') { inner.replace("\\\"", "\"").replace("\\\\", "\\") } else { inner.replace("''", "'") };
    }
    raw.to_string()
}

/// A scalar's text with a trailing `# comment` gone (only outside quotes).
fn without_comment(raw: &str) -> &str {
    let trimmed = raw.trim_start();
    if trimmed.starts_with('"') || trimmed.starts_with('\'') {
        return raw;
    }
    match raw.find(" #") {
        Some(at) => &raw[..at],
        None => raw,
    }
}

fn needs_quotes(text: &str) -> bool {
    text.is_empty()
        || text.trim() != text
        || text.contains(": ")
        || text.contains(" #")
        || text.starts_with(['[', ']', '{', '}', '#', '&', '*', '!', '|', '>', '\'', '"', '%', '@', '`', '-', '?', ','])
        || matches!(text.to_ascii_lowercase().as_str(), "true" | "false" | "yes" | "no" | "null" | "~")
}

fn render_text(text: &str) -> String {
    if needs_quotes(text) {
        format!("\"{}\"", text.replace('\\', "\\\\").replace('"', "\\\""))
    } else {
        text.to_string()
    }
}

impl FrontMatter {
    pub fn new() -> FrontMatter {
        FrontMatter::default()
    }

    /// Where `key`'s lines are: its own line, and any indented or `- item` lines under it.
    fn span(&self, key: &str) -> Option<(usize, usize)> {
        let start = self.lines.iter().position(|line| key_of(line) == Some(key))?;
        let mut end = start + 1;
        while end < self.lines.len() && key_of(&self.lines[end]).is_none() && !self.lines[end].is_empty() && (self.lines[end].starts_with([' ', '\t', '-'])) {
            end += 1;
        }
        Some((start, end))
    }

    /// The value of a top-level key Glyph can read, or None (absent, empty, or a shape it doesn't read).
    pub fn get(&self, key: &str) -> Option<Value> {
        let (start, end) = self.span(key)?;
        let line = &self.lines[start];
        let raw = without_comment(&line[line.find(':')? + 1..]).trim();
        if raw.is_empty() {
            let items: Vec<String> = self.lines[start + 1..end]
                .iter()
                .filter_map(|l| l.trim_start().strip_prefix('-').map(|item| unquote(without_comment(item))))
                .filter(|item| !item.is_empty())
                .collect();
            return (!items.is_empty()).then_some(Value::List(items));
        }
        if raw.starts_with('[') && raw.ends_with(']') {
            let items = raw[1..raw.len() - 1].split(',').map(unquote).filter(|item| !item.is_empty()).collect();
            return Some(Value::List(items));
        }
        match raw {
            "true" | "True" | "TRUE" => Some(Value::Bool(true)),
            "false" | "False" | "FALSE" => Some(Value::Bool(false)),
            _ => Some(Value::Text(unquote(raw))),
        }
    }

    pub fn text(&self, key: &str) -> Option<String> {
        match self.get(key)? {
            Value::Text(text) => Some(text),
            Value::Bool(b) => Some(b.to_string()),
            Value::List(_) => None,
        }
    }

    pub fn flag(&self, key: &str) -> bool {
        matches!(self.get(key), Some(Value::Bool(true)))
    }

    /// Sets a key, or removes it with None. A key whose value is already this is left exactly as written.
    pub fn set(&mut self, key: &str, value: Option<Value>) {
        if self.get(key) == value && (value.is_some() || self.span(key).is_none()) {
            return;
        }
        let rendered = value.map(|value| match value {
            Value::Text(text) => vec![format!("{key}: {}", render_text(&text))],
            Value::Bool(b) => vec![format!("{key}: {b}")],
            Value::List(items) if items.is_empty() => vec![format!("{key}: []")],
            Value::List(items) => vec![format!("{key}: [{}]", items.iter().map(|i| render_text(i)).collect::<Vec<_>>().join(", "))],
        });
        match (self.span(key), rendered) {
            (Some((start, end)), Some(lines)) => {
                self.lines.splice(start..end, lines);
            }
            (Some((start, end)), None) => {
                self.lines.drain(start..end);
            }
            (None, Some(lines)) => self.lines.extend(lines),
            (None, None) => {}
        }
    }

    /// Whether the block holds nothing but blank lines, which `join` leaves out.
    pub fn is_empty(&self) -> bool {
        self.lines.iter().all(|l| l.trim().is_empty())
    }

    /// Whether every line is one of `keys` set on one line: nothing else, no
    /// list below a key, no comment the person wrote.
    pub fn only(&self, keys: &[&str]) -> bool {
        self.lines.iter().filter(|l| !l.trim().is_empty()).all(|l| {
            !l.starts_with([' ', '\t', '#']) && l.split_once(':').is_some_and(|(key, _)| keys.contains(&key.trim()))
        })
    }

    /// Whether the key starting on line `at` is the library's (`LIBRARY_KEYS`):
    /// an `id` whose value is a ticket's key is the page's.
    fn library_key_at(&self, at: usize) -> bool {
        let Some(key) = key_of(&self.lines[at]) else { return false };
        if !LIBRARY_KEYS.contains(&key) {
            return false;
        }
        key != "id" || !self.text("id").is_some_and(|id| is_issue_key(&id))
    }

    /// The block in two: the library's lines (its keys' spans, and every line
    /// that is no page key's: comments, blank lines) and the page's (the spans
    /// of every other key). A two-block file's first block is all library.
    fn parted(&self) -> (FrontMatter, FrontMatter) {
        let mut library = Vec::new();
        let mut page = Vec::new();
        let mut at = 0;
        while at < self.lines.len() {
            let Some(key) = key_of(&self.lines[at]) else {
                library.push(self.lines[at].clone());
                at += 1;
                continue;
            };
            let (start, end) = self.span(key).unwrap_or((at, at + 1));
            let (start, end) = if start == at { (start, end) } else { (at, at + 1) };
            let into = if self.library_key_at(at) { &mut library } else { &mut page };
            into.extend(self.lines[start..end].iter().cloned());
            at = end;
        }
        (FrontMatter { lines: library }, FrontMatter { lines: page })
    }

    /// The page's keys in this block, as a block of their own: empty for the
    /// library's own block of a two-block file, and for one with nothing but the
    /// library's keys and the person's comments.
    pub fn page(&self) -> FrontMatter {
        self.parted().1
    }

    /// Whether the block holds a key of the page's: the mark of a one-block file.
    pub fn has_page_keys(&self) -> bool {
        self.page().lines.iter().any(|line| key_of(line).is_some())
    }

    /// This block with the page's keys made `page`'s: as it stands where they
    /// already are (so an unchanged page writes the file back byte for byte),
    /// else the library's lines in their order and the page's after them.
    pub fn with_page(&self, page: Option<&FrontMatter>) -> FrontMatter {
        let (library, had) = self.parted();
        let wanted = page.map(|page| self.page_lines_for(page)).unwrap_or_default();
        if had.lines == wanted {
            return self.clone();
        }
        FrontMatter { lines: library.lines.into_iter().chain(wanted).collect() }
    }

    /// `page`'s lines as one block can hold them beside the library's. The one
    /// `id:` of a block the library has claimed is the library's, so a page's
    /// `id: GHO-12` (the ticket key the Dart side still writes, until every
    /// device reads `issue:`) is written `issue: GHO-12`, the key other tools
    /// use, or left out where the page says `issue:` already. A block with no
    /// library id yet takes the page's lines as they are.
    fn page_lines_for(&self, page: &FrontMatter) -> Vec<String> {
        let claimed = self.text("id").is_some_and(|id| !is_issue_key(&id));
        let tickets = page.text("id").is_some_and(|id| is_issue_key(&id));
        if !claimed || !tickets {
            return page.lines.clone();
        }
        let has_issue = page.get("issue").is_some();
        let mut lines = Vec::with_capacity(page.lines.len());
        for line in &page.lines {
            if key_of(line) == Some("id") {
                if let Some(colon) = line.find(':').filter(|_| !has_issue) {
                    lines.push(format!("issue:{}", &line[colon + 1..]));
                }
                continue;
            }
            lines.push(line.clone());
        }
        lines
    }

    /// Gives the library's `id` to this block. A one-block ticket written by
    /// hand may hold its own `id: GHO-12`: that moves to `issue:`, the key
    /// other tools use and every reader of ours reads too, so the library's id
    /// doesn't take the ticket's.
    pub fn claim_id(&mut self, id: &str) {
        if let Some(had) = self.text("id").filter(|had| is_issue_key(had)) {
            if self.get("issue").is_none() {
                self.set("issue", Some(Value::Text(had)));
            }
        }
        self.set("id", Some(Value::Text(id.to_string())));
    }
}

/// A file in either shape read to the library's block and the page's body: the
/// body the Dart side sees opens with the page's own block where the file has
/// page keys, wherever the file keeps them. A two-block file reads as it always
/// did (its first block, then the rest). A one-block file's page keys are taken
/// out as a block at the top of the body; a first block with page keys that a
/// second block follows (a file no app writes) is read as both blocks' page keys
/// in one, and written back as one.
pub fn read(text: &str) -> (FrontMatter, String) {
    let (front, rest) = split(text);
    let front = front.unwrap_or_default();
    if !front.has_page_keys() {
        return (front, rest.to_string());
    }
    let mut page = front.page();
    let (second, rest) = match split(rest) {
        (Some(second), after) => (Some(second), after),
        (None, _) => (None, rest),
    };
    if let Some(second) = second {
        page.lines.extend(second.lines);
    }
    (front, join(Some(&page), rest))
}

/// The file written from the library's block and the page's body, in the shape
/// the file had: a one-block file (a block with page keys) takes the body's
/// block into its own, a two-block file keeps the body's block as the second,
/// and with `one_block()` on every file is written as one. Nothing of the
/// person's goes: the library's lines keep their order and their comments.
pub fn write(front: &FrontMatter, body: &str) -> String {
    if !one_block() && !front.has_page_keys() {
        return join(Some(front), body);
    }
    let (page, rest) = split(body);
    join(Some(&front.with_page(page.as_ref())), rest)
}

#[cfg(test)]
mod tests {
    use super::*;

    const OBSIDIAN: &str = "---\nid: 7c1e\ncreated: 2026-09-14T10:32:10.123Z\n# a comment the person wrote\ntags:\n  - bugbash\n  - \"android\"\naliases: [Bug bash, 'The bash']\ncover:\n  image: a.png\n  alt: A picture\npinned: true\n---\n# AttackFM\n\n---\n\nA break above.\n";

    #[test]
    fn reads_the_keys_obsidian_writes() {
        let (front, body) = split(OBSIDIAN);
        let front = front.expect("front matter");
        assert_eq!(front.text("id").as_deref(), Some("7c1e"));
        assert_eq!(front.get("tags"), Some(Value::List(vec!["bugbash".into(), "android".into()])));
        assert_eq!(front.get("aliases"), Some(Value::List(vec!["Bug bash".into(), "The bash".into()])));
        assert!(front.flag("pinned"));
        assert_eq!(front.get("cover"), None, "a nested map isn't a shape Glyph reads");
        assert!(body.starts_with("# AttackFM\n\n---\n"), "a later --- is the body's thematic break");
    }

    #[test]
    fn writing_changes_only_the_keys_that_changed_and_keeps_everything_else() {
        let (front, body) = split(OBSIDIAN);
        let mut front = front.unwrap();
        front.set("pinned", Some(Value::Bool(true)));
        assert_eq!(join(Some(&front), body), OBSIDIAN, "setting a value it already has rewrites nothing");
        front.set("pinned", None);
        front.set("archived", Some(Value::Text("2026-09-15T08:00:00.000Z".into())));
        front.set("tags", Some(Value::List(vec!["bugbash".into()])));
        let out = join(Some(&front), body);
        assert!(out.contains("# a comment the person wrote\ntags: [bugbash]\naliases: [Bug bash, 'The bash']\ncover:\n  image: a.png\n  alt: A picture\n"));
        assert!(!out.contains("pinned"));
        assert!(out.contains("archived: 2026-09-15T08:00:00.000Z\n---\n# AttackFM"));
    }

    #[test]
    fn a_file_without_front_matter_is_all_body_and_gets_a_block_only_when_needed() {
        let (front, body) = split("# Plain\n\n---\nnot metadata\n");
        assert!(front.is_none());
        assert_eq!(body, "# Plain\n\n---\nnot metadata\n");
        assert_eq!(join(Some(&FrontMatter::new()), body), body);
        let mut fresh = FrontMatter::new();
        fresh.set("id", Some(Value::Text("n1".into())));
        assert_eq!(join(Some(&fresh), "# Plain\n"), "---\nid: n1\n---\n# Plain\n");
    }

    #[test]
    fn quotes_what_yaml_would_misread() {
        let mut front = FrontMatter::new();
        front.set("notion-board", Some(Value::Text("https://www.notion.so/abc".into())));
        front.set("title", Some(Value::Text("Bugs: the list".into())));
        front.set("answer", Some(Value::Text("yes".into())));
        let out = join(Some(&front), "");
        assert!(out.contains("notion-board: https://www.notion.so/abc\n"));
        assert!(out.contains("title: \"Bugs: the list\"\n"));
        assert!(out.contains("answer: \"yes\"\n"));
        let (again, _) = split(&out);
        assert_eq!(again.unwrap().text("title").as_deref(), Some("Bugs: the list"));
    }

    const ONE_BLOCK_FILE: &str = "---\nstatus: To do\nid: 7c1e\n# the person's comment\ntags:\n  - bugbash\ncreated: 2026-09-14T10:32:10.123Z\ntype: ticket\npinned: true\n---\n# Loop\n\nIt loops.\n";
    const TWO_BLOCK_FILE: &str = "---\nid: 7c1e\ncreated: 2026-09-14T10:32:10.123Z\n---\n---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Loop\n";

    #[test]
    fn a_one_block_file_reads_as_the_librarys_block_and_the_pages_body() {
        let (front, body) = read(ONE_BLOCK_FILE);
        assert_eq!(front.text("id").as_deref(), Some("7c1e"));
        assert!(front.flag("pinned") && front.has_page_keys());
        assert_eq!(body, "---\nstatus: To do\ntags:\n  - bugbash\ntype: ticket\n---\n# Loop\n\nIt loops.\n", "the page's keys with their lists, in their order; the comment stays the library's");
        assert_eq!(write(&front, &body), ONE_BLOCK_FILE, "an unchanged page writes the file back byte for byte");
        let (two_front, two_body) = read(TWO_BLOCK_FILE);
        assert!(!two_front.has_page_keys());
        assert_eq!(two_body, "---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Loop\n", "a two-block file reads as it always did");
        assert_eq!(write(&two_front, &two_body), TWO_BLOCK_FILE);
        assert_eq!(read("# Plain\n"), (FrontMatter::new(), "# Plain\n".to_string()));
    }

    #[test]
    fn a_changed_page_is_written_into_the_one_block_and_a_second_block_never_made() {
        let (mut front, body) = read(ONE_BLOCK_FILE);
        front.set("pinned", None);
        let out = write(&front, &body.replace("status: To do", "status: Done"));
        assert_eq!(out, "---\nid: 7c1e\n# the person's comment\ncreated: 2026-09-14T10:32:10.123Z\nstatus: Done\ntags:\n  - bugbash\ntype: ticket\n---\n# Loop\n\nIt loops.\n");
        assert_eq!(write(&front, "# Loop\n"), "---\nid: 7c1e\n# the person's comment\ncreated: 2026-09-14T10:32:10.123Z\n---\n# Loop\n", "every page key taken off leaves the library's");
        // A first block with page keys that a second block follows reads as one page and writes back as one block.
        let (front, body) = read("---\nid: x\ntags: [a]\n---\n---\ntype: ticket\n---\n# Both\n");
        assert_eq!(body, "---\ntags: [a]\ntype: ticket\n---\n# Both\n");
        assert_eq!(write(&front, &body), "---\nid: x\ntags: [a]\ntype: ticket\n---\n# Both\n");
    }

    #[test]
    fn a_tickets_id_is_the_pages_and_gives_way_to_issue_when_the_library_claims_the_line() {
        assert!(is_issue_key("GHO-12") && is_issue_key("gho-1") && is_issue_key(" A1-999999 "));
        assert!(!is_issue_key("7c1e") && !is_issue_key("G-1") && !is_issue_key("GHO-0") && !is_issue_key("GHO-1234567") && !is_issue_key("1A-2") && !is_issue_key("ABCDEFGHIJK-1"));
        let (front, body) = read("---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Loop\n");
        assert_eq!(front.text("id").as_deref(), Some("GHO-12"), "the block still says it");
        assert_eq!(body, "---\ntype: ticket\nid: GHO-12\nstatus: To do\n---\n# Loop\n", "but it is the page's key, not the library's");
        let mut front = front;
        front.claim_id("7c1e");
        assert_eq!(join(Some(&front), ""), "---\ntype: ticket\nid: 7c1e\nstatus: To do\nissue: GHO-12\n---\n", "the line is the library's, the key moved to issue:");
        // The page still says `id: GHO-12` (the key the Dart side writes today): merged into the claimed block it is `issue:`.
        assert_eq!(write(&front, &body), "---\nid: 7c1e\ntype: ticket\nissue: GHO-12\nstatus: To do\n---\n# Loop\n");
        assert_eq!(write(&front, "---\ntype: ticket\nid: GHO-12\nissue: GHO-12\n---\n# Loop\n"), "---\nid: 7c1e\ntype: ticket\nissue: GHO-12\n---\n# Loop\n", "said twice, the id line goes");
        let mut plain = FrontMatter::new();
        plain.set("id", Some(Value::Text("7c1e".into())));
        plain.claim_id("7c1e");
        assert_eq!(plain.get("issue"), None, "a library id is claimed in place");
    }

    #[test]
    fn with_one_block_on_a_two_block_file_is_written_as_one() {
        one_block_for_test(true);
        let (front, body) = read(TWO_BLOCK_FILE);
        assert_eq!(write(&front, &body), "---\nid: 7c1e\ncreated: 2026-09-14T10:32:10.123Z\ntype: ticket\nissue: GHO-12\nstatus: To do\n---\n# Loop\n");
        assert_eq!(write(&front, "# Loop\n"), "---\nid: 7c1e\ncreated: 2026-09-14T10:32:10.123Z\n---\n# Loop\n");
        let mut fresh = FrontMatter::new();
        fresh.set("id", Some(Value::Text("n1".into())));
        assert_eq!(write(&fresh, "---\nbook: true\n---\n# Book\n"), "---\nid: n1\nbook: true\n---\n# Book\n");
        one_block_for_test(false);
        assert_eq!(write(&fresh, "---\nbook: true\n---\n# Book\n"), "---\nid: n1\n---\n---\nbook: true\n---\n# Book\n", "off: two blocks as before");
    }

    #[test]
    fn an_unclosed_block_is_body_and_windows_line_ends_are_read() {
        assert!(split("---\nid: x\nno close\n").0.is_none());
        let (front, body) = split("---\r\nid: w\r\n---\r\nBody\r\n");
        assert_eq!(front.unwrap().text("id").as_deref(), Some("w"));
        assert_eq!(body, "Body\r\n");
    }
}
