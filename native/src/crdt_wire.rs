//! A Yjs v1 update read as bytes, for the one thing `yrs` cannot be asked: where an update cuts, and what words
//! each block holds, before it is applied (crdt.rs `apply_remote`, "A change that splits a character in two").
//!
//! The web's `applyTextDiff` compares UTF-16 code units, so an emoji swapped for a near one is cut between its
//! two halves, and Yjs, cutting a block of text there, writes U+FFFD over both halves (`ContentString.splice`):
//! every member's copy reads U+FFFD twice where the emoji was. yrs 0.26 keeps the whole character in a block it
//! then counts one unit short. So before an update is applied, the places it cuts are read from it here
//! (`cuts`), and any character of two units that one of them falls inside is written as U+FFFD twice, in this
//! copy's own state and in the updates themselves (`mend`), which is what Yjs holds after the same update. Two
//! units either way, so no clock moves and nothing else in the document is touched.
//!
//! The layout is Yjs's `UpdateEncoderV1` (yjs/src/utils/encoding.js, `Item.write`, the contents' own `write`s,
//! `DeleteSet`), with lib0's variable-length integers and its `any`.

use std::collections::HashSet;
use std::ops::Range;

/// A place in a client's clock where a block is cut: before the unit at `clock`.
pub type Cut = (u64, u64);

struct Reader<'a> {
    bytes: &'a [u8],
    at: usize,
}

const SHORT: &str = "That document update ends early.";

impl<'a> Reader<'a> {
    fn byte(&mut self) -> Result<u8, String> {
        let byte = *self.bytes.get(self.at).ok_or(SHORT)?;
        self.at += 1;
        Ok(byte)
    }

    /// lib0's unsigned integer: seven bits a byte, least significant first.
    fn var(&mut self) -> Result<u64, String> {
        let mut value = 0u64;
        let mut shift = 0u32;
        loop {
            let byte = self.byte()?;
            if shift > 63 {
                return Err("That document update holds a number too large.".to_string());
            }
            value |= u64::from(byte & 0x7f) << shift;
            if byte < 0x80 {
                return Ok(value);
            }
            shift += 7;
        }
    }

    fn skip(&mut self, length: u64) -> Result<Range<usize>, String> {
        let end = self.at.checked_add(usize::try_from(length).map_err(|_| SHORT)?).filter(|end| *end <= self.bytes.len()).ok_or(SHORT)?;
        let span = self.at..end;
        self.at = end;
        Ok(span)
    }

    /// A string: its byte length, then UTF-8. Answers the span of both and the span of the text alone.
    fn string(&mut self) -> Result<(Range<usize>, Range<usize>), String> {
        let from = self.at;
        let length = self.var()?;
        let text = self.skip(length)?;
        Ok((from..text.end, text))
    }

    /// lib0's signed integer: a sign bit and six bits in the first byte.
    fn var_int(&mut self) -> Result<(), String> {
        let mut byte = self.byte()?;
        let mut more = byte & 0x80 != 0;
        let mut read = 1;
        while more {
            byte = self.byte()?;
            more = byte & 0x80 != 0;
            read += 1;
            if read > 10 {
                return Err("That document update holds a number too large.".to_string());
            }
        }
        Ok(())
    }

    /// lib0's `any`, passed over.
    fn any(&mut self, depth: u32) -> Result<(), String> {
        if depth > 64 {
            return Err("That document update nests too deep.".to_string());
        }
        match self.byte()? {
            127 | 126 | 121 | 120 => Ok(()),
            125 => self.var_int(),
            124 => self.skip(4).map(|_| ()),
            123 | 122 => self.skip(8).map(|_| ()),
            119 => self.string().map(|_| ()),
            118 => {
                for _ in 0..self.var()? {
                    self.string()?;
                    self.any(depth + 1)?;
                }
                Ok(())
            }
            117 => {
                for _ in 0..self.var()? {
                    self.any(depth + 1)?;
                }
                Ok(())
            }
            116 => {
                let length = self.var()?;
                self.skip(length).map(|_| ())
            }
            _ => Err("That document update holds a value of a kind this Ghost.md does not know.".to_string()),
        }
    }
}

/// One block of words in an update: whose, from which clock, and where its string lies in the bytes.
struct Words {
    client: u64,
    clock: u64,
    /// The length and the UTF-8 together, and the UTF-8 alone.
    whole: Range<usize>,
    text: Range<usize>,
}

/// One block an update puts in: whose, from which clock, how long, and the block it was put before (its right
/// origin), when it names one.
pub struct Put {
    pub client: u64,
    pub clock: u64,
    pub length: u64,
    pub before: Option<(u64, u64)>,
}

/// What an update holds that matters here.
#[derive(Default)]
struct Read {
    cuts: Vec<Cut>,
    words: Vec<Words>,
    put: Vec<Put>,
}

