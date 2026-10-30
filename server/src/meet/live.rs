//! A meeting's captions while Ghost is in it, sealed to the account and passed to its devices as they come (Matt,
//! 2026-10-30: "If possible add real time transcriptions for meetings"). docs/MEET.md, "Live captions".
//!
//! Until now a meeting's words reached the person only with its take, after the call. The bot reads the captions as the
//! meeting goes (meet/bot/lib/captions.mjs) and now also hands each batch of finished lines here, with the line still
//! being said, every second and a half or so (`POST /api/internal/meet/{id}/live`). Each batch is sealed in that
//! request to the account's encryption PUBLIC key, as a take is (`seal::seal_in_place`, with contexts of its own), and
//! the clear words are wiped: the service cannot open what it passes on. The sealed frame goes at once to every
//! signed-in socket of the account (live.rs, the pokes' registry: `{ t: "captions", ... }`), and one with finished
//! lines in it is kept, sealed and in memory alone, so a device that comes to the front mid-meeting catches up
//! (`GET /api/v1/meet/{id}/live?after=<seq>`). Nothing of it is ever on disk or in a log.
//!
//! ```text
//! bot -> service      POST /api/internal/meet/{id}/live   { startedAt?, lines: [{ at, speaker, text }], partial? }
//! service -> device   { t: "captions", meeting, seq, wrapped, data }        finished lines (and the line being said)
//! service -> device   { t: "captions", meeting, partial, wrapped, data }    the line being said alone; not kept
//! service -> device   { t: "captions", meeting, ended: true }               the feed is over: the take has come, or the
//!                                                                           meeting is done, failed or skipped
//! device -> service   GET /api/v1/meet/{id}/live?after=<seq>  { live, first, frames: [{ seq, wrapped, data }] }
//! ```
//!
//! A frame opens as a take does on the device (lib/meet/live_captions.dart): its key out of `wrapped` with the account's
//! private key in `meet-live-key:<meeting>:<n>`, then `data` (base64url of the version byte, the IV and AES-256-GCM)
//! with `meet-live:<meeting>:<n>` as associated data, `<n>` the frame's `seq`, or `p<partial>` for one with the line
//! being said alone. So a frame moved to another meeting, or to another place in the same one, opens nothing. Inside:
//! `{ v: 1, meeting, startedAt, lines: [{ at, speaker, text }], partial: { at, speaker, text } | null }`, `at` in ms
//! since the recording began, as the take's captions are.
//!
//! Limits: the bot's batches, per meeting, `POST_BURST` at once and `POST_PER_SECOND` after (429 past them); at most
//! `LINES_MOST` lines a batch, `TEXT_MOST` characters a line and `SPEAKER_MOST` a name (400 past them), and a body of
//! `BODY_MOST`. Kept: `FEED_BYTES_MOST` of sealed frames a meeting, the oldest let go past it (`first` says where the
//! kept ones begin; the take carries every line all the same), and `FEEDS_MOST` meetings at once (the bot is in one
//! at a time). A feed with nothing new for `STALE_MS` is forgotten. A device's catch-up, `GETS_PER_MINUTE` an account.
//!
//! Who may: the bot, on this machine with its token (meet.rs `bot_only`), for a meeting it is joining or in (409
//! otherwise, which tells it to stop sending); the meeting's own account for the catch-up, and nobody else (404, as
//! every other account's meeting is answered). The frames go to that account's sockets alone.
//!
//! An older app ignores a frame it does not know (lib/live/transport.dart); an older bot sends nothing here, and the
//! device has the meeting's words when the take comes, as before.

use crate::guard::{Bucket, RateLimiter};
use crate::mail::seal;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use std::collections::HashMap;
use std::sync::Mutex;
use std::time::Instant;
use zeroize::Zeroize;

/// Batches a meeting's bot may send at once, and after: one every second and a half is the bot's pace.
pub const POST_BURST: f64 = 20.0;
pub const POST_PER_SECOND: f64 = 2.0;
/// The most lines one batch carries: a minute of a busy meeting's captions is a few dozen.
pub const LINES_MOST: usize = 100;
/// The most characters one line's words, and one speaker's name, may have.
pub const TEXT_MOST: usize = 2000;
pub const SPEAKER_MOST: usize = 120;
/// The largest batch's body.
pub const BODY_MOST: usize = 64 * 1024;
/// Sealed frames kept for one meeting, for the catch-up: past this the oldest are let go.
pub const FEED_BYTES_MOST: usize = 4 * 1024 * 1024;
/// Meetings with a feed at once: the bot is in one at a time, so this is room to spare, and at most 32 MB kept in all.
pub const FEEDS_MOST: usize = 8;
/// A feed nothing has come to for this long is forgotten (ms).
pub const STALE_MS: i64 = 30 * 60 * 1000;
/// A device's catch-ups, per account, a minute.
pub const GETS_PER_MINUTE: u32 = 120;

