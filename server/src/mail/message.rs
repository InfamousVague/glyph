//! A mail as it arrives, raw MIME, turned into what a device files as a note (docs/MAIL.md, "What is sealed"): its
//! subject, who sent it, when, its body as Markdown, and its files - in memory, a moment before it is sealed.
//!
//! The body is the HTML part turned into Markdown when there is one (htmd), else the plain part as it is. Pictures the
//! HTML shows from the mail itself (`cid:`) stay as `![…](cid:…)`, and the device points them at the pictures it keeps.
//! A picture fetched from the web is left out: in a note it would be fetched every time the note is drawn, and a
//! sender's tracking pixel would learn when you read it. A link that runs a script is made inert.
//!
//! What is sealed, `GML1` (the share's `GSP1`, for mail): four magic bytes, the length of the head as four bytes
//! big-endian, the head as JSON, then each file's bytes one after another in the order the head lists them.
//!
//!   { "v": 1, "subject", "from", "to", "date" (ms), "body" (Markdown), "files": [{ "name", "type", "size", "cid" }] }

use mail_parser::{MessageParser, MimeHeaders, PartType};
use serde_json::{json, Value};
use std::borrow::Cow;

pub const MAGIC: &[u8; 4] = b"GML1";
/// The most a body keeps, in bytes of Markdown: a synced note is sealed whole, and the service takes 1.4 MB of it.
const BODY_BYTES: usize = 900_000;
/// The most files one mail keeps.
const FILES: usize = 40;

/// Why a mail could not be read.
#[derive(Debug, PartialEq, Eq)]
pub struct Unreadable;

fn address_of(address: Option<&mail_parser::Address<'_>>) -> String {
    let Some(first) = address.and_then(|a| a.first()) else { return String::new() };
    match (first.name(), first.address()) {
        (Some(name), Some(addr)) if !name.trim().is_empty() => format!("{} <{addr}>", name.trim()),
        (_, Some(addr)) => addr.to_string(),
        (Some(name), None) => name.trim().to_string(),
        (None, None) => String::new(),
    }
}

/// Only pictures carried in the mail itself: `cid:` sources, kept as Markdown images; anything from the web goes.
fn picture(_: &dyn htmd::element_handler::Handlers, element: htmd::Element) -> Option<htmd::element_handler::HandlerResult> {
    let attr = |name: &str| element.attrs.iter().find(|a| &*a.name.local == name).map(|a| a.value.to_string());
    let src = attr("src")?;
    if !src.to_ascii_lowercase().starts_with("cid:") {
        return None;
    }
    let alt = attr("alt").unwrap_or_default().replace(['[', ']', '\n'], " ");
    Some(format!("![{}]({})", alt.trim(), src.replace([' ', '(', ')'], "")).into())
}

/// An HTML body as Markdown: no styles, scripts or head, pictures as `picture` keeps them, and no link that runs code.
fn markdown_of(html: &str) -> String {
    let converter = htmd::HtmlToMarkdown::builder()
        .options(htmd::options::Options { bullet_list_marker: htmd::options::BulletListMarker::Dash, ul_bullet_spacing: 1, ..Default::default() })
        .skip_tags(vec!["script", "style", "head", "title", "meta", "link", "noscript", "template"])
        .add_handler(vec!["img"], picture)
        .build();
    let markdown = converter.convert(html).unwrap_or_default();
    inert(&markdown)
}

/// `](javascript:…)` and its kin, made `](#)`: a note's links open in a browser, and a mail's sender is a stranger.
fn inert(markdown: &str) -> String {
    let mut out = String::with_capacity(markdown.len());
    let mut rest = markdown;
    while let Some(at) = rest.find("](") {
        let (before, after) = rest.split_at(at + 2);
        out.push_str(before);
        let scheme = after.trim_start().to_ascii_lowercase();
        if ["javascript:", "vbscript:", "data:", "file:"].iter().any(|s| scheme.starts_with(s)) {
            out.push_str("#)");
            // To the parenthesis that closes the link, past any the address opens and closes itself.
            let (mut depth, mut end, mut escaped) = (1, after.len(), false);
            for (i, c) in after.char_indices() {
                match c {
                    _ if escaped => escaped = false,
                    '\\' => escaped = true,
                    '(' => depth += 1,
                    ')' => {
                        depth -= 1;
                        if depth == 0 {
                            end = i + 1;
                            break;
                        }
                    }
                    _ => {}
                }
            }
            rest = &after[end..];
        } else {
            rest = after;
        }
    }
    out.push_str(rest);
    out
}

