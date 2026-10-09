//! Team notes and live typing (docs/STAGE7.md, "Live typing and team notes"): Yjs documents in Rust, by `yrs`,
//! speaking the wire the web app's `yjs` 13 and `y-protocols` speak, so a phone and a Mac edit one note.
//!
//! What the web keeps in `../glyph/src/app/core/team/doc.ts` (a `Y.Doc` per note, its words in the text `body`,
//! the updates made here that the service has not been given) is kept here behind a number, as crypto.rs keeps
//! a key. Held to the web's own libraries by fixtures they wrote (tool/yjs_vectors.mjs, tests/yjs_vectors.rs),
//! in both directions.
//!
//! - **Offsets are UTF-16 code units**, as a JavaScript string's and a Dart `String`'s are: an emoji is two.
//! - **Updates are Yjs's v1 encoding**, base64url without padding where they cross (crypto.rs seals them).
//! - **A change made here is queued** (`pending`) until `crdt_posted` says the service has it; a change that
//!   arrives (`crdt_apply`) is not, which is doc.ts's `REMOTE` origin.
//! - **A change never splits a surrogate pair.** The web's `applyTextDiff` compares code units, so "😀" turned
//!   into "😁" keeps the first unit and swaps the second, and Yjs then writes U+FFFD over both halves. Here the
//!   kept head and foot are drawn back to whole characters first, so the emoji is replaced whole. The update is
//!   another, as valid, and every copy still arrives at the same words.
//! - **Where yrs 0.26 is not Yjs**, this file makes up for it, and says so at `apply_remote`: a deletion that
//!   arrives before what it deletes, and a change from the web that does split a character, which is read as
//!   Yjs reads it (U+FFFD twice where the character was; crdt_wire.rs).
//! - **A team's canvas is types beside the words** (docs/SHARED.md, S9; the web's `core/team/canvas.ts`):
//!   `canvas-nodes` a map of node id to a map of the node's fields (a card's words a text of its own),
//!   `canvas-edges` the same for the lines, `canvas-order` the node ids in their z-order, `canvas-comments` the
//!   threads (their replies an array only ever added to), and `canvas-meta`'s `seeded`. Two members moving
//!   different cards, or typing in the same one, both keep what they did. The whole canvas is handed in and only
//!   what differs is written, as the web's view hands its own back.
//! - **No lock of the notes'**, and no `init`: dispatch.rs answers these before it looks for the library.
//!
//! | command | takes | answers |
//! | --- | --- | --- |
//! | `crdt_open` | `{state?, pending?, words?, clientId?}` | `{doc, clientId, text}` |
//! | `crdt_close` | `{doc}` | whether there was one |
//! | `crdt_text` | `{doc}` | the words |
//! | `crdt_apply_diff` | `{doc, to}` | `{changed, update, text}`: doc.ts `reconcile` |
//! | `crdt_edit` | `{doc, edits: [{index, remove?, insert?}]}` | `{changed, update, text}`: an editor's own changes, in order, as one |
//! | `crdt_state` | `{doc, vector?}` | the whole document as an update, or what `vector` lacks |
//! | `crdt_vector` | `{doc}` | the state vector |
//! | `crdt_apply` | `{doc, updates}` | `{changed, text}`: doc.ts `applyRemote` |
//! | `crdt_pending` | `{doc}` | the updates not yet with the service, in order |
//! | `crdt_posted` | `{doc, count}` | how many are still pending |
//! | `crdt_lacks` | `{mine, theirs}` | whether `theirs` holds anything `mine` lacks (live/team.ts `lacks`) |
//! | `crdt_relative` | `{doc, index, assoc?}` | a relative position, as `Y.relativePositionToJSON` writes one |
//! | `crdt_absolute` | `{doc, position}` | its index now, or `null` |
//! | `crdt_canvas_has` | `{doc}` | whether the document's types hold a canvas yet (canvas.ts `hasTeamCanvas`) |
//! | `crdt_canvas_read` | `{doc}` | `{nodes, edges, comments}`: the canvas the types hold (canvas.ts `read`, before it is parsed) |
//! | `crdt_canvas_write` | `{doc, canvas: {nodes, edges, comments?}, seed?}` | `{changed, update, text}`: canvas.ts `write`, only what differs, as one change |
//! | `awareness_open` | `{clientId}` | `{awareness, update}` |
//! | `awareness_close` | `{awareness}` | whether there was one |
//! | `awareness_set` | `{awareness, state}` or `{awareness, field, value}` | `{update, added, updated, touched, removed}` |
//! | `awareness_encode` | `{awareness, clients?}` | an awareness update |
//! | `awareness_apply` | `{awareness, update}` | `{added, updated, touched, removed}` |
//! | `awareness_remove` | `{awareness, clients}` | `{removed}` |
//! | `awareness_states` | `{awareness}` | `[{client, clock, state}]` |
//! | `awareness_tick` | `{awareness, now?}` | `{update, removed}`: the fifteen-second renewal and thirty-second forgetting |
//!
//! Awareness is y-protocols' own few lines, ported (it is a map of JSON by client and a clock each, and its wire
//! is three fields a client), rather than yrs's `sync::Awareness`, which wants a document and an observer where
//! this wants an answer: who is here, with the `user` and `cursor` the web's carets read, as JSON.

use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};

use serde::Deserialize;
use serde_json::{json, Value};
use yrs::updates::decoder::Decode as _;
use yrs::updates::encoder::Encode as _;
use yrs::types::ToJson as _;
use yrs::{Any, Array as _, ArrayPrelim, ArrayRef, Assoc, ClientID, Doc, GetString as _, IndexScope, Map as _, MapPrelim, MapRef, OffsetKind, Options, Out, ReadTxn, StateVector, StickyIndex, Text as _, TextPrelim, TextRef, Transact as _, TransactionMut, Update, ID};

use crate::crypto::{from_base64url, to_base64url};

/// The field a note's words live in (doc.ts `FIELD`).
pub const FIELD: &str = "body";
/// What marks a transaction as one that arrived, for anything that watches the document.
const REMOTE: &str = "remote";
/// After this long unheard, a client is forgotten; at half of it this device says it is still here.
/// y-protocols `outdatedTimeout`.
const OUTDATED_MS: u64 = 30_000;
/// The largest client id JavaScript can hold exactly, and so the largest Yjs can carry.
const MAX_CLIENT: u64 = (1 << 53) - 1;

const COMMANDS: [&str; 24] = [
    "crdt_open",
    "crdt_close",
    "crdt_text",
    "crdt_apply_diff",
    "crdt_edit",
    "crdt_state",
    "crdt_vector",
    "crdt_apply",
    "crdt_pending",
    "crdt_posted",
    "crdt_lacks",
    "crdt_relative",
    "crdt_absolute",
    "crdt_canvas_has",
    "crdt_canvas_read",
    "crdt_canvas_write",
    "awareness_open",
    "awareness_close",
    "awareness_set",
    "awareness_encode",
    "awareness_apply",
    "awareness_remove",
    "awareness_states",
    "awareness_tick",
];

/// Whether `command` is one of this module's.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

// --- a document ---------------------------------------------------------------------

/// One note's document, and the changes made here that the service has not been given.
struct Held {
    doc: Doc,
    text: TextRef,
    pending: Vec<Vec<u8>>,
    /// Updates that arrived before what they build on, kept to be applied again once it has come (`settle`).
    early: Vec<Vec<u8>>,
}

/// A fresh client id as Yjs makes one: thirty-two random bits.
fn new_client() -> Result<u64, String> {
    let mut bytes = [0u8; 4];
    getrandom::getrandom(&mut bytes).map_err(|e| format!("The phone gave no random bytes: {e}"))?;
    Ok(u64::from(u32::from_le_bytes(bytes)))
}

fn client_of(id: u64) -> Result<ClientID, String> {
    if id > MAX_CLIENT {
        return Err("A client id is at most 53 bits.".to_string());
    }
    Ok(ClientID::new(id))
}

fn decode_update(bytes: &[u8]) -> Result<Update, String> {
    Update::decode_v1(bytes).map_err(|e| format!("That is not a document update: {e}"))
}

fn decode_vector(bytes: &[u8]) -> Result<StateVector, String> {
    StateVector::decode_v1(bytes).map_err(|e| format!("That is not a state vector: {e}"))
}

impl Held {
    fn new(client: u64) -> Result<Held, String> {
        let mut options = Options::with_client_id(client_of(client)?);
        options.offset_kind = OffsetKind::Utf16;
        let doc = Doc::with_options(options);
        let text = doc.get_or_insert_text(FIELD);
        Ok(Held { doc, text, pending: Vec::new(), early: Vec::new() })
    }