/// The context frame `n` of meeting `id` has its key wrapped in.
pub fn key_context(id: &str, n: &str) -> String {
    format!("meet-live-key:{id}:{n}")
}

/// The context frame `n` of meeting `id` is sealed in.
pub fn seal_context(id: &str, n: &str) -> String {
    format!("meet-live:{id}:{n}")
}

/// One line of the captions, as the bot reads it (the take's NDJSON line).
#[derive(Deserialize)]
pub struct Line {
    pub at: i64,
    #[serde(default)]
    pub speaker: String,
    pub text: String,
}

/// A batch, as the bot sends it.
#[derive(Deserialize)]
pub struct Batch {
    #[serde(default, rename = "startedAt")]
    pub started_at: Option<i64>,
    #[serde(default)]
    pub lines: Vec<Line>,
    #[serde(default)]
    pub partial: Option<Line>,
}

impl Batch {
    /// Why the batch is refused, in the bot's log's words; None for one within the limits.
    pub fn refused(&self) -> Option<&'static str> {
        if self.lines.len() > LINES_MOST {
            return Some("Too many lines in one batch.");
        }
        let long = |l: &Line| l.text.chars().count() > TEXT_MOST || l.speaker.chars().count() > SPEAKER_MOST || l.at < 0;
        if self.lines.iter().any(long) || self.partial.as_ref().is_some_and(long) {
            return Some("A line is too long, or its time is not one.");
        }
        None
    }
}

/// A line as it is sealed, borrowed from the batch so its words are never copied into the clear.
#[derive(Serialize)]
struct Said<'a> {
    at: i64,
    speaker: &'a str,
    text: &'a str,
}

impl<'a> Said<'a> {
    fn of(line: &'a Line) -> Self {
        Said { at: line.at, speaker: &line.speaker, text: &line.text }
    }
}

/// What a frame holds, sealed.
#[derive(Serialize)]
struct Payload<'a> {
    v: u8,
    meeting: &'a str,
    #[serde(rename = "startedAt")]
    started_at: Option<i64>,
    lines: Vec<Said<'a>>,
    partial: Option<Said<'a>>,
}

/// A sealed frame kept for the catch-up.
#[derive(Clone)]
struct Frame {
    seq: u64,
    wrapped: String,
    data: String,
}

/// One meeting's feed.
struct Feed {
    account: i64,
    started_at: Option<i64>,
    seq: u64,
    partials: u64,
    frames: Vec<Frame>,
    bytes: usize,
    touched: i64,
    bucket: Bucket,
}

/// Every meeting with a feed, kept on the accounts (`Accounts::captions`) so the bot's routes and the device's reach
/// the same.
#[derive(Default)]
pub struct LiveCaptions {
    feeds: Mutex<HashMap<String, Feed>>,
    gets: Mutex<Option<RateLimiter<i64>>>,
    /// The bytes kept a meeting, where not `FEED_BYTES_MOST`: a test's smaller room.
    room: Option<usize>,
}

/// What a batch came to.
pub enum Sent {
    /// Sealed, and the frame to send the account's sockets.
    Frame(Value),
    /// Nothing in it: no lines and no line being said.
    Empty,
    /// Past the meeting's pace.
    Busy,
    /// Too many meetings have a feed.
    Full,
    /// It could not be sealed.
    Failed,
}

impl LiveCaptions {
    fn lock(&self) -> std::sync::MutexGuard<'_, HashMap<String, Feed>> {
        self.feeds.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Spends one of the account's catch-ups, if it has one left.
    pub fn may_get(&self, account: i64) -> bool {
        let now = Instant::now();
        let Ok(mut gets) = self.gets.lock() else { return false };
        gets.get_or_insert_with(|| RateLimiter::new(GETS_PER_MINUTE, now)).take(account, now)
    }

    /// Seals `batch` for meeting `meeting` of `account` to `public`, keeps it when it has finished lines, and answers the
    /// frame to send that account's sockets. The clear words are wiped here, whatever comes of it: the batch's own, and
    /// the bytes they were sealed from, which are ciphertext by then.
    pub fn send(&self, meeting: &str, account: i64, public: &str, batch: Batch, now: i64) -> Sent {
        // The batch wipes itself as it goes ([Batch]'s Drop).
        self.sealed(meeting, account, public, &batch, now)
    }

