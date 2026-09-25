//! Session tokens: AttackFM's identity token, copied (AttackFM/server/crates/identity), for Glyph accounts.
//!
//! The shape is AttackFM's exactly - a version tag, the claims as JSON, and an Ed25519 signature over both, three
//! base64url fields - and so is the reasoning: not a JWT, so there is no algorithm in the token for anyone to choose,
//! and verification needs only the public key. Only the tag differs, so a token from one service is never taken by
//! the other. The signing key is made on first boot and kept in the database (src/store.rs).

use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use ed25519_dalek::{Signature, Signer, SigningKey, Verifier, VerifyingKey};
use serde::{Deserialize, Serialize};

/// The token version, so the format can change without the service mistaking an
/// old token for a new one. Bumped only on a breaking shape change.
const TOKEN_V: &str = "glyph1";

/// Exactly `N` bytes from unpadded base64url - a key is 32, a signature 64 - or
/// nothing: text that will not decode and bytes of any other length are the same
/// refusal. It does not trim; the callers that forgive surrounding whitespace
/// trim before they ask, and a token's signature is taken exactly as it came.
fn decode_array<const N: usize>(s: &str) -> Option<[u8; N]> {
    URL_SAFE_NO_PAD.decode(s).ok()?.try_into().ok()
}

/// What a verified token asserts: who the bearer is, and for how long.
///
/// Kept minimal on purpose - identity only. Everything an account keeps is
/// found by `sub` in the database, never carried in the token, so a token stays
/// good however the account changes and says nothing about what is in it.
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Claims {
    /// The account's id (`accounts.id`). Stable for the life of the account, and
    /// what every row it keeps is found by.
    pub sub: i64,
    /// The handle at issue time, for display without a round-trip. `sub` - not
    /// this - is identity: a handle is matched without its case, an id exactly.
    pub handle: String,
    /// Issued-at, unix seconds.
    pub iat: i64,
    /// Expiry, unix seconds: a week on (accounts.rs), renewed with `refresh` long
    /// before, so a stolen token is only useful until it lapses. A live socket
    /// lasts until then too (live.rs).
    pub exp: i64,
}

/// Why a token was refused. Kept apart for the tests below, and for a caller
/// that ever needs to tell an expired token from one that is not ours; the
/// service's one caller (accounts.rs `claims`) answers every refusal alike,
/// "Your session has ended. Sign in again."
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum VerifyError {
    /// The wire form was not `v.claims.sig`, or a field would not decode.
    Malformed,
    /// A field decoded but the version tag is not one this build speaks.
    Version,
    /// The signature did not match the public key. Not one of ours, or tampered.
    BadSignature,
    /// The signature was good but the token has lapsed.
    Expired,
}

/// The signing half. Held only by this service; never shipped to a client.
pub struct Issuer {
    key: SigningKey,
}

impl Issuer {
    /// A fresh signing key. Called once, on the service's first start
    /// (accounts.rs); the bytes are then kept in the database (see
    /// `secret_b64`) and reloaded on every start after.
    pub fn generate() -> Self {
        let mut rng = rand::rngs::OsRng;
        Self { key: SigningKey::generate(&mut rng) }
    }

    /// Reload from the 32 secret bytes produced by `secret_b64`.
    pub fn from_secret_b64(s: &str) -> Option<Self> {
        Some(Self { key: SigningKey::from_bytes(&decode_array(s.trim())?) })
    }

    /// The secret, base64url, for the database's meta table. This is the crown
    /// jewel: anyone holding it can mint a token for any account, which is why
    /// the database is the one thing on the box to back up, and to guard.
    pub fn secret_b64(&self) -> String {
        URL_SAFE_NO_PAD.encode(self.key.to_bytes())
    }

    /// The public half, base64url, published at `GET v1/pubkey`. Safe to
    /// publish - it verifies tokens but cannot mint them.
    pub fn public_b64(&self) -> String {
        URL_SAFE_NO_PAD.encode(self.key.verifying_key().to_bytes())
    }

    /// The verifier for this issuer's tokens: how the service checks its own.
    pub fn verifier(&self) -> TokenVerifier {
        TokenVerifier { key: self.key.verifying_key() }
    }

    /// Sign a set of claims into a wire token.
    pub fn issue(&self, claims: &Claims) -> String {
        let body = format!(
            "{TOKEN_V}.{}",
            URL_SAFE_NO_PAD.encode(serde_json::to_vec(claims).expect("claims serialize"))
        );
        let sig = self.key.sign(body.as_bytes());
        format!("{body}.{}", URL_SAFE_NO_PAD.encode(sig.to_bytes()))
    }
}

/// The verifying half: the public key, and nothing else.
#[derive(Clone)]
pub struct TokenVerifier {
    key: VerifyingKey,
}

impl TokenVerifier {
    /// Build from the published public key (`public_b64`), as anyone could. Only the tests do: this service checks
    /// its own tokens with its own key.
    #[cfg(test)]
    pub fn from_public_b64(s: &str) -> Option<Self> {
        VerifyingKey::from_bytes(&decode_array(s.trim())?).ok().map(|key| Self { key })
    }

