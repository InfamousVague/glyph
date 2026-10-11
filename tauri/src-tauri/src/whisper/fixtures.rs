//! What the model-bound whisper tests and the voice suite share: where the
//! models are, and macOS's `afconvert` turning an audio file into the 16 kHz
//! mono WAV the engine reads.

use std::path::{Path, PathBuf};
use std::process::Command;

/// The repository's `models/`, or `GLYPH_MODELS_DIR` - which is how the
/// benchmarks run from a test binary pushed to a phone, where the path this
/// crate was compiled at does not exist.
pub fn models_dir() -> PathBuf {
    std::env::var_os("GLYPH_MODELS_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|| Path::new(env!("CARGO_MANIFEST_DIR")).join("..").join("models"))
}

/// `input` written to `output` as 16 kHz mono 16-bit PCM by `afconvert`, or
/// why not: no `afconvert` here (it is macOS's), or a file it cannot read.
pub fn to_16k_mono_wav(input: &Path, output: &Path) -> Result<(), String> {
    let converted = Command::new("afconvert")
        .args(["-f", "WAVE", "-d", "LEI16@16000", "-c", "1"])
        .arg(input)
        .arg(output)
        .status()
        .map_err(|e| format!("afconvert: {e}"))?;
    if !converted.success() {
        return Err(format!("afconvert could not read {}", input.display()));
    }
    Ok(())
}
