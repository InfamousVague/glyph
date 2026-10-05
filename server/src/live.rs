//! Live sync's relay (docs/LIVE.md): a WebSocket per device, passing sealed edits between one account's own devices
//! while they have the same note open - and, for a team's notes (docs/SHARED.md, S6), between an organization's
//! members across their accounts.
//!
//! It knows accounts, organizations and rooms and nothing else. What passes through is ciphertext under a key it
//! never sees - the devices seal every message with the account key, or the organization key, before sending - so
//! it cannot read a word, and it keeps nothing: no message is stored or logged. A room is a note id, which the sync
//! feed already shows it, or an organization's own room for who is in the app (`org` on the frame says whose).
//!
//! The protocol, all JSON text frames:
//!
//! ```text
//! client -> server   { t: "auth",  token }                 first frame, within AUTH_WAIT, or the socket is closed
//! server -> client   { t: "ready", id }                    this socket's connection id
//! client -> server   { t: "join",  room, org? }            org: an organization's room, for its members
//! client -> server   { t: "leave", room, org? }
//! client -> server   { t: "msg",   room, org?, data, to? } data: base64url ciphertext; to: one connection, or all
//! server -> client   { t: "joined", room, org?, first, peers }  first: the room was empty until now (see LIVE.md, Seeding)
//! server -> client   { t: "peers",  room, org?, peers, left? }  another device came or went; left: the connection that went
//! server -> client   { t: "msg",    room, org?, from, data }
//! server -> client   { t: "error",  message }              a frame refused, the socket kept
//! ```
//!
//! An organization's room is joined by its members alone, checked fresh at every join and again, on a message, once
//! `RECHECK_SECS` have passed since the last check: a member removed is out of the organization's rooms within that
//! long, told "No such organization." as a stranger is.
//!
//! A browser cannot put an Authorization header on a WebSocket, so the token comes in the first frame rather than the
//! URL, where access logs would keep it.

