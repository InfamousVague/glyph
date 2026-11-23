//! The node: one device on the direct network (docs/OPEN_NETWORK.md, section 2; lib/net/p2p/node.dart is what the app
//! holds it by).
//!
//! It offers one thing: framed streams to another node by its id, on a numbered channel. A stream is a QUIC
//! bidirectional stream. Whoever opens it says the channel in its first byte; the other end answers one byte
//! ([`ACCEPTED`]) once it has checked that this node may have that channel, and from there both ends send frames of
//! `[length: 4 bytes, big-endian][bytes]`, at most [`MAX_FRAME`] bytes each.
//!
//! What it never does:
//! - look anyone up, or publish where it is: the endpoint is made with no address lookup at all, and its DNS (only
//!   ever asked for a link helper's name) asks the system's own servers and nobody else's;
//! - talk to a link helper the app did not name: a hint's helper is used only when it is one of this node's own;
//! - let a node that was not allowed say anything, or tell it anything: one that comes through a link helper is
//!   refused before any handshake (the helper says who is calling), and any other as soon as the handshake has said
//!   who it is, before iroh has taken the link for its own and told it this node's addresses;
//! - hold more than it was told to: every length from the other side is checked before it is believed, a frame's
//!   memory grows only as its bytes arrive, a stream's queue of frames to send is bounded and closes the stream
//!   when it overflows, and everything read but not yet taken by the app is counted against a stream's window and
//!   the node's one budget ([`NODE_BUDGET`]).

use std::{
    collections::HashMap,
    future::Future,
    net::{IpAddr, SocketAddr},
    sync::{
        Arc, Mutex, MutexGuard, RwLock,
        atomic::{AtomicU64, AtomicUsize, Ordering},
    },
    time::Duration,
};

use iroh::{
    Endpoint, EndpointAddr, EndpointId, RelayMode, RelayUrl, SecretKey, TransportAddr, Watcher,
    dns::DnsResolver,
    endpoint::{
        AfterHandshakeOutcome, ConnectError, ConnectWithOptsError, ConnectingError, Connection, ConnectionError, EndpointHooks, IncomingAddr,
        PathList, QuicTransportConfig, ReadError, ReadExactError, RecvStream, SendStream, TransportErrorCode, VarInt, WriteError, presets,
    },
};
use n0_future::StreamExt;
use tokio::{
    runtime::Handle,
    sync::{Notify, Semaphore, mpsc, watch},
    task::JoinSet,
    time::{Instant, timeout, timeout_at},
};
use tokio_util::sync::CancellationToken;

use crate::wire::{Channels, Closed, Command, Config, Event, FRAME_AT, Hint, MAX_ADDRESSES, MAX_FRAME, OpenError, PathKind};

/// The one protocol a node speaks. Another number is another protocol: a node of one never talks to the other.
pub const ALPN: &[u8] = b"ghost/1";

/// What the accepting end answers a stream's channel with.
const ACCEPTED: u8 = 1;

/// What a link or a stream is closed with, for the other end to read.
mod code {
    /// This node has not allowed the other.
    pub const NOT_ALLOWED: u32 = 1;
    /// The other is allowed, but not on that channel.
    pub const REFUSED: u32 = 2;
    /// The stream was closed.
    pub const CLOSED: u32 = 3;
    /// What came was no frame.
    pub const BROKEN: u32 = 4;
    /// The link carried no stream for [`super::LINK_IDLE`].
    pub const IDLE: u32 = 5;
    /// The other node linked again: its earlier link is let go.
    pub const REPLACED: u32 = 6;
    /// This node is stopping.
    pub const STOPPED: u32 = 7;
    /// This node has all the links it takes.
    pub const BUSY: u32 = 8;
    /// More was sent than the stream's queue holds.
    pub const OVERFLOW: u32 = 9;
}

/// How many streams the other node may have open to this one at once, on one link. Seven, not a rounder number: QUIC
/// (noq) tells the other end of a place that has come free only once more than an eighth of them are free, which
/// with fewer than eight is at once; with eight, the eighth place would wait for a second stream to end.
pub const STREAMS_PER_LINK: u32 = 7;
/// QUIC's own windows: how much the other node may send on one stream, and on one link, that nothing here has read.
const STREAM_WINDOW: u32 = 256 * 1024;
const LINK_WINDOW: u32 = 1024 * 1024;
/// How much this node sends on one link that the other has not yet acknowledged.
const SEND_WINDOW: u64 = 4 * 1024 * 1024;

/// A stream's queue of frames not yet written: past either, the stream is closed.
pub const SEND_QUEUE_BYTES: usize = 4 * 1024 * 1024;
pub const SEND_QUEUE_FRAMES: usize = 4096;
/// Every so many frames written, the app is told how far the writing has got; and whenever the queue is empty, and
/// whenever the next frame has not gone within a moment.
const SAY_SENT_EVERY: u64 = 64;
const SAY_SENT_WITHIN: Duration = Duration::from_millis(10);

/// What a stream may have read that the app has not taken: a frame of the most, and a little.
pub const TAKE_WINDOW: usize = MAX_FRAME + 64 * 1024;
/// What the whole node may have read that the app has not taken, whoever sent it.
pub const NODE_BUDGET: usize = 32 * 1024 * 1024;
/// What a frame costs of both, over its bytes (an empty frame is not free), and what an incoming stream costs of the
/// budget until the app has handled its end.
pub const FRAME_COST: usize = 64;
pub const STREAM_COST: usize = 256;
/// A frame's bytes are made room for this much at a time, as they come.
const READ_STEP: usize = 64 * 1024;
/// A frame whose length has been said is given this long, and its bytes no slower than this, before the stream is
/// taken to be broken: what was set aside for it is not held for a sender that never sends.
const FRAME_GRACE: Duration = Duration::from_secs(15);
const FRAME_SLOWEST: usize = 8 * 1024;

/// Handshakes under way at once, and incoming links in all.
const MOST_HANDSHAKES: usize = 64;
const MOST_INCOMING_LINKS: usize = 256;
const HANDSHAKE_TIME: Duration = Duration::from_secs(10);
/// An incoming stream says its channel within this.
const CHANNEL_TIME: Duration = Duration::from_secs(10);
/// A link that carries no stream is closed after this: an open link costs both devices a packet every few seconds.
/// (The tests do not wait half a minute to see it.)
pub const LINK_IDLE: Duration = Duration::from_secs(if cfg!(test) { 4 } else { 30 });
/// A stream that was closed is given this long to write what was queued before it, and then this long for the other
/// end to see its end.
const CLOSE_FLUSH: Duration = Duration::from_secs(10);
const CLOSE_SEEN: Duration = Duration::from_secs(5);
/// What `open` waits at least and at most, whatever it was asked.
const OPEN_SHORTEST: Duration = Duration::from_millis(100);
const OPEN_LONGEST: Duration = Duration::from_secs(60);
/// The app hears where this node is no more often than this.
const WHEREABOUTS_EVERY: Duration = Duration::from_secs(1);
/// A link's round trip is looked at again this often, and a second after the link comes up.
const PATH_LOOK: Duration = Duration::from_secs(10);
/// A stopping node's own tasks are given this long to end before they are ended for it.
const TASKS_WAIT: Duration = Duration::from_secs(2);

/// A lock that a panic elsewhere has not made useless.
fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|poisoned| poisoned.into_inner())
}

/// Who may link with this node, and on which channels. Kept by the node across a stop and a start.
#[derive(Debug, Default)]
struct Admission {
    allowed: HashMap<EndpointId, Channels>,
    open: Channels,
}

impl Admission {
    /// Whether `node` may link at all.
    fn admits(&self, node: &EndpointId) -> bool {
        !self.open.is_empty() || self.allowed.get(node).is_some_and(|c| !c.is_empty())
    }

    /// Whether `node` may open a stream on `channel`.
    fn permits(&self, node: &EndpointId, channel: u8) -> bool {
        self.open.has(channel) || self.allowed.get(node).is_some_and(|c| c.has(channel))
    }
}

type Gatekeeper = Arc<RwLock<Admission>>;

fn admits(gate: &Gatekeeper, node: &EndpointId) -> bool {
    gate.read().unwrap_or_else(|p| p.into_inner()).admits(node)
}

