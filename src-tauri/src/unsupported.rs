//! What iOS does not have, and the one way a command says so there.
//!
//! Cargo.toml builds none of whisper.cpp, llama.cpp, reqwest, sha2 or ring for
//! iOS (its `cfg(not(target_os = "ios"))` table), so on-device transcription,
//! formatting, update checks, the APK, Notion and link previews have nothing to
//! run on there. Their commands still EXIST on iOS, with the same signatures:
//! a page written against one surface is a page that needs no platform switch
//! to load (capture_commands.rs's header makes the argument). Each answers
//! with its sentence below instead of doing anything.
//!
//! The shape, the same in every seam: one statement at the top of the body,
//!
//! ```ignore
//! #[cfg(target_os = "ios")]
//! return on_ios(TRANSCRIPTION, (app, state));
//! ```
//!
//! and the real body under `#[cfg(not(target_os = "ios"))]`. The arguments go
//! into `on_ios` so a build that never reads them does not warn about them.
//! One function with the refusal inside it, rather than a second copy of the
//! whole command under `#[cfg]`: the signature is then written once, and an
//! iOS stub cannot drift from the real command's arguments. (notion.rs and
//! link_preview.rs were two copies each until this module.)
//!
//! A status that is an ANSWER rather than a refusal - "the model is not
//! present", "no models here" - is not this module's: `model_downloads`
//! answers those with `cfg!`, because both branches compile everywhere.
//!
//! The sentences are word for word what the page has always been sent. Nothing
//! on the page matches on them (rg, 2026-09-25), but a person reads them, and
//! the test below keeps them as they are.

/// The capture seam: live dictation, the refine pass, whisper's models.
pub const TRANSCRIPTION: &str = "On-device transcription is not supported on iOS yet.";

/// The formatting seam: the language models and their runs.
pub const FORMATTING: &str = "Formatting on the phone is not available on iOS yet.";

/// `ota_check`.
pub const UPDATES: &str = "Over-the-air updates are Android-only.";

/// `ota_fetch_apk`.
pub const APK: &str = "There is no APK on iOS.";

/// `notion_request`.
pub const NOTION: &str = "Notion is not available on iOS yet.";

/// `link_preview`.
pub const LINK_PREVIEWS: &str = "Link previews are not available on iOS yet.";

/// The refusal a command gives on iOS: `message`, as the error its `invoke`
/// rejects with. `_unused` takes the command's arguments, which iOS never reads.
pub fn on_ios<T>(message: &str, _unused: impl Sized) -> Result<T, String> {
    Err(message.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn each_refusal_is_the_sentence_the_page_has_always_had() {
        let refused = |message: &str| on_ios::<()>(message, ("app", "state")).unwrap_err();
        assert_eq!(refused(TRANSCRIPTION), "On-device transcription is not supported on iOS yet.");
        assert_eq!(refused(FORMATTING), "Formatting on the phone is not available on iOS yet.");
        assert_eq!(refused(UPDATES), "Over-the-air updates are Android-only.");
        assert_eq!(refused(APK), "There is no APK on iOS.");
        assert_eq!(refused(NOTION), "Notion is not available on iOS yet.");
        assert_eq!(refused(LINK_PREVIEWS), "Link previews are not available on iOS yet.");
    }
}
