// node test/academy/fixtures/web_lessons.mjs   (the web dev server already running on 127.0.0.1:5279, read-only)
//
// Reads the web app's own academy/lessons.ts as its page runs it (dev server, read-only) and writes:
//   test/academy/fixtures/web_lessons.json  - every lesson's words, the chapters, the cheat sheet's rows with the
//     Marks plugin on and off, and what every lesson's check answers for every text of a corpus (each lesson's own
//     example and every text lessons.test.ts tries)
//   lib/academy/lessons.g.dart              - the words as Dart
import { chromium } from '/Users/matt/.npm/_npx/e41f203b7505f1fb/node_modules/playwright/index.mjs';
import { readFileSync, writeFileSync } from 'node:fs';

const BASE = 'http://127.0.0.1:5279/';
const FLUTTER = '/Users/matt/Development/Apps/ghost-flutter/';
const testSource = readFileSync('/Users/matt/Development/Apps/glyph/src/app/academy/lessons.test.ts', 'utf8');
const tried = [...testSource.matchAll(/passes\('(\w+)', ('(?:[^'\\]|\\.)*')\)/g)].map((m) => (0, eval)(m[2]));

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 });
await context.route('**/*', (route) => (new URL(route.request().url()).host === new URL(BASE).host ? route.continue() : route.abort('blockedbyclient')));
const page = await context.newPage();
await page.goto(BASE);
await page.evaluate(() => {
  localStorage.clear();
  localStorage.setItem('glyph-guide-seen', '1');
  localStorage.setItem('glyph-account-gate-seen', '1');
});
await page.reload();
await page.waitForTimeout(2000);
const out = await page.evaluate(async (tried) => {
  const L = await import('/src/app/academy/lessons.ts');
  const G = await import('/src/app/guide/marks.ts');
  const R = await import('/src/app/plugins/registry.ts');
  const rows = () => G.markGroups().flatMap((group) => group.rows.map((row) => ({ name: row.name, symbol: row.symbol })));
  const lessons = L.LESSONS.map(({ passes, ...rest }) => ({ ...rest, standard: rest.standard === true, needs: rest.needs ?? null, check: passes.toString() }));
  const corpus = [...new Set([...L.LESSONS.map((l) => l.example), ...tried, '', '   ', 'plain words'])];
  const answers = corpus.map((text) => L.LESSONS.map((l) => (l.passes(text) ? '1' : '0')).join(''));
  const on = rows();
  const nowOn = L.lessonsNow().map((l) => l.id);
  R.plugins.setEnabled('marks', false);
  const off = rows();
  const nowOff = L.lessonsNow().map((l) => l.id);
  const answersOff = corpus.map((text) => L.LESSONS.map((l) => (l.passes(text) ? '1' : '0')).join(''));
  R.plugins.setEnabled('marks', true);
  return { chapters: [...L.CHAPTERS], about: L.CHAPTER_ABOUT, lessons, corpus, answers, answersOff, rows: on, rowsOff: off, nowOn, nowOff };
}, tried);
await browser.close();

writeFileSync(`${FLUTTER}test/academy/fixtures/web_lessons.json`, JSON.stringify(out, null, 1));

const s = (text) => `'${text.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/\$/g, '\\$').replace(/\n/g, '\\n')}'`;
let dart = `// MADE, not written: the words of the web app's own academy/lessons.ts, read off its running page (LESSONS,\n// CHAPTERS, CHAPTER_ABOUT) on 2026-10-08. The checks are lessons.dart's, by each lesson's id.\n// coverage:ignore-file\npart of 'lessons.dart';\n\n`;
dart += `/// \`CHAPTERS\`.\nconst List<String> chapters = <String>[${out.chapters.map(s).join(', ')}];\n\n`;
dart += `/// What each chapter is about, said on the contents and at the head of the chapter (\`CHAPTER_ABOUT\`).\nconst Map<String, String> chapterAbout = <String, String>{\n${out.chapters.map((c) => `  ${s(c)}: ${s(out.about[c])},`).join('\n')}\n};\n\n`;
dart += `/// \`LESSONS\`, in the order they are taught.\nfinal List<Lesson> lessons = List<Lesson>.unmodifiable(<Lesson>[\n`;
for (const l of out.lessons) {
  dart += `  Lesson._(\n    id: ${s(l.id)},\n    chapter: ${s(l.chapter)},\n    symbol: ${s(l.symbol)},\n${l.standard ? '    standard: true,\n' : ''}${l.needs ? `    needs: ${s(l.needs)},\n` : ''}    rows: <String>[${l.rows.map(s).join(', ')}],\n    title: ${s(l.title)},\n    teach: ${s(l.teach)},\n    example: ${s(l.example)},\n    task: ${s(l.task)},\n    praise: ${s(l.praise)},\n    hint: ${s(l.hint)},\n  ),\n`;
}
dart += `]);\n`;
writeFileSync(`${FLUTTER}lib/academy/lessons.g.dart`, dart);
console.log(out.lessons.length, 'lessons', out.corpus.length, 'texts', out.rows.length, 'rows', out.rowsOff.length, 'rows off', out.nowOff.length, 'now off');
const keys = new Set(out.lessons.flatMap((l) => Object.keys(l)));
console.log([...keys].join(' '));