/// A body cut to what a note keeps, at a character's edge, saying so.
fn kept(body: String) -> String {
    if body.len() <= BODY_BYTES {
        return body;
    }
    let mut end = BODY_BYTES;
    while !body.is_char_boundary(end) {
        end -= 1;
    }
    format!("{}\n\nThe rest of this mail was too long to keep.", &body[..end])
}

/// A file's name: what it was called, without any path, or a plain one for its kind.
fn file_name(given: Option<&str>, kind: &str, n: usize) -> String {
    let base = given.map(|g| g.rsplit(['/', '\\']).next().unwrap_or(g).trim().to_string()).filter(|g| !g.is_empty());
    base.unwrap_or_else(|| {
        let ext = match kind {
            "image/jpeg" => "jpg",
            "image/png" => "png",
            "image/gif" => "gif",
            "image/webp" => "webp",
            "message/rfc822" => "eml",
            "application/pdf" => "pdf",
            _ => "bin",
        };
        format!("file-{n}.{ext}")
    })
}

/// The raw mail, read and laid out as `GML1`, with `to` the address it was sent to; `now` (ms) where it has no date.
pub fn payload(raw: &[u8], to: &str, now: i64) -> Result<Vec<u8>, Unreadable> {
    let message = MessageParser::default().parse(raw).ok_or(Unreadable)?;
    let html = message.html_part(0).and_then(|part| match &part.body {
        PartType::Html(html) => Some(html.as_ref()),
        _ => None,
    });
    let body = match html {
        Some(html) => markdown_of(html),
        None => message.body_text(0).map(Cow::into_owned).unwrap_or_default(),
    };
    let mut files: Vec<Value> = Vec::new();
    let mut bytes: Vec<&[u8]> = Vec::new();
    for (n, part) in message.attachments().enumerate() {
        if files.len() >= FILES {
            break;
        }
        let kind = part.content_type().map(|t| format!("{}/{}", t.ctype(), t.subtype().unwrap_or("octet-stream")).to_ascii_lowercase()).unwrap_or_else(|| "application/octet-stream".into());
        let contents: &[u8] = match &part.body {
            PartType::Binary(b) | PartType::InlineBinary(b) => b.as_ref(),
            PartType::Text(t) | PartType::Html(t) => t.as_bytes(),
            // A mail forwarded as an attachment: the mail itself, as a file.
            PartType::Message(_) => part.contents(),
            PartType::Multipart(_) => continue,
        };
        if contents.is_empty() {
            continue;
        }
        files.push(json!({ "name": file_name(part.attachment_name(), &kind, n + 1), "type": kind, "size": contents.len(), "cid": part.content_id() }));
        bytes.push(contents);
    }
    let head = json!({
        "v": 1,
        "subject": message.subject().unwrap_or("").trim(),
        "from": address_of(message.from()),
        "to": to,
        "date": message.date().map(|d| d.to_timestamp() * 1000).unwrap_or(now),
        "body": kept(body),
        "files": files,
    });
    let head = serde_json::to_vec(&head).map_err(|_| Unreadable)?;
    let length = u32::try_from(head.len()).map_err(|_| Unreadable)?;
    let mut out = Vec::with_capacity(8 + head.len() + bytes.iter().map(|b| b.len()).sum::<usize>());
    out.extend_from_slice(MAGIC);
    out.extend_from_slice(&length.to_be_bytes());
    out.extend_from_slice(&head);
    for b in bytes {
        out.extend_from_slice(b);
    }
    Ok(out)
}

/// The head and the files back out of a payload, for the tests (the device's reading is lib/mail/mail_note.dart's).
#[cfg(test)]
pub fn read(payload: &[u8]) -> (Value, Vec<Vec<u8>>) {
    assert_eq!(&payload[..4], MAGIC);
    let length = u32::from_be_bytes(payload[4..8].try_into().unwrap()) as usize;
    let head: Value = serde_json::from_slice(&payload[8..8 + length]).unwrap();
    let mut at = 8 + length;
    let mut files = Vec::new();
    for file in head["files"].as_array().unwrap() {
        let size = file["size"].as_u64().unwrap() as usize;
        files.push(payload[at..at + size].to_vec());
        at += size;
    }
    (head, files)
}

#[cfg(test)]
pub mod tests {
    use super::*;

