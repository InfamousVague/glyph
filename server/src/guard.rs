//! Who may ask, and how often: the address a request really came from, and the token buckets every limit in the
//! service spends from.
//!
//! The box behind this service is not Glyph's. It serves AttackFM, its review server, the registry and PrettyCardboard,
//! so each limit here is as much for the neighbours as for Glyph: sign-in per address and per handle (accounts.rs),
//! share reads by address (shares.rs), Notion sign-in (notion.rs), the old format route (format.rs), and the frames of
//! each live socket (live.rs). The service binds to loopback, so Caddy is the only door, and the address a limit counts
//! is the one Caddy says it accepted.

use axum::http::HeaderMap;
use std::collections::HashMap;
use std::net::IpAddr;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// The address a request really came from.
///
/// The service binds to 127.0.0.1, so every peer it sees is Caddy. Caddy's
/// `reverse_proxy` sets `X-Forwarded-For` to the client it accepted, and by
/// default REPLACES whatever the client claimed rather than appending to it,
/// so the header is one address. The LAST entry is taken anyway: if a trusted
/// proxy is ever added in front, the rightmost address is still the one Caddy
/// wrote, and the leftmost is still whatever the client typed.
///
/// The header is only believed from a loopback peer. Anything else reaching
/// this socket is not Caddy, and gets limited by the address it really has.
pub fn client_ip(peer: IpAddr, forwarded_for: Option<&str>) -> IpAddr {
    if !peer.is_loopback() {
        return peer;
    }
    forwarded_for
        .and_then(|h| h.rsplit(',').next())
        .and_then(|last| last.trim().parse().ok())
        .unwrap_or(peer)
}

/// `client_ip` for a request as axum hands it over: the peer the socket saw, and the headers Caddy passed on. Every
/// route that limits by address asks this, so the header it believes is named in one place.
pub fn client_ip_of(peer: IpAddr, headers: &HeaderMap) -> IpAddr {
    client_ip(peer, headers.get("x-forwarded-for").and_then(|v| v.to_str().ok()))
}

/// A token bucket: `capacity` at once, refilled continuously at `per_second`, one token a take.
///
/// The one piece of arithmetic behind every limit here. `RateLimiter` keeps one per client address (or per handle);
/// live sync's relay (src/live.rs) keeps one per socket, for the frames a device sends. They used to be two copies of
/// these lines with different numbers in them, and a refill rule that drifts between two copies is a limit that
/// behaves differently depending on which door a client came in by.
pub struct Bucket {
    tokens: f64,
    at: Instant,
    capacity: f64,
    per_second: f64,
}

impl Bucket {
    /// A full bucket.
    pub fn new(capacity: f64, per_second: f64, now: Instant) -> Self {
        Bucket { tokens: capacity, at: now, capacity, per_second }
    }

