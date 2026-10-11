//! The account's keys and the sealed wire (docs/STAGE7.md, "Crypto"): what the web app asks of WebCrypto in
//! `tauri/src/app/core/sync/crypto.ts`, `core/orgs/wrap.ts`, `core/account/encKey.ts` and `share/share.ts`,
//! byte for byte, so a note sealed on the phone opens on the Mac and the reverse. Held to the web code by
//! fixtures the web code itself wrote (tool/crypto_vectors.mjs, tests/crypto_vectors.rs), in both directions.
//!
//! **Keys are held here.** WebCrypto kept the account key non-extractable; here a key lives in this process's
//! table and the app holds a number that names it. A key leaves only where the web let it:
//!
//! - the account key wrapped under a password's or a recovery code's wrap key (`account_key_wrap`);
//! - a public key (`key_public`);
//! - the pair's private half, for the account's other devices: sealed under the account key in one step
//!   (`pair_seal`), or as the JWK the web's `exportPrivateKey` answers (`pair_export_jwk`), which the caller seals;
//! - `key_keep`, the raw bytes of the account key, the device key or the pair, for the phone's Keystore-backed
//!   storage at sign-in, read back by `key_restore` at launch. A wrap key and an organization key are refused:
//!   the first lives for one sign-in and the second in memory only.
//!
//! And a key is **extractable** or not, as a `CryptoKey` is: only a new account key, or one unwrapped to be
//! wrapped again (a changed password, a new recovery sheet), may be wrapped; only a pair just made may have its
//! private half exported. `key_settle` answers the copy a device keeps, which may do neither. An organization's
//! key crosses as raw bytes where the web's does (`wrap_for`, `unwrap_with`, `seal_key_import`: its
//! `wrapFor(pub, orgKey, …)`, `unwrapWith` and `importKey('raw', …)`); `org_key_new`, `org_key_wrap` and
//! `org_key_unwrap` do the same without the bytes ever leaving.
//!
//! **None of this takes the notes' lock**, or needs `init`: dispatch.rs answers these before it looks for the
//! library. So a 600,000-round `derive` on one thread never holds up `list_notes` on another; the Dart side
//! (lib/account/crypto.dart) asks the long ones from a second isolate for exactly that.
//!
//! Bytes are base64url without padding wherever they cross, in either direction: the wire's own form. (Either
//! alphabet and any padding is read, as the web's `fromBase64Url` reads them.)
//!
//! | command | takes | answers |
//! | --- | --- | --- |
//! | `salt` | `{handle, kind: "password" \| "recovery"}` | the salt, a string |
//! | `normalise_code` | `{code}` | the code as it is compared |
//! | `derive` | `{secret, salt, rounds?}` | `{login, wrapKey}` |
//! | `account_key_new` | | `{key}` |
//! | `account_key_wrap` | `{key, wrapKey}` | the wrapped key |
//! | `account_key_unwrap` | `{wrapped, wrapKey, extractable?}` | `{key}` |
//! | `key_settle` | `{key}` | `{key}`: the copy a device keeps, not extractable |
//! | `seal_key_import` | `{raw}` | `{key}`: a key that seals, from its 32 bytes |
//! | `seal` | `{key, context, text \| data \| value}` | the sealed blob |
//! | `open` | `{key, context, blob, as?: "text" \| "data" \| "value"}` | what was sealed (`value` by default) |
//! | `seal_file` | `{key, context, path, out}` | `{bytes}`, the sealed file's length |
//! | `open_file` | `{key, context, path, out}` | `{bytes}` |
//! | `recovery_code_new` | | `XXXX-XXXX-XXXX` |
//! | `recovery_sheet` | `{handle, key, rounds?}` | `{codes, entries: [{login, wrapped}]}` |
//! | `device_key_new` | | `{key, public}` |
//! | `device_key_sign` | `{key, nonce}` | the signature |
//! | `device_key_verify` | `{public, nonce, signature}` | whether that device signed that nonce: the service's half, for a service in memory |
//! | `pair_new` | | `{key, public}` |
//! | `pair_seal` | `{key, accountKey}` | the private half's JWK, sealed as `encryption-key` |
//! | `pair_open` | `{sealed, accountKey}` | `{key, public}` |
//! | `pair_export_jwk` | `{key}` | the private half as a JWK (an extractable pair only) |
//! | `pair_import_jwk` | `{jwk}` | `{key, public}`, not extractable |
//! | `key_public` | `{key}` | a device key's 32 bytes or a pair's 65-byte point |
//! | `org_key_new` | | `{key}` |
//! | `org_key_wrap` | `{key, public, context}` | the wrap: point ‖ iv ‖ ciphertext |
//! | `org_key_unwrap` | `{pair, wrapped, context}` | `{key}` |
//! | `wrap_for` | `{public, raw, context}` | the wrap, of a key given as bytes |
//! | `unwrap_with` | `{pair, wrapped, context}` | the key's 32 bytes |
//! | `share_key_new`, `short_id` | | 32 and 16 random bytes |
//! | `share_seal` | `{key, shared, pictures?, pictureFiles?}` | the sealed share (`GSP1` when it has pictures) |
//! | `share_open` | `{key, blob}` | `{shared, pictures}` |
//! | `sha256` | `{data}` | the digest's 32 bytes |
//! | `sha256_16` | `{data}` | 32 hex characters |
//! | `digest_file` | `{path}` | the same of a file, or `null` where there is none |
//! | `key_keep` | `{key}` | `{kind, raw}` |
//! | `key_restore` | `{kind, raw}` | `{key}`, with `public` for a device key or a pair |
//! | `key_forget` | `{key}` | whether there was one |
//! | `keys_forget` | | how many were forgotten |

use std::collections::HashMap;
use std::io::Read as _;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use aes_gcm::aead::{Aead, AeadInPlace, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Nonce, Tag};
use base64::Engine as _;
use ed25519_dalek::Signer as _;
use hmac::{Hmac, Mac};
use p256::elliptic_curve::sec1::ToEncodedPoint as _;
use serde::Deserialize;
use serde_json::{json, Map, Value};
use sha2::{Digest as _, Sha256};
use zeroize::{Zeroize, Zeroizing};

/// OWASP's floor for PBKDF2-SHA-256 as of 2023: crypto.ts `ROUNDS`.
pub const ROUNDS: u32 = 600_000;
/// The one byte a sealed blob starts with.
const VERSION: u8 = 1;
const IV_BYTES: usize = 12;
const TAG_BYTES: usize = 16;
/// A P-256 public key, raw: the uncompressed point.
const POINT_BYTES: usize = 65;
/// What the account key is wrapped as.
const ACCOUNT_KEY: &str = "account-key";
/// What the pair's private half is sealed as (encKey.ts `CONTEXT`).
const ENCRYPTION_KEY: &str = "encryption-key";
/// What a share is sealed as (share.ts `CONTEXT`).
const SHARE: &str = "glyph/v1/share";
/// HKDF's info for an organization key's wrap, before `:<context>` (wrap.ts `INFO`).
const ORG_INFO: &str = "glyph/v1/org-key";
/// AttackFM's alphabet: no 0/O or 1/I.
const ALPHABET: &[u8; 32] = b"ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
/// Codes to a recovery sheet.
pub const CODES: usize = 8;
/// A share's first four bytes when it carries pictures.
const PICTURED: [u8; 4] = *b"GSP1";

const NEWER: &str = "This was sealed by a newer Ghost.md. Update the app to read it.";
const NOT_OPENED: &str = "That could not be opened: it was sealed with another key, or for something else, or it has been changed.";
const WRONG_SECRET: &str = "That password or recovery code does not open this account's key.";
const BAD_WRAP: &str = "That wrap could not be read.";
const NEWER_SHARE: &str = "This link was shared by a newer Ghost.md. Update the app to read it.";

/// Every command this module answers. dispatch.rs asks before it looks for the library.
const COMMANDS: [&str; 39] = [
    "salt",
    "normalise_code",
    "derive",
    "account_key_new",
    "account_key_wrap",
    "account_key_unwrap",
    "key_settle",
    "seal_key_import",
    "seal",
    "open",
    "seal_file",
    "open_file",
    "recovery_code_new",
    "recovery_sheet",
    "device_key_new",
    "device_key_sign",
    "device_key_verify",
    "pair_new",
    "pair_seal",
    "pair_open",
    "pair_export_jwk",
    "pair_import_jwk",
    "key_public",
    "org_key_new",
    "org_key_wrap",
    "org_key_unwrap",
    "wrap_for",
    "unwrap_with",
    "share_key_new",
    "short_id",
    "share_seal",
    "share_open",
    "sha256",
    "sha256_16",
    "digest_file",
    "key_keep",
    "key_restore",
    "key_forget",
    "keys_forget",
];

/// Whether `command` is one of this module's.
pub fn has(command: &str) -> bool {
    COMMANDS.contains(&command)
}

// --- bytes and text ---------------------------------------------------------------

/// URL-safe base64 with no padding: crypto.ts `toBase64Url`.
pub fn to_base64url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

/// Bytes out of base64 in either alphabet, padded or not: what crypto.ts `fromBase64Url` reads.
pub fn from_base64url(text: &str) -> Result<Vec<u8>, String> {
    let plain: String = text.trim().chars().filter(|c| *c != '=').map(|c| if c == '+' { '-' } else if c == '/' { '_' } else { c }).collect();
    base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(plain).map_err(|_| "That is not base64.".to_string())
}

fn to_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{b:02x}")).collect()
}

/// `count` bytes from the system's generator: `crypto.getRandomValues`.
fn random<const N: usize>() -> Result<[u8; N], String> {
    let mut out = [0u8; N];
    getrandom::getrandom(&mut out).map_err(|e| format!("The phone gave no random bytes: {e}"))?;
    Ok(out)
}

/// What JavaScript's `trim` takes from either end: its white space and line ends, which are not quite Rust's
/// (U+FEFF goes, U+0085 stays).
fn js_space(c: char) -> bool {
    matches!(c, '\t' | '\n' | '\u{b}' | '\u{c}' | '\r' | ' ' | '\u{a0}' | '\u{1680}' | '\u{2000}'..='\u{200a}' | '\u{2028}' | '\u{2029}' | '\u{202f}' | '\u{205f}' | '\u{3000}' | '\u{feff}')
}

/// What a secret is salted with: the handle as typed, trimmed and lower-cased, after `glyph/v1/` (a password) or
/// `glyph/v1/recovery/` (a recovery code). crypto.ts `passwordSalt` and `recoverySalt`.
pub fn salt(handle: &str, recovery: bool) -> String {
    let handle = handle.trim_matches(js_space).to_lowercase();
    if recovery {
        format!("glyph/v1/recovery/{handle}")
    } else {
        format!("glyph/v1/{handle}")
    }
}