fn permits(gate: &Gatekeeper, node: &EndpointId, channel: u8) -> bool {
    gate.read().unwrap_or_else(|p| p.into_inner()).permits(node, channel)
}

/// iroh's own check as a handshake ends: a second look at a caller `Run::admit` has already let through, and the
/// count of links. It holds the list and a count, never the endpoint (which holds it).
#[derive(Debug)]
struct Gate {
    admission: Gatekeeper,
    incoming: Arc<AtomicUsize>,
}

impl EndpointHooks for Gate {
    async fn after_handshake(&self, conn: &Connection) -> AfterHandshakeOutcome {
        // A link this node dialled is one it chose.
        if conn.side().is_client() {
            return AfterHandshakeOutcome::Accept;
        }
        if !admits(&self.admission, &conn.remote_id()) {
            return AfterHandshakeOutcome::Reject { error_code: VarInt::from_u32(code::NOT_ALLOWED), reason: b"not allowed".to_vec() };
        }
        if self.incoming.load(Ordering::Relaxed) >= MOST_INCOMING_LINKS {
            return AfterHandshakeOutcome::Reject { error_code: VarInt::from_u32(code::BUSY), reason: b"busy".to_vec() };
        }
        AfterHandshakeOutcome::Accept
    }
}

/// What lives as long as the node does.
struct Shared {
    events: mpsc::UnboundedSender<Event>,
    admission: Gatekeeper,
    /// The node while it is up, for what must not wait behind a start or a stop: sending, closing, taking.
    run: RwLock<Option<Arc<Run>>>,
    /// Streams are numbered by the node, never twice, across every start.
    next_stream: AtomicU64,
}

impl Shared {
    fn say(&self, event: Event) {
        let _ = self.events.send(event);
    }

    fn running(&self) -> Option<Arc<Run>> {
        self.run.read().unwrap_or_else(|p| p.into_inner()).clone()
    }
}

/// What the app asks that is done in order, one at a time. (Who is allowed is written down at once, where the app
/// asks it: only what follows from it waits its turn here.)
enum Act {
    Start(Config, Option<TestHelper>),
    Stop,
    /// Who is allowed has changed: what is open and no longer allowed is closed.
    Recheck,
    /// A node was disallowed: everything with it is closed.
    LetGo(EndpointId),
    Open {
        request: u32,
        node: [u8; 32],
        channel: u8,
        wait: Duration,
        hint: Hint,
    },
    NetworkChanged,
    End,
}

/// A link helper inside a test's own process: its map (with the port its address discovery listens on), and leave to
/// trust its self-signed certificate. There is no such thing outside the tests.
#[cfg(test)]
pub(crate) type TestHelper = iroh::RelayMap;
#[cfg(not(test))]
pub(crate) type TestHelper = std::convert::Infallible;

/// Why a frame could not be queued.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SendError {
    /// No such stream: it has closed, or never was.
    NoStream,
    /// Longer than [`MAX_FRAME`].
    TooLong,
    /// The stream's queue was full: the stream is closed.
    Overflow,
}

/// A node, as the C interface and the tests hold it. It is off until it is started; dropping it stops it.
pub struct Node {
    shared: Arc<Shared>,
    acts: mpsc::UnboundedSender<Act>,
}

impl Node {
    /// A node whose tasks run on `on`, and whose events are given to `sink` one at a time, in order.
    pub fn new(on: &Handle, sink: impl Fn(Event) + Send + 'static) -> Node {
        let (events, mut said) = mpsc::unbounded_channel();
        let (acts, asked) = mpsc::unbounded_channel();
        let shared = Arc::new(Shared { events, admission: Gatekeeper::default(), run: RwLock::new(None), next_stream: AtomicU64::new(0) });
        on.spawn(async move {
            while let Some(event) = said.recv().await {
                sink(event);
            }
        });
        on.spawn(lifecycle(shared.clone(), asked, on.clone()));
        Node { shared, acts }
    }

    pub fn start(&self, config: Config) {
        let _ = self.acts.send(Act::Start(config, None));
    }

    #[cfg(test)]
    pub(crate) fn start_with(&self, config: Config, helper: TestHelper) {
        let _ = self.acts.send(Act::Start(config, Some(helper)));
    }

    pub fn stop(&self) {
        let _ = self.acts.send(Act::Stop);
    }

    /// Lets `node` open streams on `channels`, in place of what it could before; none takes it off the list. In force
    /// when this returns: a caller or a stream that comes after it is judged by it. What it closes (streams on
    /// channels the node no longer has) is closed a moment later, in its turn.
    pub fn allow(&self, node: [u8; 32], channels: Channels) {
        let Ok(id) = EndpointId::from_bytes(&node) else { return };
        {
            let mut admission = self.shared.admission.write().unwrap_or_else(|p| p.into_inner());
            if channels.is_empty() {
                admission.allowed.remove(&id);
            } else {
                admission.allowed.insert(id, channels);
            }
        }
        let _ = self.acts.send(Act::Recheck);
    }

    /// Takes `node` off the list (in force when this returns) and closes every link and stream with it.
    pub fn disallow(&self, node: [u8; 32]) {
        let Ok(id) = EndpointId::from_bytes(&node) else { return };
        self.shared.admission.write().unwrap_or_else(|p| p.into_inner()).allowed.remove(&id);
        let _ = self.acts.send(Act::LetGo(id));
    }

    /// The channels anyone at all may open, in place of what they were. In force when this returns.
    pub fn open_to_all(&self, channels: Channels) {
        self.shared.admission.write().unwrap_or_else(|p| p.into_inner()).open = channels;
        let _ = self.acts.send(Act::Recheck);
    }

    /// Answered with [`Event::Opened`] or [`Event::OpenFailed`], naming `request`.
    pub fn open(&self, request: u32, node: [u8; 32], channel: u8, wait: Duration, hint: Hint) {
        let _ = self.acts.send(Act::Open { request, node, channel, wait, hint });
    }

    pub fn network_changed(&self) {
        let _ = self.acts.send(Act::NetworkChanged);
    }

    /// Queues a frame on a stream. It is written in its turn, and [`Event::Sent`] says when it has been.
    pub fn send(&self, stream: u64, frame: &[u8]) -> Result<(), SendError> {
        if frame.len() > MAX_FRAME {
            return Err(SendError::TooLong);
        }
        let st = self.shared.running().and_then(|run| lock(&run.streams).get(&stream).cloned()).ok_or(SendError::NoStream)?;
        let mut bytes = Vec::with_capacity(4 + frame.len());
        bytes.extend_from_slice(&(frame.len() as u32).to_be_bytes());
        bytes.extend_from_slice(frame);
        let mut queued = lock(&st.queued);
        if queued.closing {
            return Err(SendError::NoStream);
        }
        if queued.bytes + bytes.len() > SEND_QUEUE_BYTES || queued.frames >= SEND_QUEUE_FRAMES {
            queued.closing = true;
            drop(queued);
            st.stop_for(Closed::Overflow);
            return Err(SendError::Overflow);
        }
        queued.bytes += bytes.len();
        queued.frames += 1;
        st.out.send(Out::Frame(bytes)).map_err(|_| SendError::NoStream)
    }

    /// Closes a stream: what was queued before is written first, then the other end sees the end of it.
    /// [`Event::Closed`] says when. Closing what is closed is nothing.
    pub fn close(&self, stream: u64) {
        let Some(st) = self.shared.running().and_then(|run| lock(&run.streams).get(&stream).cloned()) else {
            return;
        };
        let mut queued = lock(&st.queued);
        if !queued.closing {
            queued.closing = true;
            let _ = st.out.send(Out::Finish);
            drop(queued);
            st.close_asked.notify_one();
        }
    }

    /// The app has handed `frames` frames of `bytes` bytes in all to whoever listens on a stream: that much more may
    /// be read for it.
    pub fn taken(&self, stream: u64, frames: u32, bytes: u32) {
        let Some(run) = self.shared.running() else { return };
        let credit = lock(&run.credits).get(&stream).cloned();
        if let Some(credit) = credit {
            run.give_back(&credit, (bytes as usize).saturating_add((frames as usize).saturating_mul(FRAME_COST)));
        }
    }

