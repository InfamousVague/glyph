//! Live sync's relay (src/live.rs, docs/LIVE.md), over a real socket: the in-memory router the other tests drive cannot
//! upgrade a connection, so these start the service on a loopback port and talk to it as a device does.
//!
//! No test here passes by waiting for nothing to happen. What a device should NOT hear is proven by `hears_nothing`,
//! which asks the relay for an answer and requires it to be the next frame: anything wrongly sent would already be
//! queued ahead of it. A quiet window would pass a relay that is merely slow.

use crate::accounts::Accounts;
use crate::live::{CLOSE_AUTH, CLOSE_BUSY, MAX_FRAME, ROOMS_PER_SOCKET, SOCKETS_PER_ACCOUNT};
use crate::test_support::{accounts_in, routes, signup_body, TempDir};
use crate::wire::now_secs;
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::net::SocketAddr;
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Arc;
use std::time::Duration;
use tokio::net::TcpStream;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::http::HeaderValue;
use tokio_tungstenite::tungstenite::Message;
use tokio_tungstenite::{connect_async, MaybeTlsStream, WebSocketStream};

type Socket = WebSocketStream<MaybeTlsStream<TcpStream>>;

struct Server {
    addr: SocketAddr,
    accounts: Arc<Accounts>,
    _dir: TempDir,
}

async fn server() -> Server {
    let dir = TempDir::new("live");
    let accounts = accounts_in(dir.path());
    let service = routes(Some(accounts.clone()));
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        axum::serve(listener, service.into_make_service_with_connect_info::<SocketAddr>()).await.unwrap();
    });
    Server { addr, accounts, _dir: dir }
}

impl Server {
    /// A new account, signed up the way a device does it; answers its token.
    async fn account(&self, handle: &str) -> String {
        let body: Value = reqwest::Client::new()
            .post(format!("http://{}/glyph/api/v1/signup", self.addr))
            .json(&signup_body(handle, None))
            .send()
            .await
            .unwrap()
            .json()
            .await
            .unwrap();
        body["token"].as_str().expect("a token").to_string()
    }

    fn url(&self) -> String {
        format!("ws://{}/glyph/api/v1/live", self.addr)
    }

    /// A device on the socket, signed in: answers it and its connection id.
    async fn device(&self, token: &str) -> (Socket, u64) {
        let (mut socket, _) = connect_async(self.url()).await.unwrap();
        send(&mut socket, json!({ "t": "auth", "token": token })).await;
        let ready = next(&mut socket).await;
        assert_eq!(ready["t"], "ready", "{ready}");
        (socket, ready["id"].as_u64().unwrap())
    }
}

async fn send(socket: &mut Socket, value: Value) {
    socket.send(Message::Text(value.to_string().into())).await.unwrap();
}

/// The next frame with words in it, skipping the relay's pings.
async fn next(socket: &mut Socket) -> Value {
    loop {
        let frame = tokio::time::timeout(Duration::from_secs(3), socket.next()).await.expect("a frame in time").expect("open").unwrap();
        match frame {
            Message::Text(text) => return serde_json::from_str(&text).unwrap(),
            Message::Close(frame) => return json!({ "closed": frame.map(|f| u16::from(f.code)) }),
            _ => continue,
        }
    }
}

/// Nothing is waiting for this device - what it should see of a message not meant for it.
///
/// It joins a room of its own and the next frame must be the answer to that. The join takes the relay's lock, which a
/// message holds while it is queued for every member it goes to, so a message sent before this that reached the device
/// wrongly is queued ahead of the answer, and arrives first, however slow the machine is. For a message from another
/// socket, call this on the sender first: its own answer proves its message has been relayed.
async fn hears_nothing(socket: &mut Socket) {
    static PROBES: AtomicUsize = AtomicUsize::new(0);
    let room = format!("probe-{}", PROBES.fetch_add(1, Ordering::Relaxed));
    send(socket, json!({ "t": "join", "room": room })).await;
    assert_eq!(next(socket).await, json!({ "t": "joined", "room": room, "first": true, "peers": 0 }), "nothing arrives before the answer");
}

