// Counts docs/store/play/listing.md's pasted blocks against Play's limits and reads them for what the listing may not
// say: a third party's name, an em or en dash, an exclamation mark. Exit 1 on anything over or banned.
//   node docs/store/play/check.mjs
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const text = readFileSync(join(dirname(fileURLToPath(import.meta.url)), 'listing.md'), 'utf8');
const blocks = [...text.matchAll(/```\n([\s\S]*?)\n```/g)].map((m) => m[1]);
const fields = [['App name', 30], ['Short description', 80], ['Full description', 4000], ['Release notes', 500]];
const brands = /\b(claude|anthropic|notion|slack|github|google|figma|lovart|posthog|openai|gemini|mcp|chatgpt|gpt|elevenlabs|wear os|android|todoist|iphone|mac|windows)\b/i;
let bad = blocks.length !== fields.length;
if (bad) console.log(`Expected ${fields.length} blocks, found ${blocks.length}`);
fields.forEach(([label, limit], i) => {
  const s = blocks[i] ?? '';
  const over = s.length > limit || Array.from(s).length > limit;
  console.log(`${label}: ${s.length} / ${limit}${over ? '  OVER' : ''}`);
  if (over) bad = true;
  for (const line of s.split('\n')) {
    const hit = line.match(brands)?.[0] ?? (/[–—]/.test(line) ? 'dash' : /!/.test(line) ? '!' : null);
    if (hit) {
      console.log(`  ${label}: "${hit}" in: ${line.slice(0, 80)}`);
      bad = true;
    }
  }
});
process.exit(bad ? 1 : 0);