    /// The app has handled a stream's [`Event::Closed`]: whatever was still counted for it is let go.
    pub fn done(&self, stream: u64) {
        let Some(run) = self.shared.running() else { return };
        if lock(&run.streams).contains_key(&stream) {
            return;
        }
        let credit = lock(&run.credits).remove(&stream);
        if let Some(credit) = credit {
            let held = std::mem::take(&mut *lock(&credit.held));
            run.budget.add_permits(held + credit.stream);
        }
    }

    /// A command as the C interface is given it (src/wire.rs); what `ghost_p2p_command` answers.
    pub fn command(&self, bytes: &[u8]) -> i32 {
        use crate::wire::Malformed;
        let command = match Command::decode(bytes) {
            Ok(command) => command,
            Err(Malformed::TooLong) if bytes.first() == Some(&crate::wire::cmd::SEND) => return crate::ffi::TOO_LONG,
            Err(_) => return crate::ffi::MALFORMED,
        };
        match command {
            Command::Start(config) => self.start(config),
            Command::Stop => self.stop(),
            Command::Allow { node, channels } => self.allow(node, channels),
            Command::Disallow { node } => self.disallow(node),
            Command::OpenToAll { channels } => self.open_to_all(channels),
            Command::Open { request, node, channel, timeout, hint } => self.open(request, node, channel, timeout, hint),
            Command::Send { stream, .. } => {
                return match self.send(stream, &bytes[FRAME_AT..]) {
                    Ok(()) => crate::ffi::OK,
                    Err(SendError::NoStream) => crate::ffi::NO_STREAM,
                    Err(SendError::TooLong) => crate::ffi::TOO_LONG,
                    Err(SendError::Overflow) => crate::ffi::OVERFLOW,
                };
            }
            Command::Close { stream } => self.close(stream),
            Command::Taken { stream, frames, bytes } => self.taken(stream, frames, bytes),
            Command::Done { stream } => self.done(stream),
            Command::NetworkChanged => self.network_changed(),
        }
        crate::ffi::OK
    }

    /// How much of the node's budget is free, while it is up: the tests' own look at the counting.
    #[cfg(test)]
    pub(crate) fn budget_free(&self) -> Option<usize> {
        self.shared.running().map(|run| run.budget.available_permits())
    }

    /// What has crossed this node's sockets since it came up, as iroh counts it: bytes sent, bytes received, and
    /// datagrams received.
    #[cfg(test)]
    pub(crate) fn traffic(&self) -> Option<(u64, u64, u64)> {
        let run = self.shared.running()?;
        let m = &run.ep.metrics().socket;
        Some((
            m.send_ipv4.get() + m.send_ipv6.get() + m.send_relay.get(),
            m.recv_data_ipv4.get() + m.recv_data_ipv6.get() + m.recv_data_relay.get(),
            m.recv_datagrams.get(),
        ))
    }

    /// What iroh knows of where `node` is, while this one is up.
    #[cfg(test)]
    pub(crate) async fn knows_of(&self, node: [u8; 32]) -> Vec<TransportAddr> {
        let Some(run) = self.shared.running() else { return Vec::new() };
        let Ok(id) = EndpointId::from_bytes(&node) else { return Vec::new() };
        run.ep.remote_info(id).await.map(|info| info.into_addrs().map(|a| a.into_addr()).collect()).unwrap_or_default()
    }
}

impl Drop for Node {
    fn drop(&mut self) {
        let _ = self.acts.send(Act::End);
    }
}

/// The node id a secret makes, with nothing started.
pub fn node_id(secret: &[u8; 32]) -> [u8; 32] {
    *SecretKey::from_bytes(secret).public().as_bytes()
}

/// Starting, stopping and who is allowed: one thing at a time, in the order asked.
async fn lifecycle(shared: Arc<Shared>, mut asked: mpsc::UnboundedReceiver<Act>, on: Handle) {
    /// Says so if this ever ends by a bug: the app must not go on believing a node is up that nothing is running.
    struct Fell(Arc<Shared>);
    impl Drop for Fell {
        fn drop(&mut self) {
            if std::thread::panicking() {
                *self.0.run.write().unwrap_or_else(|p| p.into_inner()) = None;
                self.0.say(Event::Down { problem: "The direct network stopped by itself.".into() });
            }
        }
    }
    let _fell = Fell(shared.clone());
    let mut run: Option<Arc<Run>> = None;
    let mut started_with: Option<Config> = None;
    while let Some(act) = asked.recv().await {
        match act {
            Act::Start(config, helper) => {
                if let Some(up) = &run {
                    if started_with.as_ref() == Some(&config) {
                        shared.say(Event::Up { node: *up.id.as_bytes() });
                        continue;
                    }
                    end(&shared, &mut run).await;
                    shared.say(Event::Off);
                }
                match Run::begin(&shared, &config, helper, &on).await {
                    Ok(up) => {
                        *shared.run.write().unwrap_or_else(|p| p.into_inner()) = Some(up.clone());
                        shared.say(Event::Up { node: *up.id.as_bytes() });
                        up.go();
                        run = Some(up);
                        started_with = Some(config);
                    }
                    Err(problem) => {
                        started_with = None;
                        shared.say(Event::Down { problem });
                    }
                }
            }
            Act::Stop => {
                end(&shared, &mut run).await;
                started_with = None;
                shared.say(Event::Off);
            }
            Act::Recheck => {
                if let Some(up) = &run {
                    up.admission_changed();
                }
            }
            Act::LetGo(node) => {
                if let Some(up) = &run {
                    up.let_go(&node);
                }
            }
            Act::Open { request, node, channel, wait, hint } => match &run {
                Some(up) => up.tasks.spawn(up.clone().open(request, node, channel, wait, hint)),
                None => shared.say(Event::OpenFailed { request, why: OpenError::NotUp, message: "The direct network is not up.".into() }),
            },
            Act::NetworkChanged => {
                if let Some(up) = &run {
                    let ep = up.ep.clone();
                    up.tasks.spawn(async move { ep.network_change().await });
                }
            }
            Act::End => break,
        }
    }
    end(&shared, &mut run).await;
}

/// Stops the node where it is up. When this returns nothing of it is left: no task, no link, no socket.
async fn end(shared: &Arc<Shared>, run: &mut Option<Arc<Run>>) {
    let Some(up) = run.take() else { return };
    *shared.run.write().unwrap_or_else(|p| p.into_inner()) = None;
    up.shut().await;
}

/// What a stream's writer is handed.
enum Out {
    /// A frame with its length in front, as it goes on the wire.
    Frame(Vec<u8>),
    /// The stream was closed here: nothing after this.
    Finish,
}

#[derive(Default)]
struct Queued {
    bytes: usize,
    frames: usize,
    /// Nothing more is taken: it was closed here, it overflowed, or it has ended.
    closing: bool,
}

/// What a stream has read that the app has not taken.
struct Credit {
    window: Semaphore,
    /// What its frames have counted against the node's budget, and not yet given back.
    held: Mutex<usize>,
    /// What the stream itself counts, given back only when the app has handled its end.
    stream: usize,
}

struct Stream {
    id: u64,
    peer: EndpointId,
    channel: u8,
    incoming: bool,
    out: mpsc::UnboundedSender<Out>,
    queued: Mutex<Queued>,
    close_asked: Notify,
    stop: CancellationToken,
    /// Why it was stopped, where something stopped it.
    why: Mutex<Option<Closed>>,
    credit: Arc<Credit>,
}

impl Stream {
    fn stop_for(&self, why: Closed) {
        lock(&self.why).get_or_insert(why);
        self.stop.cancel();
    }
}

/// A link: one QUIC connection with another node, whichever of the two dialled.
struct Link {
    peer: EndpointId,
    conn: Connection,
    incoming: bool,
    stop: CancellationToken,
    /// What the connection is closed with, and what its streams are told, where something ended it.
    ended: Mutex<Option<(u32, Closed)>>,
    /// How many streams it carries (or is setting up), and how many of them this node opened.
    streams: watch::Sender<usize>,
    ours: AtomicUsize,
    /// How its path stands, as last seen.
    path: Mutex<Option<(PathKind, Option<u32>)>>,
}

impl Link {
    fn end_with(&self, code: u32, why: Closed) {
        lock(&self.ended).get_or_insert((code, why));
        self.stop.cancel();
    }

    fn live(&self) -> bool {
        !self.stop.is_cancelled() && self.conn.close_reason().is_none()
    }