/// A recovery code as it is compared: letters and digits only, upper case. crypto.ts `normaliseCode`.
pub fn normalise_code(code: &str) -> String {
    code.chars().filter(char::is_ascii_alphanumeric).map(|c| c.to_ascii_uppercase()).collect()
}

// --- secrets ----------------------------------------------------------------------

/// One 32-byte block of PBKDF2-HMAC-SHA-256 (RFC 8018, `F`): the keyed HMAC is cloned for each round, so the
/// password is hashed once.
fn pbkdf2_block(keyed: &Hmac<Sha256>, salt: &[u8], rounds: u32, index: u32) -> [u8; 32] {
    let mut mac = keyed.clone();
    mac.update(salt);
    mac.update(&index.to_be_bytes());
    let mut u: [u8; 32] = mac.finalize().into_bytes().into();
    let mut block = u;
    for _ in 1..rounds {
        let mut mac = keyed.clone();
        mac.update(&u);
        u = mac.finalize().into_bytes().into();
        for (out, byte) in block.iter_mut().zip(u.iter()) {
            *out ^= byte;
        }
    }
    u.zeroize();
    block
}

/// The 64 bytes a secret becomes: PBKDF2-HMAC-SHA-256 over `rounds`, salted with `salt`. The two blocks do not
/// depend on each other, so with `threads` they are made side by side and a sign-in waits half as long.
pub fn derive_bytes(secret: &str, salt: &str, rounds: u32, threads: bool) -> Result<Zeroizing<[u8; 64]>, String> {
    if rounds == 0 {
        return Err("A secret is derived over at least one round.".to_string());
    }
    let keyed = <Hmac<Sha256> as Mac>::new_from_slice(secret.as_bytes()).map_err(|_| "That secret could not be used.".to_string())?;
    let salt = salt.as_bytes();
    let (first, second) = if threads {
        std::thread::scope(|scope| {
            let second = scope.spawn(|| pbkdf2_block(&keyed, salt, rounds, 2));
            let first = pbkdf2_block(&keyed, salt, rounds, 1);
            (first, second.join())
        })
    } else {
        (pbkdf2_block(&keyed, salt, rounds, 1), Ok(pbkdf2_block(&keyed, salt, rounds, 2)))
    };
    let mut second = second.map_err(|_| "The secret's second half could not be derived.".to_string())?;
    let mut first = first;
    let mut out = Zeroizing::new([0u8; 64]);
    out[..32].copy_from_slice(&first);
    out[32..].copy_from_slice(&second);
    first.zeroize();
    second.zeroize();
    Ok(out)
}

// --- the keys this process holds -------------------------------------------------

/// Thirty-two bytes of key, wiped when let go.
struct Secret(Zeroizing<[u8; 32]>);

impl Secret {
    fn new(bytes: [u8; 32]) -> Secret {
        Secret(Zeroizing::new(bytes))
    }

    fn from_slice(bytes: &[u8]) -> Option<Secret> {
        let bytes: [u8; 32] = bytes.try_into().ok()?;
        Some(Secret::new(bytes))
    }

    fn cipher(&self) -> Aes256Gcm {
        Aes256Gcm::new(self.0.as_slice().into())
    }
}

/// A key, and what it is for. The kind is checked wherever a key is used, as WebCrypto checked a key's usages.
enum Key {
    /// The second half of a derived secret: wraps and unwraps the account key, and nothing else.
    Wrap(Secret),
    /// The account key: seals what is synced.
    Account(Secret),
    /// An organization's key: seals a team's notes and rooms.
    Org(Secret),
    /// This device's signing key, Ed25519.
    Device(ed25519_dalek::SigningKey),
    /// The account's encryption pair, P-256.
    Pair(p256::SecretKey),
}

impl Key {
    fn kind(&self) -> &'static str {
        match self {
            Key::Wrap(_) => "wrap",
            Key::Account(_) => "account",
            Key::Org(_) => "org",
            Key::Device(_) => "device",
            Key::Pair(_) => "pair",
        }
    }
}

/// A key as the table holds it: with whether it may be wrapped or exported, WebCrypto's `extractable`.
struct Entry {
    key: Key,
    extractable: bool,
}

impl std::ops::Deref for Entry {
    type Target = Key;

    fn deref(&self) -> &Key {
        &self.key
    }
}

struct Table {
    next: u64,
    keys: HashMap<u64, Arc<Entry>>,
}

static KEYS: Mutex<Option<Table>> = Mutex::new(None);

fn with_table<T>(f: impl FnOnce(&mut Table) -> T) -> T {
    let mut table = crate::lock::lock(&KEYS);
    f(table.get_or_insert_with(|| Table { next: 1, keys: HashMap::new() }))
}

/// Keeps `key`, not extractable, and answers the number the app will name it by. A number is never used twice
/// in a process.
fn hold(key: Key) -> u64 {
    hold_as(key, false)
}

fn hold_as(key: Key, extractable: bool) -> u64 {
    with_table(|table| {
        let handle = table.next;
        table.next += 1;
        table.keys.insert(handle, Arc::new(Entry { key, extractable }));
        handle
    })
}

/// The account key under `handle`, when it may be wrapped: WebCrypto refuses `exportKey` on any other.
fn wrappable(handle: u64) -> Result<Arc<Entry>, String> {
    let entry = held(handle)?;
    match &entry.key {
        Key::Account(_) if entry.extractable => Ok(entry),
        Key::Account(_) => Err("That account key is the copy a device keeps, and cannot be wrapped.".to_string()),
        other => Err(format!("A {} key is not the account key.", other.kind())),
    }
}

fn held(handle: u64) -> Result<Arc<Entry>, String> {
    with_table(|table| table.keys.get(&handle).cloned()).ok_or_else(|| "That key is not held any more.".to_string())
}

/// A key that seals: the account's or an organization's.
fn sealing(handle: u64) -> Result<Aes256Gcm, String> {
    match &held(handle)?.key {
        Key::Account(secret) | Key::Org(secret) => Ok(secret.cipher()),
        other => Err(format!("A {} key does not seal.", other.kind())),
    }
}

fn wrapping(handle: u64) -> Result<Aes256Gcm, String> {
    match &held(handle)?.key {
        Key::Wrap(secret) => Ok(secret.cipher()),
        other => Err(format!("A {} key does not wrap the account key.", other.kind())),
    }
}

fn pair(handle: u64) -> Result<p256::SecretKey, String> {
    match &held(handle)?.key {
        Key::Pair(secret) => Ok(secret.clone()),
        other => Err(format!("A {} key is not the account's encryption pair.", other.kind())),
    }
}

// --- sealed blobs -----------------------------------------------------------------

/// `1 ‖ iv ‖ AES-GCM(bytes)`, bound to `context`: crypto.ts `sealBytes`.
fn seal_bytes(cipher: &Aes256Gcm, bytes: &[u8], context: &str) -> Result<Vec<u8>, String> {
    let iv: [u8; IV_BYTES] = random()?;
    let sealed = cipher.encrypt(Nonce::from_slice(&iv), Payload { msg: bytes, aad: context.as_bytes() }).map_err(|_| "That could not be sealed.".to_string())?;
    let mut out = Vec::with_capacity(1 + IV_BYTES + sealed.len());
    out.push(VERSION);
    out.extend_from_slice(&iv);
    out.extend_from_slice(&sealed);
    Ok(out)
}

/// The bytes back out of a sealed blob: crypto.ts `openBytes`. Fails on the wrong key, a tampered blob, or a
/// blob moved from another context, and says so when a newer app sealed it.
fn open_bytes(cipher: &Aes256Gcm, sealed: &[u8], context: &str) -> Result<Vec<u8>, String> {
    if sealed.first() != Some(&VERSION) {
        return Err(NEWER.to_string());
    }
    if sealed.len() < 1 + IV_BYTES + TAG_BYTES {
        return Err(NOT_OPENED.to_string());
    }
    let (iv, rest) = sealed[1..].split_at(IV_BYTES);
    cipher.decrypt(Nonce::from_slice(iv), Payload { msg: rest, aad: context.as_bytes() }).map_err(|_| NOT_OPENED.to_string())
}

/// The account key wrapped: `iv ‖ AES-GCM(raw key)`, with no version byte. crypto.ts `wrap`.
fn wrap_account(account: &Secret, wrap: &Aes256Gcm) -> Result<String, String> {
    let iv: [u8; IV_BYTES] = random()?;
    let sealed = wrap.encrypt(Nonce::from_slice(&iv), Payload { msg: account.0.as_slice(), aad: ACCOUNT_KEY.as_bytes() }).map_err(|_| "The account key could not be wrapped.".to_string())?;
    let mut out = iv.to_vec();
    out.extend_from_slice(&sealed);
    Ok(to_base64url(&out))
}

/// The account key out of `wrapped`. GCM's tag is the check of the password or code: there is nothing to compare
/// by hand. crypto.ts `unwrap`.
fn unwrap_account(wrapped: &str, wrap: &Aes256Gcm) -> Result<Secret, String> {
    let bytes = from_base64url(wrapped).map_err(|_| WRONG_SECRET.to_string())?;
    if bytes.len() < IV_BYTES + TAG_BYTES {
        return Err(WRONG_SECRET.to_string());
    }
    let (iv, rest) = bytes.split_at(IV_BYTES);
    let raw = Zeroizing::new(wrap.decrypt(Nonce::from_slice(iv), Payload { msg: rest, aad: ACCOUNT_KEY.as_bytes() }).map_err(|_| WRONG_SECRET.to_string())?);
    Secret::from_slice(&raw).ok_or_else(|| "That is not an account key.".to_string())
}

// --- files -------------------------------------------------------------------------

/// The temporary file a sealed or opened file is written through, beside where it will be.
fn beside(path: &Path) -> PathBuf {
    let mut name = std::ffi::OsString::from(".");
    name.push(crate::note::new_id());
    name.push(".part");
    path.with_file_name(name)
}