    fn sealed(&self, meeting: &str, account: i64, public: &str, batch: &Batch, now: i64) -> Sent {
        let said = |l: &&Line| !l.text.trim().is_empty();
        let lines: Vec<Said> = batch.lines.iter().filter(said).map(Said::of).collect();
        let partial = batch.partial.as_ref().filter(said).map(Said::of);
        if lines.is_empty() && partial.is_none() {
            return Sent::Empty;
        }
        let mut feeds = self.lock();
        feeds.retain(|_, f| now - f.touched < STALE_MS);
        if !feeds.contains_key(meeting) && feeds.len() >= FEEDS_MOST {
            return Sent::Full;
        }
        let feed = feeds.entry(meeting.to_string()).or_insert_with(|| Feed {
            account,
            started_at: None,
            seq: 0,
            partials: 0,
            frames: Vec::new(),
            bytes: 0,
            touched: now,
            bucket: Bucket::new(POST_BURST, POST_PER_SECOND, Instant::now()),
        });
        if !feed.bucket.take(Instant::now()) {
            return Sent::Busy;
        }
        feed.touched = now;
        if batch.started_at.is_some() {
            feed.started_at = batch.started_at;
        }
        let kept = !lines.is_empty();
        let n = if kept {
            feed.seq += 1;
            feed.seq.to_string()
        } else {
            feed.partials += 1;
            format!("p{}", feed.partials)
        };
        let mut payload = serde_json::to_vec(&Payload { v: 1, meeting, started_at: feed.started_at, lines, partial }).unwrap_or_default();
        let sealed = seal::seal_in_place(public, &key_context(meeting, &n), &seal_context(meeting, &n), &mut payload);
        let Ok((wrapped, head)) = sealed else {
            payload.zeroize();
            return Sent::Failed;
        };
        let data = URL_SAFE_NO_PAD.encode([&head[..], &payload[..]].concat());
        payload.zeroize();
        if !kept {
            return Sent::Frame(json!({ "t": "captions", "meeting": meeting, "partial": feed.partials, "wrapped": wrapped, "data": data }));
        }
        let frame = Frame { seq: feed.seq, wrapped, data };
        feed.bytes += frame.wrapped.len() + frame.data.len();
        feed.frames.push(frame.clone());
        // The oldest let go past the meeting's room: the take has every line all the same.
        let room = self.room.unwrap_or(FEED_BYTES_MOST);
        while feed.bytes > room && feed.frames.len() > 1 {
            let gone = feed.frames.remove(0);
            feed.bytes -= gone.wrapped.len() + gone.data.len();
        }
        Sent::Frame(json!({ "t": "captions", "meeting": meeting, "seq": frame.seq, "wrapped": frame.wrapped, "data": frame.data }))
    }

    /// The frames kept for meeting `meeting` after `after`, for its account alone: `{ live, first, frames }`. A meeting
    /// with no feed (none came, or it is over) is `live: false` and no frames.
    pub fn since(&self, meeting: &str, account: i64, after: u64, now: i64) -> Value {
        let mut feeds = self.lock();
        feeds.retain(|_, f| now - f.touched < STALE_MS);
        match feeds.get(meeting).filter(|f| f.account == account) {
            Some(feed) => {
                let frames: Vec<Value> = feed.frames.iter().filter(|f| f.seq > after).map(|f| json!({ "seq": f.seq, "wrapped": f.wrapped, "data": f.data })).collect();
                json!({ "live": true, "first": feed.frames.first().map_or(feed.seq + 1, |f| f.seq), "frames": frames })
            }
            None => json!({ "live": false, "first": null, "frames": [] }),
        }
    }

    /// Every feed nothing has come to for `STALE_MS`, forgotten: the hourly sweep's (meet.rs `sweep_poking`), for a bot
    /// that went without saying the meeting was over.
    pub fn forget_stale(&self, now: i64) {
        self.lock().retain(|_, f| now - f.touched < STALE_MS);
    }

    /// Meeting `meeting`'s feed is over: forgotten, and the account whose it was answered, for the frame that says so.
    pub fn end(&self, meeting: &str) -> Option<i64> {
        self.lock().remove(meeting).map(|f| f.account)
    }

    /// How many meetings have a feed, for tests.
    #[cfg(test)]
    pub fn feeds(&self) -> usize {
        self.lock().len()
    }