use crate::accounts::Accounts;
use crate::guard::Bucket;
use crate::wire::{base64url, now_secs};
use axum::extract::ws::{CloseFrame, Message, Utf8Bytes, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::http::{HeaderMap, StatusCode};
use axum::response::{IntoResponse, Response};
use axum::routing::get;
use axum::Router;
use futures_util::{SinkExt, StreamExt};
use serde::Deserialize;
use serde_json::{json, Value};
use std::collections::{HashMap, HashSet};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use tokio::sync::mpsc;

/// How long a new socket has to say who it is.
const AUTH_WAIT: Duration = Duration::from_secs(10);
/// A ping this often keeps phone networks and proxies from dropping a socket that is only listening.
const PING_EVERY: Duration = Duration::from_secs(25);
/// Devices live at once on one account: more than anyone has, fewer than a runaway client would open.
pub const SOCKETS_PER_ACCOUNT: usize = 16;
/// Notes one device can have live at once.
pub const ROOMS_PER_SOCKET: usize = 64;
/// The largest frame, a whole note's document as it joins included.
pub const MAX_FRAME: usize = 64 * 1024;
/// Messages waiting to go out to one device. A device that falls this far behind is closed rather than fed forever:
/// it comes back, asks for the document, and is whole again.
const QUEUE: usize = 128;
/// Frames a device may send: a burst, and a steady rate. Typing is a few a second; a caret moving, a few more.
const BURST: f64 = 200.0;
const PER_SECOND: f64 = 100.0;
/// One room name: a note id, or anything else shaped like one, as base64url. Kept short and plain so a room is never a
/// way in.
const ROOM_LENGTH: std::ops::RangeInclusive<usize> = 1..=64;

/// How long a socket's membership of an organization stands before a message makes the relay look again (seconds);
/// a test sets it to 0 to see a removed member cut off at once.
pub(crate) static RECHECK_SECS: AtomicU64 = AtomicU64::new(60);

/// Close codes. 4000-4999 are the application's own; a client reconnects after all of these but CLOSE_AUTH.
pub const CLOSE_AUTH: u16 = 4401;
pub const CLOSE_BUSY: u16 = 4429;
pub const CLOSE_BAD: u16 = 4400;
pub const CLOSE_BEHIND: u16 = 4408;

pub struct Live {
    accounts: Arc<Accounts>,
    hub: Mutex<Hub>,
    next: AtomicU64,
}

/// Whose room: one account's own devices (LIVE.md), or an organization's members across their accounts (SHARED.md, S6).
#[derive(Clone, PartialEq, Eq, Hash)]
enum Scope {
    Account(i64),
    Org(String),
}

/// Who is where. Members are kept in the order they joined, and a room with none is removed.
#[derive(Default)]
struct Hub {
    rooms: HashMap<(Scope, String), Vec<Member>>,
    sockets: HashMap<i64, usize>,
}

#[derive(Clone)]
struct Member {
    id: u64,
    out: mpsc::Sender<Message>,
}

#[derive(Deserialize)]
#[serde(tag = "t", rename_all = "lowercase")]
enum Incoming {
    Join {
        room: String,
        #[serde(default)]
        org: Option<String>,
    },
    Leave {
        room: String,
        #[serde(default)]
        org: Option<String>,
    },
    Msg {
        room: String,
        #[serde(default)]
        org: Option<String>,
        data: String,
        to: Option<u64>,
    },
}

/// A frame about a room, with the organization on it when the room is one's.
fn about(scope: &Scope, room: &str, mut value: Value) -> Value {
    value["room"] = json!(room);
    if let Scope::Org(org) = scope {
        value["org"] = json!(org);
    }
    value
}

/// The scope a device's frame names: the organization's, or the account's own.
fn scope_of(account: i64, org: Option<&str>) -> Scope {
    match org {
        Some(org) => Scope::Org(org.to_string()),
        None => Scope::Account(account),
    }
}

#[derive(Deserialize)]
struct Auth {
    t: String,
    token: String,
}

pub fn router(accounts: Arc<Accounts>) -> Router {
    let live = Arc::new(Live { accounts, hub: Mutex::new(Hub::default()), next: AtomicU64::new(1) });
    Router::new().route("/api/v1/live", get(upgrade)).with_state(live)
}

/// A WebSocket is not covered by CORS, so a page's origin is checked here: the apps' own origins, as the HTTP routes
/// allow them, or the site the service is served from.
///
/// That second half matters and is easy to miss. A browser sends `Origin` on EVERY WebSocket, same-origin included,
/// unlike a same-origin fetch, which is why the HTTP routes' list has no `https://attack.fm` in it - and a check made
/// from that list alone would refuse the web version of Glyph at its own address. So the page's origin is also let in
/// when it names the very host it connected to (behind Caddy, the `Host` it passes on). A client that sends no origin
/// at all - the phone's and the Mac's own networking, a test - is let through: the token is what admits a device, and
/// a page elsewhere never has one.
async fn upgrade(State(live): State<Arc<Live>>, headers: HeaderMap, ws: WebSocketUpgrade) -> Response {
    if let Some(origin) = headers.get("origin") {
        let host = headers.get("host").and_then(|h| h.to_str().ok());
        if !crate::allowed_origin(origin.as_bytes()) && !same_site(origin.to_str().unwrap_or(""), host) {
            return StatusCode::FORBIDDEN.into_response();
        }
    }
    ws.max_message_size(MAX_FRAME).max_frame_size(MAX_FRAME).on_upgrade(move |socket| serve(live, socket))
}

/// A page served over HTTPS from the host this socket reached.
fn same_site(origin: &str, host: Option<&str>) -> bool {
    host.is_some_and(|host| origin.strip_prefix("https://") == Some(host))
}

fn text(value: Value) -> Message {
    Message::Text(Utf8Bytes::from(value.to_string()))
}

fn close(code: u16, reason: &'static str) -> Message {
    Message::Close(Some(CloseFrame { code, reason: Utf8Bytes::from_static(reason) }))
}

impl Live {
    fn hub(&self) -> std::sync::MutexGuard<'_, Hub> {
        // A panic while holding the lock leaves the map as it was; carrying on is better than refusing every device.
        self.hub.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Counts a socket against its account, or refuses it.
    fn admit(&self, account: i64) -> bool {
        let mut hub = self.hub();
        let count = hub.sockets.entry(account).or_insert(0);
        if *count >= SOCKETS_PER_ACCOUNT {
            return false;
        }
        *count += 1;
        true
    }

    fn release(&self, account: i64) {
        let mut hub = self.hub();
        if let Some(count) = hub.sockets.get_mut(&account) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                hub.sockets.remove(&account);
            }
        }
    }

    /// Whether an account has joined an organization, asked of the store: at every join, and on a message once the
    /// last answer is older than RECHECK_SECS.
    fn member(&self, account: i64, org: &str) -> bool {
        self.accounts.store.is_member(account, org)
    }

    /// Puts a socket in a room. Answers whether it opened the room, and the devices already there, each of which is
    /// told the new count.
    fn join(&self, scope: Scope, room: &str, member: Member) -> (bool, usize) {
        let mut hub = self.hub();
        let members = hub.rooms.entry((scope.clone(), room.to_string())).or_default();
        if members.iter().any(|m| m.id == member.id) {
            return (false, members.len() - 1);
        }
        let first = members.is_empty();
        members.push(member);
        let peers = members.len() - 1;
        let told = about(&scope, room, json!({ "t": "peers", "peers": peers }));
        for other in members.iter().take(members.len() - 1) {
            let _ = other.out.try_send(text(told.clone()));
        }
        (first, peers)
    }

    /// Takes a socket out of a room, telling whoever is left.
    fn leave(&self, scope: &Scope, room: &str, id: u64) {
        let mut hub = self.hub();
        let key = (scope.clone(), room.to_string());
        let Some(members) = hub.rooms.get_mut(&key) else { return };
        members.retain(|m| m.id != id);
        if members.is_empty() {
            hub.rooms.remove(&key);
            return;
        }
        // Who went, so the others can drop its presence at once rather than when it times out (docs/SHARED.md, S6).
        let told = text(about(scope, room, json!({ "t": "peers", "peers": members.len() - 1, "left": id })));
        for other in members.iter() {
            let _ = other.out.try_send(told.clone());
        }
    }

    /// Passes a sealed message to the room's other devices, or to one of them. A device whose queue is full has fallen
    /// too far behind to catch up message by message: it is taken out and closed, and comes back whole.
    fn relay(&self, scope: &Scope, room: &str, from: u64, data: &str, to: Option<u64>) {
        let message = text(about(scope, room, json!({ "t": "msg", "from": from, "data": data })));
        let behind: Vec<Member> = {
            let hub = self.hub();
            let Some(members) = hub.rooms.get(&(scope.clone(), room.to_string())) else { return };
            members
                .iter()
                .filter(|m| m.id != from && to.is_none_or(|to| m.id == to))
                .filter(|m| matches!(m.out.try_send(message.clone()), Err(mpsc::error::TrySendError::Full(_))))
                .cloned()
                .collect()
        };
        for member in behind {
            self.drop_everywhere(member.id);
            // Queued behind what it has not read yet: it arrives when the backlog does, and then the socket ends.
            tokio::spawn(async move {
                let _ = member.out.send(close(CLOSE_BEHIND, "Fell behind. Reconnect.")).await;
            });
        }
    }

    /// A socket out of every room it is in, whoever's: its id is one of a kind across the relay.
    fn drop_everywhere(&self, id: u64) {
        let rooms: Vec<(Scope, String)> = {
            let hub = self.hub();
            hub.rooms.iter().filter(|(_, members)| members.iter().any(|m| m.id == id)).map(|(key, _)| key.clone()).collect()
        };
        for (scope, room) in rooms {
            self.leave(&scope, &room, id);
        }
    }
}