    /// Check a token against a wall-clock `now` (unix seconds) and return its
    /// claims. The signature is checked before the clock, so a lapsed-but-valid
    /// token is distinguishable from a forgery.
    pub fn verify(&self, token: &str, now: i64) -> Result<Claims, VerifyError> {
        let mut it = token.splitn(3, '.');
        let ver = it.next().ok_or(VerifyError::Malformed)?;
        let claims_b64 = it.next().ok_or(VerifyError::Malformed)?;
        let sig_b64 = it.next().ok_or(VerifyError::Malformed)?;
        if it.next().is_some() {
            return Err(VerifyError::Malformed);
        }
        if ver != TOKEN_V {
            return Err(VerifyError::Version);
        }

        let signature = Signature::from_bytes(&decode_array(sig_b64).ok_or(VerifyError::Malformed)?);
        let body = format!("{ver}.{claims_b64}");
        self.key
            .verify(body.as_bytes(), &signature)
            .map_err(|_| VerifyError::BadSignature)?;

        let claims: Claims = URL_SAFE_NO_PAD
            .decode(claims_b64)
            .ok()
            .and_then(|v| serde_json::from_slice(&v).ok())
            .ok_or(VerifyError::Malformed)?;
        if now >= claims.exp {
            return Err(VerifyError::Expired);
        }
        Ok(claims)
    }
}

/// Verify a detached Ed25519 signature: `message` was signed by the private key
/// matching `public_b64`, and `sig_b64` is the result.
///
/// This is the primitive behind passwordless login. A device holds its own key
/// and registers the public half; to log in it signs a one-time challenge the
/// service hands out (accounts/challenges.rs), and the service checks it here.
/// Same curve as the token, but a wholly separate key per device - the service
/// never sees a device's private key, only that it can produce signatures the
/// public half accepts.
pub fn verify_detached(public_b64: &str, message: &[u8], sig_b64: &str) -> bool {
    let Some(key) = decode_array(public_b64.trim()).and_then(|bytes| VerifyingKey::from_bytes(&bytes).ok()) else {
        return false;
    };
    let Some(signature) = decode_array(sig_b64.trim()).map(|bytes| Signature::from_bytes(&bytes)) else {
        return false;
    };
    key.verify(message, &signature).is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn claims(now: i64, ttl: i64) -> Claims {
        Claims { sub: 42, handle: "matt".into(), iat: now, exp: now + ttl }
    }

    #[test]
    fn round_trips() {
        let iss = Issuer::generate();
        let ver = TokenVerifier::from_public_b64(&iss.public_b64()).unwrap();
        let c = claims(1_000, 3_600);
        let token = iss.issue(&c);
        assert_eq!(ver.verify(&token, 1_000).unwrap(), c);
    }

    #[test]
    fn secret_reload_issues_the_same_key() {
        let iss = Issuer::generate();
        let reloaded = Issuer::from_secret_b64(&iss.secret_b64()).unwrap();
        assert_eq!(iss.public_b64(), reloaded.public_b64());
    }

    #[test]
    fn rejects_expiry() {
        let iss = Issuer::generate();
        let ver = iss.verifier();
        let token = iss.issue(&claims(1_000, 60));
        assert_eq!(ver.verify(&token, 1_061), Err(VerifyError::Expired));
    }

    #[test]
    fn rejects_a_foreign_key() {
        let a = Issuer::generate();
        let b = Issuer::generate();
        let token = a.issue(&claims(1_000, 60));
        assert_eq!(b.verifier().verify(&token, 1_000), Err(VerifyError::BadSignature));
    }

    #[test]
    fn decode_array_takes_exactly_n_bytes_and_nothing_else() {
        let key = [7u8; 32];
        assert_eq!(decode_array::<32>(&URL_SAFE_NO_PAD.encode(key)), Some(key));
        assert_eq!(decode_array::<64>(&URL_SAFE_NO_PAD.encode(key)), None, "32 bytes are not a signature");
        assert_eq!(decode_array::<32>(&URL_SAFE_NO_PAD.encode([7u8; 31])), None, "one short");
        assert_eq!(decode_array::<32>("not base64!"), None);
        assert_eq!(decode_array::<32>(&format!(" {}", URL_SAFE_NO_PAD.encode(key))), None, "it does not trim");
    }

    #[test]
    fn a_detached_signature_checks_against_its_own_key_only() {
        let device = SigningKey::generate(&mut rand::rngs::OsRng);
        let public = URL_SAFE_NO_PAD.encode(device.verifying_key().to_bytes());
        let signature = URL_SAFE_NO_PAD.encode(device.sign(b"nonce").to_bytes());
        assert!(verify_detached(&public, b"nonce", &signature));
        assert!(verify_detached(&format!(" {public} "), b"nonce", &format!("{signature}\n")), "both are trimmed");
        assert!(!verify_detached(&public, b"another nonce", &signature));
        let stranger = URL_SAFE_NO_PAD.encode(SigningKey::generate(&mut rand::rngs::OsRng).verifying_key().to_bytes());
        assert!(!verify_detached(&stranger, b"nonce", &signature));
        assert!(!verify_detached("short", b"nonce", &signature));
        assert!(!verify_detached(&public, b"nonce", "short"));
    }

    #[test]
    fn rejects_tampering() {
        let iss = Issuer::generate();
        let token = iss.issue(&claims(1_000, 60));
        // Flip the last body char before the signature.
        let mut parts: Vec<&str> = token.splitn(3, '.').collect();
        let mutated = parts[1].to_string() + "x";
        parts[1] = &mutated;
        let bad = parts.join(".");
        assert_eq!(iss.verifier().verify(&bad, 1_000), Err(VerifyError::BadSignature));
    }
}
