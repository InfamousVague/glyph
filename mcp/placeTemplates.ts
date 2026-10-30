import { frontMatterEnd, frontMatterValue } from '../tauri/src/app/core/frontMatter.ts';
import { propertyList } from '../tauri/src/app/core/properties.ts';
import { fillTemplate } from '../tauri/src/app/core/template.ts';
import { titleKey } from '../tauri/src/app/core/titleKey.ts';
import { pathName, type Kept } from './folders.ts';

/**
 * A folder's own template, as create_note files into it (Matt, 2026-10-30, of a list of plain-Markdown features: "add
 * all 12"; the app's lib/notes/place_templates.dart). A template is a page of the account's Templates notebook,
 * `templates: page` in its front matter, and the folders it is for are named on that page, from the top with `/`
 * between: `folders: [Kiln, Work/Clients]`. A folder with none takes the one of the folder it is in. The note made
 * there starts from the template filled (`{{date}}`, `{{time}}`, `{{title}}`, `{{author}}`; `{{cursor}}` taken out),
 * and the words the caller gave go under it.
 */

/** A note's body as this reads it. */
type Page = { body: string; archived?: boolean };

const PAGE = /^page$/i;
const HEADING = /^#{1,6}\s+(.*)$/;

/** Whether a body is a template's page. */
export function isTemplatePage(body: string): boolean {
  return PAGE.test(frontMatterValue(body, 'templates')?.trim() ?? '') && !/^(true|yes)$/i.test(frontMatterValue(body, 'book')?.trim() ?? '');
}

function pathKey(path: string): string {
  return path
    .split(/[/›]/)
    .map((part) => titleKey(part.trim()))
    .filter(Boolean)
    .join('/');
}

/** Whether a page's `folders:` entry is the folder at `path` ("Work/Clients"): the whole path, or its own name alone. */
function namesFolder(said: string, path: string): boolean {
  const want = pathKey(said);
  if (!want) return false;
  if (want === pathKey(path)) return true;
  return !said.includes('/') && want === pathKey(path.split('/').pop() ?? '');
}

/** The page whose template a note made in `folder` starts from: the folder's own, else its parents' up to the top. */
export function folderTemplatePage<P extends Page>(pages: readonly P[], list: readonly Kept[], folder: Kept): P | null {
  const path = pathName(list, folder.id).split(' › ');
  const own = pages.filter((page) => !page.archived && isTemplatePage(page.body));
  for (let depth = path.length; depth > 0; depth -= 1) {
    const name = path.slice(0, depth).join('/');
    const found = own.find((page) =>
      propertyList(frontMatterValue(page.body, 'folders')).some((said) => namesFolder(said, name)),
    );
    if (found) return found;
  }
  return null;
}

const CURSOR = /\{\{\s*cursor\s*\}\}/g;
const AUTHOR = /\{\{\s*author\s*\}\}/g;

/**
 * The words a note made from a template's page starts with: the page's words after its front matter, filled for
 * `title` at `at`, a heading the caller wrote taken as the title, and the caller's own words under the template.
 */
export function fromTemplatePage(page: string, words: string, { at, author = '' }: { at: Date; author?: string }): string {
  const lines = page.split('\n');
  const template = lines.slice(frontMatterEnd(lines)).join('\n');
  const given = words.replace(/^\s+/, '');
  const first = given.split('\n')[0] ?? '';
  const heading = HEADING.exec(first);
  const title = heading ? heading[1]!.trim() : '';
  const rest = heading ? given.slice(first.length).trim() : given.trim();
  const filled = fillTemplate(template.replace(AUTHOR, author), { at, title }).replace(CURSOR, '');
  // A template with no heading of its own keeps the caller's.
  const head = heading && !/^\s*#{1,6}\s/.test(filled) ? `${first}\n\n` : '';
  return `${head}${filled.trimEnd()}${rest ? `\n\n${rest}` : ''}\n`;
}
