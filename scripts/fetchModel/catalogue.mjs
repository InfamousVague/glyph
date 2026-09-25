/**
 * The model files scripts/fetch-model.mjs will put in `models/`: for each,
 * its name, its size and the SHA-256 its bytes must hash to.
 *
 * THE SAME TABLE LIVES IN RUST, and the Rust is the one that matters: the
 * whisper models in src-tauri/src/whisper/model.rs and the formatting models
 * in src-tauri/src/llm/model.rs are what the phone verifies its download
 * against. A hash changed in one and not the other is a model that passes the
 * tests here and is refused on the device, so catalogue.test.mjs reads both
 * Rust files and fails when a file, a size, a hash or a pinned revision here
 * is not the one there.
 *
 * Kept apart from fetch-model.mjs, which starts downloading the moment it is
 * run, so the test can import the table without fetching a byte.
 */

/** Where the whisper models come from: Hugging Face, the last of model.rs's MIRRORS. */
export const WHISPER_SOURCE = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

/** The whisper models, by the name fetch-model's first argument gives them. */
export const WHISPER = {
  base: {
    file: 'ggml-base.en-q5_1.bin',
    bytes: 59_721_011,
    sha256: '4baf70dd0d7c4247ba2b81fafd9c01005ac77c2f9ef064e00dcf195d0e2fdd2f',
  },
  small: {
    file: 'ggml-small.en-q5_1.bin',
    bytes: 190_098_681,
    sha256: 'bfdff4894dcb76bbf647d56263ea2a96645423f1669176f4844a1bf8e478ad30',
  },
};

/** The formatting models: id -> file, size, LFS hash, pinned source. */
export const LLM = {
  'qwen3.5-2b': {
    file: 'Qwen3.5-2B-Q4_K_M.gguf',
    bytes: 1_280_835_840,
    sha256: 'aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223',
    source: 'https://huggingface.co/unsloth/Qwen3.5-2B-GGUF/resolve/f6d5376be1edb4d416d56da11e5397a961aca8ae',
  },
  'qwen3.5-4b': {
    file: 'Qwen3.5-4B-Q4_K_M.gguf',
    bytes: 2_740_937_888,
    sha256: '00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4',
    source: 'https://huggingface.co/unsloth/Qwen3.5-4B-GGUF/resolve/e87f176479d0855a907a41277aca2f8ee7a09523',
  },
  'qwen3.5-9b': {
    file: 'Qwen3.5-9B-Q4_K_M.gguf',
    bytes: 5_680_522_464,
    sha256: '03b74727a860a56338e042c4420bb3f04b2fec5734175f4cb9fa853daf52b7e8',
    source: 'https://huggingface.co/unsloth/Qwen3.5-9B-GGUF/resolve/3885219b6810b007914f3a7950a8d1b469d598a5',
  },
  'gemma-4-e4b': {
    file: 'gemma-4-E4B-it-Q4_K_M.gguf',
    bytes: 4_977_171_584,
    sha256: '85a896a047553e842f25297ee5b031d64ff30147d9c4af17b1e4b394cd1fab87',
    source: 'https://huggingface.co/unsloth/gemma-4-E4B-it-GGUF/resolve/bfc15c382204943c3a8fff0c750b94ae2364d7a3',
  },
};

/** The formatting model `fetch-model llm` fetches: llm/model.rs's DEFAULT. */
export const LLM_DEFAULT = 'qwen3.5-4b';
