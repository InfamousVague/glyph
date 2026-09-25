/**
 * deploy-ota's command line: which parts of a release it builds and
 * publishes, and the release number and notes when they are given by hand.
 * The flags themselves are listed, with an example each, in the Usage of
 * deploy-ota.mjs's header.
 *
 * Read here rather than inline at the top of the deploy for two reasons. The
 * checks on --release and --notes can be tested without starting a deploy
 * (flags.test.mjs). And inline, they ran before the script had defined its
 * `fail`: a mistyped `--release x` stopped with "ReferenceError: Cannot
 * access 'fail' before initialization" rather than the sentence saying what
 * --release needs. The exit code was 1 either way; the words were not.
 */
import { fail } from '../lib/say.mjs';

/** The deploy's choices, from its argument list (process.argv, or any list with the flags in it). */
export function deployFlags(argv) {
  const has = (flag) => argv.includes(flag);

  // The release number by hand, for the one case the live manifest cannot answer: after a rollback it is an older
  // manifest, so the next release must go past the HIGHEST ever published, not past what is live.
  const releaseFlag = argv.indexOf('--release');
  const askedRelease = releaseFlag >= 0 ? Number(argv[releaseFlag + 1]) : null;
  if (releaseFlag >= 0 && (!Number.isInteger(askedRelease) || askedRelease < 1)) fail('--release needs a whole number, the release this is on the current version.');

  const notesFlag = argv.indexOf('--notes');
  const notes = notesFlag >= 0 ? String(argv[notesFlag + 1] ?? '').trim() : '';
  if (notesFlag >= 0 && (!notes || notes.startsWith('--'))) fail('--notes needs the text of what changed.');
  if (notes.length > 2000) fail('--notes is limited to 2000 characters; the app refuses a longer manifest.');

  return {
    withApk: has('--apk'),
    withDesktop: has('--desktop'),
    /** Claude's MCP server as one file (scripts/build-mcp.mjs), published at /glyph/mcp/glyph-mcp.mjs beside the app. */
    withMcp: has('--mcp'),
    sameVersion: has('--same-version'),
    isPublic: has('--public'),
    // Leave the connection open (it closes itself two minutes after its last use)
    // so a server deploy straight after this one spends no second login.
    keepConnection: has('--keep-connection'),
    // Ship without running the tests first: only for a release that cannot wait. The
    // Test results page in that build then says its report is from other code.
    skipTests: has('--skip-tests'),
    askedRelease,
    notes,
  };
}