    /// The text's own branch, which a position is found in and checked against.
    fn branch(&self) -> yrs::branch::BranchPtr {
        yrs::branch::BranchPtr::from(<TextRef as AsRef<yrs::branch::Branch>>::as_ref(&self.text))
    }

    fn words(&self) -> String {
        self.text.get_string(&self.doc.transact())
    }

    /// The whole document as one update, or what a peer at `vector` lacks: `Y.encodeStateAsUpdate`.
    fn state(&self, vector: Option<&StateVector>) -> Vec<u8> {
        let empty = StateVector::default();
        self.doc.transact().encode_state_as_update_v1(vector.unwrap_or(&empty))
    }

    /// Updates that arrived, applied as one transaction. All are read before any is applied, so one that is not
    /// an update leaves the document as it was.
    ///
    /// Two things `yrs` 0.26 does not do as Yjs does are made up for here, and the fixtures hold both:
    ///
    /// - **A deletion that arrives before what it deletes.** yrs keeps it, and then loses the part of it that
    ///   becomes possible in the same call that brings the missing words (`settle`).
    /// - **A change that splits a character in two** (the web's `applyTextDiff` makes one when an emoji is
    ///   swapped for a near one). Yjs, cutting a block of words there, writes U+FFFD over both halves; yrs keeps
    ///   the whole character in a block it now counts one unit short, and what it would send on after that is
    ///   no longer a document Yjs can read. So where an update cuts is read from it first (crdt_wire.rs), and
    ///   a character it cuts through is written as U+FFFD twice in this copy and in the update before anything
    ///   is applied (`mended`): the words Yjs holds, and every member reads the same. Should a cut ever get
    ///   past that, the change is refused and the document put back as it was (`whole`).
    fn apply_remote(&mut self, updates: &[Vec<u8>]) -> Result<(), String> {
        updates.iter().try_for_each(|bytes| decode_update(bytes).map(|_| ()))?;
        // Only words with a character of two units in them can be split, here or as they arrive.
        let pairs = self.words().chars().any(|c| c.len_utf16() == 2);
        let updates = if pairs || updates.iter().any(|bytes| bytes.iter().any(|byte| *byte >= 0xf0)) { self.mended(updates)? } else { updates.to_vec() };
        let decoded = updates.iter().map(|bytes| decode_update(bytes)).collect::<Result<Vec<_>, _>>()?;
        let before = (pairs || self.words().chars().any(|c| c.len_utf16() == 2)).then(|| (self.state(None), self.early.clone()));
        // Whether anything waited at any moment, one update on another of the same call included.
        let mut waited = false;
        {
            let mut txn = self.doc.transact_mut_with(REMOTE);
            for update in decoded {
                txn.apply_update(update).map_err(|e| format!("That update could not be applied: {e}"))?;
                waited |= txn.store().pending_update().is_some() || txn.store().pending_ds().is_some();
            }
        }
        if waited {
            self.early.extend(updates.iter().cloned());
        }
        self.settle()?;
        if let Some((before, early)) = before {
            if !self.whole() {
                self.put_back(&before)?;
                self.early = early;
                return Err("That change splits a character in two, which this copy cannot hold as the others do. It was not applied.".to_string());
            }
        }
        Ok(())
    }

    /// `updates` as they are to be applied, once every character of two units that one of them cuts through
    /// (or that an early one still waiting does) reads U+FFFD twice: in this copy, which is made again from its
    /// own state so written, in the early ones, and in `updates` themselves, which are answered.
    fn mended(&mut self, updates: &[Vec<u8>]) -> Result<Vec<Vec<u8>>, String> {
        let mut cuts = std::collections::HashSet::new();
        for bytes in updates.iter().chain(self.early.iter()) {
            crate::crdt_wire::cuts(bytes, &mut cuts)?;
        }
        if let Some(state) = crate::crdt_wire::mend(&self.state(None), &cuts)? {
            self.put_back(&state)?;
        }
        for bytes in self.early.iter_mut() {
            if let Some(mended) = crate::crdt_wire::mend(bytes, &cuts)? {
                *bytes = mended;
            }
        }
        updates.iter().map(|bytes| Ok(crate::crdt_wire::mend(bytes, &cuts)?.unwrap_or_else(|| bytes.clone()))).collect()
    }

    /// The early updates applied again, once every block they were waiting for is here: a second time changes
    /// nothing that was applied the first, and brings the deletions that were lost.
    fn settle(&mut self) -> Result<(), String> {
        if self.early.is_empty() {
            return Ok(());
        }
        let mut txn = self.doc.transact_mut_with(REMOTE);
        if txn.store().pending_update().is_some() {
            return Ok(());
        }
        for bytes in &self.early {
            txn.apply_update(decode_update(bytes)?).map_err(|e| format!("That update could not be applied: {e}"))?;
        }
        if txn.store().pending_update().is_none() && txn.store().pending_ds().is_none() {
            self.early.clear();
        }
        Ok(())
    }

    /// Whether every character of two units is still one: the position of its second unit, asked for and
    /// placed again, is where it was. In a block that was split through a character it is not.
    fn whole(&self) -> bool {
        let txn = self.doc.transact();
        let words: Vec<u16> = self.text.get_string(&txn).encode_utf16().collect();
        (1..words.len()).filter(|&at| (0xD800..0xDC00).contains(&words[at - 1]) && (0xDC00..0xE000).contains(&words[at])).all(|at| {
            let placed = StickyIndex::at(&txn, self.branch(), at as u32, Assoc::After).and_then(|sticky| sticky.get_offset(&txn));
            placed.is_some_and(|offset| offset.index == at as u32)
        })
    }

    /// The document made again from `state`, a snapshot of it: what undoes an update that should not have been
    /// applied. The same client, so what this device typed is still its own.
    fn put_back(&mut self, state: &[u8]) -> Result<(), String> {
        let again = Held::new(self.doc.client_id().get())?;
        {
            let mut txn = again.doc.transact_mut_with(REMOTE);
            txn.apply_update(decode_update(state)?).map_err(|e| format!("The document could not be put back: {e}"))?;
        }
        self.doc = again.doc;
        self.text = again.text;
        Ok(())
    }

    /// `edits` made here as one transaction, each `(index, remove, insert)` in UTF-16 units against the words as
    /// the edits before it left them. The update it makes is queued and answered; `None` when nothing changed.
    fn change(&mut self, edits: &[(u32, u32, String)]) -> Result<Option<Vec<u8>>, String> {
        // Checked whole before anything is written: a change is all of its edits or none.
        let mut words: Vec<u16> = self.words().encode_utf16().collect();
        for (index, remove, insert) in edits {
            let (at, end) = (*index as usize, *index as usize + *remove as usize);
            if end > words.len() {
                return Err(format!("A change at {index} of {remove} runs past the end of the words ({}).", words.len()));
            }
            let splits = |at: usize| at > 0 && at < words.len() && (0xD800..0xDC00).contains(&words[at - 1]) && (0xDC00..0xE000).contains(&words[at]);
            if splits(at) || splits(end) {
                return Err("A change may not split a character in two.".to_string());
            }
            words.splice(at..end, insert.encode_utf16());
        }
        if edits.iter().all(|(_, remove, insert)| *remove == 0 && insert.is_empty()) {
            return Ok(None);
        }
        let update = {
            let mut txn = self.doc.transact_mut();
            for (index, remove, insert) in edits {
                if *remove > 0 {
                    self.text.remove_range(&mut txn, *index, *remove);
                }
                if !insert.is_empty() {
                    self.text.insert(&mut txn, *index, insert);
                }
            }
            txn.encode_update_v1()
        };
        self.pending.push(update.clone());
        Ok(Some(update))
    }

    /// The words made `to`, as one change: textDiff.ts `applyTextDiff`, from the words as they are. The common
    /// head and foot are kept and what lies between goes and comes; see the header for the one difference.
    fn reconcile(&mut self, to: &str) -> Result<Option<Vec<u8>>, String> {
        match stretch(&self.words(), to)? {
            Some((head, gone, came)) => self.change(&[(head, gone, came)]),
            None => Ok(None),
        }
    }

    /// `index` as a position that stays with its character: `Y.createRelativePositionFromTypeIndex` and
    /// `Y.relativePositionToJSON`. `assoc` below zero keeps to the character before; otherwise the one after.
    fn relative(&self, index: u32, assoc: i64) -> Value {
        let txn = self.doc.transact();
        let index = index.min(self.text.len(&txn));
        let side = if assoc < 0 { Assoc::Before } else { Assoc::After };
        let found = StickyIndex::at(&txn, self.branch(), index, side);
        let mut position = serde_json::Map::new();
        position.insert("tname".to_string(), json!(FIELD));
        if let Some(IndexScope::Relative(id)) = found.as_ref().map(StickyIndex::scope) {
            position.insert("item".to_string(), json!({ "client": id.client.get(), "clock": id.clock }));
        }
        position.insert("assoc".to_string(), json!(assoc));
        Value::Object(position)
    }