    /// A mail as a phone's mail app sends one: plain and HTML alternatives, an inline picture, a PDF attached.
    pub const MAIL: &str = "From: Sam Lee <sam@example.com>\r\n\
To: k7m2q9xh4t3vbn8p@in.ghostmarkdown.com\r\n\
Subject: =?UTF-8?Q?Caf=C3=A9_plans?=\r\n\
Date: Fri, 16 Oct 2026 14:05:00 +0000\r\n\
MIME-Version: 1.0\r\n\
Content-Type: multipart/mixed; boundary=\"outer\"\r\n\
\r\n\
--outer\r\n\
Content-Type: multipart/related; boundary=\"rel\"\r\n\
\r\n\
--rel\r\n\
Content-Type: multipart/alternative; boundary=\"alt\"\r\n\
\r\n\
--alt\r\n\
Content-Type: text/plain; charset=utf-8\r\n\
\r\n\
Meet at the caf=C3=A9.\r\n\
--alt\r\n\
Content-Type: text/html; charset=utf-8\r\n\
Content-Transfer-Encoding: quoted-printable\r\n\
\r\n\
<html><head><style>p{color:red}</style></head><body><h2>Plans</h2><p>Meet at the <b>caf=C3=A9</b>, see <a href=3D\"https://example.com/map\">the map</a>.</p><ul><li>bread</li><li>tea</li></ul><img src=3D\"cid:pic1@x\" alt=3D\"the door\"><img src=3D\"https://tracker.example/p.gif\"><a href=3D\"javascript:alert(1)\">click</a></body></html>\r\n\
--alt--\r\n\
--rel\r\n\
Content-Type: image/png\r\n\
Content-ID: <pic1@x>\r\n\
Content-Disposition: inline; filename=\"door.png\"\r\n\
Content-Transfer-Encoding: base64\r\n\
\r\n\
iVBORw0KGgo=\r\n\
--rel--\r\n\
--outer\r\n\
Content-Type: application/pdf; name=\"menu.pdf\"\r\n\
Content-Disposition: attachment; filename=\"menu.pdf\"\r\n\
Content-Transfer-Encoding: base64\r\n\
\r\n\
JVBERi0xLjQK\r\n\
--outer--\r\n";

    #[test]
    fn a_mail_becomes_its_subject_its_sender_markdown_and_its_files() {
        let (head, files) = read(&payload(MAIL.as_bytes(), "k7m2q9xh4t3vbn8p@in.ghostmarkdown.com", 1).unwrap());
        assert_eq!(head["subject"], "Café plans");
        assert_eq!(head["from"], "Sam Lee <sam@example.com>");
        assert_eq!(head["date"], 1_792_159_500_000i64);
        let body = head["body"].as_str().unwrap();
        assert!(body.contains("## Plans"), "{body}");
        assert!(body.contains("**café**") && body.contains("[the map](https://example.com/map)"), "{body}");
        assert!(body.contains("- bread") && body.contains("- tea"), "{body}");
        assert!(body.contains("![the door](cid:pic1@x)"), "{body}");
        assert!(!body.contains("tracker") && !body.contains("javascript") && !body.contains("color"), "{body}");
        let names: Vec<_> = head["files"].as_array().unwrap().iter().map(|f| (f["name"].as_str().unwrap(), f["type"].as_str().unwrap(), f["cid"].as_str())).collect();
        assert_eq!(names, vec![("door.png", "image/png", Some("pic1@x")), ("menu.pdf", "application/pdf", None)]);
        assert_eq!(files[0], [0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a]);
        assert_eq!(files[1], b"%PDF-1.4\n");
    }

    #[test]
    fn a_plain_mail_keeps_its_words_and_one_with_no_date_takes_now() {
        let plain = "From: a@example.com\r\nSubject: Note\r\n\r\nLine one.\r\nLine two.\r\n";
        let (head, files) = read(&payload(plain.as_bytes(), "x@in.ghostmarkdown.com", 42).unwrap());
        assert_eq!((head["subject"].as_str(), head["from"].as_str(), head["date"].as_i64()), (Some("Note"), Some("a@example.com"), Some(42)));
        assert!(head["body"].as_str().unwrap().starts_with("Line one.\r\nLine two.") || head["body"].as_str().unwrap().starts_with("Line one.\nLine two."));
        assert!(files.is_empty());
    }

    #[test]
    fn a_body_past_what_a_note_keeps_is_cut_and_says_so() {
        let long = format!("Subject: Long\r\n\r\n{}", "é".repeat(BODY_BYTES));
        let (head, _) = read(&payload(long.as_bytes(), "x@in.ghostmarkdown.com", 0).unwrap());
        let body = head["body"].as_str().unwrap();
        assert!(body.len() < BODY_BYTES + 100 && body.ends_with("The rest of this mail was too long to keep."));
    }

    #[test]
    fn a_link_that_runs_code_is_made_inert() {
        assert_eq!(inert("[a](javascript:x()) and [b](https://ok) [c]( data:text/html,1)"), "[a](#) and [b](https://ok) [c](#)");
    }
}
