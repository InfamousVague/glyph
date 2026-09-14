#!/usr/bin/env node
/**
 * Puts the whisper models in `models/`, byte-for-byte the files the app will
 * accept.
 *
 * Three callers, one file. `cargo test` reads `models/` for the transcription
 * tests and the benchmark; the model upload to attack.fm/glyph/models/ is made
 * FROM `models/`, so what the phone downloads is what was verified here; and a
 * desktop `tauri dev` can be pointed at the same bytes rather than fetching
 * them a second time.
 *
 * The hashes are Hugging Face's, not ours. Every file in
 * huggingface.co/ggerganov/whisper.cpp is a Git LFS object, and an LFS object
 * id IS the SHA-256 of the content - read from the repository's tree API
 * (`/api/models/ggerganov/whisper.cpp/tree/main`, field `lfs.oid`) on
 * 2026-09-12 and confirmed against a full download over HTTPS the same day.
 * They are pinned rather than fetched at run time on purpose: a checksum read
 * from the same server as the file only proves the server agrees with itself.
 *
 * THE SAME TABLE LIVES IN src-tauri/src/whisper/model.rs, which is what the
 * phone verifies its download against. A hash changed in one and not the other
 * is a model that passes the tests and is refused on the device.
 *
 * An existing file is re-hashed rather than trusted by its size, because this
 * script is also the last check before an upload, and a truncated-then-padded
 * file or a model swapped by hand has the right size and the wrong bytes.
 *
 * The formatting models (0.9.0) go in `models/llm/`, from the same table
 * src-tauri/src/llm/model.rs pins: Hugging Face at a fixed revision, the LFS
 * object id as the hash. `cargo test --lib llm::tests` reads them from there.
 *
 * Usage:
 *   node scripts/fetch-model.mjs          # base.en-q5_1, the app's default
 *   node scripts/fetch-model.mjs small    # small.en-q5_1, the one to measure against
 *   node scripts/fetch-model.mjs all      # every whisper model
 *   node scripts/fetch-model.mjs llm      # the default formatting model (Qwen3.5 4B)
 *   node scripts/fetch-model.mjs llm:qwen3.5-9b   # one formatting model by id
 *   node scripts/fetch-model.mjs llm:all
 */
import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream, existsSync, mkdirSync, renameSync, rmSync, statSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { fileURLToPath } from 'node:url';

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const MODELS = join(ROOT, 'models');
const SOURCE = 'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';

const CATALOGUE = {
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
const LLM = {
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
const LLM_DEFAULT = 'qwen3.5-4b';

const say = (line) => console.log(`  ${line}`);
const fail = (message) => {
  console.error(`\nError: ${message}\n`);
  process.exit(1);
};
const megabytes = (bytes) => `${(bytes / 1_000_000).toFixed(1)} MB`;

async function sha256Of(path) {
  const hash = createHash('sha256');
  await pipeline(createReadStream(path), hash);
  return hash.digest('hex');
}

/*
 * Downloads into `<file>.part` and renames only once the hash matches, so a
 * file at the real name is always a verified one - which is the same promise
 * model.rs makes on the phone, and the reason neither side ever has to hash a
 * model just to decide whether it is present.
 */
async function fetchModel({ file, bytes, sha256, source = SOURCE, dir = MODELS }) {
  const target = join(dir, file);
  if (existsSync(target)) {
    const actual = await sha256Of(target);
    if (actual === sha256) {
      say(`${file}: present and verified (${megabytes(bytes)})`);
      return;
    }
    say(`${file}: present but its SHA-256 is ${actual}, not ${sha256} - fetching again`);
    rmSync(target);
  }

  const url = `${source}/${file}`;
  say(`${file}: fetching ${megabytes(bytes)} from ${url}`);
  const response = await fetch(url, { redirect: 'follow' });
  if (!response.ok || response.body == null) {
    fail(`${url} answered ${response.status} ${response.statusText}`);
  }

  const part = `${target}.part`;
  const hash = createHash('sha256');
  let received = 0;
  let lastShown = 0;
  const counted = Readable.fromWeb(response.body).map((chunk) => {
    hash.update(chunk);
    received += chunk.length;
    // A line per 10%, not a line per chunk: this runs in CI logs and terminals
    // alike, and 12,000 progress lines is a log nobody reads.
    if (received - lastShown >= bytes / 10 || received === bytes) {
      lastShown = received;
      say(`  ${megabytes(received)} of ${megabytes(bytes)}`);
    }
    return chunk;
  });
  await pipeline(counted, createWriteStream(part));

  const actual = hash.digest('hex');
  if (actual !== sha256 || statSync(part).size !== bytes) {
    rmSync(part, { force: true });
    fail(`${file} arrived with SHA-256 ${actual} (${received} bytes); expected ${sha256} (${bytes} bytes)`);
  }
  renameSync(part, target);
  say(`${file}: verified ${sha256}`);
}

const wanted = process.argv[2] ?? 'base';
let chosen;
if (wanted === 'llm' || wanted.startsWith('llm:')) {
  const id = wanted === 'llm' ? LLM_DEFAULT : wanted.slice(4);
  const picked = id === 'all' ? Object.values(LLM) : [LLM[id]];
  if (picked.includes(undefined)) {
    fail(`unknown formatting model "${id}" - expected one of: ${Object.keys(LLM).join(', ')}, all`);
  }
  chosen = picked.map((model) => ({ ...model, dir: join(MODELS, 'llm') }));
} else {
  chosen = wanted === 'all' ? Object.values(CATALOGUE) : [CATALOGUE[wanted]];
  if (chosen.includes(undefined)) {
    fail(`unknown model "${wanted}" - expected one of: ${Object.keys(CATALOGUE).join(', ')}, all, llm, llm:<id>`);
  }
}

for (const model of chosen) {
  mkdirSync(model.dir ?? MODELS, { recursive: true });
  await fetchModel(model);
}