    /// A relative position's index in the words as they are now, or `None` when it cannot be placed: it names
    /// something this copy has not been given, or it was never in this document's words.
    /// `Y.createAbsolutePositionFromRelativePosition`, and live/team.ts `caretIndexes`'s check of the type.
    fn absolute(&self, position: &Value) -> Result<Option<u32>, String> {
        let unreadable = || "That is not a relative position.".to_string();
        let position = position.as_object().ok_or_else(unreadable)?;
        let side = if position.get("assoc").and_then(Value::as_i64).unwrap_or(0) < 0 { Assoc::Before } else { Assoc::After };
        let id = |value: &Value| -> Result<ID, String> {
            let client = value.get("client").and_then(Value::as_u64).ok_or_else(unreadable)?;
            let clock = value.get("clock").and_then(Value::as_u64).and_then(|clock| u32::try_from(clock).ok()).ok_or_else(unreadable)?;
            Ok(ID::new(client_of(client)?, clock))
        };
        let sticky = if let Some(item) = position.get("item").filter(|item| !item.is_null()) {
            StickyIndex::from_id(id(item)?, side)
        } else if let Some(name) = position.get("tname").and_then(Value::as_str) {
            if name != FIELD {
                return Ok(None);
            }
            StickyIndex::new(IndexScope::Root(name.into()), side)
        } else if let Some(nested) = position.get("type").filter(|nested| !nested.is_null()) {
            StickyIndex::new(IndexScope::Nested(id(nested)?), side)
        } else {
            return Err(unreadable());
        };
        let txn = self.doc.transact();
        // A whole-type position has no item to walk from: Yjs answers the end of the words, or their start.
        if matches!(sticky.scope(), IndexScope::Root(_)) {
            return Ok(Some(if side == Assoc::Before { 0 } else { self.text.len(&txn) }));
        }
        let Some(offset) = sticky.get_offset(&txn) else { return Ok(None) };
        if offset.branch != self.branch() {
            return Ok(None);
        }
        Ok(Some(offset.index))
    }
}

/// The one stretch that makes `from` into `to`, in UTF-16 units: how far the common head runs, how many units
/// go, and what comes. `None` when they are the same words. Never between the two halves of a character.
fn stretch(from: &str, to: &str) -> Result<Option<(u32, u32, String)>, String> {
    let from: Vec<u16> = from.encode_utf16().collect();
    let to: Vec<u16> = to.encode_utf16().collect();
    if from == to {
        return Ok(None);
    }
    let most = from.len().min(to.len());
    let mut head = 0;
    while head < most && from[head] == to[head] {
        head += 1;
    }
    // Not between the two halves of a character.
    if head > 0 && (0xD800..0xDC00).contains(&from[head - 1]) {
        head -= 1;
    }
    let mut foot = 0;
    while foot < most - head && from[from.len() - 1 - foot] == to[to.len() - 1 - foot] {
        foot += 1;
    }
    if foot > 0 && (0xDC00..0xE000).contains(&from[from.len() - foot]) {
        foot -= 1;
    }
    let gone = (from.len() - head - foot) as u32;
    let came = String::from_utf16(&to[head..to.len() - foot]).map_err(|_| "Those words are not text.".to_string())?;
    Ok(Some((head as u32, gone, came)))
}

// --- a team's canvas ----------------------------------------------------------------

const CANVAS_NODES: &str = "canvas-nodes";
const CANVAS_EDGES: &str = "canvas-edges";
const CANVAS_ORDER: &str = "canvas-order";
const CANVAS_COMMENTS: &str = "canvas-comments";
const CANVAS_META: &str = "canvas-meta";

/// The fields of a node or an edge that are words, kept as a text of their own so typing in one card by two
/// members merges (canvas.ts `WORDS`).
const CANVAS_WORDS: [&str; 1] = ["text"];

/// The document's own named roots that hold the structure: shared by name, never made twice.
struct Roots {
    nodes: MapRef,
    edges: MapRef,
    order: ArrayRef,
    comments: MapRef,
    meta: MapRef,
}

/// A value as JSON holds it, for a field of a card.
fn any_of(value: &Value) -> Any {
    match value {
        Value::Null => Any::Null,
        Value::Bool(flag) => Any::Bool(*flag),
        Value::Number(number) => Any::Number(number.as_f64().unwrap_or(0.0)),
        Value::String(text) => Any::String(text.as_str().into()),
        Value::Array(list) => Any::Array(list.iter().map(any_of).collect()),
        Value::Object(fields) => Any::Map(Arc::new(fields.iter().map(|(key, value)| (key.clone(), any_of(value))).collect())),
    }
}

/// And back: a whole number as a whole number, as JavaScript writes one. `None` for what JSON leaves out.
fn json_of(any: &Any) -> Option<Value> {
    Some(match any {
        Any::Undefined => return None,
        Any::Null => Value::Null,
        Any::Bool(flag) => json!(flag),
        Any::Number(number) if number.fract() == 0.0 && number.abs() < 9.0e15 => json!(*number as i64),
        Any::Number(number) => json!(number),
        Any::BigInt(number) => json!(number),
        Any::String(text) => json!(text.as_ref()),
        Any::Buffer(_) => Value::Null,
        Any::Array(list) => Value::Array(list.iter().map(|one| json_of(one).unwrap_or(Value::Null)).collect()),
        Any::Map(fields) => Value::Object(fields.iter().filter_map(|(key, value)| json_of(value).map(|value| (key.clone(), value))).collect()),
    })
}

/// What a map or an array holds at one place, as the JSON the page reads of it: a text its words, a value itself.
fn plain_of<T: ReadTxn>(txn: &T, out: &Out) -> Option<Value> {
    match out {
        Out::Any(any) => json_of(any),
        Out::YText(text) => Some(json!(text.get_string(txn))),
        Out::YArray(list) => json_of(&list.to_json(txn)),
        Out::YMap(fields) => json_of(&fields.to_json(txn)),
        _ => None,
    }
}

fn plain<T: ReadTxn>(txn: &T, fields: &MapRef) -> serde_json::Map<String, Value> {
    fields.iter(txn).filter_map(|(key, value)| plain_of(txn, &value).map(|value| (key.to_string(), value))).collect()
}

fn sorted_keys<T: ReadTxn>(txn: &T, map: &MapRef) -> Vec<String> {
    let mut keys: Vec<String> = map.keys(txn).map(str::to_string).collect();
    keys.sort();
    keys
}

fn ids_of<T: ReadTxn>(txn: &T, order: &ArrayRef) -> Vec<String> {
    order.iter(txn).map(|one| match one {
        Out::Any(Any::String(id)) => id.to_string(),
        _ => String::new(),
    }).collect()
}

impl Held {
    /// The roots, made where this copy has not met them: outside any transaction.
    fn roots(&self) -> Roots {
        Roots {
            nodes: self.doc.get_or_insert_map(CANVAS_NODES),
            edges: self.doc.get_or_insert_map(CANVAS_EDGES),
            order: self.doc.get_or_insert_array(CANVAS_ORDER),
            comments: self.doc.get_or_insert_map(CANVAS_COMMENTS),
            meta: self.doc.get_or_insert_map(CANVAS_META),
        }
    }

    /// Whether the types hold a canvas yet: seeded here, or arrived from another device (`hasTeamCanvas`).
    fn canvas_seeded(&self) -> bool {
        let meta = self.roots().meta;
        let txn = self.doc.transact();
        match meta.get(&txn, "seeded") {
            Some(Out::Any(Any::Bool(flag))) => flag,
            Some(Out::Any(Any::Number(number))) => number != 0.0,
            Some(Out::Any(Any::String(text))) => !text.is_empty(),
            Some(Out::Any(Any::Null | Any::Undefined)) | None => false,
            Some(_) => true,
        }
    }