async fn serve(live: Arc<Live>, mut socket: WebSocket) {
    // Who this is: the first frame, a token, checked by the one verifier every route uses.
    let claims = match tokio::time::timeout(AUTH_WAIT, socket.recv()).await {
        Ok(Some(Ok(Message::Text(frame)))) => serde_json::from_str::<Auth>(&frame)
            .ok()
            .filter(|auth| auth.t == "auth")
            .and_then(|auth| live.accounts.claims(&auth.token)),
        _ => None,
    };
    let Some(claims) = claims else {
        let _ = socket.send(close(CLOSE_AUTH, "Sign in first.")).await;
        return;
    };
    if !live.admit(claims.sub) {
        let _ = socket.send(close(CLOSE_BUSY, "Too many devices are live at once.")).await;
        return;
    }
    let account = claims.sub;
    let id = live.next.fetch_add(1, Ordering::Relaxed);
    let (out, mut outbox) = mpsc::channel::<Message>(QUEUE);
    let (mut sink, mut stream) = socket.split();

    // Everything to this device goes through one queue, so the room's messages and the pings never interleave badly.
    let writer = tokio::spawn(async move {
        let mut ping = tokio::time::interval(PING_EVERY);
        ping.tick().await;
        loop {
            tokio::select! {
                next = outbox.recv() => match next {
                    Some(message) => {
                        let ending = matches!(message, Message::Close(_));
                        if sink.send(message).await.is_err() || ending {
                            break;
                        }
                    }
                    None => break,
                },
                _ = ping.tick() => {
                    if sink.send(Message::Ping(Default::default())).await.is_err() {
                        break;
                    }
                }
            }
        }
    });

    let _ = out.send(text(json!({ "t": "ready", "id": id }))).await;
    // The rooms this socket is in: the organization’s, or none for the account’s own, and the room.
    let mut rooms: HashSet<(Option<String>, String)> = HashSet::new();
    // When each organization’s membership was last confirmed for this socket.
    let mut verified: HashMap<String, Instant> = HashMap::new();
    // `BURST` frames at once, refilled at `PER_SECOND`.
    let mut bucket = Bucket::new(BURST, PER_SECOND, Instant::now());
    // The socket lasts as long as the token does; the device comes back with a fresh one.
    let ends = tokio::time::sleep(Duration::from_secs(u64::try_from((claims.exp - now_secs()).max(0)).unwrap_or(0)));
    tokio::pin!(ends);

    loop {
        let frame = tokio::select! {
            frame = stream.next() => frame,
            () = &mut ends => {
                let _ = out.send(close(CLOSE_AUTH, "Your session has ended. Sign in again.")).await;
                break;
            }
        };
        let Some(Ok(frame)) = frame else { break };
        let frame = match frame {
            Message::Text(frame) => frame,
            Message::Close(_) => break,
            // Pings are answered by the socket itself; a pong is just the device still being there.
            Message::Ping(_) | Message::Pong(_) => continue,
            Message::Binary(_) => {
                let _ = out.send(close(CLOSE_BAD, "Text frames only.")).await;
                break;
            }
        };
        if !bucket.take(Instant::now()) {
            let _ = out.send(close(CLOSE_BUSY, "Too many messages. Slow down.")).await;
            break;
        }
        let refuse = |message: &'static str| text(json!({ "t": "error", "message": message }));
        match serde_json::from_str::<Incoming>(&frame) {
            Ok(Incoming::Join { room, org }) => {
                let key = (org.clone(), room.clone());
                if !base64url(&room, ROOM_LENGTH) || org.as_deref().is_some_and(|org| !base64url(org, ROOM_LENGTH)) {
                    let _ = out.try_send(refuse("That room name could not be read."));
                } else if !rooms.contains(&key) && rooms.len() >= ROOMS_PER_SOCKET {
                    let _ = out.try_send(refuse("Too many notes live at once on this device."));
                } else if org.as_deref().is_some_and(|org| !live.member(account, org)) {
                    // An organization's room is its members': a stranger, and an invitee who has not joined, get the
                    // organization's own refusal (orgs.rs), which says nothing about whether it exists.
                    let _ = out.try_send(refuse("No such organization."));
                } else {
                    if let Some(org) = &org {
                        verified.insert(org.clone(), Instant::now());
                    }
                    let scope = scope_of(account, org.as_deref());
                    let (first, peers) = live.join(scope.clone(), &room, Member { id, out: out.clone() });
                    rooms.insert(key);
                    let _ = out.try_send(text(about(&scope, &room, json!({ "t": "joined", "first": first, "peers": peers }))));
                }
            }
            Ok(Incoming::Leave { room, org }) => {
                if rooms.remove(&(org.clone(), room.clone())) {
                    live.leave(&scope_of(account, org.as_deref()), &room, id);
                }
            }
            // Ciphertext as base64url, and nothing else: the relay only ever carries sealed bytes it cannot read.
            Ok(Incoming::Msg { room, org, data, to }) => {
                if !rooms.contains(&(org.clone(), room.clone())) {
                    let _ = out.try_send(refuse("Join the room first."));
                } else if !base64url(&data, 1..=MAX_FRAME) {
                    let _ = out.try_send(refuse("That message could not be read."));
                } else if let Some(org_id) = org {
                    // Membership looked at again now and then: a member removed is out of the organization's rooms
                    // within RECHECK_SECS, and told as a stranger is.
                    let stale = verified.get(&org_id).is_none_or(|at| at.elapsed() >= Duration::from_secs(RECHECK_SECS.load(Ordering::Relaxed)));
                    if stale && !live.member(account, &org_id) {
                        let gone: Vec<String> = rooms.iter().filter(|(o, _)| o.as_deref() == Some(org_id.as_str())).map(|(_, r)| r.clone()).collect();
                        for r in gone {
                            rooms.remove(&(Some(org_id.clone()), r.clone()));
                            live.leave(&Scope::Org(org_id.clone()), &r, id);
                        }
                        verified.remove(&org_id);
                        let _ = out.try_send(refuse("No such organization."));
                    } else {
                        if stale {
                            verified.insert(org_id.clone(), Instant::now());
                        }
                        live.relay(&Scope::Org(org_id), &room, id, &data, to);
                    }
                } else {
                    live.relay(&Scope::Account(account), &room, id, &data, to);
                }
            }
            Err(_) => {
                let _ = out.try_send(refuse("That frame could not be read."));
            }
        }
    }

    for (org, room) in &rooms {
        live.leave(&scope_of(account, org.as_deref()), room, id);
    }
    live.release(account);
    // Let a close already queued go out before the writer is stopped.
    drop(out);
    let _ = tokio::time::timeout(Duration::from_secs(2), writer).await;
}