    fn carrying(self: &Arc<Self>, ours: bool) -> Carried {
        self.streams.send_modify(|n| *n += 1);
        if ours {
            self.ours.fetch_add(1, Ordering::Relaxed);
        }
        Carried { link: self.clone(), ours }
    }

    /// Done once it has carried nothing for [`LINK_IDLE`].
    async fn idle(&self) {
        let mut count = self.streams.subscribe();
        loop {
            if count.wait_for(|n| *n == 0).await.is_err() {
                return;
            }
            if timeout(LINK_IDLE, count.wait_for(|n| *n > 0)).await.is_err() {
                return;
            }
        }
    }
}

/// A stream that `open` has opened and the other end has taken: its link, its place on it, and its two halves.
type Opened = (Arc<Link>, Carried, SendStream, RecvStream);

/// A stream a link is counted as carrying, for as long as this is held.
struct Carried {
    link: Arc<Link>,
    ours: bool,
}

impl Drop for Carried {
    fn drop(&mut self) {
        if self.ours {
            self.link.ours.fetch_sub(1, Ordering::Relaxed);
        }
        self.link.streams.send_modify(|n| *n = n.saturating_sub(1));
    }
}

/// The node's own tasks, so a stop can wait for every one and end what does not end.
struct Tasks {
    set: Mutex<Option<JoinSet<()>>>,
    on: Handle,
}

impl Tasks {
    fn spawn(&self, task: impl Future<Output = ()> + Send + 'static) {
        if let Some(set) = lock(&self.set).as_mut() {
            while set.try_join_next().is_some() {}
            set.spawn_on(task, &self.on);
        }
    }

    async fn end(&self, within: Duration) {
        let Some(mut set) = lock(&self.set).take() else { return };
        let ended = timeout(within, async { while set.join_next().await.is_some() {} }).await.is_ok();
        if !ended {
            set.abort_all();
            while set.join_next().await.is_some() {}
        }
    }
}

/// The node while it is up: an endpoint, its links and their streams. A start makes one, a stop ends it.
struct Run {
    shared: Arc<Shared>,
    ep: Endpoint,
    id: EndpointId,
    /// The link helpers: as iroh holds each, and as the app wrote it.
    helpers: Vec<(RelayUrl, String)>,
    helpers_only: bool,
    stop: CancellationToken,
    tasks: Tasks,
    links: Mutex<HashMap<EndpointId, Vec<Arc<Link>>>>,
    incoming_links: Arc<AtomicUsize>,
    /// One dial at a time to any one node.
    dialling: Mutex<HashMap<EndpointId, Arc<tokio::sync::Mutex<()>>>>,
    streams: Mutex<HashMap<u64, Arc<Stream>>>,
    /// Kept past a stream's end, until the app has handled it.
    credits: Mutex<HashMap<u64, Arc<Credit>>>,
    budget: Semaphore,
    handshakes: Arc<Semaphore>,
    /// How the path to each linked node was last said to stand.
    paths: Mutex<HashMap<EndpointId, (PathKind, Option<u32>)>>,
}

/// QUIC, bounded: the other node opens only streams of both directions and only so many, never sends a datagram, and
/// is acknowledged only so far ahead of what has been read.
fn transport() -> QuicTransportConfig {
    QuicTransportConfig::builder()
        .max_concurrent_bidi_streams(VarInt::from_u32(STREAMS_PER_LINK))
        .max_concurrent_uni_streams(VarInt::from_u32(0))
        .stream_receive_window(VarInt::from_u32(STREAM_WINDOW))
        .receive_window(VarInt::from_u32(LINK_WINDOW))
        .send_window(SEND_WINDOW)
        .datagram_receive_buffer_size(None)
        .build()
}

impl Run {
    async fn begin(shared: &Arc<Shared>, config: &Config, test_helper: Option<TestHelper>, on: &Handle) -> Result<Arc<Run>, String> {
        let mut helpers: Vec<(RelayUrl, String)> = Vec::new();
        for written in &config.helpers {
            if !written.starts_with("https://") {
                return Err(format!("A link helper's address begins https://, and this one does not: {written}"));
            }
            let url: RelayUrl = written.parse().map_err(|_| format!("This is not a link helper's address: {written}"))?;
            if !helpers.iter().any(|(known, _)| *known == url) {
                helpers.push((url, written.clone()));
            }
        }
        if config.helpers_only && helpers.is_empty() {
            return Err("Only through link helpers was chosen, and there is no link helper.".into());
        }
        let incoming_links = Arc::new(AtomicUsize::new(0));
        let mut builder = Endpoint::builder(presets::Minimal)
            .secret_key(SecretKey::from_bytes(&config.secret))
            .alpns(vec![ALPN.to_vec()])
            // Nobody is looked up and nothing is published: there is no address lookup to ask or to tell.
            .clear_address_lookup()
            .relay_mode(if helpers.is_empty() { RelayMode::Disabled } else { RelayMode::custom(helpers.iter().map(|(url, _)| url.clone())) })
            .transport_config(transport())
            // A link helper's name is asked of the system's own DNS servers and of no public one behind them.
            .dns_resolver(DnsResolver::builder().with_system_defaults().disable_fallback().build())
            .hooks(Gate { admission: shared.admission.clone(), incoming: incoming_links.clone() });
        #[cfg(test)]
        if let Some(map) = test_helper {
            builder = builder.relay_mode(RelayMode::Custom(map)).ca_tls_config(iroh::tls::CaTlsConfig::insecure_skip_verify());
        }
        #[cfg(not(test))]
        let _ = test_helper;
        if config.helpers_only {
            // No socket of this node's own at all: every packet goes through a link helper.
            builder = builder.clear_ip_transports();
        }
        let ep = builder.bind().await.map_err(|e| format!("The direct network could not start: {e:#}"))?;
        let run = Arc::new(Run {
            shared: shared.clone(),
            id: ep.id(),
            ep,
            helpers,
            helpers_only: config.helpers_only,
            stop: CancellationToken::new(),
            tasks: Tasks { set: Mutex::new(Some(JoinSet::new())), on: on.clone() },
            links: Mutex::default(),
            incoming_links,
            dialling: Mutex::default(),
            streams: Mutex::default(),
            credits: Mutex::default(),
            budget: Semaphore::new(NODE_BUDGET),
            handshakes: Arc::new(Semaphore::new(MOST_HANDSHAKES)),
            paths: Mutex::default(),
        });
        Ok(run)
    }

    /// Sets it going, once the app has been told it is up: taking callers, and saying where it is. (In that order,
    /// so that nothing a node says of itself comes before "up".)
    fn go(self: &Arc<Self>) {
        self.tasks.spawn(self.clone().serve());
        self.tasks.spawn(self.clone().tell_whereabouts());
    }

    /// Ends everything: the streams say so, every linked node is told, the sockets close.
    async fn shut(self: Arc<Self>) {
        self.stop.cancel();
        let links: Vec<Arc<Link>> = lock(&self.links).values().flatten().cloned().collect();
        for link in links {
            link.end_with(code::STOPPED, Closed::Stopped);
        }
        // Tells every linked node and waits for it to have heard (a few seconds at the very most), then ends iroh's
        // own tasks. The sockets themselves close when the last holder of the endpoint goes, just below.
        self.ep.close().await;
        self.tasks.end(TASKS_WAIT).await;
        // What a task that had to be ended could not say for itself.
        let left: Vec<u64> = lock(&self.streams).drain().map(|(id, _)| id).collect();
        for stream in left {
            self.shared.say(Event::Closed { stream, why: Closed::Stopped });
        }
        let linked: Vec<EndpointId> = lock(&self.paths).drain().map(|(node, _)| node).collect();
        for node in linked {
            self.shared.say(Event::Path { node: *node.as_bytes(), kind: PathKind::None, rtt_ms: None });
        }
        lock(&self.links).clear();
    }

    /// Takes whoever calls.
    async fn serve(self: Arc<Self>) {
        loop {
            let incoming = tokio::select! {
                _ = self.stop.cancelled() => return,
                incoming = self.ep.accept() => incoming,
            };
            let Some(incoming) = incoming else { return };
            // Through a link helper, the helper says who is calling before any handshake: a node that is not allowed
            // is refused here, and so learns nothing of this one at all.
            if let IncomingAddr::Relay { endpoint_id, .. } = incoming.remote_addr()
                && !admits(&self.shared.admission, &endpoint_id)
            {
                incoming.refuse();
                continue;
            }
            let Ok(slot) = self.handshakes.clone().try_acquire_owned() else {
                incoming.ignore();
                continue;
            };
            let run = self.clone();
            self.tasks.spawn(async move {
                let shaken = timeout(HANDSHAKE_TIME, run.admit(incoming));
                let conn = tokio::select! {
                    _ = run.stop.cancelled() => None,
                    conn = shaken => conn.ok().flatten(),
                };
                drop(slot);
                if let Some(conn) = conn {
                    run.linked(conn, true);
                }
            });
        }
    }

