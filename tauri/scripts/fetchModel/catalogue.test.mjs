// @vitest-environment node
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import { ROOT } from '../lib/paths.mjs';
import { LLM, LLM_DEFAULT, WHISPER, WHISPER_SOURCE } from './catalogue.mjs';

/*
 * "THE SAME TABLE LIVES IN src-tauri/src/whisper/model.rs" - fetch-model.mjs
 * has said so since it was written, and nothing checked it. These read the
 * two Rust files as text (they are the truth: the phone verifies against
 * them) and hold the scripts' copy to them, both ways, so a model added,
 * dropped or re-hashed on one side only fails here rather than on a phone.
 */

const WHISPER_RS = join(ROOT, 'src-tauri/src/whisper/model.rs');
const LLM_RS = join(ROOT, 'src-tauri/src/llm/model.rs');

const number = (digits) => Number(digits.replaceAll('_', ''));

/** Every `ModelSpec { file, bytes, sha256 }` literal in a Rust source, by file name. */
function modelSpecs(rust) {
  const specs = new Map();
  const literal = /ModelSpec\s*\{\s*file:\s*"([^"]+)",\s*bytes:\s*([\d_]+),\s*sha256:\s*"([^"]+)",?\s*\}/g;
  for (const [, file, bytes, sha256] of rust.matchAll(literal)) specs.set(file, { file, bytes: number(bytes), sha256 });
  return specs;
}

/** Every `LlmSpec { id, spec: ModelSpec {...}, hugging_face }` constant in a Rust source, by id, with its constant's name. */
function llmSpecs(rust) {
  const specs = new Map();
  const literal =
    /pub const (\w+): LlmSpec = LlmSpec\s*\{\s*id:\s*"([^"]+)",\s*spec:\s*ModelSpec\s*\{\s*file:\s*"([^"]+)",\s*bytes:\s*([\d_]+),\s*sha256:\s*"([^"]+)",?\s*\},\s*hugging_face:\s*"([^"]+)",?\s*\}/g;
  for (const [, name, id, file, bytes, sha256, huggingFace] of rust.matchAll(literal)) {
    specs.set(id, { name, file, bytes: number(bytes), sha256, source: huggingFace });
  }
  return specs;
}

/** What differs between the scripts' models and the Rust's, keyed the same way, as sentences; empty when they agree. */
function differences(ours, theirs, fields) {
  const found = [];
  for (const key of ours.keys()) if (!theirs.has(key)) found.push(`${key} is in the scripts' table and not the Rust`);
  for (const key of theirs.keys()) if (!ours.has(key)) found.push(`${key} is in the Rust and not the scripts' table`);
  for (const [key, mine] of ours) {
    const rust = theirs.get(key);
    if (!rust) continue;
    for (const field of fields) if (mine[field] !== rust[field]) found.push(`${key}: ${field} is ${mine[field]} here and ${rust[field]} in the Rust`);
  }
  return found;
}

const byFile = (models) => new Map(Object.values(models).map((m) => [m.file, m]));

describe('the model catalogue fetch-model pins', () => {
  const whisperRs = readFileSync(WHISPER_RS, 'utf8');
  const llmRs = readFileSync(LLM_RS, 'utf8');

  it('is the whisper table in src-tauri/src/whisper/model.rs: every file, size and hash', () => {
    const rust = modelSpecs(whisperRs);
    expect(rust.size).toBeGreaterThan(0);
    expect(differences(byFile(WHISPER), rust, ['bytes', 'sha256'])).toEqual([]);
  });

  it('fetches whisper models from a mirror the app itself trusts', () => {
    const mirrors = /pub const MIRRORS: \[&str; \d+\] = \[([^\]]*)\]/.exec(whisperRs)?.[1] ?? '';
    expect([...mirrors.matchAll(/"([^"]+)"/g)].map((m) => m[1])).toContain(WHISPER_SOURCE);
  });

  it('is the formatting-model table in src-tauri/src/llm/model.rs: every id, file, size, hash and pinned revision', () => {
    const rust = llmSpecs(llmRs);
    expect(rust.size).toBeGreaterThan(0);
    expect(differences(new Map(Object.entries(LLM)), rust, ['file', 'bytes', 'sha256', 'source'])).toEqual([]);
  });

  it('fetches the formatting model the app formats with by default', () => {
    const name = /pub const DEFAULT: LlmSpec = (\w+);/.exec(llmRs)?.[1];
    const byName = new Map([...llmSpecs(llmRs).values()].map((spec) => [spec.name, spec]));
    expect(name).toBeTruthy();
    expect(LLM[LLM_DEFAULT].file).toBe(byName.get(name)?.file);
  });

  it('can tell: a hash changed on one side, or a model dropped from one, is reported by name', () => {
    const whisper = modelSpecs(whisperRs);
    const [first] = whisper.values();
    const drifted = modelSpecs(whisperRs.replace(first.sha256, '0'.repeat(64)));
    expect(differences(whisper, drifted, ['bytes', 'sha256'])).toEqual([
      `${first.file}: sha256 is ${first.sha256} here and ${'0'.repeat(64)} in the Rust`,
    ]);
    const llm = llmSpecs(llmRs);
    const last = [...llm.values()].at(-1);
    const dropped = llmSpecs(llmRs.replace(new RegExp(`pub const ${last.name}: LlmSpec[\\s\\S]*?\\n\\};\\n`), ''));
    const id = [...llm.keys()].at(-1);
    expect(differences(llm, dropped, ['file'])).toEqual([`${id} is in the scripts' table and not the Rust`]);
  });
});