    /// The types as the canvas they hold, before it is parsed: the nodes in their order, the edges and the
    /// threads by id (canvas.ts `read`).
    fn canvas_read(&self) -> Value {
        let roots = self.roots();
        let txn = self.doc.transact();
        let mut ids: Vec<String> = Vec::new();
        for id in ids_of(&txn, &roots.order) {
            if !ids.contains(&id) && roots.nodes.contains_key(&txn, &id) {
                ids.push(id);
            }
        }
        for id in sorted_keys(&txn, &roots.nodes) {
            if !ids.contains(&id) {
                ids.push(id);
            }
        }
        let item = |map: &MapRef, id: &str| -> Value {
            let mut out = serde_json::Map::new();
            out.insert("id".to_string(), json!(id));
            if let Some(Out::YMap(fields)) = map.get(&txn, id) {
                out.extend(plain(&txn, &fields));
            }
            Value::Object(out)
        };
        let thread = |id: &str| -> Value {
            let mut out = serde_json::Map::new();
            out.insert("id".to_string(), json!(id));
            let mut replies = json!([]);
            if let Some(Out::YMap(fields)) = roots.comments.get(&txn, id) {
                out.extend(plain(&txn, &fields));
                if let Some(Out::YArray(list)) = fields.get(&txn, "replies") {
                    replies = json_of(&list.to_json(&txn)).unwrap_or(json!([]));
                }
            }
            out.insert("replies".to_string(), replies);
            Value::Object(out)
        };
        json!({
            "nodes": ids.iter().map(|id| item(&roots.nodes, id)).collect::<Vec<_>>(),
            "edges": sorted_keys(&txn, &roots.edges).iter().map(|id| item(&roots.edges, id)).collect::<Vec<_>>(),
            "comments": sorted_keys(&txn, &roots.comments).iter().map(|id| thread(id)).collect::<Vec<_>>(),
        })
    }

    /// `next` written into the types as one change, only what differs from what they hold (canvas.ts `write`);
    /// with `seed`, the structure is marked as there. The update it makes is queued and answered; `None` when
    /// nothing changed.
    fn canvas_write(&mut self, next: &Value, seed: bool) -> Result<Option<Vec<u8>>, String> {
        let list = |field: &str| -> Result<Vec<&serde_json::Map<String, Value>>, String> {
            match next.get(field) {
                None | Some(Value::Null) => Ok(Vec::new()),
                Some(Value::Array(items)) => items.iter().map(|item| item.as_object().filter(|item| item.get("id").is_some_and(Value::is_string)).ok_or_else(|| format!("A canvas's {field} each have an id."))).collect(),
                Some(_) => Err(format!("A canvas's {field} are a list.")),
            }
        };
        let (nodes, edges, comments) = (list("nodes")?, list("edges")?, list("comments")?);
        let id_of = |item: &serde_json::Map<String, Value>| item["id"].as_str().unwrap_or_default().to_string();
        // A card's words may not be cut through a character, here as in the note's own.
        let roots = self.roots();
        let before = self.doc.transact().state_vector();
        let update = {
            let mut txn = self.doc.transact_mut();
            write_all(&mut txn, &roots.nodes, &nodes)?;
            write_all(&mut txn, &roots.edges, &edges)?;
            write_threads(&mut txn, &roots.comments, &comments)?;
            let wanted: Vec<String> = nodes.iter().map(|node| id_of(node)).collect();
            // Gone, or doubled by two devices putting the same id in at once: taken out, from the end so the
            // indexes hold.
            let had = ids_of(&txn, &roots.order);
            let mut seen_here: Vec<&String> = Vec::new();
            for at in (0..had.len()).rev() {
                let id = &had[at];
                if !wanted.contains(id) || seen_here.contains(&id) {
                    roots.order.remove(&mut txn, at as u32);
                }
                seen_here.push(id);
            }
            let now = ids_of(&txn, &roots.order);
            if now != wanted {
                // New ids put in where they belong; an order that still differs is rewritten whole (a card sent
                // to the back).
                for (at, id) in wanted.iter().enumerate() {
                    if !now.contains(id) {
                        let at = (at as u32).min(roots.order.len(&txn));
                        roots.order.insert(&mut txn, at, id.as_str());
                    }
                }
                if ids_of(&txn, &roots.order) != wanted {
                    let length = roots.order.len(&txn);
                    roots.order.remove_range(&mut txn, 0, length);
                    roots.order.insert_range(&mut txn, 0, wanted.iter().map(String::as_str).collect::<Vec<_>>());
                }
            }
            if seed {
                roots.meta.insert(&mut txn, "seeded", 1.0);
            }
            txn.encode_update_v1()
        };
        // Nothing written is nothing made: the clocks stand where they stood, and nothing was deleted.
        if self.doc.transact().state_vector() == before && update.len() <= 2 {
            return Ok(None);
        }
        self.pending.push(update.clone());
        Ok(Some(update))
    }
}

fn write_all(txn: &mut TransactionMut, into: &MapRef, items: &[&serde_json::Map<String, Value>]) -> Result<(), String> {
    let wanted: Vec<&str> = items.iter().filter_map(|item| item["id"].as_str()).collect();
    for id in sorted_keys(txn, into) {
        if !wanted.contains(&id.as_str()) {
            into.remove(txn, &id);
        }
    }
    for item in items {
        let id = item["id"].as_str().unwrap_or_default();
        let fields = match into.get(txn, id) {
            Some(Out::YMap(fields)) => fields,
            _ => into.insert(txn, id, MapPrelim::default()),
        };
        write_fields(txn, &fields, item, &[])?;
    }
    Ok(())
}

/// One node's, edge's or thread's fields: those gone taken out, those that differ set, its words changed where
/// they changed (canvas.ts `writeFields`). `kept` are fields written elsewhere and left alone here.
fn write_fields(txn: &mut TransactionMut, fields: &MapRef, item: &serde_json::Map<String, Value>, kept: &[&str]) -> Result<(), String> {
    for key in sorted_keys(txn, fields) {
        if key != "id" && key != "replies" && key != "resolved" && !item.contains_key(&key) {
            fields.remove(txn, &key);
        }
    }
    for (key, value) in item {
        if key == "id" || kept.contains(&key.as_str()) {
            continue;
        }
        let held = fields.get(txn, key);
        if CANVAS_WORDS.contains(&key.as_str()) {
            if let Value::String(words) = value {
                match held {
                    Some(Out::YText(text)) => {
                        if let Some((head, gone, came)) = stretch(&text.get_string(txn), words)? {
                            if gone > 0 {
                                text.remove_range(txn, head, gone);
                            }
                            if !came.is_empty() {
                                text.insert(txn, head, &came);
                            }
                        }
                    }
                    _ => {
                        fields.insert(txn, key.as_str(), TextPrelim::new(words.as_str()));
                    }
                }
                continue;
            }
        }
        if held.as_ref().and_then(|held| plain_of(txn, held)).as_ref() != Some(value) || matches!(held, Some(Out::YText(_))) {
            fields.insert(txn, key.as_str(), any_of(value));
        }
    }
    Ok(())
}

/// The threads: each a map of its fields, with `replies` an array only ever added to, so two members replying at
/// once both land; `resolved` set and taken off as the thread closes and reopens (canvas.ts `writeThreads`).
fn write_threads(txn: &mut TransactionMut, into: &MapRef, threads: &[&serde_json::Map<String, Value>]) -> Result<(), String> {
    let wanted: Vec<&str> = threads.iter().filter_map(|thread| thread["id"].as_str()).collect();
    for id in sorted_keys(txn, into) {
        if !wanted.contains(&id.as_str()) {
            into.remove(txn, &id);
        }
    }
    for thread in threads {
        let id = thread["id"].as_str().unwrap_or_default();
        let fields = match into.get(txn, id) {
            Some(Out::YMap(fields)) => fields,
            _ => into.insert(txn, id, MapPrelim::default()),
        };
        let mut rest = (*thread).clone();
        let replies = rest.remove("replies");
        let resolved = rest.remove("resolved").filter(|resolved| !resolved.is_null());
        write_fields(txn, &fields, &rest, &[])?;
        let held = match fields.get(txn, "replies") {
            Some(Out::YArray(held)) => held,
            _ => fields.insert(txn, "replies", ArrayPrelim::default()),
        };
        let replies = replies.as_ref().and_then(Value::as_array).cloned().unwrap_or_default();
        let have = held.len(txn) as usize;
        if replies.len() > have {
            for reply in &replies[have..] {
                held.push_back(txn, any_of(reply));
            }
        }
        match resolved {
            Some(resolved) => {
                let was = fields.get(txn, "resolved").and_then(|was| plain_of(txn, &was));
                let same = was.as_ref().is_some_and(|was| was.get("by") == resolved.get("by") && was.get("at") == resolved.get("at"));
                if !same {
                    fields.insert(txn, "resolved", any_of(&resolved));
                }
            }
            None => {
                if fields.contains_key(txn, "resolved") {
                    fields.remove(txn, "resolved");
                }
            }
        }
    }
    Ok(())
}

// --- awareness ----------------------------------------------------------------------

/// What one client last said, and when it was heard.
struct Meta {
    clock: u64,
    heard_ms: u64,
}

/// Who is in a room: y-protocols' `Awareness`, its states as JSON.
struct Aware {
    client: u64,
    states: BTreeMap<u64, Value>,
    meta: BTreeMap<u64, Meta>,
}

