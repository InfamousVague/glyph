// @vitest-environment node
import { describe, expect, it } from 'vitest';
import type { Kept } from './folders.ts';
import { folderTemplatePage, fromTemplatePage, isTemplatePage } from './placeTemplates.ts';

/**
 * A folder's own template as create_note files into it (placeTemplates.ts; Matt, 2026-10-30, of a list of
 * plain-Markdown features: "add all 12"; the app's lib/notes/place_templates.dart): the page whose `folders:` names the
 * folder, or a folder it is inside, and the note it starts, filled, with the caller's words under it.
 */
const list: Kept[] = [
  { id: 'work', name: 'Work' },
  { id: 'clients', name: 'Clients', parent: 'work' },
  { id: 'acme', name: 'Acme', parent: 'clients' },
  { id: 'kiln', name: 'Kiln' },
] as Kept[];

const bug = { body: '---\ntitle: "Bug report"\ntemplates: page\nfolders: [Kiln, Work/Clients]\n---\n# {{title}}\n\nBy {{author}} on {{date:YYYY-MM-DD}}\n\n## Steps\n\n1. {{cursor}}\n' };
const plain = { body: '---\ntitle: "Notes"\ntemplates: page\n---\n# {{title}}\n' };
const notebook = { body: '---\ntitle: "Templates"\nbook: true\ntemplates: true\nfolders: [Kiln]\n---\n# Templates\n' };

describe('a folder’s template', () => {
  it('is the page that names it, or a folder it is inside; never the Templates notebook itself', () => {
    expect(isTemplatePage(bug.body)).toBe(true);
    expect(isTemplatePage(notebook.body)).toBe(false);
    expect(folderTemplatePage([notebook, plain, bug], list, list[3]!)).toBe(bug);
    expect(folderTemplatePage([plain, bug], list, list[2]!)).toBe(bug);
    expect(folderTemplatePage([plain, bug], list, list[0]!)).toBeNull();
  });

  it('starts the note filled, the caller’s heading its title and the caller’s words under it', () => {
    const at = new Date(2026, 9, 30, 9, 5);
    const made = fromTemplatePage(bug.body, '# Login loops\n\nSigning in sends you back.', { at, author: 'matt' });
    expect(made).toBe('# Login loops\n\nBy matt on 2026-10-30\n\n## Steps\n\n1.\n\nSigning in sends you back.\n');
    expect(made).not.toContain('{{');
    expect(made).not.toContain('folders:');
  });
});