/// `bytes` at `path`, whole or not at all: through a hidden file beside it, flushed, then renamed over.
fn write_whole(path: &Path, parts: &[&[u8]]) -> Result<(), String> {
    use std::io::Write as _;
    if let Some(parent) = path.parent().filter(|p| !p.as_os_str().is_empty()) {
        std::fs::create_dir_all(parent).map_err(|e| format!("There is nowhere to write {}: {e}", path.display()))?;
    }
    let part = beside(path);
    let written = (|| -> std::io::Result<()> {
        let mut file = std::fs::File::create(&part)?;
        for bytes in parts {
            file.write_all(bytes)?;
        }
        file.sync_all()?;
        std::fs::rename(&part, path)
    })();
    written.map_err(|e| {
        let _ = std::fs::remove_file(&part);
        format!("{} could not be written: {e}", path.display())
    })
}

fn read_whole(path: &Path) -> Result<Vec<u8>, String> {
    std::fs::read(path).map_err(|e| format!("{} could not be read: {e}", path.display()))
}

/// The file at `path` sealed into the file at `out`, in the wire's own layout (`1 ‖ iv ‖ ciphertext ‖ tag`, the
/// bytes a `PUT` carries), without either crossing to the app. An hour's recording is read once, sealed where it
/// lies and written once: one copy of it in memory, where base64 through JSON would have made five.
fn seal_file(cipher: &Aes256Gcm, context: &str, path: &Path, out: &Path) -> Result<u64, String> {
    let mut bytes = read_whole(path)?;
    let iv: [u8; IV_BYTES] = random()?;
    let tag = cipher.encrypt_in_place_detached(Nonce::from_slice(&iv), context.as_bytes(), &mut bytes).map_err(|_| "That file could not be sealed.".to_string())?;
    write_whole(out, &[&[VERSION], &iv, &bytes, tag.as_slice()])?;
    Ok((1 + IV_BYTES + bytes.len() + TAG_BYTES) as u64)
}

/// The sealed file at `path` opened into the file at `out`. Nothing is written unless the whole of it is what was
/// sealed: the tag is checked before a byte is trusted.
fn open_file(cipher: &Aes256Gcm, context: &str, path: &Path, out: &Path) -> Result<u64, String> {
    let mut bytes = read_whole(path)?;
    if bytes.first() != Some(&VERSION) {
        return Err(NEWER.to_string());
    }
    if bytes.len() < 1 + IV_BYTES + TAG_BYTES {
        return Err(NOT_OPENED.to_string());
    }
    let tag = Tag::clone_from_slice(&bytes[bytes.len() - TAG_BYTES..]);
    let iv: [u8; IV_BYTES] = bytes[1..1 + IV_BYTES].try_into().map_err(|_| NOT_OPENED.to_string())?;
    let end = bytes.len() - TAG_BYTES;
    let body = &mut bytes[1 + IV_BYTES..end];
    cipher.decrypt_in_place_detached(Nonce::from_slice(&iv), context.as_bytes(), body, &tag).map_err(|_| NOT_OPENED.to_string())?;
    write_whole(out, &[body])?;
    Ok(body.len() as u64)
}

/// The first sixteen bytes of a SHA-256, as hex: what sync remembers a file by (core/sync/notes.ts `sha`).
pub fn sha256_16(bytes: &[u8]) -> String {
    to_hex(&Sha256::digest(bytes)[..16])
}

