//! Nodes in one process, linked over this machine's own loopback and through a link helper run inside the test, by
//! the same calls the C interface makes. `cargo test` in native/p2p runs them; the three that only measure what an
//! idle node costs are run by name (`cargo test cost -- --ignored --nocapture`).

use std::{
    collections::VecDeque,
    net::{Ipv4Addr, SocketAddr},
    time::Duration,
};

use iroh::{Endpoint, EndpointAddr, EndpointId, SecretKey, TransportAddr, endpoint::presets};
use tokio::{runtime::Handle, sync::mpsc, time::timeout};

use crate::{
    node::{ALPN, FRAME_COST, LINK_IDLE, NODE_BUDGET, Node, SEND_QUEUE_BYTES, STREAM_COST, STREAMS_PER_LINK, SendError, node_id},
    wire::{Channels, Closed, Config, Event, Hint, MAX_FRAME, OpenError, PathKind, hex},
};

/// How long anything is waited for before the test says it never came. Long: other builds share this machine.
const PATIENCE: Duration = Duration::from_secs(30);

/// A node and what it has said, as the app's side holds one: it takes each frame it is handed, and says when it
/// has handled a stream's end.
struct Dev {
    node: Node,
    said: mpsc::UnboundedReceiver<Event>,
    kept: VecDeque<Event>,
    secret: [u8; 32],
    id: [u8; 32],
    /// Whether it takes frames as it is handed them. A test turns it off to stand for an app that has stopped.
    takes: bool,
}

impl Dev {
    fn new(n: u8) -> Dev {
        let (tx, said) = mpsc::unbounded_channel();
        let node = Node::new(&Handle::current(), move |event| {
            let _ = tx.send(event);
        });
        let secret = [n; 32];
        Dev { node, said, kept: VecDeque::new(), secret, id: node_id(&secret), takes: true }
    }

    fn config(&self) -> Config {
        Config { secret: self.secret, helpers: vec![], helpers_only: false }
    }

    /// The next event `want` is true of, whatever else came before it (which is kept, in order, for later).
    async fn next(&mut self, what: &str, mut want: impl FnMut(&Event) -> bool) -> Event {
        if let Some(at) = self.kept.iter().position(&mut want) {
            return self.kept.remove(at).expect("it is there");
        }
        let found = timeout(PATIENCE, async {
            loop {
                let event = self.said.recv().await.expect("the node's events ended");
                if want(&event) {
                    return event;
                }
                self.kept.push_back(event);
            }
        })
        .await;
        found.unwrap_or_else(|_| panic!("{} never came. Kept: {:?}", what, self.kept.iter().map(brief).collect::<Vec<_>>()))
    }

    /// Whether an event `want` is true of comes within `within`.
    async fn comes(&mut self, within: Duration, mut want: impl FnMut(&Event) -> bool) -> bool {
        if self.kept.iter().any(&mut want) {
            return true;
        }
        timeout(within, async {
            loop {
                let event = self.said.recv().await.expect("the node's events ended");
                let found = want(&event);
                self.kept.push_back(event);
                if found {
                    return;
                }
            }
        })
        .await
        .is_ok()
    }

    async fn up(&mut self) {
        self.node.start(self.config());
        self.came_up().await;
    }

    async fn came_up(&mut self) {
        let id = self.id;
        match self.next("up", |e| matches!(e, Event::Up { .. } | Event::Down { .. })).await {
            Event::Up { node } => assert_eq!(node, id, "the node id is the one its secret makes"),
            other => panic!("it did not come up: {other:?}"),
        }
    }

    async fn off(&mut self) {
        self.node.stop();
        self.next("off", |e| matches!(e, Event::Off)).await;
    }

    /// Where it next says it is.
    async fn whereabouts(&mut self) -> (Option<String>, Vec<String>) {
        match self.next("whereabouts", |e| matches!(e, Event::Whereabouts { .. })).await {
            Event::Whereabouts { helper, addresses } => (helper, addresses),
            _ => unreachable!(),
        }
    }

    /// A hint that says only its loopback address: the port it is bound on, from where it says it is.
    async fn here(&mut self) -> Hint {
        let (_, addresses) = self.whereabouts().await;
        let port = addresses
            .iter()
            .filter_map(|a| a.parse::<SocketAddr>().ok())
            .find(|a| a.is_ipv4())
            .map(|a| a.port())
            .expect("an IPv4 address of its own");
        Hint { helper: None, addresses: vec![format!("127.0.0.1:{port}")] }
    }

    async fn open(&mut self, request: u32, to: [u8; 32], channel: u8, hint: &Hint) -> Result<u64, (OpenError, String)> {
        self.open_within(request, to, channel, hint, Duration::from_secs(10)).await
    }

    async fn open_within(&mut self, request: u32, to: [u8; 32], channel: u8, hint: &Hint, wait: Duration) -> Result<u64, (OpenError, String)> {
        self.node.open(request, to, channel, wait, hint.clone());
        match self
            .next("an answer to open", |e| matches!(e, Event::Opened { request: r, .. } | Event::OpenFailed { request: r, .. } if *r == request))
            .await
        {
            Event::Opened { stream, .. } => Ok(stream),
            Event::OpenFailed { why, message, .. } => {
                // Shown only where the test fails: why an open that should have gone another way went this one.
                eprintln!("open {request} failed: {why:?}, {message}");
                Err((why, message))
            }
            _ => unreachable!(),
        }
    }

    async fn incoming(&mut self) -> (u64, [u8; 32], u8) {
        match self.next("an incoming stream", |e| matches!(e, Event::Incoming { .. })).await {
            Event::Incoming { stream, node, channel } => (stream, node, channel),
            _ => unreachable!(),
        }
    }