fn sealed(tag: &str) -> String {
    URL_SAFE_NO_PAD.encode(format!("ciphertext:{tag}"))
}

#[tokio::test]
async fn a_socket_must_say_who_it_is_first() {
    let s = server().await;
    // A frame that is not a sign-in, and then a sign-in with a token that is not one: both closed with the code
    // a device reads as "sign in again".
    for first in [json!({ "t": "join", "room": "a" }), json!({ "t": "auth", "token": "glyph1.not.ours" })] {
        let (mut socket, _) = connect_async(s.url()).await.unwrap();
        send(&mut socket, first).await;
        assert_eq!(next(&mut socket).await, json!({ "closed": CLOSE_AUTH }));
    }
}

#[tokio::test]
async fn an_edit_reaches_the_accounts_other_device_and_not_its_own() {
    let s = server().await;
    let token = s.account("matt").await;
    let (mut phone, phone_id) = s.device(&token).await;
    let (mut mac, mac_id) = s.device(&token).await;

    send(&mut phone, json!({ "t": "join", "room": "note-1" })).await;
    assert_eq!(next(&mut phone).await, json!({ "t": "joined", "room": "note-1", "first": true, "peers": 0 }));
    send(&mut mac, json!({ "t": "join", "room": "note-1" })).await;
    // The second in is not first - it asks for the document rather than making one (LIVE.md, Seeding).
    assert_eq!(next(&mut mac).await, json!({ "t": "joined", "room": "note-1", "first": false, "peers": 1 }));
    assert_eq!(next(&mut phone).await, json!({ "t": "peers", "room": "note-1", "peers": 1 }));

    send(&mut phone, json!({ "t": "msg", "room": "note-1", "data": sealed("h") })).await;
    assert_eq!(next(&mut mac).await, json!({ "t": "msg", "room": "note-1", "from": phone_id, "data": sealed("h") }));
    hears_nothing(&mut phone).await;

    send(&mut mac, json!({ "t": "msg", "room": "note-1", "data": sealed("i") })).await;
    assert_eq!(next(&mut phone).await, json!({ "t": "msg", "room": "note-1", "from": mac_id, "data": sealed("i") }));
}

#[tokio::test]
async fn another_account_in_a_room_of_the_same_name_hears_nothing() {
    let s = server().await;
    let (mut mine, _) = s.device(&s.account("matt").await).await;
    let (mut theirs, _) = s.device(&s.account("someone").await).await;
    send(&mut mine, json!({ "t": "join", "room": "note-1" })).await;
    next(&mut mine).await;
    send(&mut theirs, json!({ "t": "join", "room": "note-1" })).await;
    // Rooms belong to an account: the other account opens its own, and is first in it.
    assert_eq!(next(&mut theirs).await, json!({ "t": "joined", "room": "note-1", "first": true, "peers": 0 }));
    send(&mut mine, json!({ "t": "msg", "room": "note-1", "data": sealed("secret") })).await;
    // Mine's own answer first, so the secret has been relayed to whoever it was going to reach.
    hears_nothing(&mut mine).await;
    hears_nothing(&mut theirs).await;
}

#[tokio::test]
async fn a_message_can_go_to_one_device() {
    let s = server().await;
    let token = s.account("matt").await;
    let (mut a, _) = s.device(&token).await;
    let (mut b, b_id) = s.device(&token).await;
    let (mut c, _) = s.device(&token).await;
    // One at a time, each join and the peer counts it causes read before the next, so the order is the test's.
    send(&mut a, json!({ "t": "join", "room": "n" })).await;
    assert_eq!(next(&mut a).await["t"], "joined");
    send(&mut b, json!({ "t": "join", "room": "n" })).await;
    assert_eq!(next(&mut b).await["t"], "joined");
    assert_eq!(next(&mut a).await["peers"], 1);
    send(&mut c, json!({ "t": "join", "room": "n" })).await;
    assert_eq!(next(&mut c).await["t"], "joined");
    assert_eq!(next(&mut a).await["peers"], 2);
    assert_eq!(next(&mut b).await["peers"], 2);
    // A whole document for the device that asked for it, not for everyone in the room.
    send(&mut a, json!({ "t": "msg", "room": "n", "data": sealed("state"), "to": b_id })).await;
    assert_eq!(next(&mut b).await["data"], sealed("state"));
    hears_nothing(&mut c).await;
    // Addressed to a device of the account's that is not in the room, it goes to nobody: not to that device, and not
    // to the room instead.
    let (mut d, d_id) = s.device(&token).await;
    send(&mut a, json!({ "t": "msg", "room": "n", "data": sealed("stray"), "to": d_id })).await;
    hears_nothing(&mut a).await;
    for other in [&mut b, &mut c, &mut d] {
        hears_nothing(other).await;
    }
}