    /// The bytes kept for one meeting, for tests.
    #[cfg(test)]
    pub fn kept_bytes(&self, meeting: &str) -> usize {
        self.lock().get(meeting).map_or(0, |f| f.bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::mail::seal::tests::account_pair;

    fn batch(text: &str) -> Batch {
        Batch { started_at: Some(1_792_159_500_000), lines: vec![Line { at: 1000, speaker: "Sam Lee".into(), text: text.into() }], partial: None }
    }

    /// Opens frame `n` of `meeting` as a device does.
    fn opened(secret: &p256::SecretKey, meeting: &str, n: &str, frame: &Value) -> Result<Value, String> {
        let sealed = URL_SAFE_NO_PAD.decode(frame["data"].as_str().unwrap()).unwrap();
        let clear = seal::open_sealed_with(secret, frame["wrapped"].as_str().unwrap(), &key_context(meeting, n), &sealed, &seal_context(meeting, n))?;
        Ok(serde_json::from_slice(&clear).unwrap())
    }

    #[test]
    fn a_meeting_keeps_its_room_letting_the_oldest_frames_go_and_says_where_they_begin() {
        let (secret, public) = account_pair();
        let feeds = LiveCaptions { room: Some(4000), ..LiveCaptions::default() };
        for n in 0..8 {
            assert!(matches!(feeds.send("m1", 7, &public, batch(&format!("{n} {}", "words ".repeat(100))), 1000), Sent::Frame(_)));
        }
        assert!(feeds.kept_bytes("m1") <= 4000 + 2000, "{}", feeds.kept_bytes("m1"));
        let kept = feeds.since("m1", 7, 0, 1000);
        let first = kept["first"].as_u64().unwrap();
        assert!(first > 1, "the oldest went: {kept}");
        let frames = kept["frames"].as_array().unwrap();
        assert_eq!(frames.last().unwrap()["seq"], 8);
        assert_eq!(frames[0]["seq"].as_u64(), Some(first));
        assert!(opened(&secret, "m1", "8", frames.last().unwrap()).unwrap()["lines"][0]["text"].as_str().unwrap().starts_with("7 "));
    }

    #[test]
    fn a_feed_left_alone_is_forgotten_and_there_is_room_for_so_many_meetings_at_once() {
        let (_, public) = account_pair();
        let feeds = LiveCaptions::default();
        for n in 0..FEEDS_MOST {
            assert!(matches!(feeds.send(&format!("m{n}"), 7, &public, batch("hello"), 1000), Sent::Frame(_)));
        }
        assert!(matches!(feeds.send("one-more", 7, &public, batch("hello"), 1000), Sent::Full));
        assert!(matches!(feeds.send("m0", 7, &public, batch("hello"), 1000), Sent::Frame(_)), "a meeting with a feed goes on");
        // Half an hour on, every one of them is forgotten, and a new meeting has room.
        assert!(matches!(feeds.send("one-more", 7, &public, batch("hello"), 1000 + STALE_MS), Sent::Frame(_)));
        assert_eq!(feeds.feeds(), 1);
        assert_eq!(feeds.since("m0", 7, 0, 1000 + STALE_MS)["live"], false);
        // And by the hourly sweep, with nothing asked of them.
        feeds.forget_stale(1000 + 2 * STALE_MS);
        assert_eq!(feeds.feeds(), 0);
        // Another account's meeting is not this one's to catch up on.
        assert!(matches!(feeds.send("m1", 7, &public, batch("hello"), 5000), Sent::Frame(_)));
        assert_eq!(feeds.since("m1", 8, 0, 5000)["live"], false);
    }

    #[test]
    fn a_batch_with_nothing_said_is_nothing_and_one_too_long_is_refused() {
        let (_, public) = account_pair();
        let feeds = LiveCaptions::default();
        assert!(matches!(feeds.send("m1", 7, &public, batch("   "), 1000), Sent::Empty));
        assert_eq!(feeds.feeds(), 0);
        let long = Batch { started_at: None, lines: vec![Line { at: 1, speaker: String::new(), text: "a".repeat(TEXT_MOST + 1) }], partial: None };
        assert!(long.refused().is_some());
        let many = Batch { started_at: None, lines: (0..=LINES_MOST).map(|n| Line { at: n as i64, speaker: String::new(), text: "a".into() }).collect(), partial: None };
        assert!(many.refused().is_some());
        let backwards = Batch { started_at: None, lines: vec![], partial: Some(Line { at: -1, speaker: String::new(), text: "a".into() }) };
        assert!(backwards.refused().is_some());
        assert!(batch("fine").refused().is_none());
    }
}

/// A batch's words are wiped where they lay whenever it goes, sealed or refused.
impl Drop for Batch {
    fn drop(&mut self) {
        for line in self.lines.iter_mut().chain(self.partial.iter_mut()) {
            line.text.zeroize();
            line.speaker.zeroize();
        }
    }
}

/// The frame that tells a device the feed of `meeting` is over.
pub fn ended_frame(meeting: &str) -> Value {
    json!({ "t": "captions", "meeting": meeting, "ended": true })
}