    /// Refills for the time since the last take, then spends one token if there is a whole one.
    pub fn take(&mut self, now: Instant) -> bool {
        self.tokens = (self.tokens + now.duration_since(self.at).as_secs_f64() * self.per_second).min(self.capacity);
        self.at = now;
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

/// A token bucket per client address.
///
/// A bucket rather than a fixed window because the phone's traffic is bursty
/// by nature: Matt pauses, the phone sends, he carries on and pauses again. A
/// window resetting on the minute lets forty requests through across its edge;
/// a bucket holds the same average and never more than `capacity` in a row.
///
/// Shared by every request a route answers, so it keeps its own lock: a caller
/// holds a `RateLimiter`, not a `Mutex` around one, and `take` is the whole of
/// what it does with it.
pub struct RateLimiter<K = IpAddr> {
    held: Mutex<Held<K>>,
    capacity: f64,
    per_second: f64,
}

struct Held<K> {
    buckets: HashMap<K, Bucket>,
    last_prune: Instant,
}

/// How long an address may go unseen before its bucket is forgotten. A bucket
/// untouched this long is full again anyway, so forgetting it changes nothing.
const FORGET_AFTER: Duration = Duration::from_secs(600);

/// Keyed by anything, not only an address: sign-in is also limited per handle (src/accounts.rs), so a guesser
/// spreading attempts across many addresses still meets one bucket per account.
impl<K: Eq + std::hash::Hash> RateLimiter<K> {
    pub fn new(per_minute: u32, now: Instant) -> Self {
        Self {
            held: Mutex::new(Held { buckets: HashMap::new(), last_prune: now }),
            capacity: f64::from(per_minute),
            per_second: f64::from(per_minute) / 60.0,
        }
    }

    /// Spend one request for `key`, if it has one left.
    ///
    /// A poisoned lock REFUSES. Nothing below can panic while holding it, so
    /// this is a policy for a case that should not arise, and it is the one each
    /// caller wrote for itself (`lock().map(..).unwrap_or(false)`) before the
    /// lock moved in here: a limiter that cannot count lets nobody through, which
    /// for sign-in is the side a password guesser does not want it to fail on.
    /// store.rs and live.rs carry on through a poisoned lock instead; theirs
    /// guard data, and this guards a door.
    pub fn take(&self, key: K, now: Instant) -> bool {
        let Ok(mut held) = self.held.lock() else { return false };
        if now.duration_since(held.last_prune) > FORGET_AFTER {
            held.buckets.retain(|_, b| now.duration_since(b.at) < FORGET_AFTER);
            held.last_prune = now;
        }
        let (capacity, per_second) = (self.capacity, self.per_second);
        held.buckets.entry(key).or_insert_with(|| Bucket::new(capacity, per_second, now)).take(now)
    }

    #[cfg(test)]
    fn tracked(&self) -> usize {
        self.held.lock().map(|held| held.buckets.len()).unwrap_or(0)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trusts_forwarded_for_only_from_caddy() {
        let caddy: IpAddr = "127.0.0.1".parse().unwrap();
        let phone: IpAddr = "203.0.113.9".parse().unwrap();
        assert_eq!(client_ip(caddy, Some("203.0.113.9")), phone);
        assert_eq!(client_ip(caddy, Some("198.51.100.1, 203.0.113.9")), phone, "the rightmost is the one Caddy wrote");
        assert_eq!(client_ip(caddy, None), caddy);
        assert_eq!(client_ip(caddy, Some("not an address")), caddy);
        let stranger: IpAddr = "198.51.100.7".parse().unwrap();
        assert_eq!(client_ip(stranger, Some("203.0.113.9")), stranger, "a non-loopback peer cannot claim an address");
    }

    #[test]
    fn client_ip_of_reads_the_forwarded_for_header_caddy_sets() {
        let caddy: IpAddr = "127.0.0.1".parse().unwrap();
        let mut headers = HeaderMap::new();
        assert_eq!(client_ip_of(caddy, &headers), caddy);
        headers.insert("x-forwarded-for", "198.51.100.1, 203.0.113.9".parse().unwrap());
        assert_eq!(client_ip_of(caddy, &headers), "203.0.113.9".parse::<IpAddr>().unwrap());
        let stranger: IpAddr = "198.51.100.7".parse().unwrap();
        assert_eq!(client_ip_of(stranger, &headers), stranger);
    }

    #[test]
    fn a_bucket_spends_its_burst_then_refills_at_its_rate_and_never_past_full() {
        // The relay's numbers (src/live.rs): 200 at once, 100 a second.
        let start = Instant::now();
        let mut bucket = Bucket::new(200.0, 100.0, start);
        for i in 0..200 {
            assert!(bucket.take(start), "frame {i} of the burst");
        }
        assert!(!bucket.take(start), "the burst is spent");
        assert!(!bucket.take(start + Duration::from_millis(5)), "five milliseconds buys half a frame");
        // Twenty more buy two, on top of the half: two frames, and not a third.
        let soon = start + Duration::from_millis(25);
        assert!(bucket.take(soon) && bucket.take(soon));
        assert!(!bucket.take(soon));
        // An hour idle fills it to 200, not to 360,000.
        let later = start + Duration::from_secs(3600);
        for _ in 0..200 {
            assert!(bucket.take(later));
        }
        assert!(!bucket.take(later));
    }

    #[test]
    fn allows_a_burst_of_twenty_then_refuses_until_it_refills() {
        let start = Instant::now();
        let ip: IpAddr = "203.0.113.9".parse().unwrap();
        let limiter = RateLimiter::<IpAddr>::new(20, start);
        for i in 0..20 {
            assert!(limiter.take(ip, start), "request {i} of the burst");
        }
        assert!(!limiter.take(ip, start), "the twenty-first in the same instant");
        assert!(!limiter.take(ip, start + Duration::from_secs(2)), "two seconds buys less than one");
        assert!(limiter.take(ip, start + Duration::from_secs(3)), "three seconds buys exactly one");
        assert!(!limiter.take(ip, start + Duration::from_secs(3)));

        let other: IpAddr = "198.51.100.1".parse().unwrap();
        assert!(limiter.take(other, start), "one address's burst is not another's");
    }

    #[test]
    fn forgets_addresses_it_has_not_seen_for_ten_minutes() {
        let start = Instant::now();
        let limiter = RateLimiter::<IpAddr>::new(20, start);
        limiter.take("203.0.113.9".parse().unwrap(), start);
        limiter.take("198.51.100.1".parse().unwrap(), start + Duration::from_secs(700));
        assert_eq!(limiter.tracked(), 1);
    }
}