/// What an awareness change touched, as y-protocols' two events say it: `updated` is the `change` event's (a
/// state that is now different), `touched` the `update` event's (every state said again, different or not).
#[derive(Default)]
struct Touched {
    added: Vec<u64>,
    updated: Vec<u64>,
    touched: Vec<u64>,
    removed: Vec<u64>,
}

impl Touched {
    fn json(&self) -> Value {
        json!({ "added": self.added, "updated": self.updated, "touched": self.touched, "removed": self.removed })
    }
}

fn now_ms() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_millis() as u64).unwrap_or(0)
}

/// lib0's variable-length unsigned integer: seven bits a byte, least significant first.
fn write_var(out: &mut Vec<u8>, mut value: u64) {
    while value > 0x7f {
        out.push(0x80 | (value & 0x7f) as u8);
        value >>= 7;
    }
    out.push(value as u8);
}

fn read_var(bytes: &[u8], at: &mut usize) -> Result<u64, String> {
    let mut value = 0u64;
    let mut shift = 0u32;
    loop {
        let byte = *bytes.get(*at).ok_or("That awareness update ends early.")?;
        *at += 1;
        if shift > 56 {
            return Err("That awareness update holds a number too large.".to_string());
        }
        value |= u64::from(byte & 0x7f) << shift;
        if byte < 0x80 {
            return Ok(value);
        }
        shift += 7;
    }
}

impl Aware {
    /// A room's awareness with this device in it, saying nothing yet: the constructor's `setLocalState({})`.
    fn new(client: u64, now: u64) -> Aware {
        let mut aware = Aware { client, states: BTreeMap::new(), meta: BTreeMap::new() };
        aware.set_local(Some(json!({})), now);
        aware
    }

    /// `setLocalState`: this device's state replaced (or removed with `None`), its clock one on.
    fn set_local(&mut self, state: Option<Value>, now: u64) -> Touched {
        let clock = self.meta.get(&self.client).map_or(0, |meta| meta.clock + 1);
        let before = self.states.get(&self.client).cloned();
        let mut touched = Touched::default();
        match (&state, &before) {
            (None, _) => touched.removed.push(self.client),
            (Some(_), None) => touched.added.push(self.client),
            (Some(state), Some(before)) => {
                touched.touched.push(self.client);
                if state != before {
                    touched.updated.push(self.client);
                }
            }
        }
        match state {
            Some(state) => self.states.insert(self.client, state),
            None => self.states.remove(&self.client),
        };
        self.meta.insert(self.client, Meta { clock, heard_ms: now });
        touched
    }

    /// `encodeAwarenessUpdate`: for each client its id, its clock and its state as JSON text (`null` when gone).
    /// A client never heard of is left out, where the page would have thrown.
    fn encode(&self, clients: &[u64]) -> Vec<u8> {
        let known: Vec<(&u64, &Meta)> = clients.iter().filter_map(|client| self.meta.get(client).map(|meta| (client, meta))).collect();
        let mut out = Vec::new();
        write_var(&mut out, known.len() as u64);
        for (client, meta) in known {
            write_var(&mut out, *client);
            write_var(&mut out, meta.clock);
            let state = self.states.get(client).map_or_else(|| "null".to_string(), Value::to_string);
            write_var(&mut out, state.len() as u64);
            out.extend_from_slice(state.as_bytes());
        }
        out
    }

    /// `applyAwarenessUpdate`. Read whole before any of it is applied.
    fn apply(&mut self, update: &[u8], now: u64) -> Result<Touched, String> {
        let mut at = 0;
        let count = read_var(update, &mut at)?;
        let mut said = Vec::new();
        for _ in 0..count {
            let client = read_var(update, &mut at)?;
            let clock = read_var(update, &mut at)?;
            let length = read_var(update, &mut at)? as usize;
            let text = update.get(at..at.saturating_add(length)).ok_or("That awareness update ends early.")?;
            at += length;
            let state: Value = serde_json::from_slice(text).map_err(|_| "That awareness update holds a state that is not JSON.".to_string())?;
            said.push((client, clock, state));
        }
        let mut touched = Touched::default();
        for (client, mut clock, state) in said {
            let known = self.meta.get(&client).map(|meta| meta.clock);
            let before = self.states.get(&client).cloned();
            let current = known.unwrap_or(0);
            if !(current < clock || (current == clock && state.is_null() && before.is_some())) {
                continue;
            }
            if state.is_null() {
                // Never let another device remove this one's state: say it is still here, a clock on.
                if client == self.client && before.is_some() {
                    clock += 1;
                } else {
                    self.states.remove(&client);
                }
            } else {
                self.states.insert(client, state.clone());
            }
            self.meta.insert(client, Meta { clock, heard_ms: now });
            if known.is_none() && !state.is_null() {
                touched.added.push(client);
            } else if known.is_some() && state.is_null() {
                touched.removed.push(client);
            } else if !state.is_null() {
                if Some(&state) != before.as_ref() {
                    touched.updated.push(client);
                }
                touched.touched.push(client);
            }
        }
        Ok(touched)
    }

    /// `removeAwarenessStates`: the clients that left with a connection, or went quiet.
    fn remove(&mut self, clients: &[u64], now: u64) -> Vec<u64> {
        let mut removed = Vec::new();
        for client in clients {
            if self.states.remove(client).is_some() {
                if *client == self.client {
                    if let Some(meta) = self.meta.get_mut(client) {
                        meta.clock += 1;
                        meta.heard_ms = now;
                    }
                }
                removed.push(*client);
            }
        }
        removed
    }

    /// What y-protocols does every three seconds: this device's state said again once it is fifteen seconds old,
    /// and every other client unheard for thirty forgotten. Answers the update to send, if any, and who went.
    fn tick(&mut self, now: u64) -> (Option<Vec<u8>>, Vec<u64>) {
        let mut update = None;
        if let (Some(state), Some(meta)) = (self.states.get(&self.client).cloned(), self.meta.get(&self.client)) {
            if OUTDATED_MS / 2 <= now.saturating_sub(meta.heard_ms) {
                self.set_local(Some(state), now);
                update = Some(self.encode(&[self.client]));
            }
        }
        let quiet: Vec<u64> = self.meta.iter().filter(|(client, meta)| **client != self.client && OUTDATED_MS <= now.saturating_sub(meta.heard_ms) && self.states.contains_key(client)).map(|(client, _)| *client).collect();
        let removed = self.remove(&quiet, now);
        (update, removed)
    }
}

// --- what this process holds --------------------------------------------------------

struct Table<T> {
    next: u64,
    held: HashMap<u64, Arc<Mutex<T>>>,
}

impl<T> Table<T> {
    fn new() -> Table<T> {
        Table { next: 1, held: HashMap::new() }
    }
}

static DOCS: Mutex<Option<Table<Held>>> = Mutex::new(None);
static ROOMS: Mutex<Option<Table<Aware>>> = Mutex::new(None);

fn hold<T>(table: &Mutex<Option<Table<T>>>, value: T) -> u64 {
    let mut table = crate::lock::lock(table);
    let table = table.get_or_insert_with(Table::new);
    let handle = table.next;
    table.next += 1;
    table.held.insert(handle, Arc::new(Mutex::new(value)));
    handle
}

fn held<T>(table: &Mutex<Option<Table<T>>>, handle: u64, what: &str) -> Result<Arc<Mutex<T>>, String> {
    crate::lock::lock(table).as_ref().and_then(|table| table.held.get(&handle).cloned()).ok_or_else(|| format!("That {what} is not held any more."))
}

fn drop_held<T>(table: &Mutex<Option<Table<T>>>, handle: u64) -> bool {
    crate::lock::lock(table).as_mut().is_some_and(|table| table.held.remove(&handle).is_some())
}

// --- the commands -------------------------------------------------------------------

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpenDoc {
    state: Option<String>,
    #[serde(default)]
    pending: Vec<String>,
    words: Option<String>,
    client_id: Option<u64>,
}

#[derive(Deserialize)]
struct ByDoc {
    doc: u64,
}

#[derive(Deserialize)]
struct Diff {
    doc: u64,
    to: String,
}

#[derive(Deserialize)]
struct Edit {
    index: u32,
    #[serde(default)]
    remove: u32,
    #[serde(default)]
    insert: String,
}

#[derive(Deserialize)]
struct Edits {
    doc: u64,
    edits: Vec<Edit>,
}

#[derive(Deserialize)]
struct State {
    doc: u64,
    vector: Option<String>,
}

#[derive(Deserialize)]
struct Apply {
    doc: u64,
    updates: Vec<String>,
}

#[derive(Deserialize)]
struct Posted {
    doc: u64,
    count: usize,
}

#[derive(Deserialize)]
struct Lacks {
    mine: String,
    theirs: String,
}

#[derive(Deserialize)]
struct Relative {
    doc: u64,
    index: u32,
    assoc: Option<i64>,
}

