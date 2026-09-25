//! The rest the format route gives the model after a call that could not finish.
//!
//! Only `/glyph/api/format` asks the model anything, so this lives with it rather than with the service's shared
//! limits in guard.rs: a rate limit is about how often a client may ask, and this is about whether the model is worth
//! asking at all.

use std::time::{Duration, Instant};

/// Stops calling the model for a while after a call that could not finish.
///
/// MEASURED on the box (2026-09-12, qwen3.5:9b, 198-word note): once a call is
/// admitted, generating its 263 tokens of annotations took 57 to 64 seconds.
/// The whole budget is 45. So on a CPU that busy an admitted call does not
/// produce a late answer - it produces NO answer, after holding AttackFM's only
/// slot until the budget runs out and the call is cancelled. The admission gate
/// cannot see that coming; it only knows the call was admitted.
///
/// So one overrun opens this, and while it is open the endpoint answers 503 at
/// once without asking Ollama anything. The worst a phone can then cost
/// AttackFM is one wasted slot-hold per cooldown, however long Matt dictates.
/// A refusal at the admission gate does NOT open it: that call never ran, so
/// it cost nothing and says nothing about whether the next one could finish.
/// When the box is quiet enough - or the model is changed for one that fits -
/// the first call after the cooldown succeeds and nothing stays open.
pub struct Breaker {
    open_until: Option<Instant>,
    cooldown: Duration,
}

impl Breaker {
    pub fn new(cooldown: Duration) -> Self {
        Self { open_until: None, cooldown }
    }

    pub fn is_open(&self, now: Instant) -> bool {
        self.open_until.is_some_and(|until| now < until)
    }

    /// An admitted call ran out of budget.
    pub fn overran(&mut self, now: Instant) {
        self.open_until = Some(now + self.cooldown);
    }

    /// How long until the model is asked again, for the error message.
    pub fn remaining(&self, now: Instant) -> Duration {
        self.open_until.map(|until| until.saturating_duration_since(now)).unwrap_or_default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_breaker_stays_shut_until_an_overrun_and_reopens_after_the_cooldown() {
        let start = Instant::now();
        let mut breaker = Breaker::new(Duration::from_secs(600));
        assert!(!breaker.is_open(start), "a fresh service asks the model");
        breaker.overran(start);
        assert!(breaker.is_open(start + Duration::from_secs(599)));
        assert_eq!(breaker.remaining(start + Duration::from_secs(100)), Duration::from_secs(500));
        assert!(!breaker.is_open(start + Duration::from_secs(600)), "and asks again after the cooldown");
    }
}
