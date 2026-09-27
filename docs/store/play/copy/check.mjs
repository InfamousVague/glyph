// Reads the four copy files, counts the pasted blocks against Play's limits, the captions' words, and every line
// against the banned list. Prints the counts, then the hits. Exit code 1 when anything is over or banned.
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const read = (f) => readFileSync(join(here, f), 'utf8');
const files = { 'listing.md': read('listing.md'), 'whats-new.md': read('whats-new.md'), 'screenshots.md': read('screenshots.md'), 'feature-graphic.md': read('feature-graphic.md') };

const blocks = (text) => [...text.matchAll(/```\n([\s\S]*?)\n```/g)].map((m) => m[1]);
const cp = (s) => Array.from(s).length;
let bad = false;
const over = (label, s, limit) => {
  const n = cp(s);
  console.log(`${label}: ${n} characters (${s.length} UTF-16 units), limit ${limit}${n > limit ? '  OVER' : ''}`);
  if (n > limit) bad = true;
};

const listing = blocks(files['listing.md']);
over('App name', listing[0], 30);
over('App name, alternative', listing[1], 30);
over('Short description', listing[2], 80);
over('Short description, alternative', listing[3], 80);
over('Full description', listing[4], 4000);
const notes = blocks(files['whats-new.md']);
over('Release notes', notes[0], 500);

// Captions: the last cell of each table row that is not a heading or a rule.
for (const line of files['screenshots.md'].split('\n')) {
  if (!line.startsWith('|') || /^\|\s*(#|---)/.test(line)) continue;
  const cells = line.split('|').map((c) => c.trim()).filter(Boolean);
  const caption = cells[cells.length - 1];
  const words = caption.split(/\s+/).length;
  console.log(`Caption "${caption}": ${words} words${words > 7 ? '  OVER' : ''}`);
  if (words > 7) bad = true;
}
for (const m of files['screenshots.md'].matchAll(/\("([^"]+)"\)/g)) {
  const words = m[1].split(/\s+/).length;
  console.log(`Spare caption "${m[1]}": ${words} words${words > 7 ? '  OVER' : ''}`);
  if (words > 7) bad = true;
}

const banned = [
  /[–—]/, // en and em dashes
  /!/,
  /\?(\s|"|$)/, // a question asked, not a query string
  /\b(seamless|effortless|elevate|unlock|unleash|supercharge|game-changer|powerful|intuitive|robust|cutting-edge|next-level|leverage|empower|streamline|revolutionis?z?e|journey|dive in|look no further|imagine|best|ultimate|whether you're|in today's)\b/i,
  /^with ghost\.md,/im,
  /download now/i,
];
const emoji = /\p{Extended_Pictographic}/u;
const heat = /🔥🔥[^🔥]+🔥🔥/u;
for (const [name, text] of Object.entries(files)) {
  text.split('\n').forEach((line, i) => {
    for (const re of banned) if (re.test(line)) { console.log(`BANNED ${name}:${i + 1}: ${line.trim()}`); bad = true; }
    if (emoji.test(line.replace(heat, ''))) { console.log(`EMOJI ${name}:${i + 1}: ${line.trim()}`); bad = true; }
    if (/\bfrom\b[^.]*\bto\b/i.test(line)) console.log(`read: from…to ${name}:${i + 1}: ${line.trim().slice(0, 140)}`);
  });
}
console.log(bad ? 'Something to fix.' : 'Clean.');
process.exit(bad ? 1 : 0);
