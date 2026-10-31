import { existsSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from './build.ts';
// The site's look: the app's tokens and inks, the kit's fonts, the reader's own styles come in through the components.
import './styles.css';

/**
 * `ghost-publish <Library folder> [--out site] [--title …] [--base https://…] [--noindex] [--today YYYY-MM-DD]`
 *
 * Built by Vite into one file, dist/ghost-publish.js, with its stylesheets and fonts beside it in dist/assets/
 * (publish/vite.config.ts); bin/ghost-publish.mjs runs it. The assets it writes into the site are whatever that folder
 * holds, so a stylesheet added to the imports above is in every site the next build makes.
 */

interface Args {
  library: string | null;
  out: string;
  title?: string;
  baseUrl?: string;
  robots?: string;
  today?: string;
  quiet: boolean;
  help: boolean;
}

export function parseArgs(argv: readonly string[]): Args {
  const args: Args = { library: null, out: 'site', quiet: false, help: false };
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]!;
    const next = () => {
      i += 1;
      if (argv[i] === undefined) throw new Error(`${arg} wants a value`);
      return argv[i]!;
    };
    if (arg === '--out' || arg === '-o') args.out = next();
    else if (arg === '--title') args.title = next();
    else if (arg === '--base' || arg === '--base-url') args.baseUrl = next();
    else if (arg === '--noindex') args.robots = 'noindex';
    else if (arg === '--today') args.today = next();
    else if (arg === '--quiet' || arg === '-q') args.quiet = true;
    else if (arg === '--help' || arg === '-h') args.help = true;
    else if (arg.startsWith('-')) throw new Error(`Unknown option ${arg}`);
    else if (args.library === null) args.library = arg;
    else throw new Error(`One library at a time: ${arg}`);
  }
  return args;
}

const HELP = `ghost-publish: a Ghost.md library folder as a website.

  ghost-publish <library> [--out <folder>] [--title <name>] [--base <https://…>] [--noindex] [--today <YYYY-MM-DD>]

  <library>   the Library folder (a clone of its repository); . for the current folder
  --out       where to write the site (default: site)
  --title     the site's name (default: publish.json's, else the folder's name)
  --base      the address it will live at, for the sitemap, the feed and canonical links
  --noindex   ask search engines to stay out
  --today     the day queries run on (default: today)

The library's own publish.json (or .glyph/config.json's "publish") says the rest: which folders, whether orgs/ is
published, how many recent notes the home page lists. .trash/ is never published; a note with private: true never is.
`;

/** The bundle's stylesheets, found beside it: Vite names them with a hash. */
function assetsBeside(dist: string): { dir: string; css: string[]; search: string } {
  const dir = join(dist, 'assets');
  if (!existsSync(dir)) throw new Error(`No assets folder beside the bundle at ${dir}: build it with "vite build --config publish/vite.config.ts" from tauri/.`);
  const css = readdirSync(dir)
    .filter((name) => name.endsWith('.css'))
    .sort()
    .map((name) => `assets/${name}`);
  const search = 'assets/search.js';
  if (!existsSync(join(dir, 'search.js'))) throw new Error(`The search script is missing from ${dir}.`);
  return { dir, css, search };
}

export function main(argv: readonly string[], here: string = dirname(fileURLToPath(import.meta.url))): number {
  let args: Args;
  try {
    args = parseArgs(argv);
  } catch (failure) {
    console.error((failure as Error).message);
    console.error(HELP);
    return 2;
  }
  if (args.help || args.library === null) {
    console.log(HELP);
    return args.help ? 0 : 2;
  }
  try {
    const result = build({
      library: args.library,
      out: args.out,
      config: { ...(args.title ? { title: args.title } : {}), ...(args.baseUrl ? { baseUrl: args.baseUrl } : {}), ...(args.robots ? { robots: args.robots } : {}) },
      assets: assetsBeside(here),
      today: args.today,
      log: args.quiet ? undefined : (line) => console.log(line),
    });
    if (args.quiet) console.log(`${result.pages} pages → ${result.out}`);
    return 0;
  } catch (failure) {
    console.error(`ghost-publish: ${(failure as Error).message}`);
    return 1;
  }
}

// Run as the CLI when this is the entry; imported by the tests for parseArgs.
if (process.argv[1] && /ghost-publish(\.m?js)?$/.test(process.argv[1]) || process.env.GHOST_PUBLISH_MAIN === '1') {
  process.exitCode = main(process.argv.slice(2));
}
