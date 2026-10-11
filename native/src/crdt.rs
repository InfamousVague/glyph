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
//! - **Undo in a live note is the document's own** (docs/PARITY.md, Differs 26): the page swaps CodeMirror's
//!   history for `Y.UndoManager` over the note's text while an editor is bound to it (`editor/liveBinding.ts`,
//!   y-codemirror's `yCollab`), and so does this, with yrs's `UndoManager` (`Undo`, below). It follows the changes
//!   an editor made (`crdt_edit`, which is the binding's origin) and nothing else: not what arrives, not a
//!   reconcile. An undo or a redo is a change like any other made here: one update, queued in `pending`.
//! - **No lock of the notes'**, and no `init`: dispatch.rs answers these before it looks for the library.
//!
//! | command | takes | answers |
//! | --- | --- | --- |
//! | `crdt_open` | `{state?, pending?, words?, clientId?}` | `{doc, clientId, text}` |
//! | `crdt_close` | `{doc}` | whether there was one |
//! | `crdt_text` | `{doc}` | the words |
//! | `crdt_apply_diff` | `{doc, to}` | `{changed, update, text, undo?}`: doc.ts `reconcile` (`undo`, here and below: what the undo holds after it, while an editor is bound) |
//! | `crdt_edit` | `{doc, edits: [{index, remove?, insert?}], now?}` | `{changed, update, text, undo?}`: an editor's own changes, in order, as one |
//! | `crdt_state` | `{doc, vector?}` | the whole document as an update, or what `vector` lacks |
//! | `crdt_vector` | `{doc}` | the state vector |
//! | `crdt_apply` | `{doc, updates}` | `{changed, text, splices?, undo?}`: doc.ts `applyRemote`, and the words' own account of the change where they gave one |
//! | `crdt_pending` | `{doc}` | the updates not yet with the service, in order |
//! | `crdt_posted` | `{doc, count}` | how many are still pending |
//! | `crdt_lacks` | `{mine, theirs}` | whether `theirs` holds anything `mine` lacks (live/team.ts `lacks`) |
//! | `crdt_relative` | `{doc, index, assoc?}` | a relative position, as `Y.relativePositionToJSON` writes one |
//! | `crdt_absolute` | `{doc, position}` | its index now, or `null` |
//! | `crdt_canvas_has` | `{doc}` | whether the document's types hold a canvas yet (canvas.ts `hasTeamCanvas`) |
//! | `crdt_canvas_read` | `{doc}` | `{nodes, edges, comments}`: the canvas the types hold (canvas.ts `read`, before it is parsed) |
//! | `crdt_canvas_write` | `{doc, canvas: {nodes, edges, comments?}, seed?}` | `{changed, update, text}`: canvas.ts `write`, only what differs, as one change |
//! | `crdt_undo_open` | `{doc, captureMs?}` | `{canUndo, canRedo}`: a new undo manager over the words, nothing in it (`new Y.UndoManager(text)`) |
//! | `crdt_undo_close` | `{doc}` | whether there was one: the editor is unbound, and its steps are gone |
//! | `crdt_undo_caret` | `{doc, anchor, head, assoc?}` | whether it was kept: where the editor's selection stands, for the step the next change begins |
//! | `crdt_undo` | `{doc, now?}` | `{changed, update, text, splices, caret, undo}`: the last step taken back, and the selection kept with it |
//! | `crdt_redo` | `{doc, now?}` | the same, for the last step taken back put in again |
//! | `crdt_undo_state` | `{doc}` | `{open, canUndo, canRedo}` |
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
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use serde::Deserialize;
use serde_json::{json, Value};
use yrs::updates::decoder::Decode as _;
use yrs::updates::encoder::Encode as _;
use yrs::types::{Delta, ToJson as _};
use yrs::{Any, Array as _, ArrayPrelim, ArrayRef, Assoc, ClientID, Doc, GetString as _, IndexScope, Map as _, MapPrelim, MapRef, Observable as _, OffsetKind, Options, Origin, Out, ReadTxn, StateVector, StickyIndex, Subscription, Text as _, TextPrelim, TextRef, Transact as _, TransactionMut, Update, ID};
use yrs::undo::UndoManager;

use crate::crypto::{from_base64url, to_base64url};

/// The field a note's words live in (doc.ts `FIELD`).
pub const FIELD: &str = "body";
/// What marks a transaction as one that arrived, for anything that watches the document.
const REMOTE: &str = "remote";
/// What marks a transaction as a bound editor's own: y-codemirror's sync plugin gives its configuration as the
/// origin of every change it writes into the text, and adds that one origin to the undo manager's tracked ones
/// (`YUndoManagerPluginValue`: `addTrackedOrigin(this.syncConf)`).
const EDITOR: &str = "editor";
/// What marks a change made on this device by anything else: textDiff.ts `LOCAL`, which no undo manager tracks.
const LOCAL: &str = "local";
/// How long typing goes on being one step: `Y.UndoManager`'s `captureTimeout`, which liveBinding.ts leaves at its 500.
const CAPTURE_MS: u64 = 500;
/// After this long unheard, a client is forgotten; at half of it this device says it is still here.
/// y-protocols `outdatedTimeout`.
const OUTDATED_MS: u64 = 30_000;
/// The largest client id JavaScript can hold exactly, and so the largest Yjs can carry.
const MAX_CLIENT: u64 = (1 << 53) - 1;

