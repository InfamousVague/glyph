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
 * is a model that passes the tests and is refused on the device. This side's
 * copy is fetchModel/catalogue.mjs, and its test fails when the two differ.
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
import { createWriteStream, existsSync, mkdirSync, renameSync, rmSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { LLM, LLM_DEFAULT, WHISPER, WHISPER_SOURCE } from './fetchModel/catalogue.mjs';
import { sha256OfFile } from './lib/hash.mjs';
import { ROOT } from './lib/paths.mjs';
import { fatal, say } from './lib/say.mjs';

const MODELS = join(ROOT, 'models');
const megabytes = (bytes) => `${(bytes / 1_000_000).toFixed(1)} MB`;

/*
 * Downloads into `<file>.part` and renames only once the hash matches, so a
 * file at the real name is always a verified one - which is the same promise
 * model.rs makes on the phone, and the reason neither side ever has to hash a
 * model just to decide whether it is present.
 */
async function fetchModel({ file, bytes, sha256, source = WHISPER_SOURCE, dir = MODELS }) {
  const target = join(dir, file);
  if (existsSync(target)) {
    const actual = await sha256OfFile(target);
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
    fatal(`${url} answered ${response.status} ${response.statusText}`);
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
    fatal(`${file} arrived with SHA-256 ${actual} (${received} bytes); expected ${sha256} (${bytes} bytes)`);
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
    fatal(`unknown formatting model "${id}" - expected one of: ${Object.keys(LLM).join(', ')}, all`);
  }
  chosen = picked.map((model) => ({ ...model, dir: join(MODELS, 'llm') }));
} else {
  chosen = wanted === 'all' ? Object.values(WHISPER) : [WHISPER[wanted]];
  if (chosen.includes(undefined)) {
    fatal(`unknown model "${wanted}" - expected one of: ${Object.keys(WHISPER).join(', ')}, all, llm, llm:<id>`);
  }
}

for (const model of chosen) {
  mkdirSync(model.dir ?? MODELS, { recursive: true });
  await fetchModel(model);
}