#[tokio::test]
async fn a_device_leaving_is_told_to_the_others() {
    let s = server().await;
    let token = s.account("matt").await;
    let (mut a, _) = s.device(&token).await;
    let (mut b, _) = s.device(&token).await;
    send(&mut a, json!({ "t": "join", "room": "n" })).await;
    next(&mut a).await;
    send(&mut b, json!({ "t": "join", "room": "n" })).await;
    next(&mut b).await;
    next(&mut a).await;
    send(&mut b, json!({ "t": "leave", "room": "n" })).await;
    assert_eq!(next(&mut a).await, json!({ "t": "peers", "room": "n", "peers": 0 }));
    // And a socket that simply goes, as a phone does when it sleeps.
    send(&mut b, json!({ "t": "join", "room": "n" })).await;
    next(&mut b).await;
    next(&mut a).await;
    drop(b);
    assert_eq!(next(&mut a).await, json!({ "t": "peers", "room": "n", "peers": 0 }));
}

#[tokio::test]
async fn it_refuses_what_it_should_not_carry_and_keeps_the_socket() {
    let s = server().await;
    let (mut a, _) = s.device(&s.account("matt").await).await;
    // Not in the room yet.
    send(&mut a, json!({ "t": "msg", "room": "n", "data": sealed("x") })).await;
    assert_eq!(next(&mut a).await["t"], "error");
    // A room name that is not one.
    send(&mut a, json!({ "t": "join", "room": "../../etc" })).await;
    assert_eq!(next(&mut a).await["t"], "error");
    // Words rather than sealed bytes: the relay only carries base64url it cannot read.
    send(&mut a, json!({ "t": "join", "room": "n" })).await;
    next(&mut a).await;
    send(&mut a, json!({ "t": "msg", "room": "n", "data": "plain words, not ciphertext" })).await;
    assert_eq!(next(&mut a).await["t"], "error");
    // Still open after all that.
    send(&mut a, json!({ "t": "leave", "room": "n" })).await;
    send(&mut a, json!({ "t": "join", "room": "m" })).await;
    assert_eq!(next(&mut a).await["t"], "joined");
}

#[tokio::test]
async fn a_frame_past_the_limit_ends_the_socket() {
    let s = server().await;
    let (mut a, _) = s.device(&s.account("matt").await).await;
    send(&mut a, json!({ "t": "join", "room": "n" })).await;
    next(&mut a).await;
    let too_big = "A".repeat(MAX_FRAME + 1);
    let _ = a.send(Message::Text(json!({ "t": "msg", "room": "n", "data": too_big }).to_string().into())).await;
    let ended = tokio::time::timeout(Duration::from_secs(3), async {
        loop {
            match a.next().await {
                None | Some(Err(_)) => return true,
                Some(Ok(Message::Close(_))) => return true,
                Some(Ok(_)) => continue,
            }
        }
    })
    .await
    .unwrap_or(false);
    assert!(ended, "a frame over MAX_FRAME must end the socket");
}