const COMMANDS: [&str; 30] = [
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
    "crdt_undo_open",
    "crdt_undo_close",
    "crdt_undo_caret",
    "crdt_undo",
    "crdt_redo",
    "crdt_undo_state",
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
    /// The undo of the editor bound to this document, while one is (`undo_open`).
    undo: Option<Undo>,
    /// Every block an undo of this copy's has put in again, by the block it was: Yjs's `redone`, which yrs keeps
    /// on the block but follows without the offset (`Undo`, "Where yrs 0.26 is not Yjs"). `absolute` follows this.
    again: Vec<Again>,
}

/// A deleted block (`length` units from `clock` of `client`) that an undo put in again as the units from `to`.
struct Again {
    client: u64,
    clock: u64,
    length: u64,
    to: (u64, u64),
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
        Ok(Held { doc, text, pending: Vec::new(), early: Vec::new(), undo: None, again: Vec::new() })
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
    ///
    /// Answers the change as the words saw it (`splices_of`), each stretch against the words as the one before
    /// left them, for a bound editor to make the same change y-codemirror makes of a text event; `None` when the
    /// words gave no account that can be trusted (the document was made again on the way).
    fn apply_remote(&mut self, updates: &[Vec<u8>]) -> Result<Option<Vec<(u32, u32, String)>>, String> {
        updates.iter().try_for_each(|bytes| decode_update(bytes).map(|_| ()))?;
        // Only words with a character of two units in them can be split, here or as they arrive.
        let pairs = self.words().chars().any(|c| c.len_utf16() == 2);
        let updates = if pairs || updates.iter().any(|bytes| bytes.iter().any(|byte| *byte >= 0xf0)) { self.mended(updates)? } else { updates.to_vec() };
        let decoded = updates.iter().map(|bytes| decode_update(bytes)).collect::<Result<Vec<_>, _>>()?;
        let before = (pairs || self.words().chars().any(|c| c.len_utf16() == 2)).then(|| (self.state(None), self.early.clone()));
        // The document as it stands now is the one that hears the rest (`mended` may have made it again), and
        // each transaction below tells the words what it changed.
        let heard: Arc<Mutex<Vec<Option<Vec<(u32, u32, String)>>>>> = Arc::default();
        let hears = heard.clone();
        let watch: Subscription = self.text.observe(move |txn, event| crate::lock::lock(&hears).push(splices_of(event.delta(txn))));
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
        drop(watch);
        if let Some((before, early)) = before {
            if !self.whole() {
                self.put_back(&before)?;
                self.early = early;
                return Err("That change splits a character in two, which this copy cannot hold as the others do. It was not applied.".to_string());
            }
        }
        let told = std::mem::take(&mut *crate::lock::lock(&heard));
        Ok(told.into_iter().collect::<Option<Vec<_>>>().map(|each| each.into_iter().flatten().collect()))
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
        // An undo manager is its document's: its steps name blocks whose kept words and whose "put in again as"
        // are this copy's alone, and neither is in a state. A document made again starts its undo again, empty.
        let capture = self.undo.take().map(|undo| undo.capture_ms);
        self.again.clear();
        self.doc = again.doc;
        self.text = again.text;
        if let Some(capture) = capture {
            self.undo_open(capture);
        }
        Ok(())
    }

    /// `edits` made here as one transaction, each `(index, remove, insert)` in UTF-16 units against the words as
    /// the edits before it left them. The update it makes is queued and answered; `None` when nothing changed.
    /// `origin` says whose they are: [`EDITOR`] for a bound editor's, which its undo follows, else [`LOCAL`].
    fn change(&mut self, edits: &[(u32, u32, String)], origin: &'static str) -> Result<Option<Vec<u8>>, String> {
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
            let mut txn = self.doc.transact_mut_with(origin);
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
        if origin != EDITOR {
            self.undo_forget();
        }
        self.pending.push(update.clone());
        Ok(Some(update))
    }

