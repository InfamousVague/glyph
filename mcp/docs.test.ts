// @vitest-environment node
import { beforeEach, describe, expect, it } from 'vitest';
import { chaptersOf } from '../tauri/src/app/book/book.ts';
import type { Note } from '../tauri/src/app/core/store.ts';
import { open } from '../tauri/src/app/core/sync/crypto.ts';
import { forgetTeamDocs } from '../tauri/src/app/core/team/doc.ts';
import { DOCS_GUIDE, DOCS_INSTRUCTIONS, docsBookBody, docsPageBody, docsParts, docsTitleProblem, isDocsBody, withDocsPage } from './docs.ts';
import { DOCS_GUIDE_URI } from './prompts.ts';
import { rulesInstructions } from './server.ts';
import { aNote, anOrganization, connected, teamDevice } from './testKit.ts';

/**
 * Docs through the connector (mcp/docs.ts; Matt, 2026-10-31: "add it to the Claude and other AI connector so they can
 * make docs on ghost expose it in the MCP and then add instructions for AI to know how to use it"): the index's shape
 * as the app's lib/core/docs_book.dart writes it (test/core/docs_book_test.dart holds the app to the same bodies),
 * create_docs and add_doc_page called as Claude calls them, a team's docs made the team's, and the words Claude is
 * told.
 */

const INDEX = '---\ntitle: "Field guide"\nbook: true\ntype: docs\n---\n# Field guide\n\nHow the garden works.\n\n## Getting started\n\n1. [[Welcome]]\n2. [[Install]]\n\n## Using it\n\n3. [[Planting]]\n4. [[Watering]]\n';

type Created = { created: { id: string; title: string; workspace?: { id: string; name: string; organization: boolean } | null }; parts: { title: string; pages: { id: string; title: string }[] }[] };

beforeEach(() => {
  forgetTeamDocs();
});

