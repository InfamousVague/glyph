//! A mail sealed on arrival, so that only the account's own devices can open it (docs/MAIL.md, "The seal").
//!
//! Two layers, the same two an organization's notes have (docs/SHARED.md, S2, S3):
//!
//! 1. **A key wrapped to the account.** A fresh 32-byte key for this one mail, wrapped to the account's encryption
//!    PUBLIC key by ECIES exactly as an organization key is wrapped to a member (core/orgs/wrap.ts `wrapFor`,
//!    native/src/crypto.rs `wrap_for`): an ephemeral P-256 pair, ECDH with the account's point, HKDF-SHA-256 with no
//!    salt and the info `glyph/v1/org-key:<context>`, AES-256-GCM with the context as associated data. The wrap is the
//!    ephemeral point (65 bytes), the IV (12) and the ciphertext, base64url. The context is `inbound-mail:<mail id>`,
//!    new for this: no wrap of an organization's key (`org-key:…`) opens as a mail's, nor the reverse, and a mail's
//!    wrap moved onto another mail opens nothing.
//! 2. **The mail under that key**, as `sealBytes` seals everything synced (core/sync/crypto.ts): a version byte (1),
//!    a fresh 12-byte IV and AES-256-GCM, with `mail:<mail id>` as associated data.
//!
//! A device opens it with what it already has: `unwrap_with` (the account's pair, the wrap, `inbound-mail:<id>`) gives
//! the 32 bytes, `seal_key_import` takes them up, and `open` (`mail:<id>`) gives the mail. Nothing new in the core.
//!
//! The service holds the public key only. Once `seal_for` has answered, nothing it made can be opened here.

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use sha2::Sha256;
use zeroize::Zeroizing;

/// HKDF's info before `:<context>`, the organization key's own (wrap.ts `INFO`): the scheme is the same scheme.
const WRAP_INFO: &str = "glyph/v1/org-key";
/// `sealBytes`'s version byte.
const VERSION: u8 = 1;
const IV_BYTES: usize = 12;

/// The context a mail's key is wrapped in.
pub fn wrap_context(id: &str) -> String {
    format!("inbound-mail:{id}")
}

/// The context the mail itself is sealed in.
pub fn seal_context(id: &str) -> String {
    format!("mail:{id}")
}

fn random<const N: usize>() -> [u8; N] {
    use rand::RngCore;
    let mut out = [0u8; N];
    rand::rngs::OsRng.fill_bytes(&mut out);
    out
}

/// The AES key an agreement comes to: ECDH's shared x through HKDF-SHA-256, no salt, the context in the info.
fn agreed(secret: &p256::SecretKey, public: &p256::PublicKey, context: &str) -> Result<Aes256Gcm, String> {
    let shared = p256::ecdh::diffie_hellman(secret.to_nonzero_scalar(), public.as_affine());
    let mut key = Zeroizing::new([0u8; 32]);
    hkdf::Hkdf::<Sha256>::new(Some(&[]), shared.raw_secret_bytes().as_slice())
        .expand(format!("{WRAP_INFO}:{context}").as_bytes(), key.as_mut_slice())
        .map_err(|_| "The mail's key could not be made.".to_string())?;
    Ok(Aes256Gcm::new(key.as_slice().into()))
}

/// `bytes` wrapped to the account whose encryption public key is `public` (its raw point, base64url), bound to
/// `context`. A mail's 32-byte key here; an incoming hook's whole payload in src/hooks.rs, which seals with this and
/// nothing else, as `wrapFor` would seal any bytes it is handed.
pub fn wrap_for(public: &str, bytes: &[u8], context: &str) -> Result<String, String> {
    let point = URL_SAFE_NO_PAD.decode(public).map_err(|_| "That account's key could not be read.".to_string())?;
    let theirs = p256::PublicKey::from_sec1_bytes(&point).map_err(|_| "That account's key could not be read.".to_string())?;
    let ephemeral = loop {
        // Thirty-two random bytes, drawn again in the one case in 2^32 that they are not a scalar of the curve.
        if let Ok(secret) = p256::SecretKey::from_slice(Zeroizing::new(random::<32>()).as_slice()) {
            break secret;
        }
    };
    let cipher = agreed(&ephemeral, &theirs, context)?;
    let iv: [u8; IV_BYTES] = random();
    let sealed = cipher.encrypt(Nonce::from_slice(&iv), Payload { msg: bytes, aad: context.as_bytes() }).map_err(|_| "The mail's key could not be wrapped.".to_string())?;
    let mut out = ephemeral.public_key().to_encoded_point(false).as_bytes().to_vec();
    out.extend_from_slice(&iv);
    out.extend_from_slice(&sealed);
    Ok(URL_SAFE_NO_PAD.encode(out))
}