    /// The handshake with a caller, and who it turns out to be: a link where that node is allowed, nothing where it
    /// is not.
    ///
    /// The order matters. As soon as iroh takes a link for its own (which it does before it asks the gate) it tells
    /// the other end every address this node has, so that the two can find a straight path. So the caller is looked
    /// at before that: the connection is held by its early handle, which iroh has not yet taken, until the
    /// handshake has said who is calling, and a node that is not allowed is closed on there, never having been told
    /// that list. Nothing is read from or written to the early handle (whatever a caller sent ahead of its
    /// handshake waits, within QUIC's windows, until the handshake has ended and proved who sent it).
    ///
    /// What this does not close (README.md, "What a caller that is turned away can still learn"): QUIC's hole
    /// punching, inside iroh, answers a caller's own list of addresses with a small probe to each before anything
    /// here has a say, and a probe shows where it came from.
    async fn admit(&self, incoming: iroh::endpoint::Incoming) -> Option<Connection> {
        let early = incoming.accept().ok()?.into_0rtt();
        // iroh has nothing to wait on for "the handshake has said who it is", so it is looked for: after one
        // millisecond, then two, and so on to twenty.
        let mut pause = Duration::from_millis(1);
        let caller = loop {
            if early.peer_identity().is_some() {
                break early.remote_id().ok()?;
            }
            tokio::select! {
                _ = early.closed() => return None,
                _ = tokio::time::sleep(pause) => {}
            }
            pause = (pause * 2).min(Duration::from_millis(20));
        };
        if !admits(&self.shared.admission, &caller) {
            early.close(VarInt::from_u32(code::NOT_ALLOWED), b"not allowed");
            return None;
        }
        // The rest of the handshake; then iroh takes the link, and the gate looks once more.
        early.handshake_completed().await.ok()
    }

    /// A link is up: it is listed, and a task carries it until it ends.
    fn linked(self: &Arc<Self>, conn: Connection, incoming: bool) -> Arc<Link> {
        let peer = conn.remote_id();
        let (streams, _) = watch::channel(0);
        let link = Arc::new(Link {
            peer,
            conn,
            incoming,
            stop: self.stop.child_token(),
            ended: Mutex::new(None),
            streams,
            ours: AtomicUsize::new(0),
            path: Mutex::new(None),
        });
        {
            let mut links = lock(&self.links);
            let list = links.entry(peer).or_default();
            if incoming {
                // A node that links again has let its earlier link go (it dials only where it has none): so is it here.
                for earlier in list.iter().filter(|l| l.incoming) {
                    earlier.end_with(code::REPLACED, Closed::LinkLost);
                }
                self.incoming_links.fetch_add(1, Ordering::Relaxed);
            }
            list.push(link.clone());
        }
        // Allowed when the handshake ended; and now?
        if incoming && !admits(&self.shared.admission, &peer) {
            link.end_with(code::NOT_ALLOWED, Closed::NotAllowed);
        }
        self.tasks.spawn(self.clone().carry(link.clone()));
        link
    }

    /// Carries a link until it ends: takes the streams the other node opens, watches its path, lets it go when idle.
    async fn carry(self: Arc<Self>, link: Arc<Link>) {
        /// Whatever way this task ends, the link is closed and no longer listed.
        struct Ends(Arc<Run>, Arc<Link>);
        impl Drop for Ends {
            fn drop(&mut self) {
                let (run, link) = (&self.0, &self.1);
                // Closed here only where it is not closed already: closing it again would put "closed here" in
                // place of what the other end closed it with, which an open under way is about to read.
                if link.conn.close_reason().is_none() {
                    let code = (*lock(&link.ended)).map(|(code, _)| code).unwrap_or(code::CLOSED);
                    link.conn.close(VarInt::from_u32(code), b"");
                }
                link.stop.cancel();
                {
                    let mut links = lock(&run.links);
                    if let Some(list) = links.get_mut(&link.peer) {
                        list.retain(|l| !Arc::ptr_eq(l, link));
                        if list.is_empty() {
                            links.remove(&link.peer);
                        }
                    }
                }
                if link.incoming {
                    run.incoming_links.fetch_sub(1, Ordering::Relaxed);
                }
                run.say_path(&link.peer);
            }
        }
        let _ends = Ends(self.clone(), link.clone());
        let take = async {
            while let Ok((send, recv)) = link.conn.accept_bi().await {
                self.tasks.spawn(self.clone().taken_in(link.clone(), send, recv));
            }
        };
        // What follows the path never ends the link: iroh's word on a link's paths can end a moment before the link
        // itself is known to have, and closing it here in that moment would hide why the other end closed it.
        let watch = async {
            loop {
                self.watch_path(&link).await;
                tokio::time::sleep(Duration::from_secs(1)).await;
            }
        };
        tokio::select! {
            _ = link.stop.cancelled() => {}
            _ = take => {}
            _ = link.conn.closed() => {}
            _ = watch => {}
            _ = link.idle() => link.end_with(code::IDLE, Closed::LinkLost),
        }
    }