describe('the docs type', () => {
  it('writes the index the app writes, and reads its parts back', () => {
    const body = docsBookBody('Field guide', {
      about: 'How the garden works.',
      parts: [
        { title: 'Getting started', pages: ['Welcome', 'Install'] },
        { title: 'Using it', pages: ['Planting', 'Watering'] },
      ],
    });
    expect(body).toBe(INDEX);
    expect(isDocsBody(body)).toBe(true);
    expect(isDocsBody('---\nbook: true\n---\n# Plain\n')).toBe(false);
    expect(isDocsBody('---\nbook: true\ndocs: read\n---\n# Home\n')).toBe(false);
    expect(docsParts(body).map(({ title, pages }) => ({ title, pages }))).toEqual([
      { title: 'Getting started', pages: ['Welcome', 'Install'] },
      { title: 'Using it', pages: ['Planting', 'Watering'] },
    ]);
    expect(docsBookBody('Handbook', { parts: [{ title: 'Getting started', pages: [] }] })).toBe('---\ntitle: "Handbook"\nbook: true\ntype: docs\n---\n# Handbook\n\n## Getting started\n');
  });

  it('adds a page under its part, at its place, numbering the rest; a part not there is made at the end', () => {
    expect(withDocsPage(INDEX, 'getting STARTED', 'Your first bed')).toContain('1. [[Welcome]]\n2. [[Install]]\n3. [[Your first bed]]\n\n## Using it\n\n4. [[Planting]]\n5. [[Watering]]\n');
    expect(withDocsPage(INDEX, 'Using it', 'Tools', 1)).toContain('## Using it\n\n3. [[Tools]]\n4. [[Planting]]\n5. [[Watering]]\n');
    expect(withDocsPage(INDEX, 'Troubleshooting', 'Pests')).toMatch(/4\. \[\[Watering\]\]\n\n## Troubleshooting\n\n5\. \[\[Pests\]\]\n$/);
    expect(withDocsPage(INDEX, 'Using it', 'welcome')).toBe(INDEX);
    const empty = docsBookBody('Handbook', { parts: [{ title: 'Getting started', pages: [] }, { title: 'Later', pages: [] }] });
    expect(withDocsPage(empty, 'Getting started', 'Welcome')).toContain('## Getting started\n\n1. [[Welcome]]\n\n## Later\n');
    expect(withDocsPage('---\nbook: true\ntype: docs\n---\n# B\n\n## One\n\n- [[A]]\n', 'One', 'B')).toContain('- [[A]]\n- [[B]]\n');
  });

  it('writes a page with its heading once and its icon, and refuses a title a link could not name', () => {
    expect(docsPageBody('Install', 'Download it.', '📦')).toBe('---\nicon: 📦\n---\n# Install\n\nDownload it.\n');
    expect(docsPageBody('Install', '# Install\n\nDownload it.')).toBe('# Install\n\nDownload it.\n');
    expect(docsTitleProblem('Install')).toBeNull();
    for (const bad of ['A [draft]', 'Q&A #2', 'a|b', ' ', 'x'.repeat(121)]) expect(docsTitleProblem(bad)).not.toBeNull();
  });
});

describe('create_docs', () => {
  it('makes the index of parts and every page, signed by the AI, and answers each page’s id', async () => {
    const { service, call } = await connected();
    const said = await call('create_docs', {
      title: 'Field guide',
      about: 'How the garden works.',
      parts: [
        { title: 'Getting started', pages: [{ title: 'Welcome', body: 'What the guide is for.\n\n## Who it is for\n\nGardeners. See [[Install]].', icon: '👋' }, { title: 'Install', body: 'Getting the tools.' }] },
        { title: 'Using it', pages: [{ title: 'Planting', body: 'When and where.' }] },
      ],
    });
    expect(said.isError).toBe(false);
    const made = JSON.parse(said.text) as Created;
    expect(made.created.title).toBe('Field guide');
    expect(made.parts.map((p) => [p.title, p.pages.map((page) => page.title)])).toEqual([
      ['Getting started', ['Welcome', 'Install']],
      ['Using it', ['Planting']],
    ]);
    const index = (await service.stored(made.created.id))!.note.body;
    expect(isDocsBody(index)).toBe(true);
    expect(index).toContain('authors: matt, Claude');
    expect(chaptersOf(index).map((c) => c.title)).toEqual(['Welcome', 'Install', 'Planting']);
    expect(index).toContain('How the garden works.\n\n## Getting started\n\n1. [[Welcome]]\n2. [[Install]]\n\n## Using it\n\n3. [[Planting]]\n');
    const welcome = (await service.stored(made.parts[0]!.pages[0]!.id))!.note.body;
    expect(welcome).toBe('---\nicon: 👋\nauthors: matt, Claude\n---\n# Welcome\n\nWhat the guide is for.\n\n## Who it is for\n\nGardeners. See [[Install]].\n');
  });

  it('refuses, making nothing, a title used twice, one a note has, or one a link could not name', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('g', '# Groceries\n\n- eggs'));
    const page = (title: string) => ({ title: 'A', pages: [{ title, body: 'Words.' }] });
    const refused = async (args: Record<string, unknown>, says: string) => {
      const answer = await call('create_docs', args);
      expect(answer.isError).toBe(true);
      expect(answer.text).toContain(says);
    };
    await refused({ title: 'Guide', parts: [{ title: 'A', pages: [{ title: 'One', body: '' }, { title: 'one', body: '' }] }] }, 'Two of these are called');
    await refused({ title: 'Guide', parts: [page('Groceries')] }, 'There is already a note called “Groceries”');
    await refused({ title: 'Groceries', parts: [page('One')] }, 'add to those docs with add_doc_page');
    await refused({ title: 'Guide', parts: [page('Q&A #2')] }, 'cut short');
    await refused({ title: 'Guide', parts: [] }, '');
    expect([...service.notes.keys()]).toEqual(['g']);
  });

  it('makes docs in an organization’s workspace the team’s, index and pages, from their first word', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    const made = JSON.parse((await call('create_docs', { title: 'Handbook', workspace: 'Ghost', parts: [{ title: 'Basics', pages: [{ title: 'Holidays', body: 'How to book one.' }] }] })).text) as Created;
    expect(made.created.workspace).toEqual({ id: `org-${org.id}`, name: 'Ghost', organization: true });
    const ids = [made.created.id, made.parts[0]!.pages[0]!.id];
    for (const id of ids) expect(service.notes.has(id)).toBe(false);
    await phone.sync();
    expect(isDocsBody(phone.notes.get(ids[0]!)!.body)).toBe(true);
    expect(phone.notes.get(ids[1]!)!.body).toContain('# Holidays\n\nHow to book one.');
  });
});

