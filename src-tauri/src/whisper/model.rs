//! whisper's model files: which ones exist, what their bytes must hash to, and
//! where they come from. Whether one is on this device, and the verified
//! download that puts it there, are `model_files`'s, which the formatting
//! models share.
//!
//! The hashes are Hugging Face's. Every file in ggerganov/whisper.cpp is a Git
//! LFS object, an LFS object id is the SHA-256 of the content, and these were
//! read from the repository's tree API on 2026-09-12 and confirmed against full
//! downloads the same day. `scripts/fetch-model.mjs` pins the same table; the
//! two must change together.

use crate::model_files::{mirrors, ModelSpec};

/// base.en, 5-bit quantised: 59.7 MB, and the default (DESIGN section 6.2).
///
/// English-only because OpenAI's model card says the `.en` models do better on
/// English, "especially for the tiny.en and base.en models", and a dictation
/// language setting is a later problem. q5_1 because it is 40% of the F16
/// file's 148 MB - a download a person will wait for on a phone - with the
/// accuracy measured in `whisper/tests.rs` rather than assumed.
pub const BASE_EN_Q5_1: ModelSpec = ModelSpec {
    file: "ggml-base.en-q5_1.bin",
    bytes: 59_721_011,
    sha256: "4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f",
};

/// small.en, 5-bit quantised: 190 MB. The candidate to switch to once the
/// phone has been measured - see the benchmark in `whisper/tests.rs` for what
/// it costs on the desktop.
pub const SMALL_EN_Q5_1: ModelSpec = ModelSpec {
    file: "ggml-small.en-q5_1.bin",
    bytes: 190_098_681,
    sha256: "bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30",
};

/// THE model the app captures with. Switching is this one line: the download,
/// the status, the load and the page all follow it.
pub const ACTIVE: ModelSpec = BASE_EN_Q5_1;

/// The model that improves a saved recording after Done (0.6.0), in the
/// background, where it does not have to keep up with speech.
///
/// Measured 2026-09-13 on 73 LibriSpeech dev-clean clips, clean and with pink
/// noise (`tests::accuracy`): small.en makes 6.1% / 7.0% word errors against
/// base.en's 10.0% / 11.0%. It cannot run live - on the arm64 emulator it
/// streams at 0.21x real time - but a 59 s recording takes it 11.9 s there.
/// large-v3-turbo scored 3.6% and took 54 s for the same minute; medium.en
/// was no better than small at three times the cost.
pub const REFINE: ModelSpec = SMALL_EN_Q5_1;

/// Where models are fetched from, in order.
///
/// attack.fm first because it is ours: it cannot rename a file, rate-limit a
/// phone, or go down with somebody else's outage, and it is what the upload
/// from `models/` populates. Hugging Face second, because until that upload
/// has happened (and whenever attack.fm is unreachable) a first launch should
/// still be able to dictate. The hash is checked either way, so the order is
/// about reliability, never about trust.
pub const MIRRORS: [&str; 2] = [
    "https://attack.fm/glyph/models",
    "https://huggingface.co/ggerganov/whisper.cpp/resolve/main",
];

/// The mirrors to try, most preferred first: any that a signed update manifest
/// has moved the app to, then the compiled-in [`MIRRORS`], without repeats.
///
/// Passed INTO `model_files::fetch` rather than read from inside it, because it
/// takes no Tauri types (the capture service may drive it with no Tauri
/// runtime) and the moved mirrors live in the OTA layer's state. The compiled
/// list is always appended, never replaced: if the domain Glyph moved to dies
/// too, the one the APK shipped with is still tried, and Hugging Face after it.
/// Moving a mirror cannot weaken anything - the SHA-256 stays pinned in this
/// binary, so a mirror only ever decides where bytes come from, never which
/// bytes are accepted.
pub fn mirrors_with(preferred: &[String]) -> Vec<String> {
    mirrors(preferred, MIRRORS)
}

#[cfg(test)]
mod mirror_tests {
    use super::*;

    #[test]
    fn with_nothing_moved_it_is_the_compiled_list() {
        assert_eq!(mirrors_with(&[]), MIRRORS.map(String::from).to_vec());
    }

    #[test]
    fn moved_mirrors_come_first_and_the_compiled_ones_are_never_dropped() {
        let moved = vec!["https://glyph.example/models/".to_string(), MIRRORS[0].to_string()];
        let all = mirrors_with(&moved);
        assert_eq!(all[0], "https://glyph.example/models", "trailing slash trimmed, moved mirror first");
        assert_eq!(all.len(), 3, "the compiled attack.fm mirror is not repeated: {all:?}");
        assert!(MIRRORS.iter().all(|m| all.iter().any(|a| a == m)), "every compiled mirror stays: {all:?}");
    }
}