    /// The words made `to`, as one change: textDiff.ts `applyTextDiff`, from the words as they are. The common
    /// head and foot are kept and what lies between goes and comes; see the header for the one difference.
    fn reconcile(&mut self, to: &str) -> Result<Option<Vec<u8>>, String> {
        match stretch(&self.words(), to)? {
            Some((head, gone, came)) => self.change(&[(head, gone, came)], LOCAL),
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

    /// The unit an undo of this copy's put `id` in again as, and that one again, to the last: Yjs's `followRedone`,
    /// offset and all. `id` itself when no undo has.
    fn followed(&self, id: ID) -> ID {
        let (mut client, mut clock) = (id.client.get(), u64::from(id.clock));
        // Each block is put in again once, so no more hops than there are of them.
        for _ in 0..=self.again.len() {
            let Some(next) = self.again.iter().find(|next| next.client == client && next.clock <= clock && clock < next.clock + next.length) else { break };
            (client, clock) = (next.to.0, next.to.1 + (clock - next.clock));
        }
        match (client_of(client), u32::try_from(clock)) {
            (Ok(client), Ok(clock)) => ID::new(client, clock),
            _ => id,
        }
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
            StickyIndex::from_id(self.followed(id(item)?), side)
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

// --- undo in a live note ------------------------------------------------------------

/// A caret as two relative positions (`relative`), anchor and head: what y-codemirror keeps with a step (its
/// `YRange`), so the selection can be put back where it stood before the step was made.
type Caret = Option<(Value, Value)>;

/// What the manager's two listeners keep between a command and the change it makes.
#[derive(Default)]
struct Carets {
    /// The editor's selection as last said (`crdt_undo_caret`), for a step that begins with the next change:
    /// y-undomanager.js `_beforeChangeSelection`, stored as positions when the selection is made and given on
    /// `stack-item-added` to a step that has none.
    before: Caret,
    /// The selection kept with the step just taken back or put in again (`stack-item-popped`).
    popped: Caret,
}

/// A bound editor's undo: `new Y.UndoManager(session.text)` as liveBinding.ts makes it and y-codemirror uses it.
///
/// Its steps are the document's own account of what this editor wrote: the blocks it put in and the blocks it
/// took out, by their ids. Taking a step back deletes the first and puts the second in again where they stood,
/// as new blocks beside the old; so the letters another member wrote meanwhile are never touched, and a run put
/// back lands before, among or after theirs as the document orders them, which no history kept beside the
/// document can know.
///
/// - **What it follows**: transactions of origin [`EDITOR`] (`crdt_edit`) and its own. Not [`REMOTE`], not
///   [`LOCAL`], not a canvas's.
/// - **How typing is grouped**: changes less than `capture_ms` apart are one step, and an undo ends the step.
/// - **It lives as long as the binding**: `undo_open` makes a new one with nothing in it, `undo_close` lets it
///   go, and so does `put_back`, which makes the document again (a new one is made for the new document).
///
/// **Where yrs 0.26 is not Yjs, and what is done about each** (the rest is held to the page step for step by
/// test/live/undo_beside_others_test.dart, which also pins each of these three with both answers):
///
/// - **A step whose letters are two runs of one block cannot be taken back.** yrs reads where to cut every run
///   first and then cuts (undo.rs `pop`: `insertions.blocks().collect()`, then `materialize` each), so the second
///   cut is made by places the first has moved, in a block already cut short: an overflow, and in a release
///   build a block of a length it does not have. A step is two runs of one block only when something else this
///   device wrote lies between two of the editor's keys less than the capture time apart, which is a change of
///   origin [`LOCAL`] (a reconcile) or a canvas's, made while an editor is bound. Yjs keeps its steps through one
///   of those. Here the steps are let go at it (`undo_forget`): nothing before it can be taken back, what is
///   typed after it can. Nothing in the app does that to a bound note today: a pass leaves its words alone
///   (lib/team/doc.dart `reconcileKept`) and a canvas is not bound as words. And the steps are looked at as each
///   change is taken and before any is taken back (`undo_sound`): were one ever to hold two runs of one client's
///   letters, the steps are let go and yrs is not asked.
/// - **A block put in again is followed without its offset** (store.rs `follow_redone`: the block's own
///   `redone`, where Yjs's `followRedone` adds `diff`). One hop is right, since yrs cuts the block where the hop
///   starts and a cut block's `redone` is moved along with it. The second is not: letters deleted together and
///   put back are one block, and once that block has been deleted and put back AGAIN, a step whose letters are
///   only its tail is followed to the head of the newest copy.
///   - **For the words, this is NOT made up for, and the two differ**: type `IJ`, wait, type `KL`, delete `JKL`
///     in one go, undo, redo, undo, undo. Yjs has taken back `KL` and holds `IJ`; this holds `I`: the `J`, a
///     letter of the step before, went one undo early. It is this person's own letter, the next undo would have
///     taken it, a redo puts it back, and every member holds the same words; but it is not the page's answer.
///     What makes it right is yrs following with the offset (five lines of store.rs, in
///     native/patches/yrs-0.26.0-undo.patch with what was measured with it); it cannot be done from outside,
///     since which letters Yjs reaches depends on where yrs's blocks are cut, which nothing here can see.
///     test/live/undo_beside_others_test.dart pins the case with both answers.
///   - **For a POSITION it is made up for**: a caret that stood at the end of words deleted and put back is
///     followed here, offset and all, before yrs is asked where it is (`again` below keeps where every block an
///     undo put in went, read from the undo's own updates, which name it; `absolute`).
/// - **A block that was cut stays cut** (store.rs `materialize`, its own "todo: txn merge blocks insert?"), where
///   Yjs joins it again at the end of the transaction when what cut it turned out not to lie inside it. So a
///   deleted run another member wrote "into" while it was gone (after a letter of it, but ordered after the whole
///   run) is two blocks here and one in Yjs, an undo puts it back as two runs, and a letter a member wrote before
///   its first letter at that same moment is ordered against the first run alone: it can land between the two
///   where the page has it after both. NOT made up for (nothing here can join yrs's blocks): every letter of
///   both is there and every member holds the same words, in an order that is not the page's. Met once in four
///   thousand drawn scenarios.
struct Undo {
    manager: UndoManager<Caret>,
    capture_ms: u64,
    /// The time the manager reads, set by each command that may begin or lengthen a step. Never set back: yrs
    /// subtracts the last change's time from it unchecked, and Yjs, reading a clock that went back, still counts
    /// the change as inside the step.
    clock: Arc<AtomicU64>,
    carets: Arc<Mutex<Carets>>,
}

/// Where an editor's selection stands, in UTF-16 units of the words: CodeMirror's `SelectionRange`, as far as
/// y-codemirror reads it (`toYRange`).
#[derive(Deserialize)]
struct CaretAt {
    anchor: u32,
    head: u32,
    #[serde(default)]
    assoc: i64,
}

/// What an undo or a redo did: nothing, when there was no step to take.
#[derive(Default)]
struct Undone {
    /// The change as an update, queued in `pending` like any other made here.
    update: Option<Vec<u8>>,
    /// The change as the words saw it, each `(at, removed, inserted)` in the words as the one before left them.
    splices: Vec<(u32, u32, String)>,
    /// Where the selection stood before the step, in the words as they are now.
    caret: Option<Value>,
}

/// A text event's account of a change as splices, each against the words as the one before it left them; `None`
/// when it holds something that is not words (the note's text never does).
fn splices_of(delta: &[Delta]) -> Option<Vec<(u32, u32, String)>> {
    let mut at = 0u32;
    let mut out = Vec::new();
    for part in delta {
        match part {
            Delta::Retain(length, _) => at += length,
            Delta::Deleted(length) => out.push((at, *length, String::new())),
            Delta::Inserted(Out::Any(Any::String(words)), _) => {
                out.push((at, 0, words.to_string()));
                at += words.encode_utf16().count() as u32;
            }
            Delta::Inserted(..) => return None,
        }
    }
    Some(out)
}

/// `words` after `splices`, or `None` when one does not fit them.
fn spliced(words: &str, splices: &[(u32, u32, String)]) -> Option<Vec<u16>> {
    let mut words: Vec<u16> = words.encode_utf16().collect();
    for (at, removed, inserted) in splices {
        let (at, end) = (*at as usize, *at as usize + *removed as usize);
        if end > words.len() {
            return None;
        }
        words.splice(at..end, inserted.encode_utf16());
    }
    Some(words)
}

impl Undo {
    fn tick(&self, now: Option<u64>) {
        self.clock.fetch_max(now.unwrap_or_else(now_ms), Ordering::Relaxed);
    }

    fn state(&self) -> Value {
        json!({ "open": true, "canUndo": self.manager.can_undo(), "canRedo": self.manager.can_redo() })
    }
}

impl Held {
    /// A new undo manager over the words with nothing in it, in place of any there was: an editor has just been
    /// bound (`bindLive`).
    fn undo_open(&mut self, capture_ms: u64) {
        // The one there was lets go of the document first.
        self.undo = None;
        let clock = Arc::new(AtomicU64::new(0));
        let carets = Arc::new(Mutex::new(Carets::default()));
        let mut options = yrs::undo::Options::<Caret>::default();
        options.capture_timeout_millis = capture_ms;
        options.tracked_origins.insert(Origin::from(EDITOR));
        let read = clock.clone();
        options.timestamp = Arc::new(move || read.load(Ordering::Relaxed));
        let manager = UndoManager::with_scope_and_options(&self.doc, &self.text, options);
        // y-undomanager.js: a step that begins is given the selection as it stood before its first change, and
        // keeps it however long it grows.
        let kept = carets.clone();
        manager.observe_item_added_with(EDITOR, move |_, event| {
            if event.meta().is_none() {
                *event.meta_mut() = crate::lock::lock(&kept).before.clone();
            }
        });
        let kept = carets.clone();
        manager.observe_item_popped_with(EDITOR, move |_, event| {
            crate::lock::lock(&kept).popped = event.meta().clone();
        });
        self.undo = Some(Undo { manager, capture_ms, clock, carets });
    }

    fn undo_state(&self) -> Value {
        self.undo.as_ref().map_or_else(|| json!({ "open": false, "canUndo": false, "canRedo": false }), Undo::state)
    }

    /// Something this device wrote that is not the bound editor's (a reconcile, a canvas) and not the undo's own:
    /// the steps are let go, and a new undo begins with nothing in it. See `Undo`, "Where yrs 0.26 is not Yjs".
    fn undo_forget(&mut self) {
        if let Some(capture) = self.undo.as_ref().map(|undo| undo.capture_ms) {
            self.undo_open(capture);
        }
    }

    /// Whether every step holds at most one run of each client's letters, which is all yrs can take back
    /// (`Undo`, "Where yrs 0.26 is not Yjs").
    fn undo_sound(&self) -> bool {
        let one_run = |steps: &[yrs::undo::StackItem<Caret>]| steps.iter().all(|step| step.insertions().iter().all(|(_, runs)| runs.len() <= 1));
        self.undo.as_ref().is_none_or(|undo| one_run(undo.manager.undo_stack()) && one_run(undo.manager.redo_stack()))
    }

    /// Where the bound editor's selection stands now, kept as two positions that stay with their characters
    /// (y-undomanager.js `_storeSelection`: `toYRange`, both ends by the range's own side), for the step the next
    /// change begins. Answers whether there is an undo to keep it.
    fn undo_caret(&self, at: &CaretAt) -> bool {
        let Some(undo) = self.undo.as_ref() else { return false };
        let kept = (self.relative(at.anchor, at.assoc), self.relative(at.head, at.assoc));
        crate::lock::lock(&undo.carets).before = Some(kept);
        true
    }

    /// A bound editor's own `edits` as one change (`change`), which its undo follows: the time is read first.
    fn typed(&mut self, edits: &[(u32, u32, String)], now: Option<u64>) -> Result<Option<Vec<u8>>, String> {
        if let Some(undo) = self.undo.as_ref() {
            undo.tick(now);
        }
        let update = self.change(edits, EDITOR)?;
        if !self.undo_sound() {
            // Never reached while every change of another origin lets the steps go; were it, the steps go here,
            // before yrs is ever asked to take this one back.
            self.undo_forget();
        }
        Ok(update)
    }

    /// A kept caret in the words as they are now: y-codemirror's `fromYRange`. `None` when either end cannot be
    /// placed, where the page throws and puts no selection back either.
    fn caret_now(&self, caret: &Caret) -> Option<Value> {
        let (anchor, head) = caret.as_ref()?;
        let at = |position: &Value| self.absolute(position).ok().flatten();
        let (from, to) = (at(anchor)?, at(head)?);
        Some(json!({ "anchor": from, "head": to, "assoc": head.get("assoc").and_then(Value::as_i64).unwrap_or(0) }))
    }

    /// The last step taken back (`UndoManager.undo`), or with `redo` the last one taken back put in again: steps
    /// are passed over until one changes something, as Yjs passes over them. What it changed is one update, queued
    /// like any change made here, and is answered with the words' own account of it.
    fn undo(&mut self, redo: bool, now: Option<u64>) -> Result<Undone, String> {
        if self.undo.is_none() {
            return Ok(Undone::default());
        }
        if !self.undo_sound() {
            // Never reached while every change of another origin lets the steps go; were it, the steps go here,
            // and yrs is not asked.
            self.undo_forget();
            return Ok(Undone::default());
        }
        if let Some(undo) = self.undo.as_ref() {
            undo.tick(now);
        }
        let before = self.words();
        let vector = self.doc.transact().state_vector();
        // Heard as the step is made: the words' account of the change, and the update it is.
        let heard: Arc<Mutex<Option<Option<Vec<(u32, u32, String)>>>>> = Arc::default();
        let made: Arc<Mutex<Option<Vec<u8>>>> = Arc::default();
        let (hears, makes) = (heard.clone(), made.clone());
        let words_watch: Subscription = self.text.observe(move |txn, event| {
            *crate::lock::lock(&hears) = Some(splices_of(event.delta(txn)));
        });
        let update_watch = self.doc.observe_update_v1(move |_, event| {
            *crate::lock::lock(&makes) = Some(event.update.clone());
        });
        let changed = match (&update_watch, self.undo.as_mut()) {
            (Ok(_), Some(undo)) => {
                crate::lock::lock(&undo.carets).popped = None;
                if redo { undo.manager.redo_blocking() } else { undo.manager.undo_blocking() }
            }
            _ => false,
        };
        drop(words_watch);
        if let Err(e) = update_watch {
            return Err(format!("The document was busy: {e}"));
        }
        drop(update_watch);
        if !changed {
            return Ok(Undone::default());
        }
        let after = self.words();
        // The update as the transaction made it; were it ever not heard, everything since the step began, which
        // holds it.
        let update = crate::lock::lock(&made).take().unwrap_or_else(|| self.state(Some(&vector)));
        self.pending.push(update.clone());
        // Each block the step put in again says which block it was by the one it was put before: itself.
        let me = self.doc.client_id().get();
        for block in crate::crdt_wire::put(&update).unwrap_or_default() {
            if let (true, Some(was)) = (block.client == me, block.before) {
                self.again.push(Again { client: was.0, clock: was.1, length: block.length, to: (block.client, block.clock) });
            }
        }
        // The words' own account, when it leads from the words before to the words after; else the one stretch
        // that does.
        let told = crate::lock::lock(&heard).take().flatten();
        let fits = |splices: &Vec<(u32, u32, String)>| spliced(&before, splices).is_some_and(|words| words == after.encode_utf16().collect::<Vec<u16>>());
        let splices = match told.filter(fits) {
            Some(splices) => splices,
            None => stretch(&before, &after)?.into_iter().collect(),
        };
        let popped = self.undo.as_ref().and_then(|undo| crate::lock::lock(&undo.carets).popped.take());
        let caret = self.caret_now(&popped);
        Ok(Undone { update: Some(update), splices, caret })
    }
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
        self.undo_forget();
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
    /// When they were made, in milliseconds, by which the undo groups typing; the clock's when left out.
    now: Option<u64>,
}

#[derive(Deserialize)]
struct UndoCaret {
    doc: u64,
    #[serde(flatten)]
    at: CaretAt,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UndoOpen {
    doc: u64,
    capture_ms: Option<u64>,
}

#[derive(Deserialize)]
struct UndoStep {
    doc: u64,
    now: Option<u64>,
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

/// What a change made here did, with what the undo holds after it while an editor is bound.
fn changed(held: &Held, update: Option<Vec<u8>>) -> Value {
    let mut said = json!({ "changed": update.is_some(), "update": update.map(|update| to_base64url(&update)), "text": held.words() });
    if held.undo.is_some() {
        said["undo"] = held.undo_state();
    }
    said
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
                made.change(&[(0, 0, words)], LOCAL)?;
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
                Ok(changed(held, update))
            })
        }
        "crdt_edit" => {
            let Edits { doc, edits, now } = read(command, args)?;
            let edits: Vec<(u32, u32, String)> = edits.into_iter().map(|edit| (edit.index, edit.remove, edit.insert)).collect();
            with_doc(doc, |held| {
                let update = held.typed(&edits, now)?;
                Ok(changed(held, update))
            })
        }
        "crdt_undo_open" => {
            let UndoOpen { doc, capture_ms } = read(command, args)?;
            with_doc(doc, |held| {
                held.undo_open(capture_ms.unwrap_or(CAPTURE_MS));
                Ok(held.undo_state())
            })
        }
        "crdt_undo_close" => {
            let ByDoc { doc } = read(command, args)?;
            with_doc(doc, |held| Ok(json!(held.undo.take().is_some())))
        }
        "crdt_undo_caret" => {
            let UndoCaret { doc, at } = read(command, args)?;
            with_doc(doc, |held| Ok(json!(held.undo_caret(&at))))
        }
        "crdt_undo" | "crdt_redo" => {
            let UndoStep { doc, now } = read(command, args)?;
            with_doc(doc, |held| {
                let done = held.undo(command == "crdt_redo", now)?;
                let mut said = changed(held, done.update);
                said["splices"] = done.splices.iter().map(|(at, removed, inserted)| json!({ "at": at, "removed": removed, "inserted": inserted })).collect();
                said["caret"] = done.caret.unwrap_or(Value::Null);
                said["undo"] = held.undo_state();
                Ok(said)
            })
        }
        "crdt_undo_state" => {
            let ByDoc { doc } = read(command, args)?;
            with_doc(doc, |held| Ok(held.undo_state()))
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
                let told = held.apply_remote(&updates)?;
                let after = held.words();
                let mut said = json!({ "changed": after != before, "text": after });
                // The words' own account of it, when it leads from the words before to the words after: what a
                // bound editor does with it, stretch for stretch. Left out otherwise, and the caller compares.
                if let Some(splices) = told.filter(|splices| !splices.is_empty() && spliced(&before, splices).is_some_and(|words| words == after.encode_utf16().collect::<Vec<u16>>())) {
                    said["splices"] = splices.iter().map(|(at, removed, inserted)| json!({ "at": at, "removed": removed, "inserted": inserted })).collect();
                }
                if held.undo.is_some() {
                    said["undo"] = held.undo_state();
                }
                Ok(said)
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
                Ok(changed(held, update))
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
        assert_eq!(got, json!({"changed": true, "text": "# Plan\n\nFirst.\n", "splices": [{"at": 0, "removed": 0, "inserted": "# Plan\n\nFirst.\n"}]}));
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

    /// Two members on one note, the first with an editor bound (its undo open): the words, and each other's
    /// updates as they are made.
    fn pair(words: &str) -> (u64, u64) {
        let mine = open(json!({"words": words, "clientId": 1}));
        let theirs = open(json!({"clientId": 2}));
        ask("crdt_apply", json!({"doc": theirs, "updates": [ask("crdt_state", json!({"doc": mine}))]}));
        ask("crdt_posted", json!({"doc": mine, "count": 1}));
        assert_eq!(ask("crdt_undo_open", json!({"doc": mine})), json!({"open": true, "canUndo": false, "canRedo": false}));
        (mine, theirs)
    }

    /// An editor's change at `now`, and the same heard by `to`.
    fn typed(doc: u64, to: u64, index: u32, remove: u32, insert: &str, now: u64) -> Value {
        let said = ask("crdt_edit", json!({"doc": doc, "edits": [{"index": index, "remove": remove, "insert": insert}], "now": now}));
        ask("crdt_apply", json!({"doc": to, "updates": [said["update"]]}));
        said
    }

    #[test]
    fn undo_takes_back_what_the_editor_typed_as_one_update_and_leaves_what_arrived() {
        let (mine, theirs) = pair("Buy");
        // Two keys inside the capture time are one step; a third after it is another.
        typed(mine, theirs, 3, 0, " mi", 1_000);
        typed(mine, theirs, 6, 0, "lk", 1_400);
        let third = typed(mine, theirs, 8, 0, "!", 2_000);
        assert_eq!(third["undo"], json!({"open": true, "canUndo": true, "canRedo": false}));
        // The other member writes at the start; it arrives, and is no step of this editor's.
        let said = ask("crdt_edit", json!({"doc": theirs, "edits": [{"index": 0, "insert": "Sam: "}]}));
        assert!(said.get("undo").is_none(), "a document with no editor bound says nothing of undo");
        ask("crdt_apply", json!({"doc": mine, "updates": [said["update"]]}));
        assert_eq!(text(mine), "Sam: Buy milk!");
        let waiting = ask("crdt_pending", json!({"doc": mine})).as_array().unwrap().len();

        let undone = ask("crdt_undo", json!({"doc": mine, "now": 3_000}));
        assert_eq!((undone["changed"].as_bool(), undone["text"].as_str()), (Some(true), Some("Sam: Buy milk")));
        assert_eq!(undone["splices"], json!([{"at": 13, "removed": 1, "inserted": ""}]));
        assert_eq!(undone["undo"], json!({"open": true, "canUndo": true, "canRedo": true}));
        // One update more is owed the service, and it is the one answered; the other member takes it like any.
        let pending = ask("crdt_pending", json!({"doc": mine}));
        assert_eq!(pending.as_array().unwrap().len(), waiting + 1);
        assert_eq!(pending.as_array().unwrap().last(), Some(&undone["update"]));
        assert_eq!(ask("crdt_apply", json!({"doc": theirs, "updates": [undone["update"]]})), json!({"changed": true, "text": "Sam: Buy milk", "splices": [{"at": 13, "removed": 1, "inserted": ""}]}));

        let undone = ask("crdt_undo", json!({"doc": mine, "now": 3_100}));
        assert_eq!(undone["text"], "Sam: Buy");
        assert_eq!(undone["splices"], json!([{"at": 8, "removed": 5, "inserted": ""}]));
        assert_eq!(undone["undo"], json!({"open": true, "canUndo": false, "canRedo": true}));
        ask("crdt_apply", json!({"doc": theirs, "updates": [undone["update"]]}));
        // Nothing left: nothing changes, nothing is owed.
        let nothing = ask("crdt_undo", json!({"doc": mine, "now": 3_200}));
        assert_eq!(nothing, json!({"changed": false, "update": null, "text": "Sam: Buy", "splices": [], "caret": null, "undo": {"open": true, "canUndo": false, "canRedo": true}}));
        assert_eq!(ask("crdt_pending", json!({"doc": mine})).as_array().unwrap().len(), waiting + 2);

        // Put in again, in the order they were taken back; and a key typed ends what could be put in again.
        let redone = ask("crdt_redo", json!({"doc": mine, "now": 3_300}));
        assert_eq!(redone["text"], "Sam: Buy milk");
        assert_eq!(redone["splices"], json!([{"at": 8, "removed": 0, "inserted": " milk"}]));
        ask("crdt_apply", json!({"doc": theirs, "updates": [redone["update"]]}));
        assert_eq!(text(theirs), "Sam: Buy milk");
        let said = typed(mine, theirs, 13, 0, "?", 9_000);
        assert_eq!(said["undo"], json!({"open": true, "canUndo": true, "canRedo": false}));
        assert_eq!(ask("crdt_redo", json!({"doc": mine, "now": 9_100}))["changed"], false);
        assert_eq!(text(theirs), "Sam: Buy milk?");

        // A member who was away the whole time has the same words from the updates alone, in the order made.
        let late = open(json!({"clientId": 3}));
        ask("crdt_apply", json!({"doc": late, "updates": [ask("crdt_state", json!({"doc": theirs}))]}));
        assert_eq!(text(late), text(mine));
    }

    #[test]
    fn a_run_deleted_here_is_put_back_where_its_letters_stood_among_what_another_wrote() {
        // docs/PARITY.md, Differs 26: the editor's history heard "X at 3" in each of these and answered one way;
        // Yjs answers each by where X stands among the letters taken out (test/live/undo_beside_others_test.dart
        // asks Yjs itself; these are its answers).
        let after = |at: u32, heard_first: bool| -> String {
            let (mine, theirs) = pair("0123456789");
            if heard_first {
                typed(mine, theirs, 3, 3, "", 1_000);
            }
            let said = ask("crdt_edit", json!({"doc": theirs, "edits": [{"index": at, "insert": "X"}]}));
            if !heard_first {
                typed(mine, theirs, 3, 3, "", 1_000);
            }
            ask("crdt_apply", json!({"doc": mine, "updates": [said["update"]]}));
            assert_eq!(text(mine), "012X6789");
            let undone = ask("crdt_undo", json!({"doc": mine, "now": 5_000}));
            ask("crdt_apply", json!({"doc": theirs, "updates": [undone["update"]]}));
            assert_eq!(text(theirs), undone["text"].as_str().unwrap());
            undone["text"].as_str().unwrap().to_string()
        };
        assert_eq!(after(3, true), "012345X6789", "written once they had heard of the deleting: after the run");
        assert_eq!(after(3, false), "012X3456789", "written at the same moment between 2 and 3: before the run");
        assert_eq!(after(4, false), "0123X456789", "written at the same moment between 3 and 4: inside the run");
        assert_eq!(after(6, false), "012345X6789", "written at the same moment between 5 and 6: after the run");

        // Typing taken back, the other writing there meanwhile, and the typing put in again: before theirs.
        let (mine, theirs) = pair("0123456789");
        typed(mine, theirs, 5, 0, "abc", 1_000);
        let undone = ask("crdt_undo", json!({"doc": mine, "now": 2_000}));
        ask("crdt_apply", json!({"doc": theirs, "updates": [undone["update"]]}));
        let said = ask("crdt_edit", json!({"doc": theirs, "edits": [{"index": 5, "insert": "X"}]}));
        ask("crdt_apply", json!({"doc": mine, "updates": [said["update"]]}));
        assert_eq!(text(mine), "01234X56789");
        let redone = ask("crdt_redo", json!({"doc": mine, "now": 3_000}));
        assert_eq!(redone["text"], "01234abcX56789");
        assert_eq!(redone["splices"], json!([{"at": 5, "removed": 0, "inserted": "abc"}]));
    }

    #[test]
    fn undo_follows_the_editor_alone_and_only_while_one_is_bound() {
        let (mine, theirs) = pair("one");
        // A reconcile (words that reach the note without the editor) is textDiff.ts's LOCAL: no step.
        ask("crdt_apply_diff", json!({"doc": mine, "to": "one two"}));
        assert_eq!(ask("crdt_undo_state", json!({"doc": mine})), json!({"open": true, "canUndo": false, "canRedo": false}));
        assert_eq!(ask("crdt_undo", json!({"doc": mine}))["changed"], false);
        // The editor's is.
        typed(mine, theirs, 7, 0, " three", 1_000);
        assert_eq!(ask("crdt_undo_state", json!({"doc": mine})), json!({"open": true, "canUndo": true, "canRedo": false}));
        // And a reconcile while there are steps lets them go (`Undo`, "Where yrs 0.26 is not Yjs"): this very
        // case, two keys of one step with other words of this device's between them, is the one yrs cuts wrongly.
        let between = open(json!({"words": "", "clientId": 31}));
        ask("crdt_undo_open", json!({"doc": between}));
        ask("crdt_edit", json!({"doc": between, "edits": [{"index": 0, "insert": "c"}], "now": 1_000}));
        ask("crdt_apply_diff", json!({"doc": between, "to": "c\n+"}));
        assert_eq!(ask("crdt_undo_state", json!({"doc": between})), json!({"open": true, "canUndo": false, "canRedo": false}));
        ask("crdt_edit", json!({"doc": between, "edits": [{"index": 3, "insert": "def"}], "now": 1_040}));
        let undone = ask("crdt_undo", json!({"doc": between, "now": 1_080}));
        assert_eq!((undone["text"].as_str(), &undone["undo"]), (Some("c\n+"), &json!({"open": true, "canUndo": false, "canRedo": true})));
        assert_eq!(ask("crdt_undo", json!({"doc": between, "now": 1_100}))["changed"], false);
        assert!(with_doc(between, |held| Ok(held.undo_sound())).unwrap());
        // Unbound, the steps are gone; bound again, there are none; and what is typed with no editor bound is no step.
        assert_eq!(ask("crdt_undo_close", json!({"doc": mine})), true);
        assert_eq!(ask("crdt_undo_close", json!({"doc": mine})), false);
        assert_eq!(ask("crdt_undo_state", json!({"doc": mine})), json!({"open": false, "canUndo": false, "canRedo": false}));
        assert_eq!(ask("crdt_undo", json!({"doc": mine})), json!({"changed": false, "update": null, "text": "one two three", "splices": [], "caret": null, "undo": {"open": false, "canUndo": false, "canRedo": false}}));
        ask("crdt_edit", json!({"doc": mine, "edits": [{"index": 0, "insert": ">"}]}));
        ask("crdt_undo_open", json!({"doc": mine}));
        assert_eq!(ask("crdt_undo", json!({"doc": mine}))["changed"], false);
        assert_eq!(text(mine), ">one two three");
        // A step keeps the selection as it stood before its first change, and answers it where it is now.
        assert_eq!(ask("crdt_undo_caret", json!({"doc": mine, "anchor": 4, "head": 8})), true);
        let said = ask("crdt_edit", json!({"doc": mine, "edits": [{"index": 4, "remove": 4}], "now": 1_000}));
        assert_eq!(said["text"], ">one three");
        ask("crdt_undo_caret", json!({"doc": mine, "anchor": 4, "head": 4}));
        ask("crdt_edit", json!({"doc": mine, "edits": [{"index": 4, "insert": " 2"}], "now": 1_100}));
        ask("crdt_undo_caret", json!({"doc": mine, "anchor": 6, "head": 6}));
        // The other member, who has heard all of it, writes before it.
        ask("crdt_apply", json!({"doc": theirs, "updates": [ask("crdt_state", json!({"doc": mine}))]}));
        assert_eq!(text(theirs), ">one 2 three");
        ask("crdt_apply", json!({"doc": mine, "updates": [ask("crdt_edit", json!({"doc": theirs, "edits": [{"index": 0, "insert": "## "}]}))["update"]]}));
        let undone = ask("crdt_undo", json!({"doc": mine, "now": 2_000}));
        assert_eq!(undone["text"], "## >one two three");
        assert_eq!(undone["caret"], json!({"anchor": 7, "head": 11, "assoc": 0}));
        // The editor puts its selection there and says so; and the step put in again answers where the selection
        // stood when the step was taken back, which is where it was last said before that: after " 2".
        ask("crdt_undo_caret", json!({"doc": mine, "anchor": 7, "head": 11}));
        let redone = ask("crdt_redo", json!({"doc": mine, "now": 2_100}));
        assert_eq!(redone["text"], "## >one 2 three");
        assert_eq!(redone["caret"], json!({"anchor": 9, "head": 9, "assoc": 0}));
        // A selection said to a document with no editor bound is kept by nobody.
        assert_eq!(ask("crdt_undo_caret", json!({"doc": theirs, "anchor": 0, "head": 0})), false);
    }

    #[test]
    fn a_character_of_two_units_is_taken_back_and_put_in_again_whole() {
        let (mine, theirs) = pair("a😀b");
        typed(mine, theirs, 3, 0, "👻é", 1_000);
        typed(mine, theirs, 1, 2, "", 5_000);
        assert_eq!(text(mine), "a👻éb");
        let undone = ask("crdt_undo", json!({"doc": mine, "now": 9_000}));
        assert_eq!(undone["text"], "a😀👻éb");
        assert_eq!(undone["splices"], json!([{"at": 1, "removed": 0, "inserted": "😀"}]));
        let undone = ask("crdt_undo", json!({"doc": mine, "now": 9_100}));
        assert_eq!(undone["text"], "a😀b");
        assert_eq!(undone["splices"], json!([{"at": 3, "removed": 3, "inserted": ""}]));
        let redone = ask("crdt_redo", json!({"doc": mine, "now": 9_200}));
        assert_eq!(redone["text"], "a😀👻éb");
        assert!(with_doc(mine, |held| Ok(held.whole())).unwrap());
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