/// `sha256_16` of a file, read a quarter of a megabyte at a time; `None` where there is no such file.
pub fn digest_file(path: &Path) -> Option<String> {
    let mut source = std::fs::File::open(path).ok()?;
    let mut hasher = Sha256::new();
    let mut buffer = vec![0u8; 256 * 1024];
    loop {
        let read = source.read(&mut buffer).ok()?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    Some(to_hex(&hasher.finalize()[..16]))
}

// --- recovery codes ---------------------------------------------------------------

/// One code, `XXXX-XXXX-XXXX`: sixty bits. crypto.ts `newRecoveryCode`.
fn recovery_code() -> Result<String, String> {
    let picks: [u8; 12] = random()?;
    let picks: Vec<u8> = picks.iter().map(|byte| ALPHABET[(byte & 31) as usize]).collect();
    let group = |at: usize| String::from_utf8_lossy(&picks[at..at + 4]).into_owned();
    Ok(format!("{}-{}-{}", group(0), group(4), group(8)))
}

/// A recovery sheet: eight new codes, and for each what the service keeps. crypto.ts `newSheet`, with the eight
/// derivations side by side as its `Promise.all` had them.
fn recovery_sheet(handle: &str, account: &Secret, rounds: u32) -> Result<Value, String> {
    let codes = (0..CODES).map(|_| recovery_code()).collect::<Result<Vec<_>, _>>()?;
    let salt = salt(handle, true);
    let entries = std::thread::scope(|scope| {
        let working: Vec<_> = codes
            .iter()
            .map(|code| {
                let salt = &salt;
                scope.spawn(move || -> Result<Value, String> {
                    let derived = derive_bytes(&normalise_code(code), salt, rounds, false)?;
                    let wrap = Secret::from_slice(&derived[32..]).ok_or("no wrap key")?;
                    Ok(json!({ "login": to_hex(&derived[..32]), "wrapped": wrap_account(account, &wrap.cipher())? }))
                })
            })
            .collect();
        working.into_iter().map(|one| one.join().map_err(|_| "A recovery code could not be derived.".to_string())?).collect::<Result<Vec<_>, String>>()
    })?;
    Ok(json!({ "codes": codes, "entries": entries }))
}

// --- the encryption pair and an organization's key ---------------------------------

/// A fresh P-256 private key: thirty-two random bytes, drawn again in the one case in 2^32 that they are not a
/// scalar of the curve.
fn new_pair() -> Result<p256::SecretKey, String> {
    loop {
        let bytes = Zeroizing::new(random::<32>()?);
        if let Ok(key) = p256::SecretKey::from_slice(bytes.as_slice()) {
            return Ok(key);
        }
    }
}

/// A pair's public key as the service keeps it: the raw uncompressed point.
fn point_of(secret: &p256::SecretKey) -> Vec<u8> {
    secret.public_key().to_encoded_point(false).as_bytes().to_vec()
}

/// The private half as WebCrypto exports it (`exportKey('jwk', …)`), so `importEncryptionKey` on the Mac takes it.
fn jwk_of(secret: &p256::SecretKey) -> Value {
    let point = secret.public_key().to_encoded_point(false);
    let coordinate = |bytes: Option<&p256::FieldBytes>| to_base64url(bytes.map(|b| b.as_slice()).unwrap_or_default());
    json!({
        "key_ops": ["deriveBits"],
        "ext": true,
        "kty": "EC",
        "x": coordinate(point.x()),
        "y": coordinate(point.y()),
        "crv": "P-256",
        "d": to_base64url(Zeroizing::new(secret.to_bytes()).as_slice()),
    })
}

/// A pair back from its private half's JWK. The public point is worked out from `d`; an `x` or `y` that
/// disagrees with it is refused, as WebCrypto refuses one.
fn pair_of_jwk(jwk: &Value) -> Result<p256::SecretKey, String> {
    let refuse = || "That is not the account's encryption key.".to_string();
    let field = |name: &str| jwk.get(name).and_then(Value::as_str);
    if field("kty") != Some("EC") || field("crv") != Some("P-256") {
        return Err(refuse());
    }
    let d = Zeroizing::new(from_base64url(field("d").ok_or_else(refuse)?).map_err(|_| refuse())?);
    let secret = p256::SecretKey::from_slice(&d).map_err(|_| refuse())?;
    let point = secret.public_key().to_encoded_point(false);
    for (name, ours) in [("x", point.x()), ("y", point.y())] {
        if let Some(theirs) = field(name) {
            if from_base64url(theirs).ok().as_deref() != ours.map(|b| b.as_slice()) {
                return Err(refuse());
            }
        }
    }
    Ok(secret)
}

/// The AES key two halves of an agreement come to: ECDH's shared x, through HKDF-SHA-256 with no salt and the
/// context in its info. wrap.ts `agreed`.
fn agreed(secret: &p256::SecretKey, public: &p256::PublicKey, context: &str) -> Result<Aes256Gcm, String> {
    let shared = p256::ecdh::diffie_hellman(secret.to_nonzero_scalar(), public.as_affine());
    let mut key = Zeroizing::new([0u8; 32]);
    hkdf::Hkdf::<Sha256>::new(Some(&[]), shared.raw_secret_bytes().as_slice())
        .expand(format!("{ORG_INFO}:{context}").as_bytes(), key.as_mut_slice())
        .map_err(|_| BAD_WRAP.to_string())?;
    Ok(Aes256Gcm::new(key.as_slice().into()))
}

/// `org_key` wrapped for the member whose public key is `public`, bound to `context`: wrap.ts `wrapFor`.
fn wrap_for(public: &str, org_key: &Secret, context: &str) -> Result<String, String> {
    let theirs = p256::PublicKey::from_sec1_bytes(&from_base64url(public)?).map_err(|_| "That is not a member's public key.".to_string())?;
    let ephemeral = new_pair()?;
    let cipher = agreed(&ephemeral, &theirs, context)?;
    let iv: [u8; IV_BYTES] = random()?;
    let sealed = cipher.encrypt(Nonce::from_slice(&iv), Payload { msg: org_key.0.as_slice(), aad: context.as_bytes() }).map_err(|_| "The organization's key could not be wrapped.".to_string())?;
    let mut out = point_of(&ephemeral);
    out.extend_from_slice(&iv);
    out.extend_from_slice(&sealed);
    Ok(to_base64url(&out))
}

/// The organization key out of `wrapped`, with this account's private key: wrap.ts `unwrapWith`.
fn unwrap_with(secret: &p256::SecretKey, wrapped: &str, context: &str) -> Result<Secret, String> {
    let bytes = from_base64url(wrapped).map_err(|_| BAD_WRAP.to_string())?;
    if bytes.len() < POINT_BYTES + IV_BYTES + 17 {
        return Err(BAD_WRAP.to_string());
    }
    let ephemeral = p256::PublicKey::from_sec1_bytes(&bytes[..POINT_BYTES]).map_err(|_| BAD_WRAP.to_string())?;
    let cipher = agreed(secret, &ephemeral, context)?;
    let (iv, rest) = bytes[POINT_BYTES..].split_at(IV_BYTES);
    let raw = Zeroizing::new(cipher.decrypt(Nonce::from_slice(iv), Payload { msg: rest, aad: context.as_bytes() }).map_err(|_| "That wrap is not for this account, or not for this organization.".to_string())?);
    Secret::from_slice(&raw).ok_or_else(|| BAD_WRAP.to_string())
}

// --- shares ------------------------------------------------------------------------

/// A picture's name as a note writes it (share.ts `PICTURE_NAME`): `[A-Za-z0-9_-][A-Za-z0-9_.-]{0,127}`.
fn picture_name(name: &str) -> bool {
    let plain = |c: char| c.is_ascii_alphanumeric() || c == '_' || c == '-';
    let mut chars = name.chars();
    chars.next().is_some_and(plain) && name.len() <= 128 && chars.all(|c| plain(c) || c == '.')
}

/// A share's key as its link carries it: thirty-two bytes, base64url.
fn share_cipher(key: &str) -> Result<Aes256Gcm, String> {
    let raw = Zeroizing::new(from_base64url(key).map_err(|_| "That is not a share's key.".to_string())?);
    Ok(Secret::from_slice(&raw).ok_or_else(|| "That is not a share's key.".to_string())?.cipher())
}

/// A share sealed under its own key: share.ts `sealShare`. With no pictures it is its JSON alone; with them,
/// `GSP1`, the length of the words as four bytes, the words (each picture's name and size where the pictures
/// were), then the pictures' bytes one after another, in the order given.
fn seal_share(key: &str, words: &Map<String, Value>, pictures: &[(String, Vec<u8>)]) -> Result<String, String> {
    let cipher = share_cipher(key)?;
    let mut words = words.clone();
    words.remove("pictures");
    if pictures.is_empty() {
        let text = serde_json::to_vec(&words).map_err(|e| e.to_string())?;
        return Ok(to_base64url(&seal_bytes(&cipher, &text, SHARE)?));
    }
    words.insert("pictures".to_string(), Value::Array(pictures.iter().map(|(name, bytes)| json!([name, bytes.len()])).collect()));
    let head = serde_json::to_vec(&words).map_err(|e| e.to_string())?;
    let length = u32::try_from(head.len()).map_err(|_| "That is more than a share can hold.".to_string())?;
    let mut out = Vec::with_capacity(8 + head.len() + pictures.iter().map(|(_, bytes)| bytes.len()).sum::<usize>());
    out.extend_from_slice(&PICTURED);
    out.extend_from_slice(&length.to_be_bytes());
    out.extend_from_slice(&head);
    for (_, bytes) in pictures {
        out.extend_from_slice(bytes);
    }
    Ok(to_base64url(&seal_bytes(&cipher, &out, SHARE)?))
}

/// A share opened: share.ts `openShare`. Answers the words (without a `pictures` field) and the pictures by name.
fn open_share(key: &str, blob: &str) -> Result<(Value, Vec<(String, Vec<u8>)>), String> {
    let bytes = open_bytes(&share_cipher(key)?, &from_base64url(blob)?, SHARE)?;
    let unreadable = || "That share could not be read.".to_string();
    let mut pictures = Vec::new();
    let mut shared: Value = if bytes.starts_with(&PICTURED) {
        let length = bytes.get(4..8).map(|b| u32::from_be_bytes([b[0], b[1], b[2], b[3]]) as usize).ok_or_else(unreadable)?;
        let head = bytes.get(8..8 + length).ok_or_else(unreadable)?;
        let head: Value = serde_json::from_slice(head).map_err(|_| unreadable())?;
        let mut at = 8 + length;
        for entry in head.get("pictures").and_then(Value::as_array).map(Vec::as_slice).unwrap_or_default() {
            let name = entry.get(0).and_then(Value::as_str);
            let size = entry.get(1).and_then(Value::as_u64).unwrap_or(0) as usize;
            if let (Some(name), true) = (name.filter(|name| picture_name(name)), size > 0) {
                // `slice` in the page: as much as is there, never past the end.
                let end = at.saturating_add(size).min(bytes.len());
                pictures.push((name.to_string(), bytes.get(at..end).unwrap_or_default().to_vec()));
            }
            at = at.saturating_add(size);
        }
        head
    } else {
        serde_json::from_slice(&bytes).map_err(|_| unreadable())?
    };
    if shared.get("v").and_then(Value::as_i64) != Some(1) || !shared.get("pages").is_some_and(Value::is_array) {
        return Err(NEWER_SHARE.to_string());
    }
    if let Some(words) = shared.as_object_mut() {
        words.remove("pictures");
    }
    Ok((shared, pictures))
}

// --- the commands ------------------------------------------------------------------

#[derive(Deserialize)]
struct Salt {
    handle: String,
    kind: String,
}

#[derive(Deserialize)]
struct Derive {
    secret: String,
    salt: String,
    rounds: Option<u32>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct WrapAccount {
    key: u64,
    wrap_key: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct UnwrapAccount {
    wrapped: String,
    wrap_key: u64,
    #[serde(default)]
    extractable: bool,
}

#[derive(Deserialize)]
struct Seal {
    key: u64,
    context: String,
    text: Option<String>,
    data: Option<String>,
    value: Option<Value>,
}

#[derive(Deserialize)]
struct Open {
    key: u64,
    context: String,
    blob: String,
    #[serde(rename = "as")]
    form: Option<String>,
}

#[derive(Deserialize)]
struct File {
    key: u64,
    context: String,
    path: PathBuf,
    out: PathBuf,
}

#[derive(Deserialize)]
struct Sheet {
    handle: String,
    key: u64,
    rounds: Option<u32>,
}

#[derive(Deserialize)]
struct ByKey {
    key: u64,
}

#[derive(Deserialize)]
struct Sign {
    key: u64,
    nonce: String,
}

#[derive(Deserialize)]
struct Verify {
    public: String,
    nonce: String,
    signature: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairSeal {
    key: u64,
    account_key: u64,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct PairOpen {
    sealed: String,
    account_key: u64,
}

#[derive(Deserialize)]
struct OrgWrap {
    key: u64,
    public: String,
    context: String,
}

#[derive(Deserialize)]
struct WrapFor {
    public: String,
    raw: String,
    context: String,
}

#[derive(Deserialize)]
struct Raw {
    raw: String,
}

#[derive(Deserialize)]
struct Jwk {
    jwk: Value,
}

#[derive(Deserialize)]
struct OrgUnwrap {
    pair: u64,
    wrapped: String,
    context: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ShareSeal {
    key: String,
    shared: Map<String, Value>,
    /// Pictures by name, as base64url, in the order they are to be carried.
    #[serde(default)]
    pictures: Vec<(String, String)>,
    /// Pictures by name, each read from a file here rather than sent across.
    #[serde(default)]
    picture_files: Vec<(String, PathBuf)>,
}

#[derive(Deserialize)]
struct ShareOpen {
    key: String,
    blob: String,
}

#[derive(Deserialize)]
struct Data {
    data: String,
}

#[derive(Deserialize)]
struct ByPath {
    path: PathBuf,
}

#[derive(Deserialize)]
struct Restore {
    kind: String,
    raw: String,
}

#[derive(Deserialize)]
struct Code {
    code: String,
}

fn read<T: serde::de::DeserializeOwned>(command: &str, args: Value) -> Result<T, String> {
    serde_json::from_value(args).map_err(|e| format!("invalid args for command `{command}`: {e}"))
}

fn device_public(key: &ed25519_dalek::SigningKey) -> String {
    to_base64url(key.verifying_key().as_bytes())
}

/// One of this module's commands. The table in the header says what each takes and answers.
pub fn call(command: &str, args: Value) -> Result<Value, String> {
    match command {
        "salt" => {
            let Salt { handle, kind } = read(command, args)?;
            match kind.as_str() {
                "password" => Ok(json!(salt(&handle, false))),
                "recovery" => Ok(json!(salt(&handle, true))),
                _ => Err(format!("Nothing is salted as {kind}.")),
            }
        }
        "normalise_code" => {
            let Code { code } = read(command, args)?;
            Ok(json!(normalise_code(&code)))
        }
        // The two halves of a secret: the login half as hex, and the wrap key, held here.
        "derive" => {
            let Derive { secret, salt, rounds } = read(command, args)?;
            let secret = Zeroizing::new(secret);
            let derived = derive_bytes(&secret, &salt, rounds.unwrap_or(ROUNDS), true)?;
            let wrap = Secret::from_slice(&derived[32..]).ok_or("no wrap key")?;
            Ok(json!({ "login": to_hex(&derived[..32]), "wrapKey": hold(Key::Wrap(wrap)) }))
        }
        // Extractable, so it can be wrapped; `key_settle` is the copy a device keeps.
        "account_key_new" => Ok(json!({ "key": hold_as(Key::Account(Secret::new(random()?)), true) })),
        "account_key_wrap" => {
            let WrapAccount { key, wrap_key } = read(command, args)?;
            let wrap = wrapping(wrap_key)?;
            match &wrappable(key)?.key {
                Key::Account(account) => Ok(json!(wrap_account(account, &wrap)?)),
                other => Err(format!("A {} key is not the account key.", other.kind())),
            }
        }
        "account_key_unwrap" => {
            let UnwrapAccount { wrapped, wrap_key, extractable } = read(command, args)?;
            let account = unwrap_account(&wrapped, &wrapping(wrap_key)?)?;
            Ok(json!({ "key": hold_as(Key::Account(account), extractable) }))
        }
        // crypto.ts `settle` and wrap.ts `settleEncryptionKey`: the same key, no longer extractable. One that
        // already is not is answered as it is.
        "key_settle" => {
            let ByKey { key } = read(command, args)?;
            let entry = held(key)?;
            if !entry.extractable {
                return Ok(json!({ "key": key }));
            }
            let copy = match &entry.key {
                Key::Account(secret) => Key::Account(Secret::new(*secret.0)),
                Key::Pair(secret) => Key::Pair(secret.clone()),
                other => return Err(format!("A {} key is not one a device settles.", other.kind())),
            };
            Ok(json!({ "key": hold(copy) }))
        }
        // WebCrypto's `importKey('raw', …, 'AES-GCM')`: an organization's key out of its wrap, where the caller
        // holds the bytes as the web's does.
        "seal_key_import" => {
            let Raw { raw } = read(command, args)?;
            let raw = Zeroizing::new(from_base64url(&raw)?);
            Ok(json!({ "key": hold(Key::Org(Secret::from_slice(&raw).ok_or("A key that seals is 32 bytes.")?)) }))
        }
        "seal" => {
            let Seal { key, context, text, data, value } = read(command, args)?;
            let cipher = sealing(key)?;
            let bytes = match (text, data, value) {
                (Some(text), None, None) => text.into_bytes(),
                (None, Some(data), None) => from_base64url(&data)?,
                // `JSON.stringify`, as crypto.ts `seal` writes a value.
                (None, None, Some(value)) => serde_json::to_vec(&value).map_err(|e| e.to_string())?,
                (None, None, None) => b"null".to_vec(),
                _ => return Err("seal takes one of text, data and value.".to_string()),
            };
            Ok(json!(to_base64url(&seal_bytes(&cipher, &bytes, &context)?)))
        }
        "open" => {
            let Open { key, context, blob, form } = read(command, args)?;
            let bytes = open_bytes(&sealing(key)?, &from_base64url(&blob).map_err(|_| NOT_OPENED.to_string())?, &context)?;
            match form.as_deref().unwrap_or("value") {
                "data" => Ok(json!(to_base64url(&bytes))),
                "text" => Ok(json!(String::from_utf8(bytes).map_err(|_| "What was sealed is not text.".to_string())?)),
                "value" => serde_json::from_slice(&bytes).map_err(|_| "What was sealed is not JSON.".to_string()),
                other => Err(format!("Nothing is opened as {other}.")),
            }
        }
        "seal_file" => {
            let File { key, context, path, out } = read(command, args)?;
            Ok(json!({ "bytes": seal_file(&sealing(key)?, &context, &path, &out)? }))
        }
        "open_file" => {
            let File { key, context, path, out } = read(command, args)?;
            Ok(json!({ "bytes": open_file(&sealing(key)?, &context, &path, &out)? }))
        }
        "recovery_code_new" => Ok(json!(recovery_code()?)),
        "recovery_sheet" => {
            let Sheet { handle, key, rounds } = read(command, args)?;
            match &wrappable(key)?.key {
                Key::Account(account) => recovery_sheet(&handle, account, rounds.unwrap_or(ROUNDS)),
                other => Err(format!("A {} key is not the account key.", other.kind())),
            }
        }
        "device_key_new" => {
            let key = ed25519_dalek::SigningKey::from_bytes(&*Zeroizing::new(random::<32>()?));
            let public = device_public(&key);
            Ok(json!({ "key": hold(Key::Device(key)), "public": public }))
        }
        "device_key_sign" => {
            let Sign { key, nonce } = read(command, args)?;
            match &held(key)?.key {
                Key::Device(device) => Ok(json!(to_base64url(&device.sign(nonce.as_bytes()).to_bytes()))),
                other => Err(format!("A {} key does not sign.", other.kind())),
            }
        }
        // What server/src/accounts.rs does with a device's signature at `login/device`: no key of this device's is
        // asked for, and anything that is not a key or a signature is simply not a match.
        "device_key_verify" => {
            use ed25519_dalek::Verifier as _;
            let Verify { public, nonce, signature } = read(command, args)?;
            let public: Option<[u8; 32]> = from_base64url(&public).ok().and_then(|bytes| bytes.try_into().ok());
            let signature: Option<[u8; 64]> = from_base64url(&signature).ok().and_then(|bytes| bytes.try_into().ok());
            let (Some(public), Some(signature)) = (public, signature) else { return Ok(json!(false)) };
            let Ok(verifying) = ed25519_dalek::VerifyingKey::from_bytes(&public) else { return Ok(json!(false)) };
            Ok(json!(verifying.verify(nonce.as_bytes(), &ed25519_dalek::Signature::from_bytes(&signature)).is_ok()))
        }
        "pair_new" => {
            let secret = new_pair()?;
            let public = to_base64url(&point_of(&secret));
            Ok(json!({ "key": hold_as(Key::Pair(secret), true), "public": public }))
        }
        // wrap.ts `exportPrivateKey` and `importEncryptionKey`, for a caller that seals the JWK itself.
        "pair_export_jwk" => {
            let ByKey { key } = read(command, args)?;
            if !held(key)?.extractable {
                return Err("That pair is the copy a device keeps: its private half cannot be exported.".to_string());
            }
            Ok(jwk_of(&pair(key)?))
        }
        "pair_import_jwk" => {
            let Jwk { jwk } = read(command, args)?;
            let secret = pair_of_jwk(&jwk)?;
            let public = to_base64url(&point_of(&secret));
            Ok(json!({ "key": hold(Key::Pair(secret)), "public": public }))
        }
        "pair_seal" => {
            let PairSeal { key, account_key } = read(command, args)?;
            if !held(key)?.extractable {
                return Err("That pair is the copy a device keeps: its private half cannot be exported.".to_string());
            }
            let account = match &held(account_key)?.key {
                Key::Account(account) => account.cipher(),
                other => return Err(format!("A {} key is not the account key.", other.kind())),
            };
            let jwk = Zeroizing::new(serde_json::to_vec(&jwk_of(&pair(key)?)).map_err(|e| e.to_string())?);
            Ok(json!(to_base64url(&seal_bytes(&account, &jwk, ENCRYPTION_KEY)?)))
        }
        "pair_open" => {
            let PairOpen { sealed, account_key } = read(command, args)?;
            let account = match &held(account_key)?.key {
                Key::Account(account) => account.cipher(),
                other => return Err(format!("A {} key is not the account key.", other.kind())),
            };
            let jwk = Zeroizing::new(open_bytes(&account, &from_base64url(&sealed).map_err(|_| NOT_OPENED.to_string())?, ENCRYPTION_KEY)?);
            let secret = pair_of_jwk(&serde_json::from_slice(&jwk).map_err(|_| "That is not the account's encryption key.".to_string())?)?;
            let public = to_base64url(&point_of(&secret));
            Ok(json!({ "key": hold(Key::Pair(secret)), "public": public }))
        }
        "key_public" => {
            let ByKey { key } = read(command, args)?;
            match &held(key)?.key {
                Key::Device(device) => Ok(json!(device_public(device))),
                Key::Pair(secret) => Ok(json!(to_base64url(&point_of(secret)))),
                other => Err(format!("A {} key has no public half.", other.kind())),
            }
        }
        "org_key_new" => Ok(json!({ "key": hold(Key::Org(Secret::new(random()?))) })),
        "org_key_wrap" => {
            let OrgWrap { key, public, context } = read(command, args)?;
            match &held(key)?.key {
                Key::Org(org) => Ok(json!(wrap_for(&public, org, &context)?)),
                other => Err(format!("A {} key is not an organization's key.", other.kind())),
            }
        }
        "org_key_unwrap" => {
            let OrgUnwrap { pair: handle, wrapped, context } = read(command, args)?;
            let org = unwrap_with(&pair(handle)?, &wrapped, &context)?;
            Ok(json!({ "key": hold(Key::Org(org)) }))
        }
        // wrap.ts `wrapFor` and `unwrapWith` as the web has them: the organization's key as bytes.
        "wrap_for" => {
            let WrapFor { public, raw, context } = read(command, args)?;
            let raw = Zeroizing::new(from_base64url(&raw)?);
            Ok(json!(wrap_for(&public, &Secret::from_slice(&raw).ok_or("An organization's key is 32 bytes.")?, &context)?))
        }
        "unwrap_with" => {
            let OrgUnwrap { pair: handle, wrapped, context } = read(command, args)?;
            Ok(json!(to_base64url(unwrap_with(&pair(handle)?, &wrapped, &context)?.0.as_slice())))
        }
        "share_key_new" => Ok(json!(to_base64url(&*Zeroizing::new(random::<32>()?)))),
        "short_id" => Ok(json!(to_base64url(&random::<16>()?))),
        "share_seal" => {
            let ShareSeal { key, shared, pictures, picture_files } = read(command, args)?;
            let mut carried = Vec::with_capacity(pictures.len() + picture_files.len());
            for (name, data) in pictures {
                carried.push((name, from_base64url(&data)?));
            }
            for (name, path) in picture_files {
                carried.push((name, read_whole(&path)?));
            }
            Ok(json!(seal_share(&key, &shared, &carried)?))
        }
        "share_open" => {
            let ShareOpen { key, blob } = read(command, args)?;
            let (shared, pictures) = open_share(&key, &blob)?;
            let pictures: Vec<Value> = pictures.iter().map(|(name, bytes)| json!([name, to_base64url(bytes)])).collect();
            Ok(json!({ "shared": shared, "pictures": pictures }))
        }
        "sha256" => {
            let Data { data } = read(command, args)?;
            Ok(json!(to_base64url(&Sha256::digest(from_base64url(&data)?))))
        }
        "sha256_16" => {
            let Data { data } = read(command, args)?;
            Ok(json!(sha256_16(&from_base64url(&data)?)))
        }
        "digest_file" => {
            let ByPath { path } = read(command, args)?;
            Ok(json!(digest_file(&path)))
        }
        // For the phone's secure storage, at sign-in.
        "key_keep" => {
            let ByKey { key } = read(command, args)?;
            let key = held(key)?;
            let raw = match &key.key {
                Key::Account(secret) => to_base64url(secret.0.as_slice()),
                Key::Device(device) => to_base64url(&*Zeroizing::new(device.to_bytes())),
                Key::Pair(secret) => to_base64url(Zeroizing::new(secret.to_bytes()).as_slice()),
                other => return Err(format!("A {} key is never kept.", other.kind())),
            };
            Ok(json!({ "kind": key.kind(), "raw": raw }))
        }
        // From the phone's secure storage, at launch.
        "key_restore" => {
            let Restore { kind, raw } = read(command, args)?;
            let raw = Zeroizing::new(from_base64url(&raw)?);
            let refuse = || format!("That is not a kept {kind} key.");
            match kind.as_str() {
                "account" => Ok(json!({ "key": hold(Key::Account(Secret::from_slice(&raw).ok_or_else(refuse)?)) })),
                "device" => {
                    let seed: [u8; 32] = raw.as_slice().try_into().map_err(|_| refuse())?;
                    let key = ed25519_dalek::SigningKey::from_bytes(&seed);
                    let public = device_public(&key);
                    Ok(json!({ "key": hold(Key::Device(key)), "public": public }))
                }
                "pair" => {
                    let secret = p256::SecretKey::from_slice(&raw).map_err(|_| refuse())?;
                    let public = to_base64url(&point_of(&secret));
                    Ok(json!({ "key": hold(Key::Pair(secret)), "public": public }))
                }
                _ => Err(format!("A {kind} key is never kept.")),
            }
        }
        "key_forget" => {
            let ByKey { key } = read(command, args)?;
            Ok(json!(with_table(|table| table.keys.remove(&key).is_some())))
        }
        // Signing out: every key this process holds.
        "keys_forget" => Ok(json!(with_table(|table| {
            let held = table.keys.len();
            table.keys.clear();
            held
        }))),
        _ => Err(format!("Ghost.md's core has no command named {command}.")),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A few rounds, for tests that are not about how many: fakeService.ts `FAST`.
    const FAST: u32 = 1_000;

    fn ask(command: &str, args: Value) -> Value {
        call(command, args).unwrap_or_else(|e| panic!("{command}: {e}"))
    }

    fn refused(command: &str, args: Value) -> String {
        call(command, args).expect_err(command)
    }

    fn handle(answer: &Value, field: &str) -> u64 {
        answer[field].as_u64().unwrap_or_else(|| panic!("no {field} in {answer}"))
    }

    fn derived(secret: &str, salt: &str) -> (String, u64) {
        let said = ask("derive", json!({"secret": secret, "salt": salt, "rounds": FAST}));
        (said["login"].as_str().unwrap().to_string(), handle(&said, "wrapKey"))
    }

    fn account() -> u64 {
        handle(&ask("account_key_new", json!({})), "key")
    }

    #[test]
    fn the_derivation_is_pbkdf2_as_the_standard_has_it() {
        for (secret, salt, rounds) in [("correct horse", "glyph/v1/matt", 1), ("correct horse", "glyph/v1/matt", 2), ("pässword ✓", "glyph/v1/recovery/sam", 1_000), ("", "", 3)] {
            let mut expected = [0u8; 64];
            pbkdf2::pbkdf2_hmac::<Sha256>(secret.as_bytes(), salt.as_bytes(), rounds, &mut expected);
            assert_eq!(derive_bytes(secret, salt, rounds, true).unwrap().as_slice(), expected.as_slice(), "{secret} {rounds}");
            assert_eq!(derive_bytes(secret, salt, rounds, false).unwrap().as_slice(), expected.as_slice(), "one thread, {secret} {rounds}");
        }
        assert!(derive_bytes("x", "y", 0, true).is_err());
    }

    // crypto.test.ts, "a secret".

    #[test]
    fn a_secret_becomes_a_login_half_and_a_wrap_key_the_same_every_time() {
        let salt_of = |handle: &str, kind: &str| ask("salt", json!({"handle": handle, "kind": kind})).as_str().unwrap().to_string();
        assert_eq!(salt_of("Matt", "password"), "glyph/v1/matt");
        assert_eq!(salt_of("  Matt\u{feff}\n", "password"), "glyph/v1/matt");
        assert_eq!(salt_of("Matt", "recovery"), "glyph/v1/recovery/matt");
        let (one, _) = derived("correct horse", &salt_of("Matt", "password"));
        let (two, _) = derived("correct horse", &salt_of("matt", "password"));
        assert!(one.len() == 64 && one.chars().all(|c| c.is_ascii_hexdigit() && !c.is_ascii_uppercase()));
        assert_eq!(one, two);
        // Another password, another handle, the recovery salt: each another login.
        assert_ne!(derived("correct horsf", "glyph/v1/matt").0, one);
        assert_ne!(derived("correct horse", "glyph/v1/sam").0, one);
        assert_ne!(derived("correct horse", "glyph/v1/recovery/matt").0, one);
    }

    #[test]
    fn a_wrap_key_only_wraps_and_is_never_kept() {
        let (_, wrap) = derived("correct horse", "glyph/v1/matt");
        assert_eq!(refused("seal", json!({"key": wrap, "context": "prefs", "text": "x"})), "A wrap key does not seal.");
        assert_eq!(refused("key_keep", json!({"key": wrap})), "A wrap key is never kept.");
        assert_eq!(refused("key_public", json!({"key": wrap})), "A wrap key has no public half.");
        assert_eq!(refused("account_key_wrap", json!({"key": wrap, "wrapKey": wrap})), "A wrap key is not the account key.");
    }

    // crypto.test.ts, "the account key".

    #[test]
    fn the_account_key_wraps_under_a_password_and_comes_back_only_under_the_same_one() {
        let key = account();
        let (_, right) = derived("correct horse", "glyph/v1/matt");
        let (_, wrong) = derived("wrong horse", "glyph/v1/matt");
        let wrapped = ask("account_key_wrap", json!({"key": key, "wrapKey": right}));
        let wrapped = wrapped.as_str().unwrap();
        assert!(wrapped.chars().all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_'));
        assert_eq!(from_base64url(wrapped).unwrap().len(), 12 + 32 + 16);

        let back = handle(&ask("account_key_unwrap", json!({"wrapped": wrapped, "wrapKey": right})), "key");
        let sealed = ask("seal", json!({"key": key, "context": "note:a", "value": {"words": "hello"}}));
        assert_eq!(ask("open", json!({"key": back, "context": "note:a", "blob": sealed})), json!({"words": "hello"}));

        assert_eq!(refused("account_key_unwrap", json!({"wrapped": wrapped, "wrapKey": wrong})), WRONG_SECRET);
        assert_eq!(refused("account_key_unwrap", json!({"wrapped": "AAAA", "wrapKey": right})), WRONG_SECRET);
        // The account key does not unwrap itself: only a derived half does.
        assert_eq!(refused("account_key_unwrap", json!({"wrapped": wrapped, "wrapKey": key})), "A account key does not wrap the account key.");
    }

    #[test]
    fn a_kept_account_key_comes_back_from_storage_as_the_same_key() {
        let key = account();
        let kept = ask("key_keep", json!({"key": key}));
        assert_eq!(kept["kind"], "account");
        assert_eq!(from_base64url(kept["raw"].as_str().unwrap()).unwrap().len(), 32);
        let again = handle(&ask("key_restore", kept), "key");
        assert_ne!(again, key);
        let sealed = ask("seal", json!({"key": key, "context": "prefs", "value": [1, 2, 3]}));
        assert_eq!(ask("open", json!({"key": again, "context": "prefs", "blob": sealed})), json!([1, 2, 3]));
        assert!(call("key_restore", json!({"kind": "account", "raw": "AAAA"})).is_err());
        assert_eq!(refused("key_restore", json!({"kind": "wrap", "raw": kept_raw_of(32)})), "A wrap key is never kept.");
    }

    fn kept_raw_of(bytes: usize) -> String {
        to_base64url(&vec![7u8; bytes])
    }

    // crypto.test.ts, "a sealed blob".

    #[test]
    fn a_sealed_blob_opens_only_under_its_own_key_and_its_own_context() {
        let (key, other) = (account(), account());
        let blob = ask("seal", json!({"key": key, "context": "note:one", "value": {"body": "# Weekend trip"}}));
        assert_eq!(refused("open", json!({"key": other, "context": "note:one", "blob": blob})), NOT_OPENED);
        assert_eq!(refused("open", json!({"key": key, "context": "note:two", "blob": blob})), NOT_OPENED);
        assert_eq!(ask("open", json!({"key": key, "context": "note:one", "blob": blob})), json!({"body": "# Weekend trip"}));
    }

    #[test]
    fn a_sealed_blob_never_repeats_itself_and_never_carries_its_words_in_the_clear() {
        let key = account();
        let seal = || ask("seal", json!({"key": key, "context": "note:a", "value": "the deposit is four hundred"})).as_str().unwrap().to_string();
        let (one, two) = (seal(), seal());
        assert_ne!(one, two);
        let bytes = from_base64url(&one).unwrap();
        assert_eq!(bytes[0], 1);
        assert!(!String::from_utf8_lossy(&bytes).contains("deposit"));
    }

    #[test]
    fn a_sealed_blob_is_refused_when_tampered_with_and_says_so_when_a_newer_app_sealed_it() {
        let key = account();
        let sealed = ask("seal", json!({"key": key, "context": "recording:a", "data": to_base64url(&[1, 2, 3, 4])}));
        let mut bytes = from_base64url(sealed.as_str().unwrap()).unwrap();
        assert_eq!(bytes.len(), 1 + 12 + 4 + 16);
        let last = bytes.len() - 1;
        bytes[last] ^= 1;
        assert_eq!(refused("open", json!({"key": key, "context": "recording:a", "blob": to_base64url(&bytes), "as": "data"})), NOT_OPENED);
        bytes[last] ^= 1;
        assert_eq!(ask("open", json!({"key": key, "context": "recording:a", "blob": to_base64url(&bytes), "as": "data"})), to_base64url(&[1, 2, 3, 4]));
        bytes[0] = 9;
        assert_eq!(refused("open", json!({"key": key, "context": "recording:a", "blob": to_base64url(&bytes), "as": "data"})), NEWER);
        assert_eq!(refused("open", json!({"key": key, "context": "recording:a", "blob": "", "as": "data"})), NEWER);
        assert_eq!(refused("open", json!({"key": key, "context": "recording:a", "blob": "AQID"})), NOT_OPENED);
    }

    #[test]
    fn a_sealed_blob_carries_bytes_of_any_size_text_as_it_is_and_nothing_at_all() {
        let key = account();
        let audio: Vec<u8> = (0..60_000u32).map(|i| (i * 37 + (i >> 8)) as u8).collect();
        let sealed = ask("seal", json!({"key": key, "context": "recording:a", "data": to_base64url(&audio)}));
        assert_eq!(ask("open", json!({"key": key, "context": "recording:a", "blob": sealed, "as": "data"})), to_base64url(&audio));
        // Text is sealed as written, so the app's own JSON is what the Mac parses.
        let text = "{\"v\":1,\"at\":1.0,\"words\":\"día ✓ 😀\"}";
        let sealed = ask("seal", json!({"key": key, "context": "prefs", "text": text}));
        assert_eq!(ask("open", json!({"key": key, "context": "prefs", "blob": sealed, "as": "text"})), text);
        let empty = ask("seal", json!({"key": key, "context": "prefs", "data": ""}));
        assert_eq!(ask("open", json!({"key": key, "context": "prefs", "blob": empty, "as": "data"})), "");
        assert_eq!(refused("seal", json!({"key": key, "context": "prefs", "text": "a", "value": 1})), "seal takes one of text, data and value.");
    }

    // crypto.test.ts, "recovery codes".

    #[test]
    fn recovery_codes_are_three_groups_of_four_from_an_alphabet_with_no_0_o_1_or_i() {
        for _ in 0..50 {
            let code = ask("recovery_code_new", json!({}));
            let code = code.as_str().unwrap();
            let groups: Vec<&str> = code.split('-').collect();
            assert!(groups.len() == 3 && groups.iter().all(|g| g.len() == 4 && g.bytes().all(|b| ALPHABET.contains(&b))), "{code}");
        }
        assert_eq!(ask("normalise_code", json!({"code": "abcd-efgh ijkl"})), "ABCDEFGHIJKL");
    }

    #[test]
    fn a_sheet_s_every_code_unwraps_the_account_key_typed_however_it_is_typed() {
        let key = account();
        let sheet = ask("recovery_sheet", json!({"handle": "Matt", "key": key, "rounds": FAST}));
        let codes: Vec<&str> = sheet["codes"].as_array().unwrap().iter().map(|c| c.as_str().unwrap()).collect();
        let entries = sheet["entries"].as_array().unwrap();
        assert_eq!((codes.len(), entries.len()), (CODES, CODES));
        assert_eq!(codes.iter().collect::<std::collections::HashSet<_>>().len(), CODES);
        let typed = codes[3].to_lowercase().replace('-', " ");
        let (login, wrap) = derived(&normalise_code(&typed), &salt("matt", true));
        assert_eq!(login, entries[3]["login"]);
        let back = handle(&ask("account_key_unwrap", json!({"wrapped": entries[3]["wrapped"], "wrapKey": wrap})), "key");
        let sealed = ask("seal", json!({"key": key, "context": "prefs", "value": "ok"}));
        assert_eq!(ask("open", json!({"key": back, "context": "prefs", "blob": sealed})), "ok");
        // Another code's wrap does not open under this one.
        assert_eq!(refused("account_key_unwrap", json!({"wrapped": entries[4]["wrapped"], "wrapKey": wrap})), WRONG_SECRET);
    }

    // crypto.test.ts, "the device key".

    #[test]
    fn the_device_key_signs_a_nonce_the_service_can_check_with_the_public_half() {
        use ed25519_dalek::Verifier as _;
        let made = ask("device_key_new", json!({}));
        let public: [u8; 32] = from_base64url(made["public"].as_str().unwrap()).unwrap().try_into().unwrap();
        let signature = ask("device_key_sign", json!({"key": made["key"], "nonce": "nonce-1"}));
        let signature: [u8; 64] = from_base64url(signature.as_str().unwrap()).unwrap().try_into().unwrap();
        let verifying = ed25519_dalek::VerifyingKey::from_bytes(&public).unwrap();
        assert!(verifying.verify(b"nonce-1", &ed25519_dalek::Signature::from_bytes(&signature)).is_ok());
        assert!(verifying.verify(b"nonce-2", &ed25519_dalek::Signature::from_bytes(&signature)).is_err());
        assert_eq!(ask("key_public", json!({"key": made["key"]})), made["public"]);
        // And the core's own check, which a service in memory is handed, says what dalek's said.
        let said = to_base64url(&signature);
        assert_eq!(ask("device_key_verify", json!({"public": made["public"], "nonce": "nonce-1", "signature": said})), json!(true));
        assert_eq!(ask("device_key_verify", json!({"public": made["public"], "nonce": "nonce-2", "signature": said})), json!(false));
        assert_eq!(ask("device_key_verify", json!({"public": "not a key", "nonce": "nonce-1", "signature": said})), json!(false));
        // Kept, restored: the same key signs the same.
        let again = ask("key_restore", ask("key_keep", json!({"key": made["key"]})));
        assert_eq!(again["public"], made["public"]);
        assert_eq!(ask("device_key_sign", json!({"key": again["key"], "nonce": "nonce-1"})), to_base64url(&signature));
        assert_eq!(refused("seal", json!({"key": made["key"], "context": "prefs", "text": "x"})), "A device key does not seal.");
    }

    // wrap.test.ts.

    #[test]
    fn an_organization_key_wraps_for_a_public_key_and_unwraps_with_its_private_half_bound_to_the_context() {
        let (sam, lee) = (ask("pair_new", json!({})), ask("pair_new", json!({})));
        assert_eq!(from_base64url(sam["public"].as_str().unwrap()).unwrap().len(), 65);
        let org = handle(&ask("org_key_new", json!({})), "key");
        let wrapped = ask("org_key_wrap", json!({"key": org, "public": sam["public"], "context": "org-key:org-1:1"}));
        assert_eq!(from_base64url(wrapped.as_str().unwrap()).unwrap().len(), 65 + 12 + 32 + 16);
        let back = handle(&ask("org_key_unwrap", json!({"pair": sam["key"], "wrapped": wrapped, "context": "org-key:org-1:1"})), "key");
        let sealed = ask("seal", json!({"key": org, "context": "org:org-1:note:n", "value": {"v": 1}}));
        assert_eq!(ask("open", json!({"key": back, "context": "org:org-1:note:n", "blob": sealed})), json!({"v": 1}));
        // Another member's key, another organization, another generation: none of them opens it.
        let not_theirs = "That wrap is not for this account, or not for this organization.";
        assert_eq!(refused("org_key_unwrap", json!({"pair": lee["key"], "wrapped": wrapped, "context": "org-key:org-1:1"})), not_theirs);
        assert_eq!(refused("org_key_unwrap", json!({"pair": sam["key"], "wrapped": wrapped, "context": "org-key:org-2:1"})), not_theirs);
        assert_eq!(refused("org_key_unwrap", json!({"pair": sam["key"], "wrapped": wrapped, "context": "org-key:org-1:2"})), not_theirs);
        assert_eq!(refused("org_key_unwrap", json!({"pair": sam["key"], "wrapped": "AAAA", "context": "org-key:org-1:1"})), BAD_WRAP);
        // Every wrap is fresh.
        assert_ne!(ask("org_key_wrap", json!({"key": org, "public": sam["public"], "context": "org-key:org-1:1"})), wrapped);
        // An organization's key lives in memory only.
        assert_eq!(refused("key_keep", json!({"key": org})), "A org key is never kept.");
        assert!(call("org_key_wrap", json!({"key": org, "public": "AAAA", "context": "c"})).is_err());
    }

    // wrap.test.ts and encKey.test.ts: the pair travels as its private half, sealed under the account key.

    #[test]
    fn the_pair_travels_to_another_device_sealed_under_the_account_key() {
        let key = account();
        let made = ask("pair_new", json!({}));
        let org = handle(&ask("org_key_new", json!({})), "key");
        let wrapped = ask("org_key_wrap", json!({"key": org, "public": made["public"], "context": "org-key:org-1:1"}));
        let sealed = ask("pair_seal", json!({"key": made["key"], "accountKey": key}));
        // The service holds ciphertext it cannot read: a JWK inside, and none of it outside.
        let jwk = ask("open", json!({"key": key, "context": "encryption-key", "blob": sealed}));
        assert_eq!((jwk["kty"].as_str(), jwk["crv"].as_str(), jwk["ext"].as_bool()), (Some("EC"), Some("P-256"), Some(true)));
        assert_eq!(jwk["key_ops"], json!(["deriveBits"]));
        for field in ["x", "y", "d"] {
            assert_eq!(from_base64url(jwk[field].as_str().unwrap()).unwrap().len(), 32, "{field}");
        }
        assert!(!sealed.as_str().unwrap().contains(jwk["d"].as_str().unwrap()));

        let elsewhere = ask("pair_open", json!({"sealed": sealed, "accountKey": key}));
        assert_eq!(elsewhere["public"], made["public"]);
        let back = handle(&ask("org_key_unwrap", json!({"pair": elsewhere["key"], "wrapped": wrapped, "context": "org-key:org-1:1"})), "key");
        let blob = ask("seal", json!({"key": org, "context": "live:org:org-1:presence", "data": "AQID"}));
        assert_eq!(ask("open", json!({"key": back, "context": "live:org:org-1:presence", "blob": blob, "as": "data"})), "AQID");
        // Kept in the phone's storage and read back at launch.
        let kept = ask("key_keep", json!({"key": made["key"]}));
        assert_eq!(kept["kind"], "pair");
        assert_eq!(ask("key_restore", kept)["public"], made["public"]);

        // Another account's key does not open it, and neither does a blob that is not a pair.
        assert_eq!(refused("pair_open", json!({"sealed": sealed, "accountKey": account()})), NOT_OPENED);
        let not_a_pair = ask("seal", json!({"key": key, "context": "encryption-key", "value": {"kty": "RSA"}}));
        assert_eq!(refused("pair_open", json!({"sealed": not_a_pair, "accountKey": key})), "That is not the account's encryption key.");
        // A JWK whose public half is not its private half's.
        let mut crossed = jwk.clone();
        crossed["x"] = jwk["y"].clone();
        let crossed = ask("seal", json!({"key": key, "context": "encryption-key", "value": crossed}));
        assert_eq!(refused("pair_open", json!({"sealed": crossed, "accountKey": key})), "That is not the account's encryption key.");
    }

    // crypto.test.ts "is kept non-extractable, and still seals and opens"; wrap.test.ts "is kept there
    // non-extractable".

    #[test]
    fn only_an_extractable_key_is_wrapped_or_exported_and_a_settled_one_still_seals() {
        let key = account();
        let (_, wrap) = derived("x", "glyph/v1/m");
        let kept = handle(&ask("key_settle", json!({"key": key})), "key");
        assert_ne!(kept, key);
        assert_eq!(handle(&ask("key_settle", json!({"key": kept})), "key"), kept, "settled already: itself");
        let sealed = ask("seal", json!({"key": key, "context": "prefs", "value": [1, 2, 3]}));
        assert_eq!(ask("open", json!({"key": kept, "context": "prefs", "blob": sealed})), json!([1, 2, 3]));
        let not_wrapped = "That account key is the copy a device keeps, and cannot be wrapped.";
        assert_eq!(refused("account_key_wrap", json!({"key": kept, "wrapKey": wrap})), not_wrapped);
        assert_eq!(refused("recovery_sheet", json!({"handle": "m", "key": kept, "rounds": FAST})), not_wrapped);
        // Unwrapped to be kept, and unwrapped to be wrapped again under a new password.
        let wrapped = ask("account_key_wrap", json!({"key": key, "wrapKey": wrap}));
        let plain = handle(&ask("account_key_unwrap", json!({"wrapped": wrapped, "wrapKey": wrap})), "key");
        assert_eq!(refused("account_key_wrap", json!({"key": plain, "wrapKey": wrap})), not_wrapped);
        let again = handle(&ask("account_key_unwrap", json!({"wrapped": wrapped, "wrapKey": wrap, "extractable": true})), "key");
        assert!(ask("account_key_wrap", json!({"key": again, "wrapKey": wrap})).is_string());
        // A key back from the phone's storage is a kept one.
        let restored = handle(&ask("key_restore", ask("key_keep", json!({"key": key}))), "key");
        assert_eq!(refused("account_key_wrap", json!({"key": restored, "wrapKey": wrap})), not_wrapped);

        // The pair: its private half leaves once, from the pair just made.
        let made = ask("pair_new", json!({}));
        let jwk = ask("pair_export_jwk", json!({"key": made["key"]}));
        assert_eq!((jwk["kty"].as_str(), jwk["crv"].as_str()), (Some("EC"), Some("P-256")));
        let elsewhere = ask("pair_import_jwk", json!({"jwk": jwk}));
        assert_eq!(elsewhere["public"], made["public"]);
        let settled = ask("key_settle", json!({"key": made["key"]}))["key"].clone();
        let not_exported = "That pair is the copy a device keeps: its private half cannot be exported.";
        for kept in [&elsewhere["key"], &settled] {
            assert_eq!(refused("pair_export_jwk", json!({"key": kept})), not_exported);
            assert_eq!(refused("pair_seal", json!({"key": kept, "accountKey": key})), not_exported);
            assert_eq!(ask("key_public", json!({"key": kept})), made["public"]);
        }
        assert_eq!(refused("pair_import_jwk", json!({"jwk": {"kty": "EC", "crv": "P-384", "d": jwk["d"]}})), "That is not the account's encryption key.");
        assert_eq!(handle(&ask("key_settle", json!({"key": wrap})), "key"), wrap, "nothing to settle: itself");
    }

    #[test]
    fn an_organization_key_crosses_as_bytes_where_the_web_s_does() {
        let sam = ask("pair_new", json!({}));
        let raw = to_base64url(&[9u8; 32]);
        let wrapped = ask("wrap_for", json!({"public": sam["public"], "raw": raw, "context": "org-key:org-1:1"}));
        assert_eq!(ask("unwrap_with", json!({"pair": sam["key"], "wrapped": wrapped, "context": "org-key:org-1:1"})), raw);
        // The same key by either road: what one seals, the other opens.
        let by_bytes = handle(&ask("seal_key_import", json!({"raw": raw})), "key");
        let by_handle = handle(&ask("org_key_unwrap", json!({"pair": sam["key"], "wrapped": wrapped, "context": "org-key:org-1:1"})), "key");
        let sealed = ask("seal", json!({"key": by_bytes, "context": "org:org-1:note:n", "text": "hello"}));
        assert_eq!(ask("open", json!({"key": by_handle, "context": "org:org-1:note:n", "blob": sealed, "as": "text"})), "hello");
        assert_eq!(refused("unwrap_with", json!({"pair": sam["key"], "wrapped": wrapped, "context": "org-key:org-1:2"})), "That wrap is not for this account, or not for this organization.");
        assert_eq!(refused("unwrap_with", json!({"pair": sam["key"], "wrapped": "AAAA", "context": "org-key:org-1:1"})), BAD_WRAP);
        assert_eq!(refused("seal_key_import", json!({"raw": "AAAA"})), "A key that seals is 32 bytes.");
        assert_eq!(refused("wrap_for", json!({"public": sam["public"], "raw": "AAAA", "context": "c"})), "An organization's key is 32 bytes.");
        // The whole digest, for whoever wants all of it.
        assert_eq!(from_base64url(ask("sha256", json!({"data": to_base64url(b"abc")})).as_str().unwrap()).unwrap()[..4], [0xba, 0x78, 0x16, 0xbf]);
    }

    #[test]
    fn a_share_is_its_json_alone_or_gsp1_with_its_pictures_after_the_words() {
        let key = ask("share_key_new", json!({}));
        let key = key.as_str().unwrap();
        assert_eq!(key.len(), 43);
        assert_eq!(ask("short_id", json!({})).as_str().unwrap().len(), 22);
        let shared = json!({"v": 1, "kind": "note", "title": "Trip", "pages": [{"title": "Trip", "body": "![](image/a.png)"}], "at": 1_759_000_000_000u64});
        let plain = ask("share_seal", json!({"key": key, "shared": shared}));
        let opened = ask("share_open", json!({"key": key, "blob": plain}));
        assert_eq!((&opened["shared"], &opened["pictures"]), (&shared, &json!([])));

        let png = b"\x89PNG\r\n\x1a\n picture".to_vec();
        let pictured = ask("share_seal", json!({"key": key, "shared": shared, "pictures": [["a.png", to_base64url(&png)], ["b-2.jpg", to_base64url(&[0xff, 0xd8, 0xff])]]}));
        let raw = open_bytes(&share_cipher(key).unwrap(), &from_base64url(pictured.as_str().unwrap()).unwrap(), SHARE).unwrap();
        assert_eq!(&raw[..4], b"GSP1");
        let length = u32::from_be_bytes(raw[4..8].try_into().unwrap()) as usize;
        let head: Value = serde_json::from_slice(&raw[8..8 + length]).unwrap();
        assert_eq!(head["pictures"], json!([["a.png", png.len()], ["b-2.jpg", 3]]));
        assert_eq!(&raw[8 + length..8 + length + png.len()], png.as_slice());
        let opened = ask("share_open", json!({"key": key, "blob": pictured}));
        assert_eq!(opened["shared"], shared);
        assert_eq!(opened["pictures"], json!([["a.png", to_base64url(&png)], ["b-2.jpg", to_base64url(&[0xff, 0xd8, 0xff])]]));

        // Another link's key; a note's ciphertext passed off as a share; a share from a newer app.
        let other = ask("share_key_new", json!({}));
        assert_eq!(refused("share_open", json!({"key": other, "blob": pictured})), NOT_OPENED);
        let newer = ask("share_seal", json!({"key": key, "shared": {"v": 2, "pages": []}}));
        assert_eq!(refused("share_open", json!({"key": key, "blob": newer})), NEWER_SHARE);
        assert_eq!(refused("share_open", json!({"key": "short", "blob": plain})), "That is not a share's key.");
        // A name that could reach outside the picture store is left out, and the ones after it still line up.
        let sly = seal_share(key, shared.as_object().unwrap(), &[("../x.png".to_string(), vec![1, 2]), ("ok.png".to_string(), vec![3, 4])]).unwrap();
        assert_eq!(ask("share_open", json!({"key": key, "blob": sly}))["pictures"], json!([["ok.png", to_base64url(&[3, 4])]]));
    }

    #[test]
    fn a_file_is_sealed_and_opened_where_it_lies_in_the_wire_s_own_layout() {
        let dir = crate::test_support::TempDir::new("crypto-files");
        let key = account();
        let wav: Vec<u8> = b"RIFF".iter().copied().chain((0..300_000u32).map(|i| (i * 31) as u8)).collect();
        std::fs::write(dir.join("n1.wav"), &wav).unwrap();
        let (plain, sealed, back) = (dir.join("n1.wav"), dir.join("out/n1.sealed"), dir.join("n1.back"));
        let said = ask("seal_file", json!({"key": key, "context": "file:r-n1", "path": plain, "out": sealed}));
        assert_eq!(said["bytes"].as_u64(), Some(wav.len() as u64 + 29));
        // The same bytes `seal` would have made: `open` reads the file's.
        let bytes = std::fs::read(&sealed).unwrap();
        assert_eq!(ask("open", json!({"key": key, "context": "file:r-n1", "blob": to_base64url(&bytes), "as": "data"})), to_base64url(&wav));
        assert_eq!(ask("open_file", json!({"key": key, "context": "file:r-n1", "path": sealed, "out": back}))["bytes"].as_u64(), Some(wav.len() as u64));
        assert_eq!(std::fs::read(&back).unwrap(), wav);
        // And what `seal` made, `open_file` opens.
        let blob = ask("seal", json!({"key": key, "context": "file:i-png-a", "data": to_base64url(b"\x89PNG")}));
        std::fs::write(dir.join("a.sealed"), from_base64url(blob.as_str().unwrap()).unwrap()).unwrap();
        ask("open_file", json!({"key": key, "context": "file:i-png-a", "path": dir.join("a.sealed"), "out": dir.join("a.png")}));
        assert_eq!(std::fs::read(dir.join("a.png")).unwrap(), b"\x89PNG");

        // The wrong file id, a changed byte, a newer version: nothing is written.
        let nothing = dir.join("nothing");
        assert_eq!(refused("open_file", json!({"key": key, "context": "file:r-n2", "path": sealed, "out": nothing})), NOT_OPENED);
        let mut changed = bytes.clone();
        changed[20] ^= 1;
        std::fs::write(dir.join("changed"), &changed).unwrap();
        assert_eq!(refused("open_file", json!({"key": key, "context": "file:r-n1", "path": dir.join("changed"), "out": nothing})), NOT_OPENED);
        changed[0] = 2;
        std::fs::write(dir.join("changed"), &changed).unwrap();
        assert_eq!(refused("open_file", json!({"key": key, "context": "file:r-n1", "path": dir.join("changed"), "out": nothing})), NEWER);
        assert!(!nothing.exists());
        assert!(refused("seal_file", json!({"key": key, "context": "c", "path": dir.join("gone"), "out": nothing})).contains("could not be read"));
        let left: Vec<_> = std::fs::read_dir(&*dir).unwrap().filter_map(|e| e.ok()).map(|e| e.file_name().to_string_lossy().into_owned()).filter(|name| name.ends_with(".part")).collect();
        assert!(left.is_empty(), "{left:?}");

        // A file's fingerprint is the first sixteen bytes of its SHA-256, read from the file or from bytes.
        let digest = ask("digest_file", json!({"path": plain}));
        assert_eq!(digest, ask("sha256_16", json!({"data": to_base64url(&wav)})));
        assert_eq!(digest.as_str().unwrap().len(), 32);
        assert_eq!(ask("digest_file", json!({"path": dir.join("gone")})), Value::Null);
        assert_eq!(sha256_16(b"abc"), "ba7816bf8f01cfea414140de5dae2223");
    }

    #[test]
    fn base64url_is_the_web_s_and_reads_either_alphabet() {
        let bytes: Vec<u8> = (0..=255u8).collect();
        let text = to_base64url(&bytes);
        assert!(!text.contains(['+', '/', '=']));
        assert_eq!(from_base64url(&text).unwrap(), bytes);
        assert_eq!(from_base64url(&base64::engine::general_purpose::STANDARD.encode(&bytes)).unwrap(), bytes);
        assert_eq!(from_base64url("YQ==").unwrap(), b"a");
        assert!(from_base64url("not base64!").is_err());
    }

    #[test]
    fn a_forgotten_key_is_gone_and_its_number_is_not_used_again() {
        let key = account();
        assert_eq!(ask("key_forget", json!({"key": key})), true);
        assert_eq!(ask("key_forget", json!({"key": key})), false);
        assert_eq!(refused("seal", json!({"key": key, "context": "prefs", "text": "x"})), "That key is not held any more.");
        assert!(account() > key);
        assert!(has("derive") && has("keys_forget") && !has("list_notes"));
        assert!(refused("derive", json!({"secret": "x"})).starts_with("invalid args for command `derive`: missing field `salt`"));
    }
}