describe('add_doc_page', () => {
  it('puts the page’s line under its part and makes the page, filed where the docs are', async () => {
    const { service, call, account } = await connected();
    await account.changePrefs(() => ({ workspaces: { list: [{ id: 'w-home', name: 'Home' }], notes: {} } }));
    const made = JSON.parse((await call('create_docs', { title: 'Field guide', workspace: 'Home', parts: [{ title: 'Basics', pages: [{ title: 'Soil', body: 'Dig.' }, { title: 'Water', body: 'Pour.' }] }] })).text) as Created;
    const said = await call('add_doc_page', { docs: 'Field guide', part: 'Basics', title: 'Light', body: 'How much sun.', position: 1 });
    expect(said.isError).toBe(false);
    const added = JSON.parse(said.text) as { created: { id: string; title: string; workspace: { name: string } | null }; docs: { id: string } };
    expect(added.created.title).toBe('Light');
    expect(added.created.workspace?.name).toBe('Home');
    expect(added.docs.id).toBe(made.created.id);
    const index = (await service.stored(made.created.id))!.note.body;
    expect(index).toContain('## Basics\n\n1. [[Light]]\n2. [[Soil]]\n3. [[Water]]\n');
    await call('add_doc_page', { docs: made.created.id, part: 'Pests', title: 'Aphids', body: 'Small and green.' });
    expect((await service.stored(made.created.id))!.note.body).toMatch(/## Pests\n\n4\. \[\[Aphids\]\]\n$/);
  });

  it('refuses a note that is not docs, and a page title a note has', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('b', '---\nbook: true\n---\n# Plans\n\n- [[One]]\n'));
    await service.deviceWrites(aNote('d', INDEX));
    await service.deviceWrites(aNote('w', '# Welcome\n'));
    expect((await call('add_doc_page', { docs: 'Plans', part: 'A', title: 'Two', body: 'x' })).text).toContain('is not docs');
    expect((await call('add_doc_page', { docs: 'd', part: 'Using it', title: 'welcome', body: 'x' })).text).toContain('There is already a note called “welcome”');
    expect((await service.stored('d'))!.note.body).toBe(INDEX);
  });

  it('puts a page of a team’s docs in the team, beside its index', async () => {
    const { service, call } = await connected();
    const org = await anOrganization(service);
    const phone = teamDevice(service, org);
    phone.put('d', INDEX.replace('# Field guide', '# Team guide').replace('"Field guide"', '"Team guide"'), { path: 'orgs/Ghost/Team guide.md' });
    await phone.sync();
    const added = JSON.parse((await call('add_doc_page', { docs: 'Team guide', part: 'Using it', title: 'Pruning', body: 'In winter.' })).text) as { created: { id: string; workspace: { organization: boolean } } };
    expect(added.created.workspace.organization).toBe(true);
    expect(service.notes.has(added.created.id)).toBe(false);
    const row = service.teamNotes(org.id).get(added.created.id)!;
    const note = (await open<{ note: Note }>(org.key, row.blob!, `org:${org.id}:note:${added.created.id}`)).note;
    expect(note.path).toBe('orgs/Ghost/Pruning.md');
    await phone.sync();
    expect(phone.notes.get('d')!.body).toContain('4. [[Watering]]\n5. [[Pruning]]\n');
  });
});

describe('what Claude is told', () => {
  it('says how to write docs in the instructions, and offers the guide as a prompt and a resource', async () => {
    const said = rulesInstructions('# Claude rules\n');
    expect(said).toContain(DOCS_INSTRUCTIONS);
    expect(DOCS_INSTRUCTIONS).toContain('create_docs');
    expect(DOCS_INSTRUCTIONS).toContain('add_doc_page');
    const { client } = await connected();
    const { tools } = await client.listTools();
    expect(tools.map((t) => t.name)).toEqual(expect.arrayContaining(['create_docs', 'add_doc_page']));
    // A page is nothing but its fields: a key Claude made up is refused, not dropped.
    const parts = (tools.find((t) => t.name === 'create_docs')!.inputSchema.properties as Record<string, { items?: { additionalProperties?: boolean; properties?: Record<string, { items?: { additionalProperties?: boolean } }> } }>).parts;
    expect(parts?.items?.additionalProperties).toBe(false);
    expect(parts?.items?.properties?.pages?.items?.additionalProperties).toBe(false);
    const { messages } = await client.getPrompt({ name: 'ghost-docs-guide', arguments: { topic: 'our release process' } });
    expect((messages[0]!.content as { text: string }).text).toContain('Write docs on Ghost.md about our release process.');
    expect((messages[0]!.content as { text: string }).text).toContain(DOCS_GUIDE);
    expect(await client.readResource({ uri: DOCS_GUIDE_URI })).toEqual({ contents: [{ uri: DOCS_GUIDE_URI, mimeType: 'text/markdown', text: DOCS_GUIDE }] });
  });

  it('keeps `type: docs` when a rewrite of the index drops its front matter', async () => {
    const { service, call } = await connected();
    await service.deviceWrites(aNote('d', INDEX));
    await call('update_note', { id: 'd', body: '# Field guide\n\nHow the garden works.\n\n## Getting started\n\n1. [[Welcome]]\n' });
    expect(isDocsBody((await service.stored('d'))!.note.body)).toBe(true);
  });
});