    /// Follows a link's path for as long as the link is up.
    async fn watch_path(&self, link: &Link) {
        let mut changes = link.conn.paths_stream();
        let mut look = tokio::time::interval_at(Instant::now() + Duration::from_secs(1), PATH_LOOK);
        look.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            let seen = tokio::select! {
                changed = changes.next() => match changed {
                    Some(paths) => standing(&paths),
                    None => return,
                },
                _ = look.tick() => standing(&link.conn.paths()),
            };
            if let Some(seen) = seen {
                *lock(&link.path) = Some(seen);
                self.say_path(&link.peer);
            }
        }
    }

    /// Says how the path to `peer` stands, where that is not what was last said: straight if any of its links is,
    /// and none when the last link has gone.
    fn say_path(&self, peer: &EndpointId) {
        let now = {
            let links = lock(&self.links);
            let mut best: Option<(PathKind, Option<u32>)> = None;
            for link in links.get(peer).into_iter().flatten().filter(|l| l.live()) {
                let Some(seen) = *lock(&link.path) else { continue };
                best = Some(match best {
                    None => seen,
                    Some(had)
                        if (seen.0 as u8, std::cmp::Reverse(seen.1.unwrap_or(u32::MAX)))
                            > (had.0 as u8, std::cmp::Reverse(had.1.unwrap_or(u32::MAX))) =>
                    {
                        seen
                    }
                    Some(had) => had,
                });
            }
            best
        };
        let mut said = lock(&self.paths);
        match (said.get(peer).copied(), now) {
            (None, None) => {}
            (Some(_), None) => {
                said.remove(peer);
                self.shared.say(Event::Path { node: *peer.as_bytes(), kind: PathKind::None, rtt_ms: None });
            }
            (before, Some(now)) => {
                let same = before.is_some_and(|before| before.0 == now.0 && close_enough(before.1, now.1));
                if !same {
                    said.insert(*peer, now);
                    self.shared.say(Event::Path { node: *peer.as_bytes(), kind: now.0, rtt_ms: now.1 });
                }
            }
        }
    }

    /// The other node opened a stream: its first byte says the channel, and it is taken only where that is allowed.
    async fn taken_in(self: Arc<Self>, link: Arc<Link>, mut send: SendStream, mut recv: RecvStream) {
        let carried = link.carrying(false);
        let stop = link.stop.child_token();
        let mut first = [0u8; 1];
        let channel = tokio::select! {
            _ = stop.cancelled() => None,
            read = timeout(CHANNEL_TIME, recv.read_exact(&mut first)) => matches!(read, Ok(Ok(()))).then_some(first[0]),
        };
        let Some(channel) = channel else {
            turn_back(&mut send, &mut recv, code::BROKEN);
            return;
        };
        if !permits(&self.shared.admission, &link.peer, channel) {
            turn_back(&mut send, &mut recv, code::REFUSED);
            return;
        }
        // What the stream itself costs, until the app has handled its end: streams opened and closed faster than the
        // app looks at them are not kept without bound either.
        let paid = tokio::select! {
            _ = stop.cancelled() => false,
            permit = self.budget.acquire_many(STREAM_COST as u32) => permit.map(|p| p.forget()).is_ok(),
        };
        if !paid {
            turn_back(&mut send, &mut recv, code::STOPPED);
            return;
        }
        if send.write_all(&[ACCEPTED]).await.is_err() {
            self.budget.add_permits(STREAM_COST);
            return;
        }
        let (st, queue) = self.listed(&link, channel, true, stop, STREAM_COST);
        self.shared.say(Event::Incoming { stream: st.id, node: *link.peer.as_bytes(), channel });
        // Allowed when it was asked; and now?
        if !permits(&self.shared.admission, &link.peer, channel) {
            st.stop_for(Closed::NotAllowed);
        }
        self.pump(&link, st, send, recv, queue).await;
        drop(carried);
    }

    /// Opens a stream to `node` on `channel`, dialling where no link is up.
    async fn open(self: Arc<Self>, request: u32, node: [u8; 32], channel: u8, wait: Duration, hint: Hint) {
        let fail = |why: OpenError, message: &str| self.shared.say(Event::OpenFailed { request, why, message: message.into() });
        let Ok(peer) = EndpointId::from_bytes(&node) else {
            return fail(OpenError::BadRequest, "That is not a node id.");
        };
        if peer == self.id {
            return fail(OpenError::BadRequest, "A node does not link with itself.");
        }
        // How far it got, for the answer where the wait runs out; and the link, where one that was up already was used.
        let reached = AtomicUsize::new(0);
        let used: Mutex<Option<Arc<Link>>> = Mutex::new(None);
        let attempt = async {
            let (link, fresh) = self.link_to(peer, &hint).await?;
            if !fresh {
                *lock(&used) = Some(link.clone());
            }
            let carried = link.carrying(true);
            reached.store(1, Ordering::Relaxed);
            let (mut send, mut recv) = link.conn.open_bi().await.map_err(|e| why_lost(&e))?;
            reached.store(2, Ordering::Relaxed);
            send.write_all(&[channel]).await.map_err(|e| match e {
                WriteError::ConnectionLost(e) => why_lost(&e),
                _ => (OpenError::Unreachable, "The link was lost.".to_string()),
            })?;
            let mut answer = [0u8; 1];
            match recv.read_exact(&mut answer).await {
                Ok(()) if answer[0] == ACCEPTED => Ok((link, carried, send, recv)),
                Ok(()) => {
                    turn_back(&mut send, &mut recv, code::BROKEN);
                    Err((OpenError::Refused, "It answered what is no answer.".to_string()))
                }
                Err(ReadExactError::ReadError(ReadError::Reset(code))) if code == VarInt::from_u32(code::REFUSED) => {
                    Err((OpenError::Refused, "It does not take that channel from this device.".to_string()))
                }
                Err(ReadExactError::ReadError(ReadError::ConnectionLost(e))) => Err(why_lost(&e)),
                Err(_) => Err((OpenError::Refused, "It closed the stream as it was opened.".to_string())),
            }
        };
        // What the attempt came to, or that the wait ran out, or that this node stopped. The attempt itself, and with
        // it its place on the link, is gone by the end of this.
        enum Outcome {
            Came(Result<Opened, (OpenError, String)>),
            WaitedOut,
            Stopped,
        }
        let outcome = tokio::select! {
            _ = self.stop.cancelled() => Outcome::Stopped,
            came = timeout(wait.clamp(OPEN_SHORTEST, OPEN_LONGEST), attempt) => came.map(Outcome::Came).unwrap_or(Outcome::WaitedOut),
        };
        let opened = match outcome {
            Outcome::Came(opened) => opened,
            Outcome::Stopped => Err((OpenError::NotUp, "The direct network is not up.".to_string())),
            // The link is up and has no place for one more stream: nothing is wrong with the link.
            Outcome::WaitedOut if reached.load(Ordering::Relaxed) == 1 => {
                Err((OpenError::TooMany, "As many streams are open to it as one link carries.".to_string()))
            }
            Outcome::WaitedOut => {
                // A link that was up already, carries nothing else and does not answer is let go, so that the next try
                // dials. One that carries other streams is left to them: QUIC ends it within half a minute if the
                // other device has really gone.
                if let Some(link) = lock(&used).take()
                    && *link.streams.borrow() == 0
                {
                    link.end_with(code::IDLE, Closed::LinkLost);
                }
                Err((OpenError::Unreachable, "It did not answer in time.".to_string()))
            }
        };
        match opened {
            Ok((link, carried, send, recv)) => {
                let (st, queue) = self.listed(&link, channel, false, link.stop.child_token(), 0);
                self.shared.say(Event::Opened { request, stream: st.id });
                self.pump(&link, st, send, recv, queue).await;
                drop(carried);
            }
            Err((why, message)) => fail(why, &message),
        }
    }

    /// The link to `peer`: the newest that is up, or a dial by the hint and by what iroh already knows of it.
    async fn link_to(self: &Arc<Self>, peer: EndpointId, hint: &Hint) -> Result<(Arc<Link>, bool), (OpenError, String)> {
        if let Some(link) = self.live_link(&peer) {
            return Ok((link, false));
        }
        let one = lock(&self.dialling).entry(peer).or_default().clone();
        let dialled = async {
            let _turn = one.lock().await;
            if let Some(link) = self.live_link(&peer) {
                return Ok((link, false));
            }
            let conn = self.ep.connect(self.dial_addr(peer, hint), ALPN).await.map_err(|e| why_no_link(&e))?;
            Ok((self.linked(conn, false), true))
        }
        .await;
        // Nobody else waiting on this dial: its turn-keeper is not kept.
        let mut dialling = lock(&self.dialling);
        if Arc::strong_count(&one) <= 2 {
            dialling.remove(&peer);
        }
        dialled
    }

    fn live_link(&self, peer: &EndpointId) -> Option<Arc<Link>> {
        lock(&self.links).get(peer)?.iter().rev().find(|l| l.live()).cloned()
    }

    /// Where to dial `peer`, from what it last said: its link helper only where that is one of this node's own (this
    /// node talks to no server the app did not name, whoever asks), and its addresses unless this node shows its own
    /// to nobody.
    fn dial_addr(&self, peer: EndpointId, hint: &Hint) -> EndpointAddr {
        let mut addrs = Vec::new();
        if let Some(url) = hint.helper.as_deref().and_then(|h| h.parse::<RelayUrl>().ok())
            && self.helpers.iter().any(|(own, _)| *own == url)
        {
            addrs.push(TransportAddr::Relay(url));
        }
        if !self.helpers_only {
            for addr in hint.addresses.iter().take(MAX_ADDRESSES).filter_map(|a| a.parse::<SocketAddr>().ok()) {
                let ip = addr.ip().to_canonical();
                if addr.port() != 0 && !ip.is_unspecified() && !ip.is_multicast() && ip != IpAddr::V4(std::net::Ipv4Addr::BROADCAST) {
                    addrs.push(TransportAddr::Ip(SocketAddr::new(ip, addr.port())));
                }
            }
        }
        EndpointAddr::from_parts(peer, addrs)
    }

    /// A stream is up: it is given its number, its queue and its windows, and listed for the app to send on.
    fn listed(
        &self,
        link: &Arc<Link>,
        channel: u8,
        incoming: bool,
        stop: CancellationToken,
        cost: usize,
    ) -> (Arc<Stream>, mpsc::UnboundedReceiver<Out>) {
        let id = self.shared.next_stream.fetch_add(1, Ordering::Relaxed) + 1;
        let credit = Arc::new(Credit { window: Semaphore::new(TAKE_WINDOW), held: Mutex::new(0), stream: cost });
        lock(&self.credits).insert(id, credit.clone());
        let (out, queue) = mpsc::unbounded_channel();
        let st = Arc::new(Stream {
            id,
            peer: link.peer,
            channel,
            incoming,
            out,
            queued: Mutex::default(),
            close_asked: Notify::new(),
            stop,
            why: Mutex::new(None),
            credit,
        });
        lock(&self.streams).insert(id, st.clone());
        (st, queue)
    }

    /// Carries a stream until it ends, and says why it did.
    async fn pump(&self, link: &Link, st: Arc<Stream>, mut send: SendStream, mut recv: RecvStream, mut queue: mpsc::UnboundedReceiver<Out>) {
        enum End {
            Stopped,
            Overdue,
            Read(ReadEnd),
            Wrote(WriteEnd),
        }
        let end = {
            let overdue = async {
                st.close_asked.notified().await;
                tokio::time::sleep(CLOSE_FLUSH).await;
            };
            tokio::select! {
                // In this order: a stream that was told to stop says so, whatever else has happened to it by then.
                biased;
                _ = st.stop.cancelled() => End::Stopped,
                _ = overdue => End::Overdue,
                end = self.read_frames(&st, &mut recv) => End::Read(end),
                end = self.write_frames(&st, &mut send, &mut queue) => End::Wrote(end),
            }
        };
        let why = match end {
            End::Wrote(WriteEnd::Finished) => {
                // Closed here, and everything queued before is written. The end is sent, and the other end given a
                // while to see it (it resets its own half when it does): so a frame sent just before a close, or a
                // close just before a stop, is not lost to what comes after.
                let _ = send.finish();
                let seen = async {
                    let mut rest = [0u8; 4096];
                    while let Ok(Some(_)) = recv.read(&mut rest).await {}
                };
                tokio::select! {
                    _ = st.stop.cancelled() => {}
                    _ = timeout(CLOSE_SEEN, seen) => {}
                }
                let _ = recv.stop(VarInt::from_u32(code::CLOSED));
                Closed::ByUs
            }
            End::Overdue => {
                turn_back(&mut send, &mut recv, code::CLOSED);
                Closed::ByUs
            }
            End::Read(ReadEnd::Ended) | End::Wrote(WriteEnd::StoppedByThem) => {
                turn_back(&mut send, &mut recv, code::CLOSED);
                Closed::ByThem
            }
            End::Read(ReadEnd::Broken) => {
                turn_back(&mut send, &mut recv, code::BROKEN);
                Closed::Broken
            }
            // The link went: by this node's own doing where it ended it (stopping, no longer allowing the other),
            // which is then what is said.
            End::Read(ReadEnd::Lost) | End::Wrote(WriteEnd::Lost) => {
                (*lock(&link.ended)).map(|(_, why)| why).unwrap_or(if self.stop.is_cancelled() { Closed::Stopped } else { Closed::LinkLost })
            }
            End::Stopped => {
                let why = (*lock(&st.why)).or((*lock(&link.ended)).map(|(_, why)| why)).unwrap_or(if self.stop.is_cancelled() {
                    Closed::Stopped
                } else {
                    Closed::LinkLost
                });
                turn_back(
                    &mut send,
                    &mut recv,
                    match why {
                        Closed::NotAllowed => code::NOT_ALLOWED,
                        Closed::Overflow => code::OVERFLOW,
                        Closed::Stopped => code::STOPPED,
                        _ => code::CLOSED,
                    },
                );
                why
            }
        };
        // Told to stop for a reason while it was ending another way: the reason it was given stands.
        let why = (*lock(&st.why)).unwrap_or(why);
        lock(&self.streams).remove(&st.id);
        lock(&st.queued).closing = true;
        self.shared.say(Event::Closed { stream: st.id, why });
    }

    /// Reads frames off a stream and hands each to the app, whole and in order, until the stream ends.
    async fn read_frames(&self, st: &Stream, recv: &mut RecvStream) -> ReadEnd {
        loop {
            let mut head = [0u8; 4];
            match recv.read_exact(&mut head).await {
                Ok(()) => {}
                // Ended between two frames: closed.
                Err(ReadExactError::FinishedEarly(0)) => return ReadEnd::Ended,
                Err(ReadExactError::FinishedEarly(_)) => return ReadEnd::Broken,
                Err(ReadExactError::ReadError(e)) => return ReadEnd::of(e),
            }
            let len = u32::from_be_bytes(head) as usize;
            if len > MAX_FRAME {
                return ReadEnd::Broken;
            }
            // Room for it in what the app has not yet taken, of this stream's and of the node's, before a byte of
            // it is read: while there is none, nothing is read, and QUIC holds the other node back. If the other
            // end gives the stream up meanwhile, that is seen without reading.
            let held = {
                let room = self.hold(&st.credit, len + FRAME_COST);
                tokio::pin!(room);
                tokio::select! {
                    held = &mut room => held,
                    reset = recv.received_reset() => match reset {
                        Ok(Some(_)) => return ReadEnd::Ended,
                        // It ended the stream after this frame: the frame is still to be read.
                        Ok(None) => room.await,
                        Err(_) => return ReadEnd::Lost,
                    },
                }
            };
            let by = Instant::now() + FRAME_GRACE + Duration::from_secs((len / FRAME_SLOWEST) as u64);
            // The event the frame is handed over in, filled as the bytes come: never room for more than the next
            // step of a length the other node only said.
            let mut bytes = Event::frame_header(st.id, len.min(READ_STEP));
            while bytes.len() - FRAME_AT < len {
                let at = bytes.len();
                bytes.resize(at + (len - (at - FRAME_AT)).min(READ_STEP), 0);
                match timeout_at(by, recv.read_exact(&mut bytes[at..])).await {
                    Ok(Ok(())) => {}
                    Ok(Err(ReadExactError::ReadError(e))) => return ReadEnd::of(e),
                    // Ended inside a frame, or left it half-sent.
                    Ok(Err(ReadExactError::FinishedEarly(_))) | Err(_) => return ReadEnd::Broken,
                }
            }
            held.keep();
            self.shared.say(Event::Frame { bytes });
        }
    }

    /// Writes a stream's queued frames, in order, until it is closed here or cannot be written to.
    async fn write_frames(&self, st: &Stream, send: &mut SendStream, queue: &mut mpsc::UnboundedReceiver<Out>) -> WriteEnd {
        let mut written = 0u64;
        let mut said = 0u64;
        loop {
            let Some(next) = queue.recv().await else { return WriteEnd::Lost };
            match next {
                Out::Finish => {
                    if written != said {
                        self.shared.say(Event::Sent { stream: st.id, frames: written });
                    }
                    return WriteEnd::Finished;
                }
                Out::Frame(bytes) => {
                    let writing = send.write_all(&bytes);
                    tokio::pin!(writing);
                    // Frames written and not yet said to be are said before this one is waited on for long: the other
                    // end may not be reading, and what did go must not seem stuck behind what has not.
                    let wrote = if written != said {
                        tokio::select! {
                            biased;
                            wrote = &mut writing => wrote,
                            _ = tokio::time::sleep(SAY_SENT_WITHIN) => {
                                said = written;
                                self.shared.say(Event::Sent { stream: st.id, frames: written });
                                writing.await
                            }
                        }
                    } else {
                        writing.await
                    };
                    if let Err(e) = wrote {
                        return match e {
                            WriteError::Stopped(_) => WriteEnd::StoppedByThem,
                            _ => WriteEnd::Lost,
                        };
                    }
                    {
                        let mut queued = lock(&st.queued);
                        queued.bytes = queued.bytes.saturating_sub(bytes.len());
                        queued.frames = queued.frames.saturating_sub(1);
                    }
                    written += 1;
                    if queue.is_empty() || written - said >= SAY_SENT_EVERY {
                        said = written;
                        self.shared.say(Event::Sent { stream: st.id, frames: written });
                    }
                }
            }
        }
    }

    /// Sets `cost` aside for a frame about to be read: of the stream's window, then of the node's budget. Waits where
    /// there is not that much; given back by itself if the frame never reaches the app.
    async fn hold<'a>(&'a self, credit: &'a Arc<Credit>, cost: usize) -> Held<'a> {
        if let Ok(permit) = credit.window.acquire_many(cost as u32).await {
            permit.forget();
        }
        if let Ok(permit) = self.budget.acquire_many(cost as u32).await {
            permit.forget();
        }
        *lock(&credit.held) += cost;
        Held { run: self, credit, cost }
    }

    /// Lets go of `cost` that was set aside for a stream, or of as much of it as is still set aside.
    fn give_back(&self, credit: &Credit, cost: usize) {
        let given = {
            let mut held = lock(&credit.held);
            let given = cost.min(*held);
            *held -= given;
            given
        };
        if given > 0 {
            credit.window.add_permits(given);
            self.budget.add_permits(given);
        }
    }

    /// Who is allowed has changed: a stream the other node opened on a channel it may no longer have is closed, and
    /// so is the link of a node that may no longer link (unless this node has a stream of its own on it).
    fn admission_changed(&self) {
        let admission = self.shared.admission.read().unwrap_or_else(|p| p.into_inner());
        for st in lock(&self.streams).values() {
            if st.incoming && !admission.permits(&st.peer, st.channel) {
                st.stop_for(Closed::NotAllowed);
            }
        }
        for (peer, links) in lock(&self.links).iter() {
            if !admission.admits(peer) {
                for link in links.iter().filter(|l| l.incoming && l.ours.load(Ordering::Relaxed) == 0) {
                    link.end_with(code::NOT_ALLOWED, Closed::NotAllowed);
                }
            }
        }
    }

    /// `disallow`: every link with the node is closed, and every stream with it.
    fn let_go(&self, peer: &EndpointId) {
        for link in lock(&self.links).get(peer).into_iter().flatten() {
            link.end_with(code::NOT_ALLOWED, Closed::NotAllowed);
        }
    }

    /// Tells the app where this node is, whenever that changes and no more than once a second.
    async fn tell_whereabouts(self: Arc<Self>) {
        let mut addr = self.ep.watch_addr();
        let mut told: Option<(Option<String>, Vec<String>)> = None;
        let mut told_at: Option<Instant> = None;
        loop {
            let now = self.whereabouts(&addr.get());
            let news = match &told {
                Some(told) => *told != now,
                // Nothing to say is not said first.
                None => now.0.is_some() || !now.1.is_empty(),
            };
            if news {
                let wait = told_at.map(|at| (at + WHEREABOUTS_EVERY).saturating_duration_since(Instant::now())).unwrap_or_default();
                if !wait.is_zero() {
                    tokio::select! {
                        _ = self.stop.cancelled() => return,
                        _ = tokio::time::sleep(wait) => continue,
                    }
                }
                self.shared.say(Event::Whereabouts { helper: now.0.clone(), addresses: now.1.clone() });
                told = Some(now);
                told_at = Some(Instant::now());
            }
            tokio::select! {
                _ = self.stop.cancelled() => return,
                changed = addr.updated() => if changed.is_err() { return },
            }
        }
    }

    /// The link helper this node is on, as the app wrote it, and the addresses worth telling: the most useful
    /// first, and no more than the app keeps.
    fn whereabouts(&self, addr: &EndpointAddr) -> (Option<String>, Vec<String>) {
        let helper = addr.relay_urls().find_map(|url| self.helpers.iter().find(|(own, _)| own == url).map(|(_, written)| written.clone()));
        let mut addrs: Vec<(u8, SocketAddr)> = addr
            .ip_addrs()
            .filter_map(|a| Some((rank(&a.ip().to_canonical())?, SocketAddr::new(a.ip().to_canonical(), a.port()))))
            .filter(|(_, a)| a.port() != 0)
            .collect();
        addrs.sort();
        addrs.dedup();
        (helper, addrs.into_iter().take(MAX_ADDRESSES).map(|(_, a)| a.to_string()).collect())
    }
}