    /// The next frame on `stream`, taken as the app takes it.
    async fn frame(&mut self, stream: u64) -> Vec<u8> {
        let event = self.next("a frame", |e| e.as_frame().is_some_and(|(s, _)| s == stream)).await;
        let frame = event.as_frame().expect("a frame").1.to_vec();
        if self.takes {
            self.node.taken(stream, 1, frame.len() as u32);
        }
        frame
    }

    /// Why `stream` closed; its end is then handled, as the app does.
    async fn closed(&mut self, stream: u64) -> Closed {
        match self.next("a stream's end", |e| matches!(e, Event::Closed { stream: s, .. } if *s == stream)).await {
            Event::Closed { why, .. } => {
                self.node.done(stream);
                why
            }
            _ => unreachable!(),
        }
    }

    /// Waits until `frames` frames of `stream` have been written.
    async fn sent(&mut self, stream: u64, frames: u64) {
        self.next("word of what was sent", |e| matches!(e, Event::Sent { stream: s, frames: n } if *s == stream && *n >= frames)).await;
    }

    async fn path(&mut self, of: [u8; 32], kind: PathKind) -> Option<u32> {
        match self.next("a path", |e| matches!(e, Event::Path { node, kind: k, .. } if *node == of && *k == kind)).await {
            Event::Path { rtt_ms, .. } => rtt_ms,
            _ => unreachable!(),
        }
    }

    /// The budget is whole again: nothing read is still counted.
    async fn budget_is_whole(&self) {
        for _ in 0..200 {
            if self.node.budget_free() == Some(NODE_BUDGET) {
                return;
            }
            tokio::time::sleep(Duration::from_millis(25)).await;
        }
        panic!("the budget is not whole: {:?} of {NODE_BUDGET}", self.node.budget_free());
    }
}

