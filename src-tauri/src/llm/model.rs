//! Which language models can format notes, and where their bytes come from.
//!
//! The same promise as `whisper::model`: a file at a model's real name has
//! been verified, because the only writer is `whisper::model::fetch`, which
//! hashes as it downloads and renames on a match.
//!
//! Several models rather than one, chosen in Settings, because the right
//! trade is the phone's to make: a 2B answers in seconds and misses things, a
//! 9B is careful and takes minutes and 5.7 GB. The page carries the names and
//! the descriptions; this is the part that has to be right byte for byte.
//!
//! Every hash is the Git LFS object id read from the repository's tree API on
//! 2026-09-13 (an LFS id IS the SHA-256 of the content), and every Hugging
//! Face mirror is pinned to the revision it was read at, so a later push to
//! that repository cannot turn a verified download into a failed one. All four
//! are Apache-2.0.

use crate::whisper::model::ModelSpec;

/// One model the phone can format with.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LlmSpec {
    /// The page's name for it, stable: it is what a preference stores.
    pub id: &'static str,
    pub spec: ModelSpec,
    /// The Hugging Face repository, at the revision the hash was read.
    pub hugging_face: &'static str,
}

/// Qwen3.5 2B Instruct, Q4_K_M: 1.28 GB. The quick one, and the one the arm64
/// emulator (2.5 GB of RAM) can run. Measured in 0.4.x as the smallest model
/// that followed instructions without inventing; it still shortens.
pub const QWEN3_5_2B: LlmSpec = LlmSpec {
    id: "qwen3.5-2b",
    spec: ModelSpec {
        file: "Qwen3.5-2B-Q4_K_M.gguf",
        bytes: 1_280_835_840,
        sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223",
    },
    hugging_face: "https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae",
};

/// Qwen3.5 4B Instruct, Q4_K_M: 2.74 GB. The default: careful enough to
/// keep every fact, small enough for any recent phone.
pub const QWEN3_5_4B: LlmSpec = LlmSpec {
    id: "qwen3.5-4b",
    spec: ModelSpec {
        file: "Qwen3.5-4B-Q4_K_M.gguf",
        bytes: 2_740_937_888,
        sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4",
    },
    hugging_face: "https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523",
};

/// Qwen3.5 9B Instruct, Q4_K_M: 5.68 GB. The best of the four and the
/// slowest; wants 12 GB of RAM (the Fold has it).
pub const QWEN3_5_9B: LlmSpec = LlmSpec {
    id: "qwen3.5-9b",
    spec: ModelSpec {
        file: "Qwen3.5-9B-Q4_K_M.gguf",
        bytes: 5_680_522_464,
        sha256: "03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8",
    },
    hugging_face: "https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/3885219b6810b007914f3a7950a8d1b469d598a5",
};

/// Gemma 4 E4B, Q4_K_M: 4.98 GB. A different family with a different voice:
/// runs like a 4B (its per-layer embeddings are what make the file big).
pub const GEMMA_4_E4B: LlmSpec = LlmSpec {
    id: "gemma-4-e4b",
    spec: ModelSpec {
        file: "gemma-4-E4B-it-Q4_K_M.gguf",
        bytes: 4_977_171_584,
        sha256: "85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87",
    },
    hugging_face: "https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/bfc15c382204943c3a8fff0c750b94ae2364d7a3",
};

/// Every model the app offers, in the order Settings lists them.
pub const CATALOGUE: [LlmSpec; 4] = [QWEN3_5_2B, QWEN3_5_4B, QWEN3_5_9B, GEMMA_4_E4B];

/// The one a fresh install formats with, until Settings says otherwise.
pub const DEFAULT: LlmSpec = QWEN3_5_4B;

/// Our own mirror, the same directory as whisper's models.
const OURS: &str = "https://attack.fm/glyph/models";

/// The model with this id, if the app knows it.
pub fn find(id: &str) -> Option<&'static LlmSpec> {
    CATALOGUE.iter().find(|m| m.id == id)
}

/// Where `model` is fetched from, most preferred first: any mirror a signed
/// update manifest has moved the app to, then attack.fm, then Hugging Face at
/// the pinned revision. The hash is checked either way, so the order is about
/// reliability, never about trust. Hugging Face is always last and always
/// present: a model too big for our box to carry is still fetchable.
pub fn mirrors_with(model: &LlmSpec, preferred: &[String]) -> Vec<String> {
    let mut all: Vec<String> = Vec::new();
    for mirror in preferred.iter().map(String::as_str).chain([OURS, model.hugging_face]) {
        let mirror = mirror.trim_end_matches('/');
        if !mirror.is_empty() && !all.iter().any(|seen| seen == mirror) {
            all.push(mirror.to_string());
        }
    }
    all
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ids_are_unique_and_the_default_is_in_the_catalogue() {
        for (i, a) in CATALOGUE.iter().enumerate() {
            for b in &CATALOGUE[i + 1..] {
                assert_ne!(a.id, b.id);
                assert_ne!(a.spec.file, b.spec.file);
            }
        }
        assert_eq!(find(DEFAULT.id), Some(&DEFAULT));
        assert_eq!(find("gpt-4"), None);
    }

    #[test]
    fn a_moved_mirror_comes_first_and_hugging_face_stays_pinned_and_last() {
        let mirrors = mirrors_with(&QWEN3_5_4B, &["https://notes.example/glyph/models/".to_string()]);
        assert_eq!(mirrors[0], "https://notes.example/glyph/models");
        assert_eq!(mirrors[1], OURS);
        assert!(mirrors[2].contains("/resolve/e87f1764"), "{mirrors:?}");
        assert_eq!(mirrors.len(), 3);
        assert_eq!(mirrors_with(&QWEN3_5_4B, &[OURS.to_string()]).len(), 2, "no repeats");
    }
}