#[tokio::test]
async fn a_page_from_elsewhere_cannot_open_one() {
    let s = server().await;
    let mut request = s.url().into_client_request().unwrap();
    request.headers_mut().insert("origin", HeaderValue::from_static("https://evil.example"));
    assert!(connect_async(request).await.is_err(), "an origin the HTTP routes refuse must be refused here too");
    // The Mac and phone apps' own origin is let in.
    let mut request = s.url().into_client_request().unwrap();
    request.headers_mut().insert("origin", HeaderValue::from_static("tauri://localhost"));
    assert!(connect_async(request).await.is_ok());
    // And the page served from this very host: a browser sends Origin on every WebSocket, same-origin included, so
    // without this the web version would be refused at its own address.
    let mut request = s.url().into_client_request().unwrap();
    let own = format!("https://{}", s.addr);
    request.headers_mut().insert("origin", HeaderValue::from_str(&own).unwrap());
    assert!(connect_async(request).await.is_ok(), "the site's own page must be let in");
    // But not a page that merely names a host of its own.
    let mut request = s.url().into_client_request().unwrap();
    request.headers_mut().insert("origin", HeaderValue::from_static("https://attack.fm.evil.example"));
    assert!(connect_async(request).await.is_err());
}

#[tokio::test]
async fn an_account_may_have_sixteen_devices_live_and_not_a_seventeenth() {
    let s = server().await;
    let token = s.account("matt").await;
    let mut live = Vec::new();
    for _ in 0..SOCKETS_PER_ACCOUNT {
        live.push(s.device(&token).await);
    }
    let (mut one_more, _) = connect_async(s.url()).await.unwrap();
    send(&mut one_more, json!({ "t": "auth", "token": token })).await;
    assert_eq!(next(&mut one_more).await, json!({ "closed": CLOSE_BUSY }), "a runaway client, not a seventeenth phone");
    // Another account is counted on its own.
    let (_other, _) = s.device(&s.account("sam").await).await;
    // And the sixteen are still live.
    hears_nothing(&mut live[0].0).await;
}

#[tokio::test]
async fn a_device_may_have_sixty_four_notes_live_and_joining_one_again_is_not_another() {
    let s = server().await;
    let (mut a, _) = s.device(&s.account("matt").await).await;
    for i in 0..ROOMS_PER_SOCKET {
        send(&mut a, json!({ "t": "join", "room": format!("n{i}") })).await;
        assert_eq!(next(&mut a).await["t"], "joined", "note {i}");
    }
    send(&mut a, json!({ "t": "join", "room": "one-too-many" })).await;
    assert_eq!(next(&mut a).await, json!({ "t": "error", "message": "Too many notes live at once on this device." }));
    // A note it already has is not one more, and joining it twice leaves it the one member.
    send(&mut a, json!({ "t": "join", "room": "n0" })).await;
    assert_eq!(next(&mut a).await, json!({ "t": "joined", "room": "n0", "first": false, "peers": 0 }));
    // Leaving one makes room.
    send(&mut a, json!({ "t": "leave", "room": "n1" })).await;
    send(&mut a, json!({ "t": "join", "room": "one-too-many" })).await;
    assert_eq!(next(&mut a).await, json!({ "t": "joined", "room": "one-too-many", "first": true, "peers": 0 }));
}

#[tokio::test]
async fn a_socket_ends_when_its_token_does_and_says_sign_in_again() {
    let s = server().await;
    s.account("matt").await;
    // The socket is open before the token is made, so the token's three seconds need cover only the one frame that
    // signs in with it, not the connection and the upgrade as well.
    let (mut phone, _) = connect_async(s.url()).await.unwrap();
    let token = s.accounts.issue_until(1, "matt", now_secs() + 3);
    send(&mut phone, json!({ "t": "auth", "token": token })).await;
    let ready = next(&mut phone).await;
    assert_eq!(ready["t"], "ready", "{ready}");
    // The ceiling only bounds a failure; the close ends the wait the moment it comes.
    let ended = tokio::time::timeout(Duration::from_secs(15), async {
        loop {
            match phone.next().await {
                Some(Ok(Message::Close(frame))) => return frame.map(|f| u16::from(f.code)),
                Some(Ok(_)) => continue,
                other => panic!("the socket ended without a close frame: {other:?}"),
            }
        }
    })
    .await
    .expect("closed when the token lapsed, within the ceiling");
    assert_eq!(ended, Some(CLOSE_AUTH), "the code a device reads as sign in again, and then comes back with a fresh token");
}