#[derive(Deserialize)]
struct Absolute {
    doc: u64,
    position: Value,
}

#[derive(Deserialize)]
struct CanvasWrite {
    doc: u64,
    canvas: Value,
    #[serde(default)]
    seed: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct OpenRoom {
    client_id: u64,
}

#[derive(Deserialize)]
struct ByRoom {
    awareness: u64,
}

#[derive(Deserialize)]
struct SetLocal {
    awareness: u64,
    /// The whole state, `null` to leave; or one `field` of it and its `value`.
    #[serde(default, deserialize_with = "present")]
    state: Option<Value>,
    field: Option<String>,
    #[serde(default)]
    value: Value,
}

/// A field that was sent, `null` included: `Some(Value::Null)` where a plain `Option` would read `None`.
fn present<'de, D: serde::Deserializer<'de>>(deserializer: D) -> Result<Option<Value>, D::Error> {
    Value::deserialize(deserializer).map(Some)
}

#[derive(Deserialize)]
struct Encode {
    awareness: u64,
    clients: Option<Vec<u64>>,
}

#[derive(Deserialize)]
struct ApplyRoom {
    awareness: u64,
    update: String,
}

#[derive(Deserialize)]
struct Remove {
    awareness: u64,
    clients: Vec<u64>,
}

#[derive(Deserialize)]
struct Tick {
    awareness: u64,
    now: Option<u64>,
}

fn read<T: serde::de::DeserializeOwned>(command: &str, args: Value) -> Result<T, String> {
    serde_json::from_value(args).map_err(|e| format!("invalid args for command `{command}`: {e}"))
}

/// `f` with document `handle`, under its own lock.
fn with_doc<T>(handle: u64, f: impl FnOnce(&mut Held) -> Result<T, String>) -> Result<T, String> {
    let held = held(&DOCS, handle, "document")?;
    let mut held = crate::lock::lock(&held);
    f(&mut held)
}

/// `f` with room `handle`'s awareness, under its own lock.
fn with_room<T>(handle: u64, f: impl FnOnce(&mut Aware) -> Result<T, String>) -> Result<T, String> {
    let held = held(&ROOMS, handle, "room")?;
    let mut held = crate::lock::lock(&held);
    f(&mut held)
}

fn changed(update: Option<Vec<u8>>, text: String) -> Value {
    json!({ "changed": update.is_some(), "update": update.map(|update| to_base64url(&update)), "text": text })
}

/// One of this module's commands. The table in the header says what each takes and answers.
pub fn call(command: &str, args: Value) -> Result<Value, String> {
    match command {
        // doc.ts `make`: a kept document (its state, and what was pending when it was kept), or a new one seeded
        // with the note's words, the whole of it pending for the service.
        "crdt_open" => {
            let OpenDoc { state, pending, words, client_id } = read(command, args)?;
            let client = match client_id {
                Some(client) => client,
                None => new_client()?,
            };
            let mut made = Held::new(client)?;
            if let Some(state) = state {
                made.apply_remote(&[from_base64url(&state)?])?;
                made.pending = pending.iter().map(|update| from_base64url(update)).collect::<Result<_, _>>()?;
            } else if let Some(words) = words.filter(|words| !words.is_empty()) {
                made.change(&[(0, 0, words)])?;
                made.pending = vec![made.state(None)];
            }
            let text = made.words();
            Ok(json!({ "doc": hold(&DOCS, made), "clientId": client, "text": text }))
        }
        "crdt_close" => {
            let ByDoc { doc } = read(command, args)?;
            Ok(json!(drop_held(&DOCS, doc)))
        }
        "crdt_text" => {
            let ByDoc { doc } = read(command, args)?;
            with_doc(doc, |held| Ok(json!(held.words())))
        }
        "crdt_apply_diff" => {
            let Diff { doc, to } = read(command, args)?;
            with_doc(doc, |held| {
                let update = held.reconcile(&to)?;
                Ok(changed(update, held.words()))
            })
        }
        "crdt_edit" => {
            let Edits { doc, edits } = read(command, args)?;
            let edits: Vec<(u32, u32, String)> = edits.into_iter().map(|edit| (edit.index, edit.remove, edit.insert)).collect();
            with_doc(doc, |held| {
                let update = held.change(&edits)?;
                Ok(changed(update, held.words()))
            })
        }
        "crdt_state" => {
            let State { doc, vector } = read(command, args)?;
            // An empty vector is a device with nothing: team.ts sends one from a room with no document.
            let vector = match vector.filter(|vector| !vector.is_empty()) {
                Some(vector) => Some(decode_vector(&from_base64url(&vector)?)?),
                None => None,
            };
            with_doc(doc, |held| Ok(json!(to_base64url(&held.state(vector.as_ref())))))
        }
        "crdt_vector" => {
            let ByDoc { doc } = read(command, args)?;
            with_doc(doc, |held| Ok(json!(to_base64url(&held.doc.transact().state_vector().encode_v1()))))
        }
        "crdt_apply" => {
            let Apply { doc, updates } = read(command, args)?;
            let updates = updates.iter().map(|update| from_base64url(update)).collect::<Result<Vec<_>, _>>()?;
            with_doc(doc, |held| {
                let before = held.words();
                held.apply_remote(&updates)?;
                let after = held.words();
                Ok(json!({ "changed": after != before, "text": after }))
            })
        }
        "crdt_pending" => {
            let ByDoc { doc } = read(command, args)?;
            with_doc(doc, |held| Ok(json!(held.pending.iter().map(|update| to_base64url(update)).collect::<Vec<_>>())))
        }
        "crdt_posted" => {
            let Posted { doc, count } = read(command, args)?;
            with_doc(doc, |held| {
                let count = count.min(held.pending.len());
                held.pending.drain(..count);
                Ok(json!(held.pending.len()))
            })
        }
        "crdt_lacks" => {
            let Lacks { mine, theirs } = read(command, args)?;
            let vector = |text: &str| -> Result<StateVector, String> {
                if text.is_empty() {
                    return Ok(StateVector::default());
                }
                decode_vector(&from_base64url(text)?)
            };
            let (mine, theirs) = (vector(&mine)?, vector(&theirs)?);
            Ok(json!(theirs.iter().any(|(client, clock)| mine.get(client) < *clock)))
        }
        "crdt_relative" => {
            let Relative { doc, index, assoc } = read(command, args)?;
            with_doc(doc, |held| Ok(held.relative(index, assoc.unwrap_or(0))))
        }
        "crdt_absolute" => {
            let Absolute { doc, position } = read(command, args)?;
            with_doc(doc, |held| Ok(json!(held.absolute(&position)?)))
        }
        "crdt_canvas_has" => {
            let ByDoc { doc } = read(command, args)?;
            with_doc(doc, |held| Ok(json!(held.canvas_seeded())))
        }
        "crdt_canvas_read" => {
            let ByDoc { doc } = read(command, args)?;
            with_doc(doc, |held| Ok(held.canvas_read()))
        }
        "crdt_canvas_write" => {
            let CanvasWrite { doc, canvas, seed } = read(command, args)?;
            with_doc(doc, |held| {
                let update = held.canvas_write(&canvas, seed)?;
                Ok(changed(update, held.words()))
            })
        }
        "awareness_open" => {
            let OpenRoom { client_id } = read(command, args)?;
            if client_id > MAX_CLIENT {
                return Err("A client id is at most 53 bits.".to_string());
            }
            let aware = Aware::new(client_id, now_ms());
            let update = to_base64url(&aware.encode(&[client_id]));
            Ok(json!({ "awareness": hold(&ROOMS, aware), "update": update }))
        }
        "awareness_close" => {
            let ByRoom { awareness } = read(command, args)?;
            Ok(json!(drop_held(&ROOMS, awareness)))
        }
        "awareness_set" => {
            let SetLocal { awareness, state, field, value } = read(command, args)?;
            with_room(awareness, |aware| {
                let state = match (state, field) {
                    (Some(Value::Null), None) => None,
                    (Some(state), None) => Some(state),
                    // `setLocalStateField`: nothing to set a field of once this device has left.
                    (None, Some(field)) => {
                        let Some(Value::Object(mut state)) = aware.states.get(&aware.client).cloned() else {
                            return Ok(json!({ "update": Value::Null, "added": [], "updated": [], "touched": [], "removed": [] }));
                        };
                        state.insert(field, value);
                        Some(Value::Object(state))
                    }
                    _ => return Err("awareness_set takes a state, or a field and its value.".to_string()),
                };
                let mut said = aware.set_local(state, now_ms()).json();
                said["update"] = json!(to_base64url(&aware.encode(&[aware.client])));
                Ok(said)
            })
        }
        "awareness_encode" => {
            let Encode { awareness, clients } = read(command, args)?;
            with_room(awareness, |aware| {
                let clients = clients.unwrap_or_else(|| aware.states.keys().copied().collect());
                Ok(json!(to_base64url(&aware.encode(&clients))))
            })
        }
        "awareness_apply" => {
            let ApplyRoom { awareness, update } = read(command, args)?;
            let update = from_base64url(&update)?;
            with_room(awareness, |aware| Ok(aware.apply(&update, now_ms())?.json()))
        }
        "awareness_remove" => {
            let Remove { awareness, clients } = read(command, args)?;
            with_room(awareness, |aware| Ok(json!({ "removed": aware.remove(&clients, now_ms()) })))
        }
        "awareness_states" => {
            let ByRoom { awareness } = read(command, args)?;
            with_room(awareness, |aware| {
                let states: Vec<Value> = aware.states.iter().map(|(client, state)| json!({ "client": client, "clock": aware.meta.get(client).map_or(0, |meta| meta.clock), "state": state })).collect();
                Ok(json!(states))
            })
        }
        "awareness_tick" => {
            let Tick { awareness, now } = read(command, args)?;
            with_room(awareness, |aware| {
                let (update, removed) = aware.tick(now.unwrap_or_else(now_ms));
                Ok(json!({ "update": update.map(|update| to_base64url(&update)), "removed": removed }))
            })
        }
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ask(command: &str, args: Value) -> Value {
        call(command, args).unwrap_or_else(|e| panic!("{command}: {e}"))
    }

    fn open(args: Value) -> u64 {
        ask("crdt_open", args)["doc"].as_u64().unwrap()
    }

    fn text(doc: u64) -> String {
        ask("crdt_text", json!({"doc": doc})).as_str().unwrap().to_string()
    }

    #[test]
    fn a_seeded_document_holds_its_words_and_the_whole_of_it_is_pending() {
        let made = ask("crdt_open", json!({"words": "# Plan\n\nFirst.\n", "clientId": 7}));
        assert_eq!((made["clientId"].as_u64(), made["text"].as_str()), (Some(7), Some("# Plan\n\nFirst.\n")));
        let doc = made["doc"].as_u64().unwrap();
        let pending = ask("crdt_pending", json!({"doc": doc}));
        assert_eq!(pending, json!([ask("crdt_state", json!({"doc": doc}))]), "doc.ts: pending = [Y.encodeStateAsUpdate(doc)]");
        // A device with nothing takes the pending update and has the words.
        let other = open(json!({"clientId": 8}));
        assert_eq!(text(other), "");
        assert_eq!(ask("crdt_pending", json!({"doc": other})), json!([]));
        let got = ask("crdt_apply", json!({"doc": other, "updates": pending}));
        assert_eq!(got, json!({"changed": true, "text": "# Plan\n\nFirst.\n"}));
        assert_eq!(ask("crdt_pending", json!({"doc": other})), json!([]), "what arrives is not owed back");
        assert_eq!(ask("crdt_apply", json!({"doc": other, "updates": pending}))["changed"], false, "an update is idempotent");
        // A random client id is thirty-two bits, as Yjs's is.
        assert!(ask("crdt_open", json!({}))["clientId"].as_u64().unwrap() <= u64::from(u32::MAX));
        assert_eq!(call("crdt_open", json!({"clientId": 1u64 << 53})), Err("A client id is at most 53 bits.".into()));
    }

    #[test]
    fn a_reconcile_keeps_the_common_head_and_foot_and_queues_one_update() {
        let doc = open(json!({"words": "one two three", "clientId": 1}));
        ask("crdt_posted", json!({"doc": doc, "count": 1}));
        let said = ask("crdt_apply_diff", json!({"doc": doc, "to": "one 2 three"}));
        assert_eq!((said["changed"].as_bool(), said["text"].as_str()), (Some(true), Some("one 2 three")));
        assert_eq!(ask("crdt_pending", json!({"doc": doc})), json!([said["update"]]));
        // Only the middle went and came: a peer that typed at the end at the same moment keeps its words.
        let peer = open(json!({"clientId": 2}));
        ask("crdt_apply", json!({"doc": peer, "updates": [ask("crdt_state", json!({"doc": doc, "vector": ""}))]}));
        let theirs = ask("crdt_apply_diff", json!({"doc": peer, "to": "one 2 three four"}));
        let mine = ask("crdt_apply_diff", json!({"doc": doc, "to": "zero one 2 three"}));
        ask("crdt_apply", json!({"doc": doc, "updates": [theirs["update"]]}));
        ask("crdt_apply", json!({"doc": peer, "updates": [mine["update"]]}));
        assert_eq!(text(doc), "zero one 2 three four");
        assert_eq!(text(peer), text(doc));
        // The same words again change nothing and queue nothing.
        let same = ask("crdt_apply_diff", json!({"doc": doc, "to": "zero one 2 three four"}));
        assert_eq!(same, json!({"changed": false, "update": null, "text": "zero one 2 three four"}));
        assert_eq!(ask("crdt_posted", json!({"doc": doc, "count": 99})), 0);
    }

    #[test]
    fn offsets_are_utf16_and_a_character_is_never_split() {
        let doc = open(json!({"words": "a😀b", "clientId": 1}));
        // "😀" to "😁" share their first code unit; the whole character goes and comes.
        ask("crdt_apply_diff", json!({"doc": doc, "to": "a😁b"}));
        assert_eq!(text(doc), "a😁b");
        ask("crdt_apply_diff", json!({"doc": doc, "to": "a😁😁b"}));
        assert_eq!(text(doc), "a😁😁b");
        ask("crdt_apply_diff", json!({"doc": doc, "to": "a😁b"}));
        assert_eq!(text(doc), "a😁b");
        // An editor's change at code unit 3 is after the emoji.
        let said = ask("crdt_edit", json!({"doc": doc, "edits": [{"index": 3, "insert": "é"}, {"index": 0, "remove": 1}]}));
        assert_eq!(said["text"], "😁éb");
        assert_eq!(call("crdt_edit", json!({"doc": doc, "edits": [{"index": 1, "insert": "x"}]})), Err("A change may not split a character in two.".into()));
        assert!(call("crdt_edit", json!({"doc": doc, "edits": [{"index": 3, "remove": 9}]})).unwrap_err().contains("runs past the end"));
        assert_eq!(text(doc), "😁éb", "a refused change changed nothing");
        assert_eq!(ask("crdt_edit", json!({"doc": doc, "edits": []}))["changed"], false);
        // A peer built from the pending updates alone has the same words.
        let peer = open(json!({"clientId": 2}));
        ask("crdt_apply", json!({"doc": peer, "updates": ask("crdt_pending", json!({"doc": doc}))}));
        assert_eq!(text(peer), "😁éb");
    }

    #[test]
    fn a_kept_document_comes_back_with_what_was_pending() {
        let doc = open(json!({"words": "kept", "clientId": 3}));
        ask("crdt_apply_diff", json!({"doc": doc, "to": "kept words"}));
        let (state, pending) = (ask("crdt_state", json!({"doc": doc})), ask("crdt_pending", json!({"doc": doc})));
        assert_eq!(pending.as_array().unwrap().len(), 2);
        assert_eq!(ask("crdt_close", json!({"doc": doc})), true);
        assert_eq!(call("crdt_text", json!({"doc": doc})), Err("That document is not held any more.".into()));
        let again = ask("crdt_open", json!({"state": state, "pending": pending, "clientId": 3}));
        assert_eq!(again["text"], "kept words");
        let again = again["doc"].as_u64().unwrap();
        assert_eq!(ask("crdt_pending", json!({"doc": again})), pending);
        assert_eq!(ask("crdt_posted", json!({"doc": again, "count": 1})), 1);
        assert_eq!(ask("crdt_vector", json!({"doc": again})), ask("crdt_vector", json!({"doc": again})));
        assert!(call("crdt_apply", json!({"doc": again, "updates": ["AAECAwQF_w"]})).is_err());
        assert_eq!(text(again), "kept words");
    }

    #[test]
    fn a_state_vector_says_what_a_peer_lacks() {
        let (a, b) = (open(json!({"words": "shared", "clientId": 1})), open(json!({"clientId": 2})));
        let (va, vb) = (ask("crdt_vector", json!({"doc": a})), ask("crdt_vector", json!({"doc": b})));
        assert_eq!(ask("crdt_lacks", json!({"mine": vb, "theirs": va})), true);
        assert_eq!(ask("crdt_lacks", json!({"mine": va, "theirs": vb})), false);
        assert_eq!(ask("crdt_lacks", json!({"mine": "", "theirs": va})), true);
        // Only what the vector lacks is sent.
        let diff = ask("crdt_state", json!({"doc": a, "vector": vb}));
        ask("crdt_apply", json!({"doc": b, "updates": [diff]}));
        ask("crdt_apply_diff", json!({"doc": a, "to": "shared words"}));
        let vb = ask("crdt_vector", json!({"doc": b}));
        let small = ask("crdt_state", json!({"doc": a, "vector": vb}));
        assert!(small.as_str().unwrap().len() < ask("crdt_state", json!({"doc": a})).as_str().unwrap().len());
        assert_eq!(ask("crdt_apply", json!({"doc": b, "updates": [small]}))["text"], "shared words");
        assert_eq!(ask("crdt_lacks", json!({"mine": ask("crdt_vector", json!({"doc": b})), "theirs": ask("crdt_vector", json!({"doc": a}))})), false);
    }

    #[test]
    fn a_relative_position_stays_with_its_character() {
        let doc = open(json!({"words": "hello world", "clientId": 5}));
        let at = ask("crdt_relative", json!({"doc": doc, "index": 6}));
        assert_eq!(at, json!({"tname": "body", "item": {"client": 5, "clock": 6}, "assoc": 0}));
        assert_eq!(ask("crdt_relative", json!({"doc": doc, "index": 6, "assoc": -1})), json!({"tname": "body", "item": {"client": 5, "clock": 5}, "assoc": -1}));
        // The end of the words, and anything past it, is the type itself.
        let end = ask("crdt_relative", json!({"doc": doc, "index": 11}));
        assert_eq!(end, json!({"tname": "body", "assoc": 0}));
        assert_eq!(ask("crdt_relative", json!({"doc": doc, "index": 99})), end);
        assert_eq!(ask("crdt_relative", json!({"doc": doc, "index": 0, "assoc": -1})), json!({"tname": "body", "assoc": -1}));

        ask("crdt_apply_diff", json!({"doc": doc, "to": "oh, hello world"}));
        assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": at})), 10);
        assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": end})), 15);
        assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": {"tname": "body", "assoc": -1}})), 0);
        // Something this copy was never given, and another field's position, cannot be placed.
        assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": {"tname": "body", "item": {"client": 99, "clock": 3}, "assoc": 0}})), Value::Null);
        assert_eq!(ask("crdt_absolute", json!({"doc": doc, "position": {"tname": "title", "assoc": 0}})), Value::Null);
        assert!(call("crdt_absolute", json!({"doc": doc, "position": {"assoc": 0}})).is_err());
    }

    #[test]
    fn awareness_is_who_is_here_by_clock_and_never_lets_another_remove_this_device() {
        let a = Aware::new(1, 0);
        assert_eq!(a.encode(&[1]), [1, 1, 0, 2, b'{', b'}'], "one client; id 1, clock 0, the two characters of an empty state");
        let (mut a, mut b) = (a, Aware::new(300, 0));
        let user = json!({"user": {"name": "matt", "hue": "moss"}, "cursor": {"anchor": {"tname": "body", "assoc": 0}, "head": {"tname": "body", "assoc": 0}}});
        let touched = a.set_local(Some(user.clone()), 10);
        assert_eq!((touched.updated.as_slice(), touched.touched.as_slice()), (&[1u64][..], &[1u64][..]));
        let heard = b.apply(&a.encode(&[1]), 20).unwrap();
        assert_eq!((heard.added.as_slice(), b.states.get(&1)), (&[1u64][..], Some(&user)));
        // The same again is older news: nothing.
        assert!(b.apply(&a.encode(&[1]), 30).unwrap().json() == Touched::default().json());
        // Said again unchanged: touched, not updated.
        a.set_local(Some(user.clone()), 40);
        let again = b.apply(&a.encode(&[1]), 50).unwrap();
        assert_eq!((again.updated.len(), again.touched.as_slice()), (0, &[1u64][..]));
        // Leaving is a null state at a later clock.
        a.set_local(None, 60);
        assert_eq!(b.apply(&a.encode(&[1]), 70).unwrap().removed, [1]);
        assert!(!b.states.contains_key(&1));
        // Another device saying this one has left is answered by a clock one on, and the state stays.
        let mut liar = Aware::new(300, 0);
        liar.set_local(None, 0);
        let before = b.meta[&300].clock;
        b.apply(&liar.encode(&[300]), 80).unwrap();
        assert!(b.states.contains_key(&300) && b.meta[&300].clock == before + 2, "the removal's clock, and one on");
        // A long client id and a state with every kind of character survive the wire.
        let mut far = Aware::new(MAX_CLIENT, 0);
        far.set_local(Some(json!({"user": {"name": "día ✓ 😀"}})), 0);
        b.apply(&far.encode(&[MAX_CLIENT]), 90).unwrap();
        assert_eq!(b.states[&MAX_CLIENT]["user"]["name"], "día ✓ 😀");
        assert!(b.apply(&[2, 1], 0).is_err() && b.apply(&[1, 5, 9, 3, b'{'], 0).is_err());
    }

    #[test]
    fn a_quiet_client_is_forgotten_and_this_device_says_it_is_still_here() {
        let mut a = Aware::new(1, 0);
        let mut b = Aware::new(2, 0);
        // A device's first empty state, at clock 0, is news to nobody (y-protocols asks for a later clock than
        // the 0 it assumes of a stranger): it is heard of when it first says something.
        assert!(a.apply(&b.encode(&[2]), 500).unwrap().added.is_empty() && !a.states.contains_key(&2));
        b.set_local(Some(json!({"user": {"name": "sam"}})), 900);
        assert_eq!(a.apply(&b.encode(&[2]), 1_000).unwrap().added, [2]);
        assert_eq!(a.tick(14_999), (None, vec![]));
        let (update, removed) = a.tick(15_000);
        assert!(update.is_some() && removed.is_empty());
        assert_eq!(a.meta[&1].clock, 1);
        assert_eq!(b.apply(&update.unwrap(), 15_000).unwrap().added, [1]);
        let (_, removed) = a.tick(31_000);
        assert_eq!(removed, [2]);
        assert!(!a.states.contains_key(&2));
        assert_eq!(a.remove(&[1, 2, 9], 31_000), [1], "this device's own leaving is a clock on");
    }

    #[test]
    fn the_awareness_commands_carry_user_and_cursor_between_two_rooms() {
        let (mine, theirs) = (ask("awareness_open", json!({"clientId": 11})), ask("awareness_open", json!({"clientId": 12})));
        let (a, b) = (mine["awareness"].as_u64().unwrap(), theirs["awareness"].as_u64().unwrap());
        let said = ask("awareness_set", json!({"awareness": a, "field": "user", "value": {"name": "matt", "hue": null, "color": "var(--app-ink)"}}));
        assert_eq!(said["updated"], json!([11]));
        assert_eq!(ask("awareness_apply", json!({"awareness": b, "update": said["update"]}))["added"], json!([11]));
        let cursor = json!({"anchor": {"tname": "body", "item": {"client": 5, "clock": 6}, "assoc": 0}, "head": {"tname": "body", "assoc": 0}});
        let said = ask("awareness_set", json!({"awareness": a, "field": "cursor", "value": cursor}));
        assert_eq!(ask("awareness_apply", json!({"awareness": b, "update": said["update"]}))["updated"], json!([11]));
        let states = ask("awareness_states", json!({"awareness": b}));
        assert_eq!(states[0], json!({"client": 11, "clock": 2, "state": {"user": {"name": "matt", "hue": null, "color": "var(--app-ink)"}, "cursor": cursor}}));
        assert_eq!(states[1], json!({"client": 12, "clock": 0, "state": {}}));
        // Everyone known, for a device that has just joined.
        ask("awareness_set", json!({"awareness": b, "field": "user", "value": {"name": "sam"}}));
        let all = ask("awareness_encode", json!({"awareness": b}));
        let late = ask("awareness_open", json!({"clientId": 13}))["awareness"].as_u64().unwrap();
        assert_eq!(ask("awareness_apply", json!({"awareness": late, "update": all}))["added"], json!([11, 12]));
        // Leaving: a null state; and the room let go.
        let left = ask("awareness_set", json!({"awareness": a, "state": null}));
        assert_eq!(left["removed"], json!([11]));
        assert_eq!(ask("awareness_apply", json!({"awareness": b, "update": left["update"]}))["removed"], json!([11]));
        assert_eq!(ask("awareness_set", json!({"awareness": a, "field": "cursor", "value": 1}))["update"], Value::Null);
        assert_eq!(ask("awareness_remove", json!({"awareness": late, "clients": [12, 99]}))["removed"], json!([12]));
        assert_eq!(ask("awareness_tick", json!({"awareness": late, "now": 0})), json!({"update": null, "removed": []}));
        assert_eq!(ask("awareness_close", json!({"awareness": a})), true);
        assert_eq!(call("awareness_states", json!({"awareness": a})), Err("That room is not held any more.".into()));
    }
}
