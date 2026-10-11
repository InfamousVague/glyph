// Writes web_library.json beside this file: what the web app's own code answers over the library the store
// screenshots are taken over, for the Dart ports to be held to (test/core/*_test.dart, test/home/home_layout_test.dart).
//
// It runs the web app's TypeScript as it stands, read-only, with Node's own type stripping:
//
//   node --experimental-strip-types test/core/fixtures/make_web_library.mjs
//
// from this repo's root, with tauri/ and ../ghost-md-app-store-pack beside it. The clock is seed.mjs's (a Monday
// morning in London); what it writes of time is how long ago each note was made and touched, so the fixture reads the
// same in any time zone.
process.env.TZ = 'Europe/London';
import { mkdtempSync, readFileSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const here = new URL('.', import.meta.url).pathname;
const web = new URL('../../../tauri/src/app/', import.meta.url).pathname;
const pack = new URL('../../../../ghost-md-app-store-pack/tools/', import.meta.url).pathname;

// core/sampleNote.ts imports a picture and the picture store, which only a bundler can give it: a copy without them.
const sample = join(mkdtempSync(join(tmpdir(), 'ghost-fixture-')), 'sampleNote.ts');
writeFileSync(
  sample,
  readFileSync(`${web}core/sampleNote.ts`, 'utf8')
    .replace("import { imageMarkdown } from './images.ts';", "const imageMarkdown = (name: string, alt: string) => `![${alt}](image/${name})`;")
    .replace("import smokeUrl from '../assets/sample-smoke.jpg';", "const smokeUrl = '';"),
);

const { library, NOW } = await import(`${pack}seed.mjs`);
const { exampleNotebookBody, exampleTicketBodies, exampleJournal, todayFor } = await import(`${web}core/starterNotes.ts`);
const { boardNoteBody } = await import(`${web}core/boardNote.ts`);
const { sampleNoteBody } = await import(sample);
const { noteTitle } = await import(`${web}core/noteTitle.ts`);
const { peekMarkdown } = await import(`${web}notes/peek.ts`);
const L = await import(`${web}home/homeLayout.ts`);
const { bookIndex, placeOf, chaptersOf } = await import(`${web}book/book.ts`);
const { ticketOf, statusesOf } = await import(`${web}core/properties.ts`);
const { canvasOf } = await import(`${web}canvas/jsonCanvas.ts`);
const { when } = await import(`${web}notes/when.ts`);
const { journalCards } = await import(`${web}book/journalMonths.ts`);
const { matches } = await import(`${web}notes/allNotes.ts`);

const { notes } = library();
const at = new Date(NOW);
const starters = {
  tickets: exampleTicketBodies(todayFor(at)).map((t) => t.body),
  notebook: exampleNotebookBody(),
  board: boardNoteBody(),
  journal: exampleJournal(at).journal,
  entry: exampleJournal(at).entry,
  sample: sampleNoteBody(null),
};
const index = bookIndex(notes);
const today = new Date(NOW).setHours(0, 0, 0, 0);
const shape = (plan) => ({ cut: plan.cut, sections: plan.sections.map((s) => ({ key: s.key, heading: s.heading, mark: s.mark, count: s.count, draw: s.draw, notes: s.notes.map((n) => n.id) })) });
const out = {
  now: NOW,
  notes: notes.map((n) => ({ id: n.id, body: n.body, starred: !!n.starred, createdAgo: NOW - n.createdAt, updatedAgo: NOW - n.updatedAt })),
  starters,
  read: Object.fromEntries(
    notes.map((n) => {
      const place = placeOf(index, n);
      const ticket = ticketOf(n.body, place ? statusesOf(place.book.body) : undefined);
      return [
        n.id,
        {
          title: noteTitle(n.body),
          firstLine: L.firstLine(n.body),
          kind: L.kindOf(n),
          peek: peekMarkdown(n.body),
          book: place ? place.title : null,
          at: place ? place.at : null,
          chapters: chaptersOf(n.body).map((c) => c.title),
          ticket: ticket ? { id: ticket.id, status: ticket.status, category: ticket.category, assignee: ticket.assignee } : null,
          cards: canvasOf(n.body)?.nodes.length ?? null,
          when: when(n.updatedAt, NOW),
        },
      ];
    }),
  ),
  counts: L.homeCounts(notes),
  plans: Object.fromEntries(['spotlight', 'cards', 'timeline', 'list'].map((layout) => [layout, shape(L.homePlan(layout, L.homeLists(notes, '', 'all'), { now: today }))])),
  searched: Object.fromEntries(['sam', 'cabin friday', 'PRD-11', 'beta 28th', 'nothing-has-this'].map((q) => [q, notes.filter((n) => matches(n, q)).map((n) => n.id)])),
  pinnedOnly: shape(L.homePlan('spotlight', L.homeLists(notes, '', 'pinned'), { now: today })),
  booksOnly: shape(L.homePlan('cards', L.homeLists(notes, '', 'books'), { now: today })),
  journalCards: Object.fromEntries([...journalCards([...notes, { id: 'j', body: starters.journal, createdAt: NOW, updatedAt: NOW, source: 'editor' }, { id: 'e', body: starters.entry, createdAt: NOW, updatedAt: NOW, source: 'editor' }])]),
};
writeFileSync(`${here}web_library.json`, `${JSON.stringify(out, null, 1)}\n`);
console.log(`web_library.json: ${notes.length} notes, ${Object.keys(out.plans).length} layouts`);