fn read(bytes: &[u8]) -> Result<Read, String> {
    let mut r = Reader { bytes, at: 0 };
    let mut out = Read::default();
    for _ in 0..r.var()? {
        let structs = r.var()?;
        let client = r.var()?;
        let mut clock = r.var()?;
        for _ in 0..structs {
            let info = r.byte()?;
            let kind = info & 0x1f;
            // A skip, and a block collected as garbage: a length, and nothing cut.
            if info == 10 || kind == 0 {
                clock += r.var()?;
                continue;
            }
            // Where it was put: after `origin`, before `right origin`. Each is a cut in the block it names. (Its
            // own two ends are not: a block this copy already holds part of is taken from where that part ends.)
            if info & 0x80 != 0 {
                let (of, at) = (r.var()?, r.var()?);
                out.cuts.push((of, at + 1));
            }
            let mut before = None;
            if info & 0x40 != 0 {
                let (of, at) = (r.var()?, r.var()?);
                out.cuts.push((of, at));
                before = Some((of, at));
            }
            if info & 0xc0 == 0 {
                // With neither, it names its parent: a root by name, or a type by the block that made it.
                if r.var()? == 1 {
                    r.string()?;
                } else {
                    r.var()?;
                    r.var()?;
                }
                if info & 0x20 != 0 {
                    r.string()?;
                }
            }
            let length = match kind {
                // Deleted: only how long it was.
                1 => r.var()?,
                // JSON, an older Yjs's: that many strings.
                2 => {
                    let count = r.var()?;
                    for _ in 0..count {
                        r.string()?;
                    }
                    count
                }
                3 => {
                    let length = r.var()?;
                    r.skip(length)?;
                    1
                }
                4 => {
                    let (whole, text) = r.string()?;
                    let said = std::str::from_utf8(&bytes[text.clone()]).map_err(|_| "That document update holds words that are not text.".to_string())?;
                    let units = said.encode_utf16().count() as u64;
                    out.words.push(Words { client, clock, whole, text });
                    units
                }
                // An embed: JSON as a string.
                5 => {
                    r.string()?;
                    1
                }
                // A format: its name, and its value as JSON.
                6 => {
                    r.string()?;
                    r.string()?;
                    1
                }
                // A type: which, and for an XML element or hook its name.
                7 => {
                    let which = r.var()?;
                    if which == 3 || which == 5 {
                        r.string()?;
                    }
                    1
                }
                8 => {
                    let count = r.var()?;
                    for _ in 0..count {
                        r.any(0)?;
                    }
                    count
                }
                // A document in a document: its id, and what it was made with.
                9 => {
                    r.string()?;
                    r.any(0)?;
                    1
                }
                _ => return Err("That document update holds a block of a kind this Ghost.md does not know.".to_string()),
            };
            out.put.push(Put { client, clock, length, before });
            clock += length;
        }
    }
    // What was deleted: each stretch cuts at its two ends.
    for _ in 0..r.var()? {
        let client = r.var()?;
        for _ in 0..r.var()? {
            let (from, length) = (r.var()?, r.var()?);
            out.cuts.push((client, from));
            out.cuts.push((client, from + length));
        }
    }
    Ok(out)
}

/// Every block `update` puts in, in the order it holds them (crdt.rs `again`: an undo's update puts each block
/// it restores before the block it restores, and says so).
pub fn put(update: &[u8]) -> Result<Vec<Put>, String> {
    Ok(read(update)?.put)
}

/// Every place `update` cuts, added to `cuts`.
pub fn cuts(update: &[u8], cuts: &mut HashSet<Cut>) -> Result<(), String> {
    cuts.extend(read(update)?.cuts);
    Ok(())
}

/// `update` with U+FFFD twice in place of every character of two units that one of `cuts` falls inside, or
/// `None` when there is none: what Yjs holds of those words once it has cut there.
pub fn mend(update: &[u8], cuts: &HashSet<Cut>) -> Result<Option<Vec<u8>>, String> {
    let held = read(update)?;
    let mut out: Vec<u8> = Vec::new();
    let mut copied = 0;
    for words in &held.words {
        let said = std::str::from_utf8(&update[words.text.clone()]).map_err(|_| "That document update holds words that are not text.".to_string())?;
        let mut clock = words.clock;
        let mut mended: Option<String> = None;
        for (at, c) in said.char_indices() {
            if c.len_utf16() == 2 && cuts.contains(&(words.client, clock + 1)) {
                let so_far = mended.get_or_insert_with(|| said[..at].to_string());
                so_far.push_str("\u{FFFD}\u{FFFD}");
            } else if let Some(so_far) = mended.as_mut() {
                so_far.push(c);
            }
            clock += c.len_utf16() as u64;
        }
        if let Some(mended) = mended {
            out.extend_from_slice(&update[copied..words.whole.start]);
            let mut length = mended.len() as u64;
            while length > 0x7f {
                out.push(0x80 | (length & 0x7f) as u8);
                length >>= 7;
            }
            out.push(length as u8);
            out.extend_from_slice(mended.as_bytes());
            copied = words.whole.end;
        }
    }
    if copied == 0 {
        return Ok(None);
    }
    out.extend_from_slice(&update[copied..]);
    Ok(Some(out))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_number_and_a_value_are_read_as_lib0_writes_them() {
        let mut r = Reader { bytes: &[0xe9, 0x07, 0x7f], at: 0 };
        assert_eq!(r.var(), Ok(1001));
        assert_eq!(r.var(), Ok(127));
        assert!(r.var().is_err());
        // {"a": [1, -200, "é", true, null, 1.5]} as lib0's `any`.
        let any = [118, 1, 1, b'a', 117, 6, 125, 1, 125, 0xc8, 0x03, 119, 2, 0xc3, 0xa9, 120, 126, 123, 0, 0, 0, 0, 0, 0, 0xf8, 0x3f];
        let mut r = Reader { bytes: &any, at: 0 };
        assert_eq!(r.any(0), Ok(()));
        assert_eq!(r.at, any.len());
    }
}
