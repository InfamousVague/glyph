import { copyFileSync, existsSync, mkdirSync, readdirSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { basename, dirname, join, resolve } from 'node:path';
import { isoDay } from '../../src/app/core/days.ts';
import { configFrom, readConfig, type PublishConfig } from './config.ts';
import { feed, sitemap } from './feeds.ts';
import { queryLibraryOf } from './fences.tsx';
import { readLibrary } from './library.ts';
import { resolver } from './links.ts';
import { renderHome, renderNotFound, renderPage, type SiteAssets, type SiteContext } from './page.tsx';
import { searchIndex } from './search.ts';

/**
 * The build: a Library folder in, a folder of HTML out (docs/MARKDOWN_FIRST.md §8; Matt, 2026-10-31, decision 4:
 * "build the publisher now"). Reads the config, walks the notes, resolves every link, renders every page, then writes
 * the home page, the 404, the sitemap, the feed, the search's index and script, the stylesheets and fonts the bundle
 * carries, and only the pictures, files, films and tapes some page asked for.
 */

export interface BuildOptions {
  /** The Library folder: a clone of the repository. */
  library: string;
  /** Where the site is written. Emptied first. */
  out: string;
  /** Overrides from the command line, over the library's own config. */
  config?: Partial<Record<'title' | 'baseUrl' | 'robots', string>>;
  /** Where the bundle's own files are (its stylesheets, fonts and the search script): the built dist/, or the sources' stand-ins in a test. */
  assets: { dir: string; css: string[]; search: string };
  /** The day queries run on; today when left out. */
  today?: string;
  log?: (line: string) => void;
}

export interface BuildResult {
  pages: number;
  files: number;
  out: string;
  config: PublishConfig;
}

function copyDir(from: string, to: string): void {
  mkdirSync(to, { recursive: true });
  for (const name of readdirSync(from)) {
    const source = join(from, name);
    const target = join(to, name);
    if (statSync(source).isDirectory()) copyDir(source, target);
    else copyFileSync(source, target);
  }
}

function write(out: string, href: string, text: string): void {
  const path = join(out, ...href.split('/'));
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, text);
}

export function build(options: BuildOptions): BuildResult {
  const log = options.log ?? (() => undefined);
  const root = resolve(options.library);
  if (!existsSync(root) || !statSync(root).isDirectory()) throw new Error(`Not a folder: ${root}`);
  let config = readConfig(root);
  if (options.config) config = configFrom({ ...options.config }, config);
  const library = readLibrary(root, config);
  const title = config.title ?? basename(root);
  const links = resolver(library);
  const assets: SiteAssets = { css: options.assets.css, search: options.assets.search };
  const ctx: SiteContext = { library, config, resolver: links, assets, title, fences: { ...queryLibraryOf(library), library, today: options.today ?? isoDay(new Date()) } };

  const out = resolve(options.out);
  if (out === root || root.startsWith(`${out}/`)) throw new Error(`The site would be written over the library itself (${out}): choose another --out.`);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(out, { recursive: true });

  // The pages first: rendering is what finds the files they use.
  for (const page of library.pages) {
    write(out, page.href, renderPage(page, ctx));
    log(`  ${page.href}`);
  }
  write(out, 'index.html', renderHome(ctx));
  write(out, '404.html', renderNotFound(ctx));
  write(out, 'sitemap.xml', sitemap(library, config.baseUrl));
  write(out, 'feed.xml', feed(library, title, config.baseUrl, config.recent));
  write(out, 'search.json', JSON.stringify(searchIndex(library)));
  if (config.robots === 'noindex') write(out, 'robots.txt', 'User-agent: *\nDisallow: /\n');
  else write(out, 'robots.txt', `User-agent: *\nAllow: /\n${config.baseUrl ? `Sitemap: ${config.baseUrl}/sitemap.xml\n` : ''}`);

  // The bundle's own files: stylesheets, the fonts they name, the search script.
  copyDir(options.assets.dir, join(out, 'assets'));

  // The files the pages asked for, at the paths the notes link.
  let files = 0;
  for (const path of links.used) {
    const source = library.files.get(path);
    if (!source) continue;
    const target = join(out, ...path.split('/'));
    mkdirSync(dirname(target), { recursive: true });
    copyFileSync(source, target);
    files += 1;
  }
  log(`${library.pages.length} pages, ${files} files → ${out}`);
  return { pages: library.pages.length, files, out, config };
}