/// What was set aside for a frame being read. Kept once the frame is on its way to the app (which gives it back as
/// it takes the frame); given back here if the read ends before that.
struct Held<'a> {
    run: &'a Run,
    credit: &'a Credit,
    cost: usize,
}

impl Held<'_> {
    fn keep(self) {
        std::mem::forget(self);
    }
}

impl Drop for Held<'_> {
    fn drop(&mut self) {
        self.run.give_back(self.credit, self.cost);
    }
}

enum ReadEnd {
    /// The other end closed the stream (its end came between two frames, or it reset it).
    Ended,
    /// What came was no frame.
    Broken,
    Lost,
}

impl ReadEnd {
    fn of(e: ReadError) -> ReadEnd {
        match e {
            ReadError::Reset(_) => ReadEnd::Ended,
            _ => ReadEnd::Lost,
        }
    }
}

enum WriteEnd {
    /// Closed here, and everything before it written.
    Finished,
    /// The other end stopped reading: it closed the stream.
    StoppedByThem,
    Lost,
}

/// Gives up both halves of a stream at once, saying why.
fn turn_back(send: &mut SendStream, recv: &mut RecvStream, code: u32) {
    let _ = send.reset(VarInt::from_u32(code));
    let _ = recv.stop(VarInt::from_u32(code));
}

