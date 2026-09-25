//! What a device sends to prove who it is, checked and made ready to keep: a handle, a login half, a wrapped key, a
//! recovery sheet - and the hashes the service keeps in their place.
//!
//! None of these is a password. A device derives a login half from the password (and one from each recovery code)
//! and sends only that, so what is hashed here is already 32 random-looking bytes, and nothing the service keeps can
//! unwrap the account key (docs/SYNC.md). The rules are pure, and the refusals are the words the app shows.

use super::RECOVERY_CODES;
use crate::wire::{base64url, error};
use argon2::password_hash::{rand_core::OsRng, PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use axum::http::StatusCode;
use axum::response::Response;
use serde::Deserialize;
use sha2::Digest;

/// A wrapped key is a few dozen bytes of base64; this is a ceiling on a mistake, not on anything real.
const WRAPPED_LIMIT: usize = 512;

/// What a device is called when it did not say: a sign-up's first device, or one added later.
const DEVICE_LABEL: &str = "device";

/// AttackFM's handle rule: 3 to 24 letters, digits, `.`, `_` or `-`, starting with a letter or digit.
pub fn valid_handle(handle: &str) -> bool {
    let n = handle.chars().count();
    (3..=24).contains(&n)
        && handle.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-' | '.'))
        && handle.chars().next().is_some_and(|c| c.is_ascii_alphanumeric())
}

/// A login half is 32 bytes a device derived, as 64 hex characters. Anything else is not one.
pub fn valid_login(login: &str) -> bool {
    login.len() == 64 && login.bytes().all(|b| b.is_ascii_hexdigit())
}

pub fn valid_wrapped(wrapped: &str) -> bool {
    base64url(wrapped, 1..=WRAPPED_LIMIT)
}

/// A device's label as it is kept: the one it gave, trimmed, or `DEVICE_LABEL` when it gave none.
pub fn device_label(label: &str) -> &str {
    let label = label.trim();
    if label.is_empty() {
        DEVICE_LABEL
    } else {
        label
    }
}

/// A login half's Argon2 hash, as AttackFM hashes a password. Hex is taken in either case.
pub fn hash_login(login: &str) -> Result<String, Response> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(login.to_lowercase().as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|_| error(StatusCode::INTERNAL_SERVER_ERROR, "Could not store that password."))
}

/// Whether `login` is the half `hash` was made from. An empty hash - an account with no password - matches nothing.
pub fn verify_login(login: &str, hash: &str) -> bool {
    !hash.is_empty()
        && PasswordHash::new(hash).map(|parsed| Argon2::default().verify_password(login.to_lowercase().as_bytes(), &parsed).is_ok()).unwrap_or(false)
}

/// A recovery code's login half, as it is kept: SHA-256. The half is already 32 random-looking bytes, so a fast hash
/// is enough, and it can be looked up directly.
pub fn hash_code(login: &str) -> String {
    sha2::Sha256::digest(login.to_lowercase().as_bytes()).iter().map(|b| format!("{b:02x}")).collect()
}

/// One code of a recovery sheet as a device sends it: the code's login half, and the account key wrapped under it.
#[derive(Deserialize)]
pub struct CodeBody {
    login: String,
    wrapped: String,
}

/// A recovery sheet, checked and made ready to store: eight codes, each a login half and a wrapped key.
pub fn sheet(codes: &[CodeBody]) -> Result<Vec<(String, String)>, Response> {
    if codes.len() != RECOVERY_CODES {
        return Err(error(StatusCode::BAD_REQUEST, "A recovery sheet is eight codes."));
    }
    codes
        .iter()
        .map(|code| {
            if valid_login(&code.login) && valid_wrapped(&code.wrapped) {
                Ok((hash_code(&code.login), code.wrapped.clone()))
            } else {
                Err(error(StatusCode::BAD_REQUEST, "A recovery code could not be read."))
            }
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::test_support::{login, wrapped};

    fn code(login: String, wrapped: String) -> CodeBody {
        CodeBody { login, wrapped }
    }

    #[test]
    fn a_handle_is_three_to_twenty_four_plain_characters_starting_with_one_that_is_not_punctuation() {
        for ok in ["sam", "matt.w", "m_2-x", "a".repeat(24).as_str(), "9lives"] {
            assert!(valid_handle(ok), "{ok}");
        }
        for no in ["ab", &"a".repeat(25), ".matt", "_matt", "-matt", "matt w", "mätt", "matt/x", ""] {
            assert!(!valid_handle(no), "{no}");
        }
    }

    #[test]
    fn a_login_half_is_sixty_four_hex_characters_and_nothing_else() {
        assert!(valid_login(&login(1)));
        assert!(valid_login(&"AB".repeat(32)), "hex in either case");
        assert!(!valid_login(&"a".repeat(63)));
        assert!(!valid_login(&"g".repeat(64)));
        assert!(!valid_login("hunter2"), "a password itself is never what arrives");
    }

    #[test]
    fn a_device_without_a_label_is_called_a_device() {
        assert_eq!(device_label("  phone "), "phone");
        assert_eq!(device_label(""), "device");
        assert_eq!(device_label("   "), "device");
    }

    #[test]
    fn a_login_hash_checks_the_half_it_was_made_from_in_either_case_and_an_empty_one_checks_nothing() {
        let hash = hash_login(&"ab".repeat(32)).unwrap();
        assert!(hash.starts_with("$argon2"), "{hash}");
        assert!(verify_login(&"ab".repeat(32), &hash));
        assert!(verify_login(&"AB".repeat(32), &hash), "a device may send its hex in capitals");
        assert!(!verify_login(&"cd".repeat(32), &hash));
        assert!(!verify_login(&"ab".repeat(32), ""), "an account with no password has none to match");
        assert!(!verify_login(&"ab".repeat(32), "not a hash"));
    }

    #[test]
    fn a_recovery_code_is_kept_as_the_sha_256_of_its_login_half_in_lower_case() {
        let half = "AB".repeat(32);
        assert_eq!(hash_code(&half), hash_code(&half.to_lowercase()));
        assert_eq!(hash_code(&half).len(), 64);
        // SHA-256 of the empty string, so the digest is really SHA-256 and not some other 32 bytes.
        assert_eq!(hash_code(""), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    }

    #[test]
    fn a_sheet_is_eight_readable_codes_kept_as_hash_and_wrapped_key() {
        let whole: Vec<CodeBody> = (0..RECOVERY_CODES).map(|i| code(login(100 + i as u8), wrapped(&format!("code{i}")))).collect();
        let kept = sheet(&whole).unwrap_or_else(|_| panic!("a whole sheet is kept"));
        assert_eq!(kept.len(), RECOVERY_CODES);
        assert_eq!(kept[3], (hash_code(&login(103)), wrapped("code3")), "each code in its place on the sheet");

        assert!(sheet(&whole[..7]).is_err(), "seven codes are not a sheet");
        let mut spoiled: Vec<CodeBody> = (0..RECOVERY_CODES).map(|i| code(login(100 + i as u8), wrapped("w"))).collect();
        spoiled[5] = code("hunter2".into(), wrapped("w"));
        assert!(sheet(&spoiled).is_err(), "one unreadable code spoils the sheet");
    }
}