/// `bytes` sealed under `key` as `sealBytes` seals them: version, IV, AES-256-GCM over `context`.
fn seal_bytes(key: &[u8; 32], bytes: &[u8], context: &str) -> Result<Vec<u8>, String> {
    let iv: [u8; IV_BYTES] = random();
    let sealed = Aes256Gcm::new(key.into()).encrypt(Nonce::from_slice(&iv), Payload { msg: bytes, aad: context.as_bytes() }).map_err(|_| "The mail could not be sealed.".to_string())?;
    let mut out = Vec::with_capacity(1 + IV_BYTES + sealed.len());
    out.push(VERSION);
    out.extend_from_slice(&iv);
    out.extend_from_slice(&sealed);
    Ok(out)
}

/// The mail `id`, its words and files as `payload`, sealed for the account whose encryption public key is `public`:
/// the wrapped key and the sealed blob, both base64url. The mail's key is made here and wiped before this returns.
pub fn seal_for(public: &str, id: &str, payload: &[u8]) -> Result<(String, String), String> {
    let key = Zeroizing::new(random::<32>());
    let wrapped = wrap_for(public, key.as_slice(), &wrap_context(id))?;
    let blob = URL_SAFE_NO_PAD.encode(seal_bytes(&key, payload, &seal_context(id))?);
    Ok((wrapped, blob))
}

/// What `unwrapWith` does, for the tests: the bytes out of a wrap, with the account's private key, in `context`.
#[cfg(test)]
pub fn unwrap_with(secret: &p256::SecretKey, wrapped: &str, context: &str) -> Result<Vec<u8>, String> {
    let bytes = URL_SAFE_NO_PAD.decode(wrapped).map_err(|e| e.to_string())?;
    if bytes.len() < 65 + IV_BYTES + 17 {
        return Err("too short".into());
    }
    let ephemeral = p256::PublicKey::from_sec1_bytes(&bytes[..65]).map_err(|e| e.to_string())?;
    let (iv, rest) = bytes[65..].split_at(IV_BYTES);
    agreed(secret, &ephemeral, context)?.decrypt(Nonce::from_slice(iv), Payload { msg: rest, aad: context.as_bytes() }).map_err(|_| "not this account's".to_string())
}

/// What a device does, for the tests: the mail's key out of its wrap with the account's private key, then the mail.
#[cfg(test)]
pub fn open_with(secret: &p256::SecretKey, id: &str, wrapped: &str, blob: &str) -> Result<Vec<u8>, String> {
    let key = unwrap_with(secret, wrapped, &wrap_context(id))?;
    let key: [u8; 32] = key.try_into().map_err(|_| "not a key".to_string())?;
    let sealed = URL_SAFE_NO_PAD.decode(blob).map_err(|e| e.to_string())?;
    if sealed.first() != Some(&VERSION) || sealed.len() < 1 + IV_BYTES + 16 {
        return Err("not sealed".into());
    }
    let (iv, rest) = sealed[1..].split_at(IV_BYTES);
    Aes256Gcm::new((&key).into()).decrypt(Nonce::from_slice(iv), Payload { msg: rest, aad: seal_context(id).as_bytes() }).map_err(|_| "not this mail".to_string())
}

#[cfg(test)]
pub mod tests {
    use super::*;

    /// A private key the tests make, and its public point as the service keeps one.
    pub fn account_pair() -> (p256::SecretKey, String) {
        let secret = p256::SecretKey::random(&mut rand::rngs::OsRng);
        let public = URL_SAFE_NO_PAD.encode(secret.public_key().to_encoded_point(false).as_bytes());
        (secret, public)
    }

    #[test]
    fn a_sealed_mail_opens_with_the_account_s_private_key_and_nothing_else() {
        let (secret, public) = account_pair();
        let (wrapped, blob) = seal_for(&public, "mail-1", b"Dear Sam").unwrap();
        assert_eq!(open_with(&secret, "mail-1", &wrapped, &blob).unwrap(), b"Dear Sam");
        let (stranger, _) = account_pair();
        assert!(open_with(&stranger, "mail-1", &wrapped, &blob).is_err(), "another account's key opens nothing");
        assert!(open_with(&secret, "mail-2", &wrapped, &blob).is_err(), "nor does the seal moved to another mail");
        // The layout: a point, an IV and a 32-byte key with its tag; a version byte, an IV, the words and a tag.
        assert_eq!(URL_SAFE_NO_PAD.decode(&wrapped).unwrap().len(), 65 + 12 + 32 + 16);
        let sealed = URL_SAFE_NO_PAD.decode(&blob).unwrap();
        assert_eq!((sealed[0], sealed.len()), (1, 1 + 12 + 8 + 16));
        assert!(!blob.contains("Dear") && !String::from_utf8_lossy(&sealed).contains("Dear"));
    }

    #[test]
    fn two_mails_are_sealed_under_two_keys() {
        let (_, public) = account_pair();
        let (a, _) = seal_for(&public, "m", b"same").unwrap();
        let (b, _) = seal_for(&public, "m", b"same").unwrap();
        assert_ne!(a, b, "a fresh key and a fresh ephemeral pair each time");
        assert!(seal_for("not a point", "m", b"x").is_err());
    }
}
