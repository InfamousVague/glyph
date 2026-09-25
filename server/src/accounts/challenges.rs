//! The nonces a device signs to sign in by its key: handed out by `login/challenge`, spent by `login/device`.
//!
//! In memory, as AttackFM keeps them: a challenge lost to a restart only means the device asks for another. One is
//! handed out whether or not the handle has an account - against account -1, which no signature can match - so asking
//! says nothing about which handles exist; and the map is pruned of expired ones each time one is handed out, which
//! the sign-in limits keep from growing past what a minute of attempts can add.

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use rand::RngCore;
use std::collections::HashMap;
use std::sync::Mutex;

/// A device-login challenge is good for two minutes.
const CHALLENGE_TTL_SECS: i64 = 120;

/// The account a challenge was handed out for when the handle has none: no row has it, so no device key matches.
pub const NO_ACCOUNT: i64 = -1;

/// Outstanding device-login challenges: nonce -> (account id, issued at, unix seconds).
#[derive(Default)]
pub struct Challenges {
    held: Mutex<HashMap<String, (i64, i64)>>,
}

impl Challenges {
    /// A fresh nonce for `account`, good until `CHALLENGE_TTL_SECS` after `now`: 24 random bytes, base64url.
    pub fn issue(&self, account: i64, now: i64) -> String {
        let mut bytes = [0u8; 24];
        rand::thread_rng().fill_bytes(&mut bytes);
        let nonce = URL_SAFE_NO_PAD.encode(bytes);
        if let Ok(mut held) = self.held.lock() {
            held.retain(|_, (_, issued)| now - *issued < CHALLENGE_TTL_SECS);
            held.insert(nonce.clone(), (account, now));
        }
        nonce
    }

    /// Spends `nonce`, whether or not what follows holds, and answers the account it was handed out for if it is
    /// still current at `now`. A nonce is good once.
    pub fn take(&self, nonce: &str, now: i64) -> Option<i64> {
        let claimed = self.held.lock().ok().and_then(|mut held| held.remove(nonce));
        claimed.filter(|(_, issued)| now - issued < CHALLENGE_TTL_SECS).map(|(account, _)| account)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_challenge_is_good_once_for_the_account_it_was_handed_out_for() {
        let challenges = Challenges::default();
        let nonce = challenges.issue(7, 1_000);
        assert_eq!(nonce.len(), 32, "24 bytes, base64url");
        assert_ne!(challenges.issue(7, 1_000), nonce, "each is fresh");
        assert_eq!(challenges.take(&nonce, 1_001), Some(7));
        assert_eq!(challenges.take(&nonce, 1_002), None, "spent");
        assert_eq!(challenges.take("never-handed-out", 1_002), None);
    }

    #[test]
    fn a_challenge_lapses_after_two_minutes_and_is_spent_by_the_late_attempt_too() {
        let challenges = Challenges::default();
        let nonce = challenges.issue(7, 1_000);
        assert_eq!(challenges.take(&nonce, 1_000 + CHALLENGE_TTL_SECS), None, "two minutes on, it has lapsed");
        let again = challenges.issue(7, 2_000);
        assert_eq!(challenges.take(&again, 2_000 + CHALLENGE_TTL_SECS - 1), Some(7), "a second inside is still good");
    }

    #[test]
    fn handing_one_out_forgets_the_ones_that_have_lapsed() {
        let challenges = Challenges::default();
        challenges.issue(7, 1_000);
        challenges.issue(8, 1_050);
        challenges.issue(9, 1_000 + CHALLENGE_TTL_SECS);
        assert_eq!(challenges.held.lock().unwrap().len(), 2, "the first had lapsed; the second had not");
    }
}