/// How a link's path stands: the one in use, or failing that the best there is.
fn standing(paths: &PathList<'_>) -> Option<(PathKind, Option<u32>)> {
    let path = paths.iter().find(|p| p.is_selected()).or_else(|| paths.iter().find(|p| p.is_ip())).or_else(|| paths.iter().find(|p| p.is_relay()))?;
    let kind = if path.is_ip() {
        PathKind::Direct
    } else if path.is_relay() {
        PathKind::Helper
    } else {
        return None;
    };
    let rtt = path.rtt();
    Some((kind, (!rtt.is_zero()).then(|| (rtt.as_micros().div_ceil(1000)).min(u32::MAX as u128 - 1) as u32)))
}

/// Whether a round trip is near enough to the one last said that saying it again would be noise.
fn close_enough(before: Option<u32>, now: Option<u32>) -> bool {
    match (before, now) {
        (Some(before), Some(now)) => before.abs_diff(now) <= (before / 4).max(10),
        (None, None) => true,
        _ => false,
    }
}

/// How useful an address of this node's is to another: public before private, loopback last (iroh names it only
/// where there is no other), and never one that means nothing off this device.
fn rank(ip: &IpAddr) -> Option<u8> {
    match ip {
        IpAddr::V4(v4) => {
            if v4.is_unspecified() || v4.is_link_local() || v4.is_multicast() || v4.is_broadcast() {
                None
            } else if v4.is_loopback() {
                Some(4)
            } else if v4.is_private() || (v4.octets()[0] == 100 && v4.octets()[1] & 0xc0 == 64) {
                Some(2)
            } else {
                Some(0)
            }
        }
        IpAddr::V6(v6) => {
            if v6.is_unspecified() || v6.is_unicast_link_local() || v6.is_multicast() {
                None
            } else if v6.is_loopback() {
                Some(4)
            } else if v6.is_unique_local() {
                Some(3)
            } else {
                Some(1)
            }
        }
    }
}

/// Why a link ended, as `open` says it.
fn why_lost(e: &ConnectionError) -> (OpenError, String) {
    match e {
        ConnectionError::ApplicationClosed(closed) if closed.error_code == VarInt::from_u32(code::NOT_ALLOWED) => {
            (OpenError::TurnedAway, "It has not allowed this device.".into())
        }
        // Refused before a handshake (it came through a link helper, which said who was calling), or closed on in
        // the middle of one, where QUIC lets no reason of the app's own be given.
        ConnectionError::ConnectionClosed(closed)
            if closed.error_code == TransportErrorCode::CONNECTION_REFUSED || closed.error_code == TransportErrorCode::APPLICATION_ERROR =>
        {
            (OpenError::TurnedAway, "It has not allowed this device.".into())
        }
        ConnectionError::ApplicationClosed(closed) if closed.error_code == VarInt::from_u32(code::BUSY) => {
            (OpenError::Unreachable, "It has all the links it takes.".into())
        }
        ConnectionError::TimedOut => (OpenError::Unreachable, "It did not answer.".into()),
        _ => (OpenError::Unreachable, "The link was lost.".into()),
    }
}

/// Why no link could be made, as `open` says it.
fn why_no_link(e: &ConnectError) -> (OpenError, String) {
    match e {
        ConnectError::Connect { source: ConnectWithOptsError::NoAddress { .. }, .. } => {
            (OpenError::Unreachable, "Nothing is known of where it is.".into())
        }
        ConnectError::Connect { source: ConnectWithOptsError::SelfConnect { .. }, .. } => {
            (OpenError::BadRequest, "A node does not link with itself.".into())
        }
        ConnectError::Connecting { source: ConnectingError::ConnectionError { source, .. }, .. } => why_lost(source),
        ConnectError::Connection { source, .. } => why_lost(source),
        _ => (OpenError::Unreachable, "It could not be reached.".into()),
    }
}