/// A stopped node's port can be bound again: at once, or within the moment the system takes to let a socket go.
async fn port_is_free(port: u16) -> std::io::Result<()> {
    let mut tries = 0;
    loop {
        match std::net::UdpSocket::bind((Ipv4Addr::UNSPECIFIED, port)) {
            Ok(_) => return Ok(()),
            Err(e) if tries >= 100 => return Err(e),
            Err(_) => {
                tries += 1;
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
        }
    }
}

fn brief(event: &Event) -> String {
    match event.as_frame() {
        Some((stream, frame)) => format!("Frame({stream}, {} bytes)", frame.len()),
        None => format!("{event:?}"),
    }
}

fn only(channels: &[u8]) -> Channels {
    Channels::of(channels)
}

/// Two nodes up, the second allowing the first channel 0, and where the second is.
async fn pair(a: u8, b: u8) -> (Dev, Dev, Hint) {
    let (mut one, mut two) = (Dev::new(a), Dev::new(b));
    one.up().await;
    two.up().await;
    two.node.allow(one.id, only(&[0]));
    let hint = two.here().await;
    (one, two, hint)
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn frames_go_both_ways_whole_and_in_order() {
    let (mut a, mut b, hint) = pair(1, 2).await;
    let ours = a.open(1, b.id, 0, &hint).await.expect("a stream");
    let (theirs, from, channel) = b.incoming().await;
    assert_eq!((from, channel), (a.id, 0));

    let big: Vec<u8> = (0..MAX_FRAME).map(|i| (i * 31 % 251) as u8).collect();
    // One way: an empty frame, the longest there is, and a burst of small ones queued all at once.
    a.node.send(ours, b"").unwrap();
    a.node.send(ours, &big).unwrap();
    for i in 0..3000u32 {
        a.node.send(ours, format!("small {i}").as_bytes()).unwrap();
    }
    assert_eq!(b.frame(theirs).await, b"");
    assert!(b.frame(theirs).await == big, "the longest frame arrives as it was sent");
    for i in 0..3000u32 {
        assert_eq!(b.frame(theirs).await, format!("small {i}").as_bytes());
    }
    a.sent(ours, 3002).await;

    // And the other, on the same stream.
    b.node.send(theirs, b"").unwrap();
    b.node.send(theirs, &big).unwrap();
    for i in 0..3000u32 {
        b.node.send(theirs, &i.to_be_bytes()).unwrap();
    }
    assert_eq!(a.frame(ours).await, b"");
    assert!(a.frame(ours).await == big);
    for i in 0..3000u32 {
        assert_eq!(a.frame(ours).await, i.to_be_bytes());
    }
    b.sent(theirs, 3002).await;

    // A frame longer than the longest is not taken at all.
    assert_eq!(a.node.send(ours, &vec![0u8; MAX_FRAME + 1]), Err(SendError::TooLong));

    // Closed by the one that opened it: a last frame first, which the other end still gets; then both are done.
    a.node.send(ours, b"last").unwrap();
    a.node.close(ours);
    a.node.close(ours);
    assert_eq!(a.node.send(ours, b"after"), Err(SendError::NoStream));
    assert_eq!(b.frame(theirs).await, b"last");
    assert_eq!(b.closed(theirs).await, Closed::ByThem);
    assert_eq!(a.closed(ours).await, Closed::ByUs);
    assert_eq!(a.node.send(ours, b"after"), Err(SendError::NoStream));
    assert_eq!(b.node.send(theirs, b"after"), Err(SendError::NoStream));
    a.budget_is_whole().await;
    b.budget_is_whole().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn the_end_that_was_dialled_may_close_too_and_open_streams_of_its_own() {
    let (mut a, mut b, hint) = pair(3, 4).await;
    a.node.allow(b.id, only(&[0]));
    let ours = a.open(1, b.id, 0, &hint).await.expect("a stream");
    let (theirs, ..) = b.incoming().await;
    // The dialled end opens one back with no hint at all: the link that is up is the one used.
    let back = b.open(2, a.id, 0, &Hint::default()).await.expect("a stream back over the same link");
    let (back_here, from, _) = a.incoming().await;
    assert_eq!(from, b.id);
    b.node.send(back, b"over the link you made").unwrap();
    assert_eq!(a.frame(back_here).await, b"over the link you made");

    // The accepting end closes the first: the one that opened it sees the end after what was sent before it.
    b.node.send(theirs, b"then gone").unwrap();
    b.node.close(theirs);
    assert_eq!(a.frame(ours).await, b"then gone");
    assert_eq!(a.closed(ours).await, Closed::ByThem);
    assert_eq!(b.closed(theirs).await, Closed::ByUs);
    // The other stream is untouched by it.
    a.node.send(back_here, b"still here").unwrap();
    assert_eq!(b.frame(back).await, b"still here");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_node_that_was_never_allowed_is_turned_away() {
    let (mut a, mut b, hint) = pair(5, 6).await;
    let mut stranger = Dev::new(7);
    stranger.up().await;
    let (why, _) = stranger.open(1, b.id, 0, &hint).await.expect_err("turned away");
    assert_eq!(why, OpenError::TurnedAway);
    // Turned away again by the same answer, not by a link that half stood.
    let (why, _) = stranger.open(2, b.id, 0, &hint).await.expect_err("turned away again");
    assert_eq!(why, OpenError::TurnedAway);
    // The one that is allowed gets through meanwhile, and nothing of the stranger's ever reached the app.
    let ours = a.open(1, b.id, 0, &hint).await.expect("a stream");
    let (_, from, _) = b.incoming().await;
    assert_eq!(from, a.id);
    assert!(!b.kept.iter().any(|e| matches!(e, Event::Incoming { node, .. } | Event::Path { node, .. } if *node == stranger.id)));
    // Allowed now, the stranger links.
    b.node.allow(stranger.id, only(&[0]));
    stranger.open(3, b.id, 0, &hint).await.expect("a stream, once allowed");
    let (_, from, _) = b.incoming().await;
    assert_eq!(from, stranger.id);
    a.node.close(ours);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_node_allowed_one_channel_is_refused_another() {
    let (mut a, mut b, hint) = pair(8, 9).await;
    let (why, _) = a.open(1, b.id, 1, &hint).await.expect_err("refused");
    assert_eq!(why, OpenError::Refused);
    let ours = a.open(2, b.id, 0, &hint).await.expect("channel 0");
    let (theirs, _, channel) = b.incoming().await;
    assert_eq!(channel, 0);
    assert!(!b.kept.iter().any(|e| matches!(e, Event::Incoming { channel: 1, .. })));

    // Allowed both, then only channel 1: the stream on channel 0 is closed, a new one on channel 1 is taken.
    b.node.allow(a.id, only(&[0, 1]));
    let second = a.open(3, b.id, 1, &hint).await.expect("channel 1, once allowed");
    let (second_there, _, channel) = b.incoming().await;
    assert_eq!(channel, 1);
    b.node.allow(a.id, only(&[1]));
    assert_eq!(b.closed(theirs).await, Closed::NotAllowed);
    assert_eq!(a.closed(ours).await, Closed::ByThem);
    a.node.send(second, b"still allowed").unwrap();
    assert_eq!(b.frame(second_there).await, b"still allowed");
    let (why, _) = a.open(4, b.id, 0, &hint).await.expect_err("channel 0 is no longer allowed");
    assert_eq!(why, OpenError::Refused);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_channel_open_to_all_takes_anyone_and_only_on_that_channel() {
    let (mut host, mut anyone) = (Dev::new(10), Dev::new(11));
    host.up().await;
    anyone.up().await;
    let hint = host.here().await;
    let (why, _) = anyone.open(1, host.id, 1, &hint).await.expect_err("nothing is open yet");
    assert_eq!(why, OpenError::TurnedAway);
    host.node.open_to_all(only(&[1]));
    let (why, _) = anyone.open(2, host.id, 0, &hint).await.expect_err("channel 0 is not open to all");
    assert_eq!(why, OpenError::Refused);
    let ours = anyone.open(3, host.id, 1, &hint).await.expect("the open channel");
    let (theirs, from, channel) = host.incoming().await;
    assert_eq!((from, channel), (anyone.id, 1));
    anyone.node.send(ours, b"hello, whoever you are").unwrap();
    assert_eq!(host.frame(theirs).await, b"hello, whoever you are");
    // No longer open: the stream is closed, and nobody not allowed can come back.
    host.node.open_to_all(Channels::NONE);
    assert_eq!(host.closed(theirs).await, Closed::NotAllowed);
    assert!(matches!(anyone.closed(ours).await, Closed::ByThem | Closed::LinkLost));
    // (Turned away, or refused on the link that is closing under it: which comes first is a matter of moments.)
    let (why, _) = anyone.open(4, host.id, 1, &hint).await.expect_err("closed to all again");
    assert!(matches!(why, OpenError::TurnedAway | OpenError::Refused), "{why:?}");
    anyone.path(host.id, PathKind::None).await;
    let (why, _) = anyone.open(5, host.id, 1, &hint).await.expect_err("closed to all again");
    assert_eq!(why, OpenError::TurnedAway);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn disallow_closes_everything_with_that_node() {
    let (mut a, mut b, hint) = pair(12, 13).await;
    a.node.allow(b.id, only(&[0]));
    let ours = a.open(1, b.id, 0, &hint).await.expect("a stream");
    let (theirs, ..) = b.incoming().await;
    let back = b.open(1, a.id, 0, &Hint::default()).await.expect("a stream back");
    let (back_here, ..) = a.incoming().await;
    b.path(a.id, PathKind::Direct).await;

    b.node.disallow(a.id);
    assert_eq!(b.closed(theirs).await, Closed::NotAllowed);
    assert_eq!(b.closed(back).await, Closed::NotAllowed);
    b.path(a.id, PathKind::None).await;
    assert!(matches!(a.closed(ours).await, Closed::ByThem | Closed::LinkLost));
    assert!(matches!(a.closed(back_here).await, Closed::ByThem | Closed::LinkLost));
    a.path(b.id, PathKind::None).await;
    let (why, _) = a.open(2, b.id, 0, &hint).await.expect_err("no longer allowed");
    assert_eq!(why, OpenError::TurnedAway);
    a.budget_is_whole().await;
    b.budget_is_whole().await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn stop_then_start_is_the_same_node_and_works_again_and_again() {
    let (mut a, mut b, mut hint) = pair(14, 15).await;
    for round in 0..4u32 {
        let ours = a.open(round, b.id, 0, &hint).await.unwrap_or_else(|e| panic!("round {round}: {e:?}"));
        let (theirs, from, _) = b.incoming().await;
        assert_eq!(from, a.id);
        a.node.send(ours, format!("round {round}").as_bytes()).unwrap();
        assert_eq!(b.frame(theirs).await, format!("round {round}").as_bytes());
        let port: u16 = hint.addresses[0].rsplit(':').next().unwrap().parse().unwrap();

        // Stopped: its streams say so, the other end's close, nothing can be sent or opened, and its port is free.
        b.off().await;
        assert_eq!(b.closed(theirs).await, Closed::Stopped);
        b.path(a.id, PathKind::None).await;
        assert!(matches!(a.closed(ours).await, Closed::ByThem | Closed::LinkLost));
        a.path(b.id, PathKind::None).await;
        assert_eq!(b.node.send(theirs, b"into nothing"), Err(SendError::NoStream));
        let (why, _) = b.open(100 + round, a.id, 0, &Hint::default()).await.expect_err("it is not up");
        assert_eq!(why, OpenError::NotUp);
        port_is_free(port).await.unwrap_or_else(|e| panic!("round {round}: the port {port} is still held after the stop: {e}"));
        let (why, _) = a.open_within(200 + round, b.id, 0, &hint, Duration::from_secs(2)).await.expect_err("nobody is there");
        assert_eq!(why, OpenError::Unreachable);

        // Started with the same secret: the same node id (`up` checks it), a new port, and who was allowed is
        // still allowed without being said again.
        b.up().await;
        hint = b.here().await;
    }
    // Started a second time with what it is already up with: nothing changes, and it says it is up.
    b.node.start(b.config());
    b.came_up().await;
    a.open(999, b.id, 0, &hint).await.expect("still the node it was");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn the_path_says_straight_and_none_once_an_idle_link_is_let_go() {
    let (mut a, mut b, hint) = pair(16, 17).await;
    let ours = a.open(1, b.id, 0, &hint).await.expect("a stream");
    let (theirs, ..) = b.incoming().await;
    let rtt = a.path(b.id, PathKind::Direct).await;
    assert!(rtt.is_some_and(|ms| ms < 1000), "a round trip on one machine: {rtt:?}");
    b.path(a.id, PathKind::Direct).await;
    a.node.close(ours);
    assert_eq!(b.closed(theirs).await, Closed::ByThem);
    assert_eq!(a.closed(ours).await, Closed::ByUs);
    // No stream is left on the link: it is let go, and both ends say there is no path.
    assert!(!a.comes(LINK_IDLE / 2, |e| matches!(e, Event::Path { kind: PathKind::None, .. })).await, "the link is kept a while");
    a.path(b.id, PathKind::None).await;
    b.path(a.id, PathKind::None).await;
    // And the next open dials again.
    a.open(2, b.id, 0, &hint).await.expect("a new link");
    a.path(b.id, PathKind::Direct).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_queue_that_overflows_closes_the_stream_and_what_is_not_taken_is_not_read() {
    let (mut a, mut b, hint) = pair(18, 19).await;
    let ours = a.open(1, b.id, 0, &hint).await.expect("a stream");
    let (theirs, ..) = b.incoming().await;
    // The app at the far end stops taking frames. One frame of the most is handed to it; the next waits unread, QUIC
    // holds the sender back, and the sender's queue fills until the stream is closed for it.
    b.takes = false;
    let big = vec![7u8; MAX_FRAME];
    a.node.send(ours, &big).unwrap();
    assert!(b.frame(theirs).await == big);
    let mut queued = 0;
    let overflowed = loop {
        match a.node.send(ours, &big) {
            Ok(()) => queued += 1,
            Err(e) => break e,
        }
        assert!(queued <= 64, "the queue took {queued} frames of the most and never filled");
        tokio::time::sleep(Duration::from_millis(20)).await;
    };
    assert_eq!(overflowed, SendError::Overflow);
    assert!(queued >= SEND_QUEUE_BYTES / (MAX_FRAME + 4), "it held what a queue holds first: {queued}");
    assert_eq!(a.closed(ours).await, Closed::Overflow);
    assert_eq!(a.node.send(ours, b"more"), Err(SendError::NoStream));
    // The far end was handed that one frame and no more, however many were sent at it.
    assert_eq!(b.closed(theirs).await, Closed::ByThem);
    assert!(!b.kept.iter().any(|e| e.as_frame().is_some()), "nothing more was read than the app had room for");
    a.budget_is_whole().await;
    b.budget_is_whole().await;

    // The link is none the worse: a new stream carries frames, and they are counted while they are not taken.
    b.takes = true;
    let ours = a.open(2, b.id, 0, &hint).await.expect("a new stream");
    let (theirs, ..) = b.incoming().await;
    b.takes = false;
    a.node.send(ours, b"counted").unwrap();
    assert_eq!(b.frame(theirs).await, b"counted");
    assert_eq!(b.node.budget_free(), Some(NODE_BUDGET - STREAM_COST - FRAME_COST - 7));
    b.node.taken(theirs, 1, 7);
    assert_eq!(b.node.budget_free(), Some(NODE_BUDGET - STREAM_COST));
    // Saying more was taken than was handed over gives nothing more back.
    b.node.taken(theirs, 1000, 1 << 30);
    assert_eq!(b.node.budget_free(), Some(NODE_BUDGET - STREAM_COST));
}

/// What a test waits on that is not a node's event: in time, or the test says what never came.
async fn soon<T>(what: &str, f: impl Future<Output = T>) -> T {
    timeout(PATIENCE, f).await.unwrap_or_else(|_| panic!("{what} never came"))
}

/// A peer that is not this library: an iroh endpoint that speaks the protocol by hand, to say what a node must not
/// believe.
async fn by_hand(n: u8) -> Endpoint {
    Endpoint::builder(presets::Minimal).secret_key(SecretKey::from_bytes(&[n; 32])).bind().await.expect("an endpoint")
}

fn at(node: [u8; 32], hint: &Hint) -> EndpointAddr {
    EndpointAddr::from_parts(EndpointId::from_bytes(&node).unwrap(), hint.addresses.iter().map(|a| TransportAddr::Ip(a.parse().unwrap())))
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn what_is_no_frame_closes_the_stream_and_nothing_else() {
    let mut b = Dev::new(20);
    b.up().await;
    let hint = b.here().await;
    let peer = by_hand(21).await;
    let peer_id = *peer.id().as_bytes();
    b.node.allow(peer_id, only(&[0]));
    let conn = soon("a link", peer.connect(at(b.id, &hint), ALPN)).await.expect("a link");
    let open = async |channel: u8| {
        let (mut send, mut recv) = soon("a stream", conn.open_bi()).await.unwrap();
        send.write_all(&[channel]).await.unwrap();
        let mut answer = [0u8; 1];
        let answered = soon("an answer to the channel", recv.read_exact(&mut answer)).await.map(|_| answer[0]);
        (send, recv, answered)
    };

    // A length past the most: the stream is closed as broken, and no room was ever made for what it claimed.
    {
        let (mut send, _recv, answered) = open(0).await;
        assert_eq!(answered.unwrap(), 1);
        let (stream, from, _) = b.incoming().await;
        assert_eq!(from, peer_id);
        send.write_all(&(MAX_FRAME as u32 + 1).to_be_bytes()).await.unwrap();
        assert_eq!(b.closed(stream).await, Closed::Broken);
        send.write_all(&u32::MAX.to_be_bytes()).await.ok();
    }

    // A frame cut short by the stream's end.
    {
        let (mut send, _recv, _) = open(0).await;
        let (stream, ..) = b.incoming().await;
        send.write_all(&10u32.to_be_bytes()).await.unwrap();
        send.write_all(b"abc").await.unwrap();
        send.finish().unwrap();
        assert_eq!(b.closed(stream).await, Closed::Broken);
    }

    // A length cut short by the stream's end.
    {
        let (mut send, _recv, _) = open(0).await;
        let (stream, ..) = b.incoming().await;
        send.write_all(&[0, 0]).await.unwrap();
        send.finish().unwrap();
        assert_eq!(b.closed(stream).await, Closed::Broken);
    }

    // A frame of the most, its length said a byte at a time and itself in pieces: it arrives whole. Then a clean end.
    {
        let (mut send, mut recv, _) = open(0).await;
        let (stream, ..) = b.incoming().await;
        let big = vec![5u8; MAX_FRAME];
        for byte in (MAX_FRAME as u32).to_be_bytes() {
            send.write_all(&[byte]).await.unwrap();
        }
        for piece in big.chunks(100_000) {
            send.write_all(piece).await.unwrap();
        }
        assert!(b.frame(stream).await == big);
        send.write_all(&[0, 0, 0, 2, b'o', b'k']).await.unwrap();
        assert_eq!(b.frame(stream).await, b"ok");
        b.node.send(stream, b"and back").unwrap();
        let mut back = [0u8; 12];
        soon("the frame back", recv.read_exact(&mut back)).await.unwrap();
        assert_eq!(&back, b"\0\0\0\x08and back");
        send.finish().unwrap();
        assert_eq!(b.closed(stream).await, Closed::ByThem);
    }

    // A channel it was not allowed: reset, with the code that says so, and the app never hears of it.
    {
        let (_send, _recv, answered) = open(9).await;
        assert!(
            matches!(answered, Err(iroh::endpoint::ReadExactError::ReadError(iroh::endpoint::ReadError::Reset(code))) if code == iroh::endpoint::VarInt::from_u32(2)),
            "{answered:?}"
        );
        assert!(!b.kept.iter().any(|e| matches!(e, Event::Incoming { channel: 9, .. })));
    }

    // More streams at once than a link carries: the next is not let through until one of them has ended. (A peer
    // that holds on to streams holds only its own places.)
    {
        let mut held = Vec::new();
        for _ in 0..STREAMS_PER_LINK {
            let (send, recv, answered) = open(0).await;
            assert_eq!(answered.unwrap(), 1);
            let (stream, ..) = b.incoming().await;
            held.push((send, recv, stream));
        }
        assert!(timeout(Duration::from_millis(500), conn.open_bi()).await.is_err(), "one stream more than a link carries was let through");
        let (send, recv, stream) = held.pop().unwrap();
        drop((send, recv));
        assert_eq!(b.closed(stream).await, Closed::ByThem);
        let (_send, _recv, answered) = open(0).await;
        assert_eq!(answered.unwrap(), 1);
        let (stream, ..) = b.incoming().await;
        // The link goes with all of them on it: each says so.
        conn.close(0u32.into(), b"");
        for stream in held.iter().map(|(_, _, stream)| *stream).chain([stream]) {
            assert_eq!(b.closed(stream).await, Closed::LinkLost);
        }
    }

    // A stranger speaking the same protocol by hand is closed on with the code that says it is not allowed.
    let stranger = by_hand(22).await;
    let turned_away = match soon("the stranger's handshake", stranger.connect(at(b.id, &hint), ALPN)).await {
        Ok(conn) => soon("the stranger's link to be closed", conn.closed()).await,
        Err(e) => panic!("the handshake itself failed: {e:#}"),
    };
    assert!(
        matches!(&turned_away, iroh::endpoint::ConnectionError::ApplicationClosed(c) if c.error_code == iroh::endpoint::VarInt::from_u32(1)),
        "{turned_away:?}"
    );
    // And a protocol of another name is not spoken at all.
    b.node.allow(*stranger.id().as_bytes(), only(&[0]));
    assert!(soon("another protocol's refusal", stranger.connect(at(b.id, &hint), b"ghost/2")).await.is_err());

    soon("the peer's endpoint to close", peer.close()).await;
    soon("the stranger's endpoint to close", stranger.close()).await;
    b.budget_is_whole().await;
}

/// A peer by hand that takes whoever links and answers each stream's channel, until the stream is ended.
fn takes_streams(peer: Endpoint) -> tokio::task::JoinHandle<Vec<iroh::endpoint::Connection>> {
    tokio::spawn(async move {
        let mut links = Vec::new();
        while let Some(incoming) = peer.accept().await {
            let Ok(conn) = incoming.await else { continue };
            links.push(conn.clone());
            tokio::spawn(async move {
                while let Ok((mut send, mut recv)) = conn.accept_bi().await {
                    let mut channel = [0u8; 1];
                    if recv.read_exact(&mut channel).await.is_ok() && send.write_all(&[1]).await.is_ok() {
                        let _ = recv.read_to_end(1 << 20).await;
                        let _ = send.reset(3u32.into());
                    }
                }
            });
            if links.len() == 1 {
                return links;
            }
        }
        links
    })
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_link_that_no_longer_answers_is_let_go_so_the_next_open_dials() {
    let mut a = Dev::new(31);
    a.up().await;
    let key = SecretKey::from_bytes(&[32; 32]);
    let listening = async || {
        let peer = Endpoint::builder(presets::Minimal).secret_key(key.clone()).alpns(vec![ALPN.to_vec()]).bind().await.expect("an endpoint");
        let port = peer.bound_sockets().iter().find(|a| a.is_ipv4()).expect("an IPv4 socket").port();
        (peer, Hint { helper: None, addresses: vec![format!("127.0.0.1:{port}")] })
    };
    let (peer, hint) = listening().await;
    let peer_id = *peer.id().as_bytes();
    let took = takes_streams(peer.clone());
    let ours = a.open(1, peer_id, 0, &hint).await.expect("a stream");
    a.node.close(ours);
    assert_eq!(a.closed(ours).await, Closed::ByUs);
    a.path(peer_id, PathKind::Direct).await;

    // The other device is gone without a word: no close, nothing. (Forgotten, not dropped: a handle that is dropped
    // says goodbye.)
    for link in soon("the peer's link", took).await.unwrap() {
        std::mem::forget(link);
    }
    drop(peer);
    tokio::time::sleep(Duration::from_millis(200)).await;
    // The link still looks up, so the next open tries it; nothing answers; and since it carries nothing else it is let
    // go at once, well before it would have been for being idle or QUIC would have given it up.
    let (why, _) = a.open_within(2, peer_id, 0, &hint, Duration::from_millis(800)).await.expect_err("nobody answers");
    assert_eq!(why, OpenError::Unreachable);
    assert!(
        a.comes(Duration::from_millis(1500), |e| matches!(e, Event::Path { node, kind: PathKind::None, .. } if *node == peer_id)).await,
        "the link that did not answer was kept"
    );
    // The device comes back somewhere else: the open dials there and is answered.
    let (peer, hint) = listening().await;
    let _took = takes_streams(peer.clone());
    a.open(3, peer_id, 0, &hint).await.expect("a stream to where it is now");
    soon("the peer's endpoint to close", peer.close()).await;
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn a_node_dials_only_by_what_it_may_and_says_why_it_cannot() {
    let (mut a, b, _hint) = pair(23, 24).await;
    // Nothing known of where it is: said at once, not after the wait.
    let before = std::time::Instant::now();
    let (why, _) = a.open(1, b.id, 0, &Hint::default()).await.expect_err("nothing to dial by");
    assert_eq!(why, OpenError::Unreachable);
    // A link helper this node was not given is not a server it will talk to, whoever names it: the hint comes to
    // nothing, at once.
    let (why, _) = a
        .open(2, b.id, 0, &Hint { helper: Some("https://helper.someone-else.example".into()), addresses: vec![] })
        .await
        .expect_err("not its helper");
    assert_eq!(why, OpenError::Unreachable);
    // Nor are addresses that are no addresses.
    let nonsense = Hint {
        helper: None,
        addresses: vec!["not an address".into(), "0.0.0.0:5".into(), "127.0.0.1:0".into(), "224.0.0.1:9".into(), "255.255.255.255:9".into()],
    };
    let (why, _) = a.open(3, b.id, 0, &nonsense).await.expect_err("nothing to dial by");
    assert_eq!(why, OpenError::Unreachable);
    assert!(before.elapsed() < Duration::from_secs(5), "three opens with nothing to dial by took {:?}", before.elapsed());
    // Itself.
    let (why, _) = a.open(4, a.id, 0, &Hint::default()).await.expect_err("itself");
    assert_eq!(why, OpenError::BadRequest);
    // An address where nobody is: the wait it was given, and no longer.
    let before = std::time::Instant::now();
    let nobody = Hint { helper: None, addresses: vec!["127.0.0.1:9".into()] };
    let (why, _) = a.open_within(5, b.id, 0, &nobody, Duration::from_millis(700)).await.expect_err("nobody there");
    assert_eq!(why, OpenError::Unreachable);
    assert!(before.elapsed() < Duration::from_secs(4), "an open given 700 ms took {:?}", before.elapsed());
    // A node that was started wrongly says so, and can be started rightly after.
    let mut c = Dev::new(25);
    c.node.start(Config { secret: c.secret, helpers: vec!["http://plain.example".into()], helpers_only: false });
    assert!(matches!(c.next("down", |e| matches!(e, Event::Down { .. })).await, Event::Down { problem } if problem.contains("https://")));
    c.node.start(Config { secret: c.secret, helpers: vec![], helpers_only: true });
    assert!(matches!(c.next("down", |e| matches!(e, Event::Down { .. })).await, Event::Down { .. }));
    c.up().await;
    assert_eq!(hex(&c.id).len(), 64);
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn two_nodes_given_only_a_link_helper_find_each_other() {
    let (map, url, _helper) = iroh::test_utils::run_relay_server().await.expect("a link helper");
    let written = url.to_string().trim_end_matches('/').to_string();
    let (mut a, mut b) = (Dev::new(26), Dev::new(27));
    let config = |d: &Dev| Config { secret: d.secret, helpers: vec![written.clone()], helpers_only: false };
    a.node.start_with(config(&a), map.clone());
    a.came_up().await;
    b.node.start_with(config(&b), map.clone());
    b.came_up().await;
    b.node.allow(a.id, only(&[0]));
    // Where it is: on the helper, said as the app wrote it.
    let there = loop {
        let (helper, _) = b.whereabouts().await;
        if helper.is_some() {
            break helper;
        }
    };
    assert_eq!(there.as_deref(), Some(written.as_str()));

    // Dialled by the helper alone, not one address: the link is made through it.
    let hint = Hint { helper: there.clone(), addresses: vec![] };
    let ours = a.open(1, b.id, 0, &hint).await.expect("a stream through the helper");
    let (theirs, from, _) = b.incoming().await;
    assert_eq!(from, a.id);
    a.node.send(ours, b"found you").unwrap();
    assert_eq!(b.frame(theirs).await, b"found you");
    // Both on one machine, so the two then find the straight path by themselves.
    a.path(b.id, PathKind::Direct).await;
    b.path(a.id, PathKind::Direct).await;

    // A node that is not allowed gets nothing by the helper: refused before any handshake, it learns no address.
    let mut stranger = Dev::new(28);
    stranger.node.start_with(config(&stranger), map.clone());
    stranger.came_up().await;
    let (why, _) = stranger.open(1, b.id, 0, &hint).await.expect_err("refused through the helper, before any handshake");
    assert_eq!(why, OpenError::TurnedAway);
    let learnt = stranger.node.knows_of(b.id).await;
    assert!(learnt.iter().all(|addr| addr.is_relay()), "a node that was turned away learnt an address: {learnt:?}");
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn only_through_link_helpers_keeps_the_path_through_the_helper() {
    let (map, url, _helper) = iroh::test_utils::run_relay_server().await.expect("a link helper");
    let written = url.to_string().trim_end_matches('/').to_string();
    let (mut hidden, mut other) = (Dev::new(29), Dev::new(30));
    hidden.node.start_with(Config { secret: hidden.secret, helpers: vec![written.clone()], helpers_only: true }, map.clone());
    hidden.came_up().await;
    other.node.start_with(Config { secret: other.secret, helpers: vec![written.clone()], helpers_only: false }, map.clone());
    other.came_up().await;
    hidden.node.allow(other.id, only(&[0]));
    other.node.allow(hidden.id, only(&[0]));
    // It says the helper and never an address of its own.
    let (helper, addresses) = loop {
        let said = hidden.whereabouts().await;
        if said.0.is_some() {
            break said;
        }
        assert!(said.1.is_empty());
    };
    assert_eq!(helper.as_deref(), Some(written.as_str()));
    assert!(addresses.is_empty(), "it told its own addresses: {addresses:?}");
    let other_is_at = loop {
        let said = other.whereabouts().await;
        if said.0.is_some() && !said.1.is_empty() {
            break said;
        }
    };

    // Dialled by the other, through the helper: the path is the helper's and stays the helper's.
    let ours = other.open(1, hidden.id, 0, &Hint { helper: helper.clone(), addresses: vec![] }).await.expect("a stream through the helper");
    let (theirs, ..) = hidden.incoming().await;
    other.path(hidden.id, PathKind::Helper).await;
    hidden.path(other.id, PathKind::Helper).await;
    for i in 0..20u8 {
        other.node.send(ours, &[i; 1000]).unwrap();
        assert_eq!(hidden.frame(theirs).await, [i; 1000]);
        hidden.node.send(theirs, &[i]).unwrap();
        assert_eq!(other.frame(ours).await, [i]);
    }
    // And a stream the other way, by the other's addresses as well as its helper: its addresses are not used.
    let back =
        hidden.open(2, other.id, 0, &Hint { helper: other_is_at.0.clone(), addresses: other_is_at.1.clone() }).await.expect("a stream the other way");
    other.incoming().await;
    hidden.node.send(back, b"still through the helper").unwrap();
    tokio::time::sleep(Duration::from_secs(3)).await;
    assert!(!other.comes(Duration::from_millis(100), |e| matches!(e, Event::Path { kind: PathKind::Direct, .. })).await, "a straight path was made");
    assert!(!hidden.comes(Duration::from_millis(100), |e| matches!(e, Event::Path { kind: PathKind::Direct, .. })).await, "a straight path was made");
    // What the other has learnt of where the hidden one is: the helper, and nothing else.
    let known = other.node.knows_of(hidden.id).await;
    assert!(!known.is_empty() && known.iter().all(|addr| addr.is_relay()), "the other learnt an address of the hidden one's own: {known:?}");
}

/// What an idle node costs, measured: run by name, with `cargo test cost -- --ignored --nocapture`. A minute each.
mod cost {
    use super::*;

    async fn counted(dev: &Dev) -> (u64, u64, u64) {
        dev.node.traffic().expect("it is up")
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    #[ignore = "a minute of measuring, not a test"]
    async fn an_idle_node_with_no_links() {
        let mut a = Dev::new(40);
        a.up().await;
        a.whereabouts().await;
        tokio::time::sleep(Duration::from_secs(3)).await;
        let before = counted(&a).await;
        tokio::time::sleep(Duration::from_secs(60)).await;
        let after = counted(&a).await;
        println!(
            "COST no helper, no links, 60 s: sent {} bytes, received {} bytes in {} datagrams",
            after.0 - before.0,
            after.1 - before.1,
            after.2 - before.2
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    #[ignore = "a minute of measuring, not a test"]
    async fn two_linked_idle_nodes() {
        let (mut a, mut b, hint) = pair(41, 42).await;
        let _ours = a.open(1, b.id, 0, &hint).await.expect("a stream");
        b.incoming().await;
        a.path(b.id, PathKind::Direct).await;
        tokio::time::sleep(Duration::from_secs(5)).await;
        let (before_a, before_b) = (counted(&a).await, counted(&b).await);
        tokio::time::sleep(Duration::from_secs(60)).await;
        let (after_a, after_b) = (counted(&a).await, counted(&b).await);
        println!(
            "COST one link, one stream open, nothing said, 60 s: the dialling node sent {} bytes and received {} bytes in {} datagrams; the dialled node sent {} bytes and received {} bytes in {} datagrams",
            after_a.0 - before_a.0,
            after_a.1 - before_a.1,
            after_a.2 - before_a.2,
            after_b.0 - before_b.0,
            after_b.1 - before_b.1,
            after_b.2 - before_b.2
        );
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    #[ignore = "a minute of measuring, not a test"]
    async fn an_idle_node_on_a_link_helper() {
        let (map, url, helper) = iroh::test_utils::run_relay_server().await.expect("a link helper");
        let written = url.to_string().trim_end_matches('/').to_string();
        let mut a = Dev::new(43);
        a.node.start_with(Config { secret: a.secret, helpers: vec![written], helpers_only: false }, map);
        a.came_up().await;
        while a.whereabouts().await.0.is_none() {}
        tokio::time::sleep(Duration::from_secs(5)).await;
        let before = counted(&a).await;
        tokio::time::sleep(Duration::from_secs(60)).await;
        let after = counted(&a).await;
        println!(
            "COST on a link helper, no links, 60 s: QUIC sent {} bytes, received {} bytes in {} datagrams (the connection to the helper itself, a TLS stream, is not in these)",
            after.0 - before.0,
            after.1 - before.1,
            after.2 - before.2
        );
        drop(helper);
    }
}

/// Not a test of anything promised, a measurement of what is not closed (README.md, "What a caller that is turned
/// away can still learn"): how often a caller that reaches this node straight, and is turned away once its handshake
/// has said who it is, has by then been shown another address of this node's. iroh's hole punching answers a caller
/// by itself: the caller names addresses of its own, and this node sends each a small probe, from whichever of its
/// addresses reaches it. Here both are on one machine, so the probe to the caller's network address comes from this
/// node's network address, which the caller (who dialled 127.0.0.1) then knows.
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore = "a measurement, not a test"]
async fn how_often_a_caller_turned_away_learns_an_address() {
    let mut b = Dev::new(60);
    b.up().await;
    let hint = b.here().await;
    let mut learnt = 0;
    let tries = 300u32;
    for n in 0..tries {
        let mut secret = [9u8; 32];
        secret[..4].copy_from_slice(&n.to_be_bytes());
        let caller = Endpoint::builder(presets::Minimal).secret_key(SecretKey::from_bytes(&secret)).bind().await.unwrap();
        if let Ok(conn) = soon("a handshake", caller.connect(at(b.id, &hint), ALPN)).await {
            soon("the close", conn.closed()).await;
        }
        tokio::time::sleep(Duration::from_millis(20)).await;
        let known = caller
            .remote_info(EndpointId::from_bytes(&b.id).unwrap())
            .await
            .map(|i| i.into_addrs().map(|a| a.into_addr()).collect::<Vec<_>>())
            .unwrap_or_default();
        if known.len() > 1 {
            learnt += 1;
            if learnt == 1 {
                println!("COST for example: {known:?}");
            }
        }
        caller.close().await;
    }
    println!("COST {learnt} of {tries} callers that were turned away had been shown another address");
}
